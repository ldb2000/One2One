import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **Critère d'acceptation n° 2 du chantier 1** (spec §2, « Critères
/// d'acceptation ») : « Créer une action depuis une phrase de transcription
/// prend un clic et conserve `sourceRef` ; le lien `mm:ss ↗` replace la lecture
/// au bon endroit à ±1 s. »
///
/// Le test est volontairement écrit **sans vue** : le clic est un seul appel de
/// service, et c'est exactement ce que la colonne de transcription fait. S'il
/// fallait deux appels pour obtenir une action correcte, le critère serait
/// violé quelle que soit l'interface posée par-dessus.
@Suite("Critère n° 2 — une action en un clic depuis une phrase")
@MainActor
struct ActionFromTranscriptCriterionTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// La réunion et le segment de la capture : `04:12 Laurent — Tous les
    /// comptes ont été désactivés, il faut remettre ça en route…`
    private func fixture(in context: ModelContext)
    -> (meeting: Meeting, segment: TranscriptSegment, speaker: Collaborator) {
        let reunion = Meeting(title: "[P25_110] Partage statut final", date: Date(), notes: "")
        reunion.durationSeconds = 1_404
        context.insert(reunion)

        let locuteur = Collaborator(name: "Laurent Deberti", role: "Manager")
        context.insert(locuteur)
        reunion.participants.append(locuteur)

        let segment = TranscriptSegment(
            orderIndex: 1,
            startSeconds: 252,
            endSeconds: 275,
            text: "il faut remettre ça en route et vérifier les droits.",
            speakerID: 1
        )
        context.insert(segment)
        segment.meeting = reunion
        segment.speaker = locuteur
        return (reunion, segment, locuteur)
    }

    @Test("Un seul appel crée l'action, avec son titre, son responsable et sa source")
    func unClic() throws {
        let context = try makeContext()
        let f = fixture(in: context)

        let action = ActionFromPhrase.createAction(from: f.segment, in: f.meeting,
                                                   context: context)

        #expect(action.title == "Remettre ça en route et vérifier les droits")
        #expect(action.collaborator === f.speaker)
        #expect(action.meeting === f.meeting)
        #expect(f.meeting.tasks.count == 1)

        let source = action.sourceRef
        #expect(source?.kind == .transcript)
        #expect(source?.stableID == f.segment.ensuredStableID)
        #expect(source?.t == 252)
    }

    @Test("L'action naît en tête du rail")
    func enTeteDuRail() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let existante = ActionTask(title: "Action déjà là")
        existante.sortOrder = 0
        context.insert(existante)
        existante.meeting = f.meeting

        let nouvelle = ActionFromPhrase.createAction(from: f.segment, in: f.meeting,
                                                     context: context)
        #expect(nouvelle.sortOrder < existante.sortOrder)
    }

    @Test("Le lien mm:ss replace la lecture à ± 1 s")
    func lienDeTimecode() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let action = ActionFromPhrase.createAction(from: f.segment, in: f.meeting,
                                                   context: context)

        let playhead = MeetingPlayhead(meetingStableID: f.meeting.ensuredStableID)
        playhead.duration = Double(f.meeting.durationSeconds)
        let cible = try #require(action.sourceRef?.t)
        playhead.seek(to: cible)

        #expect(abs(playhead.t - 252) <= 1)
        #expect(playhead.formatted == "04:12")
    }

    @Test("Une source hors de la durée connue ne sort pas de la frise")
    func sourceHorsDuree() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let playhead = MeetingPlayhead(meetingStableID: f.meeting.ensuredStableID)
        playhead.duration = 100   // fichier tronqué par l'édition audio
        playhead.seek(to: 252)
        #expect(playhead.t == 100)
    }

    @Test("Décision depuis un segment : une note horodatée qui garde la source")
    func decisionDepuisUnSegment() throws {
        let context = try makeContext()
        let f = fixture(in: context)

        let note = ActionFromPhrase.createDecision(from: f.segment, in: f.meeting,
                                                   context: context)
        #expect(note.kind == .decision)
        #expect(note.t == 252)
        #expect(note.text == "Il faut remettre ça en route et vérifier les droits")
        #expect(note.sourceRef?.kind == .transcript)
        #expect(note.sourceRef?.stableID == f.segment.ensuredStableID)
        #expect(note.sourceRef?.t == 252)
        #expect(f.meeting.timedNotes.count == 1)
    }

    @Test("Le brouillon posé pour le rail porte la même source que l'action créée")
    func brouillonEtAction() throws {
        let context = try makeContext()
        let f = fixture(in: context)
        let suite = "ActionFromTranscriptCriterionTests.\(UUID().uuidString)"
        let screen = MeetingScreenModel(defaults: UserDefaults(suiteName: suite)!)

        let brouillon = ActionFromPhrase.draft(from: f.segment)
        screen.requestAction(from: brouillon)

        #expect(screen.pendingActionDraft?.sourceRef?.stableID == f.segment.ensuredStableID)
        #expect(screen.newTaskTitle == "Remettre ça en route et vérifier les droits")
        #expect(brouillon.suggestedOwner === f.speaker)
    }
}
