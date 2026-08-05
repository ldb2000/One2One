import AppKit

/// Constantes d'apparence d'un tableau GFM rendu en grille `NSTextTable` —
/// mêmes bordures/couleurs quel que soit le tableau, pas de configuration
/// par colonne au-delà de l'alignement. Miroir de `ListMarkerLayout`/
/// `BlockquoteRuleLayout` : constantes pures, testables sans vue vivante.
/// Voir `StyleRenderer.applyVisualStyle` pour la construction effective du
/// `NSTextTable`/`NSTextTableBlock` à partir de ces valeurs.
enum TableLayout {

    /// Couleur des bordures de cellule. `separatorColor` est la couleur
    /// sémantique système pour un filet de séparation — dynamique
    /// clair/sombre, comme les autres couleurs de ce module
    /// (`ListMarkerLayout.markerColor`, `BlockquoteRuleLayout.ruleColor`).
    static let borderColor = NSColor.separatorColor

    /// Épaisseur de bordure, en points — un filet fin, pas un trait épais.
    static let borderWidth: CGFloat = 1

    /// Marge interne d'une cellule, en points, entre la bordure et son
    /// texte — évite que le texte touche le filet.
    static let cellPadding: CGFloat = 6

    /// Fond de la rangée d'en-tête (row 0) — juste assez de contraste pour
    /// la distinguer du corps sans dominer le texte.
    static let headerBackgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)

    /// Traduit l'alignement GFM (`TableCellInfo.Alignment?`, où `nil` = pas
    /// de `:` dans le séparateur source) en alignement de paragraphe visuel.
    /// `nil` et `.left` rendent identiquement (`.left`) : la distinction
    /// entre les deux n'a de sens qu'à la sérialisation (réémettre `---` vs
    /// `:---`), pas à l'affichage.
    static func textAlignment(for alignment: TableCellInfo.Alignment?) -> NSTextAlignment {
        switch alignment {
        case .none, .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
