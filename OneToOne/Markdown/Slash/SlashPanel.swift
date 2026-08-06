import AppKit
import SwiftUI

/// Panneau flottant du menu `/` : liste filtrée/groupée des `SlashCommand`
/// (catalogue produit à la tâche 3), affichée sous le curseur de frappe.
///
/// Ce fichier ne construit **que le panneau** — ni la détection du `/`, ni la
/// navigation clavier, ni l'application d'une commande (tâche 5,
/// `SlashController`). L'API exposée au contrôleur se limite à :
/// - `update(groups:selectedIndex:)` pour pousser le contenu filtré et la
///   sélection courante ;
/// - `onSelect` pour être prévenu d'un clic souris sur une entrée ;
/// - `show(near:on:)` / `dismiss()` pour piloter la visibilité et la
///   position.
///
/// Précédent suivi dans ce projet : `OneToOneQuickPickerWindow.swift`
/// (`NSPanel` non-activant et flottant), à ceci près que ce panneau-ci ne
/// doit **jamais** devenir key/main — voir `canBecomeKey` ci-dessous.
@MainActor
final class SlashPanel: NSPanel {

    /// Invoqué quand l'utilisateur clique une entrée à la souris. La
    /// navigation clavier ne passe **pas** par ce panneau : il ne devient
    /// jamais key window, donc ne reçoit jamais d'événement clavier —
    /// `SlashController` (tâche 5) intercepte les touches directement sur le
    /// `NSTextView` qui garde le focus pendant que le menu est ouvert.
    var onSelect: ((SlashCommand) -> Void)? {
        didSet { state.onCommandSelected = onSelect }
    }

    private let state = SlashPanelState()
    private let hosting: SlashPanelHostingView

    init() {
        hosting = SlashPanelHostingView(rootView: SlashPanelContent(state: state))
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: SlashPanelMetrics.width, height: SlashPanelMetrics.rowHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // `.nonactivatingPanel` évite déjà que l'app soit activée à
        // l'affichage ; `canBecomeKey`/`canBecomeMain` (ci-dessous) évitent
        // en plus que le panneau lui-même prenne le focus clavier une fois
        // affiché — c'est la propriété la plus importante de ce panneau.
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

    /// Toujours faux : le panneau ne doit jamais devenir la fenêtre clé.
    /// Sans ça, un `orderFront`/clic pourrait lui voler le focus clavier au
    /// `NSTextView` qui a ouvert le menu, et l'utilisateur perdrait la
    /// possibilité de continuer à taper pour filtrer.
    override var canBecomeKey: Bool { false }

    /// Toujours faux, pour la même raison — un panneau non-activant peut
    /// tout de même devenir main window sans ce override.
    override var canBecomeMain: Bool { false }

    /// Pousse la liste filtrée/groupée et l'index de sélection courant.
    /// `selectedIndex` est un index dans la liste **aplatie**
    /// `groups.flatMap { $0.commands }`, dans cet ordre — c'est cette
    /// convention que `SlashController` (tâche 5) doit respecter pour que la
    /// bonne entrée soit surlignée.
    func update(groups: [(group: SlashCommand.Group, commands: [SlashCommand])], selectedIndex: Int) {
        state.groups = groups.map { DisplayGroup(group: $0.group, commands: $0.commands) }
        state.selectedIndex = selectedIndex
        applySize()
    }

    /// Affiche le panneau juste sous `cursorRect` (coordonnées **écran**,
    /// telles que renvoyées par
    /// `NSTextView.firstRect(forCharacterRange:actualRange:)`), clampé sur
    /// `screen.visibleFrame`. N'active jamais l'app et ne change jamais le
    /// statut key/main de quoi que ce soit (`orderFrontRegardless`, jamais
    /// `makeKeyAndOrderFront`) — le focus reste au `NSTextView` appelant.
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

    /// Masque le panneau sans le fermer (pas de `close()` : `SlashController`
    /// réutilise la même instance d'une ouverture à l'autre).
    func dismiss() {
        orderOut(nil)
    }

    /// Recalcule la taille du panneau à partir du nombre de groupes/entrées
    /// affichés. Approximation déterministe par constantes (`SlashPanelMetrics`)
    /// plutôt que `NSHostingView.fittingSize` : ce dernier dépend du timing
    /// de mise à jour de SwiftUI vis-à-vis de `@Published`, qui n'est pas
    /// garanti synchrone avec cette mutation — un calcul par constantes reste
    /// prévisible même si moins pixel-parfait. Non vérifié visuellement, voir
    /// le rapport de tâche. Plafonnée à `SlashPanelMetrics.maxHeight` (voir sa
    /// doc) : au-delà, `SlashPanelContent` fait défiler son contenu dans un
    /// `ScrollView` plutôt que de continuer à agrandir la fenêtre.
    private func applySize() {
        let size = SlashPanelMetrics.idealSize(for: state.groups)
        setContentSize(size)
    }
}

// MARK: - Positionnement (fonction pure, testable)

/// Calcule où placer le panneau étant donné le rectangle écran du curseur,
/// la taille du panneau et le cadre visible de l'écran. Isolé de `SlashPanel`
/// pour rester testable sans `NSPanel` ni fenêtre réelle — c'est la seule
/// partie de ce fichier couverte par des tests automatisés (voir
/// `Tests/SlashPanelPositioningTests.swift`).
enum SlashPanelPositioning {

