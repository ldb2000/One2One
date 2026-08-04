import Foundation
import AppKit

/// Walks an `NSAttributedString` and emits CommonMark + GFM task-lists.
/// Round-trip with `MarkdownParser` is the canonical contract: any markdown
/// produced by this serializer parses back to the same model state.
enum MarkdownSerializer {

    /// Émet une ligne markdown par paragraphe, sauf pour les blocs fencés qui
    /// sont émis d'un seul tenant. Le parser stocke le corps d'un bloc de code
    /// comme un unique run d'attributs contenant des `\n` ; le découper ligne à
    /// ligne produirait une paire de fences par ligne.
    /// Une éventuelle ligne vide finale est supprimée : elle reviendrait sinon
    /// sous forme de paragraphe vide supplémentaire.
    ///
    /// Une ligne vide est insérée entre deux lignes consécutives quand son
    /// absence changerait la relecture CommonMark — matrice des 49 paires
    /// ordonnées de 7 types de blocs mesurée par un test temporaire (tâche 1
    /// du plan `docs/superpowers/plans/2026-08-04-menu-slash.md`, depuis
    /// supprimé) : seules 5 paires sont à risque, cf. `needsBlankLine`. Les 44
    /// autres — dont paragraphe→bloc de code, sur lequel une fixture
    /// existante s'appuie — doivent rester collées : une ligne vide uniforme
    /// entre tout bloc les casserait sans nécessité.
    static func serialize(_ source: NSAttributedString) -> String {
        guard source.length > 0 else { return "" }
        var lines: [Line] = []
        let ns = source.string as NSString
        var cursor = 0

        while cursor < source.length {
            if let fence = fencedCodeBlock(in: source, at: cursor, ns: ns) {
                lines.append(Line(markdown: fence.markdown, boundary: .other))
                cursor = fence.nextCursor
                continue
            }

            var paragraphEnd = cursor
            while paragraphEnd < source.length, ns.character(at: paragraphEnd) != 0x0A {
                paragraphEnd += 1
            }
            if paragraphEnd > cursor {
                let range = NSRange(location: cursor, length: paragraphEnd - cursor)
                lines.append(Line(markdown: emitParagraph(source: source, range: range),
                                   boundary: boundaryKind(source: source, at: range.location)))
            } else {
                lines.append(Line(markdown: "", boundary: .other))
            }
            cursor = paragraphEnd + 1
        }

        if let last = lines.last, last.markdown.isEmpty {
            lines.removeLast()
        }

        var out: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0, needsBlankLine(before: lines[index - 1].boundary, after: line.boundary) {
                out.append("")
            }
            out.append(line.markdown)
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Block boundaries

    /// Une ligne de sortie et le type de frontière qu'elle expose à son début
    /// — juste assez de résolution pour `needsBlankLine`, pas plus : les
    /// titres (h1-h6) et les blocs de code ne participent à aucune des 5
    /// paires à risque, `.other` leur suffit à tous.
    private struct Line {
        let markdown: String
        let boundary: BoundaryKind
    }

    private enum BoundaryKind {
        case plainParagraph
        case blockquote
        case thematicBreak
        case listItem
        case other
    }

    /// Classe la frontière du bloc qui commence à `location`, à partir des
    /// attributs déjà posés par `MarkdownParser` — aucun état nouveau. Un
    /// `.mdListInfo` présent l'emporte (item de liste, quel que soit son
    /// `kind` : puce, ordonné ou tâche) ; sinon le `.mdBlockType` distingue
    /// les trois cas qui participent à une paire à risque. Lire l'attribut à
    /// `location` (début de ligne) et non ailleurs importe : sur la paire
    /// item de liste→séparateur, le `\n` qui suit l'item porte lui aussi
    /// `.mdListInfo` (posé par `MarkdownParser.emitList` sur toute la plage de
    /// l'item, retour à la ligne inclus) — le lire au milieu classerait à tort
    /// le bloc suivant comme faisant partie de la liste.
    ///
    /// Un `.mdBlockType` absent tombe dans `.other` (pas de ligne vide), sans
    /// défaut implicite vers `.paragraph` — contrairement à `emitParagraph`
    /// ou `StyleRenderer`, où ce défaut est neutre (repli d'affichage). Ici il
    /// ne l'est pas : la matrice a été mesurée sur la sortie de
    /// `MarkdownParser`, qui pose toujours `.mdBlockType` explicitement.
    /// `EditorTextViewPasteTests` construit du storage à la main (texte tapé
    /// avant tout restylage, cf. son commentaire sur `ShortcutDetector`) sans
    /// cet attribut ; y défauter vers `.plainParagraph` insérerait une ligne
    /// vide parasite entre du texte inline et une image collée juste après,
    /// sur la seule foi d'une absence d'attribut plutôt que d'une paire
    /// mesurée comme à risque.
    private static func boundaryKind(source: NSAttributedString, at location: Int) -> BoundaryKind {
        if source.attribute(.mdListInfo, at: location, effectiveRange: nil) is ListInfo {
            return .listItem
        }
        guard let blockType = source.attribute(.mdBlockType, at: location, effectiveRange: nil) as? BlockType else {
            return .other
        }
        switch blockType {
        case .paragraph: return .plainParagraph
        case .blockquote: return .blockquote
        case .thematicBreak: return .thematicBreak
        default: return .other
        }
    }

    /// Les 5 paires mesurées où l'absence de ligne vide change la relecture
    /// CommonMark :
    /// - paragraphe→paragraphe : fusionnent en un seul paragraphe (soft break) ;
    /// - paragraphe→séparateur : le paragraphe devient un titre H2 Setext, le
    ///   séparateur est avalé — le pire cas, un changement de type de bloc ;
    /// - citation→paragraphe et citation→citation : continuation paresseuse de
    ///   blockquote, absorbés/fusionnés ;
    /// - item de liste→paragraphe : même continuation paresseuse, le
    ///   paragraphe est absorbé dans l'item.
    /// Toute autre paire est sûre sans ligne vide — notamment item de
    /// liste→item de liste, volontairement absent d'ici : deux items restent
    /// distincts même collés, et une ligne vide entre eux romprait leur
    /// appartenance à une même liste visuelle sans que rien ne l'exige.
    private static func needsBlankLine(before: BoundaryKind, after: BoundaryKind) -> Bool {
        switch (before, after) {
        case (.plainParagraph, .plainParagraph): return true
        case (.plainParagraph, .thematicBreak): return true
        case (.blockquote, .plainParagraph): return true
        case (.blockquote, .blockquote): return true
        case (.listItem, .plainParagraph): return true
        default: return false
        }
    }

    /// Si un bloc de code commence à `cursor`, renvoie son markdown complet et
    /// la position juste après le bloc — saut de ligne de séparation compris,
    /// celui que `MarkdownParser.appendNewline` ajoute après chaque bloc.
    /// Renvoie `nil` quand `cursor` n'est pas sur un bloc de code.
    private static func fencedCodeBlock(in source: NSAttributedString,
                                        at cursor: Int,
                                        ns: NSString) -> (markdown: String, nextCursor: Int)? {
        var effective = NSRange(location: NSNotFound, length: 0)
        let searchRange = NSRange(location: cursor, length: source.length - cursor)
        let block = source.attribute(.mdBlockType,
                                     at: cursor,
                                     longestEffectiveRange: &effective,
                                     in: searchRange) as? BlockType
        guard block == .codeBlock, effective.length > 0 else { return nil }

        let language = source.attribute(.mdCodeLanguage, at: cursor, effectiveRange: nil) as? String ?? ""
        // Un Retour tapé en fin de bloc hérite les attributs de frappe du run
        // précédent, donc son `\n` peut se retrouver inclus dans `effective`.
        // On ne retire que les `\n` de fin : ceux du début ont déjà été
        // retirés par le parser, et les retirer ici n'aurait pas de sens.
        let body = trimmingTrailingNewlines(ns.substring(with: effective))
        let fence = String(repeating: "`", count: fenceLength(for: body))
        var next = effective.location + effective.length
        if next < source.length, ns.character(at: next) == 0x0A {
            next += 1
        }
        return ("\(fence)\(language)\n\(body)\n\(fence)", next)
    }

    /// Longueur de fence à utiliser pour envelopper `body` : au moins 3
    /// backticks, et toujours strictement supérieure à la plus longue suite
    /// de backticks présente dans le corps — sinon une fence interne se
    /// refermerait prématurément et le contenu serait perdu au reparse.
    private static func fenceLength(for body: String) -> Int {
        var longestRun = 0
        var currentRun = 0
        for character in body {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return max(3, longestRun + 1)
    }

    /// Retire les `\n` de fin de `body` (uniquement ceux de fin, pas ceux de
    /// début) : un bloc de code dont le run d'attributs englobe son saut de
    /// ligne final donnerait sinon une ligne vide parasite avant la fence
    /// fermante.
    private static func trimmingTrailingNewlines(_ body: String) -> String {
        var result = body
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    // MARK: - Paragraph

    /// Emits one paragraph's markdown. A `ListInfo` attribute wins over the
    /// block type and produces a list-item prefix; otherwise the `BlockType`
    /// selects the syntax: `h1`-`h6` → `#`…`######`, `blockquote` → `>`,
    /// `thematicBreak` → `---`, `paragraph` → inline text as-is. `codeBlock`
    /// is handled upstream by `fencedCodeBlock` and is unreachable here in
    /// practice — see the case below.
    private static func emitParagraph(source: NSAttributedString, range: NSRange) -> String {
        let blockType = source.attribute(.mdBlockType, at: range.location, effectiveRange: nil)
            as? BlockType ?? .paragraph
        let listInfo = source.attribute(.mdListInfo, at: range.location, effectiveRange: nil)
            as? ListInfo

        let inline = emitInline(source: source, range: range)

        if let info = listInfo {
            return prefix(for: info) + inline
        }
        switch blockType {
        case .h1: return "# " + inline
        case .h2: return "## " + inline
        case .h3: return "### " + inline
        case .h4: return "#### " + inline
        case .h5: return "##### " + inline
        case .h6: return "###### " + inline
        case .blockquote: return "> " + inline
        case .codeBlock:
            // Inatteignable en pratique : `fencedCodeBlock` teste déjà
            // `.mdBlockType` à `range.location` — toujours un début de ligne,
            // la même position que celle-ci — avant que `emitParagraph` ne
            // soit appelé. `inline` n'est qu'un repli défensif si cet
            // invariant venait à être violé.
            return inline
        case .thematicBreak:
            return "---"
        case .paragraph:
            return inline
        }
    }

    /// Builds the list-item prefix. Indentation is two spaces per nesting
    /// `level` (clamped to >= 0); the marker depends on the kind: `-` for
    /// bullets, `N. ` for ordered items (defaulting the ordinal to 1), and
    /// `- [x]`/`- [ ]` for task items.
    private static func prefix(for info: ListInfo) -> String {
        let indent = String(repeating: "  ", count: max(0, info.level))
        switch info.kind {
        case .bullet:
            return "\(indent)- "
        case .ordered:
            return "\(indent)\(info.index ?? 1). "
        case .task:
            return "\(indent)- [\(info.checked == true ? "x" : " ")] "
        }
    }

    // MARK: - Inline

    /// Emits the inline markup for a range. Inline code wins exclusively (its
    /// content is emitted verbatim between backticks) — the `U+FFFC`
    /// placeholder characters are stripped from it first, since a code span
    /// (backticks = literal text) has no representation for an image and a
    /// run can carry both `mdInlineCode` and `mdImageURL` at once (the parser
    /// never attaches `mdInlineCode` to an `InlineCode` node's children — see
    /// `MarkdownParser`'s `InlineCode` case — so this only happens through a
    /// layout built by hand or by `NSTextView` typingAttributes, same as
    /// below). Otherwise emphasis markers are layered from the outside in —
    /// bold, then italic, then strikethrough — so `pre` accumulates
    /// left-to-right and `post` is built in mirror order; a link, if present,
    /// wraps the body inside that emphasis. The body itself is either the
    /// run's text run through `MarkdownEscaping.escapeInline`, or — when the
    /// run carries `mdImageURL` — the result of
    /// `expandingImagePlaceholders(in:url:alt:)`, so that an image wrapped in
    /// bold/italic/strikethrough/a link round-trips with its wrapping intact
    /// instead of the image markup replacing it outright.
    private static func emitInline(source: NSAttributedString, range: NSRange) -> String {
        var out = ""
        source.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            let raw = (source.string as NSString).substring(with: run)
            if (attrs[.mdInlineCode] as? Bool) == true {
                out.append("`")
                out.append(raw.filter { $0 != "\u{FFFC}" })
                out.append("`")
                return
            }
            var pre = ""
            var post = ""
            if (attrs[.mdBold] as? Bool) == true { pre += "**"; post = "**" + post }
            if (attrs[.mdItalic] as? Bool) == true { pre += "_"; post = "_" + post }
            if (attrs[.mdStrikethrough] as? Bool) == true { pre += "~~"; post = "~~" + post }

            let body: String
            if let url = attrs[.mdImageURL] as? URL {
                let alt = (attrs[.mdImageAlt] as? String) ?? ""
                body = expandingImagePlaceholders(in: raw, url: url, alt: alt)
            } else {
                body = MarkdownEscaping.escapeInline(raw)
            }

            if let url = attrs[.mdLink] as? URL {
                out.append(pre)
                out.append("[")
                out.append(body)
                out.append("](")
                out.append(MarkdownEscaping.escapeURL(url))
                out.append(")")
                out.append(post)
            } else {
                out.append(pre)
                out.append(body)
                out.append(post)
            }
        }
        return out
    }

    /// Émet le texte d'un run portant `mdImageURL`/`mdImageAlt` : chaque
    /// caractère « object replacement » (`U+FFFC`) devient `![alt](url)`,
    /// le reste passe par l'échappement inline normal. Un run peut mélanger
    /// les deux : dans un `NSTextView`, du texte tapé juste après une image
    /// hérite des `typingAttributes` du caractère précédent, donc de
    /// `mdImageURL`, sans être lui-même une image.
    private static func expandingImagePlaceholders(in raw: String, url: URL, alt: String) -> String {
        let imageMarkup = "![\(MarkdownEscaping.escapeInline(alt))](\(MarkdownEscaping.escapeURL(url)))"
        var out = ""
        var textBuffer = ""
        for character in raw {
            if character == "\u{FFFC}" {
                if !textBuffer.isEmpty {
                    out.append(MarkdownEscaping.escapeInline(textBuffer))
                    textBuffer = ""
                }
                out.append(imageMarkup)
            } else {
                textBuffer.append(character)
            }
        }
        if !textBuffer.isEmpty {
            out.append(MarkdownEscaping.escapeInline(textBuffer))
        }
        return out
    }
}
