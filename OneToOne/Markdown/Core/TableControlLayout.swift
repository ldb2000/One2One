import AppKit

enum TableControlLayout {
    static let controlDiameter: CGFloat = 16
    static let controlGap: CGFloat = 4

    static let footerHeight: CGFloat = 36
    static let footerButtonHeight: CGFloat = 22
    static let footerSegmentWidth: CGFloat = 26
    static let footerInset: CGFloat = 10
    static let footerButtonCornerRadius: CGFloat = 5
    static let addColumnButtonWidth: CGFloat = 92
    static let headerChevronSize: CGFloat = 16

    static let footerBackgroundColor = NSColor(red: 0xf7/255, green: 0xf7/255, blue: 0xf9/255, alpha: 1)
    static let footerBorderColor = NSColor(red: 0xd5/255, green: 0xd5/255, blue: 0xd8/255, alpha: 1)
    static let footerButtonBorderColor = NSColor(red: 0xcf/255, green: 0xcf/255, blue: 0xd4/255, alpha: 1)
    static let footerButtonBackgroundColor = NSColor.white
    static let footerTextColor = NSColor(white: 0, alpha: 0.42)
    static let footerButtonTextColor = NSColor(red: 0x3c/255, green: 0x3c/255, blue: 0x43/255, alpha: 1)
    static let headerChevronColor = NSColor(white: 0, alpha: 0.4)
    static let headerChevronHoverColor = NSColor(red: 0xe3/255, green: 0xe3/255, blue: 0xe8/255, alpha: 1)

    struct Placement: Equatable {
        let addRow: NSRect
        let addColumn: NSRect
        let deleteRow: NSRect?
        let deleteColumn: NSRect?
    }

    struct FooterGeometry: Equatable {
        let footerRect: NSRect
        let addRowRect: NSRect
        let deleteRowRect: NSRect
        let addColumnRect: NSRect
    }

    enum FooterAction: Equatable {
        case addRow
        case deleteRow
        case addColumn
    }

    struct HeaderCell: Equatable {
        let column: Int
        let range: NSRange
        let rect: NSRect
    }

    struct ActiveTable: Equatable {
        let range: NSRange
        let tableRect: NSRect
        let selectedCell: TableCellInfo
        let deletionTargetRange: NSRange?
        let rowCount: Int
        let columnCount: Int
        let headerCells: [HeaderCell]

        var canDeleteRow: Bool { deletionTargetRange != nil && rowCount > 2 }

        var canDeleteColumn: Bool { columnCount > 1 }
    }

    static func footerGeometry(forTableRect tableRect: NSRect) -> FooterGeometry {
        let footerRect = NSRect(x: tableRect.minX, y: tableRect.maxY, width: tableRect.width, height: footerHeight)
        let buttonY = footerRect.midY - footerButtonHeight / 2
        let addRowRect = NSRect(
            x: footerRect.minX + footerInset,
            y: buttonY,
            width: footerSegmentWidth,
            height: footerButtonHeight
        )
        let deleteRowRect = NSRect(
            x: addRowRect.maxX - 1,
            y: buttonY,
            width: footerSegmentWidth,
            height: footerButtonHeight
        )
        let addColumnRect = NSRect(
            x: footerRect.maxX - footerInset - addColumnButtonWidth,
            y: buttonY,
            width: addColumnButtonWidth,
            height: footerButtonHeight
        )
        return FooterGeometry(
            footerRect: footerRect,
            addRowRect: addRowRect,
            deleteRowRect: deleteRowRect,
            addColumnRect: addColumnRect
        )
    }

    static func footerAction(at point: NSPoint, in geometry: FooterGeometry) -> FooterAction? {
        if geometry.addRowRect.contains(point) { return .addRow }
        if geometry.deleteRowRect.contains(point) { return .deleteRow }
        if geometry.addColumnRect.contains(point) { return .addColumn }
        return nil
    }

    static func headerChevronRect(forCellRect cellRect: NSRect) -> NSRect {
        NSRect(
            x: cellRect.maxX - headerChevronSize - 6,
            y: cellRect.midY - headerChevronSize / 2,
            width: headerChevronSize,
            height: headerChevronSize
        )
    }

    static func placement(
        tableRect: NSRect,
        rowRect: NSRect,
        cellRect: NSRect,
        canDeleteRow: Bool,
        canDeleteColumn: Bool
    ) -> Placement {
        let offset = controlDiameter / 2 + controlGap / 2
        func centered(at point: NSPoint) -> NSRect {
            NSRect(
                x: point.x - controlDiameter / 2,
                y: point.y - controlDiameter / 2,
                width: controlDiameter,
                height: controlDiameter
            )
        }

        return Placement(
            addRow: centered(at: NSPoint(x: cellRect.midX - offset, y: rowRect.maxY)),
            addColumn: centered(at: NSPoint(x: cellRect.maxX, y: cellRect.midY + offset)),
            deleteRow: canDeleteRow ? centered(at: NSPoint(x: cellRect.midX + offset, y: rowRect.maxY)) : nil,
            deleteColumn: canDeleteColumn ? centered(at: NSPoint(x: cellRect.maxX, y: cellRect.midY - offset)) : nil
        )
    }

    static func gesture(at point: NSPoint, in placement: Placement) -> TableEditCommands.Gesture? {
        if placement.addRow.contains(point) { return .addRowBelow }
        if placement.addColumn.contains(point) { return .addColumnRight }
        if placement.deleteRow?.contains(point) == true { return .deleteRow }
        if placement.deleteColumn?.contains(point) == true { return .deleteColumn }
        return nil
    }

