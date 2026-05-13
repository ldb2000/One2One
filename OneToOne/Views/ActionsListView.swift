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
                ScrollView {
                    LazyVStack(spacing: 0) {
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
                .background(Color(nsColor: .textBackgroundColor))
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

/// Renders Collaborator picker options with pinned (sidebar) at the top,
/// then favourites (star), a divider, then the rest sorted A–Z.
/// Includes ad-hoc collaborators so favourited ones aren't silently hidden.
struct CollaboratorPickerOptions: View {
    let collaborators: [Collaborator]

    var body: some View {
        let active = collaborators.filter { !$0.isArchived }
        let pinned = active
            .filter { $0.pinLevel >= 2 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let favourites = active
            .filter { $0.pinLevel == 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let rest = active
            .filter { $0.pinLevel == 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Group {
            ForEach(pinned) { c in
                Label(c.name, systemImage: "pin.fill").tag(c as Collaborator?)
            }
            if !pinned.isEmpty && (!favourites.isEmpty || !rest.isEmpty) {
                Divider()
            }
            ForEach(favourites) { c in
                Label(c.name, systemImage: "star.fill").tag(c as Collaborator?)
            }
            if !favourites.isEmpty && !rest.isEmpty {
                Divider()
            }
            ForEach(rest) { c in
                Text(c.name).tag(c as Collaborator?)
            }
        }
    }
}

// GitHub-style action row.
// - Open: checkbox + title (bold) + meta line (created date, project, assignee, comments).
// - Completed: rendered as a note-style block (owner, dates, comments, project).
// - Expand to show comments thread + add comment input + editable pickers/due date.
struct ActionTaskRow: View {
    @Bindable var task: ActionTask
    let projects: [Project]
    let collaborators: [Collaborator]
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var expanded: Bool = false
    @State private var newCommentText: String = ""

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        if task.isCompleted {
            completedNoteView
        } else {
            openTaskView
        }
    }

    // MARK: - Open (GitHub-style)

    private var openTaskView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: toggleCompleted) {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(Color(red: 0.16, green: 0.65, blue: 0.27))  // GitHub-green
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Marquer comme terminée")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isEditingTitle {
                            TextField("Action…", text: $task.title, onCommit: {
                                isEditingTitle = false
                                onSave()
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                        } else {
                            Text(task.title.isEmpty ? "Sans titre" : task.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(task.title.isEmpty ? .secondary : .primary)
                                .onTapGesture(count: 2) { isEditingTitle = true }
                        }

                        if task.fromManager {
                            Label("manager", systemImage: "person.crop.square.filled.and.at.rectangle")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    metaLine
                }

                Spacer(minLength: 8)

                if !task.comments.isEmpty {
                    Label("\(task.comments.count)", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditingTitle { expanded.toggle() }
            }

            if expanded {
                Divider()
                expandedDetails
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
        .background(rowBackground)
        .overlay(
            Rectangle().frame(height: 1)
                .foregroundColor(Color.secondary.opacity(0.15)),
            alignment: .bottom
        )
    }

    @State private var isEditingTitle: Bool = false
    @State private var isHovering: Bool = false

    private var rowBackground: some View {
        Color(nsColor: .textBackgroundColor)
            .opacity(isHovering ? 0.6 : 1.0)
            .onHover { isHovering = $0 }
    }

    private var metaLine: some View {
        HStack(spacing: 4) {
            Text("#\(task.persistentModelID.hashValue & 0xFFFF, specifier: "%X")")
                .foregroundColor(.secondary)
            Text("·").foregroundColor(.secondary)
            if let createdAt = task.createdAt {
                Text("ouverte le \(Self.dateFmt.string(from: createdAt))")
            } else {
                Text("ouverte (date inconnue)")
            }
            if let project = task.project {
                Text("·").foregroundColor(.secondary)
                Label(project.name, systemImage: "folder")
            }
            if let collab = task.collaborator {
                Text("·").foregroundColor(.secondary)
                Label(collab.name, systemImage: "person.fill")
            }
            if let due = task.dueDate {
                Text("·").foregroundColor(.secondary)
                Label(Self.dateFmt.string(from: due), systemImage: "calendar")
                    .foregroundStyle(due < Date() ? .red : .secondary)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { task.project },
                    set: { task.project = $0; onSave() }
                )) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .font(.caption)

                Picker("", selection: Binding(
                    get: { task.collaborator },
                    set: { task.collaborator = $0; onSave() }
                )) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .font(.caption)

                DatePicker("", selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0; onSave() }
                ), displayedComponents: .date)
                .labelsHidden()
                .font(.caption)
                .opacity(task.dueDate == nil ? 0.6 : 1.0)

                if task.dueDate != nil {
                    Button(action: { task.dueDate = nil; onSave() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // Comments thread
            if !task.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commentaires").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(task.comments.sorted { $0.date < $1.date }) { c in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.dateFmt.string(from: c.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 84, alignment: .leading)
                            Text(c.text).font(.caption)
                            Spacer()
                            Button {
                                if let comment = task.comments.first(where: { $0.persistentModelID == c.persistentModelID }) {
                                    context.delete(comment)
                                    onSave()
                                }
                            } label: {
                                Image(systemName: "xmark.circle").font(.caption2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add comment
            HStack {
                TextField("Ajouter un commentaire…", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Ajouter") { addComment() }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 34)
    }

    // MARK: - Completed (note-style)

    private var completedNoteView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleCompleted) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                Text(task.title)
                    .font(.body.bold())
                    .strikethrough()
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let collab = task.collaborator {
                    Text("Owner: \(collab.name)").font(.caption)
                }
                Text("Du \(formattedOrUnknown(task.createdAt)) au \(formattedOrUnknown(task.completedAt))")
                    .font(.caption)
                ForEach(task.comments.sorted { $0.date < $1.date }) { c in
                    Text("\(Self.dateFmt.string(from: c.date)) — \(c.text)")
                        .font(.caption)
                }
                if let project = task.project {
                    Text("Projet: \(project.name)").font(.caption.italic())
                }
            }
            .foregroundColor(.secondary)
            .padding(.leading, 34)
        }
        .padding(.vertical, 6)
    }

    private func formattedOrUnknown(_ date: Date?) -> String {
        guard let date else { return "?" }
        return Self.dateFmt.string(from: date)
    }

    // MARK: - Mutations

    private func toggleCompleted() {
        task.isCompleted.toggle()
        if task.isCompleted {
            task.completedAt = Date()
        } else {
            task.completedAt = nil
        }
        onSave()
    }

    private func addComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let c = ActionComment(text: trimmed)
        context.insert(c)
        c.task = task
        newCommentText = ""
        onSave()
    }
}
