import Foundation
import SwiftData

/// `RESTÉ SANS RÉPONSE` de l'écran de préparation du 1:1 **subi** (capture 5b,
/// spec §6.3) — **pur** : il ne lit que le fil, n'écrit rien.
///
/// C'est le critère chantier 5 n° 4 : « une promesse du manager non tenue
/// remonte **automatiquement** à la préparation suivante ». Rien à ressaisir,
/// rien à cocher pour que la ligne apparaisse : elle est là parce que la
/// promesse n'a pas été tenue.
///
/// ## Les trois sources
///
/// 1. **Les promesses du manager non tenues** — manquées, ou ouvertes dont
///    l'échéance est passée (`CommitmentLedger`, même définition que la règle 1
///    de `ReminderRules` et que `CollaboratorSessionModel.isLate`).
/// 2. **Les sujets évoqués au moins trois fois qu'aucune décision ne tranche**
///    (`RecurringTopicsBuilder`, seuil `ReminderRules.recurringTopicThreshold`).
/// 3. **Les demandes sans réponse** du fil — `pending` ou `waiting`
///    (`AgendaCarryover.requests`, la liste même de `MyRequestsCard` au lot 13).
///
/// ## Pourquoi la règle 2 est *adaptée* et non appelée
///
/// `ReminderRules.reminders` écarte les familles déjà portées par un sujet
/// `todo` de l'ordre du jour : sur la carte manager `À NE PAS OUBLIER` c'est
/// juste — un sujet inscrit ne risque pas d'être oublié. Ici c'est l'inverse du
/// propos : un sujet que je porte depuis trois séances **sans obtenir de
/// décision** est exactement ce que cet écran doit me remettre sous les yeux.
/// Le seuil, le lexique et l'exclusion par décision sont donc repris ; celle
/// par l'ordre du jour ne l'est pas.
///
/// ## Une ligne par famille
///
/// Les trois sources se recoupent — la demande « Compensation des astreintes »
/// et la promesse « Grille de compensation des astreintes » sont le même sujet.
/// Sans regroupement, l'écran afficherait quatre lignes là où la capture en
/// montre deux, et cocher les deux moitiés du même sujet le porterait deux fois
/// à l'ordre du jour. Le regroupement se fait par `RecurringTopicFamily`, comme
/// `AgendaCarryover.stillOpen` le fait déjà ; une source qu'aucun lexique ne
/// reconnaît reste une ligne à part.
///
/// Dans un groupe, **la source la plus forte parle** : une parole donnée et non
/// tenue est le fait le plus lourd d'un entretien, avant le sujet qui l'a fait
/// naître, avant la demande qui l'a ouvert. Et `depuis le …` prend la **plus
/// ancienne** date du groupe : c'est l'ancienneté qui plaide.
@MainActor
enum UnansweredItemsBuilder {

    // MARK: - Intitulés

    static let title = "RESTÉ SANS RÉPONSE"
    static let emptyInvite =
        "Rien en suspens — aucune promesse en retard, aucune demande sans réponse, "
        + "aucun sujet resté trois fois sans décision."
    /// L'aide de la case à cocher : cocher, c'est porter la ligne en séance.
    static let checkboxHelp = "Cocher pour porter cette ligne à l'ordre du jour de l'entretien"

    // MARK: - Le modèle d'une ligne

    /// D'où sort la ligne. Décide du préfixe qu'elle prend en devenant un sujet
    /// d'ordre du jour (`PrepToAgenda.prefix(for:)`), et de qui parle quand
    /// deux sources tombent dans la même famille.
    enum Source: String, Sendable, Equatable, CaseIterable {
        case promise
        case topic
        case request

        /// Du plus fort au moins fort : `promise` > `topic` > `request`.
        var weight: Int {
            switch self {
            case .promise: return 3
            case .topic:   return 2
            case .request: return 1
            }
        }
    }

