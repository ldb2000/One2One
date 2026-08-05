import Foundation
import AppKit
import Markdown

/// Parses CommonMark + GFM markdown into an `NSAttributedString` whose runs
/// carry the custom `md*` attribute keys (`mdBold`, `mdItalic`, `mdBlockType`,
/// `mdListInfo`, …). The string returned contains only display text — no
/// markdown markup characters survive.
enum MarkdownParser {

    /// Parse `source` et renvoie le texte attribué affichable. Le `\n` final
    /// ajouté après le dernier bloc est retiré ; une source vide donne une
    /// chaîne vide marquée `.paragraph`.
    ///
    /// Exception à ce retrait : quand ce `\n` final est le **seul** caractère
    /// d'une cellule de tableau vide (`.mdTableCell`, cf. `emitTableRow` —
    /// une cellule vide n'a que son `\n` terminal pour porter l'attribut).
    /// Le retirer supprimerait alors la cellule tout entière (plus aucun
    /// caractère ne porte plus `.mdTableCell` pour elle), perdue au reparse —
    /// défaut mesuré (tâche « commande Tableau du menu `/` ») sur un tableau
    /// dont la dernière cellule (rangée et colonne les plus hautes) est vide
    /// *et* termine le document : `MarkdownRoundTripTests` documentait déjà
    /// ce cas en l'évitant délibérément dans ses fixtures plutôt qu'en le
    /// couvrant. `SlashController.insertTable` en fait un cas courant (toutes
    /// les cellules du squelette inséré sont vides), d'où ce correctif du
    /// défaut plutôt qu'un contournement côté insertion. `longestEffectiveRange`
    /// borne exactement cette cellule (chaque cellule porte une `TableCellInfo`
    /// distincte — `row`/`column` uniques — posée en un seul appel
    /// `addAttribute`, jamais fusionnée avec sa voisine) : une plage de
    /// longueur 1 signifie zéro caractère de contenu avant ce `\n`, donc une
    /// cellule vide. Une cellule non vide (plage > 1) n'est pas concernée :
    /// retirer son dernier `\n` laisse ses caractères de contenu porter
    /// `.mdTableCell` sans changement de comportement — c'est le cas déjà
    /// couvert par les fixtures existantes, non modifié ici.
    static func parse(_ source: String) -> NSAttributedString {
        let document = Document(parsing: source, options: [.parseBlockDirectives])
        let out = NSMutableAttributedString()
        var visitor = Visitor(source: source)
        visitor.walk(document.children, into: out)
        if out.length == 0 {
            return NSAttributedString(string: "", attributes: [.mdBlockType: BlockType.paragraph])
        }
        // Strip trailing newline added after the last block
        let str = out.string as NSString
        if str.hasSuffix("\n") {
            let lastIndex = out.length - 1
            var cellRange = NSRange(location: NSNotFound, length: 0)
            let cellInfo = out.attribute(.mdTableCell, at: lastIndex,
                                         longestEffectiveRange: &cellRange,
                                         in: NSRange(location: 0, length: out.length))
            let wouldEraseEmptyTableCell = cellInfo != nil && cellRange.length == 1
            if !wouldEraseEmptyTableCell {
                out.deleteCharacters(in: NSRange(location: lastIndex, length: 1))
            }
        }
        return out
    }

    // MARK: - Visitor

    private struct Visitor {
        /// Le markdown source complet, conservé pour `emitRawBlock` : c'est
        /// lui qu'on découpe via `markup.range` pour retrouver le texte
        /// littéral d'un `Table`/`HTMLBlock`, plutôt que de le reconstruire.
        let source: String
        var listNesting: Int = 0
        var orderedCounters: [Int] = []

        /// Émet récursivement chaque nœud dans `out`. Méthode `mutating` car le
        /// visiteur porte un état partagé (`listNesting`, `orderedCounters`) mis
        /// à jour au fil du parcours pour suivre l'imbrication et la numérotation.
        mutating func walk(_ children: some Sequence<Markup>, into out: NSMutableAttributedString) {
            for child in children { emit(child, into: out) }
        }

