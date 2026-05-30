# Diarize-first Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer l'alignement texte↔locuteur par recouvrement par un pipeline diarize-first (Pyannote → tour → STT par tour), avec moteur STT pluggable (Cohere/Voxtral) et deux modes configurables, tout en gardant l'exécution dans `JobQueue`.

**Architecture:** Un protocole `STTEngine` abstrait les deux modèles MLX (déjà conformes `STTGenerationModel`). `TranscriptionService.runTranscription` branche sur `AppSettings.transcriptionMode` : transcription-seule (chunks 60s, moteur au choix) ou diarize-first (Voxtral par tour). Un helper pur `TurnMerger` fusionne les tours adjacents. L'ancien `TurnAligner` (overlap) est supprimé.

**Tech Stack:** Swift, SwiftData, MLX (mlx-audio-swift : `CohereTranscribeModel`, `VoxtralRealtimeModel`), speech-swift (`PyannoteDiarizationPipeline`), XCTest, SwiftPM.

---

## Référence — API existantes vérifiées

- `loadAudioArray(from:sampleRate:) throws -> (Int, MLXArray)` — MLXAudioCore, déjà utilisé.
- `STTGenerationModel.generate(audio: MLXArray, generationParameters: STTGenerateParameters) -> STTOutput` ; `STTOutput.text: String`.
- `CohereTranscribeModel.fromDirectory(_ URL) throws -> Self` (config.json + model.safetensors).
- `VoxtralRealtimeModel.fromDirectory(_ URL) throws -> Self` (config.json + *.safetensors shardés).
- `STTGenerateParameters(maxTokens:temperature:topP:topK:verbose:language:chunkDuration:minChunkDuration:)`.
- `PyannoteDiarizer.shared.diarize(audioURL:clusterThreshold:onPhase:onProgress:) -> DiarizeOutput{turns:[TurnAligner.DiarTurn], perClusterEmbedding:[Int:[Float]]}`.
- `SpeakerMatcher.match(clusterEmbeddings:meeting:in:settings:) -> [Int: Assignment]` ; `Assignment.collaborator`, `.auto`, `.confidence`, `.ambiguous`, `.candidates`.
- `TranscriptionPhase` (MeetingView.swift:28) : `.idle .loadingModel .transcribing .diarizing .matching .reidentifying .error`.
- Call sites de `transcribeWithDiarization` : MeetingView.swift:439, MeetingView.swift:1267, MaintenanceView.swift:194 — tous dans `JobQueue.start(kind:.transcription)`.

## File Structure

- **Create** `OneToOne/Services/STT/STTEngine.swift` — protocole + résolution dossier modèle partagée.
- **Create** `OneToOne/Services/STT/CohereEngine.swift` — wrapper `CohereTranscribeModel`.
- **Create** `OneToOne/Services/STT/VoxtralEngine.swift` — wrapper `VoxtralRealtimeModel`.
- **Create** `OneToOne/Services/STT/TurnMerger.swift` — `DiarTurn`, `Block`, `mergeAdjacent`, `mergeConsecutiveBlocks` (pur).
- **Create** `OneToOne/Services/STT/DiarizeFirstTranscriber.swift` — orchestration diarize-first.
- **Modify** `OneToOne/Models/AppSettings.swift` — enums + champs + migration.
- **Modify** `OneToOne/Services/TranscriptionService.swift` — `runTranscription` branche sur mode ; moteur pluggable ; persist `[Block]` ; canonicalize `[Block]`.
- **Modify** `OneToOne/Services/PyannoteDiarizer.swift` — `TurnAligner.DiarTurn` → `TurnMerger.DiarTurn`.
- **Delete** `OneToOne/Services/TurnAligner.swift` — overlap-align supprimé.
- **Modify** `OneToOne/Views/MeetingView.swift`, `MaintenanceView.swift` — call sites `transcribeWithDiarization` → `runTranscription`.
- **Modify** `OneToOne/Views/SettingsView.swift` — pickers mode/moteur/variante.
- **Create** `Tests/TurnMergerTests.swift`. **Modify/Delete** `Tests/TurnAlignerTests.swift`, `Tests/CanonicalizeClustersTests.swift`.

`DiarizationService` (VAD énergie) est **conservé** — utilisé par `MeetingView.runDiarization()`.

---

## Task 1: Protocole STTEngine + résolution de dossier partagée

**Files:**
- Create: `OneToOne/Services/STT/STTEngine.swift`

- [ ] **Step 1: Créer le protocole + helper de résolution**

