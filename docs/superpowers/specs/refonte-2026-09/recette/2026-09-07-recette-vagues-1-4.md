# Recette visuelle des vagues 1 à 4 — écrans 1a, 1b, 1c, 3a, 3b

Faite le 2026-09-07 (soir) et le 2026-09-08, depuis
`fix/refonte-recette-vagues-1-4`, au sommet de la pile linéaire
(`#19 → … → #31`). Écrans livrés par les lots 1 à 6, 9 et 10 ; les écrans
2a/2b/5a/5b (lots 11–14), 4a/4b (lots 7–8) et 6a/6b (lots 16–18) ne sont pas
livrés et sont hors périmètre.

Références : `../ecrans/{1a-cockpit,1b-mode-seance,1c-poste-de-pilotage,3a-tiroir-ressources,3b-fiche-projet}.png`.
Spec : `../specs-one2one.md` §1.2, §2, §4. Plan : `../../../plans/2026-09-07-refonte-reunion-programme.md` §1, §4, §7.

## Conditions et protocole

| Point | Constat |
| --- | --- |
| Bundle | `swift build -c release` puis `Scripts/recette-app.sh` — **release empaqueté**, fontes Plex et `default.metallib` embarqués. |
| Store | `Scripts/recette-run.sh` puis un lanceur détaché équivalent, `HOME` **et** `CFFIXED_USER_HOME` jetables. Isolation vérifiée à chaque lancement par `lsof -p <pid> \| grep OneToOne.store` : le seul store ouvert est celui du home jetable, **zéro descripteur** sur `~/Library/Application Support/OneToOne`. Le store de production n'a jamais été ouvert. |
| Fenêtre | Fenêtre **dédiée** `1to1-meeting`, celle du correctif #31 — donc sans la barre latérale de l'application, contrairement à `lot-9-1280.png`. Redimensionnement par l'API Accessibility ciblée `AXUIElementCreateApplication(pid)`, capture par `screencapture -l <kCGWindowNumber> -x -o` sur les fenêtres filtrées `kCGWindowOwnerPID == <mon pid>`. **Aucun AppleScript** : `first application process whose unix id is …` résout mal le processus quand deux instances partagent le `CFBundleIdentifier`, et c'est ainsi qu'une fenêtre de production a été redimensionnée par un autre agent. |
| Verrou d'écran | Déverrouillé pendant la série de captures (19 h 50 – 20 h 30). Verrouillé ensuite, ce qui a repoussé les recaptures d'après correction. |
| Teams | Aucune réunion en cours : la seule fenêtre du processus `MSTeams` portait « Calendar \| APRIL \| … », jamais un titre de réunion ou d'appel. |
| Instance de l'utilisateur | `OneToOne` pid 16538 (`.build/arm64-apple-macosx/release/OneToOne`, fenêtre « NPA/LDB »), jamais touchée : ni événement, ni redimensionnement, ni arrêt. **Elle a cependant été retrouvée en 0,33 / 1 720 × 1 024 alors qu'elle était en 40,40 / 1 542 × 800 au début de la session** — cf. §« Écarts (c) », point 7. |
| Jeu de données | `RefonteDemoSeed.seed` au démarrage (`--seed`), complété par l'item **Réunion ▸ Charger le jeu de démonstration (refonte)**, qui appelle `seedLot5` puis `seedLot6`. Aucune valeur du semis n'a été modifiée. |

### ⚠️ Le « 1 920 » n'est pas 1 920 pt

L'écran de ce poste mesure **1 728 × 1 117 pt** (3 456 × 2 234 px, Retina).
AppKit borne une fenêtre au cadre visible : une demande de 1 920 × 1 080 pt
ressort en **1 728 × 1 023 pt**. Un mode d'affichage à 2 056 × 1 285 pt existe
et aurait permis la mesure exacte, mais changer la résolution d'une session de
travail active — l'utilisateur y fait tourner sa propre instance — n'est pas
une décision à prendre seul (CLAUDE.md, règle 6).

Les fichiers `*-1920.png` sont donc pris **à la plus grande taille atteignable,
1 728 × 1 023 pt** (3 456 × 2 046 px). Les `*-1280.png` sont, eux, exactement
1 280 × 800 pt (2 560 × 1 600 px). Rien n'est faux ; la largeur réelle est
écrite ici pour ne pas laisser croire à une mesure qu'on n'a pas faite.

### Captures produites

