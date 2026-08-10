import Testing
@testable import OneToOne

@Suite("MeetingView — onglets visibles selon le kind")
struct MeetingVisibleSectionsTests {

    @Test("Une note n'a que son corps et ses documents")
    func noteHasTwoSections() {
        #expect(MeetingView.visibleSections(for: .note) == [.liveNotes, .documents])
    }

    @Test("Un 1:1 garde les six onglets")
    func oneToOneKeepsAll() {
        #expect(MeetingView.visibleSections(for: .oneToOne) == MeetingView.MeetingSection.allCases)
    }

    @Test("L'onglet du corps s'intitule Note pour une note, Notes live sinon")
    func bodyTabLabelFollowsKind() {
        #expect(MeetingView.MeetingSection.liveNotes.label(for: .note) == "Note")
        #expect(MeetingView.MeetingSection.liveNotes.label(for: .oneToOne) == "Notes live")
        #expect(MeetingView.MeetingSection.documents.label(for: .note) == "Documents")
    }
}
