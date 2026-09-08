import Foundation
import SwiftData

/// Niveau d'alerte d'une demande (spec §6.2 : `Sans réponse` warn,
/// `En attente` warn, `Accordé` ok, `Refusé` report ; « une demande sans
/// réponse depuis plus de 60 jours passe en `accent/report` »).
enum RequestLevel: Equatable, Sendable {
    case ok, warn, report
}

/// Une ligne de `RESTÉ EN SUSPENS` (captures 2a, 5b) : soit un sujet reporté,
/// soit un sujet récurrent que rien n'a tranché.
struct StillOpenEntry: Equatable, Sendable {
    var text: String
    /// `1` pour un sujet reporté, le comptage du fil pour un sujet récurrent.
    var occurrences: Int
    var isRecurringTopic: Bool
}

/// Le report des sujets d'ordre du jour non traités — **la seule règle du
/// domaine 1:1 qui écrit sans passer par le magasin du fil**, parce qu'elle
/// crée des lignes (la copie sur la séance suivante).
///
/// Deux principes qui expliquent la forme du code :
/// - **On ne déplace pas, on copie.** L'item de la séance clôturée reste, en
///   `deferred`, avec sa cible : c'est ce qui permet d'afficher `→ 18/09` sur
///   la séance d'origine et de reconstituer l'historique. Déplacer effacerait
///   la trace du report, et le compteur « évoqué 3 fois » avec elle.
/// - **Idempotence par le texte et la cible.** La clôture se rejoue ; sans
///   garde, l'ordre du jour suivant doublerait à chaque tentative.
@MainActor
enum AgendaCarryover {

    /// Au-delà de quoi une demande sans réponse passe en `report` (spec §6.2).
    static let unansweredRequestDays = 60

    // MARK: - Lecture

    /// Ordre manuel, puis date de création à rang égal.
    static func sorted(_ items: [OneOnOneAgendaItem]) -> [OneOnOneAgendaItem] {
        items.sorted { gauche, droite in
            if gauche.order != droite.order { return gauche.order < droite.order }
            return gauche.createdAt < droite.createdAt
        }
    }

    /// Les sujets encore à traiter.
    static func pending(_ items: [OneOnOneAgendaItem]) -> [OneOnOneAgendaItem] {
        sorted(items.filter { $0.state == .todo })
    }

    /// Les sujets d'une séance donnée (ceux qui lui sont rattachés, plus ceux
    /// qui n'ont pas encore de séance : un sujet ajouté hors séance est à
    /// l'ordre du jour de la prochaine).
    static func items(of thread: OneOnOneThread, for meeting: Meeting) -> [OneOnOneAgendaItem] {
        sorted(thread.agendaItems.filter { item in
            item.meeting == nil || item.meeting?.persistentModelID == meeting.persistentModelID
        })
    }

    /// Les demandes du fil (spec §6.2), triées.
    static func requests(of thread: OneOnOneThread) -> [OneOnOneAgendaItem] {
        sorted(thread.agendaItems.filter { $0.kind == .request })
    }

    // MARK: - Report

    /// Migre les sujets non traités de `closing` vers `next`.
    ///
    /// - Parameter next: la séance suivante du fil, `nil` si aucune n'est
    ///   encore planifiée. Dans ce cas les sujets passent quand même
    ///   `deferred` — l'écran doit dire qu'ils ne sont pas traités — et leur
    ///   copie sera créée au prochain appel, une fois la séance connue.
    /// - Returns: les copies créées (vide sur un second appel).
    @discardableResult
    static func carryOver(from closing: Meeting,
                          to next: Meeting?,
                          in thread: OneOnOneThread,
                          in context: ModelContext) -> [OneOnOneAgendaItem] {
        var creees: [OneOnOneAgendaItem] = []

        // 1. Les sujets encore `todo` de la séance clôturée basculent.
        for item in items(of: thread, for: closing) where item.state == .todo {
            item.state = .deferred
            item.deferredToMeeting = next
        }

        // 2. Les sujets déjà `deferred` vers `next` qui n'ont pas encore de
        //    copie sur la séance cible en reçoivent une. Traiter les deux cas
        //    dans la même passe fait que le report « sans cible » de la veille
        //    se rattrape dès qu'une séance est planifiée.
        guard let next else {
            try? context.save()
            return []
        }

        for item in thread.agendaItems where item.state == .deferred {
            // Un item reporté vers une autre séance ne concerne pas cet appel.
            let cibleAttendue = item.deferredToMeeting?.persistentModelID
            if cibleAttendue == nil {
                item.deferredToMeeting = next
            } else if cibleAttendue != next.persistentModelID {
                continue
            }
            guard !hasCopy(of: item, on: next, in: thread) else { continue }

            let copie = OneOnOneAgendaItem(text: item.text,
                                           addedBySide: item.addedBySide,
                                           order: item.order,
                                           state: .todo,
                                           visibility: item.visibility,
                                           kind: item.kind,
                                           requestStatus: item.requestStatus,
                                           requestedAt: item.requestedAt)
            copie.remindedCount = item.remindedCount
            context.insert(copie)
            copie.thread = thread
            copie.meeting = next
            creees.append(copie)
        }

        try? context.save()
        return creees
    }

