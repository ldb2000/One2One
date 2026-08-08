import AppKit
import ProbeCore

/// Toute l'autorité de la sonde.
///
/// Les `NSTextView` ne décident de rien : ils reflètent. C'est l'inverse exact
/// de l'éditeur actuel, où la vue porte la logique — et c'est l'hypothèse que
/// ce prototype teste.
@MainActor
final class SelectionCoordinator: NSObject, NSTextViewDelegate {

    private(set) var document: ProbeDocument
    private(set) var selection: ProbeSelection

    let history = ProbeHistory()
    private(set) weak var stack: BlockStackView?

    /// Vrai pendant que le coordinateur écrit dans les vues : empêche les
    /// rappels d'AppKit de réécrire l'état qu'on est en train de poser.
    ///
    /// `BlockStackView.reload(document:)` écrit directement `.string` sur les
    /// vues, **hors** de `synchroniseViews` : `attach`/`apply` doivent donc
    /// lever la garde avant `reload`, et `synchroniseViews` doit pouvoir
    /// s'imbriquer dedans sans la lever prématurément à sa sortie — d'où une
    /// garde **ré-entrante** (sauvegarde/restauration de la valeur
    /// précédente) plutôt qu'un `false` en dur.
    private var isSynchronising = false

    /// Exécute `body` avec la garde levée, en restaurant sa valeur
    /// précédente en sortie — y compris quand `body` lève elle-même la garde
    /// (cas de `synchroniseViews` appelée depuis `attach`/`apply`).
    private func whileSynchronising(_ body: () -> Void) {
        let previous = isSynchronising
        isSynchronising = true
        defer { isSynchronising = previous }
        body()
    }

    init(document: ProbeDocument) {
        self.document = document
        self.selection = ProbeSelection(caret: document.startPosition)
        super.init()
    }

    func attach(stack: BlockStackView) {
        self.stack = stack
        whileSynchronising {
            stack.reload(document: document)
            synchroniseViews(focusing: true)
        }
    }

    // MARK: - Application d'une mutation

    /// Applique une mutation structurante : enregistre l'état précédent,
    /// mute le document, reconstruit la pile, replace le curseur.
    func apply(_ mutation: (inout ProbeDocument) -> ProbePosition) {
        history.record(ProbeSnapshot(document: document, selection: selection))
        let caret = mutation(&document)
        selection = ProbeSelection(caret: document.clamped(caret))
        whileSynchronising {
            stack?.reload(document: document)
            synchroniseViews(focusing: true)
        }
    }

    /// Pose une nouvelle sélection sans toucher au document.
    func setSelection(_ newSelection: ProbeSelection, focusing: Bool = true) {
        selection = ProbeSelection(anchor: document.clamped(newSelection.anchor),
                                   head: document.clamped(newSelection.head))
        synchroniseViews(focusing: focusing)
    }

    // MARK: - Reflet dans les vues

    /// Répartit la sélection sur les vues : surlignage natif pour le bloc
    /// focalisé, surlignage peint pour les autres.
    func synchroniseViews(focusing: Bool) {
        guard let stack else { return }
        whileSynchronising {
            let ranges = SelectionDistribution.ranges(for: selection, in: document)
            let focused = selection.head.blockIndex
            let focusedView = stack.view(at: focused)

            // Le premier répondant est repris **avant** de poser les plages :
            // `makeFirstResponder` fait reprendre à `NSTextView` sa propre
            // sélection et écraserait celle qu'on vient d'écrire.
            if focusing, let focusedView, focusedView.window?.firstResponder !== focusedView {
                focusedView.window?.makeFirstResponder(focusedView)
            }

            for (index, view) in stack.orderedViews.enumerated() {
                let range = ranges[index]
                if index == focused {
                    view.crossBlockSelection = nil
                    view.setSelectedRange(range ?? NSRange(location: selection.head.offset, length: 0))
                } else {
                    view.crossBlockSelection = range
                    // Sélection native vide : sinon `NSTextView` peindrait sa
                    // propre bande grise d'inactivité sous le surlignage qu'on
                    // peint nous-mêmes.
                    view.setSelectedRange(NSRange(location: range?.location ?? 0, length: 0))
                }
            }

            if focusing, let focusedView {
                focusedView.scrollToVisible(focusedView.bounds)
            }
        }
    }

