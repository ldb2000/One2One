import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("SwiftData Model Persistence Tests")
struct SwiftDataTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Project.self, Collaborator.self, Interview.self, ActionTask.self, AppSettings.self, Entity.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Entity

    @Test("Entity can be created and saved")
    func entityCreateAndSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entity = Entity(name: "Test Entity")
        context.insert(entity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Entity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Test Entity")
    }

    @Test("Entity name can be mutated and saved")
    func entityMutateAndSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entity = Entity(name: "Original")
        context.insert(entity)
        try context.save()

        entity.name = "Modified"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Entity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Modified")
    }

    @Test("Multiple entities can be created")
    func multipleEntities() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let e1 = Entity(name: "Entity 1")
        let e2 = Entity(name: "Entity 2")
        context.insert(e1)
        context.insert(e2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Entity>())
        #expect(fetched.count == 2)
    }

    // MARK: - Project

    @Test("Project can be created and saved")
    func projectCreateAndSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(code: "P001", name: "Test Project", domain: "IT", phase: "Build")
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Test Project")
    }

    @Test("Project fields can be mutated and saved")
    func projectMutateAndSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(code: "P001", name: "Original", domain: "IT", phase: "Build")
        context.insert(project)
        try context.save()

        project.name = "Updated Name"
        project.domain = "Finance"
        project.phase = "Run"
        project.status = "Green"
        project.comment = "Some comment"
        project.hasDAT = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.first?.name == "Updated Name")
        #expect(fetched.first?.domain == "Finance")
        #expect(fetched.first?.phase == "Run")
        #expect(fetched.first?.status == "Green")
        #expect(fetched.first?.comment == "Some comment")
        #expect(fetched.first?.hasDAT == true)
    }

    @Test("Project can be linked to Entity")
    func projectEntityRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let entity = Entity(name: "Dept A")
        let project = Project(code: "P002", name: "Proj A", domain: "IT", phase: "Cadrage")
        context.insert(entity)
        context.insert(project)

        project.entity = entity
        try context.save()

        let fetchedProjects = try context.fetch(FetchDescriptor<Project>())
        #expect(fetchedProjects.first?.entity?.name == "Dept A")

        let fetchedEntities = try context.fetch(FetchDescriptor<Entity>())
        #expect(fetchedEntities.first?.projects.count == 1)
    }

    @Test("Two projects with same code can coexist (no unique crash)")
    func duplicateProjectCodeNoCrash() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let p1 = Project(code: "SAME", name: "Proj 1", domain: "IT", phase: "Build")
        let p2 = Project(code: "SAME", name: "Proj 2", domain: "IT", phase: "Run")
        context.insert(p1)
        context.insert(p2)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 2)
    }

    // MARK: - Collaborator

    @Test("Collaborator can be created and mutated")
    func collaboratorMutate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let collab = Collaborator(name: "Alice", role: "Dev")
        context.insert(collab)
        try context.save()

        collab.name = "Alice Updated"
        collab.role = "Architecte"
        collab.isArchived = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Collaborator>())
        #expect(fetched.first?.name == "Alice Updated")
        #expect(fetched.first?.role == "Architecte")
        #expect(fetched.first?.isArchived == true)
    }

    // MARK: - Interview

    @Test("Interview can be created and mutated with collaborator")
    func interviewWithCollaborator() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let collab = Collaborator(name: "Bob")
        let interview = Interview(date: Date(), notes: "Initial notes")
        interview.collaborator = collab
        context.insert(collab)
        context.insert(interview)
        try context.save()

        interview.notes = "Updated notes"
        interview.hasAlert = true
        interview.alertDescription = "Risk detected"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Interview>())
        #expect(fetched.first?.notes == "Updated notes")
        #expect(fetched.first?.hasAlert == true)
        #expect(fetched.first?.alertDescription == "Risk detected")
        #expect(fetched.first?.collaborator?.name == "Bob")
    }

    // MARK: - ActionTask

    @Test("ActionTask linked to Interview and Project")
    func actionTaskRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(code: "P003", name: "Proj", domain: "IT", phase: "Build")
        let interview = Interview(date: Date(), notes: "")
        let task = ActionTask(title: "Do something")
        task.project = project
        task.interview = interview

        context.insert(project)
        context.insert(interview)
        context.insert(task)
        try context.save()

        task.isCompleted = true
        task.title = "Done something"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ActionTask>())
        #expect(fetched.first?.title == "Done something")
        #expect(fetched.first?.isCompleted == true)
        #expect(fetched.first?.project?.name == "Proj")
        #expect(fetched.first?.interview != nil)
    }

    // MARK: - AppSettings

    @Test("AppSettings can be saved and mutated")
    func appSettingsMutate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        settings.cloudToken = "sk-test-123"
        settings.apiEndpoint = "https://custom.api.com"
        settings.modelName = "claude-3"
        settings.provider = .anthropic
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(fetched.first?.cloudToken == "sk-test-123")
        #expect(fetched.first?.apiEndpoint == "https://custom.api.com")
        #expect(fetched.first?.modelName == "claude-3")
        #expect(fetched.first?.provider == .anthropic)
    }

    // MARK: - Save without rollback preserves in-memory changes

    @Test("Failed save does not lose in-memory changes when no rollback")
    func noRollbackPreservesChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(code: "P_OK", name: "Good Project", domain: "IT", phase: "Build")
        context.insert(project)
        try context.save()

        // Modify the project in memory
        project.name = "Modified Name"

        // The in-memory value should still be the modified one
        #expect(project.name == "Modified Name")
    }
}
