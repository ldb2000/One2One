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
