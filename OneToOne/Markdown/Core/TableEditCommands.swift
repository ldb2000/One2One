import AppKit

/// Opérations de structure sur un tableau markdown rendu en grille (ajouter/
/// supprimer une ligne ou une colonne) — geste clavier substitué aux
/// poignées au survol d'AppFlowy, hors d'atteinte : `EditorTextView` ne gère
/// que `mouseDown`, aucune infrastructure de suivi de souris n'existe (même
/// constat que `BlockMoveCommands`, dont cette énumération reprend le
/// patron : fonctions statiques sur `NSTextView`/`NSTextStorage`,
/// enregistrement manuel de l'inverse auprès d'`undoManager` — voir la doc
/// de `BlockMoveCommands.swapAdjacentBlocks` pour la mesure qui l'impose :
/// `shouldChangeText`/`didChangeText()` seuls n'enregistrent rien pour une
/// mutation faite directement sur `NSTextStorage`).
///
/// Brique de base : `BlockRange.of(in:at:)` délimite le tableau entier
/// (regroupement par `tableID`, balayage avant/arrière) depuis n'importe
/// quelle cellule — `tableStart(in:at:)` ci-dessous n'en retient que le
/// départ, point d'ancrage stable pour les opérations sur les lignes
/// (jamais déplacé : la rangée d'en-tête, row 0, n'est jamais retirée ni
/// précédée d'une insertion par ces opérations) et point de départ du
/// balayage propre à ce fichier (`cellsOfTable`), qui — contrairement à
/// `BlockRange` — conserve le `\n` terminal de la dernière cellule : ce
/// caractère porte `.mdTableCell` pour cette cellule (voir
/// `MarkdownParser.emitTableRow`) et doit donc rester manipulable, alors que
/// `BlockRange` l'exclut délibérément (convention « séparateur de bloc »,
/// hors de propos ici).
enum TableEditCommands {

    /// Geste déclenché depuis `EditorTextView.onTableEditCommand` — un cas
    /// par opération de ce chantier, ajouté au fil des commits (`.addRowBelow`
    /// en premier). Voir la doc de `EditorTextView.onTableEditCommand` pour
    /// le choix du clavier plutôt que du menu `/`.
    enum Gesture {
        case addRowBelow
    }

    // MARK: - Ajouter une ligne

    /// Insère une nouvelle rangée vide (une cellule par colonne) juste en
    /// dessous de la rangée portant le curseur. `false` (aucun effet) si le
    /// curseur n'est pas dans une cellule de tableau.
    @discardableResult
    static func addRowBelow(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return false }