        mutating func emit(_ markup: Markup, into out: NSMutableAttributedString) {
            switch markup {
            case let heading as Heading:
                emitBlock(heading, level: heading.level, into: out)
            case let paragraph as Paragraph:
                emitBlock(paragraph, level: 0, into: out)
            case let blockquote as BlockQuote:
                emitBlockQuote(blockquote, into: out)
            case let list as UnorderedList:
                emitList(list.children, ordered: false, into: out)
            case let list as OrderedList:
                emitList(list.children, ordered: true, into: out)
            case let cb as CodeBlock:
                emitCodeBlock(cb, into: out)
            case is ThematicBreak:
                emitThematicBreak(into: out)
            case let table as Table:
                emitTable(table, into: out)
            case let html as HTMLBlock:
                emitRawBlock(html, into: out)
            default:
                for child in markup.children { emit(child, into: out) }
            }
        }

        // MARK: - Block emitters

        /// Émet le contenu inline d'un bloc puis le marque avec un `BlockType`.
        /// `level` mappe directement les titres (1→h1 … 6→h6) ; toute autre
        /// valeur (notamment 0 pour un paragraphe) donne `.paragraph`.
        mutating func emitBlock(_ block: Markup, level: Int, into out: NSMutableAttributedString) {
            let start = out.length
            emitInline(block.children, into: out)
            let end = out.length
            if start < end {
                let blockType: BlockType
                switch level {
                case 1: blockType = .h1
                case 2: blockType = .h2
                case 3: blockType = .h3
                case 4: blockType = .h4
                case 5: blockType = .h5
                case 6: blockType = .h6
                default: blockType = .paragraph
                }
                out.addAttribute(.mdBlockType, value: blockType,
                                 range: NSRange(location: start, length: end - start))
            }
            appendNewline(out)
        }

        mutating func emitBlockQuote(_ bq: BlockQuote, into out: NSMutableAttributedString) {
            let start = out.length
            for child in bq.children { emit(child, into: out) }
            let end = out.length
            if start < end {
                out.addAttribute(.mdBlockType, value: BlockType.blockquote,
                                 range: NSRange(location: start, length: end - start))
            }
        }

        /// Émet une liste (puces, ordonnée ou tâches). Pour les listes ordonnées,
        /// un compteur est empilé dans `orderedCounters` à l'entrée, lu comme
        /// `index` de chaque item, incrémenté après chaque item, puis dépilé en
        /// sortie — ce qui préserve la numérotation indépendante par niveau.
        mutating func emitList(_ items: some Sequence<Markup>, ordered: Bool,
                               into out: NSMutableAttributedString) {
            listNesting += 1
            if ordered { orderedCounters.append(1) }
            defer {
                listNesting -= 1
                if ordered { _ = orderedCounters.popLast() }
            }
            for item in items {
                guard let listItem = item as? ListItem else { continue }
                let isTask = listItem.checkbox != nil
                let checked = listItem.checkbox.map { $0 == .checked }
                let index = ordered ? orderedCounters.last : nil
                let info: ListInfo
                if isTask {
                    info = ListInfo(kind: .task, level: listNesting - 1, index: nil, checked: checked)
                } else if ordered {
                    info = ListInfo(kind: .ordered, level: listNesting - 1, index: index, checked: nil)
                } else {
                    info = ListInfo(kind: .bullet, level: listNesting - 1, index: nil, checked: nil)
                }
                // `info` ne doit couvrir que le contenu propre de cet item
                // (son/ses paragraphe(s)), pas les sous-listes imbriquées :
                // celles-ci sont des enfants de `listItem` au même titre que
                // le paragraphe, émises par le même appel `emit` ci-dessous,
                // et posent déjà leur propre `.mdListInfo` par leur propre
                // appel récursif à `emitList`. Poser `info` sur [start, end)
                // après avoir tout émis — comme avant ce correctif —
                // écraserait cet attribut déjà correct sur toute la
                // profondeur de la sous-liste (défaut mesuré : niveau
                // toujours 0, état `checked` du parent recopié sur l'enfant).
                // On applique donc `info` par tronçon, borné à chaque
                // séquence d'enfants qui ne sont pas eux-mêmes une liste, et
                // on saute par-dessus les sous-listes sans étendre le
                // tronçon.
                var ownStart: Int? = out.length
                for child in listItem.children {
                    if child is UnorderedList || child is OrderedList {
                        if let ownStart, ownStart < out.length {
                            out.addAttribute(.mdListInfo, value: info,
                                             range: NSRange(location: ownStart, length: out.length - ownStart))
                        }
                        emit(child, into: out)
                        ownStart = out.length
                    } else {
                        emit(child, into: out)
                    }
                }
                if let ownStart, ownStart < out.length {
                    out.addAttribute(.mdListInfo, value: info,
                                     range: NSRange(location: ownStart, length: out.length - ownStart))
                }
                if ordered, let c = orderedCounters.last {
                    orderedCounters[orderedCounters.count - 1] = c + 1
                }
            }
        }

