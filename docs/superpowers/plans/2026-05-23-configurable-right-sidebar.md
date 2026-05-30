# Right Sidebar configurable + Projets affectés Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refondre la sidebar droite de la vue réunion en un container configurable hébergeant 3 panneaux (Actions existant, Projets affectés nouveau, Capture existant), avec drag-reorder, show/hide, et persistance dans `AppSettings`.

**Architecture:** Un container `ConfigurableRightSidebar` orchestre des panels (`ActionsPanel`, `ProjectsPanel`, `CapturePanel`). Layout (ordre + visibilité) sérialisé en JSON dans `AppSettings.rightSidebarLayoutJSON`. Drag via `.onDrag`/`.onDrop` sur les headers. Show/hide via popover engrenage. Le `MeetingActionsSidebar` actuel est démantelé : ses sous-vues deviennent les panels Actions et Capture (refactor pur, comportement identique).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest.

---

## File map

| Path | Responsabilité |
|---|---|
| `OneToOne/Models/AppSettings.swift` (modify) | +`rightSidebarLayoutJSON: String` + helper computed |
| `OneToOne/Views/Shared/ProjectStatusPalette.swift` (new) | `projectStatusColor`, `sortedByStatus` extraits de CollaboratorDetailView |
| `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift` (new) | Enum cases + métadonnées (titre, SF Symbol) |
| `OneToOne/Views/Meeting/Sidebar/PanelLayoutEntry.swift` (new) | Struct Codable + helper `defaultLayout` + migration ajout case manquant |
| `OneToOne/Views/Meeting/Sidebar/PanelHeader.swift` (new) | Header par panel : drag handle + titre + collapse caret |
| `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` (new) | Extrait `tasksList + formSection + helpers` de MeetingActionsSidebar |
| `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` (new) | Nouveau panneau projets archi/PM du collab |
| `OneToOne/Views/Meeting/Sidebar/CapturePanel.swift` (new) | Extrait `capturePreviewCard` |
| `OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift` (new) | Container drag-reorder + popover ⚙ show/hide |
| `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` (delete) | Remplacé entièrement |
| `OneToOne/Views/MeetingView.swift` (modify) | Callsite : `MeetingActionsSidebar(...)` → `ConfigurableRightSidebar(...)` |
| `OneToOne/Views/DetailsViews.swift` (modify) | `CollaboratorDetailView` utilise `ProjectStatusPalette.*` |
| `Tests/PanelLayoutEntryTests.swift` (new) | Round-trip JSON + fallback default + migration |

Total : 8 nouveaux, 4 modifications, 1 suppression.

**Types existants utilisés** :
- `Meeting.kind`, `Meeting.participants`, `Meeting.tasks` ✓
- `Collaborator.projectsAsArchitect`, `projectsAsManager` ✓ (sub-projet 1)
- `Project.code / name / status` ✓
- `AppSettings.captureBlacklistJSON` pattern de référence pour le helper computed
- `MeetingActionsSidebar` API (props) à conserver à l'identique côté MeetingView pour minimiser le diff au callsite

---

### Task 1: AppSettings — `rightSidebarLayoutJSON` + helper

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift`

- [ ] **Step 1: Localiser captureBlacklistJSON**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "captureBlacklistJSON\|var captureBlacklist:" OneToOne/Models/AppSettings.swift
```

Sert de pattern de référence (champ stocké String JSON + computed helper).

- [ ] **Step 2: Ajouter le champ stocké**

Dans `@Model final class AppSettings`, juste après le champ `captureBlacklistJSON` (autour ligne 137), ajouter :

```swift
/// Layout configuré de la sidebar droite des réunions.
/// JSON : `[{"id":"actions","visible":true}, …]`. Vide → defaultLayout
/// est appliqué par le helper computed.
var rightSidebarLayoutJSON: String = ""
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Models/AppSettings.swift
git commit -m "feat(sidebar-config): AppSettings.rightSidebarLayoutJSON pour persistance layout"
```

---

### Task 2: `RightSidebarPanelID` + `PanelLayoutEntry` (TDD)

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift`
- Create: `OneToOne/Views/Meeting/Sidebar/PanelLayoutEntry.swift`
- Create: `Tests/PanelLayoutEntryTests.swift`

- [ ] **Step 1: Écrire les tests failing**

`Tests/PanelLayoutEntryTests.swift` :

```swift
import XCTest
@testable import OneToOne

