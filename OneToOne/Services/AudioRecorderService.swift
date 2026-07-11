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
        streamContinuation?.finish()  // Termine l'ancienne continuation si elle existe
        return AsyncStream { continuation in
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
            try? FileManager.default.removeItem(at: fileURL)
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
        guard isRecording else { resetState(); return }
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
            // Ce chemin (notification système) contourne MeetingView, donc
            // LiveTranscriptionService.end()/abort() ne sont jamais appelés côté UI.
            // Sans ce nettoyage, une session live reste bloquée (isLive=true, modèle
            // Voxtral résident, consumeTask non annulée) et begin() ressort ensuite en
            // silence (guard !isLive) : la transcription live est morte jusqu'au
            // redémarrage de l'app. abort() est idempotent (no-op si aucune session
            // n'était active), d'où ce couplage assumé entre les deux singletons
            // @MainActor du module pour nettoyer la session live à la source.
            LiveTranscriptionService.shared.abort()
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
final class TapSink: @unchecked Sendable {
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
            // `.noDataNow` (et non `.endOfStream`) une fois le buffer fourni : le
            // converter est réutilisé buffer après buffer sur toute la session. Or
            // `.endOfStream` le FINALISE définitivement — après le 1er buffer, tous
            // les `convert` suivants renvoient 0 frame (→ `process` = nil, WAV figé à
            // ~0,1 s). `.noDataNow` signale « plus rien pour l'instant » sans clore le
            // flux : l'état interne du resampler est conservé pour l'appel suivant.
            _ = converter.convert(to: outBuf, error: &err) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
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