```swift
import Foundation

#if canImport(MLX)
import MLX
#endif

/// Moteur STT pluggable. Les deux impls (Cohere, Voxtral) wrappent un modèle
/// MLX conforme `STTGenerationModel`. `transcribe` prend un clip 16 kHz mono
/// déjà découpé et renvoie le texte trimmé.
@MainActor
protocol STTEngine: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    #if canImport(MLX)
    /// async : l'implémentation offload le calcul MLX (lourd) hors du main actor.
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String
    #endif
}

/// Résolution commune du dossier modèle : cache HuggingFace partagé, puis
/// dossier managé par OneToOne, puis chemin manuel (UserDefaults). `contains`
/// valide la présence des fichiers requis.
enum STTModelResolver {
    /// `repoId` ex. "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit".
    /// `manualKey` : clé UserDefaults d'un chemin choisi à la main (peut être nil).
    static func resolveExistingDirectory(repoId: String,
                                         manualKey: String?,
                                         contains: (URL) -> Bool) -> URL? {
        for url in candidateDirectories(repoId: repoId, manualKey: manualKey)
        where contains(url) { return url }
        return nil
    }

    static func candidateDirectories(repoId: String, manualKey: String?) -> [URL] {
        var out: [URL] = []
        if let snap = firstSnapshot(repoId: repoId) { out.append(snap) }
        out.append(managedDirectory(repoId: repoId))
        if let manualKey, let manual = UserDefaults.standard.string(forKey: manualKey) {
            out.append(URL(fileURLWithPath: manual))
        }
        return out
    }

    static func managedDirectory(repoId: String) -> URL {
        let base = URL.applicationSupportDirectory
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private static func firstSnapshot(repoId: String) -> URL? {
        let safeRepo = "models--" + repoId.replacingOccurrences(of: "/", with: "--")
        let snapshotsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            .appendingPathComponent(safeRepo, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: nil) else { return nil }
        return entries.first
    }

    /// Vrai s'il existe config.json + au moins un .safetensors dans le dossier.
    static func containsSafetensors(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return false }
        return files.contains { $0.pathExtension == "safetensors" }
    }
}
```

- [ ] **Step 2: Compiler**

Run: `swift build 2>&1 | tail -20`
Expected: build OK (warnings éventuels sur `firstSnapshot` qui ne filtre pas — acceptable, `contains` filtre ensuite).

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/STT/STTEngine.swift
git commit -m "feat(stt): STTEngine protocol + shared model resolver"
```

---

## Task 2: CohereEngine

**Files:**
- Create: `OneToOne/Services/STT/CohereEngine.swift`

- [ ] **Step 1: Implémenter le wrapper Cohere**

```swift
import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Moteur STT Cohere Transcribe (MLX local). Reprend la résolution de dossier
/// historique (cache HF + managed + chemin manuel UserDefaults).
@MainActor
final class CohereEngine: STTEngine {
    static let repoId = "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"
    static let manualPathKey = "onetoone_cohere_manual_model_path"

    #if canImport(MLXAudioSTT)
    private var model: CohereTranscribeModel?
    #endif

    var isLoaded: Bool {
        #if canImport(MLXAudioSTT)
        return model != nil
        #else
        return false
        #endif
    }

