import SwiftUI
import SwiftData

struct AgendaInspectorPanel: View {

    @Environment(\.modelContext) private var context
    @Query private var appSettings: [AppSettings]

    @StateObject private var agenda = CalendarAgendaService.shared
    @State private var selectedDate: Date = Date()
    @State private var events: [CalendarMeetingEvent] = []

    private let importer = CalendarMeetingImportService()

    private var settings: AppSettings {
        appSettings.first ?? AppSettings()
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekStripView(selectedDate: $selectedDate)
                .padding(.vertical, 8)
                .background(.background.secondary)

            Divider()

            if !agenda.hasCalendarAccess {
                permissionDeniedView
                Spacer(minLength: 0)
            } else if events.isEmpty {
                ContentUnavailableView("Aucune réunion ce jour",
                                       systemImage: "calendar",
                                       description: Text("Sélectionnez une autre date."))
                    .padding()
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 280, maxHeight: .infinity, alignment: .top)
        .task { await agenda.bootstrap() }
        .onChange(of: selectedDate) { _, _ in reload() }
        .onChange(of: agenda.eventsToday) { _, _ in reload() }
        .onAppear { reload() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func eventRow(_ event: CalendarMeetingEvent) -> some View {
        let existing = existingMeeting(for: event.id)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timeRange(event))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if event.isCancelled {
                    Label("Annulé", systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(event.title)
                .font(.body)
                .strikethrough(event.isCancelled)
                .foregroundStyle(event.isCancelled ? .secondary : .primary)
            HStack(spacing: 12) {
                if !event.attendees.isEmpty {
                    Label("\(event.attendees.count)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if event.teamsJoinURL != nil {
                    Label("Teams", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if existing != nil {
                    Label("Importé", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 8) {
                if let url = event.teamsJoinURL {
                    Button {
                        joinAndImport(event: event, url: url)
                    } label: {
                        Label("Rejoindre Teams", systemImage: "video.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if let meeting = existing {
                    Button {
                        openMeeting(meeting)
                    } label: {
                        Label("Ouvrir", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        let meeting = importer.importEvent(event, context: context, settings: settings)
                        try? context.save()
                        openMeeting(meeting)
                    } label: {
                        Label("Importer", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(rowBackground(event))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Accès au calendrier refusé")
                .font(.headline)
            Button("Ouvrir les réglages système") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                NSWorkspace.shared.open(url)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func rowBackground(_ event: CalendarMeetingEvent) -> Color {
        let now = Date()
        if event.endDate < now { return .secondary.opacity(0.05) }
        if event.startDate <= now && event.endDate >= now { return .accentColor.opacity(0.15) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func timeRange(_ event: CalendarMeetingEvent) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) ─ \(fmt.string(from: event.endDate))"
    }

    private func reload() {
        events = agenda.events(for: selectedDate)
    }

    private func existingMeeting(for eventID: String) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Opens Teams and ensures the event is imported as a Meeting (idempotent).
    /// If the Meeting doesn't exist yet, creates it with auto-matched kind/project
    /// and opens it in the app alongside Teams.
    private func joinAndImport(event: CalendarMeetingEvent, url: String) {
        TeamsLauncher.open(url)
        let meeting: Meeting
        if let existing = existingMeeting(for: event.id) {
            meeting = existing
        } else {
            meeting = importer.importEvent(event, context: context, settings: settings)
            try? context.save()
        }
        openMeeting(meeting)
    }

    private func openMeeting(_ meeting: Meeting) {
        NotificationCenter.default.post(name: .openMeetingFromAgenda,
                                        object: nil,
                                        userInfo: ["meetingID": meeting.persistentModelID.storeIdentifier ?? ""])
    }
}

extension Notification.Name {
    static let openMeetingFromAgenda = Notification.Name("OneToOne.AgendaInspectorPanel.openMeeting")
}
