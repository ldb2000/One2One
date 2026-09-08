import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import OneToOne

/// Horloge de test : le temps n'avance que quand le test le décide. Sans elle,
/// vérifier la capture périodique demanderait d'attendre deux minutes.
///
/// Portée de `TestClock` du dépôt Teams-Capture (programme §2.5).
final class CaptureTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Transposition des tests de `CaptureCoordinatorTests` de Teams-Capture sur le
/// coordinateur de OneToOne, `ScreenCaptureService` (programme §5, lot 7
/// tâche 0) : détection coupée, capture périodique qui **arme** l'écriture,
/// capture manuelle, `t` pris sur l'axe audio, `trigger` et `source` persistés.
///
/// Aucun test ne touche ScreenCaptureKit : la source est doublée (`FrameSource`).
///
/// `.serialized` pour la même raison que `ScreenCaptureServiceTests` : plusieurs
/// `ModelContainer` en mémoire pour un même schéma versionné, construits en
/// parallèle, ne sont pas garantis indépendants.
@Suite("Capture — coordinateur porté", .serialized)
@MainActor
struct CapturePortedCoordinatorTests {

    private let container: ModelContainer
    private let root: URL
    private let meeting: Meeting

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-porte-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        meeting = Meeting(title: "Réunion", date: Date())
        container.mainContext.insert(meeting)
        try container.mainContext.save()
    }

    private var context: ModelContext { container.mainContext }

    private func banded(_ f: Double) -> CGImage { SlideImageFixtures.banded(fraction: f) }

    private func service(source: any FrameSource,
                         clock: CaptureTestClock = CaptureTestClock()) -> ScreenCaptureService {
        ScreenCaptureService(
            recordingsRoot: root,
            frameSourceFactory: { _ in source },
            ocr: { _ in "" },
            reindex: { _, _ in },
            now: { clock.now }
        )
    }

    private func config(kind: MeetingKind,
                        source: CaptureSource = .teams) -> ScreenCaptureService.SessionConfiguration {
        let profil = kind.captureProfile
        return .init(windowID: 42,
                     windowTitle: "Microsoft Teams",
                     crop: .full,
                     sensitivity: profil.sensitivity,
                     source: source,
                     detectsAutomatically: profil.detectsAutomatically,
                     periodicCapture: profil.periodicCapture)
    }

    private func slides(_ service: ScreenCaptureService) -> [SlideCapture] {
        (service.currentAttachment?.slides ?? []).sorted { $0.index < $1.index }
    }

    // MARK: - Détection automatique coupée

    @Test("détection coupée : aucune capture n'est écrite d'elle-même")
    func detectionOffWritesNothing() async throws {
        let images = [banded(0.2), banded(0.2), banded(0.2), banded(0.9), banded(0.9), banded(0.9)]
        let service = service(source: ScriptedFrameSource(frames: images))
        // Un 1:1 : profil sans détection automatique.
        try service.beginSession(configuration: config(kind: .oneToOne), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        for _ in 0..<6 { await service.tick() }

        #expect(slides(service).isEmpty)
        #expect(service.state == .running)
        service.abandon()
    }

    @Test("détection coupée : la disparition de la source est toujours signalée")
    func detectionOffStillReportsMissingSource() async throws {
        let service = service(source: ScriptedFrameSource(frames: [banded(0.3), nil]))
        try service.beginSession(configuration: config(kind: .manager), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()

        #expect(service.state.isPaused)
        // Spec §5.2 : la pilule passe en `accent/warn` avec un lien de
        // reconfiguration, et **aucune** boîte de dialogue ne s'ouvre.
        #expect(service.isSourceLost)
        service.abandon()
    }

    @Test("détection coupée : la capture manuelle écrit quand même")
    func detectionOffManualStillWrites() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 6)))
        try service.beginSession(configuration: config(kind: .oneToOne), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        #expect(slides(service).isEmpty)
        #expect(await service.captureNow())
        #expect(slides(service).count == 1)
        #expect(slides(service)[0].trigger == .manual)
        service.abandon()
    }

    // MARK: - Capture périodique

    @Test("capture périodique : l'échéance force une écriture sur un contenu inchangé")
    func periodicCaptureFires() async throws {
        let clock = CaptureTestClock()
        let service = service(
            source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 12)),
            clock: clock)
        // Atelier : détection élevée + capture forcée toutes les 2 minutes.
        try service.beginSession(configuration: config(kind: .workshop), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()
        await service.tick()
        #expect(slides(service).count == 1)                  // la première, automatique
        #expect(slides(service)[0].trigger == .shareChange)

        clock.advance(by: 119)
        await service.tick()
        #expect(slides(service).count == 1)                  // l'échéance n'est pas atteinte

        clock.advance(by: 1)
        await service.tick()
        #expect(slides(service).count == 2)
        #expect(slides(service)[1].trigger == .interval)
        service.abandon()
    }

    @Test("capture périodique : une capture manuelle repousse l'échéance")
    func manualCaptureDefersPeriodic() async throws {
        let clock = CaptureTestClock()
        let service = service(
            source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 12)),
            clock: clock)
        try service.beginSession(configuration: config(kind: .workshop), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()
        await service.tick()
        #expect(slides(service).count == 1)

        clock.advance(by: 100)
        #expect(await service.captureNow())
        #expect(slides(service).count == 2)

        clock.advance(by: 30)                                // 130 s après l'écriture auto…
        await service.tick()
        #expect(slides(service).count == 2)                  // …mais 30 s après la manuelle

        clock.advance(by: 95)
        await service.tick()
        #expect(slides(service).count == 3)
        #expect(slides(service)[2].trigger == .interval)
        service.abandon()
    }

    @Test("capture périodique : rien pendant le mouvement, une seule écriture au premier tick stable")
    func periodicWaitsForStability() async throws {
        let clock = CaptureTestClock()
        // Les huit premières images diffèrent franchement d'une image à
        // l'autre : le détecteur reste en `.settling`, donc l'échéance ne peut
        // pas écrire — mais ça, une implémentation qui n'écrirait *jamais* rien
        // le vérifierait aussi. Les deux images finales, identiques entre
        // elles, sont ce qui prouve que l'échéance était bien **armée**.
        let frames = (0..<8).map { banded($0.isMultiple(of: 2) ? 0.1 : 0.9) }
            + [banded(0.9), banded(0.9)]
        let service = service(source: ScriptedFrameSource(frames: frames), clock: clock)
        try service.beginSession(configuration: config(kind: .workshop), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        clock.advance(by: 300)
        for _ in 0..<8 { await service.tick() }
        #expect(slides(service).isEmpty)

        // Neuvième tick : première image stable après le mouvement. La
        // décision est `.ignore` (un seul tick stable), ce qui suffit à la voie
        // périodique — l'échéance est dépassée depuis longtemps.
        await service.tick()
        // Dixième tick : deuxième image stable, identique à celle déjà écrite.
        // `lastWriteAt` vient d'être posé : l'échéance n'est pas rouverte.
        await service.tick()

        #expect(slides(service).count == 1)
        #expect(slides(service)[0].trigger == .interval)
        service.abandon()
    }

    @Test("capture périodique coupée : rien n'est forcé, même après une heure")
    func periodicOffForcesNothing() async throws {
        let clock = CaptureTestClock()
        let service = service(
            source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 8)),
            clock: clock)
        // Projet : détection automatique, mais pas de périodique.
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()
        await service.tick()
        #expect(slides(service).count == 1)

        clock.advance(by: 3600)
        await service.tick()
        await service.tick()
        #expect(slides(service).count == 1)
        service.abandon()
    }

    @Test("les bascules du sélecteur s'appliquent en cours de séance")
    func togglesApplyMidSession() async throws {
        let clock = CaptureTestClock()
        let service = service(
            source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 10)),
            clock: clock)
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        // Détection coupée en pleine séance : le contenu suivant n'est plus écrit.
        service.setAutomaticDetection(false)
        for _ in 0..<3 { await service.tick() }
        #expect(slides(service).isEmpty)

        // Périodique activée : la prochaine échéance écrit.
        service.setPeriodicCapture(.seconds(120))
        clock.advance(by: 121)
        await service.tick()
        #expect(slides(service).count == 1)
        #expect(slides(service)[0].trigger == .interval)
        #expect(service.configuration?.periodicCapture == .seconds(120))
        service.abandon()
    }

    // MARK: - Timecode, source, déclencheur

    @Test("chaque capture porte le t de l'axe audio, pas celui de la session")
    func timecodeComesFromPlayhead() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.4), count: 8)))
        var position: Double? = 252            // 04:12 sur la capture 4a
        try service.beginSession(configuration: config(kind: .project),
                                 meeting: meeting,
                                 context: context,
                                 timecode: { position })
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()
        await service.tick()
        #expect(slides(service).count == 1)
        #expect(slides(service)[0].t == 252)

        position = 535                          // 08:55
        #expect(await service.captureNow())
        #expect(slides(service)[1].t == 535)
        #expect(slides(service)[1].source == .teams)
        service.abandon()
    }

    @Test("sans axe temps, la capture est écrite sans t — jamais à 00:00")
    func noTimelineMeansNoTimecode() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.4), count: 4)))
        try service.beginSession(configuration: config(kind: .project),
                                 meeting: meeting,
                                 context: context,
                                 timecode: { nil })
        service.cancelLoopForTesting()

        #expect(await service.captureNow())
        // Un `t` à zéro poserait un marqueur de frise à `00:00`, c'est-à-dire à
        // un instant où rien ne s'est passé (`MeetingTimelineMarkers`).
        #expect(slides(service)[0].t == nil)
        service.abandon()
    }

    @Test("la source du sélecteur est persistée sur chaque capture")
    func sourceIsPersisted() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.4), count: 4)))
        try service.beginSession(configuration: config(kind: .project, source: .zoom),
                                 meeting: meeting,
                                 context: context)
        service.cancelLoopForTesting()

        #expect(await service.captureNow())
        #expect(slides(service)[0].source == .zoom)
        service.abandon()
    }

    // MARK: - Capture manuelle

    @Test("la capture manuelle n'est pas réécrite par le tick suivant")
    func manualCaptureIsNotDuplicated() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 8)))
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        #expect(await service.captureNow())
        #expect(slides(service).count == 1)

        // Sans l'`acknowledge` de `captureNow`, ces ticks stabiliseraient sur
        // le même contenu et l'écriraient une seconde fois.
        for _ in 0..<4 { await service.tick() }
        #expect(slides(service).count == 1)
        service.abandon()
    }

    @Test("la capture manuelle écrit même boucle arrêtée, sans changer l'état")
    func manualCaptureWorksWhileStopped() async throws {
        let service = service(source: ScriptedFrameSource(frames: Array(repeating: banded(0.3), count: 6)))
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()
        service.stop()
        #expect(service.state == .stopped)

        #expect(await service.captureNow())
        #expect(slides(service).count == 1)
        // Un geste manuel ne relance pas la session : c'est au tick de décider
        // de l'état, sur son propre constat.
        #expect(service.state == .stopped)
        service.abandon()
    }

    @Test("la capture manuelle sur une source disparue explique l'échec sans mettre en pause")
    func manualCaptureOnLostSourceExplains() async throws {
        let service = service(source: ScriptedFrameSource(frames: []))
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        #expect(!(await service.captureNow()))
        #expect(service.lastError != nil)
        #expect(service.state == .running)
        #expect(!service.isSourceLost)
        service.abandon()
    }

    @Test("la capture manuelle sans session ouverte n'écrit rien")
    func manualCaptureWithoutSessionDoesNothing() async throws {
        let service = service(source: ScriptedFrameSource(frames: [banded(0.3)]))
        #expect(!(await service.captureNow()))
        #expect(service.currentAttachment == nil)
    }

    // MARK: - Message d'erreur remis à zéro (piège 14)

    @Test("une écriture réussie effface le message d'erreur d'une panne passée")
    func successClearsLastError() async throws {
        let source = FailingFrameSource(outcomes: [.failure, .frame(banded(0.3)), .frame(banded(0.3))])
        let service = service(source: source)
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        #expect(service.lastError != nil)

        #expect(await service.captureNow())
        #expect(service.lastError == nil)
        service.abandon()
    }

    @Test("un tick réussi après la perte de la source lève la pause et sa cause")
    func successfulTickClearsSourceLost() async throws {
        let service = service(source: ScriptedFrameSource(frames: [banded(0.3), nil]))
        try service.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service.cancelLoopForTesting()

        await service.tick()
        await service.tick()
        #expect(service.isSourceLost)

        // La source réapparaît : `ScriptedFrameSource` est épuisée, on en
        // remonte une neuve par la reprise de session.
        let service2 = self.service(source: ScriptedFrameSource(frames: [banded(0.5), banded(0.5), banded(0.5)]))
        try service2.beginSession(configuration: config(kind: .project), meeting: meeting, context: context)
        service2.cancelLoopForTesting()
        await service2.tick()
        #expect(!service2.isSourceLost)
        #expect(service2.pauseCause == nil)
        service.abandon()
        service2.abandon()
    }
}
