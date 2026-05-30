# Diarized transcription + speaker identification — Design spec

**Date**: 2026-05-14
**Branch**: TBD (probable: `feat/diarized-speaker-id`)
**Author**: laurent.deberti
**Status**: Approved (design phase), awaiting implementation plan.

## 1. Goals

Replace OneToOne's current energy-based VAD diarization with a real speaker-diarization pipeline (Pyannote + Silero VAD via [soniqo/speech-swift](https://github.com/soniqo/speech-swift)), and add **cross-meeting speaker identification** by matching cluster voice embeddings (WeSpeaker ResNet34 256-dim) against per-`Collaborator` voiceprints. Cohere Transcribe (current ASR via `mlx-audio-swift`) is preserved.

## 2. Decisions log

| Ref | Decision | Value |
|-----|----------|-------|
| Q1  | Diarization stack | speech-swift Pyannote pipeline + Silero VAD (replaces energy-VAD `DiarizationService`). |
| Q2  | Embeddings model | speech-swift WeSpeaker ResNet34 256-dim. |
| Q3  | Integration mode | SPM dependency on `https://github.com/soniqo/speech-swift` (Apache 2.0). |
| Q4  | Voiceprint storage | V-B: single 256-Float32 mean per Collaborator (EMA running update). |
| Q5  | Enrollment | E-A: implicit — manual labelling of a cluster updates the assigned Collaborator's voiceprint. No dedicated enrollment screen v1. |
| Q6  | Matching scope | M-C staged: Pass 1 = meeting participants (threshold 0.60); Pass 2 = all non-archived collabs (threshold 0.75 strict). |
| Q6b | Matching trigger | W-A: at end of transcription pipeline, automatic. |
| Q7  | Transcription mode | T-B: whole-audio Cohere chunks (existing) + temporal alignment to diarization turns. Per-turn re-transcription deferred to v2. |
| Threshold | Auto-assign | cosine ≥ 0.75 → auto, badge "✓ auto". |
| Threshold | Suggestion | 0.60 ≤ cosine < 0.75 → "?" suggestion, user confirms. |
| Threshold | Ambiguous | 2 candidates both ≥ 0.75 within < 0.02 of each other → auto=false, manual choice. |
| EMA | Voiceprint update trigger | Only on **manual** assignment (avoid drift on false positives). |

## 3. Architecture

```
audio.wav
   │
   ▼
┌──────────────────────────────┐
│  PyannoteDiarizer             │   speech-swift Pyannote pipeline (Silero VAD)
│  → [(start, end, clusterID)]  │
└──────────┬───────────────────┘
           │
           ├──▶ SpeakerEmbedding.extractPerCluster
           │   → [clusterID: [Float] (256-dim mean)]
           │
           ▼
┌──────────────────────────────┐
│  TranscriptionService (existing) │ Cohere chunks 25-30s
│  → [STTChunk(start,end,text)] │
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  TurnAligner                 │ Map each STTChunk → cluster with max overlap.
│  → [(turn, text)] segments   │ Concat consecutive same-cluster chunks.
└──────────┬───────────────────┘
           │
           ▼
┌──────────────────────────────┐
│  SpeakerMatcher              │ Staged cosine (M-C) per cluster.
│  → [clusterID: Assignment]   │ Auto badge if ≥ 0.75; suggest if ≥ 0.60.
└──────────┬───────────────────┘
           │
           ▼
   TranscriptSegment[]
   + Meeting.speakerAssignmentsJSON
   + Meeting.speakerMatchMetaJSON
```

### Module map