    func load() async throws {
        #if canImport(MLXAudioSTT)
        guard model == nil else { return }
        guard let dir = STTModelResolver.resolveExistingDirectory(
            repoId: Self.repoId, manualKey: Self.manualPathKey,
            contains: { STTModelResolver.containsSafetensors($0) }) else {
            throw STTError.modelMissing(searched: STTModelResolver.candidateDirectories(
                repoId: Self.repoId, manualKey: Self.manualPathKey))
        }
        do {
            model = try CohereTranscribeModel.fromDirectory(dir)
        } catch {
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    #if canImport(MLX)
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String {
        #if canImport(MLXAudioSTT)
        guard let model else { return "" }
        let params = STTGenerateParameters(
            maxTokens: maxTokens, temperature: 0.0, topP: 1.0, topK: 0,
            verbose: false, language: language,
            chunkDuration: 1200.0, minChunkDuration: 1.0)
        // Offload MLX compute off the main actor (lourd). Box @unchecked car
        // CohereTranscribeModel/MLXArray ne sont pas Sendable — pattern repris
        // de PyannoteDiarizer.
        struct Box: @unchecked Sendable {
            let model: CohereTranscribeModel; let clip: MLXArray; let params: STTGenerateParameters
        }
        let box = Box(model: model, clip: clip, params: params)
        return await Task.detached(priority: .userInitiated) {
            box.model.generate(audio: box.clip, generationParameters: box.params)
                .text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        #else
        return ""
        #endif
    }
    #endif
}
```

- [ ] **Step 2: Compiler**

Run: `swift build 2>&1 | tail -20`
Expected: build OK.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/STT/CohereEngine.swift
git commit -m "feat(stt): CohereEngine wrapper"
```

---

## Task 3: VoxtralEngine

**Files:**
- Create: `OneToOne/Services/STT/VoxtralEngine.swift`

- [ ] **Step 1: Implémenter le wrapper Voxtral (variante paramétrable)**

```swift
import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Variante de poids Voxtral. Le repo HF résolu en dépend.
enum VoxtralVariant: String, Codable, CaseIterable, Sendable {
    case realtime4bit
    case realtimeFP16

    var repoId: String {
        switch self {
        case .realtime4bit: return "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
        case .realtimeFP16: return "mlx-community/Voxtral-Mini-4B-Realtime-2602"
        }
    }

    var label: String {
        switch self {
        case .realtime4bit: return "Realtime 4-bit (léger)"
        case .realtimeFP16: return "Realtime fp16 (précis)"
        }
    }
}

/// Moteur STT Voxtral (MLX local). Variante sélectionnée à l'init.
@MainActor
final class VoxtralEngine: STTEngine {
    static let manualPathKey = "onetoone_voxtral_manual_model_path"

    let variant: VoxtralVariant

    #if canImport(MLXAudioSTT)
    private var model: VoxtralRealtimeModel?
    #endif

    init(variant: VoxtralVariant) { self.variant = variant }

    var isLoaded: Bool {
        #if canImport(MLXAudioSTT)
        return model != nil
        #else
        return false
        #endif
    }

    func load() async throws {
        #if canImport(MLXAudioSTT)
        guard model == nil else { return }
        let repoId = variant.repoId
        guard let dir = STTModelResolver.resolveExistingDirectory(
            repoId: repoId, manualKey: Self.manualPathKey,
            contains: { STTModelResolver.containsSafetensors($0) }) else {
            throw STTError.modelMissing(searched: STTModelResolver.candidateDirectories(
                repoId: repoId, manualKey: Self.manualPathKey))
        }
        do {
            model = try VoxtralRealtimeModel.fromDirectory(dir)
        } catch {
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    #if canImport(MLX)
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String {
        #if canImport(MLXAudioSTT)
        guard let model else { return "" }
        let params = STTGenerateParameters(
            maxTokens: maxTokens, temperature: 0.0, topP: 1.0, topK: 0,
            verbose: false, language: language,
            chunkDuration: 1200.0, minChunkDuration: 1.0)
        // Offload MLX compute off the main actor — cf. CohereEngine.
        struct Box: @unchecked Sendable {
            let model: VoxtralRealtimeModel; let clip: MLXArray; let params: STTGenerateParameters
        }
        let box = Box(model: model, clip: clip, params: params)
        return await Task.detached(priority: .userInitiated) {
            box.model.generate(audio: box.clip, generationParameters: box.params)
                .text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        #else
        return ""
        #endif
    }
    #endif
}
```

- [ ] **Step 2: Compiler**

Run: `swift build 2>&1 | tail -20`
Expected: build OK.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/STT/VoxtralEngine.swift
git commit -m "feat(stt): VoxtralEngine wrapper + variant enum"
```

---

## Task 4: AppSettings — modes + migration

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift:169-180`

- [ ] **Step 1: Ajouter les enums (en haut du fichier, après les imports)**

```swift
/// Mode de transcription. Remplace l'ancien booléen `speakerIdEnabled`.
enum TranscriptionMode: String, Codable, CaseIterable, Sendable {
    case transcriptionOnly
    case diarizeFirst
}

/// Moteur STT pour le mode transcription seule.
enum STTEngineKind: String, Codable, CaseIterable, Sendable {
    case cohere
    case voxtral
}
```

- [ ] **Step 2: Remplacer le champ `speakerIdEnabled` par les nouveaux champs**

Dans la région `// MARK: - Speaker identification`, remplacer la ligne
`var speakerIdEnabled: Bool = false` par :

```swift
    /// Mode de transcription. `diarizeFirst` = diarisation Pyannote puis Voxtral
    /// par tour ; `transcriptionOnly` = texte brut sans locuteurs.
    var transcriptionModeRaw: String = TranscriptionMode.transcriptionOnly.rawValue
    /// Moteur du mode transcription seule.
    var transcriptionEngineRaw: String = STTEngineKind.cohere.rawValue
    /// Variante de poids Voxtral (utilisée dès que Voxtral est actif).
    var voxtralVariantRaw: String = VoxtralVariant.realtime4bit.rawValue
```

- [ ] **Step 3: Ajouter des accessoires typés (juste après les champs)**

```swift
    var transcriptionMode: TranscriptionMode {
        get { TranscriptionMode(rawValue: transcriptionModeRaw) ?? .transcriptionOnly }
        set { transcriptionModeRaw = newValue.rawValue }
    }
    var transcriptionEngine: STTEngineKind {
        get { STTEngineKind(rawValue: transcriptionEngineRaw) ?? .cohere }
        set { transcriptionEngineRaw = newValue.rawValue }
    }
    var voxtralVariant: VoxtralVariant {
        get { VoxtralVariant(rawValue: voxtralVariantRaw) ?? .realtime4bit }
        set { voxtralVariantRaw = newValue.rawValue }
    }
    /// Diarisation active ssi mode diarize-first (remplace `speakerIdEnabled`).
    var speakerIdEnabled: Bool { transcriptionMode == .diarizeFirst }
```

> Note migration : on **ajoute** des champs `String` avec valeurs par défaut →
> SwiftData lightweight migration sans perte. L'ancien `speakerIdEnabled`
> persisté est ignoré (les anciens users repartent en `transcriptionOnly` ;
> acceptable, ils réactiveront la diarisation dans les réglages). `speakerIdEnabled`
> devient un computed read-only — tous les call sites lecteurs continuent de marcher.

- [ ] **Step 4: Compiler**

Run: `swift build 2>&1 | tail -30`
Expected: build OK. Si erreur « cannot assign to property: 'speakerIdEnabled' is a get-only property », chercher les écritures :

Run: `grep -rn "speakerIdEnabled =" OneToOne`
Si une écriture existe, la remplacer par `settings.transcriptionMode = .diarizeFirst/.transcriptionOnly`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Models/AppSettings.swift
git commit -m "feat(settings): transcriptionMode/engine/voxtralVariant, migrate speakerIdEnabled"
```

---

## Task 5: TurnMerger (helper pur) — TDD

**Files:**
- Create: `OneToOne/Services/STT/TurnMerger.swift`
- Create: `Tests/TurnMergerTests.swift`

- [ ] **Step 1: Écrire les tests d'abord**

```swift
import XCTest
@testable import OneToOne

final class TurnMergerTests: XCTestCase {
    private func turn(_ s: Double, _ e: Double, _ c: Int) -> TurnMerger.DiarTurn {
        TurnMerger.DiarTurn(startSec: s, endSec: e, clusterID: c)
    }

    func testEmpty() {
        XCTAssertTrue(TurnMerger.mergeAdjacent([], maxGap: 0.5).isEmpty)
    }

    func testSingle() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
    }

    func testMergesSameSpeakerWithinGap() {
        // gap = 0.3 <= 0.5 → fusion
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.3, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].endSec, 2, accuracy: 0.0001)
    }

