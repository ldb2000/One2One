import AppKit

/// Gestes clavier propres aux items de liste — ⏎, Tab, ⇧Tab et ⌫ — routés
/// depuis `EditorRepresentable.Coordinator.textView(_:doCommandBy:)` quand ni
/// le menu « / » ni le menu « @ » n'ont absorbé la frappe (voir sa doc pour
/// l'ordre de priorité). Mute uniquement des attributs, jamais de marqueur
/// littéral — même discipline que `MarkdownBlockCommands`/`ShortcutDetector` :
/// l'appelant reste responsable de ne router ici qu'une fois les deux menus
/// écartés.
///
/// Chaque fonction lit l'item de liste courant via `.mdListInfo`, présent
/// soit sur le texte de l'item (ligne non vide), soit sur son seul `\n`
/// terminal (item vide mais suivi d'autre chose — voir la doc de
/// `MarkdownParser.emitList` : l'attribut couvre « contenu + retour à la
/// ligne »), soit — à défaut de tout caractère porteur, un item vide en toute
/// fin de document — dans `typingAttributes`, amorcé par un geste précédent
/// (`ShortcutDetector`, `SlashController`, ou cette même énumération).
enum ListEditingCommands {

    /// Point d'entrée unique, appelé depuis `Coordinator.textView(_:doCommandBy:)`
    /// avec le `commandSelector` reçu de `NSTextView`. Renvoie `false` pour
    /// tout sélecteur qui n'est pas un des quatre gestes couverts, ou quand le
    /// curseur n'est pas dans un item de liste : l'appelant laisse alors
    /// `NSTextView` exécuter son comportement par défaut.
    @discardableResult
    static func handle(commandSelector: Selector, in textView: NSTextView) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            return handleReturn(in: textView)
        case #selector(NSResponder.insertTab(_:)):
            return handleIndent(by: 1, in: textView)
        case #selector(NSResponder.insertBacktab(_:)):
            return handleIndent(by: -1, in: textView)
        case #selector(NSResponder.deleteBackward(_:)):
            return handleDeleteBackward(in: textView)
        default:
            return false
        }
    }

    // MARK: - ⏎

    /// Item non vide : nouvel item de même `kind`/`level`, jamais du même
    /// `checked`/`index` — une case cochée ne doit pas se propager au
    /// suivant, ni un ordinal figé (`MarkdownBlockCommands.setListKind`
    /// documente déjà que l'ordinal réel est recalculé au reparse, pas
    /// maintenu en direct). Item vide : sort de la liste, revient au
    /// paragraphe, sans insérer de nouvelle ligne — le curseur reste sur la
    /// même ligne, désormais un paragraphe vide.
    private static func handleReturn(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        // Même restriction que `SlashController.breakOutOfHeadingIfNeeded` :
        // une sélection non vide est un cas plus large, non mesuré, laissé au
        // comportement par défaut.
        guard selection.length == 0 else { return false }

        let contentRange = MarkdownBlockCommands.lineRange(in: storage, at: selection.location)
        guard let info = currentListInfo(in: textView, contentRange: contentRange) else { return false }

        if contentRange.length == 0 {
            exitEmptyListItem(in: textView, storage: storage, contentRange: contentRange)
        } else {
            continueNonEmptyListItem(info, in: textView, selection: selection)
        }
        return true
    }

    private static func exitEmptyListItem(in textView: NSTextView, storage: NSTextStorage, contentRange: NSRange) {
        if contentRange.location < storage.length {
            // Le `\n` terminal de l'item existe (l'item n'est pas en toute fin
            // de document) : il porte encore `.mdListInfo`/`.mdBlockType`,
            // seul caractère de cette ligne vide, à réattribuer directement —
            // `MarkdownBlockCommands` exclut délibérément ce `\n` de sa notion
            // de ligne (voir sa doc), donc ne peut pas le faire à notre place
            // ici ; aucune manipulation de texte, seulement des attributs.
            let newlineRange = NSRange(location: contentRange.location, length: 1)
            storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: newlineRange)
            storage.removeAttribute(.mdListInfo, range: newlineRange)
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: newlineRange)
            textView.didChangeText()
        }
        primeTypingAttributes(blockType: .paragraph, listInfo: nil, in: textView)
    }

    private static func continueNonEmptyListItem(_ info: ListInfo, in textView: NSTextView, selection: NSRange) {
        stripRiskyTypingAttributes(in: textView)
        // Le `\n` inséré termine l'item COURANT : il porte donc les attributs
        // exacts de cet item (y compris son `checked`/`index` propres), pas
        // ceux du nouvel item qui commencera juste après.
        let insertion = NSAttributedString(string: "\n", attributes: [
            .mdBlockType: BlockType.paragraph,
            .mdListInfo: info
        ])
        textView.insertText(insertion, replacementRange: selection)

        let freshInfo = ListInfo(kind: info.kind, level: info.level, index: nil,
                                 checked: info.kind == .task ? false : nil)
        primeTypingAttributes(blockType: .paragraph, listInfo: freshInfo, in: textView)
    }

    // MARK: - Tab / ⇧Tab

    private static func handleIndent(by delta: Int, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        let contentRange = MarkdownBlockCommands.lineRange(in: storage, at: selection.location)
        guard let info = currentListInfo(in: textView, contentRange: contentRange) else { return false }

        let newLevel = max(0, info.level + delta)
        guard newLevel != info.level else { return true } // déjà au niveau plancher : touche consommée, sans effet
        let updated = ListInfo(kind: info.kind, level: newLevel, index: info.index, checked: info.checked)

        if contentRange.length > 0 {
            MarkdownBlockCommands.setListLevel(newLevel, in: storage, at: contentRange.location)
            let resulting = storage.attribute(.mdListInfo, at: contentRange.location, effectiveRange: nil) as? ListInfo ?? updated
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: contentRange)
            textView.didChangeText()
            primeTypingAttributes(blockType: .paragraph, listInfo: resulting, in: textView)
        } else if contentRange.location < storage.length {
            let newlineRange = NSRange(location: contentRange.location, length: 1)
            storage.addAttribute(.mdListInfo, value: updated, range: newlineRange)
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: newlineRange)
            textView.didChangeText()
            primeTypingAttributes(blockType: .paragraph, listInfo: updated, in: textView)
        } else {
            primeTypingAttributes(blockType: .paragraph, listInfo: updated, in: textView)
        }
        return true
    }

    // MARK: - ⌫

    /// En tout début de texte de l'item (curseur exactement à
    /// `contentRange.location`, sélection vide) : retire le format de liste
    /// et garde le texte, sans supprimer aucun caractère — ni celui qui
    /// précéderait normalement le curseur (le `\n` de l'item précédent, que
    /// le comportement par défaut aurait supprimé, fusionnant les deux
    /// lignes). Toute autre position : non géré, comportement par défaut
    /// (suppression normale d'un caractère).
    private static func handleDeleteBackward(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }

        let contentRange = MarkdownBlockCommands.lineRange(in: storage, at: selection.location)
        guard selection.location == contentRange.location else { return false }
        guard let info = currentListInfo(in: textView, contentRange: contentRange) else { return false }

        if contentRange.length > 0 {
            // `setListKind` bascule vers le paragraphe quand le `kind` cible
            // égale l'existant (voir sa doc) : réappliquer le `kind` déjà en
            // place est donc précisément « retirer le format de liste, garder
            // le texte ».
            MarkdownBlockCommands.setListKind(info.kind, in: storage, at: contentRange.location)
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: contentRange)
            textView.didChangeText()
        }
        if contentRange.length == 0, contentRange.location < storage.length {
            let newlineRange = NSRange(location: contentRange.location, length: 1)
            storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: newlineRange)
            storage.removeAttribute(.mdListInfo, range: newlineRange)
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: newlineRange)
            textView.didChangeText()
        }
        primeTypingAttributes(blockType: .paragraph, listInfo: nil, in: textView)
        return true
    }

    // MARK: - Lecture de l'état courant

    /// `.mdListInfo` de l'item portant `contentRange`, ou `nil` si le curseur
    /// n'est pas dans un item de liste. Trois sources, dans l'ordre : le texte
    /// de l'item (ligne non vide), son `\n` terminal (ligne vide mais suivie
    /// d'autre chose), ou `typingAttributes` (ligne vide en toute fin de
    /// document, aucun caractère à lire).
    private static func currentListInfo(in textView: NSTextView, contentRange: NSRange) -> ListInfo? {
        guard let storage = textView.textStorage else { return nil }
        if contentRange.location < storage.length {
            return storage.attribute(.mdListInfo, at: contentRange.location, effectiveRange: nil) as? ListInfo
        }
        return textView.typingAttributes[.mdListInfo] as? ListInfo
    }

    // MARK: - `typingAttributes`

    /// Même liste qu'`ShortcutDetector.riskyTypingAttributeKeys` : à retirer
    /// avant d'amorcer un nouveau contexte de bloc/liste, pour ne pas hériter
    /// du gras/lien/code inline de l'item qui précède.
    private static let riskyTypingAttributeKeys: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    private static func stripRiskyTypingAttributes(in textView: NSTextView) {
        for key in riskyTypingAttributeKeys {
            textView.typingAttributes.removeValue(forKey: key)
        }
    }

    private static func primeTypingAttributes(blockType: BlockType, listInfo: ListInfo?, in textView: NSTextView) {
        stripRiskyTypingAttributes(in: textView)
        textView.typingAttributes[.mdBlockType] = blockType
        if let listInfo {
            textView.typingAttributes[.mdListInfo] = listInfo
        } else {
            textView.typingAttributes.removeValue(forKey: .mdListInfo)
        }
    }
}
