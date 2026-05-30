# Rapport — refactor templates + flow simplifié — Design

**Date:** 2026-05-22

## 1. Objet

Refondre la génération du rapport autour de templates 100 % éditables, supprimer la boucle Auto/Critiquer/Réviser/Valider, déplacer l'ajout au rapport manager sur clic-droit, rendre les actions auto-extraites éditables, et enrichir la génération avec le texte des attachments (pptx, pdf, …).

## 2. Décisions actées

1. `ReportTemplate` gagne un champ `preamble: String` (default seed = préambule actuel). Plus rien de hardcoded dans la chaîne de prompt côté génération.
2. Plus de schéma JSON dans le prompt de génération. LLM produit du **markdown libre**.
3. Extraction structurée (`actions`, `alerts`, `decisions`, `openQuestions`, `keyPoints`) = **2e passe LLM** avec prompt hardcoded documenté.
4. Boutons rapport → un seul **"Générer"**. Pas de versionnement UI. La génération écrase `Meeting.summary`.
5. "Ajouter au rapport manager" = **clic-droit sur sélection de texte** uniquement (plus de ✨ par puce).
6. Task rows (auto ou manuel) : assignee et échéance éditables inline via les mêmes menus que le quick-add.
7. LLM-extracted assignee résolu fuzzy contre participants → favoris → tous collabs. Sinon `unresolvedAssigneeName` stocké et chip cliquable.
8. Import pptx/docx/xlsx/pdf = **extraction texte 100 % script** (déjà OK), feed `MeetingAttachment.extractedText` + chunks RAG.
9. Génération rapport injecte une section "Documents joints" avec `extractedText` concaténés (tronqué, fallback RAG si dépassement budget).

## 3. Architecture

### 3.1 Génération du prompt rapport

```
finalPrompt = """
\(template.preamble)

\(template.promptBody résolu via TemplateVariableResolver)

\(historyAppendix)   ← selon template.historyMode

\(attachmentsBlock)  ← nouvelle section, voir §3.5

\(sectionsBlock)     ← template.sections
"""
```

Plus de "Réponds EXCLUSIVEMENT en JSON" — supprimé du code source.

### 3.2 Extraction 2e passe

Nouvelle fonction `AIReportService.extractStructured(markdown: String, meeting: Meeting, settings: AppSettings) async -> ExtractedFacts`.

- Prompt hardcoded mais commenté dans le code (raison documentée).
- Sortie JSON strict : `{ keyPoints, decisions, openQuestions, actions[{title, assignee?, deadline?}], alerts[{title, detail, severity}] }`.
- Si parsing échoue → on garde le markdown, structuré vide, log warning.
- Appelée juste après `generate(...)` retourne le markdown.

### 3.3 Suppression boutons rapport

| Avant | Après |
|---|---|
| Auto / Critiquer / Réviser / Valider | **Générer** seul |
| Picker version `v1…vN` | Supprimé |
| `currentRevision`, `isCritiquing`, `isRevising`, `isAutoLooping` states | Supprimés |
| `runCritique`, `runRevise`, `runAutoLoop`, `validateCurrentRevision` | Supprimés |

`ReportRevision` modèle conservé en DB (pas de drop destructif lightweight migration risqué) mais plus écrit ni lu côté UI. Chaque génération overwrite `Meeting.summary` uniquement. Si besoin debug futur → rollback DB manuel possible.

### 3.4 Clic-droit "Ajouter au rapport manager"

- `MeetingReportTab` rendu markdown (Text ou MarkdownEditor selon impl actuelle) gagne un `NSMenu` contextuel.
- Item visible uniquement si sélection texte non-vide.
- Action : ouvre la sheet `ManagerReportAddSheet` existante pré-remplie avec `extrait = selectedText`, `texteDuPoint = selectedText`.
- Suppression des ✨ icons par puce dans le rendu (cherche `addToManagerButton` / similaire).

### 3.5 Documents joints au prompt

```swift
// Dans AIReportService.generate
let attachments = meeting.attachments.compactMap { att -> (String, String)? in
    guard let txt = att.extractedText, !txt.isEmpty else { return nil }
    return (att.fileName, txt)
}
let budget = 30_000 - resolved.count - history.count
var attachmentsBlock = ""
if !attachments.isEmpty && budget > 1000 {
    let perAttachment = budget / max(1, attachments.count)
    attachmentsBlock = "\n\n# Documents joints à cette réunion\n"
    for (name, txt) in attachments {
        attachmentsBlock += "## \(name)\n"
        attachmentsBlock += String(txt.prefix(perAttachment)) + "\n\n"
    }
}
```

Si le budget total est dépassé (résolu + history déjà énorme) → on saute le bloc et compte sur le RAG (déjà indexé) via `additionalContext`.

### 3.6 Édition inline actions

`MeetingActionsSidebar.taskRow(_:)` modifié : "Non assigné" et "Pas d'échéance" deviennent des menus identiques à `quickAddRow`.

- Assignee menu : Participants / Favoris / + Ajouter… (factorise depuis `assigneeMenu` quick-add → helper paramétré qui prend une binding `Collaborator?`).
- Échéance menu : Aucune / Aujourd'hui / Demain / Dans 1 semaine / Personnalisée (DatePicker).

