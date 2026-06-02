import SwiftUI
import AppKit

/// Read-only (or editable) text view with persistent yellow highlights and a
/// custom context menu entry "Ajouter au rapport manager" (⇧⌘M).
///
/// Why NSViewRepresentable:
/// - SwiftUI `Text + textSelection(.enabled)` does not expose the active
///   selection nor allow us to inject persistent background-color spans on
///   arbitrary ranges.
/// - We need NSTextView for both: `selectedRange()` access AND
///   `NSTextStorage.addAttribute(.backgroundColor, ...)` on highlight ranges.
///
/// Range validation: any range whose end exceeds the text length is silently
/// ignored at render — covers the case where the source text was edited and
/// stored offsets became invalid (spec decision A1).
struct MeetingHighlightableTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let highlightedRanges: [NSRange]
    let onAddToManagerReport: (NSRange, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.isSelectable = true
        // En lecture seule, on rend le markdown stylé ; en édition, plain text.
        tv.isRichText = !isEditable
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        if isEditable {
            tv.string = text
        } else {
            tv.textStorage?.setAttributedString(Self.renderMarkdown(text))
        }
        context.coordinator.textView = tv

        // Inject custom menu item via delegate `menu(for:)`.
        // The selector below is recognized in `Coordinator`.
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            if isEditable {
                tv.string = text
            } else {
                tv.textStorage?.setAttributedString(Self.renderMarkdown(text))
            }
        }
        tv.isEditable = isEditable
        tv.isRichText = !isEditable

        // Spec 7.3: re-apply highlights only when ranges or text length changed.
        let total = (tv.string as NSString).length
        let coord = context.coordinator
        if coord.lastAppliedRanges != highlightedRanges || coord.lastAppliedTextLength != total {
            applyHighlights(to: tv)
            coord.lastAppliedRanges = highlightedRanges
            coord.lastAppliedTextLength = total
        }
    }

    /// Réapplique les surlignages jaunes sur `tv` : réinitialise d'abord tout
    /// fond puis ajoute la couleur sur chaque range valide. Les ranges hors
    /// bornes (texte modifié depuis le stockage des offsets) sont ignorées.
    private func applyHighlights(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let total = (tv.string as NSString).length
        storage.beginEditing()
        // Reset background on full range.
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: total))
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in highlightedRanges {
            guard range.location >= 0,
                  range.length > 0,
                  range.location + range.length <= total
            else { continue }
            storage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        storage.endEditing()
    }

    // MARK: - Markdown rendering (read-only mode)
    //
    // Parseur ligne à ligne minimal mais suffisant pour les rapports IA :
    //   # / ## / ### / ####    → titres en taille décroissante, gras
    //   - / * / 1.             → puces / listes numérotées
    //   ---                    → divider horizontal
    //   > quote                → italique gris
    //   ```code```             → bloc code mono
    //   `inline`               → inline mono
    //   **bold** / *italic*    → inline emphase
    //   [text](url)            → lien cliquable
    //
    // Sortie : NSAttributedString prête à être posée dans le textStorage. Les
    // offsets restent compatibles avec `highlightedRanges` (un caractère
    // markdown qui disparaît du rendu décale la longueur — on accepte ce
    // compromis : highlights stockés AVANT cette release vont être appliqués
    // sur le rendu stylé, c'est cosmétique).
    /// Convertit le markdown `source` en `NSAttributedString` stylé (titres,
    /// listes, citations, code, emphase, liens) pour l'affichage en lecture
    /// seule. Parseur ligne à ligne minimal — voir le commentaire ci-dessus.
    static func renderMarkdown(_ source: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var inCodeBlock = false
        let lines = source.components(separatedBy: "\n")

        for (idx, line) in lines.enumerated() {
            // Fenced code block toggle.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                if idx < lines.count - 1 { out.append(NSAttributedString(string: "\n")) }
                continue
            }
            if inCodeBlock {
                let para = NSMutableParagraphStyle()
                para.headIndent = 12; para.firstLineHeadIndent = 12
                out.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [
                        .font: monoFont,
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.4),
                        .paragraphStyle: para
                    ]))
                continue
            }
            // Horizontal rule.
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                let sep = NSAttributedString(
                    string: "────────────────────────────────────\n",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor.tertiaryLabelColor]
                )
                out.append(sep); continue
            }
            // Headings.
            if let (level, body) = headingLevel(line) {
                let size: CGFloat
                switch level {
                case 1: size = 22
                case 2: size = 18
                case 3: size = 15
                default: size = 13.5
                }
                let para = NSMutableParagraphStyle()
                para.paragraphSpacingBefore = level <= 2 ? 10 : 6
                para.paragraphSpacing = 4
                let attr = NSMutableAttributedString(
                    string: body + "\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: size, weight: .bold),
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: para
                    ])
                // Pour H1 et H2, ajout d'une teinte accent.
                if level <= 2 {
                    attr.addAttribute(.foregroundColor,
                                      value: NSColor.controlAccentColor,
                                      range: NSRange(location: 0, length: attr.length - 1))
                }
                out.append(attr); continue
            }
            // Blockquote.
            if line.hasPrefix("> ") {
                let body = String(line.dropFirst(2))
                let attr = renderInline(body, baseFont: NSFont.systemFont(ofSize: 13, weight: .regular))
                let mut = NSMutableAttributedString(attributedString: attr)
                mut.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .obliqueness: 0.15
                ], range: NSRange(location: 0, length: mut.length))
                mut.append(NSAttributedString(string: "\n"))
                out.append(mut); continue
            }
            // Bullet list.
            if let bullet = bulletPrefix(line) {
                let para = NSMutableParagraphStyle()
                para.headIndent = 16; para.firstLineHeadIndent = 0
                let prefix = NSAttributedString(
                    string: "  • ",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor.tertiaryLabelColor,
                                 .paragraphStyle: para])
                out.append(prefix)
                let body = renderInline(bullet, baseFont: bodyFont)
                let mut = NSMutableAttributedString(attributedString: body)
                mut.addAttribute(.paragraphStyle, value: para,
                                 range: NSRange(location: 0, length: mut.length))
                mut.append(NSAttributedString(string: "\n"))
                out.append(mut); continue
            }
            // Numbered list.
            if let (num, body) = numberedPrefix(line) {
                let para = NSMutableParagraphStyle()
                para.headIndent = 22; para.firstLineHeadIndent = 0
                let prefix = NSAttributedString(
                    string: "  \(num). ",
                    attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                 .foregroundColor: NSColor.tertiaryLabelColor,
                                 .paragraphStyle: para])
                out.append(prefix)
                let bodyAttr = renderInline(body, baseFont: bodyFont)
                let mut = NSMutableAttributedString(attributedString: bodyAttr)
                mut.addAttribute(.paragraphStyle, value: para,
                                 range: NSRange(location: 0, length: mut.length))
                mut.append(NSAttributedString(string: "\n"))
                out.append(mut); continue
            }
            // Plain line.
            let attr = renderInline(line, baseFont: bodyFont)
            let mut = NSMutableAttributedString(attributedString: attr)
            mut.append(NSAttributedString(string: "\n"))
            out.append(mut)
        }
        return out
    }

    /// Détecte un titre markdown (`#`…`######`) et retourne son niveau (1-6)
    /// avec le texte après le marqueur, ou `nil` si la ligne n'est pas un titre.
    private static func headingLevel(_ line: String) -> (Int, String)? {
        for level in (1...6).reversed() {
            let marker = String(repeating: "#", count: level) + " "
            if line.hasPrefix(marker) {
                return (level, String(line.dropFirst(marker.count)))
            }
        }
        return nil
    }

    /// Retourne le corps d'une puce markdown (`- ` ou `* `, indentation
    /// tolérée) ou `nil` si la ligne n'est pas une puce.
    private static func bulletPrefix(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
        return nil
    }

    /// Détecte une entrée de liste numérotée (`123. texte`) et retourne le
    /// numéro avec le corps, ou `nil` si la ligne ne correspond pas.
    private static func numberedPrefix(_ line: String) -> (Int, String)? {
        var i = line.startIndex
        var digits = ""
        while i < line.endIndex, line[i].isNumber { digits.append(line[i]); i = line.index(after: i) }
        guard !digits.isEmpty, i < line.endIndex, line[i] == "." else { return nil }
        let after = line.index(after: i)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return (Int(digits) ?? 1, String(line[line.index(after: after)...]))
    }

    /// Parse **bold**, *italic*, `code`, [link](url). Tout reste sur la même
    /// ligne — pas de retour à la ligne ajouté ici.
    private static func renderInline(_ s: String, baseFont: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var i = s.startIndex
        while i < s.endIndex {
            // **bold**
            if s[i...].hasPrefix("**"),
               let end = s.range(of: "**", range: s.index(i, offsetBy: 2)..<s.endIndex) {
                let body = String(s[s.index(i, offsetBy: 2)..<end.lowerBound])
                result.append(NSAttributedString(string: body, attributes: [
                    .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                ]))
                i = end.upperBound; continue
            }
            // *italic*  (single asterisk, not ** already handled)
            if s[i] == "*", !s[i...].hasPrefix("**"),
               let end = s.range(of: "*", range: s.index(after: i)..<s.endIndex) {
                let body = String(s[s.index(after: i)..<end.lowerBound])
                result.append(NSAttributedString(string: body, attributes: [
                    .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                ]))
                i = end.upperBound; continue
            }
            // `inline code`
            if s[i] == "`",
               let end = s.range(of: "`", range: s.index(after: i)..<s.endIndex) {
                let body = String(s[s.index(after: i)..<end.lowerBound])
                result.append(NSAttributedString(string: body, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 0.5, weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.4)
                ]))
                i = end.upperBound; continue
            }
            // [text](url)
            if s[i] == "[",
               let close = s.range(of: "](", range: i..<s.endIndex),
               let urlEnd = s.range(of: ")", range: close.upperBound..<s.endIndex) {
                let text = String(s[s.index(after: i)..<close.lowerBound])
                let url = String(s[close.upperBound..<urlEnd.lowerBound])
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let u = URL(string: url) { attrs[.link] = u }
                result.append(NSAttributedString(string: text, attributes: attrs))
                i = urlEnd.upperBound; continue
            }
            // Plain char.
            result.append(NSAttributedString(string: String(s[i]),
                                             attributes: [.font: baseFont]))
            i = s.index(after: i)
        }
        return result
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MeetingHighlightableTextView
        weak var textView: NSTextView?

        // Cache to enforce spec 7.3 "re-render uniquement quand la liste change".
        // Without this, every SwiftUI invalidation pass walks the whole NSTextStorage
        // even when nothing relevant changed.
        var lastAppliedRanges: [NSRange] = []
        var lastAppliedTextLength: Int = -1

        init(_ parent: MeetingHighlightableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // Always insert our action at the top of the menu, even if no
            // selection — then disable when selection is invalid.
            let item = NSMenuItem(
                title: "Ajouter au rapport manager",
                action: #selector(addToManagerReportAction(_:)),
                keyEquivalent: "M"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.representedObject = view
            let range = view.selectedRange()
            let snippet = (view.string as NSString).substring(with: range)
            let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            item.isEnabled = (range.length >= 3 && !trimmed.isEmpty)
            menu.insertItem(item, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
            return menu
        }

        /// Action du menu contextuel : récupère la sélection courante et
        /// remonte (range + texte) au parent via `onAddToManagerReport`.
        @objc func addToManagerReportAction(_ sender: NSMenuItem) {
            guard let tv = sender.representedObject as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let snippet = (tv.string as NSString).substring(with: range)
            parent.onAddToManagerReport(range, snippet)
        }
    }
}
