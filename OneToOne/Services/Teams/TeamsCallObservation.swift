import Foundation

/// Décision rendue par un tick d'observation.
enum TeamsObservationDecision: Equatable {
    case none
    case callStarted
    case callEnded
}

/// État interne de l'observation Teams. Sans dépendance framework : c'est ce
/// qui rend la machine testable sans lancer d'application.
struct TeamsCallState: Equatable {
    enum Phase: String, Equatable {
        /// Rien en vue.
        case idle
        /// Une fenêtre plausible est apparue, on attend qu'elle se stabilise.
        case observing
        /// Appel considéré comme actif ; `callStarted` a été émis.
        case stable
    }
    var phase: Phase = .idle
    /// Instant depuis lequel la fenêtre est présente sans interruption.
    var stableSince: Date?
    /// Instant depuis lequel la fenêtre a disparu, alors qu'on était en `stable`.
    var absentSince: Date?
}

/// Entrée d'un tick d'observation. `isTeamsWindowPresent` vaut vrai si une
/// fenêtre Teams est au premier plan, ou — quand l'énumération est disponible —
/// si elle existe quelque part (cf. `TeamsCallMonitor`).
struct TeamsObservationInput: Equatable {
    let isTeamsWindowPresent: Bool
    let windowTitle: String
    let now: Date
}

/// Heuristique « un appel Teams est en cours », en fonctions pures.
///
/// Philosophie (spec §3) : **pas de popup vaut mieux qu'un faux positif**. Un
/// popup non sollicité crée une réunion et démarre un enregistrement — bruit,
/// dérangement, ménage à faire. Les seuils ci-dessous sont volontairement hauts.
enum TeamsCallObservation {

    /// Durée de présence ininterrompue avant de conclure à un appel.
    static let stabilityDelay: TimeInterval = 5
    /// Durée d'absence avant de conclure à la fin de l'appel.
    ///
    /// Avec `stabilityDelay`, elle garantit aussi qu'au moins 35 s séparent
    /// deux `callStarted` : repasser par `idle` coûte 30 s d'absence, puis
    /// revenir à `stable` coûte 5 s de présence. C'est ainsi qu'est honorée
    /// la fusion « à moins de 30 s » de la spec §3 — sans compteur dédié,
    /// qui serait du code mort.
    static let absenceDelay: TimeInterval = 30

    /// Mots, en forme normalisée (minuscules, sans accents), dont la présence
    /// dans le titre d'une fenêtre Teams fait suspecter un appel. Liste **en
    /// dur** : voir spec §14 Q12. L'ajuster demande de constater des faux
    /// positifs réels, pas de les imaginer.
    static let callTokens: Set<String> = [
        "call", "meeting", "appel", "reunion", "conference", "meet", "visio"
    ]

    /// Vrai si le titre contient l'un des `callTokens`. La comparaison passe
    /// par `AgendaProjectResolver.normalizedKey`, qui replie les accents et la
    /// ponctuation : « Réunion hebdo | Microsoft Teams » → « reunion hebdo
    /// microsoft teams ».
    static func titleLooksLikeCall(_ title: String) -> Bool {
        let tokens = AgendaProjectResolver.normalizedKey(title).split(separator: " ")
        return tokens.contains { callTokens.contains(String($0)) }
    }

    /// Avance la machine d'un tick et rend la décision correspondante.
    /// `state` est modifié en place ; la fonction reste pure au sens où sa
    /// sortie ne dépend que de `state` et `input`.
    static func step(state: inout TeamsCallState, input: TeamsObservationInput) -> TeamsObservationDecision {
        let matches = input.isTeamsWindowPresent && titleLooksLikeCall(input.windowTitle)

        guard matches else {
            switch state.phase {
            case .stable:
                guard let since = state.absentSince else {
                    state.absentSince = input.now
                    return .none
                }
                guard input.now.timeIntervalSince(since) >= absenceDelay else { return .none }
                state.phase = .idle
                state.absentSince = nil
                state.stableSince = nil
                return .callEnded
            case .observing:
                // Simple clignotement : on repart de zéro sans rien émettre.
                state.phase = .idle
                state.stableSince = nil
                return .none
            case .idle:
                return .none
            }
        }

        state.absentSince = nil

        switch state.phase {
        case .idle:
            state.phase = .observing
            state.stableSince = input.now
            return .none

        case .observing:
            guard let since = state.stableSince,
                  input.now.timeIntervalSince(since) >= stabilityDelay else { return .none }
            state.phase = .stable
            return .callStarted

        case .stable:
            return .none
        }
    }
}
