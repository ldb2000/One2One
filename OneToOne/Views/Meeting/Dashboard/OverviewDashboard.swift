import SwiftUI
import UniformTypeIdentifiers

/// Onglet « Vue d'ensemble » : grille de cartes réordonnables/masquables.
/// Réutilise le layout persisté (`PanelLayoutEntry` / `rightSidebarLayoutJSON`).
struct OverviewDashboard: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]
    @Binding var isEditing: Bool
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?
    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
    let onManageParticipants: () -> Void
    let onExpandTranscript: () -> Void
    let saveContext: () -> Void

    @State private var entries: [PanelLayoutEntry] = []

    /// Cartes visibles, dans l'ordre du layout, filtrées selon le kind.
    private var visibleIDs: [RightSidebarPanelID] {
        entries.filter { entry in
            guard entry.visible else { return false }
            if entry.id == .managerAgenda { return meeting.kind == .manager }
            return true
        }.map(\.id)
    }

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 900
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isEditing { editBar }
                    grid(narrow: narrow)
                }
                .padding(4)
            }
        }
        .onAppear {
            if entries.isEmpty { entries = PanelLayoutEntry.decode(settings.rightSidebarLayoutJSON) }
        }
    }

    @ViewBuilder
    private func grid(narrow: Bool) -> some View {
        let ids = visibleIDs
        let heroIDs: [RightSidebarPanelID] = (!narrow && ids.count >= 2) ? Array(ids.prefix(2)) : []
        let rest = Array(ids.dropFirst(heroIDs.count))
        VStack(spacing: 16) {
            if !heroIDs.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    card(heroIDs[0]).frame(maxWidth: .infinity)
                    card(heroIDs[1]).frame(maxWidth: .infinity).layoutPriority(1)
                }
            }
            let columns = narrow
                ? [GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rest, id: \.self) { id in card(id) }
            }
        }
    }

    /// Une carte draggable/droppable en mode édition.
    @ViewBuilder
    private func card(_ id: RightSidebarPanelID) -> some View {
        cardContent(id)
            .modifier(DragReorderModifier(id: id, entries: $entries, enabled: isEditing, persist: persist))
    }

    @ViewBuilder
    private func cardContent(_ id: RightSidebarPanelID) -> some View {
        switch id {
        case .presence:
            PresenceCard(meeting: meeting, settings: settings, isEditing: isEditing, onManage: onManageParticipants)
        case .transcription:
            TranscriptionCard(isEditing: isEditing, onExpand: onExpandTranscript)
        case .actions:
            DashboardCard(title: "Actions", systemImage: "checklist", isEditing: isEditing) { EmptyView() } content: {
                ActionsPanel(meeting: meeting, settings: settings, allCollaborators: allCollaborators,
                             newTaskTitle: $newTaskTitle, selectedCollaborator: $selectedCollaborator,
                             showNewTaskDueDate: $showNewTaskDueDate, newTaskDueDate: $newTaskDueDate,
                             onAddTask: onAddTask, onDeleteTask: onDeleteTask,
                             onToggleTaskCompletion: onToggleTaskCompletion, saveContext: saveContext)
            }
        case .projects:
            DashboardCard(title: "Projets affectés", systemImage: "folder.fill", isEditing: isEditing) { EmptyView() } content: {
                ProjectsPanel(meeting: meeting)
            }
        case .capture:
            DashboardCard(title: "Capture", systemImage: "camera", isEditing: isEditing) { EmptyView() } content: {
                CapturePanel(currentSlides: currentSlides, onShowSlides: onShowSlides, onShowCaptureSetup: onShowCaptureSetup)
            }
        case .managerAgenda:
            DashboardCard(title: "Agenda manager", systemImage: "list.bullet.rectangle", isEditing: isEditing) { EmptyView() } content: {
                ManagerAgendaSidebar(meeting: meeting, settings: settings)
            }
        }
    }

    private var editBar: some View {
        HStack {
            Text("Glisser les cartes pour réordonner").font(.caption).foregroundColor(.secondary)
            Spacer()
            Menu {
                Section("Cartes visibles") {
                    ForEach(entries.filter { $0.id != .managerAgenda || meeting.kind == .manager }) { entry in
                        Button {
                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[idx].visible.toggle(); persist()
                            }
                        } label: {
                            if entry.visible { Label(entry.id.defaultTitle, systemImage: "checkmark") }
                            else { Text(entry.id.defaultTitle) }
                        }
                    }
                }
                Divider()
                Button("Réinitialiser") { entries = PanelLayoutEntry.defaultLayout; persist() }
            } label: { Label("Cartes", systemImage: "gearshape") }
        }
    }

    private func persist() {
        settings.rightSidebarLayoutJSON = PanelLayoutEntry.encode(entries)
        saveContext()
    }
}

/// Drag & drop de réordonnancement d'une carte (payload = `RightSidebarPanelID.rawValue`).
private struct DragReorderModifier: ViewModifier {
    let id: RightSidebarPanelID
    @Binding var entries: [PanelLayoutEntry]
    let enabled: Bool
    let persist: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { NSItemProvider(object: id.rawValue as NSString) }
                .onDrop(of: [UTType.text], delegate: CardDropDelegate(targetID: id, entries: $entries, persist: persist))
        } else {
            content
        }
    }
}

private struct CardDropDelegate: DropDelegate {
    let targetID: RightSidebarPanelID
    @Binding var entries: [PanelLayoutEntry]
    let persist: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            guard let raw = obj as? String,
                  let dragID = RightSidebarPanelID(rawValue: raw), dragID != targetID else { return }
            DispatchQueue.main.async {
                guard let from = entries.firstIndex(where: { $0.id == dragID }),
                      let to = entries.firstIndex(where: { $0.id == targetID }) else { return }
                let moved = entries.remove(at: from)
                entries.insert(moved, at: to)
                persist()
            }
        }
        return true
    }
}
