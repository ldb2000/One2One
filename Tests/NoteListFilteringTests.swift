import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteListFilter — portée et recherche de l'écran Notes")
struct NoteListFilteringTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("La portée Projet ne garde que les notes rattachées à un projet")
    func projectScope() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)
        let attached = NoteFactory.make(body: "a", project: project)
        let orphan = NoteFactory.make(body: "b")
        context.insert(attached); context.insert(orphan)

        #expect(NoteListFilter.matches(attached, query: "", scope: .project))
        #expect(!NoteListFilter.matches(orphan, query: "", scope: .project))
    }

    @Test("La portée Collaborateur ne garde que les notes avec un participant")
    func collaboratorScope() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let about = NoteFactory.make(body: "a", collaborator: collab)
        let orphan = NoteFactory.make(body: "b")
        context.insert(about); context.insert(orphan)

        #expect(NoteListFilter.matches(about, query: "", scope: .collaborator))
        #expect(!NoteListFilter.matches(orphan, query: "", scope: .collaborator))
    }

    @Test("La recherche porte sur le titre, le corps, le projet et les participants")
    func searchFields() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let collab = Collaborator(name: "Alice")
        context.insert(project); context.insert(collab)
        let note = NoteFactory.make(body: "Découplage facturation", title: "REX",
                                    project: project, collaborator: collab)
        context.insert(note)

        #expect(NoteListFilter.matches(note, query: "rex", scope: .all))
        #expect(NoteListFilter.matches(note, query: "facturation", scope: .all))
        #expect(NoteListFilter.matches(note, query: "refonte", scope: .all))
        #expect(NoteListFilter.matches(note, query: "alice", scope: .all))
        #expect(!NoteListFilter.matches(note, query: "zzz", scope: .all))
    }
}
