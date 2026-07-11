# Transcription en temps réel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher un transcript qui se construit au fil de la réunion pendant l'enregistrement micro, puis le nettoyer et l'attribuer aux locuteurs après le `stop()` pour en faire le transcript final.

**Architecture:** On remplace `AVAudioRecorder` par `AVAudioEngine` + `installTap` dans `AudioRecorderService` — même WAV Int16/16 kHz/mono en sortie, plus un `AsyncStream<[Float]>` de buffers 16 kHz mono. Un nouveau `LiveTranscriptionService` consomme ce flux : VAD Silero (CoreML) découpe aux silences, chaque fenêtre (~10-30 s + overlap) passe par le `VoxtralEngine` **existant**, et le texte dédupliqué est publié en direct. Au `stop()`, le texte live est nettoyé (`collapseRepetitions`) puis diarisé par Pyannote seul (sans 2ᵉ passe STT), l'attribution des locuteurs se faisant par recouvrement de timestamps.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `AVFoundation` (`AVAudioEngine`/`AVAudioConverter`/`AVAudioFile`), MLX via `mlx-audio-swift` (`VoxtralRealtimeModel`, `loadAudioArray`, `MLXArray`), `SpeechVAD` (Silero VAD v5 + `StreamingVADProcessor`, Pyannote diarizer).

## Global Constraints

- **Format WAV inchangé** : PCM linéaire Int16 little-endian, 16 kHz, mono. Jamais Float32 sur disque (casserait `concatenateWAVs` et doublerait la taille).
- **Emplacement WAV inchangé** : `~/Library/Application Support/OneToOne/recordings/<UUID>.wav` via `AudioRecorderService.recordingsDirectory`.
- **Surface publique `@Published` de `AudioRecorderService` inchangée** : `isRecording`, `isPaused`, `elapsedSeconds`, `currentFileURL`, `averagePower`, `peakPower`, `lastError`, `activeMeetingID`. Les vues existantes ne doivent pas changer de contrat.
- **Commentaires & libellés UI en français**, symboles/code en anglais (convention CLAUDE.md).
- **MLX mono-GPU in-process** : les appels STT live sont **séquentiels** (jamais concurrents) et **arrêtés avant** toute STT batch. Le VAD tourne sur CoreML/Neural Engine (pas le GPU).
- **Build & test** : `swift build` pour compiler ; `swift test --skip CalendarImportEventTests` pour les tests unitaires. `swift build`/`swift test` **ne linkent pas le metallib** → aucun test ne doit exécuter MLX (Voxtral) ni charger un modèle : les tests portent uniquement sur des helpers **purs**. La vérification de bout en bout (capture micro, VAD, STT live) se fait sur l'**app packagée** via `Scripts/bump-and-build.sh dev`.
- **`VoxtralRealtimeModel`/`SileroVADModel`/`StreamingVADProcessor` ne sont pas thread-safe** : une instance par flux, appels sérialisés, jamais depuis le render callback audio.
- **Modèles chargés localement** : Voxtral via `STTModelResolver` + `fromDirectory` (jamais de download à la volée) ; Silero CoreML via `fromPretrained(engine: .coreml)` (download HF au 1ᵉʳ usage, cache `~/Library/Caches/qwen3-speech/`, gérer `offlineMode`).

---

## File Structure

**Nouveaux fichiers :**
- `OneToOne/Services/Live/AudioLevelMeter.swift` — helper pur RMS/peak → dBFS (Task 2).
- `OneToOne/Services/Live/LiveTranscriptMerger.swift` — fusion/déduplication du texte des fenêtres qui se recouvrent (Task 4).
- `OneToOne/Services/Live/LiveVADSegmenter.swift` — VAD streaming Silero (CoreML) + fallback RMS → segments de parole (Task 5).
- `OneToOne/Services/Live/LiveTranscriptionService.swift` — orchestrateur `@MainActor` singleton (Task 6).
- `OneToOne/Services/Live/LiveDiarizationAligner.swift` — attribution des segments live aux tours Pyannote par recouvrement de timestamps (Task 8, helper pur).
- `OneToOne/Views/Meeting/LiveTranscriptPanel.swift` — panneau SwiftUI du transcript live (Task 7).
- Tests : `Tests/AudioLevelMeterTests.swift`, `Tests/LiveTranscriptMergerTests.swift`, `Tests/LiveDiarizationAlignerTests.swift`.

**Fichiers modifiés :**
- `OneToOne/Models/AppSettings.swift` — clé `liveTranscriptionEnabled` (Task 1).
- `OneToOne/Views/SettingsView.swift` — toggle dans « Reconnaissance vocale » (Task 1).
- `OneToOne/Services/AudioRecorderService.swift` — migration `AVAudioEngine` + `audioStream` (Task 3).
- `OneToOne/Views/MeetingView.swift` — affichage du panneau live + branche de finalisation live (Task 7, Task 8).

---

## Task 1 : Réglage d'activation (opt-in)

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift` (près de la ligne 138, à côté de `notifRecordingStart`)
- Modify: `OneToOne/Views/SettingsView.swift` (dans le `GroupBox("Reconnaissance vocale")`, ligne ~631)

**Interfaces:**
- Produces: `AppSettings.liveTranscriptionEnabled: Bool` (défaut `false`).

- [ ] **Step 1 : Ajouter la clé dans `AppSettings`**

Dans `OneToOne/Models/AppSettings.swift`, juste après la déclaration de `notifRecordingStart` (ligne 138-139), ajouter :

```swift
    /// Affiche une transcription en direct pendant l'enregistrement (opt-in ;
    /// sollicite le GPU/Neural Engine en continu — impact batterie/ventilateur).
    var liveTranscriptionEnabled: Bool = false
```

- [ ] **Step 2 : Ajouter le toggle dans `SettingsView`**

Dans `OneToOne/Views/SettingsView.swift`, à l'intérieur du `VStack` du `GroupBox("Reconnaissance vocale")` (après le bloc conditionnel `if settings.transcriptionMode == .diarizeFirst { … }`, ligne ~660), ajouter :

```swift
                    Toggle("Transcription en direct (aperçu pendant l'enregistrement)", isOn: Binding(
                        get: { settings.liveTranscriptionEnabled },
                        set: { settings.liveTranscriptionEnabled = $0; saveSettings() }
                    ))
                    Text("Sollicite le processeur en continu pendant la réunion (batterie, ventilateur). Le transcript final reste nettoyé et attribué aux locuteurs après l'enregistrement.")
                        .font(.caption)
                        .foregroundColor(.secondary)
```

- [ ] **Step 3 : Compiler**

Run: `swift build`
Expected: build réussit sans erreur.

- [ ] **Step 4 : Commit**

```bash
git add OneToOne/Models/AppSettings.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(live): réglage opt-in transcription en direct"
```

---

## Task 2 : Helper de metering (pur, TDD)

Extrait du calcul du VU-mètre pour qu'il soit testable et réutilisable par le tap `AVAudioEngine`.

**Files:**
- Create: `OneToOne/Services/Live/AudioLevelMeter.swift`
- Test: `Tests/AudioLevelMeterTests.swift`

**Interfaces:**
- Produces:
  - `enum AudioLevelMeter`
  - `static func levels(from samples: [Float]) -> (average: Float, peak: Float)` — renvoie (RMS→dBFS, crête→dBFS), plancher −160 dB, pour un buffer mono Float32 [−1, 1].

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `Tests/AudioLevelMeterTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

struct AudioLevelMeterTests {

    @Test func silenceFloorsAtMinus160() {
        let (avg, peak) = AudioLevelMeter.levels(from: [Float](repeating: 0, count: 512))
        #expect(avg == -160)
        #expect(peak == -160)
    }

