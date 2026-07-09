import Testing
@testable import OneToOne

struct PresenceStatsTests {

    @Test func countsAndPercent() {
        let s = PresenceStats.compute(statuses:
            Array(repeating: .present, count: 39)
            + Array(repeating: .refused, count: 3))
        #expect(s.present == 39)
        #expect(s.refused == 3)
        #expect(s.pending == 0)
        #expect(s.total == 42)
        #expect(s.percent == 93)   // round(39/42*100) = 92.857 → 93
    }

    @Test func withPending() {
        let s = PresenceStats.compute(statuses: [.present, .present, .pending, .refused])
        #expect(s.present == 2)
        #expect(s.pending == 1)
        #expect(s.refused == 1)
        #expect(s.total == 4)
        #expect(s.percent == 50)
    }

    @Test func emptyIsZeroPercent() {
        let s = PresenceStats.compute(statuses: [])
        #expect(s.total == 0)
        #expect(s.percent == 0)
    }
}
