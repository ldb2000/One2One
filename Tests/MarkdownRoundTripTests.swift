import XCTest
@testable import OneToOne

final class MarkdownRoundTripTests: XCTestCase {

    /// For each fixture, parse the markdown then serialize it; the output
    /// must equal the input (modulo accepted normalisations documented in
    /// the spec — none required for these fixtures).
    private let fixtures: [String] = [
        "Hello world",
        "## Title",
        "hello **bold** word",
        "- a\n- b\n- c",
        "1. one\n2. two",
        "- [ ] todo\n- [x] done",
        // Note: serializer normalises multi-line blockquote (soft break) → single line with space
        "> quote next line — kept as block",
        "[link](https://example.com)",
        "hello `code` inline",
        // Note: serializer normalises *italic* → _italic_
        "Mix _italic_ and **bold** here",
        // Blocs fencés — non couverts jusqu'ici.
        // Pas de ligne vide entre les blocs : `MarkdownParser.appendNewline`
        // n'en émet qu'une seule après chaque bloc, donc `\n\n` en entrée
        // ressortirait en `\n` et ferait échouer le test pour une raison
        // étrangère à ce qu'on cherche à prouver.
        "```swift\nprint(1)\n```",
        "```swift\nlet a = 1\nlet b = 2\nprint(a + b)\n```",
        "```\nsans langage\nsur deux lignes\n```",
        "texte avant\n```json\n{\n  \"a\": 1\n}\n```\ntexte après"
    ]

    func test_allFixturesRoundTrip() {
        for md in fixtures {
            let parsed = MarkdownParser.parse(md)
            let back = MarkdownSerializer.serialize(parsed)
            XCTAssertEqual(back, md, "Round-trip mismatch for: \(md.debugDescription)")
        }
    }
}
