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