    @Test func emptyBufferFloorsAtMinus160() {
        let (avg, peak) = AudioLevelMeter.levels(from: [])
        #expect(avg == -160)
        #expect(peak == -160)
    }

    @Test func fullScaleSquareWaveIsNearZeroDB() {
        // Signal à ±1.0 : RMS = 1.0 → 0 dBFS, crête = 1.0 → 0 dBFS.
        let samples = (0..<512).map { $0 % 2 == 0 ? Float(1.0) : Float(-1.0) }
        let (avg, peak) = AudioLevelMeter.levels(from: samples)
        #expect(abs(avg - 0) < 0.01)
        #expect(abs(peak - 0) < 0.01)
    }

    @Test func halfAmplitudePeakIsAboutMinus6dB() {
        let samples = (0..<512).map { $0 % 2 == 0 ? Float(0.5) : Float(-0.5) }
        let (_, peak) = AudioLevelMeter.levels(from: samples)
        #expect(abs(peak - (-6.02)) < 0.1)
    }
}
```

- [ ] **Step 2 : Lancer le test → échec attendu**

Run: `swift test --filter AudioLevelMeterTests`
Expected: FAIL — `cannot find 'AudioLevelMeter' in scope`.

- [ ] **Step 3 : Implémenter le helper**

Créer `OneToOne/Services/Live/AudioLevelMeter.swift` :

```swift
import Foundation
import Accelerate

/// Calcul du niveau d'entrée (VU-mètre) à partir d'un buffer mono Float32.
/// Renvoie des dBFS (0 = pleine échelle), plancher fixé à −160 dB pour le
/// silence, afin de préserver le contrat des VU-mètres existants.
enum AudioLevelMeter {

    static let floor: Float = -160

    /// - Parameter samples: buffer mono Float32, amplitudes dans [−1, 1].
    /// - Returns: `(average, peak)` en dBFS.
    static func levels(from samples: [Float]) -> (average: Float, peak: Float) {
        guard !samples.isEmpty else { return (floor, floor) }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        var peakMagnitude: Float = 0
        vDSP_maxmgv(samples, 1, &peakMagnitude, vDSP_Length(samples.count))

        return (dBFS(rms), dBFS(peakMagnitude))
    }

    private static func dBFS(_ linear: Float) -> Float {
        guard linear > 0 else { return floor }
        return max(floor, 20 * log10(linear))
    }
}
```

- [ ] **Step 4 : Lancer le test → succès attendu**

Run: `swift test --filter AudioLevelMeterTests`
Expected: PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Services/Live/AudioLevelMeter.swift Tests/AudioLevelMeterTests.swift
git commit -m "feat(live): AudioLevelMeter (RMS/peak → dBFS)"
```

---

## Task 3 : Migration `AudioRecorderService` vers `AVAudioEngine`

Remplace `AVAudioRecorder` par `AVAudioEngine` + tap. Produit le même WAV Int16/16 kHz/mono et expose en plus un `AsyncStream<[Float]>` de buffers 16 kHz mono Float32 pour le live.

**Files:**
- Modify: `OneToOne/Services/AudioRecorderService.swift` (réécriture des internals ; API publique conservée)

