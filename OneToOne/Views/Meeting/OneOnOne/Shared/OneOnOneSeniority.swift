import Foundation

/// L'ancienneté de la carte personne : `dans l'équipe depuis 3 ans`
/// (capture 2a, spec §3.3 « avatar 34 px, nom, rôle, ancienneté »).
///
/// **Pur**, et volontairement approximatif : l'ancienneté d'un collaborateur se
/// dit en années entières, ou en mois la première année. Afficher « 3 ans et
/// 2 mois » sur une carte de 300 px déplacerait l'attention vers un chiffre
/// dont personne n'a besoin au début d'un entretien.
///
/// Partagé (`Shared/`) : les captures 2b et 5a portent la même ligne.
enum OneOnOneSeniority {

    /// Jours d'un mois moyen et d'une année moyenne. Un calcul en composantes
    /// de calendrier serait plus juste au jour près, pour un libellé arrondi à
    /// l'année : la moyenne suffit et ne dépend pas du fuseau.
    private static let daysPerMonth: Double = 30.44
    private static let daysPerYear: Double = 365.25

    /// `dans l'équipe depuis 3 ans`, ou `nil` quand il n'y a rien à dire.
    ///
    /// `nil` sans date d'arrivée **et** pour une date future : la colonne
    /// `joinedAt` est vide sur toutes les fiches existantes, et une ancienneté
    /// inventée serait lue comme un fait.
    static func label(joinedAt: Date?, now: Date) -> String? {
        guard let joinedAt, joinedAt <= now else { return nil }
        let jours = now.timeIntervalSince(joinedAt) / 86_400

        let annees = Int(jours / daysPerYear)
        if annees >= 1 {
            return "dans l'équipe depuis \(annees) an\(annees > 1 ? "s" : "")"
        }
        let mois = Int(jours / daysPerMonth)
        guard mois >= 1 else { return "arrivé ce mois-ci" }
        return "dans l'équipe depuis \(mois) mois"
    }

    /// `Ingénieur CI/CD · dans l'équipe depuis 3 ans` — la deuxième ligne de la
    /// carte personne. Sans ancienneté, le rôle reste seul : un séparateur
    /// orphelin en fin de ligne se lit comme une donnée manquante.
    static func roleLine(role: String, joinedAt: Date?, now: Date) -> String {
        let role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let anciennete = label(joinedAt: joinedAt, now: now) else { return role }
        guard !role.isEmpty else { return anciennete }
        return "\(role) · \(anciennete)"
    }
}
