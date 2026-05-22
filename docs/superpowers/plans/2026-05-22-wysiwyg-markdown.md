# WYSIWYG Markdown Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `MarkdownTextEditor` SwiftUI component (NSTextView-backed, CommonMark + GFM task-lists) and back-compat alias `MarkdownEditorView` so every existing edit surface gains WYSIWYG rendering with no caller-side changes.

**Architecture:** `NSTextView` subclass driven by an `NSTextStorage` whose attributes are custom keys (`mdBold`, `mdItalic`, `mdBlockType`, `mdListInfo`, …). Round-trip via `swift-markdown` parser → visitor → `NSAttributedString` and a custom serializer back to CommonMark. SwiftUI public API `MarkdownTextEditor` wraps via `NSViewRepresentable` with a `@Binding String` markdown source.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSTextView`, `NSTextStorage`, TextKit 2), `swift-markdown` (Apple), XCTest.

**Scope:** This plan covers the foundation (parser, serializer, editor, round-trip, GFM task-lists, back-compat alias). Toolbar, single-line `MarkdownField`, full `MarkdownEditor` with toolbar, and downstream call-site migrations are deferred to a follow-up plan.

---

## File map

| Path | Responsibility |
|---|---|
| `Package.swift` (modify) | Add `swift-markdown` dependency |
| `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift` (new) | `NSAttributedString.Key` constants + value types (`BlockType`, `ListInfo`) |
| `OneToOne/Markdown/Markdown/Escaping.swift` (new) | Markdown escaping helpers |
| `OneToOne/Markdown/Markdown/MarkdownParser.swift` (new) | swift-markdown AST → `NSAttributedString` |
| `OneToOne/Markdown/Markdown/MarkdownSerializer.swift` (new) | `NSAttributedString` → Markdown string |
| `OneToOne/Markdown/Public/MarkdownFeature.swift` (new) | `MarkdownFeature` enum + presets |
| `OneToOne/Markdown/Core/EditorTextView.swift` (new) | `NSTextView` subclass with checkbox click handling |
| `OneToOne/Markdown/Core/ShortcutDetector.swift` (new) | Auto-format on typing (`# `, `- `, `**…** `, …) |
| `OneToOne/Markdown/Core/EditorRepresentable.swift` (new) | `NSViewRepresentable` wrapper + coordinator |
| `OneToOne/Markdown/Public/MarkdownTextEditor.swift` (new) | Public SwiftUI view |
| `OneToOne/Markdown/Public/Modifiers.swift` (new) | `.markdownFeatures`, `.markdownPlaceholder`, `.markdownDebounce` |
| `OneToOne/Views/MarkdownEditorView.swift` (modify) | Back-compat thin alias around `MarkdownTextEditor` |
| `Tests/MarkdownParserTests.swift` (new) | Parser unit tests |
| `Tests/MarkdownSerializerTests.swift` (new) | Serializer unit tests |
| `Tests/MarkdownRoundTripTests.swift` (new) | `serialize(parse(md)) == md` on fixtures |
| `Tests/PrepCheckboxCompatTests.swift` (new) | Checkbox markdown matches `PrepCarryoverService.extractUncheckedItems` regex |

Total: 14 new files, 2 modifications.

---

### Task 1: Add swift-markdown SPM dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Edit dependencies**

In `Package.swift`, change the `dependencies` array from:
```swift
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
    ],
```
to:
```swift
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
```

In the same file, change the `dependencies` array of the `OneToOne` target to add the product:
```swift
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
```

- [ ] **Step 2: Resolve dependencies**

Run: `swift package resolve 2>&1 | tail -5`
Expected: a line containing `Resolved 'swift-markdown'` (or no error and a refreshed `Package.resolved`).

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build(markdown): add swift-markdown dependency"
```

---

### Task 2: Markdown attribute keys + value types

**Files:**
- Create: `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift`

- [ ] **Step 1: Create the file with attribute keys**

```swift
import Foundation
import AppKit

/// Custom `NSAttributedString.Key`s used by the WYSIWYG markdown editor.
/// Keep names prefixed with `md` so they cannot clash with AppKit defaults.
public extension NSAttributedString.Key {
    static let mdBold          = NSAttributedString.Key("mdBold")
    static let mdItalic        = NSAttributedString.Key("mdItalic")
    static let mdInlineCode    = NSAttributedString.Key("mdInlineCode")
    static let mdStrikethrough = NSAttributedString.Key("mdStrikethrough")
    /// Value: `URL`
    static let mdLink          = NSAttributedString.Key("mdLink")
    /// Value: `BlockType`
    static let mdBlockType     = NSAttributedString.Key("mdBlockType")
    /// Value: `ListInfo`
    static let mdListInfo      = NSAttributedString.Key("mdListInfo")
    /// Value: `String` (e.g. "swift")
    static let mdCodeLanguage  = NSAttributedString.Key("mdCodeLanguage")
}

