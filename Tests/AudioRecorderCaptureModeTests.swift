import Testing
import Foundation
@testable import OneToOne

/// Une permission d'écran refusée doit **dégrader** l'enregistrement, jamais le
/// casser (spec D-6). Ces tests verrouillent la règle de repli.
@Suite("AudioRecorderService — résolution du mode de capture")
struct AudioRecorderCaptureModeTests {

    @Test("Micro + système demandé et permission accordée → micro + système")
    func bothWhenPermitted() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microAndSystem, hasScreenPermission: true) == .microAndSystem)
    }

    @Test("Micro + système demandé sans permission → repli micro seul")
    func fallsBackWithoutPermission() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microAndSystem, hasScreenPermission: false) == .microOnly)
    }

    @Test("Micro seul demandé reste micro seul, même avec la permission")
    func micOnlyIsHonoured() {
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microOnly, hasScreenPermission: true) == .microOnly)
        #expect(AudioRecorderService.resolvedCaptureMode(
            requested: .microOnly, hasScreenPermission: false) == .microOnly)
    }

    @Test("Au repos, aucune chronologie de provenance n'est retenue")
    @MainActor
    func idleTimelineIsEmpty() {
        #expect(AudioRecorderService.shared.provenanceTimeline.isEmpty)
        #expect(!AudioRecorderService.shared.systemAudioUnavailable)
    }
}
