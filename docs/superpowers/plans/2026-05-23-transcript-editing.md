# Transcript Editing & Reporting Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Réduit la sur-segmentation diarization, permet de supprimer un segment (texte + audio), permet de marquer des passages "importants" injectés dans le prompt LLM.

**Architecture:** Refactor `TurnAligner.mergeConsecutive` en helper réutilisable, nouvelle passe `TranscriptionService.canonicalizeClusters` post-matching, nouveau `TranscriptEditService` + `AudioFileEditor.cut` pour la suppression, nouveau champ `TranscriptSegment.isHighlighted` + `TranscriptHighlightsBuilder` + wrapping `[IMPORTANT]` dans `{{transcript}}`, menu contextuel sur badge speaker. Presets diarization threshold dans SettingsView.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, AVFoundation.

---

## File map

| Path | Change |
|---|---|
| `OneToOne/Services/TurnAligner.swift` | Extract `static mergeConsecutive(_:)` (refactor) |
| `OneToOne/Services/TranscriptionService.swift` | Add `canonicalizeClusters(_:assignments:)` + wire avant persist |
| `OneToOne/Models/TranscriptSegment.swift` | Add `isHighlighted: Bool = false` |
| `OneToOne/Services/TranscriptHighlightsBuilder.swift` (nouveau) | Build liste highlighted formatée pour LLM |
| `OneToOne/Services/TranscriptTextBuilder.swift` (nouveau) | Render `{{transcript}}` dynamique depuis segments avec wrap `[IMPORTANT]` |
| `OneToOne/Services/ReportTemplating.swift` | Nouveaux case `transcript.highlights` + bascule `transcript` vers builder dynamique |
| `OneToOne/Services/AIReportService.swift` | Fallback append `{{transcript.highlights}}` |
| `OneToOne/Services/AudioFileEditor.swift` | Add `static cut(url:from:to:)` (split + concat) |
| `OneToOne/Services/TranscriptEditService.swift` (nouveau) | `deleteSegment(_:in:context:)` atomique texte+audio+shift |
| `OneToOne/Views/MeetingView.swift` | `.contextMenu` sur badge speaker (highlight + delete) ; affichage highlighted ; alert |
| `OneToOne/Views/SettingsView.swift` | 3 boutons presets threshold + default 0.70 |
| `OneToOne/Models/AppSettings.swift` | Default `diarizationClusterThreshold` → 0.70 |
| `Tests/TurnAlignerTests.swift` | +4 tests `mergeConsecutive` |
| `Tests/CanonicalizeClustersTests.swift` (nouveau) | 3 tests TDD |
| `Tests/TranscriptHighlightsBuilderTests.swift` (nouveau) | 3 tests |
| `Tests/TranscriptEditServiceTests.swift` (nouveau) | 4 tests |

Total : 8 modifs + 4 nouveaux fichiers code + 4 fichiers tests.

---

### Task 1: Refactor `TurnAligner.mergeConsecutive`

**Files:**
- Modify: `OneToOne/Services/TurnAligner.swift`
- Modify: `Tests/TurnAlignerTests.swift` (créer si absent)

Extraire la boucle de merge actuelle (lignes 36–56) en helper public statique réutilisable.

- [ ] **Step 1: Ajouter les tests failing**

Append à `TurnAlignerTests` (ou créer `Tests/TurnAlignerTests.swift` avec class minimale si absent) :

```swift
    func test_mergeConsecutive_emptyInput_returnsEmpty() {
        XCTAssertEqual(TurnAligner.mergeConsecutive([]).count, 0)
    }

    func test_mergeConsecutive_singleSegment_returnsSingle() {
        let s = TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "hello", clusterID: 1)
        let out = TurnAligner.mergeConsecutive([s])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].text, "hello")
    }

    func test_mergeConsecutive_mergesAdjacentSameCluster() {
        let a = TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "hello", clusterID: 1)
        let b = TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "world", clusterID: 1)
        let out = TurnAligner.mergeConsecutive([a, b])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startSec, 0)
        XCTAssertEqual(out[0].endSec, 10)
        XCTAssertEqual(out[0].text, "hello world")
        XCTAssertEqual(out[0].clusterID, 1)
    }

    func test_mergeConsecutive_preservesDistinctClusters() {
        let a = TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "hello", clusterID: 1)
        let b = TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "world", clusterID: 2)
        let out = TurnAligner.mergeConsecutive([a, b])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].clusterID, 1)
        XCTAssertEqual(out[1].clusterID, 2)
    }
```

