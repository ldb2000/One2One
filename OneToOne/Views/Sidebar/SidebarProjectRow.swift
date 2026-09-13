import Foundation
import SwiftData

/// L'identité d'une ligne de projet **dans la barre latérale**, sous-section
/// comprise.
///
/// ## Le défaut qu'elle corrige
///
/// Un même projet apparaît à plusieurs endroits de la **même** `List` : il
/// peut être à la fois épinglé (« ÉPINGLÉS »), récemment ouvert (« RÉCENTS »)
/// et listé sous son entité dans l'arbre. Les trois `ForEach` l'identifiaient
/// par son `persistentModelID` — donc par **la même valeur**, trois fois, dans
/// un seul conteneur.
///
/// SwiftUI exige des identités uniques par conteneur ; quand elles ne le sont
/// pas, le rendu est indéfini. À la recette `p1f` du 2026-09-09, les deux
/// projets qui étaient à la fois épinglés **et** récents (« AE – Gestion des
/// services IO… » et « ASP – BLOOM ») ont perdu leur pastille de statut dans
/// « ÉPINGLÉS » — la structure de leur ligne « RÉCENTS », qui n'en porte pas,
/// s'y était substituée. Le troisième épinglé, « ASP – Installation nouvelle
/// GED », n'était pas dans les récents : il a gardé la sienne. C'est la
/// signature exacte d'une collision d'identité, et non un défaut de
/// `PinnedProjectsList`, dont la pastille est inconditionnelle.
///
/// Préfixer l'identité par la sous-section suffit : la même ligne garde son
/// identité d'un rendu à l'autre (ce dont dépend l'animation et la
/// réutilisation), mais deux lignes de sous-sections différentes ne se
/// confondent plus.
struct SidebarProjectRowID: Hashable, Sendable {
    /// La sous-section, en un mot stable — `ÉPINGLÉS`, `RÉCENTS`, `arbre`,
    /// `archivés`. Ce sont les libellés déjà exposés par les vues, pour que le
    /// nom de la section n'existe qu'une fois.
    let section: String
    let projet: PersistentIdentifier
}

/// Une ligne de projet prête à être rendue par un `ForEach`.
struct SidebarProjectRow: Identifiable {
    let id: SidebarProjectRowID
    let projet: Project

    /// Les lignes d'une sous-section, dans l'ordre reçu.
    static func lignes(_ projets: [Project], section: String) -> [SidebarProjectRow] {
        projets.map {
            SidebarProjectRow(
                id: SidebarProjectRowID(section: section, projet: $0.persistentModelID),
                projet: $0)
        }
    }

    /// Les sections de la barre latérale qui listent des projets. Nommées ici
    /// pour que deux vues ne puissent pas choisir le même mot par accident —
    /// ce serait la collision qu'on vient de corriger.
    enum Section {
        static let arbre = "arbre"
        static let archives = "archivés"
    }
}
