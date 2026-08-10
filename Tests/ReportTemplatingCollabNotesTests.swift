import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ReportTemplating — les notes d'un collaborateur alimentent le gabarit")
@MainActor
struct ReportTemplatingCollabNotesTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Seules les notes du collaborateur remontent, du plus récent au plus ancien")
    func collabNotesAreScopedAndSorted() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)

        let old = NoteFactory.make(body: "ancienne", date: Date(timeIntervalSince1970: 1_000), collaborator: alice)
        let recent = NoteFactory.make(body: "récente", date: Date(timeIntervalSince1970: 2_000), collaborator: alice)
        let other = NoteFactory.make(body: "de Bob", collaborator: bob)
        context.insert(old); context.insert(recent); context.insert(other)
        try context.save()

        let rendered = TemplateVariableResolver.collabNotesForTesting(for: alice, in: context)
        #expect(rendered.contains("récente"))
        #expect(rendered.contains("ancienne"))
        #expect(!rendered.contains("de Bob"))
        #expect(rendered.range(of: "récente")!.lowerBound < rendered.range(of: "ancienne")!.lowerBound)
    }

    @Test("Une vraie réunion du collaborateur n'est pas une note")
    func heldMeetingIsExcluded() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        context.insert(alice)
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        meeting.participants = [alice]
        meeting.liveNotes = "contenu du 1:1"
        context.insert(meeting)
        try context.save()

        #expect(!TemplateVariableResolver.collabNotesForTesting(for: alice, in: context).contains("contenu du 1:1"))
    }
}
