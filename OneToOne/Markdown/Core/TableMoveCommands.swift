import AppKit

/// ⌘⌥⌃↑/⌘⌥⌃↓ — permute la rangée portant le curseur avec sa voisine du
/// dessus/dessous. ⌘⌥⌃←/⌘⌥⌃→ — permute la colonne portant le curseur avec sa
/// voisine de gauche/droite.
///
/// Combinaison retenue après vérification des collisions avec
/// `TableEditCommands`/`EditorTextView.keyDown(with:)` : ⌘⌥+flèche
/// (ajouter une ligne/colonne) et ⌘⌥⇧+flèche (supprimer) sont déjà pris —
/// **⌘⌥⇧↓ et ⌘⌥⇧→ en particulier**, qui auraient été le choix « naturel »
/// pour permuter vers le bas/la droite, appartiennent déjà à
/// `deleteRow`/`deleteColumn`. ⌘⌥⌃ (Commande+Option+Contrôle) + flèche
/// n'est utilisé nulle part ailleurs dans ce module ni dans les menus de
/// l'app (`Views/Menus/MeetingCommands.swift`, aucun raccourci flèche) —
/// voir la doc de `EditorTextView.keyDown(with:)`.
///
/// Modèle : `BlockMoveCommands.swapAdjacentBlocks` — mais bien plus simple.
/// Contrairement à un bloc de texte ordinaire (dont la position de rendu
/// suit sa position dans le storage, d'où le découpage/recollage de texte
/// fait par `swapAdjacentBlocks`), la position de rendu d'une cellule de
/// tableau est entièrement pilotée par `TableCellInfo.row`/`.column`
/// (`NSTextTableBlock(startingRow:startingColumn:)`, voir `StyleRenderer`) —
/// **jamais** par sa position dans le storage. `MarkdownSerializer.
/// tableBlock` regroupe lui aussi les cellules par `(row, column)`, pas par
/// ordre de lecture (voir sa doc : « robuste si une édition future modifie
/// l'ordre des runs sans changer les valeurs de row/column elles-mêmes »).
/// Permuter deux rangées/colonnes se réduit donc à réécrire `row`/`column`
/// sur les cellules concernées : le texte ne bouge jamais dans le storage,
/// et l'opération est sa propre inverse (permuter A↔B une seconde fois
/// annule la première) — pas besoin de reconstruire une position comme le
/// fait `swapAdjacentBlocks` pour son annulation.
enum TableMoveCommands {

    /// Geste déclenché depuis `EditorTextView.onTableMoveCommand`.
    enum Gesture {
        case swapRowUp
        case swapRowDown
        case swapColumnLeft
        case swapColumnRight
    }

    // MARK: - Rangées

    /// ⌘⌥⌃↑. `false` (aucun effet) si le curseur n'est pas dans une cellule,
    /// si sa rangée est l'en-tête (row 0), ou si la rangée du dessus est
    /// l'en-tête (row 1 : son unique voisine du dessus est row 0) — l'en-tête
    /// n'est jamais permutée, ni comme source ni comme destination.
    @discardableResult
    static func swapRowUp(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return false }
        guard info.row > 1 else { return false }

