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
}