Si `task.unresolvedAssigneeName != nil` → chip orange "💡 Auto : <nom>" cliquable au-dessus du menu, qui ouvre la sheet recherche avec le nom pré-rempli.

### 3.7 Résolution fuzzy assignee

Helper `CollaboratorMatcher.match(name: String, in meeting: Meeting, all: [Collaborator]) -> Collaborator?` :

1. Normalise : lowercase + suppression accents (`folding(options: .diacriticInsensitive, locale: .current)`)
2. Exact match contre `meeting.participants`
3. Exact match contre `pinLevel >= 1`
4. Exact match contre `all`
5. Contains-match (le prénom du LLM dans `c.name` ou inversement) avec score minimum 80 % du plus court
6. Retourne nil si ambigu (>1 match avec scores égaux)

Si nil → `task.unresolvedAssigneeName = nameLLM`.

### 3.8 Modèles modifiés

```swift
// ReportTemplate
var preamble: String = "Tu es l'assistant de synthèse de OneToOne."

// ActionTask
var unresolvedAssigneeName: String? = nil
```

Lightweight migration (optionnel + default).

### 3.9 Built-in templates

Tous les 12 built-in (`BuiltInTemplates.swift`) reseedés avec `preamble` valant le préambule actuel. Les templates customs existants gardent default = préambule actuel via SwiftData default value.

## 4. UI

### 4.1 Onglet Rapport

```
┌───────────────────────────────────────────────────────────┐
│ Préparation │ Notes live │ Transcription │ Rapport ✓ │ … │
├───────────────────────────────────────────────────────────┤
│                                            [✨ Générer]   │
│                                                            │
│  # Compte-rendu projet …                                  │
│  …                                                         │
└───────────────────────────────────────────────────────────┘
```

**Un seul bouton**. Pas de Auto/Critiquer/Réviser/Valider. Pas de picker version.

### 4.2 Clic-droit rapport

User sélectionne texte → clic-droit → menu :
- Copier
- **Ajouter au rapport manager…** (item nouveau, visible si sélection non-vide)

### 4.3 Task row enrichie

```
┌──────────────────────────────────────────────────┐
│ ⚪ Étudier la connectivité réseau…           ⋯  │
│   👤 [Jean Marc BARBA ▾]  📅 [11 mai 2026 ▾]   │
│   💡 Auto : Jean Marc BARBA  ← chip si unresolved│
└──────────────────────────────────────────────────┘
```

## 5. Erreurs

- Génération échoue → toast erreur, summary inchangé.
- Extraction 2e passe échoue → markdown préservé, structuré vide, log.
- Document attachment extraction vide → ignoré silencieusement (cas normal).
- Matcher fuzzy ambigu → `unresolvedAssigneeName` stocké, UI chip orange.

## 6. Tests

- `CollaboratorMatcher` : tests unitaires (exact, accents, fuzzy, ambigu).
- `AIReportService.extractStructured` : test JSON parsing avec markdown sample.
- Manual smoke :
  1. Édite préambule du template "Suivi Projet" → génère → vérifier préambule pris en compte.
  2. Générer un rapport → actions s'affichent avec menus éditables.
  3. Clic-droit sur sélection rapport → "Ajouter au rapport manager" → sheet pré-remplie.
  4. Drop un pptx en attachment → générer rapport → le rapport mentionne contenu pptx.

## 7. YAGNI

- Pas de prompt extraction éditable (hardcoded mais commenté).
- Pas de UI historique versions.
- Pas de UI pour exclure attachment du contexte rapport.
- Pas d'auto-loop critique.
- Pas de validation/verrouillage version finale.

## 8. Migration

- `ReportTemplate.preamble` ajout (default seed = ancien préambule hardcoded).
- `ActionTask.unresolvedAssigneeName` ajout (Optional).
- Run `BuiltInTemplates.seedIfNeeded` au démarrage : si `preamble.isEmpty` sur un built-in connu, on backfill avec le default seed.
- `ReportRevision` table préservée mais plus écrite. Lecture restreinte à debug DB.

## 9. Livrables

- `OneToOne/Models/ReportTemplate.swift` modifié (preamble)
- `OneToOne/Models/OtherModels.swift` modifié (ActionTask.unresolvedAssigneeName)
- `OneToOne/Services/AIReportService.swift` réécrit (generate sans schéma JSON, +extractStructured, +attachmentsBlock)
- `OneToOne/Services/CollaboratorMatcher.swift` nouveau
- `OneToOne/Services/BuiltInTemplates.swift` modifié (preamble dans tous les Seed)
- `OneToOne/Views/MeetingView.swift` modifié (suppression boutons Critiquer/Réviser/Valider/Auto + picker version, garde "Générer")
- `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` modifié (task row inline menus + chip unresolved)
- `OneToOne/Views/Meeting/MeetingReportTab.swift` modifié (contextMenu + suppression ✨ par puce)
- `OneToOne/Views/Settings/ReportTemplateEditorView.swift` modifié (champ Préambule)
- Tests `Tests/CollaboratorMatcherTests.swift`, `Tests/AIReportServiceExtractTests.swift`

Spec ready.
