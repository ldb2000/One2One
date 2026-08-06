import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `TableMoveCommands` (permutation d'une rangée/colonne de tableau
/// avec sa voisine) et son câblage — `EditorTextView.onTableMoveCommand` →
/// `Coordinator.performTableMove(_:)`. Même schéma de montage que
/// `Tests/TableEditCommandsTests.swift`.
@MainActor
final class TableMoveCommandsTests: XCTestCase {

    private let threeBodyRowsTable = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |"
    private let threeColumnsTable = "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |"

    // MARK: - Permuter une rangée vers le haut

    func test_swapRowUp_swapsCursorRowWithThePreviousRow() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0)) // rangée 2 (corps, du milieu)

        let handled = TableMoveCommands.swapRowUp(in: editor)

        XCTAssertTrue(handled)
        // Le texte ne bouge jamais dans le storage (voir la doc de tête) :
        // seule la valeur de `row` change, la chaîne brute reste identique.
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6")
        let md = serialized(editor)
        XCTAssertEqual(md, "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |",
                       "rangée « 3 | 4 » (row 2) et rangée « 1 | 2 » (row 1) permutées")
    }

    func test_swapRowUp_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableMoveCommands.swapRowUp(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }

        let a = try info(at: "A")
        XCTAssertEqual(a.row, 0, "l'en-tête ne bouge jamais")
        let one = try info(at: "1")
        XCTAssertEqual(one.row, 2, "« 1 | 2 » (row 1) devient row 2")
        XCTAssertEqual(one.column, 0)
        let three = try info(at: "3")
        XCTAssertEqual(three.row, 1, "« 3 | 4 » (row 2) devient row 1")
        XCTAssertEqual(three.column, 0)
        let five = try info(at: "5")
        XCTAssertEqual(five.row, 3, "row 3, non concernée, inchangée")
        XCTAssertEqual(a.tableID, five.tableID)
    }

    func test_swapRowUp_onHeaderRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // en-tête

        let handled = TableMoveCommands.swapRowUp(in: editor)

        XCTAssertFalse(handled, "l'en-tête ne doit jamais être permutée")
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6")
    }

    /// La rangée 1 (première rangée de corps) : sa seule voisine du dessus
    /// est l'en-tête — refus symétrique au précédent.
    func test_swapRowUp_onFirstBodyRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0)) // rangée 1

        let handled = TableMoveCommands.swapRowUp(in: editor)

        XCTAssertFalse(handled, "la voisine du dessus de row 1 est l'en-tête")
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6")
    }

    func test_swapRowUp_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = TableMoveCommands.swapRowUp(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "Paragraphe\nA\nB\n1\n2\n3\n4\n5\n6")
    }

    /// La primitive interne (`performSwapRows`, exercée ici via l'API
    /// publique) est sa propre inverse pour une **même paire** de rangées
    /// (voir la doc de tête de `TableMoveCommands` — c'est ce sur quoi
    /// s'appuie `undoManager`, testé plus bas). Rappeler `swapRowUp` une
    /// seconde fois au même endroit n'est en revanche PAS un aller-retour :
    /// le curseur reste au même *caractère* ("3", jamais déplacé dans le
    /// storage), mais ce caractère porte maintenant `row == 1` après le
    /// premier geste — sa voisine du dessus est désormais l'en-tête, donc
    /// `swapRowUp` refuse (garde `info.row > 1`). C'est `swapRowDown` depuis
    /// ce même curseur qui referme l'aller-retour (même paire de rangées,
    /// swap dans l'autre sens).
    func test_swapRowUp_thenSwapRowDownFromSameCursor_restoresOriginalOrder() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        XCTAssertTrue(TableMoveCommands.swapRowUp(in: editor))
        XCTAssertFalse(TableMoveCommands.swapRowUp(in: editor), "row 1 après le premier geste : la voisine du dessus est l'en-tête")
        XCTAssertTrue(TableMoveCommands.swapRowDown(in: editor), "referme l'aller-retour, même paire de rangées")

        XCTAssertEqual(storage.string, originalString)
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |")
    }

    // MARK: - Annulation (rangée)

    func test_undoingASwapRowUp_restoresThePreviousOrder_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: threeBodyRowsTable)
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(TableMoveCommands.swapRowUp(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |")
        XCTAssertEqual(editor.undoManager?.canUndo, true, "la permutation doit s'être enregistrée auprès de l'undo manager")

        editor.undoManager?.undo()
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |", "⌘Z doit défaire la permutation")

        editor.undoManager?.redo()
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |", "⇧⌘Z doit la rétablir")
    }

    // MARK: - Câblage clavier réel (⌘⌥⌃↑ synthétique)

    func test_realCommandOptionControlUpArrowKeyEvent_swapsRowUp() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        editor.keyDown(with: try commandOptionControlArrowEvent(keyCode: 0x7E)) // flèche haut

        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |")
    }

    /// Vérifie l'absence de collision avec `TableEditCommands.deleteRow` :
    /// le même keyCode (flèche bas) avec ⌘⌥⌃ permute, avec ⌘⌥⇧ supprime —
    /// les deux doivent rester distinguables.
    func test_commandOptionControlDownArrow_doesNotTriggerDeleteRow() throws {
        let (editor, coordinator) = makeWiredEditor(markdown: threeBodyRowsTable)
        editor.onTableMoveCommand = { [weak coordinator] gesture in coordinator?.performTableMove(gesture) }
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        editor.keyDown(with: try commandOptionControlArrowEvent(keyCode: 0x7D)) // flèche bas

        // Permutation de row 1 ↔ row 2, PAS suppression : les deux rangées
        // doivent toujours être là, juste échangées.
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6", "aucune suppression : le texte ne bouge pas")
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |")
    }

    func test_whileSlashMenuOpen_swapRowUp_doesNotRun() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.performTableMove(.swapRowUp)

        // Une permutation ne bouge jamais le texte dans le storage (voir la
        // doc de tête de `TableMoveCommands`) : comparer `storage.string`
        // serait aveugle à une permutation qui aurait bel et bien eu lieu
        // (la chaîne resterait identique dans les deux cas) — seul
        // `TableCellInfo.row` distingue « exécutée » de « refusée ».
        // `threeLocation + 1` : le "/" tapé juste avant "3" l'a décalée
        // d'une position.
        let threeInfo = try XCTUnwrap(
            storage.attribute(.mdTableCell, at: threeLocation + 1, effectiveRange: nil) as? TableCellInfo
        )
        XCTAssertEqual(threeInfo.row, 2, "row 2 inchangée : la permutation ne doit pas s'exécuter, menu ouvert")
    }

    // MARK: - Permuter une rangée vers le bas

    func test_swapRowDown_swapsCursorRowWithTheNextRow() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0)) // rangée 1

        let handled = TableMoveCommands.swapRowDown(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 3 | 4 |\n| 1 | 2 |\n| 5 | 6 |")
    }

    func test_swapRowDown_onHeaderRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        let handled = TableMoveCommands.swapRowDown(in: editor)

        XCTAssertFalse(handled, "l'en-tête ne doit jamais être permutée")
    }

    func test_swapRowDown_onLastRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let fiveLocation = (storage.string as NSString).range(of: "5").location
        editor.setSelectedRange(NSRange(location: fiveLocation, length: 0)) // dernière rangée

        let handled = TableMoveCommands.swapRowDown(in: editor)

        XCTAssertFalse(handled, "pas de rangée après la dernière")
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6")
    }

    func test_swapRowDown_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + threeBodyRowsTable)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertFalse(TableMoveCommands.swapRowDown(in: editor))
    }

    // MARK: - Permuter une colonne vers la gauche/droite

    func test_swapColumnRight_swapsCursorColumnWithTheNextColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // colonne 0

        let handled = TableMoveCommands.swapColumnRight(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "A\nB\nC\n1\n2\n3\n4\n5\n6", "le texte ne bouge jamais dans le storage")
        XCTAssertEqual(serialized(editor), "| B | A | C |\n| --- | --- | --- |\n| 2 | 1 | 3 |\n| 5 | 4 | 6 |")
    }

    func test_swapColumnRight_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        _ = TableMoveCommands.swapColumnRight(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }
        let a = try info(at: "A")
        XCTAssertEqual(a.column, 1)
        XCTAssertEqual(a.columnCount, 3, "columnCount inchangé — seule la colonne bouge")
        let b = try info(at: "B")
        XCTAssertEqual(b.column, 0)
        let c = try info(at: "C")
        XCTAssertEqual(c.column, 2, "colonne 2, non concernée, inchangée")
        XCTAssertEqual(a.tableID, c.tableID)
    }

    func test_swapColumnRight_onRightmostColumn_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let cLocation = (storage.string as NSString).range(of: "C").location
        editor.setSelectedRange(NSRange(location: cLocation, length: 0)) // colonne 2 (dernière)

        let handled = TableMoveCommands.swapColumnRight(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "A\nB\nC\n1\n2\n3\n4\n5\n6")
    }

    func test_swapColumnLeft_swapsCursorColumnWithThePreviousColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0)) // colonne 1

        let handled = TableMoveCommands.swapColumnLeft(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(serialized(editor), "| B | A | C |\n| --- | --- | --- |\n| 2 | 1 | 3 |\n| 5 | 4 | 6 |")
    }

    func test_swapColumnLeft_onLeftmostColumn_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // colonne 0 (première)

        let handled = TableMoveCommands.swapColumnLeft(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "A\nB\nC\n1\n2\n3\n4\n5\n6")
    }

    func test_swapColumnLeft_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + threeColumnsTable)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertFalse(TableMoveCommands.swapColumnLeft(in: editor))
    }

    /// L'alignement est une propriété de colonne dupliquée par cellule (voir
    /// `TableCellInfo.alignment`) : elle doit voyager avec sa colonne, pas
    /// rester figée sur l'index. Assertion sur le markdown sérialisé
    /// (`---`/`:---`/`:---:`/`---:`), pas seulement sur les cellules.
    func test_swapColumnRight_alignmentTravelsWithItsColumn() throws {
        let alignedTable = "| A | B | C |\n|:---|:---:|---:|\n| 1 | 2 | 3 |"
        let (editor, _) = makeWiredEditor(markdown: alignedTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // colonne 0, alignée à gauche

        _ = TableMoveCommands.swapColumnRight(in: editor) // permute avec colonne 1 (centrée)

        // Colonne 0 (maintenant "B"/"2") doit porter l'alignement centré
        // qu'avait la colonne 1 ; colonne 1 (maintenant "A"/"1") doit porter
        // l'alignement gauche qu'avait la colonne 0 — les deux alignements
        // ont suivi leur contenu, pas leur ancien index.
        XCTAssertEqual(serialized(editor), "| B | A | C |\n| :---: | :--- | ---: |\n| 2 | 1 | 3 |")
    }

    // MARK: - Round-trip après reparse

    func test_swapRowUp_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableMoveCommands.swapRowUp(in: editor)

        let md = serialized(editor)
        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
    }

    // MARK: - Rendu : `NSTextTable` toujours partagée après la permutation

    func test_swapRowUp_allCellsShareTheSameNSTextTableInstanceAfterward() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableMoveCommands.swapRowUp(in: editor)

        var tables: [ObjectIdentifier] = []
        var blockCount = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            blockCount += 1
            tables.append(ObjectIdentifier(block.table))
        }
        XCTAssertEqual(blockCount, 8, "4 rangées × 2 colonnes")
        XCTAssertEqual(Set(tables).count, 1, "toutes les cellules doivent partager la même NSTextTable après permutation")
    }

    // MARK: - Fixtures (copiées de TableEditCommandsTests)

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
        editor.onTableEditCommand = { [weak coordinator] gesture in
            coordinator?.performTableEdit(gesture)
        }
        editor.onTableMoveCommand = { [weak coordinator] gesture in
            coordinator?.performTableMove(gesture)
        }

        let parsed = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(parsed)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        coordinator.lastKnownMarkdown = markdown
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        return (editor, coordinator)
    }

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

    private func makeWiredEditorInWindow(markdown: String) -> (EditorTextView, NSWindow) {
        let (editor, _) = makeWiredEditor(markdown: markdown)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = editor
        editor.undoManager?.groupsByEvent = false
        return (editor, window)
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

    private func commandOptionControlArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let char = String(UnicodeScalar(0xF701)!)
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option, .control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
