# Report Templates — Design spec

**Date**: 2026-05-14
**Branch**: TBD (probable: `feat/report-templates`)
**Author**: laurent.deberti
**Status**: Approved (design phase), awaiting implementation plan.

## 1. Goals

Replace the single hardcoded AI report prompt with a flexible, user-editable **template** system:
- 8 built-in templates covering 1:1, manager, COPIL, COSUI, CODIR, prep, démo, global.
- User can duplicate / create / edit / archive templates.
- Templates declare ordered **sections** (title + hint), an AI **prompt body** containing **`{{variables}}`**, and an **historic context mode** (`none` / `lastN` / `rag` / `hybrid`).
- A variable resolver injects current meeting data, project state, collaborator state, manager state, urgent actions, and computed "general context" before the prompt hits the LLM.
- Each Meeting carries a `reportTemplate?` chosen at creation (auto by `MeetingKind`) and overridable at any time.

## 2. Decisions log

| Ref | Decision | Value |
|-----|----------|-------|
| Q1  | Template scope | Hybrid (§C): named ordered sections + AI prompt body. Output stored as markdown in `meeting.summary`; sections give the LLM a structure to fill. |
| Q2  | Built-ins | All 8 (D1–D8) shipped + user categories `metier`, `initiative`, `custom`. |
| Q3  | Variables | Catalogue covering meeting / project / collab / manager / global. `{{contexte_general}}` powers D1 (top actions + active alerts + recent activity). |
| Q4  | Selection | Default by `MeetingKind` at Meeting creation, stored on `meeting.reportTemplate`, user-overridable via picker. |
| Q5  | History context | Per-template `historyMode` (H4). Defaults: D1 → none + `{{contexte_general}}`; D2 → lastN=2; D3 → lastN=1; D4 → lastN=1; D5 → lastN=2; D6 → lastN=1; D7 → lastN=1; D8 → none. |

## 3. Data model

### New `@Model ReportTemplate`

```swift
@Model
final class ReportTemplate {
    var stableID: UUID? = nil               // ensuredStableID pattern
    var name: String                         // e.g. "1:1 Collaborateur"
    var kindRaw: String                      // see §3.1
    var promptBody: String                   // markdown w/ {{vars}}
    var sectionsJSON: String                 // ordered list of {title,hint}
    var historyModeRaw: String = "none"      // "none"|"lastN"|"rag"|"hybrid"
    var historyN: Int = 0
    var historyK: Int = 0
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
}
```

Add `ReportTemplate.self` to `CurrentSchema`. Lightweight migration (all fields Optional or with defaults).

### 3.1 `ReportTemplateKind` enum (kindRaw values)

```swift
enum ReportTemplateKind: String, CaseIterable, Identifiable {
    case general, oneToOne, manager
    case copil, cosui, codir
    case preparation, restitution
    case metier, initiative, custom
    var id: String { rawValue }
    var label: String { ... }
    var sfSymbol: String { ... }
}
```

### 3.2 New field on `Meeting`

```swift
var reportTemplate: ReportTemplate?
```

Resolved at generation if `nil` (auto default by `MeetingKind`).

### 3.3 New field on `Project`

```swift
var planningText: String = ""
```

Free text. Used by `{{project.planning}}`.

### 3.4 `MeetingKind → ReportTemplateKind` default mapping

| MeetingKind | Default kindRaw lookup |
|---|---|
| `.global` | `general` |
| `.oneToOne` | `oneToOne` |
| `.manager` | `manager` |
| `.project` | `copil` |
| `.work` | `general` |

Picks the first `isBuiltIn = true` template matching that kind.

## 4. Variable resolver

### Service contract

```swift
enum TemplateVariableResolver {
    @MainActor
    static func resolve(prompt: String,
                        for meeting: Meeting,
                        in context: ModelContext,
                        now: Date = Date()) -> String
}
```

Pure function. Scans `prompt` for `{{[a-z_.]+}}`, substitutes via a static dictionary of resolver closures. Unknown variables are left literal (and logged once per generation).

### Variable catalogue

**Meeting**: `{{title}}` `{{date}}` `{{duration}}` `{{kind}}` `{{participants}}` `{{transcript}}` `{{notes}}` `{{custom_prompt}}`

**Project** (only when `meeting.project != nil`): `{{project.name}}` `{{project.code}}` `{{project.entity}}` `{{project.phase}}` `{{project.status}}` `{{project.planning}}` `{{project.actions_ouvertes}}` `{{project.dernier_rapport}}` `{{project.historique_n}}` (N from template)

**Collaborator** (only `.oneToOne`): `{{collab.name}}` `{{collab.role}}` `{{collab.email}}` `{{collab.actions_ouvertes}}` `{{collab.dernier_1to1}}` `{{collab.notes}}`

**Manager** (only `.manager`): `{{manager.items_actuels}}` `{{manager.dernier_cr}}`

**Global**: `{{actions_overdue}}` `{{actions_du_jour}}` `{{historique_n}}` `{{contexte_general}}` `{{date_now}}` `{{semaine}}` `{{mois}}`

### Per-resolver truncation caps