        func emitCodeBlock(_ cb: CodeBlock, into out: NSMutableAttributedString) {
            let body = cb.code.trimmingCharacters(in: .newlines)
            var attrs: [NSAttributedString.Key: Any] = [.mdBlockType: BlockType.codeBlock]
            if let lang = cb.language { attrs[.mdCodeLanguage] = lang }
            out.append(NSAttributedString(string: body, attributes: attrs))
            appendNewline(out)
        }

        func emitThematicBreak(into out: NSMutableAttributedString) {
            let attrs: [NSAttributedString.Key: Any] = [.mdBlockType: BlockType.thematicBreak]
            out.append(NSAttributedString(string: "—", attributes: attrs))
            appendNewline(out)
        }

        /// Émet un tableau GFM comme une grille de paragraphes-cellules,
        /// chacun porteur d'un `.mdTableCell` (`TableCellInfo`) — pas comme
        /// un passthrough littéral (`emitRawBlock`, toujours utilisé pour les
        /// blocs HTML). `StyleRenderer` construit un vrai
        /// `NSTextTable`/`NSTextTableBlock` par cellule à partir de cet
        /// attribut ; `MarkdownSerializer` le relit pour reconstruire les
        /// lignes `| … |`. `table.head` est la rangée d'en-tête (row 0),
        /// `table.body.rows` les rangées de corps (row 1…) — `swift-markdown`
        /// garantit que chaque rangée a exactement `maxColumnCount` cellules
        /// (complétées de cellules vides si besoin), donc `columnCount` est
        /// fiable sans revalider chaque rangée.
        ///
        /// `columnAlignments` peut être plus court que `maxColumnCount`
        /// (colonnes en excès sans alignement déclaré) : `alignment(for:)`
        /// se replie sur `nil` (pas de `:` au round-trip) au-delà de sa
        /// longueur, plutôt que planter sur un accès hors bornes.
        mutating func emitTable(_ table: Table, into out: NSMutableAttributedString) {
            let columnCount = table.maxColumnCount
            guard columnCount > 0 else { return }
            let tableID = UUID()
            let columnAlignments = table.columnAlignments
            func alignment(for column: Int) -> TableCellInfo.Alignment? {
                guard column < columnAlignments.count else { return nil }
                switch columnAlignments[column] {
                case .left: return .left
                case .center: return .center
                case .right: return .right
                case .none: return nil
                }
            }

            emitTableRow(table.head.cells, tableID: tableID, row: 0,
                        columnCount: columnCount, alignment: alignment, into: out)
            for (index, row) in table.body.rows.enumerated() {
                emitTableRow(row.cells, tableID: tableID, row: index + 1,
                            columnCount: columnCount, alignment: alignment, into: out)
            }
        }

        /// Émet une rangée : chaque cellule devient un paragraphe (contenu
        /// inline + `\n`), avec `.mdTableCell` posé sur **toute** la plage y
        /// compris ce `\n` — une cellule vide (`emitInline` ne produit alors
        /// aucun caractère) doit quand même porter l'attribut sur quelque
        /// chose, et le `\n` terminal est le seul caractère disponible.
        /// `MarkdownSerializer.tableBlock` s'appuie sur cette inclusion pour
        /// retrouver une colonne vide (fixture requise).
        func emitTableRow(_ cells: some Sequence<Table.Cell>, tableID: UUID, row: Int,
                          columnCount: Int, alignment: (Int) -> TableCellInfo.Alignment?,
                          into out: NSMutableAttributedString) {
            for (column, cell) in cells.enumerated() {
                guard column < columnCount else { break }
                let start = out.length
                emitInline(cell.children, into: out)
                appendNewline(out)
                let end = out.length
                let info = TableCellInfo(tableID: tableID, row: row, column: column,
                                         columnCount: columnCount, alignment: alignment(column))
                out.addAttribute(.mdTableCell, value: info, range: NSRange(location: start, length: end - start))
            }
        }

