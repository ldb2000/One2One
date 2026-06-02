import AppKit

/// Detects markdown shortcuts typed by the user and rewrites the underlying
/// `NSTextStorage` to apply the corresponding custom attributes.
///
/// - `# ` at line start → set `mdBlockType = .h1` on that paragraph and
///   delete the literal `# ` characters.
/// - `- ` at line start → start a bullet list (set `mdListInfo`).
/// - `- [ ] ` or `- [x] ` → start a task list with checked state.
/// - `**word** ` (typed with trailing space) → bold the word and drop the
///   asterisks.
///
/// Only triggers for features present in the active feature set so the
/// editor honours configuration.
enum ShortcutDetector {

    static func apply(after insertion: String,
                      in storage: NSTextStorage,
                      cursor: Int,
                      features: Set<MarkdownFeature>) {
        // Only fire on space — keeps logic simple and predictable.
        guard insertion == " " else { return }
        let ns = storage.string as NSString
        // Find start of current paragraph.
        var lineStart = cursor
        while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let prefix = ns.substring(with: NSRange(location: lineStart, length: cursor - lineStart))

        // Block-level prefixes (only at the very start of the paragraph).
        if let block = blockPrefix(prefix, features: features) {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
            storage.addAttribute(.mdBlockType, value: block,
                                 range: NSRange(location: lineStart, length: 0))
            return
        }

        if let list = listPrefix(prefix, features: features) {
            storage.replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
            storage.addAttribute(.mdListInfo, value: list,
                                 range: NSRange(location: lineStart, length: 0))
            return
        }

        // Inline emphasis: look for `**word**` ending right before cursor.
        if features.contains(.bold) {
            if let range = matchInline(closer: "**", opener: "**", before: cursor, in: ns) {
                applyAttributeAround(.mdBold, in: storage, openerCount: 2, closerCount: 2, range: range)
                return
            }
        }
        if features.contains(.italic) {
            if let range = matchInline(closer: "*", opener: "*", before: cursor, in: ns) {
                applyAttributeAround(.mdItalic, in: storage, openerCount: 1, closerCount: 1, range: range)
                return
            }
        }
        if features.contains(.inlineCode) {
            if let range = matchInline(closer: "`", opener: "`", before: cursor, in: ns) {
                applyAttributeAround(.mdInlineCode, in: storage, openerCount: 1, closerCount: 1, range: range)
                return
            }
        }
    }

    // MARK: - Helpers

    /// Reconnaît un préfixe de bloc en début de paragraphe et renvoie le
    /// `BlockType` correspondant, ou `nil`. La comparaison est exacte (préfixe
    /// littéral espace compris) et conditionnée à l'activation de la feature.
    private static func blockPrefix(_ prefix: String,
                                    features: Set<MarkdownFeature>) -> BlockType? {
        if prefix == "# ", features.contains(.heading(.h1))  { return .h1 }
        if prefix == "## ", features.contains(.heading(.h2)) { return .h2 }
        if prefix == "### ", features.contains(.heading(.h3)) { return .h3 }
        if prefix == "> ", features.contains(.blockquote)    { return .blockquote }
        return nil
    }

    /// Reconnaît un préfixe de liste et renvoie le `ListInfo` initial, ou `nil`.
    /// Gère les checkboxes de task-list (`- [ ] ` / `- [x] `), les puces
    /// (`- ` / `* `) et l'amorce ordonnée (`1. `), chacune gardée par sa feature.
    private static func listPrefix(_ prefix: String,
                                   features: Set<MarkdownFeature>) -> ListInfo? {
        if features.contains(.taskList) {
            if prefix == "- [ ] " { return ListInfo(kind: .task, level: 0, checked: false) }
            if prefix == "- [x] " { return ListInfo(kind: .task, level: 0, checked: true) }
        }
        if features.contains(.bulletList), prefix == "- " || prefix == "* " {
            return ListInfo(kind: .bullet, level: 0)
        }
        if features.contains(.orderedList), prefix == "1. " {
            return ListInfo(kind: .ordered, level: 0, index: 1)
        }
        return nil
    }

    /// Cherche, juste avant le curseur, un span `opener…inner…closer`. `cursor`
    /// pointe APRÈS l'espace déclencheur : le closer est donc attendu juste
    /// avant cet espace. Renvoie la plage complète (opener inclus) ou `nil` si
    /// le closer manque, l'opener est introuvable, ou l'intérieur est vide.
    private static func matchInline(closer: String, opener: String,
                                    before cursor: Int,
                                    in ns: NSString) -> NSRange? {
        // `cursor` = insertion point AFTER the trailing space. Donc l'espace
        // est à `cursor - 1` et la fin exclusive du closer est aussi à
        // `cursor - 1` (closer juste avant l'espace).
        let closerEndExclusive = cursor - 1
        guard closerEndExclusive >= closer.count else { return nil }
        let closerStart = closerEndExclusive - closer.count
        let closerCandidate = ns.substring(with: NSRange(location: closerStart, length: closer.count))
        guard closerCandidate == closer else { return nil }
        let searchEnd = closerStart
        guard searchEnd >= opener.count else { return nil }
        let openerRange = ns.range(of: opener,
                                   options: [.backwards],
                                   range: NSRange(location: 0, length: searchEnd))
        guard openerRange.location != NSNotFound else { return nil }
        let innerStart = openerRange.location + openerRange.length
        let innerLength = closerStart - innerStart
        guard innerLength > 0 else { return nil }
        // Full match = opener + inner + closer (l'espace reste en place).
        return NSRange(location: openerRange.location,
                       length: closerEndExclusive - openerRange.location)
    }

    /// Wraps a range `[opener…inner…closer]` by deleting opener and closer
    /// and tagging the remaining inner range with `attr`. `openerCount` /
    /// `closerCount` are the delimiter lengths (e.g. 2 for `**`, 1 for `*`).
    /// Deletion happens first — replacing the whole span by its inner text —
    /// then the attribute is added on the now-shifted, delimiter-free range.
    private static func applyAttributeAround(_ attr: NSAttributedString.Key,
                                             in storage: NSTextStorage,
                                             openerCount: Int,
                                             closerCount: Int,
                                             range: NSRange) {
        let innerStart = range.location + openerCount
        let innerLength = range.length - openerCount - closerCount
        guard innerLength > 0 else { return }
        let innerRange = NSRange(location: innerStart, length: innerLength)
        // Capture inner first to avoid index drift.
        let innerSubstr = (storage.string as NSString).substring(with: innerRange)
        storage.replaceCharacters(in: range, with: innerSubstr)
        let newRange = NSRange(location: range.location, length: innerLength)
        storage.addAttribute(attr, value: true, range: newRange)
    }
}
