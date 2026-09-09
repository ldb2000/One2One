import Foundation
import SwiftData

/// Écrire la relation `Project.entity` sans qu'elle se perde.
///
/// **Le défaut, mesuré.** Réaffecter `project.entity` — passer d'une entité à
/// une autre, pas la poser pour la première fois — puis appeler
/// `ModelContext.save()` **perd la nouvelle valeur environ une fois sur
/// trois** : la relation relit `nil`. Mesuré sur un store en mémoire, 200
/// tours par scénario :
///
/// | scénario | perte |
/// | --- | --- |
/// | première affectation puis `save` | 0 / 200 |
/// | réaffectation **sans** `save` | 0 / 200 |
/// | réaffectation puis `save` | 70 / 200 |
/// | réaffectation puis `save`, relue et réparée | 0 / 200 |
///
/// C'est le `save` qui perd la valeur, pas l'affectation. `Project.entity` est
/// la **seule** relation du modèle dont l'inverse est déclaré
/// (`Entity.projects`, `deleteRule: .nullify`), et c'est cet inverse que
/// SwiftData n'arrive pas à recoudre : lire `Entity.projects` juste après le
/// même `save` lève carrément
/// « Fatal error: Never access a full future backing data ». Le chef de projet
/// et l'architecte, qui n'ont pas d'inverse déclaré, ne sont pas touchés.
///
/// **Le contournement** est celui de la dernière ligne du tableau : affecter,
/// enregistrer, **relire**, et réaffecter si la valeur a disparu. Lire la
/// relation *à-un* est sûr ; c'est la collection inverse qui piège.
///
/// Ici et non dans les deux appelants : `ProjectCardDraft.apply` (édition
/// in-place, lot 4) et `ProjectBatchActions.setEntity` (barre d'actions en
/// lot, lot 2) écrivent la même relation, et un seul des deux réparé serait
/// un défaut qui revient par l'autre porte.
@MainActor
enum ProjectRelationWriter {

    /// Affecte `entity` à chaque projet, enregistre, et répare la perte
    /// éventuelle.
    ///
    /// - Returns: `true` si une réparation a été nécessaire — ce que le test
    ///   de non-régression n'exige pas mais qu'il peut observer.
    @discardableResult
    static func setEntity(_ entity: Entity?,
                          on projects: [Project],
                          in context: ModelContext? = nil) -> Bool {
        guard !projects.isEmpty else { return false }
        let contexte = context ?? projects.first?.modelContext
        for projet in projects { projet.entity = entity }
        try? contexte?.save()

        let attendu = entity?.persistentModelID
        var repare = false
        for projet in projects where projet.entity?.persistentModelID != attendu {
            projet.entity = entity
            repare = true
        }
        if repare { try? contexte?.save() }
        return repare
    }
}
