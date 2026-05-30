# Project Ownership — Chef de projet + Architecte technique — Design

**Date:** 2026-05-23

## 1. Objet

Permettre d'assigner explicitement un **chef de projet** et un **architecte technique** à chaque `Project`. Ces deux rôles structurent la suite : reprise des sujets en 1:1 (« quels projets sont sur le dos de cet architecte ? »), contextualisation prep, et nouvelles réunions de type « Architecture technique d'équipe ».

Sous-projet **1 / 3** d'une roadmap plus large. Foundation indispensable. Sub-projets suivants :
- 2 — Contextual 1:1 Prep (utilise les FK ajoutées ici)
- 3 — Team Arch Meeting + Cross-RAG

## 2. Décisions actées

1. Ajout de 2 FK Optional sur `Project` : `projectManager: Collaborator?` et `technicalArchitect: Collaborator?`.
2. 2 relations inverse sur `Collaborator` : `projectsAsManager: [Project]` et `projectsAsArchitect: [Project]` pour reverse query rapide.
3. Picker UX : favoris en haut (`pinLevel ≥ 1`), puis autres collabs, puis bouton « + Ajouter… ». Réutilise le pattern existant des actions (sidebar Actions → assignee menu).
4. ProjectDetailView : 2 nouvelles lignes dans GroupBox « Informations Générales » après Sponsor.
5. CollaboratorDetailView : nouveau GroupBox « Projets » placé entre Identité et Préparation 1:1, avec 2 sous-sections triées par statut (Red → Yellow → Green → Unknown).
6. Pas de validation forcée « doit être favori » — l'UI suggère, n'impose pas.

## 3. Architecture

### 3.1 Modèle

```swift
@Model final class Project {
    // … existants …
    var projectManager: Collaborator?
    var technicalArchitect: Collaborator?
}

@Model final class Collaborator {
    // … existants …
    @Relationship(inverse: \Project.projectManager)
    var projectsAsManager: [Project] = []

    @Relationship(inverse: \Project.technicalArchitect)
    var projectsAsArchitect: [Project] = []
}
```

Lightweight migration (Optional FK + Array relation par défaut vide). Pas de migration explicite nécessaire.

### 3.2 Composant `OwnerPickerMenu`

Nouveau fichier `OneToOne/Views/Shared/OwnerPickerMenu.swift`.

```swift
struct OwnerPickerMenu: View {
    let label: String                    // ex: "Aucun"
    @Binding var selection: Collaborator?
    let allCollaborators: [Collaborator]
    var onSaved: () -> Void = {}

    // Computed:
    // - favorites = allCollaborators.filter { $0.pinLevel >= 1 && !$0.isArchived }
    // - others    = allCollaborators.filter { $0.pinLevel == 0 && !$0.isArchived }
    // - sorted alpha within each group
}
```

Rend un `Menu(.borderlessButton)` avec :
- « Aucun » en tête (binding nil)
- Divider + Section « Favoris » si `favorites.nonEmpty`
- Divider + Section « Autres collaborateurs » si `others.nonEmpty`
- Divider + bouton « + Ajouter un collaborateur… » → présente `AddCollaboratorSheet` (déjà existante)

Label affiché : `selection?.name ?? label`. Sur sélection : set binding + appel `onSaved()` (pour `try? context.save()`).

### 3.3 ProjectDetailView — modifications

Dans GroupBox « Informations Générales », après la ligne « Sponsor », ajouter :

```swift
LabeledContent("Chef de projet") {
    OwnerPickerMenu(label: "Aucun",
                    selection: $project.projectManager,
                    allCollaborators: collaborators,
                    onSaved: saveContext)
}
LabeledContent("Architecte technique") {
    OwnerPickerMenu(label: "Aucun",
                    selection: $project.technicalArchitect,
                    allCollaborators: collaborators,
                    onSaved: saveContext)
}
```

`collaborators` est déjà un `@Query` dans `ProjectDetailView`. `saveContext` à créer si non présent (sinon `try? context.save()`).

### 3.4 CollaboratorDetailView — nouvelle GroupBox « Projets »

Placée entre l'actuelle GroupBox « Identité » et « Préparation prochaine 1:1 ». Affichée **uniquement** si `collaborator.projectsAsArchitect.nonEmpty || collaborator.projectsAsManager.nonEmpty`.

