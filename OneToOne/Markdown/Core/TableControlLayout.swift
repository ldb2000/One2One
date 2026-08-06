import AppKit

/// Géométrie des contrôles de tableau (ajouter une ligne, ajouter une
/// colonne, supprimer la ligne/la colonne courantes) — peints par
/// `MarkdownLayoutManager.drawTableControls` quand le curseur est dans une
/// cellule, hit-testés par `EditorTextView.tableControlGesture(at:)` sur
/// `mouseDown`. Les deux appellent `placementForCursor` : **un seul** calcul
/// de géométrie, jamais deux qui pourraient diverger — même schéma que
/// `ListMarkerLayout`/`BlockquoteRuleLayout` (constantes + fonctions pures,
/// testables sans vue vivante, cf. leur doc).
///
/// Déclenché sur curseur dans le tableau plutôt que sur survol de la souris
/// (voir la doc de `TableEditCommands` et d'`EditorTextView.
/// onTableEditCommand`) : `EditorTextView` n'a aucune infrastructure de
/// suivi de souris (`NSTrackingArea`, `mouseMoved`), et cette tâche n'en
/// construit pas — la position du curseur (`selectedRange().location`) est
/// la seule source de vérité, pour le dessin comme pour le clic.
///
/// Mesuré hors écran (`NSLayoutManager`/`NSTextContainer` construits sans
/// vue vivante, comme `Tests/TableEditCommandsTests.swift`) : une
/// `NSTextTable` sans largeur de colonne explicite (voir `StyleRenderer`,
/// qui n'en pose aucune) occupe la **largeur totale** du conteneur — aucune
/// marge libre à gauche ni à droite du tableau pour y loger des contrôles
/// sans empiéter sur son propre rendu. Chaque contrôle est donc centré
/// **sur** une bordure du tableau/de la rangée/de la colonne courante (moitié
/// dedans, moitié dehors) plutôt que posé dans une marge qui n'existe pas :
/// avec `controlDiameter` égal à `TableLayout.cellPadding` (6pt de part et
/// d'autre du centre), l'empiétement maximal sur le texte d'une cellule
/// voisine est nul — le rayon s'arrête exactement à la limite du remplissage.
enum TableControlLayout {

    /// Diamètre d'un contrôle, en points — égal à `TableLayout.cellPadding`
    /// (6pt de rayon) pour ne jamais empiéter au-delà du remplissage d'une
    /// cellule voisine (voir la doc de tête).
    static let controlDiameter: CGFloat = TableLayout.cellPadding * 2

    /// Couleur des contrôles d'ajout (ligne/colonne) — accent système, geste
    /// neutre/positif.
    static let addControlColor = NSColor.controlAccentColor

    /// Couleur des contrôles de suppression — rouge système, geste destructif.
    static let deleteControlColor = NSColor.systemRed

    /// Couleur du symbole (+ / ×) peint par-dessus le disque de couleur.
    static let symbolColor = NSColor.white

    /// Position des quatre contrôles, en coordonnées du **conteneur** de
    /// texte — mêmes conventions que `NSLayoutManager.boundingRect(
    /// forGlyphRange:in:)`, sans le décalage `origin`/`textContainerInset`
    /// qu'ajoute chaque appelant (`MarkdownLayoutManager.drawTableControls`
    /// pour dessiner en coordonnées vue, `EditorTextView.
    /// tableControlGesture(at:)` pour ramener un point cliqué en coordonnées
    /// conteneur avant de tester) — jamais l'inverse, un seul décalage
    /// possible par sens de conversion.
    struct Placement: Equatable {
        /// « Ajouter une ligne » (`TableEditCommands.addRowBelow`) — toujours
        /// proposé, aucune borne supérieure sur le nombre de rangées.
        let addRow: NSRect
        /// « Ajouter une colonne » (`TableEditCommands.addColumnRight`) —
        /// toujours proposé.
        let addColumn: NSRect
        /// « Supprimer la ligne » (`TableEditCommands.deleteRow`) — `nil` si
        /// la garde de `deleteRow` refuserait de toute façon (rangée d'en-tête,
        /// ou dernière rangée de corps restante) : pas de contrôle affiché
        /// pour un geste qui n'aurait aucun effet.
        let deleteRow: NSRect?
        /// « Supprimer la colonne » (`TableEditCommands.deleteColumn`) —
        /// `nil` si la garde de `deleteColumn` refuserait (dernière colonne
        /// restante).
        let deleteColumn: NSRect?
    }

    /// Calcule `Placement` à partir de trois rectangles déjà mesurés (voir
    /// `placementForCursor`) : `tableRect` (le tableau entier), `rowRect`
    /// (la rangée du curseur, même largeur que `tableRect`), `cellRect` (la
    /// seule cellule du curseur). Chaque contrôle centré sur une bordure
    /// différente — jamais deux sur la même, aucun risque de chevauchement
    /// entre contrôles :
    /// - ajouter une ligne : bordure basse de la **rangée** courante, à
    ///   l'abscisse de la **cellule** courante ;
    /// - ajouter une colonne : bordure droite de la **colonne** courante (=
    ///   bordure droite de la cellule, les colonnes partageant leur abscisse
    ///   sur toutes les rangées), à l'ordonnée de la cellule ;
    /// - supprimer la ligne : bordure gauche du **tableau**, à l'ordonnée de
    ///   la cellule ;
    /// - supprimer la colonne : bordure haute du **tableau**, à l'abscisse de
    ///   la cellule.
    static func placement(
        tableRect: NSRect, rowRect: NSRect, cellRect: NSRect,
        canDeleteRow: Bool, canDeleteColumn: Bool
    ) -> Placement {
        let radius = controlDiameter / 2
        func square(centeredAt point: NSPoint) -> NSRect {
            NSRect(x: point.x - radius, y: point.y - radius, width: controlDiameter, height: controlDiameter)
        }

        let addRow = square(centeredAt: NSPoint(x: cellRect.midX, y: rowRect.maxY))
        let addColumn = square(centeredAt: NSPoint(x: cellRect.maxX, y: cellRect.midY))
        let deleteRow = canDeleteRow ? square(centeredAt: NSPoint(x: tableRect.minX, y: cellRect.midY)) : nil
        let deleteColumn = canDeleteColumn ? square(centeredAt: NSPoint(x: cellRect.midX, y: tableRect.minY)) : nil

        return Placement(addRow: addRow, addColumn: addColumn, deleteRow: deleteRow, deleteColumn: deleteColumn)
    }

