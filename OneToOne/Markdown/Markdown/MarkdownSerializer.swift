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
    static func serialize(_ source: NSAttributedString) -> String {
        guard source.length > 0 else { return "" }
        var lines: [String] = []
        let ns = source.string as NSString
        var cursor = 0

        while cursor < source.length {
            if let fence = fencedCodeBlock(in: source, at: cursor, ns: ns) {
                lines.append(fence.markdown)
                cursor = fence.nextCursor
                continue
            }

            var paragraphEnd = cursor
            while paragraphEnd < source.length, ns.character(at: paragraphEnd) != 0x0A {
                paragraphEnd += 1
            }
            if paragraphEnd > cursor {
                let range = NSRange(location: cursor, length: paragraphEnd - cursor)
                lines.append(emitParagraph(source: source, range: range))
            } else {
                lines.append("")
            }
            cursor = paragraphEnd + 1
        }

        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
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
        case .codeBlock:
            // Inatteignable en pratique : `fencedCodeBlock` teste déjà
            // `.mdBlockType` à `range.location` — toujours un début de ligne,
            // la même position que celle-ci — avant que `emitParagraph` ne
            // soit appelé. `inline` n'est qu'un repli défensif si cet
            // invariant venait à être violé.
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
    /// content is emitted verbatim between backticks). Otherwise emphasis
    /// markers are layered from the outside in — bold, then italic, then
    /// strikethrough — so `pre` accumulates left-to-right and `post` is built
    /// in mirror order; a link, if present, wraps the escaped text inside that
    /// emphasis. Non-code text is run through `MarkdownEscaping.escapeInline`.
    private static func emitInline(source: NSAttributedString, range: NSRange) -> String {
        var out = ""
        source.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            let raw = (source.string as NSString).substring(with: run)
            if let url = attrs[.mdImageURL] as? URL {
                let alt = (attrs[.mdImageAlt] as? String) ?? ""
                out.append("![")
                out.append(MarkdownEscaping.escapeInline(alt))
                out.append("](")
                out.append(MarkdownEscaping.escapeURL(url.absoluteString))
                out.append(")")
                return
            }
            if (attrs[.mdInlineCode] as? Bool) == true {
                out.append("`")
                out.append(raw)
                out.append("`")
                return
            }
            var pre = ""
            var post = ""
            if (attrs[.mdBold] as? Bool) == true { pre += "**"; post = "**" + post }
            if (attrs[.mdItalic] as? Bool) == true { pre += "_"; post = "_" + post }
            if (attrs[.mdStrikethrough] as? Bool) == true { pre += "~~"; post = "~~" + post }

            if let url = attrs[.mdLink] as? URL {
                let body = MarkdownEscaping.escapeInline(raw)
                out.append(pre)
                out.append("[")
                out.append(body)
                out.append("](")
                out.append(MarkdownEscaping.escapeURL(url.absoluteString))
                out.append(")")
                out.append(post)
            } else {
                out.append(pre)
                out.append(MarkdownEscaping.escapeInline(raw))
                out.append(post)
            }
        }
        return out
    }
}
