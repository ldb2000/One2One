import AppKit
import SwiftUI
import SwiftData

/// Fenêtre flottante pour choisir un collaborateur et lancer un 1:1.
/// Présentée par `GlobalHotkeyService` au déclenchement du raccourci
/// d'overlay (`⌃⌥⌘1` par défaut).
@MainActor
final class OneToOneQuickPickerWindow: NSPanel {

    static let shared = OneToOneQuickPickerWindow()

    private convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        animationBehavior = .utilityWindow
    }

    /// Présente la fenêtre centrée à l'écran principal et donne le focus
    /// au champ de recherche.
    func present() {
        let host = NSHostingController(rootView: OneToOneQuickPickerView(onClose: { [weak self] in
            self?.orderOut(nil)
        }))
        contentViewController = host
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

struct OneToOneQuickPickerView: View {
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived },
           sort: [SortDescriptor(\.pinLevel, order: .reverse), SortDescriptor(\.name)])
    private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: QuickLaunchRouter

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    let onClose: () -> Void

    private var filtered: [Collaborator] {
        guard !query.isEmpty else { return Array(collaborators.prefix(20)) }
        let q = query.lowercased()
        return collaborators
            .filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Rechercher un collaborateur...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { commit() }
                    .onChange(of: query) { _, _ in highlightedIndex = 0 }
            }
            .padding(12)
            Divider()

            List(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, collab in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collab.name).font(.body)
                        if !collab.role.isEmpty {
                            Text(collab.role).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if index == highlightedIndex {
                        Image(systemName: "return").foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .background(index == highlightedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    highlightedIndex = index
                    commit()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 480, height: 360)
        .onAppear { searchFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.downArrow) {
            highlightedIndex = min(highlightedIndex + 1, max(filtered.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlightedIndex = max(highlightedIndex - 1, 0)
            return .handled
        }
    }

    private func commit() {
        guard !filtered.isEmpty else { return }
        let target = filtered[min(highlightedIndex, filtered.count - 1)]
        router.startOneToOne(collaborator: target, autoStartRecording: true, in: context)
        onClose()
    }
}
