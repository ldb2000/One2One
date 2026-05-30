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
