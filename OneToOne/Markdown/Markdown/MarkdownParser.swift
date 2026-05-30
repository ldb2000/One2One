import Foundation
import AppKit
import Markdown

/// Parses CommonMark + GFM markdown into an `NSAttributedString` whose runs
/// carry the custom `md*` attribute keys (`mdBold`, `mdItalic`, `mdBlockType`,
/// `mdListInfo`, …). The string returned contains only display text — no
/// markdown markup characters survive.
enum MarkdownParser {

    static func parse(_ source: String) -> NSAttributedString {
        let document = Document(parsing: source, options: [.parseBlockDirectives])
        let out = NSMutableAttributedString()
        var visitor = Visitor()
        visitor.walk(document.children, into: out)
        if out.length == 0 {
            return NSAttributedString(string: "", attributes: [.mdBlockType: BlockType.paragraph])
        }
        // Strip trailing newline added after the last block
        let str = out.string as NSString
        if str.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    // MARK: - Visitor

    private struct Visitor {
        var listNesting: Int = 0
        var orderedCounters: [Int] = []

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
            default:
                for child in markup.children { emit(child, into: out) }
            }
        }

        // MARK: - Block emitters

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
                let start = out.length
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
                for child in listItem.children { emit(child, into: out) }
                let end = out.length
                if start < end {
                    out.addAttribute(.mdListInfo, value: info,
                                     range: NSRange(location: start, length: end - start))
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
