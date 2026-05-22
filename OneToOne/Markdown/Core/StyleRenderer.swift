import AppKit

/// Traduit les attributs custom `md*` (présents dans le `NSTextStorage`)
/// en attributs AppKit visibles (`.font`, `.foregroundColor`, etc.) pour
/// que la WYSIWYG rendition affiche réellement gras, italique, titres, etc.
///
/// Appelé à chaque update du textStorage (chargement initial, ré-application
/// d'un binding externe, ou après un changement local + auto-format).
enum StyleRenderer {

    static let baseFontSize: CGFloat = 13

    static func applyVisualStyle(to storage: NSTextStorage) {
        guard storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        // Reset display attrs avant de réappliquer — sinon stale styling après
        // édition d'une zone qui avait `mdBold` puis ne l'a plus.
        storage.beginEditing()
        storage.removeAttribute(.font, range: fullRange)
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.paragraphStyle, range: fullRange)
        storage.removeAttribute(.obliqueness, range: fullRange)

        storage.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let block = attrs[.mdBlockType] as? BlockType ?? .paragraph
            let listInfo = attrs[.mdListInfo] as? ListInfo
            let isBold   = (attrs[.mdBold] as? Bool) == true
            let isItalic = (attrs[.mdItalic] as? Bool) == true
            let isCode   = (attrs[.mdInlineCode] as? Bool) == true
            let isStrike = (attrs[.mdStrikethrough] as? Bool) == true
            let link     = attrs[.mdLink] as? URL

            var font = baseFont(for: block, list: listInfo)
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

            if isCode {
                storage.addAttribute(.backgroundColor,
                                     value: NSColor.quaternaryLabelColor.withAlphaComponent(0.4),
                                     range: range)
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.secondaryLabelColor,
                                     range: range)
            }

            if link != nil {
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
            }

            if isStrike {
                storage.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
            }

            switch block {
            case .h1, .h2, .h3:
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.controlAccentColor,
                                     range: range)
            case .blockquote:
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.secondaryLabelColor,
                                     range: range)
                storage.addAttribute(.obliqueness, value: 0.15, range: range)
            case .codeBlock:
                storage.addAttribute(.backgroundColor,
                                     value: NSColor.quaternaryLabelColor.withAlphaComponent(0.3),
                                     range: range)
            case .thematicBreak:
                storage.addAttribute(.foregroundColor,
                                     value: NSColor.tertiaryLabelColor,
                                     range: range)
            default:
                break
            }

            // Indentation pour listes (paragraph style).
            if let info = listInfo {
                let para = NSMutableParagraphStyle()
                let baseIndent = CGFloat(info.level) * 16 + 16
                para.headIndent = baseIndent
                para.firstLineHeadIndent = baseIndent - 12
                storage.addAttribute(.paragraphStyle, value: para, range: range)
            }
        }

        storage.endEditing()
    }

    private static func baseFont(for block: BlockType, list: ListInfo?) -> NSFont {
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
