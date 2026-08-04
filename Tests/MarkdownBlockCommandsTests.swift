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

    private func storage(_ markdown: String) -> NSTextStorage {
        NSTextStorage(attributedString: MarkdownParser.parse(markdown))
    }

    private func serialized(_ storage: NSTextStorage) -> String {
        MarkdownSerializer.serialize(storage)
    }

    func test_setBlockType_preservesInlineFormatting() {
        let s = storage("Voici du **gras** ici")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Voici du **gras** ici")
    }

    func test_setBlockType_preservesImageURL() {
        let s = storage("Avant ![alt](file:///tmp/a.png) après")
        MarkdownBlockCommands.setBlockType(.blockquote, in: s, at: 0)
        XCTAssertEqual(serialized(s), "> Avant ![alt](file:///tmp/a.png) après")
    }

    func test_setBlockType_toSameType_revertsToParagraph() {
        let s = storage("Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Titre", "Réappliquer le même type revient au paragraphe.")
    }

    func test_setBlockType_clearsListInfo() {
        let s = storage("- une puce")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## une puce", "Un titre n'est pas une liste.")
    }

    func test_setListKind_preservesInlineFormatting() {
        let s = storage("Texte **fort**")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Texte **fort**")
    }

    func test_setListKind_task_producesCheckbox() {
        let s = storage("À faire")
        MarkdownBlockCommands.setListKind(.task, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- [ ] À faire")
    }

    func test_setListKind_toSameKind_revertsToParagraph() {
        let s = storage("Texte")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Texte")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Texte")
    }

    func test_setListKind_clearsBlockType() {
        let s = storage("## Titre")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Titre", "Une liste n'est pas un titre.")
    }

    func test_operatesOnlyOnCaretLine() {
        // Deux paragraphes séparés par une ligne vide : le parser émet un `\n`
        // littéral entre les deux (`appendNewline`). Un simple `\n` unique
        // dans la source markdown serait un *soft break* (`SoftBreak` →
        // espace, cf. `MarkdownParser.emitInlineNode`), donc un seul
        // paragraphe sans `\n` dans le storage — inadapté pour ce test.
        let s = storage("Première\n\nDeuxième")
        let secondLineStart = (s.string as NSString).range(of: "Deuxième").location
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: secondLineStart)
        XCTAssertEqual(serialized(s), "Première\n## Deuxième")
    }
}
