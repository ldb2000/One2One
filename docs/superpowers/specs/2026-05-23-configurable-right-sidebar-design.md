# Right Sidebar configurable + Projets affectés (1:1) — Design

**Date:** 2026-05-23

## 1. Objet

Refondre la sidebar droite de la vue réunion en un container configurable hébergeant plusieurs **panels** : Actions (existant), Projets affectés (nouveau), Capture (existant). L'utilisateur peut :
- **Réordonner** par drag & drop des en-têtes de panels.
- **Afficher / masquer** chaque panel via un menu engrenage.
- Configuration persistée dans `AppSettings`.

Sub-projet **2a / 3** de la roadmap Project Ownership. Foundation UI pour sub-projet **2b** (contextualisation LLM via panneau Projets).

## 2. Décisions actées

1. Container unique `ConfigurableRightSidebar` remplace l'actuel `MeetingActionsSidebar`. Le rail replié et le header restent au niveau container.
2. 3 panels en V1 : `actions`, `projects`, `capture`. Enum extensible.
3. Drag-reorder via SwiftUI `.onDrag` / `.onDrop` sur les headers.
4. Show/hide via popover engrenage (⚙) dans le header. Bouton "Réinitialiser".
5. Layout persisté en JSON dans `AppSettings.rightSidebarLayoutJSON`. Default seed = tous visibles dans l'ordre `[actions, projects, capture]`.
6. Panel "Projets affectés" visible uniquement pour `meeting.kind == .oneToOne` ET le partenaire a `projectsAsArchitect.nonEmpty || projectsAsManager.nonEmpty`. Sinon, dans la config, le toggle reste actif mais le panel affiche un état vide informatif.
7. ActionsPanel et CapturePanel extraits de l'actuel `MeetingActionsSidebar` (pure refactor, comportement préservé).

## 3. Architecture

### 3.1 Modèle

`AppSettings` gagne :
```swift
/// Layout configuré de la sidebar droite des réunions.
/// JSON : `[{"id":"actions","visible":true}, …]`. Vide → seed par défaut.
var rightSidebarLayoutJSON: String = ""
```

Helper computed `rightSidebarLayout: [PanelLayoutEntry] { get set }` qui décode/encode (cf. `captureBlacklist` existant).

### 3.2 Enum `RightSidebarPanelID`

```swift
enum RightSidebarPanelID: String, CaseIterable, Codable, Identifiable {
    case actions
    case projects
    case capture

    var id: String { rawValue }
    var defaultTitle: String { … }
    var systemImage: String { … }
}
```

| Case | Titre par défaut | SF Symbol |
|---|---|---|
| `.actions` | Actions | `checklist` |
| `.projects` | Projets affectés | `folder.fill` |
| `.capture` | Capture | `camera` |

### 3.3 Struct `PanelLayoutEntry`

```swift
struct PanelLayoutEntry: Codable, Identifiable, Equatable {
    let id: RightSidebarPanelID
    var visible: Bool
}
```

Helper `defaultLayout: [PanelLayoutEntry]` = tous visibles dans l'ordre enum.

### 3.4 Container `ConfigurableRightSidebar`

```swift
struct ConfigurableRightSidebar: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Binding var collapsed: Bool

    // Panels props pass-through (rétro-compat de MeetingActionsSidebar):
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    // … etc, héritées de l'ancien sidebar
}
```

Render :
- Si `collapsed` → `collapsedRail` (inchangé).
- Sinon → VStack :
  - Header (Titre "ACTIONS" → maintenant "PANNEAUX" + ⚙ gear + bouton collapse).
  - ScrollView avec `ForEach(visibleEntries)` qui dispatch sur le bon panel selon `id`.

### 3.5 Drag-reorder

Header de chaque panel (`PanelHeader` sous-vue) :
- `.onDrag { NSItemProvider(object: entry.id.rawValue as NSString) }`
- `.onDrop(of: [.text], delegate: PanelDropDelegate(target: entry, entries: $entries, save: …))`

Pendant le drag : opacity 0.5. Au drop : swap dans `entries` array + persist.

### 3.6 Show/hide popover

Bouton ⚙ dans le header de la sidebar (à côté du bouton collapse) → popover :
```
Panneaux visibles
─────────────────
☑ Actions
☑ Projets affectés
☑ Capture
─────────────────
[ Réinitialiser ]
```

Toggle = met à jour `entry.visible` + persist. "Réinitialiser" = restore `defaultLayout`.

### 3.7 ActionsPanel (extract)

Vue extraite de `MeetingActionsSidebar`. Contient `tasksList` + `formSection`. Reçoit en props :
```swift
struct ActionsPanel: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?
    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let saveContext: () -> Void
}
```

Body identique à l'actuel (taskRow + formSection + helpers menus assignee/duedate/unresolved chip). Pas de logique nouvelle, juste relocation.

### 3.8 ProjectsPanel (nouveau)

```swift
struct ProjectsPanel: View {
    let meeting: Meeting

    private var partner: Collaborator? {
        meeting.kind == .oneToOne ? meeting.participants.first : nil
    }
}
```

Affichage :
- Si `partner == nil` (réunion non-1:1) : message *"Visible uniquement pour les 1:1."*
- Si `partner` n'a aucun projet : *"Pas de projet affecté à ce collaborateur."*
- Sinon 2 sous-sections triées Red→Yellow→Green→Unknown :
  - `EN TANT QU'ARCHITECTE (N)` + rows
  - `EN TANT QUE CHEF DE PROJET (N)` + rows

Chaque row :
- Dot statut + code projet (mono) + nom + chip statut + chip `(N act)` = nb actions ouvertes du projet (via `project.actionTasks.filter { !$0.isCompleted }.count` — déjà accessible)
- `NavigationLink` → `ProjectDetailView(project: p)`

