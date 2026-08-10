import Foundation
import SwiftData

/// Écritures des commandes `/ajout-*` de l'assistant. Sorties de la vue pour
/// être testables : `ChatbotView` garde l'analyse de la saisie et les messages
/// de retour, ce service crée les objets.
///
/// Chaque entrée va vers son modèle naturel : une information devient une note
/// (`Meeting` de kind `.note`), une action devient un `ActionTask` — elle porte
/// un état d'achèvement, elle appartient donc à la vue « Actions ».
@MainActor
enum ChatbotEntryCommands {

    /// Information datée sur un projet. Le titre porte la catégorie que
    /// `ProjectInfoEntry` stockait dans un champ dédié.
    static func addProjectInfo(content: String,
                               project: Project,
                               in context: ModelContext) throws -> Meeting {
        let title = project.phase == "Build" ? "REX" : "Info projet"
        let note = NoteFactory.make(body: content, title: title, project: project)
        context.insert(note)
        try context.save()
        SpotlightIndexService.shared.index(meeting: note)
        return note
    }

    /// Information sur un collaborateur dans le contexte d'un projet.
    static func addCollaboratorInfo(content: String,
                                    project: Project,
                                    collaborator: Collaborator,
                                    in context: ModelContext) throws -> Meeting {
        let note = NoteFactory.make(body: content,
                                    title: "Info \(collaborator.name)",
                                    project: project,
                                    collaborator: collaborator)
        context.insert(note)
        try context.save()
        SpotlightIndexService.shared.index(meeting: note)
        return note
    }

    /// Action déléguée à un collaborateur sur un projet.
    static func addCollaboratorAction(content: String,
                                      project: Project,
                                      collaborator: Collaborator,
                                      in context: ModelContext) throws -> ActionTask {
        let task = ActionTask(title: content)
        task.project = project
        task.collaborator = collaborator
        task.destinataire = .collaborateur
        context.insert(task)
        try context.save()
        return task
    }
}
