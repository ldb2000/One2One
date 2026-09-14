import AVFoundation
import Foundation
import os

private let coordLog = Logger(subsystem: "com.onetoone.app", category: "recording-coordinator")

/// Ce que le coordinateur demande au recorder. `AudioRecorderService` s'y
/// conforme ; les tests passent un double.
@MainActor
protocol RecordingInputSwitching: AnyObject {
    var isRecording: Bool { get }
    var currentInputUID: String? { get }
    var onInputInterrupted: (@MainActor () -> Void)? { get set }
    func switchInput(to device: AudioInputDevice?) throws
    func stopForInputLoss()
}

/// Les deux notifications de séance (spec §4.6, décision D4).
@MainActor
protocol RecordingNotifying: AnyObject {
    func notifyAudioInputFallback(deviceName: String)
    func notifyTeamsFlowMissing()
}

enum MicrophonePermissionStatus: Sendable {
    case granted
    case denied
    case undetermined
}

/// Ce que `MeetingView` passe à `AudioRecorderService.start`.
struct RecordingStartPlan: Equatable, Sendable {
    let inputUID: String?
    let captureMode: TeamsAudioCaptureMode
}

enum RecordingStartOutcome: Equatable, Sendable {
    case proceed(RecordingStartPlan)
    /// Une feuille est affichée ; `MeetingView` rappellera `prepareStart` avec
    /// `chosenUID` au choix de l'utilisateur.
    case awaitingUserChoice
    /// Rien ne démarre : autorisation refusée (la feuille d'aide est posée) ou
    /// aucune entrée (l'appelant affiche `AudioError.inputUnavailable`).
    case blocked
}

/// Porte la **décision** de démarrage d'un enregistrement (quelle entrée, quel
/// mode, quelle feuille) et la **surveillance** des entrées en séance (spec
/// §4.4). Le câblage recorder / transcription live / playhead reste dans
/// `MeetingView`. Un coordinateur par fenêtre de réunion.
@MainActor
final class MeetingRecordingCoordinator {

    private let devices: any AudioInputDeviceProviding
    private let recorder: any RecordingInputSwitching
    private let notifier: any RecordingNotifying
    private let isTeamsRunning: @MainActor () -> Bool
    private let hasScreenPermission: @MainActor () -> Bool
    private let microphonePermission: @MainActor () async -> MicrophonePermissionStatus
    /// Durée pendant laquelle les changements de configuration de l'engine sont
    /// ignorés après une bascule. Injectable pour les tests seulement.
    private let interruptionSuppression: TimeInterval

    /// Vrai depuis le dernier démarrage où Teams était fermé : `MeetingView`
    /// s'en sert pour **ne pas** afficher le bandeau « permission écran », qui
    /// parlerait d'autre chose (spec §4.4, point 3).
    private(set) var teamsFlowMissing = false

    // `nonisolated(unsafe)` : seule `deinit` (nonisolated sur une classe
    // `@MainActor`) y accède hors du main actor, et uniquement pour annuler —
    // `Task.cancel()` est thread-safe.
    nonisolated(unsafe) private var monitoringTask: Task<Void, Never>?

    /// Vrai le temps d'une bascule. Une seule déconnexion produit deux signaux
    /// — l'événement CoreAudio de liste de périphériques et
    /// `AVAudioEngineConfigurationChange` — qui arrivent dans un ordre non
    /// garanti : sans ce verrou, le second rouvre un segment de plus et
    /// creuse un second trou de capture pour le même débranchement.
    private var isSwitching = false
    /// Les changements de configuration reçus avant cette date sont ignorés :
    /// c'est la bascule elle-même (arrêt de l'engine, pose du périphérique,
    /// redémarrage) qui les provoque. Sans cette fenêtre, chaque bascule peut
    /// en déclencher une autre — un WAV de plus à chaque tour.
    private var suppressInterruptionsUntil: Date = .distantPast

    init(devices: any AudioInputDeviceProviding,
         recorder: any RecordingInputSwitching,
         notifier: any RecordingNotifying,
         isTeamsRunning: @escaping @MainActor () -> Bool,
         hasScreenPermission: @escaping @MainActor () -> Bool,
         microphonePermission: @escaping @MainActor () async -> MicrophonePermissionStatus,
         interruptionSuppression: TimeInterval = 1.0) {
        self.devices = devices
        self.recorder = recorder
        self.notifier = notifier
        self.isTeamsRunning = isTeamsRunning
        self.hasScreenPermission = hasScreenPermission
        self.microphonePermission = microphonePermission
        self.interruptionSuppression = interruptionSuppression
    }

    deinit {
        // Le coordinateur meurt avec sa fenêtre : sans cette annulation la
        // tâche de surveillance garderait une continuation enregistrée dans
        // `AudioInputDeviceService` jusqu'au prochain événement. Le crochet du
        // recorder (`onInputInterrupted`) capture `self` faiblement et devient
        // un no-op ; `endMonitoring()` reste le chemin nominal depuis la vue.
        monitoringTask?.cancel()
    }

