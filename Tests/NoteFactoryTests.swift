import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteFactory — une note est une réunion avec soi-même")
struct NoteFactoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
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
        let context = try makeContext()
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let note = NoteFactory.make(body: "Point de vigilance", collaborator: collab)
        context.insert(note)
        try context.save()

        // Relu depuis le store, pas depuis l'instance en mémoire : c'est cet
        // aller-retour qui prouve qu'une relation posée AVANT l'insertion
        // survit à la persistance. Même motif que `Tests/SwiftDataTests.swift`.
        let fetched = try context.fetch(FetchDescriptor<Meeting>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.participants.map(\.name) == ["Alice"])
        // Côté inverse de la relation.
        #expect(collab.meetings.contains { $0.persistentModelID == note.persistentModelID })
    }

    @Test("Sans collaborateur, aucun participant")
    func noCollaboratorMeansNoParticipant() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Note libre")
        context.insert(note)
        #expect(note.participants.isEmpty)
    }
}
