import Foundation

/// La **seule** définition du « nombre d'actions » d'une réunion, et des trois
/// sous-ensembles qui s'en déduisent.
///
/// Elle existe parce que l'écran de réunion en portait deux, sans le dire : le
/// bandeau d'indicateurs et la nav du mode Relire comptaient `meeting.tasks`
/// **tel quel**, tandis que le tableau et le rail filtraient
/// `status == .open`. Une action abandonnée quittait donc le tableau tout en
/// restant dans le bandeau — « ACTIONS 3 · 2 non assignées » au-dessus d'un
/// tableau d'une seule ligne assignée (retour d'usage du 8 septembre 2026).
///
/// Les règles, une fois pour toutes :
///
/// - **Vivante** : la ligne n'est pas en attente de suppression. `isDeleted`
///   passe à vrai dès `context.delete(_:)`, mais la relation `meeting.tasks`
///   ne la lâche qu'au `save()` : sans cette garde, tout compteur lu entre les
///   deux annonce une action qui n'existe plus.
/// - **Retenue** : vivante et non abandonnée — ouverte ou faite. C'est le
///   portefeuille d'actions de la réunion, celui qu'annonce le bandeau et que
///   sa barre d'avancement remplit. Compter les seules ouvertes ferait tomber
///   « ACTIONS » à zéro à mesure qu'on coche, ce qui serait un mensonge exact.
/// - **Ouverte** : ce que listent le tableau du poste de pilotage et le rail —
///   d'où leur compteur d'onglet.
/// - **Sans porteur** : ouverte et sans responsable, au sens de
///   `ActionsRailGrouping.aUnPorteur` (un nom non résolu compte). Une action
///   faite ou abandonnée n'a plus de dette d'assignation.
///
/// Aucune écriture, aucun effet de bord : les vues l'appellent dans leur
/// `body`, ce qui les abonne aux propriétés lues et fait suivre les compteurs.
struct MeetingActionCounts: Equatable, Sendable {

    /// Ouvertes + faites : le portefeuille de la réunion.
    var retenues: Int = 0
    var ouvertes: Int = 0
    var faites: Int = 0
    var abandonnees: Int = 0
    /// Ouvertes sans responsable.
    var sansPorteur: Int = 0

    /// Part faite du portefeuille, entre 0 et 1. Vaut 0 sans action retenue :
    /// une barre pleine sur zéro action serait un mensonge.
    var doneFraction: Double {
        retenues > 0 ? Double(faites) / Double(retenues) : 0
    }

    // MARK: - Sous-ensembles

    /// Les lignes qui ne sont pas en attente de suppression.
    @MainActor
    static func vivantes(_ tasks: [ActionTask]) -> [ActionTask] {
        tasks.filter { !$0.isDeleted }
    }

    /// Le portefeuille : vivantes, non abandonnées.
    @MainActor
    static func retenues(_ tasks: [ActionTask]) -> [ActionTask] {
        vivantes(tasks).filter { $0.status != .dropped }
    }

    /// Les ouvertes : ce que listent le tableau et le rail.
    @MainActor
    static func ouvertes(_ tasks: [ActionTask]) -> [ActionTask] {
        vivantes(tasks).filter { $0.status == .open }
    }

    // MARK: - Compteurs

    @MainActor
    static func compute(_ tasks: [ActionTask]) -> MeetingActionCounts {
        var compteurs = MeetingActionCounts()
        for tache in vivantes(tasks) {
            switch tache.status {
            case .dropped:
                compteurs.abandonnees += 1
            case .done:
                compteurs.retenues += 1
                compteurs.faites += 1
            case .open:
                compteurs.retenues += 1
                compteurs.ouvertes += 1
                if !ActionsRailGrouping.aUnPorteur(tache) { compteurs.sansPorteur += 1 }
            }
        }
        return compteurs
    }

    @MainActor
    static func compute(meeting: Meeting) -> MeetingActionCounts {
        compute(meeting.tasks)
    }
}
