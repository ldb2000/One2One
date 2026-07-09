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

    var body: some View {
        if collapsed {
            collapsedRail
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed rail

    /// Rail étroit affiché lorsque la sidebar est repliée (`collapsed == true`) :
    /// un simple bouton chevron permettant de la déplier.
    private var collapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                collapsed = false
            } label: {
                Image(systemName: "chevron.left.2")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Déplier la sidebar")
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(width: 36)
        .background(MeetingTheme.surfaceCream)
    }

    // MARK: - Expanded

    /// Vue dépliée : en-tête + liste des panels visibles, ordonnés selon
    /// `entries`. Volontairement SANS ScrollView englobant (cf. note interne)
    /// pour éviter une récursion de layout AppKit.
    private var expandedPanel: some View {
        // PAS de ScrollView ici : `ActionsPanel.tasksList` a déjà son propre
        // ScrollView interne. Imbriquer 2 ScrollView macOS déclenche
        // `_NSDetectedLayoutRecursion` → freeze.
        // VStack laisse chaque panel gérer son défilement individuellement.
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries.filter(\.visible)) { entry in
                    panelSection(entry)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            configMenu
            Button {
                collapsed = true
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Replier la sidebar")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// Menu de configuration via NSMenu (Menu SwiftUI). Remplace l'ancienne
    /// `.popover` qui causait un crash récursif AppKit Auto Layout sur macOS :
    /// le `_NSConstraintBasedLayoutHostingView` de la popover entrait en
    /// récursion avec le parent sidebar à chaque toggle. NSMenu n'utilise
    /// pas le pipeline Auto Layout SwiftUI → safe.
    @ViewBuilder
    private var configMenu: some View {
        Menu {
            Section("Panneaux visibles") {
                ForEach(entries) { entry in
                    Button {
                        DispatchQueue.main.async {
                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[idx].visible.toggle()
                                persist()
                            }
                        }
                    } label: {
                        if entry.visible {
                            Label(entry.id.defaultTitle, systemImage: "checkmark")
                        } else {
                            Text(entry.id.defaultTitle)
                        }
                    }
                }
            }
            Divider()
            Button("Réinitialiser") {
                DispatchQueue.main.async {
                    entries = PanelLayoutEntry.defaultLayout
                    persist()
                }
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Configurer les panneaux")
    }

    /// Rend une section de panel : son en-tête (cible de drag-and-drop pour le
    /// réordonnancement) et, si déplié, son contenu. Le `entry` fournit l'ID du
    /// panel et son état de visibilité/position dans le layout persisté.
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
        default:
            EmptyView()
        }
    }

    // MARK: - Layout persistence

    /// Initialise `entries` depuis le layout persisté (`AppSettings`) et marque
    /// chaque panel comme déplié par défaut. Idempotent : ne fait rien si
    /// `entries` est déjà hydraté (appelé à chaque `onAppear`).
    private func hydrateLayoutAndExpansion() {
        if entries.isEmpty {
            entries = PanelLayoutEntry.decode(settings.rightSidebarLayoutJSON)
            for entry in entries where expanded[entry.id] == nil {
                expanded[entry.id] = true
            }
        }
    }

    /// Sérialise le layout courant dans `AppSettings.rightSidebarLayoutJSON` et
    /// déclenche la sauvegarde du contexte.
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
