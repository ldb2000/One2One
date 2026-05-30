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
