import XCTest
@testable import ProbeCore

/// Les quatre gestes destructifs, tous ramenés à `ProbeDocument.replace`.
final class ProbeEditingTests: XCTestCase {

    // MARK: - ⌫

    /// Le geste qui fait tout l'intérêt du prototype : ⌫ en tête de bloc
    /// fusionne avec le précédent, ce qu'aucun `NSTextView` ne sait faire seul.
    func test_deleteBackward_atTheHeadOfABlock_mergesWithThePrevious() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 0))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["UnDeux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    func test_deleteBackward_insideABlock_removesOneComposedSequence() {
        var document = ProbeDocument(texts: ["cafe\u{0301}"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 5))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["caf"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 3))
    }

    func test_deleteBackward_atTheVeryStart_doesNothing() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 0))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["Un", "Deux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 0))
    }

    func test_deleteBackward_onAMultiBlockSelection_removesIt() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.deleteBackward(in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["Uois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 1))
    }

    // MARK: - ⌦

    func test_deleteForward_atTheEndOfABlock_pullsUpTheNext() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2))

        let result = ProbeEditing.deleteForward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["UnDeux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    func test_deleteForward_atTheVeryEnd_doesNothing() {
        var document = ProbeDocument(texts: ["Un"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2))

        let result = ProbeEditing.deleteForward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["Un"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    // MARK: - ⏎

    func test_insertNewline_splitsTheBlockAtTheCaret() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let result = ProbeEditing.insertNewline(
            in: &document,
            selection: ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)))

        XCTAssertEqual(document.blocks.map(\.text), ["Bon", "jour"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 0))
    }

    func test_insertNewline_onAMultiBlockSelection_removesItThenSplits() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.insertNewline(in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["U", "ois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 0))
    }

    // MARK: - Frappe

    /// Frapper une lettre alors que trois blocs sont sélectionnés doit les
    /// réduire à un seul portant cette lettre au bon endroit.
    func test_insertText_onAMultiBlockSelection_collapsesItToOneBlock() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.insertText("X", in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["UXois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    /// Le collage passe par la même porte que la frappe.
    func test_insertText_withNewlines_pastesOneBlockPerLine() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let result = ProbeEditing.insertText(
            "a\nb",
            in: &document,
            selection: ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)))

        XCTAssertEqual(document.blocks.map(\.text), ["Bona", "bjour"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 1))
    }
}
