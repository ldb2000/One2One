import AppKit

/// `NSTextView` subclass that owns markdown-aware editing. Renders the custom
/// `md*` attribute keys with appropriate fonts/colours and intercepts clicks
/// on task-list checkboxes to toggle them in place.
final class EditorTextView: NSTextView {

    /// Set by the SwiftUI coordinator so toggling a checkbox can push the
    /// new state up the binding.
    var onTaskToggle: ((NSRange, Bool) -> Void)?

    /// Set by the SwiftUI coordinator to route a clicked link. Returns
    /// `true` if handled (typically an internal `onetoone://…` URL) — a
    /// `false`/`nil` result (no closure, or the closure declined) lets
    /// `clicked(onLink:at:)` fall through to `super`, which opens the link
    /// through the system for an external URL. See `EditorRepresentable`'s
    /// `markdownLinks(handler:)`.
    var onLinkClick: ((URL) -> Bool)?

    /// Set by the SwiftUI coordinator to handle ⌥↑ (`true`) / ⌥↓ (`false`) —
    /// déplacement du bloc portant le curseur (voir `BlockMoveCommands`).
    /// `nil` (le défaut, ex. un `EditorTextView` construit à la main sans
    /// passer par `EditorRepresentable.makeNSView`) laisse `keyDown(with:)`
    /// retomber sur `super`, comportement natif inchangé — même convention
    /// que `onLinkClick`.
    var onOptionVerticalArrow: ((Bool) -> Void)?

    /// Set par le coordinateur SwiftUI pour les opérations de structure sur
    /// un tableau (ajouter/supprimer une ligne ou une colonne, voir
    /// `TableEditCommands`) — déclenchées au clavier plutôt qu'au survol
    /// (« poignées » à la AppFlowy) : `EditorTextView` ne gère que
    /// `mouseDown`, aucune infrastructure de suivi de souris n'existe (même
    /// constat que `onOptionVerticalArrow`). Choix retenu plutôt que des
    /// entrées dans le menu `/` : ces dernières auraient exigé de faire
    /// transiter le contexte curseur (cellule de tableau ou non) à travers
    /// `SlashCatalog.grouped`/`SlashController.updateFilter`, qui ne filtrent
    /// aujourd'hui que par `MarkdownFeature` — un jeu de fonctionnalités
    /// statique, pas une position dans le document — donc un remaniement
    /// plus large pour une surface fonctionnelle équivalente ; le clavier
    /// reprend au contraire tel quel le patron déjà mesuré
    /// d'`onOptionVerticalArrow` (interception avant `doCommandBy:`,
    /// enregistrement manuel de l'inverse auprès d'`undoManager`). Combinaison
    /// ⌘⌥ + flèche (bas = ligne, droite = colonne ; ajout = flèche seule,
    /// suppression = flèche + ⇧) : aucun raccourci existant de ce module ni
    /// des menus de l'app (`Views/Menus/MeetingCommands.swift`) ne l'utilise
    /// — Tab/⇧Tab (indentation de liste) et ⌥↑/⌥↓ (déplacement de bloc)
    /// restent seuls sur leurs combinaisons respectives.
    var onTableEditCommand: ((TableEditCommands.Gesture) -> Void)?

    /// Set par le coordinateur SwiftUI pour la permutation d'une rangée/
    /// colonne de tableau avec sa voisine (voir `TableMoveCommands`) —
    /// même choix clavier qu'`onTableEditCommand` (curseur, pas survol),
    /// mais **⌘⌥⌃** + flèche plutôt que ⌘⌥/⌘⌥⇧ : ces deux dernières
    /// combinaisons sont déjà prises par `onTableEditCommand`
    /// (ajouter/supprimer) — ⌘⌥⇧↓ et ⌘⌥⇧→ en particulier, qui auraient été
    /// le choix « naturel » pour permuter vers le bas/la droite, valent déjà
    /// « supprimer la ligne/la colonne ». Voir la doc de tête de
    /// `TableMoveCommands` pour la vérification complète des collisions.
    var onTableMoveCommand: ((TableMoveCommands.Gesture) -> Void)?

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Configure les options d'édition de texte. Les corrections/complétions/
    /// remplacements automatiques sont désactivés car ils interféreraient avec
    /// la syntaxe markdown (ex. transformation des `--` en tiret long), et
    /// `importsGraphics` est coupé car l'éditeur ne gère que du texte balisé.
    ///
    /// `isAutomaticTextReplacementEnabled` ne couvre **que** les
    /// remplacements du panneau Réglages Système › Clavier › Substitutions de
    /// texte — la substitution `--`/`---` → tiret demi-cadratin/cadratin est
    /// pilotée par la propriété séparée `isAutomaticDashSubstitutionEnabled`
    /// (défaut AppKit : `true`), non couverte par le flag ci-dessus malgré ce
    /// que suggérait le commentaire précédent. Sans cette ligne, taper `-->`
    /// dans un bloc ```` ```mermaid ```` insérait un tiret cadratin (`—>`)
    /// au lieu des deux traits d'union `--` de la syntaxe de flèche — mermaid
    /// refusait alors le diagramme (« Lexical error… Unrecognized text »)
    /// alors que l'utilisateur avait tapé une syntaxe valide.
    private func commonInit() {
        isRichText = true
        allowsUndo = true
        importsGraphics = false
        usesFindBar = true
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        font = NSFont.systemFont(ofSize: 13)
        // `width: 58` réserve la gouttière de bloc à gauche (spec Screen 4 du
        // handoff `editeur_blocs` — poignée `⠿` + bouton `+`). Symétrique par
        // limitation de `NSTextView.textContainerInset` (largeur unique
        // gauche+droite) : les 58 px à droite sont wasted pour l'instant. Un
        // wrapper `NSView` documentView du scrollView (à faire step 4) rendra
        // cet inset asymétrique.
        textContainerInset = NSSize(width: BlockGutterLayout.width, height: 6)
        textContainer?.lineFragmentPadding = BlockGutterLayout.contentHorizontalPadding

        // Espace vertical entre blocs — indispensable pour que la gouttière +
        // le cadre de survol/sélection lisent comme des « cartes » plutôt que
        // comme des bandes accolées les unes aux autres. Vaut pour tout
        // paragraphe qui ne pose pas son propre `.paragraphStyle`
        // (`StyleRenderer` en pose un pour listes/citations/cellules de
        // table ; les paragraphes ordinaires héritent d'ici). Ne mute pas
        // les paragraphes stylés par `StyleRenderer`, qui gagneraient à
        // recevoir le même spacing dans un second temps.
        let base = NSMutableParagraphStyle()
        base.paragraphSpacing = BlockGutterLayout.blockSpacing
        defaultParagraphStyle = base

        registerForDraggedTypes([NSPasteboard.PasteboardType("OneToOne.BlockDragType")])
    }

    // MARK: - Glisser-déposer de bloc (step 4 handoff `editeur_blocs`)

    struct DropTarget: Equatable {
        let index: Int
        let y: CGFloat
    }

    var draggedBlockRange: NSRange? {
        didSet {
            guard draggedBlockRange != oldValue else { return }
            needsDisplay = true
        }
    }

    var dropTarget: DropTarget? {
        didSet {
            guard dropTarget != oldValue else { return }
            needsDisplay = true
        }
    }

    // MARK: - Gouttière de bloc (step 1 handoff `editeur_blocs`)

