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

    // MARK: - Collage

    /// Si le presse-papiers contient une image, l'enregistre sur disque et
    /// insère le placeholder d'image affiché par l'éditeur ; sinon délègue au
    /// collage standard.
    ///
    /// Le placeholder inséré est la même représentation que celle produite par
    /// `MarkdownParser` pour une image (`Markdown.Image` → un unique caractère
    /// « object replacement » `U+FFFC` porteur de `.mdImageURL`/`.mdImageAlt`),
    /// et non le texte `![alt](url)` littéral : sans ces attributs,
    /// `MarkdownSerializer` traiterait ce texte comme de la saisie ordinaire
    /// et échapperait ses caractères spéciaux (`!`, `[`, `]`, `(`, `)`, `_` —
    /// voir `MarkdownEscaping.escapeInline`) dès le `textDidChange` déclenché
    /// par cette insertion, corrompant la référence de façon permanente. Avec
    /// le placeholder attribué, ce même `textDidChange` fait au contraire
    /// apparaître l'image immédiatement : `StyleRenderer.applyVisualStyle`
    /// repère `.mdImageURL` sur la plage insérée et y attache le
    /// `NSTextAttachment` réel, sans attendre de frappe supplémentaire.
    override func paste(_ sender: Any?) {
        guard MediaStore.clipboardHasImage,
              let imageURL = MediaStore.saveClipboardImage() else {
            super.paste(sender)
            return
        }
        insertText(Self.imagePlaceholder(for: imageURL), replacementRange: selectedRange())
    }

    /// Construit le placeholder à insérer pour référencer `imageURL` — voir
    /// le doc-comment de `paste(_:)`. Isolé en fonction `static` pour être
    /// exercé par les tests indépendamment de `NSPasteboard.general`.
    static func imagePlaceholder(for imageURL: URL, alt: String = "image") -> NSAttributedString {
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(NSAttributedString(string: "\u{FFFC}", attributes: [
            .mdImageURL: imageURL,
            .mdImageAlt: alt
        ]))
        insertion.append(NSAttributedString(string: "\n"))
        return insertion
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
