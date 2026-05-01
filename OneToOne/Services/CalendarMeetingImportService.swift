import Foundation
import EventKit

struct CalendarMeetingAttendee: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let status: MeetingAttendanceStatus
}

struct CalendarMeetingEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let attendees: [CalendarMeetingAttendee]
}

@MainActor
final class CalendarMeetingImportService: ObservableObject {
    private let eventStore = EKEventStore()

    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    func fetchEvents(around anchorDate: Date, daysBefore: Int = 7, daysAfter: Int = 14) -> [CalendarMeetingEvent] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysBefore, to: anchorDate) ?? anchorDate
        let end = calendar.date(byAdding: .day, value: daysAfter, to: anchorDate) ?? anchorDate
        return fetchEvents(start: start, end: end)
    }

    /// Fetch events between explicit bounds, sorted chronologically (ascending).
    func fetchEvents(start: Date, end: Date) -> [CalendarMeetingEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: eventStore.calendars(for: .event))

        return eventStore.events(matching: predicate)
            .sorted(by: { $0.startDate < $1.startDate })
            .map { event in
                CalendarMeetingEvent(
                    id: event.calendarItemIdentifier,
                    title: Self.normalizedTitle(event.title),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarTitle: event.calendar.title,
                    attendees: (event.attendees ?? []).map { attendee in
                        let email = Self.extractEmail(from: attendee.url)
                        let fallbackName = email?.components(separatedBy: "@").first ?? "Participant"
                        let name = Self.normalizedAttendeeName(attendee.name, fallback: fallbackName)
                        return CalendarMeetingAttendee(
                            id: email ?? name.lowercased(),
                            name: name,
                            email: email,
                            status: attendee.participantStatus == .declined ? .absent : .participant
                        )
                    }
                )
            }
    }

    private static func normalizedTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Événement sans titre" : trimmed
    }

    private static func normalizedAttendeeName(_ name: String?, fallback: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func extractEmail(from url: URL?) -> String? {
        guard let url else { return nil }
        let absolute = url.absoluteString
        if absolute.lowercased().hasPrefix("mailto:") {
            return String(absolute.dropFirst("mailto:".count))
        }
        return absolute.isEmpty ? nil : absolute
    }
}
