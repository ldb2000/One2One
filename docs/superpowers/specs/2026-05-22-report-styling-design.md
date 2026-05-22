# Rapport — rendu stylé (HTML/CSS) pour in-app, PDF, mail — Design

**Date:** 2026-05-22

## 1. Objet

Reproduire le style visuel d'un compte-rendu professionnel (référence : `CR_Articulation_Gouvernances.pdf`) pour le rendu in-app, l'export PDF et l'export mail. Stack unique HTML+CSS, source de vérité = `meeting.summary` markdown. Le rapport reste éditable.

## 2. Décisions actées

1. **Stack** : Markdown → HTML thémé (CSS inliné) ; preview via WKWebView, PDF via `WKWebView.createPDF`, mail via NSSharingService body HTML.
2. **Convention markdown** : standard + 2 directives custom (`:::vigilance` / `:::reserve`).
3. **Header** : eyebrow + h1 + subtitle + table métadonnées auto-remplis depuis `Meeting` + `template.kind`.
4. **Décisions/Actions auto-injectées en fin** : mêmes balises HTML (`<h2>` + `<table>`) que les sections LLM. Détection de doublon : si LLM a déjà produit un H2 normalisé matchant "décisions" / "actions" / "plan d'actions" / "relevé de décisions" → remplacement par version canonique tirée de SwiftData. Sinon append.
5. **Édition** : toggle Aperçu (WKWebView read-only) ↔ Éditer (`MarkdownEditorView` existant). Source = `meeting.summary` markdown. Pas de WYSIWYG sur HTML.
6. **Couleurs** : navy `#1a2a44`, cream `#fbf4e3`, gray rows alternées, accent orange `#e89a3c`.
7. **Mail** : HTML inliné dans le body (CSS appliqué balise par balise pour compatibilité Outlook/Apple Mail/Gmail). Pas de pièce jointe PDF en V1.

## 3. Architecture

```
Meeting (summary markdown) + Template + Tasks
            │
            ▼
ReportHTMLBuilder.build(meeting:template:)
            │
            ├── eyebrow + h1 + subtitle (depuis meeting.kind / template / participants)
            ├── meta-table (OBJET / DATE / PARTICIPANTS)
            ├── MarkdownDirectivePreprocessor.process(summary)
            │       └── transforme :::vigilance / :::reserve en <div class="callout …">
            ├── MarkdownToHTMLRenderer.render(processedMarkdown)
            │       └── swift-markdown standard (préserve les blocs HTML inline)
            ├── inject "Relevé de décisions" (depuis ExtractedFacts.decisions
            │   stockés dans meeting.keyPoints/decisions OU re-derived)
            └── inject "Plan d'actions" (depuis meeting.tasks)
                ── détecte doublon par H2 normalisé → remplace ou append
            │
            ▼
       Themed HTML string (CSS via <style> block inliné)
            │
            ├──▶ WKWebView (preview onglet Rapport)
            ├──▶ WKWebView.createPDF (export PDF, remplace NSPrintOperation actuel)
            └──▶ AppleScript Mail/Outlook (réutilise composeMeetingMail existant)
```

### 3.1 Fichiers

| Path | Responsabilité |
|---|---|
| `OneToOne/Services/Report/MarkdownDirectivePreprocessor.swift` (new) | Transforme `:::vigilance` / `:::reserve` → `<div class="callout …">` AVANT swift-markdown |
| `OneToOne/Services/Report/MarkdownToHTMLRenderer.swift` (new) | swift-markdown `Markdown.Document(parsing: …)` → HTML via visitor pattern. Préserve les blocs HTML inline produits par le préprocesseur. |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` (new) | Assemble eyebrow + h1 + meta + body + tables Décisions/Actions auto. Détecte doublons H2 par titre normalisé. |
| `OneToOne/Services/Report/ReportThemeCSS.swift` (new) | `static let css: String` constante avec tout le CSS du §7 |
| `OneToOne/Views/Meeting/MeetingReportPreview.swift` (new) | `NSViewRepresentable` autour de WKWebView pour preview in-app |
| `OneToOne/Views/MeetingView.swift` (modify) | Onglet Rapport : toggle Aperçu/Éditer ; route vers `MeetingReportPreview(html:)` ou `MarkdownEditorView($meeting.summary)` |
| `OneToOne/Services/ExportService.swift` (modify) | **Refactor `buildMeetingHTML`** (l.447) → délègue à `ReportHTMLBuilder`. **Refactor `exportMeetingPDF`** (l.195) → utilise WKWebView createPDF avec le même HTML. `exportMeetingMail` / `exportMeetingOutlook` inchangés en surface — ils consomment le nouveau HTML via `composeMeetingMail`. |
| `Tests/MarkdownDirectivePreprocessorTests.swift` (new) | Tests `:::vigilance` / `:::reserve` round-trip |
| `Tests/MarkdownToHTMLRendererTests.swift` (new) | Tests parsing standard (h2, table, blockquote, list) |
| `Tests/ReportHTMLBuilderTests.swift` (new) | Tests détection doublon H2 + injection Décisions/Actions |

Total : 5 nouveaux services/vues, 3 nouveaux tests, 2 modifications.

## 4. Convention markdown

### 4.1 Standard (mappé directement)

| Markdown | Rendu HTML | Style visuel |
|---|---|---|
| `## Titre` | `<h2>Titre</h2>` | Badge navy numéroté auto (CSS `counter-increment: section`) + titre bold + underline rule |
| `### Sub` | `<h3>Sub</h3>` | Sub-section bold, sans badge |
| `- item` | `<ul><li>item</li></ul>` | Bullet point standard |
| `> texte` | `<blockquote>texte</blockquote>` | Callout cream générique |
| `**bold**` | `<strong>` | Gras navy-dark |
| `*italic*` | `<em>` | Italic muted |
| `\| col \| col \|` | `<table>` | Header navy/blanc, lignes alternées cream/blanc |

