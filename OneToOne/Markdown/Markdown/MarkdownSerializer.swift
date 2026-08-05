import Foundation
import AppKit

/// Walks an `NSAttributedString` and emits CommonMark + GFM task-lists.
/// Round-trip with `MarkdownParser` is the canonical contract: any markdown
/// produced by this serializer parses back to the same model state.
enum MarkdownSerializer {

    /// Émet une ligne markdown par paragraphe, sauf pour les blocs fencés qui
    /// sont émis d'un seul tenant. Le parser stocke le corps d'un bloc de code
    /// comme un unique run d'attributs contenant des `\n` ; le découper ligne à
    /// ligne produirait une paire de fences par ligne.
    /// Une éventuelle ligne vide finale est supprimée : elle reviendrait sinon
    /// sous forme de paragraphe vide supplémentaire.
    ///
    /// Une ligne vide est insérée entre deux lignes consécutives quand son
    /// absence changerait la relecture CommonMark. Mesuré par un test
    /// temporaire (tâche 1 du plan
    /// `docs/superpowers/plans/2026-08-04-menu-slash.md`, depuis supprimé) sur
    /// les 49 paires ordonnées de 7 types échantillonnés (paragraphe, h1, h2,
    /// citation, séparateur `---`, bloc de code fencé avec langage, item de
    /// liste à puces) : 6 paires à risque au total, cf. `needsBlankLine` — les
    /// 5 initiales plus la 6e ajoutée après revue (item de liste ordonnée
    /// d'ordinal ≠ 1, absente de cet échantillon qui ne testait que
    /// l'ordinal 1). Une revue indépendante a étendu la mesure à 225 paires
    /// (15 types : + h3-h6, bloc de code sans langage, les 4 sortes d'item —
    /// puce, tâche, ordonné à 1, ordonné ≠ 1) et vérifié que la généralisation
    /// « le `kind` de liste n'importe pas, sauf l'ordinal d'un item ordonné »
    /// tient sur cet échantillon élargi, ainsi que l'idempotence de la règle
    /// sur 245 cas. Les paires sûres — dont paragraphe→bloc de code, sur
    /// laquelle une fixture existante s'appuie — doivent rester collées : une
    /// ligne vide uniforme entre tout bloc les casserait sans nécessité.
    static func serialize(_ source: NSAttributedString) -> String {
        guard source.length > 0 else { return "" }
        var lines: [Line] = []
        let ns = source.string as NSString
        var cursor = 0

        while cursor < source.length {
            if let fence = fencedCodeBlock(in: source, at: cursor, ns: ns) {
                lines.append(Line(markdown: fence.markdown, boundary: .other))
                cursor = fence.nextCursor
                continue
            }
            if let raw = rawBlock(in: source, at: cursor, ns: ns) {
                lines.append(Line(markdown: raw.markdown, boundary: .other))
                cursor = raw.nextCursor
                continue
            }
            if let table = tableBlock(in: source, at: cursor, ns: ns) {
                lines.append(Line(markdown: table.markdown, boundary: .table))
                cursor = table.nextCursor
                continue
            }

            var paragraphEnd = cursor
            while paragraphEnd < source.length, ns.character(at: paragraphEnd) != 0x0A {
                paragraphEnd += 1
            }
            if paragraphEnd > cursor {
                let range = NSRange(location: cursor, length: paragraphEnd - cursor)
                lines.append(Line(markdown: emitParagraph(source: source, range: range),
                                   boundary: boundaryKind(source: source, at: range.location)))
            } else {
                lines.append(Line(markdown: "", boundary: .other))
            }
            cursor = paragraphEnd + 1
        }

        if let last = lines.last, last.markdown.isEmpty {
            lines.removeLast()
        }

        var out: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0, needsBlankLine(before: lines[index - 1].boundary, after: line.boundary) {
                out.append("")
            }
            out.append(line.markdown)
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Block boundaries

    /// Une ligne de sortie et le type de frontière qu'elle expose à son début
    /// — juste assez de résolution pour `needsBlankLine`, pas plus : les
    /// titres (h1-h6) et les blocs de code ne participent à aucune des 6
    /// paires à risque, `.other` leur suffit à tous.
    private struct Line {
        let markdown: String
        let boundary: BoundaryKind
    }

    private enum BoundaryKind {
        case plainParagraph
        case blockquote
        case thematicBreak
        /// `startsAtOne` distingue le seul cas où le `kind` d'un item importe
        /// pour `needsBlankLine` : un item ordonné dont l'ordinal n'est pas 1
        /// n'interrompt pas un paragraphe en CommonMark (règle de la spec,
        /// pour qu'un nombre en tête d'une ligne de texte hard-wrappé ne
        /// démarre pas une liste involontaire) — puce et tâche interrompent
        /// toujours, quel que soit leur marqueur, donc `startsAtOne: true`
        /// pour ces deux. Mesuré : `"AONE\n2. BTWO"` fusionne en un seul
        /// paragraphe où même le « 2. » littéral perd son sens de liste,
        /// alors que `"AONE\n1. BTWO"` et `"AONE\n- [ ] BTWO"` restent deux
        /// blocs distincts.
        case listItem(startsAtOne: Bool)
        /// Une grille `NSTextTable` (`.mdTableCell`), voir `tableBlock(in:at:
        /// ns:)`. Distinct de `.other` depuis la mesure sur les notes
        /// réelles (`live/meeting_158.md`) qui a révélé deux paires à risque
        /// symétriques aux six déjà connues — voir `needsBlankLine`.
        case table
        case other
    }

    /// Classe la frontière du bloc qui commence à `location`, à partir des
    /// attributs déjà posés par `MarkdownParser` — aucun état nouveau. Un
    /// `.mdListInfo` présent l'emporte (item de liste, quel que soit son
    /// `kind` : puce, ordonné ou tâche) ; sinon le `.mdBlockType` distingue
    /// les trois cas qui participent à une paire à risque, avec le même repli
    /// vers `.paragraph` que `emitParagraph`/`StyleRenderer` quand l'attribut
    /// est absent — une ligne sans `.mdBlockType` *est* un paragraphe, ce
    /// n'est pas un état neutre à part : `StyleRenderer` ne pose jamais cet
    /// attribut, il ne fait que le lire, donc le texte fraîchement tapé dans
    /// une note n'en porte aucun avant un premier passage par
    /// `MarkdownParser`. Un défaut vers `.other` désactiverait la protection
    /// sur ce chemin — mesuré : une citation convertie puis suivie d'une
    /// ligne tapée sans style (`"Cite\nTape"`, `.mdBlockType` posé seulement
    /// sur "Cite") fusionne les deux en une seule citation faute de ligne
    /// vide, exactement le scénario que ce plan corrige (convertir une ligne
    /// en citation, puis écrire dessous).
    ///
    /// Lire l'attribut à `location` (début de ligne) et non ailleurs importe :
    /// sur la paire item de liste→séparateur, le `\n` qui suit l'item porte
    /// lui aussi `.mdListInfo` (posé par `MarkdownParser.emitList` sur toute
    /// la plage de l'item, retour à la ligne inclus) — le lire au milieu
    /// classerait à tort le bloc suivant comme faisant partie de la liste.
    private static func boundaryKind(source: NSAttributedString, at location: Int) -> BoundaryKind {
        if let info = source.attribute(.mdListInfo, at: location, effectiveRange: nil) as? ListInfo {
            return .listItem(startsAtOne: startsAtOne(for: info))
        }
        let blockType = source.attribute(.mdBlockType, at: location, effectiveRange: nil) as? BlockType ?? .paragraph
        switch blockType {
        case .paragraph: return .plainParagraph
        case .blockquote: return .blockquote
        case .thematicBreak: return .thematicBreak
        default: return .other
        }
    }

    /// Cf. `BoundaryKind.listItem` : seul un item ordonné d'ordinal ≠ 1
    /// échoue à interrompre un paragraphe.
    private static func startsAtOne(for info: ListInfo) -> Bool {
        switch info.kind {
        case .bullet, .task: return true
        case .ordered: return (info.index ?? 1) == 1
        }
    }

    /// Les 6 paires mesurées (avant tableaux) où l'absence de ligne vide
    /// change la relecture CommonMark :
    /// - paragraphe→paragraphe : fusionnent en un seul paragraphe (soft break) ;
    /// - paragraphe→séparateur : le paragraphe devient un titre H2 Setext, le
    ///   séparateur est avalé — le pire cas, un changement de type de bloc ;
    /// - citation→paragraphe et citation→citation : continuation paresseuse de
    ///   blockquote, absorbés/fusionnés ;
    /// - item de liste→paragraphe : même continuation paresseuse, le
    ///   paragraphe est absorbé dans l'item — quel que soit l'ordinal de
    ///   l'item, mesuré sur un item ordonné d'ordinal 2 ;
    /// - paragraphe→item de liste ordonnée d'ordinal ≠ 1 : l'item n'interrompt
    ///   pas le paragraphe, son marqueur redevient du texte littéral et
    ///   `ListInfo` est perdu au reparse — pas une simple fusion de texte
    ///   comme les autres, une perte de structure.
    ///
    /// Deux paires supplémentaires, symétriques à ces six, mesurées sur les
    /// notes réelles (`live/meeting_158.md`, 4 tableaux) une fois les
    /// tableaux devenus des blocs réels plutôt qu'un passthrough opaque —
    /// invisibles avant ce chantier, `.rawBlock` masquait ces deux
    /// absorptions (le texte littéral restait identique en apparence, que
    /// la ligne suivante soit une vraie ligne du tableau ou un paragraphe
    /// avalé par lui) :
    /// - tableau→paragraphe : un paragraphe qui suit un tableau sans ligne
    ///   vide est absorbé comme rangée de données supplémentaire du tableau
    ///   (GFM ne borne un tableau qu'à la première ligne qui n'a pas cette
    ///   forme — un paragraphe uniligne la remplit toujours). Mesuré sur
    ///   4 occurrences dans `meeting_158` : chaque paragraphe suivant
    ///   directement un tableau (ligne vide déjà retirée par une passe
    ///   précédente) devenait une rangée fantôme à la repasse suivante.
    /// - item de liste→tableau : même continuation paresseuse que
    ///   item de liste→paragraphe, le tableau n'est alors jamais reconnu
    ///   comme un `Table` — tout son contenu redevient texte littéral de
    ///   l'item. Mesuré sur `live/meeting_157.md`.
    /// Toute autre paire est sûre sans ligne vide — notamment item de
    /// liste→item de liste, volontairement absent d'ici : deux items restent
    /// distincts même collés, et une ligne vide entre eux romprait leur
    /// appartenance à une même liste visuelle sans que rien ne l'exige ; de
    /// même paragraphe→tableau (un tableau GFM interrompt un paragraphe sans
    /// ambiguïté, cf. `MarkdownParser.correctedRange`) et tableau→tableau
    /// (deux tableaux collés fusionnent délibérément en un seul, cf. la
    /// fixture dédiée dans `MarkdownRoundTripTests`).
    private static func needsBlankLine(before: BoundaryKind, after: BoundaryKind) -> Bool {
        switch (before, after) {
        case (.plainParagraph, .plainParagraph): return true
        case (.plainParagraph, .thematicBreak): return true
        case (.blockquote, .plainParagraph): return true
        case (.blockquote, .blockquote): return true
        case (.listItem(_), .plainParagraph): return true
        case (.plainParagraph, .listItem(startsAtOne: false)): return true
        case (.table, .plainParagraph): return true
        case (.listItem(_), .table): return true
        default: return false
        }
    }

    /// Si un bloc de code commence à `cursor`, renvoie son markdown complet et
    /// la position juste après le bloc — saut de ligne de séparation compris,
    /// celui que `MarkdownParser.appendNewline` ajoute après chaque bloc.
    /// Renvoie `nil` quand `cursor` n'est pas sur un bloc de code.
    private static func fencedCodeBlock(in source: NSAttributedString,
                                        at cursor: Int,
                                        ns: NSString) -> (markdown: String, nextCursor: Int)? {
        var effective = NSRange(location: NSNotFound, length: 0)
        let searchRange = NSRange(location: cursor, length: source.length - cursor)
        let block = source.attribute(.mdBlockType,
                                     at: cursor,
                                     longestEffectiveRange: &effective,
                                     in: searchRange) as? BlockType
        guard block == .codeBlock, effective.length > 0 else { return nil }

        let language = source.attribute(.mdCodeLanguage, at: cursor, effectiveRange: nil) as? String ?? ""
        // Un Retour tapé en fin de bloc hérite les attributs de frappe du run
        // précédent, donc son `\n` peut se retrouver inclus dans `effective`.
        // On ne retire que les `\n` de fin : ceux du début ont déjà été
        // retirés par le parser, et les retirer ici n'aurait pas de sens.
        let body = trimmingTrailingNewlines(ns.substring(with: effective))
        let fence = String(repeating: "`", count: fenceLength(for: body))
        var next = effective.location + effective.length
        if next < source.length, ns.character(at: next) == 0x0A {
            next += 1
        }
        return ("\(fence)\(language)\n\(body)\n\(fence)", next)
    }

    /// Si un bloc « brut » (bloc HTML — `.mdBlockType == .rawBlock`) commence
    /// à `cursor`, renvoie son markdown littéral tel quel et la position
    /// juste après. Même stratégie que `fencedCodeBlock` :
    /// `longestEffectiveRange` regroupe tout le run malgré les `\n` internes
    /// qu'un balayage ligne à ligne couperait. Contrairement à un bloc de
    /// code, aucun fence n'enveloppe le texte : le run porte déjà le
    /// markdown source exact (posé par `MarkdownParser.emitRawBlock`), à
    /// réémettre sans transformation. Les tableaux GFM ne passent plus par
    /// ici depuis que `MarkdownParser.emitTable` les modélise en cellules —
    /// voir `tableBlock(in:at:ns:)`.
    private static func rawBlock(in source: NSAttributedString,
                                 at cursor: Int,
                                 ns: NSString) -> (markdown: String, nextCursor: Int)? {
        var effective = NSRange(location: NSNotFound, length: 0)
        let searchRange = NSRange(location: cursor, length: source.length - cursor)
        let block = source.attribute(.mdBlockType,
                                     at: cursor,
                                     longestEffectiveRange: &effective,
                                     in: searchRange) as? BlockType
        guard block == .rawBlock, effective.length > 0 else { return nil }

        let body = ns.substring(with: effective)
        var next = effective.location + effective.length
        if next < source.length, ns.character(at: next) == 0x0A {
            next += 1
        }
        return (body, next)
    }

    /// Si une cellule de tableau (`.mdTableCell`) commence à `cursor`,
    /// consomme toutes les cellules **contiguës** qui partagent le même
    /// `tableID` (une par ligne, dans l'ordre d'émission de
    /// `MarkdownParser.emitTableRow` : rangée d'en-tête puis rangées de
    /// corps, colonnes dans l'ordre), reconstruit les lignes `| … |` — y
    /// compris la ligne de séparateur d'alignement, absente du storage
    /// (elle n'existe qu'en sortie GFM, jamais comme cellule) — et renvoie
    /// le markdown assemblé plus la position juste après la dernière
    /// cellule. `nil` si `cursor` n'est pas au début d'une cellule.
    ///
    /// Regroupe par `(row, column)` plutôt que de supposer un ordre de
    /// lecture strict : robuste si une édition future modifie l'ordre des
    /// runs sans changer les valeurs de `row`/`column` elles-mêmes.
    private static func tableBlock(in source: NSAttributedString,
                                   at cursor: Int,
                                   ns: NSString) -> (markdown: String, nextCursor: Int)? {
        guard cursor < source.length,
              let firstInfo = source.attribute(.mdTableCell, at: cursor, effectiveRange: nil) as? TableCellInfo
        else { return nil }

        var cellsByRow: [Int: [Int: String]] = [:]
        var alignments: [Int: TableCellInfo.Alignment?] = [:]
        var maxRow = 0
        var columnCount = firstInfo.columnCount
        var cur = cursor

        while cur < source.length,
              let info = source.attribute(.mdTableCell, at: cur, effectiveRange: nil) as? TableCellInfo,
              info.tableID == firstInfo.tableID {
            var lineEnd = cur
            while lineEnd < source.length, ns.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            let cellRange = NSRange(location: cur, length: lineEnd - cur)
            cellsByRow[info.row, default: [:]][info.column] =
                emitInline(source: source, range: cellRange, escapingPipes: true)
            alignments[info.column] = info.alignment
            maxRow = max(maxRow, info.row)
            columnCount = max(columnCount, info.columnCount)
            cur = lineEnd < source.length ? lineEnd + 1 : lineEnd
        }

        func rowLine(_ row: Int) -> String {
            let cells = (0..<columnCount).map { cellsByRow[row]?[$0] ?? "" }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        func alignmentMarker(_ alignment: TableCellInfo.Alignment?) -> String {
            switch alignment {
            case .none: return "---"
            case .left: return ":---"
            case .center: return ":---:"
            case .right: return "---:"
            }
        }

        var lines: [String] = [rowLine(0)]
        lines.append("| " + (0..<columnCount).map { alignmentMarker(alignments[$0] ?? nil) }.joined(separator: " | ") + " |")
        if maxRow >= 1 {
            for row in 1...maxRow {
                lines.append(rowLine(row))
            }
        }

        return (lines.joined(separator: "\n"), cur)
    }

    /// Longueur de fence à utiliser pour envelopper `body` : au moins 3
    /// backticks, et toujours strictement supérieure à la plus longue suite
    /// de backticks présente dans le corps — sinon une fence interne se
    /// refermerait prématurément et le contenu serait perdu au reparse.
    private static func fenceLength(for body: String) -> Int {
        var longestRun = 0
        var currentRun = 0
        for character in body {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return max(3, longestRun + 1)
    }

    /// Retire les `\n` de fin de `body` (uniquement ceux de fin, pas ceux de
    /// début) : un bloc de code dont le run d'attributs englobe son saut de
    /// ligne final donnerait sinon une ligne vide parasite avant la fence
    /// fermante.
    private static func trimmingTrailingNewlines(_ body: String) -> String {
        var result = body
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    // MARK: - Paragraph

    /// Emits one paragraph's markdown. A `ListInfo` attribute wins over the
    /// block type and produces a list-item prefix; otherwise the `BlockType`
    /// selects the syntax: `h1`-`h6` → `#`…`######`, `blockquote` → `>`,
    /// `thematicBreak` → `---`, `paragraph` → inline text as-is. `codeBlock`
    /// is handled upstream by `fencedCodeBlock` and is unreachable here in
    /// practice — see the case below.
    private static func emitParagraph(source: NSAttributedString, range: NSRange) -> String {
        let blockType = source.attribute(.mdBlockType, at: range.location, effectiveRange: nil)
            as? BlockType ?? .paragraph
        let listInfo = source.attribute(.mdListInfo, at: range.location, effectiveRange: nil)
            as? ListInfo

        let inline = emitInline(source: source, range: range)

        if let info = listInfo {
            return prefix(for: info) + inline
        }
        switch blockType {
        case .h1: return "# " + inline
        case .h2: return "## " + inline
        case .h3: return "### " + inline
        case .h4: return "#### " + inline
        case .h5: return "##### " + inline
        case .h6: return "###### " + inline
        case .blockquote: return "> " + inline
        case .codeBlock, .rawBlock:
            // Inatteignable en pratique : `fencedCodeBlock`/`rawBlock`
            // testent déjà `.mdBlockType` à `range.location` — toujours un
            // début de ligne, la même position que celle-ci — avant que
            // `emitParagraph` ne soit appelé. `inline` n'est qu'un repli
            // défensif si cet invariant venait à être violé.
            return inline
        case .thematicBreak:
            return "---"
        case .paragraph:
            return inline
        }
    }

    /// Builds the list-item prefix. Indentation is two spaces per nesting
    /// `level` (clamped to >= 0); the marker depends on the kind: `-` for
    /// bullets, `N. ` for ordered items (defaulting the ordinal to 1), and
    /// `- [x]`/`- [ ]` for task items.
    private static func prefix(for info: ListInfo) -> String {
        let indent = String(repeating: "  ", count: max(0, info.level))
        switch info.kind {
        case .bullet:
            return "\(indent)- "
        case .ordered:
            return "\(indent)\(info.index ?? 1). "
        case .task:
            return "\(indent)- [\(info.checked == true ? "x" : " ")] "
        }
    }

    // MARK: - Inline

    /// Emits the inline markup for a range. Inline code wins exclusively (its
    /// content is emitted verbatim between backticks) — the `U+FFFC`
    /// placeholder characters are stripped from it first, since a code span
    /// (backticks = literal text) has no representation for an image and a
    /// run can carry both `mdInlineCode` and `mdImageURL` at once (the parser
    /// never attaches `mdInlineCode` to an `InlineCode` node's children — see
    /// `MarkdownParser`'s `InlineCode` case — so this only happens through a
    /// layout built by hand or by `NSTextView` typingAttributes, same as
    /// below). Otherwise emphasis markers are layered from the outside in —
    /// bold, then italic, then strikethrough — so `pre` accumulates
    /// left-to-right and `post` is built in mirror order; a link, if present,
    /// wraps the body inside that emphasis. The body itself is either the
    /// run's text run through `MarkdownEscaping.escapeInline`, or — when the
    /// run carries `mdImageURL` — the result of
    /// `expandingImagePlaceholders(in:url:alt:)`, so that an image wrapped in
    /// bold/italic/strikethrough/a link round-trips with its wrapping intact
    /// instead of the image markup replacing it outright.
    ///
    /// `escapingPipes`, quand `true` (cellule de tableau — voir
    /// `tableBlock(in:at:ns:)`), échappe en plus tout `|` littéral du texte
    /// brut en `\|` : un `|` non échappé y serait relu comme une frontière de
    /// colonne GFM, coupant la cellule en deux au reparse. Volontairement
    /// **pas** ajouté à `MarkdownEscaping.inlineSpecials` (partagé par tous
    /// les blocs) : en dehors d'un tableau, `|` n'a aucun sens spécial en
    /// CommonMark, l'échapper y ajouterait un `\` inutile et changerait la
    /// sortie de fixtures existantes sans rien corriger. N'affecte que la
    /// branche texte brut ci-dessous, pas le code inline (échappement inerte
    /// dans un span de code, GFM le protège déjà) ni l'URL d'un lien.
    private static func emitInline(source: NSAttributedString, range: NSRange, escapingPipes: Bool = false) -> String {
        var out = ""
        source.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            let raw = (source.string as NSString).substring(with: run)
            if (attrs[.mdInlineCode] as? Bool) == true {
                out.append("`")
                out.append(raw.filter { $0 != "\u{FFFC}" })
                out.append("`")
                return
            }
            var pre = ""
            var post = ""
            if (attrs[.mdBold] as? Bool) == true { pre += "**"; post = "**" + post }
            if (attrs[.mdItalic] as? Bool) == true { pre += "_"; post = "_" + post }
            if (attrs[.mdStrikethrough] as? Bool) == true { pre += "~~"; post = "~~" + post }

            let body: String
            if let url = attrs[.mdImageURL] as? URL {
                let alt = (attrs[.mdImageAlt] as? String) ?? ""
                body = expandingImagePlaceholders(in: raw, url: url, alt: alt)
            } else {
                let escaped = MarkdownEscaping.escapeInline(raw)
                body = escapingPipes ? escaped.replacingOccurrences(of: "|", with: "\\|") : escaped
            }

            if let url = attrs[.mdLink] as? URL {
                out.append(pre)
                out.append("[")
                out.append(body)
                out.append("](")
                out.append(MarkdownEscaping.escapeURL(url))
                out.append(")")
                out.append(post)
            } else {
                out.append(pre)
                out.append(body)
                out.append(post)
            }
        }
        return out
    }

    /// Émet le texte d'un run portant `mdImageURL`/`mdImageAlt` : chaque
    /// caractère « object replacement » (`U+FFFC`) devient `![alt](url)`,
    /// le reste passe par l'échappement inline normal. Un run peut mélanger
    /// les deux : dans un `NSTextView`, du texte tapé juste après une image
    /// hérite des `typingAttributes` du caractère précédent, donc de
    /// `mdImageURL`, sans être lui-même une image.
    private static func expandingImagePlaceholders(in raw: String, url: URL, alt: String) -> String {
        let imageMarkup = "![\(MarkdownEscaping.escapeInline(alt))](\(MarkdownEscaping.escapeURL(url)))"
        var out = ""
        var textBuffer = ""
        for character in raw {
            if character == "\u{FFFC}" {
                if !textBuffer.isEmpty {
                    out.append(MarkdownEscaping.escapeInline(textBuffer))
                    textBuffer = ""
                }
                out.append(imageMarkup)
            } else {
                textBuffer.append(character)
            }
        }
        if !textBuffer.isEmpty {
            out.append(MarkdownEscaping.escapeInline(textBuffer))
        }
        return out
    }
}
