import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import OneToOne

/// Le critère n° 2 du chantier 4 sur la **vraie** chaîne : `captureNow` →
/// `SlideCapture(t)` → `CaptureNoteInsertion` → confirmation, avec la réunion, le
/// coordinateur du lot 7 et les notes en base.
///
/// Aucun ScreenCaptureKit (la source d'images est doublée), aucun `NSPanel`, aucun
/// raccourci Carbon, et surtout aucune activation d'application : l'ouverture du
/// sélecteur est une **fermeture injectée**, que ces tests comptent.
/// Source qui rend toujours la même image : la boucle de la session lit en continu, et
/// une liste finie serait épuisée avant le geste manuel du test.
private final class RepeatingFrameSource: FrameSource, @unchecked Sendable {
    private let image: CGImage
    init(image: CGImage) { self.image = image }
    func captureFrame() async throws -> CGImage? { image }
}

@Suite("SessionPillTarget", .serialized)
@MainActor
struct SessionPillTargetTests {

    private let container: ModelContainer
    private let root: URL
    private let meeting: Meeting
    private let screen: MeetingScreenModel

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pill-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        meeting = Meeting(title: "[P25_110] Partage statut final", date: Date())
        meeting.kind = .project
        container.mainContext.insert(meeting)
        try container.mainContext.save()

