# Rapport — rendu stylé HTML/CSS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduire le style visuel d'un compte-rendu professionnel (navy + numbered badges + callouts cream + tableaux navy/cream alternés) pour le rendu in-app (WKWebView), l'export PDF et l'export mail/Outlook, avec édition markdown préservée.

**Architecture:** Pipeline unique markdown → HTML thémé. Source = `meeting.summary` markdown. Builder assemble header (depuis Meeting) + body markdown rendu + tables Décisions/Actions auto-injectées (dédoublonnées par H2). Trois cibles consomment le même HTML : WKWebView (preview), `createPDF` (export PDF), AppleScript Mail/Outlook (existant). swift-markdown `parseBlockDirectives` gère nativement `:::vigilance` / `:::reserve`.

**Tech Stack:** Swift 6, SwiftUI, swift-markdown (déjà linké), WebKit / WKWebView, AppKit.

---

## File map

| Path | Responsabilité |
|---|---|
| `OneToOne/Services/Report/ReportThemeCSS.swift` (new) | Constante `static let css: String` avec tout le CSS thémé |
| `OneToOne/Services/Report/MarkdownToHTMLRenderer.swift` (new) | swift-markdown `MarkupVisitor` → HTML body, gère `BlockDirective` pour callouts |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` (new) | Assemble eyebrow + h1 + meta + body + dédoublonne H2 + injecte Décisions/Actions |
| `OneToOne/Views/Meeting/MeetingReportPreview.swift` (new) | `NSViewRepresentable` autour de WKWebView (charge HTML, désactive focus clavier) |
| `OneToOne/Views/MeetingView.swift` (modify) | Onglet Rapport : toggle Aperçu (WKWebView) / Éditer (MarkdownEditorView) |
| `OneToOne/Services/ExportService.swift` (modify) | `buildMeetingHTML` délègue à `ReportHTMLBuilder` ; `exportMeetingPDF` utilise WKWebView createPDF |
| `Tests/MarkdownToHTMLRendererTests.swift` (new) | Tests parsing : headings, blockquote, table, directive vigilance/reserve |
| `Tests/ReportHTMLBuilderTests.swift` (new) | Tests détection doublon H2 + injection Décisions/Actions |

Total : 4 nouveaux services/vues, 2 nouveaux tests, 2 modifications.

**Note types existants** (audit §16 du spec) :
- `Meeting.summary / title / date / kind / participants / project / tasks / decisions / liveNotes / rawTranscript / durationSeconds` ✓
- `Project.code / name` ✓
- `Collaborator.name` ✓
- `ActionTask.title / dueDate / collaborator / unresolvedAssigneeName` ✓
- `ReportTemplate.kind.label / preamble` ✓
- `swift-markdown` `import Markdown` + `Document(parsing:options: [.parseBlockDirectives])` ✓
- `WKWebView` déjà importé dans `MermaidView.swift` ✓
- `MarkdownEditorView(text: Binding<String>, textViewID: String)` ✓
- `ExportService.composeMeetingMail` / `buildMeetingHTML` / `exportMeetingPDF` existent ✓

---

### Task 1: ReportThemeCSS — constante CSS

**Files:**
- Create: `OneToOne/Services/Report/ReportThemeCSS.swift`

- [ ] **Step 1: Créer le fichier**

```swift
import Foundation

/// CSS thémé pour le rendu HTML du compte-rendu (in-app preview, PDF, mail).
/// Inliné dans un bloc `<style>` par `ReportHTMLBuilder`. Compatible Mail.app
/// et Outlook (rendent correctement les `<style>` block via AppleScript).
enum ReportThemeCSS {

