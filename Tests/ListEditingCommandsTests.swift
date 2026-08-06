import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `ListEditingCommands` (⏎/Tab/⇧Tab/⌫ dans une liste) et son câblage
/// dans `EditorRepresentable.Coordinator.textView(_:doCommandBy:)`. Même
/// schéma de montage que `Tests/EditorRepresentableSlashWiringTests.swift` :
/// un vrai `Coordinator` branché comme délégué, `coordinator.textView(_:doCommandBy:)`
/// appelé directement (comme le ferait `NSTextView` lui-même à la frappe).
@MainActor
final class ListEditingCommandsTests: XCTestCase {

    // MARK: - ⏎ sur un item non vide : nouvel item de même type

    func test_return_onNonEmptyBulletItem_createsANewBulletItem() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("second", replacementRange: editor.selectedRange())

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "- item\n- second")
    }

    func test_return_onNonEmptyOrderedItem_createsANewOrderedItem() {
        let (editor, coordinator) = makeWiredEditor(markdown: "1. item")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("second", replacementRange: editor.selectedRange())

        XCTAssertEqual(serialized(editor), "1. item\n1. second")
    }

    /// Le nouvel item démarre toujours décoché — une case cochée ne doit pas
    /// se propager à l'item suivant.
    func test_return_onCheckedTaskItem_newItemStartsUnchecked() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- [x] fait")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("suivant", replacementRange: editor.selectedRange())

        XCTAssertEqual(serialized(editor), "- [x] fait\n- [ ] suivant")
    }

    /// Le `\n` inséré termine l'item COURANT et porte donc ses attributs
    /// exacts (y compris `checked`) — seul le *nouvel* item (typingAttributes,
    /// pas encore de caractère) doit repartir décoché. Preuve directe,
    /// indépendante de la sérialisation : sans elle, un bug qui décocherait
    /// aussi rétroactivement l'item existant ne serait détecté par aucun
    /// test (la sérialisation du premier item resterait "- [x] fait" même si
    /// l'attribut réel changeait, tant que rien ne le relit directement).
    func test_return_onCheckedTaskItem_theExistingItemStaysChecked() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- [x] fait")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        let info = editor.textStorage!.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(info?.checked, true, "l'item déjà tapé ne doit pas être décoché rétroactivement")
    }

    func test_return_onNonEmptyItem_doesNotInheritBoldFromEndOfItem() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- **gras**")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("normal", replacementRange: editor.selectedRange())

        XCTAssertEqual(serialized(editor), "- **gras**\n- normal")
    }

    // MARK: - ⏎ sur un item vide : sortir de la liste

    /// Item vide en milieu de document (un item précédent existe) : le `\n`
    /// terminal de l'item vide porte encore `.mdListInfo`, à réattribuer.
    func test_return_onEmptyItem_notLastInDocument_exitsToParagraph() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- premier")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) // crée un 2e item vide

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("texte normal", replacementRange: editor.selectedRange())

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "- premier\n\ntexte normal", "paire à risque item de liste → paragraphe : ligne vide à la sérialisation")
    }

    /// Ne doit pas insérer de nouvelle ligne : le curseur reste sur la MÊME
    /// ligne, désormais un paragraphe vide.
    func test_return_onEmptyItem_doesNotInsertANewLine() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- premier")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        let lengthBefore = editor.textStorage!.length

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(editor.textStorage!.length, lengthBefore, "aucun caractère ne doit avoir été ajouté")
    }

    /// Item vide en toute fin de document (aucun item précédent) : rien à
    /// réattribuer dans le storage (aucun `\n`), seul `typingAttributes` porte
    /// l'état amorcé — preuve directe puisque la sérialisation d'un document
    /// entièrement vide ne distinguerait pas les deux chemins.
    func test_return_onEmptyItem_veryFirstAndOnlyItem_primesTypingAttributesToParagraph() {
        let (editor, coordinator) = makeWiredEditor(markdown: "")
        type("- ", into: editor) // devient un item de liste vide, seul contenu du document

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        editor.insertText("texte", replacementRange: editor.selectedRange())

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "texte")
    }

    func test_return_notInAList_isNotHandled() {
        let (editor, coordinator) = makeWiredEditor(markdown: "Simple paragraphe")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(handled)
    }

    // MARK: - Tab : indenter

    func test_tab_onNonEmptyItem_indentsByOneLevel() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 3, length: 0)) // milieu de "item"

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "  - item")
    }

    func test_tab_twice_indentsToLevelTwo() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(serialized(editor), "    - item")
    }

    func test_tab_preservesItemText() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- **gras** et [lien](https://ex.com)")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(serialized(editor), "  - **gras** et [lien](https://ex.com)")
    }

    func test_tab_onEmptyItem_notLastInDocument_indentsTheEmptyItem() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- premier")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) // 2e item vide

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
        editor.insertText("indenté", replacementRange: editor.selectedRange())

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "- premier\n  - indenté")
    }

    func test_tab_notInAList_isNotHandled() {
        let (editor, coordinator) = makeWiredEditor(markdown: "Simple paragraphe")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))

        XCTAssertFalse(handled)
    }

    // MARK: - ⇧Tab : désindenter

    func test_backtab_onIndentedItem_removesOneLevel() {
        let (editor, coordinator) = makeWiredEditor(markdown: "  - item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "- item")
    }

    func test_backtab_atLevelZero_isConsumedWithoutGoingNegative() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertTrue(handled, "la touche est consommée même sans effet, pour ne pas déclencher un autre comportement par défaut")
        XCTAssertEqual(serialized(editor), "- item")
    }

    func test_tabThenBacktab_roundTripsToTheOriginalLevel() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(serialized(editor), "- item")
    }

    func test_backtab_notInAList_isNotHandled() {
        let (editor, coordinator) = makeWiredEditor(markdown: "Simple paragraphe")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertFalse(handled)
    }

    // MARK: - ⌫ en début d'item : retire le format, garde le texte

    func test_deleteBackward_atStartOfItem_stripsListFormat_keepsText() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "item")
    }

    func test_deleteBackward_atStartOfItem_doesNotMergeWithPreviousItem() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- premier\n- second")
        let secondItemStart = (editor.textStorage!.string as NSString).range(of: "second").location
        editor.setSelectedRange(NSRange(location: secondItemStart, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(serialized(editor), "- premier\n\nsecond", "« second » doit devenir un paragraphe séparé, pas fusionner dans « premier »")
    }

    func test_deleteBackward_preservesInlineFormatting() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- **gras** et [lien](https://ex.com)")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(serialized(editor), "**gras** et [lien](https://ex.com)")
    }

    func test_deleteBackward_taskItem_stripsToParagraph() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- [x] fait")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(serialized(editor), "fait")
    }

    /// Pas en tout début d'item (milieu de texte) : comportement par défaut,
    /// pas géré ici.
    func test_deleteBackward_midItem_isNotHandled() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: 3, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertFalse(handled)
    }

    func test_deleteBackward_notInAList_isNotHandled() {
        let (editor, coordinator) = makeWiredEditor(markdown: "Simple paragraphe")
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertFalse(handled)
    }

    func test_deleteBackward_onEmptyItem_notLastInDocument_stripsFormat() {
        let (editor, coordinator) = makeWiredEditor(markdown: "- premier")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) // 2e item vide

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
        editor.insertText("texte", replacementRange: editor.selectedRange())

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "- premier\n\ntexte")
    }

    // MARK: - Priorité : le menu « / » garde la main quand il est ouvert

    /// `SlashController.handle` n'intercepte, menu ouvert, que
    /// ↑↓/⏎/Tab/Échap (voir sa doc) — `⇧Tab` n'en fait pas partie. Sans la
    /// garde `slashController?.isOpen == true` dans `Coordinator.
    /// textView(_:doCommandBy:)`, `⇧Tab` tapé pendant la composition d'une
    /// requête sur une ligne qui est *aussi* un item de liste tomberait à
    /// tort dans `ListEditingCommands` et désindenterait l'item sous le menu
    /// encore ouvert.
    func test_backtab_whileSlashMenuOpen_isNotHandledByListEditingCommands() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("- ", into: editor) // item de liste vide
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:))) // indente à 1, pour avoir un niveau à retirer
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse du test : le menu doit être ouvert")

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertFalse(handled, "⇧Tab n'est pas une des touches que le menu « / » intercepte lui-même")
        let info = editor.textStorage!.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(info?.level, 1, "le niveau de l'item ne doit pas avoir changé pendant que le menu est ouvert")
    }

    /// Témoin symétrique : une fois le menu fermé, ⇧Tab reprend son effet
    /// normal sur la même ligne — sans lui, le test précédent pourrait passer
    /// pour une tout autre raison (ex. si ⇧Tab ne fonctionnait plus du tout).
    func test_witness_backtab_afterSlashMenuCloses_indentsNormally() {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: "")
        type("- ", into: editor)
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertTab(_:))) // niveau 1
        type("/", into: editor)
        _ = coordinator.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(controller.isOpen)

        let handled = coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertTrue(handled)
        let info = editor.textStorage!.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(info?.level, 0)
    }

    // MARK: - Fixtures

    /// Même câblage que `Tests/EditorRepresentableSlashWiringTests.makeWiredEditor`.
    private func makeWiredEditor(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var text = markdown
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let representable = EditorRepresentable(
            markdown: binding, placeholder: "", features: .full, debounce: 0, readOnly: false
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

    /// Idem, avec un `SlashController` assigné à `coordinator.slashController`
    /// (repris de `Tests/EditorRepresentableSlashWiringTests.makeWiredCoordinator`).
    private func makeWiredCoordinator(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator, SlashController) {
        let (editor, coordinator) = makeWiredEditor(markdown: markdown)
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: { [weak coordinator] in coordinator?.cancelPendingWrite() },
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) },
            presentEmojiPicker: {},
            presentFilePicker: { $0(nil) }
        )
        coordinator.slashController = controller
        return (editor, coordinator, controller)
    }

    private func makeEditorTextView() -> EditorTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        return EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
    }

    private func type(_ text: String, into editor: EditorTextView) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    private func serialized(_ editor: EditorTextView) -> String {
        MarkdownSerializer.serialize(editor.textStorage!)
    }
}
