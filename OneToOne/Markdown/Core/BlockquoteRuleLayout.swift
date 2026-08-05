import AppKit

/// Géométrie et couleur du filet vertical dessiné dans la marge gauche d'une
/// citation (`> texte`) — jamais écrit dans le storage, voir
/// `MarkdownLayoutManager` pour le dessin proprement dit. Constantes pures,
/// testables sans vue vivante. Miroir de `ListMarkerLayout`, pour le même
/// besoin côté citations plutôt que côté items de liste.
enum BlockquoteRuleLayout {

    /// Indentation du texte d'une citation, en points — réserve la marge où
    /// `MarkdownLayoutManager` dessine le filet, appliquée par
    /// `StyleRenderer.applyVisualStyle` sur `headIndent`/`firstLineHeadIndent`
    /// exactement comme `ListMarkerLayout.textIndent(for:)` le fait pour un
    /// item de liste. `BlockType` est un enum plat (pas de `level` comme
    /// `ListInfo`) : ce module ne modélise pas l'imbrication de citations,
    /// donc une seule valeur fixe, pas de progression par niveau.
    static let textIndent: CGFloat = 16

    /// Largeur du filet, en points — un trait plein de quelques points,
    /// pas une ligne fine à 1pt.
    static let ruleThickness: CGFloat = 3

    /// Espace, en points, laissé entre le bord gauche du conteneur et le
    /// filet — celui-ci ne colle pas à `x = 0`.
    static let ruleLeadingGap: CGFloat = 2

    /// Couleur du filet. Avant ce chantier, une citation était rendue en
    /// texte gris (`NSColor.secondaryLabelColor`) et légèrement penché
    /// (`obliqueness`) — `StyleRenderer` ne pose plus ni l'un ni l'autre sur
    /// le *texte*, qui garde désormais la couleur normale
    /// (`NSColor.labelColor`). Le repère visuel « ceci est une citation »
    /// passe entièrement par ce filet, qui reprend `secondaryLabelColor` :
    /// même teinte qu'avant, déplacée du texte vers la marge.
    static let ruleColor = NSColor.secondaryLabelColor
}