final class PanelLayoutEntryTests: XCTestCase {

    func test_defaultLayoutContainsAllCasesVisible() {
        let layout = PanelLayoutEntry.defaultLayout
        XCTAssertEqual(layout.count, RightSidebarPanelID.allCases.count)
        XCTAssertTrue(layout.allSatisfy { $0.visible })
        XCTAssertEqual(layout.map(\.id), RightSidebarPanelID.allCases)
    }

    func test_decodeFromJSON_roundTrip() throws {
        let original: [PanelLayoutEntry] = [
            PanelLayoutEntry(id: .projects, visible: true),
            PanelLayoutEntry(id: .actions, visible: false),
            PanelLayoutEntry(id: .capture, visible: true)
        ]
        let json = PanelLayoutEntry.encode(original)
        let decoded = PanelLayoutEntry.decode(json)
        XCTAssertEqual(decoded, original)
    }

    func test_decodeEmpty_returnsDefault() {
        let decoded = PanelLayoutEntry.decode("")
        XCTAssertEqual(decoded, PanelLayoutEntry.defaultLayout)
    }

    func test_decodeCorrupted_returnsDefault() {
        let decoded = PanelLayoutEntry.decode("not json at all")
        XCTAssertEqual(decoded, PanelLayoutEntry.defaultLayout)
    }

    func test_decodeMissingPanel_appendedAsVisible() {
        // L'utilisateur a un layout sauvegardé qui ne contient pas .capture
        // (cas où on a ajouté un nouveau case enum après update). Le décodeur
        // doit l'ajouter en queue avec visible:true.
        let partial: [PanelLayoutEntry] = [
            PanelLayoutEntry(id: .actions, visible: true),
            PanelLayoutEntry(id: .projects, visible: false)
        ]
        let json = PanelLayoutEntry.encode(partial)
        let decoded = PanelLayoutEntry.decode(json)
        XCTAssertEqual(decoded.count, RightSidebarPanelID.allCases.count)
        XCTAssertTrue(decoded.contains { $0.id == .capture && $0.visible })
        // L'ordre original est préservé pour les présents.
        XCTAssertEqual(decoded.first?.id, .actions)
        XCTAssertEqual(decoded[1].id, .projects)
        XCTAssertEqual(decoded.last?.id, .capture)
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter PanelLayoutEntryTests 2>&1 | tail -10
```
Expected: FAIL — `cannot find 'PanelLayoutEntry' / 'RightSidebarPanelID' in scope`.

- [ ] **Step 3: Implémenter `RightSidebarPanelID`**

`OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift` :

```swift
import Foundation
import SwiftUI

/// Identifiants des panels configurables de la sidebar droite des réunions.
/// L'ordre des `allCases` détermine le layout par défaut.
enum RightSidebarPanelID: String, CaseIterable, Codable, Identifiable {
    case actions
    case projects
    case capture

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .actions:  return "Actions"
        case .projects: return "Projets affectés"
        case .capture:  return "Capture"
        }
    }

    var systemImage: String {
        switch self {
        case .actions:  return "checklist"
        case .projects: return "folder.fill"
        case .capture:  return "camera"
        }
    }
}
```

- [ ] **Step 4: Implémenter `PanelLayoutEntry`**

`OneToOne/Views/Meeting/Sidebar/PanelLayoutEntry.swift` :

```swift
import Foundation

/// Entrée du layout sidebar — id + visibility. Sérialisé en JSON dans
/// `AppSettings.rightSidebarLayoutJSON`.
struct PanelLayoutEntry: Codable, Identifiable, Equatable {
    let id: RightSidebarPanelID
    var visible: Bool

    /// Layout par défaut : tous les panels dans l'ordre `RightSidebarPanelID.allCases`,
    /// tous visibles.
    static var defaultLayout: [PanelLayoutEntry] {
        RightSidebarPanelID.allCases.map { PanelLayoutEntry(id: $0, visible: true) }
    }

