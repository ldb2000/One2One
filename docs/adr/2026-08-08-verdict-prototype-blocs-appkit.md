# Verdict — une vue éditable par bloc tient-elle en AppKit ?

**Statut** : en attente
**Date** : 2026-08-08
**Prototype** : `Prototypes/BlockEditorProbe/` (jetable)
**Spec** : [`docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`](../superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md)
**Décision d'origine** : [`docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md`](2026-08-08-reecriture-editeur-architecture-appflowy.md)
**Journal de bord** : `.superpowers/sdd/2026-08-08-prototype-editeur-par-blocs/progress.md`
(non versionné — `.superpowers/` est dans `.gitignore` et peut disparaître à
tout moment ; les faits qu'il consignait sont reproduits en clair dans le
corps de cet ADR et résumés en annexe, « Relevés bruts »)

## Verdict

**En attente.** Aucune vérification à l'écran n'a eu lieu : personne n'a
lancé `swift run block-editor-probe`, ouvert la fenêtre de la sonde, ni
regardé un rendu. Tout ce que cet ADR affirme provient de trois sources
logicielles — les tests unitaires de `ProbeCore`, une sonde qui compile les
vraies sources de vue et les exerce sans ouvrir de fenêtre, et un harnais de
mesure d'échelle exécuté avec une fenêtre ouverte et mise au premier plan par
le programme lui-même (`activate(ignoringOtherApps:)`,
`makeKeyAndOrderFront`), mais jamais regardée par un humain. Aucun des quatre
critères, aucun des trois critères
d'abandon, n'a reçu sa preuve visuelle. Le verdict ne peut donc pas être
prononcé maintenant ; cet ADR consigne l'état des preuves et la liste de ce
qui manque.

### Ce qui manque exactement pour le prononcer

**Tâche 8 — fenêtre, pile de blocs, saisie native (7 points, aucun fait) :**
la fenêtre s'ouvre au premier plan, titrée, douze blocs espacés visibles ;
clic dans un bloc → curseur dans ce bloc seul ; frappe → le bloc grandit et
pousse les suivants ; `option-e` puis `e` → `é`, `option-i` puis `e` → `ê`
(point critique de la thèse même du prototype) ; redimensionnement → reflow ;
défilement → rien ne clignote ni ne se superpose ; ⌘Q ferme la sonde.

**Tâche 9 — sélection traversante (9 points, aucun fait) :** glissement
bloc 2 → bloc 5 (queue, blocs entiers, tête) ; **couleur du surlignage des
blocs non focalisés identique à celle du bloc focalisé — c'est le critère
d'abandon n°1** ; glissement inverse (5 → 2) ; arrêt propre au-delà du
dernier bloc ; ⇧→ franchissant en fin de bloc ; ⇧↓ franchissant en dernière
ligne ; ⇧←/⇧↑ symétriques ; ⌘A surlignant tout ; clic ailleurs → retour à un
curseur simple. S'ajoute, soulevé par la relecture et jamais vérifié : un
scintillement gris transitoire possible sur le bloc sous le curseur pendant
le glissement (`focusing: false` laisse le vrai premier répondant sur le
bloc de départ) — pourrait s'autocorriger au relâchement, non observé.

**Tâche 10 — édition destructive (10 points, aucun fait) :** ⌫ en tête
fusionne avec curseur à la jonction ; ⌫ interne n'affecte qu'un bloc ; ⌫ sur
un `é` composé l'efface entièrement ; ⏎ au milieu scinde ; ⏎ en fin crée un
bloc vide ; frappe sur sélection glissée 2→5 ne laisse qu'un bloc ; ⌫ sur la
même sélection ; ⌦ en fin remonte le bloc suivant ; curseur visible et bien
placé après chaque geste ; ⌘A puis ⌫ laisse un bloc vide éditable.

