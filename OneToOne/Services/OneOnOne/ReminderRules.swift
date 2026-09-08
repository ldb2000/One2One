import Foundation
import SwiftData

/// La carte `À NE PAS OUBLIER` de l'écran de préparation (spec §3.4).
///
/// Trois règles, **dans cet ordre**, et l'ordre est le propos : la première
/// chose qu'un manager doit lire en préparant son entretien, c'est ce qu'il
/// doit lui-même à la personne. Trier par gravité ou par date remettrait les
/// félicitations avant les promesses non tenues.
///
/// Pur, à l'exception de `toAgendaItems` qui matérialise le bouton
/// `Mettre à l'ordre du jour`.
@MainActor
enum ReminderRules {

    /// Le seuil de la règle 2 (spec §3.4 : « sujet évoqué ≥ 3 fois sans
    /// décision »).
    static let recurringTopicThreshold = 3

    /// Les trois règles, numérotées comme dans la spec.
    enum Rule: Int, CaseIterable, Sendable {
        case managerCommitmentLate = 1
        case undecidedRecurringTopic = 2
        case unrecognisedWin = 3
    }

    /// Un rappel prêt à afficher.
    struct Reminder: Equatable, Sendable, Identifiable {
        var id: String
        var rule: Rule
        /// La phrase de la capture 2b, telle quelle.
        var text: String
        var tone: OneOnOneTone
    }

    // MARK: - Génération

    /// Les rappels du fil, dans l'ordre des règles.
    static func reminders(for thread: OneOnOneThread, now: Date) -> [Reminder] {
        managerLateReminders(thread, now: now)
            + undecidedTopicReminders(thread, now: now)
            + unrecognisedWinReminders(thread, now: now)
    }

    /// **Règle 1** — un engagement que *je* dois et qui n'est pas tenu :
    /// manqué, ou ouvert avec une échéance passée. Du plus ancien au plus
    /// récent, l'ancienneté étant le signal.
    private static func managerLateReminders(_ thread: OneOnOneThread, now: Date) -> [Reminder] {
        let enRetard = CommitmentLedger.all(thread, side: .manager).filter {
            $0.state == .missed || CommitmentLedger.isOverdue($0, now: now)
        }
        return CommitmentLedger.byLatenessDescending(enRetard, now: now).map { engagement in
            var phrase = "Vous lui devez \(engagement.text)"
            if engagement.deferralCount > 0 {
                phrase += " — reporté \(engagement.deferralCount) fois"
            }
            return Reminder(id: "r1-\(engagement.ensuredStableID.uuidString)",
                            rule: .managerCommitmentLate,
                            text: sentence(phrase),
                            tone: .report)
        }
    }

    /// **Règle 2** — un sujet revenu au moins trois fois qu'aucune décision du
    /// fil ne mentionne.
    ///
    /// « Sans décision » se lit sur les `MeetingNote(kind: .decision)` du fil :
    /// c'est le seul endroit où une décision de 1:1 est écrite. Un sujet dont
    /// une décision parle est tranché, même si le texte de la décision ne
    /// reprend pas le libellé de la famille mot pour mot — d'où la comparaison
    /// par **famille de lexique** et non par chaîne.
    private static func undecidedTopicReminders(_ thread: OneOnOneThread, now: Date) -> [Reminder] {
        let tranchees = decidedFamilies(thread, now: now)
        let dejaALOrdreDuJour = agendaFamilies(thread)
        return RecurringTopicsBuilder.build(thread, now: now, since: nil)
            .filter { $0.count >= recurringTopicThreshold
                      && !tranchees.contains($0.family)
                      && !dejaALOrdreDuJour.contains($0.family) }
            .map { topic in
                Reminder(id: "r2-\(topic.family.rawValue)",
                         rule: .undecidedRecurringTopic,
                         text: "\(topic.label) évoquée \(topic.count) fois, jamais tranchée.",
                         tone: .warn)
            }
    }

    /// Les familles déjà portées par un sujet **à traiter** de l'ordre du jour.
    ///
    /// La carte s'appelle `À NE PAS OUBLIER` : un sujet déjà inscrit à l'ordre
    /// du jour ne risque pas d'être oublié, et le rappeler à côté de lui
    /// donnerait deux fois la même ligne à l'écran. Même règle que
    /// `AgendaCarryover.stillOpen`.
    ///
    /// Un sujet `deferred`, lui, **ne couvre pas** : il n'a justement pas été
    /// traité.
    private static func agendaFamilies(_ thread: OneOnOneThread) -> Set<RecurringTopicFamily> {
        var familles: Set<RecurringTopicFamily> = []
        for item in thread.agendaItems where item.state == .todo {
            if let famille = RecurringTopicsBuilder.family(of: item.text) {
                familles.insert(famille)
            }
        }
        return familles
    }

