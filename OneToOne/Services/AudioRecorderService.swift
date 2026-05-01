import Foundation
import AVFoundation
import Combine
import AppKit
import os

private let audioLog = Logger(subsystem: "com.onetoone.app", category: "audio")

// MARK: - AudioRecorderService

/// Enregistrement WAV (PCM 16-bit linéaire, 16 kHz mono) adapté à l'entrée
/// du modèle Cohere MLX utilisé pour la STT.
///
/// Fichiers persistés dans :
///   `~/Library/Application Support/OneToOne/recordings/<uuid>.wav`
///
/// Permissions : nécessite `NSMicrophoneUsageDescription` dans Info.plist et
/// autorisation utilisateur (demandée au premier record).
///
/// Cap durée : 3 h (configurable via `maxDurationSeconds`).
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {

    /// Singleton partagé : permet à l'enregistrement de survivre à la
    /// destruction de la `MeetingView` quand on navigue ailleurs (Actions,
    /// Collaborateur…). La même instance est récupérée au retour.
    static let shared = AudioRecorderService()

    // MARK: - Config

    /// Format cible STT : WAV PCM linéaire 16-bit 16 kHz mono.
    static let sampleRate: Double = 16_000
    static let channels: UInt32 = 1

    /// Cap dur par défaut : 3 heures.
    var maxDurationSeconds: TimeInterval = 3 * 60 * 60

    // MARK: - Published state

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var averagePower: Float = -160   // dB, pour VU-mètre
    @Published private(set) var peakPower: Float = -160      // dB
    @Published var lastError: String?
    /// Identifiant stable du meeting actuellement enregistré. Permet à
    /// `MeetingView` de savoir si l'enregistrement courant lui appartient.
    @Published private(set) var activeMeetingID: UUID?

    // MARK: - Internals

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var elapsedTimer: Timer?
    private var startDate: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartDate: Date?

    // MARK: - Permissions

    /// Demande l'autorisation micro. Retourne `true` si accordée.
    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Storage

    /// Concatène deux WAV PCM linéaires dans un nouveau fichier.
    /// Les deux fichiers doivent partager le même format audio (sample rate,
    /// nb de canaux). Utilisé pour ajouter un enregistrement supplémentaire
    /// à une réunion déjà enregistrée.
    static func concatenateWAVs(first: URL, second: URL, output: URL) throws {
        let f1 = try AVAudioFile(forReading: first)
        let f2 = try AVAudioFile(forReading: second)

        let outFile = try AVAudioFile(
            forWriting: output,
            settings: f1.fileFormat.settings,
            commonFormat: f1.processingFormat.commonFormat,
            interleaved: f1.processingFormat.isInterleaved
        )

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

    // MARK: - Lifecycle

    /// Démarre un nouvel enregistrement. Le fichier WAV est créé immédiatement.
    /// - Parameter meetingID: stable ID du meeting cible (sert à l'UI pour
    ///   savoir si l'enregistrement courant la concerne).
    /// - Returns: URL du WAV créé.
    @discardableResult
    func start(meetingID: UUID? = nil) async throws -> URL {
        guard !isRecording else { throw AudioError.alreadyRecording }

        let granted = await requestMicrophonePermission()
        guard granted else { throw AudioError.permissionDenied }

        let fileURL = Self.recordingsDirectory
            .appending(path: "\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: Self.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else {
                throw AudioError.prepareFailed
            }
            guard rec.record(forDuration: maxDurationSeconds) else {
                throw AudioError.startFailed
            }
            self.recorder = rec
            self.currentFileURL = fileURL
            self.isRecording = true
            self.isPaused = false
            self.elapsedSeconds = 0
            self.pausedAccumulated = 0
            self.pauseStartDate = nil
            self.startDate = Date()
            self.activeMeetingID = meetingID
            startTimers()
            audioLog.info("AudioRecorder: start \(fileURL.path, privacy: .public)")
            print("[Audio] start → \(fileURL.path)")
            return fileURL
        } catch {
            audioLog.error("AudioRecorder: start failed \(error.localizedDescription, privacy: .public)")
            throw AudioError.startFailed
        }
    }

    func pause() {
        guard isRecording, !isPaused, let rec = recorder else { return }
        rec.pause()
        isPaused = true
        pauseStartDate = Date()
        stopLevelTimer()
        audioLog.info("AudioRecorder: pause")
        print("[Audio] pause")
    }

    func resume() {
        guard isRecording, isPaused, let rec = recorder else { return }
        if let paused = pauseStartDate {
            pausedAccumulated += Date().timeIntervalSince(paused)
            pauseStartDate = nil
        }
        guard rec.record() else {
            lastError = "Reprise de l'enregistrement impossible."
            return
        }
        isPaused = false
        startLevelTimer()
        audioLog.info("AudioRecorder: resume")
        print("[Audio] resume")
    }

    /// Arrête l'enregistrement et retourne l'URL du WAV finalisé + durée.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let rec = recorder, let url = currentFileURL else { return nil }
        rec.stop()
        let duration = elapsedSeconds
        teardown()
        audioLog.info("AudioRecorder: stop duration=\(duration, format: .fixed(precision: 1), privacy: .public)s")
        print("[Audio] stop → \(duration)s → \(url.path)")
        return (url, duration)
    }

    /// Annule : arrête + supprime le fichier.
    func cancel() {
        guard let rec = recorder, let url = currentFileURL else {
            teardown()
            return
        }
        rec.stop()
        try? FileManager.default.removeItem(at: url)
        audioLog.info("AudioRecorder: cancel")
        print("[Audio] cancel (fichier supprimé)")
        teardown()
    }

    // MARK: - Private

    private func teardown() {
        recorder = nil
        currentFileURL = nil
        isRecording = false
        isPaused = false
        activeMeetingID = nil
        stopTimers()
        averagePower = -160
        peakPower = -160
    }

    private func startTimers() {
        startElapsedTimer()
        startLevelTimer()
    }

    private func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        stopLevelTimer()
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickLevels() }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate(); levelTimer = nil
    }

    private func tickElapsed() {
        guard let start = startDate else { return }
        let raw = Date().timeIntervalSince(start) - pausedAccumulated
        elapsedSeconds = max(0, raw)
        // Sécurité — l'AVAudioRecorder s'arrête déjà via `record(forDuration:)`.
        if elapsedSeconds >= maxDurationSeconds {
            _ = stop()
        }
    }

    private func tickLevels() {
        guard let rec = recorder, rec.isRecording else { return }
        rec.updateMeters()
        averagePower = rec.averagePower(forChannel: 0)
        peakPower = rec.peakPower(forChannel: 0)
    }
}

// MARK: - Errors

enum AudioError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case prepareFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accès au microphone refusé. Activer dans Réglages Système → Confidentialité → Microphone."
        case .alreadyRecording:
            return "Un enregistrement est déjà en cours."
        case .prepareFailed:
            return "Impossible de préparer l'enregistrement audio."
        case .startFailed:
            return "Impossible de démarrer l'enregistrement audio."
        }
    }
}

// MARK: - Delegate

extension AudioRecorderService: @preconcurrency AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            lastError = "Enregistrement interrompu."
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        lastError = error?.localizedDescription ?? "Erreur d'encodage audio."
    }
}
