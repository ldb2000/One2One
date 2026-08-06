import AppKit

/// Géométrie du rendu d'un bloc mermaid **ouvert** (curseur dedans, source
/// affiché en édition) — l'état inverse de `MermaidBlockLayout` (bloc
/// fermé, diagramme peint). Interligne normal, gouttière de numéros de
/// ligne, bande d'en-tête discrète (« mermaid » + bouton « Terminé ») —
/// exactement l'état 3 du chantier : plus aucune trace de l'ancienne
/// réservation `220pt / lineCount` (110pt la ligne pour un bloc de deux
/// lignes) qui s'appliquait jusque-là même pendant l'édition.
///
/// Même patron que `TableControlLayout`/`ListMarkerLayout` : constantes +
/// fonctions pures, testables sans vue vivante, un seul calcul de géométrie
/// partagé entre le dessin (`MarkdownLayoutManager`) et le hit-test
/// (`EditorTextView.mermaidDoneButtonRange`).
enum MermaidSourceLayout {

    /// Interligne d'un bloc mermaid en édition — remplace la réservation par
    /// bloc entier de l'état fermé : chaque ligne garde un rendu de code
    /// normal, juste plus aéré que l'interligne compact par défaut (1.0)
    /// pour rester lisible à côté de la gouttière de numéros.
    static let lineHeightMultiple: CGFloat = 1.55

    /// Largeur réservée à gauche pour les numéros de ligne — posée comme
    /// `headIndent`/`firstLineHeadIndent` par `StyleRenderer`, peinte dans la
    /// marge ainsi libérée par `MarkdownLayoutManager.drawMermaidLineNumber`
    /// (même mécanisme que `ListMarkerLayout.textIndent`).
    static let gutterWidth: CGFloat = 28

    /// Hauteur de la bande d'en-tête (« mermaid » + bouton Terminé), réservée
    /// au-dessus de la première ligne du bloc via
    /// `NSParagraphStyle.paragraphSpacingBefore`.
    static let headerHeight: CGFloat = 26

    static let gutterColor = NSColor.tertiaryLabelColor
    static let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    static let headerLabelColor = NSColor.secondaryLabelColor
    static let headerLabelFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)

    static let doneButtonFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    static let doneButtonWidth: CGFloat = 62
    static let doneButtonHeight: CGFloat = 20
    /// Marge entre le bouton « Terminé » et le bord droit du conteneur.
    static let doneButtonTrailingMargin: CGFloat = 4

    /// Rectangle du bouton « Terminé », en coordonnées **conteneur** (mêmes
    /// conventions que `TableControlLayout.Placement` : sans le décalage
    /// `origin`/`textContainerInset` qu'ajoute chaque appelant) — dans la
    /// bande d'en-tête au-dessus de `firstLineRect`, aligné à droite.
    static func doneButtonRect(above firstLineRect: NSRect, containerWidth: CGFloat) -> NSRect {
        let y = firstLineRect.minY - headerHeight + (headerHeight - doneButtonHeight) / 2
        let x = containerWidth - doneButtonWidth - doneButtonTrailingMargin
        return NSRect(x: x, y: y, width: doneButtonWidth, height: doneButtonHeight)
    }

    /// Rectangle de la bande d'en-tête elle-même (fond/label « mermaid »),
    /// au-dessus de `firstLineRect`, sur toute la largeur du conteneur.
    static func headerRect(above firstLineRect: NSRect, containerWidth: CGFloat) -> NSRect {
        NSRect(
            x: 0,
            y: firstLineRect.minY - headerHeight,
            width: containerWidth,
            height: headerHeight
        )
    }

    /// Origine (coordonnées conteneur) du numéro de ligne `index` (0-based
    /// dans le bloc), aligné à droite dans la gouttière, centré verticalement
    /// sur `lineRect`.
    static func lineNumberOrigin(lineRect: NSRect, numberSize: NSSize) -> NSPoint {
        NSPoint(
            x: gutterWidth - 6 - numberSize.width,
            y: lineRect.minY + (lineRect.height - numberSize.height) / 2
        )
    }
}
