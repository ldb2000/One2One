import Foundation
import SwiftData

/// Ce qu'on affiche de l'identité d'un collaborateur, et ce qu'on refuse
/// d'afficher.
enum CollaboratorIdentity {

    /// Rôle donné à une fiche dont le champ ne portait pas un poste.
    static let roleNeant = "Néant"

    /// Applique la règle : **un rôle qui porte une adresse n'est pas un rôle**.
    /// L'adresse rejoint le champ prévu pour elle si celui-ci est vide, et le
    /// rôle devient « Néant ».
    ///
    /// Déplacement, jamais effacement : 16 des 38 fiches concernées ont un
    /// champ `email` vide, l'adresse n'existe que dans `role`. La vider la
    /// détruirait.
    ///
    /// Quand les deux champs portent une adresse **différente**, celle du
    /// champ `email` fait foi — c'est le champ prévu pour elle.
    static func repaired(role: String, email: String) -> (role: String, email: String) {
        let roleTrimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeEmail(roleTrimmed) else { return (role, email) }
        let emailTrimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return (roleNeant, emailTrimmed.isEmpty ? roleTrimmed : emailTrimmed)
    }

    /// Passe la règle sur tout l'annuaire. Renvoie le nombre de fiches
    /// touchées — zéro à la seconde passe, la réparation étant idempotente.
    ///
    /// Appelée au démarrage, comme la réparation d'identifiants : le défaut
    /// vient de données écrites par une version passée du code, il ne se
    /// corrige pas tout seul.
    @discardableResult
    static func repairRoles(in context: ModelContext) -> Int {
        guard let tous = try? context.fetch(FetchDescriptor<Collaborator>()) else { return 0 }
        var touchees = 0
        for collaborateur in tous {
            let repare = repaired(role: collaborateur.role, email: collaborateur.email)
            guard repare.role != collaborateur.role || repare.email != collaborateur.email
            else { continue }
            collaborateur.role = repare.role
            collaborateur.email = repare.email
            touchees += 1
        }
        if touchees > 0 { try? context.save() }
        return touchees
    }

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
