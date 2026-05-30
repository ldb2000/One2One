# Project Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assigner explicitement un Chef de projet et un Architecte technique à chaque `Project`, exposer la reverse-query (un collab → ses projets) sur sa fiche.

**Architecture:** 2 nouvelles FK Optional sur `Project` (`projectManager`, `technicalArchitect`) avec relations inverse `[Project]` côté `Collaborator`. Picker réutilisable `OwnerPickerMenu` factorise le pattern « Favoris en premier + Autres + bouton Ajouter ». UI: 2 lignes dans ProjectDetailView, 1 GroupBox dans CollaboratorDetailView.

**Tech Stack:** Swift 6, SwiftUI, SwiftData.

---

## File map

| Path | Responsabilité |
|---|---|
| `OneToOne/Models/OtherModels.swift` (modify) | +2 FK sur `Project` ; +2 relations inverse sur `Collaborator` |
| `OneToOne/Views/Shared/AddCollaboratorSheet.swift` (new — déplacé depuis MeetingActionsSidebar) | Sheet recherche/création réutilisable |
| `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` (modify) | Supprimer la copie privée de `AddCollaboratorSheet` |
| `OneToOne/Views/Shared/OwnerPickerMenu.swift` (new) | Menu Favoris → Autres → Ajouter… réutilisable |
| `OneToOne/Views/DetailsViews.swift` (modify) | ProjectDetailView : 2 LabeledContent ; CollaboratorDetailView : nouvelle GroupBox "Projets" |

Total : 2 nouveaux fichiers, 3 modifications.

**Types existants utilisés** :
- `Collaborator.name / role / pinLevel / isArchived` ✓
- `Project.code / name / status` ✓
- `statusColor(_:)` helper privé dans `ProjectDetailView` (sera utilisé sur CollaboratorDetailView aussi — extraire en helper de fichier ou dupliquer)
- `Project` est utilisé en `NavigationLink { ProjectDetailView(project: …) }` (vérifier le call-site existant)

---

### Task 1: Modèle SwiftData — 2 FK + 2 relations inverse

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift`

- [ ] **Step 1: Localiser la classe `Project`**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "@Model\|final class Project\|var sponsor" OneToOne/Models/OtherModels.swift | head -10
```

- [ ] **Step 2: Ajouter les FK sur Project**

Dans `@Model final class Project { … }`, repérer la propriété `var sponsor: String`. Juste après, ajouter :

```swift
/// Chef de projet — Optional FK (Collaborator). Affiché dans
/// ProjectDetailView § Informations Générales et utilisé pour
/// la reverse query depuis la fiche collab.
var projectManager: Collaborator?

/// Architecte technique du projet — Optional FK (Collaborator).
/// Cas d'usage : dans un 1:1 avec un collab architecte, on liste
/// automatiquement tous les projets où il endosse ce rôle.
var technicalArchitect: Collaborator?
```

- [ ] **Step 3: Ajouter les relations inverse sur Collaborator**

Dans `@Model final class Collaborator { … }`, repérer le bloc des `@Relationship`. À la fin du bloc (avant les init ou autres), ajouter :

```swift
/// Projets où ce collab est désigné Chef de projet (reverse query).
@Relationship(inverse: \Project.projectManager)
var projectsAsManager: [Project] = []

/// Projets où ce collab est désigné Architecte technique (reverse query).
@Relationship(inverse: \Project.technicalArchitect)
var projectsAsArchitect: [Project] = []
```

Si `Collaborator` n'a pas encore d'autre `@Relationship` visible dans cette classe, placer ces lignes juste avant le premier `init`.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`. Si « inverse must be a one-to-one or to-many » : vérifier que `Project.projectManager` est bien `Collaborator?` (Optional).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Models/OtherModels.swift
git commit -m "feat(project-ownership): Project.projectManager + technicalArchitect + relations inverse Collaborator"
```

---

### Task 2: Extraire AddCollaboratorSheet vers fichier partagé

**Files:**
- Create: `OneToOne/Views/Shared/AddCollaboratorSheet.swift`
- Modify: `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`

`AddCollaboratorSheet` est actuellement `private struct` dans `MeetingActionsSidebar.swift` (ligne ~540). On le promeut en `internal` (default Swift) dans un fichier partagé pour le réutiliser dans `OwnerPickerMenu`.

- [ ] **Step 1: Inspecter la struct actuelle**

