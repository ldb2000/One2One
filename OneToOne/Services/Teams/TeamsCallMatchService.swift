import Foundation

/// Résultat de l'appariement entre un appel détecté et l'agenda.
enum TeamsCallMatch: Equatable {
    /// Aucun événement plausible : on n'émet **aucun** popup (spec §10).
    case none
    case matched(CalendarMeetingEvent)
    /// Plusieurs événements plausibles. Le coordinateur ne choisit pas à la
    /// place de l'utilisateur : il n'émet pas de popup de démarrage.
    case ambiguous([CalendarMeetingEvent])
}

/// Apparie un instant à un événement d'agenda. Fonctions pures : le service ne
/// lit pas EventKit lui-même, l'appelant lui passe les événements du jour
/// (`CalendarAgendaService.events(for:)`).
enum TeamsCallMatchService {

    /// Tolérance autour du `startDate` de l'événement (spec D-2).
    static let tolerance: TimeInterval = 120

    /// Retourne l'événement dont le `startDate` tombe dans
    /// `[instant − tolerance, instant + tolerance]`.
    ///
    /// Les événements annulés et ceux sans lien Teams sont écartés : sans lien
    /// Teams, rien ne dit que l'appel détecté est celui-là.
    static func match(events: [CalendarMeetingEvent],
                      at instant: Date,
                      tolerance: TimeInterval = tolerance) -> TeamsCallMatch {
        let candidates = events.filter { event in
            guard !event.isCancelled, !event.isAllDay else { return false }
            guard let url = event.teamsJoinURL, !url.isEmpty else { return false }
            return abs(event.startDate.timeIntervalSince(instant)) <= tolerance
        }
        switch candidates.count {
        case 0:  return .none
        case 1:  return .matched(candidates[0])
        default: return .ambiguous(candidates)
        }
    }
}
