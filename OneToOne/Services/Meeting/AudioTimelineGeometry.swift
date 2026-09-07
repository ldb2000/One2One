import CoreGraphics

/// La géométrie de la frise audio de 22 px (spec §2.4 : « onde échantillonnée,
/// tête de lecture 2 px `accent/action`, marqueurs ronds (note), carrés
/// (capture), losanges (décision). Clic = déplacement, glisser = balayage »).
///
/// Extraite de la vue parce qu'un `Canvas` à qui l'on passe un `NaN` ne dessine
/// rien **sans rien signaler** : une durée nulle — réunion sans audio, frise
/// affichée avant le chargement du fichier — est le cas courant, pas
/// l'exception. Tout est donc borné, jamais divisé par zéro.
enum AudioTimelineGeometry {

    /// Hauteur de la frise (spec §2.4).
    static let height: CGFloat = 22

    /// Épaisseur de la tête de lecture.
    static let playheadWidth: CGFloat = 2

    /// Diamètre d'un marqueur (rond, losange ou carré).
    static let markerSize: CGFloat = 7

    /// Largeur d'un pic d'onde, séparateur compris : sert à choisir le nombre
    /// de pics à décimer pour une largeur donnée.
    static let peakWidth: CGFloat = 6

    /// Position horizontale de l'instant `t`, bornée à `0…width`.
    static func x(t: Double, duration: Double, width: CGFloat) -> CGFloat {
        guard duration > 0, width > 0, t.isFinite else { return 0 }
        let ratio = min(max(t / duration, 0), 1)
        return CGFloat(ratio) * width
    }

    /// Instant correspondant à la position `x`, borné à `0…duration`.
    static func t(x: CGFloat, duration: Double, width: CGFloat) -> Double {
        guard duration > 0, width > 0, x.isFinite else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return Double(ratio) * duration
    }

    /// Nombre de pics à décimer pour une largeur de frise, borné pour ne pas
    /// demander deux mille barres sur une frise de 300 px.
    static func peakCount(width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, min(Int(width / peakWidth), 400))
    }
}
