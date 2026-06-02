import Foundation
import Markdown

/// Convertit du markdown CommonMark + GFM (+ block directives `:::name`)
/// en HTML body. Le HTML produit ne contient PAS le wrapper `<html>` /
/// `<body>` / `<style>` — `ReportHTMLBuilder` s'en charge.
///
/// Directives supportées :
/// - `:::vigilance` → `<div class="callout vigilance">…</div>`
/// - `:::reserve`   → `<div class="callout reserve">…</div>`
/// Autres directives → ignorées (children rendus comme markdown standard).
enum MarkdownToHTMLRenderer {

    /// Point d'entrée : convertit le markdown `source` en fragment HTML
    /// (sans wrapper `<html>`/`<body>`). Retourne `""` si `source` est vide.
    static func render(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let preprocessed = preprocessDirectives(trimmed)
        let doc = Document(parsing: preprocessed, options: [.parseBlockDirectives])
        var visitor = HTMLVisitor()
        return visitor.renderChildren(doc.children)
    }

    /// Convertit la syntaxe d'auteur `:::name\n...\n:::` (style MyST/Pandoc,
    /// produite par le LLM) en `@name {\n...\n}` que swift-markdown reconnaît
    /// nativement comme `BlockDirective`. Parcours ligne-par-ligne (plutôt
    /// que regex) pour rester robuste aux directives mal fermées.
    private static func preprocessDirectives(_ source: String) -> String {
        // Regex : :::name (sur sa propre ligne) … ::: (sur sa propre ligne)
        // On utilise une approche ligne-par-ligne pour robustesse.
        var lines = source.components(separatedBy: "\n")
        var out: [String] = []
        out.reserveCapacity(lines.count)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix(":::") && stripped != ":::" {
                // Début d'une directive
                let name = String(stripped.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                out.append("@\(name) {")
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    let innerStripped = inner.trimmingCharacters(in: .whitespaces)
                    if innerStripped == ":::" {
                        out.append("}")
                        i += 1
                        break
                    } else {
                        out.append(inner)
                        i += 1
                    }
                }
            } else {
                out.append(line)
                i += 1
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Visitor

    /// Parcourt récursivement l'arbre swift-markdown et émet le HTML
    /// correspondant. `mutating` car l'émission inline/bloc s'appelle
    /// mutuellement ; aucun état persistant n'est conservé entre deux `render`.
    private struct HTMLVisitor {

        mutating func renderChildren(_ children: some Sequence<Markup>) -> String {
            var out = ""
            for child in children {
                out += render(child)
            }
            return out
        }

        mutating func render(_ markup: Markup) -> String {
            switch markup {
            case let heading as Heading:
                let inner = renderInlineChildren(heading)
                return "<h\(heading.level)>\(inner)</h\(heading.level)>\n"
            case let paragraph as Paragraph:
                return "<p>\(renderInlineChildren(paragraph))</p>\n"
            case let bq as BlockQuote:
                return "<blockquote>\n\(renderChildren(bq.children))</blockquote>\n"
            case let list as UnorderedList:
                return renderList(list.children, ordered: false)
            case let list as OrderedList:
                return renderList(list.children, ordered: true)
            case let item as ListItem:
                let inner = renderChildren(item.children).trimmingCharacters(in: .newlines)
                // Si l'item ne contient qu'un seul paragraphe, déballer les balises <p>.
                let unwrapped = unwrapSingleParagraph(inner)
                return "<li>\(unwrapped)</li>\n"
            case let cb as CodeBlock:
                return "<pre><code>\(escape(cb.code))</code></pre>\n"
            case let table as Table:
                return renderTable(table)
            case is ThematicBreak:
                return "<hr/>\n"
            case let directive as BlockDirective:
                return renderDirective(directive)
            case let html as HTMLBlock:
                return html.rawHTML
            default:
                return renderChildren(markup.children)
            }
        }

        mutating func renderList(_ items: some Sequence<Markup>, ordered: Bool) -> String {
            let tag = ordered ? "ol" : "ul"
            var out = "<\(tag)>\n"
            for item in items { out += render(item) }
            out += "</\(tag)>\n"
            return out
        }

        mutating func renderTable(_ table: Table) -> String {
            var out = "<table>\n"
            var headerCells = ""
            for cell in table.head.cells {
                headerCells += "<th>\(renderInlineChildren(cell))</th>"
            }
            out += "<thead><tr>" + headerCells + "</tr></thead>\n"
            out += "<tbody>\n"
            for row in table.body.rows {
                var cells = ""
                for cell in row.cells {
                    cells += "<td>\(renderInlineChildren(cell))</td>"
                }
                out += "<tr>" + cells + "</tr>\n"
            }
            out += "</tbody>\n</table>\n"
            return out
        }

        /// Rend une directive bloc. `vigilance` et `reserve` produisent un
        /// `<div class="callout …">` ; toute autre directive est ignorée et
        /// seuls ses enfants sont rendus (fallback markdown standard).
        mutating func renderDirective(_ directive: BlockDirective) -> String {
            let name = directive.name.lowercased()
            let inner = renderChildren(directive.children)
            switch name {
            case "vigilance":
                return "<div class=\"callout vigilance\">\n\(inner)</div>\n"
            case "reserve":
                return "<div class=\"callout reserve\">\n\(inner)</div>\n"
            default:
                return inner
            }
        }

        mutating func renderInlineChildren(_ parent: Markup) -> String {
            var out = ""
            for child in parent.children {
                out += renderInlineNode(child)
            }
            return out
        }

        mutating func renderInlineNode(_ markup: Markup) -> String {
            switch markup {
            case let text as Text:
                return escape(text.string)
            case let strong as Strong:
                return "<strong>\(renderInlineChildren(strong))</strong>"
            case let emph as Emphasis:
                return "<em>\(renderInlineChildren(emph))</em>"
            case let code as InlineCode:
                return "<code>\(escape(code.code))</code>"
            case let link as Markdown.Link:
                let dest = link.destination ?? ""
                return "<a href=\"\(escape(dest))\">\(renderInlineChildren(link))</a>"
            case is LineBreak, is SoftBreak:
                return " "
            case let html as InlineHTML:
                return escape(html.rawHTML)
            default:
                return renderInlineChildren(markup)
            }
        }

        private func unwrapSingleParagraph(_ s: String) -> String {
            // Si la chaîne commence par <p> et termine par </p> sans autre <p> à l'intérieur,
            // déballer pour avoir un <li>texte</li> propre.
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("<p>"),
                  trimmed.hasSuffix("</p>") else { return s }
            let middle = String(trimmed.dropFirst(3).dropLast(4))
            if middle.contains("<p>") { return s }
            return middle
        }

        /// Échappe les 5 caractères dangereux en HTML (`& < > " '`) pour
        /// éviter toute injection depuis le texte source dans le rapport.
        private func escape(_ s: String) -> String {
            var out = ""
            out.reserveCapacity(s.count)
            for c in s {
                switch c {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "\"": out += "&quot;"
                case "'": out += "&#39;"
                default: out.append(c)
                }
            }
            return out
        }
    }
}
