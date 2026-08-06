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
/// vue vivante, comme `Tests/TableEditCommandsTests.swift`, plus une sonde
/// de rendu bitmap jetée après mesure — voir le rapport de tâche) : une
/// `NSTextTable` sans largeur de colonne explicite (voir `StyleRenderer`,
/// qui n'en pose aucune) occupe la **largeur totale** du conteneur — aucune
/// marge libre à gauche ni à droite du tableau pour y loger des contrôles
/// sans empiéter sur son propre rendu. Et surtout : `boundingRect(
/// forGlyphRange:in:)` renvoie le rectangle du **contenu** d'une cellule —
/// bordure et remplissage (`TableLayout.borderWidth`/`cellPadding`) déjà
/// retirés par TextKit lui-même, pas une marge en plus à soustraire ici.
/// Un premier essai centrait `deleteRow`/`deleteColumn` **sur la bordure
/// extérieure du tableau** (`tableRect.minX`/`.minY`) en misant sur cette
/// marge — inexistante : le rendu réel (sonde bitmap) montrait le contrôle
/// à cheval sur le premier caractère de la cellule. `addRow`/`addColumn`,
/// eux, centrés sur une bordure **entre deux cellules** (chacune apportant
/// son propre remplissage), avaient bien la place et rendaient correctement
/// — d'où le choix retenu : les quatre contrôles vivent tous sur une
/// bordure **interne** (jamais l'extérieure du tableau), groupés deux par
/// deux — ajouter/supprimer une ligne sur la bordure basse de la rangée
/// courante, ajouter/supprimer une colonne sur la bordure droite de la
/// colonne courante — comme deux petits boutons côte à côte plutôt
/// qu'écartés aux quatre coins du tableau.
///
/// Rendu : pastille de fond neutre (couleur de bouton système, bordure fine
/// `separatorColor`) surmontée d'une icône SF Symbols (`+`/`–`) — voir
/// `MarkdownLayoutManager.drawTableControl` — plutôt qu'un disque saturé
/// avec un trait dessiné à la main : un premier essai (disque
/// `controlAccentColor`/`systemRed` plein, croix tracée en `NSBezierPath`)
/// a été jugé peu soigné (retour utilisateur, voir le rapport de tâche) —
/// remplacé par le patron « bouton +/– » natif macOS (Mail, Réglages
/// Système, Trousseaux…) : fond neutre identique pour les quatre contrôles,
/// seule la couleur de l'**icône** distingue ajouter (neutre) de supprimer
/// (rouge, geste destructif), pour éviter l'effet « pastille de couleur ».
enum TableControlLayout {

    /// Diamètre d'un contrôle, en points — égal à `TableLayout.cellPadding`
    /// (6pt de rayon) pour ne jamais empiéter au-delà du remplissage d'une
    /// cellule voisine. Mesuré : un premier essai à 16pt (8pt de rayon, pour
    /// donner plus d'air à l'icône SF Symbols) dépassait ce rayon de
    /// sécurité — une rangée à une seule ligne mesure couramment ~16pt de
    /// haut, donc le centre vertical d'une cellule (`cellRect.midY`) ne se
    /// trouve alors qu'à 8pt de la bordure basse de la rangée (`rowRect.
    /// maxY`, où `addRow` est centré) : un clic en plein milieu du *texte*
    /// de la cellule tombait dans le contrôle. Repris à 12pt (voir
    /// `Tests/TableControlLayoutTests.
    /// test_tableControlGesture_clickInsideCellText_returnsNil`, qui a
    /// attrapé la régression).
    static let controlDiameter: CGFloat = TableLayout.cellPadding * 2

    /// Espace entre les deux pastilles d'un même groupe (ajouter/supprimer)
    /// — voir la doc de tête.
    static let controlGap: CGFloat = 4

    /// Fond des quatre contrôles — couleur de bouton système, identique
    /// qu'il s'agisse d'ajouter ou de supprimer (voir la doc de tête).
    static let controlBackgroundColor = NSColor.controlBackgroundColor

    /// Bordure fine du fond — même couleur sémantique que les filets de
    /// tableau (`TableLayout.borderColor`), pour rester cohérent avec le
    /// reste du rendu.
    static let controlBorderColor = NSColor.separatorColor
    static let controlBorderWidth: CGFloat = 1

    /// Couleur de l'icône `+` (ajouter une ligne/colonne) — `labelColor`
    /// (pas `secondaryLabelColor`, mesuré trop pâle à cette taille sur la
    /// sonde bitmap) : geste non destructif, mais doit rester lisible.
    static let addIconColor = NSColor.labelColor

    /// Couleur de l'icône `–` (supprimer la ligne/la colonne) — rouge
    /// système, geste destructif. Seule l'icône est teintée, jamais le fond
    /// (voir la doc de tête) : évite l'effet « bonbon » d'un disque
    /// entièrement rouge.
    static let deleteIconColor = NSColor.systemRed

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

    /// Calcule `Placement` à partir de deux rectangles déjà mesurés (voir
    /// `placementForCursor`) : `rowRect` (la rangée du curseur, même largeur
    /// que le tableau) et `cellRect` (la seule cellule du curseur — ses
    /// abscisses valent pour toute sa colonne, les colonnes d'`NSTextTable`
    /// partageant leur largeur sur toutes les rangées). `tableRect` n'entre
    /// plus dans le calcul (voir la doc de tête : sa bordure extérieure n'a
    /// pas la place). Deux groupes de deux pastilles, jamais sur la bordure
    /// extérieure du tableau :
    /// - **ligne** : bordure basse de la rangée courante — `addRow` à
    ///   gauche du centre de la cellule, `deleteRow` à droite ;
    /// - **colonne** : bordure droite de la colonne courante — `addColumn`
    ///   au-dessus du centre de la cellule, `deleteColumn` en dessous.
    ///
    /// `addRow`/`addColumn` gardent une position fixe que `deleteRow`/
    /// `deleteColumn` soit affiché ou non (pas de recentrage conditionnel) :
    /// plus simple, et la position ne « saute » pas selon la rangée/colonne
    /// du curseur.
    static func placement(
        tableRect: NSRect, rowRect: NSRect, cellRect: NSRect,
        canDeleteRow: Bool, canDeleteColumn: Bool
    ) -> Placement {
        let radius = controlDiameter / 2
        let clusterOffset = radius + controlGap / 2
        func square(centeredAt point: NSPoint) -> NSRect {
            NSRect(x: point.x - radius, y: point.y - radius, width: controlDiameter, height: controlDiameter)
        }

        let addRow = square(centeredAt: NSPoint(x: cellRect.midX - clusterOffset, y: rowRect.maxY))
        let deleteRow = canDeleteRow
            ? square(centeredAt: NSPoint(x: cellRect.midX + clusterOffset, y: rowRect.maxY))
            : nil

        let addColumn = square(centeredAt: NSPoint(x: cellRect.maxX, y: cellRect.midY + clusterOffset))
        let deleteColumn = canDeleteColumn
            ? square(centeredAt: NSPoint(x: cellRect.maxX, y: cellRect.midY - clusterOffset))
            : nil

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
