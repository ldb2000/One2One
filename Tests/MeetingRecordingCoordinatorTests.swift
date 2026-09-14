import Testing
import Foundation
@testable import OneToOne

/// Le coordinateur applique `AudioInputRouting` au démarrage et en séance
/// (spec §4.4) : feuilles demandées à `MeetingScreenModel`, notifications,
/// rétrogradation Teams. Tout est doublé : aucun micro, aucun Teams.
@Suite("MeetingRecordingCoordinator — démarrage et surveillance")
@MainActor
struct MeetingRecordingCoordinatorTests {

    private let macBook = AudioInputDevice(uid: "BuiltIn", name: "Microphone MacBook Pro", isBuiltIn: true, isSystemDefault: false)
    private let iphone = AudioInputDevice(uid: "iPhone", name: "iPhone de Laurent", isBuiltIn: false, isSystemDefault: true)

    private struct Harness {
        let devices: FakeAudioInputDevices
        let recorder: FakeRecorder
        let notifier: FakeNotifier
        let screen: MeetingScreenModel
        let coordinator: MeetingRecordingCoordinator
    }

    private func makeHarness(devices: [AudioInputDevice],
                             teamsRunning: Bool = true,
                             screenPermission: Bool = true,
                             micro: MicrophonePermissionStatus = .granted) -> Harness {
        let fakeDevices = FakeAudioInputDevices(devices: devices)
        let recorder = FakeRecorder()
        let notifier = FakeNotifier()
        let suite = "MeetingRecordingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let screen = MeetingScreenModel(defaults: defaults)
        let coordinator = MeetingRecordingCoordinator(
            devices: fakeDevices, recorder: recorder, notifier: notifier,
            isTeamsRunning: { teamsRunning },
            hasScreenPermission: { screenPermission },
            microphonePermission: { micro })
        return Harness(devices: fakeDevices, recorder: recorder, notifier: notifier, screen: screen, coordinator: coordinator)
    }

    // MARK: - Démarrage

    @Test("Micro préféré présent → proceed avec son UID, aucune feuille")
    func preferredPresentProceeds() async {
        let h = makeHarness(devices: [macBook, iphone])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: iphone.uid, captureMode: .microOnly)))
        #expect(h.screen.recordingPrompts == RecordingPromptState())
    }

    @Test("Réunion sans lien Teams → micro seul même si le mode demande la seconde piste")
    func noTeamsLinkIsMicOnly() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microOnly)))
        #expect(h.notifier.teamsMissingCount == 0)
    }

    @Test("Micro préféré absent → feuille de choix, awaitingUserChoice")
    func preferredMissingAsks() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .awaitingUserChoice)
        #expect(h.screen.recordingPrompts.audioInputChoice?.candidates == [macBook])
        #expect(h.screen.recordingPrompts.audioInputChoice?.missingPreferredUID == iphone.uid)
    }

    @Test("Le choix de l'utilisateur court-circuite la règle et ne touche pas au préféré")
    func chosenUIDWins() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: macBook.uid,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: macBook.uid, captureMode: .microOnly)))
        #expect(h.screen.recordingPrompts.audioInputChoice == nil)
    }

    @Test("Aucune entrée → blocked, aucune feuille")
    func noInputBlocks() async {
        let h = makeHarness(devices: [])
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .blocked)
        #expect(h.screen.recordingPrompts == RecordingPromptState())
    }

    @Test("Permission micro refusée → feuille d'aide micro, blocked, la règle n'est pas consultée")
    func deniedMicrophoneShowsHelp() async {
        let h = makeHarness(devices: [macBook], micro: .denied)
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .blocked)
        #expect(h.screen.recordingPrompts.permissionHelp == .microphone)
        #expect(h.screen.recordingPrompts.audioInputChoice == nil)
    }

    @Test("Lien Teams, Teams lancé, permission écran → micro + système, aucune notification")
    func teamsRunningKeepsSystemTrack() async {
        let h = makeHarness(devices: [macBook], teamsRunning: true, screenPermission: true)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microAndSystem)))
        #expect(h.notifier.teamsMissingCount == 0)
        #expect(h.coordinator.teamsFlowMissing == false)
    }

    @Test("Lien Teams mais Teams fermé → notification « aucun flux », micro seul, drapeau posé")
    func teamsClosedDowngrades() async {
        let h = makeHarness(devices: [macBook], teamsRunning: false, screenPermission: true)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microOnly)))
        #expect(h.notifier.teamsMissingCount == 1)
        #expect(h.coordinator.teamsFlowMissing == true)
    }

    @Test("Permission écran absente → le mode demandé est transmis tel quel (le recorder dégrade et lève le bandeau)")
    func screenPermissionMissingLeavesModeToRecorder() async {
        let h = makeHarness(devices: [macBook], teamsRunning: true, screenPermission: false)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microAndSystem)))
        #expect(h.notifier.teamsMissingCount == 0)
    }

    // MARK: - Surveillance

    @Test("Retrait de l'entrée en cours → bascule sur le micro intégré et notification avec son nom")
    func removalSwitchesAndNotifies() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.switchedTo == [macBook])
        #expect(h.notifier.fallbackNames == [macBook.name])
    }

    @Test("Retrait d'une autre entrée → rien")
    func unrelatedRemovalDoesNothing() {
        let h = makeHarness(devices: [macBook, iphone])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: "USB")
        #expect(h.recorder.switchedTo.isEmpty)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Plus aucune entrée → arrêt, aucune notification de bascule")
    func nothingLeftStops() {
        let h = makeHarness(devices: [])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.stopCount == 1)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("La bascule échoue → arrêt propre plutôt qu'un engine mort")
    func failedSwitchStops() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.recorder.switchShouldFail = true
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.stopCount == 1)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Interruption de l'engine, entrée encore présente → rebranchement silencieux sur la même entrée")
    func interruptionRebindsSameDevice() {
        let h = makeHarness(devices: [macBook, iphone])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.devices.refreshCount == 1)
        #expect(h.recorder.switchedTo == [iphone])
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Interruption de l'engine, entrée disparue de la liste → même chemin que le retrait")
    func interruptionDetectsRemoval() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.recorder.switchedTo == [macBook])
        #expect(h.notifier.fallbackNames == [macBook.name])
    }

    @Test("Interruption en défaut système (nil) → rebranchement sur le défaut, sans notification")
    func interruptionOnSystemDefaultRebinds() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = nil
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.recorder.switchedTo == [nil])
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("beginMonitoring pose le crochet du recorder, endMonitoring le retire")
    func monitoringHooksRecorder() {
        let h = makeHarness(devices: [macBook])
        #expect(h.recorder.onInputInterrupted == nil)
        h.coordinator.beginMonitoring()
        #expect(h.recorder.onInputInterrupted != nil)
        h.coordinator.endMonitoring()
        #expect(h.recorder.onInputInterrupted == nil)
    }

    @Test("Un événement removed du fournisseur déclenche la bascule")
    func providerEventTriggersFallback() async throws {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.devices.emit(.removed(uid: iphone.uid))
        // Le flux est consommé par une Task du coordinateur : on lui laisse un tour.
        for _ in 0..<50 where h.recorder.switchedTo.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(h.recorder.switchedTo == [macBook])
        h.coordinator.endMonitoring()
    }
}
