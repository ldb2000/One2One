# Prototype d'éditeur par blocs — sonder le risque central avant la réécriture

**Date** : 2026-08-08
**Décision d'origine** : réécrire l'éditeur Markdown en reprenant l'architecture
d'[appflowy-editor](https://github.com/AppFlowy-IO/appflowy-editor), AGPL-3.0
acceptée par l'auteur du dépôt.
**Portée de cette spec** : le **premier** sous-projet seulement — un prototype
jetable qui répond par oui ou non à une question, et rien d'autre.

---

## Pourquoi un prototype avant la réécriture

Trois chantiers successifs ont porté sur le rendu des blocs mermaid dans
l'éditeur actuel — superposition carte/source, géométrie du cadre, ancrage sur le
mauvais repère TextKit. Chaque correctif était juste, mesuré et relu ; le
résultat restait décevant. Le point commun de ces trois défauts n'est pas une
erreur de programmation : c'est que **les blocs sont simulés à l'intérieur d'un
seul `NSTextView`**. Espacements de paragraphe détournés pour réserver de la
place, rect de fragment confondu avec rect de texte, dessin qui déborde sur le
bloc voisin, clips à élargir à la main — cette classe de bug n'existe que là.

AppFlowy n'a aucun de ces problèmes parce que chaque bloc y est une vue autonome.
D'où la décision de réécrire.

### Ce que la réécriture contient réellement

L'existant : **12 365 lignes sur 45 fichiers**, 41 fichiers de tests, et six
consommateurs hors du module (`MeetingView`, `DetailsViews`, `PrepWindow`,
`MarkdownNoteEditor`, `EditableTextField`, `CollaboratorMentionSource`).

Dans l'ordre des dépendances :

1. modèle de document — arbre de nœuds, `Delta` pour le texte inline, chemins ;
2. transactions et undo explicites ;
3. `EditorState` — document, sélection, service de transactions ;
4. rendu par bloc — registre de constructeurs, une vue par type ;
5. **édition de texte inline avec une vue éditable par bloc** ;
6. aller-retour Markdown ;
7. parité fonctionnelle : 17 commandes `/`, listes, tableaux, mermaid, images,
   mentions, dates, liens, cases à cocher ;
8. réintégration des six consommateurs.

Chaque point aura sa propre spec.

### Le risque central est le point 5, et il est solitaire

AppFlowy hérite gratuitement de Flutter la sélection et la navigation du curseur
**à travers** les blocs. En AppKit, une vue éditable par bloc oblige à
reconstruire soi-même la sélection traversante, l'extension au clavier, la fusion
par ⌫, ⌘A et le copier-coller multi-blocs. `NSTextView` ne coopère pas entre
instances.

**Conséquence à assumer** : sur ce point précis, appflowy-editor n'a presque rien
à nous apprendre et il n'existe aucun code à transposer. La partie qui décide de
la viabilité de toute la réécriture est aussi celle où l'on est seuls. La reprise
d'architecture — et la bascule AGPL qu'elle entraîne — ne devient utile qu'aux
points 1 à 3.

C'est pourquoi ce prototype existe : obtenir un verdict en quelques jours plutôt
qu'en quelques mois.

---

## Décisions prises

| Question | Décision | Pourquoi |
|---|---|---|
| Par où commencer | Prototype du risque central (point 5) | Verdict tranché en quelques jours ; les autres points sont sûrs mais ne prouvent rien |
| Technologie du bloc de texte | **Un `NSTextView` par bloc** | Donne gratuitement la saisie des accents, les touches mortes, le correcteur et les services macOS. Les réécrire serait un chantier à soi seul, et en français le défaut se verrait au premier `ê` |
| Ce que le prototype doit prouver | Les quatre critères : sélection, édition destructive, copier-coller et undo, tenue à l'échelle | Chacun peut invalider l'approche seul |
| Hébergement | Cible SwiftPM séparée | Aucun couplage à l'app, aucun risque pour l'éditeur actuel, se supprime en un commit |
| Bascule de licence | ADR daté maintenant, fichier de licence changé plus tard | Ce prototype ne contient aucune ligne dérivée d'AppFlowy ; la bascule devient effective au point 1 |

---

## Conception

### Forme et périmètre

`Prototypes/BlockEditorProbe/`, exécutable SwiftPM `block-editor-probe` ouvrant
sa propre fenêtre via un `NSApplication` construit programmatiquement. **Rien du
module `OneToOne/Markdown/` n'est touché, importé ni modifié.**

Le modèle est volontairement pauvre : une **liste plate** de
`struct ProbeBlock { let id: UUID; var text: String }`. Pas d'arbre, pas de
`Delta`, pas de types de blocs. Le prototype ne prouve rien sur le modèle de
document — y mettre un modèle riche masquerait le vrai sujet derrière du travail
confortable.

**Hors périmètre, à ne pas ajouter** : markdown, types de blocs, images, tableaux,
mermaid, styles inline, commandes `/`, persistance, thème sombre, accessibilité.

### Trois composants

