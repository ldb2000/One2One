# Poignée de bloc, déplacement et sélection de bloc

Date : 2026-08-06
Branche : `feat/editeur-slash-blocs`
Spec mère : [`2026-08-06-editeur-appflowy-cap.md`](2026-08-06-editeur-appflowy-cap.md) — lot E
Statut : **conception, rien d'implémenté.**

---

## 1. Pourquoi cette spec existe

`CLAUDE.md` porte, de la main de l'utilisateur :

> on s'inspire de https://github.com/AppFlowy-IO/AppFlowy pour l'editeur. Commande
> avec des /, avec des **parapgraphe qu'on peut bouger** et rajouter des bloque.

Le menu `/` est livré. Les blocs s'ajoutent. **Rien ne permet de bouger un
paragraphe.** Cinquante et un commits sur cette branche n'ont pas touché le
sujet, parce qu'il ne se traite pas par une entrée de catalogue de plus : c'est
la seule fonctionnalité de la liste qui demande une infrastructure d'interaction
absente de bout en bout.

Ce document la conçoit. Il ne l'implémente pas.

---

## 2. Ce qu'AppFlowy fait, précisément

**Vérifié** (listings `editor_plugins/actions/`, énum `OptionAction`, libellés
`en-US.json`). Au survol d'un bloc, deux boutons apparaissent dans la marge
gauche :

| Bouton | Geste | Effet |
|---|---|---|
| **+** | clic | insérer un bloc **en dessous** |
| **+** | **Alt/Option + clic** | insérer un bloc **au-dessus** |
| **⋮⋮** | glisser | **déplacer** le bloc |
| **⋮⋮** | clic | ouvrir le **menu du bloc** |

Menu du bloc, actions vérifiées : `delete`, `duplicate`, `turnInto` (sous-menu
de conversion), `moveUp`, `moveDown`, `copyLinkToBlock`, `color`, `align`, plus
des actions **contribuées par le type de bloc** (`depth` pour le sommaire,
`setToPageWidth` et `distributeColumnsEvenly` pour un tableau).

Commentaire du code d'AppFlowy, vérifié : *« different block type may have
different option actions. All the block types have the delete and duplicate
options »*.

Le glisser s'appuie sur trois pièces : la poignée draggable, un **aperçu
fantôme** qui suit le curseur, et une **zone d'insertion visualisée**. Le
`CHANGELOG` ajoute l'**auto-défilement** quand on glisse vers le bord.

**Donnée de calibrage à ne pas ignorer** : le déplacement de **plusieurs** blocs
d'un coup n'est arrivé qu'en **v0.13.0, le 2026-07-24**. Une équipe à temps plein,
sur un modèle de blocs natif avec identifiants stables, a mis des années à le
livrer. Le déplacement d'**un seul** bloc, lui, est ancien et stable.

---

## 3. Ce qui manque chez nous — tout, et c'est mesurable

**Lu** sur `feat/editeur-slash-blocs` :

| Brique | État |
|---|---|
| Survol | **absent.** `EditorTextView` ne redéfinit que `mouseDown`. Aucun `mouseMoved`, aucun `updateTrackingAreas` |
| `NSTrackingArea` | **absent de l'app entière.** Zéro occurrence dans `OneToOne/` |
| Glisser-déposer | **absent de l'app entière.** Aucun `registerForDraggedTypes`, aucun `performDragOperation` |
| Sous-vues de l'éditeur | **aucune.** Pas un `addSubview` dans le module |
| Notion de « bloc » exploitable | **partielle.** `MarkdownBlockCommands.lineRange` donne la *ligne* du curseur ; personne ne calcule l'étendue d'un bloc composite (tableau, bloc de code, item de liste avec repli visuel) |
| Géométrie de bloc | **partielle.** `firstRect(forCharacterRange:)` est **mesuré** pour le curseur ; `NSLayoutManager.boundingRect(forGlyphRange:in:)` n'est utilisé nulle part |

En revanche, deux choses jouent en notre faveur :

- **Déplacer un bloc, c'est déplacer un intervalle de `NSAttributedString`.**
  Pas de modèle d'arbre à réordonner, pas de transaction, pas de CRDT. Un
  `attributedSubstring` + un `replaceCharacters` en deux temps, dans le bon
  ordre, sous `undoManager`. C'est la partie **facile**.
- **Rien de tout cela ne dépend de l'identité d'un bloc.** Le markdown n'en donne
  aucune (cf. spec mère §3.5), mais le survol, la poignée et le déplacement
  n'ont besoin que de la géométrie **du moment**. C'est précisément ce qui rend
  cette fonctionnalité atteignable, là où « copier le lien vers ce bloc » ne
  l'est pas.

