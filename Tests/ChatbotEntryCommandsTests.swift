import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Commandes /ajout-* — chaque entrée vers son modèle naturel")
@MainActor
struct ChatbotEntryCommandsTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Une info projet en phase Build devient une note titrée REX")
    func projectInfoOnBuildIsRex() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)

        let note = try ChatbotEntryCommands.addProjectInfo(
            content: "Le socle a tenu la charge", project: project, in: context)

        #expect(note.kind == .note)
        #expect(note.title == "REX")
        #expect(note.liveNotes == "Le socle a tenu la charge")
        #expect(note.project?.code == "REFSI")
    }

    @Test("Une info projet hors phase Build devient une note titrée Info projet")
    func projectInfoOutsideBuild() throws {
        let context = try makeContext()
        let project = Project(code: "DATA24", name: "Plateforme Data", domain: "Data", phase: "Run")
        context.insert(project)

        let note = try ChatbotEntryCommands.addProjectInfo(
            content: "Cadrage lancé", project: project, in: context)
        #expect(note.title == "Info projet")
    }

    @Test("Une info collaborateur devient une note où il est participant")
    func collaboratorInfoBecomesNote() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        context.insert(project); context.insert(alice)

        let note = try ChatbotEntryCommands.addCollaboratorInfo(
            content: "Monte en compétence sur le socle",
            project: project, collaborator: alice, in: context)

        #expect(note.kind == .note)
        #expect(note.title == "Info Alice")
        #expect(note.participants.map(\.name) == ["Alice"])
        #expect(note.project?.code == "REFSI")
    }

    @Test("Une action collaborateur devient un ActionTask, et aucune note")
    func collaboratorActionBecomesTask() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        context.insert(project); context.insert(alice)

        let task = try ChatbotEntryCommands.addCollaboratorAction(
            content: "Rédiger la DAT", project: project, collaborator: alice, in: context)

        #expect(task.title == "Rédiger la DAT")
        #expect(task.destinataire == .collaborateur)
        #expect(task.collaborator?.name == "Alice")
        #expect(task.project?.code == "REFSI")
        #expect(!task.isCompleted)

        let notes = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.kindRaw == "note" }))
        #expect(notes.isEmpty)
    }
}
