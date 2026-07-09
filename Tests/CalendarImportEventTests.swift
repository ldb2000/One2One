import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CalendarImportEventTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    var service: CalendarMeetingImportService!
    var settings: AppSettings!

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        service = CalendarMeetingImportService()
        settings = AppSettings()
        settings.userEmail = "me@example.com"
        context.insert(settings)
        try context.save()
    }

    private func event(id: String = "evt-1",
                       title: String = "Daily standup",
                       teamsURL: String? = nil) -> CalendarMeetingEvent {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        return CalendarMeetingEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            calendarTitle: "Work",
            attendees: [
                CalendarMeetingAttendee(id: "me@example.com", name: "Me", email: "me@example.com", status: .present),
                CalendarMeetingAttendee(id: "x@y.com", name: "X", email: "x@y.com", status: .present),
                CalendarMeetingAttendee(id: "y@y.com", name: "Y", email: "y@y.com", status: .present)
            ],
            teamsJoinURL: teamsURL,
            isCancelled: false,
            isAllDay: false
        )
    }

    func test_importEvent_populatesScheduledAndTeamsAndCalendarID() throws {
        let evt = event(teamsURL: "https://teams.microsoft.com/l/meetup-join/abc")
        let meeting = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(meeting.title, "Daily standup")
        XCTAssertEqual(meeting.scheduledStart, evt.startDate)
        XCTAssertEqual(meeting.scheduledEnd, evt.endDate)
        XCTAssertEqual(meeting.teamsJoinURL, "https://teams.microsoft.com/l/meetup-join/abc")
        XCTAssertEqual(meeting.calendarEventID, "evt-1")
        XCTAssertEqual(meeting.effectiveDuration, 1800, accuracy: 0.01)
    }

    func test_importEvent_isIdempotent_returnsExistingOnSecondCall() throws {
        let evt = event()
        let first = service.importEvent(evt, context: context, settings: settings)
        try context.save()
        let second = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)

        let count = try context.fetchCount(FetchDescriptor<Meeting>())
        XCTAssertEqual(count, 1)
    }

    func test_importEvent_setsKindFromMatchService_oneToOne() throws {
        let collab = Collaborator(name: "Alice")
        collab.email = "alice@example.com"
        context.insert(collab)
        try context.save()

        let evt = CalendarMeetingEvent(
            id: "evt-2",
            title: "Sync with Alice",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarTitle: "Work",
            attendees: [
                CalendarMeetingAttendee(id: "me@example.com", name: "Me", email: "me@example.com", status: .present),
                CalendarMeetingAttendee(id: "alice@example.com", name: "Alice", email: "alice@example.com", status: .present)
            ],
            teamsJoinURL: nil,
            isCancelled: false,
            isAllDay: false
        )
        let meeting = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(meeting.kind, .oneToOne)
    }
}
