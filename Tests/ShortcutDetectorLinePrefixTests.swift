import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre les raccourcis de **préfixe de ligne** ajoutés à `ShortcutDetector`
/// (titres, listes, citation, séparateur) — même schéma de montage que
/// `Tests/EditorRepresentableSlashWiringTests.swift` : un vrai `Coordinator`
/// branché comme délégué de l'`EditorTextView`, `editor.insertText`
/// déclenche pour de vrai `Coordinator.textDidChange` → `ShortcutDetector.apply`,
/// aucun appel manuel n'est nécessaire.
@MainActor
final class ShortcutDetectorLinePrefixTests: XCTestCase {

    // MARK: - Titres

    func test_hashSpace_convertsToH1() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("# ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "# Titre")
    }

    func test_doubleHashSpace_convertsToH2() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("## ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "## Titre")
    }

    func test_tripleHashSpace_convertsToH3() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("### ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "### Titre")
    }

    func test_quadHashSpace_convertsToH4() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("#### ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "#### Titre")
    }

    func test_quintHashSpace_convertsToH5() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("##### ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "##### Titre")
    }

    func test_sextHashSpace_convertsToH6() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("###### ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "###### Titre")
    }

    /// 7 `#` dépasse le niveau maximal (h6) : CommonMark ne reconnaît pas de
    /// titre au-delà, le préfixe doit rester du texte littéral.
    func test_sevenHashesSpace_isNotAHeading_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("####### ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "####### ")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    func test_heading_insertedAtStartOfExistingLine_convertsWholeLine() {
        let (editor, _) = makeWiredEditor(markdown: "Bonjour")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("## ", into: editor)
        XCTAssertEqual(serialized(editor), "## Bonjour")
    }

    func test_heading_preservesBoldFormattingAlreadyOnTheLine() {
        let (editor, _) = makeWiredEditor(markdown: "**gras** texte")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("# ", into: editor)
        XCTAssertEqual(serialized(editor), "# **gras** texte")
    }

    func test_heading_preservesLinkAlreadyOnTheLine() {
        let (editor, _) = makeWiredEditor(markdown: "[lien](https://exemple.fr) texte")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("> ", into: editor)
        XCTAssertEqual(serialized(editor), "> [lien](https://exemple.fr) texte")
    }

    func test_heading_preservesImageAlreadyOnTheLine() {
        let (editor, _) = makeWiredEditor(markdown: "![alt](file:///tmp/a.png) texte")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("- ", into: editor)
        XCTAssertEqual(serialized(editor), "- ![alt](file:///tmp/a.png) texte")
    }

    func test_heading_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("## ", into: editor)
        editor.insertText("Titre", replacementRange: editor.selectedRange())
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    func test_hashSpace_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("# ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "# ")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    func test_hashSpace_insideCodeBlock_doesNotConvert() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let storage = NSMutableAttributedString(string: "a\n#")
        storage.addAttribute(.mdBlockType, value: BlockType.codeBlock, range: NSRange(location: 0, length: 3))
        editor.textStorage?.setAttributedString(storage)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.typingAttributes[.mdBlockType] = BlockType.codeBlock

        editor.insertText(" ", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.textStorage?.string, "a\n# ")
        XCTAssertEqual(editor.textStorage?.attribute(.mdBlockType, at: 2, effectiveRange: nil) as? BlockType, .codeBlock)
    }

    func test_hashSpace_insideTableCell_doesNotConvert() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let cellInfo = TableCellInfo(tableID: UUID(), row: 0, column: 0, columnCount: 1, alignment: nil)
        let storage = NSMutableAttributedString(string: "#")
        storage.addAttribute(.mdTableCell, value: cellInfo, range: NSRange(location: 0, length: 1))
        editor.textStorage?.setAttributedString(storage)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.typingAttributes[.mdTableCell] = cellInfo

        editor.insertText(" ", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.textStorage?.string, "# ")
        XCTAssertNotNil(editor.textStorage?.attribute(.mdTableCell, at: 0, effectiveRange: nil), "la cellule doit rester une cellule")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    // MARK: - Liste à puces

    func test_dashSpace_convertsToBulletList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("- ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "- item")
    }

    func test_asteriskSpace_convertsToBulletList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("* ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "- item")
    }

    func test_bulletList_preservesBoldFormattingAlreadyOnTheLine() {
        let (editor, _) = makeWiredEditor(markdown: "**fort**")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("- ", into: editor)
        XCTAssertEqual(serialized(editor), "- **fort**")
    }

