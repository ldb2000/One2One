# Teams auto-record — double piste audio (plan 2/2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capturer l'audio système de Teams en plus du micro, mixer les deux pistes en un flux unique pour le STT, et conserver la provenance de chaque instant afin d'attribuer les segments transcrits à « moi » ou « distant ».

**Architecture:** Une capture `SCStream` audio-only alimente une seconde piste. Un mixeur — **fonction pure** — somme les deux buffers en un `[Float]` 16 kHz mono, celui que `LiveTranscriptionService.begin(audioStream:)` consomme déjà : tout l'aval (VAD, Whisper, merger, diarisation) reste strictement inchangé. En parallèle, l'énergie de chaque piste est horodatée dans une chronologie qui permet d'attribuer la provenance sans la deviner au timbre.

**Tech Stack:** Swift 5.9, AVFoundation, ScreenCaptureKit, SwiftData. Tests : Swift Testing pour le mixeur et la chronologie (fonctions pures), vérification à l'écran pour la capture réelle.

**Spec de référence :** [`docs/superpowers/specs/2026-08-28-teams-autorecord-popup-design.md`](../specs/2026-08-28-teams-autorecord-popup-design.md) §6.1.

**Prérequis :** le plan 1 (`2026-08-28-teams-autorecord-detection-orchestration.md`) est fusionné. `AppSettings.teamsAudioCaptureMode` et l'énumération `TeamsAudioCaptureMode` existent déjà, introduites par sa Task 7.

## Global Constraints

- Branche : `feat/teams-audio-double-piste`, partant de `master`. Aucun commit sur `master`.
- Commits conventionnels. Une PR = une intention.
- Commentaires et libellés d'interface en **français** ; symboles et code en anglais.
- **Aucune nouvelle dépendance** SwiftPM.
- **Aucune migration SwiftData**, **aucune modification d'`Info.plist`** — `NSScreenCaptureUsageDescription` n'est pas le mécanisme TCC de ScreenCaptureKit (spec §8).
- Deployment target : `.macOS("15.0")`, largement au-dessus du macOS 13 requis par `SCStream.captureAudio`.
- Le repli micro seul doit rester **silencieux et fonctionnel** : une permission refusée dégrade la capture, elle ne casse jamais l'enregistrement (spec D-6).
- Vérification avant PR : `swift test --skip CalendarImportEventTests`.

## File Structure

| Fichier | Responsabilité |
|---|---|
| `OneToOne/Services/Teams/AudioTrackMixer.swift` | **Créé.** Fonctions pures : mixage borné de deux buffers, énergie RMS, attribution de provenance. Zéro import framework au-delà de Foundation. |
| `OneToOne/Services/Teams/SystemAudioCapture.swift` | **Créé.** Enveloppe `SCStream` audio-only. Une seule responsabilité : produire des `[Float]` 16 kHz mono depuis l'audio système. |
| `OneToOne/Services/AudioRecorderService.swift` | **Modifié.** Accueille une seconde source, mixe, tient la chronologie de provenance. C'est la modification la plus structurante du chantier. |
| `OneToOne/Services/STT/SilenceAwareChunker.swift` | **Créé** (tâche 5). Fonctions pures : frontières de morceaux posées sur les creux d'énergie. Zéro I/O, zéro MLX. |
| `OneToOne/Services/TranscriptionService.swift` | **Modifié** (tâche 5). `transcribeChunks` : frontières silence + transcription bornée-parallèle, ordre préservé. |

> **Pourquoi le risque est ici et pas dans `SCStream`.** `AudioRecorderService`
> est un singleton à un seul moteur, un seul `currentFileURL` et un seul
> `activeMeetingID`. Capturer l'audio système est presque banal ; lui faire
> accepter une seconde source simultanée sans casser l'enregistrement classique
> ne l'est pas. D'où l'ordre des tâches : les fonctions pures d'abord, la
> capture ensuite, l'intégration en dernier, une fois les deux premières sûres.

---

### Task 1 : le mixeur et la chronologie de provenance

**Files:**
- Create: `OneToOne/Services/Teams/AudioTrackMixer.swift`
- Test: `Tests/AudioTrackMixerTests.swift`

**Interfaces:**
- Produces: `TrackProvenance`, `TrackEnergySample`, `AudioTrackMixer.mix(mic:system:)`, `AudioTrackMixer.rms(_:)`, `AudioTrackMixer.provenance(forRange:in:silenceThreshold:dominanceRatio:)`.

- [ ] **Step 1: Write the failing test**

