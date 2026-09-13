# Un routeur pour la fenêtre principale

**Statut :** acceptée le 2026-09-09 (décision **D0** de la refonte de la gestion des projets,
validée par Laurent le 2026-09-09)
**Portée :** `MainRoute`, `MainRouter`, `MainDetailView`, `MainSidebarView`, `ContentView`,
`MenuBarController`, `RecetteScreen`
**Références :** `docs/superpowers/specs/2026-09-09-gestion-projets-design.md` §2.1, §3 (D0) ·
`docs/superpowers/plans/2026-09-09-gestion-projets.md` (lot 0) ·
`docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md`

## Contexte

La fenêtre principale se naviguait exclusivement à la souris, et rien d'autre ne pouvait
la piloter.

- **La barre latérale était une liste de destinations inline.** `MainSidebarView` déclarait
  onze `NavigationLink` dont chacun construisait sa vue dans son propre corps
  (`DashboardView()`, `ChatbotView()`, `ProjectDetailView(project:)`…). Le lien *est* la
  destination : il n'existe aucune valeur qui désigne un écran, donc aucun moyen d'en
  sélectionner un par programme.
- **`ContentView.selectedTab` était mort.** Un `@State private var selectedTab: String? =
  "Dashboard"` que rien n'écrivait et que rien ne lisait — le vestige d'une navigation par
  jeton qui n'a jamais été branchée.
- **Quatre appelants attendaient une destination et n'en avaient pas.**
  `SearchPopover.onSelectProject` était câblé sur `{ _ in /* future: deep-link to
  ProjectDetail */ }` dans `MenuBarController` : choisir un projet dans la recherche du menu
  système ne faisait rien. La recette visuelle, elle, ne savait ouvrir qu'une **réunion**
  (`RecetteScreen.Cible`), jamais un écran de la fenêtre principale.

Or les cinq écrans de la refonte de la gestion des projets en ont besoin partout : la palette
`⌘K` ouvre un projet, la section « Récents » ouvre un projet, le fil d'Ariane
`Portfolio / ASP / P25_193` remonte au Portfolio puis à l'entité, « Tout voir » ouvre l'onglet
Actions, « 1:1 ▸ » ouvre la fiche d'un collaborateur. Sans une valeur qui nomme un écran,
aucune de ces interactions n'est réalisable — et ce n'est pas un détail d'implémentation :
c'est la moitié du handoff.

## Décision

**La fenêtre principale est routée par une valeur, et la barre latérale la sélectionne.**

1. **`MainRoute`** (`enum`, `Hashable`, `Sendable`) nomme les écrans : les huit qui existaient
   (`dashboard`, `assistant`, `actions`, `meetings`, `notes`, `manager`, `collaborators`,
   `settings`), les cinq que la refonte livre (`portfolio`, `atRisk`, `projectMeetings`,
   `projectActions`, `searchReports(String)`) et les trois fiches (`project(UUID, ProjectTab)`,
   `collaborator(UUID)`, `entity(PersistentIdentifier)`).
2. **`MainRouter`** (`@MainActor @Observable`) porte `route`, une `history` bornée à vingt
   écrans, `open(_:)`, `back()` et `openProject(_:tab:)`. Il est exposé en singleton `.shared`
   et injecté dans l'environnement par `ContentView`.
3. **`MainSidebarView` devient une `List(selection:)`** sur `MainRoute?`. Chaque
   `NavigationLink` est devenu une ligne taguée : même contenu, même rendu, destination
   déplacée.
4. **`MainDetailView` fait le `switch`.** C'est un routeur, comme `MeetingView` : il monte un
   écran, il n'en calcule aucun.

### Trois choix qui méritent d'être écrits

**Un projet et un collaborateur sont désignés par leur `stableID` ; une entité par son
`PersistentIdentifier`.** `Project` et `Collaborator` portent déjà un `stableID: UUID?`
backfillé au lancement par `repairStoreIfNeeded()`, et c'est cet identifiant que les projets
récents persistent dans `@AppStorage`. `Entity`, lui, n'en a pas. Lui en ajouter un pour ce
seul besoin aurait été un changement de modèle dans un lot qui ne change aucun rendu ;
`PersistentIdentifier` est `Hashable` et `Sendable`, ce qui suffit à une route.

**Un singleton, alors que le reste de l'état d'écran est injecté.** `MeetingScreenModel` est un
`@State` local et le programme de refonte de l'écran de réunion en a fait une règle. Ici c'est
impossible : `MenuBarController` est un `NSObject` hors de la hiérarchie SwiftUI — il ne peut
lire aucun `@Environment`, et c'est lui qui ouvre un projet depuis la recherche du menu
système. `MainRouter.shared` est donc le routeur de l'application ; `ContentView` l'injecte
tel quel, et les tests construisent leur propre instance avec leurs propres `UserDefaults`.

