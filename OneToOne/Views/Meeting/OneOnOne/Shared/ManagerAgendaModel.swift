import Foundation
import SwiftData

/// Le modèle de vue de l'ordre du jour co-construit et de `RESTÉ EN SUSPENS`
/// (capture 2a, colonne gauche) — **pur** sauf pour l'écriture explicite
/// (`move`, `add`), qui a besoin du contexte.
///
/// Le report lui-même n'est **pas** ici : il vit dans `AgendaCarryover`
/// (lot 10), et c'est lui qui décide de ce qu'un sujet non traité devient.
@MainActor
enum ManagerAgendaModel {

    // MARK: - Intitulés

    static let title = "ORDRE DU JOUR"
    /// La pilule qui dit que l'ordre du jour appartient aux deux (spec §3.3).
    static let badge = "co-construit"
    static let composerPlaceholder = "Ajouter un sujet…"
    static let emptyInvite = "Aucun sujet — écrivez le premier ci-dessous, ou reprenez-en un du suspens."
    static let pendingTitle = "RESTÉ EN SUSPENS"
    static let pendingEmptyInvite = "Rien qui traîne : tout ce qui a été évoqué a été tranché."

    // MARK: - Lignes

    /// Une ligne de l'ordre du jour, prête à rendre.
    struct Row: Identifiable {
        var item: OneOnOneAgendaItem
        /// Traité ou reporté : dans les deux cas, il ne sera pas discuté ici.
        var isStruck: Bool
        /// `→ 18/09` sur un sujet reporté.
        var deferredLabel: String?
        /// Initiales de celui qui a ajouté le sujet (avatar 16 px).
        var initials: String

        var id: PersistentIdentifier { item.persistentModelID }
    }

    /// Les sujets de la séance, dans l'ordre manuel.
    static func rows(for meeting: Meeting,
                     in thread: OneOnOneThread,
                     ownerName: String) -> [Row] {
        AgendaCarryover.items(of: thread, for: meeting).map { item in
            Row(item: item,
                isStruck: item.state != .todo,
                deferredLabel: AgendaCarryover.deferredLabel(item),
                initials: initials(for: item.addedBySide, in: thread, ownerName: ownerName))
        }
    }

    /// Initiales du côté qui a ajouté : les miennes pour mon côté du fil,
    /// celles de la personne pour l'autre.
    static func initials(for side: OneOnOneSide,
                         in thread: OneOnOneThread,
                         ownerName: String) -> String {
        CommitmentsRailModel.initials(for: side, in: thread, ownerName: ownerName)
    }

    // MARK: - Écritures

    /// Réordonne les sujets de la séance et **compacte** les rangs de 0 à n−1.
    ///
    /// Sans compactage, deux glissers de suite produisent des rangs égaux, et
    /// `AgendaCarryover.sorted` retombe alors sur la date de création : l'ordre
    /// choisi à la main serait silencieusement perdu.
    static func move(for meeting: Meeting,
                     in thread: OneOnOneThread,
                     from source: IndexSet,
                     to destination: Int,
                     in context: ModelContext) {
        var sujets = AgendaCarryover.items(of: thread, for: meeting)
        sujets.move(fromOffsets: source, toOffset: destination)
        for (rang, sujet) in sujets.enumerated() {
            sujet.order = rang
        }
        try? context.save()
    }

    /// Ajoute un sujet en fin de liste, du côté de celui qui l'écrit.
    ///
    /// - Returns: `nil` pour une ligne blanche — un sujet vide n'est pas un
    ///   sujet, et il resterait dans l'ordre du jour de la séance suivante.
    @discardableResult
    static func add(_ text: String,
                    for meeting: Meeting,
                    in thread: OneOnOneThread,
                    role: OneOnOneSide,
                    in context: ModelContext) -> OneOnOneAgendaItem? {
        let propre = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return nil }

        let rang = (AgendaCarryover.items(of: thread, for: meeting).map(\.order).max() ?? -1) + 1
        let sujet = OneOnOneAgendaItem(text: propre,
                                       addedBySide: role,
                                       order: rang,
                                       visibility: OneOnOneConfidentiality
                                           .defaultVisibility(for: role))
        context.insert(sujet)
        sujet.thread = thread
        sujet.meeting = meeting
        try? context.save()
        return sujet
    }

    // MARK: - Resté en suspens

    /// Les lignes de `RESTÉ EN SUSPENS` : ce que `AgendaCarryover.stillOpen`
    /// rend, **moins** ce que l'ordre du jour de cette séance montre déjà.
    ///
    /// Le sujet reporté de la capture (`Point objectifs S2 → 18/09`) est barré
    /// dans l'ordre du jour, juste au-dessus : le répéter dans la carte
    /// suivante ferait croire à deux sujets distincts.
    static func pendingEntries(_ thread: OneOnOneThread,
                               for meeting: Meeting,
                               now: Date) -> [StillOpenEntry] {
        let recurrents = RecurringTopicsBuilder.build(thread, now: now, since: nil)
            .map { (label: $0.label, count: $0.count) }
        let dejaVisibles = Set(AgendaCarryover.items(of: thread, for: meeting).map(\.text))
        return AgendaCarryover.stillOpen(thread, recurringTopics: recurrents)
            .filter { !dejaVisibles.contains($0.text) }
    }

    /// `Mobilité archi — évoqué 3 fois, jamais tranché` pour un sujet
    /// récurrent ; le texte seul pour un sujet reporté, qui porte déjà sa
    /// cible.
    static func pendingLabel(_ entry: StillOpenEntry) -> String {
        guard entry.isRecurringTopic else { return entry.text }
        guard entry.occurrences > 1 else { return "\(entry.text) — évoqué une fois" }
        return "\(entry.text) — évoqué \(entry.occurrences) fois, jamais tranché"
    }
}
