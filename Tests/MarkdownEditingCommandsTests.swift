import XCTest
@testable import OneToOne

/// Couvre `toggleLinePrefix`, seule fonction restante de
/// `MarkdownEditingCommands` — voir son doc-comment : cette API n'est plus
/// utilisée que pour les préfixes de texte (les tags), jamais pour les
/// types de bloc.
final class MarkdownEditingCommandsTests: XCTestCase {
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