**Interfaces:**
- Consumes: `AudioLevelMeter.levels(from:)` (Task 2).
- Produces (nouveau, en plus de l'API existante) :
  - `func makeAudioStream() -> AsyncStream<[Float]>` — flux des buffers 16 kHz mono Float32 pendant l'enregistrement actif (rien pendant la pause) ; se termine au `stop()`/`cancel()`.
- Conserve à l'identique : `start(meetingID:) async throws -> URL`, `pause()`, `resume()`, `stop() -> (url: URL, duration: TimeInterval)?`, `cancel()`, `concatenateWAVs(first:second:output:)`, `recordingsDirectory`, et tous les `@Published`.

> **Note d'implémentation clé — une seule conversion.** Créer l'`AVAudioFile` en écriture avec les settings Int16/16 kHz/mono existants ; son `processingFormat` est du **Float32 16 kHz mono** (macOS renvoie toujours du float deinterleaved). On installe un `AVAudioConverter` de `inputNode.outputFormat(forBus: 0)` **vers ce `processingFormat`**. Les buffers convertis (Float32 16 kHz mono) sont (a) écrits tels quels dans l'`AVAudioFile` — encodés en Int16 sur disque automatiquement — (b) copiés en `[Float]` vers le flux live et (c) passés à `AudioLevelMeter`. Pas de seconde conversion.

- [ ] **Step 1 : Réécrire les internes et l'API de `AudioRecorderService`**

Remplacer le contenu de `OneToOne/Services/AudioRecorderService.swift` par l'implémentation ci-dessous. La docstring d'en-tête (lignes 12-21), l'enum `AudioError` (adapter : voir Step 2) et `recordingsDirectory`/`concatenateWAVs`/`copyAudio` sont conservés à l'identique.

```swift
import Foundation
import AVFoundation
import Combine
import AppKit
import os
import SwiftData

private let audioLog = Logger(subsystem: "com.onetoone.app", category: "audio")

// MARK: - AudioRecorderService

/// Enregistrement WAV (PCM 16-bit linéaire, 16 kHz mono) via `AVAudioEngine`.
/// Le tap d'entrée alimente à la fois le fichier WAV (contrat historique) et un
/// `AsyncStream<[Float]>` de buffers 16 kHz mono pour la transcription en direct.
///
/// Fichiers persistés dans :
///   `~/Library/Application Support/OneToOne/recordings/<uuid>.wav`
///
/// Cap durée : 3 h (configurable via `maxDurationSeconds`).
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {

    static let shared = AudioRecorderService()

    // MARK: - Config
    static let sampleRate: Double = 16_000
    static let channels: UInt32 = 1
    var maxDurationSeconds: TimeInterval = 3 * 60 * 60

    // MARK: - Published state
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var averagePower: Float = -160
    @Published private(set) var peakPower: Float = -160
    @Published var lastError: String?
    @Published private(set) var activeMeetingID: UUID?

    // MARK: - Internals (engine)
    private let engine = AVAudioEngine()
    /// Encapsule conversion + écriture WAV + diffusion live, protégé par sa
    /// propre file série (le tap livre hors du main actor). Voir `TapSink`.
    private var sink: TapSink?
    private var streamContinuation: AsyncStream<[Float]>.Continuation?
    private var elapsedTimer: Timer?
    private var startDate: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartDate: Date?
    /// Throttle de publication des meters (~0.1 s).
    private var lastMeterPublish: TimeInterval = 0

    // MARK: - Permissions
    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    // MARK: - Storage (inchangé)
    static func concatenateWAVs(first: URL, second: URL, output: URL) throws {
        let f1 = try AVAudioFile(forReading: first)
        let f2 = try AVAudioFile(forReading: second)
        let outFile = try AVAudioFile(
            forWriting: output,
            settings: f1.fileFormat.settings,
            commonFormat: f1.processingFormat.commonFormat,
            interleaved: f1.processingFormat.isInterleaved)
        try copyAudio(from: f1, to: outFile)
        try copyAudio(from: f2, to: outFile)
    }

    private static func copyAudio(from input: AVAudioFile, to output: AVAudioFile) throws {
        let format = input.processingFormat
        let bufferSize: AVAudioFrameCount = 4096
        while input.framePosition < input.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
                throw AudioError.startFailed
            }
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }

    static var recordingsDirectory: URL {
        let base = URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Live audio stream
    /// Flux des buffers 16 kHz mono Float32 de l'enregistrement en cours.
    /// À appeler juste avant `start()`. Se termine au `stop()`/`cancel()`.
    func makeAudioStream() -> AsyncStream<[Float]> {
        AsyncStream { continuation in
            self.streamContinuation = continuation
        }
    }

    // MARK: - Lifecycle
    @discardableResult
    func start(meetingID: UUID? = nil) async throws -> URL {
        guard !isRecording else { throw AudioError.alreadyRecording }
        let granted = await requestMicrophonePermission()
        guard granted else { throw AudioError.permissionDenied }

        let fileURL = Self.recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: Self.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            // AVAudioFile Int16 sur disque ; processingFormat = Float32 16 kHz mono.
            let file = try AVAudioFile(forWriting: fileURL, settings: settings)
            let targetFormat = file.processingFormat
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioError.startFailed
            }
            let sink = TapSink(converter: conv, targetFormat: targetFormat,
                               file: file, continuation: streamContinuation)
            self.sink = sink
            self.currentFileURL = fileURL

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let samples = sink.process(buffer) else { return }
                Task { @MainActor [weak self] in self?.publishMetersThrottled(from: samples) }
            }

            engine.prepare()
            try engine.start()

            NotificationCenter.default.addObserver(
                self, selector: #selector(handleConfigurationChange),
                name: .AVAudioEngineConfigurationChange, object: engine)

            isRecording = true
            isPaused = false
            elapsedSeconds = 0
            pausedAccumulated = 0
            pauseStartDate = nil
            startDate = Date()
            activeMeetingID = meetingID
            notifyRecordingStartedIfEnabled(meetingID: meetingID)
            startElapsedTimer()
            audioLog.info("AudioRecorder(engine): start \(fileURL.path, privacy: .public)")
            return fileURL
        } catch {
            audioLog.error("AudioRecorder(engine): start failed \(error.localizedDescription, privacy: .public)")
            teardownEngine()
            throw AudioError.startFailed
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        sink?.setCapturing(false)      // les buffers du tap sont désormais ignorés
        pauseStartDate = Date()
        audioLog.info("AudioRecorder(engine): pause")
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if let paused = pauseStartDate {
            pausedAccumulated += Date().timeIntervalSince(paused)
            pauseStartDate = nil
        }
        isPaused = false
        sink?.setCapturing(true)
        audioLog.info("AudioRecorder(engine): resume")
    }

    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let url = currentFileURL else { return nil }
        let duration = elapsedSeconds
        finalizeAndTeardown()
        audioLog.info("AudioRecorder(engine): stop duration=\(duration, format: .fixed(precision: 1), privacy: .public)s")
        return (url, duration)
    }

    func cancel() {
        let url = currentFileURL
        finalizeAndTeardown()
        if let url { try? FileManager.default.removeItem(at: url) }
        audioLog.info("AudioRecorder(engine): cancel")
    }

    // MARK: - Meters
    @MainActor
    private func publishMetersThrottled(from samples: [Float]) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastMeterPublish >= 0.1 else { return }
        lastMeterPublish = now
        let (avg, peak) = AudioLevelMeter.levels(from: samples)
        averagePower = avg
        peakPower = peak
    }

    // MARK: - Config change
    @objc private nonisolated func handleConfigurationChange(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.lastError = "Périphérique audio modifié — enregistrement interrompu. Vérifie l'entrée micro."
            audioLog.error("AudioRecorder(engine): configuration change → stop")
            _ = self.stop()
        }
    }

    // MARK: - Teardown
    private func finalizeAndTeardown() {
        // Retire le tap et arrête l'engine, puis `sink.finish()` sérialise la
        // dernière écriture et ferme le fichier (finalise le header RIFF) AVANT
        // de rendre la main → le WAV est relisible dès le retour de `stop()`.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        sink?.finish()
        sink = nil
        streamContinuation = nil
        resetState()
    }

    private func teardownEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.finish()
        sink = nil
        streamContinuation = nil
        resetState()
    }

    private func resetState() {
        currentFileURL = nil
        isRecording = false
        isPaused = false
        activeMeetingID = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        averagePower = -160
        peakPower = -160
    }

    // MARK: - Timers
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func tickElapsed() {
        guard let start = startDate else { return }
        let raw = Date().timeIntervalSince(start) - pausedAccumulated
        elapsedSeconds = max(0, raw)
        if elapsedSeconds >= maxDurationSeconds { _ = stop() }   // backstop cap 3 h
    }

    // MARK: - Notification bannière (inchangé fonctionnellement)
    private func notifyRecordingStartedIfEnabled(meetingID: UUID?) {
        guard let container = OneToOneApp.sharedContainer else { return }
        let ctx = container.mainContext
        guard let settings = (try? ctx.fetch(FetchDescriptor<AppSettings>()))?.first,
              settings.notifRecordingStart else { return }
        let title: String
        if let id = meetingID {
            let all = (try? ctx.fetch(FetchDescriptor<Meeting>())) ?? []
            title = all.first { $0.ensuredStableID == id }?.title ?? ""
        } else { title = "" }
        MeetingNotificationService.shared.notifyRecordingStarted(meetingTitle: title)
    }
}

// MARK: - TapSink

/// Reçoit les buffers du tap `AVAudioEngine` (hors main actor), les convertit en
/// Float32 16 kHz mono, écrit le WAV et diffuse les samples sur le flux live —
/// le tout sérialisé sur une file dédiée. `@unchecked Sendable` : tout l'état
/// mutable est protégé par `queue`. La `continuation` d'`AsyncStream` est
/// Sendable et peut être appelée depuis n'importe quel thread.
private final class TapSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.onetoone.audio.write")
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private var file: AVAudioFile?
    private let continuation: AsyncStream<[Float]>.Continuation?
    private var capturing = true

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat,
         file: AVAudioFile, continuation: AsyncStream<[Float]>.Continuation?) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.file = file
        self.continuation = continuation
    }

    func setCapturing(_ on: Bool) { queue.sync { capturing = on } }

    /// Convertit, écrit le WAV et diffuse. Renvoie les samples convertis pour le
    /// calcul des meters, ou `nil` si en pause / erreur de conversion.
    func process(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        queue.sync {
            guard capturing else { return nil }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
            var consumed = false
            var err: NSError?
            _ = converter.convert(to: outBuf, error: &err) { _, status in
                if consumed { status.pointee = .endOfStream; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard err == nil, outBuf.frameLength > 0,
                  let ptr = outBuf.floatChannelData?[0] else { return nil }
            try? file?.write(from: outBuf)
            let samples = Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
            continuation?.yield(samples)
            return samples
        }
    }

    /// Ferme le fichier (finalise le header WAV) et termine le flux live.
    func finish() {
        queue.sync { file = nil }
        continuation?.finish()
    }
}

// MARK: - Errors
enum AudioError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case startFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accès au microphone refusé. Activer dans Réglages Système → Confidentialité → Microphone."
        case .alreadyRecording:
            return "Un enregistrement est déjà en cours."
        case .startFailed:
            return "Impossible de démarrer l'enregistrement audio."
        }
    }
}
```

> **Concurrence** : le tap `installTap` livre ses buffers hors du main actor. Tout l'état qu'il touche (converter, `AVAudioFile`, drapeau `capturing`, continuation du flux) vit dans `TapSink` (`@unchecked Sendable`, sérialisé par sa file `queue`). Le closure du tap n'appelle que `sink.process(buffer)` puis hop sur `Task { @MainActor }` pour les meters. `AudioRecorderService` reste `@MainActor` sans jamais partager d'état mutable avec le thread audio.

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit sans erreur d'isolation Swift 6 (l'état touché par le tap est entièrement dans `TapSink`).

- [ ] **Step 3 : Vérifier que les tests existants passent toujours**