    /// Plage du bloc actuellement survolé. Synchronisé avec
    /// `MarkdownLayoutManager.hoveredBlockRange` qui la consomme pour peindre
    /// les icônes `+`/`⠿` et le léger fond de survol.
    private var hoveredBlockRange: NSRange? {
        didSet {
            guard hoveredBlockRange != oldValue else { return }
            (layoutManager as? MarkdownLayoutManager)?.hoveredBlockRange = hoveredBlockRange
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var hoveredGutterZone: BlockGutterLayout.HitZone? {
        didSet {
            guard hoveredGutterZone != oldValue else { return }
            needsDisplay = true
        }
    }

    private var pointerLocation: NSPoint?

    /// Plage du bloc sélectionné comme objet (clic sur `⠿`). Synchronisé avec
    /// `MarkdownLayoutManager.selectedBlockRange` qui la consomme pour peindre
    /// le cadre `#0a6cff` + fond `#f4f8ff`.
    var selectedBlockRange: NSRange? {
        didSet {
            guard selectedBlockRange != oldValue else { return }
            (layoutManager as? MarkdownLayoutManager)?.selectedBlockRange = selectedBlockRange
            needsDisplay = true
        }
    }

    /// `NSTrackingArea` couvre tout le bounds du textView, refreshé à chaque
    /// changement de taille. `mouseMoved` fait la logique de suivi elle-même
    /// (calcul du bloc sous le curseur), pas besoin de multiples rects par
    /// bloc. Requiert la fenêtre : appelé par AppKit dès que le textView est
    /// attaché à une hiérarchie de vues visibles.
    private var gutterTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = gutterTrackingArea {
            removeTrackingArea(existing)
            gutterTrackingArea = nil
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        gutterTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        pointerLocation = point
        // Lecture seule : aucune affordance d'édition au survol — ni fond de
        // bloc, ni icônes `+`/`⠿` (`blockGutterHit` refuse déjà le clic).
        hoveredBlockRange = isEditable ? blockRange(at: point) : nil
        hoveredGutterZone = isEditable ? blockGutterHit(at: point)?.zone : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Certains styles de fenêtre (ex. panel utility) n'acceptent pas
        // mouseMoved par défaut ; NSTrackingArea .mouseMoved est censé
        // fonctionner indépendamment, mais on force ici en défensif.
        window?.acceptsMouseMovedEvents = true
    }

    /// Peint les icônes `+`/`⠿` de la gouttière du bloc survolé (ou
    /// sélectionné) APRÈS le rendu texte. Fait ici, pas dans
    /// `MarkdownLayoutManager.drawGlyphs`, car ce dernier est clippé au rect
    /// du `NSTextContainer` (x ≥ `textContainerOrigin.x` = 58) alors que la
    /// gouttière vit à x < 58. `NSTextView.draw` peint en coordonnées vue,
    /// sans ce clip.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockGutterIcons()
        
        if let draggedRange = draggedBlockRange, let manager = layoutManager as? MarkdownLayoutManager,
           let bodyRect = manager.viewBodyRect(for: draggedRange, origin: textContainerOrigin) {
            let fadeRect = BlockGutterLayout.selectionFrame(forBodyRect: bodyRect)
            NSColor(white: 1, alpha: 0.6).setFill()
            let path = NSBezierPath(roundedRect: fadeRect, xRadius: BlockGutterLayout.bodyCornerRadius, yRadius: BlockGutterLayout.bodyCornerRadius)
            path.fill()
        }
        
        if let target = dropTarget {
            BlockGutterLayout.accentColor.setFill()
            let lineRect = NSRect(
                x: textContainerOrigin.x,
                y: target.y - 1,
                width: textContainer?.size.width ?? max(0, bounds.width - textContainerOrigin.x),
                height: 2
            )
            let path = NSBezierPath(roundedRect: lineRect, xRadius: 1, yRadius: 1)
            path.fill()
        }
        
        drawTableFooter()
    }
    
    private func drawTableFooter() {
        guard let table = activeTableInView() else { return }
        let footer = TableControlLayout.footerGeometry(forTableRect: table.tableRect)

        let footerPath = NSBezierPath(
            roundedRect: footer.footerRect,
            xRadius: BlockGutterLayout.bodyCornerRadius,
            yRadius: BlockGutterLayout.bodyCornerRadius
        )
        TableControlLayout.footerBackgroundColor.setFill()
        footerPath.fill()
        TableControlLayout.footerBorderColor.setStroke()
        footerPath.lineWidth = 1
        footerPath.stroke()

        drawFooterButton(footer.addRowRect, label: "+", enabled: true)
        drawFooterButton(footer.deleteRowRect, label: "−", enabled: table.canDeleteRow)
        drawFooterButton(footer.addColumnRect, label: "Add Column", enabled: true)

        let bodyRows = max(0, table.rowCount - 1)
        let count = "\(bodyRows) rows · \(table.columnCount) columns" as NSString
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: TableControlLayout.footerTextColor
        ]
        let countSize = count.size(withAttributes: countAttributes)
        count.draw(
            at: NSPoint(x: footer.deleteRowRect.maxX + 12, y: footer.footerRect.midY - countSize.height / 2),
            withAttributes: countAttributes
        )

        guard let point = pointerLocation,
              let header = table.headerCells.first(where: { $0.rect.contains(point) })
        else { return }
        let chevronRect = TableControlLayout.headerChevronRect(forCellRect: header.rect)
        TableControlLayout.headerChevronHoverColor.setFill()
        NSBezierPath(roundedRect: chevronRect, xRadius: 4, yRadius: 4).fill()
        drawSystemSymbol(
            "chevron.down",
            pointSize: 8,
            color: TableControlLayout.headerChevronColor,
            in: chevronRect
        )
    }

