import Testing
import Foundation
@testable import OneToOne

/// SwiftUI déduplique les fenêtres par égalité du token : deux tokens pour la
/// même réunion doivent être égaux quelles que soient les options, sinon la
/// même réunion s'ouvre deux fois.
@Suite("OneToOneLaunchToken — l'identité d'une fenêtre est la réunion")
struct OneToOneLaunchTokenTests {

    @Test("Même réunion, options différentes → même token")
    func sameMeetingIsEqualRegardlessOfOptions() {
        let id = UUID()
        let a = OneToOneLaunchToken(meetingID: id, autoStartRecording: true)
        let b = OneToOneLaunchToken(meetingID: id, autoStartRecording: false)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test("Réunions différentes → tokens différents")
    func differentMeetingsDiffer() {
        let a = OneToOneLaunchToken(meetingID: UUID(), autoStartRecording: true)
        let b = OneToOneLaunchToken(meetingID: UUID(), autoStartRecording: true)
        #expect(a != b)
    }
}