    func testGapExactlyMaxMerges() {
        // gap == maxGap → inclusif → fusion
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.5, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
    }

    func testGapAboveMaxSeparates() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.6, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 2)
    }

    func testDifferentSpeakersSeparate() {
        let r = TurnMerger.mergeAdjacent([turn(0, 1, 0), turn(1.1, 2, 1)], maxGap: 0.5)
        XCTAssertEqual(r.count, 2)
    }

    func testContainedTurnKeepsMaxEnd() {
        // 2e tour contenu dans le 1er → end = max
        let r = TurnMerger.mergeAdjacent([turn(0, 5, 0), turn(1, 2, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].endSec, 5, accuracy: 0.0001)
    }

    func testUnsortedInputSortedFirst() {
        let r = TurnMerger.mergeAdjacent([turn(1.3, 2, 0), turn(0, 1, 0)], maxGap: 0.5)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].startSec, 0, accuracy: 0.0001)
        XCTAssertEqual(r[0].endSec, 2, accuracy: 0.0001)
    }

    func testMergeConsecutiveBlocksConcatsText() {
        let blocks = [
            TurnMerger.Block(speaker: 0, start: 0, end: 1, text: "bonjour"),
            TurnMerger.Block(speaker: 0, start: 1, end: 2, text: "ça va"),
            TurnMerger.Block(speaker: 1, start: 2, end: 3, text: "oui"),
        ]
        let r = TurnMerger.mergeConsecutiveBlocks(blocks)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].text, "bonjour ça va")
        XCTAssertEqual(r[0].end, 2, accuracy: 0.0001)
        XCTAssertEqual(r[1].speaker, 1)
    }
}
```

- [ ] **Step 2: Lancer les tests → échec attendu (type inconnu)**

Run: `swift test --filter TurnMergerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'TurnMerger' in scope`.

- [ ] **Step 3: Implémenter `TurnMerger`**

```swift
import Foundation

/// Helpers purs du pipeline diarize-first. Aucune dépendance audio/modèle.
enum TurnMerger {
    /// Tour de parole issu de la diarisation. `clusterID` 0-indexé.
    struct DiarTurn: Sendable, Equatable {
        var startSec: Double
        var endSec: Double
        var clusterID: Int
    }

    /// Un tour transcrit (sortie finale d'un appel STT).
    struct Block: Sendable, Equatable {
        var speaker: Int      // clusterID 0-indexé
        var start: Double
        var end: Double
        var text: String
    }

    /// Fusionne les tours consécutifs du même locuteur séparés de ≤ maxGap.
    /// Trie défensivement par start. `maxGap` inclusif. Gère les tours
    /// contenus/chevauchants via `max(end)`.
    static func mergeAdjacent(_ turns: [DiarTurn], maxGap: Double) -> [DiarTurn] {
        guard !turns.isEmpty else { return [] }
        let sorted = turns.sorted { $0.startSec < $1.startSec }
        var merged: [DiarTurn] = [sorted[0]]
        for t in sorted.dropFirst() {
            let lastIdx = merged.count - 1
            let last = merged[lastIdx]
            if t.clusterID == last.clusterID && (t.startSec - last.endSec) <= maxGap {
                merged[lastIdx].endSec = max(last.endSec, t.endSec)
            } else {
                merged.append(t)
            }
        }
        return merged
    }

    /// Re-fusionne les blocs adjacents du même locuteur (post-canonicalisation).
    static func mergeConsecutiveBlocks(_ blocks: [Block]) -> [Block] {
        var merged: [Block] = []
        for b in blocks {
            if var last = merged.last, last.speaker == b.speaker {
                merged.removeLast()
                last.end = b.end
                last.text = (last.text + " " + b.text).trimmingCharacters(in: .whitespaces)
                merged.append(last)
            } else {
                merged.append(b)
            }
        }
        return merged
    }
}
```

- [ ] **Step 4: Lancer les tests → succès**

Run: `swift test --filter TurnMergerTests 2>&1 | tail -20`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/STT/TurnMerger.swift Tests/TurnMergerTests.swift
git commit -m "feat(stt): TurnMerger pure helper (mergeAdjacent + mergeConsecutiveBlocks) + tests"
```

---

## Task 6: PyannoteDiarizer — basculer sur TurnMerger.DiarTurn

**Files:**
- Modify: `OneToOne/Services/PyannoteDiarizer.swift:42,114-120`

- [ ] **Step 1: Remplacer le type des turns**

Dans `struct DiarizeOutput`, remplacer :
```swift
        let turns: [TurnAligner.DiarTurn]
```
par :
```swift
        let turns: [TurnMerger.DiarTurn]
```

