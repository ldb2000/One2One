# Commandes slash — inventaire AppFlowy et prompt d'implémentation OneToOne

**Date** : 2026-08-05
**Source de référence** : AppFlowy, branche `main`, client Flutter desktop —
`frontend/appflowy_flutter/lib/plugins/document/presentation/editor_plugins/slash_menu/`
(`slash_menu_items_builder.dart` pour l'ordre et la composition du menu,
`slash_menu_items/*.dart` pour les mots-clés, `frontend/resources/translations/en-US.json`
sous `document.slashMenu` pour les libellés et les noms de groupes).

> AppFlowy est **AGPL** : aucun code n'est repris. Seule la *structure de conception*
> (clé, libellé, mots-clés, alias, groupe, filtrage contextuel) est réutilisée — comme
> déjà documenté en tête de `SlashCommand.swift`.

---

## Partie 1 — Inventaire complet des commandes slash d'AppFlowy

Ordre = celui de `_defaultSlashMenuItems()`. Groupes = clés `document.slashMenu.name.*`
utilisées côté web/mobile (`Text Style`, `List`, `Toggle`, `File & Media`, `Simple Table`,
`Visuals`, `Document`, `Advanced`).

| # | Commande AppFlowy | Libellé EN | Mots-clés (source) | Présent dans OneToOne |
|---|---|---|---|---|
| 1 | `continueWritingSlashMenuItem` | Continue writing | `continue writing` | ❌ |
| 2 | `aiWriterSlashMenuItem` | Ask AI Anything | `ai`, `openai`, `writer`, `ai writer`, `autogenerator` | ❌ |
| 3 | `paragraphSlashMenuItem` | Text | `text`, `paragraph` | ✅ « Texte » |
| 4 | `heading1SlashMenuItem` | Heading 1 | `heading 1`, `h1`, `heading1` | ✅ « Titre 1 » |
| 5 | `heading2SlashMenuItem` | Heading 2 | `heading 2`, `h2`, `heading2` | ✅ « Titre 2 » |
| 6 | `heading3SlashMenuItem` | Heading 3 | `heading 3`, `h3`, `heading3` | ✅ « Titre 3 » |
| 7 | `imageSlashMenuItem` | Image | `image`, `photo`, `picture`, `img` | ✅ « Image » |
| 8 | `bulletedListSlashMenuItem` | Bulleted list | `bulleted list`, `list`, `unordered list`, `ul` | ✅ « Liste à puces » |
| 9 | `numberedListSlashMenuItem` | Numbered list | `numbered list`, `list`, `ordered list`, `ol` | ✅ « Liste numérotée » |
| 10 | `todoListSlashMenuItem` | To-do list | `checkbox`, `todo`, `list`, `to-do`, `task` | ✅ « Case à cocher » |
| 11 | `dividerSlashMenuItem` | Divider | `divider`, `separator`, `line`, `break`, `horizontal line` | ✅ « Séparateur » |
| 12 | `quoteSlashMenuItem` | Quote | `quote`, `refer`, `blockquote`, `citation` | ✅ « Citation » |
| 13 | `tableSlashMenuItem` | Table | `table`, `rows`, `columns`, `data` | ✅ « Tableau » |
| 14 | `linkToPageSlashMenuItem` | Link to page | `page`, `notes`, `referenced page`, `referenced document`, … | ❌ |
| 15 | `twoColumnsSlashMenuItem` | 2 Columns | `column`, `two columns`, … | ❌ |
| 16 | `threeColumnsSlashMenuItem` | 3 Columns | idem | ❌ |
| 17 | `fourColumnsSlashMenuItem` | 4 Columns | idem | ❌ |
| 18 | `gridSlashMenuItem` | Grid | `grid`, `database` | ❌ |
| 19 | `referencedGridSlashMenuItem` | Linked Grid | `referenced`, `grid`, `database`, `linked` | ❌ |
| 20 | `kanbanSlashMenuItem` | Kanban | `board`, `kanban`, `database` | ❌ |
| 21 | `referencedKanbanSlashMenuItem` | Linked Kanban | `referenced`, `board`, `kanban`, `linked` | ❌ |
| 22 | `calendarSlashMenuItem` | Calendar | `calendar`, `database` | ❌ |
| 23 | `referencedCalendarSlashMenuItem` | Linked Calendar | `referenced`, `calendar`, `database`, `linked` | ❌ |
| 24 | `calloutSlashMenuItem` | Callout | `callout` | ❌ |
| 25 | `outlineSlashMenuItem` | Outline | `outline`, `table of contents`, `toc`, `tableofcontents` | ❌ |
| 26 | `mathEquationSlashMenuItem` | Math Equation | `tex`, `latex`, `katex`, `math equation`, `formula` | ❌ |
| 27 | `codeBlockSlashMenuItem` | Code | `code`, `code block`, `codeblock` | ❌ |
| 28 | `toggleListSlashMenuItem` | Toggle list | `collapsed list`, `toggle list`, `list`, `dropdown` | ❌ |
| 29 | `toggleHeading1SlashMenuItem` | Toggle heading 1 | `toggle heading 1`, `toggle h1`, `toggleh1` | ❌ |
| 30 | `toggleHeading2SlashMenuItem` | Toggle heading 2 | idem niveau 2 | ❌ |
| 31 | `toggleHeading3SlashMenuItem` | Toggle heading 3 | idem niveau 3 | ❌ |
| 32 | `emojiSlashMenuItem` | Emoji | `emoji`, `reaction`, `emoticon` | ❌ |
| 33 | `dateOrReminderSlashMenuItem` | Date or Reminder | `insert date`, `date`, `time`, `reminder`, `schedule` | 🟡 « Date » (sans rappel) |
| 34 | `photoGallerySlashMenuItem` | Photo Gallery | `image`, `image gallery`, `photo`, `photo browser`, `gallery` | ❌ |
| 35 | `fileSlashMenuItem` | File | `file upload`, `pdf`, `zip`, `archive`, `upload`, `attachment` | ❌ |
| 36 | `subPageSlashMenuItem` | Document | `sub page`, `page`, `child page`, `insert page`, `embed page`, `new page`, `create page`, `document` | ❌ |

