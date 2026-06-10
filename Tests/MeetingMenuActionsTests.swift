import XCTest
@testable import OneToOne

/// Logique d'activation des items de menu réunion selon l'état courant.
final class MeetingMenuActionsTests: XCTestCase {

    private func make(isRecording: Bool = false, isPaused: Bool = false,
                      hasWav: Bool = false, hasPlayableAudio: Bool = false,
                      isTranscribing: Bool = false, isGeneratingReport: Bool = false,
                      hasReport: Bool = false, hasTranscript: Bool = false) -> MeetingMenuActions {
        MeetingMenuActions(
            meetingTitle: "T",
            isRecording: isRecording, isPaused: isPaused, isTranscribing: isTranscribing,
            isGeneratingReport: isGeneratingReport, hasWav: hasWav,
            hasPlayableAudio: hasPlayableAudio, hasReport: hasReport, hasTranscript: hasTranscript,
            startRecording: {}, stopRecording: {}, appendRecording: {}, togglePause: {},
            retranscribe: {}, generateReport: {}, toggleCustomPrompt: {},
            importCalendar: {}, importExistingWAV: {}, editAudio: {}, revealWAV: {}, deleteMeeting: {},
            exportMarkdown: {}, exportPDF: {}, exportMail: { _ in }, exportOutlook: { _ in },
            exportAppleNotes: { _ in })
    }

    func testExportsRequireReport() {
        let no = make(hasReport: false)
        let yes = make(hasReport: true)
        for item in [MeetingMenuItem.exportMarkdown, .exportPDF, .exportMail, .exportOutlook, .exportNotes] {
            XCTAssertFalse(no.isEnabled(item), "\(item) devrait être grisé sans rapport")
            XCTAssertTrue(yes.isEnabled(item), "\(item) devrait être actif avec rapport")
        }
    }

    func testAudioItemsRequirePlayableAudio() {
        XCTAssertFalse(make(hasPlayableAudio: false).isEnabled(.editAudio))
        XCTAssertFalse(make(hasPlayableAudio: false).isEnabled(.revealWAV))
        XCTAssertTrue(make(hasPlayableAudio: true).isEnabled(.editAudio))
        XCTAssertTrue(make(hasPlayableAudio: true).isEnabled(.revealWAV))
        XCTAssertFalse(make(hasPlayableAudio: true, isTranscribing: true).isEnabled(.editAudio))
    }

    func testGenerateReportRequiresTranscriptAndNotBusy() {
        XCTAssertFalse(make(hasTranscript: false).isEnabled(.generateReport))
        XCTAssertTrue(make(hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isRecording: true, hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isTranscribing: true, hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isGeneratingReport: true, hasTranscript: true).isEnabled(.generateReport))
    }

    func testRetranscribeRequiresWavAndNotTranscribing() {
        XCTAssertFalse(make(hasWav: false).isEnabled(.retranscribe))
        XCTAssertTrue(make(hasWav: true).isEnabled(.retranscribe))
        XCTAssertFalse(make(hasWav: true, isTranscribing: true).isEnabled(.retranscribe))
    }

    func testAppendRequiresWavAndNotBusy() {
        XCTAssertFalse(make(hasWav: false).isEnabled(.appendRecording))
        XCTAssertTrue(make(hasWav: true).isEnabled(.appendRecording))
        XCTAssertFalse(make(isRecording: true, hasWav: true).isEnabled(.appendRecording))
        XCTAssertFalse(make(hasWav: true, isGeneratingReport: true).isEnabled(.appendRecording))
    }

    func testPauseOnlyWhileRecording() {
        XCTAssertFalse(make(isRecording: false).isEnabled(.pause))
        XCTAssertTrue(make(isRecording: true).isEnabled(.pause))
    }

    func testStartStopBlockedWhileTranscribingOrGenerating() {
        XCTAssertTrue(make().isEnabled(.startStopRecording))
        XCTAssertFalse(make(isTranscribing: true).isEnabled(.startStopRecording))
        XCTAssertFalse(make(isGeneratingReport: true).isEnabled(.startStopRecording))
    }

    func testAlwaysEnabled() {
        let a = make()
        XCTAssertTrue(a.isEnabled(.customPrompt))
        XCTAssertTrue(a.isEnabled(.importCalendar))
        XCTAssertTrue(a.isEnabled(.delete))
    }

    func testImportWAVBlockedWhileBusy() {
        XCTAssertTrue(make().isEnabled(.importWAV))
        XCTAssertFalse(make(isRecording: true).isEnabled(.importWAV))
        XCTAssertFalse(make(isTranscribing: true).isEnabled(.importWAV))
    }
}
