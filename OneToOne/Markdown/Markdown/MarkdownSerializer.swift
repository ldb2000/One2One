import Foundation
import AppKit

/// Walks an `NSAttributedString` and emits CommonMark + GFM task-lists.
/// Round-trip with `MarkdownParser` is the canonical contract: any markdown
/// produced by this serializer parses back to the same model state.
enum MarkdownSerializer {

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
