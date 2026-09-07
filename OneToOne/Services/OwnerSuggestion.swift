import Foundation
import SwiftData

/// Qui devrait porter cette action ? (spec §2.5 : « Suggestion de responsable :
/// locuteur de la phrase source, puis dernier porteur d'une action de même
/// préfixe de titre, puis participant unique restant ».)
///
/// Trois règles **ordonnées**, et un `nil` assumé quand aucune ne conclut : une
/// suggestion fausse coûte plus cher qu'une absence de suggestion, parce qu'un
/// clic suffit à l'accepter. C'est pour cela que la règle 3 exige un
/// participant **unique** : à deux candidats libres, deviner c'est se tromper
/// une fois sur deux.
///
/// Fonctions pures : elles lisent le graphe SwiftData, n'écrivent rien, et
/// n'ont besoin d'aucune session graphique pour être vérifiées.
@MainActor
enum OwnerSuggestion {

    /// Le responsable suggéré, ou `nil`.
    ///
    /// - Parameters:
    ///   - task: l'action à pourvoir.
    ///   - meeting: la réunion qui la porte (ses segments et ses participants).
    ///   - projectTasks: les actions du projet, pour la règle du préfixe. Les
    ///     passer en paramètre plutôt que de les chercher ici garde la fonction
    ///     testable et laisse l'appelant décider du périmètre.
    static func suggestion(for task: ActionTask,
                           in meeting: Meeting,
                           projectTasks: [ActionTask]) -> Collaborator? {
        if let locuteur = locuteurDeLaSource(task, in: meeting) { return locuteur }
        if let porteur = dernierPorteurDeMemePrefixe(task, parmi: projectTasks) { return porteur }
        return participantUniqueRestant(task, in: meeting)
    }

    // MARK: - Règle 1 — le locuteur de la phrase source

    /// Le locuteur du segment dont l'action est née.
    ///
    /// Ne vaut que pour une source `transcript` : une note ou une capture n'a
    /// pas de locuteur, et l'auteur d'une note c'est toujours moi.
    /// `stableID` est comparé tel quel, sans `ensuredStableID` : une fonction
    /// de lecture n'écrit pas dans le store pour répondre à une question.
    static func locuteurDeLaSource(_ task: ActionTask, in meeting: Meeting) -> Collaborator? {
        guard let ref = task.sourceRef, ref.kind == .transcript else { return nil }
        return meeting.transcriptSegments.first { $0.stableID == ref.stableID }?.speaker
    }

    // MARK: - Règle 2 — le dernier porteur de même préfixe

    /// Le porteur le plus récent d'une action du projet dont le titre partage
    /// le préfixe de trois mots.
    static func dernierPorteurDeMemePrefixe(_ task: ActionTask,
                                            parmi tasks: [ActionTask]) -> Collaborator? {
        let cible = prefixe(task.title)
        guard !cible.isEmpty else { return nil }
        return tasks
            .filter { autre in
                autre.persistentModelID != task.persistentModelID
                    && autre.collaborator != nil
                    && prefixe(autre.title) == cible
            }
            .max { gauche, droite in
                (gauche.createdAt ?? .distantPast) < (droite.createdAt ?? .distantPast)
            }?
            .collaborator
    }

    /// Les trois premiers mots du titre, normalisés : minuscules, diacritiques
    /// repliés, ponctuation traitée en séparateur (« Vérifier l'état des
    /// comptes GitLab » → `verifier l etat`).
    ///
    /// Trois mots, parce que deux confondent « Vérifier l'état » avec
    /// « Vérifier le budget », et que quatre ne rapprochent plus rien.
    static func prefixe(_ titre: String) -> String {
        let plie = titre.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: Locale(identifier: "fr_FR"))
        let mots = plie
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(3)
        return mots.joined(separator: " ")
    }

    // MARK: - Règle 3 — le participant unique restant

    /// Le seul participant de la réunion qui ne porte encore aucune de ses
    /// actions. `nil` dès qu'ils sont deux, ou zéro.
    static func participantUniqueRestant(_ task: ActionTask, in meeting: Meeting) -> Collaborator? {
        let dejaPorteurs = Set(
            meeting.tasks
                .filter { $0.persistentModelID != task.persistentModelID }
                .compactMap { $0.collaborator?.persistentModelID }
        )
        let libres = meeting.participants.filter { !dejaPorteurs.contains($0.persistentModelID) }
        return libres.count == 1 ? libres.first : nil
    }
}