### 4.2 Directives custom

| Markdown | Rendu HTML | Style |
|---|---|---|
| `:::vigilance\nTexte\n:::` | `<div class="callout vigilance">Texte</div>` | Callout cream avec petit dot orange + label "Point de vigilance" |
| `:::reserve\nTexte\n:::` | `<div class="callout reserve">Texte</div>` | Callout cream avec dot gris + label "Réserve exprimée" |

Pas d'autres directives (YAGNI). Les autres encarts métiers passent par `> blockquote` standard.

Le `template.promptBody` peut mentionner ces directives en exemples pour guider le LLM. Sinon il produit du markdown standard, parfaitement rendu.

**Implémentation** : swift-markdown ne supporte pas nativement les directives `:::name`. `MarkdownDirectivePreprocessor` traite le markdown brut AVANT swift-markdown :

```
:::vigilance
Attention au cas PEGA…
:::
```
→ remplacé par un bloc HTML inline :
```html
<div class="callout vigilance">

Attention au cas PEGA…

</div>
```

Les lignes vides autour du contenu permettent à swift-markdown de re-parser le contenu interne comme du markdown (inline emphasis, liens). Le bloc `<div>` lui-même est préservé en HTML pass-through.

## 5. Header auto-rempli depuis Meeting

```html
<div class="header-rule"></div>
<div class="eyebrow">COMPTE-RENDU · NEVIDIS · CONFIDENTIEL — USAGE INTERNE</div>
<h1>Projet Névidis — Point d'avancement</h1>
<p class="subtitle">Réunion projet — 22 mai 2026 à 16:30</p>

<table class="meta">
  <tr><th>OBJET</th><td>(première phrase du markdown OU titre meeting)</td></tr>
  <tr><th>DATE</th><td>22 mai 2026 à 16:30 (1h00)</td></tr>
  <tr><th>PARTICIPANTS</th><td>BUSSIERE Florian, DE BERTI Laurent, …</td></tr>
</table>
```

**Sources** :
- **Eyebrow** = `template.kind.label.uppercased() + " · " + (meeting.project.map(\.code) ou "") + " · CONFIDENTIEL — USAGE INTERNE"` (suffixe fixe ; project.code omis si pas de projet — c'est-à-dire que la séparation `·` ne s'affiche pas)
- **h1** = `meeting.title` (escapeHTML pour sécurité)
- **subtitle** = `template?.kind.label ?? meeting.kind.label + " — " + formattedDate`
- **OBJET** = première phrase du markdown extraite par builder (`first sentence before "."` après `MarkdownDirectivePreprocessor` ; on saute les directives HTML) OU fallback `meeting.title` si markdown vide
- **DATE** = `meeting.date` formaté `"d MMMM yyyy à HH:mm"` + durée extraite de `meeting.durationSeconds` si > 0 (format "(durée 1h00)")
- **PARTICIPANTS** = `meeting.participants` triés alpha par nom, joined par `", "`

## 6. Tables Décisions / Actions auto-injectées

**Détection doublon** : avant injection, builder scanne le HTML produit pour des `<h2>` dont le texte normalisé (lowercased + diacritic-insensitive + trim) matche :
- `"décisions"`, `"relevé de décisions"`, `"décisions actées"`, `"accords obtenus"` → section décisions
- `"actions"`, `"plan d'actions"`, `"actions à mener"`, `"prochaines étapes"` → section actions

Si match → remplace la `<table>` qui suit le `<h2>` par la version canonique. Sinon → append en fin de body avec un nouveau `<h2>`.