| Fichier | Écran | Géométrie de la fenêtre | État |
| --- | --- | --- | --- |
| `1a-1280.png` | 1a cockpit, mode En séance | 1 280 × 800 pt | avant correction |
| `1a-1920.png` | 1a cockpit, mode En séance | 1 728 × 1 023 pt | avant correction |
| `1b-1920.png` | tentative de mode séance plein écran | 1 728 × 1 084 pt (plein écran) | **montre l'échec**, cf. (c) n° 1 |
| `1c-1280.png` | 1c poste de pilotage, mode Relire | 1 280 × 800 pt | avant correction |
| `1c-1920.png` | 1c poste de pilotage, mode Relire | 1 728 × 1 023 pt | avant correction |
| `3a-1280.png` | 3a tiroir Ressources + « À l'écran » | 1 280 × 800 pt | avant correction |
| `3a-1920.png` | 3a tiroir Ressources + « À l'écran » | 1 728 × 1 023 pt | avant correction |
| `3b-1920.png` | 3b fiche projet en panneau, lecture | 1 728 × 1 023 pt | avant correction |
| `3b-edition-1920.png` | 3b fiche projet, **mode Édition** | 1 728 × 1 023 pt | avant correction — **jamais vu jusqu'ici** |
| `lot-9-1280.png` | 3b, recette du lot 9 (conservée) | 1 280 × 800 pt | fenêtre principale, barre latérale visible |

Toutes les captures livrées sont **antérieures aux corrections** : l'écran s'est
verrouillé avant que le binaire corrigé ne soit disponible. Elles valent donc
comme constat, pas comme démonstration du résultat. La recapture est la première
action de la reprise (§« Reste à faire »).

## Légende des verdicts

- **(a)** écart de finition, **corrigé dans cette branche** ;
- **(b)** écart déjà assumé dans `STATUS.md`, **confirmé visible**, non touché ;
- **(c)** écart fonctionnel hors finition, renvoyé au lot concerné ou au lot 19.

---

## Écran 1a — cockpit (`1a-cockpit.png`)

`recette/1a-1280.png`, `recette/1a-1920.png`. Espace Réunion, mode En séance,
fenêtre dédiée.

