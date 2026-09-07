import Foundation

/// Les règles de confidentialité **propres au 1:1** : le défaut par rôle, la
/// bascule `/privé`, le compte des lignes exclues et l'audience de chaque
/// sortie.
///
/// La règle d'exportabilité elle-même n'est **pas** ici : elle vit une seule
/// fois, dans `ConfidentialityFilter.isExportable(_:for:)` (spec §8). Ce qui
/// est ici, c'est ce qui dépend du **rôle** — que le filtre ne connaît pas.
enum OneOnOneConfidentiality {

    // MARK: - Défaut par rôle (spec §6.1)

    /// Visibilité par défaut d'une ligne saisie dans ce rôle.
    ///
    /// Le côté **collaborateur** est privé : ce que j'écris sur mon propre
    /// entretien ne part pas dans un récap sans un geste explicite sur la
    /// ligne. Le côté **manager** est partagé : le récap est destiné au
    /// collaborateur, et une note qu'il ne verra pas ne lui sert à rien.
    static func defaultVisibility(for role: OneOnOneSide) -> Visibility {
        switch role {
        case .manager:      return .shared
        case .collaborator: return .private
        }
    }

    /// Même règle depuis un fil. `nil` (réunion hors 1:1) → `shared`, comme
    /// `MeetingNoteStore.defaultVisibility(for:)`.
    static func defaultVisibility(for thread: OneOnOneThread?) -> Visibility {
        guard let thread else { return .shared }
        return defaultVisibility(for: thread.myRole)
    }

    // MARK: - Bascule /privé

    /// La bascule d'une ligne par `/privé` ou par le menu de la ligne.
    ///
    /// Depuis `escalated`, on redescend vers `private` et **jamais** vers
    /// `shared` : une ligne montée à la hiérarchie ne doit pas devenir visible
    /// du collaborateur par un aller-retour de bascule.
    ///
    /// `role` ne change pas la table — la bascule est symétrique dans les deux
    /// rôles — mais il reste dans la signature : l'appelant le connaît, et
    /// l'omettre invite à réintroduire un défaut implicite le jour où un
    /// quatrième niveau apparaît.
    static func toggledPrivacy(_ current: Visibility, role: OneOnOneSide) -> Visibility {
        switch current {
        case .private:   return .shared
        case .shared:    return .private
        case .escalated: return .private
        }
    }

    // MARK: - Lignes exclues (spec §3.2)

    /// Le nombre de lignes qui **ne sortiront pas** vers `audience`.
    ///
    /// Compte tout ce que le filtre refuse — privé *et* escaladé pour un récap
    /// collaborateur : le bouton de clôture doit dire combien de lignes
    /// n'accompagneront pas l'envoi, pas seulement combien sont privées.
    static func excludedLinesCount(_ items: [any Confidential], for audience: Audience) -> Int {
        items.filter { !ConfidentialityFilter.isExportable($0, for: audience) }.count
    }

    /// Le nombre de lignes strictement privées — le chiffre de la mention
    /// « n lignes privées seront exclues. » (capture 5a).
    static func privateLinesCount(_ items: [any Confidential]) -> Int {
        items.filter { $0.visibility == .private }.count
    }

    /// La mention du pied de clôture. `nil` quand rien n'est exclu : une
    /// phrase « 0 ligne privée » attirerait l'œil pour rien.
    static func excludedLinesLabel(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1:    return "1 ligne privée sera exclue."
        default:   return "\(count) lignes privées seront exclues."
        }
    }

    // MARK: - Audiences (D9)

    /// À qui part le récap de clôture, selon mon rôle : côté manager il part au
    /// collaborateur, côté collaborateur il part à mon manager.
    static func recapAudience(for role: OneOnOneSide) -> Audience {
        switch role {
        case .manager:      return .collaborator
        case .collaborator: return .manager
        }
    }

    /// L'export « Escalade » (D9) : la seule sortie qui emporte les lignes
    /// `escalated`, et qui n'emporte **pas** les lignes seulement `shared`.
    static let escalationAudience: Audience = .hr
}
