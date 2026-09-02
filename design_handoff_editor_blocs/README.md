# Handoff : blocs `/tableau` et `/diagramme` dans l'éditeur

## Overview

Trois chantiers dans un éditeur de texte riche de type bloc :

1. **Bloc `/diagramme` (mermaid)** — corriger le rendu cassé (hauteur fixe répartie sur les lignes du source, fond gris débordant, source visible sous le placeholder) et définir ses quatre états.
2. **Bloc `/tableau`** — définir ce que la commande insère par défaut, et les contrôles d'ajout/suppression de lignes et colonnes.
3. **Manipulation du bloc lui-même** — poignée de glissement, sélection du bloc entier, réordonnancement, menu de bloc. C'est le chantier le plus structurant : il change le layout de la colonne d'édition.

## About the design files

Le fichier dans `reference/` est une **référence de design écrite en HTML** — une maquette qui montre l'intention visuelle et le comportement attendu, **pas du code de production à copier**. Le travail consiste à **recréer ces designs dans l'environnement existant du codebase** (React/ProseMirror/Tiptap/Lexical, Vue, etc.), avec ses composants, ses tokens et ses conventions. Si aucun environnement n'existe encore, choisir le framework approprié et y implémenter les designs.

Ouvrir `reference/Editeur - blocs tableau et diagramme.html` dans un navigateur : la page est un canvas avec plusieurs « tours » d'exploration, chaque option porte un identifiant visible (`1a`, `2a`, `3a`…) référencé ci-dessous.

## Fidelity

**Haute fidélité.** Couleurs, typographies, espacements et états sont définitifs et donnés en valeurs exactes plus bas. Le style suit les conventions macOS/AppKit claires (SF/system font, bleu système `#0a6cff`). **Si le codebase a déjà un design system, ses tokens priment** : mapper les valeurs ci-dessous sur les tokens équivalents plutôt que de coder les hex en dur.

---

## Principe directeur (à lire avant tout)

> **La gouttière gauche appartient au bloc. L'intérieur du cadre appartient au contenu.**

