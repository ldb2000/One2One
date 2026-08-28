import Foundation

/// Phases du parcours auto-record (spec §4). Cet état vit **en mémoire** dans
/// le coordinateur : rien n'est persisté sur la `Meeting` (spec §5). Un crash
/// de l'application perd le parcours en cours — c'est un choix assumé.
enum TeamsAutoRecordPhase: Equatable {
    case idle
    case detected
    case snoozed
    case recording
    case callEnded
    case finalizing
    case readyForAI
    case reporting
}

/// Ce qui arrive au parcours, qu'il vienne du système ou de l'utilisateur.
enum TeamsAutoRecordEvent: Equatable {
    /// Un des trois déclencheurs de §3 a conclu à un appel.
    case callDetected(eventID: String)
    case userStarted
    case userDismissed
    case userSnoozed
    case snoozeElapsed(eventID: String)
    case callEnded
    case userStopAndFinalize
    case userContinue
    case transcriptionFinalized(segmentCount: Int)
    case userGenerateReport
    case userSkipReport
    case reportSucceeded
    case reportFailed
    /// La réunion créée par le parcours a été supprimée sous nos pieds.
    case meetingDeleted
}

/// Ce qu'il faut faire. Le coordinateur (Task 7) est seul à savoir comment.
enum TeamsAutoRecordEffect: Equatable {
    case emitDetectedNotification(eventID: String)
    case createAndOpenMeeting
    case scheduleSnooze(minutes: Int)
    case emitEndedNotification
    case stopRecording
    case emitTranscriptReadyNotification(segmentCount: Int)
    case generateReport
    case notifyReportFailure
    case setMenuBarRecording(Bool)
}

/// Réduction pure du parcours. Toute transition non listée est inerte : un
/// événement hors séquence ne doit jamais faire dérailler la machine.
enum TeamsAutoRecordState {

    static func reduce(phase: TeamsAutoRecordPhase,
                       event: TeamsAutoRecordEvent) -> (TeamsAutoRecordPhase, [TeamsAutoRecordEffect]) {
        switch (phase, event) {

        case (.idle, .callDetected(let eventID)):
            return (.detected, [.emitDetectedNotification(eventID: eventID)])

        case (.detected, .userStarted):
            return (.recording, [.createAndOpenMeeting, .setMenuBarRecording(true)])

        case (.detected, .userDismissed):
            return (.idle, [])

        case (.detected, .userSnoozed):
            return (.snoozed, [.scheduleSnooze(minutes: 5)])

        case (.snoozed, .snoozeElapsed(let eventID)):
            return (.detected, [.emitDetectedNotification(eventID: eventID)])

        case (.snoozed, .userDismissed):
            return (.idle, [])

        case (.recording, .callEnded):
            return (.callEnded, [.emitEndedNotification])

        case (.recording, .meetingDeleted):
            return (.idle, [.stopRecording, .setMenuBarRecording(false)])

        case (.callEnded, .userStopAndFinalize):
            return (.finalizing, [.stopRecording, .setMenuBarRecording(false)])

        case (.callEnded, .userContinue):
            return (.recording, [])

        case (.callEnded, .meetingDeleted):
            return (.idle, [.stopRecording, .setMenuBarRecording(false)])

        case (.finalizing, .transcriptionFinalized(let count)):
            return (.readyForAI, [.emitTranscriptReadyNotification(segmentCount: count)])

        case (.readyForAI, .userGenerateReport):
            return (.reporting, [.generateReport])

        case (.readyForAI, .userSkipReport):
            return (.idle, [])

        case (.reporting, .reportSucceeded):
            return (.idle, [])

        case (.reporting, .reportFailed):
            // On ne perd pas la transcription : la réunion reste prête et
            // l'utilisateur peut retenter depuis la fenêtre (spec §10).
            return (.readyForAI, [.notifyReportFailure])

        default:
            return (phase, [])
        }
    }
}
