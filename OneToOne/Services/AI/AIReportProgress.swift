import Foundation

/// État affichable sans conserver le contenu du raisonnement du modèle.
struct AIReportProgress {
    enum Phase: Equatable { case preparing, waiting, reasoning, writing, extracting }
    private(set) var phase: Phase = .preparing
    private(set) var characters = 0
    private(set) var phaseStartedAt = Date()
    private(set) var lastActivityAt = Date()

    mutating func start(_ phase: Phase, at now: Date = Date()) {
        self.phase = phase
        characters = 0
        phaseStartedAt = now
        lastActivityAt = now
    }

    mutating func receive(_ activity: AIClient.Activity, at now: Date = Date()) {
        let next: Phase
        let count: Int
        switch activity {
        case .waiting: next = .waiting; count = 0
        case .reasoning(let value): next = .reasoning; count = value
        case .writing(let value): next = .writing; count = value
        }
        // La seconde passe reste identifiée comme extraction, quelle que soit
        // l'activité du modèle. Aucun JSON intermédiaire ne devient le rapport.
        if phase != .extracting && phase != next { start(next, at: now) }
        characters = count
        lastActivityAt = now
    }

    var label: String {
        switch phase {
        case .preparing: return "Préparation du contexte"
        case .waiting: return "Attente du modèle"
        case .reasoning: return "Raisonnement · \(characters) car. reçus"
        case .writing: return "Rédaction · \(characters) car."
        case .extracting: return "Rapport disponible · extraction des actions et décisions"
        }
    }

    func warning(at now: Date = Date()) -> String? {
        guard now.timeIntervalSince(phaseStartedAt) >= 120 else { return nil }
        let activity = now.timeIntervalSince(lastActivityAt) >= 60
            ? "Aucune nouvelle activité reçue depuis plus d’une minute."
            : "Le modèle est toujours actif."
        let preservation = phase == .extracting ? " Le rapport rédigé est sauvegardé." : ""
        return "Cette étape dure plus de 2 minutes. \(activity)\(preservation) Vous pouvez annuler depuis la file des tâches."
    }
}
