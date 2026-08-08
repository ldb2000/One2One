# Aération des blocs et aperçu figé du bloc mermaid ouvert

**Date** : 2026-08-08
**Branche** : `feat/editeur-slash-blocs`
**Constat d'origine** : capture utilisateur — trois cadres empilés à 10 pt d'écart
(carte rendue, source mermaid ouvert, carte rendue). L'appariement source → rendu
est impossible à lire, et la bande d'en-tête « mermaid » / « Terminé » semble
appartenir au cadre du dessus.

---

## Problème

Quatre défauts distincts se conjuguent dans la capture :

1. **Blocs collés.** `BlockGutterLayout.blockSpacing = 10` sépare tous les blocs
   logiques, quelle que soit leur nature. Entre deux cartes de 450 pt de haut,
   10 pt ne se lisent pas comme une frontière.
2. **En-tête mal rattaché.** L'en-tête du bloc ouvert est logé dans le
   `paragraphSpacingBefore` de sa première ligne
   (`MermaidSourceLayout.headerHeight + bodyTopPadding` = 43 pt). Avec 10 pt
   au-dessus, il touche le cadre du bloc précédent et paraît le coiffer.
3. **Source sans son aperçu.** Un bloc ouvert n'affiche aucun rendu : les deux
   cartes visibles autour appartiennent aux blocs **voisins**. L'utilisateur
   cherche naturellement à apparier le source avec l'une des deux — aucune des
   deux n'est la bonne.