| Zone | Constat | Verdict |
| --- | --- | --- |
| Barre du haut — hauteur, fond, bordure | 38 px, `bg/app`, bordure basse `border/card` | conforme |
| Barre du haut — ordre des blocs | fil d'Ariane → titre → audio → *partage* → *capture* → type → template → Rapport → `⋯` | conforme à §2.1 pour les blocs prévus ; deux blocs en sus, cf. (b) n° 5 |
| Barre du haut — libellés | à 1 280 px, `Rapport ✓ 6:20` réduit à « R », `Capture` à « C », `● Partage actif · n voient` à un carré bleu : le titre (`maxWidth: .infinity` + `layoutPriority(1)`) gagnait l'arbitrage et comprimait les contrôles, alors que §2.1 fait du titre la colonne fluide | **(a) corrigé** — `controlsGroup` en `fixedSize(horizontal:)` |
| Barre du haut — pilule de partage | rayon `radiusButton` (6) là où §4.2 dit « pilule » et §1.2 donne 11 | **(a) corrigé** — `Capsule` |
| Barre du haut — titre de réunion | rendu dans un champ **bezelé** en fonte système, non en Plex Sans 600 13 : `EditableTextField` impose `NSFont.systemFont` et `bezelStyle = .roundedBezel`, et ignore le `.font` de l'environnement | **(c)** n° 3 |
| Barre du haut — bloc audio | remplacé par le badge « Audio archivé » et deux pastilles rondes : la réunion semée n'a pas de fichier audio. La pilule `▶ mm:ss / mm:ss` de la maquette n'est donc pas montrée | état de données, conforme au comportement |
| Barre d'espaces | 34 px, trois espaces, onglet actif souligné 2 px `accent/report`, sélecteur de mode puis date à droite | conforme |
| Barre d'espaces — compléments | `0 doc` / `4 docs` / `à générer` en 10,5 px `ink/muted`, sous le seuil de §1.2 | **(a) corrigé** — `ink/4` |
| Bandeau KPI — grille | 4 cartes, `gap` 10 | conforme |
| Bandeau KPI — hauteurs | la carte Présence dépassait ses trois voisines, là où §2.3 veut « 4 cartes égales » | **(a) corrigé** — `fixedSize` vertical + `maxHeight: .infinity` |
| Bandeau KPI — padding de carte | 10 horizontal / 12 vertical, axes inversés par rapport à « 10 × 12 » de §2.3 | **(a) corrigé** |
| Bandeau KPI — pile d'avatars | **six paires d'initiales sans pastille** : `AvatarStack` remplissait ses cercles avec `pill`, qui vaut `surface` (`#ffffff`) en thème clair, soit le fond même de la carte | **(a) corrigé** — fond `base` (`#f7f4ee`) |
| Bandeau KPI — initiales et ordre | `CA CP LD LS NL PY` | **(b)** n° 1 et n° 2 |
| Bandeau KPI — valeurs | `100 % 6/6`, `12 · 9 non assignées`, `3 dont 1 budget`, `5 · 2 critiques` | conforme |
| Bandeau KPI — points de risque | 5 points : rouge, rouge, orange, **bleu**, **gris** ; la maquette n'emploie que rouge et orange | **(c)** n° 6 |
| Bandeau KPI — ellipsis | « Le partenaire finalise lui-même la mi… » | conforme |
| Notes ↔ transcription — carte | une seule carte, `1fr \| 1px \| 1fr`, en-tête « Notes & transcription · synchronisées sur l'audio » | conforme |
| Notes ↔ transcription — bascule `Speakers` | absente : le semis ne pose pas de locuteur sur ses segments, la bascule se masque | **(c)** n° 5 |
| Colonne notes — recouvrement | à 1 280 px, la décision de 11:03 passait à la ligne et sa seconde ligne recouvrait la note de 15:20 | **(a) corrigé** — un seul `Text` concaténé |
| Colonne notes — corps | 12 px sans interligne, là où §1.2 écrit « Notes et transcription en 12,5 » et `line-height 1.55` | **(a) corrigé** |
| Colonne notes — barres de gauche | 2 px `accent/report` sur les décisions, rien sur les notes | conforme |
| Colonne notes — composeur | chips `/action /décision /risque /citer` **toujours visibles** ✓, mais `/décision` se repliait en « / décisio / n » | **(a) corrigé** |
| Colonne notes — position des chips | alignées à droite du mot « Tape » | **(b)** n° 3 |
| Colonne transcription | fond `surface/alt`, `Cohere MLX · 4 segments`, bascule `Suivre` | conforme (le compteur de segments est un ajout, cohérent avec « aucun onglet vide ») |
| Frise audio | hauteur 22 px, tête de lecture 2 px `accent/action`, ronds et losanges aux bons temps ✓ ; mais « Aucun audio » était **écrit par-dessus** les marqueurs, au milieu de la piste | **(a) corrigé** — invite réservée à la frise sans marqueur |
| Frise audio — bornes | timecodes `00:00` / `23:24` en 9,5 px, là où §1.2 donne 10 pour un timecode | **(a) corrigé** |
| Rail d'actions — largeur | **329 px** : le filet de séparation était prélevé sur le rail que §1.2 fixe à 330 | **(a) corrigé** |
| Rail d'actions — onglets et vues | `Actions 12 / Risques 5 / Historique`, `Liste / Calendrier / Eisenhower` | conforme |
| Rail d'actions — groupes | `À ASSIGNER — 9`, puis `REPORTÉES DU 1ER SEPT. — 3` | conforme (`DÉLÉGUÉES` est **(b)** n° 8, non semé ici) |
| Rail d'actions — pilules | `＋ Pierre-Yves` se repliait en « ＋ Pierre- / Yves », `＋ échéance` en « ＋ / échéanc / e » | **(a) corrigé** |
| Rail d'actions — invites | pilule vide en `accent/action`, renseignée en `accent/ok` ou neutre | conforme |
| Rail d'actions — composeur | champ + `Moi / Demain / ! / 30min`, toujours visible | conforme |
| Compteur `À ASSIGNER` | 9 et non 3 | **(b)** n° 4 |
| Dock de l'assistant | barre d'invocation en pied + `⌘K` | conforme |

## Écran 1b — mode séance plein écran (`1b-mode-seance.png`)

`recette/1b-1920.png`.

**L'écran 1b n'a pas pu être atteint.** Le bouton de la pilule audio
(« Passer en mode plein écran ») et l'item de menu **Mode séance plein écran**
(`⌃⌘F`) font bien passer la fenêtre en plein écran — la barre de titre
disparaît, `titleVisibility` est donc bien passé à `.hidden`, et l'axe
`SessionFullscreenPresenter → SessionWindowSwapper.presenter` a donc été
parcouru — mais **le contenu n'est pas substitué** : la fenêtre reste sur le
cockpit clair, tiroir Ressources compris. `Clore la séance`,
`TRANSCRIPTION LIVE`, la colonne temps et le bandeau `EN ATTENTE` sont absents
de l'arbre d'accessibilité, vérifié deux fois. La capture livrée documente cet
état.

