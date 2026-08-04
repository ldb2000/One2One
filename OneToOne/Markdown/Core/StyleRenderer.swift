import AppKit

/// Translates custom markdown attributes (`mdBold`, `mdBlockType`, etc.) into
/// AppKit display attributes. The storage string stays marker-free while the
/// serializer keeps persisting markdown syntax.
enum StyleRenderer {
    static let baseFontSize: CGFloat = 13

    static func applyVisualStyle(to storage: NSTextStorage) {
        applyVisualStyle(to: storage, affectedRange: nil)
    }

    static func applyVisualStyle(to storage: NSTextStorage, affectedRange: NSRange?) {
        guard storage.length > 0 else { return }

        let renderRange = normalizedRenderRange(affectedRange, in: storage)
        storage.beginEditing()
        storage.removeAttribute(.font, range: renderRange)
        storage.removeAttribute(.foregroundColor, range: renderRange)
        storage.removeAttribute(.backgroundColor, range: renderRange)
        storage.removeAttribute(.underlineStyle, range: renderRange)
        storage.removeAttribute(.strikethroughStyle, range: renderRange)
        storage.removeAttribute(.paragraphStyle, range: renderRange)
        storage.removeAttribute(.obliqueness, range: renderRange)
        storage.removeAttribute(.attachment, range: renderRange)

        storage.enumerateAttributes(in: renderRange, options: []) { attrs, range, _ in
            let block = attrs[.mdBlockType] as? BlockType ?? .paragraph
            let listInfo = attrs[.mdListInfo] as? ListInfo
            let isBold = (attrs[.mdBold] as? Bool) == true
            let isItalic = (attrs[.mdItalic] as? Bool) == true
            let isCode = (attrs[.mdInlineCode] as? Bool) == true
            let isStrike = (attrs[.mdStrikethrough] as? Bool) == true
            let link = attrs[.mdLink] as? URL

            var font = baseFont(for: block)
            if isBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if isItalic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if isCode {
                font = NSFont.monospacedSystemFont(ofSize: baseFontSize - 0.5, weight: .regular)
            }
            storage.addAttribute(.font, value: font, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)

            if isCode {
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.4),
                    range: range
                )
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }

            if link != nil {
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            if isStrike {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            switch block {
            case .h1, .h2, .h3:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .blockquote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                storage.addAttribute(.obliqueness, value: 0.15, range: range)
            case .codeBlock:
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.3),
                    range: range
                )
            case .thematicBreak:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .h4, .h5, .h6, .paragraph:
                break
            }

            if let info = listInfo {
                // `firstLineHeadIndent` == `headIndent` : le texte de l'item
                // (seul contenu de la ligne, le storage ne porte aucun
                // marqueur) démarre au même endroit sur sa première ligne et
                // sur ses lignes de repli. `MarkdownLayoutManager` dessine le
                // marqueur dans la marge ainsi libérée, à gauche de cette
                // position — voir `ListMarkerLayout.textIndent(for:)`.
                let para = NSMutableParagraphStyle()
                let indent = ListMarkerLayout.textIndent(for: info)
                para.headIndent = indent
                para.firstLineHeadIndent = indent
                storage.addAttribute(.paragraphStyle, value: para, range: range)
            }

            // `mdImageURL` marque un run, pas forcément un seul caractère :
            // dans `NSTextView`, du texte tapé juste après une image hérite
            // de l'attribut via les `typingAttributes` du caractère
            // précédent, sans être lui-même une image (même défaut que
            // documenté et testé côté sérialisation, voir
            // `MarkdownSerializer.expandingImagePlaceholders`). On ne pose
            // donc l'attachment / la couleur d'échec que sur les caractères
            // `U+FFFC` du run ; le reste garde le style normal posé ci-dessus
            // (police, gras, paragraphStyle…).
            if let imageURL = attrs[.mdImageURL] as? URL {
                let nsText = storage.string as NSString
                var remaining = range
                while remaining.length > 0 {
                    let placeholder = nsText.range(of: "\u{FFFC}", options: [], range: remaining)
                    guard placeholder.location != NSNotFound else { break }
                    if let attachment = ImageAttachmentFactory.attachment(for: imageURL) {
                        storage.addAttribute(.attachment, value: attachment, range: placeholder)
                    } else {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: placeholder)
                    }
                    let nextLocation = placeholder.location + placeholder.length
                    remaining = NSRange(
                        location: nextLocation,
                        length: remaining.location + remaining.length - nextLocation
                    )
                }
            }
        }

        storage.endEditing()
    }

    private static func normalizedRenderRange(_ range: NSRange?, in storage: NSTextStorage) -> NSRange {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard let range else { return fullRange }

        let location = min(max(0, range.location), storage.length)
        let upperBound = min(max(location, range.location + range.length), storage.length)
        let clamped = NSRange(location: location, length: upperBound - location)
        let nsText = storage.string as NSString
        return nsText.lineRange(for: clamped)
    }

    private static func baseFont(for block: BlockType) -> NSFont {
        switch block {
        case .h1: return NSFont.systemFont(ofSize: 22, weight: .bold)
        case .h2: return NSFont.systemFont(ofSize: 18, weight: .bold)
        case .h3: return NSFont.systemFont(ofSize: 15, weight: .bold)
        case .h4, .h5, .h6: return NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        case .codeBlock: return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        case .blockquote, .paragraph, .thematicBreak:
            return NSFont.systemFont(ofSize: baseFontSize)
        }
    }
}