    /// Encode un array en JSON pour persistance. Renvoie `""` si l'encodage
    /// échoue (sera détecté comme empty et fallback au default au prochain decode).
    static func encode(_ entries: [PanelLayoutEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Décode le JSON stocké. Fallback `defaultLayout` si :
    /// - le JSON est vide ou corrompu
    /// - un case enum est manquant (migration : ajout en queue avec visible:true)
    static func decode(_ json: String) -> [PanelLayoutEntry] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PanelLayoutEntry].self, from: data),
              !decoded.isEmpty else {
            return defaultLayout
        }

        // Migration : si un case enum a été ajouté après la sauvegarde de l'utilisateur,
        // l'ajouter en queue avec visible:true. Préserve l'ordre des panels existants.
        let presentIDs = Set(decoded.map(\.id))
        let missing = RightSidebarPanelID.allCases
            .filter { !presentIDs.contains($0) }
            .map { PanelLayoutEntry(id: $0, visible: true) }
        return decoded + missing
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter PanelLayoutEntryTests 2>&1 | tail -10
```
Expected: PASS 5/5.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift OneToOne/Views/Meeting/Sidebar/PanelLayoutEntry.swift Tests/PanelLayoutEntryTests.swift
git commit -m "feat(sidebar-config): RightSidebarPanelID + PanelLayoutEntry + migration ajout case"
```

---

### Task 3: ProjectStatusPalette — extract helpers partagés

**Files:**
- Create: `OneToOne/Views/Shared/ProjectStatusPalette.swift`
- Modify: `OneToOne/Views/DetailsViews.swift` (utilise le palette extrait)

- [ ] **Step 1: Créer le fichier extrait**

`OneToOne/Views/Shared/ProjectStatusPalette.swift` :

```swift
import SwiftUI

/// Couleurs et tri pour `Project.status` ("Red", "Yellow", "Green", "Unknown").
/// Extrait depuis CollaboratorDetailView pour partage avec ProjectsPanel
/// (sidebar configurable des réunions).
enum ProjectStatusPalette {

    /// Couleur SwiftUI pour un statut projet.
    static func color(_ status: String) -> Color {
        switch status {
        case "Red":     return .red
        case "Yellow":  return .orange
        case "Green":   return .green
        default:        return .gray
        }
    }

    /// Tri : Red → Yellow → Green → Unknown, puis alpha case-insensible.
    static func sortedByStatus(_ projects: [Project]) -> [Project] {
        let rank: [String: Int] = ["Red": 0, "Yellow": 1, "Green": 2, "Unknown": 3]
        return projects.sorted { a, b in
            let ra = rank[a.status] ?? 3
            let rb = rank[b.status] ?? 3
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 2: Localiser les copies privées dans CollaboratorDetailView**

```bash
grep -n "func projectStatusColor\|func sortedByStatus" OneToOne/Views/DetailsViews.swift
```

- [ ] **Step 3: Remplacer les appels et supprimer les helpers privés**

Dans `OneToOne/Views/DetailsViews.swift`, dans `CollaboratorDetailView` :

- Remplacer chaque appel `projectStatusColor(p.status)` par `ProjectStatusPalette.color(p.status)`.
- Remplacer chaque appel `sortedByStatus(projects)` par `ProjectStatusPalette.sortedByStatus(projects)`.
- Supprimer les fonctions privées `private func projectStatusColor(_:)` et `private func sortedByStatus(_:)` du struct.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Shared/ProjectStatusPalette.swift OneToOne/Views/DetailsViews.swift
git commit -m "refactor(shared): ProjectStatusPalette extrait de CollaboratorDetailView pour partage"
```

---

### Task 4: PanelHeader — drag handle + titre + collapse caret

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/PanelHeader.swift`

- [ ] **Step 1: Créer le fichier**

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Header d'un panel de sidebar configurable. Fournit :
/// - Icône système + titre (depuis `RightSidebarPanelID`)
/// - Caret expand/collapse cliquable
/// - Source de drag (UTType.text avec le rawValue de l'id)
/// - `dragHandle = true` rend l'ensemble draggable
struct PanelHeader: View {
    let panelID: RightSidebarPanelID
    @Binding var expanded: Bool
    var draggable: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: panelID.systemImage)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(panelID.defaultTitle.uppercased())
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .contentShape(Rectangle())
        .modifier(DragModifier(panelID: panelID, enabled: draggable))
    }
}

/// Conditionally apply `.onDrag` (macOS draggable). Wrapped in a modifier so
/// `draggable: false` désactive le drag (utile pour le rail replié plus tard).
private struct DragModifier: ViewModifier {
    let panelID: RightSidebarPanelID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.onDrag { NSItemProvider(object: panelID.rawValue as NSString) }
        } else {
            content
        }
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
git add OneToOne/Views/Meeting/Sidebar/PanelHeader.swift
git commit -m "feat(sidebar-config): PanelHeader avec drag handle + caret expand"
```

---

### Task 5: ActionsPanel — extract from MeetingActionsSidebar

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift`

C'est un refactor pur : on déplace le `tasksList + formSection` (et leurs helpers : `taskRow`, `assigneeMenu`, `rowAssigneeMenu`, `rowDueDateMenu`, `participantCandidates`, `favoriteCandidates`, `submitQuickAdd`, `canSubmitQuickAdd`, `quickAddRow`, `quickAddDateLabel`, `oneToOnePartner`, `otherCollabOpenActions`, `shortDate`, `showingAddCollaboratorSheet` state, `showingQuickAdd` state, plus les `@State` de quick-add) depuis `MeetingActionsSidebar` vers le nouveau `ActionsPanel`.

L'ancien `MeetingActionsSidebar` sera supprimé en Task 9. En attendant, on duplique pour pouvoir tester sans casser.

- [ ] **Step 1: Inspecter MeetingActionsSidebar pour identifier les sections**

```bash
grep -n "private var tasksList\|private var formSection\|private var assigneeMenu\|private func taskRow\|private func rowAssigneeMenu\|private func rowDueDateMenu\|private var participantCandidates\|private var favoriteCandidates\|private var quickAddRow\|showingQuickAdd\|showingAddCollaboratorSheet" OneToOne/Views/Meeting/MeetingActionsSidebar.swift | head -25
```

- [ ] **Step 2: Lire les blocs identifiés**

Lire l'intégralité de `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` pour avoir le code exact des sections et helpers à migrer. NE PAS modifier le fichier — juste lire.

- [ ] **Step 3: Créer ActionsPanel.swift**

`OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` :

```swift
import SwiftUI
import SwiftData

/// Panneau Actions de la sidebar configurable. Wrap le tasksList + formSection
/// (création + édition des ActionTask de la réunion). Logique identique à
/// l'ancien MeetingActionsSidebar — refactor pur.
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