**Tâche 11 — copier-coller et undo (10 points, aucun fait) :** copie
multi-blocs collée dans TextEdit sur quatre lignes tronquées ; collage
multi-lignes scindant un bloc en trois ; ⌘X réel au clavier (rendu possible
seulement depuis le correctif de l'item de menu manquant) ; **undo global
dans l'ordre des modifications et non du focus, au clavier réel — c'est le
critère d'abandon n°2** ; undo d'une fusion ; undo d'un collage ; rétablir ;
la frappe après ⌘Z vide le rétablissement ; nombre de ⌘Z nécessaires pour
défaire un accent composé par touche morte (observation, pas un défaut) ;
absence d'annulation bloc par bloc.

**Tâche 12 — tenue à l'échelle (5 points du Step 3 du brief, aucun fait) :**
ouverture à 200 blocs, défilement, frappe, ⌘A et glissement de sélection
pendant un défilement, tous observés à l'œil. S'ajoute la confirmation du
plancher de la mesure de frappe (voir plus bas).

Tant que ces contrôles n'ont pas été faits, tout énoncé de type « tient » ou
« ne tient pas » serait une extrapolation, pas un verdict.

## Les quatre critères

### 1. Sélection traversante

**Établi** (sonde sans fenêtre, tâche 9) : le
calcul et la répartition de la sélection traversante sur des `NSTextView`
indépendantes fonctionnent — glissement bloc 1 (offset 3) → bloc 3 (offset
4) donne la queue du premier bloc (3+14 caractères), les blocs intermédiaires
entiers (0+9), le bloc focalisé garde une sélection native vide et
`crossBlockSelection = nil`, les blocs hors sélection restent vierges ; ⌘A
couvre tous les blocs non focalisés en entier ; ⇧→ en fin de bloc franchit
vers le bloc suivant (interceptée = true) et rend la main au natif au milieu
d'un bloc (interceptée = false) ; ⇧← symétrique ; une frappe sur une
sélection traversante de 5 blocs → 3 avec le texte et le curseur attendus,
vues nettoyées. Un défaut critique (`moveDownAndModifySelection` sans garde
de borne, inversant la sélection en fin de dernier bloc) a été trouvé par
relecture, confirmé par mesure, et corrigé (commit `1655cae`).

**Non établi — le rendu** : le surlignage des blocs non focalisés est peint
à la main (`BlockTextView.drawBackground`, avec `NSColor.selectedTextBackgroundColor`),
précisément pour contourner le grisement natif au perte de focus. Que ce
surlignage soit **visuellement identique** à celui que peint nativement
`NSTextView` sur le bloc focalisé n'a jamais été regardé à l'écran. Ne pas
confondre : l'état se calcule et se répartit correctement (mesuré), le rendu
peint est une question distincte, entièrement ouverte.

### 2. Édition destructive

**Établi** (sonde sans fenêtre, tâche 10) :
⌫ en tête de bloc fusionne ; ⌫ au milieu reste natif ; ⌫ sur une sélection
mono-bloc reste native ; ⌦ en fin de bloc médian fusionne ; ⏎ scinde ;
frappe sur sélection traversante rend `natif = false`(*), donc
`interceptée = true`, et produit `["UXois"]` dans le scénario mesuré ; frappe mono-bloc reste native
(la voie des accents est donc atteinte) ; un geste structurant = un seul
instantané d'undo. Deux défauts trouvés par relecture et corrigés
(commit `dbf561e`) : `replacementString ?? ""` confondait un changement
d'attributs seuls (`nil`) avec un remplacement par la chaîne vide, ce qui
aurait effacé une sélection multi-blocs sans qu'aucun texte n'ait changé ;
des instantanés d'undo fantômes s'empilaient sur des gestes inertes en bord
de document (⌫ en tout début, ⌦ en toute fin).

(*) Le journal note ce résultat sans détailler la sélection d'origine ; il
est recopié tel quel, sans reconstitution du scénario.

**Non établi** : les 10 points de contrôle à l'écran listés plus haut —
notamment le comportement visuel du curseur après chaque geste et l'effet
réel de l'effacement d'un caractère composé par touche morte.

### 3. Copier-coller et undo

**Établi** (mesure directe des méthodes du coordinateur, sans fenêtre,
tâche 11) : trois frappes dans les blocs 1, 3,
0 (dans cet ordre) se défont par ⌘Z dans l'ordre inverse des
**modifications** (0, puis 3, puis 1) et non de l'ordre de visite —
l'historique est donc unifiable au niveau du conteneur. Redo correct ; une
frappe après ⌘Z vide la pile de rétablissement. Presse-papiers : copie
multi-blocs sérialisée en `"n\nDeux\nTr"` (exemple du journal, recopié tel
quel) ; collage multi-lignes → un bloc par ligne, curseur `(2,1)` ; un
collage = un seul ⌘Z ; ⌘X = un seul instantané ; ⌘C sans sélection ne vide
pas le presse-papiers ; collage non textuel = no-op sans entrée d'historique.
Un défaut Important trouvé par relecture — `ProbeMenu` n'avait aucun item
« Couper », donc ⌘X n'atteignait jamais `cut(_:)` au clavier bien que le code
de coupe lui-même soit correct — a été corrigé (commit `7eeaed4`).

**Non établi** : ces mesures passent par un appel **direct** aux méthodes du
coordinateur, pas par le vrai routage clavier/menu via la chaîne des
répondants. Le sélecteur `undo:`/`redo:` a été vérifié séparément par égalité
de `Selector`, hors fenêtre — pas par un ⌘Z réellement pressé. Reste
également à observer : le nombre de ⌘Z nécessaires pour défaire un accent
composé par touche morte (aucune fusion des frappes consécutives dans
l'historique — voir « Limites assumées »).

### 4. Tenue à l'échelle

**Établi** (harnais de mesure, fenêtre ouverte non observée par un humain,
tâche 12) : voir le tableau ci-dessous. 200
blocs vivants ne s'effondrent pas ; la question du recyclage ne se pose pas
à cette échelle.

**Non établi** : les 5 contrôles à l'œil du Step 3 (tâche 12) — ouverture à
200 blocs, défilement, frappe, ⌘A, glissement de sélection pendant un
défilement — et la confirmation que la mesure de frappe ne sous-compte pas
l'affichage des blocs sous le bloc frappé (voir la troisième nuance
ci-dessous).

## Les trois critères d'abandon

| # | Critère | État | Preuve |
|---|---|---|---|
| 1 | Le surlignage d'une sélection traversante ne peut pas être rendu correctement sans réécrire le dessin du texte | **Indéterminé** | La mécanique de calcul/répartition fonctionne (mesurée) et le mécanisme retenu (`drawBackground` peignant un fond, sans toucher au dessin des glyphes) ne constitue pas, par construction, une réécriture du dessin du texte. Mais personne n'a regardé si le résultat peint est correct — le critère ne peut donc pas être déclaré non atteint avec certitude, seulement jugé plausible. |
| 2 | L'undo ne peut pas être unifié au niveau du conteneur | **Non atteint** | Mesuré directement (tâche 11) : trois frappes dans trois blocs différents s'annulent dans l'ordre des modifications, pas du focus, jusqu'au document initial. L'undo est unifiable. Réserve : mesuré par appel direct, pas par ⌘Z réellement pressé. |
| 3 | 200 blocs imposent le recyclage **et** le recyclage casse la sélection | **Non atteint** | Mesuré (tâche 12) : montage, défilement et frappe restent, à 200 blocs, largement sous le budget d'image de 16,7 ms. 200 blocs vivants n'imposent pas le recyclage ; la question de savoir si le recyclage casserait la sélection ne se pose donc pas. |

Deux des trois critères ont des mesures directes (n°2 et n°3, tous deux
« non atteint »). Le n°1 reste partiellement ouvert : son volet « état » est
mesuré et favorable, son volet « rendu » n'a jamais été regardé.

## Les mesures d'échelle

Mesures relevées par le contrôleur (build release, binaire lancé avec
garde-fou de temps ; macOS 26.5.1, Build 25F80) :

| | 50 blocs | 200 blocs | 400 blocs |
|---|---|---|---|
| Montage initial | 18,1 ms | 37,6 ms | 77,5 ms |
| Défilement médian | 0,02 ms | 0,05 ms | 0,08 ms |
| Défilement pire pas | 0,09 ms | 0,10 ms | 0,13 ms |
| Frappe médiane | 0,15 ms | 0,26 ms | 0,38 ms |
| Frappe 95e centile | 0,20 ms | 0,30 ms | 0,45 ms |
| Frappe pire cas | 5,80 ms | 3,38 ms | 7,66 ms |

**Quatre nuances, indissociables de ce tableau** (relevées à la relecture de
la tâche 12) :

1. **Le « pire cas » de frappe n'est pas un signal de tendance.** C'est un
   maximum sur 200 échantillons, dominé par un aberrant (5,80 ms à 50 blocs
   contre 3,38 ms à 200 — non monotone). Seules la médiane et le 95e
   centile doivent servir à juger la tendance ; le pire cas documente une
   gigue d'allocation ponctuelle, pas un mur d'échelle.
2. **Le montage n'est pas purement linéaire.** Il comporte un coût fixe
   d'environ 9-10 ms (premier usage du framework texte), non amorti à 50
   blocs. La formulation correcte est « fixe + ~0,19 ms/bloc », pas un
   simple ratio linéaire.
3. **Les chiffres de frappe sont un plancher, pas un plafond**, sur les
   échantillons contenant un retour à la ligne : `displayIfNeeded()` n'est
   forcé que sur la vue frappée, pas sur toute la pile ; si la frappe fait
   grandir ou rétrécir le bloc focalisé, les blocs situés dessous se
   déplacent (nouvelle frame posée par `layout()`) sans que leur
   ré-affichage à la nouvelle position soit forcé dans la fenêtre
   chronométrée. Le coût de disposition, lui, est capturé en entier.
4. **Chaque frappe native passe par `history.record`, donc par une copie
   complète du document.** `shouldChangeTextIn` enregistre un instantané
   avant de rendre la main au natif, y compris sur la voie mono-bloc ; le
   coût de cette copie croît en O(nombre de blocs) et est inclus dans la
   latence de frappe mesurée. C'est un coût propre à la sonde — un vrai
   éditeur à undo par transactions n'aurait pas ce coût — qui participe à la
   pente linéaire par ailleurs attribuée à la disposition.

Un tableau recopié sans ces quatre nuances serait trompeur.

## Les mesures faites sans fenêtre

Pour les tâches 8 à 11, une sonde distincte du prototype (compilée hors
dépôt, dans un scratchpad, jamais commitée) compile les **vraies** sources de
vue (`SelectionCoordinator`, `BlockStackView`, `BlockTextView`) contre
`ProbeCore` et les exerce en appelant directement leurs méthodes, sans
`NSApplication.run()` et donc sans fenêtre à l'écran.

**Ce qu'elle a permis d'établir** : l'état interne après une mutation — la
convergence de `layout()` en une seule passe, l'absence de vue orpheline
après suppression/scission, la réaffectation correcte des `blockIndex`, la
position exacte du curseur après `attach`/`apply`, le contenu et les
répartitions de `NSRange` d'une sélection traversante, le contenu du
document après fusion/scission/frappe, l'ordre des snapshots dans
`ProbeHistory`. Tout cela est vérifiable parce que ce sont des valeurs
Swift — des `String`, des `NSRange`, des index — lisibles par du code, sans
qu'aucun pixel n'ait besoin d'être peint.

**Ce qu'elle ne peut pas établir** : tout ce qui n'existe qu'au moment où
AppKit compose réellement une image — la couleur et l'exactitude visuelle du
surlignage peint (critère d'abandon n°1, volet rendu), le clignotement ou la
superposition pendant un défilement, le scintillement transitoire suspecté
pendant un glissement de souris, la composition réelle des touches mortes
par le sous-système de saisie du système (option-i puis e → ê, jamais
simulable par un appel de méthode), et le routage effectif d'un événement
clavier ou d'un clic de menu réel à travers la chaîne des répondants
AppKit — la sonde appelle les méthodes du coordinateur directement, ce qui
prouve que le code fait ce qu'il doit **une fois atteint**, jamais qu'il est
**atteint** par le geste réel de l'utilisateur. C'est exactement la
distinction que porte la mesure de la tâche 11 sur `undo:`/`redo:` : l'égalité
de `Selector` est vérifiée, pas le déclenchement par un ⌘Z pressé.

## Pièges anticipés qui ne se sont pas matérialisés en obstacle

La spec anticipait trois risques nommément avant tout code :

1. **Le grisement natif de la sélection à la perte du focus** (mécanisme 1).
   Anticipé par la spec comme point pouvant, seul, invalider le verdict. Il
   n'a jamais donné lieu à un correctif après coup : dès la première version
   du code (tâche 9), `BlockTextView.drawBackground` peint lui-même le
   surlignage des blocs non focalisés, et vide leur sélection native pour
   éviter la bande grise d'inactivité. Le contournement anticipé était donc
   déjà dans le plan et a fonctionné du premier coup. Cela ne dit rien,
   en revanche, sur la fidélité visuelle du résultat peint (voir critère
   d'abandon n°1, volet rendu, toujours ouvert).
2. **L'`UndoManager` propre à chaque `NSTextView`** (mécanisme 3). Anticipé
   comme décisif pour savoir si l'undo explicite d'AppFlowy est
   transposable. Neutralisé dès la première ligne de code (tâche 8,
   `allowsUndo = false` dans `BlockTextView.init`) : aucune fragmentation de
   l'historique par bloc n'a jamais été observée, et la mesure de la tâche
   11 confirme que l'undo suit l'ordre des modifications, pas du focus.
3. **L'effondrement à 200 blocs vivants** (mécanisme 4, critère d'abandon
   n°3). La spec envisageait explicitement que 200 `NSTextView` puissent
   s'effondrer et posait la question du recyclage pour ce cas. Mesuré : ils
   ne s'effondrent pas (voir tableau ci-dessus), et jusqu'à 400 blocs les
   trois temps restent largement sous le budget d'image.

Aucun des trois n'a donné lieu à une ronde de correctif — contrairement aux
pièges non anticipés ci-dessous, tous trouvés après coup par relecture.

## Pièges non anticipés, réellement rencontrés

1. **La garde de synchronisation ne couvrait pas `reload(document:)`**
   (tâche 8). `isSynchronising` n'était levée qu'à l'intérieur de
   `synchroniseViews`, alors que `attach` et `apply` appellent
   `stack.reload(document:)` — qui écrit `.string` directement sur les vues
   — **avant** `synchroniseViews`. Toute écriture de `.string` pendant ce
   court intervalle déclenchait `textViewDidChangeSelection` sans garde, qui
   écrasait la sélection avec celle du **dernier** bloc écrit. Trouvé par
   relecture, confirmé par mesure : après `attach`, le curseur se retrouvait
   en `(bloc 7, offset 68)` au lieu de `(0,0)` ; après `apply(⏎ bloc 2)`, en
   `(bloc 3, offset 68)` au lieu de `(3,0)`. Coût : corrompt le curseur après
   **toute** mutation structurante, ce qui bloquait les tâches 9 à 11
   (toutes passent par `apply`). Corrigé (commit `d174321`) par une garde
   réentrante (`whileSynchronising`, restaurant la valeur précédente plutôt
   que `false` en dur).
2. **`moveDownAndModifySelection` sans garde de borne** (tâche 9), asymétrique
   de `moveUp` qui en avait un. ⇧↓ en fin du dernier bloc inversait la
   sélection et surlignait tout le bloc au lieu de ne rien faire. Trouvé par
   relecture, confirmé par mesure. Corrigé (commit `1655cae`).
3. **`replacementString ?? ""` confondait attributs seuls et chaîne vide**
   (tâche 10). Un changement d'attributs sans changement de texte
   (`replacementString == nil`) était traduit en « remplacer la sélection
   par rien », donc effacerait destructivement une sélection multi-blocs
   sans qu'aucun texte n'ait changé — peu probable avec `isRichText = false`
   mais destructeur si atteint. Trouvé par relecture. Corrigé (commit
   `dbf561e`), batché avec le suivant.
4. **Instantanés d'undo fantômes en bord de document** (tâche 10). ⌫ en tout
   début de document et ⌦ en toute fin renvoyaient `interceptée = true` et
   passaient par `apply`, qui enregistre l'état précédent inconditionnellement
   — alors que la mutation ne changeait rien. N ⌫ en tête de document
   empilaient N entrées d'undo inertes. Trouvé à la fois par mesure directe
   (sonde sans fenêtre) et par relecture. Ne menaçait pas le critère
   d'abandon n°2 (cosmétique pour une sonde jetable). Corrigé dans le même
   commit que le point 3, sur le modèle de la garde de borne du point 2.
5. **`ProbeMenu` sans item « Couper »** (tâche 11, code écrit à la tâche 8).
   Sans item de menu portant le sélecteur `cut:` et le raccourci `x`, ⌘X
   n'atteignait jamais `BlockTextView.cut(_:)` au clavier, bien que le code
   de coupe lui-même soit correct (mesuré). Trouvé par relecture du code de
   `ProbeMenu.swift`. Corrigé (commit `7eeaed4`).
6. **Propriété d'architecture, pas un bug : chaque frappe déclenche déjà une
   disposition sur tous les blocs.** Relevé à la relecture de la tâche 12 :
   `SelectionCoordinator.textDidChange` force `stack.layoutSubtreeIfNeeded()`
   à **chaque** frappe, et `BlockStackView.layout()` recalcule la frame de
   **tous** les blocs, pas seulement de celui qui a changé. Ce n'est pas un
   défaut à corriger — c'est une conséquence directe du choix « une pile de
   vues empilées, dimensionnée à la main, sans Auto Layout » — mais cela
   signifie que le déclencheur artificiel du harnais (« une frappe sur
   quarante force une disposition ») est du code mort : la disposition
   complète a déjà eu lieu avant qu'il n'intervienne. À retenir pour les
   points 4 et 5 de la réécriture : le coût de disposition par frappe croît
   avec le nombre total de blocs, pas avec la taille du bloc édité, et rien
   ici n'a mesuré ce coût sur des vues de bloc plus lourdes qu'un
   `NSTextView` de texte simple (carte mermaid, tableau).

## Limites assumées du prototype

Ces limites sont des choix délibérés, documentés dans le code ou le journal,
pas des défauts en attente de correction :

- **Double-clic, triple-clic et clic-⇧ perdus.**
  `BlockTextView.mouseDown(with:)` n'appelle pas `super` et ignore
  `event.clickCount`/`event.modifierFlags` : seul le clic simple de
  positionnement est traité par le coordinateur. Le mot (double-clic), le
  paragraphe (triple-clic) et l'extension par clic-⇧ sont perdus.
- **Extension verticale imprécise.** Dès que la sélection déborde déjà d'un
  bloc, ⇧↓/⇧↑ saute au bloc entier suivant/précédent sans vérifier que la
  tête est réellement sur la dernière/première ligne du bloc courant — sur
  un bloc multi-lignes, cela peut sauter des lignes intermédiaires.
  L'extension horizontale ⇧←/⇧→ reste précise caractère par caractère.
- **Aucune fusion des frappes consécutives dans l'undo.** Chaque appel à
  `shouldChangeTextIn` — donc chaque caractère, y compris chaque étape de
  composition d'un accent par touche morte — enregistre son propre
  instantané. Un ⌘Z ne défait qu'un caractère (ou qu'une étape de
  composition), jamais une séquence de frappe complète. Choix assumé dès la
  tâche 7 : « un ⌘Z par caractère suffit à prouver que l'undo est global »,
  la fusion étant qualifiée de raffinement, pas de preuve nécessaire au
  verdict.
- **Pas d'auto-défilement pendant le glissement.** La lecture du code de
  `beginSelectionDrag` (`SelectionCoordinator.swift`) ne montre aucun
  mécanisme qui ferait défiler la pile quand le pointeur sort de la zone
  visible pendant un glissement de sélection ; le défilement vers le bloc
  focalisé n'a lieu qu'au relâchement, via `synchroniseViews(focusing: true)`.
  Ce constat vient de la lecture du code, pas d'une observation à l'écran.
- **`pasteFromPasteboard` ne distingue pas un presse-papiers absent d'une
  chaîne vide.** `NSPasteboard.general.string(forType: .string)` rend `nil`
  quand il n'y a rien à coller — la garde sort alors sans rien faire — mais
  rend une chaîne vide (`""`, non `nil`) quand le presse-papiers contient
  explicitement une chaîne vide : la garde passe, et `apply` empile un
  instantané d'historique sans aucun effet visible — un ⌘Z inerte de plus. Un
  presse-papiers **non textuel**, lui, est correctement traité en no-op —
  c'est mesuré (tâche 11).

## Ce que cela implique pour les points 1 à 8 de la réécriture

Le prototype a sondé exclusivement le point 5 (« édition de texte inline
avec une vue éditable par bloc »), avec un modèle volontairement pauvre — une
liste plate de blocs texte homogènes, tous du même type de vue. Cela borne
strictement ce qu'il est permis d'en tirer.

- **Point 5 (le risque central lui-même).** Les preuves d'état sont
  encourageantes pour les trois mécanismes mesurés (sélection, édition
  destructive, undo/copier-coller), et le critère d'abandon n°3 (échelle)
  est mesuré non atteint. Mais l'implémentation réelle du point 5 devra
  résoudre des cas que ce prototype a **explicitement abandonnés** plutôt
  que résolus : double-clic, triple-clic, clic-⇧, extension verticale
  précise, auto-défilement au glissement. Ce ne sont pas des inconnues du
  risque central — ce sont des travaux connus qu'il faudra faire, et que le
  prototype n'a pas chiffrés.
- **Points 1 à 3 (modèle en arbre, transactions, `EditorState`).** Le
  prototype ne prouve rien sur eux, par construction : la spec l'interdisait
  explicitement (« le prototype ne prouve rien sur le modèle de document »).
  `ProbeDocument` est une liste plate de `ProbeBlock { id, text }`, sans
  arbre de nœuds, sans `Delta`, sans chemins. Le seul point transposable est
  plus modeste que « les transactions fonctionnent » : c'est que **l'undo
  par instantané complet, unifié au-dessus des vues et indépendant de leurs
  `UndoManager`, est un principe qui fonctionne** (mesuré, critère d'abandon
  n°2 non atteint). Cela ne dit rien sur la granularité d'une transaction
  AppFlowy réelle (opérations sur un arbre, pas snapshots de document
  entier), ni sur son coût de fusion à la frappe — voir la limite assumée
  ci-dessus sur l'absence de fusion des frappes, dont le coût réel pour le
  point 2 reste à observer (tâche 11, point 9 du contrôle à l'écran).
- **Point 4 (rendu par bloc, registre de constructeurs de vues).** Non
  sondé : le prototype n'utilise qu'un seul type de vue (`BlockTextView`)
  pour tous les blocs. Aucune sélection traversant des vues de types
  **différents** — un bloc texte vers une carte mermaid vers un tableau — n'a
  jamais été construite ni mesurée. C'est pourtant l'un des points les plus
  incertains d'un registre hétérogène : rien ici ne dit si le mécanisme de
  répartition de sélection du coordinateur (pensé pour des `NSTextView`
  uniformes) survit face à des vues qui ne sont pas du texte.
- **Point 6 (aller-retour Markdown).** Non sondé : les blocs de la sonde
  sont du texte brut, jamais du Markdown.
- **Point 7 (parité fonctionnelle — 17 commandes `/`, listes, tableaux,
  mermaid, images, mentions, dates, liens, cases à cocher).** Non sondé,
  hors périmètre explicite de la spec.
- **Point 8 (réintégration des six consommateurs).** Non sondé.
- **Note transverse (architecture) pour les points 4 et 5.** Le fait établi
  que chaque frappe déclenche déjà une disposition complète sur tous les
  blocs (piège non anticipé n°6 ci-dessus) mérite d'être surveillé quand les
  vues de bloc ne seront plus de simples `NSTextView` de texte : une carte
  mermaid ou un tableau coûtent plus cher à disposer qu'un paragraphe. Rien
  dans ce prototype ne mesure ce cas — toutes les mesures d'échelle portent
  sur des blocs de texte uniquement.

## Sort du prototype

Le code de `Prototypes/BlockEditorProbe/` doit être supprimé une fois le
verdict prononcé, conformément à la spec (« le code du prototype peut être
supprimé une fois l'ADR écrit »). Il n'est **pas** supprimé à la date de cet
ADR, puisque le verdict lui-même est en attente : le supprimer maintenant
détruirait la seule sonde permettant de rejouer une mesure sans fenêtre si
la vérification à l'écran soulevait un doute nécessitant un nouveau contrôle
de code.

## Annexe — Relevés bruts

Le journal d'exécution qui a servi à consigner les mesures de ce prototype
au moment où elles ont été prises
(`.superpowers/sdd/2026-08-08-prototype-editeur-par-blocs/progress.md`)
**n'est pas versionné** : `.superpowers/` figure dans `.gitignore` et peut
disparaître sans préavis. Cet ADR ne le cite donc plus par numéro de ligne
ailleurs dans le corps du document ; cette annexe reproduit, pour qu'ils
restent lisibles et vérifiables une fois `Prototypes/` supprimé et
`.superpowers/` absent, les deux relevés bruts déjà présentés plus haut.

### Tableau des mesures d'échelle (50 / 200 / 400 blocs)

Reprise à l'identique du tableau de la section « Les mesures d'échelle » ;
les quatre nuances qui l'accompagnent dans cette section (pire cas non
représentatif, montage non linéaire, chiffres de frappe en plancher, coût de
`history.record` inclus dans la latence) s'y appliquent également et ne sont
pas répétées ici.

| | 50 blocs | 200 blocs | 400 blocs |
|---|---|---|---|
| Montage initial | 18,1 ms | 37,6 ms | 77,5 ms |
| Défilement médian | 0,02 ms | 0,05 ms | 0,08 ms |
| Défilement pire pas | 0,09 ms | 0,10 ms | 0,13 ms |
| Frappe médiane | 0,15 ms | 0,26 ms | 0,38 ms |
| Frappe 95e centile | 0,20 ms | 0,30 ms | 0,45 ms |
| Frappe pire cas | 5,80 ms | 3,38 ms | 7,66 ms |

### Liste des mesures faites sans fenêtre (tâches 8 à 11)

Reprise à l'identique du paragraphe « Ce qu'elle a permis d'établir » de la
section « Les mesures faites sans fenêtre ». Ce qu'une sonde distincte du
prototype — compilant les vraies sources de vue (`SelectionCoordinator`,
`BlockStackView`, `BlockTextView`) contre `ProbeCore` et les exerçant en
appelant directement leurs méthodes, sans `NSApplication.run()` — a permis
d'établir :

- l'état interne après une mutation ;
- la convergence de `layout()` en une seule passe ;
- l'absence de vue orpheline après suppression/scission ;
- la réaffectation correcte des `blockIndex` ;
- la position exacte du curseur après `attach`/`apply` ;
- le contenu et les répartitions de `NSRange` d'une sélection traversante ;
- le contenu du document après fusion/scission/frappe ;
- l'ordre des snapshots dans `ProbeHistory`.

Tout cela est vérifiable parce que ce sont des valeurs Swift — des `String`,
des `NSRange`, des index — lisibles par du code, sans qu'aucun pixel n'ait eu
besoin d'être peint. Ce que cette même sonde ne peut pas établir reste décrit
dans le corps du document, section « Les mesures faites sans fenêtre ».