    static let css: String = """
    :root {
      --navy: #1a2a44;
      --navy-dark: #0d1f3a;
      --cream: #fbf4e3;
      --cream-border: #e8d9b8;
      --gray-row: #f5f3ee;
      --text: #2d2d2d;
      --muted: #7a7a7a;
      --accent-orange: #e89a3c;
      --accent-orange-dark: #b07020;
    }
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, "SF Pro Text", "Inter", Helvetica, sans-serif;
      color: var(--text);
      line-height: 1.55;
      counter-reset: section;
      max-width: 760px;
      margin: 0 auto;
      padding: 24px 32px;
      font-size: 13px;
    }
    .header-rule {
      height: 4px;
      background: var(--navy);
      margin-bottom: 18px;
    }
    .eyebrow {
      font-size: 11px;
      letter-spacing: 0.18em;
      color: var(--navy);
      font-weight: 600;
      margin-bottom: 6px;
    }
    h1 {
      font-size: 28px;
      color: var(--navy-dark);
      line-height: 1.2;
      margin: 6px 0 4px;
      font-weight: 700;
    }
    .subtitle {
      color: var(--muted);
      font-size: 14px;
      font-weight: 600;
      margin: 0 0 18px;
    }
    table.meta {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 28px;
    }
    table.meta th {
      background: var(--gray-row);
      text-align: left;
      width: 160px;
      padding: 10px 12px;
      font-size: 11px;
      letter-spacing: 0.06em;
      color: var(--navy);
      font-weight: 700;
      vertical-align: top;
    }
    table.meta td {
      padding: 10px 12px;
      background: var(--gray-row);
      vertical-align: top;
    }
    h2 {
      counter-increment: section;
      font-size: 16px;
      color: var(--navy-dark);
      margin: 22px 0 10px;
      padding-bottom: 6px;
      border-bottom: 1.5px solid var(--navy);
      font-weight: 700;
    }
    h2::before {
      content: counter(section);
      display: inline-block;
      background: var(--navy);
      color: white;
      font-size: 12px;
      font-weight: 700;
      padding: 2px 8px;
      margin-right: 10px;
      border-radius: 2px;
      vertical-align: 2px;
    }
    h3 {
      font-size: 14px;
      color: var(--navy-dark);
      margin: 14px 0 6px;
      font-weight: 700;
    }
    p { margin: 6px 0 10px; }
    table:not(.meta) {
      width: 100%;
      border-collapse: collapse;
      margin: 8px 0 18px;
    }
    table:not(.meta) thead th {
      background: var(--navy);
      color: white;
      text-align: left;
      padding: 8px 10px;
      font-size: 11px;
      letter-spacing: 0.06em;
      font-weight: 700;
    }
    table:not(.meta) tbody td {
      padding: 8px 10px;
      border-bottom: 1px solid var(--cream-border);
      vertical-align: top;
    }
    table:not(.meta) tbody tr:nth-child(even) td {
      background: var(--gray-row);
    }
    blockquote {
      background: var(--cream);
      border-radius: 3px;
      padding: 12px 14px;
      margin: 12px 0;
      font-size: 13px;
      border-left: 3px solid var(--cream-border);
    }
    blockquote p { margin: 0; }
    .callout {
      background: var(--cream);
      border-radius: 3px;
      padding: 12px 14px;
      margin: 12px 0;
      font-size: 13px;
    }
    .callout::before {
      display: inline;
      font-weight: 700;
      margin-right: 6px;
    }
    .callout.vigilance::before {
      content: "● Point de vigilance.";
      color: var(--accent-orange-dark);
    }
    .callout.reserve::before {
      content: "● Réserve exprimée.";
      color: var(--muted);
    }
    .callout p { display: inline; margin: 0; }
    .callout p + p { display: block; margin-top: 6px; }
    ul { padding-left: 22px; margin: 6px 0 10px; }
    ol { padding-left: 22px; margin: 6px 0 10px; }
    li { margin-bottom: 4px; }
    strong { color: var(--navy-dark); font-weight: 700; }
    em { color: var(--muted); font-style: italic; }
    code {
      background: var(--gray-row);
      padding: 1px 5px;
      border-radius: 2px;
      font-family: "SF Mono", "Menlo", monospace;
      font-size: 12px;
    }
    """
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne && swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/Report/ReportThemeCSS.swift
git commit -m "feat(report-styling): ReportThemeCSS — constante CSS navy + cream + callouts"
```

---

### Task 2: MarkdownToHTMLRenderer (TDD)

**Files:**
- Create: `OneToOne/Services/Report/MarkdownToHTMLRenderer.swift`
- Create: `Tests/MarkdownToHTMLRendererTests.swift`

- [ ] **Step 1: Écrire les tests failing**

Dans `Tests/MarkdownToHTMLRendererTests.swift` :

```swift
import XCTest
@testable import OneToOne

final class MarkdownToHTMLRendererTests: XCTestCase {

    func test_headings() {
        let html = MarkdownToHTMLRenderer.render("## Section 1\n\n### Sub")
        XCTAssertTrue(html.contains("<h2>Section 1</h2>"))
        XCTAssertTrue(html.contains("<h3>Sub</h3>"))
    }

    func test_paragraph() {
        let html = MarkdownToHTMLRenderer.render("Bonjour le monde.")
        XCTAssertTrue(html.contains("<p>Bonjour le monde.</p>"))
    }

    func test_emphasis() {
        let html = MarkdownToHTMLRenderer.render("Texte avec **gras** et *italic*.")
        XCTAssertTrue(html.contains("<strong>gras</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
    }

    func test_unorderedList() {
        let html = MarkdownToHTMLRenderer.render("- item un\n- item deux")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>item un</li>"))
        XCTAssertTrue(html.contains("<li>item deux</li>"))
    }

    func test_blockquote() {
        let html = MarkdownToHTMLRenderer.render("> Une note importante.")
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("Une note importante."))
    }

    func test_table() {
        let md = """
        | Col A | Col B |
        |---|---|
        | a1 | b1 |
        | a2 | b2 |
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<thead>"))
        XCTAssertTrue(html.contains("<th>Col A</th>"))
        XCTAssertTrue(html.contains("<td>a1</td>"))
    }

    func test_vigilanceDirective() {
        let md = """
        :::vigilance
        Attention au cas PEGA.
        :::
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<div class=\"callout vigilance\">"))
        XCTAssertTrue(html.contains("Attention au cas PEGA."))
    }

