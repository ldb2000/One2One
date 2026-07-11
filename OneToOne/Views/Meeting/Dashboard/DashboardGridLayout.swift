import SwiftUI

/// Taille d'une carte dans la grille : `cols` colonnes × `rows` lignes.
struct CardSpan: Equatable {
    var cols: Int
    var rows: Int
}

/// Valeur de layout portée par chaque carte pour indiquer son span à
/// `DashboardGridLayout`.
struct DashboardSpanKey: LayoutValueKey {
    static let defaultValue = CardSpan(cols: 1, rows: 1)
}

/// Grille type « dashboard/masonry » à `columns` colonnes de largeur égale et
/// une hauteur de rangée fixe (`rowHeight`). Chaque sous-vue occupe
/// `span.cols × span.rows` cellules ; le placement est un *first-fit* (ligne par
/// ligne, gauche→droite) qui autorise une carte haute (1×2, 1×3) à cohabiter avec
/// des cartes plus courtes à côté puis dessous — ce que `LazyVGrid` ne fait pas.
struct DashboardGridLayout: Layout {
    var columns: Int
    var spacing: CGFloat
    var rowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        let totalRows = placements(for: subviews).totalRows
        let height = CGFloat(totalRows) * rowHeight + CGFloat(max(0, totalRows - 1)) * spacing
        return CGSize(width: width, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard columns > 0, bounds.width > 0 else { return }
        let colWidth = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        guard colWidth > 0 else { return }
        let placed = placements(for: subviews).cells
        for (i, sub) in subviews.enumerated() {
            let cell = placed[i]
            let x = bounds.minX + CGFloat(cell.col) * (colWidth + spacing)
            let y = bounds.minY + CGFloat(cell.row) * (rowHeight + spacing)
            let w = CGFloat(cell.cols) * colWidth + CGFloat(cell.cols - 1) * spacing
            let h = CGFloat(cell.rows) * rowHeight + CGFloat(cell.rows - 1) * spacing
            sub.place(at: CGPoint(x: x, y: y),
                      anchor: .topLeading,
                      proposal: ProposedViewSize(width: w, height: h))
        }
    }

    // MARK: - Placement

    private struct Cell { var col: Int; var row: Int; var cols: Int; var rows: Int }

    /// First-fit : pour chaque carte, trouve la 1re position (ligne, colonne) où son
    /// span tient sans chevaucher une cellule déjà occupée.
    private func placements(for subviews: Subviews) -> (cells: [Cell], totalRows: Int) {
        var occupied = Set<Int>()          // clé = row * columns + col
        func key(_ r: Int, _ c: Int) -> Int { r * columns + c }
        func free(row: Int, col: Int, cols: Int, rows: Int) -> Bool {
            for r in row..<(row + rows) {
                for c in col..<(col + cols) where occupied.contains(key(r, c)) { return false }
            }
            return true
        }
        var cells: [Cell] = []
        var totalRows = 0
        for sub in subviews {
            let span = sub[DashboardSpanKey.self]
            let cols = min(max(1, span.cols), max(1, columns))
            let rows = max(1, span.rows)
            var row = 0
            while true {
                var placed = false
                let maxCol = columns - cols
                if maxCol >= 0 {
                    for col in 0...maxCol where free(row: row, col: col, cols: cols, rows: rows) {
                        for r in row..<(row + rows) {
                            for c in col..<(col + cols) { occupied.insert(key(r, c)) }
                        }
                        cells.append(Cell(col: col, row: row, cols: cols, rows: rows))
                        totalRows = max(totalRows, row + rows)
                        placed = true
                        break
                    }
                }
                if placed { break }
                row += 1
            }
        }
        return (cells, totalRows)
    }
}
