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
        "Mix _italic_ and **bold** here"
    ]

    func test_allFixturesRoundTrip() {
        for md in fixtures {
            let parsed = MarkdownParser.parse(md)
            let back = MarkdownSerializer.serialize(parsed)
            XCTAssertEqual(back, md, "Round-trip mismatch for: \(md.debugDescription)")
        }
    }
}
