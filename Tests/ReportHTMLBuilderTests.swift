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
}
