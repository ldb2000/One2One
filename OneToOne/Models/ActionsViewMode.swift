import Foundation

/// Mode d'affichage d'une liste d'actions (sélecteur de vue).
///
/// Déclaré ici et non plus dans `ActionsPanel.swift` (programme §2.1) : le rail
/// d'actions du lot 3 et l'écran `ActionsListView` en dépendent tous les deux,
/// et un type partagé n'a pas à vivre dans la vue de l'un d'eux.
///
/// Les cinq cas restent : `ActionsListView` propose toujours Kanban et Post-it.
/// C'est le **contexte réunion** qui n'en garde que trois (spec §2.5 : « Kanban
/// et Post-it supprimés du contexte réunion »), et c'est `railCases` qui le dit.
enum ActionsViewMode: String, CaseIterable {
    case liste, kanban, calendar, eisenhower, sticky

    /// Les trois vues du rail d'actions de 330 px (spec §2.5, décision D10 :
    /// Calendrier et Eisenhower restent dans le rail, en rendu compact).
    static let railCases: [ActionsViewMode] = [.liste, .calendar, .eisenhower]

    var label: String {
        switch self {
        case .liste: return "Liste"
        case .kanban: return "Kanban"
        case .calendar: return "Calendrier"
        case .eisenhower: return "Eisenhower"
        case .sticky: return "Post-it"
        }
    }

    var systemImage: String {
        switch self {
        case .liste: return "list.bullet"
        case .kanban: return "rectangle.split.3x1"
        case .calendar: return "calendar"
        case .eisenhower: return "square.grid.2x2"
        case .sticky: return "note.text"
        }
    }
}
