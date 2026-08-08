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
