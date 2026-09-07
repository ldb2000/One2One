import Foundation

/// Ce que l'écran de préparation a besoin de savoir en plus des trois règles :
/// **est-ce que le bouton a déjà fait son travail ?**
///
/// `ReminderRules.toAgendaItems` est idempotent par le texte (lot 10), donc un
/// second clic ne duplique rien — mais un bouton qui reste actif alors qu'il
/// n'a plus rien à faire ne dit pas la vérité, et on finit par cliquer deux
/// fois pour vérifier.
extension ReminderRules {

    /// Vrai quand **chaque** rappel est déjà un sujet de l'ordre du jour du
    /// fil, quel que soit son état : un sujet traité ou reporté a bien été mis
    /// à l'ordre du jour, et le remettre en créerait un doublon barré.
    ///
    /// Vrai aussi sur une liste vide — il n'y a alors rien à verser, et
    /// l'écran affiche son invite plutôt qu'un bouton actif sans effet.
    static func areAllOnAgenda(_ reminders: [Reminder],
                               in thread: OneOnOneThread) -> Bool {
        let existants = Set(thread.agendaItems.map(\.text))
        return reminders.allSatisfy { existants.contains($0.text) }
    }
}
