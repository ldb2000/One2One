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
    nonisolated static let sampleRate: Double = 16_000
    nonisolated static let channels: UInt32 = 1
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

    /// Chronologie d'énergie des deux pistes, échantillonnée à chaque bloc.
    /// C'est elle qui conserve la provenance que le mixage effacerait
    /// (spec §6.1). Vidée à chaque nouveau démarrage — pas au `stop()` : c'est
    /// après l'enregistrement qu'on s'en sert pour attribuer les segments.
    ///
    /// **Pas `@Published`** : elle est réécrite ~12 fois par seconde sur un
    /// singleton observé par *toutes* les fenêtres réunion, alors que rien ne la
    /// lit pendant l'enregistrement — la publier invaliderait ces vues pour
    /// personne. Elle reste lisible (tests, et le consommateur à venir).
    private(set) var provenanceTimeline: [TrackEnergySample] = []

    /// Vrai quand la seconde piste a été demandée mais n'a pas pu démarrer.
    /// `MeetingView` en fait un bandeau d'erreur non bloquant ; l'enregistrement
    /// continue en micro seul.
    @Published private(set) var systemAudioUnavailable = false

    /// UID de l'entrée forcée sur l'engine, `nil` = défaut système. Sert au
    /// coordinateur pour savoir si un périphérique retiré était le nôtre.
    private(set) var currentInputUID: String?

    /// URLs des segments **clos** de l'enregistrement en cours (fallback par
    /// segment, spec D1). Le segment courant est `currentFileURL`.
    private var segmentURLs: [URL] = []

    /// Bascules d'entrée survenues pendant l'enregistrement, pour le rapport.
    /// Vidée au prochain `start()`, comme `provenanceTimeline`.
    private(set) var inputSwitches: [InputSwitchMark] = []

    /// Posé par `MeetingRecordingCoordinator` pendant qu'il surveille : la
    /// notification `AVAudioEngineConfigurationChange` lui est alors remise au
    /// lieu de stopper l'enregistrement. `nil` = comportement historique.
    var onInputInterrupted: (@MainActor () -> Void)?

    // MARK: - Propriété de l'enregistrement
    //
    // Le service est un singleton observé par **toutes** les fenêtres réunion :
    // conditionner un affichage sur `isRecording` seul le fait apparaître dans
    // toutes les fenêtres à la fois (vumètre, chrono…). Les vues doivent passer
    // par `isRecording(for:)`.

    /// Vrai si l'enregistrement en cours appartient à la réunion `meetingID`.
    func isRecording(for meetingID: UUID?) -> Bool {
        Self.isOwner(isRecording: isRecording, activeMeetingID: activeMeetingID, meetingID: meetingID)
    }

    /// Règle de propriété, isolée pour être testable. Un propriétaire inconnu
    /// (`activeMeetingID == nil`) n'est revendiqué par personne — mieux vaut
    /// n'afficher l'enregistrement nulle part que partout.
    nonisolated static func isOwner(isRecording: Bool, activeMeetingID: UUID?, meetingID: UUID?) -> Bool {
        guard isRecording, let activeMeetingID, let meetingID else { return false }
        return activeMeetingID == meetingID
    }

    /// Mode de capture effectif. Une permission d'écran absente **dégrade** la
    /// capture au micro seul ; elle n'empêche jamais d'enregistrer (spec D-6).
    nonisolated static func resolvedCaptureMode(requested: TeamsAudioCaptureMode,
                                                hasScreenPermission: Bool) -> TeamsAudioCaptureMode {
        guard requested == .microAndSystem, hasScreenPermission else { return .microOnly }
        return .microAndSystem
    }

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

    // MARK: - Internals (seconde piste)
    //
    // Choix d'exécuteur : la seconde piste est **rapatriée sur la file du
    // `TapSink`**, pas l'inverse. Les blocs micro sont convertis, écrits et
    // publiés de façon synchrone sur `com.onetoone.audio.write` ; les faire
    // sauter sur le main actor pour les mixer ajouterait un saut de contexte
    // par bloc au chemin classique et exposerait l'ordre des blocs à
    // l'ordonnancement des `Task`. Le tampon système, l'horodatage et le
    // mixage vivent donc dans le `TapSink` (une seule file série, un seul
    // point de publication) ; seule la chronologie de provenance remonte au
    // main actor, et uniquement quand la seconde piste est engagée.
    private var systemCapture: SystemAudioCapture?
    /// Début de l'enregistrement. Ne sert plus que de marqueur d'engagement de
    /// la seconde piste : les temps de `provenanceTimeline` sont comptés en
    /// échantillons publiés par le `TapSink` (cf. `publishedSampleCount`), la
    /// seule horloge que la pause fige comme le fait le flux lui-même.
    private var recordingStartedAt: Date?

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

    /// Format du fichier : PCM 16 bits, 16 kHz, mono. Partagé par le démarrage
    /// et par chaque rotation de segment — deux segments de formats différents
    /// ne se concatèneraient pas.
    nonisolated static let wavSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    /// Recolle les segments d'un enregistrement à bascules (spec D1). Un seul
    /// segment : rendu tel quel. Plusieurs : concaténés dans un nouveau fichier
    /// de `recordingsDirectory`, puis les segments sont supprimés — seulement
    /// si la fusion a réussi, pour qu'un échec ne perde jamais d'audio.
    nonisolated static func mergeSegments(_ urls: [URL]) throws -> URL {
        guard let premier = urls.first else { throw AudioError.startFailed }
        guard urls.count > 1 else { return premier }
        let output = recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
        do {
            try concatenateWAVs(urls, output: output)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        for url in urls { try? FileManager.default.removeItem(at: url) }
        return output
    }

    /// Concaténation de N fichiers de même format dans `output`.
    nonisolated static func concatenateWAVs(_ urls: [URL], output: URL) throws {
        guard let premier = urls.first else { throw AudioError.startFailed }
        let modele = try AVAudioFile(forReading: premier)
        let outFile = try AVAudioFile(
            forWriting: output,
            settings: modele.fileFormat.settings,
            commonFormat: modele.processingFormat.commonFormat,
            interleaved: modele.processingFormat.isInterleaved)
        for url in urls {
            let input = try AVAudioFile(forReading: url)
            try copyAudio(from: input, to: outFile)
        }
    }

    nonisolated static func concatenateWAVs(first: URL, second: URL, output: URL) throws {
        try concatenateWAVs([first, second], output: output)
    }

    private nonisolated static func copyAudio(from input: AVAudioFile, to output: AVAudioFile) throws {
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

    nonisolated static var recordingsDirectory: URL {
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

    /// Force l'entrée de l'engine sur `uid` (`nil` = l'entrée par défaut du
    /// système). Doit être appelée engine **arrêté**, avant de lire
    /// `inputNode.outputFormat(forBus:)` : le format dépend du périphérique.
    private func bindInput(uid: String?) throws {
        let deviceID: AudioDeviceID?
        if let uid { deviceID = AudioInputDeviceService.deviceID(forUID: uid) }
        else { deviceID = AudioInputDeviceService.defaultInputDeviceID() }
        guard var id = deviceID, let unit = engine.inputNode.audioUnit else {
            throw AudioError.inputUnavailable
        }
        let status = AudioUnitSetProperty(unit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            audioLog.error("AudioRecorder: bind input \(uid ?? "default", privacy: .public) failed \(status)")
            throw AudioError.inputUnavailable
        }
    }

    /// `captureMode` vaut `.microOnly` par défaut : l'enregistrement classique
    /// d'une réunion OneToOne est strictement inchangé. Seul le parcours Teams
    /// demande `.microAndSystem`.
    @discardableResult
    func start(meetingID: UUID? = nil,
               captureMode: TeamsAudioCaptureMode = .microOnly,
               inputUID: String? = nil) async throws -> URL {
        guard !isRecording else { throw AudioError.alreadyRecording }
        let granted = await requestMicrophonePermission()
        guard granted else { throw AudioError.permissionDenied }

        provenanceTimeline = []
        systemAudioUnavailable = false
        segmentURLs = []
        inputSwitches = []

        let fileURL = Self.recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
        let settings = Self.wavSettings

        do {
            // AVAudioFile Int16 sur disque ; processingFormat = Float32 16 kHz mono.
            let file = try AVAudioFile(forWriting: fileURL, settings: settings)
            let targetFormat = file.processingFormat
            // L'entrée est liée avant de lire le format : un iPhone en
            // Continuité tourne à 48 kHz, le micro intégré à 44,1 ou 48 kHz.
            try bindInput(uid: inputUID)
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioError.startFailed
            }
            // La chronologie est datée sur la file du sink, puis remontée ici.
            // L'ordre d'arrivée des `Task` n'est pas garanti, mais chaque
            // échantillon porte son propre `time` et `AudioTrackMixer.provenance`
            // filtre sur ce temps : un tableau non trié reste exploitable.
            let onProvenance: @Sendable (TrackEnergySample) -> Void = { [weak self] sample in
                Task { @MainActor in self?.appendProvenance(sample) }
            }
            let sink = TapSink(converter: conv, targetFormat: targetFormat,
                               file: file, continuation: streamContinuation,
                               onProvenance: onProvenance)
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
            currentInputUID = inputUID
            isPaused = false
            elapsedSeconds = 0
            pausedAccumulated = 0
            pauseStartDate = nil
            startDate = Date()
            // Même instant que l'horloge de durée : la chronologie de provenance
            // date depuis le démarrage du moteur audio, pas depuis la demande
            // d'enregistrement (0,1 à 0,5 s plus tôt, le temps de la permission
            // et de l'ouverture du fichier). Un décalage constant de cet ordre
            // fausserait l'attribution sur des fenêtres de dominance de 2 s.
            recordingStartedAt = startDate
            activeMeetingID = meetingID
            notifyRecordingStartedIfEnabled(meetingID: meetingID)
            startElapsedTimer()
            // Volontairement non attendu : `start()` ne doit plus se suspendre
            // une fois `isRecording` posé. L'armement de la capture système peut
            // durer (prompt ScreenCaptureKit la première fois) ; si un `stop()`
            // tombait dans cette fenêtre, `start()` rendrait quand même son URL
            // et `MeetingView` lancerait la transcription live sur un flux déjà
            // terminé — session bloquée (`isLive`) jusqu'au redémarrage de l'app.
            // La garde `isRecording, self.sink === sink` traite l'arrivée tardive.
            Task { await startSystemTrackIfRequested(captureMode, sink: sink) }
            audioLog.info("AudioRecorder(engine): start \(fileURL.path, privacy: .public)")
            return fileURL
        } catch {
            audioLog.error("AudioRecorder(engine): start failed \(error.localizedDescription, privacy: .public)")
            teardownEngine()
            try? FileManager.default.removeItem(at: fileURL)
            throw (error as? AudioError) ?? AudioError.startFailed
        }
    }

    // MARK: - Seconde piste (audio système)

    /// Arme la capture système quand le mode la demande **et** que la permission
    /// d'écran est déjà accordée. Toute défaillance dégrade vers le micro seul :
    /// on lève le drapeau du bandeau, jamais une erreur (spec D-6).
    private func startSystemTrackIfRequested(_ requested: TeamsAudioCaptureMode,
                                            sink: TapSink) async {
        let effective = Self.resolvedCaptureMode(
            requested: requested,
            hasScreenPermission: SystemAudioCapture.isPermissionGranted())
        guard effective == .microAndSystem else {
            // Demandée mais refusée faute de permission : bandeau, pas d'échec.
            // Rien n'est publié dans le cas `.microOnly`, pour que le chemin
            // classique n'émette pas de changement d'état superflu.
            if requested == .microAndSystem { systemAudioUnavailable = true }
            return
        }
        let capture = SystemAudioCapture()
        do {
            try await capture.start { [weak sink] samples in
                // Livré directement depuis la file `SCStream`, sans détour par
                // le main actor : un main thread bouchonné y transformait le
                // retard en décalage permanent (cf. `SampleHandlerBox`).
                // `appendSystemSamples` bascule aussitôt sur la file du sink,
                // seul endroit où l'on mixe — et ne bloque pas la file de
                // capture, comme l'exige le contrat du callback.
                sink?.appendSystemSamples(samples)
            }
            // Le démarrage du `SCStream` peut durer — la validation du prompt
            // système, la première fois. Si l'enregistrement s'est arrêté
            // entre-temps (ou qu'un autre a pris la main), on referme tout de
            // suite : un `SCStream` sans lecteur continuerait de capturer
            // l'écran, témoin allumé, jusqu'à l'arrêt de l'app.
            guard isRecording, self.sink === sink else {
                await capture.stop()
                return
            }
            systemCapture = capture
            // Engagée seulement après un démarrage réussi : sinon la
            // chronologie se remplirait d'une piste distante inexistante.
            sink.engageSystemTrack(startedAt: recordingStartedAt ?? Date())
        } catch {
            // Dégradation, pas échec : l'enregistrement micro continue.
            systemAudioUnavailable = true
            audioLog.error("AudioRecorder: audio systeme indisponible \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Point d'entrée main actor de la chronologie, alimenté depuis la file du
    /// `TapSink` (un saut par bloc, uniquement en double piste).
    private func appendProvenance(_ sample: TrackEnergySample) {
        provenanceTimeline.append(sample)
    }

    /// Arrête la capture système. Appelée depuis `resetState()` — donc par
    /// `stop()`, `cancel()` **et** l'échec de démarrage : un `SCStream` oublié
    /// continuerait d'enregistrer l'écran après la réunion.
    private func stopSystemTrack() {
        recordingStartedAt = nil
        guard let capture = systemCapture else { return }
        systemCapture = nil
        Task { await capture.stop() }   // `stop()` est idempotent
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

    // MARK: - Bascule d'entrée (fallback par segment, spec D1)

    /// Ferme le segment courant, en ouvre un nouveau sur `device` (`nil` =
    /// défaut système) et rouvre le tap sur le **même** `TapSink` : le flux live
    /// ne voit aucune coupure, seul le fichier est découpé. Une pause en cours
    /// est conservée (`setCapturing` reste faux). Si une étape échoue,
    /// l'enregistrement est arrêté proprement (`stopForInputLoss`) avant de
    /// relancer l'erreur : le recorder ne reste jamais moteur arrêté avec
    /// `isRecording` vrai.
    func switchInput(to device: AudioInputDevice?) throws {
        guard isRecording, let sink else { return }
        do {
            let node = engine.inputNode
            node.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
            try bindInput(uid: device?.uid)
            let inputFormat = node.outputFormat(forBus: 0)
            guard let conv = AVAudioConverter(from: inputFormat, to: sink.targetFormat) else {
                throw AudioError.startFailed
            }
            let url = Self.recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
            let file = try AVAudioFile(forWriting: url, settings: Self.wavSettings)
            if let clos = currentFileURL { segmentURLs.append(clos) }
            sink.rotate(file: file, converter: conv)
            currentFileURL = url
            node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let samples = sink.process(buffer) else { return }
                Task { @MainActor [weak self] in self?.publishMetersThrottled(from: samples) }
            }
            engine.prepare()
            try engine.start()
            currentInputUID = device?.uid
            inputSwitches.append(InputSwitchMark(time: elapsedSeconds,
                                                 deviceName: device?.name ?? "Entrée par défaut"))
            audioLog.info("AudioRecorder(engine): switch input → \(device?.name ?? "default", privacy: .public) segment=\(url.lastPathComponent, privacy: .public)")
        } catch {
            stopForInputLoss()
            throw error
        }
    }

    /// Arrêt quand plus aucune entrée n'existe : le message historique, et le
    /// nettoyage de la session live que `MeetingView` ne fera pas (ce chemin ne
    /// passe pas par elle).
    func stopForInputLoss() {
        guard isRecording else { return }
        lastError = "Périphérique audio modifié — enregistrement interrompu. Vérifie l'entrée micro."
        audioLog.error("AudioRecorder(engine): input lost → stop")
        _ = stop()
        LiveTranscriptionService.shared.abort()
    }

    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let url = currentFileURL else { return nil }
        let duration = elapsedSeconds
        let segments = segmentURLs + [url]
        finalizeAndTeardown()
        // `finalizeAndTeardown` a clos le dernier fichier (`sink.finish()`), les
        // précédents l'ont été à chaque `rotate` : tout est relisible ici.
        let finalURL: URL
        do { finalURL = try Self.mergeSegments(segments) }
        catch {
            audioLog.error("AudioRecorder(engine): merge segments failed \(error.localizedDescription, privacy: .public) — dernier segment conservé")
            finalURL = url
        }
        audioLog.info("AudioRecorder(engine): stop duration=\(duration, format: .fixed(precision: 1), privacy: .public)s segments=\(segments.count, privacy: .public)")
        return (finalURL, duration)
    }

    func cancel() {
        guard isRecording else { resetState(); return }
        let url = currentFileURL
        let segments = segmentURLs + [url].compactMap { $0 }
        finalizeAndTeardown()
        for segment in segments {
            try? FileManager.default.removeItem(at: segment)
        }
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
            if let onInputInterrupted {
                // Le coordinateur surveille : c'est lui qui rebranche ou arrête.
                audioLog.info("AudioRecorder(engine): configuration change → coordinateur")
                onInputInterrupted()
                return
            }
            // Comportement historique, sans coordinateur.
            self.stopForInputLoss()
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
        stopSystemTrack()
        // `provenanceTimeline` survit à l'arrêt : c'est après l'enregistrement
        // qu'on attribue les segments transcrits. Elle n'est vidée qu'au
        // prochain `start()`.
        currentFileURL = nil
        segmentURLs = []
        currentInputUID = nil
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

/// Cœur de la capture, hors main actor. Reçoit les buffers du tap
/// `AVAudioEngine` **et** les blocs de la seconde piste (audio système), et
/// possède toute la chaîne :
///
/// 1. conversion des buffers micro en Float32 16 kHz mono ;
/// 2. tampon des échantillons système en attente du prochain bloc micro ;
/// 3. mixage des deux pistes quand la seconde est engagée ;
/// 4. écriture du WAV — le fichier reçoit exactement ce qui est publié ;
/// 5. horodatage de la provenance sur l'horloge du flux (échantillons publiés) ;
/// 6. diffusion sur le flux live consommé par `LiveTranscriptionService`.
///
/// Le tout est sérialisé sur une file dédiée : un seul point d'écriture, un seul
/// point de publication, donc aucun entrelacement possible entre les deux
/// pistes. `@unchecked Sendable` : tout l'état mutable est protégé par `queue`.
/// La `continuation` d'`AsyncStream` est Sendable et peut être appelée depuis
/// n'importe quel thread.
final class TapSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.onetoone.audio.write")
    /// `var` : remplacé à chaque rotation de segment, sous `queue`.
    private var converter: AVAudioConverter
    let targetFormat: AVAudioFormat
    private var file: AVAudioFile?
    private let continuation: AsyncStream<[Float]>.Continuation?
    /// Remonte l'énergie des deux pistes au service (main actor), un appel par
    /// bloc publié. `nil` quand personne n'écoute.
    private let onProvenance: (@Sendable (TrackEnergySample) -> Void)?
    private var capturing = true
    /// Origine des temps de la chronologie, posée quand la seconde piste est
    /// engagée. `nil` = enregistrement classique, une seule piste : le sink ne
    /// mixe rien et ne date rien.
    private var systemTrackStartedAt: Date?
    /// Échantillons système reçus depuis le dernier bloc micro publié, en
    /// attente d'être mixés avec le prochain. Prélevé bloc à bloc, jamais vidé
    /// d'un coup : le flux publié reste calé sur l'horloge micro.
    private var pendingSystemSamples: [Float] = []
    /// Le plafond du reliquat n'est signalé qu'une fois : il se déclenche à
    /// chaque bloc tant que la dérive dure, et noierait le journal.
    private var didReportPendingOverflow = false
    /// Horloge du flux : nombre d'échantillons déjà publiés. C'est *exactement*
    /// celle que compte `LiveVADSegmenter` pour dater ses segments, et la pause
    /// la fige comme elle fige le flux (aucun bloc n'est publié). Une horloge
    /// murale, elle, continuerait de tourner : après la moindre pause — un clic
    /// — toute la chronologie de provenance serait décalée de la durée mise en
    /// pause, et l'attribution tomberait à côté jusqu'à la fin.
    private var publishedSampleCount = 0

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat,
         file: AVAudioFile, continuation: AsyncStream<[Float]>.Continuation?,
         onProvenance: (@Sendable (TrackEnergySample) -> Void)? = nil) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.file = file
        self.continuation = continuation
        self.onProvenance = onProvenance
    }

    func setCapturing(_ on: Bool) { queue.sync { capturing = on } }

    /// Engage la seconde piste : à partir de là, chaque bloc publié est mixé et
    /// sa provenance datée sur l'horloge du flux. `startedAt` ne sert plus qu'à
    /// marquer l'engagement (« la seconde piste tourne ») ; il ne date rien.
    /// Appelée une fois, au démarrage réussi de la capture système.
    func engageSystemTrack(startedAt: Date) { queue.sync { systemTrackStartedAt = startedAt } }

    /// Vide ce que le convertisseur retient encore (amorce du resampler, ~70 ms
    /// à 48 → 16 kHz) dans le segment qui se ferme : sans cela chaque bascule
    /// d'entrée perdrait une syllabe. Le convertisseur est finalisé par
    /// `.endOfStream`, ce qui est sans conséquence : il est remplacé juste après.
    /// Drainé même en pause (pas de `guard capturing`, à la différence de
    /// `process()`) : l'amorce a été captée **avant** la pause, la perdre serait
    /// incorrect ; en double piste, `publish` la mixera avec le reliquat système
    /// du moment (vidé par la pause, donc silence), ce qui reste correct.
    /// Boucle jusqu'à `.endOfStream` (ou `.error`) : un seul appel à `convert`
    /// ne garantit pas de vider toute l'amorce en un buffer ; `tours` est un
    /// garde-fou (8 × 8 192 frames, largement au-delà de toute amorce possible)
    /// au cas où le convertisseur ne signalerait jamais la fin.
    private func drainConverter() {
        var tours = 0
        while tours < 8 {
            tours += 1
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 8192) else { return }
            var err: NSError?
            let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            guard err == nil, status != .error, outBuf.frameLength > 0,
                  let ptr = outBuf.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
            publish(micSamples: samples, converted: outBuf)
            if status == .endOfStream { return }
        }
    }

    /// Change de fichier et de convertisseur **sans** toucher à la continuation
    /// ni à l'horloge du flux : c'est le cœur du fallback par segment (spec D1).
    /// L'amorce encore détenue par l'ancien convertisseur est d'abord vidée et
    /// publiée dans le segment qui se ferme (`drainConverter`), puis l'ancien
    /// `AVAudioFile` est relâché, ce qui finalise son en-tête WAV ;
    /// `publishedSampleCount` continue de courir sans interruption.
    func rotate(file: AVAudioFile, converter: AVAudioConverter) {
        queue.sync {
            drainConverter()
            self.file = file
            self.converter = converter
        }
    }

    /// Dépose des échantillons système dans le tampon du prochain bloc micro.
    /// `async` et non `sync` : appelée pour chaque buffer capturé, directement
    /// depuis la file de `SCStream`, la bloquer sur une file qui écrit un
    /// fichier ferait décrocher la capture. L'ordre est préservé — une seule
    /// file émettrice, une seule file réceptrice. Ce qui arrive avant
    /// l'engagement est jeté plutôt que retenu : aucun tampon ne doit pouvoir
    /// grossir sans jamais être drainé.
    func appendSystemSamples(_ samples: [Float]) {
        queue.async {
            guard self.systemTrackStartedAt != nil else { return }
            self.pendingSystemSamples.append(contentsOf: samples)
        }
    }

    /// Convertit, écrit le WAV et diffuse. Renvoie les samples convertis pour le
    /// calcul des meters, ou `nil` si en pause / erreur de conversion.
    func process(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        queue.sync {
            guard capturing else {
                // En pause on ne retient rien : le bloc micro est ignoré, et
                // sans ce vidage le tampon système grossirait toute la pause.
                pendingSystemSamples.removeAll(keepingCapacity: true)
                return nil
            }
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
            let samples = Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
            publish(micSamples: samples, converted: outBuf)
            // Les meters restent un niveau **d'entrée micro** : le vumètre dit
            // ce que capte le micro, pas ce que contient le mixage.
            return samples
        }
    }

    /// Écrit le bloc dans le WAV **et** le publie dans le flux unique consommé
    /// par `LiveTranscriptionService` — le fichier et le flux reçoivent
    /// exactement la même donnée. En double piste, le bloc micro est mixé avec
    /// un prélèvement d'audio système de sa propre taille : le flux publié et le
    /// fichier restent verrouillés sur l'horloge micro, seule horloge dont
    /// `LiveVADSegmenter` déduit ses horodatages (il compte les échantillons).
    /// Toujours appelée depuis `queue`, jamais ailleurs : c'est l'unique point
    /// d'écriture et de publication.
    private func publish(micSamples: [Float], converted: AVAudioPCMBuffer) {
        // Instant du début de ce bloc dans l'horloge du flux, lu avant de la
        // faire avancer (cf. `publishedSampleCount`).
        let blockStart = Double(publishedSampleCount) / AudioRecorderService.sampleRate
        guard systemTrackStartedAt != nil else {
            // Enregistrement classique : le buffer converti part au fichier tel
            // quel et les échantillons au flux — donnée et ordre inchangés.
            try? file?.write(from: converted)
            continuation?.yield(micSamples)
            publishedSampleCount += micSamples.count
            return
        }
        let pendingBefore = pendingSystemSamples.count
        let systemSamples = AudioTrackMixer.takeAligned(from: &pendingSystemSamples,
                                                        count: micSamples.count)
        let dropped = pendingBefore - systemSamples.count - pendingSystemSamples.count
        if dropped > 0, !didReportPendingOverflow {
            didReportPendingOverflow = true
            audioLog.error("AudioRecorder: reliquat audio systeme plafonne, \(dropped, privacy: .public) echantillons jetes (derive d'horloge)")
        }
        onProvenance?(TrackEnergySample(
            time: blockStart,
            micEnergy: AudioTrackMixer.rms(micSamples),
            systemEnergy: AudioTrackMixer.rms(systemSamples)))
        // `mix` rend la piste micro telle quelle quand l'autre est vide, et
        // complète de silence un prélèvement plus court : la sortie fait
        // toujours exactement la taille du bloc micro.
        let mixed = AudioTrackMixer.mix(mic: micSamples, system: systemSamples)
        writeToFile(mixed)
        continuation?.yield(mixed)
        publishedSampleCount += mixed.count
    }

    /// Recompose un buffer dans le format du fichier (Float32 mono 16 kHz,
    /// `processingFormat` du WAV) pour y écrire le mixage. Sans cela le fichier
    /// ne contiendrait que le micro, et toute retranscription ultérieure
    /// perdrait la voix distante.
    private func writeToFile(_ samples: [Float]) {
        guard let file, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel.update(from: base, count: samples.count) }
        }
        try? file.write(from: buffer)
    }

    /// Ferme le fichier (finalise le header WAV) et termine le flux live.
    func finish() {
        queue.sync {
            file = nil
            systemTrackStartedAt = nil
            pendingSystemSamples = []
            didReportPendingOverflow = false
            publishedSampleCount = 0
        }
        continuation?.finish()
    }
}

// MARK: - Errors

/// Une bascule d'entrée, datée sur l'horloge de l'enregistrement.
struct InputSwitchMark: Equatable, Sendable {
    let time: TimeInterval
    let deviceName: String
}

enum AudioError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case startFailed
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accès au microphone refusé. Activer dans Réglages Système → Confidentialité → Microphone."
        case .alreadyRecording:
            return "Un enregistrement est déjà en cours."
        case .startFailed:
            return "Impossible de démarrer l'enregistrement audio."
        case .inputUnavailable:
            return "L'entrée audio choisie n'est pas disponible."
        }
    }
}
