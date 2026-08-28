import AppKit
import Foundation
import SwiftData
import os

private let coordLog = Logger(subsystem: "com.onetoone.app", category: "teams-autorecord")

/// Orchestre le parcours auto-record : reçoit les trois déclencheurs de §3,
/// avance la machine à états pure de `TeamsAutoRecordState`, applique les
/// effets. Seul fichier du chantier à connaître à la fois SwiftData, les
/// notifications et le routeur de fenêtres.
///
/// Le coordinateur ne possède **pas** le pipeline d'enregistrement : arrêt,
/// transcription et rapport vivent dans `MeetingView`. Il le sollicite par
/// des `MeetingRequest`, et la fenêtre lui rend compte par
/// `transcriptionDidFinish`, `reportDidFinish` et `meetingWasDeleted`.
@MainActor
final class TeamsAutoRecordCoordinator {

    static let shared = TeamsAutoRecordCoordinator()

    /// Ce que le coordinateur demande à la fenêtre de réunion.
    enum MeetingRequest: Equatable {
        case startRecording
        case stopAndFinalize
        case generateReport
    }

    /// Ce que le coordinateur émet vers l'extérieur. Passer par une valeur
    /// plutôt que par des appels directs rend le parcours testable sans
    /// `UNUserNotificationCenter`, qui plante hors bundle applicatif.
    enum Outbound: Equatable {
        case detectedPopup(eventTitle: String)
        case endedPopup(meetingID: UUID)
        case transcriptReadyPopup(segmentCount: Int, meetingID: UUID, reportAvailable: Bool)
        case linkProposalPopup(eventTitle: String, meetingID: UUID)
        case sttErrorPopup(meetingID: UUID)
        case reportFailedPopup(meetingID: UUID)
        case openWindow(meetingID: UUID, autoStartRecording: Bool)
        case menuBarRecording(Bool)
    }

    /// Posted quand une demande est déposée pour une réunion ; `userInfo`
    /// porte `meetingID` (UUID string). Une fenêtre montée la consomme via
    /// `consumePendingRequest(for:)` ; une fenêtre qui s'ouvre ensuite la
    /// consomme à son `onAppear`.
    static let meetingRequestNotification = Notification.Name("OneToOne.TeamsAutoRecordCoordinator.meetingRequest")

    /// Phase courante — en mémoire, jamais persistée (spec §5).
    private(set) var phase: TeamsAutoRecordPhase = .idle

    /// Livraison des effets externes. Les tests la remplacent par un
    /// enregistreur.
    var deliver: @MainActor (Outbound) -> Void = TeamsAutoRecordCoordinator.deliverToSystem

    /// Événement d'agenda du parcours en cours, et réunion créée pour lui.
    private var currentEvent: CalendarMeetingEvent?
    private var currentMeetingID: UUID?
    /// Événement d'un second appel détecté pendant l'enregistrement, proposé à
    /// la liaison plutôt qu'à la création d'une seconde réunion (spec D-10).
    private var linkCandidateEvent: CalendarMeetingEvent?
    /// Empêche de re-proposer le même appel après un refus ou un parcours
    /// complet (spec §3).
    private var lastHandledEventID: String?
    /// Vrai entre `.meetingDeleted` et le retour au repos : la fenêtre
    /// n'existe plus, on ne lui demande rien.
    private var meetingIsGone = false
    private var pendingRequest: (meetingID: UUID, request: MeetingRequest)?

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var snoozeTask: Task<Void, Never>?
    private var clockTimer: Timer?

    /// Cadence de réévaluation de l'agenda pour le déclencheur 3.
    private static let clockInterval: TimeInterval = 30

    private init() {}

    // MARK: - Cycle de vie