- Gouttière (56–58 px à gauche de la colonne de contenu) : poignée de glissement `⠿`, bouton d'insertion `+`. Rien d'autre.
- Intérieur du cadre : le contenu et ses contrôles propres (menus de colonne du tableau, barre d'actions du diagramme).

Les deux zones ne se recouvrent jamais — c'est ce qui permet aux contrôles ligne/colonne du tableau de coexister avec la manipulation du bloc sans conflit de cible de clic.

Deuxième principe : **rien de permanent ne flotte au-dessus du contenu.** Toutes les affordances apparaissent au survol ou à la sélection, en faible contraste, ancrées à une structure (en-tête, gouttière, barre de pied).

---

## Screen 1 — Bloc diagramme (`/diagramme`), réf. `2a`

Quatre états, dans l'ordre du cycle de vie.

### 1.1 Rendu en cours

- Conteneur : `border: 1px solid #e0ddd7`, `border-radius: 8px`, `background: #faf8f5`, **`height: 104px` fixe**, `display: grid; place-items: center`, `overflow: hidden`.
- Contenu : spinner 11×11 px (`border: 1.5px solid rgba(0,0,0,.18)`, `border-top-color: rgba(0,0,0,.42)`, `border-radius: 50%`, rotation 0,8 s linéaire infinie) + label « Diagramme… », `12px/1`, `rgba(0,0,0,.42)`, `gap: 8px`.
- Badge langage en haut à droite : `position:absolute; top:7px; right:8px`, `font: 500 10px/1 ui-monospace`, `color: rgba(0,0,0,.3)`, `background: rgba(0,0,0,.04)`, `padding: 3px 6px`, `border-radius: 4px`, texte « mermaid ».

**Bugs à corriger explicitement** (c'est l'état actuel cassé) :
- La hauteur du placeholder ne doit **pas** être calculée par ligne de source. Une hauteur provisoire unique et modeste (104 px), sur **une seule ligne de layout**. Le bug actuel réserve 220 pt et les répartit sur les lignes du source → 2 lignes = 2 bandes de 110 pt.
- Le **source doit être masqué** dès que le placeholder est posé. Aujourd'hui il reste visible dessous.
- Le fond du bloc de code ne doit **pas** déborder sur toute la largeur de la page — il est contenu par le cadre du bloc, dont la largeur max est la colonne de texte.

### 1.2 Rendu, au survol

- Conteneur : `border: 1px solid #e6e3dd`, `border-radius: 8px`, `background: #fff`, `padding: 18px 16px`. **Hauteur libre, dictée par le SVG rendu.** Largeur max = colonne de texte ; SVG centré, mis à l'échelle vers le bas s'il dépasse, jamais vers le haut.
- Barre d'actions, visible **uniquement au survol** : `position:absolute; top:8px; right:8px`, `background: rgba(250,250,252,.92)`, `border: 1px solid #dedbd5`, `border-radius: 7px`, `box-shadow: 0 1px 3px rgba(0,0,0,.07)`, `padding: 3px`, `gap: 2px`.
  - Bouton « Modifier » : `height: 22px`, `padding: 0 9px`, `border-radius: 5px`, `font: 11.5px/1`, `color: #3c3c43`, fond transparent → `rgba(0,0,0,.07)` au survol.
  - Séparateur : `width:1px`, `background:#e2dfd9`, `margin: 3px 1px`.
  - Bouton « Copier l'image » (icône `⧉`) : carré 24×22 px, mêmes états.

### 1.3 Source ouvert (clic sur le diagramme)

- Conteneur : `border: 1px solid #d4d1cb`, `border-radius: 8px`, `overflow: hidden`.
- En-tête : `background: #f5f3ef`, `border-bottom: 1px solid #e4e1db`, `padding: 6px 8px 6px 12px`, `display:flex; align-items:center; gap:8px`.
  - Label langage à gauche : `font: 500 10.5px/1 ui-monospace`, `rgba(0,0,0,.42)`.
  - Bouton « Terminé » à droite : `height:21px`, `padding: 0 10px`, `border: 1px solid #cfccc6`, `border-radius:5px`, `background:#fff` → `#f0eeea` au survol, `font: 11.5px/1`, `color:#3c3c43`.
- Corps : `background: #fcfbf9`, `font: 12.5px/1.55 ui-monospace, Menlo, monospace`, `color: #1d1d1f`.
  - **Interligne normal : `line-height: 1.55`.** C'est le correctif central — pas de hauteur de ligne dérivée de la hauteur du diagramme.
  - Gouttière de numéros de ligne : `padding: 10px 0 10px 10px`, `color: rgba(0,0,0,.22)`, `text-align: right`, `user-select: none`.
  - Code : `padding: 10px 12px`, `white-space: pre`.
- Le diagramme se re-rend à la fermeture (bouton « Terminé », `Esc`, ou clic hors du bloc).

### 1.4 Diagramme invalide

- Conteneur : `border: 1px solid #e9b8b3`, `background: #fdf6f5`, `border-radius: 8px`, `padding: 14px 16px`. **Cadre teinté, pas de liseré rouge vif.**
- Titre : puce ronde 14 px `background:#d9483b`, glyphe `!` blanc `700 10px/14px` ; texte « Diagramme invalide » `600 12.5px/1`, `color: #c0392f`, `gap: 7px`.
- Message d'erreur brut de mermaid : `font: 12px/1.5 ui-monospace`, `color: #8a3a31`, **tronqué à 2 lignes**.
- Bouton « Ouvrir le source » : `height:22px`, `padding: 0 10px`, `border: 1px solid #dcb5b0`, `border-radius:5px`, `background:#fff` → `#fbeeec` au survol, `font: 11.5px/1`, `color:#8a3a31`.
- **Le source reste intact dans le document** — jamais d'écrasement ni de perte à l'erreur de parsing.

---

## Screen 2 — Bloc tableau : insertion par défaut (`/tableau`), réf. `2b`

Ce que la commande insère :

- Table `3 colonnes × 2 rangées de corps` + 1 rangée d'en-tête.
- `width: 100%` (toute la colonne de texte), `border-collapse: collapse`, `table-layout: fixed` (colonnes de largeur égale), `border: 1px solid #dedbd5` sur la table.
- Cellules : `border: 1px solid #e4e1db`, `padding: 6px 9px`, `font: 13px/1.45` system font, `color: #1d1d1f`.
- Rangée d'en-tête : `background: rgba(0,0,0,.035)` + `font-weight: 600`. Pas de bordure épaisse.
- Les libellés « Colonne 1/2/3 » sont des **placeholders** (`color: rgba(0,0,0,.3)`), pas du texte inséré : ils disparaissent à la frappe et ne sont pas sérialisés dans le document.
- Le curseur se place dans la **première cellule d'en-tête**.
- **Toutes les rangées vides ont la même hauteur** : imposer une hauteur de ligne minimale sur les cellules (`min-height` équivalent à `height: 19px` + un contenu de hauteur de ligne garantie). Une cellule vide ne doit jamais s'effondrer.

## Screen 3 — Contrôles ligne/colonne, réf. `1a` (option interactive), `1b`, `1c`, `1d`

`1a` est la direction recommandée et est **interactive dans la maquette** — la manipuler pour comprendre le comportement.

### Ce qui ne va pas dans la version actuelle
Les badges ✕ rouge et ✚ bleu sont permanents, saturés, et flottent au-dessus du contenu : les contrôles concurrencent les données. Les apps macOS cachent les actions destructrices derrière des menus et gardent les affordances permanentes en faible contraste, ancrées à la structure.

### `1a` — menus d'en-tête + barre de pied (recommandé)

- Cadre : `background:#fff`, `border: 1px solid #d5d5d8`, `border-radius: 8px`, `box-shadow: 0 1px 2px rgba(0,0,0,.06), 0 6px 18px rgba(0,0,0,.05)`, `overflow: hidden`.
- En-tête : `background: linear-gradient(#fdfdfd, #f4f4f6)`, `border-bottom: 1px solid #dcdce0`, séparateurs verticaux `1px solid #e6e6ea`.
  - Libellé : `600 11.5px/1.2`, `color: rgba(0,0,0,.55)`, `padding: 6px 8px 6px 10px`, `text-align:left`, ellipsis.
  - Chevron `⌄` : 16×16 px, `border-radius: 4px`, **`opacity: 0` par défaut → `1` au survol de la colonne ou menu ouvert**, `transition: opacity .12s`, survol `background:#e3e3e8`. La cellule d'en-tête passe à `#e6e6ec` quand son menu est ouvert.
- Gouttière de gauche : `width: 30px`, `background: #fafafc` (`#eaf0ff` si rangée sélectionnée), `border-right: 1px solid #e6e6ea` ; poignée `⌄` `11px/1`, `rgba(0,0,0,.4)`, `opacity 0 → 1` au survol de la rangée.
- Corps : `padding: 7px 10px` (dense : `4px 10px`), `border-bottom: 1px solid #eeeef2`, `border-right: 1px solid #f0f0f4`, première colonne `#1d1d1f`, autres `rgba(0,0,0,.62)`. Rangée sélectionnée : `background: #f4f7ff`. Zébrures optionnelles : `#fafafc` une ligne sur deux.
- Barre de pied : `padding: 7px 10px`, `border-top: 1px solid #e2e2e6`, `background:#f7f7f9`.
  - Segmented `+` / `−` : boutons 26×22 px, `border: 1px solid #cfcfd4`, `background: linear-gradient(#fff,#f6f6f8)`, rayons `5px 0 0 5px` / `0 5px 5px 0`, survol `#ededf1`.
  - Compteur « N rows · M columns » : `11px/1`, `rgba(0,0,0,.42)`.
  - Bouton « Add Column » à droite : `height:22px`, `padding: 0 9px`, mêmes styles de bouton.
- Menu de colonne (popover) : `width: 208px`, `padding: 4px`, `background: rgba(247,247,249,.98)`, `border: .5px solid rgba(0,0,0,.14)`, `border-radius: 7px`, `box-shadow: 0 8px 24px rgba(0,0,0,.2)`, `backdrop-filter: blur(20px)`, positionné sous l'en-tête cliqué. Items : `padding: 5px 9px`, `border-radius: 4px`, survol `background:#0a6cff; color:#fff`. Raccourci aligné à droite, `font-size: 11px`, `opacity: .45`.
  - Items : Insert Column Before · Insert Column After (`⌘⌥→`) · Sort Ascending · **Delete Column** (`⌘⌫`, `color:#c8342b`, survol `background:#c8342b; color:#fff`).
- Le menu se ferme au `mousedown` hors du popover.
- Garde-fous : impossible de supprimer la dernière colonne ou la dernière rangée.

### Alternatives documentées
- `1b` — rails d'insertion : trait bleu 2 px `#0a6cff` + pastille `+` 18 px dans la gouttière entre colonnes, au survol de l'espace inter-colonnes. Barre d'état en pied qui verbalise l'action.
- `1c` — barre d'outils de fenêtre + gouttière type tableur (numéros de ligne, lettres de colonne, colonne sélectionnée teintée `#dfe8fb` / `#f2f6ff`). Rien ne flotte jamais sur les données.
- `1d` — rangée/colonne fantôme en pointillés (`1px dashed #dcdce4`, `+ New row`) pour l'ajout, menu contextuel pour la suppression.

---

## Screen 4 — Le bloc comme objet déplaçable, réf. `3a` (interactif) et `3b`

C'est le chantier qui manque le plus. Un tableau ou un diagramme est un **objet dans le flux**, pas du texte. Il lui faut trois choses que le texte n'affiche pas : une **prise** (où saisir), une **limite** (jusqu'où va le bloc), une **cible** (où il atterrit).

### Layout de la colonne d'édition

```
[ gouttière 58px ][ corps du bloc, flex:1 ]
   +   ⠿  (12px)
```

- Wrapper de bloc : `display:flex; align-items:flex-start; padding: 5px 0; position: relative`.
- Gouttière : `width: 58px; flex: none; display:flex; justify-content:flex-end; gap: 3px; padding: 2px 12px 0 0`. Les 12 px de padding droit sont importants — collés au bloc, les contrôles étaient laids.
- Corps : `flex: 1; min-width: 0; padding: 9px 11px; border-radius: 6px; border: 1.5px solid transparent` (la bordure transparente réserve la place, pour que la sélection ne fasse pas sauter le layout).

### Les cinq états (réf. `3b`)

| État | Gouttière | Corps |
|---|---|---|
| **1. Repos** | rien (`opacity: 0`) | fond transparent, bordure transparente |
| **2. Survol** | `+` et `⠿` à `opacity:1`, `transition: opacity .12s` | `background: rgba(0,0,0,.018)` |
| **3. Sélectionné** | — | `border: 1.5px solid #0a6cff`, `background: #f4f8ff` |
| **4. Glissement** | `⠿` visible | bloc entier `opacity: .4`, **reste en place** |
| **5. Menu ouvert** | `⠿` actif | popover ancré à la poignée |

Boutons de gouttière : 17×22 px, `border-radius: 4px`, fond transparent → `rgba(0,0,0,.06)` au survol.
- `⠿` : `12px/1 ui-monospace`, `rgba(0,0,0,.42)`, `cursor: grab` (→ `grabbing` pendant le drag).
- `+` : `13px/1` system, `rgba(0,0,0,.35)`.

**Indicateur de dépôt** : un **trait** de 2 px `#0a6cff`, `border-radius: 1px`, aligné sur la colonne de contenu (`left: 58px; right: 0`), positionné en haut du bloc cible si le curseur est dans sa moitié supérieure, en bas sinon. Une **ligne**, pas un rectangle de zone : un bloc s'insère *entre* deux blocs. Prévoir le cas du dépôt après le dernier bloc.

**Menu du bloc** (clic sur `⠿`, ou clic droit sur le bloc) — mêmes styles de popover que le menu de colonne, `width: 224px` :

| Item | Raccourci |
|---|---|
| Monter | `⌥↑` |
| Descendre | `⌥↓` |
| — | |
| Dupliquer | `⌘D` |
| Modifier le source | `⏎` |
| — | |
| Supprimer le bloc (`#c8342b`) | `⌘⌫` |

Le clavier double la souris : sans `⌥↑`/`⌥↓`, déplacer un bloc en bas d'un long document impose un drag interminable.

### Distinction critique : sélection de bloc vs curseur dans le contenu

- Clic **dans** une cellule → curseur texte, contrôles ligne/colonne actifs, `⌫` supprime du texte.
- Clic sur `⠿` (ou `Esc` depuis le contenu) → **le bloc entier est sélectionné**, `⌘X` / `⌘C` / `⌫` agissent sur le bloc, `⌥↑`/`⌥↓` le déplacent.

Ce sont deux modes de sélection distincts et ils doivent être visuellement distincts : curseur clignotant vs cadre bleu plein.

### Question de produit ouverte
Le `+` de la gouttière insère-t-il un bloc **au-dessus** du bloc survolé (convention Notion) ou **en dessous** ? À trancher avant l'implémentation.

---

## State management

Pour la partie blocs (voir la classe logique du fichier de référence) :

```
blocks: [{ id, type: 'text'|'table'|'diagram', ...content }]
hoveredBlock: index | null      // survol → affordances de gouttière
draggedBlock: index | null      // drag en cours → opacity .4
dropAt:       index | null      // 0..blocks.length, position du trait bleu
selectedBlock: id | null        // sélection du bloc entier
```

Réordonnancement : `splice` de l'élément hors du tableau, puis insertion à `from < to ? to - 1 : to`. Après le dépôt, le bloc déplacé devient le bloc sélectionné (feedback de fin d'action).

Pour la table (`1a`) : `cols[]`, `rows[][]`, `hoveredCol`, `hoveredRow`, `selectedRow`, `openMenu: { col, x } | null`.

## Design tokens

**Couleurs**

| Rôle | Valeur |
|---|---|
| Accent / sélection | `#0a6cff` |
| Fond de sélection | `#f4f8ff` · `#f4f7ff` (rangée) |
| Texte principal | `#1d1d1f` |
| Texte secondaire | `rgba(0,0,0,.62)` |
| Texte tertiaire / labels | `rgba(0,0,0,.42)` – `rgba(0,0,0,.55)` |
| Placeholder | `rgba(0,0,0,.3)` |
| Bordure de cadre | `#d5d5d8` · `#e3e0da` (papier) |
| Bordure de cellule | `#e4e1db` · `#eeeef2` · `#f0f0f4` |
| Fond d'en-tête | `linear-gradient(#fdfdfd, #f4f4f6)` |
| Fond de barre | `#f7f7f9` |
| Survol de bloc | `rgba(0,0,0,.018)` |
| Survol de contrôle | `rgba(0,0,0,.06)` – `rgba(0,0,0,.07)` |
| Destructif | `#c8342b` (menus) · `#c0392f` / `#8a3a31` / `#d9483b` (erreur diagramme) |
| Erreur — fond / bordure | `#fdf6f5` / `#e9b8b3` |
| Popover | `rgba(247,247,249,.98)`, bordure `rgba(0,0,0,.14)` |

**Typographie** — `-apple-system, system-ui, sans-serif` ; monospace `ui-monospace, Menlo, monospace`.

| Usage | Valeur |
|---|---|
| Corps de bloc / cellules | `13px / 1.45` |
| Table dense | `12.5px / 1.45` |
| En-tête de colonne | `600 11.5px / 1.2` |
| Barre d'état, légendes | `11px` – `11.5px` |
| Items de menu | `13px / 1` |
| Raccourcis de menu | `11px`, `opacity .45` (`.55` sur destructif) |
| Source de code | `12.5px / 1.55` mono |
| Badge langage | `500 10px / 1` mono |

**Espacement** — 2 · 3 · 4 · 6 · 9 · 10 · 12 · 18 · 26 px. Gouttière de bloc 58 px (dont 12 px de padding droit). Gouttière de table 28–30 px.

**Rayons** — 4 px (item de menu, petit bouton) · 5 px (bouton) · 6 px (corps de bloc) · 7 px (popover, groupe de boutons) · 8 px (cadre de contenu) · 10 px (cadre de fenêtre).

**Ombres**
- Cadre de table : `0 1px 2px rgba(0,0,0,.06), 0 6px 18px rgba(0,0,0,.05)`
- Popover : `0 8px 24px rgba(0,0,0,.2)` (`.16` pour le menu de bloc)
- Barre d'actions flottante : `0 1px 3px rgba(0,0,0,.07)`

**Transitions** — `opacity .12s` et `background .12s` sur toutes les affordances au survol. Rien de plus lent : ces éléments doivent suivre le curseur.

## Assets

Aucun. Toutes les icônes sont des glyphes Unicode (`⌄` `⠿` `+` `−` `⧉` `!`) ou des SVG inline 13×13 px (`stroke: #5b5b62`, `stroke-width: 1.1`, accent `#0a6cff` `stroke-width: 1.4`). **Si le codebase a une bibliothèque d'icônes, l'utiliser** — les glyphes Unicode sont un pis-aller de maquette et ne rendent pas identiquement sur toutes les plateformes. En particulier `⠿` (braille) doit devenir une vraie icône « drag handle » à six points.

## Files

- `reference/Editeur - blocs tableau et diagramme.html` — la maquette. Ouvrir dans un navigateur.
  - Tour `3` (en haut) : manipulation du bloc — `3a` interactif (glisser la poignée), `3b` les cinq états.
  - Tour `2` : blocs diagramme (`2a`, quatre états) et tableau (`2b`, insertion par défaut).
  - Tour `1` : contrôles ligne/colonne — `1a` interactif, `1b`/`1c`/`1d` alternatives.
- `screenshots/` — captures des cinq maquettes clés (`3a`, `3b`, `2a`, `2b`, `1a`), à 2×. Utiles comme référence visuelle rapide, mais **le HTML fait foi** : les états interactifs (survol, drag, menus ouverts) ne sont pas tous capturables.
- `reference/support.js` — runtime de la maquette. Aucun intérêt pour l'implémentation, nécessaire seulement pour ouvrir le fichier.

## Ordre d'implémentation suggéré

1. **Gouttière de bloc + sélection de bloc** (Screen 4) — c'est un changement de layout de la colonne d'édition ; tout le reste s'y greffe.
2. **Correctifs du bloc diagramme** (Screen 1.1 et 1.3) — hauteur du placeholder et interligne du source : deux bugs isolés, gain immédiat.
3. **Insertion par défaut de `/tableau`** (Screen 2).
4. **Glisser-déposer + menu de bloc** (Screen 4, suite).
5. **Contrôles ligne/colonne** (Screen 3, option `1a`).
