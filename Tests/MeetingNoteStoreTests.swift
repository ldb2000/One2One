import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Notes horodatées — tri, filtres et reprise des notes libres")
@MainActor
struct MeetingNoteStoreTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func note(_ t: Double,
                      _ text: String,
                      kind: MeetingNoteKind = .note,
                      visibility: Visibility = .shared,
                      order: Int = 0) -> MeetingNote {
        MeetingNote(t: t, text: text, kind: kind, visibility: visibility, orderIndex: order)
    }

    // MARK: - Fonctions pures

    @Test("Le tri suit le timecode, puis l'ordre manuel à timecode égal")
    func triParTimecodePuisOrdre() {
        let notes = [
            note(252, "c"),
            note(0, "b", order: 1),
            note(0, "a", order: 0),
            note(12, "d")
        ]
        #expect(MeetingNoteStore.sorted(notes).map(\.text) == ["a", "b", "d", "c"])
    }

    @Test("Le filtre par nature ne rend que les lignes demandées")
    func filtreParNature() {
        let notes = [
            note(0, "note"),
            note(10, "décision", kind: .decision),
            note(20, "risque", kind: .risk)
        ]
        #expect(MeetingNoteStore.filtered(notes, kind: .decision).map(\.text) == ["décision"])
        #expect(MeetingNoteStore.filtered(notes, kind: nil).count == 3)
    }

    @Test("Le regroupement par nature couvre exactement les natures présentes")
    func regroupementParNature() {
        let notes = [
            note(0, "n1"),
            note(5, "n2"),
            note(10, "d", kind: .decision)
        ]
        let groupes = MeetingNoteStore.grouped(by: \.kind, notes)
        #expect(Set(groupes.keys) == [.note, .decision])
        #expect(groupes[.note]?.count == 2)
        #expect(groupes[.decision]?.count == 1)
    }

    @Test("Le markdown horodate chaque ligne")
    func markdownHorodate() {
        let rendu = MeetingNoteStore.markdown([note(252, "On garde le périmètre", kind: .decision)])
        #expect(rendu == "- [04:12] (Décision) On garde le périmètre")
    }

    @Test("Le bloc de contexte laisse les lignes non exportables dehors")
    func blocDeContexteFiltre() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "1:1 Awa")
        reunion.kind = .oneToOne
        context.insert(reunion)
        for n in [note(0, "Point charge de travail"),
                  note(30, "Salaire — à ne pas ressortir", visibility: .private)] {
            n.meeting = reunion
            context.insert(n)
        }
        try context.save()

        let pourCollaborateur = MeetingNoteStore.contextBlock(for: reunion, audience: .collaborator)
        #expect(pourCollaborateur.contains("Point charge de travail"))
        #expect(!pourCollaborateur.contains("Salaire"))

        let pourMoi = MeetingNoteStore.contextBlock(for: reunion, audience: .me)
        #expect(pourMoi.contains("Salaire"))

        // Une réunion sans note exportable ne produit **aucun** bloc : un
        // en-tête « Notes » vide dans un prompt invite le modèle à inventer.
        let vide = Meeting(title: "Sans note")
        context.insert(vide)
        #expect(MeetingNoteStore.contextBlock(for: vide, audience: .projectTeam).isEmpty)
    }

    @Test("La visibilité par défaut suit le type de réunion")
    func visibiliteParDefaut() {
        #expect(MeetingNoteStore.defaultVisibility(for: .manager) == .private)
        #expect(MeetingNoteStore.defaultVisibility(for: .oneToOne) == .shared)
        #expect(MeetingNoteStore.defaultVisibility(for: .project) == .shared)
        #expect(MeetingNoteStore.defaultVisibility(for: .global) == .shared)
        #expect(MeetingNoteStore.defaultVisibility(for: .workshop) == .shared)
    }

    @Test("Seules les lignes non privées sont indexables")
    func indexables() {
        let notes = [
            note(0, "public"),
            note(10, "secret", visibility: .private),
            note(20, "escalade", visibility: .escalated)
        ]
        #expect(MeetingNoteStore.indexable(notes).map(\.text) == ["public", "escalade"])
    }

    // MARK: - Import des notes libres

    @Test("À la première ouverture, les notes live deviennent une note t = 0")
    func importDesNotesLive() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL P25_110")
        reunion.kind = .project
        reunion.liveNotes = "Budget à revoir\nRelancer l'éditeur"
        context.insert(reunion)
        try context.save()

        let creee = MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context)

        #expect(creee != nil)
        #expect(reunion.timedNotes.count == 1)
        let note = try #require(reunion.timedNotes.first)
        #expect(note.t == 0)
        #expect(note.kind == .note)
        #expect(note.visibility == .shared)
        #expect(note.text == "Budget à revoir\nRelancer l'éditeur")
        // Le markdown historique n'est pas effacé : l'éditeur de notes live et
        // les gabarits de rapport le lisent encore.
        #expect(reunion.liveNotes == "Budget à revoir\nRelancer l'éditeur")
        #expect(reunion.notesMigrated)
    }

    @Test("Un second appel ne recrée rien")
    func importIdempotent() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "COPIL")
        reunion.liveNotes = "Un point"
        context.insert(reunion)
        try context.save()

        _ = MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context)
        let second = MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context)

        #expect(second == nil)
        #expect(reunion.timedNotes.count == 1)
    }

    @Test("Une réunion sans notes live est marquée migrée sans créer de ligne vide")
    func importSansContenu() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "Réunion vierge")
        reunion.liveNotes = "   \n  "
        context.insert(reunion)
        try context.save()

        let creee = MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context)

        #expect(creee == nil)
        #expect(reunion.timedNotes.isEmpty)
        #expect(reunion.notesMigrated)
    }

    @Test("Le 1:1 manager reprend ses notes en privé")
    func importCoteManagerEnPrive() throws {
        let context = try makeContext()
        let reunion = Meeting(title: "1:1 avec mon manager")
        reunion.kind = .manager
        reunion.liveNotes = "Demande de formation"
        context.insert(reunion)
        try context.save()

        _ = MeetingNoteStore.importLiveNotesIfNeeded(reunion, in: context)
        #expect(reunion.timedNotes.first?.visibility == .private)
    }

    /// `Meeting.textualContent` est l'énumération unique lue par `/cherche` et
    /// par `NoteFactory.isDiscardableEmptyNote` : une note horodatée oubliée là
    /// serait introuvable **et** ferait supprimer sans confirmation une note qui
    /// porte du texte.
    @Test("Une note horodatée est déclarée dans textualContent et retient la note")
    func texteDeclareEtNoteRetenue() throws {
        let context = try makeContext()
        let libre = Meeting(title: "")
        libre.kind = .note
        context.insert(libre)
        try context.save()

        #expect(NoteFactory.isDiscardableEmptyNote(libre))

        let ligne = MeetingNote(t: 0, text: "Idée à creuser")
        ligne.meeting = libre
        context.insert(ligne)
        try context.save()

        #expect(libre.textualContent.contains { $0.text == "Idée à creuser" })
        #expect(!NoteFactory.isDiscardableEmptyNote(libre),
                "une note qui porte une ligne horodatée n'est pas vide")
    }
}