    /// Coin haut-gauche du panneau, en coordonnées écran AppKit (origine en
    /// bas-gauche, y croissant vers le haut — donc l'origine renvoyée est le
    /// coin **bas**-gauche de la fenêtre, dont le bord *haut* correspond au
    /// "haut-gauche" demandé par la tâche).
    ///
    /// Règles, dans cet ordre :
    /// 1. Par défaut, juste sous le curseur : le bord haut du panneau touche
    ///    le bas du rectangle du curseur (`cursorRect.minY`).
    /// 2. Si cette position ferait déborder le panneau sous le bas de
    ///    l'écran, bascule au-dessus du curseur : le bord bas du panneau
    ///    touche le haut du rectangle du curseur (`cursorRect.maxY`).
    /// 3. Filet de sécurité : quoi qu'il arrive, ne jamais renvoyer un y en
    ///    dessous du bas de l'écran visible (cas dégénéré où même la
    ///    bascule ne suffirait pas — panneau plus haut que l'écran, ou
    ///    rectangle curseur lui-même hors du cadre visible).
    /// 4. En x, le panneau s'aligne sur le bord gauche du rectangle du
    ///    curseur, clampé pour ne déborder ni à droite ni à gauche de
    ///    l'écran.
    static func origin(cursorRect: NSRect, panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        var y = cursorRect.minY - panelSize.height

        if y < visibleFrame.minY {
            y = cursorRect.maxY
        }

        y = max(y, visibleFrame.minY)

        var x = cursorRect.minX
        x = min(x, visibleFrame.maxX - panelSize.width)
        x = max(x, visibleFrame.minX)

        return NSPoint(x: x, y: y)
    }
}

/// `NSHostingView` qui répond `true` à `acceptsFirstMouse` : un clic sur une
/// entrée doit déclencher l'action dès le premier clic, même si le panneau
/// n'est pas "actif" au sens AppKit (il ne devient jamais key — voir
/// `SlashPanel.canBecomeKey`). Sans ce override, AppKit pourrait consommer
/// le premier clic pour amener la fenêtre au premier plan sans le
/// transmettre à la vue cliquée. `acceptsFirstMouse` vit sur `NSView`, pas
/// `NSWindow` — d'où ce sous-classement plutôt qu'un override sur `SlashPanel`.
private final class SlashPanelHostingView: NSHostingView<SlashPanelContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Contenu SwiftUI

/// État observable du panneau, poussé par `SlashPanel.update`. Interne : le
/// contrôleur ne parle qu'à `SlashPanel`, jamais directement à cet objet.
@MainActor
private final class SlashPanelState: ObservableObject {
    @Published var groups: [DisplayGroup] = []
    @Published var selectedIndex: Int = 0
    var onCommandSelected: ((SlashCommand) -> Void)?
}

/// Groupe affichable : enveloppe locale de `(group:, commands:)` pour donner
/// un identifiant stable à `ForEach` — `SlashCommand.Group` n'est
/// qu'`Equatable`, pas `Hashable` (catalogue de la tâche 3, non modifié ici).
private struct DisplayGroup: Identifiable, Equatable {
    let group: SlashCommand.Group
    let commands: [SlashCommand]
    var id: String { group.rawValue }
}

private struct SlashPanelContent: View {
    @ObservedObject var state: SlashPanelState

