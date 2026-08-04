import XCTest
import AppKit
@testable import OneToOne

/// Caractérise le comportement des commandes de bloc. Les trois premiers tests
/// documentent la perte d'information du chemin actuel — ils seront inversés
/// par la tâche 3, une fois `MarkdownBlockCommands` en place.
final class MarkdownBlockCommandsTests: XCTestCase {

    /// Applique l'ancien chemin : texte d'affichage → `toggleLinePrefix` →
    /// reparse global, tel que `MarkdownToolbar.apply(_:to:)` le fait.
    private func legacyApply(markdown: String, prefix: String) -> String {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let result = MarkdownEditingCommands.toggleLinePrefix(
            in: storage.string,
            range: NSRange(location: 0, length: 0),
            prefix: prefix
        )
        return MarkdownSerializer.serialize(MarkdownParser.parse(result.text))
    }

    func test_legacyHeadingButton_destroysInlineFormatting() {
        let out = legacyApply(markdown: "Voici du **gras** et un [lien](https://ex.com)", prefix: "## ")
        XCTAssertEqual(out, "## Voici du gras et un lien",
                       "Comportement actuel : le gras et le lien sont perdus.")
    }

    func test_legacyListButton_destroysImageURL() {
        let out = legacyApply(markdown: "Avant ![alt](file:///tmp/a.png) après", prefix: "- ")
        XCTAssertFalse(out.contains("file:///tmp/a.png"),
                       "Comportement actuel : l'URL de l'image est perdue.")
    }

    func test_legacyHeadingButton_isNotReversible() {
        let once = legacyApply(markdown: "Titre", prefix: "## ")
        let twice = legacyApply(markdown: once, prefix: "## ")
        XCTAssertEqual(twice, once,
                       "Comportement actuel : réappliquer n'enlève pas le titre.")
    }
}
