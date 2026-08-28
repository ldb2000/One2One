import Testing
import Foundation
@testable import OneToOne

/// Table de transitions du parcours auto-record. Le chemin nominal, mais
/// surtout les sorties : refus, snooze, poursuite d'enregistrement, suppression
/// de la réunion en cours de route.
@Suite("TeamsAutoRecordState — machine à états du parcours")
struct TeamsAutoRecordStateTests {

    private func reduce(_ phase: TeamsAutoRecordPhase,
                        _ event: TeamsAutoRecordEvent) -> (TeamsAutoRecordPhase, [TeamsAutoRecordEffect]) {
        TeamsAutoRecordState.reduce(phase: phase, event: event)
    }

    @Test("Chemin nominal complet")
    func nominalPath() {
        var (phase, effects) = reduce(.idle, .callDetected(eventID: "EVT-1"))
        #expect(phase == .detected)
        #expect(effects == [.emitDetectedNotification(eventID: "EVT-1")])

        (phase, effects) = reduce(phase, .userStarted)
        #expect(phase == .recording)
        #expect(effects == [.createAndOpenMeeting, .setMenuBarRecording(true)])

        (phase, effects) = reduce(phase, .callEnded)
        #expect(phase == .callEnded)
        #expect(effects == [.emitEndedNotification])

        (phase, effects) = reduce(phase, .userStopAndFinalize)
        #expect(phase == .finalizing)
        #expect(effects == [.stopRecording, .setMenuBarRecording(false)])

        (phase, effects) = reduce(phase, .transcriptionFinalized(segmentCount: 42))
        #expect(phase == .readyForAI)
        #expect(effects == [.emitTranscriptReadyNotification(segmentCount: 42)])

        (phase, effects) = reduce(phase, .userGenerateReport)
        #expect(phase == .reporting)
        #expect(effects == [.generateReport])

        (phase, effects) = reduce(phase, .reportSucceeded)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Ignorer ramène au repos sans rien créer")
    func dismissReturnsToIdle() {
        let (phase, effects) = reduce(.detected, .userDismissed)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Snooze arme un rappel et attend")
    func snoozeSchedulesReminder() {
        var (phase, effects) = reduce(.detected, .userSnoozed)
        #expect(phase == .snoozed)
        #expect(effects == [.scheduleSnooze(minutes: 5)])

        (phase, effects) = reduce(phase, .snoozeElapsed(eventID: "EVT-1"))
        #expect(phase == .detected)
        #expect(effects == [.emitDetectedNotification(eventID: "EVT-1")])
    }

    @Test("Continuer l'enregistrement revient en capture sans rien arrêter")
    func continueRecordingResumes() {
        let (phase, effects) = reduce(.callEnded, .userContinue)
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    @Test("Reporter le rapport laisse la réunion prête, sans le générer")
    func skipReportKeepsMeetingReady() {
        let (phase, effects) = reduce(.readyForAI, .userSkipReport)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Un échec du provider IA n'efface pas le travail : on reste prêt à retenter")
    func reportFailureStaysReady() {
        let (phase, effects) = reduce(.reporting, .reportFailed)
        #expect(phase == .readyForAI)
        #expect(effects == [.notifyReportFailure])
    }

    @Test("La suppression de la réunion pendant la capture force l'arrêt")
    func deletionForcesStop() {
        let (phase, effects) = reduce(.recording, .meetingDeleted)
        #expect(phase == .idle)
        #expect(effects == [.stopRecording, .setMenuBarRecording(false)])
    }

    @Test("Ignorer pendant un snooze annule le parcours sans effet")
    func dismissWhileSnoozedReturnsToIdle() {
        let (phase, effects) = reduce(.snoozed, .userDismissed)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("La suppression de la réunion après la fin d'appel force aussi l'arrêt")
    func deletionAfterCallEndedForcesStop() {
        let (phase, effects) = reduce(.callEnded, .meetingDeleted)
        #expect(phase == .idle)
        #expect(effects == [.stopRecording, .setMenuBarRecording(false)])
    }

    @Test("Un arrêt manuel suivi d'une transcription rejoint le parcours sans popup de fin")
    func manualStopThenTranscriptionSkipsEndedPopup() {
        let (phase, effects) = reduce(.recording, .transcriptionFinalized(segmentCount: 7))
        #expect(phase == .readyForAI)
        #expect(effects == [.setMenuBarRecording(false), .emitTranscriptReadyNotification(segmentCount: 7)])
    }

    @Test("Une transcription arrivée pendant le popup de fin d'appel le rend caduc")
    func transcriptionDuringCallEndedProceeds() {
        let (phase, effects) = reduce(.callEnded, .transcriptionFinalized(segmentCount: 3))
        #expect(phase == .readyForAI)
        #expect(effects == [.setMenuBarRecording(false), .emitTranscriptReadyNotification(segmentCount: 3)])
    }

    @Test("Une détection pendant un enregistrement en cours ne relance rien")
    func detectionDuringRecordingIsIgnored() {
        let (phase, effects) = reduce(.recording, .callDetected(eventID: "EVT-2"))
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    @Test("Un événement hors séquence ne change rien")
    func outOfOrderEventIsInert() {
        let (phase, effects) = reduce(.idle, .userStopAndFinalize)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }
}
