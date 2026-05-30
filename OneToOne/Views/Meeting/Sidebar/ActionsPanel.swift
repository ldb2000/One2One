import SwiftUI
import SwiftData

/// Panneau Actions de la sidebar configurable. Wrap le tasksList + formSection
/// (création + édition des ActionTask de la réunion). Logique identique à
/// l'ancien MeetingActionsSidebar — refactor pur.
struct ActionsPanel: View {

    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]

    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?

    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let saveContext: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showingAddCollaboratorSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tasksList
            formSection
        }
    }

    // MARK: - Tasks list

    private var tasksList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let collab = oneToOnePartner, !otherCollabOpenActions(for: collab).isEmpty {
                    Text("Actions ouvertes de \(collab.name)")
                        .font(MeetingTheme.sectionLabel)
                        .tracking(1.2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    ForEach(otherCollabOpenActions(for: collab)) { task in
                        taskRow(task)
                            .opacity(0.85)
                    }
                    Divider().padding(.vertical, 4)
                    Text("Cette réunion")
                        .font(MeetingTheme.sectionLabel)
                        .tracking(1.2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                ForEach(meeting.tasks) { task in
                    taskRow(task)
                }
            }
            .padding(10)
        }
    }

    private var oneToOnePartner: Collaborator? {
        guard meeting.kind == .oneToOne else { return nil }
        return meeting.participants.first
    }

    private func otherCollabOpenActions(for collab: Collaborator) -> [ActionTask] {
        // Tasks assigned to collab, open, not part of THIS meeting.
        let direct = collab.assignedTasks
        let viaInterviews = collab.interviews.flatMap { $0.tasks }
        var seen = Set<PersistentIdentifier>()
        let combined = (direct + viaInterviews).filter { task in
            guard !task.isCompleted else { return false }
            guard task.meeting?.persistentModelID != meeting.persistentModelID else { return false }
            return seen.insert(task.persistentModelID).inserted
        }
        return combined.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    @ViewBuilder
    private func taskRow(_ task: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { onToggleTaskCompletion(task) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                EditableTextField(placeholder: "Action…", text: Bindable(task).title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 22)

                Spacer()
                Menu {
                    Button(role: .destructive) { onDeleteTask(task) } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let hint = task.unresolvedAssigneeName, task.collaborator == nil {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text("Auto : \(hint)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Choisir") {
                        showingAddCollaboratorSheet = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
                .padding(.leading, 30)
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                rowAssigneeMenu(task)
                Text("·").foregroundColor(.secondary)
                rowDueDateMenu(task)
                Spacer()
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
    }

    // MARK: - Form section

    private var formSection: some View {
        VStack(spacing: 8) {
            EditableTextField(placeholder: "Nouvelle action…", text: $newTaskTitle)
                .frame(height: 24)
            HStack(spacing: 8) {
                assigneeMenu
                Toggle(isOn: $showNewTaskDueDate) {
                    Label("Échéance", systemImage: "calendar").font(.caption)
                }
                .toggleStyle(.checkbox)
                if showNewTaskDueDate {
                    DatePicker("", selection: Binding(
                        get: { newTaskDueDate ?? Date() },
                        set: { newTaskDueDate = $0 }
                    ), displayedComponents: .date).labelsHidden()
                }
            }
            Button(action: onAddTask) {
                Label("Ajouter l'action", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MeetingTheme.accentOrange)
            .disabled(newTaskTitle.isEmpty)
        }
        .padding(14)
        .background(MeetingTheme.canvasCream)
        .sheet(isPresented: $showingAddCollaboratorSheet) {
            AddCollaboratorSheet(
                allCollaborators: allCollaborators,
                onPick: { collab in
                    selectedCollaborator = collab
                    showingAddCollaboratorSheet = false
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let c = Collaborator(name: trimmed)
                    context.insert(c)
                    try? context.save()
                    selectedCollaborator = c
                    showingAddCollaboratorSheet = false
                }
            )
        }
    }

    // MARK: - Assignee menu

    private var participantCandidates: [Collaborator] {
        meeting.participants
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var favoriteCandidates: [Collaborator] {
        let participantIDs = Set(meeting.participants.map { $0.persistentModelID })
        return allCollaborators
            .filter { $0.pinLevel >= 1 && !participantIDs.contains($0.persistentModelID) && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var assigneeLabel: String {
        selectedCollaborator?.name ?? "Non assigné"
    }

    @ViewBuilder
    private var assigneeMenu: some View {
        Menu {
            Button {
                selectedCollaborator = nil
            } label: {
                if selectedCollaborator == nil {
                    Label("Non assigné", systemImage: "checkmark")
                } else {
                    Text("Non assigné")
                }
            }

            if !participantCandidates.isEmpty {
                Divider()
                Section("Participants") {
                    ForEach(participantCandidates) { c in
                        Button {
                            selectedCollaborator = c
                        } label: {
                            if selectedCollaborator?.persistentModelID == c.persistentModelID {
                                Label(c.name, systemImage: "checkmark")
                            } else {
                                Text(c.name)
                            }
                        }
                    }
                }
            }

            if !favoriteCandidates.isEmpty {
                Divider()
                Section("Favoris") {
                    ForEach(favoriteCandidates) { c in
                        Button {
                            selectedCollaborator = c
                        } label: {
                            if selectedCollaborator?.persistentModelID == c.persistentModelID {
                                Label(c.name, systemImage: "checkmark")
                            } else {
                                Text(c.name)
                            }
                        }
                    }
                }
            }

            Divider()
            Button {
                showingAddCollaboratorSheet = true
            } label: {
                Label("Ajouter un collaborateur…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.caption)
                Text(assigneeLabel)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Assigner à un participant, un favori, ou un nouveau collaborateur")
    }

    // MARK: - Per-task inline menus

    @ViewBuilder
    private func rowAssigneeMenu(_ task: ActionTask) -> some View {
        Menu {
            Button {
                task.collaborator = nil
                task.unresolvedAssigneeName = nil
                saveContext()
            } label: { Text("Non assigné") }

            if !participantCandidates.isEmpty {
                Divider()
                Section("Participants") {
                    ForEach(participantCandidates) { c in
                        Button(c.name) {
                            task.collaborator = c
                            task.unresolvedAssigneeName = nil
                            saveContext()
                        }
                    }
                }
            }
            if !favoriteCandidates.isEmpty {
                Divider()
                Section("Favoris") {
                    ForEach(favoriteCandidates) { c in
                        Button(c.name) {
                            task.collaborator = c
                            task.unresolvedAssigneeName = nil
                            saveContext()
                        }
                    }
                }
            }
        } label: {
            // macOS Menu .borderlessButton n'accepte qu'un Text/Label plat
            // dans son label. AvatarMini + HStack complexe disparait. On
            // utilise un Label SwiftUI standard avec SF Symbol + nom.
            Label(
                task.collaborator?.name ?? "Non assigné",
                systemImage: task.collaborator != nil
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
            .font(.caption)
            .foregroundColor(task.collaborator != nil ? .primary : .secondary)
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func rowDueDateMenu(_ task: ActionTask) -> some View {
        Menu {
            Button("Aucune") {
                task.dueDate = nil
                saveContext()
            }
            Button("Aujourd'hui") {
                task.dueDate = Date()
                saveContext()
            }
            Button("Demain") {
                task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                saveContext()
            }
            Button("Dans 1 semaine") {
                task.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                saveContext()
            }
        } label: {
            Label(
                task.dueDate.map(shortDate) ?? "Pas d'échéance",
                systemImage: "calendar"
            )
            .font(.caption)
            .foregroundColor(task.dueDate != nil ? .primary : .secondary)
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Utilities

    private func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.timeZone = .current
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}
