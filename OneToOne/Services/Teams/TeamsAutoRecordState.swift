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
    /// Un appel est détecté alors qu'un enregistrement tourne déjà (spec D-10).
    case callDetectedWhileRecording(eventID: String)
    /// L'utilisateur accepte de rattacher ce second appel à la réunion en cours.
    case userLinkedToCurrentMeeting(eventID: String)
    case userStarted
    /// La capture n'a pas pu démarrer, ou n'appartient pas à cette réunion.
    case recordingFailed
    case userDismissed
    case userSnoozed
    case snoozeElapsed(eventID: String)
    case callEnded
    case userStopAndFinalize
    case userContinue
    case transcriptionFinalized(segmentCount: Int)
    case userGenerateReport
    case userSkipReport
    /// L'utilisateur relance la transcription depuis le popup « STT indisponible ».
    case userRetrySTT
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
    case emitLinkProposal(eventID: String)
    case linkEventToCurrentMeeting(eventID: String)
    /// Le STT n'a rien produit : on propose de le retenter plutôt que de
    /// promettre un rapport (spec §10).
    case emitSTTErrorNotification
    case retryTranscription
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

        case (.recording, .callDetectedWhileRecording(let eventID)),
             (.callEnded, .callDetectedWhileRecording(let eventID)):
            return (phase, [.emitLinkProposal(eventID: eventID)])

        case (.recording, .userLinkedToCurrentMeeting(let eventID)),
             (.callEnded, .userLinkedToCurrentMeeting(let eventID)):
            return (phase, [.linkEventToCurrentMeeting(eventID: eventID)])

        case (.recording, .transcriptionFinalized(let count)) where count == 0,
             (.callEnded, .transcriptionFinalized(let count)) where count == 0:
            // Arrêt manuel, mais le STT n'a rien produit : on coupe l'icône
            // et on propose de retenter plutôt que de promettre un rapport.
            return (.idle, [.setMenuBarRecording(false), .emitSTTErrorNotification])

        case (.finalizing, .transcriptionFinalized(let count)) where count == 0:
            // Rien à résumer : inutile de proposer un rapport.
            return (.idle, [.emitSTTErrorNotification])

        case (.recording, .transcriptionFinalized(let count)),
             (.callEnded, .transcriptionFinalized(let count)):
            // Arrêt manuel depuis la fenêtre, puis transcription : on rejoint
            // le parcours sans repasser par le popup de fin d'appel.
            return (.readyForAI, [.setMenuBarRecording(false),
                                  .emitTranscriptReadyNotification(segmentCount: count)])

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

        case (.finalizing, .meetingDeleted), (.readyForAI, .meetingDeleted), (.reporting, .meetingDeleted):
            // La capture est déjà arrêtée ; il n'y a plus rien à demander à
            // une fenêtre qui n'existe plus. On rend simplement la machine.
            return (.idle, [])

        case (.recording, .recordingFailed), (.callEnded, .recordingFailed):
            // Pas de capture : rien à finaliser, on éteint l'icône et on rend la machine.
            return (.idle, [.setMenuBarRecording(false)])

        case (.finalizing, .recordingFailed):
            // La fenêtre nous dit qu'aucune capture ne lui appartient : l'icône
            // est déjà éteinte, on rend simplement la machine.
            return (.idle, [])

        case (.idle, .userRetrySTT):
            // On rejoint le parcours à la finalisation : la transcription
            // rendra compte comme après un arrêt.
            return (.finalizing, [.retryTranscription])

        default:
            return (phase, [])
        }
    }
}
