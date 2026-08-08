import XCTest
import AppKit
@testable import OneToOne

/// `StyleRenderer.applyBlockSpacing` pose l'écart vertical sur le **dernier**
/// paragraphe de chaque bloc logique. L'écart large s'applique dès qu'un des
/// deux blocs du couple dessine un cadre — sans quoi une carte suivie d'un
/// paragraphe aurait 28 pt en dessous mais 10 pt au-dessus, une asymétrie
/// visible à l'écran.
///
/// Ces tests n'utilisent **que** des blocs de code non-mermaid comme cartes :
/// un bloc ```` ```mermaid ```` déclencherait un vrai `WKWebView` en tâche de
/// fond (voir la doc de tête de `StyleRendererMermaidTests`).
final class StyleRendererBlockSpacingTests: XCTestCase {

    /// Espacement posé sur le dernier paragraphe du bloc contenant `needle`.
    private func spacingAfterBlock(containing needle: String, in markdown: String) throws -> CGFloat {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        let ns = storage.string as NSString
        let location = ns.range(of: needle).location
        XCTAssertNotEqual(location, NSNotFound, "« \(needle) » introuvable dans le storage stylé")
        let block = BlockRange.of(in: storage, at: location).range
        let lastCharacter = max(block.location, NSMaxRange(block) - 1)
        let terminal = ns.lineRange(for: NSRange(location: lastCharacter, length: 0))
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: terminal.location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacing
    }

    func test_textFollowedByText_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }

    func test_textFollowedByACard_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByText_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "```swift\nprint(1)\n```\n\nSuite")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByACard_getsTheWideSpacing() throws {
        let markdown = "```swift\nprint(1)\n```\n\n```swift\nprint(2)\n```"
        let spacing = try spacingAfterBlock(containing: "print(1)", in: markdown)
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    /// Dernier bloc du document : aucun bloc ne suit, seule la nature du bloc
    /// lui-même décide. Garde-fou contre une lecture hors bornes du « bloc
    /// suivant ».
    func test_lastCardOfTheDocument_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "Intro\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_lastTextBlockOfTheDocument_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Second", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }
}