    /// Les familles qu'une décision du fil a tranchées.
    private static func decidedFamilies(_ thread: OneOnOneThread,
                                        now: Date) -> Set<RecurringTopicFamily> {
        var tranchees: Set<RecurringTopicFamily> = []
        for reunion in OneOnOneThreadStore.meetings(of: thread, now: now) {
            for note in reunion.timedNotes where note.kind == .decision {
                if let famille = RecurringTopicsBuilder.family(of: note.text) {
                    tranchees.insert(famille)
                }
            }
        }
        return tranchees
    }

    /// **Règle 3** — une action de la personne, close depuis le dernier
    /// entretien, qu'aucun feedback du fil ne cite.
    ///
    /// « Depuis le dernier 1:1 » et pas « depuis toujours » : sans cette borne,
    /// chaque préparation ressortirait tout l'historique des réussites, et la
    /// carte deviendrait un mur qu'on cesse de lire.
    private static func unrecognisedWinReminders(_ thread: OneOnOneThread, now: Date) -> [Reminder] {
        guard let collaborateur = thread.collaborator else { return [] }
        let depuis = OneOnOneThreadStore.lastMeetingDate(of: thread, now: now)
        let feedbacks = feedbackTexts(thread, now: now)

        let closes = collaborateur.assignedTasks.filter { action in
            guard action.isCompleted, let close = action.completedAt, close <= now else { return false }
            if let depuis, close < depuis { return false }
            return true
        }

        return closes
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .filter { action in
                let titre = RecurringTopicsBuilder.fold(action.title)
                guard !titre.isEmpty else { return false }
                return !feedbacks.contains { $0.contains(titre) }
            }
            .map { action in
                Reminder(id: "r3-\(action.persistentModelID.hashValue)",
                         rule: .unrecognisedWin,
                         text: sentence("Féliciter pour \(action.title)"),
                         tone: .ok)
            }
    }

    private static func feedbackTexts(_ thread: OneOnOneThread, now: Date) -> [String] {
        OneOnOneThreadStore.meetings(of: thread, now: now)
            .flatMap(\.timedNotes)
            .filter { $0.kind == .feedback }
            .map { RecurringTopicsBuilder.fold($0.text) }
    }

    /// Termine une phrase par un point, sans en doubler un déjà présent :
    /// « la présentation COSUI du 1er sept. » finit déjà par un point
    /// d'abréviation, et « sept.. » se voit.
    private static func sentence(_ text: String) -> String {
        let propre = text.trimmingCharacters(in: .whitespaces)
        return propre.hasSuffix(".") ? propre : propre + "."
    }

    // MARK: - Mise à l'ordre du jour

    /// Le bouton `Mettre à l'ordre du jour` (capture 2b) : un sujet par rappel,
    /// à la suite de l'ordre du jour existant.
    ///
    /// **Idempotent par le texte** : le bouton n'est pas désactivé après le
    /// premier clic (rien ne le dit à l'écran), donc un second clic ne doit
    /// rien ajouter.
    @discardableResult
    static func toAgendaItems(_ reminders: [Reminder],
                              for thread: OneOnOneThread,
                              role: OneOnOneSide,
                              in context: ModelContext) -> [OneOnOneAgendaItem] {
        var prochainRang = (thread.agendaItems.map(\.order).max() ?? -1) + 1
        var existants = Set(thread.agendaItems.map(\.text))
        var crees: [OneOnOneAgendaItem] = []

        for rappel in reminders {
            guard !existants.contains(rappel.text) else { continue }
            let item = OneOnOneAgendaItem(text: rappel.text,
                                          addedBySide: role,
                                          order: prochainRang,
                                          state: .todo,
                                          visibility: OneOnOneConfidentiality.defaultVisibility(for: role))
            context.insert(item)
            item.thread = thread
            crees.append(item)
            existants.insert(rappel.text)
            prochainRang += 1
        }

        if !crees.isEmpty { try? context.save() }
        return crees
    }
}
