import Foundation
import SwiftData

/// Les cinq crans de l'échelle `① COMMENT ÇA VA` (spec §3.3).
///
/// Les libellés sont figés : ils sont la question posée, pas une étiquette
/// d'interface. « Sous tension » n'est pas « Moyen ».
enum MoodLevel: Int, CaseIterable, Identifiable, Sendable {
    case difficile   = 1
    case sousTension = 2
    case caVa        = 3
    case bien        = 4
    case tresBien    = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .difficile:   return "Difficile"
        case .sousTension: return "Sous tension"
        case .caVa:        return "Ça va"
        case .bien:        return "Bien"
        case .tresBien:    return "Très bien"
        }
    }

    /// Le cran d'une valeur brute, bornée. Une restauration douteuse ne doit
    /// pas faire disparaître la barre de l'histogramme.
    static func clamped(_ value: Int) -> MoodLevel {
        MoodLevel(rawValue: min(5, max(1, value))) ?? .caVa
    }
}

/// L'histogramme `MORAL — 6 DERNIERS 1:1`, son delta et sa tendance.
///
/// **L'humeur n'est jamais déduite par un modèle.** Elle est saisie à la main,
/// une fois par séance : une humeur inventée par un LLM depuis une
/// transcription se retrouverait dans un historique que l'utilisateur croit
/// avoir écrit lui-même, et servirait un jour d'argument dans un entretien
/// annuel.
@MainActor
enum MoodTrend {

    /// Le nombre de barres de l'histogramme (spec §3.4).
    static let historyLength = 6

    /// Le demi-point de la règle de tendance (spec §3.4).
    static let threshold = 0.5

    /// Sens de la tendance.
    enum Direction: Equatable, Sendable {
        case enBaisse, stable, enHausse

        /// Le libellé de l'en-tête de la carte. `nil` pour `stable` : la
        /// capture 2b n'affiche rien quand il n'y a rien à signaler, et écrire
        /// « stable » attirerait l'œil pour dire « rien ».
        var label: String? {
            switch self {
            case .enBaisse: return "en baisse"
            case .stable:   return nil
            case .enHausse: return "en hausse"
            }
        }
    }

    /// Un point de l'histogramme.
    struct Point: Equatable, Sendable {
        var value: Int
        var recordedAt: Date

        var level: MoodLevel { MoodLevel.clamped(value) }
    }

    // MARK: - Série

    /// Les `limit` derniers relevés du fil, **du plus ancien au plus récent** —
    /// l'histogramme se lit de gauche à droite.
    static func series(_ thread: OneOnOneThread, limit: Int = historyLength) -> [Point] {
        let tous = thread.moodEntries
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { Point(value: $0.clampedValue, recordedAt: $0.recordedAt) }
        return tous.count <= limit ? tous : Array(tous.suffix(limit))
    }

    /// Le relevé d'une séance donnée, s'il existe.
    static func entry(for meeting: Meeting, in thread: OneOnOneThread) -> MoodEntry? {
        thread.moodEntries.first { $0.meeting?.persistentModelID == meeting.persistentModelID }
    }

    // MARK: - Tendance

    /// « en baisse » si la moyenne des **2 derniers** est inférieure à la
    /// moyenne des **3 précédents** moins un demi-point ; « en hausse » à
    /// l'identique dans l'autre sens (spec §3.4).
    ///
    /// `stable` sous cinq points : la règle est définie sur 2 + 3, et
    /// l'appliquer à trois relevés ferait crier à la baisse au troisième
    /// entretien d'une personne qui vient d'arriver.
    static func direction(_ values: [Int]) -> Direction {
        guard values.count >= 5 else { return .stable }
        let derniers = values.suffix(2)
        let precedents = values.dropLast(2).suffix(3)
        guard precedents.count == 3 else { return .stable }

        let moyenneDerniers = Double(derniers.reduce(0, +)) / 2
        let moyennePrecedents = Double(precedents.reduce(0, +)) / 3

        if moyenneDerniers < moyennePrecedents - threshold { return .enBaisse }
        if moyenneDerniers > moyennePrecedents + threshold { return .enHausse }
        return .stable
    }

    /// La tendance du fil.
    static func direction(of thread: OneOnOneThread) -> Direction {
        direction(series(thread).map(\.value))
    }

    // MARK: - Delta

    /// Le cran courant, le précédent et sa date. `nil` s'il n'y a pas encore
    /// deux relevés : il n'y a alors rien à comparer.
    static func delta(_ thread: OneOnOneThread) -> (current: MoodLevel,
                                                    previous: MoodLevel,
                                                    previousAt: Date)? {
        let serie = series(thread, limit: Int.max)
        guard serie.count >= 2,
              let courant = serie.last,
              let precedent = serie.dropLast().last else { return nil }
        return (courant.level, precedent.level, precedent.recordedAt)
    }

    /// `↓ vs 21 août (Bien)` de la capture 2a. `nil` sans relevé précédent.
    static func deltaLabel(_ thread: OneOnOneThread) -> String? {
        guard let delta = delta(thread) else { return nil }
        let fleche: String
        switch delta.current.rawValue - delta.previous.rawValue {
        case ..<0: fleche = "↓"
        case 0:    fleche = "="
        default:   fleche = "↑"
        }
        return "\(fleche) vs \(OneOnOneDateFormat.dayMonth(delta.previousAt)) (\(delta.previous.label))"
    }

    // MARK: - Explication

    /// La phrase sous l'histogramme : le sujet récurrent le plus cité sur la
    /// période (spec §3.4).
    ///
    /// `nil` en dessous de deux occurrences : un sujet cité une fois n'explique
    /// rien, et présenter une occurrence isolée comme la cause d'une baisse de
    /// moral est une conclusion que la donnée ne porte pas.
    static func explanation(_ topics: [(label: String, count: Int)]) -> String? {
        guard let premier = topics.max(by: { $0.count < $1.count }),
              premier.count >= 2 else { return nil }
        return "Cause citée \(premier.count) fois : \(premier.label)."
    }

    // MARK: - Saisie

    /// Enregistre le cran de la séance, en **remplaçant** un relevé existant.
    ///
    /// Une séance a une humeur, pas un journal d'humeurs : sans remplacement,
    /// une correction en séance ajouterait une deuxième barre au même jour et
    /// décalerait tout l'histogramme.
    @discardableResult
    static func record(_ value: Int,
                       for meeting: Meeting,
                       in thread: OneOnOneThread,
                       in context: ModelContext) -> MoodEntry {
        if let existante = entry(for: meeting, in: thread) {
            existante.value = min(5, max(1, value))
            existante.recordedAt = meeting.date
            try? context.save()
            return existante
        }

        let entree = MoodEntry(value: value, recordedAt: meeting.date)
        context.insert(entree)
        entree.thread = thread
        entree.meeting = meeting
        try? context.save()
        return entree
    }
}
