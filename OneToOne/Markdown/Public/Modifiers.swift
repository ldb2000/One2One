import SwiftUI

public extension MarkdownTextEditor {
    /// Restrict the set of markdown features the editor permits. Passing an
    /// empty set disables every formatting affordance, leaving a plain
    /// multi-line text editor (typed markdown syntax is no longer auto-formatted).
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

    /// Debounce delay (in seconds) before pushing edits to the `@Binding`.
    /// Default 0.3 s. A positive value is expected; 0 effectively pushes on
    /// every keystroke, and there is no enforced upper bound.
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
