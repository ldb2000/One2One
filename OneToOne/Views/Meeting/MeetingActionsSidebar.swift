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
            LazyVStack(spacing: 8) {
                ForEach(meeting.tasks) { task in
                    taskRow(task)
                }
            }
            .padding(10)
        }
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
                if let c = task.collaborator {
                    HStack(spacing: 4) {
                        AvatarMini(collaborator: c, tint: settings.meetingParticipantColor)
                        Text(c.name).font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text("Non assigné").font(.caption).foregroundColor(.secondary)
                }
                Text("·").foregroundColor(.secondary)
                if let dd = task.dueDate {
                    Text(shortDate(dd)).font(MeetingTheme.meta).foregroundColor(.secondary)
                } else {
                    Text("Pas d'échéance").font(.caption).foregroundColor(.secondary)
                }
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
                Picker("Assigné à", selection: $selectedCollaborator) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                }
                .pickerStyle(.menu)
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
        df.dateFormat = "dd/MM/yyyy"
        return df.string(from: d)
    }
}