    @Environment(\.modelContext) private var context
    @State private var showingAddCollaboratorSheet: Bool = false
    @State private var showingQuickAdd: Bool = false
    @State private var quickAddTitle: String = ""
    @State private var quickAddDueDate: Date? = nil
    @State private var quickAddProject: Project? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tasksList
            formSection
        }
    }

    // … Coller ICI les helpers extraits de MeetingActionsSidebar :
    //   - var tasksList
    //   - var formSection
    //   - var oneToOnePartner
    //   - func otherCollabOpenActions(for:)
    //   - func taskRow(_:)
    //   - var assigneeMenu
    //   - func rowAssigneeMenu(_:)
    //   - func rowDueDateMenu(_:)
    //   - var participantCandidates
    //   - var favoriteCandidates
    //   - var quickAddRow
    //   - var canSubmitQuickAdd
    //   - func submitQuickAdd()
    //   - func quickAddDateLabel(_:)
    //   - func shortDate(_:)
    //
    // Copier le code EXACT depuis MeetingActionsSidebar.swift. Aucune
    // modification de logique.
}
```

**Important** : coller le code des helpers depuis `MeetingActionsSidebar.swift` à l'IDENTIQUE. Pas de réécriture. Le fichier d'origine reste intact pour cette task.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`. Si erreur "ambiguous", c'est normal — il y a maintenant 2 copies des mêmes helpers. Les noms sont privés dans chaque struct donc devraient cohabiter. Si conflit, ajuster.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift
git commit -m "feat(sidebar-config): ActionsPanel — extract du tasksList + formSection (refactor pur)"
```

---

### Task 6: CapturePanel — extract from MeetingActionsSidebar

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/CapturePanel.swift`

- [ ] **Step 1: Localiser capturePreviewCard**

```bash
grep -n "private var capturePreviewCard\|currentSlides\|onShowSlides\|onShowCaptureSetup" OneToOne/Views/Meeting/MeetingActionsSidebar.swift | head
```

