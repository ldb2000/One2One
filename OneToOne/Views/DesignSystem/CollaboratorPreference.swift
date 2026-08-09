import Foundation

/// Règle de partition des collaborateurs selon la préférence persistée de la
/// sidebar (clé `@AppStorage`, valeurs `"pinned"` / `"favourites"` / `"both"`,
/// défaut `"both"`) :
/// - `pinned`     → épinglés au top, divider, le reste A–Z
/// - `favourites` → favoris au top, divider, le reste A–Z
/// - `both`       → épinglés ET favoris au top (alpha mixé), divider, le reste A–Z
/// Inclut tous les collaborateurs non-archivés pour ne pas masquer un favori.
///
/// Seul endroit qui lit ce réglage et décide de l'ordre qui en résulte —
/// extrait de `CollaboratorPickerOptions` (tâche 2, ronde de correctif 1)
/// pour que le sous-menu « Assigné à » de la barre d'outils (`ActionsListView.filtresMenu`)
/// partage exactement la même règle plutôt que d'en recopier une variante.
/// `CollaboratorPickerOptions` continue de porter son propre `@AppStorage`
/// (nécessaire à sa réactivité SwiftUI) mais délègue le calcul ici ; ne pas
/// dupliquer le `switch` ci-dessous ailleurs.
///
/// Distinct de `Sidebar.filteredActiveCollaborators`, qui lit la même clé
/// mais pour un usage différent (un *filtre* qui exclut, pas une
/// *partition* qui garde tout en réordonnant) — non concerné par cette
/// extraction.
enum CollaboratorPreference {
    /// Clé `@AppStorage` partagée par les deux lecteurs, pour qu'ils pointent
    /// sans ambiguïté sur la même valeur persistée.
    static let appStorageKey = "sidebar.collabsFilter"

    static func partition(_ collaborators: [Collaborator], preference: String) -> (top: [Collaborator], rest: [Collaborator]) {
        let active = collaborators
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch preference {
        case "pinned":
            return (active.filter { $0.pinLevel == 2 },
                    active.filter { $0.pinLevel != 2 })
        case "favourites":
            return (active.filter { $0.pinLevel == 1 },
                    active.filter { $0.pinLevel != 1 })
        default:  // both
            return (active.filter { $0.pinLevel >= 1 },
                    active.filter { $0.pinLevel == 0 })
        }
    }

    /// Icône de pastille associée au niveau d'épinglage — partagée par les
    /// deux rendus (`Picker` et sous-menu « Assigné à ») pour rester
    /// visuellement cohérents.
    static func pillIcon(for c: Collaborator) -> String {
        switch c.pinLevel {
        case 2:  return "pin.fill"
        case 1:  return "star.fill"
        default: return "person"
        }
    }
}
