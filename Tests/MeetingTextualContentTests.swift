import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `Meeting.textualContent` est l'énumération **unique** du texte libre qu'une
/// réunion porte. Deux lecteurs doivent rester en phase : la recherche
/// `/cherche` de l'assistant, qui affiche l'étiquette de chaque occurrence, et
/// le prédicat de note vide (`NoteFactory.isDiscardableEmptyNote`), qui n'a
/// besoin que du texte. Le test verrouille l'énumération : un champ texte
/// ajouté à `Meeting` sans être déclaré ici le fait échouer.
@Suite("Meeting.textualContent — une seule énumération du texte d'une réunion")
struct MeetingTextualContentTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    @Test("Chaque champ texte de la réunion s'y retrouve")
    func everyFreeTextFieldIsListed() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "titre-x", date: Date(), notes: "notes-x")
        context.insert(meeting)
        meeting.liveNotes = "livenotes-x"
        meeting.customPrompt = "prompt-x"
        meeting.rawTranscript = "brute-x"
        meeting.mergedTranscript = "fusionnee-x"
        meeting.summary = "rapport-x"
        meeting.shortSummary = "resume-x"
        meeting.prepNotes = "prepa-x"
        meeting.referencedAbsent = "absent-x"
        meeting.nextDeadline = "echeance-x"
        meeting.calendarEventTitle = "agenda-x"
        meeting.keyPoints = ["point-x"]
        meeting.decisions = ["decision-x"]
        meeting.openQuestions = ["question-x"]

        let texts = meeting.textualContent.map(\.text)
        let expected = ["titre-x", "notes-x", "livenotes-x", "prompt-x", "fusionnee-x",
                        "rapport-x", "resume-x", "prepa-x", "absent-x", "echeance-x",
                        "agenda-x", "point-x", "decision-x", "question-x"]
        for marker in expected {
            #expect(texts.contains(marker), "\(marker) manque à l'énumération")
        }
        #expect(meeting.textualContent.allSatisfy { !$0.label.isEmpty },
                "chaque occurrence porte une étiquette, /cherche l'affiche")
    }

    /// `/cherche` n'affiche qu'une transcription : la fusionnée si elle existe,
    /// la brute sinon. Le prédicat de note vide reste juste malgré ce choix,
    /// puisque « la fusionnée sinon la brute » n'est vide que si les deux le
    /// sont.
    @Test("Sans transcription fusionnée, la brute prend sa place")
    func rawTranscriptStandsInForMerged() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "", date: Date(), notes: "")
        context.insert(meeting)
        meeting.rawTranscript = "brute-seule"

        #expect(meeting.textualContent.map(\.text).contains("brute-seule"))

        meeting.mergedTranscript = "fusionnee"
        let texts = meeting.textualContent.map(\.text)
        #expect(texts.contains("fusionnee"))
        #expect(!texts.contains("brute-seule"))
    }
}