Aucune comparaison de finition n'est donc mesurable sur 1b : palette `dark/*`,
grille `78 \| 1fr \| 400`, colonne temps, bandeau d'assignation et panneau
assistant restent à recetter. Cf. **(c)** n° 1.

Les écarts que l'audit du code a relevés sur cette branche, non observables
faute d'écran, sont reportés au lot concerné : trois couleurs de la palette
**claire** posées sur fond sombre (`okDeep` pour l'avatar du locuteur, `report`
pour `Clore la séance`, `action` pour `Assigner maintenant` et le bouton
d'envoi de l'assistant), le jeton `dark/cardActive` (`#232019`) inemployé pour
son rôle, le timecode de la barre d'état en 12 px au lieu de 10, et trois
tailles hors barème (19, 13,5 et 9 px).

## Écran 1c — poste de pilotage (`1c-poste-de-pilotage.png`)

`recette/1c-1280.png`, `recette/1c-1920.png`. Espace Réunion, mode Relire.

**C'est l'écran le plus fidèle des cinq.**

| Zone | Constat | Verdict |
| --- | --- | --- |
| Nav latérale — largeur | 190 px | conforme |
| Nav latérale — tête | badge `1:1` + `One2One`, puis libellé `SÉANCE` | conforme (la maquette les montre) |
| Nav latérale — entrées | `Synthèse · Notes 6 · Transcription 23′ · Actions 12 · Rapport — · Documents 4 · Assistant` | conforme dans l'ordre et la forme |
| Nav latérale — `Notes 6` | 6 et non 5 | **(b)** n° 6 |
| Nav latérale — `Documents 4` | la maquette écrit `Documents ＋` ; le compteur est plus juste, et §1.1 veut « un compteur **ou** un état » | **(b)** n° 12 |
| Nav latérale — compléments de `Synthèse` et `Assistant` | `généré` et `⌘K`, absents de la maquette | **(b)** n° 7 |
| Nav latérale — entrée active | carte blanche, ombre 1 px | conforme |
| Nav latérale — icône de `Notes` | barre oblique là où la maquette dessine un crayon | écart de symbole, non chiffré par la spec — laissé |
| Bloc projet | `S/D — Modernisation CI/CD` + les trois dernières réunions | conforme (nom : **(b)** n° 10) |
| Bloc `ALERTES` — compteur | `ALERTES 5` sans point médian, là où la maquette écrit `ALERTES · 5` | **(a) corrigé** |
| Bloc `ALERTES` — surplus | `+1 autres` au pluriel pour un seul reste, en `ink/muted` à 11 px | **(a) corrigé** (singulier + `ink/4`) |
| Bloc `ALERTES` — titres | « Chiffrage du reste à faire non validé », « Comptes GitLab désactivés »… au lieu des titres de la maquette | **(b)** n° 9 |
| Bloc `ALERTES` — point du 5ᵉ risque | bleu (`action`) | **(c)** n° 6 |
| En-tête — titre et métadonnées | titre 14/600 sur une ligne, puis `P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants` | conforme à la maquette, qui empile aussi les deux lignes |
| En-tête — boutons | `Capture`, `Exporter ⌄` (grisé, rien à exporter), `Rapport` | conforme ; `Capture` est **(b)** n° 5 |
| En-tête — sélecteur de mode | `Préparer / En séance / Relire` en haut à droite, absent de la maquette | **(b)** n° 11 |
| Carte `EN UNE PHRASE` | libellé mono, chip `généré`, résumé en 12,5 px, chips de sujets (`Migration AP`, `Ressources`, `GitLab / CI-CD`, `Facturation`) | conforme |
| Cartes côte à côte | empilées à 1 280 px (colonne fluide sous 900 px) | **(b)** n° 13 |
| Carte `DÉCISIONS PRISES · 3` | point médian ✓, trois lignes `11:03 / 13:40 / 20:15` avec porteur en `ink/4` | conforme |
| Tableau d'actions — colonnes | `20 \| 1fr \| 108 \| 92 \| 62 \| 76 \| 30`, en-têtes `INTITULÉ / RESPONSABLE / ÉCHÉANCE / CHARGE / SOURCE` + `⋯` | conforme au pixel |
| Tableau d'actions — en-tête de carte | `Actions` + pilule `9 sans responsable` + `Tableau / Eisenhower / Calendrier` + `＋ Action` | conforme |
| Tableau d'actions — lignes | source `04:12 ↗`, `Reporté` en date, responsables en `accent/ok`, invites `＋ assigner` / `＋ date` | conforme |
| Frise audio en pied | pleine largeur de la colonne principale (comme la maquette, qui la fait commencer après la nav), étiquettes `04:12`, `07:48`, `DÉCISION` ×3, `15:20`, bouton `✂ Éditer` | conforme |
| Frise audio — « Aucun audio » | superposé aux marqueurs | **(a) corrigé** |
| Barre du haut | **reste affichée** au-dessus du poste de pilotage, que la maquette 1c ne montre pas | **(c)** n° 4 |
| Dock de l'assistant | présent entre le corps et la frise, absent du texte de §2.7 | **(b)** n° 7 (même justification) |

