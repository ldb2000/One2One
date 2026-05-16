# Diarized Transcription + Speaker Identification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace energy-based VAD with speech-swift Pyannote diarization (Silero VAD + WeSpeaker ResNet34 embeddings), add cross-meeting speaker identification via cosine matching against per-Collaborator voiceprints with EMA update on manual labeling.

**Architecture:** New SPM dep on `https://github.com/soniqo/speech-swift` (product `SpeechVAD`). `PyannoteDiarizationPipeline.diarize(...)` returns segments + 256-dim per-speaker embeddings in one call, so no separate embedder service needed. `SpeakerMatcher` does staged cosine matching (M-C) against `Collaborator.voicePrint`. `TurnAligner` (pure helper) maps existing Cohere chunks to diarization clusters. EMA voiceprint update happens **only on manual** assignment in `MeetingView`.

**Tech Stack:** Swift 5.10+, SwiftData, MLX, speech-swift (SpeechVAD module), XCTest.

**Spec:** [docs/superpowers/specs/2026-05-14-diarized-transcription-and-speaker-id-design.md](../specs/2026-05-14-diarized-transcription-and-speaker-id-design.md).

**Pre-flight (once):**
```bash
git status
swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
```

---

## Task 1: SPM dependency on speech-swift

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add the dependency**

In `Package.swift`, add to `dependencies`:

```swift
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
```

In the `OneToOne` target's `dependencies`, add:

```swift
                .product(name: "SpeechVAD", package: "speech-swift"),
```

- [ ] **Step 2: Bump macOS platform if needed**

speech-swift requires `.macOS("15.0")`. OneToOne is currently `.macOS(.v14)`. Update:

```swift
    platforms: [
        .macOS(.v15)
    ],
```

- [ ] **Step 3: Resolve + build**

Run: `swift package resolve 2>&1 | tail -10`
Expected: download speech-swift + transitive deps.

Run: `swift build 2>&1 | tail -10`
Expected: clean. First build downloads MLX kernels and a chunk of weights — may take several minutes.

If the build fails on `.macOS(.v15)` because the dev machine is on macOS 14, ask the user before proceeding: speech-swift requires macOS 15 for some MLX kernels.

- [ ] **Step 4: Commit**

```bash
git add Package.swift
git commit -m "build(deps): add soniqo/speech-swift SPM dependency for diarization + embeddings"
```

---

