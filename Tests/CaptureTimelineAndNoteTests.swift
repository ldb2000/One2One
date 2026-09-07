import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les critères d'acceptation n° 3 et n° 4 du chantier 4 :
/// « chaque capture est reliée à un timecode et retrouvable depuis la frise »
/// et « le texte extrait est cherchable dans la réunion ».
///
/// Aucun appel MLX : `reindexAttachment` embarque un pipeline d'embeddings que
/// `swift test` ne peut pas exécuter (pas de `default.metallib`, cf. CLAUDE.md).
/// Ce qui est vérifié ici, c'est la chaîne **observable** : OCR →
/// `extractedText` du lot → chunks → index lexical qui retrouve la phrase.
@Suite("Captures — frise, note et recherche", .serialized)
@MainActor
struct CaptureTimelineAndNoteTests {

    private let container: ModelContainer
    private let meeting: Meeting

    init() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        meeting = Meeting(title: "[P25_110] Partage statut final", date: Date())
        meeting.durationSeconds = 1404
        container.mainContext.insert(meeting)
        try container.mainContext.save()
    }

    private var context: ModelContext { container.mainContext }

    /// Un lot de captures rattaché à la réunion, comme le service en crée un.
    private func batch() -> MeetingAttachment {
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/lot.slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        lot.fileName = "Captures"
        lot.meeting = meeting
        context.insert(lot)
        return lot
    }

    @discardableResult
    private func capture(in lot: MeetingAttachment,
                         index: Int,
                         t: Double?,
                         trigger: CaptureTrigger = .shareChange,
                         ocr: String = "") -> SlideCapture {
        let capture = SlideCapture(index: index, capturedAt: Date(), imagePath: "/tmp/slide-\(index).png")
        capture.t = t
        capture.trigger = trigger
        capture.ocrText = ocr
        capture.attachment = lot
        context.insert(capture)
        return capture
    }

    // MARK: - Critère n° 3 : un timecode et un marqueur par capture

    @Test("chaque capture horodatée porte un marqueur carré sur la frise")
    func everyCaptureHasAMarker() {
        let lot = batch()
        capture(in: lot, index: 1, t: 252)
        capture(in: lot, index: 2, t: 535)
        capture(in: lot, index: 3, t: 728, trigger: .manual)

        let reperes = MeetingTimelineMarkers.allMarkers(for: meeting)
        let carres = reperes.filter { $0.kind == .capture }
        #expect(carres.count == 3)
        #expect(carres.map(\.t) == [252, 535, 728])
    }

    @Test("une capture sans timecode n'a pas de marqueur — jamais un carré à 00:00")
    func captureWithoutTimecodeHasNoMarker() {
        let lot = batch()
        capture(in: lot, index: 1, t: nil)
        #expect(MeetingTimelineMarkers.allMarkers(for: meeting).filter { $0.kind == .capture }.isEmpty)
    }

    @Test("le dernier carré est désigné : c'est celui que la frise met en accent/action")
    func lastCaptureIsIdentified() {
        let lot = batch()
        capture(in: lot, index: 1, t: 252)
        capture(in: lot, index: 2, t: 728)
        capture(in: lot, index: 3, t: 535)

        let reperes = MeetingTimelineMarkers.allMarkers(for: meeting)
        #expect(MeetingTimelineMarkers.lastCaptureT(reperes) == 728)
    }

    @Test("sans capture, aucun dernier carré et aucune légende")
    func noCaptureNoLegend() {
        let note = MeetingNote(t: 100, text: "Une note")
        note.meeting = meeting
        context.insert(note)

        let reperes = MeetingTimelineMarkers.allMarkers(for: meeting)
        #expect(!reperes.isEmpty)
        #expect(MeetingTimelineMarkers.lastCaptureT(reperes) == nil)
        #expect(MeetingTimelineMarkers.captureLegend(reperes) == nil)
    }

    @Test("la légende ■ = capture apparaît dès qu'une capture existe")
    func legendAppearsWithCaptures() {
        let lot = batch()
        capture(in: lot, index: 1, t: 252)
        let reperes = MeetingTimelineMarkers.allMarkers(for: meeting)
        #expect(MeetingTimelineMarkers.captureLegend(reperes) == "■ = capture")
    }

    @Test("le carré de capture fait 12 px, comme la spec §5.2")
    func markerSizeMatchesSpec() {
        #expect(MeetingTimelineMarkers.captureMarkerSize == 12)
    }

    // MARK: - Insertion dans une note

    @Test("une capture insérée dans les notes porte un sourceRef {capture, id, t}")
    func insertionCarriesSourceRef() {
        let lot = batch()
        let capture = capture(in: lot, index: 1, t: 728, trigger: .manual, ocr: "tableau de chiffrage")
        let note = CaptureNoteInsertion.insert(capture, in: meeting, context: context)

        let ref = try? #require(note?.sourceRef)
        #expect(ref?.kind == .capture)
        #expect(ref?.stableID == capture.id)
        #expect(ref?.t == 728)
        #expect(note?.t == 728)
        #expect(note?.text == "Capture 12:08 — tableau de chiffrage")
    }

    @Test("insérer deux fois la même capture ne duplique pas la carte")
    func insertionIsIdempotent() {
        let lot = batch()
        let capture = capture(in: lot, index: 1, t: 252)
        let premiere = CaptureNoteInsertion.insert(capture, in: meeting, context: context)
        let seconde = CaptureNoteInsertion.insert(capture, in: meeting, context: context)
        #expect(premiere?.persistentModelID == seconde?.persistentModelID)
        #expect(meeting.timedNotes.count == 1)
    }

    @Test("la carte retrouve sa capture, et rien quand la référence est morte")
    func cardResolvesItsCapture() {
        let lot = batch()
        let capture = capture(in: lot, index: 1, t: 252)
        let note = try? #require(CaptureNoteInsertion.insert(capture, in: meeting, context: context))
        #expect(CaptureNoteInsertion.capture(for: note!, in: meeting)?.id == capture.id)

        // Référence morte : la capture a été supprimée, la colonne doit
        // afficher la ligne de texte et non un cadre vide.
        context.delete(capture)
        try? context.save()
        #expect(CaptureNoteInsertion.capture(for: note!, in: meeting) == nil)
    }

    @Test("une note ordinaire ne porte pas de carte de capture")
    func plainNoteHasNoCard() {
        let note = MeetingNote(t: 100, text: "Une note")
        note.meeting = meeting
        context.insert(note)
        #expect(CaptureNoteInsertion.capture(for: note, in: meeting) == nil)
    }

    @Test("l'action issue d'une capture porte la pilule ◫ mm:ss")
    func actionFromCaptureShowsPill() {
        let lot = batch()
        let capture = capture(in: lot, index: 1, t: 728, trigger: .manual, ocr: "Reprise AP : 3 j-h")
        let brouillon = CaptureNoteInsertion.actionDraft(for: capture)
        #expect(brouillon.title == "Reprise AP : 3 j-h")
        #expect(brouillon.sourceRef?.kind == .capture)

        // La pilule elle-même vient du lot 3 : on vérifie qu'une action
        // construite depuis ce brouillon l'affiche bien (spec §5.3).
        let action = ActionTask(title: brouillon.title)
        action.sourceRef = brouillon.sourceRef
        context.insert(action)
        #expect(ActionCardEditing.libelleSource(action) == "◫ 12:08")
    }

    // MARK: - Critère n° 4 : le texte extrait est cherchable

    @Test("l'OCR d'une capture entre dans le texte indexé du lot")
    func ocrLandsInAttachmentText() throws {
        let lot = batch()
        capture(in: lot, index: 1, t: 252, ocr: "Reprise AP : 3 j-h · Marine : 21 000 €")
        capture(in: lot, index: 2, t: 535, ocr: "Planning migration — jalon du 11 septembre")

        // Même agrégation que `ScreenCaptureService.rebuildAttachmentText`,
        // appelée à chaque OCR terminé.
        var texte = ""
        for capture in lot.slides.sorted(by: { $0.index < $1.index }) {
            texte += "--- Slide \(capture.index) ---\n\(capture.ocrText)\n\n"
        }
        lot.extractedText = texte

        #expect(lot.extractedText.contains("21 000"))
        #expect(lot.extractedText.contains("Planning migration"))

        // Le découpage RAG produit bien au moins un chunk depuis ce texte :
        // c'est ce que `reindexAttachment` insère en `TranscriptChunk`.
        let chunks = TextChunker.chunk(lot.extractedText)
        #expect(!chunks.isEmpty)
        #expect(chunks.contains { $0.contains("Reprise AP") })
    }

    @Test("le chunk d'une capture est retrouvé par une recherche lexicale")
    func ocrChunkIsSearchable() throws {
        let lot = batch()
        capture(in: lot, index: 1, t: 728, ocr: "Reprise AP : 3 j-h · Marine : 21 000 €")
        lot.extractedText = "--- Slide 1 ---\nReprise AP : 3 j-h · Marine : 21 000 €\n"

        var chunks: [TranscriptChunk] = []
        for (index, texte) in TextChunker.chunk(lot.extractedText).enumerated() {
            let chunk = TranscriptChunk(text: texte, orderIndex: index, sourceType: "attachment")
            chunk.meeting = meeting
            chunk.attachment = lot
            context.insert(chunk)
            chunks.append(chunk)
        }
        // Une ligne de transcription, pour que l'index ait de la concurrence :
        // un index à un seul document trouverait n'importe quoi.
        let bruit = TranscriptChunk(text: "On reprend le point sur les congés.",
                                    orderIndex: 99,
                                    sourceType: "transcript")
        bruit.meeting = meeting
        context.insert(bruit)
        chunks.append(bruit)
        try context.save()

        let index = BM25Index(chunks: chunks)
        let scores = index.score(query: "chiffrage Reprise AP Marine")
        let meilleur = scores.max { $0.value < $1.value }
        #expect(meilleur?.key == chunks[0].chunkId)
        // Le chunk de la capture désigne bien le lot de captures : l'assistant
        // peut donc citer la capture, pas seulement son texte.
        #expect(chunks[0].attachment?.kind == AttachmentCopyPolicy.slidesKind)
    }
}
