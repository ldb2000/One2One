# Meeting preparation — design

> **Status:** Draft (à valider avant plan d'implémentation)
> **Date:** 2026-05-19
> **Owner:** Laurent De Berti

## Objet

Permettre de préparer une réunion en amont : noter des questions, points à aborder, infos à partager, sous forme de markdown avec checkboxes interactives. Trois cas distincts :

1. **1:1 (oneToOne / manager)** : prep persistante attachée au `Collaborator`. Pas besoin de meeting concrète. Accessible depuis la vue collab et depuis la menubar.
2. **Projet** : prep persistante attachée au `Project`, vise la prochaine réunion projet. Pas besoin de date. Accessible depuis la vue projet et la menubar.
3. **Global / Work** : prep attachée à une `Meeting` spécifique (calendrier requis). Accessible depuis le tab Préparation de cette meeting.

Items non cochés à la fin d'un meeting → repoussés automatiquement dans le pool standing correspondant (collab ou projet). Pas de carryover pour global/work.

## Architecture

```
Models/
  OtherModels.swift (modify)
    - Collaborator + standingPrepNotes, standingPrepUpdatedAt
    - Meeting        + prepNotes, prepGeneratedAt, prepCarryoverDone
  Project.swift (modify)
    - Project        + standingPrepNotes, standingPrepUpdatedAt
  AppSettings.swift (modify)
    - prepAutoCarryover: Bool = true

Services/
  AIReportService.swift (extend)
    - generatePrep(collab:project:meeting:in:settings:) -> String
  PrepCarryoverService.swift (new)
    - drainStandingIntoMeeting(meeting:in:)
    - carryoverUncheckedFromMeeting(meeting:in:)
    - extractUncheckedItems(from:) -> [String]

Views/
  MeetingView.swift (modify)
    - new MeetingSection case .preparation
    - MeetingPrepTab subview
  MeetingPrepTab.swift (new)
    - éditeur markdown + panneau contexte
  MeetingPrepContextPanel.swift (new)
    - actions ouvertes, derniers points, alertes
  CollaboratorDetailView (modify)
    - section "Préparation prochaine 1:1"
  ProjectDetailView (modify)
    - section "Préparation prochaine réunion"
  Menubar (MenuBarController modify)
    - sous-menu "Préparer…"
  PrepWindow.swift (new)
    - fenêtre dédiée pour édition standing prep depuis menubar
  CalendarMeetingPicker.swift (new)
    - sheet pour cas global/work
```

## Modèles

### Collaborator
```swift
var standingPrepNotes: String = ""
var standingPrepUpdatedAt: Date?
```

### Project
```swift
var standingPrepNotes: String = ""
var standingPrepUpdatedAt: Date?
```

### Meeting
```swift
var prepNotes: String = ""
var prepGeneratedAt: Date?
/// True après drain initial OU après carryover post-meeting (double usage).
/// Garantit l'idempotence des deux opérations.
var prepCarryoverDone: Bool = false
```

### AppSettings
```swift
var prepAutoCarryover: Bool = true
```

Aucun nouveau modèle. Migration lightweight via defaults — aucune intervention manuelle.

## Flux de données

### Drain (standing → meeting)

Déclenché au **plus tard** à la 1re ouverture du tab Préparation d'une `Meeting` dont `prepCarryoverDone == false`. Idéalement, aussi à la création de la meeting si le code créateur a connaissance de collab/projet.

```
guard !meeting.prepCarryoverDone else { return }
switch meeting.kind {
case .oneToOne, .manager:
    if let collab = meeting.participants.first, !collab.standingPrepNotes.isEmpty {
        if !meeting.prepNotes.isEmpty {
            meeting.prepNotes = collab.standingPrepNotes + "\n\n" + meeting.prepNotes
        } else {
            meeting.prepNotes = collab.standingPrepNotes
        }
        collab.standingPrepNotes = ""
        collab.standingPrepUpdatedAt = Date()
    }
case .project:
    if let project = meeting.project, !project.standingPrepNotes.isEmpty {
        if !meeting.prepNotes.isEmpty {
            meeting.prepNotes = project.standingPrepNotes + "\n\n" + meeting.prepNotes
        } else {
            meeting.prepNotes = project.standingPrepNotes
        }
        project.standingPrepNotes = ""
        project.standingPrepUpdatedAt = Date()
    }
case .global, .work:
    break  // pas de pool
}
meeting.prepCarryoverDone = true
saveContext()
```

### Carryover (meeting → standing)

Déclenché à la **fin de la transcription** (`onTranscriptionFinished`). Si la meeting n'est pas transcrite, déclenché à la fermeture manuelle du meeting (bouton "Terminer").

```
guard settings.prepAutoCarryover else { return }
guard !meeting.prepCarryoverDone else { return }  // double usage du flag — voir note
let unchecked = PrepCarryoverService.extractUncheckedItems(from: meeting.prepNotes)
guard !unchecked.isEmpty else {
    meeting.prepCarryoverDone = true
    return
}
let block = "<!-- reporté de la réunion \(formatDate(meeting.date)) -->\n" +
            unchecked.joined(separator: "\n") + "\n\n"
switch meeting.kind {
case .oneToOne, .manager:
    if let collab = meeting.participants.first {
        collab.standingPrepNotes = block + collab.standingPrepNotes
        collab.standingPrepUpdatedAt = Date()
    }
case .project:
    if let project = meeting.project {
        project.standingPrepNotes = block + project.standingPrepNotes
        project.standingPrepUpdatedAt = Date()
    }
case .global, .work:
    break  // pas de pool, items perdus (ou utilisateur les copie manuellement)
}
meeting.prepCarryoverDone = true
saveContext()
```

**Note sur `prepCarryoverDone`** : le flag a un double usage temporel — d'abord pour bloquer le drain (déjà fait à la création), ensuite pour bloquer le carryover (à la fin). Comme drain et carryover sont mutuellement exclusifs dans le cycle de vie (drain à la naissance, carryover à la mort), un seul flag suffit. Si on voulait dissocier plus tard : ajouter `prepDrainDone` séparé.

### Extraction des unchecked
```swift
static func extractUncheckedItems(from md: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"^(\s*)- \[ \] (.+)$"#, options: .anchorsMatchLines)
    let ns = md as NSString
    let matches = regex.matches(in: md, range: NSRange(location: 0, length: ns.length))
    return matches.map { m -> String in
        let line = ns.substring(with: m.range)
        return line
    }
}
```

## UI

### MeetingView tab "Préparation"

Layout split 60/40 :

- **Gauche** : éditeur `MarkdownEditorView` lié à `meeting.prepNotes`. Checkboxes interactives (déjà géré par le rendering markdown depuis la session précédente).
- **Droite** : panneau contexte 3 sections collapsibles :
  - **Actions ouvertes** (collab ou projet selon kind)
  - **Derniers points** (3 dernières meetings du couple/projet, titre + date + résumé court)
  - **Alertes** (Élevé/Critique du projet)
  - Chaque item draggable vers l'éditeur (drag = insertion `- [ ] <texte>\n`)
  - Bouton "Tout ajouter" par section

- **Bouton "✨ Générer brouillon IA"** en bas de l'éditeur :
  - Disabled si `prepGeneratedAt != nil` (déjà généré).
  - Confirm modal "Remplacer la préparation actuelle ?" si `prepNotes` non vide.

### CollaboratorDetailView — section prep

```
▼ Préparation prochaine 1:1   [3 items · maj il y a 2j]    [✨ Générer]
  ┌──────────────────────────────────────────────┐
  │ MarkdownEditorView                            │
  │ lié à collab.standingPrepNotes               │
  └──────────────────────────────────────────────┘
```
- Collapsible, replié par défaut si `standingPrepNotes.isEmpty`.
- Pas de panneau contexte ici (la collab detail view affiche déjà actions/notes en parallèle).

### ProjectDetailView — section prep

Identique au cas collab, sur `project.standingPrepNotes`.

### Menubar — sous-menu "Préparer…"

```
Préparer…  ▶
  1:1 ────────────────────────
   👤 Bastien
   👤 Jacqueline
   👤 Nicolas
  Projets ────────────────────
   📁 Architecture transverse
   📁 MEP1
  ────────────────────────────
   Choisir réunion calendrier…
```
- **1:1** : `Collaborator` avec `pinLevel > 0`, triés alpha, max 10.
- **Projets** : 5 projets avec activité récente (réunions < 14j) OU pinned.
- Clic collab/projet → ouvre `PrepWindow` (nouvelle fenêtre via `WindowGroup(id:)`).
- "Choisir réunion calendrier…" → sheet `CalendarMeetingPicker` listant meetings futures avec `scheduledStart`, sélection → ouvre `MeetingView` directement sur tab `.preparation`.

### PrepWindow

Fenêtre standalone avec :
- Header : "Préparation 1:1 — Bastien" (ou "Préparation projet — MEP1")
- Body : `MarkdownEditorView` lié à `standingPrepNotes` du target
- Footer : bouton "✨ Générer" + "Fermer"
- Frame `minWidth: 600, minHeight: 480`

### Badges

| Contexte | Affichage |
|---|---|
| Meeting future, `prepNotes.isEmpty` ET pool standing vide | Capsule orange `⚠ À préparer` dans header meeting |
| Meeting future, contenu non vide quelque part | Capsule verte `✓ Préparée` |
| Collab/Project avec `standingPrepNotes` non vide | Capsule discrète "N items en prep" dans la sidebar / detail view |

## Prompt "Générer brouillon"

Inputs assemblés par `AIReportService.generatePrep(collab:project:meeting:in:settings:)` :

- Si `meeting` fourni : `meeting.title`, `scheduledStart`, agenda (`meeting.notes` si rempli par calendrier)
- Participants nommés (selon kind : "1:1 avec X" ou "réunion projet Y")
- 3 dernières meetings du même couple (1:1) ou projet → titre + date + résumé court
- Actions ouvertes attribuées au collab/projet (titre + échéance + statut)
- Alertes Élevé/Critique du projet
- Notes accumulées sur le collab (dernières 500 chars de `collab.notes`)

Prompt :

```
Tu prépares la réunion "<title|"prochaine 1:1 avec X">" prévue le <date|"prochaine occurrence">.

Participants: <list>
Projet: <name|nil>

Historique récent :
<3 derniers résumés>

Actions ouvertes côté <collab|projet> :
<list>

Alertes en cours :
<list>

Notes accumulées :
<excerpt>

Produis une PRÉPARATION en markdown organisée en sections (omets celles vides) :
- ## Points à aborder
- ## Questions à poser
- ## Décisions à obtenir
- ## Infos à partager

Chaque item = puce checkbox `- [ ] ...`. Reste concis, factuel.
Ne reprends pas tel quel les actions ouvertes sauf si elles méritent
une discussion. Inutile de répéter le contexte historique.
```

Sortie = markdown brut, directement injecté dans `prepNotes` (ou `standingPrepNotes` selon contexte).

## Erreurs gérées

| Cas | Comportement |
|---|---|
| Meeting sans `scheduledStart` | Tab visible, pas de badge "À préparer". Drain skip si pas de participant/projet (mais en pratique kind .oneToOne implique participant). |
| `prepNotes` non vide à l'ouverture | Drain skip (déjà rempli ou drainé). |
| User édite la prep pendant le meeting | Autorisé. |
| Click checkbox | Toggle `[ ]` ↔ `[x]`, save immédiat. |
| Bouton "Générer" écrase prep | Confirm modal obligatoire. |
| LLM down | Erreur bandeau orange, prep manuelle reste possible. |
| Calendrier event sans agenda | Prompt fonctionne (utilise seulement historique + actions). |
| Drag d'un item contexte → éditeur | Insère `- [ ] <texte>\n` au curseur. |
| Carryover de 50 items | OK pas de cap. |
| Source meeting supprimée après carryover | Items déjà copiés, pas de référence — OK. |
| Drain ET prep manuelle non vide | Concatène standing en tête, vide standing. |
| Carryover `.global`/`.work` | Skip, items perdus (mais utilisateur peut copier-coller manuellement avant fermeture). |
| Menubar "Préparer…" → collab archivée | Collab archivée filtrée hors liste. |

## Tests

### Unitaires (`Tests/PrepCarryoverServiceTests.swift`)

```swift
func test_carryover_oneToOne_pushesUncheckedToCollabStandingPool()
func test_carryover_project_pushesUncheckedToProjectStandingPool()
func test_carryover_global_skipsAndMarksFlag()
func test_carryover_idempotent_doesNotDoubleApply()
func test_drain_oneToOne_movesStandingIntoMeetingOnCreate()
func test_drain_clearsStandingAfterMove()
func test_drain_concatenates_whenBothNonEmpty()
func test_extracts_indentedCheckboxesOnly_ignoresChecked()
func test_extracts_ignoresCheckedItems()
func test_carryover_skipsWhenSettingDisabled()
```

### Manuels

- Menubar → "Préparer…" → 1:1 X → fenêtre s'ouvre, édite, ferme, rouvre, persistance OK.
- Créer meeting 1:1 avec X depuis quick-launch → tab Préparation déjà rempli (standing drainé).
- Finir transcription, items non cochés → standing de X repeuplé.
- Tab Préparation sur meeting `.global` future → vide, badge "À préparer".
- ProjectDetailView → section prep visible, édition OK.
- Bouton "Générer brouillon" sur collab sans meeting → produit markdown.
- Badge dans header meeting cycle correctement (vide → "À préparer", rempli → "Préparée").

## YAGNI / hors scope

- Pas de prep partagée entre plusieurs participants (1 collab principal seulement).
- Pas de tracking "qui a coché quoi" (mono-utilisateur).
- Pas de templates de prep (l'utilisateur peut copier-coller depuis un draft persistant).
- Pas de carryover récursif entre standing pools.
- Pas de notification "tu n'as rien préparé pour ta réunion dans 1h" en V1 (peut s'ajouter sur `MeetingNotificationService`).

## Plan d'implémentation

À détailler dans `docs/superpowers/plans/2026-05-19-meeting-preparation-plan.md` via la skill `writing-plans` après validation.
