import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NotesSection — les notes d'une fiche")
struct NotesSectionScopeTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Une fiche projet ne montre que les notes de ce projet")
    func projectTarget() throws {
        let context = try makeContext()
        let a = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        let b = Project(code: "B", name: "Beta", domain: "d", phase: "Build")
        context.insert(a); context.insert(b)
        let noteA = NoteFactory.make(body: "a", project: a)
        let noteB = NoteFactory.make(body: "b", project: b)
        context.insert(noteA); context.insert(noteB)

        let result = NotesSection.notes(for: .project(a), in: [noteA, noteB])
        #expect(result.map(\.liveNotes) == ["a"])
    }

    @Test("Une fiche collaborateur ne montre que les notes où il participe")
    func collaboratorTarget() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)
        let noteAlice = NoteFactory.make(body: "a", collaborator: alice)
        let noteBob = NoteFactory.make(body: "b", collaborator: bob)
        context.insert(noteAlice); context.insert(noteBob)

        let result = NotesSection.notes(for: .collaborator(alice), in: [noteAlice, noteBob])
        #expect(result.map(\.liveNotes) == ["a"])
    }

    @Test("Une vraie réunion n'est pas une note")
    func heldMeetingIsNotANote() throws {
        let context = try makeContext()
        let project = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        context.insert(project)
        let meeting = Meeting(title: "Comité", date: Date())
        meeting.kind = .project
        meeting.project = project
        context.insert(meeting)

        #expect(NotesSection.notes(for: .project(project), in: [meeting]).isEmpty)
    }

    @Test("Un vrai 1:1 avec le collaborateur en participant n'est pas une note")
    func heldOneToOneIsNotANote() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        context.insert(alice)
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        meeting.participants = [alice]
        context.insert(meeting)

        #expect(NotesSection.notes(for: .collaborator(alice), in: [meeting]).isEmpty)
    }

    @Test("Les notes sont triées du plus récent au plus ancien")
    func sortedByDateDescending() throws {
        let context = try makeContext()
        let project = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        context.insert(project)
        let old = NoteFactory.make(body: "vieille", date: Date(timeIntervalSince1970: 1_000), project: project)
        let recent = NoteFactory.make(body: "récente", date: Date(timeIntervalSince1970: 2_000), project: project)
        context.insert(old); context.insert(recent)

        #expect(NotesSection.notes(for: .project(project), in: [old, recent]).map(\.liveNotes)
                == ["récente", "vieille"])
    }
}
