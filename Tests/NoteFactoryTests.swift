import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteFactory — une note est une réunion avec soi-même")
struct NoteFactoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    @Test("Le kind est note et le corps va dans liveNotes")
    func kindAndBody() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Idée du jour")
        context.insert(note)
        #expect(note.kind == .note)
        #expect(note.liveNotes == "Idée du jour")
    }

    @Test("Le projet est rattaché")
    func projectIsLinked() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)
        let note = NoteFactory.make(body: "REX", title: "REX", project: project)
        context.insert(note)
        #expect(note.project?.code == "REFSI")
    }

    @Test("Le collaborateur devient participant, et le lien survit à la sauvegarde")
    func collaboratorBecomesParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let note = NoteFactory.make(body: "Point de vigilance", collaborator: collab)
        context.insert(note)
        try context.save()

        // Second contexte sur le même conteneur. C'est la seule façon de sortir
        // de la carte d'identité du premier : un `fetch` sur le contexte qui a
        // fait le `save` rend l'instance déjà en mémoire, et l'assertion serait
        // tautologique. Le dépôt ne fait nulle part cette distinction
        // (cf. `Tests/SwiftDataTests.swift`) ; ici elle compte, parce que
        // `NoteFactory` pose la relation AVANT l'insertion.
        let verifier = ModelContext(container)
        let fetchedNotes = try verifier.fetch(FetchDescriptor<Meeting>())
        #expect(fetchedNotes.count == 1)
        #expect(fetchedNotes.first?.participants.map(\.name) == ["Alice"])
        // Côté inverse, relu lui aussi depuis le second contexte.
        let fetchedCollabs = try verifier.fetch(FetchDescriptor<Collaborator>())
        #expect(fetchedCollabs.first?.meetings.count == 1)
    }

    @Test("Sans collaborateur, aucun participant")
    func noCollaboratorMeansNoParticipant() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Note libre")
        context.insert(note)
        #expect(note.participants.isEmpty)
    }

    // MARK: - isDiscardableEmptyNote

    @Test("Une note fraîchement fabriquée est jetable")
    func freshNoteIsDiscardable() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        #expect(NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Un titre ou un corps, même réduit à des espaces autour, la retient")
    func titleOrBodyKeepsIt() throws {
        let context = try makeContext()
        let titled = NoteFactory.make(title: "  Titre  ")
        let bodied = NoteFactory.make(body: "\n Contenu \n")
        context.insert(titled); context.insert(bodied)
        #expect(!NoteFactory.isDiscardableEmptyNote(titled))
        #expect(!NoteFactory.isDiscardableEmptyNote(bodied))
    }

    @Test("Des blancs seuls ne retiennent pas la note")
    func whitespaceOnlyIsStillDiscardable() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "   \n\t ", title: "  ")
        context.insert(note)
        #expect(NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Une pièce jointe retient la note, même sans titre ni corps")
    func attachmentKeepsIt() throws {
        let context = try makeContext()
        let note = NoteFactory.make()
        context.insert(note)
        let attachment = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/doc.pdf"), kind: "pdf")
        attachment.meeting = note
        context.insert(attachment)
        try context.save()
        #expect(!NoteFactory.isDiscardableEmptyNote(note))
    }

    @Test("Le projet ou le participant posés par la fabrique ne retiennent pas la note")
    func targetAloneDoesNotKeepIt() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let collab = Collaborator(name: "Alice")
        context.insert(project); context.insert(collab)
        let projectNote = NoteFactory.make(project: project)
        let collabNote = NoteFactory.make(collaborator: collab)
        context.insert(projectNote); context.insert(collabNote)
        #expect(NoteFactory.isDiscardableEmptyNote(projectNote))
        #expect(NoteFactory.isDiscardableEmptyNote(collabNote))
    }

    @Test("Une réunion vide qui n'est pas une note n'est jamais jetable")
    func nonNoteIsNeverDiscardable() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "", date: Date())
        meeting.kind = .oneToOne
        context.insert(meeting)
        #expect(!NoteFactory.isDiscardableEmptyNote(meeting))
    }
}
