import Foundation
import SwiftData

/// Les six onglets de l'écran projet de la capture
/// `1d-ecran-projet-pilotage.png`.
///
/// `fiche` est l'actuel `ProjectDetailView` : la refonte n'en supprime rien,
/// elle le range comme dernier onglet (« Fiche complète »).
enum ProjectTab: String, CaseIterable, Sendable {
    case pilotage
    case meetings
    case actions
    case mails
    case documents
    case fiche

    /// L'intitulé de l'onglet, tel que la capture 1d l'écrit.
    var label: String {
        switch self {
        case .pilotage:  return "Pilotage"
        case .meetings:  return "Réunions & CR"
        case .actions:   return "Actions"
        case .mails:     return "Mails"
        case .documents: return "Documents"
        case .fiche:     return "Fiche complète"
        }
    }
}

/// Un écran de la fenêtre principale (décision **D0**).
///
/// **Pourquoi ce type existe.** La barre latérale était une liste de
/// `NavigationLink` à destination inline (`Views/Sidebar.swift`) : rien ne
/// savait sélectionner un écran par programme, et `ContentView.selectedTab`
/// était mort. Or la palette `⌘K`, la section « Récents », le fil d'Ariane de
/// la capture 1d, « Tout voir » et `SearchPopover.onSelectProject` (jusqu'ici
/// un no-op, `MenuBarController.swift`) doivent tous pouvoir dire « ouvre cet
/// écran ». Une route nommée, `Hashable`, est ce qu'une `List(selection:)`
/// attend et ce qu'un routeur peut pousser.
///
/// **Identités.** Un projet et un collaborateur sont désignés par leur
/// `stableID` (`UUID`), comme les jetons inter-fenêtres. `Entity` **n'a pas**
/// de `stableID` : il est désigné par son `PersistentIdentifier`, qui est
/// `Hashable` et `Sendable` — ajouter une colonne à `Entity` pour ce seul
/// besoin ne se justifiait pas dans un lot qui ne change aucun rendu.
enum MainRoute: Hashable, Sendable {

    // MARK: Écrans existants, inchangés

    case dashboard
    case assistant
    case actions
    case meetings
    case notes
    case manager
    case collaborators
    case settings

    // MARK: Écrans de la refonte (lots 1 à 6)

    /// Le Portfolio de la capture `1a-portfolio.png` (lot 2).
    case portfolio
    /// La vue « À risque » de la capture `1f-vue-a-risque.png` (lot 5).
    case atRisk
    /// « Mes réunions projets » — la liste des réunions filtrée (lot 1).
    case projectMeetings
    /// « Actions projets » — la liste des actions filtrée (lot 1).
    case projectActions
    /// « Chercher « x » dans les CR » (décision **D8**, lot 3).
    case searchReports(String)

    // MARK: Fiches

    /// L'écran projet de la capture 1d, sur l'onglet donné (lot 4). Jusque-là,
    /// `MainDetailView` y monte l'actuel `ProjectDetailView`.
    case project(UUID, ProjectTab)
    /// La fiche d'un collaborateur (`CollaboratorFicheView`).
    case collaborator(UUID)
    /// La fiche d'une entité (`EntityDetailView`).
    case entity(PersistentIdentifier)
}