**État actuel OneToOne** : 11 entrées (`SlashCatalog.all`) — Texte, Titre 1-3, Liste à
puces, Liste numérotée, Case à cocher, Citation, Séparateur, Tableau, Image, Date.

---

## Partie 2 — Ce qui est implémentable dans OneToOne (avec verdict)

Contrainte structurante : **l'éditeur OneToOne est adossé à du markdown sérialisé**
(`MarkdownParser` ↔ `MarkdownSerializer`, round-trip garanti). Toute commande doit
produire une représentation qui **survit à un aller-retour markdown**. AppFlowy, lui,
persiste un arbre de nœuds JSON — d'où des blocs (colonnes, kanban) qui n'ont aucun
équivalent markdown et qui ne sont donc *pas* transposables tels quels.

| Commande à ajouter | Représentation markdown retenue | Coût | Priorité | Verdict |
|---|---|---|---|---|
| **Bloc de code** (`/code`) | Bloc fencé ` ```lang ` — `BlockType.codeBlock` + `.mdCodeLanguage` **existent déjà** (`MarkdownSerializer.fencedCodeBlock`) | S | 🔥 P0 | ✅ Faire — tout le socle est là, il manque l'entrée de menu et l'insertion |
| **Titres 4-6** (`/h4`, `/h5`, `/h6`) | `####`… — `BlockType.h4/h5/h6` + `LineBlockType.h4/h5/h6` + `MarkdownFeature.heading(.h4…)` **existent déjà** | XS | 🔥 P0 | ✅ Faire — 3 entrées de catalogue, zéro code moteur |
| **Emoji** (`/emoji`) | Caractère Unicode inséré tel quel, aucune syntaxe | XS | 🔥 P0 | ✅ Faire — `NSApp.orderFrontCharacterPalette(_:)` natif macOS |
| **Callout** (`/callout`) | Citation GFM avec préfixe emoji : `> 💡 texte` → round-trip en `blockquote`, sans perte | M | 🟠 P1 | ✅ Faire — variante « alerte GitHub » (`> [!NOTE]`) possible mais nécessite un parseur dédié |
| **Rappel** (`/rappel`) | Extension de l'entrée « Date » existante : `SlashDateSelection.reminder` est **déjà capturé mais ignoré** par `SlashController.insertDate` | M | 🟠 P1 | ✅ Faire — spec déjà écrite : `docs/superpowers/specs/2026-08-05-dates-et-rappels.md` |
| **Fichier joint** (`/fichier`) | Lien markdown `[nom.pdf](media://…)` — `MediaStore` ne sait aujourd'hui que `saveClipboardImage()` | M | 🟠 P1 | ✅ Faire — généraliser `MediaStore` à un type de fichier quelconque |
| **Sommaire / Outline** (`/sommaire`) | Liste à puces de liens statiques vers les titres, générée à l'insertion | M | 🟡 P2 | ✅ Faire en version **statique**. Un sommaire *vivant* exigerait un bloc recalculé à chaque frappe — hors périmètre |
| **Lien vers une entité** (`/projet`, `/personne`, `/entretien`) | `[Nom du projet](onetoone://project/<uuid>)` — le schéma `onetoone://` existe déjà (`MickeyIntegration`) | L | 🟡 P2 | ✅ Faire — **c'est la transposition OneToOne des items « base de données » d'AppFlowy** (lignes 14, 18-23, 36 du tableau ci-dessus) |
| **Liste dépliable** (`/toggle`) | `<details><summary>…</summary>…</details>` → passerait par `BlockType.rawBlock` (passthrough littéral, non replié à l'écran) | L | 🔵 P3 | ⚠️ Déconseillé en l'état — sans repli visuel, la valeur d'usage est nulle. Nécessite un vrai bloc pliable côté `MarkdownLayoutManager` |
| **Titres dépliables** (`/toggle h1-h3`) | idem | L | 🔵 P3 | ⚠️ Même verdict, dépend de la précédente |
| **Équation** (`/equation`) | `$$…$$` en `rawBlock` (texte brut monospace, pas de rendu KaTeX) | M | 🔵 P3 | ⚠️ Faible valeur pour un usage « manager d'architectes » |
| **IA** (`/ia`, `/continuer`) | Aucune syntaxe — insère le texte généré par `DirectLLMClient` | L | ⚖️ à arbitrer | ⚠️ **Explicitement hors périmètre** par décision utilisateur du 2026-08-04 (cf. en-tête de `SlashCatalog.swift`). Le socle technique existe pourtant (`DirectLLMClient`, provider `.direct`). **Décision à reprendre explicitement** avant de coder |
| **Galerie photo** (`/galerie`) | N-images côte à côte : pas d'équivalent markdown | L | ⛔ | ❌ Ne pas faire — `/image` répété couvre le besoin |
| **Colonnes 2/3/4** | Aucun équivalent markdown ; exige une mise en page multi-colonnes TextKit | XL | ⛔ | ❌ Ne pas faire |
| **Grid / Kanban / Calendar (+ liés)** | Bases de données génériques ; OneToOne a des modèles SwiftData typés, pas de DB générique | XL | ⛔ | ❌ Ne pas faire — remplacées par « Lien vers une entité » ci-dessus |
| **Sous-page** (`/document`) | Hiérarchie de documents ; OneToOne n'a pas de notion de page imbriquée | XL | ⛔ | ❌ Ne pas faire — remplacée par « Lien vers une entité » |

### Blocage préalable identifié (à traiter avant toute autre entrée)

`SlashPanel` **n'a ni hauteur maximale ni défilement** :
`SlashPanelMetrics.idealSize(for:)` (`SlashPanel.swift:318`) calcule une hauteur
strictement proportionnelle au nombre de lignes, et `SlashPanelContent` est un `VStack`
nu, sans `ScrollView`. Avec 11 entrées ça tient ; en passant à ~20, le panneau
dépassera l'écran et la navigation clavier sortira du champ visible. **C'est le lot 0
du prompt ci-dessous.**

---

## Partie 3 — Prompt de développement

> À copier-coller tel quel dans une session de développement dédiée.

---

### PROMPT

Tu implémentes les **commandes slash manquantes** de l'éditeur markdown de OneToOne
(app macOS SwiftUI + SwiftData, exécutable SwiftPM, `swift build` / `swift test`).
Lis `CLAUDE.md` et `docs/architecture.md` avant de commencer.

#### Contexte technique à assimiler d'abord

Lis intégralement, dans cet ordre :

1. `OneToOne/Markdown/Slash/SlashCommand.swift` — modèle d'une entrée (clé, libellé,
   mots-clés, alias, raccourci, groupe, `Action`, `requiredFeature`). Les doc-comments
   y expliquent **pourquoi** `.insertThematicBreak` / `.insertTable` sont des
   *insertions* et non des *conversions* : respecte cette distinction.
