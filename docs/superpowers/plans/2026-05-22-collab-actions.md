# Collaborator actions & prep — UX fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre la fiche collaborateur réellement interactive (prep dépliable, actions cochables, ajout rapide) et permettre de cocher les actions urgentes depuis le menubar.

**Architecture:** Pas de nouveau service. Modifs ciblées sur `CollaboratorDetailView` (fichier `DetailsViews.swift`) et `MenuBarController`. Utilise les modèles SwiftData existants (`ActionTask`, `Collaborator`, `Project`).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit (NSMenu).

---

## File map

| Path | Responsibility |
|---|---|
| `OneToOne/Views/DetailsViews.swift` (modify) | `CollaboratorDetailView` : prep expand state, cochable, quick-add row |
| `OneToOne/Services/MenuBarController.swift` (modify) | Urgent items → submenu Marquer fait / Ouvrir + overflow |

Total : 2 modifications, 0 nouveau fichier.

**Note types existants:**
- `ActionTask.isCompleted: Bool`, `ActionTask.completedAt: Date?` (pas `completedDate`).
- `ActionTask.collaborator: Collaborator?` (relation directe, pas `assignedCollaborator`).
- `ActionTask.init(title:dueDate:)` — `project` et `collaborator` à set après init.

---

### Task 1: Fix prep DisclosureGroup expand

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift` (CollaboratorDetailView, lignes ~886-921)

- [ ] **Step 1: Localiser le bloc**

```bash
grep -n "DisclosureGroup(isExpanded: .constant" OneToOne/Views/DetailsViews.swift
```
Expected: une seule ligne match dans `CollaboratorDetailView`.

- [ ] **Step 2: Ajouter @State**

Dans `CollaboratorDetailView`, à proximité des autres `@State` (chercher `@State` existants au début du struct), ajouter :
```swift
@State private var prepExpanded: Bool = false
```

- [ ] **Step 3: Remplacer le DisclosureGroup**

Remplacer :
```swift
DisclosureGroup(isExpanded: .constant(!collaborator.standingPrepNotes.isEmpty)) {
```
par :
```swift
DisclosureGroup(isExpanded: $prepExpanded) {
```

Et juste avant le `DisclosureGroup`, dans le `GroupBox { ... }`, ajouter un `.onAppear` au niveau du `GroupBox` (ou au-dessus du `DisclosureGroup`) :

```swift
.onAppear {
    if !prepExpanded {
        prepExpanded = !collaborator.standingPrepNotes.isEmpty
    }
}
```

Si le `GroupBox` n'a pas d'emplacement naturel pour `.onAppear`, l'attacher au `DisclosureGroup` lui-même.

- [ ] **Step 4: Ajouter empty-state CTA**

Dans le contenu du `DisclosureGroup` (premier `VStack`), juste avant `MarkdownEditorView`, ajouter :
```swift
if collaborator.standingPrepNotes.isEmpty {
    HStack {
        Spacer()
        Text("Aucune préparation. Saisis directement ci-dessous ou clique sur « Générer brouillon IA ».")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        Spacer()
    }
    .padding(.bottom, 4)
}
```

Et hors du `DisclosureGroup`, ajouter un bouton "Créer une préparation" visible UNIQUEMENT quand `!prepExpanded && collaborator.standingPrepNotes.isEmpty`. L'emplacement : à l'intérieur du `GroupBox` du prep, après le `DisclosureGroup` :
```swift
if !prepExpanded && collaborator.standingPrepNotes.isEmpty {
    HStack {
        Spacer()
        Button("Créer une préparation") {
            prepExpanded = true
        }
        .buttonStyle(.bordered)
        Spacer()
    }
    .padding(.top, 4)
}
```

- [ ] **Step 5: Build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne && swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "fix(collab): rendre la section préparation 1:1 dépliable + CTA si vide"
```

---

### Task 2: Cochable actions

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift` (CollaboratorDetailView, lignes ~931-948 — la `ForEach(pendingTasks)` et bouton checkbox)

- [ ] **Step 1: Localiser la row pending**

```bash
grep -n 'systemName: "circle"' OneToOne/Views/DetailsViews.swift
```
Repérer le match dans `CollaboratorDetailView` (section "Actions en cours").

- [ ] **Step 2: Remplacer Image par Button**

Le bloc actuel est :
```swift
ForEach(pendingTasks) { task in
    HStack {
        Image(systemName: "circle")
            .foregroundColor(.gray)
            .font(.caption)
        Text(task.title)
        Spacer()
        if let project = task.project { ... }
        if let dueDate = task.dueDate { ... }
    }
}
```

Remplacer par :
```swift
ForEach(pendingTasks) { task in
    HStack {
        Button {
            task.isCompleted = true
            task.completedAt = Date()
            try? context.save()
        } label: {
            Image(systemName: "circle")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Marquer comme fait")

        Text(task.title)
        Spacer()
        if let project = task.project {
            Text(project.name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        if let dueDate = task.dueDate {
            Text(dueDate, style: .date)
                .font(.caption2)
                .foregroundColor(dueDate < Date() ? .red : .secondary)
        }
    }
}
```

- [ ] **Step 3: Décocher depuis "Terminées"**

Localiser `DisclosureGroup("Terminées (\(doneTasks.count))")` juste après. Le bloc actuel :
```swift
ForEach(doneTasks) { task in
    HStack {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.caption)
        Text(task.title)
            .strikethrough()
            .foregroundColor(.secondary)
    }
}
```

Remplacer par :
```swift
ForEach(doneTasks) { task in
    HStack {
        Button {
            task.isCompleted = false
            task.completedAt = nil
            try? context.save()
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Marquer comme à faire")

        Text(task.title)
            .strikethrough()
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(collab): rendre la checkbox des actions cochable (toggle isCompleted)"
```

---

### Task 3: Quick-add action row

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift` (CollaboratorDetailView)

- [ ] **Step 1: Ajouter @State et @Query**

En haut de `CollaboratorDetailView`, à côté des autres `@State` / `@Query`, ajouter :
```swift
@State private var showingQuickAdd: Bool = false
@State private var quickAddTitle: String = ""
@State private var quickAddProject: Project? = nil
@State private var quickAddDueDate: Date? = nil
@Query(filter: #Predicate<Project> { !$0.isArchived },
       sort: \Project.name) private var availableProjects: [Project]
```

- [ ] **Step 2: Bouton + dans le header de la GroupBox**

Localiser le `label:` de la `GroupBox` "Actions en cours" :
```bash
grep -n 'Text("Actions en cours")' OneToOne/Views/DetailsViews.swift
```

Remplacer le label HStack :
```swift
HStack {
    Text("Actions en cours")
    let count = collaborator.assignedTasks.filter { !$0.isCompleted }.count
    if count > 0 {
        Text("\(count)") ...
    }
}
```

par :
```swift
HStack {
    Text("Actions en cours")
    let count = collaborator.assignedTasks.filter { !$0.isCompleted }.count
    if count > 0 {
        Text("\(count)")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
    Spacer()
    Button {
        showingQuickAdd.toggle()
        if showingQuickAdd {
            quickAddTitle = ""
            quickAddProject = nil
            quickAddDueDate = nil
        }
    } label: {
        Image(systemName: showingQuickAdd ? "xmark.circle" : "plus.circle.fill")
            .foregroundStyle(showingQuickAdd ? .secondary : Color.accentColor)
    }
    .buttonStyle(.plain)
    .help(showingQuickAdd ? "Annuler" : "Ajouter une action")
}
```

- [ ] **Step 3: Row quick-add**

Dans le contenu de la GroupBox (le `VStack(alignment: .leading, spacing: 5)`), juste avant le `ForEach(pendingTasks)`, ajouter :

```swift
if showingQuickAdd {
    quickAddRow
        .padding(.bottom, 6)
}
```

Puis ajouter le helper dans le struct (par exemple juste avant `body` ou en bas) :

```swift
@ViewBuilder
private var quickAddRow: some View {
    HStack(spacing: 8) {
        TextField("Titre de l'action…", text: $quickAddTitle)
            .textFieldStyle(.roundedBorder)
            .onSubmit(submitQuickAdd)

        Menu {
            Button("Aucun") { quickAddProject = nil }
            Divider()
            ForEach(availableProjects) { p in
                Button(p.name) { quickAddProject = p }
            }
        } label: {
            Text(quickAddProject?.name ?? "Projet")
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 120)
        }
        .menuStyle(.borderlessButton)

        Menu {
            Button("Aucune") { quickAddDueDate = nil }
            Button("Aujourd'hui") { quickAddDueDate = Date() }
            Button("Demain") { quickAddDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
            Button("Dans une semaine") { quickAddDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
        } label: {
            Text(quickAddDueDate.map { dateLabel($0) } ?? "Échéance")
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 110)
        }
        .menuStyle(.borderlessButton)

        Button {
            submitQuickAdd()
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(canSubmitQuickAdd ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmitQuickAdd)
        .keyboardShortcut(.return, modifiers: [])

        Button {
            showingQuickAdd = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
    }
}

private var canSubmitQuickAdd: Bool {
    !quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func submitQuickAdd() {
    let trimmed = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let task = ActionTask(title: trimmed, dueDate: quickAddDueDate)
    task.collaborator = collaborator
    task.project = quickAddProject
    context.insert(task)
    try? context.save()
    quickAddTitle = ""
    quickAddProject = nil
    quickAddDueDate = nil
    showingQuickAdd = false
}

private func dateLabel(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = "d MMM"
    return f.string(from: d)
}
```

**Note** : si `dateLabel` existe déjà dans le fichier (cas possible), réutiliser et supprimer le doublon.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`. Si "invalid redeclaration of 'dateLabel'", supprimer la déclaration ajoutée et utiliser l'existante.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(collab): bouton + ajout rapide d'action avec projet/échéance inline"
```

---

### Task 4: Menubar urgent submenu (Marquer fait / Ouvrir)

**Files:**
- Modify: `OneToOne/Services/MenuBarController.swift` (`appendUrgentSection`, lignes ~278-299)

- [ ] **Step 1: Localiser le for-loop**

```bash
grep -n "for task in urgent.prefix(3)" OneToOne/Services/MenuBarController.swift
```

- [ ] **Step 2: Remplacer le bloc**

Remplacer :
```swift
urgentTaskByKey.removeAll()
for task in urgent.prefix(3) {
    let key = UUID().uuidString
    urgentTaskByKey[key] = task
    let item = NSMenuItem(title: urgentLabel(for: task),
                          action: #selector(showUrgent(_:)),
                          keyEquivalent: "")
    item.target = self
    item.representedObject = key
    menu.addItem(item)
}
menu.addItem(.separator())
```

par :
```swift
urgentTaskByKey.removeAll()
for task in urgent.prefix(3) {
    let key = UUID().uuidString
    urgentTaskByKey[key] = task

    let parent = NSMenuItem(title: urgentLabel(for: task),
                            action: nil, keyEquivalent: "")
    let sub = NSMenu()

    let done = NSMenuItem(title: "✓  Marquer comme fait",
                          action: #selector(markUrgentDone(_:)),
                          keyEquivalent: "")
    done.target = self
    done.representedObject = key
    sub.addItem(done)

    let open = NSMenuItem(title: "Ouvrir…",
                          action: #selector(showUrgent(_:)),
                          keyEquivalent: "")
    open.target = self
    open.representedObject = key
    sub.addItem(open)

    parent.submenu = sub
    menu.addItem(parent)
}
if urgent.count > 3 {
    let overflow = NSMenuItem(title: "Voir toutes (\(urgent.count))…",
                              action: #selector(openMainWindow),
                              keyEquivalent: "")
    overflow.target = self
    menu.addItem(overflow)
}
menu.addItem(.separator())
```

- [ ] **Step 3: Ajouter le selector markUrgentDone**

Localiser `@objc private func showUrgent(_ sender: NSMenuItem)` (vers ligne 473) et ajouter juste au-dessus :

```swift
@objc private func markUrgentDone(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String,
          let task = urgentTaskByKey[key],
          let container = container else { return }
    task.isCompleted = true
    task.completedAt = Date()
    try? container.mainContext.save()
    rebuildMenu()
}
```

- [ ] **Step 4: Vérifier rebuildMenu existe**

```bash
grep -n "func rebuildMenu\|rebuildMenu()" OneToOne/Services/MenuBarController.swift | head
```
Expected: la fonction existe. Si elle s'appelle autrement (ex: `refreshMenu`, `buildMenu`), adapter le nom dans `markUrgentDone`.

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/MenuBarController.swift
git commit -m "feat(menubar): submenu Marquer comme fait / Ouvrir sur actions urgentes + overflow"
```

---

### Task 5: Final build + smoke test

**Files:** (aucun — vérif manuelle)

- [ ] **Step 1: Full build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 2: Lancement + smoke**

```bash
swift run 2>&1 | head -30 &
```

Manuel :
1. Ouvrir une fiche collaborateur. La section "Préparation prochaine 1:1" doit être dépliable. Bouton "Créer une préparation" visible si vide.
2. Cocher une action en cours → passe dans "Terminées (N)". Décocher dans "Terminées" → revient dans pending.
3. Cliquer `+` du header "Actions en cours" → row inline. Saisir titre, choisir projet, échéance, ✓ → action créée et apparaît dans la liste.
4. Esc dans la row inline ferme sans créer.
5. Cliquer icône menubar → "Actions urgentes" affiche des submenu. Hover sur un item → "✓ Marquer comme fait" / "Ouvrir…". Click "Marquer comme fait" → item disparaît au prochain refresh.
6. Si > 3 urgentes, item "Voir toutes (N)…" en bas → ouvre la fenêtre principale.

- [ ] **Step 3: Vérifier historique commits**

```bash
git log --oneline -6
```
Expected: 4 commits avec prefix `fix(collab)`, `feat(collab)`, `feat(menubar)`.

---

## Self-review

**Spec coverage:**
- §2 Toggle expansion via @State + CTA "Créer préparation" → Task 1. ✓
- §2 Checkbox = Button flip → Task 2. ✓
- §2 Quick-add inline → Task 3. ✓
- §2 Menubar submenu Marquer fait / Ouvrir + Voir toutes → Task 4. ✓
- §3 Modifs `DetailsViews.swift` + `MenuBarController.swift` → Tasks 1-3 + 4. ✓
- §4.1 Prep section → Task 1. ✓
- §4.2 Cochable code exact → Task 2 (avec correction `completedAt` au lieu de `completedDate`). ✓
- §4.3 Quick-add row → Task 3. ✓
- §4.4 Menubar submenu code → Task 4. ✓
- §5 Erreurs (save silencieux) → Tasks 1-4 utilisent `try?`. ✓
- §6 Tests manuels → Task 5. ✓

**Placeholder scan:**
- Aucun "TBD" / "TODO".
- Tous les snippets de code sont complets.
- Le seul point d'adaptation est `dateLabel` (Step 4 Task 3) et nom `rebuildMenu` (Step 4 Task 4) — instructions explicites pour adapter si besoin.

**Type consistency:**
- `ActionTask.completedAt` utilisé partout (pas `completedDate`). ✓
- `ActionTask.collaborator` utilisé pour assigner (pas `assignedCollaborator`). ✓
- `availableProjects` (`@Query` Task 3) → cohérent avec usage Menu Task 3. ✓
- `quickAddProject` / `quickAddDueDate` / `quickAddTitle` / `showingQuickAdd` — cohérents Task 3. ✓
- `urgentTaskByKey` réutilisé Task 4 (déjà existant). ✓
- `openMainWindow` selector existant utilisé pour overflow Task 4. ✓

Aucune correction inline nécessaire.