        let suite = UserDefaults(suiteName: "SessionPillTargetTests")!
        suite.removePersistentDomain(forName: "SessionPillTargetTests")
        screen = MeetingScreenModel(defaults: suite)
        screen.attach(meetingID: meeting.ensuredStableID)
    }

    private var context: ModelContext { container.mainContext }

    private func service(_ frames: [CGImage?], ocr: String = "") -> ScreenCaptureService {
        ScreenCaptureService(recordingsRoot: root,
                             frameSourceFactory: { _ in ScriptedFrameSource(frames: frames) },
                             ocr: { _ in ocr },
                             reindex: { _, _ in })
    }

    private func option(_ source: CaptureSource = .teams) -> CaptureSourceOption {
        CaptureSourceOption(source: source,
                            badge: "TEAMS",
                            title: "Microsoft Teams",
                            subtitle: "Réunion · partage en cours",
                            windowID: 42,
                            isActive: true)
    }

    /// Une cible branchée sur la réunion du test. `selectorOpenings` compte les retours
    /// dans l'application — ils doivent rester à zéro sur le chemin d'une capture.
    private final class Compteur { var selectorOpenings = 0 }

    private func target(_ service: ScreenCaptureService,
                        compteur: Compteur,
                        recording: Bool = true) -> MeetingPillTarget {
        let handle = ActiveMeetingHandle(meeting: meeting,
                                        screen: screen,
                                        context: context) { [meeting, screen, context] in
            CaptureSessionCoordinator(meeting: meeting, screen: screen, service: service, context: context)
        }
        return MeetingPillTarget(handle: handle,
                                 isRecording: { _ in recording },
                                 onOpenSourceSelector: { _ in compteur.selectorOpenings += 1 })
    }

    // MARK: - La chaîne complète

    @Test("capturer depuis la pastille écrit la capture au t de la réunion, l'insère dans les notes, et ne ramène personne dans l'app")
    func fullChainWithoutReturningToTheApp() async throws {
        // La réunion enregistre depuis 18 min 42 s : le `t` de la capture doit être
        // celui de l'axe audio, pas l'horloge de la session de capture.
        let debut = Date().addingTimeInterval(-1_122)
        meeting.recordingStartedAt = debut
        screen.playhead.beginRecording(startedAt: debut)

        let compteur = Compteur()
        let service = service([SlideImageFixtures.banded(fraction: 0.2)], ocr: "Marine : 21 000 €")
        let cible = target(service, compteur: compteur)
        screen.capture.selected = option()

        let resultat = await cible.captureNow()

        guard case .captured(let capture) = resultat else {
            Issue.record("capture attendue, obtenu \(resultat)")
            return
        }
        // 1. La capture est écrite, avec un timecode issu du playhead.
        let ecrites = meeting.attachments.flatMap(\.slides)
        #expect(ecrites.count == 1)
        #expect(ecrites.first?.id == capture.id)
        #expect(capture.t != nil)
        #expect((capture.t ?? 0) >= 1_122)
        #expect(capture.thumbnailPath.hasSuffix(".png"))
        #expect(ecrites.first?.trigger == .manual)

        // 2. La vignette a glissé dans les notes, au timecode de la capture, par
        //    référence et non par copie.
        let notes = meeting.timedNotes
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.sourceRef?.kind == .capture)
        #expect(note.sourceRef?.stableID == capture.id)
        #expect(note.t == capture.t)

        // 3. Aucun retour dans l'application.
        #expect(compteur.selectorOpenings == 0)
        #expect(screen.capture.showPopover == false)

        await service.finish()
    }

    @Test("deux captures de suite n'insèrent pas deux fois la même note")
    func insertionIsIdempotentPerCapture() async throws {
        let debut = Date().addingTimeInterval(-60)
        screen.playhead.beginRecording(startedAt: debut)
        let compteur = Compteur()
        // Source intarissable : la boucle de la session consomme des images en
        // continu, et une liste finie serait épuisée avant le second geste manuel — la
        // pastille verrait alors « source introuvable ». La détection automatique est
        // coupée pour que seules les deux captures manuelles soient écrites.
        let service = ScreenCaptureService(
            recordingsRoot: root,
            frameSourceFactory: { _ in RepeatingFrameSource(image: SlideImageFixtures.banded(fraction: 0.2)) },
            ocr: { _ in "" },
            reindex: { _, _ in })
        let cible = target(service, compteur: compteur)
        screen.capture.setAutomaticDetection(false)
        screen.capture.selected = option()

        _ = await cible.captureNow()
        _ = await cible.captureNow()

        #expect(meeting.attachments.flatMap(\.slides).count == 2)
        // Une note par capture, et aucune en double.
        #expect(meeting.timedNotes.count == 2)
        let references = Set(meeting.timedNotes.compactMap { $0.sourceRef?.stableID })
        #expect(references.count == 2)

        await service.finish()
    }

    @Test("sans aucune source, la pastille demande le sélecteur au lieu de capturer dans le vide")
    func withoutSourceItAsksForTheSelector() async {
        let compteur = Compteur()
        let service = service([SlideImageFixtures.banded(fraction: 0.2)])
        let cible = target(service, compteur: compteur)
        // `screen.capture.selected` est nil et le catalogue n'a jamais été construit.

        let resultat = await cible.captureNow()
        #expect(resultat == .needsSource)
        #expect(meeting.attachments.flatMap(\.slides).isEmpty)
        // Le protocole n'ouvre le sélecteur que si le modèle le décide : la cible ne l'a
        // pas fait d'elle-même.
        #expect(compteur.selectorOpenings == 0)

        cible.openSourceSelector()
        #expect(compteur.selectorOpenings == 1)
        #expect(screen.capture.showPopover)
    }

    @Test("une source perdue rend l'échec, avec le message du service")
    func lostSourceFails() async {
        let compteur = Compteur()
        // La source rend `nil` dès le premier appel : fenêtre disparue.
        let service = service([])
        let cible = target(service, compteur: compteur)
        screen.capture.selected = option()

        let resultat = await cible.captureNow()
        if case .failed = resultat {
            // Attendu.
        } else {
            Issue.record("échec attendu, obtenu \(resultat)")
        }
        #expect(meeting.attachments.flatMap(\.slides).isEmpty)
        #expect(compteur.selectorOpenings == 0)
    }

    // MARK: - Note et action

    @Test("la note de la pastille est créée au t courant, avec les commandes de note")
    func noteAtCurrentTimecode() async {
        screen.playhead.beginRecording(startedAt: Date().addingTimeInterval(-300))
        let compteur = Compteur()
        let cible = target(service([]), compteur: compteur)

        #expect(cible.createNote("Reprise AP à chiffrer"))
        #expect(cible.createNote("/décision On part sur la V3"))
        #expect(cible.createNote("   ") == false)

        let notes = MeetingNoteStore.sorted(meeting.timedNotes)
        #expect(notes.count == 2)
        #expect(notes.contains { $0.kind == .decision && $0.text == "On part sur la V3" })
        #expect(notes.allSatisfy { $0.t >= 300 })
        #expect(compteur.selectorOpenings == 0)
    }

    @Test("l'action depuis la capture porte la première ligne d'OCR et la chaîne de citation")
    func actionFromCapture() async throws {
        screen.playhead.beginRecording(startedAt: Date().addingTimeInterval(-1_122))
        let compteur = Compteur()
        let service = service([SlideImageFixtures.banded(fraction: 0.2)],
                              ocr: "Marine : 21 000 €\nReprise AP : 8 000 €")
        let cible = target(service, compteur: compteur)
        screen.capture.selected = option()

        let resultat = await cible.captureNow()
        guard case .captured(let capture) = resultat else {
            Issue.record("capture attendue, obtenu \(resultat)")
            return
        }
        // L'OCR est écrit par une tâche détachée : on l'attend comme le fait le lot 7.
        await service.drainOCRTasksForTesting()
        #expect(cible.firstOCRLine(forCaptureID: capture.id) == "Marine : 21 000 €")

        // Une saisie en cours dans le rail ne doit pas être consommée par la pastille.
        screen.newTaskTitle = "titre à moitié tapé"
        #expect(cible.createAction(fromCaptureID: capture.id))
        #expect(screen.newTaskTitle == "titre à moitié tapé")

        let action = try #require(meeting.tasks.first)
        #expect(action.title == "Marine : 21 000 €")
        #expect(action.sourceRef?.kind == .capture)
        #expect(action.sourceRef?.stableID == capture.id)
        #expect(screen.pendingActionDraft == nil)
        #expect(compteur.selectorOpenings == 0)

        await service.finish()
    }

    @Test("une capture inconnue ne crée pas d'action")
    func unknownCaptureCreatesNothing() {
        let cible = target(service([]), compteur: Compteur())
        #expect(cible.createAction(fromCaptureID: UUID()) == false)
        #expect(meeting.tasks.isEmpty)
    }

    // MARK: - Chrono

    @Test("sans axe temps, le chrono est absent plutôt que faux")
    func elapsedIsNilWithoutTimeline() {
        let cible = target(service([]), compteur: Compteur())
        #expect(cible.elapsed == nil)

        screen.playhead.beginRecording(startedAt: Date().addingTimeInterval(-42))
        #expect((cible.elapsed ?? 0) >= 42)
    }
}
