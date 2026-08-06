import AppKit

/// Plage du **bloc entier** contenant une position du storage : une ligne
/// logique et ses attributs (paragraphe, item de liste, titre, citation), ou
/// — pour les trois cas qui dépassent la simple ligne — le bloc markdown
/// entier : bloc de code (`.mdBlockType == .codeBlock`, run unique pouvant
/// contenir plusieurs `\n`), tableau (suite de paragraphes-cellules
/// `.mdTableCell` partageant un `tableID`), bloc brut (`.mdBlockType ==
/// .rawBlock`, run unique multi-ligne). `MarkdownBlockCommands.lineRange`
/// s'arrête à la ligne ; celle-ci va plus loin pour ces trois cas — sans quoi
/// déplacer une seule ligne d'un tableau le disloquerait.
///
/// Fonction pure et testable, sur le modèle de `SlashPanelPositioning.origin`/
/// `SlashPanelSizing.height` : aucune dépendance à `NSTextView`, seulement au
/// storage attribué (comme `MarkdownBlockCommands.lineRange`, dont elle
/// réutilise le résultat pour le cas simple, sans le muter). Brique de base
/// pour `BlockMoveCommands` (⌥↑/⌥↓) et, plus tard, la sélection multi-blocs
/// et les opérations sur tableaux.
struct BlockRange: Equatable {
    /// Plage du bloc, séparateur `\n` final exclu — même convention que
    /// `MarkdownBlockCommands.lineRange`.
    let range: NSRange

    /// Bloc contenant `location`. `location` hors bornes est ramené à la
    /// première ou dernière position du storage, comme `lineRange` — piloté
    /// par une position de curseur qui peut légitimement déborder.
    static func of(in storage: NSTextStorage, at location: Int) -> BlockRange {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return BlockRange(range: NSRange(location: 0, length: 0)) }
        let safe = min(max(0, location), ns.length)

        if let table = tableRange(in: storage, ns: ns, at: safe) {
            return BlockRange(range: table)
        }
        if let run = attributedRunRange(in: storage, ns: ns, at: safe) {
            return BlockRange(range: run)
        }
        return BlockRange(range: MarkdownBlockCommands.lineRange(in: storage, at: safe))
    }

    // MARK: - Bloc de code / bloc brut

    /// `.mdBlockType == .codeBlock`/`.rawBlock` posé par `MarkdownParser.
    /// emitCodeBlock`/`emitRawBlock` sur un run unique pouvant contenir
    /// plusieurs `\n` — `longestEffectiveRange` retrouve tout le run d'un
    /// coup (valeur d'attribut uniforme sur toute sa longueur), là où
    /// `MarkdownBlockCommands.lineRange` ne donnerait que la ligne portant
    /// `location`. `\n` de fin retirés comme le fait
    /// `MarkdownSerializer.trimmingTrailingNewlines` : un Retour tapé en fin
    /// de bloc hérite les `typingAttributes` du dernier caractère et peut
    /// donc étendre le run jusqu'à inclure son propre `\n` (voir
    /// `MarkdownSerializer.fencedCodeBlock`).
    private static func attributedRunRange(in storage: NSTextStorage, ns: NSString, at location: Int) -> NSRange? {
        guard location < storage.length,
              let blockType = storage.attribute(.mdBlockType, at: location, effectiveRange: nil) as? BlockType,
              blockType == .codeBlock || blockType == .rawBlock
        else { return nil }

        var effective = NSRange(location: NSNotFound, length: 0)
        _ = storage.attribute(.mdBlockType, at: location, longestEffectiveRange: &effective,
                              in: NSRange(location: 0, length: storage.length))
        return trimmingTrailingNewlines(effective, in: ns)
    }

    private static func trimmingTrailingNewlines(_ range: NSRange, in ns: NSString) -> NSRange {
        var length = range.length
        while length > 0, ns.character(at: range.location + length - 1) == 0x0A {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    // MARK: - Tableau

    /// `.mdTableCell` : chaque cellule est son propre paragraphe
    /// (`MarkdownParser.emitTableRow`), regroupées seulement par `tableID`
    /// partagé — pas par une plage d'attribut contiguë comme le cas
    /// précédent, chaque `TableCellInfo` diffère par cellule (`row`/`column`
    /// propres), donc `longestEffectiveRange` ne dépasserait pas une seule
    /// cellule. Balaie en arrière puis en avant, ligne par ligne, tant que la
    /// ligne voisine porte le même `tableID` — même regroupement que
    /// `MarkdownSerializer.tableBlock`, qui ne balaie que vers l'avant depuis
    /// le début déjà connu du tableau ; ici `location` peut tomber n'importe
    /// où dedans, d'où le balayage dans les deux sens.
    private static func tableRange(in storage: NSTextStorage, ns: NSString, at location: Int) -> NSRange? {
        guard location < storage.length,
              let info = storage.attribute(.mdTableCell, at: location, effectiveRange: nil) as? TableCellInfo
        else { return nil }
        let tableID = info.tableID

        var start = lineBounds(in: ns, at: location).start
        while start > 0 {
            let candidate = lineBounds(in: ns, at: start - 1).start
            guard let previous = storage.attribute(.mdTableCell, at: candidate, effectiveRange: nil) as? TableCellInfo,
                  previous.tableID == tableID
            else { break }
            start = candidate
        }

        var bounds = lineBounds(in: ns, at: location)
        var contentsEnd = bounds.contentsEnd
        while bounds.end < storage.length,
              let next = storage.attribute(.mdTableCell, at: bounds.end, effectiveRange: nil) as? TableCellInfo,
              next.tableID == tableID {
            bounds = lineBounds(in: ns, at: bounds.end)
            contentsEnd = bounds.contentsEnd
        }

        return NSRange(location: start, length: contentsEnd - start)
    }

    // MARK: - Frontières de ligne physiques (NSString)

    /// Début, fin de contenu (`\n` terminal exclu) et fin (`\n` terminal
    /// inclus s'il existe) de la ligne physique contenant `location` — même
    /// notion que `MarkdownBlockCommands.lineRange`, mais renvoyant aussi les
    /// deux autres bornes utiles au balayage de `tableRange`.
    private static func lineBounds(in ns: NSString, at location: Int) -> (start: Int, contentsEnd: Int, end: Int) {
        let full = ns.lineRange(for: NSRange(location: location, length: 0))
        var contentsEnd = full.location + full.length
        if contentsEnd > full.location, ns.character(at: contentsEnd - 1) == 0x0A {
            contentsEnd -= 1
        }
        return (full.location, contentsEnd, full.location + full.length)
    }
}
