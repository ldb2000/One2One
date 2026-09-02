import Foundation

/// Tout ce que l'agent aura le droit de voir, et rien d'autre.
///
/// C'est un DTO `Sendable` volontairement pauvre : ni `ActionTask`, ni
/// `ModelContext`, ni `Meeting`. Deux raisons. La construction du dossier reste
/// une fonction pure, donc testable sans base. Et surtout, **ce type est la
/// frontière de confidentialité** : l'audio, les transcriptions brutes, les
/// autres collaborateurs et les autres projets n'ont pas de champ ici, donc
/// aucun chemin de code ne peut les faire fuir dans le dossier de travail.
struct AgentWorkspaceInput: Sendable {

    struct Action: Sendable {
        var title: String
        /// Ce que l'auteur a écrit dans la feuille de lancement.
        var request: String
        var dueDate: Date?
        var isUrgent: Bool
        var isImportant: Bool
        /// Libellé du destinataire (« Moi », « Collaborateur », « Chef »).
        var audience: String
        var comments: [String]
    }

    struct Project: Sendable {
        var name: String
        var phase: String?
        var sponsor: String?
        var entity: String?
        var summary: String?
    }

    struct Collaborator: Sendable {
        var name: String
        var role: String?
        var notes: String?
    }

    /// Un compte rendu **rédigé** — jamais la transcription brute.
    struct Meeting: Sendable {
        var title: String
        var date: Date
        var report: String
    }

    struct Mail: Sendable {
        var subject: String
        var date: Date
        var sender: String
        var body: String
    }

    struct Alert: Sendable {
        var title: String
        var severity: String
        var detail: String
    }

    var action: Action
    /// Format imposé par l'auteur, ou `nil` pour laisser l'agent choisir.
    var expectedFormat: String?
    var project: Project?
    var collaborator: Collaborator?
    var meetings: [Meeting]
    var mails: [Mail]
    var alerts: [Alert]
}

/// Un fichier du dossier de travail : chemin **relatif** et contenu.
struct AgentWorkspaceFile: Equatable, Sendable {
    let path: String
    let contents: String
}
