import Foundation
import AppKit

/// Walks an `NSAttributedString` and emits CommonMark + GFM task-lists.
/// Round-trip with `MarkdownParser` is the canonical contract: any markdown
/// produced by this serializer parses back to the same model state.
enum MarkdownSerializer {

    /// Splits the attributed string on newlines and emits one markdown line per
    /// paragraph. A single trailing empty line is dropped so the output has no
    /// spurious blank line at the end (it would otherwise round-trip to an extra
    /// empty paragraph).
    static func serialize(_ source: NSAttributedString) -> String {
        guard source.length > 0 else { return "" }
        var lines: [String] = []
        let ns = source.string as NSString
        var paragraphStart = 0
        while paragraphStart < source.length {
            var paragraphEnd = paragraphStart
            while paragraphEnd < source.length, ns.character(at: paragraphEnd) != 0x0A {
                paragraphEnd += 1
            }
            if paragraphEnd > paragraphStart {
                let range = NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart)
                lines.append(emitParagraph(source: source, range: range))
            } else {
                lines.append("")
            }
            paragraphStart = paragraphEnd + 1
        }
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Paragraph

    /// Emits one paragraph's markdown. A `ListInfo` attribute wins over the
    /// block type and produces a list-item prefix; otherwise the `BlockType`
    /// selects the syntax: `h1`-`h6` → `#`…`######`, `blockquote` → `>`,
    /// `codeBlock` → fenced ``` block, `thematicBreak` → `---`, `paragraph` →
    /// inline text as-is.
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
            let lang = (source.attribute(.mdCodeLanguage, at: range.location, effectiveRange: nil) as? String) ?? ""
            let body = (source.string as NSString).substring(with: range)
            return "```\(lang)\n\(body)\n```"
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
