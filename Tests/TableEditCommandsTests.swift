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

    // MARK: - Ajouter une colonne

    func test_addColumnLeft_insertsAnEmptyColumnBeforeTheCursorsColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0)) // colonne 1

        let handled = TableEditCommands.addColumnLeft(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "A\n\nB\n1\n\n2\n3\n\n4")
    }

    func test_addColumnLeft_onLeftmostColumn_prependsAtTheRowStart() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // colonne 0

        let handled = TableEditCommands.addColumnLeft(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "\nA\nB\n\n1\n2\n\n3\n4")
        let aInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "A").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(aInfo.column, 1, "l'ancienne première colonne doit être décalée à droite")
        XCTAssertEqual(aInfo.columnCount, 3)
    }

    func test_addColumnLeft_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        _ = TableEditCommands.addColumnLeft(in: editor)

        let md = serialized(editor)
        XCTAssertEqual(md, "|  | A | B |\n| --- | --- | --- |\n|  | 1 | 2 |\n|  | 3 | 4 |")
    }

    func test_realCommandOptionLeftArrowKeyEvent_addsAColumnLeft() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        editor.keyDown(with: try commandOptionArrowEvent(keyCode: 0x7B)) // flèche gauche

        XCTAssertEqual(storage.string, "\nA\nB\n\n1\n2\n\n3\n4")
    }

    /// `.markdownReadOnly(true)` : les raccourcis d'édition de tableau
    /// (⌘⌥/⌘⌥⇧/⌘⌥⌃ + flèche) ne doivent pas muter le storage — `keyDown`
    /// les écarte en lecture seule avant même d'atteindre les handlers.
    func test_commandOptionArrowKeyEvent_onAReadOnlyEditor_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        editor.isEditable = false
        let storage = try XCTUnwrap(editor.textStorage)
        let before = storage.string
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        editor.keyDown(with: try commandOptionArrowEvent(keyCode: 0x7B)) // flèche gauche

        XCTAssertEqual(storage.string, before)
    }

    func test_addColumnRight_insertsAnEmptyColumnRightAfterTheCursorsColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0)) // colonne 0

        let handled = TableEditCommands.addColumnRight(in: editor)

        XCTAssertTrue(handled)
        // Une nouvelle cellule vide ("\n") insérée après chaque cellule de
        // colonne 0 ("A", "1", "3"), avant la colonne 1 existante.
        XCTAssertEqual(storage.string, "A\n\nB\n1\n\n2\n3\n\n4")
    }

    func test_addColumnRight_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addColumnRight(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }

        let a = try info(at: "A")
        XCTAssertEqual(a.row, 0)
        XCTAssertEqual(a.column, 0, "colonne 0 inchangée")
        XCTAssertEqual(a.columnCount, 3, "columnCount doit augmenter sur TOUTES les cellules, y compris celles non déplacées")

        // "B" était colonne 1, doit devenir colonne 2 (décalée à droite de
        // la nouvelle colonne).
        let b = try info(at: "B")
        XCTAssertEqual(b.column, 2)
        XCTAssertEqual(b.columnCount, 3)

        let one = try info(at: "1")
        XCTAssertEqual(one.row, 1)
        XCTAssertEqual(one.column, 0)
        let two = try info(at: "2")
        XCTAssertEqual(two.column, 2)

        let three = try info(at: "3")
        XCTAssertEqual(three.row, 2)
        XCTAssertEqual(three.column, 0)
        let four = try info(at: "4")
        XCTAssertEqual(four.column, 2)

        XCTAssertEqual(a.tableID, one.tableID)
        XCTAssertEqual(a.tableID, four.tableID)
    }

    /// La nouvelle colonne elle-même : une cellule vide par rangée, colonne
    /// 1, alignement `nil` (pas d'alignement établi pour une colonne neuve).
    func test_addColumnRight_newColumnHasEmptyCellsWithCorrectInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addColumnRight(in: editor)

        // "A\n\nB\n1\n\n2\n3\n\n4" : la nouvelle cellule de la rangée 0 est le
        // "\n" isolé entre "A\n" et "B".
        let ns = storage.string as NSString
        let aLocation = ns.range(of: "A").location
        let newCellRow0 = aLocation + 2 // après "A\n"
        let info0 = try XCTUnwrap(storage.attribute(.mdTableCell, at: newCellRow0, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(info0.row, 0)
        XCTAssertEqual(info0.column, 1)
        XCTAssertEqual(info0.columnCount, 3)
        XCTAssertNil(info0.alignment)

        let oneLoc = ns.range(of: "1").location
        let newCellRow1 = oneLoc + 2 // après "1\n"
        let info1 = try XCTUnwrap(storage.attribute(.mdTableCell, at: newCellRow1, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(info1.row, 1)
        XCTAssertEqual(info1.column, 1)
    }

    /// Colonne cursor la plus à droite : la nouvelle colonne s'ajoute en fin
    /// de chaque rangée.
    func test_addColumnRight_onRightmostColumn_appendsAtTheRowEnd() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0)) // colonne 1 (dernière)

        _ = TableEditCommands.addColumnRight(in: editor)

        XCTAssertEqual(storage.string, "A\nB\n\n1\n2\n\n3\n4\n")
        let fourInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "4").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(fourInfo.column, 1, "colonne 1 (« 4 ») inchangée, la nouvelle colonne est à sa droite (colonne 2)")
    }

    func test_addColumnRight_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + table)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = TableEditCommands.addColumnRight(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "Paragraphe\nA\nB\n1\n2\n3\n4")
    }

    // MARK: - Aller-retour markdown (colonne)

    func test_addColumnRight_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addColumnRight(in: editor)

        let md = serialized(editor)
        XCTAssertEqual(md, "| A |  | B |\n| --- | --- | --- |\n| 1 |  | 2 |\n| 3 |  | 4 |",
                       "3 colonnes après ajout, séparateur suivant")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        var columnCounts: Set<Int> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            columnCounts.insert(info.columnCount)
        }
        XCTAssertEqual(columnCounts, [3], "columnCount == 3 sur toutes les cellules après reparse")
    }

    // MARK: - Rendu (colonne) : `NSTextTable` toujours partagée après l'insertion

    func test_addColumnRight_allCellsShareTheSameNSTextTableInstanceAfterward() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        _ = TableEditCommands.addColumnRight(in: editor)

        var tables: [ObjectIdentifier] = []
        var blockCount = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            blockCount += 1
            tables.append(ObjectIdentifier(block.table))
        }
        // 3 rangées × 3 colonnes (2 originales + 1 nouvelle).
        XCTAssertEqual(blockCount, 9)
        XCTAssertEqual(Set(tables).count, 1, "toutes les cellules, y compris la nouvelle colonne, doivent partager la même NSTextTable")
    }

    // MARK: - Annulation (colonne)

    func test_undoingAnAddColumn_restoresThePreviousStorage_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: table)
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(TableEditCommands.addColumnRight(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "A\n\nB\n1\n\n2\n3\n\n4")
        XCTAssertEqual(editor.undoManager?.canUndo, true, "l'ajout doit s'être enregistré auprès de l'undo manager")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, originalString, "⌘Z doit défaire l'ajout de colonne")
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        let bInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "B").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(bInfo.column, 1, "la renumérotation doit elle aussi être défaite (retour à column 1)")
        XCTAssertEqual(bInfo.columnCount, 2)

        editor.undoManager?.redo()
        XCTAssertEqual(storage.string, "A\n\nB\n1\n\n2\n3\n\n4", "⇧⌘Z doit rétablir l'ajout")
    }

    // MARK: - Câblage clavier réel (⌘⌥→ synthétique, colonne)

    func test_realCommandOptionRightArrowKeyEvent_addsAColumnRight() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        editor.keyDown(with: try commandOptionArrowEvent(keyCode: 0x7C)) // flèche droite

        XCTAssertEqual(storage.string, "A\n\nB\n1\n\n2\n3\n\n4")
    }

    func test_whileSlashMenuOpen_addColumnRight_doesNotRun() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.performTableEdit(.addColumnRight)

        XCTAssertEqual(storage.string, "A\nB\n/1\n2\n3\n4", "l'ajout ne doit pas s'exécuter, menu ouvert")
    }

    // MARK: - Supprimer une ligne

    /// Trois rangées de corps (row 1, 2, 3), pour pouvoir supprimer une
    /// rangée du milieu sans toucher aux bords.
    private let threeBodyRowsTable = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |"
    /// `table` a déjà 2 rangées de corps (row 1, row 2) — insuffisant pour
    /// tester le refus de la dernière rangée de corps restante.
    private let oneBodyRowTable = "| A | B |\n|---|---|\n| 1 | 2 |"

    func test_deleteRow_removesTheCursorsRow() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0)) // rangée 2 (corps, du milieu)

        let handled = TableEditCommands.deleteRow(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n5\n6", "la rangée « 3 | 4 » a disparu, les autres restent contiguës")
    }

    func test_deleteRow_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableEditCommands.deleteRow(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }

        let a = try info(at: "A")
        XCTAssertEqual(a.row, 0)
        let one = try info(at: "1")
        XCTAssertEqual(one.row, 1)
        XCTAssertEqual(one.column, 0)
        // L'ancienne rangée 3 (« 5 | 6 ») doit être renumérotée row 2.
        let five = try info(at: "5")
        XCTAssertEqual(five.row, 2)
        XCTAssertEqual(five.column, 0)
        let six = try info(at: "6")
        XCTAssertEqual(six.row, 2)
        XCTAssertEqual(six.column, 1)
        XCTAssertEqual(a.tableID, five.tableID)
    }

    // MARK: - Refus aux bords

    func test_deleteRow_onHeaderRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let aLocation = (storage.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0)) // en-tête

        let handled = TableEditCommands.deleteRow(in: editor)

        XCTAssertFalse(handled, "la rangée d'en-tête ne doit jamais être supprimée")
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n3\n4\n5\n6")
    }

    func test_deleteRow_onlyRemainingBodyRow_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: oneBodyRowTable) // une seule rangée de corps
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        let handled = TableEditCommands.deleteRow(in: editor)

        XCTAssertFalse(handled, "un tableau sans corps n'a pas de sens")
        XCTAssertEqual(storage.string, "A\nB\n1\n2")
    }

    /// `table` a 2 rangées de corps (row 1, row 2) : supprimer l'une d'elles
    /// est permis tant qu'il en reste au moins une.
    func test_deleteRow_whenTwoBodyRowsRemain_isAllowed() throws {
        let (editor, _) = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0)) // rangée 2 (dernière)

        let handled = TableEditCommands.deleteRow(in: editor)

        XCTAssertTrue(handled)
        // "2" devient la dernière cellule du tableau mais garde son propre
        // "\n" terminal (posé par `MarkdownParser.emitTableRow` sur chaque
        // cellule) : seul un reparse complet retire le "\n" de tout le
        // document (voir `MarkdownParser.parse`), pas une mutation directe
        // du storage.
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n")
        XCTAssertEqual(serialized(editor), "| A | B |\n| --- | --- |\n| 1 | 2 |", "l'aller-retour markdown n'a lui aucune trace de ce \\n de fin")
    }

    func test_deleteRow_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = TableEditCommands.deleteRow(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "Paragraphe\nA\nB\n1\n2\n3\n4\n5\n6")
    }

    // MARK: - Aller-retour markdown (suppression de ligne)

    func test_deleteRow_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        _ = TableEditCommands.deleteRow(in: editor)

        let md = serialized(editor)
        XCTAssertEqual(md, "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 5 | 6 |")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        var rows: Set<Int> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            rows.insert(info.row)
        }
        XCTAssertEqual(rows, [0, 1, 2], "3 rangées après reparse")
    }

    // MARK: - Annulation (suppression de ligne)

    /// Le contenu réel de la rangée supprimée (pas seulement une rangée vide)
    /// doit être restauré à l'identique par ⌘Z.
    func test_undoingADeleteRow_restoresTheExactContent_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: threeBodyRowsTable)
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(TableEditCommands.deleteRow(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n5\n6")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, originalString, "⌘Z doit restaurer le contenu exact de la rangée supprimée")
        let fourInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "4").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(fourInfo.row, 2, "la renumérotation doit elle aussi être défaite (retour à row 2)")

        editor.undoManager?.redo()
        XCTAssertEqual(storage.string, "A\nB\n1\n2\n5\n6", "⇧⌘Z doit rétablir la suppression")
    }

    // MARK: - Câblage clavier réel (⌘⌥⇧↓ synthétique)

    func test_realCommandOptionShiftDownArrowKeyEvent_deletesTheRow() throws {
        let (editor, _) = makeWiredEditor(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))

        editor.keyDown(with: try commandOptionShiftArrowEvent(keyCode: 0x7D)) // flèche bas

        XCTAssertEqual(storage.string, "A\nB\n1\n2\n5\n6")
    }

    func test_whileSlashMenuOpen_deleteRow_doesNotRun() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: threeBodyRowsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let threeLocation = (storage.string as NSString).range(of: "3").location
        editor.setSelectedRange(NSRange(location: threeLocation, length: 0))
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.performTableEdit(.deleteRow)

        XCTAssertEqual(storage.string, "A\nB\n1\n2\n/3\n4\n5\n6", "la suppression ne doit pas s'exécuter, menu ouvert")
    }

    // MARK: - Supprimer une colonne

    /// Trois colonnes (0, 1, 2), pour pouvoir supprimer une colonne du
    /// milieu sans toucher aux bords.
    private let threeColumnsTable = "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |"
    /// Une seule colonne : fixture pour le refus de la dernière colonne.
    private let oneColumnTable = "| A |\n|---|\n| 1 |"

    func test_deleteColumn_removesTheCursorsColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0)) // colonne 1 (du milieu)

        let handled = TableEditCommands.deleteColumn(in: editor)

        XCTAssertTrue(handled)
        XCTAssertEqual(storage.string, "A\nC\n1\n3\n4\n6", "la colonne « B | 2 | 5 » a disparu")
    }

    func test_deleteColumn_otherCellsSurviveWithCorrectTableCellInfo() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))

        _ = TableEditCommands.deleteColumn(in: editor)

        let ns = storage.string as NSString
        func info(at substring: String) throws -> TableCellInfo {
            let location = ns.range(of: substring).location
            return try XCTUnwrap(storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo)
        }

        let a = try info(at: "A")
        XCTAssertEqual(a.row, 0)
        XCTAssertEqual(a.column, 0, "colonne 0 inchangée")
        XCTAssertEqual(a.columnCount, 2, "columnCount doit diminuer sur TOUTES les cellules")

        // "C" était colonne 2, doit devenir colonne 1 (décalée à gauche).
        let c = try info(at: "C")
        XCTAssertEqual(c.column, 1)
        XCTAssertEqual(c.columnCount, 2)

        let one = try info(at: "1")
        XCTAssertEqual(one.row, 1)
        XCTAssertEqual(one.column, 0)
        let three = try info(at: "3")
        XCTAssertEqual(three.row, 1)
        XCTAssertEqual(three.column, 1)

        let four = try info(at: "4")
        XCTAssertEqual(four.row, 2)
        XCTAssertEqual(four.column, 0)
        let six = try info(at: "6")
        XCTAssertEqual(six.row, 2)
        XCTAssertEqual(six.column, 1)

        XCTAssertEqual(a.tableID, six.tableID)
    }

    // MARK: - Refus aux bords (colonne)

    func test_deleteColumn_onlyRemainingColumn_isRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: oneColumnTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        let handled = TableEditCommands.deleteColumn(in: editor)

        XCTAssertFalse(handled, "un tableau sans colonne n'a pas de sens")
        XCTAssertEqual(storage.string, "A\n1")
    }

    /// Symétrique de `test_deleteRow_whenTwoBodyRowsRemain_isAllowed` :
    /// supprimer jusqu'à ne laisser qu'une seule colonne est permis, une
    /// deuxième suppression est alors refusée.
    func test_deleteColumn_downToTheLastColumn_thenRefused() throws {
        let (editor, _) = makeWiredEditor(markdown: table) // 2 colonnes
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0)) // colonne 1

        XCTAssertTrue(TableEditCommands.deleteColumn(in: editor))
        // "3" (row 1) porte encore son propre "\n" terminal (elle avait
        // toujours eu une cellule après elle, « 4 », qui seule manquait de
        // "\n" — voir la même remarque pour la suppression de ligne) : seul
        // un reparse complet retire le "\n" de tout le document.
        XCTAssertEqual(storage.string, "A\n1\n3\n")

        editor.setSelectedRange(NSRange(location: 0, length: 0)) // colonne 0, seule restante
        let handled = TableEditCommands.deleteColumn(in: editor)

        XCTAssertFalse(handled, "il ne doit plus rester qu'une seule colonne, sa suppression est refusée")
        XCTAssertEqual(storage.string, "A\n1\n3\n")
    }

    func test_deleteColumn_cursorOutsideTable_isANoOp() throws {
        let (editor, _) = makeWiredEditor(markdown: "Paragraphe\n\n" + threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        let handled = TableEditCommands.deleteColumn(in: editor)

        XCTAssertFalse(handled)
        XCTAssertEqual(storage.string, "Paragraphe\nA\nB\nC\n1\n2\n3\n4\n5\n6")
    }

    // MARK: - Aller-retour markdown (suppression de colonne)

    func test_deleteColumn_roundTripsCorrectly() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))

        _ = TableEditCommands.deleteColumn(in: editor)

        let md = serialized(editor)
        XCTAssertEqual(md, "| A | C |\n| --- | --- |\n| 1 | 3 |\n| 4 | 6 |")

        let reparsed = NSTextStorage(attributedString: MarkdownParser.parse(md))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), md, "round-trip stable")
        var columnCounts: Set<Int> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            columnCounts.insert(info.columnCount)
        }
        XCTAssertEqual(columnCounts, [2], "columnCount == 2 sur toutes les cellules après reparse")
    }

    // MARK: - Rendu (colonne) : `NSTextTable` toujours partagée après la suppression

    func test_deleteColumn_allCellsShareTheSameNSTextTableInstanceAfterward() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))

        _ = TableEditCommands.deleteColumn(in: editor)

        var tables: [ObjectIdentifier] = []
        var blockCount = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first as? NSTextTableBlock else { return }
            blockCount += 1
            tables.append(ObjectIdentifier(block.table))
        }
        // 3 rangées × 2 colonnes restantes.
        XCTAssertEqual(blockCount, 6)
        XCTAssertEqual(Set(tables).count, 1, "toutes les cellules doivent partager la même NSTextTable après la suppression")
    }

    // MARK: - Annulation (suppression de colonne)

    /// Le contenu réel de la colonne supprimée (pas seulement une colonne
    /// vide fraîchement ajoutée) doit être restauré à l'identique par ⌘Z.
    func test_undoingADeleteColumn_restoresTheExactContent_andRedoReappliesIt() throws {
        let (editor, window) = makeWiredEditorInWindow(markdown: threeColumnsTable)
        XCTAssertNotNil(editor.window, "prémisse : la vue doit être rattachée à \(window) pour que undoManager résolve")
        let storage = try XCTUnwrap(editor.textStorage)
        let originalString = storage.string
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))

        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(TableEditCommands.deleteColumn(in: editor))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(storage.string, "A\nC\n1\n3\n4\n6")

        editor.undoManager?.undo()
        XCTAssertEqual(storage.string, originalString, "⌘Z doit restaurer le contenu exact de la colonne supprimée")
        let cInfo = try XCTUnwrap(storage.attribute(.mdTableCell, at: (storage.string as NSString).range(of: "C").location, effectiveRange: nil) as? TableCellInfo)
        XCTAssertEqual(cInfo.column, 2, "la renumérotation doit elle aussi être défaite (retour à column 2)")
        XCTAssertEqual(cInfo.columnCount, 3)

        editor.undoManager?.redo()
        XCTAssertEqual(storage.string, "A\nC\n1\n3\n4\n6", "⇧⌘Z doit rétablir la suppression")
    }

    // MARK: - Câblage clavier réel (⌘⌥⇧→ synthétique)

    func test_realCommandOptionShiftRightArrowKeyEvent_deletesTheColumn() throws {
        let (editor, _) = makeWiredEditor(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))

        editor.keyDown(with: try commandOptionShiftArrowEvent(keyCode: 0x7C)) // flèche droite

        XCTAssertEqual(storage.string, "A\nC\n1\n3\n4\n6")
    }

    func test_whileSlashMenuOpen_deleteColumn_doesNotRun() throws {
        let (editor, coordinator, controller) = makeWiredCoordinator(markdown: threeColumnsTable)
        let storage = try XCTUnwrap(editor.textStorage)
        let bLocation = (storage.string as NSString).range(of: "B").location
        editor.setSelectedRange(NSRange(location: bLocation, length: 0))
        type("/", into: editor)
        XCTAssertTrue(controller.isOpen, "prémisse : le menu doit être ouvert")

        coordinator.performTableEdit(.deleteColumn)

        XCTAssertEqual(storage.string, "A\n/B\nC\n1\n2\n3\n4\n5\n6", "la suppression ne doit pas s'exécuter, menu ouvert")
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
            presentEmojiPicker: {},
            presentFilePicker: { $0(nil) }
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

    private func commandOptionShiftArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let char = String(UnicodeScalar(0xF701)!)
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option, .shift],
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