Run: `swift test --skip CalendarImportEventTests`
Expected: PASS — en particulier `AudioWaveformTests`, `AudioImportServiceTests`, `AudioCompressionServiceTests`, `AudioFileEditorTests`, `WavRetentionServiceTests` (ils lisent des WAV ; le format n'a pas changé).

- [ ] **Step 4 : Vérification manuelle sur l'app packagée (capture réelle)**

Run: `Scripts/bump-and-build.sh dev`
Puis dans l'app : créer une réunion, démarrer un enregistrement, parler ~5 s, mettre en pause ~3 s, reprendre ~5 s, arrêter.
Expected :
- La transcription batch se déclenche et produit du texte (le WAV est lisible juste après `stop()`).
- Le VU-mètre bouge pendant l'enregistrement, se fige pendant la pause.
- Le fichier `recordings/<UUID>.wav` fait > 44 octets, durée ≈ temps parlé hors pause.
- Débrancher/rebrancher un casque en cours d'enregistrement → message d'erreur `lastError` affiché (pas de crash).

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Services/AudioRecorderService.swift
git commit -m "feat(audio): AudioRecorderService sur AVAudioEngine + flux live 16 kHz"
```

---

## Task 4 : Fusion/déduplication du texte des fenêtres (pur, TDD)

Les fenêtres STT se recouvrent (~1,5 s d'overlap audio) et Voxtral n'a pas de contexte inter-fenêtres. Ce helper accumule le texte des fenêtres en supprimant le préfixe redondant dû au recouvrement.

**Files:**
- Create: `OneToOne/Services/Live/LiveTranscriptMerger.swift`
- Test: `Tests/LiveTranscriptMergerTests.swift`

**Interfaces:**
- Produces:
  - `struct LiveTranscriptMerger`
  - `mutating func append(_ window: String) -> String` — ajoute le texte d'une fenêtre, renvoie le transcript accumulé courant.
  - `var text: String` — transcript accumulé.
  - `static func overlapSuffixPrefix(_ previousTail: String, _ next: String) -> Int` — longueur (en mots) du chevauchement entre la fin de l'accumulé et le début de la nouvelle fenêtre.

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer `Tests/LiveTranscriptMergerTests.swift` :

```swift
import Testing
@testable import OneToOne

struct LiveTranscriptMergerTests {

    @Test func firstWindowIsKeptVerbatim() {
        var m = LiveTranscriptMerger()
        let out = m.append("bonjour comment vas tu")
        #expect(out == "bonjour comment vas tu")
        #expect(m.text == "bonjour comment vas tu")
    }

    @Test func overlappingWordsAreNotDuplicated() {
        var m = LiveTranscriptMerger()
        _ = m.append("je pense que le projet")
        let out = m.append("le projet avance bien")
        #expect(out == "je pense que le projet avance bien")
    }

    @Test func noOverlapConcatenatesWithSpace() {
        var m = LiveTranscriptMerger()
        _ = m.append("première partie")
        let out = m.append("sujet totalement différent")
        #expect(out == "première partie sujet totalement différent")
    }

    @Test func emptyWindowIsIgnored() {
        var m = LiveTranscriptMerger()
        _ = m.append("texte")
        let out = m.append("   ")
        #expect(out == "texte")
    }

    @Test func overlapDetectionIsCaseInsensitive() {
        let n = LiveTranscriptMerger.overlapSuffixPrefix("le Projet", "Le projet avance")
        #expect(n == 2)
    }
}
```

- [ ] **Step 2 : Lancer → échec attendu**

Run: `swift test --filter LiveTranscriptMergerTests`
Expected: FAIL — `cannot find 'LiveTranscriptMerger' in scope`.

- [ ] **Step 3 : Implémenter**

Créer `OneToOne/Services/Live/LiveTranscriptMerger.swift` :

```swift
import Foundation

/// Accumule le texte de fenêtres STT qui se recouvrent, en supprimant le
/// chevauchement de mots entre la fin du texte déjà accumulé et le début de la
/// nouvelle fenêtre (Voxtral n'ayant aucun contexte inter-fenêtres). Comparaison
/// insensible à la casse ; on cherche le plus long chevauchement (jusqu'à 12 mots).
struct LiveTranscriptMerger {

    private(set) var text: String = ""
    private static let maxOverlapWords = 12

    mutating func append(_ window: String) -> String {
        let trimmed = window.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard !text.isEmpty else { text = trimmed; return text }

        let overlap = Self.overlapSuffixPrefix(text, trimmed)
        if overlap == 0 {
            text += " " + trimmed
        } else {
            let remainingWords = Self.words(trimmed).dropFirst(overlap)
            if !remainingWords.isEmpty {
                text += " " + remainingWords.joined(separator: " ")
            }
        }
        return text
    }

    /// Nombre de mots communs entre le suffixe de `previousTail` et le préfixe
    /// de `next` (le plus long, ≤ maxOverlapWords). Insensible à la casse.
    static func overlapSuffixPrefix(_ previousTail: String, _ next: String) -> Int {
        let tail = words(previousTail).map { $0.lowercased() }
        let head = words(next).map { $0.lowercased() }
        let maxK = min(maxOverlapWords, tail.count, head.count)
        var best = 0
        var k = 1
        while k <= maxK {
            if Array(tail.suffix(k)) == Array(head.prefix(k)) { best = k }
            k += 1
        }
        return best
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }
}
```

- [ ] **Step 4 : Lancer → succès attendu**

Run: `swift test --filter LiveTranscriptMergerTests`
Expected: PASS (5 tests).

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Services/Live/LiveTranscriptMerger.swift Tests/LiveTranscriptMergerTests.swift
git commit -m "feat(live): LiveTranscriptMerger (déduplication de l'overlap)"
```

---

## Task 5 : Segmenteur VAD streaming (Silero CoreML + fallback RMS)

Consomme les buffers 16 kHz mono et émet des segments de parole (frontières de silence) via Silero. Si le modèle Silero est indisponible (hors-ligne, échec de chargement), bascule sur une découpe RMS + timeout.

**Files:**
- Create: `OneToOne/Services/Live/LiveVADSegmenter.swift`

**Interfaces:**
- Produces:
  - `actor LiveVADSegmenter`
  - `init(minSilenceSeconds: Float = 0.6, maxWindowSeconds: Double = 30)`
  - `func loadSilero() async -> Bool` — tente de charger Silero CoreML ; renvoie `false` si indisponible (le fallback RMS sera utilisé).
  - `func feed(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>]` — renvoie 0..n segments de parole *clos* (en secondes depuis le début du flux) détectés dans ce buffer.
  - `func flush() -> [ClosedRange<Double>]` — clôt un éventuel segment de parole ouvert en fin de flux.
  - `func reset()`

> **Contrainte** : `SileroVADModel`/`StreamingVADProcessor` ne sont pas thread-safe → l'`actor` sérialise tous les accès. Le VAD ne consomme pas de GPU (backend CoreML).

- [ ] **Step 1 : Implémenter le segmenteur**

Créer `OneToOne/Services/Live/LiveVADSegmenter.swift` :

```swift
import Foundation
import Accelerate
#if canImport(SpeechVAD)
import SpeechVAD
#endif

/// Découpe le flux audio en segments de parole aux frontières de silence.
/// Stratégie principale : Silero VAD v5 (backend CoreML / Neural Engine — ne
/// sollicite pas le GPU). Repli : détection d'énergie (RMS) + longueur max de
/// fenêtre, si Silero n'est pas chargeable (hors-ligne, modèle absent).
actor LiveVADSegmenter {

    private let minSilenceSeconds: Float
    private let maxWindowSeconds: Double

    #if canImport(SpeechVAD)
    private var processor: StreamingVADProcessor?
    #endif
    private var useSilero = false

    // État commun / fallback RMS
    private var elapsedSeconds: Double = 0
    private var speechOpenStart: Double?
    private var silenceAccumulated: Double = 0
    private var lastSpeechEnd: Double = 0
    // Noise floor glissant pour le fallback.
    private var noiseFloor: Float = 0.005

    init(minSilenceSeconds: Float = 0.6, maxWindowSeconds: Double = 30) {
        self.minSilenceSeconds = minSilenceSeconds
        self.maxWindowSeconds = maxWindowSeconds
    }

    func loadSilero() async -> Bool {
        #if canImport(SpeechVAD)
        do {
            let model = try await SileroVADModel.fromPretrained(engine: .coreml)
            var config = VADConfig.sileroDefault
            config.minSilenceDuration = minSilenceSeconds
            processor = StreamingVADProcessor(model: model, config: config)
            useSilero = true
            return true
        } catch {
            useSilero = false
            return false
        }
        #else
        return false
        #endif
    }

    func reset() {
        #if canImport(SpeechVAD)
        processor?.reset()
        #endif
        elapsedSeconds = 0
        speechOpenStart = nil
        silenceAccumulated = 0
        lastSpeechEnd = 0
        noiseFloor = 0.005
    }

    /// Segments de parole clos détectés dans ce buffer.
    func feed(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>] {
        #if canImport(SpeechVAD)
        if useSilero, let processor {
            let events = processor.process(samples: samples)
            elapsedSeconds += Double(samples.count) / sampleRate
            var out: [ClosedRange<Double>] = []
            for e in events {
                if case let .speechEnded(segment) = e {
                    out.append(Double(segment.startTime)...Double(segment.endTime))
                }
            }
            return out.flatMap { splitLongWindow($0) }
        }
        #endif
        return feedRMS(samples, sampleRate: sampleRate)
    }

    func flush() -> [ClosedRange<Double>] {
        #if canImport(SpeechVAD)
        if useSilero, let processor {
            let events = processor.flush()
            var out: [ClosedRange<Double>] = []
            for e in events {
                if case let .speechEnded(segment) = e {
                    out.append(Double(segment.startTime)...Double(segment.endTime))
                }
            }
            return out.flatMap { splitLongWindow($0) }
        }
        #endif
        if let start = speechOpenStart, elapsedSeconds > start {
            speechOpenStart = nil
            return splitLongWindow(start...elapsedSeconds)
        }
        return []
    }

    // MARK: - Fallback RMS
    private func feedRMS(_ samples: [Float], sampleRate: Double) -> [ClosedRange<Double>] {
        let frameSamples = max(1, Int(0.030 * sampleRate))
        var closed: [ClosedRange<Double>] = []
        var i = 0
        while i + frameSamples <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress!.advanced(by: i), 1, &rms, vDSP_Length(frameSamples))
            }
            let frameDur = Double(frameSamples) / sampleRate
            elapsedSeconds += frameDur
            // Noise floor glissant (EMA lente).
            noiseFloor = 0.995 * noiseFloor + 0.005 * rms
            let threshold = max(0.005, noiseFloor * 1.5)
            if rms >= threshold {
                if speechOpenStart == nil { speechOpenStart = elapsedSeconds - frameDur }
                silenceAccumulated = 0
            } else if speechOpenStart != nil {
                silenceAccumulated += frameDur
                if silenceAccumulated >= Double(minSilenceSeconds) {
                    let start = speechOpenStart!
                    closed.append(contentsOf: splitLongWindow(start...(elapsedSeconds - silenceAccumulated)))
                    speechOpenStart = nil
                    silenceAccumulated = 0
                }
            }
            i += frameSamples
        }
        // Forcer une coupe si la fenêtre ouverte dépasse maxWindowSeconds.
        if let start = speechOpenStart, elapsedSeconds - start >= maxWindowSeconds {
            closed.append(contentsOf: splitLongWindow(start...elapsedSeconds))
            speechOpenStart = elapsedSeconds
        }
        return closed
    }

    /// Scinde un segment plus long que maxWindowSeconds en tranches successives.
    private func splitLongWindow(_ range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        guard range.upperBound - range.lowerBound > maxWindowSeconds else { return [range] }
        var out: [ClosedRange<Double>] = []
        var s = range.lowerBound
        while s < range.upperBound {
            let e = min(s + maxWindowSeconds, range.upperBound)
            out.append(s...e)
            s = e
        }
        return out
    }
}
```

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit (le module `SpeechVAD` est déjà une dépendance — cf. `PyannoteDiarizer` sous `#if canImport(SpeechVAD)`).

- [ ] **Step 3 : Commit**

```bash
git add OneToOne/Services/Live/LiveVADSegmenter.swift
git commit -m "feat(live): LiveVADSegmenter (Silero CoreML + fallback RMS)"
```

> Vérification fonctionnelle du VAD : couverte par le test manuel de bout en bout en Task 6 (l'app packagée charge Silero et découpe l'audio réel). Impossible en `swift test` (download HF + Neural Engine).

---

## Task 6 : `LiveTranscriptionService` (orchestrateur)

Consomme le flux audio de `AudioRecorderService`, découpe via `LiveVADSegmenter`, transcrit chaque fenêtre par le `VoxtralEngine` **existant** (séquentiellement), fusionne via `LiveTranscriptMerger`, publie le transcript live et conserve les segments horodatés pour la finalisation.

**Files:**
- Create: `OneToOne/Services/Live/LiveTranscriptionService.swift`

**Interfaces:**
- Consumes: `AudioRecorderService.makeAudioStream()` (Task 3), `LiveVADSegmenter` (Task 5), `LiveTranscriptMerger` (Task 4), `VoxtralEngine` + `loadAudioArray`/`MLXArray` (existant), `AppSettings.voxtralVariant` (existant).
- Produces:
  - `struct LiveSegment: Sendable { let start: Double; let end: Double; let text: String }`
  - `@MainActor final class LiveTranscriptionService: ObservableObject`
  - `static let shared`
  - `@Published private(set) var liveTranscript: String`
  - `@Published private(set) var isLive: Bool`
  - `@Published private(set) var statusMessage: String?`
  - `func begin(audioStream: AsyncStream<[Float]>, language: String, variant: VoxtralVariant) async`
  - `func end() -> [LiveSegment]` — arrête le live, renvoie les segments horodatés accumulés.

> **Découpe fenêtre → clip** : on garde un tampon `ring: [Float]` de tout l'audio depuis le début (mono 16 kHz — ~1,9 Mo/min, acceptable pour ≤ 3 h ? 3 h = ~345 Mo ; **borner** le ring aux N dernières minutes n'est pas trivial car les segments VAD référencent des timestamps absolus). **Décision** : conserver le ring complet en mémoire pour le live (le WAV reste la source disque) ; si l'empreinte est un problème, une itération ultérieure le bornera. Pour transcrire un segment `start...end`, on slice `ring[Int(start*16000)..<Int(end*16000)]`, on l'étend de ~1,5 s d'overlap à gauche (`max(0, start-1.5)`), on crée un `MLXArray` et on appelle `engine.transcribe`.

