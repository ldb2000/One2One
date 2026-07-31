# Actions enrichies — Sous-projet 1 : Fondations (destinataire + priorité)

Date : 2026-07-11 · Branche : `feat/Actions-enhanced`

## Contexte

Le modèle `ActionTask` (titre, assignee `collaborator`, `dueDate`, `isCompleted`,
`fromManager`, commentaires) ne distingue pas **à qui/pourquoi** sert une action,
ni sa **priorité**. On veut gérer les actions selon leur destinataire
(collaborateur / moi / remontée au chef) et poser les bases d'une matrice
Eisenhower. Surface retenue : une **carte Actions à sélecteur de vue** dans le
dashboard (redimensionnable via le système de cartes existant).

Ce lot est le socle ; les 5 vues (Eisenhower, Kanban, Calendar, Timeline, Sticky)
et l'intégration à `ActionsListView`/`ManagerReportItem` sont des lots ultérieurs.

## Modèle

`ActionTask` (migration légère SwiftData — champs additifs à valeur par défaut) :
- `destinataireRaw: String = ActionAudience.moi.rawValue` + wrapper calculé
  `destinataire: ActionAudience` (convention Raw+wrapper du projet).
- `isUrgent: Bool = false`
- `isImportant: Bool = false`
- `sortOrder: Int = 0` (ordre manuel, utilisé par les vues suivantes).

Nouvel enum :
```swift
enum ActionAudience: String, Codable, CaseIterable, Sendable {
    case collaborateur   // déléguée à un collaborateur (assignee = collaborator)
    case moi             // pour moi
    case chef            // à remonter à mon manager
}
// label + systemImage + couleur d'accent par cas
```

Champs existants conservés : `collaborator` reste l'assignee (pertinent surtout
quand `destinataire == .collaborateur`) ; `fromManager`/`managerMeeting`
inchangés (orthogonaux).

Migration : les actions existantes prennent `destinataire = .moi` par défaut
(l'utilisateur re-catégorise) ; pas de backfill automatique dans ce lot.

## UI — carte Actions

**Saisie (« Nouvelle action »)** :
- Sélecteur **destinataire** : Collaborateur / Moi / Chef. En mode Collaborateur,
  le picker d'assignee existant reste visible ; sinon masqué.
- Deux bascules compactes **Urgent** / **Important**.
- Défaut : réunion `.oneToOne` → destinataire = Collaborateur + partenaire
  pré-sélectionné ; sinon → Moi.

**Édition par ligne** : menu existant (assignee, échéance) complété par
destinataire + urgent/important. Une pastille de priorité (couleur selon
quadrant urgent×important) est affichée sur la ligne.

**Vue** : liste **groupée par destinataire** en 3 sections —
*Mes actions* (moi) · *Déléguées* (collaborateur, sous-groupées par assignee si
pertinent) · *À remonter au chef* (chef). Les actions terminées restent en bas
de leur groupe (comportement actuel conservé).

**Scaffold sélecteur de vue** : un `enum ActionsViewMode` + un `Picker` segmenté
dans l'en-tête de la carte (`DashboardCard.headerActions`). Un seul mode dans ce
lot : `.liste` (groupée par destinataire). Les modes Eisenhower/Kanban/… seront
ajoutés aux lots suivants sans refonte.

## Plomberie

`MeetingView` détient l'état du brouillon de nouvelle action ; on ajoute
`newTaskAudience`, `newTaskUrgent`, `newTaskImportant` (bindings passés via
`OverviewDashboard` → `ActionsPanel`, comme les champs existants). `addTask()`
applique ces champs + le défaut selon `meeting.kind`.

## Périmètre / non-objectifs

- **Touché** : `OtherModels.swift` (ActionTask + enum), `ActionsPanel.swift`,
  `MeetingView.swift` (addTask + bindings), `OverviewDashboard.swift` (passage
  des bindings).
- **Inchangé** : `ActionsListView` (liste globale), `ManagerReportItem`, les
  popovers menubar, les 5 vues visuelles.

## Vérification

- Build + test manuel in-app : créer une action pour chaque destinataire, régler
  urgent/important, vérifier le regroupement en 3 sections et la persistance
  (migration OK au lancement). Éditer une action existante.