        let start = tableStart(in: storage, at: location)
        performInsertRow(afterRow: info.row, anchor: start, in: textView, storage: storage)
        return true
    }

    // MARK: - Ancrage / lecture du tableau

    /// Position de la première cellule (row 0, column 0) du tableau
    /// contenant `location` — seule la portion « départ » de `BlockRange`
    /// nous intéresse ici, sa fin étant retaillée pour un usage différent
    /// (voir la doc de tête).
    private static func tableStart(in storage: NSTextStorage, at location: Int) -> Int {
        BlockRange.of(in: storage, at: location).range.location
    }

    /// Cellules du tableau `tableID` à partir de `tableStart`, dans l'ordre
    /// du document (rangée d'en-tête puis rangées de corps, colonnes dans
    /// l'ordre — même ordre que `MarkdownParser.emitTableRow`) : chaque
    /// `range` est la ligne physique complète, `\n` terminal inclus —
    /// contrairement à `BlockRange`, dont la convention exclut ce dernier
    /// séparateur (voir la doc de tête). Balayage borné par `tableID` : la
    /// même logique que `BlockRange.tableRange`, jamais dupliquée en sens
    /// inverse ici puisque `tableStart` fournit déjà le départ exact.
    private static func cellsOfTable(
        startingAt tableStart: Int, tableID: UUID, in storage: NSTextStorage
    ) -> [(range: NSRange, info: TableCellInfo)] {
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

    // MARK: - Primitives ligne (partagées ajout / suppression, undo réciproque)

    /// Insère une rangée vide de `columnCount` cellules (alignements repris
    /// de la rangée d'en-tête, jamais retirée par ces opérations) juste
    /// après la rangée `afterRow` (0 = en-tête) du tableau atteint depuis
    /// `anchor`, et renumérote (+1) les rangées déjà présentes au-delà.
    /// Racine de `addRowBelow` (geste direct) et de l'annulation de
    /// `performRemoveRow` — schéma `BlockMoveCommands.swapAdjacentBlocks` :
    /// chaque exécution réenregistre son inverse exact auprès
    /// d'`undoManager`, ce qui fait fonctionner ⌘Z et ⇧⌘Z symétriquement
    /// sans code dédié à chacun.
    ///
    /// La renumérotation (mutation d'attribut seule, aucune longueur de
    /// texte affectée) précède toujours l'insertion elle-même : les
    /// positions capturées dans `cellsOfTable` restent donc valides tout du
    /// long, sans recalcul après coup.
    private static func performInsertRow(afterRow: Int, anchor: Int, in textView: NSTextView, storage: NSTextStorage) {
        let start = tableStart(in: storage, at: anchor)
        guard let tableID = (storage.attribute(.mdTableCell, at: start, effectiveRange: nil) as? TableCellInfo)?.tableID
        else { return }
        let allCells = cellsOfTable(startingAt: start, tableID: tableID, in: storage)
        guard let columnCount = allCells.first?.info.columnCount else { return }

        var alignments = [TableCellInfo.Alignment?](repeating: nil, count: columnCount)
        for cell in allCells where cell.info.row == 0 {
            alignments[cell.info.column] = cell.info.alignment
        }

        let newRow = NSMutableAttributedString()
        for column in 0..<columnCount {
            let cellInfo = TableCellInfo(tableID: tableID, row: afterRow + 1, column: column,
                                         columnCount: columnCount, alignment: alignments[column] ?? nil)
            newRow.append(NSAttributedString(string: "\n", attributes: [.mdTableCell: cellInfo]))
        }

        performInsertRowContent(afterRow: afterRow, content: newRow, anchor: start, in: textView, storage: storage)
    }

    /// Insère `content` (déjà porteur de sa `TableCellInfo` finale par
    /// cellule — vide côté `performInsertRow`, contenu original capturé
    /// côté annulation de `performRemoveRow`) comme rangée `afterRow + 1`.
    private static func performInsertRowContent(
        afterRow: Int, content: NSAttributedString, anchor: Int, in textView: NSTextView, storage: NSTextStorage
    ) {
        let start = tableStart(in: storage, at: anchor)
        guard let tableID = (storage.attribute(.mdTableCell, at: start, effectiveRange: nil) as? TableCellInfo)?.tableID
        else { return }
        let allCells = cellsOfTable(startingAt: start, tableID: tableID, in: storage)
        guard !allCells.isEmpty else { return }

        let insertLocation: Int
        if let firstOfNext = allCells.first(where: { $0.info.row == afterRow + 1 }) {
            insertLocation = firstOfNext.range.location
        } else {
            let last = allCells[allCells.count - 1]
            insertLocation = last.range.location + last.range.length
        }

        storage.beginEditing()
        for cell in allCells where cell.info.row > afterRow {
            let bumped = TableCellInfo(tableID: tableID, row: cell.info.row + 1, column: cell.info.column,
                                       columnCount: cell.info.columnCount, alignment: cell.info.alignment)
            storage.addAttribute(.mdTableCell, value: bumped, range: cell.range)
        }
        storage.replaceCharacters(in: NSRange(location: insertLocation, length: 0), with: content)
        storage.endEditing()

        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: start, length: 0))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: min(insertLocation, storage.length), length: 0))

        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            performRemoveRow(row: afterRow + 1, anchor: start, in: tv, storage: storage)
        }
    }

    /// Retire la rangée `row` du tableau atteint depuis `anchor` et
    /// renumérote (-1) les rangées suivantes ; capture le texte attribué
    /// retiré pour le réinsérer identique au rétablissement (⇧⌘Z) via
    /// `performInsertRowContent`, sans quoi le contenu réel d'une rangée
    /// supprimée (pas seulement une rangée vide fraîchement ajoutée) serait
    /// perdu à l'annulation.
    private static func performRemoveRow(row: Int, anchor: Int, in textView: NSTextView, storage: NSTextStorage) {
        let start = tableStart(in: storage, at: anchor)
        guard let tableID = (storage.attribute(.mdTableCell, at: start, effectiveRange: nil) as? TableCellInfo)?.tableID
        else { return }
        let allCells = cellsOfTable(startingAt: start, tableID: tableID, in: storage)
        let rowCells = allCells.filter { $0.info.row == row }
        guard let firstOfRow = rowCells.first, let lastOfRow = rowCells.last else { return }

        let removeRange = NSRange(location: firstOfRow.range.location,
                                  length: lastOfRow.range.location + lastOfRow.range.length - firstOfRow.range.location)
        let removedContent = storage.attributedSubstring(from: removeRange)

        storage.beginEditing()
        for cell in allCells where cell.info.row > row {
            let bumped = TableCellInfo(tableID: tableID, row: cell.info.row - 1, column: cell.info.column,
                                       columnCount: cell.info.columnCount, alignment: cell.info.alignment)
            storage.addAttribute(.mdTableCell, value: bumped, range: cell.range)
        }
        storage.replaceCharacters(in: removeRange, with: "")
        storage.endEditing()

        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: start, length: 0))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: min(removeRange.location, storage.length), length: 0))

        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            performInsertRowContent(afterRow: row - 1, content: removedContent, anchor: start, in: tv, storage: storage)
        }
    }
}
