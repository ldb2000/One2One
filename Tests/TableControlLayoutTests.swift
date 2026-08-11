import XCTest
import AppKit
@testable import OneToOne

/// Couvre `TableControlLayout` (géométrie des contrôles de tableau — ajouter/
/// supprimer une ligne/colonne, visibles quand le curseur est dans une
/// cellule) à trois niveaux :
/// - `placement(...)` : la formule pure (rectangles à partir de rectangles
///   déjà mesurés), déterministe, sans dépendance à une métrique de police —
///   la couverture principale de la géométrie.
/// - `placementForCursor(...)` : la lecture du storage (position du
///   tableau/de la rangée/de la cellule, gardes de suppression) — assertions
///   sur `nil`/non-`nil`, pas sur des pixels exacts (dépendraient des
///   métriques de police du système de test).
/// - `EditorTextView.tableControlGesture(at:)` : le câblage vue réelle
///   (sélection → conteneur → hit-test), en cliquant au centre d'un contrôle
///   dont la position est obtenue via `placementForCursor` (donc pas
///   totalement indépendant de la géométrie, mais indépendant du câblage —
///   sélection, décalage `textContainerInset`, dispatch — qui est ce que ce
///   niveau vise à couvrir).
///
/// Le clic réel (`NSEvent` + `mouseDown`) n'est pas exercé : un essai
/// précédent a bloqué le process dans la boucle de tracking AppKit d'un
/// `super.mouseDown` en attente de `mouseUp` (voir la doc de
/// `EditorTextViewTaskToggleTests`, même mesure). `tableControlGesture(at:)`
/// est donc testée comme fonction pure, comme `toggleTaskMarker(at:)`.
@MainActor
final class TableControlLayoutTests: XCTestCase {

    // MARK: - `placement(...)` — formule pure

    private let tableRect = NSRect(x: 10, y: 100, width: 300, height: 60)
    private let rowRect = NSRect(x: 10, y: 130, width: 300, height: 20)
    private let cellRect = NSRect(x: 160, y: 130, width: 150, height: 20)

    /// Décalage horizontal/vertical d'un contrôle par rapport au centre de
    /// son groupe — même formule que `TableControlLayout.placement`
    /// (`controlDiameter / 2 + controlGap / 2`), reproduite ici pour ne pas
    /// dépendre du détail interne d'implémentation, seulement de ses deux
    /// constantes publiques.
    private var clusterOffset: CGFloat {
        TableControlLayout.controlDiameter / 2 + TableControlLayout.controlGap / 2
    }

