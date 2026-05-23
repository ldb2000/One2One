import XCTest
import SwiftData
@testable import OneToOne

final class ProjectsContextBuilderTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_nonOneToOneMeeting_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "COPIL", date: Date())
        m.kindRaw = MeetingKind.project.rawValue
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_oneToOneWithoutPartner_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "1:1 vide", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = []
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_partnerWithoutProjects_returnsEmpty() throws {
        let ctx = try makeContext()
        let p = Collaborator(name: "Alice DUPONT")
        ctx.insert(p)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [p]
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_oneArchitectProject_includesHeaderAndRole() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "NEVIDIS", name: "Projet Névidis", domain: "Infra", phase: "Build")
        proj.status = "Yellow"
        proj.technicalArchitect = alice
        ctx.insert(proj)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        XCTAssertTrue(out.contains("## NEVIDIS · Projet Névidis (statut: Yellow)"))
        XCTAssertTrue(out.contains("Architecte technique"))
        XCTAssertTrue(out.contains("Alice DUPONT"))
    }

    @MainActor
    func test_includesTop3SummariesAndOpenActions() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "COOG", name: "Migration Coog", domain: "Infra", phase: "Build")
        proj.status = "Red"
        proj.technicalArchitect = alice
        ctx.insert(proj)

        let cal = Calendar.current
        for i in 0..<4 {
            let date = cal.date(byAdding: .day, value: -i * 7, to: Date())!
            let m = Meeting(title: "Comité semaine \(i)", date: date)
            m.kindRaw = MeetingKind.project.rawValue
            m.project = proj
            m.summary = "Résumé semaine \(i)"
            ctx.insert(m)
        }

        let open = ActionTask(title: "Migrer DD", dueDate: nil)
        open.project = proj
        open.collaborator = alice
        ctx.insert(open)
        let done = ActionTask(title: "Action close", dueDate: nil)
        done.isCompleted = true
        done.project = proj
        ctx.insert(done)

        let current = Meeting(title: "1:1 Alice", date: Date())
        current.kindRaw = MeetingKind.oneToOne.rawValue
        current.participants = [alice]
        ctx.insert(current)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: current, in: ctx)
        XCTAssertTrue(out.contains("Résumé semaine 0"))
        XCTAssertTrue(out.contains("Résumé semaine 1"))
        XCTAssertTrue(out.contains("Résumé semaine 2"))
        XCTAssertFalse(out.contains("Résumé semaine 3"))
        XCTAssertTrue(out.contains("Migrer DD"))
        XCTAssertFalse(out.contains("Action close"))
    }

    @MainActor
    func test_archivedProjectExcluded() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "OLD", name: "Vieux projet", domain: "Legacy", phase: "Run")
        proj.technicalArchitect = alice
        proj.isArchived = true
        ctx.insert(proj)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        XCTAssertEqual(out, "")
    }

    @MainActor
    func test_sortRedYellowGreenAndTruncatesAtFive() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let statuses = ["Green", "Red", "Yellow", "Unknown", "Red", "Green", "Yellow"]
        for (i, s) in statuses.enumerated() {
            let p = Project(code: "P\(i)", name: "Projet \(i)", domain: "X", phase: "Build")
            p.status = s
            p.technicalArchitect = alice
            ctx.insert(p)
        }
        let m = Meeting(title: "1:1", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        let countHeaders = out.components(separatedBy: "## P").count - 1
        XCTAssertLessThanOrEqual(countHeaders, 5)
        let firstRedIdx = out.range(of: "(statut: Red)")?.lowerBound
        let firstYellowIdx = out.range(of: "(statut: Yellow)")?.lowerBound
        XCTAssertNotNil(firstRedIdx)
        if let r = firstRedIdx, let y = firstYellowIdx {
            XCTAssertTrue(r < y, "Red doit apparaître avant Yellow")
        }
    }
}