**Décisions canoniques** depuis `meeting.decisions: [String]` (champ SwiftData existant alimenté par `extractStructured` via `apply(report:)`) :
```html
<h2>Relevé de décisions</h2>
<table>
  <thead><tr><th>#</th><th>Décision</th></tr></thead>
  <tbody>
    <tr><td>D1</td><td>Catalogue par exception…</td></tr>
    <tr><td>D2</td><td>Tri hebdomadaire amont…</td></tr>
  </tbody>
</table>
```

**Actions canoniques** depuis `meeting.tasks` (relation inverse, sans filtre — toutes les tasks attachées à ce meeting). Tri par `task.dueDate ?? .distantFuture` ascendant. `Porteur` = `task.collaborator?.name ?? task.unresolvedAssigneeName ?? "—"`. `Échéance` = `task.dueDate` formatée fr ou `"—"` si nil.

```html
<h2>Plan d'actions</h2>
<table>
  <thead><tr><th>#</th><th>Action</th><th>Porteur</th><th>Échéance</th></tr></thead>
  <tbody>
    <tr><td>A1</td><td>Rédiger résumé</td><td>L. De Berti</td><td>Fait</td></tr>
  </tbody>
</table>
```

Si `decisions.isEmpty && tasks.isEmpty` → aucune injection (pas de section vide).

## 7. CSS theme

Variables CSS principales (fichier `ReportThemeCSS.swift` constante `css`) :

```css
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

body {
  font-family: -apple-system, "SF Pro Text", "Inter", Helvetica, sans-serif;
  color: var(--text);
  line-height: 1.55;
  counter-reset: section;
  max-width: 760px;
  margin: 0 auto;
  padding: 24px 32px;
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
}

h1 {
  font-size: 28px;
  color: var(--navy-dark);
  line-height: 1.2;
  margin: 6px 0 4px;
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
}

h2 {
  counter-increment: section;
  font-size: 16px;
  color: var(--navy-dark);
  margin: 22px 0 10px;
  padding-bottom: 6px;
  border-bottom: 1.5px solid var(--navy);
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
}
table:not(.meta) tbody td {
  padding: 8px 10px;
  border-bottom: 1px solid var(--cream-border);
}
table:not(.meta) tbody tr:nth-child(even) td {
  background: var(--gray-row);
}

blockquote {
  background: var(--cream);
  border-radius: 3px;
  padding: 12px 14px;
  margin: 12px 0;
  font-size: 14px;
}

.callout {
  background: var(--cream);
  border-radius: 3px;
  padding: 12px 14px;
  margin: 12px 0;
  font-size: 14px;
}
.callout::before {
  display: inline-block;
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

ul { padding-left: 22px; }
li { margin-bottom: 4px; }
strong { color: var(--navy-dark); }
em { color: var(--muted); }
```

## 8. Mail / Outlook — flow existant réutilisé

L'app utilise déjà `composeMeetingMail` (`ExportService.swift:228`) qui :
1. Construit le HTML via `buildMeetingHTML(meeting:includeTranscript:)` (l.447)
2. Route vers `runMailCompose` (AppleScript Mail.app) ou `runOutlookCompose` (AppleScript Outlook.app)
3. Les deux apps natives macOS rendent les `<style>…</style>` blocks correctement

**Refactor minimal** : `buildMeetingHTML` délègue à `ReportHTMLBuilder.build(meeting:template:)`. Les fonctions publiques (`exportMeetingMail`, `exportMeetingOutlook`) restent inchangées en surface — elles bénéficient automatiquement du nouveau style.

**Pas besoin** de `ReportInlineStyler` en V1 : Mail.app et Outlook.app rendent le `<style>` block normalement. Si plus tard on cible Gmail webmail (qui strip `<style>`), un styler inline pourra être ajouté.

**Détail conservé** : l'option `MeetingMailExportOptions.includeTranscript` (transcript intégral en annexe) reste — le builder accepte un paramètre `includeTranscript: Bool` et ajoute une dernière section `<h2>Transcription complète</h2>` si demandée. Idem pour `includeSlidesPDF` (pièce jointe inchangée).

## 9. Édition

Toggle entre 2 modes dans l'onglet Rapport :

```
┌──────────────────────────────────────────────────────────────┐
│ Template : Suivi Projet  [👁 Aperçu][✏ Éditer]  [📄 PDF][✉ Mail]  [✨ Générer] │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│  Aperçu : WKWebView avec le HTML stylé                        │
│  ────────────────────────────────────                         │
│  ou                                                            │
│  Éditer : MarkdownEditorView lié à meeting.summary            │
│                                                                │
└──────────────────────────────────────────────────────────────┘
```

- Default = Aperçu
- Toggle Éditer → MarkdownEditorView, modifications écrites direct dans `meeting.summary` (`@Bindable meeting`)
- Re-toggle Aperçu → re-build HTML avec les changements
- "Générer" écrase `summary` sans confirmation (V1 — simple)

