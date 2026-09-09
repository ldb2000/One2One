import Foundation
import SwiftData

/// Les actions en lot sur une sélection de projets (décision **D15**).
///
/// **Pourquoi un service.** Ces six opérations vivaient en méthodes privées de
/// `Sidebar.swift` (`batchSetPhase`, `batchSetStatus`, `batchSetEntity`,
/// `batchArchive`, `batchDelete`), inatteignables depuis ailleurs et non
/// testées. Le Portfolio a la même sélection multiple, et le lot 6 y ajoutera
/// « Déplacer vers une entité » — c'est-à-dire exactement `setEntity`, à la
/// place du glisser-déposer par `code` qui disparaît. Une seule
/// implémentation, deux appelants.
///
/// **L'identité est le `PersistentIdentifier`** : c'est ce qu'une sélection
/// SwiftUI retient, et le seul identifiant qu'un `Project` porte à coup sûr
/// (`stableID` peut être `nil` sur les lignes anciennes, `code` n'est pas
/// unique dans le store).
///
/// `@MainActor` parce qu'un `@Model` SwiftData n'est pas `Sendable` et que le
/// contexte de la fenêtre est celui de l'acteur principal.
@MainActor
enum ProjectBatchActions {

    // MARK: - Résolution

    /// Les projets désignés par la sélection, dans l'ordre de `projects`.
    ///
    /// Un identifiant qui ne désigne plus rien (projet supprimé par une autre
    /// fenêtre) est simplement ignoré : la barre d'actions ne doit pas
    /// disparaître parce qu'une ligne s'est évaporée.
    static func resolve(_ ids: Set<PersistentIdentifier>,
                        among projects: [Project]) -> [Project] {
        projects.filter { ids.contains($0.persistentModelID) }
    }

    // MARK: - Les cinq opérations

    /// Affecte la phase (valeur persistée telle quelle, décision **D14**).
    static func setPhase(_ raw: String, on projects: [Project]) {
        appliquer(projects) { $0.phase = raw }
    }

    /// Affecte le statut.
    static func setStatus(_ raw: String, on projects: [Project]) {
        appliquer(projects) { $0.status = raw }
    }

    /// Rattache (ou détache, avec `nil`) les projets à une entité.
    ///
    /// C'est l'opération que le lot 6 exposera sous le libellé « Déplacer vers
    /// une entité », en remplacement du glisser-déposer de l'arbre.
    static func setEntity(_ entity: Entity?, on projects: [Project]) {
        // Pas `appliquer` : réaffecter `Project.entity` puis enregistrer perd
        // la valeur une fois sur trois (mesures dans `ProjectRelationWriter`).
        // C'est la seule des six opérations qui écrive une relation à inverse
        // déclaré ; les cinq autres écrivent des colonnes.
        ProjectRelationWriter.setEntity(entity, on: projects)
    }

    /// Archive les projets. Ne supprime rien : un projet archivé sort du
    /// Portfolio et rejoint la section « Projets Archivés » de la barre
    /// latérale.
    static func archive(_ projects: [Project]) {
        appliquer(projects) { $0.isArchived = true }
    }

    /// Désarchive les projets — le pendant d'`archive`, pour que la section
    /// « Projets Archivés » ne soit pas un aller sans retour.
    static func unarchive(_ projects: [Project]) {
        appliquer(projects) { $0.isArchived = false }
    }

    /// Supprime les projets et tout ce qui en dépend (les relations de
    /// `Project` sont en `.cascade`).
    ///
    /// Le contexte est un paramètre, contrairement aux autres opérations :
    /// supprimer se fait **sur** le contexte, pas sur l'objet, et un projet
    /// jamais inséré n'en a pas.
    static func delete(_ projects: [Project], in context: ModelContext) {
        guard !projects.isEmpty else { return }
        for projet in projects { context.delete(projet) }
        try? context.save()
    }

    // MARK: - Mécanique

    /// Applique la modification à chaque projet, puis sauve **une fois**.
    ///
    /// Le contexte est celui des objets (`Project.modelContext`) et non un
    /// paramètre : les cinq setters modifient des objets déjà insérés, et
    /// demander à l'appelant de fournir un contexte qu'il possède déjà par
    /// l'objet inviterait à en passer un autre.
    private static func appliquer(_ projects: [Project],
                                  _ modification: (Project) -> Void) {
        guard !projects.isEmpty else { return }
        for projet in projects { modification(projet) }
        try? projects.first?.modelContext?.save()
    }
}

/// La création d'un projet depuis la barre latérale (`＋`) ou l'en-tête du
/// Portfolio (« ＋ Nouveau projet »).
///
/// Ici et non dans les deux vues : le calcul du prochain code libre était une
/// méthode privée de `Sidebar.swift`, et l'en-tête du Portfolio en avait besoin
/// à l'identique. Une fonction pure pour le code, une opération de contexte
/// pour l'insertion.
@MainActor
enum ProjectCreation {

    /// Le nom d'un projet neuf, tel que le montre la ligne créée.
    static let nomParDefaut = "Nouveau projet"
    /// Le domaine par défaut, celui que la barre latérale posait déjà.
    static let domaineParDefaut = "General"
    /// Le préfixe des codes attribués par l'application, distinct de ceux du
    /// portfolio externe (`P25_…`) : un projet créé à la main ne doit pas
    /// entrer en collision avec un code du prochain import xlsx.
    static let prefixeDeCode = "PXX_"

    /// Le premier code de la forme `PXX_001` qui n'est pas déjà pris.
    ///
    /// Fonction pure : elle prend les codes existants, pas le store.
    static func prochainCode(parmi codes: [String]) -> String {
        let pris = Set(codes)
        var index = 1
        var candidat = String(format: "\(prefixeDeCode)%03d", index)
        while pris.contains(candidat) {
            index += 1
            candidat = String(format: "\(prefixeDeCode)%03d", index)
        }
        return candidat
    }

    /// Crée et insère un projet neuf, rattaché à `entity` s'il y en a une.
    ///
    /// Phase « Cadrage » et statut par défaut : ce sont les valeurs que la
    /// barre latérale posait déjà, et le début d'un projet.
    ///
    /// **`nom` vide retombe sur `nomParDefaut`.** C'est le cas du bouton
    /// « ＋ Nouveau projet » du Portfolio, qui ne sait pas comment le projet
    /// s'appelle. La palette `⌘K`, elle, le sait : son action promet « Créer
    /// un projet « ged » », et un projet nommé « Nouveau projet » démentirait
    /// le libellé.
    ///
    /// La valeur par défaut est la chaîne vide et **non** `nomParDefaut` : un
    /// argument par défaut est évalué hors acteur, et lire là une propriété
    /// statique de cet `enum` `@MainActor` produit un avertissement de
    /// concurrence (erreur en Swift 6).
    @discardableResult
    static func creer(among projects: [Project],
                      entity: Entity? = nil,
                      nom: String = "",
                      in context: ModelContext) -> Project {
        let net = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        let projet = Project(code: prochainCode(parmi: projects.map(\.code)),
                             name: net.isEmpty ? nomParDefaut : net,
                             domain: entity?.name ?? domaineParDefaut,
                             sponsor: "",
                             projectType: ProjectType.metier.label,
                             phase: ProjectPhase.cadrage.label)
        projet.entity = entity
        context.insert(projet)
        try? context.save()
        return projet
    }
}
