import Testing
import Foundation
@testable import OneToOne

@Suite("SentenceContextExtractor")
struct SentenceContextExtractorTests {

    @Test("Extracts 2 sentences before and after middle selection")
    func middleSelection() {
        let text = "First sentence. Second sentence. SELECTED. Fourth sentence. Fifth sentence."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.contains("Second sentence."))
        #expect(result.before.contains("First sentence."))
        #expect(result.after.contains("Fourth sentence."))
        #expect(result.after.contains("Fifth sentence."))
    }

    @Test("Empty before when selection is at the start")
    func startSelection() {
        let text = "SELECTED. After one. After two."
        let range = NSRange(location: 0, length: 8)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before == "")
        #expect(result.after.contains("After one."))
    }

    @Test("Empty after when selection is at the end")
    func endSelection() {
        let text = "Before two. Before one. SELECTED"
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.after == "")
        #expect(result.before.contains("Before one."))
    }

    @Test("Plafond 400 chars on before")
    func plafond400Before() {
        let long = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50) // > 400
        let text = long + "SELECTED. End."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.count <= 400)
    }

    @Test("Plafond 400 chars on after")
    func plafond400After() {
        let long = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50)
        let text = "Start. SELECTED. " + long
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.after.count <= 400)
    }

    @Test("Stops at paragraph boundary (\\n\\n) before")
    func paragraphBoundaryBefore() {
        let text = "Paragraph A first. Paragraph A second.\n\nParagraph B. SELECTED. End."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(!result.before.contains("Paragraph A"))
        #expect(result.before.contains("Paragraph B"))
    }

    @Test("Zero-length range returns valid empty contexts")
    func zeroLength() {
        let text = "Some text here."
        let range = NSRange(location: 5, length: 0)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.count <= 400)
        #expect(result.after.count <= 400)
    }

    @Test("Range past text length returns empty contexts safely")
    func outOfBounds() {
        let text = "Short."
        let range = NSRange(location: 100, length: 5)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before == "")
        #expect(result.after == "")
    }
}
