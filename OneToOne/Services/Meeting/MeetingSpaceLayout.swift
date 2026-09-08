import CoreGraphics

/// Les largeurs de colonnes de l'espace Réunion, calculées hors de toute vue.
///
/// La spec §1.2 fixe des largeurs **fixes** (rail d'actions 330 px, nav latérale
/// 190 px) et déclare le reste fluide, avec `min-width: 0` pour que l'ellipsis
/// fonctionne. Le critère d'acceptation n° 5 du chantier 1 ajoute une garantie
/// que ni `grid-template-columns` ni `GeometryReader` ne donnent tout seuls :
/// **à 1 280 px, la colonne fluide fait au moins 520 px et aucune colonne fixe
/// ne se chevauche**.
///
/// Une soustraction de largeurs non bornée produit, en SwiftUI, une colonne
/// négative qui se traduit par un chevauchement silencieux — pas par une
/// erreur. D'où ce calcul séparé, testé : quand la fenêtre ne peut pas tenir
/// la promesse, on **retire** une colonne fixe au lieu de rogner la fluide.
enum MeetingSpaceLayout {

    /// Plancher de la colonne fluide (critère d'acceptation n° 5).
    static let fluidMinimum: CGFloat = 520

    /// Épaisseur du filet qui sépare deux colonnes d'une même carte.
    static let hairlineWidth: CGFloat = 1

    /// Colonne gauche de l'écran de séance 1:1 — carte personne, ordre du
    /// jour, resté en suspens, barre assistant (spec §3.3, capture 2a).
    static let oneOnOneLeftWidth: CGFloat = 300

    /// Rail des engagements de l'écran de séance 1:1 (spec §3.3). Même valeur
    /// que `One2OneToken.oneOnOneRailNarrow`, nommée ici parce que c'est cette
    /// table qui répartit les colonnes.
    static let oneOnOneRailWidth: CGFloat = 320

    /// Répartition des colonnes pour une largeur de fenêtre donnée.
    ///
    /// - Parameters:
    ///   - totalWidth: largeur disponible pour l'ensemble des colonnes.
    ///   - rail: largeur souhaitée du rail d'actions, `nil` s'il n'y en a pas.
    ///   - sideNav: largeur souhaitée de la nav latérale du mode Relire, `nil` sinon.
    /// - Returns: les trois largeurs effectives. Une colonne abandonnée vaut 0.
    ///   La somme ne dépasse jamais `totalWidth`, et aucun membre n'est négatif.
    static func columns(totalWidth: CGFloat,
                        rail: CGFloat?,
                        sideNav: CGFloat?) -> (fluid: CGFloat, rail: CGFloat, sideNav: CGFloat) {
        let largeur = max(0, totalWidth)
        var railWidth = max(0, rail ?? 0)
        var navWidth = max(0, sideNav ?? 0)

        // La nav latérale cède la première : la spec §1.1 dit le rail
        // « permanent », pas la navigation du poste de pilotage.
        if largeur - railWidth - navWidth < fluidMinimum { navWidth = 0 }
        if largeur - railWidth < fluidMinimum { railWidth = 0 }

        // Fenêtre plus étroite que le plancher lui-même : la fluide prend tout
        // ce qui reste, jamais une valeur négative.
        let fluid = max(0, largeur - railWidth - navWidth)
        return (fluid: fluid, rail: railWidth, sideNav: navWidth)
    }

    /// Vrai si le rail d'actions tient sans rogner la colonne fluide sous son
    /// plancher. Sert aux vues qui décident de l'afficher ou de le replier.
    static func showsRail(totalWidth: CGFloat) -> Bool {
        columns(totalWidth: totalWidth, rail: One2OneToken.actionsRailWidth, sideNav: nil).rail > 0
    }

    /// Répartition des **trois** colonnes de l'écran de séance 1:1
    /// (spec §3.3 : `300 | 1fr | 320`).
    ///
    /// Délègue à `columns(totalWidth:rail:sideNav:)` — la règle « la colonne
    /// fluide ne descend pas sous 520 px, on retire une colonne fixe plutôt
    /// que de la rogner » est ainsi écrite **une seule fois** dans le projet.
    /// La colonne gauche prend la place de la nav latérale, donc elle cède la
    /// première : le rail porte les engagements de la séance et la clôture,
    /// la colonne gauche porte du contexte.
    static func oneOnOneColumns(totalWidth: CGFloat)
        -> (left: CGFloat, center: CGFloat, rail: CGFloat) {
        let colonnes = columns(totalWidth: totalWidth,
                              rail: oneOnOneRailWidth,
                              sideNav: oneOnOneLeftWidth)
        return (left: colonnes.sideNav, center: colonnes.fluid, rail: colonnes.rail)
    }

    /// Deux colonnes égales séparées par un filet — la carte
    /// « Notes & transcription » de la spec §2.4 (`1fr 1px 1fr`).
    static func evenSplit(width: CGFloat) -> (CGFloat, CGFloat) {
        let utile = max(0, width - hairlineWidth)
        // Arrondi vers le bas, le demi-pixel restant allant à la colonne de
        // droite : la somme + le filet vaut exactement la largeur donnée, sans
        // le pixel de débordement qui décale toute la carte.
        let moitie = (utile / 2).rounded(.down)
        return (moitie, utile - moitie)
    }
}
