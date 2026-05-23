import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sidebar droite configurable des réunions. Remplace MeetingActionsSidebar.
/// Héberge 3 panels (Actions, Projets affectés, Capture) que l'utilisateur peut
/// réordonner par drag des headers et masquer via le menu engrenage.
/// Layout persisté dans `AppSettings.rightSidebarLayoutJSON`.
struct ConfigurableRightSidebar: View {

    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]

    @Binding var collapsed: Bool

    // Pass-through Actions panel:
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

    @State private var entries: [PanelLayoutEntry] = []
    @State private var expanded: [RightSidebarPanelID: Bool] = [:]
    @State private var showingConfigPopover: Bool = false

    var body: some View {
        if collapsed {
            collapsedRail
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed rail

    private var collapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Déplier la sidebar")
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: 36)
        .background(MeetingTheme.surfaceCream)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries.filter(\.visible)) { entry in
                        panelSection(entry)
                    }
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 460)
        .background(MeetingTheme.surfaceCream)
        .onAppear { hydrateLayoutAndExpansion() }
    }

    private var header: some View {
        HStack {
            Text("PANNEAUX")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingConfigPopover = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Configurer les panneaux")
            .popover(isPresented: $showingConfigPopover, arrowEdge: .top) {
                configPopoverBody
                    .padding(12)
                    .frame(minWidth: 220)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = true }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Replier la sidebar")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var configPopoverBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Panneaux visibles")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(entries.indices, id: \.self) { idx in
                Toggle(entries[idx].id.defaultTitle,
                       isOn: Binding(
                        get: { entries[idx].visible },
                        set: { entries[idx].visible = $0; persist() }
                       ))
            }
            Divider()
            Button("Réinitialiser") {
                entries = PanelLayoutEntry.defaultLayout
                persist()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    @ViewBuilder
    private func panelSection(_ entry: PanelLayoutEntry) -> some View {
        let isExpanded = Binding<Bool>(
            get: { expanded[entry.id, default: true] },
            set: { expanded[entry.id] = $0 }
        )
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(panelID: entry.id, expanded: isExpanded)
                .onDrop(of: [UTType.text], delegate: PanelDropDelegate(
                    target: entry,
                    entries: $entries,
                    persist: persist
                ))
            if isExpanded.wrappedValue {
                panelContent(entry.id)
                    .transition(.opacity)
            }
            Divider()
        }
    }

    @ViewBuilder
    private func panelContent(_ id: RightSidebarPanelID) -> some View {
        switch id {
        case .actions:
            ActionsPanel(
                meeting: meeting,
                settings: settings,
                allCollaborators: allCollaborators,
                newTaskTitle: $newTaskTitle,
                selectedCollaborator: $selectedCollaborator,
                showNewTaskDueDate: $showNewTaskDueDate,
                newTaskDueDate: $newTaskDueDate,
                onAddTask: onAddTask,
                onDeleteTask: onDeleteTask,
                onToggleTaskCompletion: onToggleTaskCompletion,
                saveContext: saveContext
            )
        case .projects:
            ProjectsPanel(meeting: meeting)
        case .capture:
            CapturePanel(
                currentSlides: currentSlides,
                onShowSlides: onShowSlides,
                onShowCaptureSetup: onShowCaptureSetup
            )
        }
    }

    // MARK: - Layout persistence

    private func hydrateLayoutAndExpansion() {
        if entries.isEmpty {
            entries = PanelLayoutEntry.decode(settings.rightSidebarLayoutJSON)
            for entry in entries where expanded[entry.id] == nil {
                expanded[entry.id] = true
            }
        }
    }

    private func persist() {
        settings.rightSidebarLayoutJSON = PanelLayoutEntry.encode(entries)
        saveContext()
    }
}

/// Drop delegate qui réordonne les entries quand un panel est draggé sur la
/// row d'un autre panel.
private struct PanelDropDelegate: DropDelegate {
    let target: PanelLayoutEntry
    @Binding var entries: [PanelLayoutEntry]
    let persist: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else {
            return false
        }
        item.loadObject(ofClass: NSString.self) { (obj, _) in
            guard let raw = obj as? String,
                  let dragID = RightSidebarPanelID(rawValue: raw),
                  dragID != target.id else { return }
            DispatchQueue.main.async {
                guard let fromIdx = entries.firstIndex(where: { $0.id == dragID }),
                      let toIdx = entries.firstIndex(where: { $0.id == target.id }) else { return }
                let moved = entries.remove(at: fromIdx)
                entries.insert(moved, at: toIdx)
                persist()
            }
        }
        return true
    }
}