- [ ] **Step 2: Confirmer RED**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift test --filter TurnAlignerTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'mergeConsecutive' in scope`.

- [ ] **Step 3: Extract helper**

Dans `OneToOne/Services/TurnAligner.swift`, remplacer le corps de `align(chunks:turns:)` (à partir de "var merged: ..." ligne ~36) par :

```swift
    static func align(chunks: [STTChunkInput], turns: [DiarTurn]) -> [AlignedSegment] {
        let mapped: [(STTChunkInput, Int)] = chunks.map { chunk in
            (chunk, clusterIDForChunk(chunk, turns: turns))
        }
        let initial: [AlignedSegment] = mapped.map { chunk, cid in
            AlignedSegment(startSec: chunk.startSec, endSec: chunk.endSec, text: chunk.text, clusterID: cid)
        }
        return mergeConsecutive(initial)
    }

    /// Merge consecutive segments sharing the same `clusterID`.
    /// Pure helper, reusable post-canonicalization.
    static func mergeConsecutive(_ segments: [AlignedSegment]) -> [AlignedSegment] {
        var merged: [AlignedSegment] = []
        for s in segments {
            if let last = merged.last, last.clusterID == s.clusterID {
                merged.removeLast()
                let newText = (last.text + " " + s.text).trimmingCharacters(in: .whitespaces)
                merged.append(AlignedSegment(
                    startSec: last.startSec,
                    endSec: s.endSec,
                    text: newText,
                    clusterID: s.clusterID
                ))
            } else {
                merged.append(s)
            }
        }
        return merged
    }
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TurnAlignerTests 2>&1 | tail -10
```
Expected: PASS 4/4 nouveaux + tout existant.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TurnAligner.swift Tests/TurnAlignerTests.swift
git commit -m "refactor(transcript-edit): extract TurnAligner.mergeConsecutive helper"
```

---

### Task 2: `canonicalizeClusters` (TDD)

**Files:**
- Create: `Tests/CanonicalizeClustersTests.swift`
- Modify: `OneToOne/Services/TranscriptionService.swift`

- [ ] **Step 1: Créer le fichier de tests failing**

`Tests/CanonicalizeClustersTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CanonicalizeClustersTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Collaborator.self, Meeting.self, Project.self,
                             ActionTask.self, TranscriptSegment.self, ReportTemplate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_canonicalize_noAssignments_returnsInputUnchanged() throws {
        let ctx = try makeContext()
        let svc = TranscriptionService(settings: AppSettings())
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: [:])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[1].clusterID, 1)
        _ = ctx
    }

    func test_canonicalize_twoClustersOneCollab_unifiesToCanonical() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice")
        ctx.insert(alice)
        try ctx.save()
        let svc = TranscriptionService(settings: AppSettings())
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.85, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: assignments)
        // 2 clusters mapped to same collab → unified, then mergeConsecutive → 1 segment
        XCTAssertEqual(out.count, 1, "Adjacent same-collab clusters should merge")
        XCTAssertEqual(out[0].startSec, 0)
        XCTAssertEqual(out[0].endSec, 10)
        XCTAssertEqual(out[0].text, "a b")
    }

    func test_canonicalize_distinctCollabs_doesNotMerge() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        ctx.insert(alice); ctx.insert(bob)
        try ctx.save()
        let svc = TranscriptionService(settings: AppSettings())
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: bob, confidence: 0.9, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: assignments)
        XCTAssertEqual(out.count, 2)
        XCTAssertNotEqual(out[0].clusterID, out[1].clusterID)
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter CanonicalizeClustersTests 2>&1 | tail -10
```
Expected: FAIL `canonicalizeClustersForTest` not found / `Assignment` init signature mismatch. Si l'init de `Assignment` diffère, lire `OneToOne/Services/SpeakerMatcher.swift` lignes 19–25 et adapter les paramètres.

- [ ] **Step 3: Implémenter `canonicalizeClusters` + test hook**

Dans `OneToOne/Services/TranscriptionService.swift`, après `persistAlignedSegments(...)` (autour ligne 410), ajouter :

```swift
    /// Pour chaque cluster mappé à un Collaborator, réécrit clusterID vers
    /// un cluster canonique (1er rencontré pour ce collab), puis re-merge
    /// consécutifs via `TurnAligner.mergeConsecutive`. Réduit la sur-segmentation
    /// quand Pyannote produit plusieurs clusters pour la même voix réelle.
    func canonicalizeClusters(_ aligned: [TurnAligner.AlignedSegment],
                               assignments: [Int: SpeakerMatcher.Assignment])
        -> [TurnAligner.AlignedSegment]
    {
        // Build map Collaborator.persistentModelID → canonical clusterID
        var canonicalByCollab: [PersistentIdentifier: Int] = [:]
        // Iterate sorted by clusterID for deterministic canonical choice
        for cid in assignments.keys.sorted() {
            guard let collab = assignments[cid]?.collaborator else { continue }
            let pid = collab.persistentModelID
            if canonicalByCollab[pid] == nil {
                canonicalByCollab[pid] = cid
            }
        }
        guard !canonicalByCollab.isEmpty else { return aligned }

        // Rewrite clusterID for segments whose cluster maps to a known collab
        let rewritten: [TurnAligner.AlignedSegment] = aligned.map { seg in
            guard let collab = assignments[seg.clusterID]?.collaborator,
                  let canonical = canonicalByCollab[collab.persistentModelID] else {
                return seg
            }
            if canonical == seg.clusterID { return seg }
            return TurnAligner.AlignedSegment(
                startSec: seg.startSec,
                endSec: seg.endSec,
                text: seg.text,
                clusterID: canonical
            )
        }
        return TurnAligner.mergeConsecutive(rewritten)
    }

    /// Test-only hook to expose the private logic to XCTest.
    #if DEBUG
    func canonicalizeClustersForTest(_ aligned: [TurnAligner.AlignedSegment],
                                      assignments: [Int: SpeakerMatcher.Assignment])
        -> [TurnAligner.AlignedSegment]
    {
        canonicalizeClusters(aligned, assignments: assignments)
    }
    #endif
```