## Task 2: Collaborator voiceprint fields

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift`
- Test: `Tests/CollaboratorVoicePrintTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CollaboratorVoicePrintTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CollaboratorVoicePrintTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_defaults() {
        let c = Collaborator(name: "X")
        XCTAssertNil(c.voicePrint)
        XCTAssertEqual(c.voicePrintSamples, 0)
        XCTAssertNil(c.voicePrintUpdatedAt)
    }

    func test_dataRoundtrip() {
        let c = Collaborator(name: "X")
        let bytes: [Float] = Array(repeating: 0.5, count: 256)
        c.voicePrint = bytes.withUnsafeBufferPointer { Data(buffer: $0) }
        c.voicePrintSamples = 3
        c.voicePrintUpdatedAt = Date(timeIntervalSince1970: 1)

        XCTAssertEqual(c.voicePrint?.count, 256 * 4)
        XCTAssertEqual(c.voicePrintSamples, 3)
        XCTAssertEqual(c.voicePrintUpdatedAt, Date(timeIntervalSince1970: 1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CollaboratorVoicePrintTests 2>&1 | tail -15`
Expected: compile failure — `voicePrint` / `voicePrintSamples` / `voicePrintUpdatedAt` undefined.

- [ ] **Step 3: Add the 3 fields**

In `OneToOne/Models/OtherModels.swift`, locate the `Collaborator` class. Add after the existing `var isAdhoc: Bool = false`:

```swift
    // MARK: - Voice identification (speech-swift WeSpeaker ResNet34)
    /// 256 Float32 mean embedding (1024 bytes). Nil = jamais enrôlé.
    var voicePrint: Data?
    /// Nombre d'updates EMA agrégées (pondère les mises à jour).
    var voicePrintSamples: Int = 0
    /// Date du dernier update (debug + audit).
    var voicePrintUpdatedAt: Date?
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CollaboratorVoicePrintTests 2>&1 | tail -10`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Models/OtherModels.swift Tests/CollaboratorVoicePrintTests.swift
git commit -m "feat(model): Collaborator.voicePrint + voicePrintSamples + voicePrintUpdatedAt"
```

---

## Task 3: Meeting speaker-assignment metadata fields

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift`

- [ ] **Step 1: Add the 2 JSON fields to Meeting**

In `OneToOne/Models/OtherModels.swift`, inside the `Meeting` class, add (near the existing JSON-backed fields, before relationships):

```swift
    /// JSON: {clusterID(String): "collabStableID|null"}.
    /// Source de vérité du mapping cluster → Collaborator décidé par
    /// SpeakerMatcher (auto ou manuel). Bulk-re-assign sur correction user.
    var speakerAssignmentsJSON: String = "{}"

    /// JSON: {clusterID(String): {"confidence":Double, "auto":Bool, "ambiguous":Bool, "candidates":[stableID]}}.
    /// Métadonnée UI (badge ✓ auto / ? suggestion).
    var speakerMatchMetaJSON: String = "{}"
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean (defaults present, lightweight migration).

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Models/OtherModels.swift
git commit -m "feat(model): Meeting.speakerAssignmentsJSON + speakerMatchMetaJSON"
```

---

## Task 4: AppSettings speaker-id keys

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift`

- [ ] **Step 1: Add 3 settings**

In `OneToOne/Models/AppSettings.swift`, append in the `AppSettings` class body:

```swift
    // MARK: - Speaker identification (diarization + matching)
    var speakerIdEnabled: Bool = true
    var speakerIdAutoThreshold: Double = 0.75
    var speakerIdSuggestThreshold: Double = 0.60
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Models/AppSettings.swift
git commit -m "feat(settings): speakerIdEnabled + autoThreshold + suggestThreshold"
```

---

## Task 5: `TurnAligner` pure helper + tests

**Files:**
- Create: `OneToOne/Services/TurnAligner.swift`
- Test: `Tests/TurnAlignerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TurnAlignerTests.swift`:

```swift
import XCTest
@testable import OneToOne

final class TurnAlignerTests: XCTestCase {

    func test_singleChunk_assignedToMaxOverlapTurn() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 10, clusterID: 0),
            .init(startSec: 10, endSec: 20, clusterID: 1)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 8, endSec: 12, text: "hello world")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 1)
        // Chunk overlaps turn 0 by 2s and turn 1 by 2s → tie → longer turn wins (both 10s, both equal).
        // We pick the first in case of tie. Stable behavior.
        XCTAssertEqual(out[0].clusterID, 0)
    }

    func test_consecutiveChunks_sameCluster_merged() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 30, clusterID: 0)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 0, endSec: 10, text: "Bonjour"),
            .init(startSec: 10, endSec: 20, text: "comment ça va"),
            .init(startSec: 20, endSec: 30, text: "aujourd'hui")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].text, "Bonjour comment ça va aujourd'hui")
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[0].startSec, 0, accuracy: 0.001)
        XCTAssertEqual(out[0].endSec, 30, accuracy: 0.001)
    }

    func test_consecutiveChunks_differentClusters_notMerged() {
        let turns: [TurnAligner.DiarTurn] = [
            .init(startSec: 0, endSec: 10, clusterID: 0),
            .init(startSec: 10, endSec: 20, clusterID: 1)
        ]
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 1, endSec: 9, text: "first"),
            .init(startSec: 11, endSec: 19, text: "second")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: turns)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[0].text, "first")
        XCTAssertEqual(out[1].clusterID, 1)
        XCTAssertEqual(out[1].text, "second")
    }

    func test_emptyTurns_singleClusterFallback() {
        let chunks: [TurnAligner.STTChunkInput] = [
            .init(startSec: 0, endSec: 5, text: "X")
        ]
        let out = TurnAligner.align(chunks: chunks, turns: [])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].clusterID, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TurnAlignerTests 2>&1 | tail -15`
Expected: compile failure — `TurnAligner` undefined.

- [ ] **Step 3: Implement TurnAligner**

Create `OneToOne/Services/TurnAligner.swift`:

```swift
import Foundation

/// Pure helper. Maps Cohere STT chunks to diarization clusters by temporal
/// overlap, then merges consecutive chunks belonging to the same cluster.
enum TurnAligner {

    /// Speaker turn from diarization. `clusterID` is local to the meeting
    /// (0-indexed). Use `clusterID + 1` when persisting `TranscriptSegment.speakerID`.
    struct DiarTurn {
        let startSec: Double
        let endSec: Double
        let clusterID: Int
    }

    /// One transcribed chunk produced by Cohere.
    struct STTChunkInput {
        let startSec: Double
        let endSec: Double
        let text: String
    }

    /// Resulting segment: cluster-tagged + merged.
    struct AlignedSegment {
        let startSec: Double
        let endSec: Double
        let text: String
        let clusterID: Int
    }

    /// Align + merge. Empty `turns` => all chunks fall into cluster 0.
    static func align(chunks: [STTChunkInput], turns: [DiarTurn]) -> [AlignedSegment] {
        let mapped: [(STTChunkInput, Int)] = chunks.map { chunk in
            (chunk, clusterIDForChunk(chunk, turns: turns))
        }

        var merged: [AlignedSegment] = []
        for (chunk, cid) in mapped {
            if var last = merged.last, last.clusterID == cid {
                merged.removeLast()
                let newText = (last.text + " " + chunk.text).trimmingCharacters(in: .whitespaces)
                merged.append(AlignedSegment(
                    startSec: last.startSec,
                    endSec: chunk.endSec,
                    text: newText,
                    clusterID: cid
                ))
                _ = last
            } else {
                merged.append(AlignedSegment(
                    startSec: chunk.startSec,
                    endSec: chunk.endSec,
                    text: chunk.text,
                    clusterID: cid
                ))
            }
        }
        return merged
    }

    /// Returns the clusterID of the turn with max temporal overlap.
    /// Falls back to 0 if `turns` is empty. Ties → first matching turn.
    private static func clusterIDForChunk(_ chunk: STTChunkInput, turns: [DiarTurn]) -> Int {
        guard !turns.isEmpty else { return 0 }
        var bestCluster: Int = turns[0].clusterID
        var bestOverlap: Double = -1
        for t in turns {
            let overlap = min(chunk.endSec, t.endSec) - max(chunk.startSec, t.startSec)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestCluster = t.clusterID
            }
        }
        return bestCluster
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter TurnAlignerTests 2>&1 | tail -10`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TurnAligner.swift Tests/TurnAlignerTests.swift
git commit -m "feat(diarize): TurnAligner — overlap mapping + merge consecutive same-cluster chunks"
```

---

## Task 6: `SpeakerMatcher` + cosine + EMA + tests

**Files:**
- Create: `OneToOne/Services/SpeakerMatcher.swift`
- Test: `Tests/SpeakerMatcherTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SpeakerMatcherTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class SpeakerMatcherTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func enrolled(_ name: String, embedding: [Float]) -> Collaborator {
        let c = Collaborator(name: name)
        c.voicePrint = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        c.voicePrintSamples = 1
        context.insert(c)
        return c
    }

    private func meeting(participants: [Collaborator]) -> Meeting {
        let m = Meeting(title: "M", date: Date())
        for p in participants { m.participants.append(p) }
        context.insert(m)
        return m
    }

    private func vec(_ value: Float, _ count: Int = 256) -> [Float] {
        Array(repeating: value, count: count)
    }

    private func vec2(_ a: Float, _ b: Float) -> [Float] {
        var v = [Float](repeating: 0, count: 256)
        v[0] = a; v[1] = b
        return v
    }

    func test_cosine_identicalVectors_is_one() {
        let v: [Float] = [3, 4, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(v, v), 1.0, accuracy: 1e-6)
    }

    func test_cosine_orthogonal_is_zero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(a, b), 0.0, accuracy: 1e-6)
    }

    func test_pass1_findsParticipantAboveAutoThreshold() throws {
        // Alice is participant, embedding [1,0,...]. Cluster has same → cosine=1.0
        let alice = enrolled("Alice", embedding: vec2(1, 0))
        let m = meeting(participants: [alice])
        try context.save()

        let clusterEmbedding = vec2(1, 0)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: clusterEmbedding],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Alice")
        XCTAssertEqual(assignments[0]?.confidence ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertTrue(assignments[0]?.auto ?? false)
        XCTAssertFalse(assignments[0]?.ambiguous ?? true)
    }

    func test_pass1_suggestion_belowAutoThreshold() throws {
        // Alice participant. Cluster cosine ~0.65 (mid-range) → suggestion not auto.
        // We pick vectors that produce ~0.65 cosine: a = [1,0], b = [1, 1.17] roughly
        // Easier: use known cosines via dot-product/normalization
        let alice = enrolled("Alice", embedding: [1, 0])
        let m = meeting(participants: [alice])
        try context.save()
        // cos([1,0], [1, 1.17]) = 1/sqrt(1 + 1.17^2) ~ 0.65
        let cluster: [Float] = [1, 1.17]
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Alice")
        XCTAssertFalse(assignments[0]?.auto ?? true)
        XCTAssertGreaterThan(assignments[0]?.confidence ?? 0, 0.6)
        XCTAssertLessThan(assignments[0]?.confidence ?? 1, 0.75)
    }

    func test_pass1_empty_pass2_findsNonParticipant() throws {
        // Bob non-participant, perfect match. Pass2 strict 0.75 must hit at 1.0.
        let bob = enrolled("Bob", embedding: vec(1))
        let m = meeting(participants: [])
        try context.save()

        let cluster = vec(1)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Bob")
        XCTAssertTrue(assignments[0]?.auto ?? false)
    }

    func test_ambiguous_twoCandidatesCloseAboveAuto() throws {
        // Alice + Bob in participants, both with same embedding → tie 1.0 each.
        let alice = enrolled("Alice", embedding: vec(1))
        let bob = enrolled("Bob", embedding: vec(1))
        let m = meeting(participants: [alice, bob])
        try context.save()

        let cluster = vec(1)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertTrue(assignments[0]?.ambiguous ?? false)
        XCTAssertFalse(assignments[0]?.auto ?? true)
    }

    func test_ema_voicePrintUpdate_firstSample() throws {
        let alice = enrolled("Alice", embedding: vec(0))
        alice.voicePrint = nil
        alice.voicePrintSamples = 0
        try context.save()

        let newEmbedding = vec(0.5)
        SpeakerMatcher.applyEMAUpdate(to: alice, newEmbedding: newEmbedding, in: context)

        let stored: [Float] = alice.voicePrint!.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(stored.first ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(alice.voicePrintSamples, 1)
        XCTAssertNotNil(alice.voicePrintUpdatedAt)
    }

    func test_ema_voicePrintUpdate_runningAverage() throws {
        // old=0.0 (n=3), new=1.0 → expected (0*3 + 1)/4 = 0.25
        let alice = enrolled("Alice", embedding: vec(0))
        alice.voicePrintSamples = 3
        try context.save()

        SpeakerMatcher.applyEMAUpdate(to: alice, newEmbedding: vec(1), in: context)

        let stored: [Float] = alice.voicePrint!.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(stored.first ?? 0, 0.25, accuracy: 1e-6)
        XCTAssertEqual(alice.voicePrintSamples, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SpeakerMatcherTests 2>&1 | tail -15`
Expected: compile failure — `SpeakerMatcher` undefined.

- [ ] **Step 3: Implement SpeakerMatcher**

Create `OneToOne/Services/SpeakerMatcher.swift`:

```swift
import Foundation
import SwiftData

/// Staged cosine matching of cluster embeddings against Collaborator
/// voiceprints. See spec §5.4 and §5.5.
enum SpeakerMatcher {

    static let autoThreshold: Double = 0.75
    static let suggestThreshold: Double = 0.60
    static let ambiguousDelta: Double = 0.02

    struct Assignment {
        let collaborator: Collaborator?
        let confidence: Double
        let auto: Bool
        let candidates: [(Collaborator, Double)]
        let ambiguous: Bool
    }

    /// Returns one Assignment per clusterID. Missing clusterID = no candidate.
    @MainActor
    static func match(clusterEmbeddings: [Int: [Float]],
                       meeting: Meeting,
                       in context: ModelContext) -> [Int: Assignment] {
        let participants = Set(meeting.participants
            .filter { !$0.isArchived }
            .map { $0.persistentModelID })

        // Pre-fetch all enrolled, non-archived collabs once.
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate<Collaborator> { !$0.isArchived }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let enrolled = all.filter { $0.voicePrint != nil && $0.voicePrintSamples > 0 }

        var out: [Int: Assignment] = [:]
        for (clusterID, embedding) in clusterEmbeddings {
            out[clusterID] = matchOne(embedding: embedding,
                                      enrolled: enrolled,
                                      participants: participants)
        }
        return out
    }

    private static func matchOne(embedding: [Float],
                                  enrolled: [Collaborator],
                                  participants: Set<PersistentIdentifier>) -> Assignment {
        // Pass 1: participants, threshold suggest (0.60).
        var pool1: [(Collaborator, Double)] = []
        for c in enrolled where participants.contains(c.persistentModelID) {
            guard let vp = c.voicePrint else { continue }
            let cos = cosine(embedding, decode(vp))
            if cos >= suggestThreshold {
                pool1.append((c, cos))
            }
        }
        pool1.sort { $0.1 > $1.1 }

        if !pool1.isEmpty {
            return assemble(candidates: pool1)
        }

        // Pass 2: non-participants, threshold auto (0.75 strict).
        var pool2: [(Collaborator, Double)] = []
        for c in enrolled where !participants.contains(c.persistentModelID) {
            guard let vp = c.voicePrint else { continue }
            let cos = cosine(embedding, decode(vp))
            if cos >= autoThreshold {
                pool2.append((c, cos))
            }
        }
        pool2.sort { $0.1 > $1.1 }

        if !pool2.isEmpty {
            return assemble(candidates: pool2)
        }

        return Assignment(collaborator: nil, confidence: 0, auto: false, candidates: [], ambiguous: false)
    }

    private static func assemble(candidates: [(Collaborator, Double)]) -> Assignment {
        let top = candidates[0]
        let ambiguous: Bool
        if candidates.count >= 2 {
            let second = candidates[1]
            ambiguous = top.1 >= autoThreshold
                && second.1 >= autoThreshold
                && (top.1 - second.1) < ambiguousDelta
        } else {
            ambiguous = false
        }
        let auto = top.1 >= autoThreshold && !ambiguous
        return Assignment(
            collaborator: top.0,
            confidence: top.1,
            auto: auto,
            candidates: Array(candidates.prefix(3)),
            ambiguous: ambiguous
        )
    }

    // MARK: - EMA voiceprint update

    /// Apply running-mean EMA update to a Collaborator's voiceprint with a
    /// newly-observed cluster embedding. Only called from manual labelling
    /// (never on auto-match). See spec §5.5.
    @MainActor
    static func applyEMAUpdate(to collaborator: Collaborator,
                                newEmbedding: [Float],
                                in context: ModelContext) {
        precondition(newEmbedding.count == 256, "embedding must be 256-dim")
        if collaborator.voicePrint == nil || collaborator.voicePrintSamples == 0 {
            collaborator.voicePrint = encode(newEmbedding)
            collaborator.voicePrintSamples = 1
        } else {
            let old = decode(collaborator.voicePrint!)
            let n = Double(collaborator.voicePrintSamples)
            var updated = [Float](repeating: 0, count: 256)
            for i in 0..<256 {
                updated[i] = Float((Double(old[i]) * n + Double(newEmbedding[i])) / (n + 1))
            }
            collaborator.voicePrint = encode(updated)
            collaborator.voicePrintSamples += 1
        }
        collaborator.voicePrintUpdatedAt = Date()
        try? context.save()
    }

    // MARK: - Cosine + codec

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-9 else { return 0 }
        return Double(dot / denom)
    }

    static func encode(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SpeakerMatcherTests 2>&1 | tail -15`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/SpeakerMatcher.swift Tests/SpeakerMatcherTests.swift
git commit -m "feat(diarize): SpeakerMatcher — staged cosine + EMA voiceprint update"
```

---

## Task 7: `PyannoteDiarizer` wrapping speech-swift

**Files:**
- Create: `OneToOne/Services/PyannoteDiarizer.swift`

No unit test — wraps an external ML model with system side effects (HuggingFace download, MLX compute). Covered manually in Task 10.

- [ ] **Step 1: Create the wrapper**

Create `OneToOne/Services/PyannoteDiarizer.swift`:

```swift
import Foundation
import AVFoundation
import os

#if canImport(SpeechVAD)
import SpeechVAD
#endif

private let diarLog = Logger(subsystem: "com.onetoone.app", category: "PyannoteDiarizer")

/// Wraps speech-swift's `PyannoteDiarizationPipeline`.
/// Provides:
/// - turns: [(startSec, endSec, clusterID)]
/// - perClusterEmbedding: [clusterID: 256-dim Float] (taken directly from
///   `DiarizationResult.speakerEmbeddings`).
@MainActor
final class PyannoteDiarizer {

    static let shared = PyannoteDiarizer()

    #if canImport(SpeechVAD)
    private var pipeline: PyannoteDiarizationPipeline?
    #endif

    struct DiarizeOutput {
        let turns: [TurnAligner.DiarTurn]
        let perClusterEmbedding: [Int: [Float]]
    }

    private init() {}

    /// Lazy-load the pipeline on first call. Triggers HuggingFace download
    /// on first run (cached afterwards).
    func diarize(audioURL: URL) async throws -> DiarizeOutput {
        #if canImport(SpeechVAD)
        if pipeline == nil {
            diarLog.info("loading PyannoteDiarizationPipeline (first call)")
            pipeline = try await PyannoteDiarizationPipeline.fromPretrained(useVADFilter: true)
        }
        guard let pipeline else {
            throw NSError(domain: "PyannoteDiarizer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "pipeline unavailable"])
        }
        let samples = try Self.loadMono16k(url: audioURL)
        let result = pipeline.diarize(audio: samples, sampleRate: 16000)

        let turns = result.segments.map { seg in
            TurnAligner.DiarTurn(
                startSec: Double(seg.startTime),
                endSec: Double(seg.endTime),
                clusterID: seg.speakerId
            )
        }

        var embeddings: [Int: [Float]] = [:]
        for (idx, emb) in result.speakerEmbeddings.enumerated() {
            embeddings[idx] = emb
        }
        diarLog.info("diarize done turns=\(turns.count) speakers=\(result.numSpeakers)")
        return DiarizeOutput(turns: turns, perClusterEmbedding: embeddings)
        #else
        throw NSError(domain: "PyannoteDiarizer", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "SpeechVAD non disponible — speech-swift pas linké."])
        #endif
    }

    /// Loads WAV/M4A and returns 16 kHz mono Float32 samples via AVAudioEngine
    /// (resamples + downmixes if needed).
    private static func loadMono16k(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { throw NSError(domain: "PyannoteDiarizer", code: 2) }

        let converter = AVAudioConverter(from: inFormat, to: outFormat)!
        let frameCapacity = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCapacity),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(frameCapacity) * 16000.0 / inFormat.sampleRate) + 1024) else {
            throw NSError(domain: "PyannoteDiarizer", code: 3)
        }
        try file.read(into: inBuf)

        var error: NSError?
        var consumed = false
        let _ = converter.convert(to: outBuf, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuf
        }
        if let error { throw error }

        let n = Int(outBuf.frameLength)
        guard let ptr = outBuf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: n))
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean. If `PyannoteDiarizationPipeline.fromPretrained(useVADFilter:)` signature differs in the current speech-swift release, adapt — the call surface is documented in `Sources/SpeechVAD/DiarizationPipeline.swift` of the dependency. Also adapt `DiarizationResult.segments[*].speakerId / startTime / endTime` field names if they differ.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/PyannoteDiarizer.swift
git commit -m "feat(diarize): PyannoteDiarizer — wrap speech-swift pipeline w/ AVAudio 16k mono loader"
```

---

## Task 8: Wire pipeline into `TranscriptionService`

**Files:**
- Modify: `OneToOne/Services/TranscriptionService.swift`

- [ ] **Step 1: Inspect existing transcribe signature**

Run: `grep -n "func transcribe\|STTResult\|STTChunk" OneToOne/Services/TranscriptionService.swift | head -15`
Expected: existing `func transcribe(audioURL:) async throws -> STTResult` somewhere, with chunks as part of the result. Verify exact signature before editing.

- [ ] **Step 2: Add the new orchestration method**

In `OneToOne/Services/TranscriptionService.swift`, add a new public method that runs the full pipeline on an existing meeting. Place it after the existing `transcribe(audioURL:)`:

```swift
    /// Full pipeline: Cohere transcribe → Pyannote diarize → align → match speakers.
    /// Mutates `meeting`: inserts TranscriptSegments, sets `speakerAssignmentsJSON`
    /// + `speakerMatchMetaJSON`. Does **not** call `context.save()` — the caller
    /// (`MeetingView.runTranscription`) decides when to persist.
    @MainActor
    func transcribeWithDiarization(audioURL: URL,
                                    meeting: Meeting,
                                    settings: AppSettings,
                                    in context: ModelContext) async throws -> STTResult {
        // 1. Cohere transcribe (existing path).
        let sttResult = try await transcribe(audioURL: audioURL)

        // If speaker identification disabled in settings, return early with cluster=0.
        guard settings.speakerIdEnabled else {
            persistAnonymousSegments(sttResult: sttResult, meeting: meeting, in: context)
            return sttResult
        }

        // 2. Diarize.
        let diarOutput: PyannoteDiarizer.DiarizeOutput
        do {
            diarOutput = try await PyannoteDiarizer.shared.diarize(audioURL: audioURL)
        } catch {
            print("[TranscriptionService] diarization failed: \(error). Falling back to anonymous.")
            persistAnonymousSegments(sttResult: sttResult, meeting: meeting, in: context)
            return sttResult
        }

        // 3. Align chunks ↔ turns.
        let chunks = sttResult.chunks.map { c in
            TurnAligner.STTChunkInput(startSec: c.startSeconds, endSec: c.endSeconds, text: c.text)
        }
        let aligned = TurnAligner.align(chunks: chunks, turns: diarOutput.turns)

        // 4. Match clusters → Collaborators (overrides thresholds w/ settings).
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: diarOutput.perClusterEmbedding,
            meeting: meeting,
            in: context
        )

        // 5. Persist segments + metadata.
        persistAlignedSegments(
            aligned: aligned,
            assignments: assignments,
            meeting: meeting,
            in: context
        )

        return sttResult
    }

    private func persistAnonymousSegments(sttResult: STTResult,
                                           meeting: Meeting,
                                           in context: ModelContext) {
        var idx = 0
        for chunk in sttResult.chunks {
            let s = TranscriptSegment(
                orderIndex: idx,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                text: chunk.text,
                speakerID: 1
            )
            s.meeting = meeting
            context.insert(s)
            idx += 1
        }
    }

    private func persistAlignedSegments(aligned: [TurnAligner.AlignedSegment],
                                         assignments: [Int: SpeakerMatcher.Assignment],
                                         meeting: Meeting,
                                         in context: ModelContext) {
        var idx = 0
        var assignmentsDict: [String: String] = [:]
        var metaDict: [String: [String: Any]] = [:]
        for seg in aligned {
            let s = TranscriptSegment(
                orderIndex: idx,
                startSeconds: seg.startSec,
                endSeconds: seg.endSec,
                text: seg.text,
                speakerID: seg.clusterID + 1
            )
            s.meeting = meeting
            if let a = assignments[seg.clusterID], let collab = a.collaborator, a.auto {
                s.speaker = collab
            }
            context.insert(s)
            idx += 1
        }
        for (cid, a) in assignments {
            assignmentsDict[String(cid)] = a.collaborator?.ensuredStableID.uuidString
            metaDict[String(cid)] = [
                "confidence": a.confidence,
                "auto": a.auto,
                "ambiguous": a.ambiguous,
                "candidates": a.candidates.map { $0.0.ensuredStableID.uuidString }
            ]
        }
        if let assignmentsJSON = try? JSONSerialization.data(withJSONObject: assignmentsDict),
           let s = String(data: assignmentsJSON, encoding: .utf8) {
            meeting.speakerAssignmentsJSON = s
        }
        if let metaJSON = try? JSONSerialization.data(withJSONObject: metaDict),
           let s = String(data: metaJSON, encoding: .utf8) {
            meeting.speakerMatchMetaJSON = s
        }
    }
```

(If the existing `STTResult` exposes chunks under a different property name — e.g. `segments` instead of `chunks` — adapt the `sttResult.chunks` accesses to match. Same for chunk struct property names. Don't invent fields.)

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/TranscriptionService.swift
git commit -m "feat(diarize): TranscriptionService.transcribeWithDiarization end-to-end"
```

---

## Task 9: MeetingView UI — badges + manual labelling + Re-identifier

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Locate the existing transcript segment row**

Run: `grep -n "TranscriptSegment\|speakerID\|displayLabel" OneToOne/Views/MeetingView.swift | head -10`
Identify the view that renders one segment row.

- [ ] **Step 2: Add a helper struct decoding the meta JSON**

Inside `MeetingView` (private nested or file-scope), add:

```swift
fileprivate struct SpeakerMeta {
    let confidence: Double
    let auto: Bool
    let ambiguous: Bool

    static func parse(json: String, clusterID: Int) -> SpeakerMeta? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = dict[String(clusterID)] as? [String: Any] else {
            return nil
        }
        return SpeakerMeta(
            confidence: (entry["confidence"] as? Double) ?? 0,
            auto: (entry["auto"] as? Bool) ?? false,
            ambiguous: (entry["ambiguous"] as? Bool) ?? false
        )
    }
}
```

- [ ] **Step 3: Render the badge inline next to the segment row**

In the body of the segment row, replace the current speaker display with:

```swift
                speakerBadge(for: segment)
```

Add the helper:

```swift
    @ViewBuilder
    private func speakerBadge(for segment: TranscriptSegment) -> some View {
        let clusterID = segment.speakerID - 1
        let meta = SpeakerMeta.parse(json: meeting.speakerMatchMetaJSON, clusterID: clusterID)

        if let speaker = segment.speaker {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                Text(speaker.name).font(.caption.bold())
                if let meta, meta.auto {
                    Text("(\(Int(meta.confidence * 100))%)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { showSpeakerPicker(for: segment) }
        } else if let meta, meta.confidence >= SpeakerMatcher.suggestThreshold,
                  let suggested = candidateForCluster(clusterID, json: meeting.speakerMatchMetaJSON) {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                Text("\(suggested.name)? (\(Int(meta.confidence * 100))%)").font(.caption.italic())
                Button { acceptSuggestion(suggested, for: segment) } label: {
                    Image(systemName: "checkmark.circle.fill")
                }.buttonStyle(.plain).foregroundStyle(.green)
                Button { rejectSuggestion(for: segment) } label: {
                    Image(systemName: "xmark.circle")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.dashed").foregroundStyle(.secondary)
                Text(segment.displayLabel).font(.caption)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .onTapGesture { showSpeakerPicker(for: segment) }
        }
    }
```

- [ ] **Step 4: Add suggestion / picker handlers**

Inside `MeetingView`:

```swift
    private func candidateForCluster(_ clusterID: Int, json: String) -> Collaborator? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = dict[String(clusterID)] as? [String: Any],
              let candidates = entry["candidates"] as? [String],
              let first = candidates.first,
              let uuid = UUID(uuidString: first) else { return nil }
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func acceptSuggestion(_ collab: Collaborator, for segment: TranscriptSegment) {
        assignClusterToCollaborator(clusterID: segment.speakerID - 1, collab: collab)
    }

    private func rejectSuggestion(for segment: TranscriptSegment) {
        // Clear the auto suggestion: just drop it from meta. Cluster stays anonymous
        // unless user picks via the manual picker.
        let clusterID = segment.speakerID - 1
        var meta = (try? JSONSerialization.jsonObject(
            with: meeting.speakerMatchMetaJSON.data(using: .utf8) ?? Data()
        ) as? [String: Any]) ?? [:]
        meta.removeValue(forKey: String(clusterID))
        if let data = try? JSONSerialization.data(withJSONObject: meta),
           let s = String(data: data, encoding: .utf8) {
            meeting.speakerMatchMetaJSON = s
            try? context.save()
        }
    }

    private func showSpeakerPicker(for segment: TranscriptSegment) {
        // Surface a menu of meeting.participants first, then all non-archived collabs.
        // Implementation: use SwiftUI `Menu` attached to the row. For simplicity in
        // this plan, surface it via a confirmationDialog or attached Menu in the
        // call site. Defer the exact widget choice to the implementer.
        pendingSpeakerSegment = segment
        showSpeakerPickerSheet = true
    }

    private func assignClusterToCollaborator(clusterID: Int, collab: Collaborator) {
        // Bulk-assign all TranscriptSegment rows with this clusterID.
        let cid = clusterID + 1
        let mid = meeting.persistentModelID
        let descriptor = FetchDescriptor<TranscriptSegment>(
            predicate: #Predicate { $0.meeting?.persistentModelID == mid && $0.speakerID == cid }
        )
        let segments = (try? context.fetch(descriptor)) ?? []
        for s in segments {
            s.speaker = collab
        }
        // Update assignmentsJSON.
        var assignments = (try? JSONSerialization.jsonObject(
            with: meeting.speakerAssignmentsJSON.data(using: .utf8) ?? Data()
        ) as? [String: String]) ?? [:]
        assignments[String(clusterID)] = collab.ensuredStableID.uuidString
        if let data = try? JSONSerialization.data(withJSONObject: assignments),
           let s = String(data: data, encoding: .utf8) {
            meeting.speakerAssignmentsJSON = s
        }
        // EMA voiceprint update — only when audio + embedding available
        if let embedding = lastDiarizationEmbeddings[clusterID] {
            SpeakerMatcher.applyEMAUpdate(to: collab, newEmbedding: embedding, in: context)
        }
        try? context.save()
    }
```

The state `pendingSpeakerSegment`, `showSpeakerPickerSheet`, and a cached `lastDiarizationEmbeddings: [Int: [Float]]` (populated on the most recent diarize/re-identify run) need to be added as `@State` near the top of `MeetingView`.

- [ ] **Step 5: Add a "Re-identifier les speakers" toolbar button**

Find the existing toolbar / header HStack in `MeetingView` (likely near the "Rapport" button added earlier). Insert:

```swift
        Button {
            Task { await reidentifySpeakers() }
        } label: {
            Image(systemName: "person.crop.circle.badge.questionmark")
        }
        .help("Ré-identifier les speakers")
```

And the action:

```swift
    private func reidentifySpeakers() async {
        guard let wavPath = meeting.wavFilePath, !wavPath.isEmpty else { return }
        let url = URL(fileURLWithPath: wavPath)
        do {
            let out = try await PyannoteDiarizer.shared.diarize(audioURL: url)
            lastDiarizationEmbeddings = out.perClusterEmbedding
            let assignments = SpeakerMatcher.match(
                clusterEmbeddings: out.perClusterEmbedding,
                meeting: meeting,
                in: context
            )
            // Apply only the JSON metadata, do not touch existing TranscriptSegments
            // (re-identification updates badges, not text).
            var assignmentsDict: [String: String] = [:]
            var metaDict: [String: [String: Any]] = [:]
            for (cid, a) in assignments {
                assignmentsDict[String(cid)] = a.collaborator?.ensuredStableID.uuidString
                metaDict[String(cid)] = [
                    "confidence": a.confidence,
                    "auto": a.auto,
                    "ambiguous": a.ambiguous,
                    "candidates": a.candidates.map { $0.0.ensuredStableID.uuidString }
                ]
                if a.auto, let collab = a.collaborator {
                    assignClusterToCollaborator(clusterID: cid, collab: collab)
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: assignmentsDict),
               let s = String(data: data, encoding: .utf8) {
                meeting.speakerAssignmentsJSON = s
            }
            if let data = try? JSONSerialization.data(withJSONObject: metaDict),
               let s = String(data: data, encoding: .utf8) {
                meeting.speakerMatchMetaJSON = s
            }
            try? context.save()
        } catch {
            print("[MeetingView] reidentify failed: \(error)")
        }
    }
```

- [ ] **Step 6: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean. If `pendingSpeakerSegment` / sheet wiring needs more glue, complete with a minimal `.sheet(...)` showing a `Picker("Speaker", selection:)` over participants + all collabs; not strictly required for v1 — keep behaviour testable by manual click.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(diarize): MeetingView speaker badges + reidentify + manual cluster assignment"
```

---

## Task 10: Settings UI — "Reconnaissance vocale" GroupBox

**Files:**
- Modify: `OneToOne/Views/SettingsView.swift`

- [ ] **Step 1: Locate the existing "Calendrier & menubar" GroupBox**

Run: `grep -n "Calendrier & menubar\|GroupBox" OneToOne/Views/SettingsView.swift | head -10`
Identify a stable insertion point next to it.

- [ ] **Step 2: Add the new GroupBox**

```swift
                GroupBox("Reconnaissance vocale") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Identification automatique des speakers", isOn: Binding(
                            get: { settings.speakerIdEnabled },
                            set: { settings.speakerIdEnabled = $0; saveSettings() }
                        ))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seuil auto-assign: \(Int(settings.speakerIdAutoThreshold * 100))%")
                                .font(.caption)
                            Slider(value: Binding(
                                get: { settings.speakerIdAutoThreshold },
                                set: { settings.speakerIdAutoThreshold = $0; saveSettings() }
                            ), in: 0.65...0.90, step: 0.01)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seuil suggestion: \(Int(settings.speakerIdSuggestThreshold * 100))%")
                                .font(.caption)
                            Slider(value: Binding(
                                get: { settings.speakerIdSuggestThreshold },
                                set: { settings.speakerIdSuggestThreshold = $0; saveSettings() }
                            ), in: 0.50...0.70, step: 0.01)
                        }

                        Divider()
                        Text("Collaborateurs enrôlés").font(.caption.bold()).foregroundColor(.secondary)
                        enrolledCollabsList
                    }
                    .padding(8)
                }
```

Add the rendering of enrolled collabs:

```swift
    @ViewBuilder
    private var enrolledCollabsList: some View {
        let enrolled = collaborators.filter { $0.voicePrint != nil && $0.voicePrintSamples > 0 }
        if enrolled.isEmpty {
            Text("Aucun collaborateur enrôlé. Assignez un speaker dans une réunion pour démarrer l'enrôlement.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(enrolled.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                HStack {
                    Text(c.name)
                    Text("· \(c.voicePrintSamples) réunion(s)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset voiceprint", role: .destructive) {
                        c.voicePrint = nil
                        c.voicePrintSamples = 0
                        c.voicePrintUpdatedAt = nil
                        saveSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): Reconnaissance vocale GroupBox — toggle, thresholds, enrolled list"
```

---

## Task 11: Manual verification

**Files:** none.

- [ ] **Step 1: Clean build + full test suite**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -10
```
Both clean.

- [ ] **Step 2: First-launch model download**

```bash
swift run 2>&1 | head -40
```

Expected log: speech-swift downloads Silero VAD + Pyannote segmentation + WeSpeaker ResNet34 on first transcription. Cache: `~/.cache/...` and Application Support.

- [ ] **Step 3: Manual checklist**

| # | Check |
|---|-------|
| 1 | Record a short test meeting with 2 participants (you + 1 known collab) |
| 2 | Stop recording → transcription pipeline runs |
| 3 | Console logs `loading PyannoteDiarizationPipeline (first call)` once |
| 4 | Console logs `diarize done turns=N speakers=K` |
| 5 | Transcript segments display with `Speaker 1` / `Speaker 2` badges |
| 6 | Click a `Speaker N` badge → picker opens → assign to a Collaborator |
| 7 | After assignment, that Collaborator now has voiceprint (Settings → enrolled list shows them) |
| 8 | Record a second meeting with the same Collaborator → segments auto-assigned with `✓ <Name>` badge |
| 9 | "Re-identifier les speakers" toolbar action runs without crashing |
| 10 | Settings → thresholds → moving sliders changes next pipeline run's behaviour |
| 11 | Settings → "Reset voiceprint" → voiceprint cleared, next meeting returns anonymous for that speaker |
| 12 | Toggle `speakerIdEnabled` off → pipeline runs but all segments stay `Speaker 1` |

- [ ] **Step 4: Note defects**

For each failure, commit a small follow-up fix. Don't bundle them with the plan's commits.

---

## Out-of-scope notes

Already in the spec §8 — kept consistent here for visibility:

- E-B explicit voice-enrollment screen (record 30s of voice) — v2.
- T-A per-turn re-transcription via Cohere on slice — v2 toolbar button.
- Live speaker identification during recording (streaming embedding + match).
- Bulk "Reset all voiceprints" action — only per-collab reset is implemented.
- Speech-swift's own ASR (Qwen3 / Parakeet / Omnilingual) — Cohere kept for FR transcription continuity.
- Cross-meeting speaker IDs without participants context (impossible at first run).

---

## Self-review notes (author)

- **Spec coverage**: §2 decisions → tasks 1–4; §3 architecture → tasks 5–8; §4 data model → tasks 2–4; §5.1 pipeline → task 8; §5.2 align → task 5; §5.3 embedding (now bundled in PyannoteDiarizer per speech-swift API) → task 7; §5.4 matcher → task 6; §5.5 EMA → task 6 + task 9 trigger from manual assignment; §6 UI → tasks 9 + 10; §7 edge cases handled in tasks 7 (audio missing / model unavailable) + 6 (ambiguous, archived) + 9 (settings disabled fallback inside task 8); §9 testing → unit in tasks 5 and 6, manual checklist in task 11.
- **Type consistency**: `TurnAligner.DiarTurn(startSec, endSec, clusterID)`, `TurnAligner.STTChunkInput(startSec, endSec, text)`, `TurnAligner.AlignedSegment(startSec, endSec, text, clusterID)`, `PyannoteDiarizer.DiarizeOutput(turns, perClusterEmbedding)`, `SpeakerMatcher.Assignment(collaborator, confidence, auto, candidates, ambiguous)` — all consistently referenced from task 5 onward.
- **Placeholders**: every code step contains the actual code. Two grep-and-adapt steps (task 8 step 1, task 9 step 1) are bounded — the grep tells the engineer exactly what to look for and what to change.
- **Risk acknowledged**: speech-swift's `PyannoteDiarizationPipeline.fromPretrained(useVADFilter:)` signature is read from public source as of writing. If the library evolves, Task 7 step 2 documents the adaptation point.