**Le routeur porte un terme en attente pour la palette.** `MainRouter.pendingPaletteQuery` est
posé par l'écran de recette `p1c` et sera consommé par la palette au lot 3. La palette n'existe
pas encore, et le routeur est le seul objet que la recette puisse atteindre avant elle. C'est
une dette assumée, bornée à une propriété et à une méthode.

## Alternatives étudiées

**(a) Garder les `NavigationLink` et ajouter un `NavigationPath` programmatique.** C'est
l'outil qu'Apple propose pour piloter une pile. Rejetée : la colonne de détail d'un
`NavigationSplitView` n'est pas une pile qu'on empile — c'est une **sélection** qu'on remplace.
Un `NavigationPath` aurait fait cohabiter deux mécanismes (sélection dans la barre latérale,
pile dans le détail) pour un seul besoin, et le fil d'Ariane de la capture 1d aurait dû
manipuler la pile de l'un tout en écrivant la sélection de l'autre.

**(b) Router par `PersistentIdentifier` partout, sans `stableID`.** Uniforme, et sans le cas
particulier de `Entity`. Rejetée : un `PersistentIdentifier` n'est pas persistable en réglage
(les projets récents en ont besoin) ni transportable entre fenêtres — les jetons de lancement
de réunion emploient déjà `stableID` pour cette raison exacte.

**(c) Étendre `QuickLaunchRouter`.** Il existe, il est déjà dans l'environnement, et il ouvre
déjà des fenêtres de réunion. Rejetée : c'est un `ObservableObject` dont le rôle est de
*consommer un jeton d'ouverture de fenêtre*, une fois. La route de la fenêtre principale est un
état durable, lu à chaque image. Les mélanger aurait fait un objet à deux natures, et rendu
`@Observable` inatteignable pour la moitié qui en profite (`List(selection:)` veut un `Binding`,
donc `@Bindable`).

## Conséquences

**Positives**

- Les cinq écrans de la refonte sont atteignables sans clic, donc **photographiables** :
  `RecetteScreen.Cible.fenetrePrincipale(MainRoute)` s'appuie directement là-dessus, et les six
  codes `p2b`, `p1a`, `p1c`, `p1d`, `p1f`, `p2a` existent dès ce lot.
- La recherche du menu système ouvre enfin le projet qu'on y choisit — un no-op de moins.
- `selectedTab` disparaît : il n'y a plus qu'un endroit qui sait quel écran est affiché.
- Ajouter un écran, désormais, c'est ajouter un cas à un `enum` et un cas à un `switch` : le
  compilateur dit où.

**Négatives et parades**

- **Une ligne dont l'objet n'a pas de `stableID` n'est pas sélectionnable.**
  `repairStoreIfNeeded()` les backfille tous au lancement, donc le cas ne se produit pas ; on
  préfère une ligne inerte à une écriture dans le store depuis `body`.
- **`MainRoute` grossira.** C'est le prix d'un `switch` total, et c'est ce qu'on veut : un
  `default` ferait taire le compilateur au moment précis où l'on a besoin qu'il parle.
- **Les cinq écrans à venir affichent une invite « Bientôt : … ».** Volontaire, et éphémère :
  chaque lot en retire une. Sobre, aux jetons `One2OneToken` et à la fonte Plex, comme tout ce
  qui vit sous `Views/Navigation/` (décision **D17**).
- **Le singleton est un état global de plus.** Borné à la fenêtre principale, sans effet de
  bord hors de la route, et testable — `MainRouter(defaults:)` reste accessible.

## Vérification

- `Tests/MainRouterTests.swift` — état initial, `open` empile le précédent, `back` dépile,
  réouvrir l'écran courant n'empile rien, histoire bornée à vingt, `openProject` route sur
  Pilotage et inscrit le projet aux récents, backfill d'un `stableID` absent, terme de palette
  consommé une seule fois, deux routes de projet distinctes par leur seul onglet.
- `Tests/RecetteScreenTests.swift` — les six écrans de fenêtre principale et leurs routes ; les
  douze écrans de réunion gardent leur cible.
- `Tests/RefonteTypographieTests.swift` — `Views/Navigation/` entre dans le périmètre
  typographique.
- Vérification par lecture : chacune des onze destinations de la barre latérale a un cas dans
  `MainDetailView`.
