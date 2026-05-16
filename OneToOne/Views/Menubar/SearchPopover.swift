import SwiftUI
import SwiftData

/// Compact cross-entity search popover. Returns the chosen target via
/// `onSelectMeeting` / `onSelectCollaborator` / `onSelectProject`.
struct SearchPopover: View {
    let onSelectMeeting: (Meeting) -> Void
    let onSelectCollaborator: (Collaborator) -> Void
    let onSelectProject: (Project) -> Void
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var meetings: [Meeting] = []
    @State private var collaborators: [Collaborator] = []
    @State private var projects: [Project] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Rechercher…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }

            if debouncedQuery.isEmpty {
                ContentUnavailableView("Tapez pour rechercher",
                                       systemImage: "magnifyingglass",
                                       description: Text("Réunions · Collaborateurs · Projets"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !meetings.isEmpty {
                            section(title: "Réunions") {
                                ForEach(meetings) { m in
                                    row(label: rowLabelMeeting(m), icon: "person.3.fill") {
                                        onSelectMeeting(m); onDismiss()
                                    }
                                }
                            }
                        }
                        if !collaborators.isEmpty {
                            section(title: "Collaborateurs") {
                                ForEach(collaborators) { c in
                                    row(label: c.pinLevel >= 1 ? "⭐ \(c.name)" : c.name,
                                        icon: "person.fill") {
                                        onSelectCollaborator(c); onDismiss()
                                    }
                                }
                            }
                        }
                        if !projects.isEmpty {
                            section(title: "Projets") {
                                ForEach(projects) { p in
                                    row(label: p.name, icon: "folder.fill") {
                                        onSelectProject(p); onDismiss()
                                    }
                                }
                            }
                        }
                        if meetings.isEmpty && collaborators.isEmpty && projects.isEmpty {
                            Text("Aucun résultat").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(width: 440, height: 360)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundColor(.secondary)
            content()
        }
    }

    private func row(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundColor(.secondary)
                Text(label).font(.body)
                Spacer()
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowLabelMeeting(_ m: Meeting) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: m.date)) — \(m.title)"
    }

    private func scheduleSearch(_ raw: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled { await runSearch(raw) }
        }
    }

    @MainActor
    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debouncedQuery = q
        guard !q.isEmpty else {
            meetings = []; collaborators = []; projects = []; return
        }

        var meetingDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        meetingDescriptor.fetchLimit = 5
        meetings = (try? context.fetch(meetingDescriptor)) ?? []

        var collabDescriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate<Collaborator> { !$0.isArchived && $0.name.localizedStandardContains(q) }
        )
        collabDescriptor.fetchLimit = 20
        let rawCollabs = (try? context.fetch(collabDescriptor)) ?? []
        collaborators = rawCollabs
            .sorted { lhs, rhs in
                if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }

        var projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> {
                !$0.isArchived && ($0.name.localizedStandardContains(q) || $0.code.localizedStandardContains(q))
            },
            sortBy: [SortDescriptor(\.name)]
        )
        projectDescriptor.fetchLimit = 5
        projects = (try? context.fetch(projectDescriptor)) ?? []
    }
}
