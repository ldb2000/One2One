# Éditeur markdown — écart avec AppFlowy et cap de travail

Date : 2026-08-06
Branche : `feat/editeur-slash-blocs`
Statut : **spec de référence**. Remplace les parties périmées de
[`2026-08-03-editeur-slash-blocs-design.md`](2026-08-03-editeur-slash-blocs-design.md)
(annoté, conservé).

Spec sœur : [`2026-08-06-poignee-de-bloc-et-deplacement.md`](2026-08-06-poignee-de-bloc-et-deplacement.md)
— la conception détaillée du seul point que l'utilisateur a écrit noir sur blanc dans
`CLAUDE.md` (« des paragraphes qu'on peut bouger »).

---

## 0. Pourquoi ce document

`CLAUDE.md` porte depuis peu cette ligne, de la main de l'utilisateur :

> on s'inspire de https://github.com/AppFlowy-IO/AppFlowy pour l'editeur. Commande
> avec des /, avec des parapgraphe qu'on peut bouger et rajouter des bloque.

Trois demandes, donc : le menu `/` (**livré**), des **blocs qu'on peut ajouter**
(livré en partie), et des **paragraphes qu'on peut bouger** (rien n'existe).
51 commits ont été poussés sur cette branche sans qu'aucun ne touche au troisième
point. Ce document fait l'état des lieux, mesure l'écart avec AppFlowy, chiffre
l'effort de chaque rapprochement, et donne un ordre de travail.

**Aucun code d'AppFlowy n'est repris.** Les dépôts `AppFlowy` et
`appflowy-editor` sont sous AGPL-3.0, incompatible avec cette app. Ce qui est
repris est de la *conception* — quelles commandes existent, comment un bloc se
manipule — et non des chaînes, des fonctions ou des icônes. Position déjà posée
en tête de `SlashCommand.swift` et de la spec du 2026-08-03.

---

## 1. Sources et niveau de preuve

Trois niveaux, tenus distincts dans tout le document :