    /// Branche les trois déclencheurs et les retours d'action de notification.
    func start(container: ModelContainer) {
        // Un second appel peut légitimement rafraîchir la référence au
        // conteneur ; les observateurs et l'horloge, eux, ne doivent pas
        // doubler.
        self.container = container
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default

        // Déclencheur 1 : surveillance locale de Teams.
        observers.append(nc.addObserver(
            forName: TeamsCallMonitor.callStartedNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetection() }
            })
        observers.append(nc.addObserver(
            forName: TeamsCallMonitor.callEndedNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handle(.callEnded) }
            })
        // Déclencheur 2 : l'utilisateur a explicitement rejoint depuis OneToOne.
        observers.append(nc.addObserver(
            forName: TeamsLauncher.didJoinNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetection() }
            })
        // Déclencheur 3 : l'heure de début d'une réunion planifiée.
        observers.append(nc.addObserver(
            forName: MeetingNotificationService.meetingStartReachedNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetection() }
            })
        // Boutons des popups.
        observers.append(nc.addObserver(
            forName: MeetingNotificationService.teamsActionNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleAction(note.userInfo) }
            })

        // Déclencheur 3, version robuste : `willPresent` ne tire qu'au premier
        // plan, or l'heure de début arrive typiquement pendant que l'utilisateur
        // est dans Teams. Une horloge de 30 s réévalue l'agenda ; la tolérance
        // de ±2 min de l'appariement et `lastHandledEventID` font le reste.
        let timer = Timer(timeInterval: Self.clockInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleDetection() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer

        TeamsCallMonitor.shared.start()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        clockTimer?.invalidate()
        clockTimer = nil
        TeamsCallMonitor.shared.stop()
        phase = .idle
        resetCurrent()
        lastHandledEventID = nil
    }

    // MARK: - Entrée des déclencheurs

    /// Apparie l'instant courant à l'agenda du jour. Les trois déclencheurs
    /// passent par ici : c'est le point unique où l'on décide qu'un appel
    /// « compte » (spec §3).
    private func handleDetection() {
        let events = CalendarAgendaService.shared.events(for: Date())
        switch TeamsCallMatchService.match(events: events, at: Date()) {
        case .none:
            coordLog.debug("appel detecte sans evenement correspondant — aucun popup")
        case .ambiguous(let candidates):
            coordLog.info("appel ambigu (\(candidates.count) evenements) — aucun popup")
        case .matched(let event):
            detected(event)
        }
    }

    /// Point d'entrée d'un appel apparié. Exposé pour les tests, qui n'ont
    /// pas d'agenda.
    func detected(_ event: CalendarMeetingEvent) {
        guard settings()?.teamsAutoRecordEnabled ?? false else {
            coordLog.debug("auto-record desactive par reglage")
            return
        }
        guard event.id != lastHandledEventID else {
            coordLog.debug("evenement deja traite — pas de re-popup")
            return
        }
        if phase == .recording || phase == .callEnded {
            // Un enregistrement tourne déjà : on propose de lier, pas de créer
            // (spec D-10). Proposé une seule fois par événement.
            linkCandidateEvent = event
            lastHandledEventID = event.id
            handle(.callDetectedWhileRecording(eventID: event.id))
            return
        }
        // On ne retient l'événement que si la machine accepte la détection :
        // une détection pendant un parcours en cours ne doit pas écraser
        // l'événement de ce parcours.
        let (next, _) = TeamsAutoRecordState.reduce(phase: phase, event: .callDetected(eventID: event.id))
        guard next == .detected, next != phase else {
            coordLog.debug("detection ignoree en phase \(String(describing: self.phase))")
            return
        }
        currentEvent = event
        handle(.callDetected(eventID: event.id))
    }

    /// Traduit une action de notification en événement de la machine.
    private func handleAction(_ userInfo: [AnyHashable: Any]?) {
        guard let actionID = userInfo?["actionID"] as? String else { return }
        switch actionID {
        case MeetingNotificationService.TeamsAction.startRecord:       handle(.userStarted)
        case MeetingNotificationService.TeamsAction.linkToCurrent:
            if let candidate = linkCandidateEvent { handle(.userLinkedToCurrentMeeting(eventID: candidate.id)) }
        case MeetingNotificationService.TeamsAction.snooze5:           handle(.userSnoozed)
        case MeetingNotificationService.TeamsAction.dismiss:           handle(.userDismissed)
        case MeetingNotificationService.TeamsAction.stopAndFinalize:   handle(.userStopAndFinalize)
        case MeetingNotificationService.TeamsAction.continueRecording: handle(.userContinue)
        case MeetingNotificationService.TeamsAction.generateReport:    handle(.userGenerateReport)
        case MeetingNotificationService.TeamsAction.skipReport:        handle(.userSkipReport)
        default: break
        }
    }

    // MARK: - Retours de la fenêtre de réunion

    /// Consomme la demande en attente pour cette réunion — une seule fois,
    /// et seulement pour la réunion visée.
    func consumePendingRequest(for meetingID: UUID) -> MeetingRequest? {
        guard let pending = pendingRequest, pending.meetingID == meetingID else { return nil }
        pendingRequest = nil
        return pending.request
    }

    /// La fenêtre a fini — ou échoué — une transcription pour cette réunion.
    /// `segmentCount` vaut 0 sur échec. Ignoré pour toute autre réunion.
    func transcriptionDidFinish(meetingID: UUID, segmentCount: Int) {
        guard meetingID == currentMeetingID else { return }
        handle(.transcriptionFinalized(segmentCount: segmentCount))
    }

    /// La fenêtre a fini — ou échoué — la génération du rapport.
    func reportDidFinish(meetingID: UUID, succeeded: Bool) {
        guard meetingID == currentMeetingID else { return }
        handle(succeeded ? .reportSucceeded : .reportFailed)
    }

    /// La fenêtre n'a pas pu démarrer la capture, ou a constaté qu'aucune
    /// capture ne lui appartient. Ignoré pour toute autre réunion.
    func recordingDidFail(meetingID: UUID) {
        guard meetingID == currentMeetingID else { return }
        handle(.recordingFailed)
    }

    /// La réunion du parcours a été supprimée par l'utilisateur.
    func meetingWasDeleted(meetingID: UUID) {
        guard meetingID == currentMeetingID else { return }
        handle(.meetingDeleted)
    }

    // MARK: - Machine à états

    /// Avance la machine et applique les effets. Point d'entrée unique.
    func handle(_ event: TeamsAutoRecordEvent) {
        let (next, effects) = TeamsAutoRecordState.reduce(phase: phase, event: event)
        guard next != phase || !effects.isEmpty else {
            coordLog.debug("evenement inerte \(String(describing: event)) en phase \(String(describing: self.phase))")
            return
        }
        coordLog.debug("\(String(describing: self.phase)) --\(String(describing: event))--> \(String(describing: next))")
        // Le contexte est mis à jour AVANT les effets, qui le lisent.
        switch event {
        case .userDismissed:  lastHandledEventID = currentEvent?.id
        case .meetingDeleted: meetingIsGone = true
        default: break
        }
        phase = next
        effects.forEach(apply)
        if next == .idle { resetCurrent() }
    }

    private func resetCurrent() {
        currentEvent = nil
        currentMeetingID = nil
        linkCandidateEvent = nil
        meetingIsGone = false
        pendingRequest = nil
        snoozeTask?.cancel()
        snoozeTask = nil
    }

    // MARK: - Effets

    private func apply(_ effect: TeamsAutoRecordEffect) {
        switch effect {
        case .emitDetectedNotification:
            guard let event = currentEvent else { return }
            deliver(.detectedPopup(eventTitle: event.title))

        case .createAndOpenMeeting:
            createAndOpenMeeting()

        case .scheduleSnooze(let minutes):
            scheduleSnooze(minutes: minutes)

        case .emitEndedNotification:
            guard let id = currentMeetingID else { return }
            deliver(.endedPopup(meetingID: id))

        case .stopRecording:
            if meetingIsGone {
                // Plus de fenêtre à solliciter : on coupe la capture nous-mêmes.
                if let id = currentMeetingID, AudioRecorderService.shared.isRecording(for: id) {
                    _ = AudioRecorderService.shared.stop()
                }
            } else {
                request(.stopAndFinalize)
            }

        case .emitTranscriptReadyNotification(let count):
            guard let id = currentMeetingID else { return }
            let available = settings().map {
                TeamsReportAvailability.isAvailable(provider: $0.provider, cloudToken: $0.cloudToken)
            } ?? false
            deliver(.transcriptReadyPopup(segmentCount: count, meetingID: id, reportAvailable: available))

        case .emitLinkProposal:
            guard let event = linkCandidateEvent, let id = currentMeetingID else { return }
            deliver(.linkProposalPopup(eventTitle: event.title, meetingID: id))

        case .linkEventToCurrentMeeting:
            linkCandidateEventToCurrentMeeting()

        case .emitSTTErrorNotification:
            guard let id = currentMeetingID else { return }
            deliver(.sttErrorPopup(meetingID: id))

        case .generateReport:
            request(.generateReport)

        case .notifyReportFailure:
            guard let id = currentMeetingID else { return }
            deliver(.reportFailedPopup(meetingID: id))

        case .setMenuBarRecording(let on):
            deliver(.menuBarRecording(on))
        }
    }

    /// Crée la réunion depuis l'événement d'agenda et ouvre sa fenêtre avec
    /// démarrage automatique de l'enregistrement. Réutilise intégralement le
    /// chemin existant `importEvent` + `QuickLaunchRouter` (via `deliver`).
    private func createAndOpenMeeting() {
        guard let container, let event = currentEvent, let settings = settings() else { return }
        let context = container.mainContext
        let meeting = CalendarMeetingImportService().importEvent(event, context: context, settings: settings)
        do { try context.save() } catch { coordLog.error("save: \(error.localizedDescription)") }

        let stableID = meeting.ensuredStableID
        currentMeetingID = stableID
        lastHandledEventID = event.id
        // Fenêtre déjà ouverte ou pas : la demande couvre les deux cas, le
        // token `autoStartRecording` ne couvre que l'ouverture.
        pendingRequest = (stableID, .startRecording)
        NotificationCenter.default.post(name: Self.meetingRequestNotification, object: nil,
                                        userInfo: ["meetingID": stableID.uuidString])
        deliver(.openWindow(meetingID: stableID, autoStartRecording: true))
    }

    /// Rattache le second événement d'agenda à la réunion en cours, sans
    /// toucher à la capture ni aux participants d'origine (spec §9).
    private func linkCandidateEventToCurrentMeeting() {
        guard let container, let meetingID = currentMeetingID, let event = linkCandidateEvent else { return }
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        guard let meeting = all.first(where: { $0.stableID == meetingID }) else { return }
        meeting.calendarEventID = event.id
        meeting.calendarEventTitle = event.title
        if meeting.teamsJoinURL?.isEmpty ?? true { meeting.teamsJoinURL = event.teamsJoinURL }
        linkCandidateEvent = nil
        do { try context.save() } catch { coordLog.error("liaison: \(error.localizedDescription)") }
    }

    /// Dépose une demande pour la réunion du parcours, la signale aux
    /// fenêtres montées, et fait venir la fenêtre au premier plan — ou
    /// l'ouvre si elle a été fermée.
    private func request(_ request: MeetingRequest) {
        guard let meetingID = currentMeetingID else { return }
        pendingRequest = (meetingID, request)
        NotificationCenter.default.post(name: Self.meetingRequestNotification, object: nil,
                                        userInfo: ["meetingID": meetingID.uuidString])
        deliver(.openWindow(meetingID: meetingID, autoStartRecording: false))
    }

    private func scheduleSnooze(minutes: Int) {
        snoozeTask?.cancel()
        guard let eventID = currentEvent?.id else { return }
        snoozeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.handle(.snoozeElapsed(eventID: eventID))
        }
    }

    // MARK: - Livraison réelle des effets

    /// Implémentation de production de `deliver` : notifications système,
    /// routeur de fenêtres, barre de menus. Interne (pas `private`) pour que
    /// les tests puissent la restaurer.
    static func deliverToSystem(_ outbound: Outbound) {
        switch outbound {
        case .detectedPopup(let title):
            MeetingNotificationService.shared.notifyTeamsCallDetected(eventTitle: title, meetingStableID: "")
        case .endedPopup(let id):
            MeetingNotificationService.shared.notifyTeamsCallEnded(meetingStableID: id.uuidString)
        case .transcriptReadyPopup(let count, let id, let reportAvailable):
            MeetingNotificationService.shared.notifyTeamsTranscriptReady(
                segmentCount: count, meetingStableID: id.uuidString, reportAvailable: reportAvailable)
        case .linkProposalPopup(let title, let id):
            MeetingNotificationService.shared.notifyTeamsCallLinkProposal(
                eventTitle: title, meetingStableID: id.uuidString)
        case .sttErrorPopup(let id):
            MeetingNotificationService.shared.notifyTeamsSTTUnavailable(meetingStableID: id.uuidString)
        case .reportFailedPopup(let id):
            MeetingNotificationService.shared.notifyTeamsReportFailed(meetingStableID: id.uuidString)
        case .openWindow(let id, let autoStart):
            NSApp.activate(ignoringOtherApps: true)
            QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(meetingID: id, autoStartRecording: autoStart)
        case .menuBarRecording(let on):
            MenuBarController.shared?.setRecording(on)
        }
    }

    // MARK: - Accès au contexte

    private func settings() -> AppSettings? {
        guard let context = container?.mainContext else { return nil }
        return (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
    }
}