- [ ] **Step 1 : Implémenter le service**

Créer `OneToOne/Services/Live/LiveTranscriptionService.swift` :

```swift
import Foundation
import Combine
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXAudioCore)
import MLXAudioCore
#endif

/// Un segment de transcription live horodaté (secondes depuis le début).
struct LiveSegment: Sendable {
    let start: Double
    let end: Double
    let text: String
}

/// Orchestme la transcription en direct : flux audio → VAD → fenêtres → Voxtral
/// (séquentiel) → fusion. Éphémère en mémoire ; le texte final est produit à la
/// fin via `end()` puis nettoyé/diarisé par le pipeline batch.
@MainActor
final class LiveTranscriptionService: ObservableObject {

    static let shared = LiveTranscriptionService()

    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var isLive: Bool = false
    @Published private(set) var statusMessage: String?

    private let sampleRate: Double = 16_000
    private let overlapSeconds: Double = 1.5
    private var engine: VoxtralEngine?
    private var segmenter: LiveVADSegmenter?
    private var merger = LiveTranscriptMerger()
    private var ring: [Float] = []
    private var segments: [LiveSegment] = []
    private var consumeTask: Task<Void, Never>?

    private init() {}

    func begin(audioStream: AsyncStream<[Float]>, language: String, variant: VoxtralVariant) async {
        guard !isLive else { return }
        isLive = true
        liveTranscript = ""
        statusMessage = "Chargement du modèle…"
        merger = LiveTranscriptMerger()
        ring = []
        segments = []

        let eng = VoxtralEngine(variant: variant)
        do { try await eng.load() } catch {
            statusMessage = "Transcription en direct indisponible (modèle STT manquant)."
            isLive = false
            return
        }
        engine = eng

        let seg = LiveVADSegmenter()
        let sileroOK = await seg.loadSilero()
        segmenter = seg
        statusMessage = sileroOK ? nil : "Découpe par énergie (VAD indisponible)."

        consumeTask = Task { [weak self] in
            await self?.consume(audioStream, language: language)
        }
    }

    private func consume(_ stream: AsyncStream<[Float]>, language: String) async {
        guard let segmenter else { return }
        for await samples in stream {
            ring.append(contentsOf: samples)
            let closed = await segmenter.feed(samples, sampleRate: sampleRate)
            for range in closed {
                await transcribeWindow(range, language: language)
            }
        }
        // Fin de flux : clore le dernier segment.
        let tail = await segmenter.flush()
        for range in tail { await transcribeWindow(range, language: language) }
    }

    private func transcribeWindow(_ range: ClosedRange<Double>, language: String) async {
        guard let engine else { return }
        let from = max(0, range.lowerBound - overlapSeconds)
        let startIdx = Int(from * sampleRate)
        let endIdx = min(ring.count, Int(range.upperBound * sampleRate))
        guard endIdx > startIdx else { return }
        let clipSamples = Array(ring[startIdx..<endIdx])
        #if canImport(MLX) && canImport(MLXAudioCore)
        let clip = MLXArray(clipSamples)
        let durationSec = Double(clipSamples.count) / sampleRate
        let maxTokens = max(64, Int(durationSec * 13) + 64)
        let text = await engine.transcribe(clip: clip, language: language, maxTokens: maxTokens)
        guard !text.isEmpty else { return }
        let merged = merger.append(text)
        liveTranscript = merged
        segments.append(LiveSegment(start: range.lowerBound, end: range.upperBound, text: text))
        #endif
    }

    /// Arrête le live et renvoie les segments horodatés accumulés.
    @discardableResult
    func end() -> [LiveSegment] {
        consumeTask?.cancel()
        consumeTask = nil
        isLive = false
        statusMessage = nil
        engine = nil
        segmenter = nil
        let result = segments
        ring = []
        return result
    }
}
```

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit. Si `MLXArray(clipSamples)` ou l'import `MLXAudioCore` posent problème, vérifier le module qui exporte `MLXArray` (utilisé par `TranscriptionService` via `import MLX`) et ajuster les imports pour coller à `VoxtralEngine.swift` (qui compile déjà avec `MLX`).