| File | Responsibility |
|---|---|
| `OneToOne/Services/PyannoteDiarizer.swift` | Wraps speech-swift Pyannote diarizer. Replaces current `DiarizationService` API. |
| `OneToOne/Services/SpeakerEmbedding.swift` | Wraps speech-swift WeSpeaker ResNet34 embedder. `extractPerCluster(audioURL:turns:) -> [Int: [Float]]`. |
| `OneToOne/Services/SpeakerMatcher.swift` | Staged cosine matching, EMA voiceprint update, public API consumed by `TranscriptionService`. |
| `OneToOne/Services/TurnAligner.swift` | Pure helper: STT chunks × diarization turns → aligned segments. Unit-testable. |
| `OneToOne/Services/TranscriptionService.swift` | Orchestrates: existing Cohere transcribe → diarize → align → embed → match → materialize segments. |
| `OneToOne/Models/OtherModels.swift` | New Collaborator fields (`voicePrint: Data?`, `voicePrintSamples: Int`, `voicePrintUpdatedAt: Date?`). New Meeting fields (`speakerAssignmentsJSON`, `speakerMatchMetaJSON`). |
| `OneToOne/Views/MeetingView.swift` | Badge UI per segment (✓ auto / ? suggestion / picker), "Re-identifier les speakers" toolbar action. |
| `OneToOne/Views/SettingsView.swift` | New "Reconnaissance vocale" GroupBox: toggle auto-id, thresholds, enrolled-list. |

## 4. Data model changes

### Collaborator

```swift
/// 256 Float32 mean embedding (1024 bytes) ou nil si jamais enrôlé.
var voicePrint: Data?

/// Nombre de samples agrégés via EMA (pondère mises à jour).
var voicePrintSamples: Int = 0

/// Date du dernier update (debug + invalidation).
var voicePrintUpdatedAt: Date?
```

### Meeting

```swift
/// JSON: {clusterID: "collabStableID|null"} — résultat matching (auto + manuel).
var speakerAssignmentsJSON: String = "{}"

/// JSON metadata pour UI: {clusterID: {confidence:Float, auto:Bool, ambiguous:Bool, candidates:[stableID]}}.
var speakerMatchMetaJSON: String = "{}"
```

Schema migration: lightweight (all Optional or String defaults). No `SchemaV2`.

## 5. Pipeline detail

### 5.1 Orchestrator

`TranscriptionService.transcribe(audioURL:)` (extended):

```swift
func transcribe(audioURL: URL,
                 meeting: Meeting,
                 in context: ModelContext) async throws -> STTResult {
    // 1. Diarize
    let turns = try await PyannoteDiarizer.shared.diarize(audioURL: audioURL)

    // 2. Cohere transcribe (existing)
    let chunks = try await asrTranscribe(audioURL: audioURL)

    // 3. Align
    let segments = TurnAligner.align(chunks: chunks, turns: turns)

    // 4. Per-cluster embedding
    let embeddings = try await SpeakerEmbedding.shared.extractPerCluster(
        audioURL: audioURL, turns: turns
    )

    // 5. Match
    let assignments = SpeakerMatcher.match(
        clusterEmbeddings: embeddings,
        meeting: meeting,
        in: context
    )

    // 6. Materialize TranscriptSegments + persist JSON metadata
    persist(segments, assignments, embeddings, on: meeting, in: context)

    return STTResult(...)
}
```

### 5.2 `TurnAligner` algorithm

```swift
struct AlignedSegment {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
    let clusterID: Int
}

static func align(chunks: [STTChunk], turns: [DiarTurn]) -> [AlignedSegment]
```

- For each `STTChunk(start, end, text)`, find the `DiarTurn` with **max temporal overlap** (`min(chunkEnd, turnEnd) − max(chunkStart, turnStart)`). Assign that turn's `clusterID`.
- After mapping, merge **consecutive chunks** with same `clusterID` into a single `AlignedSegment` (text joined with spaces).
- Edge case: chunk overlaps two turns equally → pick the longer turn.

### 5.3 `SpeakerEmbedding.extractPerCluster`

For each cluster: concatenate all sample frames from its turns, run through speech-swift WeSpeaker ResNet34, return the 256-dim mean. If total cluster duration < 0.5s → skip (returns no entry → matching skipped → segments stay anonymous).

### 5.4 `SpeakerMatcher.match` (staged)

