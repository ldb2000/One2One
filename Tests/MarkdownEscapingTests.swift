import XCTest
@testable import OneToOne

final class MarkdownEscapingTests: XCTestCase {

    /// `URL.absoluteString` est déjà percent-encodée (RFC 3986) : `escapeURL`
    /// ne doit pas la ré-encoder, sous peine d'empiler les `%` à chaque
    /// aller-retour (`%C3%A9` → `%25C3%25A9` → …).
    func test_escapeURL_doesNotReencodePercentSigns() {
        let url = URL(string: "file:///Users/x/sch%C3%A9ma.png")!
        XCTAssertEqual(MarkdownEscaping.escapeURL(url), "file:///Users/x/sch%C3%A9ma.png")
    }

    /// `(` et `)` sont des caractères d'URL valides que `URL.absoluteString`
    /// ne touche pas, mais qui casseraient la syntaxe markdown `](…)` s'ils
    /// restaient littéraux : `escapeURL` les encode à la main.
    func test_escapeURL_encodesParentheses() {
        let url = URL(string: "file:///Users/x/a(b).png")!
        XCTAssertEqual(MarkdownEscaping.escapeURL(url), "file:///Users/x/a%28b%29.png")
    }
}