| Variable family | Cap |
|---|---|
| `{{transcript}}` | None (handled by AIReportService.targetSummaryWords) |
| `{{historique_n}}` per item | 2000 chars |
| `{{project.dernier_rapport}}` | 2500 chars |
| `{{collab.dernier_1to1}}` | 2000 chars |
| `{{*.actions_ouvertes}}` | 30 items max |
| `{{contexte_general}}` | 5 actions + 3 alerts + 3 projects |

## 5. History context builder

```swift
enum HistoryContextBuilder {
    @MainActor
    static func build(for meeting: Meeting,
                      template: ReportTemplate,
                      in context: ModelContext) -> String
}
```

Mode dispatch:
- **none** → `""`.
- **lastN** → N most recent Meetings within scope (project / collab / manager / global) excluding `meeting` itself, sorted desc by date. Each item rendered as:
  ```
  --- <date short> · <title> ---
  <summary truncated to 2000>
  ```
- **rag** → top-K `TranscriptChunk` results via existing embedding search. Query = `"\(meeting.title) \(meeting.notes)"`. Each chunk rendered as `[<date> · <source title>]: <chunk>`.
- **hybrid** → `lastN` + `rag` over the rest of the corpus (chunks belonging to the lastN meetings are excluded).

Scope resolution:
- `.project` → other Meetings with same `project`.
- `.oneToOne` → other `.oneToOne` Meetings sharing the primary non-self participant.
- `.manager` → other `.manager` Meetings.
- `.global` / `.work` → recent Meetings of any kind.

### Defaults per built-in

| Template | Mode | N | K |
|---|---|---|---|
| D1 Global | none (uses `{{contexte_general}}` instead) | — | — |
| D2 1:1 Collab | lastN | 2 | — |
| D3 1:1 Manager | lastN | 1 | — |
| D4 COPIL | lastN | 1 | — |
| D5 COSUI | lastN | 2 | — |
| D6 CODIR | lastN | 1 | — |
| D7 Préparation | lastN | 1 | — |
| D8 Restitution | none | — | — |

## 6. Built-in templates

Defined in a Swift source-of-truth `BuiltInTemplates.swift` (static dict) so users can "Restaurer défaut" without DB introspection.

### D1 — Global

- Sections: `Contexte général`, `Résumé`, `Décisions`, `Actions`, `Faits marquants`.
- Prompt body uses `{{kind}}`, `{{date}}`, `{{participants}}`, `{{contexte_general}}`, `{{custom_prompt}}`, `{{transcript}}`, `{{notes}}`.

### D2 — 1:1 Collaborateur

- Sections: `Suivi du précédent`, `Sujets abordés`, `Décisions`, `Actions pour {{collab.name}}`, `Ressenti / Climat`.
- Variables: `{{collab.name}}`, `{{collab.actions_ouvertes}}`, `{{historique_n}}`.

### D3 — 1:1 Manager

- Sections: `Suivi semaine`, `Sujets`, `Demandes du manager`, `Actions`, `Points d'attention`.
- Variables: `{{manager.items_actuels}}`, `{{manager.dernier_cr}}`, `{{historique_n}}`.

### D4 — COPIL

- Sections: `Contexte projet`, `Avancement`, `Décisions`, `Risques`, `Prochaines étapes`.
- Variables: `{{project.name}}`, `{{project.planning}}`, `{{project.actions_ouvertes}}`, `{{historique_n}}`.

### D5 — COSUI

- Sections: `Avancement par sujet`, `Points bloquants`, `Actions`, `Indicateurs`.
- Variables: `{{project.name}}`, `{{historique_n}}`, `{{project.actions_ouvertes}}`.

### D6 — CODIR

- Sections: `Synthèse stratégique`, `Décisions`, `Arbitrages`, `Suite`.
- Variables: `{{historique_n}}`, `{{actions_overdue}}`.

### D7 — Préparation

- Sections: `Objectifs`, `Points à aborder`, `Questions`, `Documents pertinents`.
- Variables: `{{project.dernier_rapport}}` or `{{collab.dernier_1to1}}` (whichever applies), `{{historique_n}}`.

### D8 — Restitution / Démo

- Sections: `Contexte`, `Démo`, `Feedbacks`, `Suite`.
- Variables: `{{project.name}}`, `{{participants}}`.

### `{{contexte_general}}` resolver definition

Produces a 3-block text:
1. **Actions urgentes** — top 5 from `UrgentActionsSelector` (already implemented). One line each.
2. **Alertes actives** — top 3 `ProjectAlert` with severity `Élevé` or `Critique`, non-archived.
3. **Activité récente** — top 3 projects with at least one Meeting whose date is within the last 14 days.

Blocks are titled inline; whole section is wrapped with `Contexte actuel:` prefix.

## 7. UI

### 7.1 Settings → "Templates de rapport"

Two-column list (built-in italic + badge, then custom). Filter by `kindRaw`. Search by name.

Per-row actions: **Modifier** · **Dupliquer** · **Archiver** / **Désarchiver** · **Restaurer défaut** (built-in only) · **Supprimer** (custom only).

