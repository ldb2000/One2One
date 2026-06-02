import Foundation

/// CSS thémé pour le rendu HTML du compte-rendu (in-app preview, PDF, mail).
/// Inliné dans un bloc `<style>` par `ReportHTMLBuilder`. Compatible Mail.app
/// et Outlook (rendent correctement les `<style>` block via AppleScript).
enum ReportThemeCSS {

    /// Feuille de style complète (variables `:root` + règles) inlinée telle
    /// quelle dans le `<style>` du HTML généré.
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
