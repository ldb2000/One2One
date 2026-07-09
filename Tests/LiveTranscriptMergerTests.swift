import Testing
@testable import OneToOne

struct LiveTranscriptMergerTests {

    @Test func firstWindowIsKeptVerbatim() {
        var m = LiveTranscriptMerger()
        let out = m.append("bonjour comment vas tu")
        #expect(out == "bonjour comment vas tu")
        #expect(m.text == "bonjour comment vas tu")
    }

    @Test func overlappingWordsAreNotDuplicated() {
        var m = LiveTranscriptMerger()
        _ = m.append("je pense que le projet")
        let out = m.append("le projet avance bien")
        #expect(out == "je pense que le projet avance bien")
    }

    @Test func noOverlapConcatenatesWithSpace() {
        var m = LiveTranscriptMerger()
        _ = m.append("première partie")
        let out = m.append("sujet totalement différent")
        #expect(out == "première partie sujet totalement différent")
    }

    @Test func emptyWindowIsIgnored() {
        var m = LiveTranscriptMerger()
        _ = m.append("texte")
        let out = m.append("   ")
        #expect(out == "texte")
    }

    @Test func overlapDetectionIsCaseInsensitive() {
        let n = LiveTranscriptMerger.overlapSuffixPrefix("le Projet", "Le projet avance")
        #expect(n == 2)
    }
}