Créer `Tests/AudioTrackMixerTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Le mixage jette de l'information si on n'y prend pas garde : une fois les
/// deux pistes sommées, plus rien ne dit qui parlait. Ces tests verrouillent
/// les deux moitiés du contrat — un mixage qui ne sature pas, et une
/// chronologie qui conserve la provenance.
@Suite("AudioTrackMixer — mixage et provenance")
struct AudioTrackMixerTests {

    // MARK: - Mixage

    @Test("Deux pistes de même longueur sont sommées échantillon par échantillon")
    func mixesEqualLengths() {
        #expect(AudioTrackMixer.mix(mic: [0.1, 0.2], system: [0.3, 0.4]) == [0.4, 0.6000001])
    }

    @Test("La somme est bornée à ±1 : jamais de saturation destructive")
    func clampsToUnitRange() {
        #expect(AudioTrackMixer.mix(mic: [0.9, -0.9], system: [0.8, -0.8]) == [1.0, -1.0])
    }

    @Test("Une piste absente laisse l'autre intacte")
    func passthroughWhenOneTrackEmpty() {
        #expect(AudioTrackMixer.mix(mic: [0.5, -0.25], system: []) == [0.5, -0.25])
        #expect(AudioTrackMixer.mix(mic: [], system: [0.5, -0.25]) == [0.5, -0.25])
    }

    @Test("Des longueurs inégales n'introduisent pas de décalage : la plus courte est complétée de silence")
    func padsShorterTrack() {
        #expect(AudioTrackMixer.mix(mic: [0.5, 0.5, 0.5], system: [0.5]) == [1.0, 0.5, 0.5])
    }

    @Test("Deux pistes vides donnent un buffer vide")
    func bothEmpty() {
        #expect(AudioTrackMixer.mix(mic: [], system: []).isEmpty)
    }

    // MARK: - Énergie

    @Test("Le RMS d'un silence est nul, celui d'un signal plein vaut 1")
    func rmsBounds() {
        #expect(AudioTrackMixer.rms([0, 0, 0]) == 0)
        #expect(AudioTrackMixer.rms([1, -1, 1, -1]) == 1)
    }

    @Test("Le RMS d'un buffer vide est nul plutôt qu'indéfini")
    func rmsOfEmptyIsZero() {
        #expect(AudioTrackMixer.rms([]) == 0)
    }

    // MARK: - Provenance

    private let timeline: [TrackEnergySample] = [
        TrackEnergySample(time: 0.0, micEnergy: 0.40, systemEnergy: 0.01),
        TrackEnergySample(time: 1.0, micEnergy: 0.35, systemEnergy: 0.02),
        TrackEnergySample(time: 2.0, micEnergy: 0.01, systemEnergy: 0.50),
        TrackEnergySample(time: 3.0, micEnergy: 0.02, systemEnergy: 0.45),
        TrackEnergySample(time: 4.0, micEnergy: 0.30, systemEnergy: 0.28),
        TrackEnergySample(time: 5.0, micEnergy: 0.001, systemEnergy: 0.001)
    ]

    @Test("Le micro domine → c'est moi qui parle")
    func micDominanceIsMe() {
        #expect(AudioTrackMixer.provenance(forRange: 0.0...1.0, in: timeline) == .me)
    }

    @Test("L'audio système domine → c'est l'interlocuteur distant")
    func systemDominanceIsRemote() {
        #expect(AudioTrackMixer.provenance(forRange: 2.0...3.0, in: timeline) == .remote)
    }

    @Test("Deux pistes d'énergie comparable → on ne tranche pas")
    func comparableEnergiesAreMixed() {
        #expect(AudioTrackMixer.provenance(forRange: 4.0...4.0, in: timeline) == .mixed)
    }

    @Test("Le silence n'est attribué à personne")
    func silenceIsUnknown() {
        #expect(AudioTrackMixer.provenance(forRange: 5.0...5.0, in: timeline) == .unknown)
    }

    @Test("Un intervalle hors chronologie n'est attribué à personne")
    func rangeOutsideTimelineIsUnknown() {
        #expect(AudioTrackMixer.provenance(forRange: 90.0...95.0, in: timeline) == .unknown)
        #expect(AudioTrackMixer.provenance(forRange: 0.0...1.0, in: []) == .unknown)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioTrackMixerTests`
Expected: échec de compilation — « cannot find 'AudioTrackMixer' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/AudioTrackMixer.swift` :

```swift
import Foundation

/// Origine attribuée à un intervalle de la transcription.
///
/// Cette attribution ne vient **pas** de la diarisation : elle vient de la
/// piste d'origine, qu'on connaît gratuitement puisqu'on capture deux sources
/// séparées. `PyannoteDiarizer` reste chargé de séparer les voix *à
/// l'intérieur* de la piste distante (spec §4).
enum TrackProvenance: String, Equatable, Sendable {
    /// Micro dominant — l'utilisateur, ou quelqu'un dans la pièce.
    case me
    /// Audio système dominant — un participant à l'appel Teams.
    case remote
    /// Les deux pistes portent une énergie comparable : on ne tranche pas.
    case mixed
    /// Silence, ou intervalle hors chronologie.
    case unknown
}

/// Énergie des deux pistes à un instant donné, relative au début de
/// l'enregistrement.
struct TrackEnergySample: Equatable, Sendable {
    let time: TimeInterval
    let micEnergy: Float
    let systemEnergy: Float
}

/// Mixage de deux pistes et conservation de leur provenance. Fonctions pures :
/// aucun état, aucun framework audio, testables sans matériel.
enum AudioTrackMixer {

    /// En deçà de cette énergie moyenne cumulée, on considère qu'il ne se passe
    /// rien et on n'attribue pas l'intervalle.
    static let defaultSilenceThreshold: Float = 0.01
    /// Rapport d'énergie au-delà duquel une piste est dite dominante.
    static let defaultDominanceRatio: Float = 2.0

