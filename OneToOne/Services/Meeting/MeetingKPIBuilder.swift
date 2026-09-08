import Foundation

/// Les quatre indicateurs du bandeau de l'espace Réunion (spec §2.3).
///
/// Valeur immuable, `Equatable` : la vue la reçoit et n'a plus rien à calculer.
/// C'est ce qui permet de vérifier les chiffres — présence, non assignées,
/// première décision, points de risque — sans monter d'écran.
struct MeetingKPI: Equatable, Sendable {

    struct Presence: Equatable, Sendable {
        var present: Int = 0
        var total: Int = 0
        var percent: Int = 0
        /// Noms complets des participants, **triés**, pour l'infobulle des
        /// pastilles.
        var names: [String] = []
        /// Initiales des participants, dans le même ordre que `names`, pour
        /// `AvatarStack`.
        var initials: [String] = []
    }

    struct Actions: Equatable, Sendable {
        /// Les actions **retenues** de la réunion (ouvertes + faites), au sens
        /// de `MeetingActionCounts` : les abandonnées n'en sont plus.
        var total: Int = 0
        /// Ouvertes sans responsable — affiché en `accent/report` (spec §2.3).
        var unassigned: Int = 0
        var done: Int = 0
        /// Part faite, entre 0 et 1. Vaut 0 quand il n'y a aucune action :
        /// une barre pleine sur zéro action serait un mensonge.
        var doneFraction: Double = 0
    }

    struct Decisions: Equatable, Sendable {
        var count: Int = 0
        /// Combien portent sur le budget — le « dont 1 budget » de la capture.
        var budgetCount: Int = 0
        /// Première décision, affichée en ellipsis sous le compteur.
        var first: String?
    }

    /// Niveau d'un risque, du plus grave au plus faible. L'ordre des cas est
    /// l'ordre d'affichage des points (spec §2.3).
    enum Level: String, Comparable, Sendable {
        case critique, eleve, modere, faible

        private var rang: Int {
            switch self {
            case .critique: return 0
            case .eleve:    return 1
            case .modere:   return 2
            case .faible:   return 3
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rang < rhs.rang }
    }

    struct Risks: Equatable, Sendable {
        var count: Int = 0
        var criticalCount: Int = 0
        /// Niveaux des points affichés, du plus grave au plus faible, au plus
        /// `MeetingKPIBuilder.maxRiskDots`.
        var levels: [Level] = []
        /// Risques non représentés par un point : rendus en `+n`.
        var overflow: Int = 0
    }

    var presence = Presence()
    var actions = Actions()
    var decisions = Decisions()
    var risks = Risks()
}

/// Calcule le bandeau depuis une réunion. Aucune écriture, aucun effet de
/// bord : la vue peut l'appeler à chaque rendu.
enum MeetingKPIBuilder {

    /// Nombre maximal de points de risque avant le `+n` (spec §2.3).
    static let maxRiskDots = 8

    @MainActor
    static func build(meeting: Meeting) -> MeetingKPI {
        var kpi = MeetingKPI()
        kpi.presence = presence(meeting: meeting)
        kpi.actions = actions(meeting: meeting)
        kpi.decisions = decisions(meeting: meeting)
        kpi.risks = risks(meeting: meeting)
        return kpi
    }

    // MARK: - Présence

    @MainActor
    private static func presence(meeting: Meeting) -> MeetingKPI.Presence {
        // Ordre **par nom**, et non l'ordre du tableau de relation : SwiftData
        // ne garantit pas l'ordre d'une relation « à plusieurs », et une pile
        // d'avatars qui se réordonne d'un rendu à l'autre est un défaut visible
        // — la capture, elle, ne fixe pas d'ordre significatif.
        let ordonnes = meeting.participants.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let statuts = ordonnes.map { meeting.participantStatus(for: $0) }
        let stats = PresenceStats.compute(statuses: statuts)
        return MeetingKPI.Presence(
            present: stats.present,
            total: stats.total,
            percent: stats.percent,
            names: ordonnes.map(\.name),
            initials: ordonnes.map { initials($0.name) }
        )
    }

    /// Deux lettres, toujours : une pastille d'une seule lettre est illisible
    /// à 19 px, et le `?` vaut mieux qu'un cercle vide.
    ///
    /// Un prénom composé (`Pierre-Yves`) donne les initiales de ses deux
    /// parties (`PY`), comme sur la capture — le tiret est un séparateur de
    /// mots, pas une lettre.
    static func initials(_ name: String) -> String {
        let mots = name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "'" || $0 == "." })
            .filter { !$0.isEmpty }
        guard let premier = mots.first else { return "?" }
        if mots.count >= 2, let second = mots[1].first, let p = premier.first {
            return String([p, second]).uppercased()
        }
        return String(premier.prefix(2)).uppercased()
    }

    // MARK: - Actions

    /// Les chiffres viennent de `MeetingActionCounts`, la seule définition du
    /// « nombre d'actions » de l'écran — c'est elle qui écarte les actions
    /// abandonnées et les lignes en attente de suppression, et qui réserve
    /// « non assignées » aux actions ouvertes. Le calcul vivait ici, dupliquait
    /// la règle de porteur de `ActionsRailGrouping.aUnPorteur` et ne filtrait
    /// aucun statut : le bandeau annonçait « ACTIONS 3 · 2 non assignées »
    /// au-dessus d'un tableau d'une seule ligne.
    @MainActor
    private static func actions(meeting: Meeting) -> MeetingKPI.Actions {
        let compteurs = MeetingActionCounts.compute(meeting: meeting)
        return MeetingKPI.Actions(
            total: compteurs.retenues,
            unassigned: compteurs.sansPorteur,
            done: compteurs.faites,
            doneFraction: compteurs.doneFraction
        )
    }

    // MARK: - Décisions

    @MainActor
    private static func decisions(meeting: Meeting) -> MeetingKPI.Decisions {
        let lignes = meeting.decisions
        return MeetingKPI.Decisions(
            count: lignes.count,
            budgetCount: lignes.filter(mentionneLeBudget).count,
            first: lignes.first
        )
    }

    /// « budget » sans casse ni diacritique : une décision écrite « BUDGET
    /// gelé » ou « Rebudgétisation » compte tout autant.
    private static func mentionneLeBudget(_ ligne: String) -> Bool {
        ligne.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "fr_FR"))
            .contains("budget")
    }

    // MARK: - Risques

    @MainActor
    private static func risks(meeting: Meeting) -> MeetingKPI.Risks {
        let alertes = meeting.meetingAlerts.filter { !$0.isResolved }
        let niveaux = alertes.map { level(fromSeverity: $0.severity) }.sorted()
        return MeetingKPI.Risks(
            count: alertes.count,
            criticalCount: niveaux.filter { $0 == .critique }.count,
            levels: Array(niveaux.prefix(maxRiskDots)),
            overflow: max(0, niveaux.count - maxRiskDots)
        )
    }

    /// `ProjectAlert.severityRaw` est un texte libre historique (« Critique »,
    /// « Élevé », « Modéré », « Faible »). Une valeur inattendue retombe sur
    /// « modéré » : mieux vaut un point de la mauvaise teinte qu'un risque qui
    /// disparaît du bandeau.
    static func level(fromSeverity severite: String) -> MeetingKPI.Level {
        let normalise = severite
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalise {
        case "critique": return .critique
        case "eleve":    return .eleve
        case "modere":   return .modere
        case "faible":   return .faible
        default:         return .modere
        }
    }
}
