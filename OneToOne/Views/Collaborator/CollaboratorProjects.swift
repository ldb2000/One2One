import Foundation
import SwiftData

/// Les projets où un collaborateur est impliqué.
///
/// **Pas « portés ».** Le rôle — Chef de Projet, Architecte Technique,
/// Développeur — est un attribut de la **personne**, pas une désignation par
/// projet ; il vit dans `Collaborator.role` et s'affiche dans le sous-titre de
/// la fiche. C'est pourquoi `Project.projectManager` et
/// `Project.technicalArchitect` sont vides sur 62 des 63 projets du store
/// réel : ce n'est pas ainsi que l'organisation est pensée. S'appuyer dessus
/// donnerait un bloc structurellement vide, pour tout le monde, pour toujours.
///
/// L'implication se lit donc là où elle se manifeste : **les réunions
/// auxquelles la personne participe, et les actions qui lui sont assignées.**
enum CollaboratorProjects {

    /// Les projets où le collaborateur apparaît, du plus récemment fréquenté
    /// au plus ancien — le bloc de la fiche n'en montre que quatre, ce sont
    /// donc les plus récents qui comptent.
    ///
    /// Les notes sont écartées : une réunion avec soi-même ne dit rien d'une
    /// implication dans un projet partagé.
    static func involved(in collaborator: Collaborator) -> [Project] {
        var dernierContact: [PersistentIdentifier: Date] = [:]
        var projets: [PersistentIdentifier: Project] = [:]

        func retenir(_ projet: Project, _ date: Date) {
            let id = projet.persistentModelID
            projets[id] = projet
            dernierContact[id] = max(dernierContact[id] ?? .distantPast, date)
        }

        for meeting in MeetingStatsScope.held(collaborator.meetings) {
            if let projet = meeting.project { retenir(projet, meeting.date) }
        }
        for task in collaborator.assignedTasks {
            if let projet = task.project { retenir(projet, task.createdAt ?? .distantPast) }
        }

        return projets.values.sorted {
            let gauche = dernierContact[$0.persistentModelID] ?? .distantPast
            let droite = dernierContact[$1.persistentModelID] ?? .distantPast
            if gauche != droite { return gauche > droite }
            return $0.code < $1.code
        }
    }
}