## Écran 3a — tiroir Ressources et « À l'écran » (`3a-tiroir-ressources.png`)

`recette/3a-1280.png`, `recette/3a-1920.png`. Tiroir ouvert par
**Réunion ▸ Ressources…**, `Chiffrage_Marine_v3.xlsx` mis « À l'écran ».

| Zone | Constat | Verdict |
| --- | --- | --- |
| Tiroir — largeur | 396 px, superposé sans démonter la séance, colonne principale interactive | conforme |
| Tiroir — en-tête | `Ressources` + `4 séance` + `17 projet` + `＋ Importer` | conforme ; `4 séance` compte le lien : **(b)** n° 14 |
| Tiroir — filtres | `Cette séance · Le projet · Captures · Liens` | conforme |
| Tiroir — vignettes | icône de type 34 × 40 avec fond dédié (XLS vert, PNG neutre, PDF rouge, URL bleu), nom, `Ajouté par Sylvain · 09:32 · 40 Ko` | conforme |
| Tiroir — pièce présentée | bordure `accent/action`, fond `actionBg2`, état `À l'écran` **plein** puis `Citer` / `Envoyer` | conforme |
| Tiroir — actions des autres vignettes | `Présenter` seul (ou `Ouvrir` pour un lien) ; `Citer` et `Envoyer` n'apparaissent que sur la pièce présentée, là où §4.1 les liste par vignette | **(c)** n° 8 |
| Tiroir — ordre des pièces | la pièce présentée reste à sa place ; la maquette la met en tête | écart mineur, non chiffré — laissé |
| Tiroir — métadonnée du PDF | `09:42 · 213 Ko · cité 3 fois` là où la maquette écrit `Repris du projet · cité 3 fois` | écart mineur de libellé — laissé |
| Tiroir — zone de dépôt | permanente en fin de liste, « Glissez un fichier ici, collez un lien, ou capturez l'écran — ⌘⇧V » | conforme (le mot « ici » est en sus) |
| Tiroir — `⌘⇧V` de la zone | Plex Mono 10,5 en `ink/muted` | **(a) corrigé** |
| Pied `À L'ENVOI DU RAPPORT` | trois cases, les deux premières cochées | conforme |
| Tiroir — `✕` de fermeture | en sus de §4.1 | cohérent avec §4.3, laissé |
| « À l'écran » — carte | en haut de la colonne principale : `À l'écran  Chiffrage_Marine_v3.xlsx`, `Annoter`, `Épingler à 04:14`, `Arrêter le partage` | conforme |
| « À l'écran » — scène | document centré, **légende sous le document** (« Aperçu — les participants voient la même page »), jamais en absolu | conforme |
| « À l'écran » — légende | Plex Mono 10,5 en `ink/muted` | **(a) corrigé** |
| « À l'écran » — aperçu | « Aperçu indisponible — le document reste partagé et citable » : le `.xlsx` semé n'a pas de rendu Quick Look | état de données, conforme |
| Pilule de partage dans la barre du haut | présente et pleine `accent/action` ✓, mais réduite à un carré bleu faute de place, et en rayon de bouton | **(a) corrigé** (deux fois) |
| Bande `ÉPINGLÉ DANS LA SÉANCE` | chips `04:12 · Comptes_GitLab` et `12:08 · Chiffrage_Marine_v3` + mention « Les pièces épinglées sont citées dans le rapport » | conforme ; la chip du moment courant n'est pas en `accent/action` parce que la tête de lecture est à 0 — comportement, non écart |
| Bande — mention de pied | 11 px en `ink/muted` | **(a) corrigé** |
| Composeur de notes | recouvrait la dernière note visible de la colonne à 1 280 px | corrigé indirectement par l'interligne et le `fixedSize` des notes — **à revérifier à la recapture** |

## Écran 3b — fiche projet en panneau (`3b-fiche-projet.png`)

`recette/3b-1920.png` (lecture), `recette/3b-edition-1920.png` (**édition, vue
pour la première fois**), et `recette/lot-9-1280.png` (recette du lot 9,
conservée).

| Zone | Constat | Verdict |
| --- | --- | --- |
| Panneau — largeur | 430 px, glissé depuis la droite, ombre `-8px 0 24px rgba(0,0,0,.07)` par jetons | conforme |
| Panneau — colonne principale | atténuée et **restée consultable** (aucun `allowsHitTesting(false)`) | conforme |
| Segment projet du fil d'Ariane | bordé `accent/action`, fond `actionBg2`, chevron `⌄` | conforme |
| En-tête | `FICHE PROJET`, nom sur une ligne, `P25_110 · 4 réunions · dernière mise à jour le 4 sept. par vous`, bascule `Édition`, `✕` | conforme (les nombres viennent du semis) |
| Carte `STATUT` | libellé mono, point `warn`, `À surveiller` | conforme |
| Carte `STATUT` — en édition | le point coloré disparaît et le chevron passe **avant** le libellé (`⌄ À surveiller`) | **(c)** n° 9 |
| Carte `BUDGET CONSOMMÉ` | `40 000 € / 61 000 €` + barre | conforme |
| Barre de budget — teinte | **verte** à 65,6 % ; la maquette la dessine orange | **(b)** n° 15 |
| Budget — en édition | champs `40000` / `61000` sans séparateur de milliers ni `€` | **(b)** n° 16 |
| `JALONS` | point vert « Migration AP finalisée · 30 sept. », point orange « Migration Marine — chiffrage à valider · **bloqué** » en `report`, cercle vide « Bascule Jenkins → GitLab CI · 15 nov. » | conforme |
| `JALONS` — ligne d'ajout | `Nouveau jalon…  date · statut` en pointillé, visible **en édition seulement** | conforme à §4.3 (la maquette est en édition) |
| `JALONS` — en édition | quatre contrôles par ligne (`⊗ ⊖ ∧ ∨`), absents de la maquette | **(b)** n° 17 |
| `JALONS` — dates en édition | `30/09/2025` au format numérique là où la lecture donne `30 sept.` | écart mineur de format — laissé |
| `PÉRIMÈTRE & CONTEXTE` | libellé mono, lien `éditer`, texte encadré `surface/alt` | conforme |
| Chips de thèmes | `GitLab Nexus PostgreSQL Cléva` en grille adaptative : de larges trous entre les chips, et la chip `＋` seule sur sa propre ligne | **(b)** n° 18 |
| `RISQUES · 5` | point médian ✓, cinq risques, `＋ Ajouter un risque` en édition | conforme (5 et non 3 : semis) |
| `RISQUES` — point du 5ᵉ | gris (`ink/4`) | **(c)** n° 6 |
| `INTERLOCUTEURS` | `Olivier Freund — partenaire, décideur`, `Claire-Amélie F.-D. — architecte`, `Alexis / Jeff — périmètre Digital`, `＋ Ajouter` | conforme |
| Encart de l'assistant | **absent** : le home de recette n'a aucun endpoint IA configuré. C'est le comportement attendu (« sans endpoint : encart absent, pas d'erreur ») | conforme, non démontré |
| Pied | mention de visibilité + `Annuler` / `Enregistrer`, **en édition seulement** | **(c)** n° 10 |
| Édition — troncature | « Chiffrage du reste à faire non », « Facturation de 40k sans livra », « Claire-Amélie F.· », « partenaire, décid » : coupés **sans ellipsis** | **(c)** n° 11 |

---

## (b) — écarts déjà assumés, confirmés visibles

| n° | Écart | Source |
| --- | --- | --- |
| 1 | Pile d'avatars **triée par nom** (`CA CP LD LS NL PY`), pas dans l'ordre de la maquette | lot 1, n° 2 |
| 2 | Règle d'initiales de la capture (`PY` pour Pierre-Yves Nallet, non `PN`) | lot 1, n° 3 |
| 3 | Chips `/…` alignées à droite du composeur de notes | lot 2, n° 2 |
| 4 | `À ASSIGNER — 9` (et `9 non assignées`) au lieu de 3 : le semis pose 9 actions sans responsable | lot 4 |
| 5 | Bouton `Capture` dans la barre du haut, absent du tableau de §2.1 | lot 1, n° 5 |
| 6 | `Notes 6` au lieu de 5 : `5` est arithmétiquement impossible | lot 5, n° 1 |
| 7 | `Synthèse généré` et `Assistant ⌘K` portent un complément ; dock d'assistant dans la colonne | lot 5, n° 2 |
| 8 | Quatrième groupe `DÉLÉGUÉES` dans le rail (non peuplé par ce semis) | lot 3, n° 2 |
| 9 | Les cinq titres du bloc `ALERTES` ne sont pas ceux de 1c | lot 5, n° 6 |
| 10 | Projet nommé `S/D — Modernisation CI/CD`, non `… Chaîne CI/CD` | lot 5, n° 7 |
| 11 | Sélecteur de mode ajouté en haut à droite du poste de pilotage | lot 5, n° 3 |
| 12 | `Documents 4` au lieu de `Documents ＋` | lot 5 (nav), cohérent avec §1.1 |
| 13 | `EN UNE PHRASE` et `DÉCISIONS PRISES` s'empilent sous ~900 px | lot 5, n° 10 |
| 14 | Le filtre `Cette séance` compte le lien : `4 séance` | lot 6, n° 4 |
| 15 | Barre de budget **verte** à 65,6 % (règle chiffrée `< 70 % ok`) contre orange sur la maquette | lot 9, n° 1 |
| 16 | Budget éditable en champs inline | lot 9, n° 3 |
| 17 | Réordonnancement des jalons par chevrons, pas par glisser-déposer | lot 9, n° 4 |
| 18 | Chips de thèmes en `LazyVGrid` adaptatif, pas en flot | lot 9, n° 6 |

Le marqueur de risque en **rond ambre** sur la frise (lot 2, n° 5) est également
visible et conforme à ce qui était assumé.

## (c) — écarts fonctionnels, hors finition

| n° | Écart | Recommandation |
| --- | --- | --- |
| 1 | **L'écran 1b n'est pas atteignable.** Le plein écran s'active (barre de titre masquée), mais `SessionWindowSwapper` ne substitue pas le contenu : le cockpit clair reste affiché. Reproduit deux fois, par le bouton de la pilule audio et par l'item de menu. | **Lot 4, correctif dédié.** La piste : `WindowReader` fournit-il bien la fenêtre de la scène `1to1-meeting` ? Un `contentView` remplacé sur une autre `NSWindow` expliquerait le plein écran sans changement d'image. Bloque toute recette de 1b. |
| 2 | **La fenêtre de réunion dédiée a crashé de façon reproductible** pendant la première moitié de la session, sur une récursion Auto Layout (`_NSViewUpdateConstraints` → `NSISEngine` → `updateConstraintsIfNeeded`, cinq `.ips` entre 20 h 03 et 20 h 08), **avec un bundle empaqueté par erreur depuis un binaire antérieur au build** (cf. n° 12). Une fois le bundle reconstruit depuis `.build/release`, plus aucun crash sur une dizaine de cycles. | **Aucun lot** : cause instrumentale identifiée. À reverifier à la recapture ; si le crash revient avec le bon binaire, ouvrir un correctif au lot 19. |
| 3 | **Le titre de réunion n'est pas un titre.** `EditableTextField` force `NSFont.systemFont` et `bezelStyle = .roundedBezel` : le `.font(.plexSans(13, .semibold))` de `MeetingTopChromeBar` est ignoré, et la barre du haut porte un champ bezelé permanent au lieu du texte plat de la maquette, éditable au double-clic. | **Lot 19.** `Views/EditableTextField.swift` est hors du périmètre de cette recette (et partagé par les écrans IA et markdown) : le corriger demande une variante « titre » du composant, testée. |
| 4 | **La barre du haut reste affichée en mode Relire**, que `1c-poste-de-pilotage.png` ne montre pas — la nav de 190 px y remplace tout le chrome supérieur. `MeetingSpacesBar.estMasquee` masque bien la barre d'espaces, pas la barre du haut. | **Lot 19**, avec la décision D0. Masquer la barre du haut en Relire prive de l'accès au type, au template et au `⋯` : c'est un arbitrage, pas une finition. |
| 5 | **La bascule `Speakers` ne s'affiche jamais** : les segments du semis ne portent pas de locuteur, donc `showsSpeakerToggle` est faux et la maquette (`Speakers ON`, `Yann —`, `Laurent —`) n'est pas reproduite. | **Lot 19** ou complément de semis. `RefonteDemoSeed` est gelé pour les lots livrés ; poser des locuteurs sur les quatre segments ne change aucun compteur vérifié par les tests. À trancher. |
| 6 | **Les niveaux de risque bas sortent en bleu (`action`) et gris (`ink/4`)** sur les points du bandeau, du bloc `ALERTES` et de la fiche projet. La maquette n'emploie que `report` et `warn`. | **Lot 19.** `MeetingKPIBand.teinte` sert quatre écrans ; restreindre la palette des niveaux est une décision de charte, pas un ajustement local. |
| 7 | **La fenêtre de l'instance de production de l'utilisateur (pid 16538, « NPA/LDB ») a changé de géométrie** : 40,40 / 1 542 × 800 au début de la session, 0,33 / 1 720 × 1 024 ensuite. Je ne l'ai pas touchée après l'avoir constaté, et tout mon redimensionnement passe par `AXUIElementCreateApplication(<mon pid>)`. Une seule de mes commandes a employé System Events (`first process whose unix id is …`, refusée avec `-10006`), et c'est précisément la voie que la consigne a ensuite interdite parce qu'elle résout mal le processus quand deux instances partagent le `CFBundleIdentifier`. | **Signalé, non réparé** : remettre la fenêtre en place serait encore la toucher. À l'utilisateur de la redimensionner. Pour la suite : `Info.plist` du bundle de recette devrait porter un `CFBundleIdentifier` distinct (`com.onetoone.app.recette`), ce qui rendrait la confusion impossible — à ajouter à `Scripts/recette-app.sh` au lot 19. |
| 8 | **`Citer` et `Envoyer` n'apparaissent que sur la pièce présentée**, là où §4.1 les liste sur chaque vignette. | **Lot 15**, avec la chaîne de citation, ou lot 19. |
| 9 | **En édition, la carte `STATUT` perd son point coloré et met son chevron à gauche.** | **Lot 19** : c'est le libellé d'un `Menu` SwiftUI à reconstruire, plus qu'un ajustement. |
| 10 | **Le pied de la fiche projet (mention de visibilité, `Annuler`, `Enregistrer`) n'existe qu'en édition.** §4.3 le liste sans le conditionner. | **Lot 19.** Afficher la mention hors édition est un changement de comportement, pas de finition. |
| 11 | **La fiche projet en édition tronque ses libellés sans ellipsis** (risques, interlocuteurs). | **Lot 19** : les cellules sont des champs `EditableTextField`, même cause que le n° 3. |
| 12 | **`Scripts/recette-app.sh` peut empaqueter un binaire périmé sans le dire.** Le premier bundle de la session a été construit à partir d'un `.build/release/OneToOne` antérieur au build en cours ; il lui manquait les lots 4, 5 et 6, ce qui a produit deux heures d'observations fausses (mode Relire rendu comme au lot 1, resources absentes) avant que la comparaison des chaînes du binaire ne le révèle. | **Lot 19.** Le script devrait comparer `mtime` du binaire au dernier commit touchant `OneToOne/`, ou au minimum afficher `mtime` et taille du binaire copié. |

## Vérification

- `swift build` propre : aucune erreur, et aucun avertissement nouveau (seuls
  les préexistants — `PyannoteDiarizer`, `MLXEmbeddingEngine`,
  `AudioCompressionService`, `ManagerCategoryClassifier`, `BeautifulMermaidSwift`).
- `swift test` complet, `exit 0` : **1 041 XCTest** (1 ignoré) +
  **1 361 Swift Testing** en 177 suites = **2 402 tests**, exactement le
  chiffre de référence du sommet de la pile. Aucun test n'a changé de nombre :
  les corrections sont toutes des ajustements de vue.
- **Un échec XCTest, préexistant et indépendant de ces corrections** :
  `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`
  (`XCTAssertEqual failed: 0.0 ≠ 7200.0`). Le test place ses réunions
  « passées » à `startOfDay + 1 h` et `+ 2 h` et attend qu'elles soient
  révolues : entre minuit et 3 h du matin, elles sont dans le futur et
  `tempsPasseSeconds` vaut 0. La suite a été rejouée **sur les sources du
  commit de base** (`1fe3f0a`, `git checkout 1fe3f0a -- OneToOne/`) : elle
  échoue à l'identique. Le diff de cette branche ne touche aucun `Services/`
  ni `Models/`, et `TodayStatsCalculator` n'y figure pas. À corriger au
  lot 19 en injectant l'heure de référence, comme le font déjà les autres
  tests de la suite.
- Aucun test de lecture des sources (`SessionNoChromeTests`,
  `ActionsRailNoModalTests`, `ReviewCardsInviteTests`) n'est passé au rouge :
  aucune correction n'introduit de couleur nommée, de largeur en dur ni de
  présentation modale.

## Reste à faire

1. **Recapturer les neuf écrans** avec le binaire corrigé, écran déverrouillé,
   et remplacer les fichiers de ce dossier. Les captures livrées sont toutes
   antérieures aux corrections.
2. Traiter les onze écarts **(c)**, en commençant par le n° 1 (1b inatteignable)
   qui bloque un écran entier de la spec.
3. Rejouer la recette de 1b une fois ce correctif en place.
