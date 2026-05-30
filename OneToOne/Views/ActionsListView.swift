import SwiftUI
import SwiftData

struct ActionsListView: View {
    @Query(sort: \ActionTask.dueDate) private var allTasks: [ActionTask]
    @Query private var projects: [Project]
    @Query private var entities: [Entity]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .pending
    @State private var filterProject: Project?
    @State private var filterEntity: Entity?
    @State private var filterCollaborator: Collaborator?
    @State private var filterDueDate: DueDateFilter = .any

    enum FilterStatus: String, CaseIterable {
        case pending = "En cours"
        case completed = "Terminées"
        case all = "Toutes"
    }

    enum DueDateFilter: String, CaseIterable, Identifiable {
        case any         = "Toutes échéances"
        case withDate    = "Avec échéance"
        case withoutDate = "Sans échéance"
        case overdue     = "En retard"
        var id: String { rawValue }
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
        } else if let entity = filterEntity {
            tasks = tasks.filter { $0.project?.entity?.persistentModelID == entity.persistentModelID }
        }

        if let collaborator = filterCollaborator {
            tasks = tasks.filter { $0.collaborator?.persistentModelID == collaborator.persistentModelID }
        }

        switch filterDueDate {
        case .any:
            break
        case .withDate:
            tasks = tasks.filter { $0.dueDate != nil }
        case .withoutDate:
            tasks = tasks.filter { $0.dueDate == nil }
        case .overdue:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            tasks = tasks.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
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
                .labelsHidden()
                .frame(maxWidth: 250)

                projectFilterMenu

                Picker("Assigné à", selection: $filterCollaborator) {
                    Text("Tous").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker("Échéance", selection: $filterDueDate) {
                    ForEach(DueDateFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 170)

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

    /// Hierarchical project filter: Entities at the top level, each opens
    /// a submenu of its projects. "Sans entité" groups orphan projects.
    private var projectFilterMenu: some View {
        Menu {
            Button("Tous les projets") {
                filterProject = nil
                filterEntity = nil
            }
            Divider()
            let sortedEntities = entities.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ForEach(sortedEntities) { entity in
                let entityProjects = projects
                    .filter { $0.entity?.persistentModelID == entity.persistentModelID && !$0.isArchived }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !entityProjects.isEmpty {
                    Menu(entity.name) {
                        Button("Tous les projets de \(entity.name)") {
                            filterEntity = entity
                            filterProject = nil
                        }
                        Divider()
                        ForEach(entityProjects) { p in
                            Button(p.name) {
                                filterProject = p
                                filterEntity = nil
                            }
                        }
                    }
                }
            }
            let orphans = projects
                .filter { $0.entity == nil && !$0.isArchived }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !orphans.isEmpty {
                Divider()
                Menu("Sans entité") {
                    ForEach(orphans) { p in
                        Button(p.name) {
                            filterProject = p
                            filterEntity = nil
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(currentProjectFilterLabel).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var currentProjectFilterLabel: String {
        if let p = filterProject { return p.name }
        if let e = filterEntity { return "📂 \(e.name)" }
        return "Tous les projets"
    }

    private func addAction() {
        let task = ActionTask(title: "Nouvelle action")
        task.project = filterProject
        task.collaborator = filterCollaborator
        context.insert(task)
        saveContext()
    }
}

/// Renders Collaborator picker options groupés selon le filtre de la sidebar
/// (`sidebar.collabsFilter`) :
/// - `pinned`     → épinglés au top, divider, le reste A–Z
/// - `favourites` → favoris au top, divider, le reste A–Z
/// - `both`       → épinglés ET favoris au top (alpha mixé), divider, le reste A–Z
/// Inclut tous les collaborateurs non-archivés pour ne pas masquer un favori.
struct CollaboratorPickerOptions: View {
    let collaborators: [Collaborator]
    @AppStorage("sidebar.collabsFilter") private var collabsFilter: String = "both"

    var body: some View {
        let groups = partitioned()
        Group {
            ForEach(groups.top) { c in
                Label(c.name, systemImage: pillIcon(for: c)).tag(c as Collaborator?)
            }
            if !groups.top.isEmpty && !groups.rest.isEmpty {
                Divider()
            }
            ForEach(groups.rest) { c in
                Text(c.name).tag(c as Collaborator?)
            }
        }
    }

    private func partitioned() -> (top: [Collaborator], rest: [Collaborator]) {
        let active = collaborators
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch collabsFilter {
        case "pinned":
            return (active.filter { $0.pinLevel == 2 },
                    active.filter { $0.pinLevel != 2 })
        case "favourites":
            return (active.filter { $0.pinLevel == 1 },
                    active.filter { $0.pinLevel != 1 })
        default:  // both
            return (active.filter { $0.pinLevel >= 1 },
                    active.filter { $0.pinLevel == 0 })
        }
    }

    private func pillIcon(for c: Collaborator) -> String {
        switch c.pinLevel {
        case 2:  return "pin.fill"
        case 1:  return "star.fill"
        default: return "person"
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
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(statusHelp)

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
            // ID technique gardé en très discret (caption2 tertiary) pour
            // ne pas saturer la ligne.
            Text("#\(task.persistentModelID.hashValue & 0xFFFF, specifier: "%X")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let createdAt = task.createdAt {
                Text("·").foregroundStyle(.tertiary)
                Text("ouverte le \(Self.dateFmt.string(from: createdAt))")
            }
            // "ouverte (date inconnue)" supprimé : pas d'info utile, juste du bruit.
            if let project = task.project {
                Text("·").foregroundStyle(.tertiary)
                Label(project.name, systemImage: "folder")
            }
            if let collab = task.collaborator {
                Text("·").foregroundStyle(.tertiary)
                Label(collab.name, systemImage: "person.fill")
            }
            if let due = task.dueDate {
                Text("·").foregroundStyle(.tertiary)
                Label(Self.relativeDueLabel(due), systemImage: "calendar")
                    .foregroundStyle(Self.dueColor(due))
                    .help(Self.dateFmt.string(from: due))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Status visuals

    private enum TaskStatus {
        case overdue, dueToday, dueSoon, upcoming, undated
    }

    private var taskStatus: TaskStatus {
        guard let due = task.dueDate else { return .undated }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let in48h = cal.date(byAdding: .day, value: 2, to: today) ?? today
        if due < today { return .overdue }
        if due < tomorrow { return .dueToday }
        if due < in48h { return .dueSoon }
        return .upcoming
    }

    private var statusIcon: String {
        switch taskStatus {
        case .overdue:  return "exclamationmark.circle.fill"
        case .dueToday: return "circle.fill"
        case .dueSoon:  return "circle.fill"
        case .upcoming: return "circle"
        case .undated:  return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch taskStatus {
        case .overdue:  return .red
        case .dueToday: return .orange
        case .dueSoon:  return .blue
        case .upcoming: return .secondary
        case .undated:  return .secondary.opacity(0.6)
        }
    }

    private var statusHelp: String {
        switch taskStatus {
        case .overdue:  return "En retard — cliquer pour marquer comme terminée"
        case .dueToday: return "À échéance aujourd'hui"
        case .dueSoon:  return "Échéance dans les 48h"
        case .upcoming: return "À venir"
        case .undated:  return "Sans date"
        }
    }

    static func relativeDueLabel(_ due: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dueDay = cal.startOfDay(for: due)
        let days = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
        switch days {
        case ..<0:  return "En retard de \(-days)j"
        case 0:     return "Aujourd'hui"
        case 1:     return "Demain"
        case 2...7: return "Dans \(days)j"
        default:    return dateFmt.string(from: due)
        }
    }

    static func dueColor(_ due: Date) -> Color {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let in48h = cal.date(byAdding: .day, value: 2, to: today) ?? today
        if due < today { return .red }
        if due < in48h { return .orange }
        return .secondary
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
