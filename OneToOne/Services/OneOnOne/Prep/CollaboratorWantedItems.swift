import Foundation
import SwiftData

/// `CE QUE JE VEUX OBTENIR` de l'écran de préparation du 1:1 subi (capture 5b,
/// spec §6.3) — **pur**.
///
/// Ce ne sont pas des lignes nouvelles : ce sont **mes sujets privés**, ceux
/// que la carte `CE QUE JE VEUX DIRE` de la séance (lot 13) montre déjà. La
/// préparation les reprend cochés — je veux les porter, c'est pour cela que je
/// les ai écrits — et décocher signifie « pas cette fois », sans les effacer.
///
/// **Un sujet déjà porté par `RESTÉ SANS RÉPONSE` en est retiré.** Sur une
/// carte de dix lignes, la même demande écrite deux fois donne l'impression de
/// deux sujets distincts, et la cocher deux fois la porterait deux fois à
/// l'ordre du jour. L'exclusion se fait par **famille de lexique**, comme
/// `AgendaCarryover.stillOpen` et `ReminderRules.agendaFamilies` : un sujet
/// qu'aucun lexique ne reconnaît n'est jamais exclu, faute de savoir de quoi il
/// parle.
@MainActor
enum WantedItemsBuilder {

    // MARK: - Intitulés

    static let title = "CE QUE JE VEUX OBTENIR"
    static let emptyInvite =
        "Aucun sujet — écrivez ci-dessous ce que vous voulez obtenir de cet entretien."
    /// Le champ pointillé du pied de carte (capture 5b).
    static let composerPlaceholder = "Ajouter…"
    /// L'aide de la case à cocher : décocher, c'est renoncer pour cette fois.
    static let checkboxHelp = "Décocher pour ne pas porter ce sujet cette fois-ci"

    // MARK: - Construction

    /// Mes sujets privés encore à traiter, dans leur ordre manuel.
    ///
    /// - Parameters:
    ///   - thread: le fil, et non la séance : un sujet écrit hors séance est à
    ///     porter au prochain entretien, ce qui est précisément le cas d'un
    ///     sujet ajouté depuis cet écran-ci.
    ///   - unanswered: les lignes de `RESTÉ SANS RÉPONSE`, pour ne pas afficher
    ///     deux fois le même sujet.
    static func build(_ thread: OneOnOneThread,
                      excluding unanswered: [UnansweredItemsBuilder.Item]) -> [OneOnOneAgendaItem] {
        let dejaPortees = Set(unanswered.compactMap(\.family))
        return AgendaCarryover.sorted(thread.agendaItems)
            .filter { item in
                guard item.kind == .topic,
                      item.state == .todo,
                      item.visibility == .private else { return false }
                guard let famille = RecurringTopicsBuilder.family(of: item.text) else { return true }
                return !dejaPortees.contains(famille)
            }
    }
}