    /// Le coordinateur de production, sur les singletons.
    static func makeLive() -> MeetingRecordingCoordinator {
        MeetingRecordingCoordinator(
            devices: AudioInputDeviceService.shared,
            recorder: AudioRecorderService.shared,
            notifier: MeetingNotificationService.shared,
            isTeamsRunning: { TeamsCallMonitor.isTeamsRunning() },
            hasScreenPermission: { SystemAudioCapture.isPermissionGranted() },
            microphonePermission: {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: return .granted
                case .notDetermined: return .undetermined
                case .denied, .restricted: return .denied
                @unknown default: return .denied
                }
            })
    }

    // MARK: - Démarrage

    /// Applique dans l'ordre : permission micro, choix de l'entrée, mode de
    /// capture. `chosenUID` est le choix fait dans la feuille : il court-
    /// circuite la règle sans modifier le réglage préféré (D2).
    func prepareStart(preferredUID: String,
                      chosenUID: String?,
                      hasTeamsLink: Bool,
                      requestedMode: TeamsAudioCaptureMode,
                      screen: MeetingScreenModel) async -> RecordingStartOutcome {
        teamsFlowMissing = false

        // 1. Permission micro. `.undetermined` laisse `AudioRecorderService.start`
        //    déclencher la demande système, comme aujourd'hui.
        if await microphonePermission() == .denied {
            screen.recordingPrompts.permissionHelp = .microphone
            return .blocked
        }

        // 2. Entrée audio.
        devices.refresh()
        let inputUID: String?
        if let chosenUID {
            inputUID = chosenUID
        } else {
            switch AudioInputRouting.resolveStart(preferredUID: preferredUID, devices: devices.devices) {
            case .use(let uid):
                inputUID = uid
            case .askUser(let candidates, let missing):
                screen.recordingPrompts.audioInputChoice = AudioInputChoiceRequest(
                    missingPreferredUID: missing, candidates: candidates)
                return .awaitingUserChoice
            case .noInput:
                return .blocked
            }
        }

        // 3. Mode de capture. Une permission écran absente est laissée au
        //    recorder (bandeau jaune, spec D-6) ; Teams fermé est tranché ici (D3).
        var captureMode: TeamsAudioCaptureMode = hasTeamsLink ? requestedMode : .microOnly
        if captureMode == .microAndSystem, hasScreenPermission(), !isTeamsRunning() {
            teamsFlowMissing = true
            notifier.notifyTeamsFlowMissing()
            captureMode = .microOnly
        }

        return .proceed(RecordingStartPlan(inputUID: inputUID, captureMode: captureMode))
    }

    // MARK: - Surveillance

    /// À appeler dès que `AudioRecorderService.start` a réussi. Pose le crochet
    /// d'interruption du recorder et consomme les événements du fournisseur.
    func beginMonitoring() {
        endMonitoring()
        recorder.onInputInterrupted = { [weak self] in self?.handleInterruption() }
        let stream = devices.events()
        monitoringTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .removed(let uid) = event { self.handleRemoval(uid: uid) }
            }
        }
    }

    func endMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        recorder.onInputInterrupted = nil
    }

    /// Un périphérique a disparu. Interne (pas `private`) pour être appelée
    /// directement par les tests, sans passer par le flux.
    func handleRemoval(uid: String) {
        guard recorder.isRecording, !isSwitching else { return }
        let verdict = AudioInputRouting.fallback(removedUID: uid,
                                                 currentUID: recorder.currentInputUID,
                                                 devices: devices.devices)
        switch verdict {
        case .ignore:
            return
        case .stopRecording:
            coordLog.error("Entrée \(uid, privacy: .public) retirée, aucune autre entrée → arrêt")
            recorder.stopForInputLoss()
        case .switchTo(let device):
            isSwitching = true
            defer { isSwitching = false }
            do {
                try recorder.switchInput(to: device)
                suppressInterruptionsUntil = Date().addingTimeInterval(interruptionSuppression)
                notifier.notifyAudioInputFallback(deviceName: device.name)
                coordLog.info("Bascule sur \(device.name, privacy: .public)")
            } catch {
                coordLog.error("Bascule échouée \(error.localizedDescription, privacy: .public) → arrêt")
                recorder.stopForInputLoss()
            }
        }
    }

    /// L'engine signale un changement de configuration. Deux cas : l'entrée en
    /// cours a disparu (la liste ne la contient plus) → même chemin que le
    /// retrait ; elle est toujours là (changement de fréquence, reroutage du
    /// défaut) → on la rebranche en silence, nouveau segment, aucune notification.
    func handleInterruption() {
        guard recorder.isRecording, !isSwitching else { return }
        // La bascule elle-même provoque des changements de configuration : on
        // ignore l'écho pendant une seconde. Un vrai second retrait passe, lui,
        // par `handleRemoval`, que cette fenêtre ne bâillonne pas.
        guard Date() >= suppressInterruptionsUntil else { return }
        devices.refresh()
        if let current = recorder.currentInputUID,
           !devices.devices.contains(where: { $0.uid == current }) {
            handleRemoval(uid: current)
            return
        }
        let same = recorder.currentInputUID.flatMap { uid in devices.devices.first { $0.uid == uid } }
        isSwitching = true
        defer { isSwitching = false }
        do {
            try recorder.switchInput(to: same)
            suppressInterruptionsUntil = Date().addingTimeInterval(interruptionSuppression)
            coordLog.info("Interruption engine, rebranchement sur \(same?.name ?? "défaut système", privacy: .public)")
        } catch {
            coordLog.error("Rebranchement échoué \(error.localizedDescription, privacy: .public) → arrêt")
            recorder.stopForInputLoss()
        }
    }
}

// MARK: - Conformances de production

extension AudioRecorderService: RecordingInputSwitching {}
extension MeetingNotificationService: RecordingNotifying {}