```swift
struct Assignment {
    let collaborator: Collaborator?
    let confidence: Double           // cosine [0, 1]
    let auto: Bool                   // ≥ autoThreshold AND non-ambiguous
    let candidates: [(Collaborator, Double)]  // top-3 for UI/audit
    let ambiguous: Bool
}

static let autoThreshold: Double = 0.75
static let suggestThreshold: Double = 0.60
static let ambiguousDelta: Double = 0.02
```

Algorithm:
1. **Pass 1** — restrict to `meeting.participants` (non-archived) with `voicePrint != nil`. Collect (collab, cosine) ≥ `suggestThreshold`.
2. If Pass 1 empty: **Pass 2** — restrict to all non-archived Collaborators not in participants, with `voicePrint != nil`. Collect ≥ `autoThreshold` (stricter for non-participants).
3. Sort candidates desc by cosine. Top = first.
4. `auto = top.cosine ≥ autoThreshold AND !ambiguous`.
5. `ambiguous = (∃ 2nd candidate with cosine ≥ autoThreshold AND (top.cos − 2nd.cos) < ambiguousDelta)`.

### 5.5 EMA voiceprint update

Triggered **only when user manually assigns** a cluster → Collaborator (UI action). Never on auto-match (avoid drift).

```swift
func updateVoicePrint(collab: Collaborator, with newEmbedding: [Float]) {
    if collab.voicePrint == nil || collab.voicePrintSamples == 0 {
        collab.voicePrint = encode(newEmbedding)
        collab.voicePrintSamples = 1
    } else {
        let old = decode(collab.voicePrint!)
        let n = Double(collab.voicePrintSamples)
        var updated = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            updated[i] = Float((Double(old[i]) * n + Double(newEmbedding[i])) / (n + 1))
        }
        collab.voicePrint = encode(updated)
        collab.voicePrintSamples += 1
    }
    collab.voicePrintUpdatedAt = Date()
}
```

`encode/decode` = `Data` ↔ `[Float]` via `withUnsafeBytes`.

## 6. UI

### 6.1 MeetingView transcript

Each `TranscriptSegment` row shows speaker badge per `speakerMatchMetaJSON`:

| State | Visual | Click |
|---|---|---|
| Auto-assigned (≥ 0.75) | `✓ Jean Estellé` (green) | Open picker to change |
| Suggestion (0.60 – 0.75) | `? Marie? (67%)` (yellow) + ✓ accept + ✕ reject | Accept = bulk-assign all cluster's segments + EMA update |
| Anonymous (< 0.60 or no embedding) | `Speaker N ▼` (gray) | Picker: participants first, divider, all Collaborators A-Z |

**Click changes a speaker** → bulk-assigns **all segments of the same cluster** (uses `speakerAssignmentsJSON` as the source of truth). EMA update if cluster has an embedding.

### 6.2 "Re-identifier" toolbar action

`MeetingView` header gains `Button(systemImage: "person.crop.circle.badge.questionmark")` → re-runs Steps 4–6 of the pipeline (embeddings + matching) without re-transcribing. Useful after enriching other Collaborators' voiceprints.

### 6.3 Settings — "Reconnaissance vocale" GroupBox

- Toggle **"Identification automatique des speakers"** (`AppSettings.speakerIdEnabled = true`).
- Slider **"Seuil auto-assign"** 0.65–0.90, default 0.75 (`AppSettings.speakerIdAutoThreshold`).
- Slider **"Seuil suggestion"** 0.50–0.70, default 0.60 (`AppSettings.speakerIdSuggestThreshold`).
- List of Collaborators with `voicePrint != nil`: name + "Enrôlé · N réunions" + **Reset voiceprint** button.

`AppSettings` new fields:
```swift
var speakerIdEnabled: Bool = true
var speakerIdAutoThreshold: Double = 0.75
var speakerIdSuggestThreshold: Double = 0.60
```

When `speakerIdEnabled == false`: pipeline still runs diarization + transcription, but skips embedding + matching steps. Segments stay anonymous.

## 7. Edge cases