    func test_reserveDirective() {
        let md = """
        :::reserve
        Sujet en suspens.
        :::
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<div class=\"callout reserve\">"))
        XCTAssertTrue(html.contains("Sujet en suspens."))
    }

    func test_htmlEscaping() {
        let html = MarkdownToHTMLRenderer.render("Texte avec <script>alert('x')</script>")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;") || html.contains("alert"))
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter MarkdownToHTMLRendererTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'MarkdownToHTMLRenderer' in scope`.

- [ ] **Step 3: Implémenter le renderer**

Dans `OneToOne/Services/Report/MarkdownToHTMLRenderer.swift` :

```swift
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

    static func render(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let doc = Document(parsing: trimmed, options: [.parseBlockDirectives])
        var visitor = HTMLVisitor()
        return visitor.renderChildren(doc.children)
    }

    // MARK: - Visitor

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
                let inner = renderInline(heading.children)
                return "<h\(heading.level)>\(inner)</h\(heading.level)>\n"
            case let paragraph as Paragraph:
                return "<p>\(renderInline(paragraph.children))</p>\n"
            case let bq as BlockQuote:
                return "<blockquote>\n\(renderChildren(bq.children))</blockquote>\n"
            case let list as UnorderedList:
                return renderList(list.children, ordered: false)
            case let list as OrderedList:
                return renderList(list.children, ordered: true)
            case let item as ListItem:
                return "<li>\(renderChildren(item.children).trimmingCharacters(in: .newlines))</li>\n"
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
            // Header row
            let headerCells = table.head.cells.map { cell in
                "<th>\(renderInline(cell.children))</th>"
            }
            out += "<thead><tr>" + headerCells.joined() + "</tr></thead>\n"
            // Body rows
            out += "<tbody>\n"
            for row in table.body.rows {
                let cells = row.cells.map { cell in
                    "<td>\(renderInline(cell.children))</td>"
                }
                out += "<tr>" + cells.joined() + "</tr>\n"
            }
            out += "</tbody>\n</table>\n"
            return out
        }

        mutating func renderDirective(_ directive: BlockDirective) -> String {
            let name = directive.name.lowercased()
            switch name {
            case "vigilance":
                return "<div class=\"callout vigilance\">\n\(renderChildren(directive.children))</div>\n"
            case "reserve":
                return "<div class=\"callout reserve\">\n\(renderChildren(directive.children))</div>\n"
            default:
                // Directive inconnue → rend les enfants comme markdown standard.
                return renderChildren(directive.children)
            }
        }

        mutating func renderInline(_ children: some Sequence<InlineMarkup>) -> String {
            var out = ""
            for child in children {
                out += renderInlineNode(child)
            }
            return out
        }

        mutating func renderInlineNode(_ markup: InlineMarkup) -> String {
            switch markup {
            case let text as Text:
                return escape(text.string)
            case let strong as Strong:
                return "<strong>\(renderInline(strong.inlineChildren))</strong>"
            case let emph as Emphasis:
                return "<em>\(renderInline(emph.inlineChildren))</em>"
            case let code as InlineCode:
                return "<code>\(escape(code.code))</code>"
            case let link as Markdown.Link:
                let dest = link.destination ?? ""
                return "<a href=\"\(escape(dest))\">\(renderInline(link.inlineChildren))</a>"
            case is LineBreak, is SoftBreak:
                return " "
            case let html as InlineHTML:
                return html.rawHTML
            default:
                var out = ""
                for child in markup.children {
                    if let inline = child as? InlineMarkup {
                        out += renderInlineNode(inline)
                    }
                }
                return out
            }
        }

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

// Helper pour itérer sur les enfants inline (swift-markdown a `InlineContainer`).
private extension Markup {
    var inlineChildren: [InlineMarkup] {
        children.compactMap { $0 as? InlineMarkup }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter MarkdownToHTMLRendererTests 2>&1 | tail -15
```
Expected: PASS 9/9. Si un test rate sur les directives, vérifier que `BlockDirective` est bien parsé (option `.parseBlockDirectives` activée).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Report/MarkdownToHTMLRenderer.swift Tests/MarkdownToHTMLRendererTests.swift
git commit -m "feat(report-styling): MarkdownToHTMLRenderer (swift-markdown → HTML + directives vigilance/reserve)"
```

---

### Task 3: ReportHTMLBuilder (TDD)

**Files:**
- Create: `OneToOne/Services/Report/ReportHTMLBuilder.swift`
- Create: `Tests/ReportHTMLBuilderTests.swift`

- [ ] **Step 1: Écrire les tests failing**

Dans `Tests/ReportHTMLBuilderTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

final class ReportHTMLBuilderTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_eyebrowContainsKindAndConfidential() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Test", date: Date())
        meeting.summary = "Contenu de test."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("CONFIDENTIEL"))
        XCTAssertTrue(html.contains("Test"))
    }

    @MainActor
    func test_titleEscaped() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Titre <script>", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()
        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("<h1>Titre <script>"))
        XCTAssertTrue(html.contains("Titre &lt;script&gt;"))
    }

    @MainActor
    func test_metaParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)
        let meeting = Meeting(title: "T", date: Date())
        meeting.participants = [alice, bob]
        meeting.summary = "x"
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("Bob MARTIN"))
    }

    @MainActor
    func test_injectsDecisionsTable() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Contexte\n\nLa séance vise…"
        meeting.decisions = ["Catalogue par exception", "Tri amont"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Relevé de décisions"))
        XCTAssertTrue(html.contains("Catalogue par exception"))
        XCTAssertTrue(html.contains("Tri amont"))
        XCTAssertTrue(html.contains("D1"))
        XCTAssertTrue(html.contains("D2"))
    }

    @MainActor
    func test_injectsActionsFromTasks() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "x"
        ctx.insert(meeting)
        let task = ActionTask(title: "Préparer slides", dueDate: nil)
        task.collaborator = alice
        task.meeting = meeting
        ctx.insert(task)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Plan d'actions"))
        XCTAssertTrue(html.contains("Préparer slides"))
        XCTAssertTrue(html.contains("Alice DUPONT"))
        XCTAssertTrue(html.contains("A1"))
    }

    @MainActor
    func test_noInjectionWhenAllEmpty() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = "## Section unique\n\nContenu."
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertFalse(html.contains("Relevé de décisions"))
        XCTAssertFalse(html.contains("Plan d'actions"))
    }

    @MainActor
    func test_dedupeH2_remplaceDecisionsLLM() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "T", date: Date())
        meeting.summary = """
        ## Contexte
        Texte.

        ## Décisions
        Le LLM a écrit du texte ici qui doit être remplacé.
        """
        meeting.decisions = ["Canonique 1"]
        ctx.insert(meeting)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
        XCTAssertTrue(html.contains("Canonique 1"))
        XCTAssertFalse(html.contains("Le LLM a écrit du texte ici qui doit être remplacé."))
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter ReportHTMLBuilderTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'ReportHTMLBuilder' in scope`.

- [ ] **Step 3: Implémenter le builder**

Dans `OneToOne/Services/Report/ReportHTMLBuilder.swift` :

```swift
import Foundation
import SwiftData

/// Assemble un HTML complet (head + style + body) pour un rapport de réunion.
/// Utilisé par :
/// - `MeetingReportPreview` (WKWebView preview)
/// - `ExportService.exportMeetingPDF` (createPDF)
/// - `ExportService.buildMeetingHTML` (mail / Outlook via AppleScript)
@MainActor
enum ReportHTMLBuilder {

    static func build(meeting: Meeting,
                      template: ReportTemplate?,
                      includeTranscript: Bool) -> String {
        let eyebrow = makeEyebrow(meeting: meeting, template: template)
        let title = escape(meeting.title.isEmpty ? "Réunion" : meeting.title)
        let subtitle = makeSubtitle(meeting: meeting, template: template)
        let meta = makeMetaTable(meeting: meeting)

        // Body markdown → HTML.
        let bodyHTML = MarkdownToHTMLRenderer.render(meeting.summary)

        // Injection / dédoublonnage Décisions + Actions.
        var assembled = dedupeAndInject(
            bodyHTML: bodyHTML,
            decisions: meeting.decisions,
            tasks: meeting.tasks
        )

        // Transcript en annexe optionnel.
        if includeTranscript {
            let tx = meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tx.isEmpty {
                assembled += "<h2>Transcription complète</h2>\n"
                assembled += "<div class=\"transcript\">\(escape(tx).replacingOccurrences(of: "\n", with: "<br/>\n"))</div>\n"
            }
        }

        return """
        <!DOCTYPE html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <style>
        \(ReportThemeCSS.css)
        </style>
        </head>
        <body>
        <div class="header-rule"></div>
        <div class="eyebrow">\(eyebrow)</div>
        <h1>\(title)</h1>
        <p class="subtitle">\(subtitle)</p>
        \(meta)
        \(assembled)
        </body>
        </html>
        """
    }

    // MARK: - Eyebrow / subtitle / meta

    private static func makeEyebrow(meeting: Meeting, template: ReportTemplate?) -> String {
        var parts: [String] = []
        if let t = template {
            parts.append(t.kind.label.uppercased())
        } else {
            parts.append("COMPTE-RENDU")
        }
        if let code = meeting.project?.code, !code.isEmpty {
            parts.append(escape(code))
        }
        parts.append("CONFIDENTIEL — USAGE INTERNE")
        return parts.joined(separator: " · ")
    }

    private static func makeSubtitle(meeting: Meeting, template: ReportTemplate?) -> String {
        let kindLabel = template?.kind.label ?? meeting.kind.label
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy 'à' HH:mm"
        return "\(escape(kindLabel)) — \(fmt.string(from: meeting.date))"
    }

    private static func makeMetaTable(meeting: Meeting) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy 'à' HH:mm"
        var dateCell = fmt.string(from: meeting.date)
        if meeting.durationSeconds > 0 {
            let mins = Int(meeting.durationSeconds / 60)
            let h = mins / 60, m = mins % 60
            let dur = h > 0 ? "(durée \(h)h\(String(format: "%02d", m)))" : "(durée \(m) min)"
            dateCell += " \(dur)"
        }
        let participants = meeting.participants
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { escape($0.name) }
            .joined(separator: ", ")
        let participantsCell = participants.isEmpty ? "—" : participants

        let objet = makeObjet(meeting: meeting)

        return """
        <table class="meta">
        <tr><th>OBJET</th><td>\(objet)</td></tr>
        <tr><th>DATE</th><td>\(escape(dateCell))</td></tr>
        <tr><th>PARTICIPANTS</th><td>\(participantsCell)</td></tr>
        </table>
        """
    }

    private static func makeObjet(meeting: Meeting) -> String {
        // Première phrase du markdown (avant le premier ". " ou "\n").
        let summary = meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return escape(meeting.title.isEmpty ? "—" : meeting.title) }
        // Skip leading headings / lists.
        let lines = summary.components(separatedBy: "\n")
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("#") || t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix(":::") { continue }
            // Premier paragraphe texte → première phrase.
            if let dot = t.firstIndex(of: ".") {
                return escape(String(t[..<dot]) + ".")
            }
            return escape(t)
        }
        return escape(meeting.title.isEmpty ? "—" : meeting.title)
    }

    // MARK: - Dedupe & inject Décisions / Actions

    private static let decisionsTitleAliases: Set<String> = [
        "decisions",
        "releve de decisions",
        "relevé de décisions",
        "decisions actees",
        "accords obtenus"
    ]

    private static let actionsTitleAliases: Set<String> = [
        "actions",
        "plan d'actions",
        "actions a mener",
        "prochaines etapes",
        "prochaines étapes"
    ]

    private static func dedupeAndInject(bodyHTML: String,
                                        decisions: [String],
                                        tasks: [ActionTask]) -> String {
        var html = bodyHTML
        let decisionsBlock = decisions.isEmpty ? nil : renderDecisionsBlock(decisions)
        let actionsBlock = tasks.isEmpty ? nil : renderActionsBlock(tasks)

        if let block = decisionsBlock {
            html = replaceOrAppend(html, titleAliases: decisionsTitleAliases, block: block)
        }
        if let block = actionsBlock {
            html = replaceOrAppend(html, titleAliases: actionsTitleAliases, block: block)
        }
        return html
    }

    private static func renderDecisionsBlock(_ decisions: [String]) -> String {
        var rows = ""
        for (idx, d) in decisions.enumerated() {
            rows += "<tr><td>D\(idx + 1)</td><td>\(escape(d))</td></tr>\n"
        }
        return """
        <h2>Relevé de décisions</h2>
        <table>
        <thead><tr><th>#</th><th>Décision</th></tr></thead>
        <tbody>
        \(rows)</tbody>
        </table>
        """
    }

    private static func renderActionsBlock(_ tasks: [ActionTask]) -> String {
        let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        var rows = ""
        for (idx, t) in sorted.enumerated() {
            let porteur = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
            let dueRaw = t.dueDate.map(fmt.string(from:)) ?? "—"
            rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
        }
        return """
        <h2>Plan d'actions</h2>
        <table>
        <thead><tr><th>#</th><th>Action</th><th>Porteur</th><th>Échéance</th></tr></thead>
        <tbody>
        \(rows)</tbody>
        </table>
        """
    }

    /// Cherche un `<h2>Titre</h2>` dont le texte normalisé matche un alias.
    /// Si trouvé → remplace ce `<h2>` ET le bloc qui suit (jusqu'au prochain
    /// `<h2>` ou la fin) par `block`. Sinon append `block` à la fin.
    private static func replaceOrAppend(_ html: String,
                                        titleAliases: Set<String>,
                                        block: String) -> String {
        // Regex pour repérer les <h2>…</h2>.
        let pattern = #"<h2[^>]*>(.*?)</h2>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return html + "\n" + block
        }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        let matches = regex.matches(in: html, options: [], range: range)

        for (i, m) in matches.enumerated() {
            let titleText = nsHTML.substring(with: m.range(at: 1))
            let normalized = normalize(titleText)
            if titleAliases.contains(normalized) {
                // Trouvé : remplacer du début du <h2> jusqu'au prochain <h2> (ou fin).
                let start = m.range.location
                let nextStart: Int
                if i + 1 < matches.count {
                    nextStart = matches[i + 1].range.location
                } else {
                    nextStart = nsHTML.length
                }
                let replaceRange = NSRange(location: start, length: nextStart - start)
                return nsHTML.replacingCharacters(in: replaceRange, with: block + "\n")
            }
        }
        return html + "\n" + block + "\n"
    }

    private static func normalize(_ s: String) -> String {
        // Strip tags (au cas où des <strong>…</strong> sont à l'intérieur du h2).
        var stripped = ""
        var inside = false
        for c in s {
            if c == "<" { inside = true }
            else if c == ">" { inside = false }
            else if !inside { stripped.append(c) }
        }
        return stripped
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML escape

    private static func escape(_ s: String) -> String {
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
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter ReportHTMLBuilderTests 2>&1 | tail -15
```
Expected: PASS 6/6.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Report/ReportHTMLBuilder.swift Tests/ReportHTMLBuilderTests.swift
git commit -m "feat(report-styling): ReportHTMLBuilder (eyebrow + meta + body + auto-injection Décisions/Actions)"
```

---

### Task 4: MeetingReportPreview (WKWebView)

**Files:**
- Create: `OneToOne/Views/Meeting/MeetingReportPreview.swift`

- [ ] **Step 1: Créer le wrapper**

Dans `OneToOne/Views/Meeting/MeetingReportPreview.swift` :

```swift
import SwiftUI
import WebKit

/// NSViewRepresentable autour de WKWebView pour afficher le HTML du rapport
/// stylé. Recharge le HTML quand la prop change.
struct MeetingReportPreview: NSViewRepresentable {

    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        // Empêcher la WebView de capturer le focus clavier (cf. MermaidView).
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingReportPreview.swift
git commit -m "feat(report-styling): MeetingReportPreview (WKWebView wrapper)"
```

---

### Task 5: ExportService.buildMeetingHTML — refactor vers ReportHTMLBuilder

**Files:**
- Modify: `OneToOne/Services/ExportService.swift`

- [ ] **Step 1: Localiser buildMeetingHTML**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "private func buildMeetingHTML\|func htmlParagraphs\|func htmlList" OneToOne/Services/ExportService.swift | head
```

`buildMeetingHTML(meeting:includeTranscript:)` à ~ligne 447.

- [ ] **Step 2: Remplacer le corps**

Repérer le bloc complet de la fonction (`private func buildMeetingHTML(meeting: Meeting, includeTranscript: Bool) -> String { … }` jusqu'à sa fermeture). Le remplacer ENTIÈREMENT par :

```swift
private func buildMeetingHTML(meeting: Meeting, includeTranscript: Bool) -> String {
    // Délégué au builder thémé (rapport styling 2026-05-22).
    // Le template courant du meeting est utilisé pour eyebrow + subtitle ;
    // si nil, fallback à template kind par défaut depuis meeting.kind.
    return ReportHTMLBuilder.build(
        meeting: meeting,
        template: meeting.reportTemplate,
        includeTranscript: includeTranscript
    )
}
```

- [ ] **Step 3: Supprimer les helpers devenus inutiles s'ils ne sont pas utilisés ailleurs**

Vérifier l'usage des helpers `htmlParagraphs`, `htmlList`, `escapeHTML` :
```bash
grep -n "htmlParagraphs\|htmlList\|escapeHTML" OneToOne/Services/ExportService.swift
```

Si l'un d'eux est UNIQUEMENT utilisé par l'ancien `buildMeetingHTML` (compte les occurrences hors de la déclaration) → le supprimer. S'ils sont utilisés par `exportInterviewPDF` / `exportMeetingToAppleNotes` / etc. → les laisser.

Le builder thémé gère son propre `escape` interne, indépendant.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`. Si erreur sur un helper supprimé → restaurer.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ExportService.swift
git commit -m "refactor(report-styling): ExportService.buildMeetingHTML délègue à ReportHTMLBuilder"
```

---

### Task 6: ExportService.exportMeetingPDF — WKWebView createPDF

**Files:**
- Modify: `OneToOne/Services/ExportService.swift`

- [ ] **Step 1: Localiser exportMeetingPDF**

```bash
grep -n "func exportMeetingPDF\|NSPrintOperation" OneToOne/Services/ExportService.swift | head
```

Vers ligne 195. Le corps utilise actuellement `NSPrintOperation` sur un `NSTextView`.

- [ ] **Step 2: Réécrire pour utiliser WKWebView createPDF**

Remplacer le corps entier de `exportMeetingPDF(meeting:fileName:)` par :

```swift
func exportMeetingPDF(meeting: Meeting, fileName: String) {
    let html = buildMeetingHTML(meeting: meeting, includeTranscript: false)

    // NSSavePanel pour cible.
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = fileName.hasSuffix(".pdf") ? fileName : fileName + ".pdf"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    // WKWebView headless : charger HTML, attendre fin nav, createPDF.
    Task { @MainActor in
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        let delegate = PDFExportDelegate(targetURL: url)
        webView.navigationDelegate = delegate
        // Ancre forte sur self.delegate via objc_setAssociatedObject pour éviter
        // que delegate soit dealloc avant didFinish.
        objc_setAssociatedObject(webView, &PDFExportDelegate.assocKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.loadHTMLString(html, baseURL: nil)
    }
}

private final class PDFExportDelegate: NSObject, WKNavigationDelegate {
    nonisolated(unsafe) static var assocKey: UInt8 = 0
    let targetURL: URL
    init(targetURL: URL) { self.targetURL = targetURL }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Petit délai pour laisser le rendering finir (fonts, layouts).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let config = WKPDFConfiguration()
            // Page A4 par défaut.
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: self.targetURL)
                        print("[Export] PDF écrit : \(self.targetURL.path) (\(data.count) octets)")
                    } catch {
                        print("[Export] échec écriture PDF : \(error)")
                    }
                case .failure(let error):
                    print("[Export] createPDF échec : \(error)")
                }
            }
        }
    }
}
```

Vérifier qu'`import WebKit` est présent en tête du fichier (sinon l'ajouter avec les autres imports).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/ExportService.swift
git commit -m "refactor(report-styling): exportMeetingPDF utilise WKWebView createPDF (remplace NSPrintOperation)"
```

---

### Task 7: MeetingView onglet Rapport — toggle Aperçu/Éditer

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Localiser l'onglet Rapport**

```bash
grep -n "case .report\|activeSection == .report\|reportSection\|reportBody\b" OneToOne/Views/MeetingView.swift | head -15
```

Repérer le `case .report:` (autour de la ligne 495) — c'est le routeur de contenu de l'onglet.

- [ ] **Step 2: Ajouter @State pour le mode**

Dans la déclaration du struct `MeetingView`, ajouter (à côté de `isGenerating`) :

```swift
@State private var reportEditMode: Bool = false
```

- [ ] **Step 3: Ajouter le toggle dans la toolbar du rapport**

Localiser la HStack du `generateToolbar` (créée Task 8 du report-refactor). Juste avant le bouton "Générer", insérer le toggle :

```swift
Picker("", selection: $reportEditMode) {
    Image(systemName: "eye").tag(false)
    Image(systemName: "pencil").tag(true)
}
.pickerStyle(.segmented)
.fixedSize()
.help("Aperçu / Éditer markdown")
```

- [ ] **Step 4: Router le contenu de l'onglet**

Localiser le `case .report:` (étape 1). Le bloc rend probablement directement `meeting.summary` dans un `Text` ou `MarkdownEditorView`. Remplacer ce contenu par un router conditionnel :

```swift
case .report:
    VStack(spacing: 0) {
        generateToolbar
        Divider()
        if reportEditMode {
            MarkdownEditorView(
                text: Binding(
                    get: { meeting.summary },
                    set: { meeting.summary = $0; try? context.save() }
                ),
                textViewID: "reportEditor.\(meeting.persistentModelID.hashValue)"
            )
            .padding(12)
        } else {
            MeetingReportPreview(html: ReportHTMLBuilder.build(
                meeting: meeting,
                template: meeting.reportTemplate,
                includeTranscript: false
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

**Note** : si le `case .report:` contient déjà beaucoup de logique (bandeau "transcription absente", etc.), conserver ces sous-vues et seulement remplacer la partie qui rendait le summary. Inspecter le code avant le remplacement.

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`. Si erreur sur le routeur (struct mismatch, scope variable), adapter en gardant la logique existante autour.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(report-styling): onglet Rapport — toggle Aperçu (WKWebView stylé) / Éditer (markdown)"
```

---

### Task 8: Final build + test + smoke

**Files:** (aucun)

- [ ] **Step 1: Run tous les tests**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -10
```
Expected: tous PASS, inclus `MarkdownToHTMLRendererTests` (9) et `ReportHTMLBuilderTests` (6).

- [ ] **Step 2: Full build clean**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Historique commits**

```bash
git log --oneline -10
```
Attendu : 7 commits `feat(report-styling):` ou `refactor(report-styling):` pour Tasks 1-7.

- [ ] **Step 4: Smoke test manuel**

`swift run` et :
1. Ouvrir une réunion avec un rapport généré → onglet Rapport → mode Aperçu visible avec eyebrow navy, h1, meta-table.
2. Vérifier les sections numérotées (badge navy carré).
3. Si décisions présentes dans `meeting.decisions` → section "Relevé de décisions" en fin avec table.
4. Si actions dans `meeting.tasks` → section "Plan d'actions" en fin avec porteur/échéance.
5. Toggle "Éditer" → MarkdownEditorView visible avec markdown brut.
6. Modifier un mot → retour Aperçu → modification reflétée dans le rendu.
7. Export PDF → fichier .pdf produit, ouvre dans Preview, style préservé.
8. Export Mail → Mail.app ouvre composition avec body HTML stylé.
9. Markdown avec `:::vigilance\n…\n:::` → rendu callout cream avec dot orange "Point de vigilance".
10. Markdown avec `## Décisions` + meeting.decisions non-vide → vérifier que la section LLM est remplacée par la canonique.

---

## Self-review

**Spec coverage :**
- §2.1 stack HTML + WKWebView → Tasks 1-7. ✓
- §2.2 directives `:::vigilance`/`:::reserve` → Task 2 (via swift-markdown `BlockDirective`, pas de pré-processeur nécessaire). ✓ (simplification par rapport au spec qui mentionnait un `MarkdownDirectivePreprocessor` — pas nécessaire car `parseBlockDirectives` natif)
- §2.3 header auto Meeting → Task 3 (eyebrow / h1 / subtitle / meta). ✓
- §2.4 Décisions/Actions même style + dédoublonnage → Task 3 (`replaceOrAppend` + aliases normalisés). ✓
- §2.5 toggle Aperçu/Éditer → Task 7. ✓
- §2.6 couleurs navy/cream → Task 1 (ReportThemeCSS). ✓
- §2.7 mail flow réutilisé → Tasks 5 + 6 (refactor interne, API publique inchangée). ✓
- §3.1 file map → all tasks. ✓
- §4 markdown convention → Tasks 1 (CSS) + 2 (renderer + directives). ✓
- §5 header auto → Task 3 (`makeEyebrow`, `makeSubtitle`, `makeMetaTable`, `makeObjet`). ✓
- §6 décisions/actions injection → Task 3 (`renderDecisionsBlock`, `renderActionsBlock`, `replaceOrAppend`). ✓
- §7 CSS → Task 1 (full CSS dans `ReportThemeCSS.css`). ✓
- §8 mail flow `composeMeetingMail` réutilisé → Task 5 (refactor interne). ✓
- §9 édition → Task 7. ✓
- §10 boutons export PDF/Mail → Task 6. ✓
- §11 erreurs (mail Apple Mail fallback, PDF échec log) → Task 6 (log) + héritage du flow existant Mail. ✓
- §12 tests → Tasks 2 + 3. ✓
- §13 YAGNI → respecté.
- §14 pas de migration SwiftData → respecté.

**Écart simplificateur** (avantage) : `MarkdownDirectivePreprocessor` n'est PAS nécessaire car swift-markdown supporte nativement `:::name` via `parseBlockDirectives`. Le renderer Task 2 gère directement `BlockDirective` nodes. Une dépendance en moins.

**Placeholder scan :**
- Aucun "TBD" / "implement later".
- Tous les snippets de code sont complets.
- Task 5 Step 3 "supprimer les helpers s'ils ne sont pas utilisés ailleurs" — conditionnel mais avec commande grep explicite pour vérifier. Acceptable.
- Task 7 Step 4 "si le case contient déjà beaucoup de logique" — instructions précises pour le subagent.

**Type consistency :**
- `ReportHTMLBuilder.build(meeting:template:includeTranscript:)` — défini Task 3, utilisé Tasks 5, 6, 7. ✓
- `MarkdownToHTMLRenderer.render(_)` — défini Task 2, utilisé Task 3. ✓
- `ReportThemeCSS.css` — défini Task 1, utilisé Task 3. ✓
- `MeetingReportPreview(html:)` — défini Task 4, utilisé Task 7. ✓
- `reportEditMode: Bool` — défini Task 7. ✓
- `PDFExportDelegate.assocKey` — défini Task 6. ✓
- Types existants : `Meeting.summary / .reportTemplate / .decisions / .tasks / .participants / .project / .durationSeconds / .kind / .rawTranscript` — tous confirmés dans §16 du spec. ✓
- `ActionTask.title / .dueDate / .collaborator / .unresolvedAssigneeName / .meeting` — confirmés. ✓
- `ReportTemplate.kind: ReportTemplateKind` avec `.label` — confirmé. ✓

Aucune correction inline nécessaire.
