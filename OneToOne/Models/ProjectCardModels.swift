import Foundation
import SwiftData

/// État d'un jalon de projet (spec §1.3 `ProjectCard.milestones[].state`).
enum MilestoneState: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned    = "planned"
    case inProgress = "inProgress"
    case done       = "done"
    case late       = "late"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned:    return "Prévu"
        case .inProgress: return "En cours"
        case .done:       return "Fait"
        case .late:       return "En retard"
        }
    }
}

/// Un jalon de la fiche projet (lot 9). Les **risques** ne sont pas un nouveau
/// modèle : `ProjectAlert` existe déjà et porte sévérité, détail et réunion
/// d'origine.
@Model
final class ProjectMilestone {

    var stableID: UUID? = nil
    var label: String = ""
    var dueAt: Date?

    var stateRaw: String = MilestoneState.planned.rawValue
    var state: MilestoneState {
        get { MilestoneState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue }
    }

    /// Ordre manuel dans la fiche.
    var order: Int = 0
    var createdAt: Date = Date()

    var project: Project?

    init(label: String = "",
         dueAt: Date? = nil,
         state: MilestoneState = .planned,
         order: Int = 0) {
        self.stableID = UUID()
        self.label = label
        self.dueAt = dueAt
        self.stateRaw = state.rawValue
        self.order = order
        self.createdAt = Date()
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

/// Un interlocuteur du projet (spec §1.3 `ProjectCard.contacts`).
///
/// Un nom libre, pas une relation vers `Collaborator` : la fiche liste des
/// sponsors, métiers et prestataires qui n'ont pas de fiche dans l'annuaire et
/// n'en auront jamais. Le rattachement à un `Collaborator` connu passe déjà par
/// `Project.projectManager` et `Project.technicalArchitect`.
@Model
final class ProjectContact {

    var stableID: UUID? = nil
    var name: String = ""
    var role: String = ""
    var order: Int = 0
    var createdAt: Date = Date()

    var project: Project?

    init(name: String = "", role: String = "", order: Int = 0) {
        self.stableID = UUID()
        self.name = name
        self.role = role
        self.order = order
        self.createdAt = Date()
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}