- **Audio file missing / corrupted** → `PyannoteDiarizer` returns 1 turn covering full duration with cluster 0. UI shows "Diarization indisponible" annotation.
- **WeSpeaker model not downloaded** → speech-swift triggers download on first call (~50-100MB). Surface progress in transcription UI; cache to `~/.cache/...`.
- **Cluster duration < 0.5s** → embedding skipped; cluster stays anonymous (no fake match).
- **Collaborator archived** after enrollment → excluded from matching scope until unarchived.
- **Voiceprints of related people very close** (twins, same family) → ambiguous flag triggers; auto=false; UI shows top suggestion with both candidates in metadata.
- **EMA drift** from a wrong manual label → user clicks "Reset voiceprint" in Settings; `voicePrint = nil, voicePrintSamples = 0`.
- **`speakerIdEnabled = false`** → pipeline skips Steps 4–6; all segments persisted with `speakerID = clusterID + 1`, no `speaker`.

## 8. Out of scope (deferred)

- **E-B explicit enrollment** screen (record 30s of voice for new Collaborator) — added in v2 if implicit enrollment proves insufficient.
- **T-A per-turn re-transcription** (Cohere on slice, more accurate alignment) — kept as future toolbar option.
- **Live identification** during recording (streaming embedding + matching).
- **Speaker embeddings on overlapping speech** (current pipeline assumes one speaker per turn).
- **Reset all voiceprints** bulk action — only per-collab Reset is provided.
- **Speech-swift's own ASR** (Qwen3 / Parakeet / Omnilingual) — Cohere is preserved to avoid re-validating French transcription quality.
- **Speech-swift's Sortformer end-to-end** (Neural Engine) — Pyannote pipeline chosen for cluster output that's easier to match against pre-enrolled voiceprints.

## 9. Testing

### Unit (XCTest)

- `TurnAligner.align`:
  - Single chunk overlaps multiple turns → assigned to max-overlap turn.
  - Consecutive chunks same cluster → merged into one segment.
  - Tie overlap → longer turn wins.
- `SpeakerMatcher.match`:
  - Pass 1 finds participant at cosine 0.85 → `auto=true`, no candidates from Pass 2.
  - Pass 1 finds 0.65 → `auto=false`, `confidence=0.65`, suggestion.
  - Pass 1 empty; Pass 2 finds non-participant at 0.80 → `auto=true`.
  - Pass 1 finds 2 candidates within 0.01 of each other ≥ 0.75 → `ambiguous=true, auto=false`.
- `cosine` helper: identical vectors → 1.0; orthogonal → 0.0; ±sign correct.
- EMA update: `voicePrintSamples = 0` → embedding direct; `n = 3` → `(old * 3 + new) / 4`.

### Manual

- End-to-end pipeline on a 3-speaker test audio with all participants enrolled → all segments auto-assigned.
- Same audio with one new speaker → that cluster stays anonymous, picker offered.
- Manual assign of an anonymous cluster → voiceprint updates persisted, next meeting's matching uses it.
- "Re-identifier" button reruns matching without re-transcribing.
- Settings toggle off → pipeline skips embedding/matching; only diarization + transcription run.
- Settings sliders → next pipeline run respects updated thresholds.

## 10. Implementation notes

- speech-swift exposes one SPM product per model (`WeSpeaker`, `PyannoteDiarization`, etc.). Import only what's needed in `Package.swift`.
- Cohere transcribe path stays unchanged — keep `MLXAudioSTT` dependency intact.
- `SpeakerEmbedding` and `PyannoteDiarizer` are singletons (lazy model load on first call, then cached).
- Embedding mean per cluster: keep audio in memory only as long as needed; release between clusters.
- All four new services are `@MainActor` for SwiftData access; embedding computation happens off-main via `Task.detached` then results posted back.
- Backward compatibility: existing `DiarizationService.detectTurns` API stays (read by `MeetingView` line 1466 `runDiarization`). New `PyannoteDiarizer` lives alongside; `MeetingView.runDiarization` can later be removed once UI flows are migrated.
