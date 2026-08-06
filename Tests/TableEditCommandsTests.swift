import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `TableEditCommands` (ajout/suppression de ligne/colonne dans un
/// tableau markdown) et son câblage — `EditorTextView.onTableEditCommand` →
/// `Coordinator.performTableEdit(_:)`. Même schéma de montage que
/// `Tests/BlockMoveCommandsTests.swift`.
@MainActor
final class TableEditCommandsTests: XCTestCase {

    private let table = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"

    // MARK: - Ajouter une ligne

    func test_addRowBelow_insertsAnEmptyRowRightAfterTheCursorsRow() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0)) // rangée 1 (corps)

        let handled = TableEditCommands.addRowBelow(in: editor)

        XCTAssertTrue(handled)
        // "2" porte déjà son propre "\n" terminal ; la nouvelle rangée (2
        // cellules vides) en ajoute deux de plus avant "3" : trois "\n"
        // consécutifs, soit deux lignes vides à l'affichage brut.
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n\n\n3\n4")
    }

    /// Le contenu des autres cellules (texte + attributs `TableCellInfo`)
    /// doit survivre intact — pas seulement la chaîne brute.
    func test_addRowBelow_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addRowBelow(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }

        let a = try info(at: "A")
        XCTAssertEqual(a.row, 0)
        XCTAssertEqual(a.column, 0)
        XCTAssertEqual(a.columnCount, 2)

        let one = try info(at: "1")
        XCTAssertEqual(one.row, 1)
        XCTAssertEqual(one.column, 0)

        // La rangée "3 | 4" (row 2 avant l'insertion) doit être renumérotée row 3.
        let three = try info(at: "3")
        XCTAssertEqual(three.row, 3, "row 2 (0-based) avant l'insertion doit devenir row 3")
        XCTAssertEqual(three.column, 0)
        let four = try info(at: "4")
        XCTAssertEqual(four.row, 3)
        XCTAssertEqual(four.column, 1)

        // Toutes les cellules doivent partager le même tableID.
        XCTAssertEqual(a.tableID, one.tableID)
        XCTAssertEqual(a.tableID, three.tableID)
    }

    /// La nouvelle rangée elle-même : deux cellules vides, colonnes 0/1,
    /// row 2 (juste après la rangée 1 du curseur), alignement repris de
    /// l'en-tête (`nil` ici, aucun `:` dans le séparateur GFM source).
    func test_addRowBelow_newRowHasEmptyCellsWithCorrectInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addRowBelow(in: editor)

        // "A\nB\n1\n2\n\n\n3\n4" : "2\n" (terminal propre à la cellule "2")
        // est suivi des deux cellules vides de la nouvelle rangée, chacune un
        // simple "\n".
        let twoLocation = (storage.string as NSString).range(of: "2").location
        let firstNewCell = twoLocation + 2 // après "2\n", sur le "\n" de la 1ère cellule vide
        let secondNewCell = firstNewCell + 1

        let firstInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: firstNewCell, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(firstInfo.row, 2)
        XCTAssertEqual(firstInfo.column, 0)
        XCTAssertEqual(firstInfo.columnCount, 2)
        XCTAssertNil(firstInfo.alignment)

        let secondInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: secondNewCell, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(secondInfo.row, 2)
        XCTAssertEqual(secondInfo.column, 1)
    }

    /// Ajouter en dessous de la rangée d'en-tête (row 0) : la nouvelle
    /// rangée devient row 1, l'ancienne row 1 devient row 2.
    func test_addRowBelow_afterHeaderRow_insertsAsNewRow1() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // en-tête

        _ = TableEditCommands.addRowBelow(in: editor)

        XCTAssertEqual(storage.string, "A\nB\n\n\n1\n2\n3\n4")
        let oneInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "1").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(oneInfo.row, 2, "l'ancienne rangée 1 doit être renumérotée row 2")
    }

    /// Ajouter en dessous de la dernière rangée : insertion en fin de
    /// tableau, aucune renumérotation nécessaire.
    func test_addRowBelow_afterLastRow_appendsAtTheEnd() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableEditCommands.addRowBelow(in: editor)

        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n\n")
        let fourInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "4").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(fourInfo.row, 2, "rangée 2 (dernière) inchangée, aucune rangée suivante à renumérote")
    }

    /// Curseur hors tableau : aucun effet, pas de crash.
    func test_addRowBelow_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + table)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0)) // dans "Paragraphe"

        let handled = TableEditCommands.addRowBelow(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "Paragraphe\nA\nB\n1\n2\n3\n4")
    }

    // MARK: - Aller-retour markdown

    func test_addRowBelow_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addRowBelow(in: editor)

        let md = serialized(editor)
        XCTAssertEqual(md, "| A | B |\n| --- | --- |\n| 1 | 2 |\n|  |  |\n| 3 | 4 |")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        var rows: Set<Int> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            rows.insert(info.row)
        }
        XCTAssertEqual(rows, [0, 1, 2, 3], "4 rangées après reparse")
    }

    // MARK: - Rendu : `NSTextTable` toujours partagée après l'insertion

    /// `StyleRenderer` doit reconstruire une grille cohérente après
    /// l'ajout : toutes les cellules (existantes + nouvelles) doivent
    /// pointer vers la **même** `NSTextTable` — sans quoi la grille se
    /// disloquerait visuellement (cf. `MarkdownTableRenderingTests.
    /// test_table_allCellsShareTheSameNSTextTableInstance`, même mesure
    /// pour un tableau statique).
    func test_addRowBelow_allCellsShareTheSameNSTextTableInstanceAfterward() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addRowBelow(in: editor)

        var tables: [ObjectIdentifier] = []
        var blockCount = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            blockCount += 1
            tables.append(ObjectIdentifier(block.table))
        }
        // 4 rangées (en-tête + 3 de corps, dont la nouvelle) × 2 colonnes.
        XCTAssertEqual(blockCount, 8)
        XCTAssertEqual(Set(tables).count, 1, "toutes les cellules, y compris la nouvelle rangée, doivent partager la même NSTextTable")
    }

    // MARK: - Annulation

    func test_undoingAnAddRow_restoresThePreviousStorage_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: table)
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(TableEditCommands.addRowBelow(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n\n\n3\n4")
        XCTAssertEqual(editor.undoManager?.canUndo, true, "l'ajout doit s'être enregistré auprès de l'undo manager")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, originalString, "⌘Z doit défaire l'ajout de rangée")
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        let threeInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "3").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(threeInfo.row, 2, "la renumérotation doit elle aussi être défaite (retour à row 2)")

        editor.undoManager?.redo()
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n\n\n3\n4", "⇧⌘Z doit rétablir l'ajout")
    }

    // MARK: - Câblage clavier réel (⌘⌥↓ synthétique)

    func test_realCommandOptionDownArrowKeyEvent_addsARowBelow() throws {
        let (editor, coordinator) = makeWiredEditor(markdown: table)
        editor.onTableEditCommand = { [weak coordinator] gesture in coordinator?.performTableEdit(gesture) }
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        editor.keyDown(with: try commandOptionArrowEvent(keyCode: 0x7D)) // flèche bas

        XCTAssertEqual(storage.string, "A\nB\n1\n2\n\n\n3\n4")
    }

    func test_whileSlashMenuOpen_addRowBelow_doesNotRun() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.performTableEdit(.addRowBelow)

        XCTAssertEqual(storage.string, "A\nB\n/1\n2\n3\n4", "l'ajout ne doit pas s'exécuter, menu ouvert")
    }

    // MARK: - Fixtures (copiées de BlockMoveCommandsTests)

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
        editor.onOptionVerticalArrow = { [weak coordinator] up in
            coordinator?.moveCurrentBlock(up: up)
        }
        editor.onTableEditCommand = { [weak coordinator] gesture in
            coordinator?.performTableEdit(gesture)
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
            presentEmojiPicker: {}
        )
        coordinator.slashController = controller
        return (editor, coordinator, controller)
    }

    /// Comme `makeWiredEditor`, mais attache la vue à une vraie `NSWindow`
    /// (jamais affichée) : `NSResponder.undoManager` renvoie `nil` tant que
    /// la vue n'a pas de fenêtre.
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

    private func commandOptionArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let char = String(UnicodeScalar(0xF701)!)
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
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
