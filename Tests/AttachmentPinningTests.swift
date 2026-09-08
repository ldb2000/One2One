import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Épinglage et citation d'une pièce (spec §4.2).
///
/// **Critère d'acceptation n° 3 du chantier 3** : « une pièce épinglée est
/// retrouvable par son timecode et citée automatiquement dans le rapport ».
/// La première moitié est tenue ici — `pinnedAtT`, `Meeting.pinnedAttachments`
/// trié, le repère de frise et la puce dans les notes. La seconde arrive au
/// lot 15 ; ce que ce lot doit garantir, c'est que la liste que ce bloc lira
/// existe et soit juste.
@Suite("Épinglage et citation d'une pièce")
@MainActor
struct AttachmentPinningTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func makeMeeting(in context: ModelContext) -> Meeting {
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        reunion.kind = .project
        reunion.notesMigrated = true
        context.insert(reunion)
        return reunion
    }

    @discardableResult
    private func addPiece(_ nom: String, kind: String = "xlsx",
                          to reunion: Meeting, in context: ModelContext) -> MeetingAttachment {
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/\(nom)"), kind: kind)
        piece.fileName = nom
        piece.bookmarkData = nil
        _ = piece.ensuredStableID
        piece.meeting = reunion
        context.insert(piece)
        return piece
    }

    @discardableResult
    private func addNote(_ t: Double, _ texte: String,
                         to reunion: Meeting, in context: ModelContext) -> MeetingNote {
        let note = MeetingNote(t: t, text: texte, kind: .note,
                               orderIndex: MeetingNoteStore.nextOrderIndex(at: t, in: reunion))
        context.insert(note)
        note.meeting = reunion
        return note
    }

    // MARK: - Libellés

    /// La capture montre `◫ Chiffrage_Marine_v3 · p.2` pour un fichier nommé
    /// `Chiffrage_Marine_v3.xlsx` : l'extension est du bruit dans une phrase.
    @Test("La puce suit la capture, sans extension")
    func libelleDeLaPuce() {
        #expect(AttachmentPinning.chipText(name: "Chiffrage_Marine_v3.xlsx", page: 2)
                == "◫ Chiffrage_Marine_v3 · p.2")
        #expect(AttachmentPinning.chipText(name: "Comptes_GitLab.png")
                == "◫ Comptes_GitLab")
        // Une page 0 ou absente n'est pas mentionnée : `p.?` serait un aveu.
        #expect(AttachmentPinning.chipText(name: "a.pdf", page: 0) == "◫ a")
        #expect(AttachmentPinning.displayName("sans-extension") == "sans-extension")
    }

    // MARK: - Épingler

    @Test("Épingler pose le timecode, la puce et la citation")
    func epinglage() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)
        addNote(728, "Le chiffrage v3 annonce 21 000 € pour la fin Marine.",
                to: reunion, in: context)

        let note = AttachmentPinning.pin(ResourceItem(piece), in: reunion, at: 728, page: 2,
                                         context: context)

        #expect(piece.pinnedAtT == 728)
        #expect(piece.citationCount == 1)
        // La puce est collée à la note courante, pas à une ligne nouvelle : la
        // pièce illustre ce qu'on vient d'écrire.
        #expect(reunion.timedNotes.count == 1)
        #expect(note?.text.hasSuffix("◫ Chiffrage_Marine_v3 · p.2") == true)
        #expect(note?.text.hasPrefix("Le chiffrage v3 annonce") == true)
        // Et la chaîne de citation mène à la pièce (spec §8).
        #expect(note?.sourceRef?.kind == .capture)
        #expect(note?.sourceRef?.stableID == piece.ensuredStableID)
        #expect(note?.sourceRef?.t == 728)
    }

    /// Critère n° 3, première moitié : retrouvable **par son timecode**, dans
    /// l'ordre.
    @Test("Les pièces épinglées sortent triées par timecode")
    func retrouvableParTimecode() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let tard = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)
        let tot = addPiece("Comptes_GitLab.png", kind: "image", to: reunion, in: context)
        addPiece("Devis_partenaire_40k.pdf", kind: "pdf", to: reunion, in: context)

        AttachmentPinning.pin(ResourceItem(tard), in: reunion, at: 728, context: context)
        AttachmentPinning.pin(ResourceItem(tot), in: reunion, at: 252, context: context)

        #expect(reunion.pinnedAttachments.map(\.fileName)
                == ["Comptes_GitLab.png", "Chiffrage_Marine_v3.xlsx"])
        #expect(reunion.pinnedAttachments.compactMap(\.pinnedAtT) == [252, 728])
    }

    @Test("Un repère de frise apparaît pour chaque épingle")
    func repereDeFrise() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)
        addNote(0, "ouverture", to: reunion, in: context)

        #expect(MeetingTimelineMarkers.pinMarkers(for: reunion).isEmpty)
        AttachmentPinning.pin(ResourceItem(piece), in: reunion, at: 728, context: context)

        let epingles = MeetingTimelineMarkers.pinMarkers(for: reunion)
        #expect(epingles.count == 1)
        // Le **carré** de la spec §2.4 : la frise n'a que trois formes.
        #expect(epingles.first?.kind == .capture)
        #expect(epingles.first?.t == 728)
        #expect(epingles.first?.label == "Chiffrage_Marine_v3.xlsx")

        // Et `allMarkers` les mêle aux notes, triés.
        let tous = MeetingTimelineMarkers.allMarkers(for: reunion)
        #expect(tous.map(\.t) == [0, 728])
    }

    @Test("Sans note à cet instant, la puce fait sa propre ligne")
    func puceSansNoteCourante() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)

        let note = AttachmentPinning.pin(ResourceItem(piece), in: reunion, at: 728, context: context)
        #expect(reunion.timedNotes.count == 1)
        #expect(note?.text == "◫ Chiffrage_Marine_v3")
        #expect(note?.t == 728)
    }

    /// La note « courante » est la dernière posée **à ou avant** `t` : une
    /// note plus tardive parle d'autre chose.
    @Test("La note courante est la dernière à ou avant le timecode")
    func noteCourante() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        addNote(100, "tôt", to: reunion, in: context)
        let attendue = addNote(700, "juste avant", to: reunion, in: context)
        addNote(900, "plus tard", to: reunion, in: context)

        #expect(AttachmentPinning.currentNote(in: reunion, at: 728)?.text == attendue.text)
        #expect(AttachmentPinning.currentNote(in: reunion, at: 50) == nil)
    }

    @Test("Citer deux fois la même page n'écrit qu'une puce")
    func idempotenceDeLaPuce() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)
        let note = addNote(728, "Le chiffrage v3.", to: reunion, in: context)

        AttachmentPinning.cite(ResourceItem(piece), in: reunion, at: 728, page: 2, context: context)
        AttachmentPinning.cite(ResourceItem(piece), in: reunion, at: 728, page: 2, context: context)

        let occurrences = note.text.components(separatedBy: "◫").count - 1
        #expect(occurrences == 1)
        // Le compteur de citations, lui, compte les deux clics : c'est bien
        // deux fois qu'on a désigné la pièce.
        #expect(piece.citationCount == 2)
    }

    // MARK: - Citer sans épingler

    @Test("Citer n'épingle pas")
    func citationSansEpinglage() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Devis_partenaire_40k.pdf", kind: "pdf", to: reunion, in: context)

        AttachmentPinning.cite(ResourceItem(piece), in: reunion, at: 400, context: context)

        #expect(piece.pinnedAtT == nil)
        #expect(piece.citationCount == 1)
        #expect(reunion.pinnedAttachments.isEmpty)
        #expect(reunion.timedNotes.first?.text == "◫ Devis_partenaire_40k")
    }

    @Test("Une pièce de projet se cite mais ne s'épingle pas")
    func pieceDeProjet() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let projet = Project(code: "P25_110", name: "S/D", domain: "S/D",
                             sponsor: "OF", phase: "Réalisation", status: "Yellow")
        context.insert(projet)
        reunion.project = projet
        let piece = ProjectAttachment(url: URL(fileURLWithPath: "/tmp/Devis.pdf"))
        piece.project = projet
        context.insert(piece)
        let item = ResourceItem(piece)

        #expect(AttachmentPinning.pin(item, in: reunion, at: 100, context: context) == nil)
        #expect(AttachmentPinning.cite(item, in: reunion, at: 100, context: context) != nil)
        #expect(reunion.pinnedAttachments.isEmpty)
    }

    // MARK: - Désépingler

    /// Réécrire l'historique parce qu'on a changé d'avis sur une épingle serait
    /// pire que le désépinglage lui-même.
    @Test("Désépingler laisse la puce déjà écrite")
    func desepinglage() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", to: reunion, in: context)
        addNote(728, "Le chiffrage v3.", to: reunion, in: context)
        AttachmentPinning.pin(ResourceItem(piece), in: reunion, at: 728, context: context)

        AttachmentPinning.unpin(ResourceItem(piece), in: reunion, context: context)

        #expect(piece.pinnedAtT == nil)
        #expect(reunion.timedNotes.first?.text.contains("◫") == true)
    }

    // MARK: - La bande de la séance

    @Test("La chip du moment courant est celle du timecode voisin")
    func chipCourante() {
        #expect(PinnedInSessionStrip.isCurrent(t: 728, playhead: 728))
        #expect(PinnedInSessionStrip.isCurrent(t: 728, playhead: 729))
        #expect(!PinnedInSessionStrip.isCurrent(t: 728, playhead: 740))
        #expect(!PinnedInSessionStrip.isCurrent(t: 252, playhead: 728))
    }
}
