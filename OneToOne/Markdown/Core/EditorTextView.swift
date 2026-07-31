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

    /// Configure les options d'édition de texte. Les corrections/complétions/
    /// remplacements automatiques sont désactivés car ils interféreraient avec
    /// la syntaxe markdown (ex. transformation des `--` en tiret long), et
    /// `importsGraphics` est coupé car l'éditeur ne gère que du texte balisé.
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

    /// Intercepte le clic pour détecter s'il vise la checkbox d'une tâche.
    /// Heuristique : on remonte au début de la ligne, on calcule le rect du
    /// premier glyphe, et si l'abscisse du clic tombe dans les ~14pt de marge
    /// gauche on bascule l'état coché et on prévient le coordinator via
    /// `onTaskToggle`. Sinon on délègue au comportement standard de `NSTextView`.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if charIndex < (textStorage?.length ?? 0) {
            let nsString = string as NSString
            var lineStart = charIndex
            while lineStart > 0, nsString.character(at: lineStart - 1) != 0x0A {
                lineStart -= 1
            }
            let maxLen = min(nsString.length - lineStart, 6)
            if maxLen >= 6 {
                let prefixRange = NSRange(location: lineStart, length: 6)
                let prefixStr = nsString.substring(with: prefixRange)
                if prefixStr == "- [ ] " || prefixStr == "- [x] " {
                    let glyphIdx = layoutManager?.glyphIndexForCharacter(at: lineStart) ?? 0
                    if let container = textContainer,
                       let rect = layoutManager?.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 5), in: container) {
                        let xInTextContainer = point.x - textContainerInset.width
                        if xInTextContainer < rect.maxX + 4 {
                            let isChecked = prefixStr == "- [x] "
                            let replacement = isChecked ? "- [ ] " : "- [x] "
                            textStorage?.replaceCharacters(in: prefixRange, with: replacement)
                            onTaskToggle?(prefixRange, !isChecked)
                            return
                        }
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }
}