- [ ] **Step 3 : Commit**

```bash
git add OneToOne/Services/Live/LiveTranscriptionService.swift
git commit -m "feat(live): LiveTranscriptionService (flux → VAD → Voxtral → fusion)"
```

---

## Task 7 : UI — panneau transcript live + démarrage/arrêt du service

Affiche le transcript live à côté des notes pendant l'enregistrement (nouvel onglet « Direct »), et démarre/arrête `LiveTranscriptionService` en même temps que l'enregistrement quand le réglage est actif.

**Files:**
- Create: `OneToOne/Views/Meeting/LiveTranscriptPanel.swift`
- Modify: `OneToOne/Views/MeetingView.swift` (enum `MeetingSection` ~147-155, `sectionContent` ~511-528, démarrage/arrêt de l'enregistrement)

**Interfaces:**
- Consumes: `LiveTranscriptionService.shared` (Task 6), `AudioRecorderService.shared.makeAudioStream()` (Task 3), `AppSettings.liveTranscriptionEnabled` (Task 1).

- [ ] **Step 1 : Créer le panneau**

Créer `OneToOne/Views/Meeting/LiveTranscriptPanel.swift` :

```swift
import SwiftUI

/// Panneau du transcript en direct pendant l'enregistrement. Auto-scroll vers
/// le bas au fil des ajouts. Affiché quand la transcription en direct est active.
struct LiveTranscriptPanel: View {
    @ObservedObject var live = LiveTranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundColor(live.isLive ? .red : .secondary)
                Text("Transcription en direct")
                    .font(.headline)
                if let status = live.statusMessage {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(live.liveTranscript.isEmpty ? "En écoute…" : live.liveTranscript)
                        .font(.body)
                        .foregroundColor(live.liveTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("liveBottom")
                        .padding(.vertical, 4)
                }
                .onChange(of: live.liveTranscript) { _, _ in
                    withAnimation { proxy.scrollTo("liveBottom", anchor: .bottom) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 2 : Ajouter l'onglet « Direct » dans `MeetingSection`**

Dans `OneToOne/Views/MeetingView.swift`, enum `MeetingSection` (lignes 147-155), ajouter le case après `.liveNotes` :

```swift
        case liveTranscript = "Direct"
```

- [ ] **Step 3 : Router l'onglet dans `sectionContent`**

Dans `sectionContent` (lignes 511-528), ajouter un case :

```swift
        case .liveTranscript:
            LiveTranscriptPanel()
```

- [ ] **Step 4 : Démarrer/arrêter le service à l'enregistrement**

Repérer dans `MeetingView.swift` la fonction qui démarre l'enregistrement (celle qui appelle `recorder.start(meetingID:)`). Y insérer, **avant** l'appel `recorder.start`, la création du flux et le démarrage du live si activé :

```swift
        if settings.liveTranscriptionEnabled {
            let stream = recorder.makeAudioStream()
            Task {
                await LiveTranscriptionService.shared.begin(
                    audioStream: stream,
                    language: settings.sttLanguage,   // ⚠️ voir Step 4b : nom exact du réglage de langue
                    variant: settings.voxtralVariant)
            }
            activeSection = .liveTranscript
        }
```

- [ ] **Step 4b : Vérifier le nom exact du réglage de langue**

Le service `begin(...)` attend `language: String`. `TranscriptionService` expose déjà `self.language`. Vérifier la source exacte de la langue STT dans `AppSettings`/`TranscriptionService` (grep `self.language` dans `TranscriptionService.swift` et la clé correspondante dans `AppSettings.swift`) et remplacer `settings.sttLanguage` par le bon accès. Si aucune clé dédiée n'existe, passer `"fr"` (défaut de l'app francophone) — mais privilégier la clé existante.

- [ ] **Step 5 : Arrêter le service dans `stopRecordingAndTranscribe()`**

Dans `stopRecordingAndTranscribe()` (ligne 1261), **juste après** `guard let stopped = recorder.stop() else { return }` (ligne 1265), capturer les segments live (ils serviront en Task 8) :

```swift
        let liveSegments = settings.liveTranscriptionEnabled
            ? LiveTranscriptionService.shared.end()
            : []
```

(Le branchement de `liveSegments` dans la finalisation est fait en Task 8. Pour l'instant, ajouter cette ligne et ignorer `liveSegments` — préfixer `_ = liveSegments` en fin de fonction si le compilateur avertit d'une variable inutilisée.)

- [ ] **Step 6 : Gérer aussi `cancel`**

Repérer les endroits où `recorder.cancel()` est appelé dans `MeetingView.swift` et ajouter, à côté :

```swift
        _ = LiveTranscriptionService.shared.end()
```

- [ ] **Step 7 : Compiler**

Run: `swift build`
Expected: build réussit.

- [ ] **Step 8 : Vérification manuelle de bout en bout**

Run: `Scripts/bump-and-build.sh dev`
Dans l'app : Réglages → Reconnaissance vocale → activer « Transcription en direct ». Créer une réunion, démarrer l'enregistrement, parler plusieurs phrases distinctes.
Expected :
- L'onglet « Direct » s'ouvre, affiche « Chargement du modèle… » puis « En écoute… ».
- Au fil de la parole (latence 15-30 s), des phrases apparaissent et s'accumulent sans doublons visibles aux jointures de fenêtres.
- Arrêter → la transcription batch/diarisation se lance ensuite (comportement Task 8).
- Réglage désactivé → aucun onglet Direct, comportement identique à aujourd'hui.

- [ ] **Step 9 : Commit**

```bash
git add OneToOne/Views/Meeting/LiveTranscriptPanel.swift OneToOne/Views/MeetingView.swift
git commit -m "feat(live): panneau transcript en direct + démarrage/arrêt du service"
```

---

## Task 8 : Finalisation — texte live nettoyé + diarisation par timestamps

Quand le live était actif, on n'exécute **pas** une 2ᵉ passe STT. On nettoie le texte live (`collapseRepetitions`), on lance Pyannote **seul** pour obtenir les tours de locuteurs, on aligne chaque segment live au cluster dominant par recouvrement de timestamps, puis on réutilise le pipeline de persistance existant (`SpeakerMatcher` → `persistBlocks`).

**Files:**
- Create: `OneToOne/Services/Live/LiveDiarizationAligner.swift`
- Test: `Tests/LiveDiarizationAlignerTests.swift`
- Modify: `OneToOne/Services/TranscriptionService.swift` (nouvelle méthode publique `finalizeLiveTranscript`)
- Modify: `OneToOne/Views/MeetingView.swift` (`stopRecordingAndTranscribe` : brancher la finalisation live)

**Interfaces:**
- Consumes: `LiveSegment` (Task 6), `TurnMerger.DiarTurn`/`TurnMerger.Block`, `PyannoteDiarizer.shared.diarize(...)`, `SpeakerMatcher.match(...)`, `TranscriptionService.collapseRepetitions` (static, existant), `TranscriptionService.persistBlocks`/`canonicalizeBlocks` (existants, privés → à exposer via la nouvelle méthode).
- Produces:
  - `enum LiveDiarizationAligner`
  - `static func alignToBlocks(segments: [LiveSegment], turns: [TurnMerger.DiarTurn]) -> [TurnMerger.Block]`
  - `TranscriptionService.finalizeLiveTranscript(segments:audioURL:meeting:settings:in:onPhase:onProgress:) async throws -> STTResult`

- [ ] **Step 1 : Écrire les tests de l'aligneur (échec attendu)**

Créer `Tests/LiveDiarizationAlignerTests.swift` :

```swift
import Testing
@testable import OneToOne

struct LiveDiarizationAlignerTests {

    @Test func segmentTakesClusterWithMaxOverlap() {
        let segments = [
            LiveSegment(start: 0, end: 4, text: "bonjour"),
            LiveSegment(start: 5, end: 9, text: "ça va bien"),
        ]
        let turns = [
            TurnMerger.DiarTurn(startSec: 0, endSec: 4.5, clusterID: 0),
            TurnMerger.DiarTurn(startSec: 4.5, endSec: 10, clusterID: 1),
        ]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks.count == 2)
        #expect(blocks[0].speaker == 0)
        #expect(blocks[0].text == "bonjour")
        #expect(blocks[1].speaker == 1)
        #expect(blocks[1].text == "ça va bien")
    }

    @Test func segmentWithNoOverlapDefaultsToClusterZero() {
        let segments = [LiveSegment(start: 20, end: 24, text: "isolé")]
        let turns = [TurnMerger.DiarTurn(startSec: 0, endSec: 5, clusterID: 3)]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks.count == 1)
        #expect(blocks[0].speaker == 0)
    }

    @Test func emptyTurnsPutsEverythingOnClusterZero() {
        let segments = [LiveSegment(start: 0, end: 3, text: "a"), LiveSegment(start: 3, end: 6, text: "b")]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: [])
        #expect(blocks.allSatisfy { $0.speaker == 0 })
        #expect(blocks.count == 2)
    }

    @Test func preservesSegmentTextAndTimes() {
        let segments = [LiveSegment(start: 1, end: 2, text: "exact")]
        let turns = [TurnMerger.DiarTurn(startSec: 0, endSec: 3, clusterID: 7)]
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: segments, turns: turns)
        #expect(blocks[0].start == 1)
        #expect(blocks[0].end == 2)
        #expect(blocks[0].text == "exact")
        #expect(blocks[0].speaker == 7)
    }
}
```

- [ ] **Step 2 : Lancer → échec attendu**

Run: `swift test --filter LiveDiarizationAlignerTests`
Expected: FAIL — `cannot find 'LiveDiarizationAligner' in scope`.

- [ ] **Step 3 : Implémenter l'aligneur**

Créer `OneToOne/Services/Live/LiveDiarizationAligner.swift` :

```swift
import Foundation

