# Contextual LLM Prep — Projets dans le contexte 1:1 — Design

**Date:** 2026-05-23

## 1. Objet

Sub-projet **2b / 3** de la roadmap Project Ownership. Enrichit la génération du rapport 1:1 (et la préparation) avec le contexte des projets dont le collaborateur est architecte technique ou chef de projet : 3 derniers résumés par projet + actions ouvertes du projet. Le LLM dispose ainsi de l'historique récent et de la liste des actions en cours pour produire un compte-rendu cohérent et exhaustif.

Foundation : sub-projet 2a (sidebar configurable + panneau Projets) + sub-projet 1 (`Project.technicalArchitect` / `projectManager` + relations inverse).

## 2. Décisions actées

1. Nouvelle variable template `{{collab.projects_context}}` disponible dans `template.promptBody`. Si placeholder absent et contexte non-vide → append automatique avant les sections (mirror du comportement existant de `{{historique_n}}`).
2. Format texte structuré par projet : header `## CODE · Nom (statut: …)` + 3 derniers résumés + N actions ouvertes.
3. Top 3 résumés par projet, tronqués à 1500 caractères chacun.
4. Max 10 actions ouvertes listées par projet (les plus urgentes par échéance).
5. Max 5 projets injectés (priorité aux statuts Red puis Yellow puis Green/Unknown).
6. Budget total ~15 000 caractères ; troncature en queue si dépassement.
7. Colonne `Projet` dans la table canonique "Plan d'actions" : conditionnelle (`meeting.kind == .oneToOne` ET tasks ≥ 2 projets distincts).
8. Built-in template `d2_oneToOne` mis à jour pour inclure `{{collab.projects_context}}` dans son body (revision bumpée à 3, backfill auto).

## 3. Architecture

### 3.1 `TemplateVariableResolver.resolve(...)` — extension

Le résolveur existant traite déjà `{{title}}`, `{{date}}`, `{{participants}}`, `{{transcript}}`, `{{notes}}`, `{{historique_n}}`, `{{collab.actions_ouvertes}}`, etc. Ajouter le case `{{collab.projects_context}}`.

```swift
// Dans ReportTemplating.swift, fonction de substitution :
if prompt.contains("{{collab.projects_context}}") {
    let block = ProjectsContextBuilder.build(for: meeting, in: context)
    prompt = prompt.replacingOccurrences(of: "{{collab.projects_context}}", with: block)
}
```

`ProjectsContextBuilder` est un nouveau helper @MainActor enum dans `ReportTemplating.swift`.

### 3.2 `ProjectsContextBuilder.build(for:in:)`

Logique :
1. Si `meeting.kind != .oneToOne` → renvoie `""`.
2. `partner = meeting.participants.first` → si nil, renvoie `""`.
3. Collecte projets : `partner.projectsAsArchitect + partner.projectsAsManager`, dédupliqués par `persistentModelID`.
4. Tri Red → Yellow → Green → Unknown (réutilise `ProjectStatusPalette.sortedByStatus`), max 5 projets.
5. Pour chaque projet :
   - Récupère les meetings tagués `project == p`, triés date desc, filtrés `!summary.isEmpty`, top 3.
   - Récupère `p.tasks.filter { !$0.isCompleted }` triées par `dueDate` asc, top 10.
   - Détermine rôle : "Architecte technique" si `p.technicalArchitect.id == partner.id`, "Chef de projet" si `p.projectManager.id == partner.id`, "les deux" si les deux.
6. Concatène en texte :

```
## NEVIDIS · Projet Névidis (statut: Yellow)
Rôle de Nicolas PAOLI : Architecte technique

### 3 derniers points discutés sur ce projet
--- 15 mai 2026 · Comité hebdomadaire ---
[résumé tronqué 1500 chars]

--- 8 mai 2026 · Point projet ---
[résumé]

--- 1 mai 2026 · Comité COPIL ---
[résumé]

### Actions ouvertes sur ce projet (5)
- Migrer données disque dur — Pierre, 25 mai
- Étudier 3e datacenter — Nicolas, —
- …

```