2. `OneToOne/Markdown/Slash/SlashCatalog.swift` — le catalogue, son ordre d'affichage,
   son filtrage par `MarkdownFeature`.
3. `OneToOne/Markdown/Slash/SlashController.swift` — détection du `/`, clavier,
   application. Note les six pièges déjà traités (annulation du debounce,
   effacement de la requête, `typingAttributes` hérités via
   `stripRiskyTypingAttributes`, sortie de titre au Retour, amorçage via
   `primeTypingAttributes`).
4. `OneToOne/Markdown/Slash/SlashPanel.swift` — le panneau (`NSPanel` non activant +
   `NSHostingView`), ses métriques.
5. `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift` — `BlockType`, `ListInfo`,
   `TableCellInfo`, et **toutes** les clés `md*`.
6. `OneToOne/Markdown/Markdown/MarkdownParser.swift` +
   `MarkdownSerializer.swift` — c'est le contrat de round-trip. **Aucune commande ne
   doit produire une représentation qui ne survit pas à
   `serialize` → `parse` → `serialize`.**
7. `Tests/SlashCatalogTests.swift`, `Tests/SlashControllerTests.swift`,
   `Tests/EditorRepresentableSlashWiringTests.swift` — le style de test attendu.

#### Règles non négociables

- **Round-trip d'abord** : pour chaque nouvelle commande, écris le test de round-trip
  markdown **avant** l'implémentation. Une commande dont le contenu est altéré par un
  aller-retour est un bug bloquant, pas un détail.