Note : si `TranscriptionService.init(settings:)` n'existe pas avec cette signature, lire le fichier autour des lignes 1–50 pour adapter. Le test instancie `TranscriptionService(settings: AppSettings())` — adapter à l'init réel (peut être `()` sans args).

- [ ] **Step 4: Run tests**

```bash
swift test --filter CanonicalizeClustersTests 2>&1 | tail -10
```
Expected: PASS 3/3.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TranscriptionService.swift Tests/CanonicalizeClustersTests.swift
git commit -m "feat(transcript-edit): canonicalizeClusters réduit la sur-segmentation diarization"
```

---

### Task 3: Wire `canonicalizeClusters` dans `transcribe`

**Files:**
- Modify: `OneToOne/Services/TranscriptionService.swift:350-365`

- [ ] **Step 1: Insérer l'appel**

Dans `transcribe(...)`, autour de la ligne 350 :

Avant :
```swift
        let aligned = TurnAligner.align(chunks: chunks, turns: diarOutput.turns)

        // 4. Match clusters → Collaborators.
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: diarOutput.perClusterEmbedding,
            meeting: meeting,
            in: context,
            settings: settings
        )

        // 5. Persist segments + metadata.
        persistAlignedSegments(
            aligned: aligned,
            assignments: assignments,
            meeting: meeting,
            in: context
        )
```

Après :
```swift
        let aligned = TurnAligner.align(chunks: chunks, turns: diarOutput.turns)

        // 4. Match clusters → Collaborators.
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: diarOutput.perClusterEmbedding,
            meeting: meeting,
            in: context,
            settings: settings
        )

        // 4b. Canonicalize: unify clusters mapped to same Collaborator, then re-merge.
        let canonical = canonicalizeClusters(aligned, assignments: assignments)

        // 5. Persist segments + metadata.
        persistAlignedSegments(
            aligned: canonical,
            assignments: assignments,
            meeting: meeting,
            in: context
        )
```

- [ ] **Step 2: Build + tests existants**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Test Suite 'All tests'|failed" | tail -5
```
Expected: `Build complete!` + 0 failures.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/TranscriptionService.swift
git commit -m "feat(transcript-edit): wire canonicalizeClusters dans pipeline transcribe"
```

---

### Task 4: `TranscriptSegment.isHighlighted` field

**Files:**
- Modify: `OneToOne/Models/TranscriptSegment.swift`

- [ ] **Step 1: Ajouter le champ**

Dans `OneToOne/Models/TranscriptSegment.swift`, juste après `var speakerID: Int = 0` (ligne 21) :

```swift
    /// Marqué par l'utilisateur comme passage important pour le reporting.
    /// Injecté dans `{{transcript.highlights}}` et entouré de marqueurs
    /// `**[IMPORTANT]**...**[/IMPORTANT]**` dans `{{transcript}}`.
    var isHighlighted: Bool = false
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Models/TranscriptSegment.swift
git commit -m "feat(transcript-edit): TranscriptSegment.isHighlighted field"
```

---

### Task 5: `TranscriptHighlightsBuilder` (TDD)

**Files:**
- Create: `OneToOne/Services/TranscriptHighlightsBuilder.swift`
- Create: `Tests/TranscriptHighlightsBuilderTests.swift`

- [ ] **Step 1: Tests failing**

`Tests/TranscriptHighlightsBuilderTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TranscriptHighlightsBuilderTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Collaborator.self, Meeting.self, Project.self,
                             ActionTask.self, TranscriptSegment.self, ReportTemplate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_build_noHighlights_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        let s = TranscriptSegment(orderIndex: 0, startSeconds: 0, endSeconds: 5, text: "hi", speakerID: 1)
        s.meeting = m
        ctx.insert(s)
        try ctx.save()
        XCTAssertEqual(TranscriptHighlightsBuilder.build(meeting: m), "")
    }

    func test_build_oneHighlight_formatsTimestampSpeakerText() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        let s = TranscriptSegment(orderIndex: 0, startSeconds: 65, endSeconds: 70, text: "point clé", speakerID: 1)
        s.meeting = m
        s.speaker = alice
        s.isHighlighted = true
        ctx.insert(s)
        try ctx.save()

        let out = TranscriptHighlightsBuilder.build(meeting: m)
        XCTAssertTrue(out.contains("01:05"), "timestamp 01:05 attendu")
        XCTAssertTrue(out.contains("Alice DUPONT"), "nom speaker attendu")
        XCTAssertTrue(out.contains("point clé"), "texte segment attendu")
    }

    func test_build_multipleHighlights_preservesOrderByStartSec() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        let s1 = TranscriptSegment(orderIndex: 0, startSeconds: 10, endSeconds: 15, text: "early", speakerID: 1)
        let s2 = TranscriptSegment(orderIndex: 1, startSeconds: 100, endSeconds: 105, text: "late", speakerID: 1)
        s1.meeting = m; s2.meeting = m
        s1.isHighlighted = true; s2.isHighlighted = true
        ctx.insert(s1); ctx.insert(s2)
        try ctx.save()

        let out = TranscriptHighlightsBuilder.build(meeting: m)
        guard let earlyRange = out.range(of: "early"),
              let lateRange = out.range(of: "late") else {
            XCTFail("Both segments should appear"); return
        }
        XCTAssertTrue(earlyRange.lowerBound < lateRange.lowerBound, "early avant late")
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter TranscriptHighlightsBuilderTests 2>&1 | tail -10
```
Expected: FAIL `TranscriptHighlightsBuilder` not found.

- [ ] **Step 3: Implémenter le builder**

`OneToOne/Services/TranscriptHighlightsBuilder.swift` :

```swift
import Foundation

