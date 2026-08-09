import Foundation

/// Portée d'échéance : le filtre principal de la liste d'actions, tel que la capture 3
/// le présente en trois pilules.
///
/// À ne pas confondre avec `Urgence`, qui décide d'une **couleur**. `Portee` décide de
/// ce qui est **affiché**. Les deux se calculent à partir d'une échéance mais ne
/// partagent pas leurs seuils : une action en retard de trois jours est `.enRetard`
/// pour la portée, et `.moyenne` pour l'urgence.
public enum Portee: String, CaseIterable {
    case enRetard
    case cetteSemaine
    case toutes

    public var libelle: String {
        switch self {
        case .enRetard: return "En retard"
        case .cetteSemaine: return "Cette semaine"
        case .toutes: return "Toutes"
        }
    }

    /// Nombre de jours couverts par « Cette semaine », aujourd'hui inclus.
    static let joursDeLaSemaine = 7

    /// Une échéance tombe-t-elle dans cette portée ?
    ///
    /// Le calcul porte sur des **jours de calendrier**, comme `Urgence`.
    public static func contient(_ echeance: Date?,
                                portee: Portee,
                                maintenant: Date,
                                calendrier: Calendar = .current) -> Bool {
        if portee == .toutes { return true }
        guard let echeance else { return false }

        let jourEcheance = calendrier.startOfDay(for: echeance)
        let jourCourant = calendrier.startOfDay(for: maintenant)
        let ecart = calendrier.dateComponents([.day], from: jourCourant, to: jourEcheance).day ?? 0

        switch portee {
        case .enRetard: return ecart < 0
        case .cetteSemaine: return ecart >= 0 && ecart <= joursDeLaSemaine
        case .toutes: return true
        }
    }
}