- **Commentaires et libellés UI en français, symboles et code en anglais**
  (convention du projet).
- **Pas de code AppFlowy** : AppFlowy est AGPL. Seule la structure de conception est
  réutilisée, comme déjà noté en tête de `SlashCommand.swift`. Ne copie ni chaîne, ni
  fonction, ni icône.
- **`swift build` + `swift test` verts** après chaque lot. Ne passe pas au lot suivant
  avec un test rouge.
- **Un commit par lot**, message en français, préfixe `feat(editeur):` ou
  `fix(markdown):` selon le cas — cohérent avec l'historique.
- Chaque nouvelle entrée du catalogue vient avec : sa `Key`, son icône SF Symbols dans
  `SlashCommand.Key.slashPanelIcon`, ses mots-clés **français**, ses alias
  **anglais/markdown**, son groupe, et son test de filtrage dans `SlashCatalogTests`.

---

#### Lot 0 — Rendre le panneau extensible (PRÉREQUIS BLOQUANT)

**Problème** : `SlashPanelMetrics.idealSize(for:)` (`SlashPanel.swift:318`) calcule une
hauteur strictement proportionnelle au nombre de lignes, et `SlashPanelContent` est un
`VStack` sans `ScrollView`. En passant de 11 à ~20 entrées, le panneau dépassera l'écran.

