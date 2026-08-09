import Foundation

/// Degré d'urgence d'une échéance, tel que les captures le donnent à voir.
///
/// C'est la seule règle de couleur conditionnelle du jeu visuel : elle vit donc
/// ici, une fois, plutôt que dans chaque vue qui affiche une date.
public enum Urgence: Equatable {
    /// Dépassée de plus de sept jours — rouge.
    case forte
    /// Dépassée de sept jours ou moins — orange.
    case moyenne
    /// Pas encore due, aujourd'hui compris — gris.
    case aVenir
    /// Aucune échéance posée.
    case sansEcheance

    /// Seuil lu sur les captures 3 et 1a : « 12 j » et « 8 j » sont rouges,
    /// « 5 j » et « 2 j » sont orange. À confirmer sur les fichiers sources.
    static let seuilForteEnJours = 7

    /// Classe une échéance par rapport à un instant donné.
    ///
    /// Le calcul porte sur des **jours de calendrier**, pas sur des intervalles
    /// de 24 heures : une échéance d'hier soir est en retard d'un jour ce matin,
    /// quelle que soit l'heure.
    public static func pour(_ echeance: Date?,
                            maintenant: Date,
                            calendrier: Calendar = .current) -> Urgence {
        guard let echeance else { return .sansEcheance }

        let jourEcheance = calendrier.startOfDay(for: echeance)
        let jourCourant = calendrier.startOfDay(for: maintenant)
        let retard = calendrier.dateComponents([.day], from: jourEcheance, to: jourCourant).day ?? 0

        if retard <= 0 { return .aVenir }
        return retard > seuilForteEnJours ? .forte : .moyenne
    }
}
