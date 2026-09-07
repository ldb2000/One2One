import Foundation

/// Les cinq familles de sujets récurrents du domaine 1:1 (spec §3.4 : « chips
/// `label · n` colorées par famille — charge → warn, carrière → violet,
/// reconnaissance → ok »).
///
/// Le lexique est en **français replié** (sans accent, minuscules) et cherché
/// en sous-chaîne : la saisie en séance est rapide et fautive, `mobilite`,
/// `Mobilité` et `MOBILITE` doivent tomber dans la même famille.
enum RecurringTopicFamily: String, CaseIterable, Identifiable, Sendable {
    case charge
    case carriere
    case reconnaissance
    case formation
    case astreinte

    var id: String { rawValue }

    /// Le libellé de la chip.
    var label: String {
        switch self {
        case .charge:         return "Charge de travail"
        case .carriere:       return "Mobilité archi"
        case .reconnaissance: return "Reconnaissance"
        case .formation:      return "Formation"
        case .astreinte:      return "Astreintes"
        }
    }

    /// Formes repliées cherchées en sous-chaîne.
    var lexicon: [String] {
        switch self {
        case .charge:
            return ["charge", "sature", "rythme", "capacite", "debordé", "deborde", "surmene"]
        case .carriere:
            return ["carriere", "mobilite", "evolution", "promotion", "archi", "poste"]
        case .reconnaissance:
            return ["reconnaissance", "felicit", "merci", "valorisation", "visibilite"]
        case .formation:
            return ["formation", "competence", "certification", "former", "tutorat"]
        case .astreinte:
            return ["astreinte", "garde", "week-end", "weekend", "permanence", "compensation"]
        }
    }

    var tone: OneOnOneTone {
        switch self {
        case .charge:         return .warn
        case .carriere:       return .oneOnOne
        case .reconnaissance: return .ok
        case .formation:      return .oneOnOne
        case .astreinte:      return .warn
        }
    }
}

/// Un sujet récurrent : une famille, son libellé et son comptage.
struct RecurringTopic: Equatable, Sendable, Identifiable {
    var label: String
    var count: Int
    var family: RecurringTopicFamily

    var id: String { family.rawValue }
    var tone: OneOnOneTone { family.tone }
}

/// Le comptage des sujets récurrents du fil — **pur**.
///
/// Calculé et non stocké (programme §3) : les sources sont l'ordre du jour, les
/// notes et les thèmes, qui changent à chaque séance. Une table de plus serait
/// un troisième endroit à tenir en phase, et le premier à se désynchroniser.
@MainActor
enum RecurringTopicsBuilder {

    /// Les sujets récurrents du fil, du plus cité au moins cité.
    ///
    /// - Parameters:
    ///   - now: les réunions à venir ne comptent pas — on n'y a rien dit.
    ///   - since: borne basse d'historique (`nil` = tout le fil). Sert à la
    ///     phrase « évoquée 3 fois **depuis avril** » de la capture 2b.
    ///
    /// Les sujets d'**ordre du jour** échappent au filtre `now` : ils décrivent
    /// ce qui est sur la table, y compris pour la séance qui vient. Les exclure
    /// ferait disparaître de l'écran de préparation le sujet qu'on est en train
    /// d'y écrire.
    static func build(_ thread: OneOnOneThread, now: Date, since: Date?) -> [RecurringTopic] {
        var comptes: [RecurringTopicFamily: Int] = [:]

        for item in thread.agendaItems {
            if let since, item.createdAt < since { continue }
            if let famille = family(of: item.text) { comptes[famille, default: 0] += 1 }
        }

        for reunion in OneOnOneThreadStore.meetings(of: thread, now: now) {
            if let since, reunion.date < since { continue }
            for note in reunion.timedNotes {
                if let famille = family(of: note.text) { comptes[famille, default: 0] += 1 }
            }
            for theme in reunion.tags {
                if let famille = family(of: theme.name) { comptes[famille, default: 0] += 1 }
            }
        }

        return comptes
            .map { RecurringTopic(label: $0.key.label, count: $0.value, family: $0.key) }
            .sorted { gauche, droite in
                if gauche.count != droite.count { return gauche.count > droite.count }
                return gauche.label < droite.label
            }
    }

    /// La famille d'un texte, ou `nil` s'il n'entre dans aucun lexique.
    ///
    /// Un texte qui touche deux familles compte pour la **première** de
    /// `allCases` : trancher, plutôt que compter deux fois. Sinon la somme des
    /// chips dépasse le nombre de lignes et plus personne ne sait ce qu'elles
    /// mesurent.
    static func family(of text: String) -> RecurringTopicFamily? {
        let replie = fold(text)
        guard !replie.isEmpty else { return nil }
        return RecurringTopicFamily.allCases.first { famille in
            famille.lexicon.contains { replie.contains($0) }
        }
    }

    /// `Charge de travail · 5` — le texte de la chip.
    static func chipLabel(_ topic: RecurringTopic) -> String {
        "\(topic.label) · \(topic.count)"
    }

    /// Forme comparable : sans accent, en minuscules.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