**À faire** :
1. Plafonner la hauteur (`SlashPanelMetrics.maxHeight`, ~320 pt ≈ 12 lignes) ;
   au-delà, envelopper le contenu dans un `ScrollView`.
2. Faire défiler automatiquement jusqu'à l'entrée sélectionnée quand la navigation
   clavier (`SlashController.moveSelection(by:)`) sort du champ visible —
   `ScrollViewReader` + `scrollTo(_:anchor:)` sur l'`id` de la commande.
3. Vérifier que `SlashPanelPositioning` (bascule au-dessus du curseur quand le bas de
   l'écran est trop proche) tient toujours avec la hauteur plafonnée.

**Tests** : `SlashPanelMetrics.idealSize` ne dépasse jamais `maxHeight` ; en dessous du
plafond, la hauteur reste exactement celle d'aujourd'hui (non-régression).

---

#### Lot 1 — Titres 4, 5, 6 (coût XS)

Tout existe déjà : `BlockType.h4/h5/h6`, `MarkdownBlockCommands.LineBlockType.h4/h5/h6`,
`MarkdownFeature.heading(.h4…)`. Il ne manque que les entrées de catalogue.

Ajoute `SlashCommand.Key.heading4/5/6`, trois entrées dans `SlashCatalog.all` juste après
`Titre 3`, groupe `.basicBlocks`, raccourcis `####` / `#####` / `######`,
`requiredFeature: .heading(.h4)` etc.

**Test** : avec `Set<MarkdownFeature>.prep` (qui ne contient que h2/h3), `/h4` ne
retourne rien ; avec `.full`, il retourne l'entrée « Titre 4 ».

---

#### Lot 2 — Bloc de code (coût S, priorité la plus haute)

`BlockType.codeBlock` et `.mdCodeLanguage` existent ; `MarkdownSerializer.fencedCodeBlock`
sait déjà sérialiser (et gère la longueur de fence via `fenceLength(for:)`).
`MarkdownBlockCommands.LineBlockType` **ne contient pas** `codeBlock`, et `setBlockType`
refuse explicitement de convertir une ligne déjà dans un bloc de code.

**Décision d'architecture attendue** : traiter `/code` comme une **insertion**
(`Action.insertCodeBlock`), sur le modèle exact de `insertThematicBreak` /
`insertTable` — **pas** comme une conversion. Justifie ce choix en doc-comment,
comme le fait déjà `SlashCommand.Action`.

**À faire** :
1. `SlashCommand.Key.codeBlock`, `Action.insertCodeBlock`, entrée de catalogue
   (groupe `.basicBlocks`, raccourci ` ``` `, mots-clés `code`, `bloc de code`,
   `programme` ; alias `code`, `codeblock`, `snippet` ;
   `requiredFeature: .codeBlock`).
2. `SlashController.insertCodeBlock(at:in:)` : `stripRiskyTypingAttributes`, puis
   insertion d'un `\n` nu + une ligne portant `.mdBlockType = .codeBlock`, curseur
   placé à l'intérieur, `typingAttributes[.mdBlockType] = .codeBlock` reposé après
   `setSelectedRange` (même piège que dans `insertTable`, cf. son commentaire).
3. Langage : à l'insertion, pas de `.mdCodeLanguage` (fence nue). Si la requête
   tapée après le `/` correspond à un langage connu (`/code swift`), pose
   `.mdCodeLanguage`. Optionnel — implémente-le seulement si le reste est vert.

**Tests** : insertion sur ligne vide / ligne non vide / dans une cellule de tableau
(doit être refusée ou insérée hors tableau — décide et documente) ; round-trip
` ```\ncode\n``` ` ; le texte tapé après insertion reste dans le bloc.

---

#### Lot 3 — Emoji (coût XS)

`SlashCommand.Key.emoji`, `Action.insertEmoji`, groupe `.insertions`.
Implémentation : `NSApp.orderFrontCharacterPalette(nil)` après avoir effacé la requête
et replacé le curseur — le palette natif macOS insère directement dans le premier
répondeur. Vérifie que `EditorTextView` est bien premier répondeur au moment de l'appel.

**Piège** : `stripRiskyTypingAttributes` avant, sinon un emoji inséré après du code
inline hérite de `.mdInlineCode`.

**Test** : injection d'un présentateur de palette factice (même schéma d'injection que
`presentImagePicker` / `presentDatePicker`), vérification que le caractère rendu ne
porte aucune clé `md*`.

---

#### Lot 4 — Callout (coût M)

**Représentation retenue** : une citation GFM dont le premier caractère du contenu est
un emoji — `> 💡 Texte de l'encadré`. Round-trip acquis gratuitement : à la relecture
c'est un `blockquote` ordinaire, le contenu est intact.

**À faire** :
1. `Key.callout`, `Action.insertCallout`, groupe `.basicBlocks`, mots-clés
   `encadré`, `callout`, `note`, `avertissement` ; alias `callout`, `note`, `info` ;
   `requiredFeature: .blockquote`.
2. Insertion : conversion en `blockquote` (réutilise `applyBlockConversion`) **puis**
   insertion de l'emoji par défaut `💡` suivi d'une espace, curseur après.
3. Rendu : facultatif, mais si tu ajoutes un fond coloré au callout dans
   `StyleRenderer`, il doit être **purement dérivé** de « blockquote dont le contenu
   commence par un emoji » — aucun attribut `md*` nouveau, sinon le round-trip casse.

**Tests** : round-trip `> 💡 Attention` ; conversion depuis une ligne non vide ;
depuis une ligne vide (voir le cas `range.length == 0` traité par `applyBlockConversion`).

---

#### Lot 5 — Rappel, en extension de « Date » (coût M)

La spec existe : `docs/superpowers/specs/2026-08-05-dates-et-rappels.md`. Lis-la.
`SlashDateSelection.reminder` est **déjà capturé par le popover et ignoré** par
`SlashController.insertDate` (cf. son doc-comment). Ce lot ferme cette boucle.

**À faire** : le chantier 1 de la spec (représentation du rappel dans le texte) puis
le chantier 3 (planification effective). Renomme l'entrée en « Date ou rappel » si la
spec le prévoit ; sinon, ajoute une entrée distincte.

---

#### Lot 6 — Fichier joint (coût M)

`MediaStore` ne sait aujourd'hui que `saveClipboardImage()`.

**À faire** :
1. Généraliser `MediaStore` : `saveFile(from: URL) -> URL?`, qui copie un fichier
   quelconque dans le stockage média et renvoie son URL locale. Ne casse pas
   `saveClipboardImage` ni `markdownReference(for:alt:)`.
2. `Key.file`, `Action.insertFile`, groupe `.media`. Sélecteur : `NSOpenPanel` sans
   `allowedContentTypes` (même style que `presentImageOpenPanel`, injectable pour les
   tests).
3. Insertion d'un **lien markdown** `[nom-du-fichier.pdf](<url>)` — pas un placeholder
   image. Le nom du fichier doit passer par `MarkdownEscaping` : un fichier nommé
   `rapport [v2].pdf` casserait la syntaxe de lien sinon. **Écris le test avec ce nom
   exact.**

**Tests** : round-trip du lien ; nom de fichier contenant `[`, `]`, `(`, `)` ; annulation
du sélecteur (ne doit rien insérer).

---

#### Lot 7 — Sommaire statique (coût M)

**À faire** : `Key.outline`, `Action.insertOutline`, groupe `.insertions`. À
l'insertion, parcourir le `NSTextStorage` courant, collecter toutes les lignes dont
`.mdBlockType` est un titre, et insérer une liste à puces imbriquée (`ListInfo.level`
= niveau de titre − niveau minimal rencontré) reprenant leur texte.

**Explicitement statique** : le sommaire n'est pas recalculé ensuite. Documente-le en
doc-comment pour qu'on ne prenne pas ça pour un bug. Un sommaire vivant demanderait un
bloc recalculé à chaque frappe — hors périmètre, ne le fais pas.

**Cas limite** : document sans aucun titre → n'insère rien, ferme simplement le menu.

---

#### Lot 8 — Lien vers une entité OneToOne (coût L)

**C'est la transposition OneToOne des items « base de données » d'AppFlowy**
(`Grid` / `Kanban` / `Calendar` / `Link to page` / `Document`) : là où AppFlowy
référence des bases génériques, OneToOne référence ses modèles SwiftData typés.

**À faire** :
1. Trois entrées — « Projet », « Personne », « Entretien » — dans un **nouveau groupe**
   `SlashCommand.Group.entities` (titre : « Éléments OneToOne »), placé après
   `.insertions`.
2. Un sélecteur de recherche (popover, sur le modèle de `SlashDatePickerPresenter` —
   `NSPopover` + contenu SwiftUI, injectable pour les tests) qui liste les entités du
   type demandé et filtre à la frappe.
3. Insertion d'un lien markdown `[Nom de l'entité](onetoone://project/<uuid>)`.
   Le schéma `onetoone://` est **déjà** enregistré (`MickeyIntegration.swift:47`,
   route `session-done`) : **vérifie où les URL entrantes sont traitées et ajoute les
   routes `project` / `person` / `meeting` au même endroit**, pour qu'un clic ouvre
   réellement la fiche. Un lien qui ne mène nulle part n'est pas livrable.
4. Le nom de l'entité passe par `MarkdownEscaping` (même raison qu'au lot 6).

**Contrainte d'accès aux données** : `SlashController` n'a aujourd'hui **aucune**
dépendance SwiftData, et ne doit pas en gagner une en dur. Injecte un fournisseur
(`(EntityKind, String) -> [EntitySuggestion]`) au même titre que `presentImagePicker` /
`presentDatePicker`, résolu par l'appelant dans `EditorRepresentable`.

**Tests** : filtrage du fournisseur (avec un fournisseur factice, sans `ModelContainer`) ;
échappement du nom ; round-trip du lien ; annulation du popover.

---

#### Lots hors périmètre — ne les fais pas sans arbitrage explicite

- **Listes et titres dépliables** (`toggle`) : `<details>` en `rawBlock` serait affiché
  en texte brut, sans repli — valeur d'usage nulle. Exige un vrai bloc pliable dans
  `MarkdownLayoutManager`.
- **Équation mathématique** : `$$…$$` en `rawBlock`, sans rendu.
- **Colonnes 2/3/4**, **Galerie photo**, **Grid/Kanban/Calendar**, **Sous-page** : aucun
  équivalent markdown, ou remplacés par le lot 8.
- **IA (`Ask AI` / `Continue writing`)** : le socle existe (`DirectLLMClient`, provider
  `.direct` par défaut), mais les entrées IA ont été mises **hors périmètre par décision
  utilisateur du 2026-08-04** (cf. en-tête de `SlashCatalog.swift`). **Demande une
  décision explicite avant d'écrire la moindre ligne.**

---

#### Ordre d'exécution imposé

`Lot 0` (bloquant) → `1` → `2` → `3` → `4` → `5` → `6` → `7` → `8`.

Après chaque lot : `swift build && swift test`, puis commit. À la fin, mets à jour le
doc-comment d'en-tête de `SlashCatalog.swift` (qui liste aujourd'hui ce qui est hors
périmètre) pour refléter le nouvel état, et signale tout lot que tu n'as pas pu terminer
avec la raison précise.
