# ⌘K va à la palette, l'assistant de réunion passe à ⌘⇧K

**Statut :** acceptée le 2026-09-09 (décision **D1** de la refonte de la gestion des projets,
validée par Laurent le 2026-09-09)
**Portée :** `AppShortcut` (ex-table des raccourcis de réunion), `MeetingCommands`,
`MeetingMenuItem`, `SessionAssistantPanel`, `MeetingShortcutsSheet`, `MainRouter`,
`CommandPalette`, `StartOneToOneIntent`
**Références :** `docs/superpowers/specs/2026-09-09-gestion-projets-design.md` §2 (constat 2),
§3 (D1) · `docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md` §1c et
§Interactions · `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §1.4 ·
`docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`

## Contexte

Le handoff de la refonte de la gestion des projets demande une **palette de commandes** ouverte
par `⌘K` depuis n'importe quel écran (capture `1c-palette-cmdk.png`, §Interactions : « `⌘K` :
ouvre la palette depuis n'importe quel écran »). `⌘K` est la convention universelle des palettes
— Spotlight mis à part, c'est le geste de VS Code, de Linear, de Notion, de Slack et de Raycast.

**La combinaison était prise.** La spec §1.4 de la refonte de l'écran de réunion l'attribue à
l'assistant, et le lot 19c de cette refonte en a fait une table unique
(`Views/Menus/MeetingShortcut.swift`) avec trois surfaces de déclaration et un test qui fige la
liste des jetons **et** l'ensemble des déclarants (`Tests/MeetingShortcutsTests.swift`). Trois
endroits l'épelaient : la table, l'item « Assistant… » de `MeetingCommands`, et le doublon
assumé de `SessionAssistantPanel` — l'assistant du mode séance, qui n'est pas une feuille à
ouvrir mais un panneau déjà visible auquel le raccourci rend le clavier.

Trois autres contraintes pesaient sur le choix :

- **`HotkeySpec` est le mauvais outil.** C'est le mécanisme Carbon des raccourcis **système**,
  actifs même quand l'application n'a pas le focus. Une palette n'a rien à y faire : elle vit
  dans la fenêtre principale.
- **Le geste doit marcher sans réunion focalisée.** Les items de `MeetingCommands` sont grisés
  quand `FocusedValue(\.meetingMenu)` est `nil` ; une palette grisée sur le tableau de bord
  n'ouvrirait rien.
- **La table ne s'appelait plus comme ce qu'elle contient.** `MeetingShortcut` documentait « les
  raccourcis de l'écran de réunion » ; un raccourci de portée application n'y avait pas sa
  place sous ce nom.

## Décision

**`⌘K` ouvre la palette. L'assistant de réunion prend `⌘⇧K`. La table devient `AppShortcut`.**

1. **`Views/Menus/MeetingShortcut.swift` → `AppShortcut.swift`** (`git mv`, l'historique suit),
   `enum MeetingShortcut` → `enum AppShortcut`, `.meetingShortcut(_:)` → `.appShortcut(_:)`.
   Les huit cas de la spec §1.4 restent ; un neuvième, `palette`, arrive en tête. Aucun
   `typealias` de compatibilité : les cinq appelants sont renommés, et un test refuse toute
   trace du nom retiré.
2. **`AppShortcut.palette`** porte `⌘K`, le libellé « Palette — projets et actions, depuis
   n'importe quel écran » et la surface `.menu(.palette)`. **`AppShortcut.assistant`** garde son
   libellé et passe à `⌘⇧K`.
3. **`MeetingMenuItem` gagne `.palette`.** Le cas décrit la *surface de déclaration* — un item
   de `MeetingCommands` — et non une dépendance à une réunion : `MeetingCommands` est le seul
   endroit du dépôt où un raccourci de fenêtre principale peut être déclaré, parce qu'un menu
   natif est le seul mécanisme actif sans vue focalisée. L'item « Palette… » ne porte donc
   **aucun** `.disabled`, et c'est ce qu'un test vérifie.
4. **L'état d'ouverture est dans `MainRouter`** (`paletteTerme`, `ouvrirPalette(terme:)`,
   `fermerPalette()`), pas dans un `@State` d'écran : un item de menu natif n'a accès à aucune
   hiérarchie de vues, et le routeur est déjà le singleton que le menu système et `ContentView`
   partagent (ADR du 2026-09-09 sur le routeur). L'état *interne* de la palette — terme frappé,
   ligne sélectionnée — reste dans `PaletteModel`, comme l'état d'écran d'une réunion vit dans
   `MeetingScreenModel`.
5. **`SessionAssistantPanel` suit**, raccourci et jeton affiché.

### Une collision de noms, et pourquoi elle est traitée là où elle se produit

`AppShortcut` est **aussi** un type du framework `AppIntents` d'Apple, employé par
`OneToOneShortcuts: AppShortcutsProvider` pour déclarer les phrases Siri et Spotlight de
`StartOneToOneIntent`. Le type du dépôt le masque dans tout le module. Aucun des deux noms n'est
renommable sans perdre : celui d'Apple appartient au framework, celui du dépôt est le nom que la
décision a arrêté. Les deux occurrences de `StartOneToOneIntent.swift` sont donc qualifiées
`AppIntents.AppShortcut`, avec le commentaire qui l'explique — et nulle part ailleurs.

## Alternatives étudiées

**(a) La palette sur `⌘P`, rien ne bouge côté assistant.** `⌘P` est libre dans le dépôt.
Rejetée : c'est « imprimer » pour tout utilisateur de macOS, la spec de conception écrit `⌘K`
noir sur blanc, et l'alternative n'était retenue que si Laurent refusait le déplacement de
l'assistant — il l'a validé le 2026-09-09.

**(b) Un `HotkeySpec` global pour la palette.** Rejetée : un raccourci Carbon système ouvrirait
la palette depuis n'importe quelle **application**, pas seulement depuis n'importe quel écran.
Ce n'est pas ce que le handoff demande, et cela volerait `⌘K` à tout le poste.

**(c) Garder le nom `MeetingShortcut` et y ajouter `palette`.** Le moins de fichiers touchés.
Rejetée : le nom aurait menti sur la moitié de son contenu, et la documentation de la table dit
explicitement « les raccourcis de l'écran de réunion ». Un nom faux dans une table unique est
exactement ce qui fait rouvrir une seconde table ailleurs.

**(d) Une seconde table `AppShortcut` à côté de `MeetingShortcut`.** Rejetée pour la même
raison qu'il n'y en avait qu'une : deux tables de raccourcis divergent, et le garde-fou
« aucun second déclarant » perd son sens dès qu'il y a deux endroits légitimes où déclarer.

## Conséquences

**Positives**

- La palette s'ouvre d'un geste que tout le monde connaît, depuis n'importe quel écran.
- La table redevient exacte : elle nomme ce qu'elle contient, et le prochain raccourci de portée
  application a un endroit évident où aller.
- Le garde-fou est **renforcé** : `⌘K` n'admet désormais **aucun** second déclarant (la palette
  prend le sien dans la table), là où l'assistant en tolérait un. `⌘⇧K` hérite de l'exception
  nommée `SessionAssistantPanel`.
- La feuille « Raccourcis clavier » annonce le nouveau geste sans qu'on y touche : elle rend
  `AppShortcut.allCases`.

**Négatives et parades**

- **Un utilisateur habitué à `⌘K` pour l'assistant tapera `⌘K` et verra la palette.** La table
  porte une `note` qui le dit, la feuille d'aide la rend, et le panneau d'assistant du mode
  séance affiche son nouveau jeton `⌘⇧K` en clair dans son en-tête.
- **La spec §1.4 de la refonte réunion est désormais fausse sur une ligne.** Elle vit sur la
  branche `docs/refonte-reunion-programme`, jamais fusionnée dans la pile : elle n'est pas
  amendable ici. Cet ADR est l'amendement, et `AppShortcut.assistant.note` le dit dans le code
  — le seul endroit que lira quelqu'un qui cherche pourquoi.
- **`MeetingMenuItem` porte un cas qui n'est pas une action de réunion.** Assumé et commenté aux
  deux endroits (l'`enum` et `isEnabled`), plutôt qu'un second mécanisme de déclaration de menu
  pour un seul item.
- **`MeetingShortcutsSheet` garde son nom** alors qu'elle rend une table qui n'est plus
  seulement de réunion. C'est bien la feuille du menu `⋯` d'une **réunion** ; la renommer aurait
  fait deux intentions dans une PR qui n'en veut qu'une. Son sous-titre est corrigé.
- **La collision avec `AppIntents.AppShortcut`** reviendra mordre quiconque ajoutera un App
  Intent : le compilateur le dira, et le commentaire de `StartOneToOneIntent.swift` donne la
  parade en une ligne.

## Vérification

- `Tests/AppShortcutsTests.swift` (11 tests) — les neuf jetons attendus
  (`⌘K`, `⌘⇧K`, `⌘M`, `⌘⇧A`, `⌘⇧S`, `⌘⇧N`, `⌘⇧V`, `⌘⏎`, `⌃⌘F`) ; aucun doublon dans la table ;
  le jeton se déduit de la touche et des modificateurs ; `MeetingCommands` prend ses raccourcis
  dans la table et n'en épelle aucun ; **`⌘K` n'a aucun second déclarant** et `⌘⇧K` n'a que
  `SessionAssistantPanel` ; la palette porte le bon libellé, la bonne surface et n'est pas
  grisée ; **aucune trace du nom retiré** dans les sources.
- `Tests/CommandPaletteTests.swift` — le routeur ouvre et referme la palette, le terme de la
  recette `p1c` n'ouvre qu'une fois, `ContentView` pose la superposition avant l'environnement.
