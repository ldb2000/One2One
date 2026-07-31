import Testing
import Foundation
@testable import OneToOne

/// `AudioRecorderService` est un singleton process-wide observé par **toutes** les
/// fenêtres réunion. Ces tests verrouillent la règle de propriété : seule la
/// réunion qui enregistre affiche le vumètre / le chrono.
@Suite("AudioRecorderService — propriété de l'enregistrement")
struct AudioRecorderOwnershipTests {

    private let meetingA = UUID()
    private let meetingB = UUID()

    @Test("La réunion propriétaire de l'enregistrement est reconnue")
    func ownerMatches() {
        #expect(AudioRecorderService.isOwner(
            isRecording: true, activeMeetingID: meetingA, meetingID: meetingA))
    }

    @Test("Une autre réunion n'est pas propriétaire (bug des 2 fenêtres)")
    func otherMeetingIsNotOwner() {
        #expect(!AudioRecorderService.isOwner(
            isRecording: true, activeMeetingID: meetingA, meetingID: meetingB))
    }

    @Test("Aucun enregistrement en cours → personne n'est propriétaire")
    func notRecording() {
        #expect(!AudioRecorderService.isOwner(
            isRecording: false, activeMeetingID: meetingA, meetingID: meetingA))
    }

    @Test("Propriétaire inconnu → aucune fenêtre ne s'approprie l'enregistrement")
    func unknownOwnerClaimedByNobody() {
        #expect(!AudioRecorderService.isOwner(
            isRecording: true, activeMeetingID: nil, meetingID: meetingA))
        // Le piège `nil == nil` : une réunion sans stableID ne doit pas hériter
        // d'un enregistrement anonyme.
        #expect(!AudioRecorderService.isOwner(
            isRecording: true, activeMeetingID: nil, meetingID: nil))
    }

    @Test("Réunion sans stableID → jamais propriétaire d'un enregistrement identifié")
    func meetingWithoutStableID() {
        #expect(!AudioRecorderService.isOwner(
            isRecording: true, activeMeetingID: meetingA, meetingID: nil))
    }

    @Test("Au repos, le service n'attribue l'enregistrement à personne")
    @MainActor
    func idleServiceOwnsNothing() {
        let recorder = AudioRecorderService.shared
        #expect(!recorder.isRecording)                 // état initial du singleton
        #expect(!recorder.isRecording(for: meetingA))
        #expect(!recorder.isRecording(for: nil))
    }
}
