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
