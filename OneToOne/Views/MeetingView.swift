import SwiftUI
import SwiftData

struct MeetingView: View {
    @Bindable var meeting: Meeting
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var newTaskTitle = ""
    @State private var selectedProject: Project?
    @State private var selectedCollaborator: Collaborator?
    @State private var showNewTaskDueDate = false
    @State private var newTaskDueDate: Date? = nil
    @State private var showMarkdownPreview = false
    @State private var participantsRefreshID = UUID()

    var body: some View {
        HSplitView {
            notesPanel
                .frame(minWidth: 400)
            actionsPanel
                .frame(minWidth: 300, maxWidth: 400)
        }
        .navigationTitle(meeting.title.isEmpty ? "Réunion" : meeting.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: saveContext) {
                    Label("Enregistrer", systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Notes Panel

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    EditableTextField(placeholder: "Titre de la réunion...", text: $meeting.title)
                        .frame(height: 28)
                        .font(.title2)

                    DatePicker("", selection: $meeting.date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .frame(width: 200)
                }

                HStack {
                    Picker("Projet", selection: Binding(
                        get: { meeting.project },
                        set: { meeting.project = $0; saveContext() }
                    )) {
                        Text("Aucun projet").tag(nil as Project?)
                        ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                // Participants
                participantsSection
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Toolbar + notes
            HStack(spacing: 4) {
                Spacer()

                if !showMarkdownPreview {
                    MarkdownToolbar(textViewID: "meetingNotes")
                    Divider().frame(height: 16).padding(.horizontal, 4)
                }

                Button(action: { showMarkdownPreview.toggle() }) {
                    Image(systemName: showMarkdownPreview ? "eye.fill" : "eye")
                        .foregroundColor(showMarkdownPreview ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showMarkdownPreview ? "Masquer la preview" : "Afficher la preview")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.03))

            if showMarkdownPreview {
                MarkdownTextView(markdown: meeting.notes)
            } else {
                MarkdownEditorView(text: $meeting.notes, textViewID: "meetingNotes")
            }
        }
    }

    // MARK: - Participants

    private var availableCollaborators: [Collaborator] {
        let participantIDs = Set(meeting.participants.map(\.persistentModelID))
        return allCollaborators.filter { !participantIDs.contains($0.persistentModelID) }
    }

    private func addParticipant(_ collab: Collaborator) {
        meeting.participants.append(collab)
        saveContext()
        participantsRefreshID = UUID()
    }

    private func removeParticipant(_ participant: Collaborator) {
        meeting.participants.removeAll { $0.persistentModelID == participant.persistentModelID }
        saveContext()
        participantsRefreshID = UUID()
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Participants")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(meeting.participants) { participant in
                    HStack(spacing: 4) {
                        Text(participant.name)
                            .font(.caption)
                        Button(action: { removeParticipant(participant) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)
                }

                Menu {
                    ForEach(availableCollaborators) { collab in
                        Button(collab.name) {
                            addParticipant(collab)
                        }
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus.circle")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90)
            }
            .id(participantsRefreshID)
        }
    }

    // MARK: - Actions Panel

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Actions")
                    .font(.headline)
                let taskCount = meeting.tasks.filter { !$0.isCompleted }.count
                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                ForEach(meeting.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button(action: {
                                task.isCompleted.toggle()
                                saveContext()
                            }) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isCompleted ? .green : .gray)
                            }
                            .buttonStyle(.plain)

                            EditableTextField(placeholder: "Action...", text: Bindable(task).title)
                                .strikethrough(task.isCompleted)
                                .frame(height: 20)

                            Spacer()

                            Button(action: {
                                context.delete(task)
                                saveContext()
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { task.collaborator },
                                set: { task.collaborator = $0; saveContext() }
                            )) {
                                Text("Non assigné").tag(nil as Collaborator?)
                                ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)
                            .font(.caption)

                            if let dueDate = task.dueDate {
                                DatePicker("", selection: Binding(
                                    get: { dueDate },
                                    set: { task.dueDate = $0; saveContext() }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                .font(.caption)
                                .frame(width: 100)

                                Button(action: { task.dueDate = nil; saveContext() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { task.dueDate = Date(); saveContext() }) {
                                    Label("Échéance", systemImage: "calendar.badge.plus")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteTasks)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Add new task
            VStack(spacing: 8) {
                EditableTextField(placeholder: "Nouvelle action...", text: $newTaskTitle)
                    .frame(height: 24)

                HStack(spacing: 8) {
                    Picker("Assigné à", selection: $selectedCollaborator) {
                        Text("Non assigné").tag(nil as Collaborator?)
                        ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                    }
                    .pickerStyle(.menu)

                    Toggle(isOn: $showNewTaskDueDate) {
                        Label("Échéance", systemImage: "calendar")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)

                    if showNewTaskDueDate {
                        DatePicker("", selection: Binding(
                            get: { newTaskDueDate ?? Date() },
                            set: { newTaskDueDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                    }
                }

                Button(action: addTask) {
                    Label("Ajouter l'action", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - Actions

    private func addTask() {
        let task = ActionTask(title: newTaskTitle, dueDate: showNewTaskDueDate ? (newTaskDueDate ?? Date()) : nil)
        task.meeting = meeting
        task.project = meeting.project
        task.collaborator = selectedCollaborator
        context.insert(task)
        newTaskTitle = ""
        newTaskDueDate = nil
        showNewTaskDueDate = false
        saveContext()
    }

    private func deleteTasks(offsets: IndexSet) {
        let tasks = meeting.tasks
        for index in offsets {
            context.delete(tasks[index])
        }
        saveContext()
    }

    private func saveContext() {
        do { try context.save() } catch { print("[MeetingView] save FAILED: \(error)") }
    }
}

// Simple flow layout for participant chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxHeight = max(maxHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + maxHeight), positions)
    }
}