    private func drawFooterButton(_ rect: NSRect, label: String, enabled: Bool) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: TableControlLayout.footerButtonCornerRadius,
            yRadius: TableControlLayout.footerButtonCornerRadius
        )
        TableControlLayout.footerButtonBackgroundColor.withAlphaComponent(enabled ? 1 : 0.45).setFill()
        path.fill()
        TableControlLayout.footerButtonBorderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = label as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: label.count == 1 ? 13 : 11.5),
            .foregroundColor: TableControlLayout.footerButtonTextColor.withAlphaComponent(enabled ? 1 : 0.35)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawBlockGutterIcons() {
        guard let manager = layoutManager as? MarkdownLayoutManager else { return }
        let rangeToShow = manager.hoveredBlockRange ?? (draggedBlockRange != nil ? manager.selectedBlockRange : nil)
        guard let range = rangeToShow,
              let bodyRect = manager.viewBodyRect(for: range)
        else { return }
        let icons = BlockGutterLayout.iconsFrame(forBodyRect: bodyRect)

        if hoveredGutterZone == .handle { drawGutterHover(in: icons.handle) }
        if hoveredGutterZone == .plus { drawGutterHover(in: icons.plus) }

        drawSystemSymbol(
            BlockGutterLayout.handleSymbolName,
            pointSize: BlockGutterLayout.handleSymbolPointSize,
            color: BlockGutterLayout.handleIconColor,
            in: icons.handle
        )
        drawSystemSymbol(
            BlockGutterLayout.plusSymbolName,
            pointSize: BlockGutterLayout.plusSymbolPointSize,
            color: BlockGutterLayout.plusIconColor,
            in: icons.plus
        )
    }

    private func drawGutterHover(in rect: NSRect) {
        BlockGutterLayout.iconHoverFillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    private func drawSystemSymbol(_ name: String, pointSize: CGFloat, color: NSColor, in rect: NSRect) {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        else { return }
        let tinted = NSImage(size: source.size, flipped: false) { imageRect in
            source.draw(in: imageRect)
            color.setFill()
            imageRect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(
            at: NSPoint(x: rect.midX - tinted.size.width / 2, y: rect.midY - tinted.size.height / 2),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredBlockRange = nil
        hoveredGutterZone = nil
        pointerLocation = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let manager = layoutManager as? MarkdownLayoutManager,
              let range = hoveredBlockRange ?? (draggedBlockRange != nil ? selectedBlockRange : nil),
              let bodyRect = manager.viewBodyRect(for: range)
        else { return }
        let icons = BlockGutterLayout.iconsFrame(forBodyRect: bodyRect)
        addCursorRect(icons.plus, cursor: .arrow)
        addCursorRect(icons.handle, cursor: draggedBlockRange == nil ? .openHand : .closedHand)
    }

    /// Plage du bloc contenant `point` (coordonnées vue). Retourne `nil` si
    /// hors du storage. Ne considère PAS la zone de gouttière — un point dans
    /// la gouttière renvoie le bloc de la ligne à sa hauteur, ce qui permet
    /// au survol d'afficher la gouttière du bloc même quand la souris est
    /// pile dans la gouttière (sinon dès que la souris entre dans la
    /// gouttière, le survol s'éteindrait — self-flickering).
    func blockRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        // `characterIndexForInsertion` clamp à un x utile même si le point est
        // dans la gouttière (à gauche du texte) : il retourne alors le début
        // de la ligne à cette hauteur, ce qu'on veut.
        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(max(0, charIndex), storage.length - 1)
        return BlockRange.of(in: storage, at: safeIndex).range
    }

    /// Hit-test d'un clic dans la gouttière du bloc à la hauteur de `point`.
    /// Retourne la zone cliquée + la plage du bloc concerné, ou `nil` si le
    /// point ne touche ni `+` ni `⠿` du bloc à cette hauteur — ou si
    /// l'éditeur est en lecture seule : la poignée mène au menu de bloc
    /// mutable et `+` insère une ligne `/`, deux gestes d'édition.
    func blockGutterHit(at point: NSPoint) -> (zone: BlockGutterLayout.HitZone, range: NSRange)? {
        guard isEditable, let range = blockRange(at: point),
              let manager = layoutManager as? MarkdownLayoutManager,
              let container = textContainer
        else { return nil }
        guard let bodyContainerRect = BlockGutterLayout.containerRect(
            for: range, layoutManager: manager, container: container
        ) else { return nil }
        let bodyViewRect = bodyContainerRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        guard let zone = BlockGutterLayout.hitTest(point: point, bodyRect: bodyViewRect) else {
            return nil
        }
        return (zone, range)
    }

    // MARK: - ⌥↑ / ⌥↓ — déplacement de bloc

    /// Code matériel des flèches Haut/Bas — stables quel que soit
    /// l'agencement clavier (contrairement à `charactersIgnoringModifiers`,
    /// qui peut varier). Valeurs `kVK_UpArrow`/`kVK_DownArrow` de
    /// `Carbon.HIToolbox`, recopiées ici pour ne pas importer tout Carbon
    /// pour deux constantes.
    private static let upArrowKeyCode: UInt16 = 0x7E
    private static let downArrowKeyCode: UInt16 = 0x7D
    /// Code matériel de la flèche Droite — voir la doc de
    /// `onTableEditCommand` : ⌘⌥→ ajoute une colonne à droite.
    private static let rightArrowKeyCode: UInt16 = 0x7C
    /// Code matériel de la flèche Gauche — voir la doc de
    /// `onTableMoveCommand` : ⌘⌥⌃← permute avec la colonne de gauche.
    private static let leftArrowKeyCode: UInt16 = 0x7B

    /// Modificateurs qui distinguent réellement une combinaison — masque
    /// volontairement `.capsLock`/`.numericPad`/`.function`/`.help`, que
    /// macOS pose aussi sur un événement flèche indépendamment de ce que
    /// l'utilisateur tient réellement (mesuré : un ⌥↑ synthétique construit
    /// sans ces flags est bien celui que macOS envoie pour de vrai — voir le
    /// rapport de tâche — comparer `modifierFlags` à `.option` seul, sans ce
    /// masque, échouerait si l'OS les ajoutait).
    private static let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Intercepte ⌥↑/⌥↓ **avant** `interpretKeyEvents:`/`doCommandBy:` :
    /// mesuré (rapport de tâche), la combinaison résout via
    /// `StandardKeyBinding.dict` en DEUX sélecteurs par frappe —
    /// `moveBackward:`+`moveToBeginningOfParagraph:` pour ⌥↑,
    /// `moveForward:`+`moveToEndOfParagraph:` pour ⌥↓ — chacun *partagé* avec
    /// d'autres raccourcis (`^b`/`^a`/`^f`/`^e`) : les intercepter via
    /// `Coordinator.textView(_:doCommandBy:)` détournerait ces derniers
    /// aussi. Consomme systématiquement l'événement dès que `onOptionVerticalArrow`
    /// est présent — y compris aux bords du document (le bloc ne bouge pas,
    /// mais la touche ne doit pas non plus retomber sur la navigation par
    /// paragraphe qu'elle remplace) ; `nil` (pas de closure assignée) laisse
    /// `super` gérer, comportement natif inchangé.
    override func keyDown(with event: NSEvent) {
        // Lecture seule : tous les raccourcis interceptés ici sont des
        // commandes d'édition (déplacement de bloc, structure de tableau) —
        // on laisse AppKit gérer la frappe (navigation, sélection) sans eux.
        guard isEditable else {
            super.keyDown(with: event)
            return
        }
        if let handler = onOptionVerticalArrow,
           event.modifierFlags.intersection(Self.relevantModifiers) == .option {
            switch event.keyCode {
            case Self.upArrowKeyCode:
                moveSelectedBlockWithKeyboard(using: handler, up: true)
                return
            case Self.downArrowKeyCode:
                moveSelectedBlockWithKeyboard(using: handler, up: false)
                return
            default:
                break
            }
        }
        if let handler = onTableEditCommand,
           event.modifierFlags.intersection(Self.relevantModifiers) == [.command, .option] {
            switch event.keyCode {
            case Self.downArrowKeyCode:
                handler(.addRowBelow)
                return
            case Self.leftArrowKeyCode:
                handler(.addColumnLeft)
                return
            case Self.rightArrowKeyCode:
                handler(.addColumnRight)
                return
            default:
                break
            }
        }
        if let handler = onTableEditCommand,
           event.modifierFlags.intersection(Self.relevantModifiers) == [.command, .option, .shift] {
            switch event.keyCode {
            case Self.downArrowKeyCode:
                handler(.deleteRow)
                return
            case Self.rightArrowKeyCode:
                handler(.deleteColumn)
                return
            default:
                break
            }
        }
        if let handler = onTableMoveCommand,
           event.modifierFlags.intersection(Self.relevantModifiers) == [.command, .option, .control] {
            switch event.keyCode {
            case Self.upArrowKeyCode:
                handler(.swapRowUp)
                return
            case Self.downArrowKeyCode:
                handler(.swapRowDown)
                return
            case Self.leftArrowKeyCode:
                handler(.swapColumnLeft)
                return
            case Self.rightArrowKeyCode:
                handler(.swapColumnRight)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    private func moveSelectedBlockWithKeyboard(using handler: (Bool) -> Void, up: Bool) {
        guard let range = selectedBlockRange else {
            handler(up)
            return
        }
        setSelectedRange(NSRange(location: range.location, length: 0))
        handler(up)
        if let storage = textStorage, storage.length > 0 {
            let location = min(selectedRange().location, storage.length - 1)
            selectedBlockRange = BlockRange.of(in: storage, at: location).range
        }
    }

    // MARK: - Collage

    /// Attributs `md*` à retirer des `typingAttributes` avant d'insérer un
    /// placeholder d'image. Sans ce nettoyage, `insertText(_:replacementRange:)`
    /// les fusionne dans la plage insérée : `NSTextView` maintient
    /// `typingAttributes` à partir des attributs du caractère précédant le
    /// curseur, et complète avec ces valeurs les clés absentes de la chaîne
    /// attribuée qu'on lui passe. Un collage juste après du code inline
    /// hériterait ainsi `.mdInlineCode` sur le caractère `U+FFFC` — et
    /// `MarkdownSerializer.emitInline` donne la priorité exclusive au code
    /// inline, qui filtre les `U+FFFC` de son contenu : l'image disparaîtrait
    /// purement et simplement à la sérialisation, fichier resté orphelin sur
    /// disque. Un collage après du gras hériterait `.mdBold` et se
    /// retrouverait emballé en `**![...]**` sans que l'utilisateur l'ait
    /// demandé. Vérifié empiriquement pour ces deux cas — voir
    /// `Tests/EditorTextViewPasteTests.swift`.
    private static let inlineAttributesToStripBeforeImageInsertion: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    /// Insère le placeholder référençant `imageURL` sur sa propre ligne, en
    /// évitant qu'il hérite des attributs `md*` du contexte via
    /// `typingAttributes` (voir `inlineAttributesToStripBeforeImageInsertion`).
    /// Point d'entrée commun à `paste(_:)` et au bouton image de
    /// `MarkdownToolbar`, pour que les deux bénéficient du même nettoyage.
    func insertImagePlaceholder(for imageURL: URL, alt: String = "image") {
        for key in Self.inlineAttributesToStripBeforeImageInsertion {
            typingAttributes.removeValue(forKey: key)
        }
        insertText(Self.imagePlaceholder(for: imageURL, alt: alt), replacementRange: selectedRange())
    }

    /// Si le presse-papiers contient une image, l'enregistre sur disque et
    /// insère son placeholder ; sinon délègue au collage standard.
    ///
    /// Le placeholder inséré est la même représentation que celle produite par
    /// `MarkdownParser` pour une image (voir `ImagePlaceholder`), et non le
    /// texte `![alt](url)` littéral : sans ses attributs, `MarkdownSerializer`
    /// traiterait ce texte comme de la saisie ordinaire et échapperait ses
    /// caractères spéciaux (`!`, `[`, `]`, `(`, `)`, `_` — voir
    /// `MarkdownEscaping.escapeInline`) dès le `textDidChange` déclenché par
    /// cette insertion, corrompant la référence de façon permanente. Avec le
    /// placeholder attribué, ce même `textDidChange` fait au contraire
    /// apparaître l'image immédiatement : `StyleRenderer.applyVisualStyle`
    /// repère `.mdImageURL` sur la plage insérée et y attache le
    /// `NSTextAttachment` réel, sans attendre de frappe supplémentaire.
    ///
    /// Si `saveClipboardImage()` échoue (écriture disque impossible), le
    /// repli vers `super.paste(sender)` ne colle rien de visible : le
    /// presse-papiers ne contient par construction que de l'image à ce point
    /// (le `guard` a déjà exclu le cas contraire), et `importsGraphics =
    /// false` (`commonInit`) fait que `NSTextView` ignore le contenu image
    /// brut. C'est un échec silencieux connu et accepté (pas de UI d'erreur
    /// pour un cas limite — disque plein, permissions — jugé hors périmètre
    /// ici) plutôt qu'un bug : l'utilisateur ne perd rien puisque rien
    /// n'avait encore été inséré.
    override func paste(_ sender: Any?) {
        guard MediaStore.clipboardHasImage,
              let imageURL = MediaStore.saveClipboardImage() else {
            super.paste(sender)
            return
        }
        insertImagePlaceholder(for: imageURL)
    }

    /// Construit le placeholder à insérer pour référencer `imageURL` : le
    /// caractère `ImagePlaceholder.attributedString` entouré de retours à la
    /// ligne pour que l'image occupe sa propre ligne. Isolé en fonction
    /// `static` pour être exercé par les tests indépendamment de
    /// `NSPasteboard.general`.
    static func imagePlaceholder(for imageURL: URL, alt: String = "image") -> NSAttributedString {
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(ImagePlaceholder.attributedString(for: imageURL, alt: alt))
        insertion.append(NSAttributedString(string: "\n"))
        return insertion
    }

    // MARK: - Click handling for task checkboxes

    /// Intercepte le clic pour détecter s'il vise la case à cocher d'un item
    /// de tâche, puis pour préserver le placement du curseur sur un clic
    /// simple au-dessus d'un lien (voir `suspendingNativeLink`). Délègue au
    /// comportement standard de `NSTextView` dans tous les autres cas — y
    /// compris ⌘-clic sur un lien, qu'AppKit route lui-même vers
    /// `clicked(onLink:at:)` (ci-dessous).
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Gouttière de bloc (step 1 handoff `editeur_blocs`) : un clic sur `⠿`
        // sélectionne le bloc comme objet (mode distinct du curseur texte).
        // `+` est réservé pour l'insertion (step 4) — pour l'instant no-op mais
        // consomme le clic pour ne pas positionner le curseur là.
        if let hit = blockGutterHit(at: point) {
            switch hit.zone {
            case .handle:
                selectedBlockRange = hit.range
                var isDrag = false
                if let window = self.window {
                    let startPoint = event.locationInWindow
                    while let nextEvent = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                        if nextEvent.type == .leftMouseDragged {
                            let distance = hypot(nextEvent.locationInWindow.x - startPoint.x, nextEvent.locationInWindow.y - startPoint.y)
                            if distance > 3 {
                                isDrag = true
                                draggedBlockRange = hit.range
                                
                                let pbItem = NSPasteboardItem()
                                pbItem.setString("\(hit.range.location),\(hit.range.length)", forType: NSPasteboard.PasteboardType("OneToOne.BlockDragType"))
                                let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
                                
                                let emptyImage = NSImage(size: NSSize(width: 1, height: 1))
                                dragItem.setDraggingFrame(NSRect(origin: point, size: NSSize(width: 1, height: 1)), contents: emptyImage)
                                
                                beginDraggingSession(with: [dragItem], event: nextEvent, source: self)
                                break
                            }
                        } else if nextEvent.type == .leftMouseUp {
                            break
                        }
                    }
                }
                if !isDrag {
                    showBlockMenu(for: hit.range, at: point)
                }
            case .plus:
                insertSlashBlock(above: hit.range)
            }
            return
        }
        // Clic ailleurs → si un bloc était sélectionné comme objet, on retombe
        // en mode curseur texte : la sélection de bloc se dissipe.
        if selectedBlockRange != nil {
            selectedBlockRange = nil
        }

        if handleTableControls(at: point) { return }
        
        if toggleTaskMarker(at: point) { return }
        if let doneRange = mermaidDoneButtonRange(at: point) {
            // Ferme le bloc (état 3 → fermé) en sortant le curseur **au-delà
            // du séparateur** — la borne de fin du bloc est incluse dans
            // l'état ouvert (voir `MermaidBlockLayout.selectionTouches`),
            // rester dessus ne refermerait rien. Un bloc en toute fin de
            // document n'a pas de séparateur : on en insère un pour disposer
            // d'une position fermée. `EditorRepresentable.Coordinator.
            // updateMermaidBlockGeometryIfNeeded` referme alors sa géométrie
            // et le diagramme se re-rend (voir `MarkdownLayoutManager.
            // drawMermaidDiagram`).
            let placement = MermaidBlockLayout.doneCaretPlacement(
                afterBlock: doneRange, storageLength: textStorage?.length ?? 0
            )
            if placement.insertsSeparator {
                replaceBlockCharactersRegisteringUndo(
                    in: NSRange(location: NSMaxRange(doneRange), length: 0),
                    with: NSAttributedString(string: "\n")
                )
            }
            setSelectedRange(NSRange(location: min(placement.location, textStorage?.length ?? 0), length: 0))
            return
        }
        if let actionRange = mermaidErrorActionButtonRange(at: point) {
            // Même geste qu'un clic ailleurs sur le cadre (ci-dessous) —
            // ouvre le bloc en y plaçant le curseur — mais hit-testé
            // précisément sur la pastille « Ouvrir le source » plutôt que
            // sur toute la zone où l'image est dessinée.
            setSelectedRange(NSRange(location: actionRange.location, length: 0))
            return
        }
        if let duplicateRange = mermaidCopyButtonRange(at: point) {
            duplicateMermaidBlock(range: duplicateRange)
            return
        }
        if let mermaidRange = mermaidBlockRange(at: point) {
            setSelectedRange(NSRange(location: mermaidRange.location, length: 0))
            return
        }

        // Mesuré (sonde jetée après mesure, cf. commit) : dans cette
        // configuration TextKit 1 (`NSTextStorage` → `MarkdownLayoutManager`
        // → `NSTextContainer`), le `mouseDown` natif d'AppKit route TOUT
        // clic tombant sur une plage `.link` vers `clicked(onLink:at:)` —
        // simple clic compris, ⌘ ou pas, `isEditable` ou pas — et le
        // curseur ne se déplace jamais dans ce cas (contrairement à un clic
        // hors lien, qui positionne bien le curseur : témoin vérifié dans la
        // même sonde). La croyance répandue qu'un ⌘-clic serait nécessaire
        // en mode éditable ne s'est *pas* vérifiée ici. Sans intervention,
        // un simple clic sur un lien rendrait donc son texte impossible à
        // corriger au clavier — régression explicitement proscrite par ce
        // chantier. On ne neutralise que le cas simple clic + éditable :
        // ⌘-clic doit au contraire atteindre `clicked(onLink:at:)`.
        // Un clic sur le dernier caractère d'un bloc mermaid ouvert peut
        // poser le curseur sur la borne de fin : elle est **incluse** dans
        // l'état ouvert (`MermaidBlockLayout.selectionTouches`), le bloc
        // reste donc en édition sans repositionnement — seul « Terminé »
        // (géré plus haut) referme explicitement le bloc.
        if isEditable, !event.modifierFlags.contains(.command), let linkRange = nativeLinkRange(at: point) {
            suspendingNativeLink(in: linkRange) {
                super.mouseDown(with: event)
            }
            return
        }

        super.mouseDown(with: event)
    }

    func insertSlashBlock(above range: NSRange) {
        guard isEditable, let storage = textStorage else { return }
        let location = min(max(0, range.location), storage.length)
        let insertionRange = NSRange(location: location, length: 0)
        guard replaceBlockCharactersRegisteringUndo(
            in: insertionRange, with: NSAttributedString(string: "/\n")
        ) else { return }

        selectedBlockRange = nil
        setSelectedRange(NSRange(location: location + 1, length: 0))
    }

    func tableControlGesture(at point: NSPoint) -> TableEditCommands.Gesture? {
        guard isEditable, let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }

        let location = min(selectedRange().location, storage.length - 1)
        guard let placement = TableControlLayout.placementForCursor(
            in: storage,
            at: location,
            layoutManager: layoutManager,
            container: container
        ) else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        return TableControlLayout.gesture(at: containerPoint, in: placement)
    }

    /// Table active pour la sélection courante, en coordonnées **vue** —
    /// point d'entrée partagé par le dessin (`drawTableFooter`) et
    /// l'interaction (`handleTableControls`). La garde `isEditable` vit ici,
    /// comme dans `tableControlGesture` : en lecture seule, ni pied `+`/`−`
    /// ni menu de colonne — leurs commandes (`TableEditCommands`) mutent le
    /// storage sans autre vérification.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests, comme `tableControlGesture`.
    func activeTableInView() -> TableControlLayout.ActiveTable? {
        guard isEditable, let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }
        let location = min(selectedRange().location, storage.length - 1)
        guard let table = TableControlLayout.activeTable(
            in: storage,
            at: location,
            layoutManager: layoutManager,
            container: container
        ) else { return nil }
        let origin = textContainerOrigin
        return TableControlLayout.ActiveTable(
            range: table.range,
            tableRect: table.tableRect.offsetBy(dx: origin.x, dy: origin.y),
            selectedCell: table.selectedCell,
            deletionTargetRange: table.deletionTargetRange,
            rowCount: table.rowCount,
            columnCount: table.columnCount,
            headerCells: table.headerCells.map {
                TableControlLayout.HeaderCell(
                    column: $0.column,
                    range: $0.range,
                    rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y)
                )
            }
        )
    }

    private func handleTableControls(at point: NSPoint) -> Bool {
        guard let table = activeTableInView() else { return false }
        let footer = TableControlLayout.footerGeometry(forTableRect: table.tableRect)
        if let action = TableControlLayout.footerAction(at: point, in: footer) {
            switch action {
            case .addRow:
                setSelectedRange(NSRange(location: max(table.range.location, NSMaxRange(table.range) - 1), length: 0))
                onTableEditCommand?(.addRowBelow)
            case .deleteRow:
                guard table.canDeleteRow, let target = table.deletionTargetRange else { return true }
                setSelectedRange(NSRange(location: target.location, length: 0))
                onTableEditCommand?(.deleteRow)
            case .addColumn:
                if let lastHeader = table.headerCells.max(by: { $0.column < $1.column }) {
                    setSelectedRange(NSRange(location: lastHeader.range.location, length: 0))
                }
                onTableEditCommand?(.addColumnRight)
            }
            return true
        }

        if let header = table.headerCells.first(where: {
            TableControlLayout.headerChevronRect(forCellRect: $0.rect).contains(point)
        }) {
            setSelectedRange(NSRange(location: header.range.location, length: 0))
            showColumnMenu(forColumn: header.column, canDelete: table.canDeleteColumn, at: point)
            return true
        }
        return false
    }

    /// Laisse AppKit présenter le menu contextuel au point exact du clic.
    /// `NSMenu.popUp(..., in: self)` attend un point en coordonnées de la
    /// vue ; l'ancien chemin lui transmettait `event.locationInWindow`, ce
    /// qui ajoutait implicitement le décalage de l'éditeur et envoyait le
    /// menu vers le bas de la fenêtre.
    override func menu(for event: NSEvent) -> NSMenu? {
        // Lecture seule : menu natif d'AppKit — le menu de bloc est
        // entièrement mutable (Monter/Descendre/Dupliquer/Supprimer).
        guard isEditable else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        guard let range = blockRange(at: point) else { return super.menu(for: event) }
        selectedBlockRange = range
        return makeBlockMenu(for: range)
    }

    // MARK: - Menu de bloc (step 4)

    private func showBlockMenu(for range: NSRange, at point: NSPoint) {
        makeBlockMenu(for: range).popUp(positioning: nil, at: point, in: self)
    }

    private func makeBlockMenu(for range: NSRange) -> NSMenu {
        let menu = NSMenu(title: "Block Menu")
        menu.autoenablesItems = false
        
        let upItem = NSMenuItem(title: "Monter", action: #selector(menuMoveBlockUp(_:)), keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        upItem.representedObject = range
        upItem.keyEquivalentModifierMask = .option
        upItem.target = self
        menu.addItem(upItem)
        
        let downItem = NSMenuItem(title: "Descendre", action: #selector(menuMoveBlockDown(_:)), keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        downItem.representedObject = range
        downItem.keyEquivalentModifierMask = .option
        downItem.target = self
        menu.addItem(downItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let duplicateItem = NSMenuItem(title: "Dupliquer", action: #selector(menuDuplicateBlock(_:)), keyEquivalent: "d")
        duplicateItem.representedObject = range
        duplicateItem.keyEquivalentModifierMask = .command
        duplicateItem.target = self
        menu.addItem(duplicateItem)
        
        let editItem = NSMenuItem(title: "Modifier le source", action: #selector(menuEditBlockSource(_:)), keyEquivalent: "\r")
        editItem.representedObject = range
        editItem.keyEquivalentModifierMask = []
        editItem.target = self
        menu.addItem(editItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "Supprimer le bloc", action: #selector(menuDeleteBlock(_:)), keyEquivalent: "\u{0008}")
        deleteItem.representedObject = range
        deleteItem.keyEquivalentModifierMask = .command
        deleteItem.target = self
        let deleteTitle = NSAttributedString(string: "Supprimer le bloc", attributes: [.foregroundColor: NSColor(red: 0xc8/255, green: 0x34/255, blue: 0x2b/255, alpha: 1)])
        deleteItem.attributedTitle = deleteTitle
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func menuMoveBlockUp(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
        onOptionVerticalArrow?(true)
    }
    
    @objc private func menuMoveBlockDown(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
        onOptionVerticalArrow?(false)
    }
    
    @objc private func menuDuplicateBlock(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange, let storage = textStorage else { return }
        duplicateMermaidBlock(range: range, storage: storage)
    }

    private func duplicateMermaidBlock(range: NSRange) {
        guard let storage = textStorage else { return }
        duplicateMermaidBlock(range: range, storage: storage)
    }

    private func duplicateMermaidBlock(range: NSRange, storage: NSTextStorage) {
        let blockString = storage.attributedSubstring(from: range)

        let insertionString = NSMutableAttributedString(string: "\n")
        insertionString.append(blockString)

        let insertionLocation = range.location + range.length
        replaceBlockCharactersRegisteringUndo(
            in: NSRange(location: insertionLocation, length: 0), with: insertionString
        )
    }
    
    @objc private func menuEditBlockSource(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
    }
    
    @objc private func menuDeleteBlock(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }
        deleteBlock(range: range)
    }

    /// Supprime le bloc `range` et son `\n` séparateur éventuel, avec
    /// annulation (`replaceBlockCharactersRegisteringUndo`).
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests, comme `toggleTaskMarker`/`tableControlGesture`.
    func deleteBlock(range: NSRange) {
        guard let storage = textStorage else { return }

        let afterContent = range.location + range.length
        let lengthWithNewline: Int
        if afterContent < storage.length, (storage.string as NSString).character(at: afterContent) == 0x0A {
            lengthWithNewline = range.length + 1
        } else {
            lengthWithNewline = range.length
        }
        let deletionRange = NSRange(location: range.location, length: lengthWithNewline)

        if replaceBlockCharactersRegisteringUndo(in: deletionRange, with: NSAttributedString()),
           selectedBlockRange == range {
            selectedBlockRange = nil
        }
    }

    /// Remplace `range` par `replacement` (attributs compris) sous bracket
    /// `shouldChangeText`/`didChangeText` — le seul patron partagé par
    /// toutes les commandes de bloc (suppression, duplication, insertion
    /// `/`, glisser-déposer).
    ///
    /// L'annulation vient du bracket lui-même : avec `allowsUndo` et un
    /// `replacementString` **non nil**, `shouldChangeText` enregistre
    /// nativement l'inverse — texte **attribué** compris, `md*` inclus
    /// (mesuré : voir `EditorTextViewBlockMutationUndoTests`, restauration
    /// du texte, des attributs et symétrie ⌘Z/⇧⌘Z). Ne **pas** ajouter de
    /// `registerUndo` manuel par-dessus : l'inverse serait enregistré deux
    /// fois et ⌘Z insérerait le bloc en double (mesuré aussi). Ce constat
    /// ne contredit pas `BlockMoveCommands.swapAdjacentBlocks` ni
    /// `applyTaskToggle` : eux n'appellent pas le bracket (pas de
    /// remplacement de caractères pour un attribut seul, bracket évité pour
    /// l'échange) et doivent donc enregistrer l'inverse à la main.
    ///
    /// La plage réécrite est restylée avant `didChangeText()` : la mutation
    /// directe du storage ne passe pas par `NSTextView.insertText`, donc
    /// aucun restyle implicite n'aurait lieu.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests.
    @discardableResult
    func replaceBlockCharactersRegisteringUndo(in range: NSRange, with replacement: NSAttributedString) -> Bool {
        guard let storage = textStorage,
              range.location >= 0, NSMaxRange(range) <= storage.length,
              shouldChangeText(in: range, replacementString: replacement.string)
        else { return false }

        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        let newRange = NSRange(location: range.location, length: replacement.length)
        if newRange.length > 0 {
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: newRange)
        }
        didChangeText()
        return true
    }

    // MARK: - Menu de colonne (Tableau)
    
    private func showColumnMenu(forColumn column: Int, canDelete: Bool, at point: NSPoint) {
        let menu = NSMenu(title: "Column Menu")
        menu.autoenablesItems = false
        
        let insertBefore = NSMenuItem(title: "Insert Column Before", action: #selector(menuInsertColumnBefore(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        insertBefore.keyEquivalentModifierMask = .option
        insertBefore.representedObject = column
        insertBefore.target = self
        menu.addItem(insertBefore)
        
        let insertAfter = NSMenuItem(title: "Insert Column After", action: #selector(menuInsertColumnAfter(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        insertAfter.keyEquivalentModifierMask = .option
        insertAfter.representedObject = column
        insertAfter.target = self
        menu.addItem(insertAfter)
        
        menu.addItem(NSMenuItem.separator())
        
        let sortAsc = NSMenuItem(title: "Sort Ascending", action: #selector(menuSortAscending(_:)), keyEquivalent: "")
        sortAsc.representedObject = column
        sortAsc.target = self
        sortAsc.isEnabled = false
        menu.addItem(sortAsc)
        
        let sortDesc = NSMenuItem(title: "Sort Descending", action: #selector(menuSortDescending(_:)), keyEquivalent: "")
        sortDesc.representedObject = column
        sortDesc.target = self
        sortDesc.isEnabled = false
        menu.addItem(sortDesc)
        
        menu.addItem(NSMenuItem.separator())
        
        let delete = NSMenuItem(title: "Delete Column", action: #selector(menuDeleteColumn(_:)), keyEquivalent: "\u{0008}")
        delete.keyEquivalentModifierMask = .command
        delete.representedObject = column
        delete.target = self
        delete.isEnabled = canDelete
        let deleteTitle = NSAttributedString(string: "Delete Column", attributes: [.foregroundColor: NSColor.systemRed])
        delete.attributedTitle = deleteTitle
        menu.addItem(delete)
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    @objc private func menuInsertColumnBefore(_ sender: NSMenuItem) {
        onTableEditCommand?(.addColumnLeft)
    }
    
    @objc private func menuInsertColumnAfter(_ sender: NSMenuItem) {
        onTableEditCommand?(.addColumnRight)
    }
    
    @objc private func menuSortAscending(_ sender: NSMenuItem) {
        // TODO: Implémenter le tri
    }
    
    @objc private func menuSortDescending(_ sender: NSMenuItem) {
        // TODO: Implémenter le tri
    }
    
    @objc private func menuDeleteColumn(_ sender: NSMenuItem) {
        onTableEditCommand?(.deleteColumn)
    }

    // MARK: - Click handling for links

    /// Plage effective de l'attribut natif `.link` (posé par
    /// `StyleRenderer` à partir de `.mdLink`) sous `point`, ou `nil` si `point`
    /// ne tombe sur aucun lien. Même logique de conversion que
    /// `toggleTaskMarker` : `characterIndexForInsertion`, bornée à
    /// `storage.length - 1`.
    func nativeLinkRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard storage.attribute(.link, at: safeIndex, effectiveRange: &effectiveRange) != nil else { return nil }
        return effectiveRange
    }

    /// Retire l'attribut natif `.link` sur `range` (jamais `.mdLink`, la
    /// source de vérité markdown que `StyleRenderer` laisse intacte) le
    /// temps d'exécuter `body`, puis le restaure. Utilisé pour qu'un simple
    /// clic sur un lien, en mode éditable, traverse `super.mouseDown` comme
    /// un clic de texte ordinaire (voir le commentaire de `mouseDown`)
    /// plutôt que d'être avalé par la reconnaissance de lien native
    /// d'AppKit. Mutation directe du storage hors `beginEditing`/`endEditing`
    /// — même choix qu'`applyTaskToggle`, pour ne déclencher ni
    /// `textDidChange` ni re-sérialisation pour ce qui n'est qu'un attribut
    /// d'affichage transitoire.
    func suspendingNativeLink(in range: NSRange, _ body: () -> Void) {
        guard let storage = textStorage,
              range.location + range.length <= storage.length,
              let value = storage.attribute(.link, at: range.location, effectiveRange: nil)
        else {
            body()
            return
        }
        storage.removeAttribute(.link, range: range)
        body()
        storage.addAttribute(.link, value: value, range: range)
    }

    /// Ouvre un lien externe via le système. `Coordinator`
    /// (`EditorRepresentable.swift`) n'implémente aucune méthode
    /// `NSTextViewDelegate` liée aux liens (`textView(_:clickedOnLink:at:)`),
    /// donc appeler directement `NSWorkspace` ici équivaut à ce que ferait
    /// `super.clicked(onLink:at:)` par défaut pour une valeur `URL` — sans
    /// perdre de comportement délégué. Extrait en propriété injectable pour
    /// que les tests puissent vérifier qu'un lien décliné par `onLinkClick`
    /// atteint bien ce chemin, sans réellement lancer d'application externe
    /// pendant les tests (voir `Tests/EditorTextViewLinkClickTests.swift`).
    var openExternalLink: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Point d'entrée qu'AppKit appelle lui-même dès qu'il reconnaît un clic
    /// sur une plage `.link` (voir le commentaire de `mouseDown` : ceci
    /// couvre aussi bien le mode lecture seule — clic simple — que le
    /// ⌘-clic en mode éditable). Donne d'abord la main à `onLinkClick`
    /// (routage interne, ex. mention `onetoone://collaborator/<uuid>` — voir
    /// `EditorRepresentable.markdownLinks(handler:)`) ; si absent ou décliné
    /// (`false`), retombe sur `openExternalLink` — c'est le chemin normal
    /// pour un lien externe (`https://`, `mailto:`…). Une valeur `link` qui
    /// n'est pas une `URL` retombe directement sur `super`, comportement
    /// natif inchangé (ce chantier ne pose `.link` qu'avec des `URL`, voir
    /// `StyleRenderer`, mais `clicked(onLink:at:)` reste un point d'entrée
    /// public qu'un appelant externe pourrait invoquer avec autre chose).
    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let url = link as? URL else {
            super.clicked(onLink: link, at: charIndex)
            return
        }
        if onLinkClick?(url) == true { return }
        openExternalLink(url)
    }

    /// Bascule l'état d'une case à cocher si `point` (coordonnées de la vue,
    /// mêmes que celles de `mouseDown`) tombe sur son marqueur, et renvoie si
    /// c'était le cas. Lit `.mdListInfo` à la ligne cliquée plutôt que de
    /// comparer des caractères littéraux : le storage ne contient jamais
    /// `"- [ ] "`/`"- [x] "`, seulement le texte affichable (voir
    /// `MarkdownParser`) — comparer ces préfixes, comme le faisait l'ancienne
    /// version de cette méthode, ne pouvait donc jamais matcher sur un
    /// véritable item de tâche.
    ///
    /// La zone cliquable est restreinte à la marge où `MarkdownLayoutManager`
    /// dessine le marqueur — à gauche de `paragraphStyle.firstLineHeadIndent`,
    /// sur la hauteur du fragment de ligne — pour ne pas intercepter un clic
    /// destiné à positionner le curseur dans le texte de l'item. Ne fait rien
    /// en lecture seule (`isEditable == false`) : basculer une case reste une
    /// édition.
    ///
    /// Internal (pas `private`) pour être exercée directement par les tests
    /// sans reconstruire un `NSEvent`/`NSWindow`, sur le modèle de
    /// `insertImagePlaceholder`.
    @discardableResult
    func toggleTaskMarker(at point: NSPoint) -> Bool {
        guard isEditable, let storage = textStorage, storage.length > 0, let layoutManager else { return false }

        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return false }

        let ns = storage.string as NSString
        var lineStart = safeIndex
        while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }

        // Plage du *paragraphe cliqué* uniquement — jamais
        // `longestEffectiveRange` : `ListInfo` est `Hashable`, donc
        // `NSAttributedString` fusionne les runs adjacents de valeur égale.
        // Mesuré : une checklist neuve à trois items décochés ne porte qu'un
        // unique run `.mdListInfo` couvrant les trois lignes ; y lire
        // `longestEffectiveRange` à la 2e ligne renvoyait la plage des
        // *trois*, et écrire dessus cochait les trois d'un seul clic.
        // `NSString.lineRange(for:)` inclut le `\n` terminal, exactement
        // comme `MarkdownParser.emitList` pose `.mdListInfo` sur la plage
        // d'un item (contenu + retour à la ligne) : c'est donc la plage d'un
        // seul item, quel que soit l'état de ses voisins.
        let range = ns.lineRange(for: NSRange(location: lineStart, length: 0))

        guard let info = storage.attribute(.mdListInfo, at: lineStart, effectiveRange: nil) as? ListInfo,
              info.kind == .task else {
            return false
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let paragraphStyle = storage.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle
        let textIndent = paragraphStyle?.firstLineHeadIndent ?? ListMarkerLayout.textIndent(for: info)
        guard containerPoint.x < textIndent else { return false }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard containerPoint.y >= lineFragmentRect.minY, containerPoint.y <= lineFragmentRect.maxY else {
            return false
        }

        let toggled = ListInfo(kind: info.kind, level: info.level, index: info.index, checked: !(info.checked ?? false))
        applyTaskToggle(range: range, from: info, to: toggled)
        return true
    }

    // MARK: - Click handling for mermaid diagrams

    /// Plage du bloc mermaid affiché (diagramme peint, texte source masqué —
    /// voir `MarkdownLayoutManager.drawMermaidDiagrams`) sous `point`
    /// (coordonnées de la vue, mêmes que `toggleTaskMarker`), ou `nil`.
    ///
    /// Ne teste que les blocs actuellement **couverts** par leur diagramme
    /// (curseur ailleurs) : un bloc déjà « ouvert » (curseur dedans) n'a pas
    /// de diagramme peint dessus — `super.mouseDown` s'en charge alors
    /// normalement, positionnement du curseur au pixel cliqué, comme dans
    /// n'importe quel bloc de code ordinaire. Sans cette garde, cliquer pour
    /// repositionner le curseur *pendant* l'édition d'un bloc mermaid le
    /// ramènerait systématiquement à son début.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests, comme `toggleTaskMarker`/`tableControlGesture`.
    func mermaidBlockRange(at point: NSPoint) -> NSRange? {
        closedMermaidPresentation(at: point)?.range
    }

    /// Plage du bloc mermaid dont on a cliqué sur le bouton « Dupliquer »
    /// de la barre d'action visible au survol.
    func mermaidCopyButtonRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return nil }

        guard let blockRange = MermaidBlockLayout.blockRange(in: storage, at: safeIndex),
              !MermaidBlockLayout.selectionTouches(selectedRange().location, blockRange: blockRange),
              blockRange == hoveredBlockRange
        else { return nil }

        guard let attachment = storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment,
              let image = attachment.image
        else { return nil }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let maxWidth = max(container.size.width - firstLineRect.minX, 0)
        let drawSize = MermaidBlockLayout.fittedSize(for: image.size, maxWidth: maxWidth)
        guard drawSize.width > 0, drawSize.height > 0 else { return nil }
        let drawnRect = NSRect(x: firstLineRect.minX, y: firstLineRect.minY, width: drawSize.width, height: drawSize.height)

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        guard drawnRect.contains(containerPoint) else { return nil }

        let geo = MermaidBlockLayout.actionBarGeometry(forDrawnRect: drawnRect)
        guard geo.copyButtonRect.contains(containerPoint) else { return nil }

        return blockRange
    }

    /// Plage du bloc mermaid **fermé en erreur** (cadre teinté, voir
    /// `MermaidAttachmentFactory.frameImage`) dont le bouton « Ouvrir le
    /// source » est sous `point`, ou `nil`. Un clic n'importe où sur un bloc
    /// fermé ouvre déjà le source (`mermaidBlockRange`, appelé juste après
    /// dans `mouseDown` si celle-ci renvoie `nil`) : ce hit-test dédié ne
    /// change donc pas le geste final, mais le borne précisément à la
    /// pastille peinte plutôt qu'à toute la zone où l'image est dessinée —
    /// même schéma que `mermaidDoneButtonRange`, un calcul de géométrie
    /// partagé avec le dessin (`MermaidBlockLayout.errorActionButtonRect`),
    /// jamais deux qui pourraient diverger.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests, comme `mermaidBlockRange`/`mermaidDoneButtonRange`.
    func mermaidErrorActionButtonRange(at point: NSPoint) -> NSRange? {
        guard let hit = closedMermaidPresentation(at: point),
              let localPoint = MermaidBlockLayout.imageLocalPoint(
                fromContainerPoint: hit.containerPoint,
                drawnRect: hit.drawnRect,
                imageSize: hit.image.size
              )
        else { return nil }

        let labelSize = (MermaidBlockLayout.errorActionLabel as NSString).size(withAttributes: [.font: MermaidBlockLayout.errorActionFont])
        let buttonRect = MermaidBlockLayout.errorActionButtonRect(labelSize: labelSize)
        guard buttonRect.contains(localPoint) else { return nil }

        return hit.range
    }

    /// Résout un clic contre les rectangles réellement peints des diagrammes
    /// fermés, au lieu de demander à TextKit quel caractère se trouve sous le
    /// point. Le dessin Mermaid déborde volontairement du glyphe de sa
    /// première ligne ; dans la partie basse d'un grand cadre d'erreur,
    /// `characterIndexForInsertion(at:)` peut donc désigner la ligne suivante
    /// ou le bloc voisin et rendre le bouton visuel impossible à cliquer.
    private func closedMermaidPresentation(at point: NSPoint) -> (
        range: NSRange, image: NSImage, drawnRect: NSRect, containerPoint: NSPoint
    )? {
        guard let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let selectedLocation = selectedRange().location
        var visitedStarts = Set<Int>()
        var result: (range: NSRange, image: NSImage, drawnRect: NSRect, containerPoint: NSPoint)?

        storage.enumerateAttribute(
            .mdMermaidAttachment,
            in: NSRange(location: 0, length: storage.length)
        ) { value, attributeRange, stop in
            guard value != nil,
                  let blockRange = MermaidBlockLayout.blockRange(in: storage, at: attributeRange.location),
                  visitedStarts.insert(blockRange.location).inserted,
                  !MermaidBlockLayout.selectionTouches(selectedLocation, blockRange: blockRange),
                  let attachment = storage.attribute(
                    .mdMermaidAttachment, at: blockRange.location, effectiveRange: nil
                  ) as? NSTextAttachment,
                  let image = attachment.image
            else { return }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
            let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let maxWidth = max(container.size.width - firstLineRect.minX, 0)
            let drawSize = MermaidBlockLayout.fittedSize(for: image.size, maxWidth: maxWidth)
            guard drawSize.width > 0, drawSize.height > 0 else { return }

            let drawnRect = NSRect(
                x: firstLineRect.minX, y: firstLineRect.minY,
                width: drawSize.width, height: drawSize.height
            )
            guard drawnRect.contains(containerPoint) else { return }

            result = (blockRange, image, drawnRect, containerPoint)
            stop.pointee = true
        }
        return result
    }

    /// Invalide immédiatement puis au prochain tour de boucle AppKit les
    /// pixels d'un changement aperçu/source. Le second passage est requis :
    /// les images Mermaid sont peintes hors de l'emprise stricte des glyphes,
    /// tandis que TextKit recalcule leur géométrie pendant la notification de
    /// sélection. Une invalidation uniquement synchrone peut être consommée
    /// avant la fin de ce recalcul et laisser l'ancien cadre au-dessus du
    /// source désormais ouvert.
    func invalidateMermaidPresentation(for blockRanges: [NSRange]) {
        let invalidate = { [weak self] in
            guard let self else { return }
            if let storage = self.textStorage, let layoutManager = self.layoutManager {
                for range in blockRanges {
                    let lower = min(max(0, range.location), storage.length)
                    let upper = min(max(lower, NSMaxRange(range)), storage.length)
                    guard upper > lower else { continue }
                    layoutManager.invalidateDisplay(
                        forCharacterRange: NSRange(location: lower, length: upper - lower)
                    )
                }
            }
            self.setNeedsDisplay(self.bounds)
        }

        invalidate()
        DispatchQueue.main.async(execute: invalidate)
    }

    /// Plage du bloc mermaid **ouvert** (curseur dedans, source affiché —
    /// voir `MarkdownLayoutManager.drawMermaidHeader`) dont le bouton
    /// « Terminé » est sous `point`, ou `nil`. Dérivé du **curseur**
    /// (`selectedRange().location`), pas du point cliqué : le bouton n'est
    /// peint que pour le bloc du curseur, même schéma que
    /// `tableControlGesture` — un seul calcul de géométrie
    /// (`MermaidSourceLayout.doneButtonRect`) partagé avec le dessin, jamais
    /// deux qui pourraient diverger.
    func mermaidDoneButtonRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }
        guard let blockRange = MermaidBlockLayout.openBlockRange(
            in: storage, selection: selectedRange().location
        ) else { return nil }

        // Mêmes deux calculs que le dessin
        // (`MarkdownLayoutManager.drawMermaidHeader`) : les bornes du **texte**
        // du bloc (`MermaidSourceLayout.textBounds`, jamais les rects de
        // fragment — voir `SourceTextBounds`) et la hauteur de la bande
        // d'aperçu, qui remonte l'en-tête donc le bouton. Une divergence sur
        // l'un ou l'autre rendrait « Terminé » incliquable.
        let textBounds = MermaidSourceLayout.textBounds(
            forBlockRange: blockRange, layoutManager: layoutManager
        )
        let previewHeight = MermaidSourceLayout.previewHeight(
            in: storage, blockRange: blockRange, containerWidth: container.size.width
        )
        let buttonRect = MermaidSourceLayout.doneButtonRect(
            above: textBounds, containerWidth: container.size.width, previewHeight: previewHeight
        )

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        guard buttonRect.contains(containerPoint) else { return nil }
        return blockRange
    }



    /// Bascule effectivement `.mdListInfo` sur `range`, de `oldInfo` vers
    /// `newInfo` : mute l'attribut, restyle, notifie `onTaskToggle`, et
    /// enregistre l'inverse auprès de `undoManager`.
    ///
    /// N'utilise pas `shouldChangeText(in:replacementString:)`/
    /// `didChangeText()` : ce chemin redéclencherait tout
    /// `Coordinator.textDidChange` (raccourcis markdown, sérialisation,
    /// poussée *débouncée* vers le binding), qui ferait double emploi avec la
    /// poussée *immédiate* que fait déjà `onTaskToggle` — et la débouncée,
    /// planifiée après coup, absorberait l'avantage recherché (persistance
    /// immédiate d'un clic de case à cocher, cf. doc d'`onTaskToggle` dans
    /// `EditorRepresentable`).
    ///
    /// `applyTaskToggle` réenregistre son propre inverse à chaque exécution —
    /// bascule initiale, annulation ou rétablissement — ce qui fait
    /// fonctionner ⌘Z et ⇧⌘Z symétriquement sans code dédié à chacun. Sans
    /// cet enregistrement, une bascule mutait `textStorage` sans passer par
    /// aucun mécanisme d'undo : ⌘Z n'avait alors aucun effet sur elle et
    /// annulait à la place la dernière édition de texte réelle, sans rapport
    /// (vérifié dans une fenêtre réelle : frapper du texte, basculer une
    /// case, ⌘Z annulait la frappe et laissait la case cochée).
    private func applyTaskToggle(range: NSRange, from oldInfo: ListInfo, to newInfo: ListInfo) {
        guard let storage = textStorage, range.location + range.length <= storage.length else { return }
        storage.addAttribute(.mdListInfo, value: newInfo, range: range)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: range)
        onTaskToggle?(range, newInfo.checked ?? true)
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyTaskToggle(range: range, from: newInfo, to: oldInfo)
        }
    }
}

extension EditorTextView {
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
    
    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedBlockRange = nil
        dropTarget = nil
    }
}