7. Tronque le résultat global à 15 000 caractères si nécessaire (coupe en queue, ligne complète).

### 3.3 `AIReportService.generate` — fallback append

Logique existante pour `{{historique_n}}` :

```swift
let hasHistoryPlaceholder = resolved.contains("{{historique_n}}") || …
resolved = resolved.replacingOccurrences(of: "{{historique_n}}", with: history)
…
if !history.isEmpty, !hasHistoryPlaceholder {
    historyAppendix = "\n\nContexte historique :\n\(history)\n"
}
```

Ajouter le même pattern pour `projects_context` :

```swift
let hasProjectsPlaceholder = body.contains("{{collab.projects_context}}")
// (la résolution est faite par TemplateVariableResolver dans `resolved`)
// Si le body ne contenait pas le placeholder mais le contexte est non-vide,
// l'append en queue avant les sections.

if !hasProjectsPlaceholder {
    let projectsBlock = ProjectsContextBuilder.build(for: meeting, in: context)
    if !projectsBlock.isEmpty {
        historyAppendix += "\n\nContexte projets affectés :\n\(projectsBlock)\n"
    }
}
```

### 3.4 `ReportHTMLBuilder.renderActionsBlock` — colonne Projet conditionnelle

Logique actuelle :
```swift
private static func renderActionsBlock(_ tasks: [ActionTask]) -> String {
    // header: # / Action / Porteur / Échéance
}
```

Évolution : nouveau paramètre `includeProjectColumn: Bool` calculé en amont :

```swift
let distinctProjects = Set(tasks.compactMap { $0.project?.persistentModelID })
let includeProjectColumn = meeting.kind == .oneToOne && distinctProjects.count >= 2
let actionsBlock = renderActionsBlock(tasks, includeProjectColumn: includeProjectColumn)
```

Quand activé :
- Header : `# / Action / Projet / Porteur / Échéance`
- Row : `task.project?.code ?? "—"` (code court, pas le nom complet)

### 3.5 Built-in template `d2_oneToOne` — body évolution

Body actuel inclut `{{historique_n}}`. Ajouter `{{collab.projects_context}}` juste après. Bumper la révision marker à 3 pour appliquer le backfill au prochain lancement.

```swift
promptBody: """
1:1 avec {{collab.name}} ({{collab.role}}) — {{date}}

Tu rédiges le compte-rendu de ce 1:1. Le manager est le rédacteur.

Actions ouvertes héritées de {{collab.name}} :
{{collab.actions_ouvertes}}

Projets dont {{collab.name}} est architecte ou chef de projet :
{{collab.projects_context}}

Derniers 1:1 (pour suivi des actions précédentes) :
{{historique_n}}

{{custom_prompt}}

Transcription audio (peut contenir des erreurs STT) :
{{transcript}}

Notes prises en live (sources fiables) :
{{notes}}
"""
```

### 3.6 Fichiers impactés

