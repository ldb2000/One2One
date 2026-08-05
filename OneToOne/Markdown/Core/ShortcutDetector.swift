import AppKit

/// Converts typed markdown delimiters into the editor's marker-free attributed
/// model. Two families of raccourcis :
/// - Inline (`**`, `_`, `` ` ``) : marqueurs appariés quelque part dans la
///   ligne, ex. `**gras**` laisse `gras` visible avec `.mdBold`.
/// - Préfixe de ligne (`# `, `- `, `1. `, `- [ ] `/`[] `, `> `, `---`) : un
///   marqueur en tout début de ligne convertit le **bloc** entier via
///   `MarkdownBlockCommands` — jamais par manipulation du texte littéral
///   (voir sa doc de tête), pour ne pas détruire le gras/liens/images déjà
///   présents sur la ligne au moment de la frappe.
enum ShortcutDetector {
    static func apply(after insertion: String,
                      in textView: NSTextView,
                      cursor: Int,
                      features: Set<MarkdownFeature>) {
        guard let storage = textView.textStorage else { return }

        if insertion == "*", features.contains(.bold),
           applyInlineShortcut(marker: "**", attribute: .mdBold, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 4, length: 0))
            return
        }

        if insertion == "_", features.contains(.italic),
           applyInlineShortcut(marker: "_", attribute: .mdItalic, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 2, length: 0))
            return
        }

        if insertion == "`", features.contains(.inlineCode),
           applyInlineShortcut(marker: "`", attribute: .mdInlineCode, in: storage, cursor: cursor) {
            textView.setSelectedRange(NSRange(location: cursor - 2, length: 0))
            return
        }

        if insertion == " " {
            if applyLinePrefixShortcut(in: textView, storage: storage, cursor: cursor, features: features) { return }
        }

        if insertion == "-" {
            if applyThematicBreakShortcut(in: textView, storage: storage, cursor: cursor, features: features) { return }
        }
    }

    // MARK: - Inline (`**`, `_`, `` ` ``)

    @discardableResult
    private static func applyInlineShortcut(marker: String,
                                            attribute: NSAttributedString.Key,
                                            in storage: NSTextStorage,
                                            cursor: Int) -> Bool {
        let ns = storage.string as NSString
        let markerLength = marker.utf16.count
        guard cursor >= markerLength * 2 else { return false }
        let closerRange = NSRange(location: cursor - markerLength, length: markerLength)
        guard ns.substring(with: closerRange) == marker else { return false }

        let searchRange = NSRange(location: 0, length: cursor - markerLength)
        let openerRange = ns.range(of: marker, options: [.backwards], range: searchRange)
        guard openerRange.location != NSNotFound else { return false }

        let innerStart = openerRange.location + markerLength
        let innerLength = closerRange.location - innerStart
        guard innerLength > 0 else { return false }
        let innerRange = NSRange(location: innerStart, length: innerLength)
        let inner = storage.attributedSubstring(from: innerRange).mutableCopy() as! NSMutableAttributedString
        inner.addAttribute(attribute, value: true, range: NSRange(location: 0, length: inner.length))

        let fullRange = NSRange(location: openerRange.location, length: cursor - openerRange.location)
        storage.replaceCharacters(in: fullRange, with: inner)
        return true
    }

    // MARK: - Préfixe de ligne (titres, listes, citation)

    /// Déclenché par l'espace qui suit un marqueur de préfixe tapé en tout
    /// début de ligne. Le texte du marqueur (espace comprise) est retiré du
    /// storage, puis `MarkdownBlockCommands` applique le type/la liste sur ce
    /// qui reste — jamais l'inverse : réappliquer un type de bloc sans avoir
    /// retiré le marqueur laisserait le `#`/`-` littéral dans le texte
    /// affiché, `MarkdownBlockCommands` ne mutant que des attributs, jamais
    /// les caractères.
    private static func applyLinePrefixShortcut(in textView: NSTextView,
                                                storage: NSTextStorage,
                                                cursor: Int,
                                                features: Set<MarkdownFeature>) -> Bool {
        let ns = storage.string as NSString
        guard cursor > 0, cursor <= ns.length else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        guard cursor - 1 >= lineRange.location else { return false }

        let prefixRange = NSRange(location: lineRange.location, length: (cursor - 1) - lineRange.location)
        guard prefixRange.length > 0 else { return false }
        let prefixText = ns.substring(with: prefixRange)

        // Jamais dans un bloc de code existant ou une cellule de tableau : ces
        // contextes ont leur propre gestion du texte, un raccourci de préfixe
        // n'y a pas de sens et pourrait corrompre la sérialisation
        // (`.mdBlockType`/`.mdTableCell` coexistants sur la même ligne).
        let existingBlockType = storage.attribute(.mdBlockType, at: lineRange.location, effectiveRange: nil) as? BlockType
        guard existingBlockType != .codeBlock else { return false }
        guard storage.attribute(.mdTableCell, at: lineRange.location, effectiveRange: nil) == nil else { return false }

        let deleteLength = prefixRange.length + 1 // marqueur + l'espace qui vient d'être tapée
        let lineStart = lineRange.location

        if let level = headingLevel(for: prefixText), features.contains(.heading(level)) {
            convertToBlock(lineBlockType(for: level), deleteLength: deleteLength, in: textView, storage: storage, lineStart: lineStart)
            return true
        }
        if prefixText == ">", features.contains(.blockquote) {
            convertToBlock(.blockquote, deleteLength: deleteLength, in: textView, storage: storage, lineStart: lineStart)
            return true
        }
        if (prefixText == "[]" || prefixText == "[ ]"), features.contains(.taskList) {
            convertToList(.task, deleteLength: deleteLength, in: textView, storage: storage, lineStart: lineStart)
            return true
        }
        if (prefixText == "-" || prefixText == "*"), features.contains(.bulletList) {
            convertToList(.bullet, deleteLength: deleteLength, in: textView, storage: storage, lineStart: lineStart)
            return true
        }
        if isOrderedListMarker(prefixText), features.contains(.orderedList) {
            convertToList(.ordered, deleteLength: deleteLength, in: textView, storage: storage, lineStart: lineStart)
            return true
        }
        return false
    }

    /// `prefix` est un titre valide (1 à 6 `#`, rien d'autre) : le niveau
    /// correspondant, ou `nil` sinon (0, >6, ou tout caractère qui n'est pas
    /// `#`).
    private static func headingLevel(for prefix: String) -> HeadingLevel? {
        guard (1...6).contains(prefix.count), prefix.allSatisfy({ $0 == "#" }) else { return nil }
        return HeadingLevel(rawValue: prefix.count)
    }

    private static func lineBlockType(for level: HeadingLevel) -> MarkdownBlockCommands.LineBlockType {
        switch level {
        case .h1: return .h1
        case .h2: return .h2
        case .h3: return .h3
        case .h4: return .h4
        case .h5: return .h5
        case .h6: return .h6
        }
    }

    /// `prefix` est un marqueur de liste ordonnée valide : un ou plusieurs
    /// chiffres suivis d'un point (ex. `1.`, `12.`) — l'ordinal réel n'est pas
    /// retenu, `MarkdownBlockCommands.setListKind` n'en garde jamais un
    /// (voir sa doc : la numérotation est recalculée au reparse).
    private static func isOrderedListMarker(_ prefix: String) -> Bool {
        guard prefix.hasSuffix(".") else { return false }
        let digits = prefix.dropLast()
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Retire le marqueur (`deleteLength` caractères depuis `lineStart`, espace
    /// finale comprise) puis applique `type` via `MarkdownBlockCommands` sur ce
    /// qui reste. Restyle explicitement la ligne quand il en reste quelque
    /// chose à styler (ligne non vide) : la restylisation que fait ensuite
    /// `Coordinator.textDidChange` se fie à `pendingStyleRange`, calculé
    /// *avant* cette mutation — sa position peut ne plus correspondre après le
    /// retrait du marqueur. Amorce aussi `typingAttributes` (`primeTypingAttributes`)
    /// dans tous les cas : `MarkdownBlockCommands` ne fait rien sur une ligne
    /// devenue vide (piège 3), et même sur une ligne non vide `NSTextView` ne
    /// recalcule `typingAttributes` qu'au déplacement du curseur, jamais après
    /// une mutation directe du storage.
    private static func convertToBlock(_ type: MarkdownBlockCommands.LineBlockType,
                                       deleteLength: Int,
                                       in textView: NSTextView,
                                       storage: NSTextStorage,
                                       lineStart: Int) {
        storage.deleteCharacters(in: NSRange(location: lineStart, length: deleteLength))
        MarkdownBlockCommands.setBlockType(type, in: storage, at: lineStart)
        let remaining = MarkdownBlockCommands.lineRange(in: storage, at: lineStart)

        let resultingType: BlockType
        if remaining.length > 0 {
            resultingType = storage.attribute(.mdBlockType, at: lineStart, effectiveRange: nil) as? BlockType ?? .paragraph
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: remaining)
        } else {
            resultingType = type.blockType
        }
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        primeTypingAttributes(blockType: resultingType, listInfo: nil, in: textView)
    }

    /// Même mécanique que `convertToBlock`, pour `MarkdownBlockCommands.setListKind`.
    private static func convertToList(_ kind: ListInfo.Kind,
                                      deleteLength: Int,
                                      in textView: NSTextView,
                                      storage: NSTextStorage,
                                      lineStart: Int) {
        storage.deleteCharacters(in: NSRange(location: lineStart, length: deleteLength))
        MarkdownBlockCommands.setListKind(kind, in: storage, at: lineStart)
        let remaining = MarkdownBlockCommands.lineRange(in: storage, at: lineStart)

        let resultingInfo: ListInfo?
        if remaining.length > 0 {
            resultingInfo = storage.attribute(.mdListInfo, at: lineStart, effectiveRange: nil) as? ListInfo
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: remaining)
        } else {
            resultingInfo = ListInfo(kind: kind, level: 0, index: nil, checked: kind == .task ? false : nil)
        }
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        primeTypingAttributes(blockType: .paragraph, listInfo: resultingInfo, in: textView)
    }

    // MARK: - Séparateur `---` (insertion, pas conversion)

    /// `MarkdownBlockCommands` refuse délibérément `.thematicBreak` (voir sa
    /// doc) : appliqué à une ligne existante, il en détruirait le contenu
    /// inline à la sérialisation. Ce raccourci n'est donc jamais une
    /// conversion — seulement possible quand la ligne entière tapée jusqu'ici
    /// est exactement `---` (rien avant, rien après le curseur) : dans ce cas
    /// précis il n'y a aucun contenu inline à perdre, et on **remplace** ces
    /// trois caractères par le marqueur attribué `.mdBlockType = .thematicBreak`
    /// (même représentation que `MarkdownParser.emitThematicBreak` et que
    /// `SlashController.insertThematicBreak`, round-trip garanti par
    /// construction) suivi d'un `\n` nu qui ouvre un nouveau paragraphe pour la
    /// frappe suivante — sans lui, le texte tapé après rejoindrait la ligne du
    /// séparateur, que `MarkdownSerializer.emitParagraph` ignore pour
    /// `.thematicBreak` (`inline` jamais lu), le perdant à la sérialisation.
    private static func applyThematicBreakShortcut(in textView: NSTextView,
                                                    storage: NSTextStorage,
                                                    cursor: Int,
                                                    features: Set<MarkdownFeature>) -> Bool {
        guard features.contains(.thematicBreak) else { return false }
        let ns = storage.string as NSString
        guard cursor >= 3, cursor <= ns.length else { return false }

        let contentRange = MarkdownBlockCommands.lineRange(in: storage, at: cursor - 1)
        guard contentRange.length == 3, ns.substring(with: contentRange) == "---" else { return false }

        // Jamais dans un bloc de code, ni dans une cellule de tableau, ni sur
        // une ligne déjà membre d'une liste (taper "---" comme contenu d'un
        // item existant est probablement voulu comme texte littéral, pas
        // comme une demande de sortir l'item pour le remplacer par un
        // séparateur — pas mesuré, choix conservateur).
        let existingBlockType = storage.attribute(.mdBlockType, at: contentRange.location, effectiveRange: nil) as? BlockType
        guard existingBlockType != .codeBlock else { return false }
        guard storage.attribute(.mdTableCell, at: contentRange.location, effectiveRange: nil) == nil else { return false }
        guard storage.attribute(.mdListInfo, at: contentRange.location, effectiveRange: nil) == nil else { return false }

        let replacement = NSMutableAttributedString(
            string: "—", attributes: [.mdBlockType: BlockType.thematicBreak]
        )
        replacement.append(NSAttributedString(string: "\n"))
        storage.replaceCharacters(in: contentRange, with: replacement)

        let newCursor = contentRange.location + replacement.length
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        primeTypingAttributes(blockType: .paragraph, listInfo: nil, in: textView)
        return true
    }

    // MARK: - `typingAttributes`

    /// Clés inline à risque à retirer avant d'amorcer `typingAttributes` pour
    /// un nouveau bloc — même liste qu'`EditorTextView.
    /// inlineAttributesToStripBeforeImageInsertion`/`SlashController.
    /// riskyTypingAttributeKeys` : sans ce nettoyage, `setSelectedRange`
    /// recalcule `typingAttributes` d'après le caractère qui précède la
    /// nouvelle position (ex. la fin de la ligne précédente), qui peut porter
    /// `.mdBold`/`.mdLink`… — un titre ou une liste fraîchement créés n'ont
    /// aucune raison d'en hériter.
    private static let riskyTypingAttributeKeys: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    private static func primeTypingAttributes(blockType: BlockType, listInfo: ListInfo?, in textView: NSTextView) {
        for key in riskyTypingAttributeKeys {
            textView.typingAttributes.removeValue(forKey: key)
        }
        textView.typingAttributes[.mdBlockType] = blockType
        if let listInfo {
            textView.typingAttributes[.mdListInfo] = listInfo
        } else {
            textView.typingAttributes.removeValue(forKey: .mdListInfo)
        }
    }
}