/// Construit la liste des passages marqués comme importants par l'utilisateur,
/// formatée pour injection dans le prompt LLM via `{{transcript.highlights}}`.
/// Format : `[mm:ss · Nom du Speaker] Texte du segment` une ligne par highlight.
enum TranscriptHighlightsBuilder {

    static func build(meeting: Meeting) -> String {
        let highlighted = meeting.transcriptSegments
            .filter { $0.isHighlighted }
            .sorted { $0.startSeconds < $1.startSeconds }
        guard !highlighted.isEmpty else { return "" }

        return highlighted.map { seg in
            "[\(seg.formattedTimestamp) · \(seg.displayLabel)] \(seg.text)"
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TranscriptHighlightsBuilderTests 2>&1 | tail -10
```
Expected: PASS 3/3.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TranscriptHighlightsBuilder.swift Tests/TranscriptHighlightsBuilderTests.swift
git commit -m "feat(transcript-edit): TranscriptHighlightsBuilder pour injection LLM"
```

---

### Task 6: `TranscriptTextBuilder` + wrap `[IMPORTANT]`

**Files:**
- Create: `OneToOne/Services/TranscriptTextBuilder.swift`
- Modify: `OneToOne/Services/ReportTemplating.swift:60`

Render `{{transcript}}` depuis `meeting.transcriptSegments` avec wrap `**[IMPORTANT]**` autour des segments highlighted. Fallback sur `meeting.mergedTranscript` si aucun segment (transcript pasté manuellement).

- [ ] **Step 1: Créer le builder**

`OneToOne/Services/TranscriptTextBuilder.swift` :

```swift
import Foundation

/// Render le contenu de la variable `{{transcript}}` à partir des segments
/// de la réunion. Les segments marqués `isHighlighted` sont entourés de
/// marqueurs `**[IMPORTANT]**...**[/IMPORTANT]**` pour signaler explicitement
/// au LLM les passages prioritaires.
///
/// Fallback : si la réunion n'a pas de `transcriptSegments` (transcript pasté
/// manuellement), retourne `meeting.mergedTranscript` tel quel.
enum TranscriptTextBuilder {

    static func build(meeting: Meeting) -> String {
        let segments = meeting.transcriptSegments.sorted { $0.orderIndex < $1.orderIndex }
        guard !segments.isEmpty else { return meeting.mergedTranscript }

        return segments.map { seg in
            let prefix = "[\(seg.formattedTimestamp) · \(seg.displayLabel)] "
            if seg.isHighlighted {
                return prefix + "**[IMPORTANT]** " + seg.text + " **[/IMPORTANT]**"
            }
            return prefix + seg.text
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Modifier `ReportTemplating` case transcript**

Dans `OneToOne/Services/ReportTemplating.swift`, trouver la ligne 60 :
```swift
        case "transcript":     return meeting.mergedTranscript
```
Remplacer par :
```swift
        case "transcript":     return TranscriptTextBuilder.build(meeting: meeting)
```

- [ ] **Step 3: Ajouter case `transcript.highlights`**

Dans le même `switch` de `resolveOne` (juste après le case `"transcript"`), ajouter :
```swift
        case "transcript.highlights":
            return TranscriptHighlightsBuilder.build(meeting: meeting)
```

- [ ] **Step 4: Build + tests existants**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Test Suite 'All tests'|failed" | tail -5
```
Expected: `Build complete!` + 0 failures.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TranscriptTextBuilder.swift OneToOne/Services/ReportTemplating.swift
git commit -m "feat(transcript-edit): wrap [IMPORTANT] + variable transcript.highlights"
```

---

### Task 7: `AIReportService` fallback append `transcript.highlights`

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Localiser**

```bash
grep -n "hasProjectsPlaceholder\|hasTeamPlaceholder" OneToOne/Services/AIReportService.swift
```

- [ ] **Step 2: Ajouter le fallback**

Juste après le bloc `if !hasTeamPlaceholder { ... }` (sub-projet 3 task 4), ajouter :

```swift
        // Fallback append des passages marqués importants par l'utilisateur.
        // Si le template ne contient pas `{{transcript.highlights}}` mais que
        // la réunion a des segments highlighted, append en queue pour donner
        // au LLM le signal explicite.
        let hasHighlightsPlaceholder = body.contains("{{transcript.highlights}}")
        if !hasHighlightsPlaceholder {
            let highlights = TranscriptHighlightsBuilder.build(meeting: meeting)
            if !highlights.isEmpty {
                historyAppendix += "\n\nPassages marqués importants par l'utilisateur :\n\(highlights)\n"
            }
        }
```

Adapter les noms de variables (`body`, `meeting`, `historyAppendix`) à ceux du fallback existant si différents.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(transcript-edit): fallback append {{transcript.highlights}}"
```

---

### Task 8: `AudioFileEditor.cut`

**Files:**
- Modify: `OneToOne/Services/AudioFileEditor.swift`

Supprime in-place une portion `[fromSec, toSec]` d'un wav. Implémentation via AVFoundation composition pour éviter le triple split.

- [ ] **Step 1: Inspecter l'existant**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "import\|static func split\|AVAsset\|AVMutableComposition" OneToOne/Services/AudioFileEditor.swift
```

- [ ] **Step 2: Ajouter `cut`**

Append à la fin du `enum AudioFileEditor` dans `OneToOne/Services/AudioFileEditor.swift` (avant la fermeture `}`) :

```swift
    /// Supprime en place la portion `[fromSec, toSec]` du wav.
    /// Implémentation : crée une composition `[0,fromSec) + [toSec,duration]`,
    /// exporte vers un fichier temporaire, remplace l'original atomiquement.
    /// Throw si `fromSec >= toSec` ou si l'I/O échoue.
    static func cut(url: URL, from fromSec: Double, to toSec: Double) async throws {
        guard fromSec < toSec, fromSec >= 0 else {
            throw NSError(domain: "AudioFileEditor.cut", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid range [\(fromSec), \(toSec)]"])
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSec = CMTimeGetSeconds(duration)
        let to = min(toSec, totalSec)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "AudioFileEditor.cut", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
        }
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioFileEditor.cut", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No audio track in source"])
        }