| Path | Change |
|---|---|
| `OneToOne/Services/ReportTemplating.swift` | +`ProjectsContextBuilder` enum + ajout case dans `TemplateVariableResolver.resolve` |
| `OneToOne/Services/AIReportService.swift` | Détection `{{collab.projects_context}}` + append fallback |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` | Colonne `Projet` conditionnelle dans `renderActionsBlock` |
| `OneToOne/Services/BuiltInTemplates.swift` | `d2_oneToOne.promptBody` mis à jour + revision marker bump à 3 |
| `Tests/ProjectsContextBuilderTests.swift` (new) | Tests rendu : 1:1 sans partenaire, partenaire sans projets, tri statuts, troncature, max 5 projets |
| `Tests/ReportHTMLBuilderTests.swift` | Ajout 2 tests : colonne Projet activée / désactivée |

Total : 4 modifs, 1 nouveau test, +1 modif test existant.

## 4. UX details

- Pour le **mode .preview** (in-app + PDF) : la colonne Projet apparaît comme les autres (header navy, alternance lignes). Pas de changement de rendu.
- Pour le **mode .outlook** : la colonne s'ajoute aux 4 colonnes existantes (5 colonnes au total). Le inliner respecte les styles td/th existants.
- Si un projet n'a aucun résumé de réunion → la sous-section "3 derniers points discutés" affiche `(aucun historique disponible)` au lieu d'être vide.
- Si un projet n'a aucune action ouverte → la sous-section "Actions ouvertes" affiche `(aucune action ouverte)`.
- Si `meeting.kind != .oneToOne` → `ProjectsContextBuilder.build` retourne `""` ; la variable est remplacée par une chaîne vide ; pas de section "Contexte projets affectés" en append.

## 5. Erreurs / edge cases

- Partenaire archivé (`isArchived == true`) : on inclut quand même ses projets dans le contexte (l'utilisateur a explicitement créé ce 1:1).
- Projet archivé (`isArchived == true`) : exclu du contexte.
- Plus de 5 projets éligibles : tri par statut puis nom alpha, on coupe à 5.
- Résumés tronqués au dernier `.` ou newline avant 1500 chars pour éviter coupures milieu de phrase.
- Budget total dépassé : on coupe les projets de fin de liste plutôt que tronquer chaque résumé davantage (préserve la lisibilité des projets restants).

## 6. Tests

### 6.1 `ProjectsContextBuilderTests`

```swift
func test_nonOneToOneMeeting_returnsEmpty()
func test_oneToOneWithoutPartnerProjects_returnsEmpty()
func test_oneToOneWithOneProject_includesProjectAndTop3Summaries()
func test_oneToOneWithMultipleProjects_sortedRedYellowGreen()
func test_oneToOneWithMoreThan5Projects_truncatesTo5()
func test_oneToOneArchivedProject_excluded()
func test_oneToOneWithActions_listsOpenTasksMax10()
```

### 6.2 `ReportHTMLBuilderTests` (additions)

```swift
func test_oneToOneActionsTable_singleProject_noProjectColumn()
func test_oneToOneActionsTable_multipleProjects_includesProjectColumn()
func test_nonOneToOneActionsTable_noProjectColumn()
```

### 6.3 Smoke manuel

1. Réunion 1:1 avec un partenaire archi de 2+ projets → générer rapport → vérifier que le prompt LLM contient `## CODE · Nom (statut: …)` pour chaque projet.
2. Idem → rapport rendu → colonne Projet visible dans Plan d'actions.
3. Réunion 1:1 sans projets affectés au partenaire → pas de section "Contexte projets affectés".
4. Réunion COPIL projet → pas de variable `{{collab.projects_context}}` injectée (kind != oneToOne).

## 7. YAGNI

- Pas de RAG sémantique cross-projet (sub-projet 3).
- Pas de paramètre `projectsContextN` configurable.
- Pas de filtrage temporel (dernières N jours seulement).
- Pas de personnalisation du format texte.
- Pas d'inclusion des actions COMPLÉTÉES.
- Pas de regroupement par sponsor / entité.
- Pas de différenciation visuelle archi vs PM dans la colonne Projet (juste le code).

## 8. Migration

- Aucune migration SwiftData lourde.
- `BuiltInTemplates.seedIfNeeded` voit le marker `BuiltInTemplates.d2OneToOneRevision` à 3 (était 2) → écrase le promptBody pour les utilisateurs existants au prochain lancement. Si l'utilisateur avait personnalisé son template manuellement, perte de ses modifs (cf. discussion précédente — backfill explicite accepté pour cette série).
- Sub-projet 1 (relations inverse) doit être livré : `partner.projectsAsArchitect` et `projectsAsManager` doivent exister.

## 9. Livrables

- `OneToOne/Services/ReportTemplating.swift` modifié
- `OneToOne/Services/AIReportService.swift` modifié
- `OneToOne/Services/Report/ReportHTMLBuilder.swift` modifié
- `OneToOne/Services/BuiltInTemplates.swift` modifié (promptBody + revision marker)
- `Tests/ProjectsContextBuilderTests.swift` nouveau
- `Tests/ReportHTMLBuilderTests.swift` modifié (3 nouveaux tests)

Spec ready.