    /// Une ligne prête à rendre : une case à cocher, un libellé, une
    /// ancienneté.
    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        var text: String
        /// L'instant d'origine de la ligne. `nil` pour un sujet récurrent : le
        /// comptage n'a pas de date de naissance, et en inventer une mentirait
        /// sur l'ancienneté du sujet.
        var since: Date?
        var source: Source
        /// `depuis le 24 juil.`, ou une chaîne vide quand la ligne n'a pas de
        /// date.
        var sinceLabel: String
        /// La famille de lexique de la ligne, quand un lexique la reconnaît.
        /// Sert au regroupement, et à écarter de `CE QUE JE VEUX OBTENIR` un
        /// sujet que cette carte porte déjà (`WantedItemsBuilder`).
        var family: RecurringTopicFamily?
    }

    // MARK: - Construction

    /// Les lignes du bloc, de la plus ancienne à la plus récente.
    ///
    /// - Parameter now: l'instant de référence — celui de l'ouverture de
    ///   l'écran. Il décide de ce qui est « en retard ».
    static func build(_ thread: OneOnOneThread, now: Date) -> [Item] {
        let candidats = promiseCandidates(thread, now: now)
            + topicCandidates(thread, now: now)
            + requestCandidates(thread)
        return regrouped(candidats)
    }

    // MARK: - Les trois sources

    /// Source 1 — les promesses du manager non tenues.
    ///
    /// La date est `promisedAt` et non `dueAt` : c'est l'ancienneté de la
    /// **parole donnée** qui pèse dans un entretien, et l'échéance peut avoir
    /// été repoussée trois fois depuis (même règle que
    /// `CollaboratorSessionModel.promisedAtPill`).
    private static func promiseCandidates(_ thread: OneOnOneThread, now: Date) -> [Item] {
        let enRetard = CommitmentLedger.all(thread, side: .manager).filter {
            $0.state == .missed || CommitmentLedger.isOverdue($0, now: now)
        }
        return CommitmentLedger.byLatenessDescending(enRetard, now: now).map { engagement in
            var texte = "\(engagement.text) promise"
            if engagement.deferralCount > 0 {
                texte += engagement.deferralCount == 1
                    ? ", 1 report"
                    : ", \(engagement.deferralCount) reports"
            }
            return item(id: "promesse-\(engagement.ensuredStableID.uuidString)",
                        text: texte,
                        since: engagement.promisedAt,
                        source: .promise,
                        family: RecurringTopicsBuilder.family(of: engagement.text))
        }
    }

    /// Source 2 — les sujets évoqués au moins trois fois que rien ne tranche.
    private static func topicCandidates(_ thread: OneOnOneThread, now: Date) -> [Item] {
        let tranchees = decidedFamilies(thread, now: now)
        return RecurringTopicsBuilder.build(thread, now: now, since: nil)
            .filter { $0.count >= ReminderRules.recurringTopicThreshold
                      && !tranchees.contains($0.family) }
            .map { sujet in
                item(id: "sujet-\(sujet.family.rawValue)",
                     // L'écriture de la capture, au mot près.
                     text: "\(sujet.label) — \(sujet.count) fois évoquée, jamais tranchée",
                     since: nil,
                     source: .topic,
                     family: sujet.family)
            }
    }

    /// Les familles qu'une décision du fil a tranchées — même lecture que la
    /// règle 2 du lot 10 : « sans décision » se lit sur les
    /// `MeetingNote(kind: .decision)` du fil, le seul endroit où une décision
    /// de 1:1 est écrite.
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

    /// Source 3 — les demandes du fil qui attendent encore une réponse.
    ///
    /// `granted` et `refused` en sont exclues : une demande tranchée a eu sa
    /// réponse, même quand elle ne plaît pas. C'est le même partage que
    /// `AgendaCarryover.requestLevel`, qui ne compte les jours que pour
    /// `pending` et `waiting`.
    private static func requestCandidates(_ thread: OneOnOneThread) -> [Item] {
        AgendaCarryover.requests(of: thread)
            .filter { $0.requestStatus == .pending || $0.requestStatus == .waiting }
            .map { demande in
                item(id: "demande-\(demande.ensuredStableID.uuidString)",
                     text: demande.text,
                     since: demande.requestedAt,
                     source: .request,
                     family: RecurringTopicsBuilder.family(of: demande.text))
            }
    }

    // MARK: - Regroupement

    /// Une ligne par famille, la source la plus forte au libellé, la plus
    /// ancienne date à l'ancienneté.
    private static func regrouped(_ candidats: [Item]) -> [Item] {
        var groupes: [String: Item] = [:]
        var ordreDArrivee: [String] = []

        for candidat in candidats {
            let clef = key(of: candidat)
            guard let retenu = groupes[clef] else {
                groupes[clef] = candidat
                ordreDArrivee.append(clef)
                continue
            }
            // La plus ancienne date du groupe, quel que soit le libellé retenu.
            let date = [retenu.since, candidat.since].compactMap { $0 }.min()
            var fusionne = candidat.source.weight > retenu.source.weight ? candidat : retenu
            fusionne.since = date
            fusionne.sinceLabel = label(for: date)
            groupes[clef] = fusionne
        }

        let lignes = ordreDArrivee.compactMap { groupes[$0] }
        // Les lignes datées d'abord, de la plus ancienne à la plus récente : la
        // plus vieille est celle qu'on doit porter en premier. Celles qui n'ont
        // pas de date ferment la liste plutôt que de prendre une place
        // qu'aucune ancienneté ne justifie.
        return lignes.sorted { gauche, droite in
            switch (gauche.since, droite.since) {
            case let (.some(a), .some(b)):
                if a != b { return a < b }
                return gauche.text < droite.text
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return gauche.text < droite.text
            }
        }
    }

    /// La clef de regroupement : la famille de lexique de la ligne, ou la ligne
    /// elle-même quand aucun lexique ne la reconnaît.
    private static func key(of item: Item) -> String {
        guard let famille = item.family else { return "seul-\(item.id)" }
        return "famille-\(famille.rawValue)"
    }

    // MARK: - Outils

    private static func item(id: String,
                             text: String,
                             since: Date?,
                             source: Source,
                             family: RecurringTopicFamily?) -> Item {
        Item(id: id, text: text, since: since, source: source,
             sinceLabel: label(for: since), family: family)
    }

    /// `depuis le 24 juil.`, ou rien du tout : « depuis toujours » n'est pas
    /// une ancienneté, c'est un aveu d'ignorance.
    static func label(for date: Date?) -> String {
        guard let date else { return "" }
        return "depuis le \(OneOnOneDateFormat.dayMonth(date))"
    }
}
