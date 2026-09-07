import Foundation
import SwiftData

/// La **seule** écriture propre à l'écran de préparation du 1:1 subi hors
/// `PrepToAgenda` : le composeur `Ajouter…` de `CE QUE JE VEUX OBTENIR`
/// (capture 5b).
///
/// Un fichier de magasin à part, comme `OneOnOnePrepStore` au lot 12 :
/// `WantedItemsBuilder` et `CollabPrepModel` sont purs par construction, et y
/// glisser un `context.insert` les rendrait intestables et ferait mentir leur
/// documentation.
@MainActor
enum CollaboratorPrepStore {

    /// Ajoute un sujet privé à porter au prochain entretien.
    ///
    /// `private` sans discussion (spec §6.1) : ce que j'écris en préparant mon
    /// propre entretien ne devient visible que par le bouton
    /// `Partager les sujets`, qui est un geste explicite.
    ///
    /// Rattaché à la **séance préparée** : un sujet écrit ici est à porter à
    /// celle-là, pas au prochain entretien indéterminé.
    ///
    /// - Returns: le sujet créé, ou `nil` si le texte est vide — un sujet sans
    ///   énoncé n'est pas un sujet, et une case à cocher muette dans cette
    ///   carte serait impossible à interpréter en séance.
    @discardableResult
    static func addWantedTopic(text: String,
                               for meeting: Meeting,
                               in thread: OneOnOneThread,
                               in context: ModelContext) -> OneOnOneAgendaItem? {
        let propre = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return nil }

        let rang = (thread.agendaItems.map(\.order).max() ?? -1) + 1
        let item = OneOnOneAgendaItem(
            text: propre,
            addedBySide: .collaborator,
            order: rang,
            state: .todo,
            visibility: OneOnOneConfidentiality.defaultVisibility(for: thread.myRole),
            kind: .topic)
        context.insert(item)
        item.thread = thread
        item.meeting = meeting
        try? context.save()
        return item
    }
}