extension EditorTextView {
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType("OneToOne.BlockDragType")]) != nil else {
            return super.draggingEntered(sender)
        }
        updateDropTarget(for: sender)
        return .move
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType("OneToOne.BlockDragType")]) != nil else {
            return super.draggingUpdated(sender)
        }
        updateDropTarget(for: sender)
        return .move
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if sender?.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType("OneToOne.BlockDragType")]) != nil {
            dropTarget = nil
        } else {
            super.draggingExited(sender)
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard sender.draggingPasteboard.availableType(from: [NSPasteboard.PasteboardType("OneToOne.BlockDragType")]) != nil,
              let dropTarget = self.dropTarget,
              let draggedRange = self.draggedBlockRange,
              let storage = textStorage else {
            return super.performDragOperation(sender)
        }
        
        self.dropTarget = nil
        self.draggedBlockRange = nil
        
        let fromLocation = draggedRange.location
        let fromLength = draggedRange.length
        let toIndex = dropTarget.index

        let afterContent = fromLocation + fromLength
        let separatorLength: Int
        if afterContent < storage.length, (storage.string as NSString).character(at: afterContent) == 0x0A {
            separatorLength = 1
        } else {
            separatorLength = 0
        }

        let minLoc = min(fromLocation, toIndex)
        let maxLoc = max(afterContent + separatorLength, toIndex)
        let combinedRange = NSRange(location: minLoc, length: maxLoc - minLoc)

        // `dragRewrite` renvoie `nil` pour un dépôt dans la plage déplacée
        // elle-même : geste sans effet.
        guard let rewrite = BlockMoveCommands.dragRewrite(
            combined: storage.attributedSubstring(from: combinedRange),
            blockRange: NSRange(location: fromLocation - minLoc, length: fromLength),
            insertionIndex: toIndex - minLoc
        ) else { return true }

        if replaceBlockCharactersRegisteringUndo(in: combinedRange, with: rewrite.text) {
            let newLocation = minLoc + rewrite.blockLocation
            selectedBlockRange = NSRange(location: newLocation, length: fromLength)
            setSelectedRange(NSRange(location: newLocation, length: 0))
        }
        return true
    }
    
    private func updateDropTarget(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        guard let storage = textStorage, let manager = layoutManager as? MarkdownLayoutManager else { return }
        
        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return }
        
        guard let targetBlock = blockRange(at: point) else { return }
        
        let glyphIndex = manager.glyphIndexForCharacter(at: targetBlock.location)
        let firstLineRect = manager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        
        let lastCharIndex = targetBlock.location + targetBlock.length
        let lastGlyphIndex = manager.glyphIndexForCharacter(at: lastCharIndex > 0 ? lastCharIndex - 1 : 0)
        let lastLineRect = manager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
        
        let blockMinY = firstLineRect.minY + textContainerOrigin.y
        let blockMaxY = lastLineRect.maxY + textContainerOrigin.y
        let blockMidY = (blockMinY + blockMaxY) / 2
        
        let insertBefore = point.y < blockMidY
        
        let index = insertBefore ? targetBlock.location : min(targetBlock.location + targetBlock.length + 1, storage.length)
        let y = insertBefore ? blockMinY : blockMaxY
        
        dropTarget = DropTarget(index: index, y: y)
    }
}