Réutilise les helpers `projectStatusColor(_:)` et `sortedByStatus(_:)` créés dans sub-projet 1 sur `CollaboratorDetailView`. **Extract** ces helpers dans un fichier partagé `Views/Shared/ProjectStatusPalette.swift` au cours de ce sub-projet 2a.

### 3.9 CapturePanel (extract)

Vue extraite du `capturePreviewCard` existant. Props :
```swift
struct CapturePanel: View {
    let currentSlides: [SlideCapture]
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
}
```

Comportement strictement identique.

### 3.10 Fichiers impactés

| Path | Change |
|---|---|
| `OneToOne/Models/AppSettings.swift` | +`rightSidebarLayoutJSON` + helpers |
| `OneToOne/Views/Shared/ProjectStatusPalette.swift` (nouveau) | extract helpers `projectStatusColor`, `sortedByStatus` |
| `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift` (nouveau) | enum + métadonnées |
| `OneToOne/Views/Meeting/Sidebar/PanelLayoutEntry.swift` (nouveau) | struct + default layout |
| `OneToOne/Views/Meeting/Sidebar/PanelHeader.swift` (nouveau) | header + drag handle + collapse caret |
| `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` (nouveau) | extract du tasksList + formSection |
| `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` (nouveau) | nouveau panel projets |
| `OneToOne/Views/Meeting/Sidebar/CapturePanel.swift` (nouveau) | extract du capturePreviewCard |
| `OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift` (nouveau) | container drag-reorder + show/hide popover |
| `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` (à supprimer ou laisser en stub) | l'ancien fichier devient redondant |
| `OneToOne/Views/MeetingView.swift` (modify) | remplace `MeetingActionsSidebar(...)` par `ConfigurableRightSidebar(...)` |
| `OneToOne/Views/DetailsViews.swift` (modify) | `CollaboratorDetailView.projectStatusColor` + `sortedByStatus` retirés, remplacés par `ProjectStatusPalette.*` |

Total : 7 nouveaux fichiers, 3 modifications, 1 suppression.

### 3.11 Stratégie de migration de `MeetingActionsSidebar.swift`

L'ancien fichier contient :
- la struct `MeetingActionsSidebar` (à supprimer)
- les helpers `rowAssigneeMenu`, `rowDueDateMenu`, `taskRow`, etc.

Ces helpers déménagent dans `ActionsPanel.swift` (refactor pur, pas de logique changée). Une fois la migration faite et le call-site dans `MeetingView` mis à jour, le fichier `MeetingActionsSidebar.swift` peut être supprimé.

`AddCollaboratorSheet` reste où il est (déjà extrait sub-projet 1).

## 4. UX details

- Drag : seul le header est draggable, pas le contenu (évite frictions avec scroll/édition interne).
- Drop indicator : pendant le drag, un séparateur bleu apparaît à la position cible.
- Sidebar repliée (`collapsed: true`) : drag/show-hide indisponibles, juste le rail vertical avec icones panneaux (cliquer = ré-expand).
- Popover ⚙ : esc ou clic outside ferme.
- Lors du premier lancement après migration : `rightSidebarLayoutJSON == ""` → default layout appliqué automatiquement par le helper computed.

## 5. Erreurs / edge cases

- JSON corrompu en DB → fallback `defaultLayout`, le getter log un warning silencieux.
- Nouvel panel ajouté en V2 (ex. `.notes`) → si pas présent dans le layout sauvegardé, ajouté en queue avec `visible: true` lors du load.
- Panel `.projects` avec collab sans projet → affiche l'état vide informatif (pas masqué silencieusement).
- Drag sur une seule entrée visible : drop no-op.

## 6. Tests

- Unitaire `PanelLayoutEntryTests` :
  - Round-trip JSON encode/decode.
  - Fallback default si JSON vide.
  - Migration : ajout en queue d'un nouveau case enum non présent dans le JSON sauvegardé.
- Smoke manuel :
  1. Ouvrir une réunion 1:1 avec un partenaire archi de 2 projets. Vérifier panneau Projets visible avec les 2 projets et leur statut.
  2. Drag header "Projets" au-dessus de "Actions" → reorder visible, persiste après relance.
  3. ⚙ → décocher "Capture" → panneau disparait, persiste après relance.
  4. Click row projet → navigue vers ProjectDetailView.
  5. Réunion non-1:1 (ex: COPIL projet) → panneau Projets affiche message d'état vide.

## 7. YAGNI

- Pas de redimensionnement vertical de chaque panel.
- Pas de panels "épinglés en haut".
- Pas de thèmes / variantes de couleur.
- Pas de panels custom user-defined.
- Pas de sauvegarde layout par-meeting (un seul layout global).

## 8. Migration / compatibilité

- Aucune migration SwiftData lourde (1 champ String avec default vide).
- Le call-site dans `MeetingView` doit être unique (un seul endroit instancie `MeetingActionsSidebar`). Vérifier au préalable.
- Suppression complète du fichier `MeetingActionsSidebar.swift` après remplacement.

## 9. Livrables

- `OneToOne/Models/AppSettings.swift` modifié
- 7 nouveaux fichiers sous `OneToOne/Views/Meeting/Sidebar/`
- `OneToOne/Views/Shared/ProjectStatusPalette.swift` nouveau
- `OneToOne/Views/MeetingView.swift` modifié (call-site)
- `OneToOne/Views/DetailsViews.swift` modifié (utilise ProjectStatusPalette)
- `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` supprimé
- `Tests/PanelLayoutEntryTests.swift` nouveau

Spec ready.