Et dans le `result.segments.map`, remplacer :
```swift
                    TurnAligner.DiarTurn(
                        startSec: Double(seg.startTime),
                        endSec: Double(seg.endTime),
                        clusterID: seg.speakerId
                    )
```
par :
```swift
                    TurnMerger.DiarTurn(
                        startSec: Double(seg.startTime),
                        endSec: Double(seg.endTime),
                        clusterID: seg.speakerId
                    )
```

- [ ] **Step 2: Compiler** (échouera tant que TurnAligner référence DiarTurn — normal, corrigé Task 8)

Run: `swift build 2>&1 | grep -i "pyannote\|error" | head`
Expected: plus d'erreur dans PyannoteDiarizer.swift (erreurs résiduelles ailleurs OK, traitées Task 7-8).

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/PyannoteDiarizer.swift
git commit -m "refactor(diarize): PyannoteDiarizer uses TurnMerger.DiarTurn"
```

---

## Task 7: DiarizeFirstTranscriber + rewire TranscriptionService

**Files:**
- Create: `OneToOne/Services/STT/DiarizeFirstTranscriber.swift`
- Modify: `OneToOne/Services/TranscriptionService.swift`

- [ ] **Step 1: Créer l'orchestrateur diarize-first**

```swift
import Foundation

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// Orchestration diarize-first : Pyannote → fusion des tours → STT (Voxtral)
/// par tour → blocs attribués. Pur côté logique de découpe ; délègue le STT
/// à un `STTEngine` et la diarisation à `PyannoteDiarizer`.
@MainActor
enum DiarizeFirstTranscriber {
    static let maxGap: Double = 0.5
    static let minTurnDuration: Double = 0.6
    static let maxTokensPerTurn: Int = 1024
    static let sampleRate: Int = 16_000