    // MARK: - Mécanisme 1 : sélection traversante

    /// Pose l'ancre au clic, puis suit le glissement **au niveau du
    /// conteneur** : c'est le seul endroit qui voit tous les blocs à la fois.
    func beginSelectionDrag(from view: BlockTextView, event: NSEvent) {
        guard let stack, let window = view.window else { return }

        let anchor = position(ofWindowPoint: event.locationInWindow, in: stack)
        setSelection(ProbeSelection(caret: anchor))

        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp],
                           timeout: NSEvent.foreverDuration,
                           mode: .eventTracking) { tracked, stop in
            guard let tracked else {
                stop.pointee = true
                return
            }
            if tracked.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let head = self.position(ofWindowPoint: tracked.locationInWindow, in: stack)
            // `focusing: false` : reprendre le premier répondant à chaque
            // mouvement casserait le suivi du glissement.
            self.setSelection(ProbeSelection(anchor: self.selection.anchor, head: head),
                              focusing: false)
        }

        // Le focus n'est repris qu'au relâchement, sur le bloc de la tête.
        synchroniseViews(focusing: true)
    }

    /// Traduit un point de la fenêtre en position du document, en débordant
    /// proprement au-dessus du premier bloc et sous le dernier.
    private func position(ofWindowPoint point: NSPoint, in stack: BlockStackView) -> ProbePosition {
        let inStack = stack.convert(point, from: nil)
        guard let index = stack.blockIndex(atContentPoint: inStack),
              let view = stack.view(at: index) else {
            return document.clamped(selection.head)
        }
        let inView = view.convert(point, from: nil)
        let clampedPoint = NSPoint(x: inView.x,
                                   y: min(max(inView.y, 0), max(view.bounds.height - 1, 0)))
        return ProbePosition(blockIndex: index, offset: view.probeOffset(atViewPoint: clampedPoint))
    }

    /// ⌘A prend tout le document, pas seulement le bloc focalisé.
    func selectAllBlocks() {
        setSelection(document.wholeDocument)
    }

    // MARK: - Commandes clavier

    /// Ne reprend la main que lorsque `NSTextView` ne peut pas s'en sortir
    /// seul : au franchissement d'une frontière de bloc, ou dès que la
    /// sélection en déborde déjà.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let view = textView as? BlockTextView else { return false }

        switch selector {
        case #selector(NSResponder.selectAll(_:)):
            selectAllBlocks()
            return true

        case #selector(NSResponder.moveRightAndModifySelection(_:)),
             #selector(NSResponder.moveForwardAndModifySelection(_:)):
            return extendSelection(to: document.position(after: selection.head),
                                   whenNativeWouldSuffice: !selection.spansBlocks
                                       && selection.head.offset < document.blocks[selection.head.blockIndex].length)

        case #selector(NSResponder.moveLeftAndModifySelection(_:)),
             #selector(NSResponder.moveBackwardAndModifySelection(_:)):
            return extendSelection(to: document.position(before: selection.head),
                                   whenNativeWouldSuffice: !selection.spansBlocks
                                       && selection.head.offset > 0)

        // Limite assumée (prototype) : l'extension verticale saute au bloc
        // entier suivant/précédent dès que la sélection déborde déjà, sans
        // vérifier que la tête est réellement sur la dernière/première ligne
        // du bloc courant — sur un bloc multi-lignes, cela peut sauter des
        // lignes intermédiaires. L'extension horizontale ⇧←/⇧→, elle, reste
        // précise caractère par caractère.
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            guard selection.spansBlocks || view.isOnLastLine(offset: selection.head.offset) else { return false }
            // Garde de borne symétrique de `moveUp` : pas de bloc suivant,
            // on rend la main plutôt que de clamper sur le bloc courant (ce
            // qui ferait sauter la tête en arrière et inverserait la sélection).
            guard selection.head.blockIndex + 1 < document.blocks.count else { return false }
            let next = selection.head.blockIndex + 1
            setSelection(ProbeSelection(anchor: selection.anchor,
                                        head: ProbePosition(blockIndex: next, offset: 0)))
            return true

        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            guard selection.spansBlocks || view.isOnFirstLine(offset: selection.head.offset) else { return false }
            guard selection.head.blockIndex > 0 else { return false }
            let previous = selection.head.blockIndex - 1
            setSelection(ProbeSelection(
                anchor: selection.anchor,
                head: ProbePosition(blockIndex: previous, offset: document.blocks[previous].length)))
            return true

        case #selector(NSResponder.insertNewline(_:)):
            apply { ProbeEditing.insertNewline(in: &$0, selection: self.selection) }
            return true

        case #selector(NSResponder.deleteBackward(_:)):
            // `NSTextView` sait très bien effacer à l'intérieur d'un bloc, et
            // le faire nativement préserve la composition en cours (touches
            // mortes). On ne reprend la main qu'en tête de bloc, ou dès que la
            // sélection déborde.
            guard selection.spansBlocks || (selection.isCollapsed && selection.head.offset == 0) else {
                return false
            }
            apply { ProbeEditing.deleteBackward(in: &$0, selection: self.selection) }
            return true

        case #selector(NSResponder.deleteForward(_:)):
            let atBlockEnd = selection.isCollapsed
                && selection.head.offset == document.blocks[selection.head.blockIndex].length
            guard selection.spansBlocks || atBlockEnd else { return false }
            apply { ProbeEditing.deleteForward(in: &$0, selection: self.selection) }
            return true

        default:
            return false
        }
    }

    /// Étend la sélection vers `head`. Rend la main à `NSTextView` quand le
    /// mouvement reste dans un bloc : c'est lui qui connaît le mieux ses
    /// propres lignes.
    private func extendSelection(to head: ProbePosition, whenNativeWouldSuffice native: Bool) -> Bool {
        guard !native else { return false }
        setSelection(ProbeSelection(anchor: selection.anchor, head: head))
        return true
    }

    // MARK: - Mécanisme 2 : édition destructive

    /// Arbitre entre la voie native et la voie du modèle.
    ///
    /// Voie native (retour `true`) : la sélection tient dans un bloc. Le
    /// `NSTextView` fait son travail — accents, touches mortes, correcteur —
    /// et `textDidChange` recopiera le résultat dans le modèle.
    ///
    /// Voie du modèle (retour `false`) : la sélection déborde du bloc. Aucun
    /// `NSTextView` ne peut l'honorer ; le coordinateur applique la mutation
    /// et reconstruit.
    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedRange: NSRange,
                  replacementString: String?) -> Bool {
        guard selection.spansBlocks else {
            // Voie native, mais l'historique doit quand même voir l'état
            // d'avant : l'undo est unifié au niveau du conteneur.
            history.record(ProbeSnapshot(document: document, selection: selection))
            return true
        }
        let inserted = replacementString ?? ""
        apply { ProbeEditing.insertText(inserted, in: &$0, selection: self.selection) }
        return false
    }

    // MARK: - NSTextViewDelegate

    /// La frappe simple reste **native** : c'est ce qui donne gratuitement les
    /// accents, les touches mortes, le correcteur et les services. Le
    /// coordinateur recopie ensuite le résultat dans le modèle.
    func textDidChange(_ notification: Notification) {
        guard !isSynchronising,
              let view = notification.object as? BlockTextView else { return }
        document.setText(view.string, at: view.blockIndex)
        stack?.needsLayout = true
        stack?.layoutSubtreeIfNeeded()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSynchronising,
              let view = notification.object as? BlockTextView else { return }
        let range = view.selectedRange()
        selection = ProbeSelection(
            anchor: ProbePosition(blockIndex: view.blockIndex, offset: range.location),
            head: ProbePosition(blockIndex: view.blockIndex, offset: NSMaxRange(range)))
    }
}