        // Head: [0, fromSec)
        if fromSec > 0 {
            let headRange = CMTimeRange(
                start: .zero,
                end: CMTime(seconds: fromSec, preferredTimescale: 44100)
            )
            try track.insertTimeRange(headRange, of: sourceTrack, at: .zero)
        }
        // Tail: [toSec, totalSec]
        if to < totalSec {
            let tailRange = CMTimeRange(
                start: CMTime(seconds: to, preferredTimescale: 44100),
                end: duration
            )
            let insertAt = CMTime(seconds: fromSec, preferredTimescale: 44100)
            try track.insertTimeRange(tailRange, of: sourceTrack, at: insertAt)
        }

        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".cut.wav")
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw NSError(domain: "AudioFileEditor.cut", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create exporter"])
        }
        exporter.outputURL = tmpURL
        exporter.outputFileType = .wav

        await exporter.export()
        if let err = exporter.error {
            try? FileManager.default.removeItem(at: tmpURL)
            throw err
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: "AudioFileEditor.cut", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Export status=\(exporter.status.rawValue)"])
        }

        // Atomic replace
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
    }
```

Si `AVURLAsset.load(.duration)` ou `loadTracks(withMediaType:)` n'est pas dispo (target macOS < 13), utiliser les API sync `asset.duration` / `asset.tracks(withMediaType:)`.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`. Si manque `import AVFoundation`, l'ajouter en haut du fichier.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AudioFileEditor.swift
git commit -m "feat(transcript-edit): AudioFileEditor.cut — splice atomique range wav"
```

---

### Task 9: `TranscriptEditService.deleteSegment` (TDD)

**Files:**
- Create: `OneToOne/Services/TranscriptEditService.swift`
- Create: `Tests/TranscriptEditServiceTests.swift`

- [ ] **Step 1: Tests failing**

`Tests/TranscriptEditServiceTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TranscriptEditServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Collaborator.self, Meeting.self, Project.self,
                             ActionTask.self, TranscriptSegment.self, ReportTemplate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func insertSegments(_ tuples: [(Int, Double, Double, String)],
                                 meeting: Meeting,
                                 context: ModelContext) {
        for (idx, start, end, text) in tuples {
            let s = TranscriptSegment(orderIndex: idx, startSeconds: start,
                                      endSeconds: end, text: text, speakerID: 1)
            s.meeting = meeting
            context.insert(s)
        }
    }

    func test_delete_shiftsLaterSegmentsByRemovedDuration() async throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        // No wavFilePath → audio-less branch
        insertSegments([
            (0, 0, 5, "a"),
            (1, 5, 15, "b"),  // to delete: removedDuration = 10
            (2, 15, 20, "c"),
            (3, 20, 25, "d")
        ], meeting: m, context: ctx)
        try ctx.save()

        let target = m.transcriptSegments.first { $0.text == "b" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: ctx)

        let remaining = m.transcriptSegments.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(remaining.count, 3)
        XCTAssertEqual(remaining[0].text, "a")
        XCTAssertEqual(remaining[0].startSeconds, 0)
        XCTAssertEqual(remaining[1].text, "c")
        XCTAssertEqual(remaining[1].startSeconds, 5, "c shifted from 15 to 5")
        XCTAssertEqual(remaining[1].endSeconds, 10, "c shifted from 20 to 10")
        XCTAssertEqual(remaining[2].text, "d")
        XCTAssertEqual(remaining[2].startSeconds, 10)
    }

    func test_delete_doesNotShiftEarlierSegments() async throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        insertSegments([
            (0, 0, 5, "a"),
            (1, 5, 10, "b"),
            (2, 10, 15, "c")  // to delete
        ], meeting: m, context: ctx)
        try ctx.save()

        let target = m.transcriptSegments.first { $0.text == "c" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: ctx)

        let remaining = m.transcriptSegments.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].startSeconds, 0)
        XCTAssertEqual(remaining[1].startSeconds, 5, "earlier segments unchanged")
    }

    func test_delete_removesTargetSegment() async throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        ctx.insert(m)
        insertSegments([(0, 0, 5, "a"), (1, 5, 10, "b")], meeting: m, context: ctx)
        try ctx.save()

        let target = m.transcriptSegments.first { $0.text == "a" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: ctx)

        XCTAssertEqual(m.transcriptSegments.count, 1)
        XCTAssertFalse(m.transcriptSegments.contains { $0.text == "a" })
    }

    func test_delete_audioMissing_deletesTextOnly_noThrow() async throws {
        let ctx = try makeContext()
        let m = Meeting(title: "M", date: Date())
        // wavFilePath nil → audioAvailability == .deleted → skip splice
        ctx.insert(m)
        insertSegments([(0, 0, 5, "a")], meeting: m, context: ctx)
        try ctx.save()

        let target = m.transcriptSegments.first!
        try await TranscriptEditService.deleteSegment(target, in: m, context: ctx)
        XCTAssertEqual(m.transcriptSegments.count, 0)
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter TranscriptEditServiceTests 2>&1 | tail -10
```
Expected: FAIL `TranscriptEditService` not found.

- [ ] **Step 3: Implémenter le service**

`OneToOne/Services/TranscriptEditService.swift` :

```swift
import Foundation
import SwiftData

/// Édition destructive du transcript. Suppression atomique d'un segment :
/// texte + portion audio + shift des segments postérieurs.
enum TranscriptEditService {

    /// Supprime `seg` du transcript et splice la portion `[seg.startSeconds,
    /// seg.endSeconds]` du wav si dispo. Tous les segments commençant après
    /// `seg.endSeconds` voient leurs timestamps shiftés vers la gauche par
    /// `seg.endSeconds - seg.startSeconds`.
    ///
    /// Si `meeting.audioAvailability != .original`, le splice audio est skippé
    /// (texte supprimé seul, l'appelant peut détecter via le retour).
    ///
    /// Throw si le splice audio échoue (transcript intact).
    static func deleteSegment(_ seg: TranscriptSegment,
                               in meeting: Meeting,
                               context: ModelContext) async throws {
        let removedDuration = seg.endSeconds - seg.startSeconds
        let cutFrom = seg.startSeconds
        let cutTo = seg.endSeconds

        // 1. Splice audio first (failure-safe: si throw, transcript intact)
        if meeting.audioAvailability == .original, let wavURL = meeting.wavFileURL {
            try await AudioFileEditor.cut(url: wavURL, from: cutFrom, to: cutTo)
        }

        // 2. Shift segments after the cut
        for other in meeting.transcriptSegments {
            if other.persistentModelID == seg.persistentModelID { continue }
            if other.startSeconds >= cutTo {
                other.startSeconds -= removedDuration
                other.endSeconds -= removedDuration
            }
        }

        // 3. Delete target segment
        context.delete(seg)
        try context.save()
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter TranscriptEditServiceTests 2>&1 | tail -10
```
Expected: PASS 4/4.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TranscriptEditService.swift Tests/TranscriptEditServiceTests.swift
git commit -m "feat(transcript-edit): TranscriptEditService.deleteSegment atomique texte+audio+shift"
```

---

### Task 10: UI menu contextuel badge speaker

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift:1801, 1866-1940`

Ajouter `.contextMenu` sur le `speakerBadge` (3 variantes : assigned, suggestion, anonymous) avec items Marquer/Retirer important + Supprimer ce passage. Plus affichage highlighted dans `segmentRow`.

- [ ] **Step 1: Ajouter state pour confirmation delete**

Vers la ligne 130 de `MeetingView.swift`, dans la `@State` group, ajouter :

```swift
    @State private var segmentToDelete: TranscriptSegment?
```

- [ ] **Step 2: Modifier `segmentRow` pour bg highlight + alert**

Dans `segmentRow(_:)` (ligne 1795), wrapper la `HStack` existante :

```swift
    private func segmentRow(_ seg: TranscriptSegment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            speakerBadge(for: seg)

            Button {
                playSegmentAudio(seg)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.caption2)
                    Text(seg.formattedTimestamp)
                        .font(.caption.monospacedDigit().bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    Capsule().fill(meeting.wavFileURL == nil
                                   ? Color.secondary.opacity(0.15)
                                   : Color.accentColor.opacity(0.18))
                )
                .foregroundColor(meeting.wavFileURL == nil ? .secondary : .accentColor)
                .overlay(
                    Capsule().stroke(
                        meeting.wavFileURL == nil ? Color.clear : Color.accentColor.opacity(0.4),
                        lineWidth: 0.5
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(meeting.wavFileURL == nil)
            .help(meeting.wavFileURL == nil
                  ? "Aucun audio attaché à la réunion"
                  : "Lire l'audio à partir de \(seg.formattedTimestamp)")

            HStack(spacing: 4) {
                if seg.isHighlighted {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(seg.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .background(seg.isHighlighted ? Color.yellow.opacity(0.08) : Color.clear)
    }
```

- [ ] **Step 3: Helper menu factor + apply sur les 3 variantes du badge**

Dans `MeetingView.swift`, juste avant `private func speakerBadge(for seg: TranscriptSegment)` (ligne 1866), ajouter un helper :

```swift
    @ViewBuilder
    private func segmentActionsMenu(_ seg: TranscriptSegment) -> some View {
        Button {
            seg.isHighlighted.toggle()
            try? modelContext.save()
        } label: {
            Label(seg.isHighlighted ? "Retirer l'importance" : "Marquer comme important",
                  systemImage: seg.isHighlighted ? "star.slash" : "star.fill")
        }
        Divider()
        Button(role: .destructive) {
            segmentToDelete = seg
        } label: {
            Label("Supprimer ce passage", systemImage: "trash")
        }
    }
```

Puis dans `speakerBadge(for:)`, ajouter `.contextMenu { segmentActionsMenu(seg) }` après chacun des 3 `Button` (lignes ~1890, ~1916 implicite sur HStack suggestion, ~1932) — pour la variante "suggestion" (HStack sans Button parent ligne 1900), wrapper la HStack dans un `Button` no-op ou attacher `.contextMenu` directement sur le HStack.

Concrètement, modifier les 3 emplacements :

**Variante 1 (assigned, ligne 1872-1890)** — après `.popover(...)`, juste avant la fin du `if let speaker`, ajouter `.contextMenu { segmentActionsMenu(seg) }` :
```swift
            .popover(isPresented: Binding(
                get: { renamingSpeakerID == seg.speakerID },
                set: { if !$0 { renamingSpeakerID = nil } }
            )) {
                speakerRenamePopover(speakerID: seg.speakerID).padding(12).frame(minWidth: 240)
            }
            .contextMenu { segmentActionsMenu(seg) }   // <-- AJOUT
```

**Variante 2 (suggestion, ligne 1900-1916)** — sur le `HStack` final :
```swift
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.10))
            .clipShape(Capsule())
            .contextMenu { segmentActionsMenu(seg) }   // <-- AJOUT
```

**Variante 3 (anonymous, ligne 1933-1938)** — après le `.popover` final :
```swift
            .popover(isPresented: Binding(
                get: { renamingSpeakerID == seg.speakerID },
                set: { if !$0 { renamingSpeakerID = nil } }
            )) {
                speakerRenamePopover(speakerID: seg.speakerID).padding(12).frame(minWidth: 240)
            }
            .contextMenu { segmentActionsMenu(seg) }   // <-- AJOUT
```

- [ ] **Step 4: Ajouter l'alert au container parent**

Trouver la `ScrollView` ou `VStack` parent qui contient `ForEach(meeting.transcriptSegments) { segmentRow($0) }`. Lui attacher :

```swift
        .alert("Supprimer ce passage ?",
               isPresented: Binding(get: { segmentToDelete != nil },
                                     set: { if !$0 { segmentToDelete = nil } }),
               presenting: segmentToDelete) { seg in
            Button("Annuler", role: .cancel) { segmentToDelete = nil }
            Button("Supprimer", role: .destructive) {
                let target = seg
                segmentToDelete = nil
                Task {
                    do {
                        try await TranscriptEditService.deleteSegment(
                            target, in: meeting, context: modelContext
                        )
                    } catch {
                        print("[MeetingView] deleteSegment failed: \(error)")
                    }
                }
            }
        } message: { _ in
            Text("Le texte et la portion audio correspondante seront supprimés définitivement.")
        }
```

Localiser via :
```bash
grep -n "ForEach(meeting.transcriptSegments\|segmentRow(seg)\|segmentRow($0)" OneToOne/Views/MeetingView.swift
```

L'alert va juste après la fermeture de la `ScrollView`/`LazyVStack` contenant les segmentRow.

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(transcript-edit): UI contextMenu badge + highlight bg + delete alert"
```

---

### Task 11: SettingsView presets threshold + default 0.70

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift:179`
- Modify: `OneToOne/Views/SettingsView.swift:660-685`

- [ ] **Step 1: Bumper le default**

Dans `OneToOne/Models/AppSettings.swift` ligne 179 :

Avant :
```swift
    var diarizationClusterThreshold: Double = 0.85
```

Après :
```swift
    var diarizationClusterThreshold: Double = 0.70
```

- [ ] **Step 2: Ajouter les 3 boutons presets dans SettingsView**

Localiser dans `OneToOne/Views/SettingsView.swift` autour de la ligne 667 :

```bash
grep -n "diarizationClusterThreshold\|Séparation des voix" OneToOne/Views/SettingsView.swift
```

Juste avant le `Slider`, insérer une `HStack` de 3 boutons :

```swift
                            HStack(spacing: 8) {
                                Button("Plus de speakers") {
                                    settings.diarizationClusterThreshold = 0.95
                                    saveSettings()
                                }
                                .fontWeight(settings.diarizationClusterThreshold == 0.95 ? .bold : .regular)
                                Button("Équilibré") {
                                    settings.diarizationClusterThreshold = 0.85
                                    saveSettings()
                                }
                                .fontWeight(settings.diarizationClusterThreshold == 0.85 ? .bold : .regular)
                                Button("Moins de speakers") {
                                    settings.diarizationClusterThreshold = 0.70
                                    saveSettings()
                                }
                                .fontWeight(settings.diarizationClusterThreshold == 0.70 ? .bold : .regular)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
```

Adapter à la structure VStack/Form environnante (matcher l'indentation).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Models/AppSettings.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(transcript-edit): presets threshold diarization + default 0.70"
```

---

### Task 12: Final build + smoke

**Files:** (aucun)

- [ ] **Step 1: Full build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 2: Tous les tests**

```bash
swift test 2>&1 | grep -E "Test Suite 'All tests'|with [0-9]+ failure" | tail -5
```
Expected: tous PASS, 0 failure.

- [ ] **Step 3: Smoke checklist (Xcode Cmd+R)**

1. **Diarization canonicalize** : Retranscribe une réunion 5min avec 2 voix. Avant : N segments redondants. Après : moins de segments, fusion attendue sur passages mono-speaker.
2. **Highlight** : Clic droit badge speaker → "Marquer comme important". Vérifier :
   - Étoile ⭐ apparaît avant le texte.
   - Bg jaune subtil sur le row.
3. **Delete** : Clic droit badge → "Supprimer ce passage". Alert apparaît. Confirm.
   - Segment disparaît du transcript.
   - Wav raccourci de la durée (vérifier via player : durée totale -= durée segment).
   - Segments suivants : timestamps shiftés (premier suivant doit commencer là où le supprimé commençait).
4. **Delete sans audio** : Sur meeting où `wavFilePath` est nil (purgé), delete doit fonctionner (texte seul, pas d'erreur).
5. **Generate report** : Sur meeting avec highlights, déclencher génération.
   - Console : prompt LLM doit contenir `**[IMPORTANT]**...**[/IMPORTANT]**` autour des passages marqués.
   - Si template contient `{{transcript.highlights}}`, section dédiée peuplée.
   - Sinon, fallback append "Passages marqués importants par l'utilisateur :" en queue.
6. **Settings presets** : Préfs → Diarization → cliquer "Moins de speakers" → slider va à 0.70, label bold.

- [ ] **Step 4: Historique commits**

```bash
git log --oneline -15
```
Attendu : 11 commits `feat(transcript-edit):` / `refactor(transcript-edit):` pour Tasks 1-11.

---

## Self-review

**Spec coverage** :
- §5.1 `TranscriptSegment.isHighlighted` → Task 4. ✓
- §5.2 `diarizationClusterThreshold` default 0.70 → Task 11. ✓
- §6.1 `TurnAligner.mergeConsecutive` extract → Task 1. ✓
- §6.2 `canonicalizeClusters` → Task 2 (impl + tests) + Task 3 (wire). ✓
- §6.3 `AudioFileEditor.cut` → Task 8. ✓
- §6.4 `TranscriptEditService.deleteSegment` → Task 9. ✓
- §6.5 `TranscriptHighlightsBuilder` → Task 5. ✓
- §6.6 ReportTemplating case + wrap `[IMPORTANT]` → Task 6. ✓
- §6.7 AIReportService fallback append → Task 7. ✓
- §7.1 contextMenu badge + alert delete → Task 10. ✓
- §7.2 affichage highlighted (bg + étoile) → Task 10. ✓
- §7.3 SettingsView presets → Task 11. ✓
- §8 data flow → tous tasks. ✓
- §9 error handling → Task 9 (audio missing branch). ✓
- §10 testing → Tasks 1, 2, 5, 9. ✓
- §11 migration (no-op SwiftData) → couvert implicitement Task 4. ✓
- §12 YAGNI → respecté.
- §13 dépendances → reflétées dans ordre des tasks.

**Placeholder scan** :
- Aucun "TBD" / "implement later".
- Toutes les snippets code sont complètes.
- Adaptations notées (Task 2 init signature, Task 6 grep, Task 10 grep) sont des steps explicites de localisation, pas des placeholders.

**Type consistency** :
- `TurnAligner.AlignedSegment` (Tasks 1, 2). ✓
- `TurnAligner.mergeConsecutive(_:)` (Tasks 1, 2). ✓
- `SpeakerMatcher.Assignment` (Task 2 — adaptation init signaler si différent). ✓
- `TranscriptionService.canonicalizeClusters(_:assignments:)` (Tasks 2, 3). ✓
- `TranscriptSegment.isHighlighted: Bool` (Tasks 4, 5, 6, 10). ✓
- `TranscriptHighlightsBuilder.build(meeting:)` (Tasks 5, 6, 7). ✓
- `TranscriptTextBuilder.build(meeting:)` (Task 6). ✓
- `AudioFileEditor.cut(url:from:to:)` (Tasks 8, 9). ✓
- `TranscriptEditService.deleteSegment(_:in:context:)` (Tasks 9, 10). ✓
- `segmentActionsMenu(_:)` (Task 10). ✓
- `segmentToDelete` state (Task 10). ✓
- `meeting.audioAvailability` enum cases (Task 9 — `.original`). ✓

Aucune correction inline nécessaire.
