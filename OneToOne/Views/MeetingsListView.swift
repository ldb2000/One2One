import SwiftUI
import SwiftData

struct MeetingsListView: View {
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var filterProject: Project?

    private var filteredMeetings: [Meeting] {
        var result = meetings

        if let project = filterProject {
            result = result.filter { $0.project?.persistentModelID == project.persistentModelID }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                $0.participants.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack(spacing: 12) {
                Picker("Projet", selection: $filterProject) {
                    Text("Tous les projets").tag(nil as Project?)
                    ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Spacer()

                Text("\(filteredMeetings.count) réunion(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: addMeeting) {
                    Label("Nouvelle réunion", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if filteredMeetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune réunion")
                        .foregroundColor(.secondary)
                    Button(action: addMeeting) {
                        Label("Créer une réunion", systemImage: "plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredMeetings) { meeting in
                        NavigationLink {
                            MeetingView(meeting: meeting)
                        } label: {
                            MeetingRowView(meeting: meeting)
                        }
                    }
                    .onDelete(perform: deleteMeetings)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher une réunion...")
        .navigationTitle("Réunions")
    }

    private func addMeeting() {
        let meeting = Meeting(title: "", date: Date(), notes: "")
        context.insert(meeting)
        saveContext()
    }

    private func deleteMeetings(offsets: IndexSet) {
        let sorted = filteredMeetings
        for index in offsets {
            context.delete(sorted[index])
        }
        saveContext()
    }

    private func saveContext() {
        do { try context.save() } catch { print("[MeetingsListView] save FAILED: \(error)") }
    }
}

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title.isEmpty ? "Réunion sans titre" : meeting.title)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let project = meeting.project {
                        Label(project.name, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !meeting.participants.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(meeting.participants.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            let pendingCount = meeting.tasks.filter { !$0.isCompleted }.count
            if pendingCount > 0 {
                VStack {
                    Text("\(pendingCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    Text("actions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
