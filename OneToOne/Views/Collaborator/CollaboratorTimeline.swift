import Foundation
import SwiftData

/// Type d'une ligne du fil — ce que porte la pastille.
///
/// Les actions n'y figurent pas : la spec le dit par ses compteurs
/// (`Tout 38 · 1:1 6 · Notes 9 · Décisions 4 · Réunions 19` s'additionne
/// exactement). Elles vivent dans la colonne d'état, où l'on peut les cocher.
enum TimelineKind: String, CaseIterable, Hashable {
    case oneToOne, decision, note, meeting

    /// Libellé de la pastille, en capitales dans la vue.
    var pill: String {
        switch self {
        case .oneToOne: return "1:1"
        case .decision: return "Décision"
        case .note:     return "Note"
        case .meeting:  return "Réunion"
        }
    }
}

/// Une ligne du fil.
struct TimelineItem: Identifiable, Equatable {
    let id: String
    /// La réunion d'où vient la ligne — y compris pour une décision, qui n'a
    /// pas d'existence propre. Cliquer une ligne doit ouvrir cette réunion.
    let meetingID: PersistentIdentifier
    let kind: TimelineKind
    let date: Date
    let title: String
    let subtitle: String
    /// Nombre d'actions produites par la réunion — le badge de la ligne.
    /// C'est la seule métrique qui justifie de rouvrir une réunion ; le badge
    /// des versions précédentes comptait des *participants*.
    let actionCount: Int

    /// Vrai si la réunion a produit au moins une action. Ce qu'un groupe de
    /// mois replié affiche, déplié, se limite à celles-là : « un Echange
    /// activité sans note ni action ne mérite pas une ligne dans la fiche de
    /// quelqu'un ».
    var producedActions: Bool { actionCount > 0 }
}

/// Construit le fil chronologique unique d'une fiche collaborateur.
///
/// Réunions, 1:1, notes et décisions partagent un axe temps : les séparer en
/// quatre listes oblige à recoller la chronologie de tête. Le fil les fusionne
/// et les distingue par une pastille.
enum CollaboratorTimeline {

    static func build(for collaborator: Collaborator) -> [TimelineItem] {
        var items: [TimelineItem] = []

        for meeting in collaborator.meetings {
            let key = String(describing: meeting.persistentModelID)
            let count = meeting.tasks.count

            items.append(TimelineItem(
                id: key,
                meetingID: meeting.persistentModelID,
                kind: kind(of: meeting),
                date: meeting.date,
                title: title(of: meeting),
                subtitle: subtitle(of: meeting, actionCount: count),
                actionCount: count
            ))

            // Une décision est portée par sa réunion : elle en prend la date,
            // faute d'en avoir une propre.
            for (index, entry) in meeting.decisionEntries.enumerated() {
                items.append(TimelineItem(
                    id: "\(key)#d\(index)",
                    meetingID: meeting.persistentModelID,
                    kind: .decision,
                    date: meeting.date,
                    title: entry.text,
                    subtitle: entry.settledAt == nil ? "Actée en séance" : "Actée en séance · soldée",
                    actionCount: 0
                ))
            }
        }

        return items.sorted { $0.date > $1.date }
    }

    /// Compteurs des segments (`Tout` étant le total).
    static func counts(of items: [TimelineItem]) -> [TimelineKind: Int] {
        items.reduce(into: [:]) { tally, item in tally[item.kind, default: 0] += 1 }
    }

    // MARK: - Rendu d'une ligne

    private static func kind(of meeting: Meeting) -> TimelineKind {
        switch meeting.kind {
        case .note:              return .note
        case .oneToOne, .manager: return .oneToOne
        default:                 return .meeting
        }
    }

    private static func title(of meeting: Meeting) -> String {
        let titre = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard titre.isEmpty else { return titre }
        return "Réunion du \(meeting.date.formatted(date: .long, time: .omitted))"
    }

    private static func subtitle(of meeting: Meeting, actionCount: Int) -> String {
        var parts: [String] = []
        let others = meeting.participants.count - 1
        if others > 0 { parts.append("\(meeting.participants.count) participants") }
        parts.append(actionCount == 0 ? "Aucune action produite"
                                      : "\(actionCount) action\(actionCount > 1 ? "s" : "") produite\(actionCount > 1 ? "s" : "")")
        return parts.joined(separator: " · ")
    }
}
