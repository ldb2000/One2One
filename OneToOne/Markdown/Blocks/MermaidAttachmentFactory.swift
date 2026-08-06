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

    /// Attachments vivants, un par (source, apparence) — clé
    /// `MermaidRenderCache.key`. `StyleRenderer.applyMermaidAttachment` est
    /// réévalué à chaque frappe (comme tout le reste de `applyVisualStyle`) :
    /// sans ce cache, rouvrir un `WKWebView` à chaque caractère tapé ailleurs
    /// dans le document serait aussi ruineux qu'inutile pour un bloc mermaid
    /// déjà rendu ou déjà en cours de rendu.
    private static let liveCache: NSCache<NSString, NSTextAttachment> = {
        let cache = NSCache<NSString, NSTextAttachment>()
        cache.countLimit = 64
        return cache
    }()

    /// Clés dont le rendu web est déjà en vol — évite de lancer un second
    /// `WKWebView` pour le même bloc tant que le premier n'a pas répondu.
    private static var pendingKeys = Set<String>()

    /// Attachment mermaid pour `source`/`isDark`, partagé entre tous les
    /// appels (dédoublonné via `pendingKeys`). Renvoie immédiatement un
    /// placeholder ; si aucun rendu n'est déjà en cours pour cette clé, en
    /// lance un et appelle `onUpdate` (main actor) une fois l'attachment mis
    /// à jour en place — jamais avant, jamais deux fois pour le même rendu.
    static func attachment(for source: String, isDark: Bool, onUpdate: @escaping () -> Void) -> NSTextAttachment {
        let key = MermaidRenderCache.key(source: source, isDark: isDark)

        if let cached = liveCache.object(forKey: key as NSString) {
            return cached
        }

        let placeholderAttachment = placeholder(for: source)
        liveCache.setObject(placeholderAttachment, forKey: key as NSString)

        guard !pendingKeys.contains(key) else { return placeholderAttachment }
        pendingKeys.insert(key)

        render(source: source, isDark: isDark, into: placeholderAttachment) {
            pendingKeys.remove(key)
            onUpdate()
        }
        return placeholderAttachment
    }

    /// Vide le cache d'attachments vivants et les rendus en vol — tests
    /// uniquement, sur le modèle d'`ImageAttachmentFactory.invalidate()`.
    static func invalidateLiveCache() {
        liveCache.removeAllObjects()
        pendingKeys.removeAll()
    }

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