---

## 4. Ce qu'est un « bloc » ici — la vraie question de conception

C'est la décision structurante, et elle doit être prise **avant** d'écrire une
ligne d'interface. AppFlowy n'a pas ce problème : un bloc est un nœud de l'arbre.
Ici, il faut le **dériver des attributs**.

Proposition — un bloc est le plus grand intervalle contigu de lignes tel que :

| Cas | Frontière |
|---|---|
| Paragraphe, titre, séparateur | **une ligne**, `NSString.lineRange` |
| Item de liste | **une ligne** — un item est déplaçable seul, comme chez AppFlowy |
| Bloc de code fencé | **tout le run** `.mdBlockType == .codeBlock` (`longestEffectiveRange`) |
| Bloc HTML / passthrough | **tout le run** `.mdBlockType == .rawBlock` |
| Citation | **tout le run** `.mdBlockType == .blockquote` — plusieurs paragraphes peuvent la composer (cf. `MarkdownParser.emitBlockQuote`) |
| Tableau | **toutes les lignes partageant le même `tableID`.** La logique existe déjà : `StyleRenderer.expandedForTable` la calcule exactement, pour une autre raison |
| Cellule de tableau | **jamais un bloc déplaçable.** Une cellule ne se sort pas de sa grille ; AppFlowy désactive d'ailleurs le bouton d'options dans les cellules |

**Recommandation forte : extraire ce calcul dans un type dédié, pur et testable
— `BlockRange` — avant toute interface.** Il ne dépend que d'un `NSTextStorage`
et d'une position. Il se teste sans fenêtre, sans souris, sans `NSView`. Et il
sera réutilisé par la sélection multi-blocs, par le menu `/` contextuel et par la
barre d'outils flottante. C'est la brique qui rentabilise tout le lot.

Point de vigilance **mesuré ailleurs sur cette branche** : `ListInfo` est
`Hashable`, donc `NSAttributedString` **fusionne les runs `.mdListInfo`
adjacents de valeur égale**. Trois cases à cocher décochées consécutives ne
forment qu'un seul run. `longestEffectiveRange` sur `.mdListInfo` renverrait
donc les trois lignes — le bug exact qui cochait trois cases d'un clic, corrigé
par `EditorTextView.toggleTaskMarker` en passant par `NSString.lineRange`.
**`BlockRange` doit faire pareil pour les listes : ligne par ligne, jamais
`longestEffectiveRange`.**

---

## 5. Découpage, du moins cher au plus cher

### E1 — `BlockRange` et la géométrie *(logique pure, aucun visuel)*

1. `BlockRange.enclosing(_ location: Int, in storage: NSTextStorage) -> NSRange`,
   selon le tableau du §4.
2. `BlockRange.previous(_:)` / `next(_:)` — les blocs voisins, pour le
   déplacement.
3. Le rectangle d'un bloc :
   `layoutManager.boundingRect(forGlyphRange:in:)` sur la plage de glyphes
   correspondante, + `textContainerInset`. **À mesurer** : cette API n'est
   utilisée nulle part dans le projet ; son comportement sur des lignes portant
   un `NSTextTableBlock` n'est pas connu.

**Livrable vérifiable** : des tests sur un `NSTextStorage` construit à la main,
sans vue. Aucun changement visible pour l'utilisateur.

### E2 — Survol et poignée

1. `updateTrackingAreas` sur `EditorTextView` + `mouseMoved` → `BlockRange` du
   bloc sous le curseur.
2. Une sous-vue `NSView` (ou deux) positionnée dans la marge gauche, à la hauteur
   du bloc survolé. **Contrainte** : le module ne pose aujourd'hui aucune
   sous-vue ; il faudra vérifier l'interaction avec le défilement du
   `NSScrollView` (repositionner sur `boundsDidChangeNotification`).
3. Le menu du « ⋮⋮ » : `NSMenu` natif suffit — pas besoin du modèle non-activant
   de `SlashPanel`, puisqu'aucune frappe n'est en cours pendant qu'il est ouvert
   (même raisonnement que celui qui a fait choisir `NSPopover` pour le sélecteur
   de date).
4. **Le menu est construit par type de bloc**, dès le départ (leçon n°1 de la
   spec mère). Actions universelles : *Supprimer*, *Dupliquer*, *Monter*,
   *Descendre*, *Convertir en…*. Contribuées : rien pour l'instant, mais le
   point d'extension existe.