| Marque | Sens |
|---|---|
| **mesuré** | exécuté et observé (par cette session ou une session antérieure qui l'a consigné dans le code) |
| **lu** | établi par lecture du code source, sans exécution |
| **supposé** | déduction non vérifiée — signalée comme telle, jamais présentée comme un fait |

Côté AppFlowy, les sources sont les **listings de répertoires de l'API GitHub**
(des noms de fichiers, donc des faits, pas du code), la documentation publique
(`docs.appflowy.io`), le `README`/`CHANGELOG` d'`appflowy-editor` et le `README`
d'`AppFlowy-Collab`. Ce qui ne vient pas de là est marqué *supposé*.

---

## 2. Ce qui est déjà livré — **ne pas le refaire**

Tout ce tableau est **lu** sur `feat/editeur-slash-blocs` à `b7f3c59`.

| Domaine | Livré | Où |
|---|---|---|
| Menu `/` | déclenchement en début de ligne/après espace, panneau `NSPanel` non-activant positionné sous le curseur, filtrage à la frappe insensible casse/accents, navigation ↑↓/⏎/Tab/Échap, effacement de la requête, annulation du debounce | `Slash/SlashController.swift`, `SlashPanel.swift` |
| Catalogue `/` | **12 entrées** : Texte, Titre 1, Titre 2, Titre 3, Liste à puces, Liste numérotée, Case à cocher, Citation, Séparateur, Tableau, Image, Date | `Slash/SlashCatalog.swift` |
| Commandes de bloc | conversion par **mutation d'attributs** (`.mdBlockType`, `.mdListInfo`), jamais par réécriture de marqueurs littéraux | `Core/MarkdownBlockCommands.swift` |
| Rendu listes | puce, numéro, case à cocher **dessinés** par une sous-classe de `NSLayoutManager` ; indentation par niveau ; colonne élargie pour les ordinaux à 2-3 chiffres | `Core/MarkdownLayoutManager.swift`, `ListMarkerLayout.swift` |
| Cases à cocher | cliquables, zone restreinte à la marge du marqueur, `undo`/`redo` symétriques, écriture immédiate (non débouncée) | `Core/EditorTextView.swift` |
| Citations | filet vertical peint sur chaque ligne visuelle du bloc | `MarkdownLayoutManager`, `BlockquoteRuleLayout` |
| Images | affichées inline via `NSTextAttachment` + cache, collage presse-papiers, insertion par `/image`, placeholder attribué (jamais de markdown littéral dans le storage) | `Blocks/ImageAttachmentFactory.swift`, `Model/ImagePlaceholder.swift`, `Media/MediaStore.swift` |
| Tableaux GFM | vraie grille `NSTextTable`/`NSTextTableBlock`, en-tête en gras, alignement par colonne, bordures continues ; insertion d'un squelette 3×3 par `/tableau` | `StyleRenderer`, `TableLayout`, `SlashController.insertTable` |
| Mentions `@` | panneau, recherche, création d'un collaborateur inconnu, insertion en lien `onetoone://collaborator/<uuid>` | `Mention/` |
| Date | popover `NSPopover` ancré au curseur : champ texte, calendrier graphique, bascule « Inclure l'heure », menu « Rappel » | `Slash/SlashDatePickerPresenter.swift` |
| Aller-retour markdown | frontières de bloc (**8 paires** à ligne vide), blocs fencés d'un seul tenant, tableaux GFM et blocs HTML préservés, destination des images conservée, échappement inline structurel | `Markdown/MarkdownSerializer.swift`, `MarkdownParser.swift` |
| Tests | 21 `SlashCatalogTests`, 57 `SlashControllerTests`, 6 `SlashPanelPositioningTests`, 13 `MentionCatalogTests`, 38 `MentionControllerTests`, 26 `StyleRendererTests`, 5 `MarkdownTableRenderingTests`, 8 fixtures d'aller-retour | `Tests/` |

### 2 bis. Trois défauts livrés avec, à corriger avant d'ajouter quoi que ce soit

Ces trois-là ne sont pas des manques par rapport à AppFlowy : ce sont des
incohérences internes du code livré. **Lus**, pas supposés.

1. **Deux entrées du menu `/` sur douze ne sont jamais visibles.**
   `MarkdownNoteEditor` et `EditableTextField` — les **seuls** hôtes de l'éditeur
   dans l'app — appellent tous deux `.markdownFeatures(.prep)`. Or `.prep` ne
   contient ni `.heading(.h1)` ni `.thematicBreak`. « Titre 1 » et « Séparateur »
   sont donc filtrés par `SlashCatalog.available(for:)` **partout**, alors que
   `SlashController.insertThematicBreak` a été écrit, testé et documenté avec
   soin. `.full`, qui les débloquerait, n'a aucun appelant.

2. **Le popover de date fait choisir un rappel qui est jeté.**
   `SlashController.insertDate` insère du texte brut et ignore
   `selection.reminder` — son propre doc-comment l'admet. L'utilisateur choisit
   « La veille », valide, et rien n'en subsiste : ni dans le texte, ni ailleurs.
   Voir l'annotation portée sur
   [`2026-08-05-dates-et-rappels.md`](2026-08-05-dates-et-rappels.md).

3. **Une mention ne mène nulle part.** Le format
   `[@Nom](onetoone://collaborator/<uuid>)` a été choisi pour être résolvable
   (raison n°3 de sa spec), mais `EditorTextView.mouseDown` ne traite que les
   cases à cocher, aucun attribut `.link` natif n'est posé, et
   `MickeyIntegration.handleCallback` rejette tout hôte autre que `session-done`.
   Le lien est inerte des deux côtés.

Un quatrième point, **lu mais non mesuré** : `MarkdownParser.emitInlineNode` n'a
pas de cas `InlineHTML`. Un nœud de ce type n'ayant pas d'enfants, la branche
`default` (« descendre dans les enfants ») ne produirait rien — un `<br>` ou un
`<span>` inline serait donc **silencieusement effacé** à l'aller-retour.
`MarkdownToHTMLRenderer`, lui, traite bien `InlineHTML`. À mesurer avant de
conclure ; si c'est confirmé, c'est une perte de données du même genre que celles
déjà corrigées sur cette branche.

---

## 3. Inventaire de l'éditeur d'AppFlowy

### 3.1 Deux périmètres qu'il ne faut pas confondre

AppFlowy sépare deux choses, et c'est structurant pour lire la suite :

- **`appflowy-editor`** — le paquet Flutter réutilisable. Ses blocs intégrés
  sont peu nombreux (**vérifié** sur le listing de
  `lib/src/editor/block_component`) : `paragraph`, `heading`, `bulleted_list`,
  `numbered_list`, `todo_list`, `quote`, `divider`, `image`, `table`,
  plus `rich_text` et un `base_component`. **C'est à peu près exactement le
  périmètre que OneToOne couvre déjà.**
- **`AppFlowy`** — l'application, qui empile par-dessus une trentaine de
  greffons (**vérifié** sur le listing de
  `.../presentation/editor_plugins`) : `callout`, `code_block`, `columns`,
  `simple_table`, `toggle`, `sub_page`, `math_equation`,
  `inline_math_equation`, `mention`, `outline`, `file`, `video`, `cover`,
  `header`, `page_style`, `link_preview`, `link_embed`, `background_color`,
  `font`, `align_toolbar_item`, `find_and_replace`, `undo_redo`,
  `desktop_toolbar`, `mobile_floating_toolbar`, `context_menu`,
  `copy_and_paste`, `keyboard_interceptor`, `block_menu`, `actions`,
  `database`, `ai`, `parsers`, `migration`…

Autrement dit : **le retard de OneToOne n'est pas sur le socle de blocs, il est
sur la couche d'interaction et sur les blocs composites.**

### 3.2 Le menu `/`

**Vérifié** : le répertoire `slash_menu/slash_menu_items` contient un fichier par
famille d'entrée — `paragraph_item`, `heading_items`, `bulleted_list_item`,
`numbered_list_item`, `todo_list_item`, `quote_item`, `divider_item`,
`image_item`, `simple_table_item`, `code_block_item`, `callout_item`,
`date_item`, `emoji_item`, `file_item`, `photo_gallery_item`,
`math_equation_item`, `outline_item`, `toggle_list_item`,
`simple_columns_item`, `sub_page_item`, `database_items`, `ai_writer_item`,
`mobile_items`, plus `slash_menu_item_builder` et `slash_menu_items`.

**Deux constats de conception, vérifiés, qui contredisent une intuition
raisonnable :**

1. **Sur desktop, le menu `/` d'AppFlowy est une liste _plate_, sans en-têtes de
   groupe.** Les catégories (*Text Style*, *List*, *Toggle*, *File & Media*,
   *Visuals*, *Advanced*) n'existent que dans le menu **mobile**, à deux niveaux.
   Sur desktop, seul l'**ordre** porte le sens. OneToOne, lui, affiche déjà trois
   en-têtes de groupe (« Blocs de base », « Média », « Insertions ») — ce n'est
   donc pas un retard, c'est un choix différent, et plutôt meilleur à 12 entrées.
   **À conserver.**
2. **Le menu `/` est contextuel.** Une seconde liste, réduite, s'applique quand
   le curseur est **dans une cellule de tableau** : elle exclut l'IA, les bases
   de données, les colonnes, le tableau lui-même, le sommaire et la galerie.
   Idée directement transposable : `SlashCatalog.available(for:)` filtre
   aujourd'hui par `MarkdownFeature` mais **jamais par contexte de bloc**.
   Proposer « Tableau » à l'intérieur d'une cellule de tableau est un piège
   ouvert dans le code actuel.

Comparaison entrée par entrée :

| Entrée AppFlowy | OneToOne |
|---|---|
| Text, Heading 1-3 | ✅ |
| Bulleted / Numbered / To-do list | ✅ |
| Quote, Divider | ✅ (Séparateur invisible en `.prep`, cf. §2 bis) |
| Image | ✅ |
| Table (`simple_table`) | ✅ (insertion 3×3, sans opérations sur lignes/colonnes) |
| Date or Reminder | 🟡 date insérée en **texte brut**, rappel jeté |
| Emoji | ❌ |
| Code | ❌ (`BlockType.codeBlock` existe, aucune entrée) |
| Callout | ❌ |
| Outline / sommaire | ❌ |
| File (pièce jointe) | ❌ |
| Math equation | ❌ |
| Toggle list, Toggle heading 1-3 | ❌ |
| 2 / 3 / 4 Columns | ❌ |
| Photo gallery | ❌ |
| Sub-page (document imbriqué) | ❌ |
| Link to page | ❌ (transposable en lien vers une entité OneToOne) |
| Grid / Kanban / Calendar + versions liées | ❌ (bases de données génériques) |
| Ask AI, Continue writing | ❌ (hors périmètre par décision du 2026-08-04) |

### 3.3 Les interactions de bloc — c'est là qu'est le gros de l'écart

**La poignée de bloc**, tout **vérifié** (`actions/`, énum `OptionAction`,
libellés depuis `en-US.json`). Deux boutons apparaissent **à gauche du bloc
survolé** :

- **« + »** — infobulle « *Click to add below* », et « *Alt+click to add above* ».
  Deux gestes sur un seul bouton, sans second contrôle.
- **« ⋮⋮ »** — infobulle « *Drag to move* » + « *Click to open menu* ». Le même
  bouton est la poignée de glisser **et** l'ouverture du menu.

**Le menu de la poignée** — actions vérifiées :
`delete`, `duplicate`, `turnInto` (sous-menu), `moveUp`, `moveDown`,
`copyLinkToBlock`, `color` (fond du bloc), `align` (gauche/centre/droite),
`depth` (spécifique au bloc *outline*), `setToPageWidth` et
`distributeColumnsEvenly` (spécifiques à *simple_table*).

Le point de conception le plus utile, **vérifié dans un commentaire du code** :
*« different block type may have different option actions. All the block types
have the delete and duplicate options »*. **Le menu est calculé par type de
bloc.** Seuls *Supprimer* et *Dupliquer* sont universels ; le reste est
contribué par le type. `copyLinkToBlock` est masqué en mode local, et le bouton
d'options est désactivé dans les cellules de tableau pour ne pas casser
l'alignement.

**Le glisser-déposer** : `actions/drag_to_reorder/` contient
`draggable_option_button`, `draggable_option_button_feedback` (l'aperçu fantôme
suivant le curseur) et `visual_drag_area` (la zone d'insertion visualisée). Le
`CHANGELOG` ajoute l'**auto-défilement** pendant le glisser. Le drag est
**désactivé dans certains contextes** — commentaire vérifié : pendant le
redimensionnement d'un bloc de colonnes, par exemple.

**Le déplacement de _plusieurs_ blocs à la fois n'est arrivé qu'en v0.13.0, le
2026-07-24** (« *Select and drag multiple blocks together to move them to another
location* »). C'est un signal à prendre au sérieux : une équipe à temps plein sur
un modèle de blocs natif a mis des années à le livrer. Le déplacement d'**un**
bloc, lui, est ancien.

**La barre d'outils flottante sur sélection** — énum `ToolbarId` vérifiée, dans
l'ordre : `bold`, `underline`, `italic`, `code`, `highlightColor`, `textColor`,
`link`, `textAlign`, `moreOption`, `textHeading`, `suggestions`. Le sous-menu
« **Turn into** » y est groupé (`textHeading`, `list`, `toggle`, `quote`,
`page`) et vise Text, H1-H3, Checkbox, Bulleted, Numbered, Toggle, Toggle H1-H3,
Callout, Quote, Page. Le champ lien porte le placeholder « *Paste link or search
pages* » : **la saisie d'un lien et la recherche d'une page interne sont un seul
et même champ.** C'est exactement ce que OneToOne devrait faire de son
`onetoone://`.

**Les raccourcis markdown à la frappe** — liste vérifiée :

| Déclencheur | Résultat |
|---|---|
| `*` ou `-` + espace | liste à puces |
| `1.` + espace | liste numérotée |
| `#`×N + espace | titre niveau N |
| `[]` / `-[]` / `[x]` / `-[x]` | case à cocher, décochée ou cochée |
| `---`, `***`, `___` | séparateur |
| ` ``` ` | bloc de code |
| `"` + espace | **citation** |
| `>` + espace | **liste dépliable** (toggle) |
| `` `code` ``, `_i_`, `*i*`, `**g**`, `__g__`, `~b~`, `~~b~~` | marques inline |
| `[texte](url)` | lien |
| `--`, `=>`, `->` | tiret cadratin, flèches |

Deux détails valent d'être relevés. D'abord, **AppFlowy a réaffecté `>` au
toggle et déplacé la citation sur `"`** — un choix contestable qui prend le
contre-pied de tout le monde ; **ne pas le copier**, `>` doit rester la citation
dans OneToOne, qui n'a pas de toggle. Ensuite, le noyau expose une liste de
raccourcis **filtrable et surchargeable**, et l'app en retire plusieurs pour les
remplacer par les siens : le bon patron est une table de règles, pas une
cascade de `if` — ce que `ShortcutDetector` est aujourd'hui.

**Autres déclencheurs de caractère**, vérifiés : `/` menu de blocs, `@` menu
d'insertion inline, `[[` **et** `+` sélecteur de page, `:` sélecteur d'emoji.

**Le collage** — ordre de résolution vérifié, et instructif :

1. lien de partage AppFlowy → mention de page ;
2. URL seule → carte d'aperçu, mais **seulement** si la sélection est repliée,
   en début de ligne, et le paragraphe vide ; sinon simple lien inline ;
3. JSON interne AppFlowy → fidélité totale entre documents ;
4. **image, testée _avant_ le HTML** — raison documentée dans le code : l'URL
   d'image contenue dans le HTML n'est souvent pas joignable (exemple donné :
   coller depuis Slack). OneToOne fait déjà exactement ça
   (`EditorTextView.paste` teste `MediaStore.clipboardHasImage` avant de
   déléguer) — **sans le savoir, le bon choix est déjà pris** ;
5. HTML ;
6. texte brut.

Le menu contextuel offre « **Paste as plain text** », et une URL collée peut
être reconvertie a posteriori en Mention / URL / Bookmark / Embed.

**Le menu `@`** : quatre types mentionnables — `page`, `date`, `externalLink`,
`childPage` — avec « Recent pages », des références typées (Document, Board,
Calendar, Grid), un groupe **Reminder**, et **« Create "…" sub-page »**. La
mention de date porte `include_time`, `reminder_id` et `reminder_option`.
OneToOne ne mentionne que des collaborateurs ; la date est une insertion
séparée, en texte brut.

**Le repli (toggle)** : un seul type de bloc, `toggle_list`, avec un attribut
`level` **optionnel**. Absent → toggle simple ; valant 1-3 → *titre repliable*.
Le bloc `outline` indexe les `heading` **et** les `toggle_list` porteurs d'un
`level`. Une seule mécanique, quatre entrées de menu, intégration transparente au
sommaire — c'est la plus élégante des idées de conception relevées.

**Le sommaire** (`outline`) est un **bloc vivant**, pas une liste figée : il
collecte les titres à la volée, avec un attribut `depth` réglable depuis le menu
de la poignée (max 6), et affiche « *Add headings to create a table of
contents.* » quand il n'y en a aucun.

**Un patron de robustesse à retenir** : AppFlowy enregistre un **bloc d'erreur**
qui prend le relais quand un type de nœud est inconnu du client. C'est
exactement la fonction de `BlockType.rawBlock` dans OneToOne — même idée, déjà
en place, et il faut la garder.

Autres greffons **vérifiés** par nom : `cover` et `header` (couverture et icône
de page, titre du document éditable dans l'en-tête avec ses propres raccourcis),
`find_and_replace`, `undo_redo`, `keyboard_interceptor`,
`block_transaction_handler`, `word_count`, `page_style`, `link_embed`.

**Non vérifié, à ne pas supposer** : un historique de versions. Undo/redo est un
historique de **transactions en mémoire** dans `EditorState`. La couche CRDT
fournit techniquement un journal, mais aucune fonctionnalité d'interface
correspondante n'a été trouvée.

### 3.4 Les tableaux

Deux modèles coexistent, **vérifié** : l'ancien `table`/`table/cell` du paquet
(grille plate, cellules positionnées par `rowPosition`/`colPosition`) et le
nouveau `simple_table` de l'app, **arbre à trois niveaux** table → rangée →
cellule. Les deux sont encore enregistrés ; c'est le nouveau qu'expose le menu
`/`. Le passage d'une grille plate indexée à un vrai arbre est ce qui rend les
lignes réordonnables.

Capacités de `simple_table`, **vérifiées** (énum `SimpleTableMoreAction`) :
insérer à gauche / à droite / au-dessus / en dessous ; dupliquer la
ligne / la colonne / le tableau ; supprimer ; **effacer le contenu** ;
**réordonner** lignes et colonnes ; aligner ; couleur de fond de cellule **et**
couleur de texte, séparément ; **ligne d'en-tête ET colonne d'en-tête**,
activables indépendamment ; « Set to page width » ; « Distribute columns
evenly » ; couper/copier/coller ; « Copy link to block ». Le menu contextuel est
**différencié ligne contre colonne**. Au survol, des affordances ajoutent une
ligne, une colonne, ou les deux d'un coup depuis le coin bas-droit. Onze
fichiers de raccourcis clavier sont dédiés à la navigation dans les cellules
(flèches, Tab, Entrée, Retour arrière, Tout sélectionner).

**L'écart avec OneToOne est ici maximal** : la grille est acquise (C3), les
opérations n'existent pas du tout.

### 3.5 Le modèle de données — la différence de nature

**Vérifié** (`appflowy-editor/lib/src/core/document/`, `node.dart`, et
`docs.appflowy.io` « Demystifying AppFlowy Editor's Codebase ») :

- un `Document` est un **arbre de `Node`** de racine `page` ; chaque nœud porte
  un `type` (chaîne), un **`id` nanoid auto-généré**, un `parent`, des
  `children` en liste chaînée, des `attributes` (par ex. `checked` pour un
  `todo_list`, `level` pour un `heading`) et un `path` calculé ;
- le texte d'un nœud vit dans l'attribut **`delta`**, au format Quill Delta ;
- on ne mute jamais le document directement : on applique une **`Transaction`**,
  liste d'`Operation` — « *you must consider the implications of collaborative
  editing* » ;
- le format canonique est du **JSON** (`{"document": {"type": "page",
  "children": […]}}`) ; HTML, **Markdown**, Quill Delta et PDF sont des
  **greffons d'import/export**, pas la vérité.

**Vérifié** (`frontend/rust-lib/Cargo.toml`, `README` d'`AppFlowy-Collab`) : la
persistance et la synchronisation passent par un crate Rust `collab` bâti sur
**`yrs 0.21`** (portage Rust de Yjs), donc un **CRDT** ; `collab-document` y gère
« *block tree, text manipulation, markdown/plain text conversion* ». La pile
complète est : UI Flutter (arbre `Node`/`Delta`) ↔ FFI ↔ Rust `collab-document`
↔ Yrs.

**Nuance importante, vérifiée** : le CRDT est une couche **séparable**. Le paquet
`appflowy-editor` est publié sur pub.dev sans aucune dépendance Rust et
fonctionne sur son seul arbre `Document`/`Node`/`Delta`. Tout ce qui précède aux
§3.2 à §3.4 est donc **indépendant du CRDT** — l'absence de collaboration temps
réel dans OneToOne n'interdit rien de cet inventaire.

**L'export markdown d'AppFlowy est vérifiablement _lossy_**, et c'est le point le
plus éclairant de tout cet inventaire :

- le noyau ne compte que **10 encodeurs markdown** : `text`, `heading`,
  `bulleted_list`, `numbered_list`, `todo_list`, `quote`, `code_block`,
  `divider`, `image`, `table` ;
- plusieurs types de blocs n'ont **aucun** encodeur : `multi_image`, `video`,
  et surtout **`simple_columns`/`simple_column`** et **`outline`**. Les colonnes
  et le sommaire **ne survivent pas** à un aller-retour markdown ;
- la documentation d'import le dit : « *Some styles, such as font-size,
  font-family and text-align, are not supported yet.* » ;
- et le plus révélateur : **le copier-coller entre deux documents AppFlowy passe
  par un JSON interne, essayé en premier, pas par markdown**. C'est l'aveu de
  conception que markdown perd de l'information.

**Ce que ça dit pour OneToOne.** Le choix « markdown source de vérité » ne nous
prive pas d'un dixième de l'éditeur d'AppFlowy : il nous prive **exactement** de
ce dont AppFlowy lui-même ne sait pas faire de markdown — colonnes, galeries,
vidéo, sommaire vivant, couleurs, alignements. Ce n'est pas une coïncidence,
c'est la même frontière. Le corollaire est rassurant : **tout le reste de
l'inventaire est atteignable sans changer de format de stockage.**

**OneToOne fait l'inverse, et c'est un choix, pas un retard** : le markdown *est*
la source de vérité, le modèle en mémoire n'est qu'un `NSAttributedString` porteur
d'attributs `md*`, reconstruit à chaque chargement. Ce choix a été pris
explicitement (spec du 2026-08-03, « Non-objectifs ») parce que l'IA produit et
consomme du markdown, que les exports et les notes existantes doivent rester
intacts, et que l'app est locale et mono-utilisateur.

**La conséquence à ne jamais perdre de vue** : *un bloc de OneToOne n'a pas
d'identité*. AppFlowy donne un `id` stable à chaque nœud ; le markdown n'en donne
aucun. Tout ce qui, chez AppFlowy, s'ancre sur l'identité d'un bloc — copier le
lien vers un bloc, y attacher un commentaire, synchroniser un bloc, versionner un
bloc — n'a **pas** d'équivalent bon marché ici. En revanche, tout ce qui n'a
besoin que de la géométrie du bloc *pendant la session* — le survol, la poignée,
le déplacement — reste parfaitement atteignable.

---

## 4. Les contraintes qui fixent le coût

Toutes **mesurées**, soit par cette session, soit par une session antérieure qui
les a consignées dans le code.

| # | Contrainte | Conséquence |
|---|---|---|
| C1 | **TextKit 1**, pile montée à la main dans `EditorRepresentable.makeNSView` | pas de `NSTextAttachmentViewProvider` (vues vivantes inline), pas de `NSTextLayoutFragment` |
| C2 | **`NSTextList` ne peint rien** sur cette pile | toute décoration structurelle se dessine à la main dans `MarkdownLayoutManager` |
| C3 | **`NSTextTable` fonctionne** | la grille est acquise ; les colonnes, elles, n'ont **aucun modèle de largeur** — `StyleRenderer` n'appelle jamais `setWidth(_:type:for: .width)` (**lu**) |
| C4 | **`EditorTextView` ne gère que `mouseDown`** | aucun survol, aucun glisser-déposer, aucune `NSTrackingArea` — et **aucun `NSTrackingArea` ni `registerForDraggedTypes` nulle part dans l'app** (**lu**) |
| C5 | **Le storage ne contient jamais de marqueur markdown** | toute décoration qui y entrerait fuirait dans le fichier ; quatre bugs distincts en sont venus |
| C6 | **`insertText` fusionne les `typingAttributes`** | toute insertion doit purger les clés `md*` à risque (`stripRiskyTypingAttributes`) |
| C7 | **Le markdown est la source de vérité** | toute nouvelle construction doit survivre à `serialize → parse → serialize` |
| C8 | **Le panneau `/` n'a ni plafond de hauteur ni défilement** (**lu** : `SlashPanelMetrics.idealSize` est strictement proportionnel, `SlashPanelContent` est un `VStack` nu) | au-delà de ~15 entrées il déborde de l'écran et la navigation clavier sort du champ visible |
| C9 | **Le module ne connaît pas SwiftData** et ne doit pas le connaître | tout accès aux données passe par une closure injectée depuis `EditorRepresentable` |

---

## 5. Classement par effort

### Court — entrée au catalogue plus insertion, sur le patron existant

Le patron est établi : une `Key`, une entrée dans `SlashCatalog.all`, une icône
dans `slashPanelIcon`, un cas d'`Action`, une méthode d'insertion dans
`SlashController` bâtie sur `insertThematicBreak`/`insertTable`, un test de
filtrage et un test d'aller-retour.

| Élément | Ce qu'il faut | Contraintes |
|---|---|---|
| **Rendre visibles Titre 1 et Séparateur** | étendre `.prep` (ou basculer les hôtes sur un jeu dédié) | aucune — c'est un `Set` |
| **Titres 4, 5, 6** | 3 entrées. `BlockType.h4/5/6`, `LineBlockType.h4/5/6`, `MarkdownFeature.heading(.h4…)` **existent déjà** (**lu**) | C7 acquis |
| **Bloc de code** | `Action.insertCodeBlock`, sur le patron d'`insertThematicBreak` — **une insertion, pas une conversion** : `LineBlockType` exclut délibérément `.codeBlock` parce que `fencedCodeBlock` réémet le texte brut et perdrait l'inline de la ligne convertie (**mesuré**, cf. doc de `MarkdownBlockCommands`) | C6, C7 ; `.codeBlock` absent de `.prep` |
| **Callout** | `> 💡 Texte` — un `blockquote` dont le contenu commence par un emoji. L'aller-retour est gratuit : au reparse c'est une citation ordinaire | C5 (le fond coloré éventuel doit être **dérivé**, jamais un nouvel attribut persisté) |
| **Emoji** | `NSApp.orderFrontCharacterPalette(nil)`, injecté comme `presentImagePicker` | C6 ; vérifier que l'`EditorTextView` est premier répondeur |
| **Fichier joint** | `MediaStore.saveFile(from:)` (~15 lignes, à côté de `saveClipboardImage`) + `NSOpenPanel` + insertion d'un **lien** `[nom.pdf](url)` | C7 : le nom doit passer par `MarkdownEscaping` — tester avec `rapport [v2].pdf` |
| **Sommaire statique** | parcourir le storage, collecter les lignes dont `.mdBlockType` est un titre, insérer une liste à puces. **Statique assumé** : le sommaire d'AppFlowy est un bloc **vivant** (greffon `outline` avec profondeur réglable), celui-ci ne se recalculera pas. Et c'est cohérent — l'`outline` d'AppFlowy n'a lui-même **aucun encodeur markdown** (§3.5) : il ne survit pas à leur propre export | C7 acquis (une liste de liens est une liste) |
| **Menu `/` contextuel** | `SlashCatalog.available(for:)` ne filtre que par `MarkdownFeature`. Y ajouter le **contexte de bloc** du curseur : ne pas proposer « Tableau » à l'intérieur d'une cellule de tableau, ni « Séparateur » dans un bloc de code. AppFlowy a une seconde liste réduite pour les cellules (§3.2) | le contexte est lisible sur le storage (`.mdTableCell`, `.mdBlockType`) — logique pure, testable |

### Moyen — interface ou logique de rendu à écrire

| Élément | Ce qu'il faut | Contraintes |
|---|---|---|
| **Panneau `/` défilant** *(prérequis)* | plafond de hauteur + `ScrollView` + défilement automatique vers l'entrée sélectionnée (`ScrollViewReader`) ; revérifier `SlashPanelPositioning` | **C8** — bloque tout ajout d'entrée au-delà de ~15 |
| **Raccourcis markdown à la frappe** | `ShortcutDetector` ne connaît aujourd'hui que `**`, `_` et `` ` `` (**lu**). Manquent `# `, `## `, `### `, `- `, `1. `, `> `, `[] `, `--- `, ` ``` `. C'est le **plus gros écart d'ergonomie** avec AppFlowy pour le coût le plus faible de cette colonne | C6, C7 ; réutiliser `MarkdownBlockCommands` (mutation d'attributs), jamais l'insertion de marqueurs littéraux |
| **Clavier des listes** | Tab/⇧Tab pour imbriquer/désimbriquer (`ListInfo.level` existe déjà), ⏎ sur un item vide pour sortir de la liste, ⌫ en tête d'item pour revenir au paragraphe. Aucun `doCommandBy` du module ne les traite (**lu**) | le hook existe déjà (`Coordinator.textView(_:doCommandBy:)`) |
| **Lien cliquable + routes `onetoone://`** | `mouseDown` détecte un `.mdLink`, remonte l'URL par closure hors module, et l'app route `collaborator` / `project` / `meeting`. `MickeyIntegration` ne route que `session-done` (**lu**) | C9 ; ferme le défaut n°3 du §2 bis |
| **Rendu distinct des liens internes** | `StyleRenderer` lit le **schéma** de l'URL et stylise différemment une mention, une date et un lien externe. Il applique aujourd'hui `linkColor` + soulignement à tout `.mdLink` (**lu**) | C5 : fond et couleur sont des attributs d'affichage, sûrs ; une **icône** devrait être *dessinée* par `MarkdownLayoutManager`, pas insérée — et rien ne garantit qu'une décoration inline se place proprement là où seules des décorations de marge ont été validées (**à mesurer**) |
| **Date structurée + rappel conservé** | chantier 1 de la spec dates : `[@5 août 2026](onetoone://date/2026-08-05?reminder=P1D)` | C7 ; ferme le défaut n°2 du §2 bis |
| **Barre d'outils flottante sur sélection** | l'équivalent du `desktop_toolbar` d'AppFlowy : un panneau sur le modèle exact de `SlashPanel` (non-activant, `canBecomeKey = false`), ancré sur le rectangle de la sélection. La barre actuelle (`MarkdownToolbar`) est un `HStack` fixe hors éditeur. Réduire la liste d'AppFlowy à ce que le format porte : gras, italique, barré, code inline, lien, **« Convertir en »** (le sous-menu `suggestions`) — pas de couleur de texte ni de surlignage, sans représentation markdown | C4 : il faut un rectangle de sélection — `firstRect(forCharacterRange:)` est **mesuré** pour le curseur, **à confirmer** pour une plage de plusieurs caractères |
| **Champ lien unifié** | AppFlowy n'a qu'un champ, « *Paste link or search pages* », qui accepte une URL **ou** une recherche de page interne (§3.3). Transposé : un seul champ qui accepte une URL externe ou cherche un projet / une personne / une réunion, et pose l'`onetoone://` correspondant | dépend du lot D1 (routage) |
| **Sélection multi-blocs** | `MarkdownBlockCommands` n'opère que sur la ligne du curseur (**lu**). L'étendre à toutes les lignes d'une sélection : conversion en masse, suppression, duplication | C7 ; la duplication d'un tableau doit régénérer les `tableID` |
| **Opérations sur les tableaux** | ajouter/supprimer/dupliquer/réordonner une ligne ou une colonne, changer l'alignement, effacer le contenu. Toutes les cellules d'une table portent `columnCount` (**lu**) : ajouter une colonne impose de réécrire ce champ sur **toutes** les cellules. AppFlowy en propose une vingtaine (§3.4) ; le GFM n'en porte qu'une partie | C3, C7 |
| **Largeur de colonne** | `NSTextTableBlock.setWidth(_:type:for: .width)` n'est jamais appelé (**lu**). Il faut un modèle de largeur — et **le markdown GFM n'a aucune syntaxe pour le porter**. Soit on l'oublie à la fermeture, soit on invente un stockage hors texte | C3, **C7 la contraint fortement** |
| **Coloration syntaxique des blocs de code** | `.mdCodeLanguage` est déjà porté par le storage (**lu**). La coloration est de l'attribut d'affichage pur, posé par `StyleRenderer` | C5 respectée par construction ; coût = le tokeniseur |
| **Glisser-déposer d'un fichier dans l'éditeur** | `registerForDraggedTypes` + `performDragOperation` sur `EditorTextView`, puis `MediaStore` | C4 : à écrire de zéro, rien de tel n'existe dans l'app |
| **Poignée de bloc et déplacement** | voir la [spec dédiée](2026-08-06-poignee-de-bloc-et-deplacement.md) — c'est la demande explicite de `CLAUDE.md` | C4 en totalité |

### Lourd — infrastructure absente, ou en tension avec TextKit 1 / le markdown

| Élément | Pourquoi c'est lourd |
|---|---|
| **Glisser-déposer de blocs à la souris** | session de glisser, indicateur de dépôt peint entre deux blocs, auto-défilement. Le déplacement du texte lui-même est facile ; c'est l'affordance qui coûte. Une étape intermédiaire honnête existe : **déplacer par le clavier et par le menu de la poignée**, sans souris (cf. spec dédiée) |
| **Repli / toggle de sections** | il faut masquer des glyphes sans toucher au texte. Faisable en TextKit 1 (`NSLayoutManager` sait ne pas afficher un intervalle) mais fragile, et **aucune syntaxe markdown ne porte l'état plié**. `<details>` passerait en `rawBlock`, affiché en texte brut monospace — valeur d'usage nulle en l'état |
| **Équations mathématiques rendues** | il faut un moteur de rendu (KaTeX en `WKWebView` hors écran) + cache + attachments. C'est **exactement l'infrastructure `Blocks/` que la spec du 2026-08-03 décrivait pour mermaid et qui n'a jamais été écrite** |
| **Diagrammes mermaid** | même infrastructure, même coût. Mis hors périmètre le 2026-08-04 ; à rouvrir explicitement si on la construit pour les maths |
| **Aperçu de lien / carte d'URL** | une carte inline exigerait `NSTextAttachmentViewProvider`, donc **TextKit 2** (C1). Un repli acceptable : un attachment image statique (titre + favicon) rendu hors écran — mais alors on retombe sur l'infrastructure `Blocks/` |
| **Colonnes 2/3/4** | une rangée `NSTextTable` sans bordure ferait illusion (C3 le permet), mais **le markdown n'a aucune représentation** : il faudrait un bloc HTML en `rawBlock`, qui s'affiche en texte brut. Sans changer le format de stockage, ce n'est pas livrable |

### Hors d'atteinte dans cette architecture — le dire vaut mieux que le promettre

| Élément | Pourquoi |
|---|---|
| **Édition collaborative temps réel, curseurs distants** | AppFlowy s'appuie sur un CRDT (`yrs`) sous un arbre de blocs. OneToOne est local et mono-utilisateur, et son modèle est reconstruit à chaque chargement. Aucun besoin, aucun chemin bon marché |
| **Tout ce qui s'ancre sur l'identité d'un bloc** — copier le lien vers un bloc, commenter un bloc, historiser un bloc | le markdown ne porte **aucun identifiant de bloc**. Les `tableID` du module sont régénérés à chaque parse : ils groupent les cellules d'une même table *dans une session*, ils n'identifient rien de durable |
| **Bases de données (Grid / Kanban / Calendar) et vues liées** | AppFlowy a un moteur de base générique (`collab-database`). OneToOne a des modèles SwiftData **typés** — projets, collaborateurs, réunions. La transposition juste n'est pas « refaire une base générique », c'est **« lien vers une entité OneToOne »** (colonne *moyen*) |
| **Sous-pages / documents imbriqués** | il n'existe pas de notion de page dans OneToOne : une note est une `String` sur un modèle SwiftData. Créer une hiérarchie de documents est un chantier de modèle de données, pas un chantier d'éditeur |
| **Galerie photo** | pas de représentation markdown pour une mise en page à N images ; `/image` répété couvre le besoin réel. **AppFlowy non plus n'en fait pas de markdown** : `multi_image` n'a aucun encodeur (§3.5) |
| **Vues interactives inline** (sondage, lecteur vidéo, embed) | `NSTextAttachmentViewProvider` exige TextKit 2 (C1). Ce serait une migration de pile, pas une fonctionnalité. AppFlowy lui-même redirige son bloc `video` vers un rendu d'aperçu de lien, faute de widget natif |
| **Couleur de texte, surlignage, alignement de paragraphe** | AppFlowy les expose dans sa barre flottante, et sa propre documentation d'import prévient qu'ils **ne survivent pas** au markdown (« *font-size, font-family and text-align are not supported yet* »). Les ajouter ici produirait un réglage qui disparaît au rechargement — pire qu'une absence |
| **Colonne d'en-tête de tableau** | GFM ne définit qu'une **ligne** d'en-tête. `enableHeaderColumn` d'AppFlowy n'a pas d'équivalent markdown : purement visuel, perdu au rechargement |

---

## 6. Ordre de travail recommandé

Ce qui bloque quoi, explicitement.

```
   ┌── Lot A — remettre d'aplomb ce qui est livré ─────────────────┐
   │  A1  visibilité de Titre 1 / Séparateur (.prep)              │  aucun prérequis
   │  A2  panneau `/` plafonné + défilant       ◄── BLOQUE B, C   │
   │  A3  mesurer la perte d'InlineHTML, corriger si confirmée    │
   └──────────────────────────────────────────────────────────────┘
                              │
   ┌── Lot B — le confort de frappe (meilleur rapport valeur/coût)┐
   │  B1  raccourcis markdown à la frappe (# - > 1. [] ``` ---)   │
   │  B2  clavier des listes (Tab, ⇧Tab, ⏎ sur item vide, ⌫)      │
   └──────────────────────────────────────────────────────────────┘
                              │
   ┌── Lot C — les entrées de menu bon marché ────────────────────┐
   │  C1  Titres 4-6      C2  Bloc de code     C3  Callout        │  dépend de A2
   │  C4  Emoji           C5  Fichier joint    C6  Sommaire       │
   │  C7  menu `/` contextuel (pas de tableau dans un tableau)    │
   └──────────────────────────────────────────────────────────────┘
                              │
   ┌── Lot D — fermer les boucles ouvertes ───────────────────────┐
   │  D1  lien cliquable + routes onetoone://   ◄── BLOQUE D2, D3 │
   │  D2  rendu distinct mention / date / lien externe            │
   │  D3  date structurée en lien + rappel conservé               │
   │  D4  lien vers une entité OneToOne (projet, personne, 1:1)   │  dépend de D1
   └──────────────────────────────────────────────────────────────┘
                              │
   ┌── Lot E — la manipulation de bloc (la demande de CLAUDE.md) ─┐
   │  E1  géométrie de bloc + survol (NSTrackingArea)  ◄── BLOQUE │
   │  E2  poignée « + » et « ⋮⋮ » + menu (convertir, dupliquer,   │
   │      supprimer, monter, descendre)                           │
   │  E3  déplacement au clavier (⌃⇧↑ / ⌃⇧↓)                      │
   │  E4  glisser-déposer à la souris (lourd, optionnel)          │
   │  E5  barre d'outils flottante sur sélection (réutilise E1)   │
   └──────────────────────────────────────────────────────────────┘
                              │
   ┌── Lot F — au choix, aucun ne bloque les autres ──────────────┐
   │  F1  opérations sur les tableaux (lignes, colonnes, aligne)  │
   │  F2  coloration syntaxique des blocs de code                 │
   │  F3  glisser-déposer d'un fichier image                      │
   │  F4  sélection multi-blocs                                   │
   │  F5  infrastructure Blocks/ (maths, mermaid) — lourd         │
   └──────────────────────────────────────────────────────────────┘
```

**Justification de l'ordre.**

- **A2 bloque tout ajout d'entrée** (C8) : passer de 12 à ~18 entrées sans
  plafond ni défilement fait sortir le panneau de l'écran. C'est le seul vrai
  prérequis technique du lot C.
- **B avant C**, à rebours de l'intuition. Les raccourcis à la frappe et le
  clavier des listes sont ce qui *fait* un éditeur AppFlowy à l'usage, bien plus
  que six entrées de menu supplémentaires. Taper `- ` en début de ligne et voir
  une puce apparaître est le geste que l'utilisateur fera cent fois par jour ;
  ouvrir `/emoji` est le geste qu'il fera une fois par semaine. Et ces deux lots
  n'ont besoin d'aucune infrastructure nouvelle : le hook `doCommandBy` et
  `ShortcutDetector` existent, il n'y manque que des cas.
- **D1 bloque D2, D3 et D4** : décider comment un lien interne se clique fixe la
  façon dont on le stylise et dont on route les autres schémas. L'inverse
  produirait trois mécanismes concurrents.
- **E1 bloque E2, E3, E4 et E5** : la géométrie de bloc (à partir de quel
  intervalle de caractères commence et finit un « bloc » au sens de l'utilisateur,
  et quel rectangle il occupe) est la brique commune. C'est aussi la seule partie
  vraiment neuve du lot. Voir la spec dédiée.
- **E4 est optionnel.** E2 + E3 livrent déjà « des paragraphes qu'on peut
  bouger » — la demande de `CLAUDE.md` — sans écrire une session de glisser.
- **F5 en dernier** parce que c'est la seule ligne qui ajoute une dépendance
  lourde au bundle (un moteur de rendu embarqué) et qu'elle n'apporte rien aux
  autres.

---

## 7. Cinq idées de conception à reprendre, indépendamment des fonctionnalités

Elles ne coûtent presque rien et elles changent la qualité du résultat.

1. **Le menu d'actions d'un bloc est calculé par type de bloc.** Chez AppFlowy,
   seuls *Supprimer* et *Dupliquer* sont universels ; *Profondeur* n'existe que
   sur le sommaire, *Répartir les colonnes* que sur un tableau. Prévoir ce
   mécanisme dès le lot E2 évite de figer un menu unique qu'il faudra démonter.
2. **Un seul type de bloc peut couvrir quatre entrées de menu.** `toggle_list`
   avec un `level` optionnel est à la fois le repli simple et les trois titres
   repliables, et le sommaire l'indexe au même titre qu'un titre ordinaire. Le
   même raisonnement s'applique ici au **callout** : un `blockquote` dont le
   contenu commence par un emoji, plutôt qu'un nouveau type.
3. **Un bloc d'erreur plutôt qu'une perte.** AppFlowy affiche un bloc de repli
   quand un type lui est inconnu. `BlockType.rawBlock` remplit déjà cette
   fonction dans OneToOne — c'est une bonne décision, à ne pas défaire.
4. **Le champ lien et la recherche interne ne font qu'un.** « *Paste link or
   search pages* ». Deux champs séparés obligeraient l'utilisateur à savoir
   d'avance de quel genre de lien il s'agit.
5. **Deux gestes sur un seul bouton.** Le « + » insère en dessous au clic,
   au-dessus avec Alt. Le « ⋮⋮ » est la poignée de glisser **et** l'ouverture du
   menu. Quatre actions, deux boutons, aucune barre d'outils.

À l'inverse, **une idée d'AppFlowy à ne pas reprendre** : avoir réaffecté `>` au
repli et déplacé la citation sur `"`. `>` doit rester la citation.

---

## 8. Verdict sur `2026-08-05-commandes-slash-manquantes.md`

Document non commité, d'origine inconnue, apparu en cours de session.

**Verdict : fiable sur le fond, à conserver, à ne pas suivre tel quel.**

**Ce que j'ai vérifié et qui tient :**

- Son inventaire AppFlowy est **exact**, et c'est la partie la plus solide du
  document. Recoupé deux fois indépendamment : contre le listing GitHub de
  `slash_menu/slash_menu_items`, et contre une seconde enquête menée séparément
  sur `slash_menu_items_builder.dart` et `en-US.json`. Ses 36 lignes, dans cet
  ordre, correspondent à la liste réelle. Aucune invention.
- Sa prudence sur les groupes est **justifiée a posteriori** : il écrit que les
  noms de catégories sont « utilisé[s] côté web/mobile ». C'est exact — sur
  desktop le menu est une liste plate (§3.2). Il ne le dit pas explicitement,
  mais il ne se trompe pas.
- Son **blocage préalable** est réel et je l'ai confirmé par lecture :
  `SlashPanelMetrics.idealSize(for:)` est bien strictement proportionnel, et
  `SlashPanelContent` est bien un `VStack` sans `ScrollView`. Il cite
  `SlashPanel.swift:318` ; c'est à ~317 dans le fichier actuel. Détail.
- `SlashCommand.Key.slashPanelIcon` **existe** bien (`SlashPanel.swift:285`), et
  `Tests/SlashCatalogTests.swift` aussi.
- `MediaStore` ne sait effectivement **que** `saveClipboardImage()`.
- `SlashDateSelection.reminder` est bien **capturé puis jeté**.
- `BlockType.h4/h5/h6`, `LineBlockType.h4/h5/h6`, `MarkdownFeature.heading(.h4…)`,
  `BlockType.codeBlock`, `.mdCodeLanguage`, `MarkdownSerializer.fencedCodeBlock`
  et `fenceLength(for:)` existent tous.
- Le schéma `onetoone://` est bien enregistré côté `MickeyIntegration`
  (`callbackScheme = "onetoone"`, `MickeyIntegration.swift:47` et suivantes), et
  son exigence — « un lien qui ne mène nulle part n'est pas livrable » — est
  juste.

**Ce qui est faux ou incomplet :**

- « **11 entrées** » : il y en a **12**, et sa propre énumération en compte
  douze. Erreur d'arithmétique, sans conséquence.
- Il **ne voit pas** que « Titre 1 » et « Séparateur » sont invisibles dans tous
  les hôtes réels de l'éditeur (`.prep`). Ses tests de filtrage proposés
  (« avec `.prep`, `/h4` ne retourne rien ») frôlent le sujet sans le nommer.
- Il **ne voit pas** que la mention `onetoone://collaborator/…` est déjà inerte —
  il pose l'exigence de routage au lot 8 pour les entités, alors qu'elle est déjà
  due pour les collaborateurs livrés.
- **Son périmètre est trop étroit.** C'est un document sur *les commandes du menu
  `/`*, pas sur *l'éditeur*. Il n'a rien sur les raccourcis à la frappe, rien sur
  le clavier des listes, rien sur la poignée de bloc, rien sur le déplacement —
  c'est-à-dire rien sur la demande écrite dans `CLAUDE.md`, et rien sur ce qui
  sépare vraiment cet éditeur de celui d'AppFlowy.
- Son « ordre d'exécution imposé » (lot 0 → 8) ferait donc six semaines
  d'entrées de menu avant le premier geste de manipulation de bloc.

**Décision.** Le conserver tel quel — c'est un bon inventaire et un bon prompt
d'implémentation pour le **lot C** de ce document. Ses lots 0, 1, 2, 3, 4, 6 et 7
sont repris ici sous A2 et C1-C6, et ses lots 5 et 8 sous D3 et D4. Ne pas
l'exécuter comme plan général : il n'en est pas un.

*Ce fichier n'a pas été modifié par la présente session.*

---

## 9. Hors périmètre de ce document

- Les entrées **IA** (`Ask AI`, `Continue writing`) : mises hors périmètre par
  décision utilisateur du 2026-08-04, consignée en tête de `SlashCatalog.swift`.
  Le socle existe (`DirectLLMClient`, provider `.direct`). **Ne pas les coder
  sans rouvrir la décision explicitement.**
- Les bases de données d'AppFlowy, sa synchronisation cloud, ses espaces et vues.
- La migration TextKit 2. Elle reste possible sans toucher au format de stockage,
  et c'est le seul chemin vers les vues vivantes inline — mais rien de ce
  document ne l'exige.
- L'unification de `Views/MarkdownText.swift` avec `MarkdownParser` (étape 1
  jamais faite de la spec du 2026-08-03). Toujours souhaitable, sans rapport avec
  AppFlowy.