        /// Émet un bloc dont ce module ne modélise pas la structure (bloc
        /// HTML) comme un run unique portant son **markdown source
        /// littéral** — même mécanisme de passthrough que `emitCodeBlock`
        /// pour les blocs fencés. Le contenu survit ainsi même si rien ne
        /// sait l'interpréter ; `MarkdownSerializer.rawBlock(in:at:ns:)` le
        /// réémet tel quel, sans transformation.
        ///
        /// Le texte vient de `literalSource(for:)` (tranche exacte de
        /// `source`), pas de `Markup.format()` : mesuré (sonde du
        /// 2026-08-05, tâche 1 du plan parser-pertes-de-données), `format()`
        /// renormalise un tableau — espaces de cellule réalignés, ligne de
        /// séparateur `|---|---|` réduite à `|-|-|` — alors que
        /// `markup.range` retrouve l'octet-source exact, y compris avec des
        /// caractères accentués avant le nœud. `format()` sert de repli
        /// seulement si `range` est `nil` (ne devrait pas arriver en
        /// pratique : on parse toujours depuis une chaîne, jamais un nœud
        /// construit à la main).
        func emitRawBlock(_ markup: Markup, into out: NSMutableAttributedString) {
            let body = literalSource(for: markup) ?? markup.format()
            guard !body.isEmpty else { return }
            out.append(NSAttributedString(string: body, attributes: [.mdBlockType: BlockType.rawBlock]))
            appendNewline(out)
        }

        /// Corrige un bug mesuré de `swift-markdown` (0.8.0) : quand un
        /// `Table` GFM interrompt un `Paragraph` sans ligne vide entre les
        /// deux, `cmark-gfm` doit d'abord tenter de lire les deux premières
        /// lignes du tableau (en-tête + séparateur) comme la continuation du
        /// paragraphe avant de se raviser — et son calcul de plage source
        /// garde la trace de cette hésitation : `Paragraph.range` devient
        /// `nil`, et `Table.range.lowerBound.line` reste bloqué sur la ligne
        /// de départ du paragraphe interrompu au lieu de celle du tableau
        /// (mesuré : `"Avant\n| A | B |\n|---|---|\n| 1 | 2 |"` donne
        /// `1:1..<4:10` au lieu de `2:1..<4:10`). Sans correction,
        /// `literalSource(for:)` découpe alors `source` sur cette plage
        /// trop large et recopie le texte du paragraphe interrompu dans le
        /// bloc brut.
        ///
        /// Mesuré sur neuf variantes (tableau seul, à zéro ligne de corps,
        /// dans une citation, dans un item de liste, précédé d'un titre —
        /// sûr —, de plusieurs blocs, de texte accentué…) : seule la
        /// `.line` de `.lowerBound` est corrompue. Sa `.column` reste
        /// fiable — dérivée de l'indentation réelle de la ligne (le préfixe
        /// `> `/`  ` d'une citation ou d'un item), pas de la ligne erronée —
        /// et `.upperBound` aussi (dérivé des lignes de corps, jamais
        /// concernées par cette confusion). Une rangée de tableau GFM
        /// n'occupe jamais plus d'une ligne source (syntaxe purement
        /// linéaire, sans retour à la ligne interne à une cellule) : le
        /// nombre de lignes qu'occupe un `Table` est donc purement
        /// structurel — 2 (en-tête + séparateur) plus le nombre de rangées
        /// de corps — ce qui permet de recalculer la ligne de départ réelle
        /// à partir de la ligne de fin (fiable) sans dépendre du détail du
        /// bug ni de `Paragraph.range` (`nil` dans le cas corrompu).
        ///
        /// Sans corruption, cette correction est un no-op : la ligne
        /// recalculée égale déjà celle rapportée (vérifié sur les fixtures
        /// de `MarkdownRoundTripTests`, dont les tableaux/blocs HTML déjà
        /// collés à un titre, un séparateur ou un bloc de code sans ligne
        /// vide). Ne s'applique qu'aux `Table` : les blocs HTML n'ont pas ce
        /// défaut (`HTMLBlock.range` mesuré correct dans les mêmes
        /// scénarios, cmark n'ayant besoin d'aucun aller-retour pour les
        /// reconnaître) et n'ont pas de structure « rangée = une ligne »
        /// pour la recalculer de toute façon.
        func correctedRange(for markup: Markup) -> SourceRange? {
            guard let range = markup.range else { return nil }
            guard let table = markup as? Table else { return range }
            let rowCount = 2 + table.body.childCount
            let correctedLine = range.upperBound.line - rowCount + 1
            guard correctedLine >= 1, correctedLine <= range.upperBound.line,
                  correctedLine != range.lowerBound.line else { return range }
            let correctedLowerBound = SourceLocation(line: correctedLine,
                                                     column: range.lowerBound.column,
                                                     source: range.lowerBound.source)
            return correctedLowerBound..<range.upperBound
        }