## 10. Boutons Export

L'onglet rapport a déjà un menu Export (PDF / Mail / Outlook / Notes) via `MeetingTopChromeBar` ou similaire. Les boutons restent inchangés en surface ; ils consomment le HTML produit par `ReportHTMLBuilder` (via `buildMeetingHTML` refactoré). Désactivés si `meeting.summary.isEmpty`.

**`exportMeetingPDF` (l.195)** : refactor body. Avant = `NSPrintOperation` sur `NSTextView`. Après = WKWebView headless qui charge le HTML, attend `didFinishNavigation`, appelle `createPDF(configuration:)` → `Data` → écrit à l'URL choisie par `NSSavePanel`. Le signature publique `exportMeetingPDF(meeting:fileName:)` ne change pas.

## 11. Erreurs

- WKWebView échoue à charger → fallback affichage markdown brut dans un Text.
- createPDF échoue → toast erreur, pas de fichier écrit.
- NSSharingService Mail indisponible → fallback : copie HTML dans le presse-papiers + toast "HTML copié — colle dans ton mail".

## 12. Tests

- `MarkdownToHTMLRendererTests` :
  - heading + counter
  - blockquote standard
  - directive `:::vigilance` parsée
  - directive `:::reserve` parsée
  - tableau standard
- `ReportHTMLBuilderTests` :
  - Détection doublon H2 "Décisions" (variations casse/accents)
  - Injection Plan d'actions depuis tasks
  - Aucune injection si decisions+tasks vides
  - Eyebrow contient project.code si projet associé

Tests visuels : manuels via swift run + lancement sur réunion test.

## 13. YAGNI

- Pas de personnalisation CSS par template (V2)
- Pas de logo entête (V2)
- Pas d'export Word/docx
- Pas de PDF en pièce jointe mail
- Pas de directive custom autre que vigilance/reserve
- Pas d'édition WYSIWYG sur HTML (markdown éditeur suffit)

## 14. Migration

Aucun modèle SwiftData impacté. Pure couche de rendu en complément du markdown existant. Les rapports déjà générés s'affichent automatiquement dans le nouveau rendu (le markdown les contient).

## 15. Livrables

- `OneToOne/Services/Report/MarkdownDirectivePreprocessor.swift`
- `OneToOne/Services/Report/MarkdownToHTMLRenderer.swift`
- `OneToOne/Services/Report/ReportHTMLBuilder.swift`
- `OneToOne/Services/Report/ReportThemeCSS.swift`
- `OneToOne/Views/Meeting/MeetingReportPreview.swift`
- `OneToOne/Views/MeetingView.swift` (modifié — onglet rapport)
- `OneToOne/Services/ExportService.swift` (refactor `buildMeetingHTML` + `exportMeetingPDF`)
- `Tests/MarkdownDirectivePreprocessorTests.swift`
- `Tests/MarkdownToHTMLRendererTests.swift`
- `Tests/ReportHTMLBuilderTests.swift`

## 16. Types existants utilisés (audit code réel)

- `Meeting.summary: String` ✓
- `Meeting.title: String` ✓
- `Meeting.date: Date` ✓
- `Meeting.kind: MeetingKind` ✓ (enum avec `.label`)
- `Meeting.participants: [Collaborator]` ✓
- `Meeting.project: Project?` ✓
- `Meeting.tasks: [ActionTask]` ✓ (relation)
- `Meeting.decisions: [String]` ✓ (champ stocké, alimenté par `apply(report:)`)
- `Meeting.keyPoints / openQuestions` ✓ (idem)
- `Meeting.liveNotes: String` ✓
- `Meeting.rawTranscript: String` ✓
- `Meeting.durationSeconds: Double` ✓
- `Project.code: String` / `Project.name: String` ✓
- `Collaborator.name: String` ✓
- `ActionTask.title / dueDate / collaborator / unresolvedAssigneeName` ✓ (tous confirmés Task 1 + 7 du report-refactor précédent)
- `ReportTemplate.kind: ReportTemplateKind` ✓ (avec `.label` computed)
- `ReportTemplate.preamble` ✓ (ajouté Task 1 report-refactor)
- `swift-markdown` `import Markdown` ✓ déjà linké
- `WebKit` `import WebKit` + `WKWebView` ✓ déjà utilisé dans `MermaidView.swift`
- `MarkdownEditorView(text: Binding<String>, textViewID: String)` ✓ `EditableTextField.swift:319`
- `ExportService.composeMeetingMail` AppleScript Mail/Outlook ✓ existe
- `MeetingMailExportOptions.includeTranscript / .includeSlidesPDF` ✓

Spec ready.
