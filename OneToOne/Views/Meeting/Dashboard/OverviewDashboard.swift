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

    /// Hauteur max des cartes embarquant un `ScrollView` interne non borné (Actions, Projets,
    /// Capture, Agenda manager) : le `ScrollView` extérieur de `body` + un `ScrollView` interne
    /// non borné déclenchent une récursion de layout macOS (`_NSDetectedLayoutRecursion` → freeze).
    private let cardScrollMaxHeight: CGFloat = 380

    /// Hauteur d'une rangée de la grille ; une carte 1×N fait N rangées.
    private let gridRowHeight: CGFloat = 240

    /// Cartes visibles, dans l'ordre du layout, filtrées selon le kind.
    private var visibleEntries: [PanelLayoutEntry] {
        entries.filter { entry in
            guard entry.visible else { return false }
            if entry.id == .managerAgenda { return meeting.kind == .manager }
            return true
        }
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
        let columns = narrow ? 1 : 3
        DashboardGridLayout(columns: columns, spacing: 16, rowHeight: gridRowHeight) {
            ForEach(visibleEntries) { entry in
                card(entry.id)
                    .layoutValue(key: DashboardSpanKey.self,
                                 value: CardSpan(cols: min(entry.cols, columns), rows: entry.rows))
            }
        }
    }

    /// Une carte draggable/droppable en mode édition, qui remplit sa cellule de grille.
    @ViewBuilder
    private func card(_ id: RightSidebarPanelID) -> some View {
        cardContent(id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(DragReorderModifier(id: id, entries: $entries, enabled: isEditing, persist: persist))
    }

    @ViewBuilder
    private func cardContent(_ id: RightSidebarPanelID) -> some View {
        switch id {
        case .presence:
            PresenceCard(meeting: meeting, settings: settings, isEditing: isEditing, onManage: onManageParticipants)
        case .transcription:
            TranscriptionCard(meeting: meeting, isEditing: isEditing, onExpand: onExpandTranscript)
        case .summary:
            SummaryCard(meeting: meeting, settings: settings, isEditing: isEditing, saveContext: saveContext)
        case .actions:
            DashboardCard(title: "Actions", systemImage: "checklist", isEditing: isEditing) { EmptyView() } content: {
                ActionsPanel(meeting: meeting, settings: settings, allCollaborators: allCollaborators,
                             newTaskTitle: $newTaskTitle, selectedCollaborator: $selectedCollaborator,
                             showNewTaskDueDate: $showNewTaskDueDate, newTaskDueDate: $newTaskDueDate,
                             onAddTask: onAddTask, onDeleteTask: onDeleteTask,
                             onToggleTaskCompletion: onToggleTaskCompletion, saveContext: saveContext)
                    // Borne la hauteur pour éviter la récursion de layout (ScrollView imbriqués) sur macOS.
                    .frame(maxHeight: cardScrollMaxHeight)
            }
        case .projects:
            DashboardCard(title: "Projets affectés", systemImage: "folder.fill", isEditing: isEditing) { EmptyView() } content: {
                ProjectsPanel(meeting: meeting)
                    // Borne la hauteur par sécurité (contenu potentiellement scrollable/extensible).
                    .frame(maxHeight: cardScrollMaxHeight)
            }
        case .capture:
            DashboardCard(title: "Capture", systemImage: "camera", isEditing: isEditing) { EmptyView() } content: {
                CapturePanel(currentSlides: currentSlides, onShowSlides: onShowSlides, onShowCaptureSetup: onShowCaptureSetup)
                    // Borne la hauteur par sécurité (contenu potentiellement scrollable/extensible).
                    .frame(maxHeight: cardScrollMaxHeight)
            }
        case .managerAgenda:
            DashboardCard(title: "Agenda manager", systemImage: "list.bullet.rectangle", isEditing: isEditing) { EmptyView() } content: {
                ManagerAgendaSidebar(meeting: meeting, settings: settings)
                    // Borne la hauteur pour éviter la récursion de layout (ScrollView imbriqués) sur macOS.
                    .frame(maxHeight: cardScrollMaxHeight)
            }
        }
    }

    private var editBar: some View {
        HStack {
            Text("Glisser les cartes pour réordonner").font(.caption).foregroundColor(.secondary)
            Spacer()
            Menu {
                Section("Cartes") {
                    ForEach(entries.filter { $0.id != .managerAgenda || meeting.kind == .manager }) { entry in
                        Menu {
                            Button {
                                toggleVisible(entry.id)
                            } label: {
                                Label(entry.visible ? "Masquer" : "Afficher",
                                      systemImage: entry.visible ? "eye.slash" : "eye")
                            }
                            Divider()
                            Section("Taille") {
                                sizeButton(entry.id, cols: 1, rows: 1, "1×1")
                                sizeButton(entry.id, cols: 2, rows: 1, "2×1 (large)")
                                sizeButton(entry.id, cols: 1, rows: 2, "1×2 (haut)")
                                sizeButton(entry.id, cols: 1, rows: 3, "1×3 (très haut)")
                            }
                        } label: {
                            Label(entry.id.defaultTitle,
                                  systemImage: entry.visible ? "checkmark.circle.fill" : "circle")
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

    private func toggleVisible(_ id: RightSidebarPanelID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].visible.toggle()
        persist()
    }

    private func setSpan(_ id: RightSidebarPanelID, cols: Int, rows: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].cols = cols
        entries[idx].rows = rows
        persist()
    }

    @ViewBuilder
    private func sizeButton(_ id: RightSidebarPanelID, cols: Int, rows: Int, _ label: String) -> some View {
        let entry = entries.first { $0.id == id }
        let isCurrent = entry?.cols == cols && entry?.rows == rows
        Button { setSpan(id, cols: cols, rows: rows) } label: {
            if isCurrent { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
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
