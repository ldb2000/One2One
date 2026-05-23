import XCTest
import SwiftData
@testable import OneToOne

final class ReportHTMLBuilderTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_eyebrowContainsKindAndConfidential() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Test", date: Date())
        meeting.summary = "Contenu de test."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("CONFIDENTIEL"))
        XCTAssertTrue(html.contains("Test"))
    }

    @MainActor
    func test_titleEscaped() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Titre <script>", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()
        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("<h1>Titre <script>"))
        XCTAssertTrue(html.contains("Titre &lt;script&gt;"))
    }

    @MainActor
    func test_metaParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)
        let meeting = Meeting(title: "T", date: Date())
        meeting.participants = [alice, bob]
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("Bob MARTIN"))
    }

    @MainActor
    func test_injectsDecisionsTable() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Contexte\n\nLa séance vise…"
        meeting.decisions = ["Catalogue par exception", "Tri amont"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Relevé de décisions"))
        XCTAssertTrue(html.contains("Catalogue par exception"))
        XCTAssertTrue(html.contains("Tri amont"))
        XCTAssertTrue(html.contains("D1"))
        XCTAssertTrue(html.contains("D2"))
    }

    @MainActor
    func test_injectsActionsFromTasks() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        let task = ActionTask(title: "Préparer slides", dueDate: nil)
        task.collaborator = alice
        task.meeting = meeting
        ctx.insert(task)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Plan d'actions"))
        XCTAssertTrue(html.contains("Préparer slides"))
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("A1"))
    }

    @MainActor
    func test_noInjectionWhenAllEmpty() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Section unique\n\nContenu."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("Relevé de décisions"))
        XCTAssertFalse(html.contains("Plan d'actions"))
    }

    @MainActor
    func test_dedupeH2_remplaceDecisionsLLM() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = """
        ## Contexte
        Texte.

        ## Décisions
        Le LLM a écrit du texte ici qui doit être remplacé.
        """
        meeting.decisions = ["Canonique 1"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Canonique 1"))
        XCTAssertFalse(html.contains("Le LLM a écrit du texte ici qui doit être remplacé."))
    }

    @MainActor
    func test_oneToOneActionsTable_singleProject_noProjectColumn() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        ctx.insert(proj)
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kindRaw = MeetingKind.oneToOne.rawValue
        meeting.participants = [alice]
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche 1", dueDate: nil)
        t1.meeting = meeting
        t1.project = proj
        ctx.insert(t1)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("<th>Action</th>"))
        XCTAssertFalse(html.contains("<th>Projet</th>"),
                       "Single project → colonne Projet absente")
    }

    @MainActor
    func test_oneToOneActionsTable_multipleProjects_includesProjectColumn() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kindRaw = MeetingKind.oneToOne.rawValue
        meeting.participants = [alice]
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
        t1.meeting = meeting
        t1.project = p1
        ctx.insert(t1)
        let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
        t2.meeting = meeting
        t2.project = p2
        ctx.insert(t2)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("<th>Projet</th>"),
                      "Multi projets en 1:1 → colonne Projet présente")
        XCTAssertTrue(html.contains("P1"))
        XCTAssertTrue(html.contains("P2"))
    }

    @MainActor
    func test_nonOneToOneActionsTable_noProjectColumn() throws {
        let ctx = try makeContext()
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "COPIL", date: Date())
        meeting.kindRaw = MeetingKind.project.rawValue
        meeting.summary = "x"
        ctx.insert(meeting)
        let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
        t1.meeting = meeting; t1.project = p1
        ctx.insert(t1)
        let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
        t2.meeting = meeting; t2.project = p2
        ctx.insert(t2)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("<th>Projet</th>"),
                       "Non-1:1 → pas de colonne Projet même si multi projets")
    }
}
