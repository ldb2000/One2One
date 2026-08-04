import XCTest
import AppKit
@testable import OneToOne

/// Caractérise le comportement des commandes de bloc. Les trois premiers tests
/// (`test_headingCommand_*`, `test_listCommand_*`) documentaient jusqu'à la
/// tâche 3 la perte d'information de l'ancien chemin (`toggleLinePrefix` +
/// reparse global) ; ils sont maintenant inversés pour documenter le
/// remplacement par `MarkdownBlockCommands`, en place depuis la tâche 3.
final class MarkdownBlockCommandsTests: XCTestCase {

    func test_headingCommand_preservesInlineFormatting() {
        let s = storage("Voici du **gras** et un [lien](https://ex.com)")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Voici du **gras** et un [lien](https://ex.com)")
    }

    func test_listCommand_preservesImageURL() {
        let s = storage("Avant ![alt](file:///tmp/a.png) après")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertTrue(serialized(s).contains("file:///tmp/a.png"))
    }

    func test_headingCommand_isReversible() {
        let s = storage("Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Titre")
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

    // MARK: - Revue du 2026-08-04 : garde bloc de code, gardes anti-crash, finitions

    func test_setBlockType_onCodeBlockLine_isNoOp() {
        let s = storage("```\nune\ndeux\ntrois\n```")
        let middleLineStart = (s.string as NSString).range(of: "deux").location
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: middleLineStart)
        XCTAssertEqual(serialized(s), "```\nune\ndeux\ntrois\n```",
                       "Scinder un bloc de code par une conversion ligne à ligne n'est jamais voulu.")
    }

    func test_setListKind_onCodeBlockLine_isNoOp() {
        let s = storage("```\nune\ndeux\ntrois\n```")
        let middleLineStart = (s.string as NSString).range(of: "deux").location
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: middleLineStart)
        XCTAssertEqual(serialized(s), "```\nune\ndeux\ntrois\n```")
    }

    func test_setBlockType_emptyStorage_doesNothingAndDoesNotCrash() {
        let s = NSTextStorage(attributedString: MarkdownParser.parse(""))
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "")
    }

    func test_setListKind_caretOnFinalEmptyLine_doesNothingAndDoesNotCrash() {
        // "A\n" avec le curseur à l'emplacement 2 (juste après le `\n`) :
        // une ligne finale vide, cas typique après un Retour en fin de note.
        let s = NSTextStorage(string: "A\n")
        s.addAttribute(.mdBlockType, value: BlockType.paragraph, range: NSRange(location: 0, length: 1))
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 2)
        XCTAssertEqual(s.string, "A\n")
    }

    func test_setBlockType_withExistingListAndSameType_stripsListButKeepsType() {
        // "- ## Titre" parse en une ligne portant à la fois .mdBlockType = .h2
        // et .mdListInfo = bullet. Sans `!hasList`, le premier clic sur le
        // bouton titre remettrait `target` à `.paragraph` (current == type)
        // et supprimerait le titre en même temps que la liste.
        let s = storage("- ## Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Titre",
                       "Le premier clic retire la liste et garde le titre.")
    }

    func test_setBlockType_removesOrphanedCodeLanguage() {
        // `.mdCodeLanguage` posé à la main pour simuler une fuite via les
        // `typingAttributes` de `NSTextView` (même mécanisme documenté pour
        // `mdImageURL` dans `StyleRenderer`/`MarkdownSerializer`) : la ligne
        // n'est pas un bloc de code (`.mdBlockType = .paragraph`), donc la
        // garde du point 2 ne s'applique pas et ne peut pas servir de filet.
        let s = NSTextStorage(string: "Texte")
        s.addAttribute(.mdBlockType, value: BlockType.paragraph, range: NSRange(location: 0, length: 5))
        s.addAttribute(.mdCodeLanguage, value: "swift", range: NSRange(location: 0, length: 5))
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertNil(s.attribute(.mdCodeLanguage, at: 0, effectiveRange: nil),
                     "mdCodeLanguage ne doit pas survivre à un changement de type de bloc.")
    }

    func test_setListKind_removesOrphanedCodeLanguage() {
        let s = NSTextStorage(string: "Texte")
        s.addAttribute(.mdBlockType, value: BlockType.paragraph, range: NSRange(location: 0, length: 5))
        s.addAttribute(.mdCodeLanguage, value: "swift", range: NSRange(location: 0, length: 5))
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertNil(s.attribute(.mdCodeLanguage, at: 0, effectiveRange: nil))
    }

    func test_setListKind_ordered_producesNumberedItem() {
        let s = storage("Un point")
        MarkdownBlockCommands.setListKind(.ordered, in: s, at: 0)
        XCTAssertEqual(serialized(s), "1. Un point")
    }
}