- [ ] **Step 2: Lire le bloc capturePreviewCard**

Lire son intégralité (variable computed avec image preview, boutons, etc.).

- [ ] **Step 3: Créer CapturePanel.swift**

```swift
import SwiftUI

/// Panneau Capture de la sidebar configurable. Affiche le dernier slide capturé
/// + boutons pour ouvrir la galerie ou la configuration de capture. Refactor
/// pur — code identique à `capturePreviewCard` de l'ancien MeetingActionsSidebar.
struct CapturePanel: View {

    let currentSlides: [SlideCapture]
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void

    var body: some View {
        // … coller ici le corps EXACT de capturePreviewCard depuis
        // MeetingActionsSidebar.swift. Adapter les références aux props
        // (currentSlides, onShowSlides, onShowCaptureSetup) qui restent
        // identiques.
    }
}
```

**Important** : pas de logique nouvelle. Refactor pur.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/CapturePanel.swift
git commit -m "feat(sidebar-config): CapturePanel — extract du capturePreviewCard (refactor pur)"
```

---

### Task 7: ProjectsPanel — nouveau panneau projets archi/PM

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift`

- [ ] **Step 1: Créer le fichier**

```swift
import SwiftUI
import SwiftData

/// Panneau "Projets affectés" de la sidebar configurable.
/// Visible pour `Meeting.kind == .oneToOne` ; liste les projets où le partenaire
/// est archi technique ou chef de projet, triés Red → Yellow → Green → Unknown.
/// Pour chaque row : code · nom · chip statut · count actions ouvertes.
struct ProjectsPanel: View {

    let meeting: Meeting

    private var partner: Collaborator? {
        meeting.kind == .oneToOne ? meeting.participants.first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = partner {
                if p.projectsAsArchitect.isEmpty && p.projectsAsManager.isEmpty {
                    emptyState("Pas de projet affecté à \(p.name).")
                } else {
                    if !p.projectsAsArchitect.isEmpty {
                        section(title: "EN TANT QU'ARCHITECTE",
                                projects: p.projectsAsArchitect)
                    }
                    if !p.projectsAsManager.isEmpty {
                        section(title: "EN TANT QUE CHEF DE PROJET",
                                projects: p.projectsAsManager)
                    }
                }
            } else {
                emptyState("Visible uniquement pour les 1:1.")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyState(_ msg: String) -> some View {
        Text(msg)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(title: String, projects: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text("(\(projects.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(ProjectStatusPalette.sortedByStatus(projects)) { p in
                NavigationLink {
                    ProjectDetailView(project: p)
                } label: {
                    projectRow(p)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        let openTasks = p.actionTasks.filter { !$0.isCompleted }.count
        HStack(spacing: 6) {
            Circle()
                .fill(ProjectStatusPalette.color(p.status))
                .frame(width: 7, height: 7)
            Text(p.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(p.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            if openTasks > 0 {
                Text("\(openTasks) act")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}
```

**Note** : `Project.actionTasks` doit exister (collection inverse via `ActionTask.project`). Vérifier :
```bash
grep -n "var actionTasks\|inverse: .ActionTask.project" OneToOne/Models/OtherModels.swift OneToOne/Models/Project.swift 2>/dev/null
```
Si l'inverse n'existe pas côté `Project`, utiliser un fetch SwiftData inline OU ajouter l'inverse au modèle. Si ajout : fait dans cette task (préserve la cohérence).

- [ ] **Step 2: Si nécessaire, ajouter l'inverse `Project.actionTasks`**

Si la vérification précédente montre que `Project.actionTasks` n'existe pas, l'ajouter dans `Project.swift` (ou `OtherModels.swift`) :

```swift
@Relationship(deleteRule: .nullify, inverse: \ActionTask.project)
var actionTasks: [ActionTask] = []
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift OneToOne/Models/Project.swift OneToOne/Models/OtherModels.swift
git commit -m "feat(sidebar-config): ProjectsPanel — projets archi/PM du collab (sidebar 1:1)"
```

---

### Task 8: ConfigurableRightSidebar — container drag-reorder + popover

**Files:**
- Create: `OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift`

