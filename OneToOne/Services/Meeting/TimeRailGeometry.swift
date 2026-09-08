import CoreGraphics

/// La géométrie de la **colonne temps** du mode séance plein écran (spec §2.6,
/// capture `1b-mode-seance.png`) : « axe vertical 3 px, portion écoulée
/// `#e04b3f` ; marqueurs — rond `dark/accent action` pour une note, carré 3 px
/// de rayon `accent/report` pour une décision, trait plein `dark/ink` pour la
/// position courante. Libellé mono à gauche, aligné à 30 px du rail. »
///
/// Extraite de la vue pour la même raison qu'`AudioTimelineGeometry` : une
/// durée nulle — réunion sans audio, séance qui vient de démarrer — est le cas
/// **courant** de ce mode, pas l'exception, et un `Canvas` à qui l'on passe un
/// `NaN` ne dessine rien sans rien signaler. Tout est donc borné et rien n'est
/// jamais divisé par zéro.
enum TimeRailGeometry {

    // MARK: - Largeurs et positions fixes (capture 1b)

    /// Largeur de la colonne. Reprend le jeton de la spec §1.2 plutôt que d'en
    /// écrire une seconde valeur.
    static let columnWidth: CGFloat = One2OneToken.timeColumnWidth

    /// Épaisseur de l'axe (spec §2.6).
    static let axisWidth: CGFloat = 3

    /// Abscisse du **centre** de l'axe dans la colonne.
    static let axisCenterX: CGFloat = 41

    /// Distance entre le bord gauche du libellé mono et l'axe (spec §2.6 :
    /// « aligné à 30 px du rail »). Le libellé fait 34 px de large
    /// (`TimecodeLabel.width`) : il **passe donc légèrement derrière** l'axe,
    /// exactement comme sur la capture, où l'on lit `04:1` et non `04:12`.
    static let labelInset: CGFloat = 30

    /// Abscisse du bord gauche du libellé mono.
    static var labelX: CGFloat { axisCenterX - labelInset }

    /// Diamètre du rond d'une note.
    static let noteDiameter: CGFloat = 9

    /// Côté du carré d'une décision, et son rayon (spec §2.6 : « carré 3 px de
    /// rayon »).
    static let decisionSide: CGFloat = 11
    static let decisionCornerRadius: CGFloat = 3

    /// Le trait plein de la position courante.
    static let positionWidth: CGFloat = 15
    static let positionHeight: CGFloat = 3

    /// Écart vertical minimal entre deux libellés mono. En dessous, ils se
    /// chevauchent et deviennent illisibles : le second est **omis** plutôt que
    /// superposé (cf. `labels(markers:position:duration:length:)`).
    static let minimumLabelSpacing: CGFloat = 15

    // MARK: - Formes

    /// La forme du repère selon sa nature. Trois formes seulement, comme la
    /// frise du mode fenêtré : en inventer une par nature de note rendrait la
    /// colonne illisible.
    enum Shape: Sendable, Equatable {
        /// Rond `dark/accent action` — une note.
        case dot
        /// Carré à coins arrondis `accent/report` — une décision.
        case square
    }

    /// `.square` pour une décision, `.dot` pour tout le reste. Les captures et
    /// les planches n'ont pas de forme propre dans cette colonne : la spec
    /// §2.6 n'en nomme que deux.
    static func shape(for kind: MeetingPlayhead.Marker.Kind) -> Shape {
        switch kind {
        case .decision:                          return .square
        case .note, .risk, .capture, .board:     return .dot
        }
    }

    /// Le côté englobant d'une forme, pour la centrer sur l'axe.
    static func size(of shape: Shape) -> CGFloat {
        switch shape {
        case .dot:    return noteDiameter
        case .square: return decisionSide
        }
    }

    // MARK: - Axe vertical

    /// Ordonnée de l'instant `t` sur un axe de `length` points, bornée à
    /// `0…length`.
    ///
    /// Une durée nulle place tout à zéro : c'est le seul choix qui ne mente
    /// pas, puisqu'aucune échelle n'existe encore.
    static func y(t: Double, duration: Double, length: CGFloat) -> CGFloat {
        guard duration > 0, length > 0, t.isFinite else { return 0 }
        let ratio = min(max(t / duration, 0), 1)
        return CGFloat(ratio) * length
    }

    /// Instant correspondant à l'ordonnée `y`, borné à `0…duration`. Sert au
    /// clic sur l'axe.
    static func t(y: CGFloat, duration: Double, length: CGFloat) -> Double {
        guard duration > 0, length > 0, y.isFinite else { return 0 }
        let ratio = min(max(y / length, 0), 1)
        return Double(ratio) * duration
    }

    /// Longueur de la **portion écoulée** (`#e04b3f`) : de l'origine à la
    /// position courante. Identique à `y(t:)`, nommée à part parce que la vue
    /// la lit comme une hauteur et non comme une position — et qu'un test qui
    /// dit « la portion écoulée d'une séance à mi-course fait la moitié de
    /// l'axe » doit pouvoir s'écrire ainsi.
    static func elapsedLength(t: Double, duration: Double, length: CGFloat) -> CGFloat {
        y(t: t, duration: duration, length: length)
    }

    // MARK: - Libellés

    /// Un libellé mono de la colonne, avec l'ordonnée de son centre.
    struct Label: Sendable, Equatable, Identifiable {
        /// `mm:ss`.
        let text: String
        /// Ordonnée du **centre** du libellé sur l'axe.
        let y: CGFloat
        /// Vrai pour le libellé de la position courante, qui se lit en encre de
        /// titre et non en encre de libellé mono (capture 1b : `18:42` est le
        /// seul libellé clair de la colonne).
        let isPosition: Bool
        var id: String { "\(text)-\(isPosition)" }
    }

    /// Les libellés de la colonne : un par repère, plus celui de la position
    /// courante, du haut vers le bas.
    ///
    /// La position **gagne** en cas de collision (elle bouge, les repères non :
    /// masquer le temps courant pour préserver un repère fixe serait le mauvais
    /// arbitrage), et deux repères trop proches ne rendent que le premier.
    static func labels(markers: [MeetingPlayhead.Marker],
                       position: Double?,
                       duration: Double,
                       length: CGFloat) -> [Label] {
        var candidats: [Label] = markers
            .sorted { $0.t < $1.t }
            .map { Label(text: MeetingPlayhead.mmss($0.t),
                         y: y(t: $0.t, duration: duration, length: length),
                         isPosition: false) }

        if let position {
            let libelle = Label(text: MeetingPlayhead.mmss(position),
                                y: y(t: position, duration: duration, length: length),
                                isPosition: true)
            // La position évince les repères qu'elle recouvre, puis reprend sa
            // place dans l'ordre vertical.
            candidats.removeAll { abs($0.y - libelle.y) < minimumLabelSpacing }
            candidats.append(libelle)
            candidats.sort { $0.y < $1.y }
        }

        var retenus: [Label] = []
        for candidat in candidats {
            if let dernier = retenus.last,
               abs(candidat.y - dernier.y) < minimumLabelSpacing,
               !candidat.isPosition {
                continue
            }
            retenus.append(candidat)
        }
        return retenus
    }
}
