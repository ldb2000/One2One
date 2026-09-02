import Testing
import Foundation
import CoreGraphics
import ImageIO
import SwiftData
@testable import OneToOne

// `.serialized` : plusieurs `ModelContainer` construits en parallèle pour le même
// schéma versionné entrent en course entre eux côté SwiftData (crash observé :
// « this model instance was destroyed by calling ModelContext.reset », reproductible
// uniquement quand les 14 tests tournent ensemble, jamais isolément). Chaque test
// reste indépendant (son propre conteneur en mémoire) ; seule l'exécution est
// séquentielle.
@Suite("ScreenCaptureService", .serialized)
@MainActor
struct ScreenCaptureServiceTests {

    private let container: ModelContainer
    private let root: URL
    private let meeting: Meeting

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        meeting = Meeting(title: "Réunion", date: Date())
        container.mainContext.insert(meeting)
        try container.mainContext.save()
    }

    private var context: ModelContext { container.mainContext }

    private func banded(_ f: Double) -> CGImage { SlideImageFixtures.banded(fraction: f) }

    private func config(crop: NormalizedRect = .full) -> ScreenCaptureService.SessionConfiguration {
        .init(windowID: 42, windowTitle: "Teams", crop: crop, sensitivity: .normal)
    }

    /// Service branché sur une source de test ; OCR et réindexation neutralisés.
    private func makeService(source: any FrameSource) -> ScreenCaptureService {
        ScreenCaptureService(
            recordingsRoot: root,
            frameSourceFactory: { _ in source },
            ocr: { _ in "" },
            reindex: { _, _ in }
        )
    }

    private func pngNames(_ service: ScreenCaptureService) throws -> [String] {
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
    }

    @Test("un tick avant beginSession est inerte")
    func tickBeforeSessionIsInert() async throws {
        let service = makeService(source: ScriptedFrameSource(frames: [banded(0.3)]))
        await service.tick()
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(try pngNames(service).isEmpty)
    }

    @Test("beginSession crée l'attachment et le dossier tout de suite, sans capturer")
    func beginSessionCreatesAttachmentAndDirectory() async throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        #expect(service.state == .running)
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.kind == "slides")
        #expect(attachment.meeting === meeting)
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(service.capturedSlidesCount == 0)
    }

    @Test("deux slides distincts donnent deux SlideCapture et deux PNG numérotés sur quatre chiffres")
    func writesOneSlidePerStableChange() async throws {
        let first = banded(0.2), second = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [first, first, first, first, second, second, second, second]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<8 { await service.tick() }

        #expect(service.capturedSlidesCount == 2)
        let slides = try #require(service.currentAttachment).slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2])
        let names = try pngNames(service)
        #expect(names.count == 2)
        #expect(names[0].hasPrefix("slide-0001-"))
        #expect(names[1].hasPrefix("slide-0002-"))
        #expect(slides.allSatisfy { FileManager.default.fileExists(atPath: $0.imagePath) })
        await service.drainOCRTasksForTesting()
    }

    @Test("le crop est appliqué à l'image écrite")
    func appliesCrop() async throws {
        let frame = SlideImageFixtures.solid(gray: 0.4, width: 800, height: 600)
        let service = makeService(source: ScriptedFrameSource(frames: [frame, frame, frame, frame]))
        try service.beginSession(configuration: config(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let slide = try #require(service.currentAttachment?.slides.first)
        let fp = try #require(SlideFingerprint(contentsOf: URL(fileURLWithPath: slide.imagePath)))
        #expect(fp.samples.count == 1024)
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: slide.imagePath) as CFURL, nil)!
        let written = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(written.width == 400)
        #expect(written.height == 300)
        await service.drainOCRTasksForTesting()
    }

    @Test("la disparition de la fenêtre met en pause, sa réapparition remet en cours et efface l'erreur")
    func pausesAndResumesOnSourcePresence() async throws {
        let image = banded(0.3)
        let source = FailingFrameSource(outcomes: [.frame(image), .frame(nil), .failure, .frame(image)])
        let service = makeService(source: source)
        try service.beginSession(configuration: config(), meeting: meeting, context: context)

        await service.tick()
        #expect(service.state == .running)
        await service.tick() // nil
        guard case .paused(let reason) = service.state else { Issue.record("attendu paused, obtenu \(service.state)"); return }
        #expect(reason.contains("introuvable"))
        await service.tick() // échec d'API
        guard case .paused(let reason2) = service.state else { Issue.record("attendu paused, obtenu \(service.state)"); return }
        #expect(reason2.contains("panne simulée"))
        #expect(service.lastError != nil)
        await service.tick() // retour
        #expect(service.state == .running)
        #expect(service.lastError == nil)
    }

    @Test("stop publie stopped et garde la session ; resume reprend sur le même attachment")
    func stopThenResumeKeepsAttachment() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: Array(repeating: image, count: 8)))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.slides.count == 1)

        service.stop()
        #expect(service.state == .stopped)
        #expect(service.currentAttachment === attachment)
        #expect(service.hasOpenSession)
        await service.tick() // inerte en stopped
        #expect(service.capturedSlidesCount == 1)

        service.resume()
        // Aucun await depuis resume() : la boucle relancée n'a pas encore tické. On l'annule
        // pour continuer à piloter les ticks à la main ; l'état running vient de resume().
        service.cancelLoopForTesting()
        #expect(service.state == .running)
        #expect(service.currentAttachment === attachment)
        #expect(throws: ScreenCaptureService.SessionError.sessionAlreadyOpen) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
        await service.drainOCRTasksForTesting()
    }

    @Test("beginSession refuse d'ouvrir une seconde session")
    func beginSessionTwiceThrows() throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        #expect(throws: ScreenCaptureService.SessionError.sessionAlreadyOpen) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
    }

    @Test("après resume, les ticks continuent la numérotation et un retour arrière est un doublon")
    func ticksAfterResumeContinueNumbering() async throws {
        let first = banded(0.2), second = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [first, first, first, first, second, second, second, second, first, first, first, first]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        service.stop()
        service.resume()
        service.cancelLoopForTesting() // aucun await depuis resume() : la boucle n'a pas tické
        #expect(service.state == .running)
        for _ in 0..<8 { await service.tick() } // second → slide 2 ; retour sur first → doublon
        let slides = try #require(service.currentAttachment).slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2])
        #expect(try pngNames(service).count == 2)
        await service.drainOCRTasksForTesting()
    }

    @Test("finish clôt la session : idle, attachment relâché, un start suivant ouvre un nouvel attachment")
    func finishClosesSessionAndNextStartOpensNewAttachment() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: Array(repeating: image, count: 8)))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<4 { await service.tick() }
        let firstAttachment = try #require(service.currentAttachment)
        #expect(firstAttachment.slides.count == 1)

        await service.finish()
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(service.configuration == nil)
        await service.tick() // inerte
        #expect(firstAttachment.slides.count == 1)

        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        let secondAttachment = try #require(service.currentAttachment)
        #expect(secondAttachment !== firstAttachment)
        #expect(meeting.attachments.filter { $0.kind == "slides" }.count == 2)
    }

    @Test("un tick en vol pendant finish n'écrit ni PNG ni SlideCapture après la clôture")
    func inFlightTickCannotWriteAfterFinish() async throws {
        let first = banded(0.2), second = banded(0.8)
        // 4 ticks stables sur first → slide 1. 2 ticks sur second → armé, un tick stable :
        // le septième tick (en vol) est celui qui confirmerait le second slide.
        let source = SuspendingFrameSource(immediateFrames: [first, first, first, first, second, second])
        let service = makeService(source: source)
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        for _ in 0..<6 { await service.tick() }
        let attachment = try #require(service.currentAttachment)
        #expect(attachment.slides.count == 1)

        let inFlight = Task { @MainActor in await service.tick() }
        await source.waitUntilSuspended()

        await service.finish()
        let namesAtFinish = try pngNames(service)
        #expect(namesAtFinish.count == 1)

        source.resume(with: second)
        await inFlight.value

        #expect(try pngNames(service) == namesAtFinish, "PNG apparus APRÈS la clôture")
        #expect(attachment.slides.count == 1)
        #expect(service.state == .idle)
    }

    @Test("snapshot écrit l'image courante sans attendre la stabilisation, et le détecteur la connaît ensuite")
    func snapshotWritesImmediately() async throws {
        let image = banded(0.3)
        let service = makeService(source: ScriptedFrameSource(frames: [image, image, image, image, image]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context)
        await service.tick() // une seule référence, rien d'écrit
        #expect(service.capturedSlidesCount == 0)
        await service.snapshotForTesting()
        #expect(service.capturedSlidesCount == 1)
        for _ in 0..<3 { await service.tick() } // stabilisation : doublon, pas de second fichier
        #expect(service.capturedSlidesCount == 1)
        await service.drainOCRTasksForTesting()
    }

    @Test("appendTo reprend un lot existant : numérotation après le dernier index, PNG existants connus du détecteur")
    func appendToExistingAttachmentSeedsDetector() async throws {
        // Lot préexistant : un attachment avec un PNG déjà sur disque.
        let dir = root.appendingPathComponent(meeting.ensuredStableID.uuidString).appendingPathComponent("slides")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existingURL = dir.appendingPathComponent("slide-0001-090000.png")
        try SlideImageFixtures.writePNG(banded(0.2), to: existingURL)
        let previous = MeetingAttachment(url: URL(fileURLWithPath: "slides-old.slides"), kind: "slides")
        previous.meeting = meeting
        context.insert(previous)
        let existing = SlideCapture(index: 1, capturedAt: Date(), imagePath: existingURL.path)
        existing.attachment = previous
        context.insert(existing)
        try context.save()

        let known = banded(0.2), fresh = banded(0.8)
        let service = makeService(source: ScriptedFrameSource(frames: [known, known, known, known, fresh, fresh, fresh, fresh]))
        try service.beginSession(configuration: config(), meeting: meeting, context: context, appendTo: previous)
        #expect(service.currentAttachment === previous)
        for _ in 0..<8 { await service.tick() }

        let slides = previous.slides.sorted { $0.index < $1.index }
        #expect(slides.map(\.index) == [1, 2]) // le slide connu n'est pas réécrit
        #expect(try pngNames(service).count == 2)
        #expect(try pngNames(service)[1].hasPrefix("slide-0002-"))
        await service.drainOCRTasksForTesting()
    }

    @Test("une racine non inscriptible fait échouer beginSession avant toute capture")
    func unwritableRootFailsEarly() throws {
        let service = ScreenCaptureService(
            recordingsRoot: URL(fileURLWithPath: "/dev/null/impossible"),
            frameSourceFactory: { _ in ScriptedFrameSource(frames: []) },
            ocr: { _ in "" },
            reindex: { _, _ in }
        )
        #expect(throws: (any Error).self) {
            try service.beginSession(configuration: config(), meeting: meeting, context: context)
        }
        #expect(service.state == .idle)
        #expect(service.currentAttachment == nil)
        #expect(meeting.attachments.isEmpty)
    }

    @Test("updateSource n'agit qu'en stopped et conserve la zone")
    func updateSourceOnlyWhenStopped() throws {
        let service = makeService(source: ScriptedFrameSource(frames: []))
        let crop = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        try service.beginSession(configuration: config(crop: crop), meeting: meeting, context: context)
        service.updateSource(windowID: 7, title: "Zoom")
        #expect(service.configuration?.windowID == 42) // ignoré en running
        service.stop()
        service.updateSource(windowID: 7, title: "Zoom")
        #expect(service.configuration?.windowID == 7)
        #expect(service.configuration?.windowTitle == "Zoom")
        #expect(service.configuration?.crop == crop)
    }
}
