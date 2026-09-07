import Testing
import Foundation
@testable import OneToOne

/// Le routage du mode Préparer d'un 1:1 (spec §3 : « `2b` s'ouvre par défaut en
/// mode `Préparer` ») et le contexte de fil de la barre d'assistant.
@Suite("Préparation 1:1 — routage et barre d'assistant (spec §3, §3.3)")
@MainActor
struct ManagerPrepRoutingTests {

    // MARK: - Aiguillage

    @Test("Seul le couple (1:1, Préparer) mène à l'écran 2b")
    func aiguillage() {
        #expect(MeetingSpaceRouting.usesOneOnOnePreparation(kind: .oneToOne, mode: .prepare))
        #expect(!MeetingSpaceRouting.usesOneOnOnePreparation(kind: .oneToOne, mode: .live))
        #expect(!MeetingSpaceRouting.usesOneOnOnePreparation(kind: .oneToOne, mode: .review))
        // Le côté collaborateur a son propre écran (5b, lot 14).
        #expect(!MeetingSpaceRouting.usesOneOnOnePreparation(kind: .manager, mode: .prepare))
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(!MeetingSpaceRouting.usesOneOnOnePreparation(kind: kind, mode: .prepare))
        }
    }

    // MARK: - Mode d'ouverture

    @Test("Un 1:1 jamais ouvert et sans enregistrement s'ouvre en Préparer")
    func modeParDefaut() {
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: .oneToOne,
                                                hasRecording: false) == .prepare)
    }

    @Test("Un 1:1 déjà enregistré s'ouvre là où les autres types s'ouvrent")
    func modeAvecEnregistrement() {
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: .oneToOne,
                                                hasRecording: true) == nil)
    }

    @Test("Un choix mémorisé fait loi, y compris « En séance »")
    func choixMemorise() {
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: "live", kind: .oneToOne,
                                                hasRecording: false) == nil)
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: "prepare", kind: .oneToOne,
                                                hasRecording: false) == nil)
        // Une valeur mémorisée illisible (renommage passé) retombe sur le
        // défaut du type plutôt que sur `.live` en silence.
        #expect(MeetingSpaceRouting.initialMode(persistedRaw: "pilotage", kind: .oneToOne,
                                                hasRecording: false) == .prepare)
    }

    @Test("Les autres types gardent leur mode d'ouverture")
    func autresTypes() {
        // `.manager` n'y est plus depuis le lot 14 : un 1:1 subi s'ouvre lui
        // aussi en Préparer, sur la capture 5b. Cf.
        // `CollaboratorPrepAgendaTests.modeParDefaut`.
        for kind in [MeetingKind.global, .project, .work, .workshop, .note] {
            #expect(MeetingSpaceRouting.initialMode(persistedRaw: nil, kind: kind,
                                                    hasRecording: false) == nil)
        }
    }

    // MARK: - Barre d'assistant

    @Test("Le contexte de fil remplace le placeholder et les suggestions datées")
    func contexteDeFil() {
        // Un seul type de contexte pour les deux écrans 1:1 depuis
        // l'intégration de la vague 5 : la séance (2a) et la préparation (2b)
        // décrivent le même fil, seule la question change.
        let contexte = MeetingAssistantDock.ThreadContext(
            placeholder: ManagerPrepView.assistantSuggestion,
            threadName: "Laurent")

        #expect(contexte.placeholder == "« Qu'a-t-il demandé sans réponse depuis juin ? »")
        #expect(contexte.threadName == "Laurent")
        #expect(MeetingAssistantDock.placeholder != contexte.placeholder)
    }
}