    /// Renvoie les blocs transcrits + les embeddings par cluster (pour matching).
    /// `engine` doit être déjà chargé (`load()`).
    static func run(audioURL: URL,
                    engine: STTEngine,
                    language: String,
                    clusterThreshold: Float,
                    onPhase: ((TranscriptionPhase) -> Void)?,
                    onProgress: ((Double, String) -> Void)?) async throws
        -> (blocks: [TurnMerger.Block], embeddings: [Int: [Float]]) {
        #if canImport(MLXAudioSTT)
        // 1-2. Diarisation (émet .loadingModel / .diarizing elle-même).
        let diar = try await PyannoteDiarizer.shared.diarize(
            audioURL: audioURL, clusterThreshold: clusterThreshold,
            onPhase: onPhase, onProgress: onProgress)

        // 3. Fusion des tours adjacents même locuteur.
        let merged = TurnMerger.mergeAdjacent(diar.turns, maxGap: maxGap)

        // 4. Charge l'audio une fois, découpe par tour, transcrit.
        onPhase?(.transcribing)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: sampleRate)
        let total = audio.shape.last ?? 0
        var blocks: [TurnMerger.Block] = []
        let n = max(1, merged.count)
        for (i, t) in merged.enumerated() {
            try Task.checkCancellation()
            onProgress?(Double(i) / Double(n), "Tour \(i + 1) / \(merged.count)")
            guard (t.endSec - t.startSec) >= minTurnDuration else { continue }
            let a = max(0, Int((t.startSec * Double(sampleRate)).rounded(.down)))
            let b = min(total, Int((t.endSec * Double(sampleRate)).rounded(.down)))
            guard b > a else { continue }
            let clip = audio[a..<b]
            let text = await engine.transcribe(clip: clip, language: language, maxTokens: maxTokensPerTurn)
            guard !text.isEmpty else { continue }
            blocks.append(TurnMerger.Block(speaker: t.clusterID, start: t.startSec, end: t.endSec, text: text))
        }
        onProgress?(1.0, "Terminé")
        return (blocks, diar.perClusterEmbedding)
        #else
        throw STTError.mlxNotLinked
        #endif
    }
}
```

- [ ] **Step 2: Dans TranscriptionService — renommer + brancher sur le mode**

Remplacer la signature et le corps de `transcribeWithDiarization` (lignes 313-376)
par `runTranscription`. Conserver la signature des callbacks. Nouveau corps :

```swift
    /// Point d'entrée unique. Branche sur `settings.transcriptionMode`. Appelé
    /// par les call sites DANS un `JobQueue.start(kind: .transcription)`.
    func runTranscription(audioURL: URL,
                          meeting: Meeting,
                          settings: AppSettings,
                          in context: ModelContext,
                          onPhase: ((TranscriptionPhase) -> Void)? = nil,
                          onProgress: ((Double, String) -> Void)? = nil) async throws -> STTResult {
        switch settings.transcriptionMode {
        case .transcriptionOnly:
            let engine = makeEngine(kind: settings.transcriptionEngine, settings: settings)
            let result = try await transcribeChunks(
                audioURL: audioURL, engine: engine, settings: settings,
                onPhase: onPhase, onProgress: onProgress)
            persistAnonymousSegments(sttResult: result, meeting: meeting, in: context)
            return result

        case .diarizeFirst:
            let engine: STTEngine = VoxtralEngine(variant: settings.voxtralVariant)
            onPhase?(.loadingModel)
            do {
                try await engine.load()
            } catch {
                // moteur indisponible → on relaie l'erreur (modèle manquant).
                throw error
            }
            let diar: (blocks: [TurnMerger.Block], embeddings: [Int: [Float]])
            do {
                diar = try await DiarizeFirstTranscriber.run(
                    audioURL: audioURL, engine: engine, language: self.language,
                    clusterThreshold: Float(settings.diarizationClusterThreshold),
                    onPhase: onPhase, onProgress: onProgress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Diarisation échouée → fallback transcription seule anonyme.
                print("[TranscriptionService] diarize-first failed: \(error). Fallback anonymous.")
                let result = try await transcribeChunks(
                    audioURL: audioURL, engine: engine, settings: settings,
                    onPhase: onPhase, onProgress: onProgress)
                persistAnonymousSegments(sttResult: result, meeting: meeting, in: context)
                return result
            }

            // Matching clusters → collaborateurs.
            onPhase?(.matching)
            let assignments = SpeakerMatcher.match(
                clusterEmbeddings: diar.embeddings, meeting: meeting,
                in: context, settings: settings)
            let canonical = canonicalizeBlocks(diar.blocks, assignments: assignments)
            persistBlocks(canonical, assignments: assignments, meeting: meeting, in: context)

            let text = canonical.map { $0.text }.joined(separator: "\n")
            var result = STTResult(text: text, language: self.language,
                                   durationSeconds: 0, segments: [])
            result.clusterEmbeddings = diar.embeddings
            return result
        }
    }

    /// Fabrique le moteur du mode transcription-seule.
    private func makeEngine(kind: STTEngineKind, settings: AppSettings) -> STTEngine {
        switch kind {
        case .cohere:  return CohereEngine()
        case .voxtral: return VoxtralEngine(variant: settings.voxtralVariant)
        }
    }
```

- [ ] **Step 3: Ajouter `transcribeChunks` (généralise l'ancien `transcribe` sur un moteur)**

Ajouter cette méthode privée (réutilise la boucle 60s, mais via `STTEngine`) :

```swift
    /// Transcription seule par chunks 60s, moteur pluggable. Charge le moteur
    /// si nécessaire. Produit `STTResult` avec un segment par chunk non vide.
    private func transcribeChunks(audioURL: URL,
                                  engine: STTEngine,
                                  settings: AppSettings,
                                  onPhase: ((TranscriptionPhase) -> Void)?,
                                  onProgress: ((Double, String) -> Void)?) async throws -> STTResult {
        #if canImport(MLXAudioSTT)
        if !engine.isLoaded {
            onPhase?(.loadingModel)
            try await engine.load()
        }
        onPhase?(.transcribing)
        let t0 = Date()
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
        let sampleCount = audio.shape.last ?? 0
        let durationSec = Double(sampleCount) / 16_000.0
        let segmentSamples = 60 * 16_000
        let segmentCount = max(1, Int(ceil(Double(sampleCount) / Double(segmentSamples))))
        let perSegmentMaxTokens = max(1024, Int(60.0 * 30.0 * 1.5))
        var pieces: [String] = []
        var sttSegments: [STTSegment] = []
        for i in 0..<segmentCount {
            try Task.checkCancellation()
            let start = i * segmentSamples
            let end = min(start + segmentSamples, sampleCount)
            onProgress?(Double(i) / Double(segmentCount), "Segment \(i + 1) / \(segmentCount)")
            let clip = audio[start..<end]
            let segText = await engine.transcribe(clip: clip, language: self.language, maxTokens: perSegmentMaxTokens)
            let segClean = Self.collapseRepetitions(segText)
            pieces.append(segClean)
            if !segClean.isEmpty {
                sttSegments.append(STTSegment(
                    startSeconds: Double(start) / 16_000.0,
                    endSeconds: Double(end) / 16_000.0,
                    text: segClean))
            }
        }
        onProgress?(1.0, "Terminé")
        let combined = pieces.filter { !$0.isEmpty }.joined(separator: "\n")
        let cleaned = Self.stripWrappingQuotes(Self.collapseRepetitions(combined))
        sttLog.info("transcribeChunks done in \(Date().timeIntervalSince(t0), format: .fixed(precision: 1))s")
        return STTResult(text: cleaned, language: self.language,
                         durationSeconds: durationSec, segments: sttSegments)
        #else
        throw STTError.mlxNotLinked
        #endif
    }
```

- [ ] **Step 4: Remplacer `canonicalizeClusters` par `canonicalizeBlocks` + `persistAlignedSegments` par `persistBlocks`**

Remplacer `canonicalizeClusters(_ aligned: [TurnAligner.AlignedSegment], ...)` (lignes 406-434) par :

```swift
    /// Unifie les clusters mappés au même collaborateur vers un cluster canonique,
    /// puis re-merge les blocs adjacents. Réduit la sur-segmentation Pyannote.
    func canonicalizeBlocks(_ blocks: [TurnMerger.Block],
                            assignments: [Int: SpeakerMatcher.Assignment]) -> [TurnMerger.Block] {
        var canonicalByCollab: [PersistentIdentifier: Int] = [:]
        for cid in assignments.keys.sorted() {
            guard let collab = assignments[cid]?.collaborator else { continue }
            let pid = collab.persistentModelID
            if canonicalByCollab[pid] == nil { canonicalByCollab[pid] = cid }
        }
        guard !canonicalByCollab.isEmpty else { return blocks }
        let rewritten: [TurnMerger.Block] = blocks.map { b in
            guard let collab = assignments[b.speaker]?.collaborator,
                  let canonical = canonicalByCollab[collab.persistentModelID],
                  canonical != b.speaker else { return b }
            var nb = b; nb.speaker = canonical; return nb
        }
        return TurnMerger.mergeConsecutiveBlocks(rewritten)
    }
```

Remplacer le `#if DEBUG canonicalizeClustersForTest` (lignes 436-443) par :

```swift
    #if DEBUG
    func canonicalizeBlocksForTest(_ blocks: [TurnMerger.Block],
                                   assignments: [Int: SpeakerMatcher.Assignment]) -> [TurnMerger.Block] {
        canonicalizeBlocks(blocks, assignments: assignments)
    }
    #endif
```

Remplacer `persistAlignedSegments(aligned: [TurnAligner.AlignedSegment], ...)` (lignes 445-486) par :

```swift
    private func persistBlocks(_ blocks: [TurnMerger.Block],
                               assignments: [Int: SpeakerMatcher.Assignment],
                               meeting: Meeting,
                               in context: ModelContext) {
        for old in meeting.transcriptSegments { context.delete(old) }
        var idx = 0
        var assignmentsDict: [String: Any] = [:]
        var metaDict: [String: [String: Any]] = [:]
        for b in blocks {
            let s = TranscriptSegment(
                orderIndex: idx, startSeconds: b.start, endSeconds: b.end,
                text: b.text, speakerID: b.speaker + 1)
            s.meeting = meeting
            if let a = assignments[b.speaker], let collab = a.collaborator, a.auto {
                s.speaker = collab
            }
            context.insert(s)
            idx += 1
        }
        for (cid, a) in assignments {
            assignmentsDict[String(cid)] = a.collaborator?.ensuredStableID.uuidString ?? NSNull()
            metaDict[String(cid)] = [
                "confidence": a.confidence, "auto": a.auto, "ambiguous": a.ambiguous,
                "candidates": a.candidates.map { $0.0.ensuredStableID.uuidString }
            ]
        }
        if let d = try? JSONSerialization.data(withJSONObject: assignmentsDict),
           let s = String(data: d, encoding: .utf8) { meeting.speakerAssignmentsJSON = s }
        if let d = try? JSONSerialization.data(withJSONObject: metaDict),
           let s = String(data: d, encoding: .utf8) { meeting.speakerMatchMetaJSON = s }
    }
```

- [ ] **Step 5: Supprimer l'ancien `transcribe(audioURL:)` et la boucle MLX directe**

Supprimer la méthode `transcribe(audioURL:) async throws -> STTResult` (lignes 211-305)
— remplacée par `transcribeChunks`. Supprimer aussi le champ `private var asr: CohereTranscribeModel?`
(ligne 99) et la méthode `loadModel()` (lignes 171-201) : la résolution/chargement
passe désormais par les moteurs. Garder `loadAudioArray` n'existe pas ici —
c'est la fonction libre de MLXAudioCore ; ne rien supprimer côté audio loader
`loadMonoFloat32` (utilisé ailleurs ? vérifier au Step 6).

> Garder : `STTResult`, `STTSegment`, `STTError`, `collapseRepetitions`,
> `stripWrappingQuotes`, `persistAnonymousSegments`, `loadMonoFloat32`, et les
> helpers de chemin si encore utilisés (sinon supprimer au Step 6).

- [ ] **Step 6: Vérifier les usages résiduels avant suppression**

Run: `grep -rn "loadMonoFloat32\|resolveExistingModelDirectory\|candidateDirectories\|setManualModelDirectory\|huggingFaceSnapshotsDir\|managedModelDirectory\|\.transcribe(audioURL" OneToOne`
Pour chaque méthode de `TranscriptionService` SANS usage externe → la supprimer.
Pour `loadMonoFloat32` : si seul `TranscriptionService` interne l'utilisait et qu'on
ne l'utilise plus, supprimer ; sinon garder.

- [ ] **Step 7: Compiler**

Run: `swift build 2>&1 | tail -40`
Expected: erreurs seulement sur les call sites `transcribeWithDiarization` (Task 8) et tests TurnAligner (Task 8). Corriger toute autre erreur de compilation ici.

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Services/STT/DiarizeFirstTranscriber.swift OneToOne/Services/TranscriptionService.swift
git commit -m "feat(stt): diarize-first orchestrator + runTranscription mode branching"
```

---

## Task 8: Supprimer TurnAligner + recâbler call sites & tests

**Files:**
- Delete: `OneToOne/Services/TurnAligner.swift`
- Modify: `OneToOne/Views/MeetingView.swift:439,1267`
- Modify: `OneToOne/Views/Settings/MaintenanceView.swift:194`
- Delete/rewrite: `Tests/TurnAlignerTests.swift`, `Tests/CanonicalizeClustersTests.swift`

- [ ] **Step 1: Recâbler les 3 call sites**

Dans chacun, remplacer `stt.transcribeWithDiarization(` par `stt.runTranscription(`
(signature des arguments identique). Vérifier :

Run: `grep -rn "transcribeWithDiarization" OneToOne`
Expected: aucun résultat.

- [ ] **Step 2: Supprimer TurnAligner.swift**

```bash
git rm OneToOne/Services/TurnAligner.swift
```

- [ ] **Step 3: Réécrire CanonicalizeClustersTests pour canonicalizeBlocks**

Ouvrir `Tests/CanonicalizeClustersTests.swift`. Remplacer chaque construction
`TurnAligner.AlignedSegment(startSec:endSec:text:clusterID:)` par
`TurnMerger.Block(speaker:start:end:text:)` (champ `clusterID`→`speaker`,
`startSec`→`start`, `endSec`→`end`), et chaque appel
`canonicalizeClustersForTest(` par `canonicalizeBlocksForTest(`. Adapter les
assertions de champs (`.clusterID`→`.speaker`, `.startSec`→`.start`, `.endSec`→`.end`).

- [ ] **Step 4: Supprimer TurnAlignerTests (overlap-align supprimé)**

```bash
git rm Tests/TurnAlignerTests.swift
```

> La couverture de fusion est désormais dans `TurnMergerTests` (Task 5).

- [ ] **Step 5: Compiler + tests**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -30`
Expected: build OK, tous les tests PASS (TurnMergerTests + CanonicalizeClustersTests réécrits + le reste inchangé).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(stt): remove overlap-based TurnAligner, rewire call sites + tests"
```

---

## Task 9: SettingsView — pickers mode / moteur / variante

**Files:**
- Modify: `OneToOne/Views/SettingsView.swift`

- [ ] **Step 1: Localiser la section diarisation existante**

Run: `grep -n "speakerId\|diarization\|Diaris\|Section" OneToOne/Views/SettingsView.swift | head -40`
Repérer la `Section` qui hébergeait `speakerIdEnabled` / `diarizationClusterThreshold`.

- [ ] **Step 2: Insérer les pickers (dans cette Section, avec `@Bindable var settings` déjà en place)**

```swift
            Picker("Mode de transcription", selection: $settings.transcriptionMode) {
                Text("Transcription seule").tag(TranscriptionMode.transcriptionOnly)
                Text("Diarisation (locuteurs)").tag(TranscriptionMode.diarizeFirst)
            }

            if settings.transcriptionMode == .transcriptionOnly {
                Picker("Moteur STT", selection: $settings.transcriptionEngine) {
                    Text("Cohere Transcribe").tag(STTEngineKind.cohere)
                    Text("Voxtral").tag(STTEngineKind.voxtral)
                }
            }

            Picker("Variante Voxtral", selection: $settings.voxtralVariant) {
                ForEach(VoxtralVariant.allCases, id: \.self) { v in
                    Text(v.label).tag(v)
                }
            }
```

> Si la Section utilise `Toggle("...", isOn: $settings.speakerIdEnabled)` :
> supprimer ce Toggle (`speakerIdEnabled` est maintenant read-only dérivé du mode).
> Les sliders de seuils diarisation restent ; on peut les masquer hors mode
> diarize-first en les enveloppant dans `if settings.transcriptionMode == .diarizeFirst { ... }`.

- [ ] **Step 3: Compiler**

Run: `swift build 2>&1 | tail -20`
Expected: build OK. Si erreur sur `$settings.speakerIdEnabled` ailleurs dans la vue → supprimer/remplacer ce binding.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): UI pickers mode/engine/voxtral variant"
```

---

## Task 10: Vérification finale (build, tests, run)

**Files:** aucun (vérification)

- [ ] **Step 1: Build complet propre**

Run: `swift build 2>&1 | tail -20`
Expected: « Build complete ».

- [ ] **Step 2: Suite de tests complète**

Run: `swift test 2>&1 | tail -30`
Expected: tous PASS.

- [ ] **Step 3: Vérifier qu'aucune référence morte ne subsiste**

Run: `grep -rn "TurnAligner\|transcribeWithDiarization\|speakerIdEnabled =" OneToOne Tests`
Expected: aucun résultat (sauf éventuel commentaire historique à nettoyer).

- [ ] **Step 4: Run app (vérification manuelle)**

Utiliser le skill `run` ou lancer l'app. Vérifier :
- Réglages : 3 pickers présents, le picker Moteur n'apparaît qu'en « Transcription seule ».
- Mode transcription seule (Cohere) : transcription apparaît dans JobQueueSidebar, annulable, texte produit.
- Mode diarisation : phases `diarisation → transcription (Tour i/N) → matching`, blocs par locuteur, attribution collaborateurs.

- [ ] **Step 5: Commit final éventuel (nettoyage)**

```bash
git add -A && git commit -m "chore(stt): cleanup diarize-first migration" || echo "rien à committer"
```

---

## Self-review (effectué)

- **Couverture spec :** protocole pluggable (T1-3), modes+migration (T4), TurnMerger (T5), diarize-first flow (T7), suppression overlap (T8), réglages (T9), JobQueue conservé (call sites recâblés T8), fallback diarisation échouée (T7 Step 2). ✓
- **DiarizationService :** conservé (utilisé par `runDiarization`), spec corrigée implicitement (non listé en suppression). ✓
- **Cohérence types :** `TurnMerger.DiarTurn` (start/end/clusterID), `TurnMerger.Block` (speaker/start/end/text) ; `canonicalizeBlocks`/`persistBlocks`/`mergeConsecutiveBlocks` cohérents ; `runTranscription` même signature que l'ancien `transcribeWithDiarization`. ✓
- **Placeholders :** aucun ; code complet par étape. ✓
