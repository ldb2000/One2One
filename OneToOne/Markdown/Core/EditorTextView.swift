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

    /// Attributs `md*` à retirer des `typingAttributes` avant d'insérer un
    /// placeholder d'image. Sans ce nettoyage, `insertText(_:replacementRange:)`
    /// les fusionne dans la plage insérée : `NSTextView` maintient
    /// `typingAttributes` à partir des attributs du caractère précédant le
    /// curseur, et complète avec ces valeurs les clés absentes de la chaîne
    /// attribuée qu'on lui passe. Un collage juste après du code inline
    /// hériterait ainsi `.mdInlineCode` sur le caractère `U+FFFC` — et
    /// `MarkdownSerializer.emitInline` donne la priorité exclusive au code
    /// inline, qui filtre les `U+FFFC` de son contenu : l'image disparaîtrait
    /// purement et simplement à la sérialisation, fichier resté orphelin sur
    /// disque. Un collage après du gras hériterait `.mdBold` et se
    /// retrouverait emballé en `**![...]**` sans que l'utilisateur l'ait
    /// demandé. Vérifié empiriquement pour ces deux cas — voir
    /// `Tests/EditorTextViewPasteTests.swift`.
    private static let inlineAttributesToStripBeforeImageInsertion: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    /// Insère le placeholder référençant `imageURL` sur sa propre ligne, en
    /// évitant qu'il hérite des attributs `md*` du contexte via
    /// `typingAttributes` (voir `inlineAttributesToStripBeforeImageInsertion`).
    /// Point d'entrée commun à `paste(_:)` et au bouton image de
    /// `MarkdownToolbar`, pour que les deux bénéficient du même nettoyage.
    func insertImagePlaceholder(for imageURL: URL, alt: String = "image") {
        for key in Self.inlineAttributesToStripBeforeImageInsertion {
            typingAttributes.removeValue(forKey: key)
        }
        insertText(Self.imagePlaceholder(for: imageURL, alt: alt), replacementRange: selectedRange())
    }

    /// Si le presse-papiers contient une image, l'enregistre sur disque et
    /// insère son placeholder ; sinon délègue au collage standard.
    ///
    /// Le placeholder inséré est la même représentation que celle produite par
    /// `MarkdownParser` pour une image (voir `ImagePlaceholder`), et non le
    /// texte `![alt](url)` littéral : sans ses attributs, `MarkdownSerializer`
    /// traiterait ce texte comme de la saisie ordinaire et échapperait ses
    /// caractères spéciaux (`!`, `[`, `]`, `(`, `)`, `_` — voir
    /// `MarkdownEscaping.escapeInline`) dès le `textDidChange` déclenché par
    /// cette insertion, corrompant la référence de façon permanente. Avec le
    /// placeholder attribué, ce même `textDidChange` fait au contraire
    /// apparaître l'image immédiatement : `StyleRenderer.applyVisualStyle`
    /// repère `.mdImageURL` sur la plage insérée et y attache le
    /// `NSTextAttachment` réel, sans attendre de frappe supplémentaire.
    ///
    /// Si `saveClipboardImage()` échoue (écriture disque impossible), le
    /// repli vers `super.paste(sender)` ne colle rien de visible : le
    /// presse-papiers ne contient par construction que de l'image à ce point
    /// (le `guard` a déjà exclu le cas contraire), et `importsGraphics =
    /// false` (`commonInit`) fait que `NSTextView` ignore le contenu image
    /// brut. C'est un échec silencieux connu et accepté (pas de UI d'erreur
    /// pour un cas limite — disque plein, permissions — jugé hors périmètre
    /// ici) plutôt qu'un bug : l'utilisateur ne perd rien puisque rien
    /// n'avait encore été inséré.
    override func paste(_ sender: Any?) {
        guard MediaStore.clipboardHasImage,
              let imageURL = MediaStore.saveClipboardImage() else {
            super.paste(sender)
            return
        }
        insertImagePlaceholder(for: imageURL)
    }

    /// Construit le placeholder à insérer pour référencer `imageURL` : le
    /// caractère `ImagePlaceholder.attributedString` entouré de retours à la
    /// ligne pour que l'image occupe sa propre ligne. Isolé en fonction
    /// `static` pour être exercé par les tests indépendamment de
    /// `NSPasteboard.general`.
    static func imagePlaceholder(for imageURL: URL, alt: String = "image") -> NSAttributedString {
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(ImagePlaceholder.attributedString(for: imageURL, alt: alt))
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