/// Attribue chaque segment de transcription live au locuteur (clusterID) du
/// tour Pyannote avec lequel il partage le plus de temps. La diarisation étant
/// batch, cette attribution se fait après l'enregistrement, par recouvrement de
/// timestamps — sans réexécuter la STT.
enum LiveDiarizationAligner {

    static func alignToBlocks(segments: [LiveSegment],
                              turns: [TurnMerger.DiarTurn]) -> [TurnMerger.Block] {
        segments.map { seg in
            let speaker = dominantCluster(start: seg.start, end: seg.end, turns: turns)
            return TurnMerger.Block(speaker: speaker, start: seg.start, end: seg.end, text: seg.text)
        }
    }

    /// clusterID du tour de plus grand recouvrement ; 0 par défaut (aucun tour
    /// ne recouvre le segment, ou liste vide).
    private static func dominantCluster(start: Double, end: Double,
                                        turns: [TurnMerger.DiarTurn]) -> Int {
        var best = 0
        var bestOverlap = 0.0
        for t in turns {
            let overlap = min(end, t.endSec) - max(start, t.startSec)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = t.clusterID
            }
        }
        return best
    }
}
```

- [ ] **Step 4 : Lancer → succès attendu**

Run: `swift test --filter LiveDiarizationAlignerTests`
Expected: PASS (4 tests).

- [ ] **Step 5 : Commit de l'aligneur**

```bash
git add OneToOne/Services/Live/LiveDiarizationAligner.swift Tests/LiveDiarizationAlignerTests.swift
git commit -m "feat(live): LiveDiarizationAligner (attribution locuteurs par timestamps)"
```

- [ ] **Step 6 : Ajouter `finalizeLiveTranscript` dans `TranscriptionService`**

Dans `OneToOne/Services/TranscriptionService.swift`, ajouter cette méthode publique (à placer près de `runTranscription`, elle réutilise les helpers privés `canonicalizeBlocks`/`persistBlocks`/`deleteExistingSegments` déjà présents dans le fichier) :

```swift
    /// Finalise un transcript live (aucune 2ᵉ passe STT) : nettoyage anti-boucles
    /// du texte, diarisation Pyannote seule, attribution des locuteurs par
    /// recouvrement de timestamps, puis persistance via le chemin existant.
    func finalizeLiveTranscript(segments: [LiveSegment],
                                audioURL: URL,
                                meeting: Meeting,
                                settings: AppSettings,
                                in context: ModelContext,
                                onPhase: ((TranscriptionPhase) -> Void)? = nil,
                                onProgress: ((Double, String) -> Void)? = nil) async throws -> STTResult {
        // 1. Nettoyage anti-répétitions, segment par segment.
        let cleaned = segments.map {
            LiveSegment(start: $0.start, end: $0.end,
                        text: Self.collapseRepetitions($0.text))
        }

        // 2. Diarisation Pyannote seule (pas de STT). PyannoteDiarizer émet ses
        //    propres phases via `onPhase`/`onProgress` transmis ci-dessous.
        let diar: PyannoteDiarizer.DiarizeOutput
        do {
            diar = try await PyannoteDiarizer.shared.diarize(
                audioURL: audioURL,
                clusterThreshold: Float(settings.diarizationClusterThreshold),
                onPhase: onPhase, onProgress: onProgress)
        } catch {
            // Repli : pas de diarisation → tout sur locuteur 0, persistance anonyme.
            let blocks = LiveDiarizationAligner.alignToBlocks(segments: cleaned, turns: [])
            persistBlocks(blocks, assignments: [:], meeting: meeting, in: context)
            let text = blocks.map { $0.text }.joined(separator: "\n")
            return STTResult(text: text, language: self.language,
                             durationSeconds: cleaned.last?.end ?? 0, segments: [])
        }

        // 3. Attribution des locuteurs par timestamps.
        let blocks = LiveDiarizationAligner.alignToBlocks(segments: cleaned, turns: diar.turns)

        // 4. Matching collaborateurs + persistance (chemin existant).
        onPhase?(.matching)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: diar.perClusterEmbedding, meeting: meeting,
            in: context, settings: settings)
        let canonical = canonicalizeBlocks(blocks, assignments: assignments)
        persistBlocks(canonical, assignments: assignments, meeting: meeting, in: context)

        let text = canonical.map { $0.text }.joined(separator: "\n")
        var result = STTResult(text: text, language: self.language,
                               durationSeconds: diar.turns.last?.endSec ?? (cleaned.last?.end ?? 0),
                               segments: [])
        result.clusterEmbeddings = diar.perClusterEmbedding
        return result
    }