        /// Extrait la sous-chaîne de `source` couverte par la plage —
        /// corrigée via `correctedRange(for:)` — du nœud. `SourceLocation.
        /// column` compte des **octets UTF-8** depuis le début de sa ligne
        /// (pas des `Character`) — d'où l'indexation via `source.utf8`
        /// plutôt que directement sur `source`, pour rester correct sur du
        /// texte accentué.
        func literalSource(for markup: Markup) -> String? {
            guard let range = correctedRange(for: markup) else { return nil }
            var lineStarts: [String.Index] = [source.startIndex]
            var idx = source.startIndex
            while idx < source.endIndex {
                if source[idx] == "\n" {
                    let next = source.index(after: idx)
                    lineStarts.append(next)
                    idx = next
                } else {
                    idx = source.index(after: idx)
                }
            }
            func index(line: Int, column: Int) -> String.Index? {
                guard line >= 1, line <= lineStarts.count else { return nil }
                return source.utf8.index(lineStarts[line - 1], offsetBy: column - 1,
                                         limitedBy: source.endIndex)
            }
            guard let start = index(line: range.lowerBound.line, column: range.lowerBound.column),
                  let end = index(line: range.upperBound.line, column: range.upperBound.column),
                  start <= end else { return nil }
            return String(source[start..<end])
        }

        // MARK: - Inline

        func emitInline(_ children: some Sequence<Markup>, into out: NSMutableAttributedString) {
            for child in children { emitInlineNode(child, into: out) }
        }

        func emitInlineNode(_ node: Markup, into out: NSMutableAttributedString) {
            switch node {
            case let text as Text:
                out.append(NSAttributedString(string: text.string))
            case let strong as Strong:
                let start = out.length
                emitInline(strong.children, into: out)
                let end = out.length
                if start < end {
                    out.addAttribute(.mdBold, value: true,
                                     range: NSRange(location: start, length: end - start))
                }
            case let em as Emphasis:
                let start = out.length
                emitInline(em.children, into: out)
                let end = out.length
                if start < end {
                    out.addAttribute(.mdItalic, value: true,
                                     range: NSRange(location: start, length: end - start))
                }
            case let code as InlineCode:
                let start = out.length
                out.append(NSAttributedString(string: code.code))
                let end = out.length
                if start < end {
                    out.addAttribute(.mdInlineCode, value: true,
                                     range: NSRange(location: start, length: end - start))
                }
            case let image as Markdown.Image:
                // Une image devient un unique caractère « object replacement »
                // porteur de sa destination : le texte reste sérialisable même
                // si le fichier est absent ou illisible. Voir `ImagePlaceholder`
                // pour le point de construction partagé avec le collage.
                guard let destination = image.source,
                      let url = URL(string: destination) else {
                    out.append(NSAttributedString(string: image.plainText))
                    return
                }
                out.append(ImagePlaceholder.attributedString(for: url, alt: image.plainText))
            case let link as Markdown.Link:
                let start = out.length
                emitInline(link.children, into: out)
                let end = out.length
                if start < end, let urlString = link.destination, let url = URL(string: urlString) {
                    out.addAttribute(.mdLink, value: url,
                                     range: NSRange(location: start, length: end - start))
                }
            case let strike as Strikethrough:
                let start = out.length
                emitInline(strike.children, into: out)
                let end = out.length
                if start < end {
                    out.addAttribute(.mdStrikethrough, value: true,
                                     range: NSRange(location: start, length: end - start))
                }
            case is SoftBreak, is LineBreak:
                out.append(NSAttributedString(string: " "))
            default:
                for child in node.children { emitInlineNode(child, into: out) }
            }
        }

        func appendNewline(_ out: NSMutableAttributedString) {
            out.append(NSAttributedString(string: "\n"))
        }
    }
}