```bash
sed -n '540,650p' OneToOne/Views/Meeting/MeetingActionsSidebar.swift
```

- [ ] **Step 2: Créer le fichier partagé**

Créer `OneToOne/Views/Shared/AddCollaboratorSheet.swift` avec **exactement** le contenu de la struct `AddCollaboratorSheet` actuelle (lignes ~540-fin), MAIS :
- Supprimer le mot-clé `private` devant `struct`
- Ajouter les imports requis (`import SwiftUI`, `import SwiftData` si présents dans le fichier d'origine)
- Conserver `@Environment(\.dismiss)`, `@State`, le bloc `body`, et l'init exact

Le résultat doit être :

```swift
import SwiftUI
import SwiftData

/// Sheet de recherche / création de Collaborator.
/// Réutilisée par MeetingActionsSidebar (assignee picker) et
/// OwnerPickerMenu (chef de projet / architecte technique).
struct AddCollaboratorSheet: View {
    let allCollaborators: [Collaborator]
    let onPick: (Collaborator) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    // … coller ici le reste du body et des helpers ORIGINAUX …
}
```

**Important** : copier-coller exactement la struct existante (corps complet). Ne pas réécrire.

- [ ] **Step 3: Supprimer la copie dans MeetingActionsSidebar.swift**

Dans `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`, supprimer entièrement le `private struct AddCollaboratorSheet` (depuis sa déclaration jusqu'à sa fermeture finale). Tous les call-sites continuent de marcher (la struct est maintenant trouvée dans le module).

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`. Si erreur « ambiguous », vérifier qu'il ne reste qu'une seule définition de `AddCollaboratorSheet` dans le projet.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Shared/AddCollaboratorSheet.swift OneToOne/Views/Meeting/MeetingActionsSidebar.swift
git commit -m "refactor(shared): extraire AddCollaboratorSheet vers Views/Shared pour réutilisation"
```

---

### Task 3: Composant OwnerPickerMenu

**Files:**
- Create: `OneToOne/Views/Shared/OwnerPickerMenu.swift`

- [ ] **Step 1: Créer le fichier**

`OneToOne/Views/Shared/OwnerPickerMenu.swift` :

```swift
import SwiftUI
import SwiftData

/// Menu déroulant pour choisir un Collaborator (chef de projet, architecte
/// technique, ou tout autre rôle d'ownership). Réutilise le pattern :
///   Aucun → Favoris (pinLevel ≥ 1) → Autres collaborateurs → + Ajouter…
///
/// Le bouton « + Ajouter… » présente `AddCollaboratorSheet` qui permet
/// de rechercher ou créer un nouveau collab. Le collab créé est passé
/// au binding via `onCreate` interne.
struct OwnerPickerMenu: View {

    let label: String                    // ex: "Aucun"
    @Binding var selection: Collaborator?
    let allCollaborators: [Collaborator]
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var showingAddSheet: Bool = false

    private var favorites: [Collaborator] {
        allCollaborators
            .filter { $0.pinLevel >= 1 && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var others: [Collaborator] {
        allCollaborators
            .filter { $0.pinLevel == 0 && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            Button {
                selection = nil
                onSaved()
            } label: { Text("Aucun") }

            if !favorites.isEmpty {
                Divider()
                Section("⭐ Favoris") {
                    ForEach(favorites) { c in
                        Button(c.name) {
                            selection = c
                            onSaved()
                        }
                    }
                }
            }

            if !others.isEmpty {
                Divider()
                Section("Autres collaborateurs") {
                    ForEach(others) { c in
                        Button(c.name) {
                            selection = c
                            onSaved()
                        }
                    }
                }
            }

            Divider()
            Button {
                showingAddSheet = true
            } label: {
                Label("Ajouter un collaborateur…", systemImage: "plus")
            }
        } label: {
            Label(
                selection?.name ?? label,
                systemImage: selection != nil
                    ? "person.crop.circle.fill"
                    : "person.crop.circle"
            )
            .font(.callout)
            .foregroundColor(selection != nil ? .primary : .secondary)
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showingAddSheet) {
            AddCollaboratorSheet(
                allCollaborators: allCollaborators,
                onPick: { c in
                    selection = c
                    showingAddSheet = false
                    onSaved()
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let c = Collaborator(name: trimmed)
                    context.insert(c)
                    try? context.save()
                    selection = c
                    showingAddSheet = false
                    onSaved()
                }
            )
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Shared/OwnerPickerMenu.swift
git commit -m "feat(project-ownership): OwnerPickerMenu (favoris → autres → ajouter)"
```

---

### Task 4: ProjectDetailView — 2 LabeledContent

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift`

- [ ] **Step 1: Localiser la ligne Sponsor**

```bash
grep -n 'LabeledContent("Sponsor")\|placeholder: "Sponsor"' OneToOne/Views/DetailsViews.swift
```
Cible : autour de la ligne 75 dans `ProjectDetailView` GroupBox « Informations Générales ».

- [ ] **Step 2: Ajouter les 2 LabeledContent**

Repérer le bloc :
```swift
LabeledContent("Sponsor") {
    EditableTextField(placeholder: "Sponsor", text: $project.sponsor)
        .frame(height: 24)
}
```

Juste après sa fermeture `}`, ajouter :

```swift
LabeledContent("Chef de projet") {
    OwnerPickerMenu(
        label: "Aucun",
        selection: $project.projectManager,
        allCollaborators: collaborators,
        onSaved: { try? context.save() }
    )
}
LabeledContent("Architecte technique") {
    OwnerPickerMenu(
        label: "Aucun",
        selection: $project.technicalArchitect,
        allCollaborators: collaborators,
        onSaved: { try? context.save() }
    )
}
```

`collaborators` et `context` sont déjà des propriétés de `ProjectDetailView` (lignes 28 et 31 du fichier).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(project-ownership): ProjectDetailView — chef de projet + architecte technique"
```

---

### Task 5: CollaboratorDetailView — GroupBox « Projets »

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift`

- [ ] **Step 1: Localiser CollaboratorDetailView**

```bash
grep -n "struct CollaboratorDetailView\|GroupBox(\"Identité\")\|Préparation prochaine 1:1" OneToOne/Views/DetailsViews.swift | head
```
Cible : autour de la ligne 806 (struct), Identité ligne ~834, Préparation 1:1 ligne ~913.

- [ ] **Step 2: Repérer le point d'insertion**

Lire les lignes 870-895 pour identifier la fin du GroupBox « Identité ». Le GroupBox « Identité » se termine par sa fermeture `}`, puis vient le GroupBox suivant (`GroupBox { DisclosureGroup … }` pour la prep 1:1).

L'insertion va se faire **entre** le `}` qui ferme Identité et le `GroupBox {` qui ouvre la prep.

- [ ] **Step 3: Insérer le nouveau GroupBox**

Insérer :

```swift
// Projets dont ce collab est archi technique ou chef de projet.
if !collaborator.projectsAsArchitect.isEmpty
    || !collaborator.projectsAsManager.isEmpty {
    GroupBox("Projets") {
        VStack(alignment: .leading, spacing: 14) {
            if !collaborator.projectsAsArchitect.isEmpty {
                ownershipSection(
                    title: "EN TANT QU'ARCHITECTE TECHNIQUE",
                    projects: collaborator.projectsAsArchitect
                )
            }
            if !collaborator.projectsAsManager.isEmpty {
                ownershipSection(
                    title: "EN TANT QUE CHEF DE PROJET",
                    projects: collaborator.projectsAsManager
                )
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4: Ajouter les helpers privés**

À l'intérieur de `struct CollaboratorDetailView` (n'importe où parmi les autres helpers privés, par exemple juste avant le `body`), ajouter :

```swift
@ViewBuilder
private func ownershipSection(title: String, projects: [Project]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.0)
            Text("(\(projects.count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        ForEach(sortedByStatus(projects)) { p in
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
    HStack(spacing: 8) {
        Circle()
            .fill(projectStatusColor(p.status))
            .frame(width: 8, height: 8)
        Text(p.code)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        Text("·").foregroundStyle(.tertiary)
        Text(p.name)
            .font(.callout)
            .lineLimit(1)
        Spacer()
        Text(p.status)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(projectStatusColor(p.status).opacity(0.18)))
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
}

/// Tri : Red → Yellow → Green → Unknown, puis alpha par nom.
private func sortedByStatus(_ projects: [Project]) -> [Project] {
    let rank: [String: Int] = ["Red": 0, "Yellow": 1, "Green": 2, "Unknown": 3]
    return projects.sorted { a, b in
        let ra = rank[a.status] ?? 3
        let rb = rank[b.status] ?? 3
        if ra != rb { return ra < rb }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// Couleur statut projet — copie locale de `statusColor` qui est privé dans
/// ProjectDetailView. Si plus tard on factor : extraire dans un helper de
/// module (`ProjectStatusPalette.color(_:)`).
private func projectStatusColor(_ s: String) -> Color {
    switch s {
    case "Red":     return .red
    case "Yellow":  return .orange
    case "Green":   return .green
    default:        return .gray
    }
}
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -8
```
Expected: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(project-ownership): CollaboratorDetailView — GroupBox Projets (archi + PM)"
```

---

### Task 6: Final build + smoke test

**Files:** (aucun)

- [ ] **Step 1: Full build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 2: Tests existants pas régressés**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -5
```
Expected: tous pass (pas de tests nouveaux pour ce plan, juste vérifier la non-régression).

- [ ] **Step 3: Smoke test manuel**

`swift run` et :
1. Ouvrir un projet → Informations Générales → ligne « Chef de projet » → menu déroulant affiche « ⭐ Favoris » au-dessus de « Autres collaborateurs ». Sélectionner un favori.
2. Idem « Architecte technique ».
3. Quitter l'app, relancer, ré-ouvrir le projet → les 2 sélections sont persistées.
4. Click « + Ajouter un collaborateur… » → sheet de recherche → créer un nouveau collab → vérifier qu'il devient l'archi sélectionné.
5. Ouvrir la fiche du collab assigné comme archi → nouvelle GroupBox « Projets » visible avec sous-section « EN TANT QU'ARCHITECTE TECHNIQUE » contenant le projet.
6. Click row projet → navigue vers `ProjectDetailView`.
7. Pour un collab affecté à 3 projets de statuts variés (Red, Yellow, Green) → vérifier le tri Red d'abord, Yellow, Green.
8. Désassigner (set Aucun) un projet → row disparaît de la fiche collab au prochain refresh.

- [ ] **Step 4: Commit history check**

```bash
git log --oneline -6
```
Expected : 5 commits `feat(project-ownership):` / `refactor(shared):` correspondant aux Tasks 1-5.

---

## Self-review

**Spec coverage** :
- §2.1 + §3.1 modèle : 2 FK + 2 relations inverse → Task 1. ✓
- §2.3 + §3.2 OwnerPickerMenu favoris-first + recherche → Task 3. ✓
- §2.4 + §3.3 ProjectDetailView 2 LabeledContent → Task 4. ✓
- §2.5 + §3.4 CollaboratorDetailView GroupBox Projets + tri Red→Yellow→Green → Task 5. ✓
- §3.5 file map → Tasks 1-5 + Task 2 (extraction AddCollaboratorSheet). ✓
- §5 UX details (favori archivé exclu, suppression collab nullify FK) → Task 1 + Task 3 (filter `!isArchived`). ✓
- §6 erreurs / edge cases → Task 3 (favorites/others vides → sections cachées). ✓
- §7 YAGNI → respecté.
- §8 tests smoke → Task 6. ✓

**Placeholder scan** :
- Aucun « TBD », « implement later ».
- Task 2 Step 2 : « coller le corps complet de la struct existante » est une instruction explicite mais nécessite l'inspection du code source à l'étape précédente. Acceptable car la cible (fichier `MeetingActionsSidebar.swift` lignes 540+) est précisément localisée.
- Task 5 Step 3 « entre Identité et la prep 1:1 » est référencé via lecture lignes 870-895 — pointeur précis.

**Type consistency** :
- `Project.projectManager: Collaborator?` / `Project.technicalArchitect: Collaborator?` — Task 1, utilisés Tasks 4. ✓
- `Collaborator.projectsAsManager: [Project]` / `projectsAsArchitect: [Project]` — Task 1, utilisés Task 5. ✓
- `OwnerPickerMenu(label:selection:allCollaborators:onSaved:)` — Task 3, utilisé Task 4. ✓
- `AddCollaboratorSheet(allCollaborators:onPick:onCreate:)` — Task 2 (existait déjà avec cette signature), utilisé Task 3. ✓
- `ownershipSection(title:projects:)`, `projectRow(_:)`, `sortedByStatus(_:)`, `projectStatusColor(_:)` — Task 5 (cohérents entre eux). ✓
- `ProjectDetailView(project: …)` — utilisé Task 5 dans NavigationLink (constructeur existant). ✓

Aucune correction inline nécessaire.