```

> **Vérifications à faire par l'implémenteur avant compilation :**
> - `canonicalizeBlocks(_:assignments:)` accepte `[TurnMerger.Block]` + `[Int: SpeakerMatcher.Assignment]` (signature vue dans `runTranscription`).
> - `persistBlocks(_:assignments:meeting:in:)` : signature identique à l'appel existant ligne 311. Dans la branche de repli, `persistBlocks(blocks, assignments: [:], …)` — annoter `[Int: SpeakerMatcher.Assignment]()` si l'inférence du dictionnaire vide échoue.
> - `PyannoteDiarizer.diarize` transmet `onPhase`/`onProgress` : ne pas émettre de phase inventée depuis `finalizeLiveTranscript`.

- [ ] **Step 7 : Brancher la finalisation live dans `stopRecordingAndTranscribe()`**

Dans `OneToOne/Views/MeetingView.swift`, `stopRecordingAndTranscribe()`. On a déjà `let liveSegments = …` (Task 7 Step 5). Dans le bloc `do { … }` qui appelle `stt.runTranscription(...)` (ligne ~1322), remplacer l'appel unique par un aiguillage :

```swift
            let result: STTResult
            if !liveSegments.isEmpty {
                result = try await stt.finalizeLiveTranscript(
                    segments: liveSegments,
                    audioURL: finalURL,
                    meeting: meeting,
                    settings: settings,
                    in: context,
                    onPhase: { phase in Task { @MainActor in self.transcriptionPhase = phase } },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                    }
                )
            } else {
                result = try await stt.runTranscription(
                    audioURL: finalURL,
                    meeting: meeting,
                    settings: settings,
                    in: context,
                    onPhase: { phase in Task { @MainActor in self.transcriptionPhase = phase } },
                    onProgress: { fraction, status in
                        Task { @MainActor in
                            self.transcriptionProgress = fraction
                            self.transcriptionProgressStatus = status
                        }
                    }
                )
            }
```

Le reste de la fonction (assignation `meeting.rawTranscript = result.text`, `mergedTranscript`, `activeSection = .transcript`, `saveContext()`) est inchangé et consomme `result`.

> **Cas append** : si `pendingAppendBaseURL` est non nil (append d'un enregistrement à un existant), les timestamps live ne couvrent que le nouveau segment, pas l'audio concaténé → **forcer le chemin batch**. Ajouter en tête d'aiguillage : `let useLive = !liveSegments.isEmpty && pendingAppendBaseURL == nil` et tester `useLive` au lieu de `!liveSegments.isEmpty`. (À ce point de la fonction `pendingAppendBaseURL` a déjà été remis à `nil` après la concat ; capturer sa valeur booléenne **avant** la concat, dans une variable `let wasAppend = pendingAppendBaseURL != nil`, et utiliser `!wasAppend`.)

- [ ] **Step 8 : Compiler**

Run: `swift build`
Expected: build réussit. Corriger les signatures selon les vérifications du Step 6 si nécessaire.

- [ ] **Step 9 : Tests unitaires complets**

Run: `swift test --skip CalendarImportEventTests`
Expected: PASS — dont `LiveTranscriptMergerTests`, `AudioLevelMeterTests`, `LiveDiarizationAlignerTests`.

- [ ] **Step 10 : Vérification manuelle de bout en bout**

Run: `Scripts/bump-and-build.sh dev`
Live activé : enregistrer un dialogue à deux voix (~1 min), arrêter.
Expected :
- Pendant : transcript live qui s'accumule (onglet Direct).
- Après `stop()` : phase de diarisation puis onglet Transcription rempli, **segments attribués à des locuteurs** (pas une seule voix), texte nettoyé (pas de « (×N — boucle) » parasite).
- Comparer grossièrement au texte live : le final doit couvrir le même contenu, mieux structuré par locuteur.
- Refaire avec live désactivé → pipeline batch complet inchangé.

- [ ] **Step 11 : Commit**

```bash
git add OneToOne/Services/TranscriptionService.swift OneToOne/Views/MeetingView.swift
git commit -m "feat(live): finalisation — texte live nettoyé + diarisation par timestamps"
```

---

## Récapitulatif des vérifications manuelles (app packagée)

Ces points ne sont pas couvrables par `swift test` (matériel micro, MLX/metallib, download HF) et **doivent** être vérifiés sur l'app packagée via `Scripts/bump-and-build.sh dev` :

1. **Task 3** — capture engine : WAV valide et lisible juste après stop, VU-mètre, pause/resume, changement de périphérique sans crash.
2. **Task 6/7** — live : chargement modèle, transcript qui s'accumule, dédup des jointures, latence acceptable.
3. **Task 8** — finalisation : diarisation post-stop, locuteurs attribués, texte nettoyé ; append et live-désactivé passent par le batch.
4. **Régression** — enregistrement avec live désactivé : comportement strictement identique à aujourd'hui.
5. **Permission micro** — première utilisation sur app packagée : la demande d'autorisation micro s'affiche (l'`inputNode` d'`AVAudioEngine` déclenche le même TCC que l'ancien recorder).
