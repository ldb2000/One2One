import SwiftUI
import SwiftData

struct ActionsListView: View {
    @Query(sort: \ActionTask.dueDate) private var allTasks: [ActionTask]
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .pending
    @State private var filterProject: Project?
    @State private var filterCollaborator: Collaborator?

    enum FilterStatus: String, CaseIterable {
        case pending = "En cours"
        case completed = "Terminées"
        case all = "Toutes"
    }

    private var filteredTasks: [ActionTask] {
        var tasks = allTasks

        switch filterStatus {
        case .pending:
            tasks = tasks.filter { !$0.isCompleted }
        case .completed:
            tasks = tasks.filter { $0.isCompleted }
        case .all:
            break
        }

        if let project = filterProject {
            tasks = tasks.filter { $0.project?.persistentModelID == project.persistentModelID }
        }

        if let collaborator = filterCollaborator {
            tasks = tasks.filter { $0.collaborator?.persistentModelID == collaborator.persistentModelID }
        }

        if !searchText.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        return tasks
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters bar
            HStack(spacing: 12) {
                Picker("Statut", selection: $filterStatus) {
                    ForEach(FilterStatus.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                Picker("Projet", selection: $filterProject) {
                    Text("Tous les projets").tag(nil as Project?)
                    ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker("Assigné à", selection: $filterCollaborator) {
                    Text("Tous").tag(nil as Collaborator?)
                    ForEach(collaborators) { c in Text(c.name).tag(c as Collaborator?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Spacer()

                Text("\(filteredTasks.count) action(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Task list
            if filteredTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune action trouvée")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        ActionTaskRow(
                            task: task,
                            projects: projects,
                            collaborators: collaborators,
                            onSave: saveContext,
                            onDelete: { context.delete(task); saveContext() }
                        )
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher une action...")
        .navigationTitle("Actions")
    }

    private func saveContext() {
        do { try context.save() } catch { print("Save error: \(error)") }
    }
}

// Reusable action row component
struct ActionTaskRow: View {
    @Bindable var task: ActionTask
    let projects: [Project]
    let collaborators: [Collaborator]
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: {
                    task.isCompleted.toggle()
                    onSave()
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
                .buttonStyle(.plain)

                EditableTextField(placeholder: "Action...", text: $task.title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 20)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Supprimer cette action")
            }

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { task.project },
                    set: { task.project = $0; onSave() }
                )) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .font(.caption)

                Picker("", selection: Binding(
                    get: { task.collaborator },
                    set: { task.collaborator = $0; onSave() }
                )) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    ForEach(collaborators) { c in Text(c.name).tag(c as Collaborator?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .font(.caption)

                if let dueDate = task.dueDate {
                    DatePicker("", selection: Binding(
                        get: { dueDate },
                        set: { task.dueDate = $0; onSave() }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .font(.caption)
                    .frame(width: 100)

                    Button(action: { task.dueDate = nil; onSave() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { task.dueDate = Date(); onSave() }) {
                        Label("Échéance", systemImage: "calendar.badge.plus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if task.reminderID != nil {
                    Image(systemName: "bell.fill").font(.caption2).foregroundColor(.blue)
                }

                Spacer()

                if let interview = task.interview, let collab = interview.collaborator {
                    Text("1:1 \(collab.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let meeting = task.meeting {
                    Text("Réunion: \(meeting.title)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }
}
