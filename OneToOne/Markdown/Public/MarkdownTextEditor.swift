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
