import Testing
import Foundation
@testable import OneToOne

/// Les embranchements du parcours : un second appel pendant un enregistrement,
/// un provider IA absent, un STT qui n'a rien produit. Trois chemins qu'aucune
/// démonstration ne traverse et que l'usage réel trouve tout de suite.
@Suite("Teams auto-record — cas limites")
struct TeamsAutoRecordEdgeCasesTests {
    @MainActor
    @Test("LM Studio exige un modèle ; OpenRouter exige en plus une clé")
    func endpointConfigurationAvailability() {
        let settings = AppSettings()
        #expect(!TeamsReportAvailability.isAvailable(settings: settings))
        settings.modelName = "local-model"
        #expect(TeamsReportAvailability.isAvailable(settings: settings))
        let remote = AppSettings(modelName: "vendor/model", provider: .openRouter)
        #expect(!TeamsReportAvailability.isAvailable(settings: remote))
        remote.cloudToken = "test-key"
        #expect(TeamsReportAvailability.isAvailable(settings: remote))
    }

    // MARK: - D-9 : disponibilité du rapport

    @Test("Le provider local est toujours disponible, sans jeton")
    func localProvidersNeedNoToken() {
        #expect(!TeamsReportAvailability.isAvailable(provider: .direct, cloudToken: ""))
        #expect(TeamsReportAvailability.isAvailable(provider: .ollama, cloudToken: ""))
        #expect(TeamsReportAvailability.isAvailable(provider: .geminiOAuth, cloudToken: ""))
    }

    @Test("Un provider distant sans jeton n'est pas disponible")
    func remoteProviderWithoutTokenIsUnavailable() {
        #expect(!TeamsReportAvailability.isAvailable(provider: .anthropic, cloudToken: ""))
        #expect(!TeamsReportAvailability.isAvailable(provider: .openai, cloudToken: "   "))
        #expect(!TeamsReportAvailability.isAvailable(provider: .gemini, cloudToken: ""))
    }

    @Test("Un provider distant avec jeton est disponible")
    func remoteProviderWithTokenIsAvailable() {
        #expect(TeamsReportAvailability.isAvailable(provider: .anthropic, cloudToken: "sk-xxx"))
    }

    // MARK: - D-10 : concurrence

    @Test("Un appel détecté pendant un enregistrement propose de lier, pas de créer")
    func secondCallProposesLink() {
        for phase in [TeamsAutoRecordPhase.recording, .callEnded] {
            let (next, effects) = TeamsAutoRecordState.reduce(
                phase: phase, event: .callDetectedWhileRecording(eventID: "EVT-2"))
            #expect(next == phase, "On ne quitte pas la phase en cours")
            #expect(effects == [.emitLinkProposal(eventID: "EVT-2")])
        }
    }

    @Test("Accepter la liaison rattache l'événement sans toucher à la capture")
    func linkingKeepsRecording() {
        for phase in [TeamsAutoRecordPhase.recording, .callEnded] {
            let (next, effects) = TeamsAutoRecordState.reduce(
                phase: phase, event: .userLinkedToCurrentMeeting(eventID: "EVT-2"))
            #expect(next == phase)
            #expect(effects == [.linkEventToCurrentMeeting(eventID: "EVT-2")])
        }
    }

    @Test("Refuser la liaison ne modifie rien")
    func decliningLinkChangesNothing() {
        let (phase, effects) = TeamsAutoRecordState.reduce(phase: .recording, event: .userDismissed)
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    // MARK: - §10 : STT muet

    @Test("Une transcription vide après finalisation déclenche le popup d'erreur, pas celui du rapport")
    func emptyTranscriptAfterFinalizingRaisesError() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .finalizing, event: .transcriptionFinalized(segmentCount: 0))
        #expect(phase == .idle)
        #expect(effects == [.emitSTTErrorNotification])
    }

    @Test("Une transcription vide après arrêt manuel coupe l'icône et signale l'erreur")
    func emptyTranscriptAfterManualStopRaisesError() {
        for phase in [TeamsAutoRecordPhase.recording, .callEnded] {
            let (next, effects) = TeamsAutoRecordState.reduce(
                phase: phase, event: .transcriptionFinalized(segmentCount: 0))
            #expect(next == .idle)
            #expect(effects == [.setMenuBarRecording(false), .emitSTTErrorNotification])
        }
    }

    @Test("Une transcription non vide suit le chemin nominal")
    func nonEmptyTranscriptProceeds() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .finalizing, event: .transcriptionFinalized(segmentCount: 1))
        #expect(phase == .readyForAI)
        #expect(effects == [.emitTranscriptReadyNotification(segmentCount: 1)])
    }
}
