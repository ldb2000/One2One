import Testing
import Foundation
@testable import OneToOne

@Suite("MeetingStatsScope — une note ne compte pas comme une réunion tenue")
struct MeetingStatsScopeTests {

    @Test("Une note est écartée")
    func noteIsExcluded() {
        let note = Meeting(title: "Note", date: Date())
        note.kind = .note
        #expect(MeetingStatsScope.held([note]).isEmpty)
    }

    @Test("Un 1:1 est conservé")
    func oneToOneIsKept() {
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        #expect(MeetingStatsScope.held([meeting]).count == 1)
    }

    @Test("L'ordre d'entrée est préservé")
    func orderIsPreserved() {
        let a = Meeting(title: "A", date: Date())
        a.kind = .global
        let note = Meeting(title: "N", date: Date())
        note.kind = .note
        let b = Meeting(title: "B", date: Date())
        b.kind = .project
        #expect(MeetingStatsScope.held([a, note, b]).map(\.title) == ["A", "B"])
    }
}