    func test_bulletList_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("- ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    func test_dashSpace_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("- ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "- ")
        XCTAssertNil(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil))
    }

    // MARK: - Liste numérotée

    /// Vérifie aussi directement `.mdListInfo` (pas seulement le texte
    /// sérialisé) : un `"1. item"` resté texte littéral non converti
    /// sérialise de façon identique — `.`/chiffres ne figurent pas dans
    /// `MarkdownEscaping.inlineSpecials`, donc rien n'y est échappé — et
    /// **ne serait détecté par aucune assertion sur la seule chaîne**
    /// (mesuré par mutation : neutraliser la détection ne faisait échouer
    /// aucune version antérieure de ce test qui ne comparait que la chaîne).
    func test_oneDotSpace_convertsToOrderedList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("1. ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "1. item")
        let info = editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(info?.kind, .ordered, "« 1. » doit avoir converti la ligne en item de liste ordonnée, pas être resté texte littéral")
    }

    func test_multiDigitDotSpace_convertsToOrderedList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("12. ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        // `MarkdownBlockCommands.setListKind` ne fixe jamais d'ordinal
        // explicite (voir sa doc) : le marqueur affiché retombe sur 1, quel
        // que soit le nombre tapé.
        XCTAssertEqual(serialized(editor), "1. item")
    }

    func test_orderedList_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("1. ", into: editor)
        editor.insertText("item", replacementRange: editor.selectedRange())
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    func test_oneDotSpace_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("1. ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "1. ")
        XCTAssertNil(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil))
    }

    // MARK: - Case à cocher

    func test_dashBracketSpaceBracketSpace_fullMarker_convertsToTaskList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("- [ ] ", into: editor)
        editor.insertText("à faire", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "- [ ] à faire")
    }

    func test_bracketBracketSpace_shorthand_convertsToTaskList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("[] ", into: editor)
        editor.insertText("à faire", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "- [ ] à faire")
    }

    func test_bracketSpaceBracketSpace_shorthand_convertsToTaskList() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("[ ] ", into: editor)
        editor.insertText("à faire", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "- [ ] à faire")
    }

    /// Une case fraîchement créée démarre toujours décochée — même sur une
    /// ligne vide (rien à lire dans le storage : c'est `typingAttributes` qui
    /// porte l'état amorcé, piège 3).
    func test_taskList_onEmptyLine_startsUnchecked() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("[] ", into: editor)
        let primed = editor.typingAttributes[.mdListInfo] as? ListInfo
        XCTAssertEqual(primed?.kind, .task)
        XCTAssertEqual(primed?.checked, false)
    }

    func test_taskList_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("- [ ] ", into: editor)
        editor.insertText("à faire", replacementRange: editor.selectedRange())
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    func test_bracketBracketSpace_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("[] ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "[] ")
        XCTAssertNil(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil))
    }

    /// `- ` convertit d'abord en puce (bulletList activé) ; sans `taskList`,
    /// le `"[] "` tapé ensuite reste du texte littéral **dans l'item** —
    /// aucun blocage de la conversion précédente.
    func test_dashSpace_thenBracketBracketSpace_taskListDisabled_staysABulletWithLiteralText() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [.bulletList])
        type("- [] ", into: editor)
        editor.insertText("texte", replacementRange: editor.selectedRange())
        // `[`/`]` sont des `inlineSpecials` (`MarkdownEscaping`) : échappés à
        // la sérialisation, comme tout `[`/`]` littéral hors lien/image.
        XCTAssertEqual(serialized(editor), "- \\[\\] texte")
    }

    // MARK: - Citation

    /// Vérifie aussi directement `.mdBlockType` : `>` ne figure pas dans
    /// `MarkdownEscaping.inlineSpecials`, donc un `"> dit quelque chose"`
    /// resté texte littéral non converti sérialiserait de façon identique à
    /// la vraie citation — même angle mort que pour `1. ` (voir
    /// `test_oneDotSpace_convertsToOrderedList`), mesuré par mutation.
    func test_greaterThanSpace_convertsToBlockquote() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("> ", into: editor)
        editor.insertText("dit quelque chose", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "> dit quelque chose")
        XCTAssertEqual(
            editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType,
            .blockquote,
            "« > » doit avoir converti la ligne en citation, pas être resté texte littéral"
        )
    }

    func test_blockquote_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("> ", into: editor)
        editor.insertText("dit quelque chose", replacementRange: editor.selectedRange())
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    func test_greaterThanSpace_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("> ", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "> ")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    // MARK: - Séparateur (insertion, pas conversion)

    func test_tripleDash_convertsToThematicBreak() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("---", into: editor)
        editor.insertText("Après", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "---\nAprès")
    }

    /// Comme pour `SlashController.insertThematicBreak` : une ligne vide
    /// sépare le paragraphe qui précède du séparateur à la sérialisation
    /// (paire à risque `plainParagraph → thematicBreak`), sans qu'aucun `\n`
    /// supplémentaire n'ait été inséré dans le storage lui-même.
    func test_tripleDash_afterParagraph_serializesWithABlankLineBefore() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.insertText("Avant", replacementRange: editor.selectedRange())
        type("\n---", into: editor)
        editor.insertText("Après", replacementRange: editor.selectedRange())
        XCTAssertEqual(serialized(editor), "Avant\n\n---\nAprès")
    }

    func test_tripleDash_roundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("---", into: editor)
        let out = serialized(editor)
        let reparsed = MarkdownParser.parse(out)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), out)
    }

    /// La ligne entière doit être exactement `---` : si autre chose la suit
    /// déjà (curseur repositionné en tête d'une ligne non vide), aucune
    /// conversion n'a lieu — sinon le contenu qui suit serait perdu
    /// (`.thematicBreak` ignore l'inline à la sérialisation).
    func test_tripleDash_withTrailingContentOnTheSameLine_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.insertText("xyz", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("---", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "---xyz")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    func test_tripleDash_disabledFeature_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "", features: [])
        type("---", into: editor)
        XCTAssertEqual(editor.textStorage?.string, "---")
        XCTAssertNil(editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil))
    }

    func test_tripleDash_insideCodeBlock_doesNotConvert() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let storage = NSMutableAttributedString(string: "a\n--")
        storage.addAttribute(.mdBlockType, value: BlockType.codeBlock, range: NSRange(location: 0, length: 4))
        editor.textStorage?.setAttributedString(storage)
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.typingAttributes[.mdBlockType] = BlockType.codeBlock

        editor.insertText("-", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.textStorage?.string, "a\n---")
        XCTAssertEqual(editor.textStorage?.attribute(.mdBlockType, at: 2, effectiveRange: nil) as? BlockType, .codeBlock)
    }

    /// Tapé comme contenu littéral d'un item de liste déjà existant : choix
    /// conservateur (non mesuré), voir la doc d'`applyThematicBreakShortcut`.
    func test_tripleDash_typedInsideAnExistingListItem_staysLiteral() {
        let (editor, _) = makeWiredEditor(markdown: "")
        type("- ", into: editor) // devient un item de liste vide
        type("---", into: editor) // tapé comme texte de cet item

        // `-` est un `inlineSpecial` (`MarkdownEscaping`) : échappé à la
        // sérialisation puisque ce n'est pas devenu un séparateur.
        XCTAssertEqual(serialized(editor), "- \\-\\-\\-")
        XCTAssertNotNil(editor.textStorage?.attribute(.mdListInfo, at: 0, effectiveRange: nil))
        XCTAssertNotEqual(
            editor.textStorage?.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType,
            .thematicBreak
        )
    }

    // MARK: - Fixtures

    /// Même câblage que `Tests/EditorRepresentableSlashWiringTests.makeWiredEditor` :
    /// `editor.delegate = coordinator` réel, `editor.insertText` déclenche
    /// pour de vrai `Coordinator.textDidChange` (donc `ShortcutDetector.apply`).
    private func makeWiredEditor(markdown: String, features: Set<MarkdownFeature> = .full) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var text = markdown
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let representable = EditorRepresentable(
            markdown: binding, placeholder: "", features: features, debounce: 0, readOnly: false
        )
        let coordinator = representable.makeCoordinator()
        let editor = makeEditorTextView()
        editor.delegate = coordinator
        coordinator.textView = editor

        let parsed = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(parsed)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        coordinator.lastKnownMarkdown = markdown
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        return (editor, coordinator)
    }

    private func makeEditorTextView() -> EditorTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        return EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
    }

    /// Frappe caractère par caractère (déclenche pour de vrai le cycle
    /// délégué AppKit à chaque caractère, contrairement à une insertion
    /// groupée — voir la doc de la même fonction dans
    /// `Tests/EditorRepresentableSlashWiringTests.swift`).
    private func type(_ text: String, into editor: EditorTextView) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    private func serialized(_ editor: EditorTextView) -> String {
        MarkdownSerializer.serialize(editor.textStorage!)
    }
}
