import SwiftUI

/// Le ton d'un élément du domaine 1:1 : ce que la spec appelle `warn`,
/// `accent/oneonone` (violet) et `ok`.
///
/// Un **ton** et non une couleur : les règles métier sont pures et testées, et
/// la table §1.2 reste la seule à nommer une couleur. C'est ici que la
/// correspondance se fait, une fois, et nulle part ailleurs.
enum OneOnOneTone: Equatable, Sendable {
    case warn, oneOnOne, ok

    var color: Color {
        switch self {
        case .warn:     return One2OneToken.warn
        case .oneOnOne: return One2OneToken.oneOnOne
        case .ok:       return One2OneToken.ok
        }
    }

    var backgroundColor: Color {
        switch self {
        case .warn:     return One2OneToken.warnBg
        case .oneOnOne: return One2OneToken.oneOnOneBg
        case .ok:       return One2OneToken.okBg
        }
    }

    /// L'encre lisible sur `backgroundColor` — les paires de la table §1.2 qui
    /// tiennent 4,5:1 sous 12 px (cf. `One2OneTokensTests`).
    var inkColor: Color {
        switch self {
        case .warn:     return One2OneToken.warnInk
        case .oneOnOne: return One2OneToken.oneOnOneInk
        case .ok:       return One2OneToken.okDeep
        }
    }
}

extension OneOnOneObjective {

    /// Ton d'un objectif par avancement (spec §3.4 : < 30 % `warn`,
    /// < 70 % violet, ≥ 70 % `ok`).
    static func tone(forProgress progress: Int) -> OneOnOneTone {
        let borne = min(100, max(0, progress))
        switch borne {
        case ..<30: return .warn
        case ..<70: return .oneOnOne
        default:    return .ok
        }
    }

    var tone: OneOnOneTone { Self.tone(forProgress: clampedProgress) }
}

/// La liste des objectifs de la carte `OBJECTIFS S2` (capture 2b).
enum OneOnOneObjectiveList {

    /// Ordre manuel, puis date de création à rang égal.
    static func sorted(_ objectives: [OneOnOneObjective]) -> [OneOnOneObjective] {
        objectives.sorted { gauche, droite in
            if gauche.order != droite.order { return gauche.order < droite.order }
            return gauche.createdAt < droite.createdAt
        }
    }

    /// `Revue prévue le 18 sept.` — la revue la **plus proche** de la carte, et
    /// non la dernière saisie : c'est celle-là qui arrive.
    ///
    /// `nil` quand aucun objectif n'a de date de revue.
    static func reviewLabel(_ objectives: [OneOnOneObjective]) -> String? {
        guard let plusProche = objectives.compactMap(\.reviewAt).min() else { return nil }
        return "Revue prévue le \(OneOnOneDateFormat.dayMonth(plusProche))"
    }
}
