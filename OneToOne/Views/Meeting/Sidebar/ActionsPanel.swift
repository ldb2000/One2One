import SwiftUI
import SwiftData

/// Mode d'affichage de la carte Actions (sélecteur de vue).
enum ActionsViewMode: String, CaseIterable {
    case liste, eisenhower
    var label: String {
        switch self { case .liste: return "Liste"; case .eisenhower: return "Eisenhower" }
    }
    var systemImage: String {
        switch self { case .liste: return "list.bullet"; case .eisenhower: return "square.grid.2x2" }
    }
}

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
    @Binding var newTaskAudience: ActionAudience
    @Binding var newTaskUrgent: Bool
    @Binding var newTaskImportant: Bool
    @Binding var newTaskPomodoros: Int

    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let saveContext: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showingAddCollaboratorSheet: Bool = false
    @State private var viewMode: ActionsViewMode = .liste

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $viewMode) {
                ForEach(ActionsViewMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 10)

            switch viewMode {
            case .liste:      tasksList
            case .eisenhower: eisenhowerView
            }
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
                ForEach(ActionAudience.allCases, id: \.self) { audience in
                    let group = sortedGroup(meeting.tasks.filter { $0.destinataire == audience })
                    if !group.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: audience.systemImage).font(.caption2)
                            Text(audience.sectionTitle).tracking(1.0)
                            Spacer()
                            let total = group.reduce(0) { $0 + $1.pomodoros }
                            if total > 0 { Text(chargeLabel(total)) }
                        }
                        .font(MeetingTheme.sectionLabel)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4).padding(.top, 4)
                        ForEach(group) { task in
                            taskRow(task)
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    /// Tri d'un groupe : non terminées d'abord, puis par échéance croissante
    /// (sans échéance en dernier), puis ordre manuel.
    private func sortedGroup(_ tasks: [ActionTask]) -> [ActionTask] {
        tasks.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
            if da != db { return da < db }
            return a.sortOrder < b.sortOrder
        }
    }

    /// Le collaborateur « en face » d'un 1:1 (1er participant), uniquement pour
    /// les réunions `.oneToOne`. `nil` pour tout autre type : sert à n'afficher
    /// le rappel des actions ouvertes que dans le contexte d'un tête-à-tête.
    private var oneToOnePartner: Collaborator? {
        guard meeting.kind == .oneToOne else { return nil }
        return meeting.participants.first
    }

    /// Actions ouvertes (non terminées) assignées à `collab`, agrégées depuis
    /// ses assignations directes et celles de ses interviews, dédupliquées, et
    /// en excluant celles de la réunion courante. Triées par échéance croissante
    /// (les actions sans échéance en dernier).
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

                priorityDot(task)

                Spacer()
                Menu {
                    Section("Destinataire") {
                        ForEach(ActionAudience.allCases, id: \.self) { audience in
                            Button {
                                task.destinataire = audience
                                if audience != .collaborateur { task.collaborator = nil }
                                saveContext()
                            } label: {
                                if task.destinataire == audience {
                                    Label(audience.label, systemImage: "checkmark")
                                } else {
                                    Label(audience.label, systemImage: audience.systemImage)
                                }
                            }
                        }
                    }
                    Divider()
                    Toggle(isOn: Binding(
                        get: { task.isUrgent },
                        set: { task.isUrgent = $0; saveContext() }
                    )) { Label("Urgent", systemImage: "exclamationmark") }
                    Toggle(isOn: Binding(
                        get: { task.isImportant },
                        set: { task.isImportant = $0; saveContext() }
                    )) { Label("Important", systemImage: "star") }
                    Divider()
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
                Text("·").foregroundColor(.secondary)
                rowChargeMenu(task)
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

    // MARK: - Vue Eisenhower

    private var eisenhowerView: some View {
        ScrollView {
            EisenhowerBoard(tasks: meeting.tasks, onToggle: onToggleTaskCompletion)
                .padding(10)
        }
    }

    // MARK: - Priority

    /// Pastille de priorité selon le quadrant urgent×important (rien si aucun).
    @ViewBuilder
    private func priorityDot(_ task: ActionTask) -> some View {
        if task.isUrgent || task.isImportant {
            Circle()
                .fill(EisenhowerBoard.quadrantColor(urgent: task.isUrgent, important: task.isImportant))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Form section

    private var formSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                EditableTextField(placeholder: "Nouvelle action…", text: $newTaskTitle)
                    .frame(height: 24)
                Button(action: onAddTask) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(newTaskTitle.isEmpty ? .secondary : MeetingTheme.accentOrange)
                }
                .buttonStyle(.plain)
                .disabled(newTaskTitle.isEmpty)
                .help("Ajouter l'action")
            }
            HStack(spacing: 8) {
                destinataireMenu
                if newTaskAudience == .collaborateur { assigneeMenu }
                iconToggle("Urgent", systemImage: "exclamationmark", isOn: $newTaskUrgent, color: .blue)
                iconToggle("Important", systemImage: "star.fill", isOn: $newTaskImportant, color: .orange)
                dueDateChip
                chargeChip
                Spacer(minLength: 0)
            }
        }
        .padding(10)
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

    // MARK: - Compact form controls

    private var destinataireMenu: some View {
        Menu {
            ForEach(ActionAudience.allCases, id: \.self) { a in
                Button {
                    newTaskAudience = a
                    if a != .collaborateur { selectedCollaborator = nil }
                } label: {
                    if newTaskAudience == a { Label(a.label, systemImage: "checkmark") }
                    else { Label(a.label, systemImage: a.systemImage) }
                }
            }
        } label: {
            Label(newTaskAudience.label, systemImage: newTaskAudience.systemImage)
                .font(.caption).labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Destinataire")
    }

    private func iconToggle(_ title: String, systemImage: String,
                            isOn: Binding<Bool>, color: Color) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(isOn.wrappedValue ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isOn.wrappedValue ? color : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var dueDateChip: some View {
        Menu {
            Button("Aucune") { newTaskDueDate = nil; showNewTaskDueDate = false }
            Button("Aujourd'hui") { newTaskDueDate = Date(); showNewTaskDueDate = true }
            Button("Demain") {
                newTaskDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                showNewTaskDueDate = true
            }
            Button("Dans 1 semaine") {
                newTaskDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                showNewTaskDueDate = true
            }
        } label: {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundColor(showNewTaskDueDate ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(showNewTaskDueDate ? MeetingTheme.accentOrange : Color.secondary.opacity(0.12)))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Échéance")
    }

    private var chargeChip: some View {
        Menu {
            ForEach([0, 1, 2, 3, 4, 6, 8], id: \.self) { n in
                Button(n == 0 ? "Aucune" : chargeLabel(n)) { newTaskPomodoros = n }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "timer").font(.caption)
                if newTaskPomodoros > 0 { Text("\(newTaskPomodoros)").font(.caption2) }
            }
            .foregroundColor(newTaskPomodoros > 0 ? .white : .secondary)
            .frame(height: 24).padding(.horizontal, 7)
            .background(Capsule().fill(newTaskPomodoros > 0 ? MeetingTheme.accentOrange : Color.secondary.opacity(0.12)))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Charge (pomodoros)")
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

    /// Menu de charge (pomodoros) par action.
    @ViewBuilder
    private func rowChargeMenu(_ task: ActionTask) -> some View {
        Menu {
            ForEach([0, 1, 2, 3, 4, 6, 8], id: \.self) { n in
                Button {
                    task.pomodoros = n
                    saveContext()
                } label: {
                    let text = n == 0 ? "Aucune" : chargeLabel(n)
                    if task.pomodoros == n { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
        } label: {
            Label(
                task.pomodoros > 0 ? "\(task.pomodoros) 🍅" : "Charge",
                systemImage: "timer"
            )
            .font(.caption)
            .foregroundColor(task.pomodoros > 0 ? .primary : .secondary)
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// "N 🍅 · ~Xh Ym" — charge en pomodoros (25 min chacun).
    private func chargeLabel(_ pomodoros: Int) -> String {
        let mins = pomodoros * 25
        let time: String
        if mins >= 60 {
            let h = mins / 60, m = mins % 60
            time = m == 0 ? "\(h)h" : "\(h)h\(m)"
        } else {
            time = "\(mins) min"
        }
        return "\(pomodoros) 🍅 · \(time)"
    }

    // MARK: - Utilities

    /// Formateur de date court (jj/MM/aaaa, locale fr_FR) mis en cache : un
    /// `DateFormatter` est coûteux à instancier, on le réutilise pour toutes
    /// les lignes d'actions.
    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.timeZone = .current
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    private func shortDate(_ d: Date) -> String {
        Self.shortDateFormatter.string(from: d)
    }
}
