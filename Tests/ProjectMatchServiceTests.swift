import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class ProjectMatchServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeEvent(title: String,
                           attendees: [(name: String, email: String)] = []) -> CalendarMeetingEvent {
        let start = Date()
        return CalendarMeetingEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarTitle: "Work",
            attendees: attendees.map {
                CalendarMeetingAttendee(id: $0.email, name: $0.name, email: $0.email, status: .participant)
            },
            teamsJoinURL: nil,
            isCancelled: false,
            isAllDay: false
        )
    }

    private func makeSettings(userEmail: String = "me@example.com",
                              managerEmail: String = "") -> AppSettings {
        let s = AppSettings()
        s.userEmail = userEmail
        s.managerEmail = managerEmail
        return s
    }

    func test_managerEmailWins_overEverythingElse() {
        let settings = makeSettings(managerEmail: "boss@example.com")
        let event = makeEvent(title: "Sync hebdo",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Boss", "boss@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .manager)
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.001)
    }

    func test_twoAttendees_matchedCollaborator_oneToOne() throws {
        let collab = Collaborator(name: "Sylvain Estellé")
        collab.email = "sylvain@example.com"
        context.insert(collab)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "Entretien Sylvain",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Sylvain", "sylvain@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .oneToOne)
        XCTAssertEqual(s.collaborator?.email, "sylvain@example.com")
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.001)
    }

    func test_twoAttendees_noCollaborator_oneToOneLowConfidence() {
        let settings = makeSettings()
        let event = makeEvent(title: "Entretien Sylvain",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Sylvain", "sylvain@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .oneToOne)
        XCTAssertNil(s.collaborator)
        XCTAssertLessThan(s.confidence, 0.9)
        XCTAssertFalse(s.autoApply(threshold: 0.9))
    }

    func test_projectFuzzyMatch_highConfidenceAutoApplies() throws {
        let proj = Project(code: "TIP", name: "Téléphonie iPMI", domain: "Téléphonie", phase: "Build")
        context.insert(proj)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "[Téléphonie iPMI] Cadrage",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("A", "a@x.com"),
                                ("B", "b@x.com"),
                                ("C", "c@x.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .project)
        XCTAssertEqual(s.project?.name, "Téléphonie iPMI")
        XCTAssertGreaterThanOrEqual(s.confidence, 0.9)
        XCTAssertTrue(s.autoApply(threshold: 0.9))
    }

    func test_projectFuzzyMatch_accentInsensitive() throws {
        let proj = Project(code: "DIAP", name: "diapason", domain: "Outils", phase: "Run")
        context.insert(proj)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "diapason : solution préconisée",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("X", "x@y.com"),
                                ("Y", "y@y.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .project)
        XCTAssertEqual(s.project?.name, "diapason")
    }

    func test_noMatch_fallsBackToGlobal() {
        let settings = makeSettings()
        let event = makeEvent(title: "Daily standup",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("X", "x@y.com"),
                                ("Y", "y@y.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .global)
        XCTAssertLessThan(s.confidence, 0.5)
    }

    func test_normalize_stripsAccentsPunctuationAndCase() {
        XCTAssertEqual(
            ProjectMatchService.normalizedTokens("[Téléphonie iPMI] - Cadrage !"),
            ["telephonie", "ipmi", "cadrage"]
        )
    }
}
