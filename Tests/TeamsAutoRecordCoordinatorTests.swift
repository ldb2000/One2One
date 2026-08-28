import XCTest
import SwiftData
@testable import OneToOne

/// Le coordinateur est l'orchestrateur du parcours : c'est lui qui crée la
/// réunion, sollicite la fenêtre et émet les popups. On le teste de bout en
/// bout avec un conteneur en mémoire, en interceptant ses effets externes via
/// `deliver` — jamais via UNUserNotificationCenter, qui plante hors bundle.
@MainActor
final class TeamsAutoRecordCoordinatorTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    var outbound: [TeamsAutoRecordCoordinator.Outbound] = []
    let coordinator = TeamsAutoRecordCoordinator.shared

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        context.insert(AppSettings())
        try context.save()
        outbound = []
        coordinator.start(container: container)
        coordinator.deliver = { [weak self] in self?.outbound.append($0) }
    }

    override func tearDown() {
        coordinator.stop()
        coordinator.deliver = TeamsAutoRecordCoordinator.deliverToSystem
    }

    private var settings: AppSettings {
        (try? context.fetch(FetchDescriptor<AppSettings>()))!.first!
    }

    /// Date de début fixe : deux appels du helper pour le « même » événement
    /// doivent produire la **même** occurrence, sinon les gardes par occurrence
    /// ne veulent plus rien dire.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// `startOffset` construit une autre occurrence de la même série : même
    /// identifiant, autre date de début (cf. récurrences EventKit).
    private func event(_ id: String = "EVT-1", title: String = "Comité hebdo",
                       startOffset: TimeInterval = 0) -> CalendarMeetingEvent {
        let start = base.addingTimeInterval(startOffset)
        return CalendarMeetingEvent(id: id, title: title,
                                    startDate: start, endDate: start.addingTimeInterval(3600),
                                    calendarTitle: "Pro", attendees: [],
                                    teamsJoinURL: "https://teams.microsoft.com/l/meetup-join/\(id)",
                                    isCancelled: false, isAllDay: false)
    }

    private func meetings() throws -> [Meeting] {
        try context.fetch(FetchDescriptor<Meeting>())
    }

    /// Détection + Démarrer : retourne le stableID de la réunion créée.
    private func startRecording() throws -> UUID {
        coordinator.detected(event())
        coordinator.handle(.userStarted)
        return try XCTUnwrap(try meetings().first?.ensuredStableID)
    }

    // MARK: - Détection

    func test_disabledSetting_blocksDetection() {
        settings.teamsAutoRecordEnabled = false
        coordinator.detected(event())
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(outbound.isEmpty)
    }

    func test_detection_emitsPopupWithEventTitle() {
        coordinator.detected(event(title: "Point projet"))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound, [.detectedPopup(eventTitle: "Point projet")])
    }

    func test_dismiss_returnsToIdle_andSameEventIsNotProposedAgain() {
        coordinator.detected(event())
        coordinator.handle(.userDismissed)
        XCTAssertEqual(coordinator.phase, .idle)
        outbound = []
        coordinator.detected(event())
        XCTAssertEqual(coordinator.phase, .idle, "Un événement refusé n'est pas re-proposé")
        XCTAssertTrue(outbound.isEmpty)
    }

    func test_snooze_thenDismiss_cancelsWithoutPopup() {
        coordinator.detected(event())
        coordinator.handle(.userSnoozed)
        XCTAssertEqual(coordinator.phase, .snoozed)
        outbound = []
        coordinator.handle(.userDismissed)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(outbound.isEmpty)
    }

    /// Une bannière que l'utilisateur laisse expirer ne produit aucune action :
    /// sans remplacement, le parcours resterait en `.detected` pour la session.
    func test_secondDetectionWhilePopupIsUp_supersedesIt() throws {
        coordinator.detected(event("EVT-A", title: "Réunion A"))
        coordinator.detected(event("EVT-B", title: "Réunion B"))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound, [.detectedPopup(eventTitle: "Réunion A"),
                                  .detectedPopup(eventTitle: "Réunion B")])
        coordinator.handle(.userStarted)
        let meeting = try XCTUnwrap(try meetings().first)
        XCTAssertEqual(meeting.calendarEventID, "EVT-B", "Démarrer agit sur le dernier popup émis")
        XCTAssertEqual(try meetings().count, 1)
    }

    func test_sameEventRedetectedWhilePopupIsUp_isIgnored() {
        coordinator.detected(event("EVT-A", title: "Réunion A"))
        coordinator.detected(event("EVT-A", title: "Réunion A"))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound, [.detectedPopup(eventTitle: "Réunion A")],
                       "Un même événement re-détecté ne re-notifie pas")
    }

    /// Le popup « Transcription prête » ignoré ne doit pas figer le parcours :
    /// l'appel suivant prime, comme un « Plus tard » implicite.
    func test_detectionWhileReadyForAI_startsNewParcours() throws {
        let meetingID = try startRecording()
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 5)
        XCTAssertEqual(coordinator.phase, .readyForAI)
        outbound = []

        coordinator.detected(event("EVT-B", title: "Réunion B"))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound.last, .detectedPopup(eventTitle: "Réunion B"))
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID),
                     "Le parcours abandonné ne laisse pas de demande derrière lui")
    }

    // MARK: - Récurrences

    /// EventKit donne le même `calendarItemIdentifier` à toutes les occurrences
    /// d'une série : sans la date de début, refuser le point hebdomadaire une
    /// fois le refuserait pour toujours.
    func test_secondOccurrenceOfHandledEvent_isProposed() {
        coordinator.detected(event("EVT-A", title: "Point hebdo"))
        coordinator.handle(.userDismissed)
        XCTAssertEqual(coordinator.phase, .idle)
        outbound = []

        coordinator.detected(event("EVT-A", title: "Point hebdo", startOffset: 7 * 24 * 3600))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound, [.detectedPopup(eventTitle: "Point hebdo")])
    }

    func test_secondOccurrence_createsItsOwnMeeting() throws {
        let firstID = try startRecording()
        coordinator.transcriptionDidFinish(meetingID: firstID, segmentCount: 3)
        coordinator.handle(.userSkipReport)
        XCTAssertEqual(coordinator.phase, .idle)

        let nextWeek = event(startOffset: 7 * 24 * 3600)
        coordinator.detected(nextWeek)
        XCTAssertEqual(coordinator.phase, .detected)
        coordinator.handle(.userStarted)

        let all = try meetings()
        XCTAssertEqual(all.count, 2, "La semaine suivante crée sa propre réunion")
        XCTAssertEqual(Set(all.map(\.calendarEventID)), ["EVT-1"], "Même série, même identifiant")
        XCTAssertEqual(Set(all.compactMap(\.scheduledStart)), [base, nextWeek.startDate])
    }

    // MARK: - Démarrage

    func test_start_createsLinkedMeeting_opensWindow_andLightsMenuBar() throws {
        let meetingID = try startRecording()
        XCTAssertEqual(coordinator.phase, .recording)
        let meeting = try XCTUnwrap(try meetings().first)
        XCTAssertEqual(meeting.calendarEventID, "EVT-1")
        XCTAssertEqual(meeting.title, "Comité hebdo")
        XCTAssertNotNil(meeting.teamsJoinURL)
        XCTAssertEqual(coordinator.consumePendingRequest(for: meetingID), .startRecording)
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID))
        XCTAssertEqual(Array(outbound.suffix(2)), [
            .openWindow(meetingID: meetingID, autoStartRecording: true),
            .menuBarRecording(true)
        ])
    }

    func test_detectionDuringRecording_proposesLink_once() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertEqual(outbound, [.linkProposalPopup(eventTitle: "Autre réunion", meetingID: meetingID)])
        XCTAssertEqual(try meetings().count, 1, "Pas de seconde réunion")
        outbound = []
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        XCTAssertTrue(outbound.isEmpty, "Un second appel n'est proposé qu'une fois")
    }

    func test_linking_attachesSecondEvent_keepsRecording() throws {
        let meetingID = try startRecording()
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        outbound = []
        coordinator.handle(.userLinkedToCurrentMeeting(eventID: "EVT-2"))
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertTrue(outbound.isEmpty)
        let meeting = try XCTUnwrap(try meetings().first)
        XCTAssertEqual(meeting.calendarEventID, "EVT-2")
        XCTAssertEqual(meeting.calendarEventTitle, "Autre réunion")
        XCTAssertEqual(meeting.ensuredStableID, meetingID)
    }

    func test_transcriptReady_withoutProvider_saysReportUnavailable() throws {
        settings.provider = .anthropic
        settings.cloudToken = ""
        let meetingID = try startRecording()
        outbound = []
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 9)
        XCTAssertEqual(outbound, [.menuBarRecording(false),
                                  .transcriptReadyPopup(segmentCount: 9, meetingID: meetingID, reportAvailable: false)])
    }

    func test_emptyTranscript_raisesSTTError_andReturnsToIdle() throws {
        let meetingID = try startRecording()
        coordinator.handle(.callEnded)
        coordinator.handle(.userStopAndFinalize)
        outbound = []
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 0)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(outbound, [.sttErrorPopup(meetingID: meetingID)])
    }

    // MARK: - Chemin nominal

    func test_nominalPath_endToEnd() throws {
        let meetingID = try startRecording()
        outbound = []

        coordinator.handle(.callEnded)
        XCTAssertEqual(coordinator.phase, .callEnded)
        XCTAssertEqual(outbound, [.endedPopup(meetingID: meetingID)])
        outbound = []

        coordinator.handle(.userStopAndFinalize)
        XCTAssertEqual(coordinator.phase, .finalizing)
        XCTAssertEqual(outbound, [.openWindow(meetingID: meetingID, autoStartRecording: false),
                                  .menuBarRecording(false)])
        XCTAssertEqual(coordinator.consumePendingRequest(for: meetingID), .stopAndFinalize)
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID), "Une demande ne se consomme qu'une fois")
        outbound = []

        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 12)
        XCTAssertEqual(coordinator.phase, .readyForAI)
        XCTAssertEqual(outbound, [.transcriptReadyPopup(segmentCount: 12, meetingID: meetingID, reportAvailable: true)])
        outbound = []

        coordinator.handle(.userGenerateReport)
        XCTAssertEqual(coordinator.phase, .reporting)
        XCTAssertEqual(outbound, [.openWindow(meetingID: meetingID, autoStartRecording: false)])
        XCTAssertEqual(coordinator.consumePendingRequest(for: meetingID), .generateReport)

        coordinator.reportDidFinish(meetingID: meetingID, succeeded: true)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID))
    }

    func test_afterCompletion_sameEventIsNotProposedAgain() throws {
        let meetingID = try startRecording()
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 2)
        coordinator.handle(.userSkipReport)
        XCTAssertEqual(coordinator.phase, .idle)
        outbound = []
        coordinator.detected(event())
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(outbound.isEmpty)
        XCTAssertEqual(try meetings().count, 1)
    }

    // MARK: - Retours de la fenêtre

    func test_pendingRequest_isScopedToItsMeeting() throws {
        let meetingID = try startRecording()
        coordinator.handle(.callEnded)
        coordinator.handle(.userStopAndFinalize)
        XCTAssertNil(coordinator.consumePendingRequest(for: UUID()), "Une autre réunion ne voit pas la demande")
        XCTAssertEqual(coordinator.consumePendingRequest(for: meetingID), .stopAndFinalize)
    }

    func test_callbacksFromAnotherMeeting_areIgnored() throws {
        _ = try startRecording()
        coordinator.handle(.callEnded)
        coordinator.handle(.userStopAndFinalize)
        coordinator.transcriptionDidFinish(meetingID: UUID(), segmentCount: 5)
        XCTAssertEqual(coordinator.phase, .finalizing, "La transcription d'une autre réunion ne fait pas avancer le parcours")
        coordinator.reportDidFinish(meetingID: UUID(), succeeded: true)
        XCTAssertEqual(coordinator.phase, .finalizing)
        coordinator.meetingWasDeleted(meetingID: UUID())
        XCTAssertEqual(coordinator.phase, .finalizing)
    }

    func test_manualStopThenTranscription_skipsEndedPopup() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 4)
        XCTAssertEqual(coordinator.phase, .readyForAI)
        XCTAssertEqual(outbound, [.menuBarRecording(false),
                                  .transcriptReadyPopup(segmentCount: 4, meetingID: meetingID, reportAvailable: true)])
    }

    func test_reportFailure_keepsMeetingReady_andNotifies() throws {
        let meetingID = try startRecording()
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 4)
        coordinator.handle(.userGenerateReport)
        outbound = []
        coordinator.reportDidFinish(meetingID: meetingID, succeeded: false)
        XCTAssertEqual(coordinator.phase, .readyForAI)
        XCTAssertEqual(outbound, [.reportFailedPopup(meetingID: meetingID)])
    }

    func test_recordingFailure_returnsToIdle_andTurnsOffMenuBar() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.recordingDidFail(meetingID: meetingID)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(outbound, [.menuBarRecording(false)])
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID), "La demande .startRecording est retirée")
    }

    func test_deletionDuringRecording_stopsWithoutAskingTheWindow() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.meetingWasDeleted(meetingID: meetingID)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(outbound, [.menuBarRecording(false)], "Pas d'ouverture de fenêtre pour une réunion supprimée")
        XCTAssertNil(coordinator.consumePendingRequest(for: meetingID))
    }

    func test_retrySTTAction_fromIdle_resumesAtFinalizing_andRequestsRetranscription() throws {
        let meetingID = try startRecording()
        coordinator.handle(.callEnded)
        coordinator.handle(.userStopAndFinalize)
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 0)
        XCTAssertEqual(coordinator.phase, .idle)
        outbound = []
        coordinator.handleAction(actionID: MeetingNotificationService.TeamsAction.retrySTT, meetingID: meetingID)
        XCTAssertEqual(coordinator.phase, .finalizing)
        XCTAssertEqual(outbound, [.openWindow(meetingID: meetingID, autoStartRecording: false)])
        XCTAssertEqual(coordinator.consumePendingRequest(for: meetingID), .retryTranscription)
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 5)
        XCTAssertEqual(coordinator.phase, .readyForAI, "La transcription relancée rend compte et rejoint le chemin nominal")
    }

    func test_retrySTTAction_outsideIdle_isIgnored() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.handleAction(actionID: MeetingNotificationService.TeamsAction.retrySTT, meetingID: meetingID)
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertTrue(outbound.isEmpty)
    }

    func test_linkToCurrentAction_routesToLinking() throws {
        let meetingID = try startRecording()
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        coordinator.handleAction(actionID: MeetingNotificationService.TeamsAction.linkToCurrent, meetingID: meetingID)
        XCTAssertEqual(coordinator.phase, .recording)
        XCTAssertEqual(try XCTUnwrap(try meetings().first).calendarEventID, "EVT-2")
    }

    func test_declinedLink_doesNotSuppressLaterProposalOfThatEvent() throws {
        _ = try startRecording()
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        coordinator.handle(.userDismissed)          // refuse la liaison — inerte en .recording
        coordinator.handle(.meetingDeleted)          // ramène la machine au repos
        XCTAssertEqual(coordinator.phase, .idle)
        outbound = []
        coordinator.detected(event("EVT-2", title: "Autre réunion"))
        XCTAssertEqual(coordinator.phase, .detected)
        XCTAssertEqual(outbound, [.detectedPopup(eventTitle: "Autre réunion")])
    }

    func test_manualStopWithEmptyTranscript_turnsOffMenuBar_andRaisesSTTError() throws {
        let meetingID = try startRecording()
        outbound = []
        coordinator.transcriptionDidFinish(meetingID: meetingID, segmentCount: 0)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(outbound, [.menuBarRecording(false), .sttErrorPopup(meetingID: meetingID)])
    }
}
