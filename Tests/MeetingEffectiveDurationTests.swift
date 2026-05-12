import XCTest
import SwiftData
@testable import OneToOne

final class MeetingEffectiveDurationTests: XCTestCase {

    func test_effectiveDuration_usesScheduledWhenBothPresentAndOrdered() {
        let meeting = Meeting(title: "Test", date: Date())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        meeting.scheduledStart = start
        meeting.scheduledEnd = end
        meeting.durationSeconds = 120  // should be ignored
        XCTAssertEqual(meeting.effectiveDuration, 3600, accuracy: 0.01)
    }

    func test_effectiveDuration_fallsBackToRecordingWhenScheduledMissing() {
        let meeting = Meeting(title: "Test", date: Date())
        meeting.durationSeconds = 1800
        XCTAssertEqual(meeting.effectiveDuration, 1800, accuracy: 0.01)
    }

    func test_effectiveDuration_fallsBackWhenScheduledInverted() {
        let meeting = Meeting(title: "Test", date: Date())
        let start = Date()
        meeting.scheduledStart = start
        meeting.scheduledEnd = start.addingTimeInterval(-60)  // inverted
        meeting.durationSeconds = 500
        XCTAssertEqual(meeting.effectiveDuration, 500, accuracy: 0.01)
    }

    func test_effectiveDuration_prefersMeetingDurationSecondsOverRecording() {
        let meeting = Meeting(title: "Test", date: Date())
        meeting.meetingDurationSeconds = 2700  // 45 min calendar legacy
        meeting.durationSeconds = 500          // should be ignored
        XCTAssertEqual(meeting.effectiveDuration, 2700, accuracy: 0.01)
    }
}
