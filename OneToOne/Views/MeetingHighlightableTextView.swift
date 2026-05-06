import SwiftUI
import AppKit

/// Read-only (or editable) text view with persistent yellow highlights and a
/// custom context menu entry "Ajouter au rapport manager" (⇧⌘M).
///
/// Why NSViewRepresentable:
/// - SwiftUI `Text + textSelection(.enabled)` does not expose the active
///   selection nor allow us to inject persistent background-color spans on
///   arbitrary ranges.
/// - We need NSTextView for both: `selectedRange()` access AND
///   `NSTextStorage.addAttribute(.backgroundColor, ...)` on highlight ranges.
///
/// Range validation: any range whose end exceeds the text length is silently
/// ignored at render — covers the case where the source text was edited and
/// stored offsets became invalid (spec decision A1).
struct MeetingHighlightableTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let highlightedRanges: [NSRange]
    let onAddToManagerReport: (NSRange, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.string = text
        context.coordinator.textView = tv

        // Inject custom menu item via delegate `menu(for:)`.
        // The selector below is recognized in `Coordinator`.
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        tv.isEditable = isEditable

        // Spec 7.3: re-apply highlights only when ranges or text length changed.
        let total = (tv.string as NSString).length
        let coord = context.coordinator
        if coord.lastAppliedRanges != highlightedRanges || coord.lastAppliedTextLength != total {
            applyHighlights(to: tv)
            coord.lastAppliedRanges = highlightedRanges
            coord.lastAppliedTextLength = total
        }
    }

    private func applyHighlights(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let total = (tv.string as NSString).length
        storage.beginEditing()
        // Reset background on full range.
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: total))
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in highlightedRanges {
            guard range.location >= 0,
                  range.length > 0,
                  range.location + range.length <= total
            else { continue }
            storage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MeetingHighlightableTextView
        weak var textView: NSTextView?

        // Cache to enforce spec 7.3 "re-render uniquement quand la liste change".
        // Without this, every SwiftUI invalidation pass walks the whole NSTextStorage
        // even when nothing relevant changed.
        var lastAppliedRanges: [NSRange] = []
        var lastAppliedTextLength: Int = -1

        init(_ parent: MeetingHighlightableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // Always insert our action at the top of the menu, even if no
            // selection — then disable when selection is invalid.
            let item = NSMenuItem(
                title: "Ajouter au rapport manager",
                action: #selector(addToManagerReportAction(_:)),
                keyEquivalent: "M"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.representedObject = view
            let range = view.selectedRange()
            let snippet = (view.string as NSString).substring(with: range)
            let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            item.isEnabled = (range.length >= 3 && !trimmed.isEmpty)
            menu.insertItem(item, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
            return menu
        }

        @objc func addToManagerReportAction(_ sender: NSMenuItem) {
            guard let tv = sender.representedObject as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let snippet = (tv.string as NSString).substring(with: range)
            parent.onAddToManagerReport(range, snippet)
        }
    }
}
