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
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker("Assigné à", selection: $filterCollaborator) {
                    Text("Tous").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Spacer()

                Button(action: addAction) {
                    Label("Nouvelle action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

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

    private func addAction() {
        let task = ActionTask(title: "Nouvelle action")
        task.project = filterProject
        task.collaborator = filterCollaborator
        context.insert(task)
        saveContext()
    }
}

/// Renders Collaborator picker options with favourites/pinned first,
/// a divider, then the rest sorted alphabetically. Adhoc collaborators
/// are excluded for cleanliness.
struct CollaboratorPickerOptions: View {
    let collaborators: [Collaborator]

    var body: some View {
        let filtered = collaborators.filter { !$0.isAdhoc && !$0.isArchived }
        let pinned = filtered
            .filter { $0.pinLevel > 0 }
            .sorted { lhs, rhs in
                if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        let rest = filtered
            .filter { $0.pinLevel == 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Group {
            ForEach(pinned) { c in
                Label(c.name, systemImage: c.pinLevel >= 2 ? "pin.fill" : "star.fill").tag(c as Collaborator?)
            }
            if !pinned.isEmpty && !rest.isEmpty {
                Divider()
            }
            ForEach(rest) { c in
                Text(c.name).tag(c as Collaborator?)
            }
        }
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

                if task.fromManager {
                    Label("manager", systemImage: "person.crop.square.filled.and.at.rectangle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                        .help("Action demandée par le manager")
                }

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
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .font(.caption)

                Picker("", selection: Binding(
                    get: { task.collaborator },
                    set: { task.collaborator = $0; onSave() }
                )) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .font(.caption)

                DatePicker("", selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0; onSave() }
                ), displayedComponents: .date)
                .labelsHidden()
                .font(.caption)
                .opacity(task.dueDate == nil ? 0.6 : 1.0)
                .help(task.dueDate == nil ? "Définir une échéance" : "Modifier l'échéance")

                if task.dueDate != nil {
                    Button(action: { task.dueDate = nil; onSave() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Retirer l'échéance")
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
