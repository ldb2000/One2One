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
    /// Value: `String` — the info-string of a fenced code block, used as the
    /// language hint after the opening ``` fence (e.g. "swift", "json"). Empty
    /// or absent means an unlabelled fence.
    static let mdCodeLanguage  = NSAttributedString.Key("mdCodeLanguage")
}

/// Block-level kind applied to a whole paragraph range.
/// `paragraph` is the default body text; `h1`-`h6` are heading levels;
/// `blockquote` is a `>` quote; `codeBlock` is a fenced block whose language is
/// carried by `mdCodeLanguage`; `thematicBreak` is a horizontal rule (`---`).
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
    /// 1-based ordinal — relevant only when `kind == .ordered`; ignored otherwise.
    public let index: Int?
    /// Checkbox state — relevant only when `kind == .task`; ignored otherwise.
    public let checked: Bool?

    /// Creates list metadata. `index` is meaningful only for `.ordered` items
    /// and `checked` only for `.task` items; both should be left `nil` for the
    /// kinds they don't apply to.
    public init(kind: Kind, level: Int = 0, index: Int? = nil, checked: Bool? = nil) {
        self.kind = kind
        self.level = level
        self.index = index
        self.checked = checked
    }
}
