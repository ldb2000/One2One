import SwiftUI

struct CalendarEventImportSheet: View {
    let anchorDate: Date
    let onImport: (CalendarMeetingEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CalendarMeetingImportService()
    @State private var events: [CalendarMeetingEvent] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var accessDenied = false

    private var filteredEvents: [CalendarMeetingEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.calendarTitle.localizedCaseInsensitiveContains(searchText)
                || $0.attendees.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Importer depuis Calendrier")
                    .font(.title3.bold())
                Spacer()
                Button("Fermer") { dismiss() }
            }

            Text("Choisissez un événement proche de la date de la réunion pour importer le titre et les participants.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("Rechercher un événement…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button(action: loadEvents) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            if accessDenied {
                ContentUnavailableView(
                    "Accès Calendrier refusé",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Autorisez l'accès au Calendrier dans les réglages macOS pour importer vos réunions.")
                )
            } else if isLoading {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Chargement des événements…")
                    Spacer()
                }
                Spacer()
            } else if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "Aucun événement trouvé",
                    systemImage: "calendar",
                    description: Text("Aucun événement n'a été trouvé autour du \(anchorDate.formatted(date: .abbreviated, time: .omitted)).")
                )
            } else {
                List(filteredEvents, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened)) • \(event.calendarTitle)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Importer") {
                                onImport(event)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if !event.attendees.isEmpty {
                            Text(event.attendees.map { attendee in
                                attendee.status == .absent ? "\(attendee.name) (absent)" : attendee.name
                            }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 460)
        .task { loadEvents() }
    }

    private func loadEvents() {
        Task {
            isLoading = true
            let granted = await service.requestAccess()
            if granted {
                let cal = Calendar.current
                let yesterdayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
                let end = cal.date(byAdding: .day, value: 30, to: yesterdayStart) ?? Date()
                events = service.fetchEvents(start: yesterdayStart, end: end)
                accessDenied = false
            } else {
                accessDenied = true
                events = []
            }
            isLoading = false
        }
    }
}
