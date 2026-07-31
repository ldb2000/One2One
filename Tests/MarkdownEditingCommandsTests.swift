import XCTest
@testable import OneToOne

final class MarkdownEditingCommandsTests: XCTestCase {
    func test_wrapSelection_wrapsSelectedTextAndKeepsInnerSelection() {
        let text = "hello world"
        let range = (text as NSString).range(of: "world")

        let result = MarkdownEditingCommands.wrapSelection(
            in: text,
            range: range,
            marker: "**",
            placeholder: "texte"
        )

        XCTAssertEqual(result.text, "hello **world**")
        XCTAssertEqual((result.text as NSString).substring(with: result.selectedRange), "world")
    }

    func test_wrapSelection_unwrapsWhenSelectionIsAlreadyWrapped() {
        let text = "hello **world**"
        let range = (text as NSString).range(of: "world")

        let result = MarkdownEditingCommands.wrapSelection(
            in: text,
            range: range,
            marker: "**",
            placeholder: "texte"
        )

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual((result.text as NSString).substring(with: result.selectedRange), "world")
    }

    func test_wrapSelection_emptySelectionInsertsPlaceholder() {
        let result = MarkdownEditingCommands.wrapSelection(
            in: "hello ",
            range: NSRange(location: 6, length: 0),
            marker: "_",
            placeholder: "texte"
        )

        XCTAssertEqual(result.text, "hello _texte_")
        XCTAssertEqual((result.text as NSString).substring(with: result.selectedRange), "texte")
    }

    func test_toggleLinePrefix_replacesExclusiveHeadingPrefix() {
        let result = MarkdownEditingCommands.toggleLinePrefix(
            in: "## Title",
            range: NSRange(location: 4, length: 0),
            prefix: "### ",
            exclusivePrefixes: ["# ", "## ", "### "]
        )

        XCTAssertEqual(result.text, "### Title")
    }

    func test_toggleLinePrefix_removesPrefixWhenAllSelectedLinesHaveIt() {
        let text = "- a\n- b\n"
        let result = MarkdownEditingCommands.toggleLinePrefix(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            prefix: "- ",
            exclusivePrefixes: ["- "]
        )

        XCTAssertEqual(result.text, "a\nb\n")
    }

    func test_toggleLinePrefix_appliesPrefixToEverySelectedLine() {
        let text = "a\nb\n"
        let result = MarkdownEditingCommands.toggleLinePrefix(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            prefix: "- ",
            exclusivePrefixes: ["- "]
        )

        XCTAssertEqual(result.text, "- a\n- b\n")
    }
}