```
┌─ Projets ─────────────────────────────────────────┐
│ EN TANT QU'ARCHITECTE TECHNIQUE  (3)              │
│  ● NEVIDIS · Projet Névidis             [Yellow]→ │
│  ● COOG · Migration Coog                [Red]   → │
│  ● APRIL-IO · Poste vs Citrix           [Green] → │
│                                                   │
│ EN TANT QUE CHEF DE PROJET  (1)                   │
│  ● PEGA · Migration PEGA                [Yellow]→ │
└───────────────────────────────────────────────────┘
```

- Tri intra-section : `Red → Yellow → Green → Unknown`, puis alpha.
- Couleur du dot : selon `project.status` (constante existante `statusColor(_:)`).
- Click row : push `ProjectDetailView` via `NavigationLink`.
- Chip statut à droite avec texte du statut.

### 3.5 Fichiers impactés

| Path | Change |
|---|---|
| `OneToOne/Models/OtherModels.swift` | +2 fields `Project` (projectManager, technicalArchitect) + 2 relations inverse `Collaborator` |
| `OneToOne/Views/Shared/OwnerPickerMenu.swift` | new |
| `OneToOne/Views/DetailsViews.swift` | ProjectDetailView : 2 LabeledContent ; CollaboratorDetailView : nouveau GroupBox Projets |

Total : 1 nouveau fichier, 2 modifications. Aucun test unitaire nécessaire (UI + binding direct).

## 4. Contexte pour les sous-projets suivants

- **Sub-projet 2** (Contextual 1:1 Prep) utilisera `collaborator.projectsAsArchitect` + `projectsAsManager` pour :
  - Bloc « Projets de l'architecte » dans le tab Préparation
  - Variable template `{{collab.projects_as_architect}}` injectée dans le prompt LLM
  - Colonne `Projet` ajoutée au canonical Plan d'actions du rapport 1:1
- **Sub-projet 3** (Team Arch Meeting) utilisera l'agrégation des projets par équipe pour construire l'agenda.

## 5. UX details

- Si un collab change de favori → archivé → désaffecté projet : pas de cascade automatique. Le projet garde le collab comme archi/PM même s'il n'est plus favori (cohérence historique). L'UI affichera juste son nom sans mise en avant favori.
- Si un collab est supprimé : SwiftData remet `Project.projectManager` / `technicalArchitect` à `nil` (default delete rule = nullify pour Optional FK).
- Re-assigner un nouveau archi écrase l'ancien sans historisation (V1, on garde simple).

## 6. Erreurs / edge cases

- `collab.isArchived == true` : exclu des menus Favoris et Autres (déjà filtré dans le picker via `!$0.isArchived`).
- Aucun favori : la section Favoris du menu n'apparaît pas, on a juste « Autres collaborateurs ».
- ProjectDetailView ouvert sans `@Query collaborators` (cas non-prévu) : OwnerPickerMenu reçoit `[]` → menu vide sauf « Aucun » et « + Ajouter ».

## 7. YAGNI

- Pas de multi-architecte par projet (1 seul).
- Pas d'historique des assignations (qui était archi avant).
- Pas de notification « tu as été assigné comme architecte sur X ».
- Pas de validation « doit être favori avant d'être archi ».
- Pas de panneau dédié à la liste « tous les archi de l'équipe ».
- Sponsor reste un String libre.

## 8. Tests

- Pas de tests unitaires (relations SwiftData + UI binding direct, peu de logique métier).
- Smoke test manuel :
  1. Ouvrir un projet → Informations Générales → assigner Chef de projet via picker. Vérifier persistance après restart app.
  2. Idem Architecte technique.
  3. Ouvrir le collab assigné → GroupBox Projets visible avec le projet listé sous la bonne sous-section.
  4. Click row projet → navigue vers ProjectDetailView.
  5. Vérifier tri Red → Yellow → Green pour un collab affecté à plusieurs projets de statuts variés.
  6. Désassigner un projet (set nil) → la row disparaît de la fiche collab.
  7. Picker affiche favoris en premier, autres ensuite.

## 9. Livrables

- `OneToOne/Models/OtherModels.swift` modifié
- `OneToOne/Views/Shared/OwnerPickerMenu.swift` nouveau
- `OneToOne/Views/DetailsViews.swift` modifié (deux views)

Spec ready.