4. **Cadre ouvert peu lisible.** Conséquence des trois précédents : le cadre du
   source (qui possède pourtant déjà fond, liseré, bande d'en-tête et gouttière)
   se fond dans ses voisins.

Le défaut 3 est le plus structurant, et il touche un correctif récent : le rendu
est **volontairement** suspendu pendant l'édition depuis le 2026-08-08. Relancer
un rendu à chaque frappe faisait se superposer carte et source (mécanisme et
correctif détaillés dans `STATUS.md`). Toute solution qui réaffiche un rendu
pendant l'édition doit éviter de rouvrir ce chemin.

---

## Décisions

| Question | Décision | Pourquoi |
|---|---|---|
| Aperçu pendant l'édition ? | **Oui, figé** — la dernière image rendue, jamais recalculée à la frappe | Lève l'ambiguïté d'appariement sans relancer de rendu : le mécanisme corrigé le 2026-08-08 reste fermé |
| Portée de l'écart élargi | **Blocs-cartes seulement** | Le texte courant garde ses 10 pt et ne se délave pas |
| Hauteur de l'aperçu | **Plafonnée à 240 pt**, ratio conservé | Un diagramme de 450 pt ne repousse pas le source hors de l'écran pendant la frappe |
| Contenu de l'aperçu | **L'attachment tel quel** : diagramme, cadre d'erreur ou placeholder | Voir le message « Parse error » au-dessus du source pendant qu'on le corrige est un gain |

---

## Conception

### 1. Respiration entre blocs

`BlockGutterLayout` gagne, à côté de `blockSpacing` :

```swift
/// Écart vertical sous un bloc qui dessine un cadre — nettement plus large
/// que `blockSpacing`, qui reste l'écart du texte courant.
static let cardBlockSpacing: CGFloat = 28

/// `true` si le bloc commençant à `location` peint un cadre (mermaid, tableau,
/// image, bloc de code). Fonction pure, lue au **début** du bloc.
static func isCardBlock(in storage: NSTextStorage, at location: Int) -> Bool
```

`isCardBlock` lit les attributs posés par le parseur et le renderer :
`.mdMermaidAttachment`, `.mdTableCell`, `.mdImageURL`, ou
`.mdBlockType ∈ { .codeBlock, .rawBlock }`.

`StyleRenderer.applyBlockSpacing` parcourt déjà les blocs dans l'ordre. La valeur
posée sur le dernier paragraphe de chaque bloc devient :

> `cardBlockSpacing` si **ce bloc** ou **le bloc suivant** est une carte,
> `blockSpacing` sinon.

Le coup d'œil au bloc suivant est gratuit — l'itération l'atteint de toute façon —
et il donne 28 pt **des deux côtés** de chaque carte.

**Contrainte à respecter :** ne poser que `paragraphSpacing`, jamais
`paragraphSpacingBefore`. Dans TextKit les deux s'additionnent ; deux cartes
voisines recevraient sinon 56 pt.

Voisinages résultants :

| Avant ↓ / Après → | Texte | Carte |
|---|---|---|
| **Texte** | 10 pt | 28 pt |
| **Carte** | 28 pt | 28 pt |

### 2. Aperçu figé dans le bloc ouvert

`MermaidSourceLayout` gagne la géométrie de la bande d'aperçu, sur le patron déjà
en place dans ce fichier (constantes + fonctions pures, testables sans vue vivante) :

```swift
static let previewMaximumHeight: CGFloat = 240
static let previewVerticalPadding: CGFloat = 12

/// Hauteur totale réservée à la bande d'aperçu — `0` quand
/// `attachment.image == nil` (le cadre garde alors son allure actuelle :
/// en-tête + source).
static func previewHeight(forAttachmentSize size: NSSize?, containerWidth: CGFloat) -> CGFloat

/// Rectangle de l'image dans la bande, centré horizontalement, sous l'en-tête.
static func previewRect(
    above firstLineRect: NSRect, containerWidth: CGFloat, imageSize: NSSize?
) -> NSRect
```

L'image est réduite **deux fois**, ratio conservé à chaque étape : d'abord à la
largeur du conteneur (`MermaidBlockLayout.fittedSize`, comme le fait déjà le
dessin du bloc fermé), puis à `previewMaximumHeight` si elle dépasse encore.
`previewHeight` renvoie la hauteur ainsi obtenue plus `2 × previewVerticalPadding`.

`containerWidth` est un paramètre de `previewHeight`, pas seulement de
`previewRect` : sans lui, une image plus large que le conteneur serait réduite au
dessin mais pas dans la hauteur réservée — un vide sous l'aperçu.

Disposition verticale du cadre ouvert, de haut en bas : **en-tête** (`mermaid` +
« Terminé ») → **aperçu** → filet `dividerColor` → **source** avec sa gouttière de
numéros de ligne. L'en-tête, désormais en haut d'un cadre nettement plus haut,
cesse mécaniquement d'avoir l'air de coiffer la carte du dessus.

Trois raccords :

1. **`StyleRenderer.applyOpenMermaidGeometry`** reçoit la taille de l'image et
   réserve `paragraphSpacingBefore = headerHeight + previewHeight + bodyTopPadding`.
   La taille est déjà sous la main dans la branche « bloc ouvert » de
   `applyMermaidAttachment`, qui repose l'attachment existant tel quel ; la
   largeur du conteneur se lit sur le même chemin que la sélection courante
   (`storage.layoutManagers.first?.firstTextView?.textContainer?.size.width`,
   dans le `MainActor.assumeIsolated` déjà présent), avec repli sur
   `MermaidBlockLayout.columnWidth` si aucune vue n'est attachée — le cas des
   tests, qui doivent pouvoir exercer la fonction sans vue vivante.
   C'est le **même levier** qu'aujourd'hui pour l'en-tête : toujours pas de
   `minimumLineHeight` gonflé sur la première ligne, donc toujours pas de curseur
   vertical surdimensionné (défaut déjà corrigé, à ne pas réintroduire).
2. **`headerRect` / `frameRect` / `bodyRect`** se décalent de `previewHeight`.
3. **`MarkdownLayoutManager.drawOpenMermaidBackgrounds`** peint l'image dans
   `previewRect`, dans la passe fond où le cadre est déjà dessiné et clippé.

Aucun rendu n'est relancé pendant l'édition. L'image affichée est celle de la
dernière fermeture ; « Terminé » déclenche le rendu du source final, exactement
comme aujourd'hui.

### 3. Point de correction unique

`headerRect` gagne un paramètre `previewHeight`. Ses **trois** appelants le
calculent depuis le même attachment :

- le fond du cadre (`drawOpenMermaidBackgrounds`) ;
- le dessin de l'en-tête (`drawMermaidHeader`) ;
- le hit-test du bouton (`EditorTextView.mermaidDoneButtonRange`, via
  `doneButtonRect`, qui dérive de `headerRect`).

Deux valeurs divergentes remettraient le bouton « Terminé » hors de sa zone
cliquable. C'est le même principe que `TableControlLayout.placementForCursor` :
un seul calcul partagé dessin/hit-test, jamais deux qui pourraient dériver.

---

## Tests

| Suite | Ajouts |
|---|---|
| `MermaidSourceLayoutTests` | `previewHeight` : `nil` → 0, image haute → plafond 240, image basse → taille réelle ; `previewRect` centré sous l'en-tête ; `headerRect` / `doneButtonRect` / `frameRect` décalés du bon montant |
| `StyleRendererMermaidTests` | bloc ouvert **avec** image → `paragraphSpacingBefore == headerHeight + previewHeight + bodyTopPadding` ; **sans** image → valeur actuelle inchangée ; le rendu n'est toujours pas relancé à la frappe |
| `BlockGutterLayoutTests` | `isCardBlock` vrai pour mermaid / tableau / image / bloc de code, faux pour paragraphe / titre / liste |
| `StyleRendererBlockSpacingTests` (nouvelle) | les quatre voisinages du tableau ci-dessus, plus le dernier bloc du document |

Vérification standard du dépôt : `swift test --skip CalendarImportEventTests`.

**Vérification à l'écran obligatoire** — la géométrie TextKit ne se juge pas en
test unitaire. Scénario : un document avec deux blocs mermaid rendus encadrant un
troisième ouvert, plus un bloc mermaid en tout début de document.

---

## Risques

1. **`paragraphSpacingBefore` passe de 43 à ~295 pt.** `drawMermaidHeader`
   élargit déjà temporairement son clip à toute la hauteur de la vue, sans quoi
   l'en-tête du bloc suivant disparaît derrière le cadre du précédent. L'aperçu
   est peint dans la passe **fond**, dont le clip est différent : il lui faut le
   même élargissement.
2. **Bloc mermaid en tout début de document.** `paragraphSpacingBefore` porte
   alors sur le premier paragraphe du conteneur. TextKit 1 l'honore aujourd'hui
   pour les 43 pt de l'en-tête, donc le levier tient — à confirmer à l'écran avec
   une bande beaucoup plus haute.
3. **Poignée de gouttière du bloc ouvert.** Elle se cale sur les rects de ligne,
   donc sur la première ligne de **source** : elle se retrouvera à côté du source
   et non en haut du cadre. Accepté pour cette PR, noté dans `STATUS.md`.

---

## Hors périmètre

- Rafraîchir l'aperçu pendant la frappe (debounce). Écarté : c'est le chemin qui
  a produit la superposition carte/source corrigée le 2026-08-08.
- Badge signalant que l'aperçu est figé. L'aperçu se met à jour à « Terminé » ;
  un indicateur supplémentaire encombrerait l'en-tête sans lever d'ambiguïté.
- Réaligner la poignée de gouttière sur le haut du cadre d'un bloc ouvert
  (risque 3).
- Toute modification du parseur, du sérialiseur ou du stockage : ce chantier ne
  touche que des attributs d'affichage et du dessin, comme le reste de
  `StyleRenderer` et de `MarkdownLayoutManager`.
