import SwiftUI
import SwiftData

struct MeetingActionsSidebar: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]

    @Binding var collapsed: Bool
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?

    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
    let saveContext: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showingAddCollaboratorSheet: Bool = false

    var body: some View {
        if collapsed {
            collapsedRail
        } else {
            expandedPanel
        }
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tasksList
            formSection
            Divider()
            capturePreviewCard
        }
        .frame(minWidth: 300, maxWidth: 440)
        .background(MeetingTheme.surfaceCream)
    }

    private var header: some View {
        HStack {
            Text("ACTIONS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)
            let openCount = meeting.tasks.filter { !$0.isCompleted }.count
            if openCount > 0 {
                Text("\(openCount)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(MeetingTheme.accentOrange))
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = true }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Replier le panneau")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

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
            HStack(spacing: 4) {
                if let c = task.collaborator {
                    AvatarMini(collaborator: c, tint: settings.meetingParticipantColor)
                    Text(c.name).font(.caption).foregroundColor(.secondary)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("Non assigné").font(.caption).foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
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
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
                if let dd = task.dueDate {
                    Text(shortDate(dd)).font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Pas d'échéance").font(.caption).foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var capturePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            if let latest = currentSlides.last,
               let image = NSImage(contentsOfFile: latest.imagePath) {
                Button(action: onShowSlides) {
                    ZStack(alignment: .bottomLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Slide \(latest.index)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            Text(latest.capturedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MeetingTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onShowCaptureSetup) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Aucune capture")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    // MARK: - Collapsed rail

    private var collapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help("Déplier le panneau")

            let openCount = meeting.tasks.filter { !$0.isCompleted }.count
            if openCount > 0 {
                ZStack {
                    Circle().fill(MeetingTheme.accentOrange)
                    Text("\(openCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                }
                .frame(width: 22, height: 22)
                .help(openTasksTooltip)
            }

            Image(systemName: "checkmark.circle")
                .foregroundColor(.secondary)

            Spacer()

            if !currentSlides.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "camera.viewfinder").foregroundColor(.secondary)
                        Text("\(currentSlides.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 8, y: -4)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(MeetingTheme.surfaceCream)
        .overlay(alignment: .leading) {
            Rectangle().fill(MeetingTheme.hairline).frame(width: 0.5)
        }
    }

    private var openTasksTooltip: String {
        meeting.tasks
            .filter { !$0.isCompleted }
            .prefix(3)
            .map { String($0.title.prefix(40)) }
            .joined(separator: "\n")
    }

    private func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.timeZone = .current
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}

// MARK: - Add collaborator search sheet

private struct AddCollaboratorSheet: View {
    let allCollaborators: [Collaborator]
    let onPick: (Collaborator) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [Collaborator] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allCollaborators.filter { !$0.isArchived }
        guard !trimmed.isEmpty else {
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return base
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var exactMatchExists: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCollaborators.contains { $0.name.lowercased() == trimmed }
    }

    private var canCreate: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !exactMatchExists
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choisir un collaborateur").font(.headline)
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher par nom…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let first = filtered.first { onPick(first) }
                        else if canCreate { onCreate(query) }
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            List {
                if canCreate {
                    Button {
                        onCreate(query)
                    } label: {
                        Label("Créer « \(query.trimmingCharacters(in: .whitespacesAndNewlines)) »",
                              systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(filtered) { c in
                    Button {
                        onPick(c)
                    } label: {
                        HStack {
                            Text(c.name)
                            if c.pinLevel >= 1 {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            Spacer()
                            if !c.role.isEmpty {
                                Text(c.role)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty && !canCreate {
                    Text("Aucun résultat. Tape un nom pour créer un nouveau collaborateur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 360, minHeight: 380)
    }
}