- [ ] **Step 1: Créer le fichier**

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sidebar droite configurable des réunions. Remplace MeetingActionsSidebar.
/// Héberge 3 panels (Actions, Projets affectés, Capture) que l'utilisateur peut
/// réordonner par drag des headers et masquer via le menu engrenage.
/// Layout persisté dans `AppSettings.rightSidebarLayoutJSON`.
struct ConfigurableRightSidebar: View {

    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]

    @Binding var collapsed: Bool

    // Pass-through Actions panel:
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?
    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
    let saveContext: () -> Void

    @State private var entries: [PanelLayoutEntry] = []
    @State private var expanded: [RightSidebarPanelID: Bool] = [:]
    @State private var showingConfigPopover: Bool = false

    var body: some View {
        if collapsed {
            collapsedRail
        } else {
            expandedPanel
        }
    }

    // MARK: - Collapsed rail

    private var collapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Déplier la sidebar")
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: 36)
        .background(MeetingTheme.surfaceCream)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries.filter(\.visible)) { entry in
                        panelSection(entry)
                    }
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 460)
        .background(MeetingTheme.surfaceCream)
        .onAppear { hydrateLayoutAndExpansion() }
    }

    private var header: some View {
        HStack {
            Text("PANNEAUX")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingConfigPopover = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Configurer les panneaux")
            .popover(isPresented: $showingConfigPopover, arrowEdge: .top) {
                configPopoverBody
                    .padding(12)
                    .frame(minWidth: 220)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed = true }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Replier la sidebar")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var configPopoverBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Panneaux visibles")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(entries.indices, id: \.self) { idx in
                Toggle(entries[idx].id.defaultTitle,
                       isOn: Binding(
                        get: { entries[idx].visible },
                        set: { entries[idx].visible = $0; persist() }
                       ))
            }
            Divider()
            Button("Réinitialiser") {
                entries = PanelLayoutEntry.defaultLayout
                persist()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    @ViewBuilder
    private func panelSection(_ entry: PanelLayoutEntry) -> some View {
        let isExpanded = Binding<Bool>(
            get: { expanded[entry.id, default: true] },
            set: { expanded[entry.id] = $0 }
        )
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(panelID: entry.id, expanded: isExpanded)
                .onDrop(of: [UTType.text], delegate: DropDelegate_(
                    target: entry,
                    entries: $entries,
                    persist: persist
                ))
            if isExpanded.wrappedValue {
                panelContent(entry.id)
                    .transition(.opacity)
            }
            Divider()
        }
    }

    @ViewBuilder
    private func panelContent(_ id: RightSidebarPanelID) -> some View {
        switch id {
        case .actions:
            ActionsPanel(
                meeting: meeting,
                settings: settings,
                allCollaborators: allCollaborators,
                newTaskTitle: $newTaskTitle,
                selectedCollaborator: $selectedCollaborator,
                showNewTaskDueDate: $showNewTaskDueDate,
                newTaskDueDate: $newTaskDueDate,
                onAddTask: onAddTask,
                onDeleteTask: onDeleteTask,
                onToggleTaskCompletion: onToggleTaskCompletion,
                saveContext: saveContext
            )
        case .projects:
            ProjectsPanel(meeting: meeting)
        case .capture:
            CapturePanel(
                currentSlides: currentSlides,
                onShowSlides: onShowSlides,
                onShowCaptureSetup: onShowCaptureSetup
            )
        }
    }

    // MARK: - Layout persistence

    private func hydrateLayoutAndExpansion() {
        if entries.isEmpty {
            entries = PanelLayoutEntry.decode(settings.rightSidebarLayoutJSON)
            for entry in entries where expanded[entry.id] == nil {
                expanded[entry.id] = true
            }
        }
    }

    private func persist() {
        settings.rightSidebarLayoutJSON = PanelLayoutEntry.encode(entries)
        saveContext()
    }
}

