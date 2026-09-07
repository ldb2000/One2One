import Foundation

/// Le ton des cinq crans de `① COMMENT ÇA VA` (spec §3.3 : « cran choisi bordé
/// de sa couleur »).
///
/// Une **table de tons** et non de couleurs : `OneOnOneTone` (lot 10) est la
/// seule passerelle du domaine vers la table §1.2, et `One2OneTokens.swift`
/// reste le seul fichier qui nomme une couleur.
///
/// `Difficile` est en `accent/report` et non en `warn` : c'est le cran qui doit
/// arrêter le regard du manager, et le distinguer de « Sous tension » est tout
/// l'intérêt d'une échelle à cinq crans.
enum OneOnOneMoodTone {

    static func tone(_ level: MoodLevel) -> OneOnOneTone {
        switch level {
        case .difficile:   return .report
        case .sousTension: return .warn
        case .caVa:        return .oneOnOne
        case .bien:        return .ok
        case .tresBien:    return .ok
        }
    }

    /// Vrai pour le cran le plus haut, qui prend la variante **profonde** de
    /// son ton : `Bien` et `Très bien` partagent `ok`, et deux crans voisins de
    /// la même couleur exacte seraient indiscernables une fois choisis.
    static func isDeep(_ level: MoodLevel) -> Bool {
        level == .tresBien
    }
}