    /// Index de départ de chaque groupe dans la liste aplatie
    /// (`groups.flatMap { $0.commands }`), pour convertir l'index aplati de
    /// `state.selectedIndex` en surlignage par ligne.
    private var flatOffsets: [String: Int] {
        var offset = 0
        var result: [String: Int] = [:]
        for group in state.groups {
            result[group.id] = offset
            offset += group.commands.count
        }
        return result
    }

    /// Identifiant (`SlashCommand.Key`, unique dans tout `SlashCatalog.all` —
    /// pas seulement au sein d'un groupe) de l'entrée actuellement
    /// sélectionnée dans la liste aplatie. Sert d'ancre à
    /// `ScrollViewProxy.scrollTo` pour amener la sélection en vue quand la
    /// navigation clavier (`SlashController.moveSelection`) la fait sortir de
    /// la zone visible du panneau plafonné (`SlashPanelMetrics.maxHeight`).
    private var selectedCommandID: SlashCommand.Key? {
        var index = 0
        for group in state.groups {
            for command in group.commands {
                if index == state.selectedIndex { return command.id }
                index += 1
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if state.groups.isEmpty {
                Text("Aucun résultat")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: SlashPanelMetrics.emptyHeight, alignment: .leading)
                    .padding(.horizontal, 10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(state.groups) { group in
                                SlashPanelGroupHeader(title: group.group.title)
                                ForEach(Array(group.commands.enumerated()), id: \.element.id) { offsetInGroup, command in
                                    let globalIndex = (flatOffsets[group.id] ?? 0) + offsetInGroup
                                    SlashPanelRow(command: command, isSelected: globalIndex == state.selectedIndex)
                                        .id(command.id)
                                        .onTapGesture { state.onCommandSelected?(command) }
                                }
                            }
                        }
                        .padding(.vertical, SlashPanelMetrics.verticalInset)
                    }
                    // Fait défiler l'entrée sélectionnée en vue à chaque
                    // changement de sélection (flèches haut/bas, via
                    // `SlashController.moveSelection`) ou de contenu filtré
                    // (nouvelle frappe dans la requête, qui réinitialise aussi
                    // `selectedIndex` à 0 côté `SlashController.updateFilter`
                    // — d'où le second `onChange` : ramène le défilement en
                    // haut même quand l'index numérique lui-même ne change
                    // pas). `anchor` par défaut (`nil`) : défilement minimal
                    // suffisant pour rendre la ligne entièrement visible, que
                    // la sélection sorte par le bas ou par le haut.
                    .onChange(of: state.selectedIndex) { _, _ in
                        guard let id = selectedCommandID else { return }
                        proxy.scrollTo(id)
                    }
                    .onChange(of: state.groups) { _, _ in
                        guard let id = selectedCommandID else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .frame(width: SlashPanelMetrics.width)
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

/// En-tête d'un groupe (« Blocs de base », « Média »).
private struct SlashPanelGroupHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(height: SlashPanelMetrics.headerHeight, alignment: .leading)
            .padding(.horizontal, 10)
    }
}

/// Une entrée : icône, libellé, raccourci aligné à droite. Surlignée quand
/// `isSelected` (entrée courante de la navigation clavier, pilotée par
/// `SlashController`).
private struct SlashPanelRow: View {
    let command: SlashCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: command.key.slashPanelIcon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(command.label)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: SlashPanelMetrics.rowHeight)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// Icône SF Symbols par entrée — jugement visuel du panneau, aucun code ne
/// dépend de cette valeur (le catalogue, tâche 3, n'en porte pas).
private extension SlashCommand.Key {
    var slashPanelIcon: String {
        switch self {
        case .text: return "text.alignleft"
        case .heading1: return "1.square"
        case .heading2: return "2.square"
        case .heading3: return "3.square"
        case .bulletList: return "list.bullet"
        case .orderedList: return "list.number"
        case .taskList: return "checklist"
        case .blockquote: return "text.quote"
        case .callout: return "lightbulb"
        case .thematicBreak: return "minus"
        case .image: return "photo"
        case .date: return "calendar"
        case .table: return "tablecells"
        }
    }
}

// MARK: - Métriques

/// Constantes de mise en page, partagées entre le calcul de taille
/// (`SlashPanel.applySize`) et les vues SwiftUI, pour que la taille de
/// fenêtre demandée corresponde à ce que le contenu dessine réellement.
enum SlashPanelMetrics {
    static let width: CGFloat = 260
    static let rowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 22
    static let verticalInset: CGFloat = 6
    static let emptyHeight: CGFloat = 40

    /// Nombre de lignes pleines visibles avant que le panneau ne plafonne et
    /// devienne défilant (voir `SlashPanelSizing.height`, et le `ScrollView`
    /// de `SlashPanelContent`). Mesuré, pas deviné : le catalogue actuel
    /// (`SlashCatalog.all`, 12 entrées en 3 groupes) fait déjà 390pt sans
    /// plafond (12 lignes + 3 en-têtes + marge verticale — `verticalInset * 2
    /// + 3 * headerHeight + 12 * rowHeight`) — largement au-delà des 8 lignes
    /// retenues ici, donc ce plafond s'exerce déjà sur le catalogue
    /// d'aujourd'hui, pas seulement en anticipation d'un futur catalogue plus
    /// large. 8 lignes reste par ailleurs une fraction confortable de la
    /// hauteur d'écran disponible : sur cette machine de développement,
    /// `NSScreen.main?.visibleFrame.height` mesure 1021pt (MacBook Pro, barre
    /// de menu et encoche déjà déduites) ; même le plus petit écran
    /// raisonnablement pris en charge aujourd'hui (~800pt de hauteur visible)
    /// laisse encore plus de trois fois `maxHeight` (ci-dessous) de marge, y
    /// compris quand le panneau bascule au-dessus du curseur faute de place
    /// en dessous (`SlashPanelPositioning.origin`).
    static let maxVisibleRows: Int = 8

    /// Plafond de hauteur du panneau — voir `maxVisibleRows` pour la
    /// justification du nombre de lignes. Calculé à partir de
    /// `rowHeight`/`verticalInset` plutôt que codé en dur, pour rester
    /// cohérent si l'un des deux change.
    static let maxHeight: CGFloat = verticalInset * 2 + CGFloat(maxVisibleRows) * rowHeight

    /// Taille idéale du panneau pour un contenu donné. `groups` est
    /// `[DisplayGroup]` mais ce type est privé au fichier — l'appelant
    /// (interne, `SlashPanel.applySize`) passe l'état déjà projeté. Délègue
    /// le calcul de hauteur à `SlashPanelSizing.height`, qui ne prend que des
    /// `Int` et reste donc testable depuis la cible de test malgré la
    /// visibilité `fileprivate` de `DisplayGroup` — voir sa doc.
    fileprivate static func idealSize(for groups: [DisplayGroup]) -> NSSize {
        guard !groups.isEmpty else {
            return NSSize(width: width, height: emptyHeight)
        }
        let rowCount = groups.reduce(0) { $0 + $1.commands.count }
        let height = SlashPanelSizing.height(groupCount: groups.count, rowCount: rowCount)
        return NSSize(width: width, height: height)
    }
}

// MARK: - Hauteur (fonction pure, testable)

/// Calcule la hauteur idéale du panneau pour un contenu donné, plafonnée à
/// `SlashPanelMetrics.maxHeight`. Extraite de `SlashPanelMetrics.idealSize`
/// pour rester testable indépendamment de `[DisplayGroup]` (type privé au
/// fichier) : même stratégie que `SlashPanelPositioning.origin` (voir sa
/// doc) — une fonction pure prenant des types simples, `internal` pour que
/// `Tests/SlashPanelSizingTests.swift` l'exerce directement, sans dépendre du
/// rendu SwiftUI (non pilotable dans ce projet — voir
/// `Tests/SlashPanelPositioningTests.swift`).
enum SlashPanelSizing {

    /// `groupCount` : nombre d'en-têtes affichés (un par groupe non vide de
    /// `SlashCatalog.grouped`). `rowCount` : nombre total d'entrées, tous
    /// groupes confondus. Le cas « aucun résultat » (0 groupe) n'est pas
    /// modélisé ici : `SlashPanelMetrics.idealSize` le court-circuite avant
    /// d'atteindre cette fonction (hauteur fixe `emptyHeight`).
    static func height(groupCount: Int, rowCount: Int) -> CGFloat {
        let natural = SlashPanelMetrics.verticalInset * 2
            + CGFloat(groupCount) * SlashPanelMetrics.headerHeight
            + CGFloat(rowCount) * SlashPanelMetrics.rowHeight
        return min(natural, SlashPanelMetrics.maxHeight)
    }
}
