import Foundation
import EventKit
import SwiftData

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
    let teamsJoinURL: String?
    let isCancelled: Bool
    let isAllDay: Bool
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
                    },
                    teamsJoinURL: TeamsURLExtractor.extract(
                        url: event.url,
                        notes: event.notes,
                        location: event.location
                    ),
                    isCancelled: event.status == .canceled,
                    isAllDay: event.isAllDay
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

    // MARK: - Import

    /// Imports a calendar event as a Meeting. Idempotent on `calendarEventID`:
    /// re-importing the same event returns the existing Meeting unchanged.
    /// Saves the context internally so the Meeting's storeIdentifier is stable
    /// before notifications reference it.
    func importEvent(_ event: CalendarMeetingEvent,
                     context: ModelContext,
                     settings: AppSettings) -> Meeting {
        if let existing = findExisting(eventID: event.id, in: context) {
            return existing
        }

        let meeting = Meeting(title: event.title, date: event.startDate)
        // Insert BEFORE setting relations so SwiftData inverse-keys wire up correctly.
        context.insert(meeting)

        meeting.scheduledStart = event.startDate
        meeting.scheduledEnd = event.endDate
        meeting.teamsJoinURL = event.teamsJoinURL
        meeting.calendarEventID = event.id
        meeting.calendarEventTitle = event.title
        meeting.meetingDurationSeconds = max(0, Int(event.endDate.timeIntervalSince(event.startDate).rounded()))

        let suggestion = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        meeting.kind = suggestion.kind
        if let project = suggestion.project {
            meeting.project = project
        }
        if let collab = suggestion.collaborator,
           !meeting.participants.contains(where: { $0.persistentModelID == collab.persistentModelID }) {
            meeting.participants.append(collab)
        }

        // Materialize attendees as Collaborator. Skip self only when we can
        // identify "me" via email; never skip attendees without email — many
        // internal Outlook/Teams events expose names only.
        let me = settings.userEmail.lowercased()
        for attendee in event.attendees {
            let email = (attendee.email ?? "").lowercased()
            if !me.isEmpty && email == me { continue }
            let collab = upsertCollaborator(for: attendee, in: context)
            if !meeting.participants.contains(where: { $0.persistentModelID == collab.persistentModelID }) {
                meeting.participants.append(collab)
            }
            meeting.setParticipantStatus(attendee.status, for: collab)
        }

        // Save BEFORE scheduling notifications — storeIdentifier is temporary
        // until first save, and we encode it in the notification userInfo.
        try? context.save()
        MeetingNotificationService.shared.schedule(for: meeting, settings: settings)
        return meeting
    }

    private func findExisting(eventID: String, in context: ModelContext) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func upsertCollaborator(for attendee: CalendarMeetingAttendee,
                                     in context: ModelContext) -> Collaborator {
        let email = (attendee.email ?? "").lowercased()
        let name = attendee.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []

        if !email.isEmpty,
           let match = all.first(where: { $0.email.lowercased() == email }) {
            return match
        }
        // Fallback dedup by name (case-insensitive) when email is missing.
        if !name.isEmpty,
           let match = all.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            if match.email.isEmpty && !email.isEmpty { match.email = attendee.email ?? "" }
            return match
        }
        let collab = Collaborator(name: name.isEmpty ? "Participant" : name)
        collab.email = attendee.email ?? ""
        context.insert(collab)
        return collab
    }
}
