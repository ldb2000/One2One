import Testing
import Foundation
@testable import OneToOne

/// L'appariement est le second garde-fou contre les faux positifs : même si la
/// fenêtre Teams ressemble à un appel, aucun popup n'est émis sans événement
/// d'agenda commençant à ±2 min. Ces tests verrouillent la tolérance.
@Suite("TeamsCallMatchService — appariement appel ↔ agenda")
struct TeamsCallMatchServiceTests {

    private let now = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private func event(_ id: String, startOffset: TimeInterval, cancelled: Bool = false) -> CalendarMeetingEvent {
        let start = now.addingTimeInterval(startOffset)
        return CalendarMeetingEvent(
            id: id,
            title: "Réunion \(id)",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarTitle: "Pro",
            attendees: [],
            teamsJoinURL: "https://teams.microsoft.com/l/meetup-join/\(id)",
            isCancelled: cancelled,
            isAllDay: false)
    }

    @Test("Un événement commencé il y a 1 min correspond")
    func matchesOneMinuteAgo() {
        let e = event("A", startOffset: -60)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .matched(e))
    }

    @Test("Un événement commençant dans 2 min pile correspond")
    func matchesExactlyTwoMinutesAhead() {
        let e = event("A", startOffset: 120)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .matched(e))
    }

    @Test("Un événement commencé il y a 3 min ne correspond pas")
    func noMatchThreeMinutesAgo() {
        #expect(TeamsCallMatchService.match(events: [event("A", startOffset: -180)], at: now) == .none)
    }

    @Test("Aucun événement → aucune correspondance")
    func noEvents() {
        #expect(TeamsCallMatchService.match(events: [], at: now) == .none)
    }

    @Test("Deux événements dans la fenêtre → ambiguïté, pas de choix arbitraire")
    func ambiguousMatch() {
        let a = event("A", startOffset: -30)
        let b = event("B", startOffset: 30)
        #expect(TeamsCallMatchService.match(events: [a, b], at: now) == .ambiguous([a, b]))
    }

    @Test("Un événement annulé est ignoré")
    func cancelledIsIgnored() {
        #expect(TeamsCallMatchService.match(events: [event("A", startOffset: 0, cancelled: true)],
                                            at: now) == .none)
    }

    @Test("Un événement sur la journée entière est ignoré, même dans la fenêtre")
    func allDayIsIgnored() {
        let start = now
        let e = CalendarMeetingEvent(id: "A", title: "Séminaire",
                                     startDate: start, endDate: start.addingTimeInterval(86_400),
                                     calendarTitle: "Pro", attendees: [],
                                     teamsJoinURL: "https://teams.microsoft.com/l/meetup-join/A",
                                     isCancelled: false, isAllDay: true)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .none)
    }

    @Test("Un événement sans lien Teams est ignoré")
    func withoutTeamsURLIsIgnored() {
        let start = now
        let e = CalendarMeetingEvent(id: "A", title: "Point interne",
                                     startDate: start, endDate: start.addingTimeInterval(1800),
                                     calendarTitle: "Pro", attendees: [],
                                     teamsJoinURL: nil, isCancelled: false, isAllDay: false)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .none)
    }
}
