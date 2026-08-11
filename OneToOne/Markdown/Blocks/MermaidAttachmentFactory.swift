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

    /// Largeur maximale d'un diagramme rendu (état 2 : « largeur maximale =
    /// la colonne de texte ») — même valeur qu'`ImageAttachmentFactory.
    /// maxWidth`, déjà la convention retenue dans ce module pour approximer
    /// la colonne de texte sans avoir à faire remonter la largeur réelle du
    /// conteneur jusqu'au callback de rendu asynchrone (qui n'y a pas accès).
    private static let maxDiagramWidth: CGFloat = MermaidBlockLayout.columnWidth

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
    /// lance un et appelle `onUpdate` (main actor) avec l'attachment mis à
    /// jour en place — jamais avant, jamais deux fois pour le même rendu.
    /// L'attachment est passé au callback pour que l'appelant retrouve le
    /// bloc par **identité** au moment où le rendu aboutit (le bloc a pu
    /// bouger entre-temps — voir `StyleRenderer.refreshMermaidGeometry`),
    /// jamais par une position capturée au lancement.
    static func attachment(for source: String, isDark: Bool, onUpdate: @escaping (NSTextAttachment) -> Void) -> NSTextAttachment {
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
            onUpdate(placeholderAttachment)
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
                // État 2 : le SVG rasterisé par `MermaidRenderer` n'a lui-même
                // aucun cadre — `framedDiagram` en compose un (fond + liseré
                // discrets) directement dans l'image finale, pour que
                // l'attachment soit un objet fini une fois pour toutes :
                // `MarkdownLayoutManager.drawMermaidDiagram` n'a plus ensuite
                // qu'à le dessiner tel quel, jamais à l'entourer une seconde
                // fois ni à le redimensionner dans une zone réservée.
                image = framedDiagram(rendered)
            case .failure(let message):
                // État 4 : cadre teinté (pas un liseré rouge vif), message
                // mermaid tronqué à deux lignes en monospace (voir
                // `frameImage`), bouton « Ouvrir le source » — cliquer
                // n'importe où sur ce cadre ouvre déjà le source (voir
                // `EditorTextView.mermaidBlockRange`), et le bouton
                // lui-même est en plus hit-testé précisément
                // (`EditorTextView.mermaidErrorActionButtonRange`, géométrie
                // partagée via `MermaidBlockLayout.errorActionButtonRect`).
                image = frameImage(
                    title: "Diagramme invalide", detail: message,
                    borderColor: .systemRed, titleColor: .systemRed,
                    tinted: true, actionLabel: MermaidBlockLayout.errorActionLabel
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

    /// Compose `diagram` (le SVG rasterisé par `MermaidRenderer`, sans cadre
    /// propre) à l'intérieur d'un cadre discret — fond
    /// `MermaidBlockLayout.backgroundColor`, liseré `borderColor`, marge
    /// interne horizontale/verticale définie par `MermaidBlockLayout` —
    /// directement dans l'image finale.
    /// L'attachment devient ainsi un objet fini une fois pour toutes :
    /// `MarkdownLayoutManager.drawMermaidDiagram` le dessine tel quel, sans
    /// fond ni liseré supplémentaires (jamais un double cadre) et sans le
    /// redimensionner (jamais une zone réservée plus grande que lui).
    ///
    /// `diagram` est réduit si besoin pour que la largeur **finale** (cadre
    /// compris) ne dépasse pas `maxDiagramWidth` — jamais agrandi (une petite
    /// icône n'a pas à remplir la colonne).
    static func framedDiagram(_ diagram: NSImage) -> NSImage {
        guard diagram.size.width > 0, diagram.size.height > 0 else { return diagram }

        let maxContentWidth = maxDiagramWidth - MermaidBlockLayout.horizontalInset * 2
        let scale = diagram.size.width > maxContentWidth ? maxContentWidth / diagram.size.width : 1
        let contentSize = NSSize(width: diagram.size.width * scale, height: diagram.size.height * scale)
        // La carte finale garde la même largeur que le placeholder et le
        // cadre d'erreur. Le SVG reste centré dans cette largeur commune :
        // sinon deux diagrammes valides ayant des contenus intrinsèquement
        // différents produisent des blocs de largeur différente.
        let size = NSSize(
            width: maxDiagramWidth,
            height: contentSize.height + MermaidBlockLayout.verticalInset * 2
        )

        return NSImage(size: size, flipped: false) { rect in
            let card = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: MermaidBlockLayout.cardCornerRadius,
                yRadius: MermaidBlockLayout.cardCornerRadius
            )
            MermaidBlockLayout.backgroundColor.setFill()
            card.fill()

            NSGraphicsContext.current?.saveGraphicsState()
            card.addClip()
            diagram.draw(in: NSRect(
                x: (rect.width - contentSize.width) / 2,
                y: MermaidBlockLayout.verticalInset,
                width: contentSize.width, height: contentSize.height
            ))
            NSGraphicsContext.current?.restoreGraphicsState()

            MermaidBlockLayout.borderColor.setStroke()
            card.lineWidth = 1
            card.stroke()
            return true
        }
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
            let isError = detail != nil || tinted
            let background = isError ? MermaidBlockLayout.errorBackgroundColor : MermaidBlockLayout.loadingBackgroundColor
            let resolvedBorderColor = isError ? MermaidBlockLayout.errorBorderColor : MermaidBlockLayout.borderColor
            let card = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: MermaidBlockLayout.cardCornerRadius,
                yRadius: MermaidBlockLayout.cardCornerRadius
            )
            background.setFill()
            card.fill()
            card.lineWidth = 1
            resolvedBorderColor.setStroke()
            card.stroke()

            if detail == nil {
                let loadingAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: MermaidBlockLayout.loadingTextColor
                ]
                let loadingText = title as NSString
                let loadingSize = loadingText.size(withAttributes: loadingAttrs)
                let groupWidth = 12 + 8 + loadingSize.width
                let groupX = rect.midX - groupWidth / 2
                let spinnerCenter = NSPoint(x: groupX + 6, y: rect.midY)
                let spinnerTrack = NSBezierPath()
                spinnerTrack.appendArc(withCenter: spinnerCenter, radius: 5.5, startAngle: 0, endAngle: 360)
                spinnerTrack.lineWidth = 1.5
                NSColor.labelColor.withAlphaComponent(0.16).setStroke()
                spinnerTrack.stroke()
                let spinnerArc = NSBezierPath()
                spinnerArc.appendArc(withCenter: spinnerCenter, radius: 5.5, startAngle: 35, endAngle: 155)
                spinnerArc.lineWidth = 1.5
                spinnerArc.lineCapStyle = .round
                NSColor.labelColor.withAlphaComponent(0.46).setStroke()
                spinnerArc.stroke()
                loadingText.draw(
                    at: NSPoint(x: groupX + 20, y: rect.midY - loadingSize.height / 2),
                    withAttributes: loadingAttrs
                )
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: isError ? MermaidBlockLayout.errorTitleColor : titleColor
            ]
            if isError {
                let iconRect = NSRect(x: 16, y: rect.height - 31, width: 14, height: 14)
                MermaidBlockLayout.errorTitleColor.setFill()
                NSBezierPath(ovalIn: iconRect).fill()
                let markAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let mark = "!" as NSString
                let markSize = mark.size(withAttributes: markAttrs)
                mark.draw(
                    at: NSPoint(x: iconRect.midX - markSize.width / 2, y: iconRect.midY - markSize.height / 2),
                    withAttributes: markAttrs
                )
                (title as NSString).draw(
                    in: NSRect(x: 37, y: rect.height - 33, width: rect.width - 53, height: 19),
                    withAttributes: titleAttrs
                )
            }

            if let badge {
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                let badgeText = badge as NSString
                let badgeSize = badgeText.size(withAttributes: badgeAttrs)
                let badgeRect = NSRect(
                    x: rect.width - 12 - badgeSize.width - 12,
                    y: rect.height - 13 - badgeSize.height,
                    width: badgeSize.width + 12,
                    height: badgeSize.height + 6
                )
                NSColor.labelColor.withAlphaComponent(0.04).setFill()
                NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
                badgeText.draw(
                    at: NSPoint(x: badgeRect.midX - badgeSize.width / 2, y: badgeRect.midY - badgeSize.height / 2),
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
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: MermaidBlockLayout.errorDetailColor,
                    .paragraphStyle: paragraph
                ]
                let lineHeight = ("Ag" as NSString).size(withAttributes: detailAttrs).height
                let detailRect = NSRect(
                    x: 16, y: max(CGFloat(42), rect.height - 39 - lineHeight * 2),
                    width: rect.width - 32, height: lineHeight * 2
                )
                (detail as NSString).draw(in: detailRect, withAttributes: detailAttrs)
            }

            if let actionLabel {
                let buttonAttrs: [NSAttributedString.Key: Any] = [
                    .font: MermaidBlockLayout.errorActionFont,
                    .foregroundColor: MermaidBlockLayout.errorDetailColor
                ]
                let buttonText = actionLabel as NSString
                let textSize = buttonText.size(withAttributes: buttonAttrs)
                // Géométrie partagée avec le hit-test — voir
                // `EditorTextView.mermaidErrorActionButtonRange` : un seul
                // calcul, jamais deux qui pourraient diverger.
                let buttonRect = MermaidBlockLayout.errorActionButtonRect(labelSize: textSize)
                let pill = NSBezierPath(roundedRect: buttonRect, xRadius: 5, yRadius: 5)
                NSColor.white.setFill()
                pill.fill()
                NSColor(red: 0xdc/255, green: 0xb5/255, blue: 0xb0/255, alpha: 1).setStroke()
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