    /// Somme les deux pistes, échantillon par échantillon, en bornant à ±1.
    ///
    /// La piste la plus courte est complétée de silence plutôt que tronquée :
    /// tronquer décalerait tout ce qui suit, et un décalage cumulatif ruinerait
    /// l'alignement de la chronologie de provenance.
    static func mix(mic: [Float], system: [Float]) -> [Float] {
        if system.isEmpty { return mic }
        if mic.isEmpty { return system }
        let count = max(mic.count, system.count)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let a = i < mic.count ? mic[i] : 0
            let b = i < system.count ? system[i] : 0
            out[i] = max(-1, min(1, a + b))
        }
        return out
    }

    /// Énergie efficace du buffer, dans `[0, 1]`. Un buffer vide vaut 0 plutôt
    /// que `NaN`.
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Attribue un intervalle de temps à une provenance, en comparant l'énergie
    /// cumulée des deux pistes sur cet intervalle.
    static func provenance(forRange range: ClosedRange<TimeInterval>,
                           in timeline: [TrackEnergySample],
                           silenceThreshold: Float = defaultSilenceThreshold,
                           dominanceRatio: Float = defaultDominanceRatio) -> TrackProvenance {
        let inRange = timeline.filter { range.contains($0.time) }
        guard !inRange.isEmpty else { return .unknown }

        let micTotal = inRange.reduce(Float(0)) { $0 + $1.micEnergy }
        let systemTotal = inRange.reduce(Float(0)) { $0 + $1.systemEnergy }
        let count = Float(inRange.count)
        guard (micTotal / count) >= silenceThreshold || (systemTotal / count) >= silenceThreshold else {
            return .unknown
        }
        if micTotal >= systemTotal * dominanceRatio { return .me }
        if systemTotal >= micTotal * dominanceRatio { return .remote }
        return .mixed
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioTrackMixerTests`
Expected: PASS, 13 tests.

> Si `mixesEqualLengths` échoue sur `0.6000001`, c'est l'arithmétique flottante
> attendue en `Float` : ajuster la valeur attendue à ce que produit la machine
> plutôt que d'introduire une tolérance, le test documente alors le comportement
> réel.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/AudioTrackMixer.swift Tests/AudioTrackMixerTests.swift
git commit -m "feat(audio): mixeur pur deux pistes et attribution de provenance"
```

---

### Task 2 : la capture de l'audio système

**Files:**
- Create: `OneToOne/Services/Teams/SystemAudioCapture.swift`
- Test: `Tests/SystemAudioCaptureTests.swift`

**Interfaces:**
- Consumes: `AudioRecorderService.sampleRate` (`16_000`) et `AudioRecorderService.channels` (`1`), constantes statiques existantes.
- Produces: `SystemAudioCapture`, `SystemAudioCapture.makeConfiguration()`, `SystemAudioCapture.isPermissionGranted()`, `SystemAudioCapture.start(onSamples:)`, `SystemAudioCapture.stop()`.

> **Ce qui est testable ici.** Ni `SCStream` ni la permission ne se simulent en
> test unitaire. La configuration, en revanche, est une valeur : un mauvais
> `sampleRate` ou un `channelCount` à 2 produirait un flux inexploitable par le
> STT, et se verrait seulement à l'oreille. On la teste.

- [ ] **Step 1: Write the failing test**

Créer `Tests/SystemAudioCaptureTests.swift` :

```swift
import Testing
import Foundation
import ScreenCaptureKit
@testable import OneToOne

/// La configuration du flux est une valeur, donc testable — et c'est elle qui
/// décide si le STT recevra quelque chose d'exploitable. Un `sampleRate` qui ne
/// correspond pas à celui du micro rendrait le mixage incohérent.
@Suite("SystemAudioCapture — configuration du flux")
struct SystemAudioCaptureTests {

    @Test("Le flux capture l'audio et rien d'autre")
    func capturesAudioOnly() {
        let config = SystemAudioCapture.makeConfiguration()
        #expect(config.capturesAudio)
        // Vidéo réduite au minimum légal : on ne veut pas d'image (spec §1).
        #expect(config.width == 2)
        #expect(config.height == 2)
    }

    @Test("Le taux d'échantillonnage suit celui du micro")
    func sampleRateMatchesRecorder() {
        #expect(SystemAudioCapture.makeConfiguration().sampleRate == Int(AudioRecorderService.sampleRate))
    }

    @Test("Le flux est mono, comme la piste micro")
    func monoChannel() {
        #expect(SystemAudioCapture.makeConfiguration().channelCount == Int(AudioRecorderService.channels))
    }

    @Test("L'audio de OneToOne lui-même est exclu, pour ne pas s'enregistrer en boucle")
    func excludesOwnAudio() {
        #expect(SystemAudioCapture.makeConfiguration().excludesCurrentProcessAudio)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SystemAudioCaptureTests`
Expected: échec de compilation — « cannot find 'SystemAudioCapture' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/SystemAudioCapture.swift` :

```swift
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

private let sysAudioLog = Logger(subsystem: "com.onetoone.app", category: "system-audio")

/// Capture l'audio système via `ScreenCaptureKit`, sans vidéo. C'est la seconde
/// piste d'une réunion Teams : ce que disent les participants distants.
///
/// La permission d'enregistrement d'écran est requise. Si elle manque, `start`
/// échoue proprement et l'appelant continue en micro seul (spec D-6) : cette
/// classe ne notifie pas l'utilisateur elle-même.
@MainActor
final class SystemAudioCapture: NSObject, SCStreamOutput {

    /// Appelée à chaque bloc capturé, en 16 kHz mono.
    private var onSamples: (([Float]) -> Void)?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.onetoone.system-audio", qos: .userInitiated)

    /// Configuration du flux : audio seul, aligné sur la piste micro.
    ///
    /// `width`/`height` sont posés au minimum légal parce que `SCStream` exige
    /// une taille de sortie même quand seule l'audio nous intéresse ; on ne
    /// consomme jamais les échantillons vidéo.
    nonisolated static func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(AudioRecorderService.sampleRate)
        config.channelCount = Int(AudioRecorderService.channels)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return config
    }

    /// Vrai si la permission d'enregistrement d'écran est **déjà** accordée.
    /// Ne déclenche aucune demande : c'est `start` qui provoquera le prompt
    /// système, au moment où l'utilisateur a demandé un enregistrement.
    nonisolated static func isPermissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Démarre la capture. Lance une erreur si la permission manque ou si
    /// aucun écran n'est partageable — à l'appelant de retomber sur micro seul.
    func start(onSamples: @escaping ([Float]) -> Void) async throws {
        self.onSamples = onSamples
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AudioError.startFailed
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: Self.makeConfiguration(), delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        sysAudioLog.info("capture audio systeme demarree")
    }

    /// Arrête la capture. Idempotent.
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.onSamples = nil
        do { try await stream.stopCapture() } catch {
            sysAudioLog.warning("arret capture: \(error.localizedDescription)")
        }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let samples = Self.floatSamples(from: sampleBuffer) else { return }
        Task { @MainActor in self.onSamples?(samples) }
    }

    /// Extrait les échantillons `Float32` mono d'un `CMSampleBuffer` audio.
    nonisolated static func floatSamples(from buffer: CMSampleBuffer) -> [Float]? {
        guard let description = buffer.formatDescription,
              let asbd = description.audioStreamBasicDescription,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr,
              let data = audioBufferList.mBuffers.mData else { return nil }
        let count = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SystemAudioCaptureTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/SystemAudioCapture.swift Tests/SystemAudioCaptureTests.swift
git commit -m "feat(audio): capture ScreenCaptureKit de l'audio systeme, sans video"
```

---

### Task 3 : l'intégration dans `AudioRecorderService`

**Files:**
- Modify: `OneToOne/Services/AudioRecorderService.swift`
- Test: `Tests/AudioRecorderCaptureModeTests.swift`

**Interfaces:**
- Consumes: `AudioTrackMixer.mix(mic:system:)`, `.rms(_:)`, `TrackEnergySample` (Task 1) ; `SystemAudioCapture` (Task 2) ; `TeamsAudioCaptureMode` (plan 1, Task 6).
- Produces: `AudioRecorderService.resolvedCaptureMode(requested:hasScreenPermission:)`, `AudioRecorderService.start(meetingID:captureMode:)`, `AudioRecorderService.provenanceTimeline`, `AudioRecorderService.systemAudioUnavailable`.

> **La règle de repli, isolée.** « Quel mode de capture applique-t-on, compte
> tenu de ce que l'utilisateur a demandé et de la permission dont on dispose ? »
> est une décision pure, et c'est celle dont la régression serait la plus
> silencieuse : un repli qui ne se déclenche pas fait échouer l'enregistrement
> entier au lieu de le dégrader. On la sort du singleton pour la tester.

- [ ] **Step 1: Write the failing test**

Créer `Tests/AudioRecorderCaptureModeTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Une permission d'écran refusée doit **dégrader** l'enregistrement, jamais le
/// casser (spec D-6). Ces tests verrouillent la règle de repli.
@Suite("AudioRecorderService — résolution du mode de capture")
struct AudioRecorderCaptureModeTests {

    @Test("Micro + système demandé et permission accordée → micro + système")
    func bothWhenPermitted() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microAndSystem, hasScreenPermission: true) == .microAndSystem)
    }

    @Test("Micro + système demandé sans permission → repli micro seul")
    func fallsBackWithoutPermission() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microAndSystem, hasScreenPermission: false) == .microOnly)
    }

    @Test("Micro seul demandé reste micro seul, même avec la permission")
    func micOnlyIsHonoured() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microOnly, hasScreenPermission: true) == .microOnly)
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microOnly, hasScreenPermission: false) == .microOnly)
    }

    @Test("Au repos, aucune chronologie de provenance n'est retenue")
    @MainActor
    func idleTimelineIsEmpty() {
        #expect(AudioRecorderService.shared.provenanceTimeline.isEmpty)
        #expect(!AudioRecorderService.shared.systemAudioUnavailable)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioRecorderCaptureModeTests`
Expected: échec de compilation — « type 'AudioRecorderService' has no member 'resolvedCaptureMode' ».

- [ ] **Step 3: Write minimal implementation**

Dans `OneToOne/Services/AudioRecorderService.swift`, ajouter aux propriétés publiées :

```swift
    /// Chronologie d'énergie des deux pistes, échantillonnée à chaque bloc.
    /// C'est elle qui conserve la provenance que le mixage effacerait
    /// (spec §6.1). Vidée à chaque nouveau démarrage.
    @Published private(set) var provenanceTimeline: [TrackEnergySample] = []

    /// Vrai quand la seconde piste a été demandée mais n'a pas pu démarrer.
    /// `MeetingView` en fait un bandeau d'erreur non bloquant ; l'enregistrement
    /// continue en micro seul.
    @Published private(set) var systemAudioUnavailable = false
```

et aux propriétés internes :

```swift
    private var systemCapture: SystemAudioCapture?
    /// Derniers échantillons système reçus, en attente du prochain bloc micro
    /// avec lequel les mixer.
    private var pendingSystemSamples: [Float] = []
    private var recordingStartedAt: Date?
```

Ajouter la règle de repli, en fonction pure, près de `isOwner` :

```swift
    /// Mode de capture effectif. Une permission d'écran absente **dégrade** la
    /// capture au micro seul ; elle n'empêche jamais d'enregistrer (spec D-6).
    nonisolated static func resolvedCaptureMode(requested: TeamsAudioCaptureMode,
                                                hasScreenPermission: Bool) -> TeamsAudioCaptureMode {
        guard requested == .microAndSystem, hasScreenPermission else { return .microOnly }
        return .microAndSystem
    }
```

Étendre `start` d'un paramètre par défaut, de sorte que **tous les appels
existants restent valides** et que l'enregistrement classique conserve son
comportement au bit près :

```swift
    /// `captureMode` vaut `.microOnly` par défaut : l'enregistrement classique
    /// d'une réunion OneToOne est strictement inchangé. Seul le parcours Teams
    /// demande `.microAndSystem`.
    @discardableResult
    func start(meetingID: UUID? = nil,
               captureMode: TeamsAudioCaptureMode = .microOnly) async throws -> URL {
```

Dans le corps de `start`, juste après la vérification de la permission micro, réinitialiser l'état de la seconde piste :

```swift
        provenanceTimeline = []
        pendingSystemSamples = []
        systemAudioUnavailable = false
        recordingStartedAt = Date()
```

puis, une fois le moteur micro démarré avec succès et avant de rendre `fileURL`, armer la seconde piste :

```swift
        let effective = Self.resolvedCaptureMode(
            requested: captureMode,
            hasScreenPermission: SystemAudioCapture.isPermissionGranted())
        if effective == .microAndSystem {
            let capture = SystemAudioCapture()
            do {
                try await capture.start { [weak self] samples in
                    guard let self else { return }
                    self.pendingSystemSamples.append(contentsOf: samples)
                }
                systemCapture = capture
            } catch {
                // Dégradation, pas échec : l'enregistrement micro continue.
                systemAudioUnavailable = true
                print("[AudioRecorderService] audio système indisponible: \(error)")
            }
        } else if captureMode == .microAndSystem {
            // Demandé mais refusé faute de permission.
            systemAudioUnavailable = true
        }
```

Dans le `TapSink` côté micro — au point où les échantillons micro sont publiés
vers `makeAudioStream()` — mixer et horodater. Remplacer la publication directe
par :

```swift
    /// Mixe le bloc micro avec l'audio système en attente, note l'énergie des
    /// deux pistes, et publie le résultat dans le flux unique consommé par
    /// `LiveTranscriptionService`.
    private func publish(micSamples: [Float]) {
        let systemSamples = pendingSystemSamples
        pendingSystemSamples = []

        if !systemSamples.isEmpty || systemCapture != nil {
            let elapsed = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            provenanceTimeline.append(TrackEnergySample(
                time: elapsed,
                micEnergy: AudioTrackMixer.rms(micSamples),
                systemEnergy: AudioTrackMixer.rms(systemSamples)))
        }
        let mixed = AudioTrackMixer.mix(mic: micSamples, system: systemSamples)
        streamContinuation?.yield(mixed)
    }
```

> **Note pour l'implémenteur.** Le nom exact de la continuation
> (`streamContinuation` ci-dessus) et le point de publication actuel sont à
> relever dans `makeAudioStream()` et dans le `TapSink` : n'introduisez pas un
> second chemin de publication, remplacez celui qui existe. Le contrat à tenir
> est qu'après cette tâche, `makeAudioStream()` produise toujours **un seul**
> flux, désormais mixé.

Dans `stop()`, arrêter la seconde piste avant le moteur micro :

```swift
        if let capture = systemCapture {
            systemCapture = nil
            Task { await capture.stop() }
        }
        pendingSystemSamples = []
        recordingStartedAt = nil
```

Enfin, dans `MeetingView.startRecording()`, demander la double piste quand la
réunion est liée à un événement Teams :

```swift
            let mode: TeamsAudioCaptureMode =
                (meeting.teamsJoinURL?.isEmpty == false) ? settings.teamsAudioCaptureMode : .microOnly
            let url = try await recorder.start(meetingID: meeting.ensuredStableID, captureMode: mode)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioRecorderCaptureModeTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the full suite**

Run: `swift test --skip CalendarImportEventTests`
Expected: PASS, hors les échecs préexistants listés dans `STATUS.md`. Vérifier en particulier que `AudioRecorderOwnershipTests` et `AudioRecorderConverterTests` passent toujours : ils couvrent l'enregistrement classique, qui ne doit pas avoir bougé.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/AudioRecorderService.swift OneToOne/Views/MeetingView.swift \
        Tests/AudioRecorderCaptureModeTests.swift
git commit -m "feat(audio): seconde piste systeme mixee dans le flux STT unique"
```

---

### Task 4 : le bandeau d'erreur et la vérification à l'écran

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`
- Modify: `STATUS.md`

- [ ] **Step 1: Afficher le bandeau de repli**

Dans `MeetingView`, à côté du bandeau d'erreur existant qui présente
`recorder.lastError`, ajouter un bandeau non bloquant :

```swift
            if recorder.systemAudioUnavailable {
                Label("Audio Teams non capturé — enregistrement du micro seul. " +
                      "Autorisez l'enregistrement de l'écran dans Réglages Système pour capter les participants distants.",
                      systemImage: "speaker.slash")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
```

- [ ] **Step 2: Construire et lancer**

Run: `Scripts/bump-and-build.sh dev`
Expected: l'app se lance depuis `~/Applications`.

- [ ] **Step 3: Scénario 1 — double piste nominale**

Autoriser OneToOne dans Réglages Système → Confidentialité → Enregistrement de l'écran. Rejoindre un appel Teams, accepter le popup, faire parler l'interlocuteur distant puis parler soi-même.
Attendu : la transcription contient les deux voix. Aucun bandeau jaune.

- [ ] **Step 4: Scénario 2 — permission refusée**

Retirer l'autorisation d'enregistrement d'écran, relancer, démarrer un enregistrement Teams.
Attendu : l'enregistrement démarre quand même, le bandeau jaune s'affiche, la transcription ne contient que la voix locale. **Aucune erreur bloquante.**

- [ ] **Step 5: Scénario 3 — non-régression de l'enregistrement classique**

Démarrer une réunion OneToOne sans lien Teams et enregistrer.
Attendu : comportement identique à avant le chantier — une seule piste, aucun bandeau, aucune chronologie de provenance.

- [ ] **Step 6: Mettre `STATUS.md` à jour**

Consigner l'état, la prochaine action et la date.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Views/MeetingView.swift STATUS.md
git commit -m "feat(audio): bandeau de repli micro seul et verification a l'ecran"
```


---

### Task 5 : import audio long — frontières sur les silences et transcription bornée-parallèle

> **Décision du 2026-08-31** : avance l'item v3 « transcription d'un audio importé »,
> inspiré du pipeline d'import d'Open WebUI (`split_on_silence` + chunks en parallèle,
> `backend/open_webui/routers/audio.py`). Chez nous le découpage existe déjà —
> `transcribeChunks` coupe en fenêtres **fixes de 60 s**, séquentiellement — donc la
> tâche est : poser chaque frontière sur le creux d'énergie voisin (fini les mots coupés
> à 60 s pile), et borner une parallélisation qui préserve l'ordre. Bénéficie à
> l'import (`AudioImportService` → `retranscribe`) **et** à la retranscription des
> réunions enregistrées — même chemin.

**Files:**
- Create: `OneToOne/Services/STT/SilenceAwareChunker.swift`
- Modify: `OneToOne/Services/TranscriptionService.swift` (uniquement `transcribeChunks`)
- Test: `Tests/SilenceAwareChunkerTests.swift`

**Interfaces:**
- Consumes: `STTEngine.transcribe(clip:language:maxTokens:)` (existant, `async` non-throwing) ;
  `loadAudioArray(from:sampleRate:)` (existant) ; `Self.collapseRepetitions`, `STTSegment`,
  `STTResult` (existants).
- Produces: `SilenceAwareChunker.frameEnergies(_:)`, `SilenceAwareChunker.chunkRanges(sampleCount:energies:frameSamples:targetChunkSamples:searchRadiusSamples:)`.

> **Honnêteté sur la parallélisation.** Open WebUI parallélise des appels *réseau* — le
> gain est linéaire. Notre STT est un GPU local : le calcul se sérialise sur Metal, le
> gain vient du recouvrement pré/post-traitement (découpage, détokenisation) avec le
> GPU. D'où une borne à **2 en vol** — au-delà, la mémoire des clips ne paie plus rien.
> Le jour où un moteur distant rejoint `STTEngineKind`, la borne devient un paramètre.

- [ ] **Step 1: Write the failing test**

Créer `Tests/SilenceAwareChunkerTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Couper à 60 s pile tombe au milieu d'un mot ; couper au creux d'énergie le
/// plus proche tombe entre deux phrases. Ces tests verrouillent le contrat :
/// couverture totale, aucun recouvrement, frontière dans la fenêtre de
/// recherche, et sur le creux quand il existe.
@Suite("SilenceAwareChunker — frontières sur les silences")
struct SilenceAwareChunkerTests {

    /// Signal déterministe : `seconds` de « voix » (sinusoïde d'amplitude 0,5).
    private func voice(seconds: Int) -> [Float] {
        (0..<(seconds * 16_000)).map { 0.5 * sin(Float($0) * 0.3) }
    }

    private func silence(seconds: Int) -> [Float] {
        [Float](repeating: 0, count: seconds * 16_000)
    }

    // MARK: - Énergie par trame

    @Test("Le silence a une énergie nulle, la voix non")
    func energiesSeparateSilenceFromVoice() {
        let energies = SilenceAwareChunker.frameEnergies(voice(seconds: 1) + silence(seconds: 1))
        let half = energies.count / 2
        #expect(energies.prefix(half).allSatisfy { $0 > 0.1 })
        #expect(energies.suffix(half).allSatisfy { $0 < 0.001 })
    }

    @Test("Un signal vide n'a pas de trames")
    func emptySignalHasNoFrames() {
        #expect(SilenceAwareChunker.frameEnergies([]).isEmpty)
    }

    @Test("La dernière trame, incomplète, est mesurée quand même")
    func partialLastFrameIsMeasured() {
        let energies = SilenceAwareChunker.frameEnergies(
            [Float](repeating: 0.5, count: SilenceAwareChunker.frameSamples + 100))
        #expect(energies.count == 2)
        #expect(energies[1] > 0.1)
    }

    // MARK: - Bornes des morceaux

    private func ranges(for samples: [Float]) -> [Range<Int>] {
        SilenceAwareChunker.chunkRanges(sampleCount: samples.count,
                                        energies: SilenceAwareChunker.frameEnergies(samples))
    }

    @Test("Un signal court tient dans un seul morceau")
    func shortSignalIsOneChunk() {
        let samples = voice(seconds: 30)
        #expect(ranges(for: samples) == [0..<samples.count])
    }

    @Test("La frontière tombe dans le trou de silence proche de la cible")
    func boundaryLandsInTheSilenceGap() {
        // 57 s de voix, 2 s de silence, 60 s de voix : la cible à 60 s a un
        // creux à portée (57–59 s, dans le rayon de ±5 s). Total 119 s : après
        // la coupe à 57 s il reste 62 s, sous le seuil « cible + rayon » (65 s),
        // donc exactement deux morceaux — pas de troisième coupe forcée.
        let samples = voice(seconds: 57) + silence(seconds: 2) + voice(seconds: 60)
        let result = ranges(for: samples)
        #expect(result.count == 2)
        let boundary = result[0].upperBound
        #expect(boundary >= 57 * 16_000 && boundary <= 59 * 16_000,
                "la coupe doit tomber dans le silence, pas à 60 s pile")
    }

    @Test("Sans creux à portée, la frontière reste dans la fenêtre de recherche")
    func withoutGapBoundaryStaysInWindow() {
        let samples = voice(seconds: 130)
        let result = ranges(for: samples)
        #expect(result.count >= 2)
        let boundary = result[0].upperBound
        #expect(boundary >= 55 * 16_000 && boundary <= 65 * 16_000)
    }

    @Test("Les morceaux couvrent tout le signal, sans recouvrement ni trou")
    func chunksTileTheSignal() {
        for seconds in [30, 61, 130, 200] {
            let samples = voice(seconds: 40) + silence(seconds: 1) + voice(seconds: max(0, seconds - 41))
            let result = ranges(for: samples)
            #expect(result.first?.lowerBound == 0)
            #expect(result.last?.upperBound == samples.count)
            for (a, b) in zip(result, result.dropFirst()) {
                #expect(a.upperBound == b.lowerBound)
                #expect(!a.isEmpty)
            }
        }
    }

    @Test("Un signal vide ne produit aucun morceau")
    func emptySignalHasNoChunks() {
        #expect(SilenceAwareChunker.chunkRanges(sampleCount: 0, energies: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SilenceAwareChunkerTests`
Expected: échec de compilation — « cannot find 'SilenceAwareChunker' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/STT/SilenceAwareChunker.swift` :

```swift
import Foundation

/// Découpe un signal 16 kHz mono en morceaux d'environ une minute dont les
/// frontières tombent sur le creux d'énergie le plus proche de la cible — au
/// lieu de couper au milieu d'un mot à 60 s pile. Inspiré du pipeline
/// d'import d'Open WebUI (`split_on_silence`), adapté à un STT par fenêtres.
///
/// Fonctions pures : pas d'I/O, pas de MLX — testables sur des signaux
/// synthétiques.
enum SilenceAwareChunker {

    /// Taille de trame pour la mesure d'énergie : 200 ms à 16 kHz.
    static let frameSamples = 3_200
    /// Longueur visée d'un morceau : 60 s, comme les fenêtres historiques.
    static let targetChunkSamples = 60 * 16_000
    /// Rayon de recherche du creux autour de la cible : ±5 s.
    static let searchRadiusSamples = 5 * 16_000

    /// Énergie RMS par trame de `frameSamples`. La dernière trame, incomplète,
    /// est mesurée sur ce qu'il reste.
    static func frameEnergies(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frameSamples + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + frameSamples, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            energies.append((sum / Float(end - start)).squareRoot())
            start = end
        }
        return energies
    }

    /// Bornes des morceaux couvrant `0..<sampleCount`, contiguës et sans
    /// recouvrement. Chaque frontière est posée au début de la trame la moins
    /// énergique dans `[cible − rayon, cible + rayon]` ; à égalité, la
    /// première gagne (déterministe).
    static func chunkRanges(sampleCount: Int,
                            energies: [Float],
                            frameSamples: Int = frameSamples,
                            targetChunkSamples: Int = targetChunkSamples,
                            searchRadiusSamples: Int = searchRadiusSamples) -> [Range<Int>] {
        guard sampleCount > 0 else { return [] }
        var ranges: [Range<Int>] = []
        var cursor = 0
        // Tant qu'il reste plus d'un morceau « cible + rayon », on coupe ; le
        // reste part d'un bloc — jamais de miette finale d'une poignée de
        // secondes, que Whisper hallucinerait.
        while sampleCount - cursor > targetChunkSamples + searchRadiusSamples {
            let target = cursor + targetChunkSamples
            let windowStart = max(cursor + frameSamples, target - searchRadiusSamples)
            let windowEnd = min(sampleCount - frameSamples, target + searchRadiusSamples)
            var bestBoundary = target
            var bestEnergy = Float.greatestFiniteMagnitude
            var frame = windowStart / frameSamples
            while frame * frameSamples <= windowEnd {
                let boundary = frame * frameSamples
                if boundary > cursor, frame < energies.count, energies[frame] < bestEnergy {
                    bestEnergy = energies[frame]
                    bestBoundary = boundary
                }
                frame += 1
            }
            ranges.append(cursor..<bestBoundary)
            cursor = bestBoundary
        }
        ranges.append(cursor..<sampleCount)
        return ranges
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SilenceAwareChunkerTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Brancher `transcribeChunks` — frontières silence + parallélisation bornée**

Dans `OneToOne/Services/TranscriptionService.swift`, remplacer dans `transcribeChunks`
le bloc allant de `let segmentSamples = 60 * 16_000` à la fin de la boucle `for`
(exclues : les lignes `onProgress?(1.0, …)` et suivantes, inchangées) par :

```swift
        onProgress?(0, "Découpage sur les silences…")
        let floats = audio.asArray(Float.self)
        let energies = SilenceAwareChunker.frameEnergies(floats)
        let ranges = SilenceAwareChunker.chunkRanges(sampleCount: sampleCount, energies: energies)
        // 65 s max par morceau (60 s de cible + 5 s de rayon).
        let perSegmentMaxTokens = max(1024, Int(65.0 * 30.0 * 1.5))

        /// Deux transcriptions en vol au plus : le GPU sérialise le gros du
        /// calcul, le gain vient du recouvrement pré/post-traitement. Au-delà,
        /// la mémoire des clips ne paie plus rien. (À exposer en paramètre le
        /// jour où un moteur distant rejoint `STTEngineKind`.)
        let maxConcurrent = 2
        var texts = [String](repeating: "", count: ranges.count)
        var completed = 0
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            func addTask(_ index: Int) {
                // Le clip est tranché ici, dans le contexte de l'acteur ; la
                // sous-tâche ne capture que sa tranche.
                let clip = audio[ranges[index].lowerBound..<ranges[index].upperBound]
                group.addTask {
                    (index, await engine.transcribe(clip: clip, language: self.language,
                                                    maxTokens: perSegmentMaxTokens))
                }
            }
            while next < min(maxConcurrent, ranges.count) { addTask(next); next += 1 }
            while let (index, raw) = try await group.next() {
                try Task.checkCancellation()
                texts[index] = Self.collapseRepetitions(raw)
                completed += 1
                onProgress?(Double(completed) / Double(ranges.count),
                            "Segment \(completed) / \(ranges.count)")
                if next < ranges.count { addTask(next); next += 1 }
            }
        }

        var pieces: [String] = []
        var sttSegments: [STTSegment] = []
        for (index, range) in ranges.enumerated() where !texts[index].isEmpty {
            pieces.append(texts[index])
            sttSegments.append(STTSegment(
                startSeconds: Double(range.lowerBound) / 16_000.0,
                endSeconds: Double(range.upperBound) / 16_000.0,
                text: texts[index]))
        }
```

La suite de la fonction (jointure, `collapseRepetitions`, `STTResult`) est inchangée.
Si le compilateur exige `Sendable` sur la capture du clip `MLXArray` dans
`group.addTask`, résoudre au minimum (capture explicite `[clip]`, ou
`nonisolated(unsafe) let` local) et **le consigner dans le rapport** — ne pas convertir
le clip en `[Float]` (ça doublerait la mémoire).

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS, aucun échec nouveau (la suite passe sans `--skip` depuis le plan 1). La
retranscription réelle d'un fichier relève de la vérification à l'écran de la tâche 4 —
ajouter à ses scénarios : « importer un audio > 5 min, vérifier que les timestamps des
segments suivent les coupes et que la barre affiche “Segment n / N” ».

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Services/STT/SilenceAwareChunker.swift OneToOne/Services/TranscriptionService.swift Tests/SilenceAwareChunkerTests.swift
git commit -m "feat(stt): frontieres de chunks sur les silences et transcription bornee-parallele"
```

## Journal d'exécution

**2026-08-31 — vague de correction unique après la revue de branche.** Écarts au plan,
tous assumés :

- **`maxConcurrent` : 2 → 1** (tâche 5). Deux `model.generate` en vol partageaient l'état
  `MLXArray` du modèle, que mlx-swift documente comme non thread-safe, pour un gain limité
  au recouvrement du pré/post-traitement sur un GPU qui sérialise de toute façon. Les
  frontières posées sur les silences — le vrai apport de la tâche — sont conservées, ainsi
  que la structure de groupe borné : relever la borne restera un jeton à changer.
- **Livraison des blocs système sortie du main actor** (tâche 3). Le `Task { @MainActor }`
  par bloc transformait un bouchon du main thread en retard **permanent** de la voix
  distante (une fois la rafale absorbée, le débit entrant redevient égal au débit sortant,
  le retard ne se résorbe plus). Les blocs sont désormais livrés depuis la file `SCStream`,
  le callback étant protégé par une boîte verrouillée (`SampleHandlerBox`).
- **Provenance horodatée sur l'horloge des échantillons publiés**, plus sur l'horloge
  murale (tâche 3). C'est l'horloge que compte `LiveVADSegmenter`, et la pause la fige
  comme elle fige le flux ; une horloge murale décalait toute la chronologie de la durée
  mise en pause.
- **Attribution « moi » / « distant » reportée.** Le plan promettait la provenance ; la
  branche livre la chronologie et le mécanisme de décision, mais **aucun consommateur**.
  Le câblage (segments → `speakerID`) et la persistance qui va avec — le WAV est mixé,
  la provenance y est détruite — sont un chantier de suite. Spec §6.1(4), D-7 et `STATUS.md`
  ont été amendés pour le dire.
