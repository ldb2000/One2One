import AppKit
import SwiftUI

/// Panneau flottant du menu `@` : liste plate de `MentionRow` (candidats
/// puis, éventuellement, l'entrée « Créer … »), affichée sous le curseur de
/// frappe — même architecture que `SlashPanel` (voir sa doc de tête pour le
/// détail : `NSPanel` non-activant, jamais key/main, hébergeant une vue
/// SwiftUI). Second panneau plutôt que généralisation de `SlashPanel` : la
/// spec laissait les deux options ouvertes (« telle quelle, ou généralisée »)
/// — le contenu affiché diffère assez (pas de groupes, une colonne « rôle »,
/// une entrée de création stylée différemment) pour qu'une base commune
/// ajoute plus d'indirection qu'elle n'économise de code, pour deux panneaux
/// de cette taille.
///
/// Ce fichier ne construit **que le panneau** — ni la détection du `@`, ni la
/// navigation clavier, ni l'application d'une entrée (`MentionController`).
/// `SlashPanelPositioning.origin(...)` (positionnement sous/au-dessus du
/// curseur, clampé à l'écran) est réutilisée telle quelle, pas dupliquée :
/// fonction pure indépendante de `SlashCommand`, déjà couverte par
/// `Tests/SlashPanelPositioningTests.swift`.
///
/// Comme `SlashPanel`, ce panneau n'est **pas testable** dans ce projet (pas
/// de dépendance permettant de piloter la vue SwiftUI qu'il héberge) — voir
/// le rapport de tâche.
@MainActor
final class MentionPanel: NSPanel {

    /// Invoqué au clic souris sur une entrée. La navigation clavier ne passe
    /// **pas** par ce panneau (il ne devient jamais key window) — voir
    /// `canBecomeKey`.
    var onSelect: ((MentionRow) -> Void)? {
        didSet { state.onRowSelected = onSelect }
    }

    private let state = MentionPanelState()
    private let hosting: MentionPanelHostingView

    init() {
        hosting = MentionPanelHostingView(rootView: MentionPanelContent(state: state))
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: MentionPanelMetrics.width, height: MentionPanelMetrics.rowHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        contentView = hosting
        applySize()
    }

    /// Toujours faux — voir `SlashPanel.canBecomeKey` pour la justification
    /// (identique ici) : le focus clavier doit rester sur l'`NSTextView`.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Pousse la liste filtrée (candidats + entrée « Créer … » éventuelle) et
    /// l'index de sélection courant, dans l'ordre de `rows`.
    func update(rows: [MentionRow], selectedIndex: Int) {
        state.rows = rows
        state.selectedIndex = selectedIndex
        applySize()
    }

    /// Même contrat que `SlashPanel.show(near:on:)`.
    func show(near cursorRect: NSRect, on screen: NSScreen?) {
        let visibleFrame = screen?.visibleFrame ?? cursorRect
        let origin = SlashPanelPositioning.origin(
            cursorRect: cursorRect,
            panelSize: frame.size,
            visibleFrame: visibleFrame
        )
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    /// Masque sans fermer — `MentionController` réutilise la même instance.
    func dismiss() {
        orderOut(nil)
    }

    private func applySize() {
        let size = MentionPanelMetrics.idealSize(for: state.rows)
        setContentSize(size)
    }
}

/// Même raison d'être que `SlashPanel`'s `SlashPanelHostingView` : un clic
/// doit déclencher l'action dès le premier clic sur ce panneau non-activant.
private final class MentionPanelHostingView: NSHostingView<MentionPanelContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Contenu SwiftUI

@MainActor
private final class MentionPanelState: ObservableObject {
    @Published var rows: [MentionRow] = []
    @Published var selectedIndex: Int = 0
    var onRowSelected: ((MentionRow) -> Void)?
}

private struct MentionPanelContent: View {
    @ObservedObject var state: MentionPanelState

    var body: some View {
        Group {
            if state.rows.isEmpty {
                Text("Aucun collaborateur")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: MentionPanelMetrics.emptyHeight, alignment: .leading)
                    .padding(.horizontal, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.rows.enumerated()), id: \.offset) { index, row in
                        MentionPanelRow(row: row, isSelected: index == state.selectedIndex)
                            .onTapGesture { state.onRowSelected?(row) }
                    }
                }
                .padding(.vertical, MentionPanelMetrics.verticalInset)
            }
        }
        .frame(width: MentionPanelMetrics.width)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// Une entrée : `.candidate` affiche le nom et, s'il n'est pas vide, le rôle
/// aligné à droite ; `.create` affiche le libellé « Créer "…" » avec une
/// icône distincte. Surlignée quand `isSelected`.
private struct MentionPanelRow: View {
    let row: MentionRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch row {
            case .candidate(let candidate):
                Image(systemName: "person.crop.circle")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(candidate.name)
                    .font(.body)
                    .lineLimit(1)
                if !candidate.role.isEmpty {
                    Spacer(minLength: 12)
                    Text(candidate.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .create(let typedName):
                Image(systemName: "person.badge.plus")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text("Créer « \(typedName) »")
                    .font(.body)
                    .lineLimit(1)
            }
        }
        .frame(height: MentionPanelMetrics.rowHeight)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Métriques

enum MentionPanelMetrics {
    static let width: CGFloat = 280
    static let rowHeight: CGFloat = 26
    static let verticalInset: CGFloat = 6
    static let emptyHeight: CGFloat = 40

    fileprivate static func idealSize(for rows: [MentionRow]) -> NSSize {
        guard !rows.isEmpty else {
            return NSSize(width: width, height: emptyHeight)
        }
        let height = verticalInset * 2 + CGFloat(rows.count) * rowHeight
        return NSSize(width: width, height: height)
    }
}