    static func placementForCursor(
        in storage: NSTextStorage,
        at location: Int,
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> Placement? {
        guard storage.length > 0 else { return nil }
        let safeLocation = min(max(0, location), storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: safeLocation, effectiveRange: nil) as? TableCellInfo
        else { return nil }

        let cells = cellsOfTable(containing: safeLocation, tableID: info.tableID, in: storage)
        guard !cells.isEmpty else { return nil }

        let rowCells = cells.filter { $0.info.row == info.row }
        guard !rowCells.isEmpty else { return nil }

        let cellLineRange = (storage.string as NSString).lineRange(for: NSRange(location: safeLocation, length: 0))
        let cellGlyphRange = layoutManager.glyphRange(forCharacterRange: cellLineRange, actualCharacterRange: nil)
        let cellRect = layoutManager.boundingRect(forGlyphRange: cellGlyphRange, in: container)

        let rowRect = unionGlyphRects(rowCells.map(\.range), layoutManager: layoutManager, container: container)
        let tableLayoutRect = unionGlyphRects(cells.map(\.range), layoutManager: layoutManager, container: container)
        let tableContentRect = boundingGlyphRect(cells.map(\.range), layoutManager: layoutManager, container: container)
        let visualBottom = tableContentRect.maxY + TableLayout.cellVerticalPadding + TableLayout.borderWidth
        let tableRect = NSRect(
            x: tableLayoutRect.minX,
            y: tableLayoutRect.minY,
            width: tableLayoutRect.width,
            height: max(0, visualBottom - tableLayoutRect.minY)
        )

        let bodyRowCount = Set(cells.map(\.info.row)).filter { $0 > 0 }.count
        let canDeleteRow = info.row > 0 && bodyRowCount > 1
        let canDeleteColumn = info.columnCount > 1

        return placement(
            tableRect: tableRect,
            rowRect: rowRect,
            cellRect: cellRect,
            canDeleteRow: canDeleteRow,
            canDeleteColumn: canDeleteColumn
        )
    }

    static func activeTable(
        in storage: NSTextStorage,
        at location: Int,
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> ActiveTable? {
        guard storage.length > 0 else { return nil }
        let safeLocation = min(max(0, location), storage.length - 1)
        guard let selected = storage.attribute(.mdTableCell, at: safeLocation, effectiveRange: nil) as? TableCellInfo
        else { return nil }

        let cells = cellsOfTable(containing: safeLocation, tableID: selected.tableID, in: storage)
        guard !cells.isEmpty else { return nil }
        let tableRange = cells.map(\.range).reduce(NSRange(location: cells[0].range.location, length: 0)) { partial, range in
            NSUnionRange(partial, range)
        }
        let tableLayoutRect = unionGlyphRects(cells.map(\.range), layoutManager: layoutManager, container: container)
        let tableGlyphRange = layoutManager.glyphRange(forCharacterRange: tableRange, actualCharacterRange: nil)
        let tableContentRect = layoutManager.boundingRect(forGlyphRange: tableGlyphRange, in: container)
        let visualBottom = tableContentRect.maxY + TableLayout.cellVerticalPadding + TableLayout.borderWidth
        let tableRect = NSRect(
            x: tableLayoutRect.minX,
            y: tableLayoutRect.minY,
            width: tableLayoutRect.width,
            height: max(0, visualBottom - tableLayoutRect.minY)
        )
        let rowCount = Set(cells.map(\.info.row)).count
        let columnCount = selected.columnCount
        let deletionTargetRow = selected.row > 0
            ? selected.row
            : cells.map(\.info.row).filter { $0 > 0 }.max()
        let deletionTargetRange = deletionTargetRow.flatMap { row in
            cells.first(where: { $0.info.row == row })?.range
        }
        let headerCells = cells
            .filter { $0.info.row == 0 }
            .map { cell in
                HeaderCell(
                    column: cell.info.column,
                    range: cell.range,
                    rect: unionGlyphRects([cell.range], layoutManager: layoutManager, container: container)
                )
            }

        return ActiveTable(
            range: tableRange,
            tableRect: tableRect,
            selectedCell: selected,
            deletionTargetRange: deletionTargetRange,
            rowCount: rowCount,
            columnCount: columnCount,
            headerCells: headerCells
        )
    }

    private static func cellsOfTable(
        containing location: Int,
        tableID: UUID,
        in storage: NSTextStorage
    ) -> [(range: NSRange, info: TableCellInfo)] {
        let tableStart = BlockRange.of(in: storage, at: location).range.location
        let ns = storage.string as NSString
        var result: [(range: NSRange, info: TableCellInfo)] = []
        var cursor = tableStart
        while cursor < storage.length,
              let info = storage.attribute(.mdTableCell, at: cursor, effectiveRange: nil) as? TableCellInfo,
              info.tableID == tableID {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            result.append((lineRange, info))
            cursor = lineRange.location + lineRange.length
        }
        return result
    }

    private static func unionGlyphRects(
        _ ranges: [NSRange],
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> NSRect {
        ranges.reduce(NSRect.null) { partial, range in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = NSRect.null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                rect = rect.isNull ? lineRect : rect.union(lineRect)
            }
            return partial.isNull ? rect : partial.union(rect)
        }
    }

    private static func boundingGlyphRect(
        _ ranges: [NSRange],
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> NSRect {
        ranges.reduce(NSRect.null) { partial, range in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            return partial.isNull ? rect : partial.union(rect)
        }
    }
}
