import Foundation

/// Ce qu'on affiche de l'identité d'un collaborateur, et ce qu'on refuse
/// d'afficher.
enum CollaboratorIdentity {

    /// Le poste, ou rien si le champ contient une adresse mail.
    ///
    /// 38 fiches sur 366 portent une adresse dans `role` — un import
    /// d'annuaire a rempli le mauvais champ. L'écran ne la présente pas comme
    /// un poste ; **nettoyer les données est un geste distinct**, qui n'a pas
    /// été fait : le champ reste tel quel en base.
    static func displayRole(_ role: String) -> String {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return looksLikeEmail(trimmed) ? "" : trimmed
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        guard text.contains("@"), !text.contains(" ") else { return false }
        let parts = text.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    /// Sous-titre d'identité : rôle · entité · projets. Les morceaux absents
    /// sont sautés, sans laisser de séparateur orphelin. Jamais l'email : ce
    /// n'est pas une information de pilotage, et il n'y a pas la place.
    static func subtitle(role: String, entity: String?, projects: Int) -> String {
        [displayRole(role),
         entity,
         projects > 0 ? "\(projects) projet\(projects > 1 ? "s" : "")" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
