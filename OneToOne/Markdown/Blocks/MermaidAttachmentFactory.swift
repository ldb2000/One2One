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
    // Source de vérité unique : `MermaidBlockLayout` (partagée avec la
    // géométrie du bloc fermé, pour que la hauteur réservée à la pose du
    // placeholder corresponde exactement à l'image qu'il porte).
    private static let frameWidth: CGFloat = MermaidBlockLayout.placeholderWidth
    private static let frameHeightShort: CGFloat = MermaidBlockLayout.placeholderHeight
    private static let frameHeightWithDetail: CGFloat = MermaidBlockLayout.errorFrameHeight

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

    /// Attachment provisoire affiché pendant le rendu asynchrone — cadre
    /// discret, hauteur modeste (`MermaidBlockLayout.placeholderHeight`,
    /// jamais les 220pt étalés sur les lignes de l'ancien défaut), étiquette
    /// `mermaid` en haut à droite (état 1 du chantier).
    static func placeholder(for source: String) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        apply(
            image: frameImage(
                title: "Diagramme…", detail: nil,
                borderColor: .tertiaryLabelColor, titleColor: .secondaryLabelColor,
                badge: "mermaid"
            ),
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
                // État 4 : cadre teinté (pas un liseré rouge vif), message
                // mermaid tronqué à deux lignes en monospace (voir
                // `frameImage`), bouton « Ouvrir le source » — cliquer
                // n'importe où sur ce cadre ouvre déjà le source, voir
                // `EditorTextView.mermaidBlockRange` : le bouton n'est donc
                // qu'une affordance visuelle, pas un hit-test séparé.
                image = frameImage(
                    title: "Diagramme invalide", detail: message,
                    borderColor: .systemRed, titleColor: .systemRed,
                    tinted: true, actionLabel: "Ouvrir le source"
                )
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
    /// aussi bien au placeholder de chargement (état 1, `badge`) qu'au
    /// message d'erreur mermaid (état 4, `tinted`/`actionLabel`).
    /// `NSImage(size:flipped:drawingHandler:)` plutôt que `lockFocus()` : ne
    /// dépend pas d'un contexte de fenêtre actif, donc utilisable en
    /// environnement headless (tests).
    ///
    /// - Parameters:
    ///   - badge: étiquette discrète en haut à droite (ex. `"mermaid"`,
    ///     état 1) — absente par défaut.
    ///   - tinted: `true` pour un cadre teinté par `borderColor` (fond et
    ///     liseré atténués) plutôt que le liseré plein contrasté par défaut —
    ///     état 4, pour ne pas peindre un liseré rouge vif.
    ///   - actionLabel: pastille de bouton dessinée en bas à gauche (ex.
    ///     `"Ouvrir le source"`, état 4) — purement visuelle, le clic sur
    ///     tout le cadre ouvre déjà le source (`EditorTextView.
    ///     mermaidBlockRange`), pas de hit-test séparé à câbler.
    static func frameImage(
        title: String, detail: String?, borderColor: NSColor, titleColor: NSColor,
        badge: String? = nil, tinted: Bool = false, actionLabel: String? = nil
    ) -> NSImage {
        let height = detail == nil ? frameHeightShort : frameHeightWithDetail
        let size = NSSize(width: frameWidth, height: height)
        return NSImage(size: size, flipped: false) { rect in
            let background = tinted ? borderColor.withAlphaComponent(0.10) : NSColor.controlBackgroundColor
            background.setFill()
            rect.fill()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            borderColor.withAlphaComponent(tinted ? 0.4 : 1).setStroke()
            border.stroke()

            let badgeWidth: CGFloat = badge == nil ? 0 : 66
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: titleColor
            ]
            let titleRect = NSRect(x: 12, y: rect.height - 24, width: rect.width - 24 - badgeWidth, height: 18)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            if let badge {
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                let badgeText = badge as NSString
                let badgeSize = badgeText.size(withAttributes: badgeAttrs)
                badgeText.draw(
                    at: NSPoint(x: rect.width - 12 - badgeSize.width, y: rect.height - 12 - badgeSize.height),
                    withAttributes: badgeAttrs
                )
            }

            if let detail {
                // Monospace, tronqué à deux lignes (`lineBreakMode` +
                // hauteur bornée à `2 * lineHeight`) — un message d'erreur
                // mermaid peut être long, il ne doit ni déborder du cadre ni
                // agrandir sa hauteur (fixe, voir `frameHeightWithDetail`).
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let detailAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph
                ]
                let lineHeight = ("Ag" as NSString).size(withAttributes: detailAttrs).height
                let detailTop = actionLabel == nil ? 10 : 36
                let detailRect = NSRect(
                    x: 12, y: max(CGFloat(detailTop), rect.height - 24 - 6 - lineHeight * 2),
                    width: rect.width - 24, height: lineHeight * 2
                )
                (detail as NSString).draw(in: detailRect, withAttributes: detailAttrs)
            }

            if let actionLabel {
                let buttonAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
                let buttonText = actionLabel as NSString
                let textSize = buttonText.size(withAttributes: buttonAttrs)
                let buttonRect = NSRect(x: 12, y: 10, width: textSize.width + 20, height: 20)
                let pill = NSBezierPath(roundedRect: buttonRect, xRadius: buttonRect.height / 2, yRadius: buttonRect.height / 2)
                NSColor.controlBackgroundColor.setFill()
                pill.fill()
                NSColor.separatorColor.setStroke()
                pill.lineWidth = 1
                pill.stroke()
                buttonText.draw(
                    at: NSPoint(x: buttonRect.midX - textSize.width / 2, y: buttonRect.midY - textSize.height / 2),
                    withAttributes: buttonAttrs
                )
            }
            return true
        }
    }
}
