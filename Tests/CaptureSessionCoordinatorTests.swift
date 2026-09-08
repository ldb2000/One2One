import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import OneToOne

/// Le câblage entre le sélecteur, l'état d'écran et le service : ouverture de
/// session, geste manuel, `⌘⇧S`, changement de source.
///
/// Aucun appel à ScreenCaptureKit : la source est doublée et `refreshOptions()`
/// — le seul chemin qui énumère les fenêtres — n'est jamais appelé ici ; les
/// options sont posées à la main, exactement comme le catalogue les rendrait.
@Suite("CaptureSessionCoordinator", .serialized)
@MainActor
struct CaptureSessionCoordinatorTests {

    private let container: ModelContainer
    private let root: URL
    private let meeting: Meeting
    private let screen: MeetingScreenModel

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-coord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        meeting = Meeting(title: "[P25_110] Partage statut final", date: Date())
        meeting.kind = .project
        container.mainContext.insert(meeting)
        try container.mainContext.save()

        let suite = UserDefaults(suiteName: "CaptureSessionCoordinatorTests")!
        suite.removePersistentDomain(forName: "CaptureSessionCoordinatorTests")
        screen = MeetingScreenModel(defaults: suite)
        screen.attach(meetingID: meeting.ensuredStableID)
    }

    private var context: ModelContext { container.mainContext }

    private func banded(_ f: Double) -> CGImage { SlideImageFixtures.banded(fraction: f) }

    private func service(_ source: any FrameSource) -> ScreenCaptureService {
        ScreenCaptureService(recordingsRoot: root,
                             frameSourceFactory: { _ in source },
                             ocr: { _ in "" },
                             reindex: { _, _ in })
    }

    private func coordinator(_ service: ScreenCaptureService) -> CaptureSessionCoordinator {
        CaptureSessionCoordinator(meeting: meeting, screen: screen, service: service, context: context)
    }

    private func option(_ source: CaptureSource,
                        active: Bool = true,
                        windowID: CGWindowID = 42) -> CaptureSourceOption {
        CaptureSourceOption(source: source,
                            badge: source == .teams ? "TEAMS" : "ÉCRAN",
                            title: source.label,
                            subtitle: active ? "Réunion · partage en cours" : "Aucune réunion active",
                            windowID: windowID,
                            isActive: active)
    }

    // MARK: - Ouverture de session

    @Test("capturer sans aucune source ouvre le sélecteur au lieu de capturer au hasard")
    func captureWithoutSourceOpensSelector() async {
        let service = service(ScriptedFrameSource(frames: [banded(0.3)]))
        let coordinateur = coordinator(service)

        #expect(!(await coordinateur.captureNow()))
        #expect(screen.capture.showPopover)
        #expect(!service.hasOpenSession)
    }

    @Test("choisir une source ouvre la session dessus")
    func selectingOpensSession() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 6)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.teams))
        #expect(service.hasOpenSession)
        #expect(service.configuration?.source == .teams)
        #expect(service.configuration?.windowID == 42)
        service.cancelLoopForTesting()
        service.abandon()
    }

    @Test("capturer avec une source retenue ouvre la session et écrit")
    func captureOpensSessionAndWrites() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 6)))
        let coordinateur = coordinator(service)
        screen.capture.selected = option(.teams)

        #expect(await coordinateur.captureNow())
        #expect(coordinateur.captureCount == 1)
        #expect(coordinateur.captures.first?.trigger == .manual)
        service.cancelLoopForTesting()
        service.abandon()
    }

    @Test("le t de la capture vient de la tête de lecture de la réunion")
    func timecodeComesFromThePlayhead() async {
        let debut = Date(timeIntervalSince1970: 1_700_000_000)
        screen.playhead.now = { debut.addingTimeInterval(252) }
        screen.playhead.beginRecording(startedAt: debut)

        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 4)))
        let coordinateur = coordinator(service)
        screen.capture.selected = option(.teams)

        #expect(await coordinateur.captureNow())
        #expect(coordinateur.captures.first?.t == 252)
        service.cancelLoopForTesting()
        service.abandon()
    }

    @Test("sans axe temps, la capture est écrite sans t")
    func noTimelineNoTimecode() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 4)))
        let coordinateur = coordinator(service)
        screen.capture.selected = option(.screen, windowID: 0)

        #expect(await coordinateur.captureNow())
        #expect(coordinateur.captures.first?.t == nil)
        service.cancelLoopForTesting()
        service.abandon()
    }

    @Test("une capture pose son marqueur sur la frise : elle est retrouvable (critère n° 3)")
    func captureIsFindableOnTheTimeline() async {
        let debut = Date(timeIntervalSince1970: 1_700_000_000)
        screen.playhead.now = { debut.addingTimeInterval(728) }
        screen.playhead.beginRecording(startedAt: debut)

        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 4)))
        let coordinateur = coordinator(service)
        screen.capture.selected = option(.teams)

        #expect(await coordinateur.captureNow())
        let carres = screen.playhead.markers.filter { $0.kind == .capture }
        #expect(carres.map(\.t) == [728])
        service.cancelLoopForTesting()
        service.abandon()
    }

    // MARK: - Changement de source

    @Test("choisir la même source deux fois n'ouvre pas une seconde session")
    func selectingSameSourceIsANoOp() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 8)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.teams))
        let premier = service.currentAttachment?.persistentModelID
        await coordinateur.select(option(.teams))
        #expect(service.currentAttachment?.persistentModelID == premier)
        service.cancelLoopForTesting()
        service.abandon()
    }

    @Test("changer de source clôt le lot courant et en ouvre un sur la nouvelle")
    func changingSourceRestartsTheSession() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 12)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.teams))
        service.cancelLoopForTesting()
        #expect(service.configuration?.source == .teams)

        await coordinateur.select(option(.screen, windowID: 0))
        // Une session porte **une** source, figée à sa construction : le
        // sélecteur ne peut pas confirmer un choix sans effet.
        #expect(service.configuration?.source == .screen)
        service.cancelLoopForTesting()
        service.abandon()
    }

    // MARK: - ⌘⇧S

    @Test("⌘⇧S ouvre le sélecteur la première fois, capture ensuite")
    func shortcutOpensThenCaptures() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 8)))
        let coordinateur = coordinator(service)

        // Première utilisation : aucune source retenue. `refreshOptions()`
        // toucherait ScreenCaptureKit, mais l'ouverture du sélecteur est
        // publiée **avant** l'énumération : c'est ce que le test observe.
        #expect(CaptureState.shortcutOutcome(selected: nil, sourceLost: false) == .openSelector)

        // Source retenue : le raccourci capture directement.
        screen.capture.selected = option(.teams)
        #expect(CaptureState.shortcutOutcome(selected: screen.capture.selected,
                                             sourceLost: service.isSourceLost) == .captureNow)
        #expect(await coordinateur.captureNow())
        #expect(coordinateur.captureCount == 1)
        service.cancelLoopForTesting()
        service.abandon()
    }

    // MARK: - Pilule d'état

    @Test("la pilule du coordinateur suit l'état réel du service")
    func pillFollowsService() async {
        let service = service(ScriptedFrameSource(frames: [banded(0.3), nil]))
        let coordinateur = coordinator(service)

        #expect(coordinateur.pill == .idle)

        await coordinateur.select(option(.teams))
        service.cancelLoopForTesting()
        #expect(coordinateur.pill == .armed(source: .teams, count: 0, automatic: true))

        // La source disparaît : la pilule le dit, sans dialogue.
        await service.tick()
        await service.tick()
        #expect(coordinateur.pill == .lost(count: 0))
        service.abandon()
    }

    @Test("les bascules du sélecteur atteignent le service et le service seul décide")
    func togglesReachTheService() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 8)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.teams))
        service.cancelLoopForTesting()

        coordinateur.setPeriodicCapture(true)
        #expect(service.configuration?.periodicCapture == CaptureState.periodicInterval)
        #expect(screen.capture.periodicCapture == CaptureState.periodicInterval)

        coordinateur.setAutomaticDetection(false)
        #expect(service.configuration?.detectsAutomatically == false)
        #expect(!screen.capture.detectsAutomatically)
        service.abandon()
    }

    @Test("les défauts du type s'appliquent à l'ouverture de la session")
    func kindDefaultsApplyOnSessionStart() async {
        meeting.kind = .oneToOne
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 6)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.teams))
        // Profil 1:1 : aucune capture sans geste, même sur une source active.
        #expect(service.configuration?.detectsAutomatically == false)
        #expect(!screen.capture.detectsAutomatically)
        service.cancelLoopForTesting()
        service.abandon()
        meeting.kind = .project
    }

    @Test("une source inactive ouvre la session sans détection automatique")
    func inactiveSourceOpensWithoutDetection() async {
        let service = service(ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 4)))
        let coordinateur = coordinator(service)

        await coordinateur.select(option(.zoom, active: false, windowID: 0))
        // Rien à détecter : armer la détection donnerait une pilule qui promet
        // des captures qui ne viendront pas.
        #expect(service.configuration?.detectsAutomatically == false)
        service.cancelLoopForTesting()
        service.abandon()
    }
}
