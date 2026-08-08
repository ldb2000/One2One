import AppKit
import ProbeCore

/// Un bloc = un `NSTextView`.
///
/// Cette vue ne décide de rien : elle reflète ce que le coordinateur lui dit.
/// Elle garde en revanche la **saisie native** — accents, touches mortes,
/// correcteur, services macOS — qui est la raison d'être du choix
/// « un `NSTextView` par bloc » plutôt qu'un moteur de saisie maison.
final class BlockTextView: NSTextView {

    /// Index du bloc dans le document, réaffecté à chaque `reload`.
    var blockIndex: Int = 0

    /// Autorité unique. `unowned` volontaire : le coordinateur possède la pile
    /// qui possède ces vues.
    unowned let owner: SelectionCoordinator

    /// Part de la sélection traversante à peindre **quand ce bloc n'a pas le
    /// focus**. Nil pour le bloc focalisé, qui garde le surlignage natif.
    var crossBlockSelection: NSRange? {
        didSet {
            guard crossBlockSelection != oldValue else { return }
            needsDisplay = true
        }
    }

    init(owner: SelectionCoordinator) {
        self.owner = owner

        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        // La largeur est pilotée à la main par `BlockStackView` : pas d'Auto
        // Layout, pour ne pas confondre le coût des vues avec celui du moteur
        // de contraintes lors de la mesure à 200 blocs.
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0

        super.init(frame: .zero, textContainer: container)

        isRichText = false
        isEditable = true
        isSelectable = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        drawsBackground = false
        textContainerInset = NSSize(width: 0, height: 3)
        font = NSFont.systemFont(ofSize: 14)
        // L'undo est unifié au niveau du conteneur : voir `ProbeHistory`.
        allowsUndo = false
        delegate = owner
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    // MARK: - Mesure

    /// Hauteur nécessaire pour afficher tout le texte à cette largeur.
    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 22 }
        let contentWidth = max(width - textContainerInset.width * 2, 1)
        if abs(container.size.width - contentWidth) > 0.5 {
            container.size = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        return max(ceil(used), 18) + textContainerInset.height * 2
    }

    // MARK: - Surlignage d'un bloc sans focus

    /// Peint la part de sélection traversante de ce bloc.
    ///
    /// `NSTextView` grise sa propre sélection dès qu'il perd le focus, or un
    /// seul bloc peut l'avoir. On peint donc le surlignage nous-mêmes pour les
    /// autres, à partir des rects du gestionnaire de disposition. Ce n'est
    /// **pas** réécrire le dessin du texte : on ne fait qu'ajouter un fond.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let range = crossBlockSelection, range.length > 0,
              let manager = layoutManager, let container = textContainer else { return }

        NSColor.selectedTextBackgroundColor.setFill()
        let origin = textContainerOrigin
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        manager.enumerateEnclosingRects(forGlyphRange: glyphs,
                                        withinSelectedGlyphRange: glyphs,
                                        in: container) { painted, _ in
            painted.offsetBy(dx: origin.x, dy: origin.y).fill()
        }
    }

    // MARK: - Souris

    /// Le clic ne pose pas la sélection lui-même : il la demande au
    /// coordinateur, qui seul sait ce qu'est une sélection traversante.
    ///
    /// Limite assumée (prototype) : `super` n'est pas appelé et
    /// `event.clickCount` / `event.modifierFlags` sont ignorés — le
    /// double-clic (mot), le triple-clic (paragraphe) et le clic-⇧
    /// (extension) sont donc perdus. Le clic simple de positionnement reste
    /// correct : `characterIndexForInsertion` est la même primitive que
    /// celle qu'utiliserait `NSTextView` en interne.
    override func mouseDown(with event: NSEvent) {
        owner.beginSelectionDrag(from: self, event: event)
    }

    /// Position du document sous un point exprimé dans les coordonnées de
    /// cette vue.
    func probeOffset(atViewPoint point: NSPoint) -> Int {
        characterIndexForInsertion(at: point)
    }

    // MARK: - Lignes

    /// Vrai si le décalage tombe sur le dernier fragment de ligne du bloc.
    /// Sert à savoir quand ↓ doit franchir la frontière de bloc.
    func isOnLastLine(offset: Int) -> Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var lineRange = NSRange()
        let glyph = min(manager.glyphIndexForCharacter(at: offset), manager.numberOfGlyphs - 1)
        manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        return NSMaxRange(lineRange) >= manager.numberOfGlyphs
    }

    /// Symétrique : vrai sur le premier fragment de ligne du bloc.
    func isOnFirstLine(offset: Int) -> Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var lineRange = NSRange()
        let glyph = min(manager.glyphIndexForCharacter(at: offset), manager.numberOfGlyphs - 1)
        manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        return lineRange.location == 0
    }

    override func selectAll(_ sender: Any?) {
        owner.selectAllBlocks()
    }

    // MARK: - Actions déléguées au coordinateur

    /// `NSTextView` implémente `copy:`/`cut:`/`paste:` (protocole `NSText`)
    /// et, premier répondant, les capterait avant le coordinateur.
    override func copy(_ sender: Any?) {
        owner.copySelection()
    }

    override func cut(_ sender: Any?) {
        owner.cutSelection()
    }

    override func paste(_ sender: Any?) {
        owner.pasteFromPasteboard()
    }

    /// `undo:` et `redo:` n'existent pas sur `NSResponder` : les déclarer ici
    /// met le premier répondant sur leur chemin, avant tout `UndoManager`
    /// que la fenêtre pourrait fournir.
    @objc func undo(_ sender: Any?) {
        owner.undoLastEdit()
    }

    @objc func redo(_ sender: Any?) {
        owner.redoLastEdit()
    }

    // MARK: - Validation des items de menu / raccourcis clavier

    /// `NSTextView.validateUserInterfaceItem` désactive nativement
    /// `copy:`/`cut:` d'après sa **propre** `selectedRange()` — la part de
    /// sélection qui vit dans ce seul bloc. Or sur une sélection traversante
    /// née au clavier, la tête peut tomber en offset 0 du bloc suivant ou en
    /// fin du bloc précédent : la plage locale du bloc focalisé est alors
    /// vide (longueur 0) bien que la sélection globale, portée par
    /// `owner.selection`, ne le soit pas. Le natif désactiverait donc
    /// `copy:`/`cut:` — et un item de menu désactivé ne répond plus à son
    /// raccourci clavier, ce qui rend ⌘C/⌘X muets. Piège masqué par ⌘A, qui
    /// n'est pas concerné par cette validation et fonctionne toujours : la
    /// seule autorité correcte ici est la sélection du coordinateur.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return !owner.selection.isCollapsed
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
