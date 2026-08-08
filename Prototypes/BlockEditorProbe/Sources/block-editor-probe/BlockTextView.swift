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
}
