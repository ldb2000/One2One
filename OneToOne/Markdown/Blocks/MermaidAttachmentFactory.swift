import AppKit

/// Construit — et met à jour de façon **asynchrone** — l'`NSTextAttachment`
/// affiché à la place d'un bloc ```` ```mermaid ```` dans l'éditeur.
///
/// Contrairement à `ImageAttachmentFactory` (lecture disque synchrone), le
/// rendu web n'est pas immédiat : `placeholder(for:)` pose tout de suite un
/// attachment provisoire, puis `render(source:isDark:into:completion:)` mute
/// **la même instance** une fois le SVG prêt (succès) ou l'erreur mermaid
/// connue (échec). Remplacer `.image`/`.bounds` sur un `NSTextAttachment`
/// déjà posé dans le storage ne touche pas `NSTextStorage` lui-même — aucune
/// pile d'annulation polluée, aucune sauvegarde déclenchée, aucun saut de
/// curseur. Voir `MermaidAttachmentFactoryTests.test_mutatingAttachmentImage_doesNotEditTextStorage`.
///
/// Le source markdown (le texte entre les fences) n'est jamais lu ni modifié
/// par cette fabrique : un diagramme invalide affiche un cadre d'erreur à la
/// place de l'image, mais le texte source reste intact dans le document.
@MainActor
enum MermaidAttachmentFactory {
    private static let frameWidth: CGFloat = 320
    private static let frameHeightShort: CGFloat = 60
    private static let frameHeightWithDetail: CGFloat = 110

    /// Attachment provisoire affiché pendant le rendu asynchrone.
    static func placeholder(for source: String) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        apply(
            image: frameImage(title: "Diagramme…", detail: nil, borderColor: .tertiaryLabelColor, titleColor: .secondaryLabelColor),
            to: attachment
        )
        return attachment
    }

    /// Lance le rendu de `source` et, une fois prêt, met à jour `attachment`
    /// en place (image + bounds). `completion` est appelé sur le main actor
    /// après la mutation, pour que l'appelant invalide l'affichage du glyphe
    /// concerné — jamais le storage.
    static func render(source: String, isDark: Bool, into attachment: NSTextAttachment, completion: @escaping () -> Void) {
        MermaidRenderer.render(source: source, isDark: isDark) { outcome in
            let image: NSImage
            switch outcome {
            case .success(let rendered):
                image = rendered
            case .failure(let message):
                image = frameImage(title: "Diagramme invalide", detail: message, borderColor: .systemRed, titleColor: .systemRed)
            }
            apply(image: image, to: attachment)
            completion()
        }
    }

    private static func apply(image: NSImage, to attachment: NSTextAttachment) {
        attachment.image = image
        attachment.bounds = ImageAttachmentFactory.displayBounds(for: image.size)
    }

    /// Construit un cadre bordé avec un titre (et un détail optionnel) — sert
    /// aussi bien au placeholder de chargement qu'au message d'erreur
    /// mermaid. `NSImage(size:flipped:drawingHandler:)` plutôt que
    /// `lockFocus()` : ne dépend pas d'un contexte de fenêtre actif, donc
    /// utilisable en environnement headless (tests).
    static func frameImage(title: String, detail: String?, borderColor: NSColor, titleColor: NSColor) -> NSImage {
        let height = detail == nil ? frameHeightShort : frameHeightWithDetail
        let size = NSSize(width: frameWidth, height: height)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            borderColor.setStroke()
            border.stroke()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: titleColor
            ]
            let titleRect = NSRect(x: 12, y: rect.height - 24, width: rect.width - 24, height: 18)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            if let detail {
                let detailAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                let detailRect = NSRect(x: 12, y: 10, width: rect.width - 24, height: rect.height - 38)
                (detail as NSString).draw(in: detailRect, withAttributes: detailAttrs)
            }
            return true
        }
    }
}
