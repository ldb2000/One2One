# Collaborator actions & prep — UX fixes design

**Date:** 2026-05-22

## 1. Objet

Trois irritants sur la fiche collaborateur (`CollaboratorDetailView`) + une lacune sur le menubar :

1. **Préparation prochaine 1:1** — le `DisclosureGroup` est verrouillé via `.constant(...)` et reste replié si `standingPrepNotes` est vide ; impossible de le déplier pour saisir une prep.
2. **Actions en cours** — la coche est un `Image` statique, pas de toggle de `isCompleted`.
3. **Ajout rapide d'action** — aucun bouton sur la section "Actions en cours".
4. **Menubar** — les items "Actions urgentes" n'offrent qu'« Ouvrir » ; impossible de cocher comme fait sans naviguer.

## 2. Décisions actées

- Toggle d'expansion via `@State` ; pré-expansion si prep non-vide ; bouton explicite "Créer une préparation" quand vide.
- Checkbox = `Button` qui flip `task.isCompleted` + maj `task.completedDate`.
- Quick-add inline en haut de la liste (titre + projet + échéance + confirm/cancel). Pas de sheet.
- Menubar : chaque item urgent devient un submenu avec « ✓ Marquer comme fait » et « Ouvrir ». Si > 3 urgentes, ajout d'un item « Voir toutes (N)… » qui ouvre `AllTasksView` filtré urgentes.

## 3. Architecture

Pas de nouveau service. Modifs ciblées :

| Fichier | Changement |
|---|---|
| `OneToOne/Views/DetailsViews.swift` | `CollaboratorDetailView` : `@State prepExpanded` ; `Button` toggle sur checkbox ; row quick-add ; helper `addQuickAction()` |
| `OneToOne/Services/MenuBarController.swift` | `appendUrgentSection()` : submenu par item ; entry "Voir toutes" si overflow ; nouveaux selectors `@objc markUrgentDone(_:)` |
| `OneToOne/Services/UrgentActionsSelector.swift` (lecture seule, pas modifié) | — |

## 4. Détails UI

### 4.1 Prep section

```swift
@State private var prepExpanded: Bool = false
// .onAppear { prepExpanded = !collaborator.standingPrepNotes.isEmpty }

DisclosureGroup(isExpanded: $prepExpanded) {
    if collaborator.standingPrepNotes.isEmpty && !prepExpanded {
        Button("Créer une préparation") { prepExpanded = true }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
    } else {
        MarkdownEditorView(...)
        // bouton Générer brouillon IA inchangé
    }
}
```

État vide doit afficher l'éditeur dès qu'on déplie ; bouton "Créer une préparation" pré-déplie pour rendre l'affordance évidente.

### 4.2 Actions cochables

```swift
Button {
    task.isCompleted.toggle()
    task.completedDate = task.isCompleted ? Date() : nil
    try? context.save()
} label: {
    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
        .foregroundColor(task.isCompleted ? .green : .gray)
}
.buttonStyle(.plain)
```

Row label reste cliquable (NavigationLink ou Sheet vers le détail action) — comportement existant conservé.

### 4.3 Quick-add row

Header de la GroupBox :
```
[Actions en cours] [3]              [+]
```

Bouton `+` toggle un état `@State showingQuickAdd: Bool`. Quand `true`, row inline en tête de liste :

```
[ Titre… ]  [Projet ▾]  [Échéance ▾]  [✓]  [✗]
```

- Projet : `Menu` listant projets actifs + "Aucun"
- Échéance : `DatePicker` compact + bouton "Aucune"
- ✓ : crée `ActionTask(title:..., dueDate:..., project:..., assignedCollaborator: collaborator)`, save, ferme row
- ✗ : ferme sans créer
- Enter dans le TextField = ✓

Validation : titre non-vide trimmed sinon ✓ disabled.

### 4.4 Menubar submenu urgent

`MenuBarController.appendUrgentSection()` :

```swift
for task in urgent.prefix(3) {
    let parent = NSMenuItem(title: urgentLabel(for: task), action: nil, keyEquivalent: "")
    let sub = NSMenu()
    let done = NSMenuItem(title: "✓ Marquer comme fait",
                          action: #selector(markUrgentDone(_:)),
                          keyEquivalent: "")
    done.target = self
    done.representedObject = key
    sub.addItem(done)
    let open = NSMenuItem(title: "Ouvrir",
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
                              action: #selector(openAllUrgent),
                              keyEquivalent: "")
    overflow.target = self
    menu.addItem(overflow)
}
```

`markUrgentDone(_:)` : récupère task via `urgentTaskByKey`, set `isCompleted = true` + `completedDate = Date()`, save, rebuild menu.

`openAllUrgent` : `QuickLaunchRouter.shared.pendingToken = ...` ou activation de fenêtre principale + sélection `AllTasksView` (mécanisme existant à confirmer en plan).

## 5. Erreurs

- Quick-add titre vide → bouton ✓ disabled, pas d'erreur.
- Save échec → log seulement (cohérent avec reste de l'app).
- Concurrence menubar/main window : `try? context.save()` puis `rebuildMenu()` est suffisant.

## 6. Tests

- Pas de logique métier nouvelle → tests UI manuels :
  1. Fiche collab : créer/déplier prep, cocher action, ajouter action via quick-add.
  2. Menubar : urgent submenu Marquer fait → disparait de la liste au prochain refresh ; Ouvrir = comportement existant.

## 7. YAGNI

- Pas d'édition inline du titre / échéance d'une action existante (déjà accessible via détail).
- Pas de drag-to-reorder.
- Pas de raccourci clavier global pour quick-add (popover menubar suffit).
- Pas de undo (delete via détail).

## 8. Livrables

- `DetailsViews.swift` modifié (CollaboratorDetailView)
- `MenuBarController.swift` modifié (submenu urgent + overflow)
- Spec doc commité
