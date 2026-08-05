import SwiftUI

/// Multi-line WYSIWYG markdown editor without a toolbar. Drop-in replacement
/// for `MarkdownEditorView`.
///
/// Configure via the `markdown…` view modifiers. Defaults: `features = .basic`,
/// `debounce = 0.3` s (a positive interval is expected — see
/// `markdownDebounce(_:)`), `readOnly = false`, empty placeholder.
public struct MarkdownTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var features: Set<MarkdownFeature> = .basic
    var debounce: TimeInterval = 0.3
    var readOnly: Bool = false
    var editorID: String = ""
    /// Closures des mentions `@` de collaborateurs, injectées par
    /// `markdownMentions(search:create:)`. `nil` (le défaut) désactive la
    /// fonctionnalité : ce module ne connaît pas SwiftData, donc aucune
    /// recherche par défaut n'est possible sans que l'appelant en fournisse
    /// une — voir `Modifiers.swift`.
    var mentionSearch: ((String) -> [MentionCandidate])?
    var mentionCreate: ((String) -> MentionCandidate?)?

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        EditorRepresentable(
            markdown: $text,
            placeholder: placeholder,
            features: features,
            debounce: debounce,
            readOnly: readOnly,
            editorID: editorID,
            mentionSearch: mentionSearch,
            mentionCreate: mentionCreate
        )
    }
}