/// Drop delegate qui réordonne les entries quand un panel est draggé sur la
/// row d'un autre panel.
private struct DropDelegate_: DropDelegate {
    let target: PanelLayoutEntry
    @Binding var entries: [PanelLayoutEntry]
    let persist: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else {
            return false
        }
        item.loadObject(ofClass: NSString.self) { (obj, _) in
            guard let raw = obj as? String,
                  let dragID = RightSidebarPanelID(rawValue: raw),
                  dragID != target.id else { return }
            DispatchQueue.main.async {
                guard let fromIdx = entries.firstIndex(where: { $0.id == dragID }),
                      let toIdx = entries.firstIndex(where: { $0.id == target.id }) else { return }
                let moved = entries.remove(at: fromIdx)
                entries.insert(moved, at: toIdx)
                persist()
            }
        }
        return true
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -10
```
Expected: `Build complete!`. Si erreur sur `MeetingTheme.surfaceCream` : vérifier que c'est bien la propriété utilisée dans `MeetingActionsSidebar` original. Si différent (ex: `MeetingTheme.background`), adapter.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift
git commit -m "feat(sidebar-config): ConfigurableRightSidebar container — drag-reorder + popover ⚙"
```

---

### Task 9: Wire MeetingView + supprimer MeetingActionsSidebar

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`
- Delete: `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`

- [ ] **Step 1: Localiser le callsite unique**

```bash
grep -n "MeetingActionsSidebar(" OneToOne/Views/MeetingView.swift
```
Unique callsite autour de la ligne 252.

- [ ] **Step 2: Remplacer le call par ConfigurableRightSidebar**

Dans `OneToOne/Views/MeetingView.swift`, repérer le bloc :

```swift
MeetingActionsSidebar(
    meeting: meeting,
    settings: settings,
    allCollaborators: allCollaborators,
    currentSlides: currentSlides,
    collapsed: $actionsCollapsed,
    newTaskTitle: $newTaskTitle,
    selectedCollaborator: $selectedCollaborator,
    showNewTaskDueDate: $showNewTaskDueDate,
    newTaskDueDate: $newTaskDueDate,
    onAddTask: addTask,
    onDeleteTask: { task in
        context.delete(task)
        saveContext()
    },
    onToggleTaskCompletion: { task in
        task.isCompleted.toggle()
        saveContext()
    },
    onShowSlides:       { showSlidesList = true },
    onShowCaptureSetup: { showCaptureSetup = true },
    // … reste possible des props
)
```

Remplacer le nom `MeetingActionsSidebar` par `ConfigurableRightSidebar`. Les props sont identiques (volontairement, pour minimiser le diff). Vérifier qu'il n'y a pas de prop supplémentaire dans `MeetingActionsSidebar` (par exemple `saveContext`) — si oui, l'ajouter à l'appel.

- [ ] **Step 3: Build pour valider l'API**

```bash
swift build 2>&1 | tail -10
```
Expected: `Build complete!`. Si "ambiguous" sur le nom des helpers extraits (ActionsPanel les a maintenant), ce n'est pas grave tant que `MeetingActionsSidebar` est encore présent. Le conflit se résout à la prochaine étape.

- [ ] **Step 4: Supprimer MeetingActionsSidebar.swift**

```bash
rm OneToOne/Views/Meeting/MeetingActionsSidebar.swift
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -10
```
Expected: `Build complete!`. Si "cannot find 'MeetingActionsSidebar'" → reste un call-site oublié. Grep et corriger.

- [ ] **Step 6: Tests existants**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -5
```
Expected: tous PASS, dont PanelLayoutEntryTests (5).

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingActionsSidebar.swift
git commit -m "feat(sidebar-config): wire MeetingView vers ConfigurableRightSidebar + drop MeetingActionsSidebar"
```

---

### Task 10: Final build + smoke

**Files:** (aucun)

- [ ] **Step 1: Full build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 2: Tous les tests**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -8
```
Expected: tous PASS dont `PanelLayoutEntryTests` (5/5).

- [ ] **Step 3: Smoke test manuel**

`swift run` et :
1. Ouvrir une réunion 1:1 avec un partenaire qui a des projets archi (sub-projet 1 doit être déployé). La sidebar droite affiche 3 panels : Actions, Projets affectés, Capture.
2. Click ⚙ → popover avec 3 toggles → décocher Capture → le panneau Capture disparaît.
3. Relancer l'app → Capture reste masqué (layout persisté).
4. Re-cocher Capture via ⚙.
5. Drag le header "Projets affectés" au-dessus de "Actions" → l'ordre s'inverse → persiste après restart.
6. Click "Réinitialiser" dans le popover → ordre revient à `[actions, projects, capture]`.
7. Cliquer le caret d'un panel → contenu collapse/expand.
8. Click row projet dans ProjectsPanel → navigue vers ProjectDetailView.
9. Réunion non-1:1 (ex: COPIL) → panneau Projets affiche "Visible uniquement pour les 1:1.".
10. Click bouton sidebar.right → toute la sidebar se replie en rail.

- [ ] **Step 4: Commit history check**

```bash
git log --oneline -12
```
Attendu : commits `feat(sidebar-config):` et `refactor(shared):` pour Tasks 1-9.

---

## Self-review

**Spec coverage** :
- §2.1 container unique → Task 8. ✓
- §2.2 3 panels enum extensible → Task 2 (RightSidebarPanelID). ✓
- §2.3 drag-reorder via `.onDrag`/`.onDrop` → Tasks 4 (PanelHeader source) + 8 (drop delegate). ✓
- §2.4 popover engrenage show/hide + Réinitialiser → Task 8. ✓
- §2.5 persistance JSON AppSettings → Tasks 1 (field) + 2 (encode/decode) + 8 (hydrate/persist). ✓
- §2.6 panneau Projets visible 1:1 uniquement + état vide informatif → Task 7. ✓
- §2.7 refactor pur Actions + Capture → Tasks 5 + 6. ✓
- §3.1 modèle → Task 1. ✓
- §3.2 enum → Task 2. ✓
- §3.3 struct PanelLayoutEntry → Task 2 (avec migration ajout case). ✓
- §3.4 container API → Task 8. ✓
- §3.5 drag-reorder mécanisme → Tasks 4 + 8. ✓
- §3.6 show/hide popover → Task 8. ✓
- §3.7 ActionsPanel → Task 5. ✓
- §3.8 ProjectsPanel → Task 7. ✓
- §3.9 CapturePanel → Task 6. ✓
- §3.10 file map → all tasks. ✓
- §3.11 migration MeetingActionsSidebar → Task 9 (delete). ✓
- §4 UX details (drag header only, popover esc, hydrate au load) → Tasks 4 + 8. ✓
- §5 erreurs (JSON corrompu fallback, nouveau case enum append) → Task 2 + tests. ✓
- §6 tests → Tasks 2 (unit) + 10 (smoke). ✓
- §7 YAGNI → respecté.
- §8 migration → Task 1 (default empty) + Task 2 (decode fallback). ✓
- §9 livrables → all tasks. ✓

**Placeholder scan** :
- Aucun "TBD" / "implement later".
- Task 5 Step 3 : "Coller ICI les helpers extraits…" est une instruction explicite référencée à un fichier source précis (`MeetingActionsSidebar.swift`) qu'il faut lire à l'étape 2. Acceptable car la cible est précisément localisée.
- Task 6 Step 3 idem pour `capturePreviewCard`.
- Task 7 Step 2 conditionnel "si `Project.actionTasks` n'existe pas" avec commande grep pour vérifier — actionnable.
- Task 9 Step 2 "Vérifier qu'il n'y a pas de prop supplémentaire" — actionnable via grep dans le fichier original.

**Type consistency** :
- `RightSidebarPanelID` cases `actions`/`projects`/`capture` — Tasks 2, 4, 7, 8. ✓
- `PanelLayoutEntry(id:visible:)` — Tasks 2, 8. ✓
- `PanelLayoutEntry.defaultLayout / encode(_:) / decode(_:)` — Tasks 2 (def) + 8 (usage). ✓
- `PanelHeader(panelID:expanded:draggable:)` — Tasks 4 (def) + 8 (usage). ✓
- `ActionsPanel(meeting:settings:allCollaborators:newTaskTitle:selectedCollaborator:showNewTaskDueDate:newTaskDueDate:onAddTask:onDeleteTask:onToggleTaskCompletion:saveContext:)` — Tasks 5 (def) + 8 (usage). ✓
- `ProjectsPanel(meeting:)` — Tasks 7 (def) + 8 (usage). ✓
- `CapturePanel(currentSlides:onShowSlides:onShowCaptureSetup:)` — Tasks 6 (def) + 8 (usage). ✓
- `ProjectStatusPalette.color(_:) / .sortedByStatus(_:)` — Task 3 (def) + 7 (usage). ✓
- `AppSettings.rightSidebarLayoutJSON` — Tasks 1 (def) + 8 (usage). ✓
- `Project.actionTasks` — Task 7 (vérif + ajout conditionnel) + usage Task 7. ✓

Aucune correction inline nécessaire.
