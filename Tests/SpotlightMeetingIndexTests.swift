import Testing
import Foundation
@testable import OneToOne

@Suite("Spotlight — indexation des réunions et des notes")
@MainActor
struct SpotlightMeetingIndexTests {

    @Test("Une note porte son titre et son corps, sans transcription")
    func noteItemCarriesBody() {
        let note = Meeting(title: "Idée archi", date: Date())
        note.kind = .note
        note.liveNotes = "Découpler le module de facturation"
        note.mergedTranscript = "NE DOIT PAS ETRE INDEXE"

        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(note)
        let description = item.attributeSet.contentDescription ?? ""

        #expect(item.attributeSet.displayName == "Idée archi")
        #expect(description.contains("Découpler le module de facturation"))
        #expect(!description.contains("NE DOIT PAS ETRE INDEXE"))
        #expect(item.domainIdentifier == "meetings")
    }

    @Test("Un 1:1 porte son résumé court et le nom du participant en mot-clé")
    func oneToOneItemCarriesSummaryAndParticipant() {
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kind = .oneToOne
        meeting.shortSummary = "Montée en charge sur le socle"
        let alice = Collaborator(name: "Alice")
        meeting.participants = [alice]

        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(meeting)
        #expect((item.attributeSet.contentDescription ?? "").contains("Montée en charge sur le socle"))
        #expect((item.attributeSet.keywords ?? []).contains("OneToOne"))
        #expect((item.attributeSet.keywords ?? []).contains("Alice"))
    }

    @Test("Une réunion sans titre reste identifiable")
    func untitledMeetingHasFallbackName() {
        let meeting = Meeting(title: "", date: Date())
        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(meeting)
        #expect(item.attributeSet.displayName?.isEmpty == false)
    }
}