5. « Convertir en… » réutilise `MarkdownBlockCommands` **tel quel** — c'est déjà
   la couche qui mute par attributs sans détruire l'inline.

**Piège** : la marge gauche est déjà occupée. `MarkdownLayoutManager` y dessine
les puces, les numéros, les cases à cocher (`ListMarkerLayout.textIndent`) et le
filet de citation (`BlockquoteRuleLayout.ruleLeadingGap`). La poignée doit vivre
**à gauche de tout ça**, ce qui suppose d'élargir `textContainerInset.width`
(aujourd'hui 6 pt) — et donc de revérifier `toggleTaskMarker`, qui compare
`containerPoint.x` à `firstLineHeadIndent`.

### E3 — Déplacement au clavier et par le menu

Le cœur, et le moins cher une fois E1 fait.

```
monter :  découper la plage du bloc courant
          l'insérer avant la plage du bloc précédent
descendre : symétrique
```

Contraintes :

- passer par `shouldChangeText(in:replacementString:)` / `didChangeText()` pour
  que le pipeline normal s'exécute (sérialisation, debounce, `undo`) — **ne pas**
  muter `textStorage` directement, piège déjà rencontré et documenté
  (`EditorTextView.applyTaskToggle`) ;
- purger les `typingAttributes` à risque avant l'insertion
  (`stripRiskyTypingAttributes`) — contrainte C6 de la spec mère ;
- déplacer un bloc peut créer une **nouvelle paire de blocs adjacents** :
  `MarkdownSerializer.needsBlankLine` gère déjà les 8 paires connues, mais
  **il faut le vérifier par test**, pas le supposer ;
- raccourcis : `⌃⇧↑` / `⌃⇧↓` (macOS n'y a pas de convention forte ; ne pas
  prendre `⌥↑`/`⌥↓`, qui déplacent le curseur par paragraphe).

**Livrable** : « des paragraphes qu'on peut bouger » est **satisfait à ce
stade**, sans avoir écrit une seule ligne de glisser-déposer.

### E4 — Glisser-déposer à la souris *(optionnel, lourd)*

`NSDraggingSource` sur la poignée, aperçu fantôme via
`NSDraggingItem.setDraggingFrame(_:contents:)`, indicateur de dépôt peint entre
deux blocs (dans `MarkdownLayoutManager` ou dans une sous-vue de recouvrement),
auto-défilement au bord.

**Ne l'entreprendre qu'après E3, et seulement si E3 ne suffit pas à l'usage.**
Le rappel de calibrage du §2 vaut ici : c'est la partie qu'AppFlowy a mis le
plus longtemps à stabiliser, avec un modèle de données bien plus favorable.

### E5 — Barre d'outils flottante sur sélection

Réutilise la géométrie d'E1 et le patron de `SlashPanel`. Voir la spec mère.

---

## 6. Ce que cette spec ne promet pas

- **Copier le lien vers un bloc.** Le markdown ne porte aucun identifiant de
  bloc. Sans changer le format de stockage, c'est hors d'atteinte — et changer le
  format contredirait la décision fondatrice de ce module.
- **Déplacer plusieurs blocs à la fois.** Possible après E3 + la sélection
  multi-blocs, mais à ne pas annoncer : AppFlowy a mis des années à le faire avec
  de meilleures cartes.
- **Couleur de fond ni alignement de bloc.** Ces deux actions du menu d'AppFlowy
  n'ont pas de représentation markdown : elles disparaîtraient au rechargement.
  Les proposer serait mentir à l'utilisateur — même faute que le menu « Rappel »
  du sélecteur de date, qui fait choisir une valeur qu'il jette
  ([spec dates](2026-08-05-dates-et-rappels.md)).
- **Déplacer une cellule hors de son tableau.**

---

## 7. Ordre et dépendances

```
E1 (BlockRange + géométrie)  ──┬──►  E2 (survol + poignée + menu)
                               ├──►  E3 (déplacement clavier)   ◄── satisfait CLAUDE.md
                               ├──►  E5 (barre flottante)
                               └──►  sélection multi-blocs, menu `/` contextuel
                                        │
                                        └──►  E4 (glisser-déposer)  — optionnel
```

E1 est le seul travail réellement neuf et il ne se voit pas. C'est aussi celui
qui doit être écrit en premier et testé seul : tout le reste s'appuie dessus, et
tout le reste est de l'interface, donc peu testable dans ce projet (`SlashPanel`
et `MentionPanel` ne le sont pas — ne pas inventer de couverture).