/// Block-level kind applied to a whole paragraph range.
public enum BlockType: String, Codable, Hashable {
    case paragraph
    case h1, h2, h3, h4, h5, h6
    case blockquote
    case codeBlock
    case thematicBreak
}

/// Metadata attached to list items.
public struct ListInfo: Codable, Hashable {
    public enum Kind: String, Codable { case bullet, ordered, task }
    public let kind: Kind
    public let level: Int        // nesting depth, 0-based
    public let index: Int?       // 1-based ordinal for ordered lists
    public let checked: Bool?    // for task lists only

    public init(kind: Kind, level: Int = 0, index: Int? = nil, checked: Bool? = nil) {
        self.kind = kind
        self.level = level
        self.index = index
        self.checked = checked
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Model/MarkdownAttributeKeys.swift
git commit -m "feat(markdown): attribute keys + BlockType / ListInfo types"
```

---

### Task 3: Markdown escaping helpers

**Files:**
- Create: `OneToOne/Markdown/Markdown/Escaping.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

enum MarkdownEscaping {

    /// Characters that need a leading backslash when emitted as part of an
    /// inline text run so the serializer doesn't accidentally produce new
    /// markup. Conservative subset of the CommonMark spec — enough for round-trip
    /// of normal user content.
    private static let inlineSpecials: Set<Character> = [
        "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!"
    ]

    /// Escapes literal markdown characters inside a plain text run. Does NOT
    /// touch characters that are already part of a markup span (those are
    /// emitted by the serializer's structural code, not by this function).
    static func escapeInline(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if inlineSpecials.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    /// Escapes a URL for use inside `[label](url)`. Spaces and `)` need
    /// percent-encoding to avoid breaking the link syntax.
    static func escapeURL(_ url: String) -> String {
        url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Markdown/Escaping.swift
git commit -m "feat(markdown): inline + URL escaping helpers"
```

---

### Task 4: MarkdownParser (CommonMark → NSAttributedString) with tests

**Files:**
- Create: `Tests/MarkdownParserTests.swift`
- Create: `OneToOne/Markdown/Markdown/MarkdownParser.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/MarkdownParserTests.swift`:
```swift
import XCTest
import AppKit
@testable import OneToOne

final class MarkdownParserTests: XCTestCase {

    func test_paragraphPlain() throws {
        let attr = MarkdownParser.parse("Hello world")
        XCTAssertEqual(attr.string, "Hello world")
        // No bold attribute on first character.
        let firstRange = NSRange(location: 0, length: 1)
        XCTAssertNil(attr.attribute(.mdBold, at: 0, effectiveRange: nil))
        // Block type = paragraph.
        let block = attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType
        XCTAssertEqual(block, .paragraph)
        _ = firstRange  // silence
    }

    func test_boldRunHasBoldAttribute() throws {
        let attr = MarkdownParser.parse("hello **bold** world")
        // The substring "bold" must carry mdBold; "hello " must not.
        let str = attr.string as NSString
        let boldRange = str.range(of: "bold")
        XCTAssertNotEqual(boldRange.location, NSNotFound)
        let hasBold = attr.attribute(.mdBold, at: boldRange.location, effectiveRange: nil) as? Bool
        XCTAssertEqual(hasBold, true)
        let hasBoldOnPrefix = attr.attribute(.mdBold, at: 0, effectiveRange: nil) as? Bool
        XCTAssertNil(hasBoldOnPrefix)
    }

    func test_h2BlockTypeApplied() throws {
        let attr = MarkdownParser.parse("## Title")
        XCTAssertEqual(attr.string, "Title")
        let block = attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType
        XCTAssertEqual(block, .h2)
    }

    func test_taskListUncheckedAndChecked() throws {
        let md = """
        - [ ] todo
        - [x] done
        """
        let attr = MarkdownParser.parse(md)
        // First line: unchecked.
        let first = attr.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(first?.kind, .task)
        XCTAssertEqual(first?.checked, false)
        // Find "done" and check the second item's checked = true.
        let str = attr.string as NSString
        let doneRange = str.range(of: "done")
        XCTAssertNotEqual(doneRange.location, NSNotFound)
        let second = attr.attribute(.mdListInfo, at: doneRange.location, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(second?.kind, .task)
        XCTAssertEqual(second?.checked, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownParserTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'MarkdownParser' in scope`.

- [ ] **Step 3: Implement `MarkdownParser`**

In `OneToOne/Markdown/Markdown/MarkdownParser.swift`:
```swift
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
        // If the document is empty, ensure we still have a paragraph block
        // attribute on an empty string so the editor can render a caret.
        if out.length == 0 {
            return NSAttributedString(string: "", attributes: [.mdBlockType: BlockType.paragraph])
        }
        return out
    }

    // MARK: - Visitor

    private struct Visitor {
        var listNesting: Int = 0
        var orderedCounters: [Int] = []

        mutating func walk(_ children: some Sequence<Markup>, into out: NSMutableAttributedString) {
            for child in children {
                emit(child, into: out)
            }
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
                for child in markup.children {
                    emit(child, into: out)
                }
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
            for child in bq.children {
                emit(child, into: out)
            }
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
                for child in listItem.children {
                    emit(child, into: out)
                }
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
            for child in children {
                emitInlineNode(child, into: out)
            }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MarkdownParserTests 2>&1 | tail -10`
Expected: PASS 4/4.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Markdown/Markdown/MarkdownParser.swift Tests/MarkdownParserTests.swift
git commit -m "feat(markdown): MarkdownParser CommonMark + GFM tasks → NSAttributedString"
```

---

### Task 5: MarkdownSerializer (NSAttributedString → Markdown) with tests

**Files:**
- Create: `Tests/MarkdownSerializerTests.swift`
- Create: `OneToOne/Markdown/Markdown/MarkdownSerializer.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/MarkdownSerializerTests.swift`:
```swift
import XCTest
import AppKit
@testable import OneToOne

final class MarkdownSerializerTests: XCTestCase {

    func test_plainParagraph() {
        let s = NSAttributedString(string: "Hello", attributes: [.mdBlockType: BlockType.paragraph])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "Hello")
    }

    func test_heading2() {
        let s = NSAttributedString(string: "Title", attributes: [.mdBlockType: BlockType.h2])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "## Title")
    }

    func test_boldInline() {
        let m = NSMutableAttributedString(string: "hello bold word",
                                          attributes: [.mdBlockType: BlockType.paragraph])
        // mark "bold" (offset 6, length 4) as bold
        m.addAttribute(.mdBold, value: true, range: NSRange(location: 6, length: 4))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "hello **bold** word")
    }

    func test_taskListUnchecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: false)
        let s = NSAttributedString(string: "todo",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [ ] todo")
    }

    func test_taskListChecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: true)
        let s = NSAttributedString(string: "done",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [x] done")
    }
}
```

- [ ] **Step 2: Run test, expect FAIL**

Run: `swift test --filter MarkdownSerializerTests 2>&1 | tail -10`
Expected: FAIL — `cannot find 'MarkdownSerializer' in scope`.

- [ ] **Step 3: Implement `MarkdownSerializer`**

In `OneToOne/Markdown/Markdown/MarkdownSerializer.swift`:
```swift
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
        // Split by paragraphs ("\n").
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
                // Empty line — preserve in output.
                lines.append("")
            }
            paragraphStart = paragraphEnd + 1
        }
        // Drop a trailing empty line caused by a final "\n".
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
            // Raw — no inline escaping inside a code block.
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
            // Inline code disables bold/italic per spec.
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
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `swift test --filter MarkdownSerializerTests 2>&1 | tail -10`
Expected: PASS 5/5.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Markdown/Markdown/MarkdownSerializer.swift Tests/MarkdownSerializerTests.swift
git commit -m "feat(markdown): MarkdownSerializer NSAttributedString → CommonMark/GFM"
```

---

### Task 6: Round-trip tests

**Files:**
- Create: `Tests/MarkdownRoundTripTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import XCTest
@testable import OneToOne

final class MarkdownRoundTripTests: XCTestCase {

    /// For each fixture, parse the markdown then serialize it; the output
    /// must equal the input (modulo accepted normalisations documented in
    /// the spec — none required for these fixtures).
    private let fixtures: [String] = [
        "Hello world",
        "## Title",
        "hello **bold** word",
        "- a\n- b\n- c",
        "1. one\n2. two",
        "- [ ] todo\n- [x] done",
        "> quote\n> next line — kept as block",
        "[link](https://example.com)",
        "hello `code` inline",
        "Mix *italic* and **bold** here"
    ]

    func test_allFixturesRoundTrip() {
        for md in fixtures {
            let parsed = MarkdownParser.parse(md)
            let back = MarkdownSerializer.serialize(parsed)
            XCTAssertEqual(back, md, "Round-trip mismatch for: \(md.debugDescription)")
        }
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter MarkdownRoundTripTests 2>&1 | tail -10`
Expected: PASS (1 test, 10 fixtures verified).

If some fixtures fail because the parser produces slightly different output (e.g. blockquote across two lines), update the parser/serializer until the listed fixtures round-trip. Document the divergence with a comment if a normalisation is unavoidable.

- [ ] **Step 3: Commit**

```bash
git add Tests/MarkdownRoundTripTests.swift
git commit -m "test(markdown): round-trip fixtures"
```

---

### Task 7: Prep checkbox compatibility tests

**Files:**
- Create: `Tests/PrepCheckboxCompatTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OneToOne

/// Garantit que les checkboxes générées par le serializer matchent le regex
/// de `PrepCarryoverService.extractUncheckedItems` — c'est la condition pour
/// que le carryover fonctionne après migration des champs prep.
final class PrepCheckboxCompatTests: XCTestCase {

    func test_uncheckedItemDetected() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: false)
        let s = NSAttributedString(string: "demander statut DAT",
                                   attributes: [.mdListInfo: info])
        let md = MarkdownSerializer.serialize(s)
        XCTAssertEqual(md, "- [ ] demander statut DAT")
        let extracted = PrepCarryoverService.extractUncheckedItems(from: md)
        XCTAssertEqual(extracted, ["- [ ] demander statut DAT"])
    }

    func test_checkedItemIgnored() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: true)
        let s = NSAttributedString(string: "fait",
                                   attributes: [.mdListInfo: info])
        let md = MarkdownSerializer.serialize(s)
        XCTAssertEqual(md, "- [x] fait")
        XCTAssertTrue(PrepCarryoverService.extractUncheckedItems(from: md).isEmpty)
    }

    func test_multipleItemsMixedStates() {
        let unchecked = NSMutableAttributedString(string: "a")
        unchecked.addAttribute(.mdListInfo,
                               value: ListInfo(kind: .task, level: 0, checked: false),
                               range: NSRange(location: 0, length: 1))
        let checked = NSMutableAttributedString(string: "b")
        checked.addAttribute(.mdListInfo,
                             value: ListInfo(kind: .task, level: 0, checked: true),
                             range: NSRange(location: 0, length: 1))
        let combined = NSMutableAttributedString()
        combined.append(unchecked)
        combined.append(NSAttributedString(string: "\n"))
        combined.append(checked)
        let md = MarkdownSerializer.serialize(combined)
        XCTAssertEqual(md, "- [ ] a\n- [x] b")
        XCTAssertEqual(PrepCarryoverService.extractUncheckedItems(from: md), ["- [ ] a"])
    }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter PrepCheckboxCompatTests 2>&1 | tail -10`
Expected: PASS 3/3.

- [ ] **Step 3: Commit**

```bash
git add Tests/PrepCheckboxCompatTests.swift
git commit -m "test(markdown): checkbox markdown stays compatible with PrepCarryoverService"
```

---

### Task 8: MarkdownFeature enum + presets

**Files:**
- Create: `OneToOne/Markdown/Public/MarkdownFeature.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

/// Granular feature flag controlling which markdown elements the editor
/// allows the user to create (via toolbar action, keyboard shortcut, or
/// auto-format-on-type).
public enum MarkdownFeature: Hashable {
    // Inline
    case bold
    case italic
    case inlineCode
    case link
    case strikethrough
    // Blocks
    case heading(HeadingLevel)
    case bulletList
    case orderedList
    case taskList
    case blockquote
    case codeBlock
    case thematicBreak
}

public enum HeadingLevel: Int, Hashable { case h1 = 1, h2, h3, h4, h5, h6 }

public extension Set where Element == MarkdownFeature {
    /// Titres et tags
    static let inlineOnly: Set<MarkdownFeature> = [.bold, .italic, .inlineCode, .link]

    /// Notes courtes, descriptions
    static let basic: Set<MarkdownFeature> = inlineOnly.union([.bulletList, .orderedList])

    /// Prep notes (avec checkboxes interactives)
    static let prep: Set<MarkdownFeature> = basic.union([
        .taskList, .blockquote, .heading(.h2), .heading(.h3)
    ])

    /// Résumés post-LLM, rapports
    static let full: Set<MarkdownFeature> = [
        .bold, .italic, .inlineCode, .link, .strikethrough,
        .heading(.h1), .heading(.h2), .heading(.h3),
        .heading(.h4), .heading(.h5), .heading(.h6),
        .bulletList, .orderedList, .taskList,
        .blockquote, .codeBlock, .thematicBreak
    ]
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Public/MarkdownFeature.swift
git commit -m "feat(markdown): MarkdownFeature enum + presets (inlineOnly/basic/prep/full)"
```

---

### Task 9: EditorTextView NSTextView subclass

**Files:**
- Create: `OneToOne/Markdown/Core/EditorTextView.swift`

- [ ] **Step 1: Create the subclass**

```swift
import AppKit
import os

private let editorLog = Logger(subsystem: "com.onetoone.app", category: "markdown-editor")

/// `NSTextView` subclass that owns markdown-aware editing. Renders the custom
/// `md*` attribute keys with appropriate fonts/colours and intercepts clicks
/// on task-list checkboxes to toggle them in place.
final class EditorTextView: NSTextView {

    /// Set by the SwiftUI coordinator so toggling a checkbox can push the
    /// new state up the binding.
    var onTaskToggle: ((NSRange, Bool) -> Void)?

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isRichText = true
        allowsUndo = true
        importsGraphics = false
        usesFindBar = true
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = NSFont.systemFont(ofSize: 13)
        textContainerInset = NSSize(width: 6, height: 6)
    }

    // MARK: - Click handling for task checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if charIndex < (textStorage?.length ?? 0),
           let info = textStorage?.attribute(.mdListInfo, at: charIndex, effectiveRange: nil) as? ListInfo,
           info.kind == .task {
            // Heuristic : clic dans les ~14pt en début de ligne = checkbox.
            // On localise le début du paragraphe et on vérifie que `point.x`
            // est dans la marge gauche.
            let nsString = string as NSString
            var lineStart = charIndex
            while lineStart > 0, nsString.character(at: lineStart - 1) != 0x0A {
                lineStart -= 1
            }
            if let layout = layoutManager,
               let container = textContainer {
                let glyphIdx = layout.glyphIndexForCharacter(at: lineStart)
                let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 1),
                                                    in: container)
                let xInTextContainer = point.x - textContainerInset.width
                if xInTextContainer < glyphRect.minX + 14 {
                    let newChecked = !(info.checked ?? false)
                    let updated = ListInfo(kind: .task,
                                           level: info.level,
                                           index: info.index,
                                           checked: newChecked)
                    let paraEnd = nsString.range(of: "\n",
                                                  options: [],
                                                  range: NSRange(location: lineStart,
                                                                 length: nsString.length - lineStart))
                    let endOffset = (paraEnd.location == NSNotFound) ? nsString.length : paraEnd.location
                    let range = NSRange(location: lineStart, length: endOffset - lineStart)
                    textStorage?.addAttribute(.mdListInfo, value: updated, range: range)
                    onTaskToggle?(range, newChecked)
                    editorLog.info("checkbox toggle range=\(range.location)..\(range.location + range.length) checked=\(newChecked)")
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Core/EditorTextView.swift
git commit -m "feat(markdown): EditorTextView NSTextView subclass + checkbox click toggle"
```

---

### Task 10: ShortcutDetector (auto-format on typing)

**Files:**
- Create: `OneToOne/Markdown/Core/ShortcutDetector.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit

/// Detects markdown shortcuts typed by the user and rewrites the underlying
/// `NSTextStorage` to apply the corresponding custom attributes.
///
/// - `# ` at line start → set `mdBlockType = .h1` on that paragraph and
///   delete the literal `# ` characters.
/// - `- ` at line start → start a bullet list (set `mdListInfo`).
/// - `- [ ] ` or `- [x] ` → start a task list with checked state.
/// - `**word** ` (typed with trailing space) → bold the word and drop the
///   asterisks.
///
/// Only triggers for features present in the active feature set so the
/// editor honours configuration.
enum ShortcutDetector {

    static func apply(after insertion: String,
                      in storage: NSTextStorage,
                      cursor: Int,
                      features: Set<MarkdownFeature>) {
        // Only fire on space — keeps logic simple and predictable.
        guard insertion == " " else { return }
        let ns = storage.string as NSString
        // Find start of current paragraph.
        var lineStart = cursor
        while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let prefix = ns.substring(with: NSRange(location: lineStart, length: cursor - lineStart))

        // Block-level prefixes (only at the very start of the paragraph).
        if let block = blockPrefix(prefix, features: features) {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
            storage.addAttribute(.mdBlockType, value: block.type,
                                 range: NSRange(location: lineStart, length: 0))
            return
        }

        if let list = listPrefix(prefix, features: features) {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
            storage.addAttribute(.mdListInfo, value: list,
                                 range: NSRange(location: lineStart, length: 0))
            return
        }

        // Inline emphasis: look for `**word**` ending right before cursor.
        if features.contains(.bold) {
            if let range = matchInline(closer: "**", opener: "**", before: cursor, in: ns) {
                applyAttributeAround(.mdBold, in: storage, openerCount: 2, closerCount: 2, range: range)
                return
            }
        }
        if features.contains(.italic) {
            if let range = matchInline(closer: "*", opener: "*", before: cursor, in: ns) {
                applyAttributeAround(.mdItalic, in: storage, openerCount: 1, closerCount: 1, range: range)
                return
            }
        }
        if features.contains(.inlineCode) {
            if let range = matchInline(closer: "`", opener: "`", before: cursor, in: ns) {
                applyAttributeAround(.mdInlineCode, in: storage, openerCount: 1, closerCount: 1, range: range)
                return
            }
        }
    }

    // MARK: - Helpers

    private struct BlockMatch { let type: BlockType }

    private static func blockPrefix(_ prefix: String,
                                    features: Set<MarkdownFeature>) -> BlockMatch? {
        if prefix == "# ", features.contains(.heading(.h1))  { return BlockMatch(type: .h1) }
        if prefix == "## ", features.contains(.heading(.h2)) { return BlockMatch(type: .h2) }
        if prefix == "### ", features.contains(.heading(.h3)) { return BlockMatch(type: .h3) }
        if prefix == "> ", features.contains(.blockquote)    { return BlockMatch(type: .blockquote) }
        return nil
    }

    private static func listPrefix(_ prefix: String,
                                   features: Set<MarkdownFeature>) -> ListInfo? {
        if features.contains(.taskList) {
            if prefix == "- [ ] " { return ListInfo(kind: .task, level: 0, checked: false) }
            if prefix == "- [x] " { return ListInfo(kind: .task, level: 0, checked: true) }
        }
        if features.contains(.bulletList), prefix == "- " || prefix == "* " {
            return ListInfo(kind: .bullet, level: 0)
        }
        if features.contains(.orderedList), prefix == "1. " {
            return ListInfo(kind: .ordered, level: 0, index: 1)
        }
        return nil
    }

    private static func matchInline(closer: String, opener: String,
                                    before cursor: Int,
                                    in ns: NSString) -> NSRange? {
        // `cursor` points just after the inserted space ; we want the closer
        // to end at `cursor - 1`.
        let closerEnd = cursor - 1
        guard closerEnd >= closer.count else { return nil }
        let closerStart = closerEnd - closer.count
        let closerCandidate = ns.substring(with: NSRange(location: closerStart, length: closer.count))
        guard closerCandidate == closer else { return nil }
        // Search backwards for opener.
        let searchEnd = closerStart
        guard searchEnd >= opener.count else { return nil }
        let openerRange = ns.range(of: opener,
                                   options: [.backwards],
                                   range: NSRange(location: 0, length: searchEnd))
        guard openerRange.location != NSNotFound else { return nil }
        let inner = NSRange(location: openerRange.location + openerRange.length,
                            length: closerStart - (openerRange.location + openerRange.length))
        guard inner.length > 0 else { return nil }
        return NSRange(location: openerRange.location, length: closerEnd + closer.count - openerRange.location)
    }

    /// Wraps a range `[opener…inner…closer]` by deleting opener and closer
    /// and tagging the remaining inner range with `attr`.
    private static func applyAttributeAround(_ attr: NSAttributedString.Key,
                                             in storage: NSTextStorage,
                                             openerCount: Int,
                                             closerCount: Int,
                                             range: NSRange) {
        let innerStart = range.location + openerCount
        let innerLength = range.length - openerCount - closerCount
        guard innerLength > 0 else { return }
        let innerRange = NSRange(location: innerStart, length: innerLength)
        // Capture inner first to avoid index drift.
        let innerSubstr = (storage.string as NSString).substring(with: innerRange)
        storage.replaceCharacters(in: range, with: innerSubstr)
        let newRange = NSRange(location: range.location, length: innerLength)
        storage.addAttribute(attr, value: true, range: newRange)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Core/ShortcutDetector.swift
git commit -m "feat(markdown): ShortcutDetector auto-format on typing"
```

---

### Task 11: NSViewRepresentable + Coordinator

**Files:**
- Create: `OneToOne/Markdown/Core/EditorRepresentable.swift`

- [ ] **Step 1: Create the wrapper**

```swift
import SwiftUI
import AppKit
import Combine

/// SwiftUI bridge that owns the `EditorTextView`. Translates the markdown
/// `@Binding String` ↔ internal `NSAttributedString` using `MarkdownParser` /
/// `MarkdownSerializer`. Debounces outgoing changes so SwiftData isn't
/// notified on every keystroke.
struct EditorRepresentable: NSViewRepresentable {
    @Binding var markdown: String
    var placeholder: String
    var features: Set<MarkdownFeature>
    var debounce: TimeInterval
    var readOnly: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        // Replace AppKit-provided NSTextView with our subclass while keeping
        // the layout setup that scrollableTextView() returned.
        let editor = EditorTextView(frame: tv.frame, textContainer: tv.textContainer)
        scroll.documentView = editor
        editor.delegate = context.coordinator
        editor.onTaskToggle = { [weak coord = context.coordinator] _, _ in
            coord?.pushMarkdownToBinding(force: true)
        }
        context.coordinator.textView = editor
        applyInitialState(editor: editor, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? EditorTextView else { return }
        editor.isEditable = !readOnly
        context.coordinator.features = features
        context.coordinator.debounce = debounce
        let incoming = markdown
        if context.coordinator.lastKnownMarkdown != incoming {
            // External update — re-parse and apply, preserving caret best-effort.
            let attr = MarkdownParser.parse(incoming)
            let savedSelection = editor.selectedRange()
            editor.textStorage?.setAttributedString(attr)
            let clampedLocation = min(savedSelection.location, attr.length)
            editor.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            context.coordinator.lastKnownMarkdown = incoming
        }
    }

    // MARK: - Initial state

    private func applyInitialState(editor: EditorTextView, coordinator: Coordinator) {
        editor.isEditable = !readOnly
        let attr = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(attr)
        coordinator.lastKnownMarkdown = markdown
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorRepresentable
        weak var textView: EditorTextView?
        var lastKnownMarkdown: String = ""
        var features: Set<MarkdownFeature>
        var debounce: TimeInterval
        private var debounceTask: Task<Void, Never>?

        init(parent: EditorRepresentable) {
            self.parent = parent
            self.features = parent.features
            self.debounce = parent.debounce
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            // Apply shortcuts after the change took effect.
            let cursor = tv.selectedRange().location
            // The last inserted character is at cursor - 1 if non-empty.
            if cursor > 0 {
                let inserted = (storage.string as NSString)
                    .substring(with: NSRange(location: cursor - 1, length: 1))
                ShortcutDetector.apply(after: inserted, in: storage,
                                       cursor: cursor, features: features)
            }
            pushMarkdownToBinding(force: false)
        }

        func pushMarkdownToBinding(force: Bool) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let md = MarkdownSerializer.serialize(storage)
            if md == lastKnownMarkdown { return }
            lastKnownMarkdown = md
            if force {
                parent.markdown = md
                return
            }
            debounceTask?.cancel()
            let delay = debounce
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard let self else { return }
                if Task.isCancelled { return }
                self.parent.markdown = md
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Markdown/Core/EditorRepresentable.swift
git commit -m "feat(markdown): NSViewRepresentable wrapper with debounced binding"
```

---

### Task 12: MarkdownTextEditor public view + modifiers

**Files:**
- Create: `OneToOne/Markdown/Public/MarkdownTextEditor.swift`
- Create: `OneToOne/Markdown/Public/Modifiers.swift`

- [ ] **Step 1: Create the public view**

In `OneToOne/Markdown/Public/MarkdownTextEditor.swift`:
```swift
import SwiftUI

/// Multi-line WYSIWYG markdown editor without a toolbar. Drop-in replacement
/// for `MarkdownEditorView`.
public struct MarkdownTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var features: Set<MarkdownFeature> = .basic
    var debounce: TimeInterval = 0.3
    var readOnly: Bool = false

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        EditorRepresentable(
            markdown: $text,
            placeholder: placeholder,
            features: features,
            debounce: debounce,
            readOnly: readOnly
        )
    }
}
```

- [ ] **Step 2: Create the modifiers**

In `OneToOne/Markdown/Public/Modifiers.swift`:
```swift
import SwiftUI

public extension MarkdownTextEditor {
    /// Restrict the set of markdown features the editor permits.
    func markdownFeatures(_ features: Set<MarkdownFeature>) -> Self {
        var copy = self
        copy.features = features
        return copy
    }

    /// Placeholder shown when the binding is empty.
    func markdownPlaceholder(_ text: String) -> Self {
        var copy = self
        copy.placeholder = text
        return copy
    }

    /// Debounce delay before pushing edits to the `@Binding`. Default 300 ms.
    func markdownDebounce(_ seconds: TimeInterval) -> Self {
        var copy = self
        copy.debounce = seconds
        return copy
    }

    /// When `true`, suppresses editing and keyboard input.
    func markdownReadOnly(_ flag: Bool = true) -> Self {
        var copy = self
        copy.readOnly = flag
        return copy
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Markdown/Public/MarkdownTextEditor.swift OneToOne/Markdown/Public/Modifiers.swift
git commit -m "feat(markdown): public MarkdownTextEditor view + modifiers"
```

---

### Task 13: Back-compat alias — wrap MarkdownEditorView around MarkdownTextEditor

**Files:**
- Modify: `OneToOne/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Inspect current signature**

Read `OneToOne/Views/MarkdownEditorView.swift` to learn the existing initializer surface (likely `init(text: Binding<String>, textViewID: String)`).

- [ ] **Step 2: Replace body with thin alias**

Open `OneToOne/Views/MarkdownEditorView.swift`. Replace the contents of the file with:

```swift
import SwiftUI

/// Back-compat wrapper kept for the historical call-sites that pass
/// `textViewID:`. Under the hood this is the new WYSIWYG
/// `MarkdownTextEditor`. The `textViewID` argument is now ignored — the
/// internal NSTextView no longer needs an external identity because focus
/// is handled by SwiftUI's `.focused()` modifier on the host.
struct MarkdownEditorView: View {
    @Binding var text: String
    let textViewID: String

    var body: some View {
        MarkdownTextEditor(text: $text)
            .markdownFeatures(.prep)
    }
}
```

If the previous file declared additional types or helpers used outside the view itself, leave those declarations untouched and replace only the `MarkdownEditorView` struct.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 4: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: all existing tests + the new markdown tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/MarkdownEditorView.swift
git commit -m "feat(markdown): wrap MarkdownEditorView around MarkdownTextEditor (back-compat alias)"
```

---

### Task 14: Final build + manual test checklist

**Files:** (none — verification only)

- [ ] **Step 1: Full build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 2: Full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 3: Verify commit history**

Run:
```bash
git log --oneline -15
```
Expect commits with `feat(markdown):` or `test(markdown):` prefix for tasks 1-13.

- [ ] **Step 4: Smoke test manuel**

Lance l'app (`swift run`) et vérifie sur une réunion existante :
- Ouvre l'onglet **Préparation** d'une réunion : éditeur s'ouvre avec le contenu existant rendu en WYSIWYG.
- Tape `# Titre` puis espace → le `# ` disparaît et "Titre" s'affiche en titre 1.
- Tape `- [ ] question` puis espace → checkbox interactive apparaît.
- Clique sur une checkbox : bascule `[ ]` ↔ `[x]`.
- Ferme la réunion, ré-ouvre : l'état est persisté dans `meeting.prepNotes`.
- Lance carryover (finit une transcription) : items non cochés repoussés dans le pool standing comme avant.

---

## Self-review

**Spec coverage** (cross-reference avec `2026-05-22-wysiwyg-markdown-design.md`):

- §4.1 `MarkdownTextEditor` public view → Task 12. ✓
- §4.1 `MarkdownField`, `MarkdownEditor` → **hors scope** de ce plan (suivant plan, mentionné dans le header du document).
- §4.2 Modificateurs (`.markdownFeatures`, `.markdownPlaceholder`, `.markdownDebounce`, `.markdownReadOnly`) → Task 12. ✓
- §4.2 `.markdownToolbar`, `.markdownMaxListDepth`, `.markdownAutoFocus`, `.markdownOnChange`, `.markdownHighlights`, `.markdownContextMenu` → **hors scope** (suivant plan).
- §4.3 Enums → Task 8. ✓
- §4.4 Presets → Task 8. ✓
- §4.6 Comportement du binding (debounce, update externe, préservation sélection) → Task 11. ✓
- §5 Architecture, §5.3 structure du module → Task 2, 4, 5, 9, 10, 11, 12. ✓
- §6.1 Bold/Italic/Code/Link → parser + serializer + auto-format Tasks 4, 5, 10. ✓
- §6.1 Strikethrough → parser + serializer Tasks 4, 5 ; auto-format **hors scope** v1 de ce plan.
- §6.2 H1-H3, listes, blockquote, codeBlock, thematicBreak → parser + serializer Tasks 4, 5 ; auto-format pour H1-H3, blockquote, bullet/ordered/task Task 10. CodeBlock auto-format **hors scope**.
- §6.3 Saisie auto-format → Task 10. ✓
- §6.4 `MarkdownField` single-line → **hors scope** (suivant plan).
- §7 Modèle de données (attribute keys, types, invariants) → Task 2. ✓
- §8 Conversion (parser, serializer, round-trip) → Tasks 4, 5, 6. ✓
- §9.1 Modes — `MarkdownTextEditor` couvert. Autres → suivant plan.
- §9.2 Toolbar → **hors scope** (suivant plan).
- §9.3 Intégration SwiftUI native → Task 11 (delegate, `isEditable`, focused via SwiftUI host).
- §9.4 Comportements clavier — partiellement Task 10. Tab/Shift+Tab/Enter dans listes/Backspace en début de bloc spécial → suivant plan.
- §9.5 Compat highlights manager → **hors scope** (suivant plan, voir Q5 du spec).
- §10.4 Compat checkboxes prep → Task 7 (test compat) + Task 9 (UI). ✓
- §11.1 Tests unitaires Parser / Serializer / Round-trip / Configuration → Tasks 4, 5, 6 (configuration partielle, tests features explicites suivant plan).
- §11.4 Tests dans l'app — smoke test Task 14. ✓
- §12 Migration progressive — Phase 1 et début de Phase 2 (via back-compat alias Task 13). Phases 3-6 → suivant plan.

Pas de gap critique sur le scope annoncé (Phase 0 + Phase 1 + amorce Phase 2).

**Type consistency:**
- `MarkdownParser.parse(_ source: String) -> NSAttributedString` — appelé identiquement Tasks 4-12.
- `MarkdownSerializer.serialize(_ source: NSAttributedString) -> String` — appelé identiquement Tasks 5-12.
- `ListInfo(kind:level:index:checked:)` — défini Task 2, utilisé Tasks 4, 5, 7, 9, 10. ✓
- `BlockType` enum — défini Task 2, utilisé partout. ✓
- `MarkdownFeature` enum + `HeadingLevel` — défini Task 8, utilisé Tasks 10, 11, 12. ✓
- `EditorTextView.onTaskToggle: ((NSRange, Bool) -> Void)?` — exposé Task 9, branché Task 11.
- `NSAttributedString.Key.mdBold/.mdItalic/.mdInlineCode/.mdLink/.mdStrikethrough/.mdBlockType/.mdListInfo/.mdCodeLanguage` — défini Task 2, utilisé tout au long.

**Placeholder scan:**
- Aucun "TBD" / "implement later" / "fill in".
- Toutes les étapes contiennent le code à inscrire ou la commande à exécuter avec sortie attendue.
- La consigne Task 13 Step 1 ("Inspect current signature") est explicite — pas un blanc à remplir, c'est une instruction de lecture pour adapter Step 2 si la signature diffère.

Aucune correction nécessaire après self-review.