    /// Vrai quand la séance cible porte déjà un sujet `todo` du même texte.
    ///
    /// La comparaison est faite sur le **texte** et non sur un identifiant de
    /// provenance : l'utilisateur peut aussi avoir ressaisi le sujet à la main
    /// sur la séance suivante, et le lui faire apparaître deux fois serait
    /// incompréhensible.
    private static func hasCopy(of item: OneOnOneAgendaItem,
                                on target: Meeting,
                                in thread: OneOnOneThread) -> Bool {
        thread.agendaItems.contains { candidat in
            candidat.persistentModelID != item.persistentModelID
                && candidat.state == .todo
                && candidat.text == item.text
                && candidat.meeting?.persistentModelID == target.persistentModelID
        }
    }

    /// `→ 18/09` sur un sujet reporté ; `nil` sur tout le reste.
    static func deferredLabel(_ item: OneOnOneAgendaItem) -> String? {
        guard item.state == .deferred, let cible = item.deferredToMeeting else { return nil }
        return "→ \(OneOnOneDateFormat.shortSlashed(cible.date))"
    }

    // MARK: - Resté en suspens

    /// `RESTÉ EN SUSPENS` : les sujets reportés du fil, puis les sujets
    /// récurrents que ne recouvre aucun sujet d'ordre du jour.
    ///
    /// - Parameter recurringTopics: sortie de `RecurringTopicsBuilder.build`,
    ///   réduite à ce qui compte ici. Passée en paramètre plutôt que calculée :
    ///   la fonction reste pure, et l'écran de préparation n'a pas à
    ///   recompter deux fois.
    static func stillOpen(_ thread: OneOnOneThread,
                          recurringTopics: [(label: String, count: Int)]) -> [StillOpenEntry] {
        let reportes = sorted(thread.agendaItems.filter { $0.state == .deferred })
        var entrees = reportes.map {
            StillOpenEntry(text: $0.text, occurrences: 1, isRecurringTopic: false)
        }

        // Un sujet récurrent déjà présent à l'ordre du jour n'est pas « resté
        // en suspens » : il est en train d'être traité.
        let dejaCites = Set(thread.agendaItems.map { normalized($0.text) })
        for topic in recurringTopics {
            let clef = normalized(topic.label)
            guard !dejaCites.contains(where: { $0.contains(clef) || clef.contains($0) }) else { continue }
            entrees.append(StillOpenEntry(text: topic.label,
                                          occurrences: topic.count,
                                          isRecurringTopic: true))
        }
        return entrees
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Demandes

    /// Niveau d'alerte d'une demande. `.ok` pour un sujet ordinaire : il n'y a
    /// pas de réponse à attendre, donc rien à signaler.
    static func requestLevel(_ item: OneOnOneAgendaItem, now: Date) -> RequestLevel {
        guard item.kind == .request else { return .ok }
        switch item.requestStatus {
        case .granted: return .ok
        case .refused: return .report
        case .pending, .waiting:
            guard let depuis = item.requestedAt else { return .warn }
            let jours = now.timeIntervalSince(depuis) / 86_400
            return jours > Double(unansweredRequestDays) ? .report : .warn
        }
    }

    /// `Demandé le 10 juil. · relancé 2 fois` (capture 5a). Chaîne vide si la
    /// demande n'a pas de date : rien à raconter.
    static func requestHistoryLabel(_ item: OneOnOneAgendaItem) -> String {
        guard let depuis = item.requestedAt else { return "" }
        var texte = "Demandé le \(OneOnOneDateFormat.dayMonth(depuis))"
        if item.remindedCount > 0 {
            texte += " · relancé \(item.remindedCount) fois"
        }
        return texte
    }

    /// Relance : le bouton `Relancer` de la capture 5a.
    /// - Returns: le nouveau nombre de relances.
    @discardableResult
    static func remind(_ item: OneOnOneAgendaItem) -> Int {
        item.remindedCount += 1
        return item.remindedCount
    }
}