    /// Point d'entrée partagé par le dessin et le hit-test : mesure la
    /// géométrie du tableau/de la rangée/de la cellule portant `location`
    /// (`.mdTableCell`), calcule les gardes de suppression, puis appelle
    /// `placement(...)`. `nil` si `location` n'est pas dans une cellule de
    /// tableau — pas de contrôle à afficher/tester ailleurs dans le document.
    ///
    /// Les gardes (`canDeleteRow`/`canDeleteColumn`) reprennent les
    /// **mêmes conditions** que `TableEditCommands.deleteRow`/`deleteColumn`
    /// (`info.row > 0 && maxRow > 1`, `info.columnCount > 1`) — lues ici pour
    /// décider si le contrôle correspondant a une chance d'avoir un effet,
    /// jamais redoublées comme autorité : `TableEditCommands` reste seul à
    /// réellement refuser une suppression (appelé tel quel par
    /// `EditorRepresentable.Coordinator.performTableEdit`, y compris pour un
    /// clic sur un contrôle — voir `EditorTextView.mouseDown`), donc même un
    /// écart entre les deux resterait sans danger (au pire un contrôle
    /// affiché qui ne ferait rien).
    static func placementForCursor(
        in storage: NSTextStorage, at location: Int,
        layoutManager: NSLayoutManager, container: NSTextContainer
    ) -> Placement? {
        guard location >= 0, location < storage.length,
              let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return nil }

        let ns = storage.string as NSString

        func rect(for range: NSRange) -> NSRect {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        }

        let tableRange = BlockRange.of(in: storage, at: location).range
        let tableRect = rect(for: tableRange)

        let cellLineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        let cellRect = rect(for: cellLineRange)

        // Rangée entière : les cellules d'une même rangée sont contiguës en
        // storage (même `tableID` + `row`, colonnes dans l'ordre — voir
        // `MarkdownParser.emitTableRow`) ; balayage local borné à la rangée,
        // même patron que `TableEditCommands.cellsOfTable` mais sans balayer
        // tout le tableau.
        var rowStart = cellLineRange.location
        while rowStart > 0 {
            let previousLine = ns.lineRange(for: NSRange(location: rowStart - 1, length: 0))
            guard let previous = storage.attribute(.mdTableCell, at: previousLine.location, effectiveRange: nil) as? TableCellInfo,
                  previous.tableID == info.tableID, previous.row == info.row
            else { break }
            rowStart = previousLine.location
        }
        var rowEnd = cellLineRange.location + cellLineRange.length
        while rowEnd < storage.length {
            let nextLine = ns.lineRange(for: NSRange(location: rowEnd, length: 0))
            guard let next = storage.attribute(.mdTableCell, at: nextLine.location, effectiveRange: nil) as? TableCellInfo,
                  next.tableID == info.tableID, next.row == info.row
            else { break }
            rowEnd = nextLine.location + nextLine.length
        }
        let rowRect = rect(for: NSRange(location: rowStart, length: rowEnd - rowStart))

        // Rangée maximale du tableau, pour la garde `deleteRow` (même
        // condition que `TableEditCommands.deleteRow` : `maxRow > 1`, au
        // moins deux rangées de corps quel que soit celle du curseur).
        var maxRow = info.row
        var cursor = tableRange.location
        while cursor < storage.length,
              let cellInfo = storage.attribute(.mdTableCell, at: cursor, effectiveRange: nil) as? TableCellInfo,
              cellInfo.tableID == info.tableID {
            maxRow = max(maxRow, cellInfo.row)
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            cursor = lineRange.location + lineRange.length
        }

        let canDeleteRow = info.row > 0 && maxRow > 1
        let canDeleteColumn = info.columnCount > 1

        return placement(
            tableRect: tableRect, rowRect: rowRect, cellRect: cellRect,
            canDeleteRow: canDeleteRow, canDeleteColumn: canDeleteColumn
        )
    }

    /// Contrôle sous `point` (coordonnées conteneur, voir la doc de
    /// `Placement`), ou `nil` si aucun n'y correspond. Renvoie directement
    /// `TableEditCommands.Gesture` — pas d'enum séparée à faire correspondre
    /// à la main : les quatre contrôles sont exactement les quatre gestes
    /// existants.
    static func gesture(at point: NSPoint, in placement: Placement) -> TableEditCommands.Gesture? {
        if placement.addRow.contains(point) { return .addRowBelow }
        if placement.addColumn.contains(point) { return .addColumnRight }
        if let deleteRow = placement.deleteRow, deleteRow.contains(point) { return .deleteRow }
        if let deleteColumn = placement.deleteColumn, deleteColumn.contains(point) { return .deleteColumn }
        return nil
    }
}