    func test_placement_addRow_isOnTheRowsBottomBorder_leftOfCellCenter() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        XCTAssertEqual(placement.addRow.midX, cellRect.midX - clusterOffset)
        XCTAssertEqual(placement.addRow.midY, rowRect.maxY, "bordure basse de la RANGÉE, jamais de la table (voir la doc de tête)")
        XCTAssertEqual(placement.addRow.width, TableControlLayout.controlDiameter)
        XCTAssertEqual(placement.addRow.height, TableControlLayout.controlDiameter)
    }

    func test_placement_addColumn_isOnTheColumnsRightBorder_aboveCellCenter() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        XCTAssertEqual(placement.addColumn.midX, cellRect.maxX, "bordure droite de la COLONNE, jamais de la table")
        XCTAssertEqual(placement.addColumn.midY, cellRect.midY + clusterOffset)
    }

    /// `deleteRow` partage la bordure basse de la rangée avec `addRow` (même
    /// `y`) — c'est le point central du nouveau schéma : les deux pastilles
    /// vivent sur une bordure **interne** (entre deux rangées, jamais la
    /// bordure extérieure du tableau) où `TableLayout.cellPadding` est
    /// disponible des deux côtés. Un premier essai centrait `deleteRow` sur
    /// `tableRect.minX` (bordure gauche du tableau) : la sonde de rendu
    /// bitmap a montré le contrôle empiéter sur le premier caractère de la
    /// cellule — voir la doc de tête de `TableControlLayout` et le rapport
    /// de tâche.
    func test_placement_deleteRow_whenAllowed_isOnTheRowsBottomBorder_rightOfCellCenter() throws {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        let deleteRow = try XCTUnwrap(placement.deleteRow)
        XCTAssertEqual(deleteRow.midX, cellRect.midX + clusterOffset)
        XCTAssertEqual(deleteRow.midY, rowRect.maxY, "même bordure qu'addRow — un seul groupe, pas deux contrôles isolés")
    }

    func test_placement_deleteRow_whenRefused_isNil() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: false, canDeleteColumn: true
        )

        XCTAssertNil(placement.deleteRow, "aucun contrôle pour un geste que TableEditCommands.deleteRow refuserait")
    }

    /// `addRow` ne se recentre pas quand `deleteRow` est absent (voir la
    /// doc de `placement`) : sa position reste la même, guide ou pas guide
    /// à côté — pas de « saut » selon la rangée du curseur.
    func test_placement_addRow_positionIsStable_whetherOrNotDeleteRowIsShown() {
        let shown = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )
        let hidden = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: false, canDeleteColumn: true
        )

        XCTAssertEqual(shown.addRow, hidden.addRow)
    }

    func test_placement_deleteColumn_whenAllowed_isOnTheColumnsRightBorder_belowCellCenter() throws {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        let deleteColumn = try XCTUnwrap(placement.deleteColumn)
        XCTAssertEqual(deleteColumn.midX, cellRect.maxX, "même bordure qu'addColumn")
        XCTAssertEqual(deleteColumn.midY, cellRect.midY - clusterOffset)
    }

    func test_placement_deleteColumn_whenRefused_isNil() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: false
        )

        XCTAssertNil(placement.deleteColumn, "aucun contrôle pour un geste que TableEditCommands.deleteColumn refuserait")
    }

    /// Les quatre contrôles sont centrés sur quatre bordures distinctes —
    /// aucun risque qu'ils se recouvrent l'un l'autre (rayons de
    /// `controlDiameter / 2`, très inférieurs aux dimensions du tableau
    /// utilisées ici).
    func test_placement_fourControls_doNotOverlapEachOther() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )
        let rects = [placement.addRow, placement.addColumn, placement.deleteRow!, placement.deleteColumn!]
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count where j != i {
                XCTAssertFalse(rects[i].intersects(rects[j]), "\(rects[i]) et \(rects[j]) ne devraient pas se chevaucher")
            }
        }
    }

    // MARK: - `gesture(at:in:)` — hit-test pur

    func test_gesture_hitsEachControlAtItsCenter() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        XCTAssertEqual(TableControlLayout.gesture(at: NSPoint(x: placement.addRow.midX, y: placement.addRow.midY), in: placement), .addRowBelow)
        XCTAssertEqual(TableControlLayout.gesture(at: NSPoint(x: placement.addColumn.midX, y: placement.addColumn.midY), in: placement), .addColumnRight)
        XCTAssertEqual(TableControlLayout.gesture(at: NSPoint(x: placement.deleteRow!.midX, y: placement.deleteRow!.midY), in: placement), .deleteRow)
        XCTAssertEqual(TableControlLayout.gesture(at: NSPoint(x: placement.deleteColumn!.midX, y: placement.deleteColumn!.midY), in: placement), .deleteColumn)
    }

    func test_gesture_pointFarFromAnyControl_isNil() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: true, canDeleteColumn: true
        )

        XCTAssertNil(TableControlLayout.gesture(at: NSPoint(x: cellRect.midX, y: cellRect.midY), in: placement),
                     "le centre de la cellule (texte) ne doit déclencher aucun geste")
    }

    func test_gesture_deleteRowRefused_clickAtWouldBeCenter_isNil() {
        let placement = TableControlLayout.placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: false, canDeleteColumn: true
        )

        let wouldBeCenter = NSPoint(x: cellRect.midX + clusterOffset, y: rowRect.maxY)
        XCTAssertNil(TableControlLayout.gesture(at: wouldBeCenter, in: placement))
    }

    func test_footerGeometry_matchesTheSegmentedToolbarLayout() {
        let geometry = TableControlLayout.footerGeometry(forTableRect: tableRect)

        XCTAssertEqual(geometry.footerRect, NSRect(x: 10, y: 160, width: 300, height: 36))
        XCTAssertEqual(geometry.addRowRect.width, 26)
        XCTAssertEqual(geometry.deleteRowRect.minX, geometry.addRowRect.maxX - 1)
        XCTAssertEqual(geometry.addColumnRect.maxX, geometry.footerRect.maxX - TableControlLayout.footerInset)
        XCTAssertEqual(geometry.addColumnRect.height, TableControlLayout.footerButtonHeight)
    }

    func test_footerAction_hitsEachVisibleCommand() {
        let geometry = TableControlLayout.footerGeometry(forTableRect: tableRect)

        XCTAssertEqual(TableControlLayout.footerAction(at: center(of: geometry.addRowRect), in: geometry), .addRow)
        XCTAssertEqual(TableControlLayout.footerAction(at: center(of: geometry.deleteRowRect), in: geometry), .deleteRow)
        XCTAssertEqual(TableControlLayout.footerAction(at: center(of: geometry.addColumnRect), in: geometry), .addColumn)
        XCTAssertNil(TableControlLayout.footerAction(at: NSPoint(x: geometry.footerRect.midX, y: geometry.footerRect.midY), in: geometry))
    }

    func test_headerChevron_isInsetInsideTheHeaderCell() {
        let cell = NSRect(x: 20, y: 40, width: 120, height: 30)
        let chevron = TableControlLayout.headerChevronRect(forCellRect: cell)

        XCTAssertTrue(cell.contains(chevron))
        XCTAssertEqual(chevron.width, TableControlLayout.headerChevronSize)
        XCTAssertEqual(chevron.maxX, cell.maxX - 6)
    }

    // MARK: - `placementForCursor(...)` — lecture du storage (gardes)

    private let table = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
    private let oneBodyRowTable = "| A | B |\n|---|---|\n| 1 | 2 |"
    private let oneColumnTable = "| A |\n|---|\n| 1 |"

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    func test_placementForCursor_cursorOutsideTable_isNil() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: "Paragraphe\n\n" + table)
        let placement = TableControlLayout.placementForCursor(
            in: storage, at: 0, layoutManager: layoutManager, container: container
        )
        XCTAssertNil(placement)
    }

    func test_placementForCursor_headerRow_deleteRowIsNil() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: table)
        let aLocation = (storage.string as NSString).range(of: "A").location

        let placement = try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: aLocation, layoutManager: layoutManager, container: container
        ))
        XCTAssertNil(placement.deleteRow, "la rangée d'en-tête ne doit jamais proposer de suppression")
        XCTAssertNotNil(placement.deleteColumn, "2 colonnes : la suppression de colonne reste possible")
        XCTAssertNotNil(placement.addRow)
        XCTAssertNotNil(placement.addColumn)
    }

    func test_activeTable_headerSelection_targetsTheLastBodyRowForFooterDeletion() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: table)
        let aLocation = (storage.string as NSString).range(of: "A").location

        let active = try XCTUnwrap(TableControlLayout.activeTable(
            in: storage, at: aLocation, layoutManager: layoutManager, container: container
        ))
        let target = try XCTUnwrap(active.deletionTargetRange)
        let info = try XCTUnwrap(storage.attribute(.mdTableCell, at: target.location, effectiveRange: nil) as? TableCellInfo)

        XCTAssertEqual(info.row, 2)
        XCTAssertTrue(active.canDeleteRow)
    }

    func test_activeTable_bodySelection_targetsThatBodyRowForFooterDeletion() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: table)
        let oneLocation = (storage.string as NSString).range(of: "1").location

        let active = try XCTUnwrap(TableControlLayout.activeTable(
            in: storage, at: oneLocation, layoutManager: layoutManager, container: container
        ))
        let target = try XCTUnwrap(active.deletionTargetRange)
        let info = try XCTUnwrap(storage.attribute(.mdTableCell, at: target.location, effectiveRange: nil) as? TableCellInfo)

        XCTAssertEqual(info.row, 1)
        XCTAssertTrue(active.canDeleteRow)
    }

    func test_placementForCursor_bodyRow_withTwoBodyRows_deleteRowIsPresent() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: table)
        let oneLocation = (storage.string as NSString).range(of: "1").location

        let placement = try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: oneLocation, layoutManager: layoutManager, container: container
        ))
        XCTAssertNotNil(placement.deleteRow, "2 rangées de corps : en supprimer une reste possible")
    }

    func test_placementForCursor_onlyOneBodyRowRemaining_deleteRowIsNil() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: oneBodyRowTable)
        let oneLocation = (storage.string as NSString).range(of: "1").location

        let placement = try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: oneLocation, layoutManager: layoutManager, container: container
        ))
        XCTAssertNil(placement.deleteRow, "un tableau sans corps n'a pas de sens — même garde que TableEditCommands.deleteRow")
    }

    func test_placementForCursor_singleColumnTable_deleteColumnIsNil() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: oneColumnTable)
        let oneLocation = (storage.string as NSString).range(of: "1").location

        let placement = try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: oneLocation, layoutManager: layoutManager, container: container
        ))
        XCTAssertNil(placement.deleteColumn, "un tableau sans colonne n'a pas de sens — même garde que TableEditCommands.deleteColumn")
    }

    func test_placementForCursor_addRowAndAddColumn_alwaysPresentRegardlessOfGuards() throws {
        let (storage, layoutManager, container) = makeLayout(markdown: oneColumnTable)
        let oneLocation = (storage.string as NSString).range(of: "1").location

        let placement = try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: oneLocation, layoutManager: layoutManager, container: container
        ))
        // `addRow`/`addColumn` n'ont pas de borne supérieure — toujours
        // proposés, même dans un tableau à une seule colonne.
        XCTAssertEqual(placement.addRow.width, TableControlLayout.controlDiameter)
        XCTAssertEqual(placement.addColumn.width, TableControlLayout.controlDiameter)
    }

    // MARK: - `EditorTextView.tableControlGesture(at:)` — câblage vue réelle

    func test_tableControlGesture_clickAtAddRowControlCenter_returnsAddRowBelow() throws {
        let editor = makeWiredEditor(markdown: table)
        let oneLocation = (editor.textStorage!.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        let placement = try requirePlacement(for: editor)
        let point = viewPoint(for: placement.addRow, in: editor)

        XCTAssertEqual(editor.tableControlGesture(at: point), .addRowBelow)
    }

    func test_tableControlGesture_clickAtAddColumnControlCenter_returnsAddColumnRight() throws {
        let editor = makeWiredEditor(markdown: table)
        let oneLocation = (editor.textStorage!.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        let placement = try requirePlacement(for: editor)
        let point = viewPoint(for: placement.addColumn, in: editor)

        XCTAssertEqual(editor.tableControlGesture(at: point), .addColumnRight)
    }

    func test_tableControlGesture_clickAtDeleteRowControlCenter_returnsDeleteRow() throws {
        let editor = makeWiredEditor(markdown: table)
        let oneLocation = (editor.textStorage!.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0)) // rangée de corps, 2 rangées de corps au total

        let placement = try requirePlacement(for: editor)
        let deleteRow = try XCTUnwrap(placement.deleteRow)
        let point = viewPoint(for: deleteRow, in: editor)

        XCTAssertEqual(editor.tableControlGesture(at: point), .deleteRow)
    }

    func test_tableControlGesture_clickAtDeleteColumnControlCenter_returnsDeleteColumn() throws {
        let editor = makeWiredEditor(markdown: table)
        let oneLocation = (editor.textStorage!.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        let placement = try requirePlacement(for: editor)
        let deleteColumn = try XCTUnwrap(placement.deleteColumn)
        let point = viewPoint(for: deleteColumn, in: editor)

        XCTAssertEqual(editor.tableControlGesture(at: point), .deleteColumn)
    }

    /// Sur la rangée d'en-tête, `deleteRow` est `nil` (voir `placementForCursor`
    /// côté storage) — cliquer où le contrôle *aurait été* dessiné ne renvoie
    /// donc aucun geste.
    func test_tableControlGesture_onHeaderRow_deleteRowControl_returnsNil() throws {
        let editor = makeWiredEditor(markdown: table)
        let aLocation = (editor.textStorage!.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))

        let placement = try requirePlacement(for: editor)
        XCTAssertNil(placement.deleteRow, "prémisse : aucun contrôle de suppression sur l'en-tête")
    }

    /// Cliquer au centre du *texte* d'une cellule (pas sur un contrôle) ne
    /// doit déclencher aucun geste — régression : les contrôles ne doivent
    /// pas intercepter les clics normaux de positionnement du curseur.
    func test_tableControlGesture_clickInsideCellText_returnsNil() throws {
        let editor = makeWiredEditor(markdown: table)
        let storage = try XCTUnwrap(editor.textStorage)
        let oneLocation = (storage.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))

        guard let layoutManager = editor.layoutManager, let container = editor.textContainer else {
            return XCTFail("layout manager/container manquant")
        }
        let cellLineRange = (storage.string as NSString).lineRange(for: NSRange(location: oneLocation, length: 0))
        let cellGlyphRange = layoutManager.glyphRange(forCharacterRange: cellLineRange, actualCharacterRange: nil)
        let cellRect = layoutManager.boundingRect(forGlyphRange: cellGlyphRange, in: container)
        let point = NSPoint(
            x: cellRect.midX + editor.textContainerInset.width,
            y: cellRect.midY + editor.textContainerInset.height
        )

        XCTAssertNil(editor.tableControlGesture(at: point))
    }

    func test_tableControlGesture_cursorOutsideTable_returnsNilForAnyPoint() throws {
        let editor = makeWiredEditor(markdown: "Paragraphe\n\n" + table)
        editor.setSelectedRange(NSRange(location: 0, length: 0)) // dans "Paragraphe"

        XCTAssertNil(editor.tableControlGesture(at: NSPoint(x: 50, y: 50)))
    }

    func test_tableControlGesture_notEditable_returnsNil() throws {
        let editor = makeWiredEditor(markdown: table)
        let oneLocation = (editor.textStorage!.string as NSString).range(of: "1").location
        editor.setSelectedRange(NSRange(location: oneLocation, length: 0))
        editor.isEditable = false

        let placement = try requirePlacement(for: editor, ignoringEditable: true)
        let point = viewPoint(for: placement.addRow, in: editor)

        XCTAssertNil(editor.tableControlGesture(at: point), "lecture seule : aucun contrôle de tableau cliquable")
    }

    // MARK: - Lecture seule

    /// `.markdownReadOnly(true)` : le point d'entrée partagé dessin/
    /// interaction des contrôles de tableau doit refuser un éditeur non
    /// éditable — sinon le pied `+`/`−` et le menu de colonne restent
    /// peints et actifs, et leurs commandes mutent une note en lecture
    /// seule (même garde que `tableControlGesture`).
    @MainActor
    func test_activeTableInView_onAReadOnlyEditor_returnsNil() throws {
        let editor = makeWiredEditor(markdown: table)
        let aLocation = (editor.textStorage!.string as NSString).range(of: "A").location
        editor.setSelectedRange(NSRange(location: aLocation, length: 0))
        XCTAssertNotNil(editor.activeTableInView(), "prémisse : la table est active en mode éditable")

        editor.isEditable = false

        XCTAssertNil(editor.activeTableInView())
    }

    // MARK: - Fixtures

    private func makeLayout(markdown: String) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)

        let parsed = MarkdownParser.parse(markdown)
        storage.setAttributedString(parsed)
        StyleRenderer.applyVisualStyle(to: storage)
        layoutManager.ensureLayout(for: container)
        return (storage, layoutManager, container)
    }

    private func makeWiredEditor(markdown: String) -> EditorTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: container)

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        StyleRenderer.applyVisualStyle(to: textStorage)
        layoutManager.ensureLayout(for: container)
        return editor
    }

    /// Recalcule `Placement` pour la sélection actuelle de `editor`, comme le
    /// ferait `tableControlGesture(at:)` en interne — utilisé pour dériver un
    /// point de clic à partir d'une géométrie réelle plutôt que de
    /// coordonnées devinées.
    private func requirePlacement(for editor: EditorTextView, ignoringEditable: Bool = false) throws -> TableControlLayout.Placement {
        let storage = try XCTUnwrap(editor.textStorage)
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let location = min(editor.selectedRange().location, storage.length - 1)
        return try XCTUnwrap(TableControlLayout.placementForCursor(
            in: storage, at: location, layoutManager: layoutManager, container: container
        ))
    }

    /// Centre de `rect` (coordonnées conteneur) ramené en coordonnées vue —
    /// inverse de la conversion faite par `tableControlGesture(at:)`.
    private func viewPoint(for rect: NSRect, in editor: EditorTextView) -> NSPoint {
        NSPoint(
            x: rect.midX + editor.textContainerInset.width,
            y: rect.midY + editor.textContainerInset.height
        )
    }
}