        performSwapRows(info.row, info.row - 1, tableID: info.tableID, anchor: location, in: textView, storage: storage)
        return true
    }

    /// ⌘⌥⌃↓. `false` si le curseur n'est pas dans une cellule, si sa rangée
    /// est l'en-tête, ou si c'est déjà la dernière rangée du tableau.
    @discardableResult
    static func swapRowDown(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return false }
        guard info.row > 0 else { return false }

        let start = tableStart(in: storage, at: location)
        let allCells = cellsOfTable(startingAt: start, tableID: info.tableID, in: storage)
        let maxRow = allCells.map({ $0.info.row }).max() ?? 0
        guard info.row < maxRow else { return false }

        performSwapRows(info.row, info.row + 1, tableID: info.tableID, anchor: location, in: textView, storage: storage)
        return true
    }

    // MARK: - Colonnes

    /// ⌘⌥⌃←. `false` si le curseur n'est pas dans une cellule, ou si c'est
    /// déjà la colonne la plus à gauche (aucune colonne n'a de statut
    /// particulier comme la rangée d'en-tête — pas de garde symétrique ici).
    @discardableResult
    static func swapColumnLeft(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return false }
        guard info.column > 0 else { return false }

        performSwapColumns(info.column, info.column - 1, tableID: info.tableID, anchor: location, in: textView, storage: storage)
        return true
    }

    /// ⌘⌥⌃→. `false` si le curseur n'est pas dans une cellule, ou si c'est
    /// déjà la colonne la plus à droite.
    @discardableResult
    static func swapColumnRight(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return false }
        guard info.column < info.columnCount - 1 else { return false }

        performSwapColumns(info.column, info.column + 1, tableID: info.tableID, anchor: location, in: textView, storage: storage)
        return true
    }

    // MARK: - Primitives (undo = même appel, l'opération est sa propre inverse)

    /// Échange `rowA`/`rowB` sur les cellules qui les portent actuellement
    /// (capturées une fois dans `allCells`, avant toute mutation — comparer
    /// à des valeurs figées, pas relire `storage` en cours de boucle). Rien
    /// d'autre ne change : ni le texte, ni sa position, ni `column`/
    /// `columnCount`/`alignment` d'aucune cellule — `alignment` (propriété de
    /// colonne, dupliquée par cellule, voir `TableCellInfo`) n'a donc pas
    /// besoin d'un traitement séparé, il reste sur sa cellule et « suit »
    /// naturellement la rangée déplacée.
    ///
    /// `shouldChangeText`/`didChangeText()` en bracket n'enregistrerait rien
    /// auprès d'`undoManager` pour cette mutation d'attribut directe sur
    /// `NSTextStorage` — mesuré à deux reprises déjà (`EditorTextView.
    /// applyTaskToggle`, `BlockMoveCommands.swapAdjacentBlocks`) : parade
    /// identique, enregistrement manuel. Réenregistre le **même appel**
    /// (`rowA`, `rowB` inchangés) comme inverse : permuter A↔B une seconde
    /// fois restaure l'état initial, l'opération est sa propre inverse —
    /// contrairement à `swapAdjacentBlocks`, qui doit recalculer une
    /// nouvelle position à chaque annulation/rétablissement (le texte, lui,
    /// bouge). `anchor` (position brute du curseur au moment du geste) reste
    /// valide sans recalcul à travers annulation et rétablissement pour la
    /// même raison : aucune mutation ici ne déplace ni n'allonge le texte.
    private static func performSwapRows(
        _ rowA: Int, _ rowB: Int, tableID: UUID, anchor: Int, in textView: NSTextView, storage: NSTextStorage
    ) {
        let start = tableStart(in: storage, at: anchor)
        let allCells = cellsOfTable(startingAt: start, tableID: tableID, in: storage)

        storage.beginEditing()
        for cell in allCells {
            if cell.info.row == rowA {
                storage.addAttribute(.mdTableCell, value: withRow(cell.info, rowB), range: cell.range)
            } else if cell.info.row == rowB {
                storage.addAttribute(.mdTableCell, value: withRow(cell.info, rowA), range: cell.range)
            }
        }
        storage.endEditing()

        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: start, length: 0))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: min(anchor, storage.length), length: 0))

        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            performSwapRows(rowA, rowB, tableID: tableID, anchor: anchor, in: tv, storage: storage)
        }
    }

    /// Symétrique de `performSwapRows` pour `column` — même remarque sur
    /// `alignment` : chaque cellule garde la sienne, donc l'alignement d'une
    /// colonne « suit » bien la colonne permutée (ses cellules emportent
    /// leur valeur avec elles).
    private static func performSwapColumns(
        _ columnA: Int, _ columnB: Int, tableID: UUID, anchor: Int, in textView: NSTextView, storage: NSTextStorage
    ) {
        let start = tableStart(in: storage, at: anchor)
        let allCells = cellsOfTable(startingAt: start, tableID: tableID, in: storage)

        storage.beginEditing()
        for cell in allCells {
            if cell.info.column == columnA {
                storage.addAttribute(.mdTableCell, value: withColumn(cell.info, columnB), range: cell.range)
            } else if cell.info.column == columnB {
                storage.addAttribute(.mdTableCell, value: withColumn(cell.info, columnA), range: cell.range)
            }
        }
        storage.endEditing()

        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: start, length: 0))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: min(anchor, storage.length), length: 0))

        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            performSwapColumns(columnA, columnB, tableID: tableID, anchor: anchor, in: tv, storage: storage)
        }
    }

    // MARK: - Aides

    private static func withRow(_ info: TableCellInfo, _ row: Int) -> TableCellInfo {
        TableCellInfo(tableID: info.tableID, row: row, column: info.column, columnCount: info.columnCount, alignment: info.alignment)
    }

    private static func withColumn(_ info: TableCellInfo, _ column: Int) -> TableCellInfo {
        TableCellInfo(tableID: info.tableID, row: info.row, column: column, columnCount: info.columnCount, alignment: info.alignment)
    }

    /// Position de la première cellule (row 0, column 0) du tableau
    /// contenant `location` — voir `TableEditCommands.tableStart`, même
    /// fonction, dupliquée ici (`private` là-bas, inaccessible).
    private static func tableStart(in storage: NSTextStorage, at location: Int) -> Int {
        BlockRange.of(in: storage, at: location).range.location
    }

    /// Cellules du tableau `tableID` à partir de `tableStart` — voir
    /// `TableEditCommands.cellsOfTable`, même fonction, dupliquée ici
    /// (`private` là-bas, inaccessible). Chaque `range` est la ligne
    /// physique complète (`\n` terminal inclus), qui porte `.mdTableCell`
    /// pour la dernière cellule du tableau (voir la doc de tête de
    /// `TableEditCommands`).
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
}
