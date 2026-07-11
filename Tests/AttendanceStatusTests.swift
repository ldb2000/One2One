import Testing
import EventKit
@testable import OneToOne

struct AttendanceStatusTests {

    // Rétro-compatibilité : les raw values persistées ne changent pas.
    @Test func rawValuesRemainStableForExistingData() {
        #expect(MeetingAttendanceStatus.present.rawValue == "participant")
        #expect(MeetingAttendanceStatus.refused.rawValue == "absent")
        #expect(MeetingAttendanceStatus.pending.rawValue == "pending")
    }

    @Test func oldPersistedRawDecodesToNewCases() {
        #expect(MeetingAttendanceStatus(rawValue: "participant") == .present)
        #expect(MeetingAttendanceStatus(rawValue: "absent") == .refused)
        #expect(MeetingAttendanceStatus(rawValue: "pending") == .pending)
        #expect(MeetingAttendanceStatus(rawValue: "inconnu") == nil)
    }

    @Test func labelsAreFrench() {
        #expect(MeetingAttendanceStatus.present.label == "Présent")
        #expect(MeetingAttendanceStatus.refused.label == "A refusé")
        #expect(MeetingAttendanceStatus.pending.label == "En attente")
    }

    @Test func calendarMappingCoversAllStatuses() {
        #expect(MeetingAttendanceStatus.fromCalendar(.declined) == .refused)
        #expect(MeetingAttendanceStatus.fromCalendar(.tentative) == .pending)
        #expect(MeetingAttendanceStatus.fromCalendar(.pending) == .pending)
        #expect(MeetingAttendanceStatus.fromCalendar(.accepted) == .present)
        #expect(MeetingAttendanceStatus.fromCalendar(.unknown) == .present)
    }

    @Test func allCasesHasThree() {
        #expect(MeetingAttendanceStatus.allCases.count == 3)
    }
}