| Composant | Responsabilité | Testable sans vue |
|---|---|---|
| `ProbeDocument` | La liste de blocs et **toutes** ses mutations | oui |
| `SelectionCoordinator` | Bloc focalisé, ancre et tête de sélection ; reçoit les événements, décide, répartit | oui, pour le calcul de répartition |
| `BlockTextView` | Un `NSTextView` par bloc, empilés dans un `NSScrollView` | non |

L'autorité est entièrement dans le coordinateur. Les `NSTextView` ne décident de
rien : ils reflètent. C'est l'inverse exact de l'éditeur actuel, où la vue porte
la logique.

### Les quatre mécanismes

**1. Sélection traversante.** Le coordinateur pose l'ancre au `mouseDown`, suit le
glissement au niveau du conteneur, puis attribue à chaque bloc sa part : entière
pour les intermédiaires, partielle pour les extrêmes. ⇧↓ et ⇧→ transfèrent au
bloc suivant quand le mouvement dépasse la borne. ⌘A prend tout.

> **Piège attendu** : `NSTextView` grise sa sélection dès qu'il perd le focus, or
> un seul bloc peut l'avoir. Il faudra forcer `selectedTextAttributes` ou peindre
> le surlignage soi-même. Si ce point seul résiste, le verdict est déjà négatif.

**2. Édition destructive.** ⌫ en tête de bloc fusionne avec le précédent ; ⏎ au
milieu scinde ; la frappe sur une sélection multi-blocs supprime puis insère. Les
trois passent par une **unique** fonction de mutation de `ProbeDocument`, jamais
par les `NSTextView`.

**3. Copier-coller et undo.** La copie sérialise la sélection multi-blocs dans le
pasteboard ; le collage insère en scindant le bloc courant.

> **Piège attendu** : chaque `NSTextView` a son propre `UndoManager`, donc ⌘Z
> annulerait bloc par bloc. Il faut les désactiver et enregistrer l'inverse au
> niveau du conteneur. C'est ce point qui décide si l'undo explicite d'AppFlowy
> est transposable.

**4. Tenue à l'échelle.** 200 blocs, trois mesures : montage initial, fluidité au
défilement, latence de frappe. Si 200 `NSTextView` vivants s'effondrent, le
prototype doit dire si le recyclage — vraies vues éditables pour le visible et le
focalisé, texte dessiné pour le reste — suffit à sauver l'approche.

---

## Tests

`ProbeDocument` et le calcul de répartition du coordinateur sont des unités
pures : à partir d'un document et d'une sélection multi-blocs, quel document
produisent ⌫, ⏎, la frappe et le collage. Ceux-là ont de vrais tests unitaires.

Les gestes eux-mêmes se vérifient **à la main dans la fenêtre**. Automatiser un
glisser-souris AppKit coûterait plus cher que le prototype entier, et ce
prototype existe pour donner un verdict vite.

---

## Livrable

**Le livrable n'est pas le code : c'est un ADR** dans `docs/adr/`, qui énonce :

- tient / ne tient pas ;
- les trois mesures d'échelle réellement relevées ;
- les pièges réellement rencontrés — pas ceux anticipés dans cette spec ;
- ce qu'ils impliquent pour les points 1 à 8.

Le code du prototype peut être supprimé une fois l'ADR écrit.

Un second ADR, distinct, consigne et date la décision de licence : réécriture en
reprenant l'architecture d'appflowy-editor, AGPL-3.0 acceptée. Il annule les
décisions n°1 (« le markdown reste la source de vérité, aucun modèle de blocs »),
n°2 (« TextKit 1 est conservé ») et n°4 (« aucun code AppFlowy n'est repris ») de
`STATUS.md`. Le fichier de licence du dépôt n'est **pas** modifié à ce stade : ce
prototype ne contient aucune ligne dérivée, la bascule devient effective au
point 1.

---

## Critère d'abandon

Fixé maintenant, pour ne pas être rationalisé après coup. On déclare « ne tient
pas » si **l'un** de ces trois se vérifie :

1. le surlignage d'une sélection traversante ne peut pas être rendu correctement
   sans réécrire le dessin du texte ;
2. l'undo ne peut pas être unifié au niveau du conteneur ;
3. 200 blocs imposent le recyclage **et** le recyclage casse la sélection.

**Limite de temps : trois sessions de travail.** Au-delà, on tranche avec ce
qu'on a plutôt que de s'acharner.

## Ce qu'on fait du verdict

- **Tient** → on enchaîne sur les points 1 à 3 (modèle, transactions, undo), là
  où appflowy-editor est réellement transposable, chacun avec sa spec.
- **Ne tient pas** → repli sur la sortie des blocs mermaid, tableaux et images du
  flux TextKit en vraies `NSView` ancrées. Cela supprime la classe de bug des
  trois derniers chantiers sans réécriture, et reste un pas vers l'architecture
  par blocs plutôt qu'un détour.

Dans les deux cas, l'éditeur actuel n'est pas touché : la branche
`feat/editeur-slash-blocs` garde ses 16 commits et l'application continue de
fonctionner.