Editor form: Name, Kind (picker), History mode + N + K, Section editor (reorderable list of `{title, hint}` rows), Prompt body (TextEditor) with a clickable **variables palette** on the right (categorised; click inserts `{{var}}` at cursor).

### 7.2 MeetingView header

A new **Template** picker next to the existing **Rapport** button. Label: `meeting.reportTemplate?.name ?? "Auto"`. Menu options are templates whose `kindRaw` is compatible with `meeting.kind` (per §3.4 mapping) + a "Tous" sub-section for cross-kind picks. Selecting → assigns `meeting.reportTemplate`, saves.

### 7.3 Generation flow

`AIReportService.generate(meeting:settings:onProgress:)` (new convenience entry — keeps the existing typed-args entry available):
1. Resolve template: `meeting.reportTemplate ?? defaultTemplate(for: meeting.kind, in: context)`.
2. Build history block via `HistoryContextBuilder.build(...)`.
3. Resolve all variables via `TemplateVariableResolver.resolve(prompt:...)`.
4. Append the sections schema (`# Section 1: <title> — <hint>` lines) to the prompt so the LLM organises its output that way.
5. Call `AIClient.send`. Parse output, store in `meeting.summary`.

## 8. Migration & seeding

### 8.1 Seed at startup

In `repairStoreIfNeeded`, after existing dedup loops:

```swift
BuiltInTemplates.seedIfNeeded(in: context)
```

`seedIfNeeded` is idempotent — fetches existing `ReportTemplate` rows with `isBuiltIn = true`, compares to the static dict by `name`, inserts only missing ones. Never overwrites user-edited content unless user clicks **Restaurer défaut**.

### 8.2 "Restaurer défaut" action

Looks up the built-in entry in `BuiltInTemplates.dict[name]` and rewrites `promptBody` + `sectionsJSON` + `historyMode/N/K`. Keeps `name` + `stableID`.

### 8.3 Backward compatibility

- Existing Meetings without `reportTemplate` → at generation, fallback to default by kind. Not backfilled.
- The existing typed-args `AIReportService.generate(mergedTranscript:meetingKind:...)` keeps working until callsites migrate. New entry `generate(meeting:settings:onProgress:)` is the recommended path. Only MeetingView is migrated in v1; ManagerCRGenerator path stays untouched (already uses its own pipeline).

## 9. Edge cases

- Unknown variable → left literal `{{foo}}` in resolved prompt + console warning (logged once per `resolve` call).
- `historyN = 0` → empty string.
- `meeting.project == nil` for a template using `{{project.*}}` → all project vars resolve to empty string.
- `meeting.participants` empty for `.oneToOne` template → `{{collab.*}}` empty.
- Template archived but referenced by a Meeting → fallback to default-by-kind silently.
- Built-in template deletion attempt → blocked at UI (button absent) and at model (`ReportTemplate.delete` checks `isBuiltIn`).
- `rag`/`hybrid` mode when `TranscriptChunk` embeddings are missing or empty → silently downgrades to `lastN` with the template's `historyN` value (or 1 if 0).

## 10. Tests

### Unit (XCTest, in-memory `ModelContext`)
- `TemplateVariableResolver.resolve`:
  - Substitutes known vars (`{{title}}`, `{{project.name}}`, `{{collab.name}}`).
  - Leaves unknown literal (`{{not_a_var}}` stays).
  - Empty value when relationship missing (`{{project.name}}` for a Meeting without project).
- `HistoryContextBuilder`:
  - `none` returns `""`.
  - `lastN=2` over 5 Meetings of same project returns the 2 most recent, descending, truncated.
  - `lastN` excludes the current Meeting.
- `BuiltInTemplates.seedIfNeeded`:
  - First call inserts 8 rows.
  - Second call inserts 0 (idempotent).
  - User-modified built-in's `promptBody` is preserved on subsequent seed.
- `MeetingKind → ReportTemplateKind` default mapping resolves to a built-in row when present.

### Manual
- Settings: create custom template, set sections + prompt + history mode, save.
- Meeting: select the new template, generate report → output respects the section ordering.
- Variables palette: click inserts at cursor.
- Restaurer défaut: built-in template reverts to factory text.

## 11. Out of scope (deferred)

- Variable pipes/filters (`{{actions | overdue_only}}`).
- Import/export of templates as JSON.
- Sharing templates across users.
- Sections with typed fields (e.g. structured `actions[]` parsed from output) — current design stays markdown.
- ManagerCRGenerator migration to templates (kept on its own pipeline for v1).
- A "preview prompt" sandbox in the editor (shows resolved prompt for an example meeting before saving).

## 12. Implementation notes

- `BuiltInTemplates` lives in `OneToOne/Services/BuiltInTemplates.swift` as a static dict; sections + prompt body are Swift string literals to make Pull Requests reviewable.
- `TemplateVariableResolver` + `HistoryContextBuilder` should live in `OneToOne/Services/ReportTemplating.swift` (a single file — small surface, ~200 LOC each).
- `ReportTemplate` editor view lives in `OneToOne/Views/Settings/ReportTemplateEditorView.swift` (new directory if not present).
- The variables palette is a static enum-driven data source (no need to scan the prompt for what's used).
