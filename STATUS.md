# État du projet

Dernière mise à jour : 2026-09-08 CEST

## Intégration vague 7 : la pile redevient linéaire (2026-09-08)

Trois branches développées en parallèle sous le sommet de recette
`fix/refonte-recette-vagues-1-4` (PR #36), remises en pile linéaire :
`#36 → 14 (#43) → 42 → 18 (#44)`.

| Maillon | Branche | Base après intégration | `swift test` |
| --- | --- | --- | --- |
| 1 | `feat/refonte-lot-14-1to1-collab-prepa` (#43) | `fix/refonte-recette-vagues-1-4` | 1 923 ST + 1 054 XCT = **2 977**, vert (05:17 CEST) |

### Maillon 1 — lot 14 sur la recette

Rebase `--onto origin/fix/refonte-recette-vagues-1-4 origin/feat/refonte-lot-13-1to1-collab-seance`.
**Un seul conflit : `STATUS.md`** — union, la section du lot 14 en tête de celle de
l'intégration de la vague 6. Tout le code s'est recousu seul, et la lecture le confirme
plutôt que le rebase :

- `MeetingSpaceRouting.swift` — la recette n'y avait pas touché ; les cinq prédicats de
  1:1 (11, 12, 13, 14) cohabitent, `initialMode` couvre les deux types de tête-à-tête.
- `MeetingSpaceView.contenu` — l'ordre voulu est en place : Atelier en séance → 1:1 mené
  (séance, préparation) → 1:1 subi (séance, préparation) → Relire → standard. Les
  prédicats restent exclusifs deux à deux (`RefonteVague5IntegrationTests.routageExclusif`).
- `RecetteScreen` — onze codes, `1a 1b 1c 2a 2b 3a 3b 4a 5a 5b 6a`.
- `OneToOneApp.ouvrirEcranDeRecette` et `MeetingCommands` — mêmes semis, chacun appelé une
  fois : lots 5, 6, 7, 11, 12, 13 puis `seedWorkshopComplete` pour l'atelier.

`Scripts/recette-run.sh` a été **corrigé au passage** : sa liste `SCREENS` et sa table
d'en-tête ignoraient `5a` et `5b`, ajoutés aux lots 13 et 14 sans que le script suive.
Aucun test ne lisait ce fichier — c'est la recette manuelle qui aurait buté sur
« code inconnu ».

## Refonte de l'écran de réunion — lot 14 : 1:1 collaborateur, préparation en 2 minutes (5b) (2026-09-08)

Branche `feat/refonte-lot-14-1to1-collab-prepa`, **rebasée sur
`feat/refonte-lot-13-1to1-collab-seance`** (sommet de la pile après le rebase du lot 13 sur le
lot 8). Plan du lot dans
`docs/superpowers/plans/2026-09-08-refonte-lot-14-1to1-collab-prepa.md`.

**État : livré, `swift build` propre, `swift test` vert (1 823 Swift Testing + 1 041 XCTest, un
seul échec, préexistant et horaire — cf. plus bas), PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** ; le crochet est prêt
(`ONETOONE_SEED_DEMO_SCREEN=5b`).

### L'écran

`kind == .manager` + mode **Préparer** → `CollaboratorPrepView` : une **carte étroite de 940 px,
centrée**, et rien d'autre — ni rail d'actions, ni bandeau d'indicateurs, ni barre d'assistant.
Deux minutes veut dire dix lignes qu'on lit d'un coup d'œil ; une colonne de plus et l'écran
devient un tableau de bord qu'on remet à plus tard. Une branche dans `MeetingSpaceView.contenu`,
gardée par `MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation` — exclusive des quatre autres
branches, ce que vérifie `CollaboratorPrepAgendaTests.routageExclusif` type par type et mode par
mode.

C'est aussi le **mode d'ouverture par défaut** d'un entretien subi sans enregistrement :
`initialMode` accepte désormais les **deux** types de tête-à-tête (`OneOnOneThreadStore.faceToFace`)
et non le seul `.oneToOne`.

| Bloc | Contenu |
| --- | --- |
| En-tête (`CollabPrepHeader`) | avatar `YP`, `1:1 avec Yann — demain 14:00`, `Préparation · 2 min · dernier point le <date>`, badge **bordé** `Collaborateur`. **Sans bouton** : un entretien subi ne se démarre pas depuis chez moi. |
| `RESTÉ SANS RÉPONSE` (`UnansweredCard`, `accent/report`) | cases **décochées**, libellé + `depuis le <date>` |
| `CE QUE J'AI LIVRÉ DEPUIS` (`DeliveredSinceCard`, `accent/ok`) | `DeliveredItemsBuilder` du lot 13, lignes `✓ … · date` et `◐ … · cause`, **sans bouton `Citer`** |
| `CE QUE JE VEUX OBTENIR` (`WantedCard`, `accent/oneonone`) | cases **cochées**, composeur pointillé `Ajouter…` |
| Pied | `En faire mon ordre du jour` (violet plein), `Partager les sujets à Yann` (bordé, confirmation légère), mention de provenance |

### La règle « resté sans réponse » — critère chantier 5 n° 4

`UnansweredItemsBuilder` (pur). Trois sources, **aucune saisie** :

1. **les promesses du manager non tenues** — manquées, ou ouvertes et échues (`CommitmentLedger`,
   la définition de la règle 1 de `ReminderRules`) ;
2. **les sujets évoqués ≥ 3 fois qu'aucune décision ne tranche** (`RecurringTopicsBuilder`, seuil
   `ReminderRules.recurringTopicThreshold`) ;
3. **les demandes `pending`/`waiting`** du fil (`AgendaCarryover.requests`, la liste même de
   `MyRequestsCard` au lot 13).

**La règle 2 du lot 10 est adaptée, pas appelée.** `ReminderRules.reminders` écarte les familles
déjà portées par un sujet `todo` de l'ordre du jour : sur la carte manager `À NE PAS OUBLIER`
c'est juste — un sujet inscrit ne risque pas d'être oublié. Ici c'est l'inverse du propos : un
sujet que je porte depuis trois séances **sans obtenir de décision** est exactement ce que cet
écran doit me remettre sous les yeux. Le seuil, le lexique et l'exclusion par décision sont
repris ; celle par l'ordre du jour ne l'est pas.

**Une ligne par famille de lexique.** Les trois sources se recoupent — la demande « Compensation
des astreintes » et la promesse « Grille de compensation des astreintes » sont le même sujet.
Sans regroupement l'écran afficherait quatre lignes là où la capture en montre deux, et cocher les
deux moitiés du même sujet le porterait deux fois à l'ordre du jour. Dans un groupe, **la source
la plus forte parle** (promesse > sujet récurrent > demande : une parole donnée et non tenue est
le fait le plus lourd d'un entretien), et `depuis le …` prend la **plus ancienne** date du groupe —
c'est l'ancienneté qui plaide, et c'est elle qui trie les lignes.

Sur le jeu des lots 10 et 13, cela donne exactement les deux lignes de la capture :
`Mobilité archi — 4 fois évoquée, jamais tranchée · depuis le 10 juil.` et
`Grille de compensation des astreintes promise, 2 reports · depuis le 24 juil.`

### `En faire mon ordre du jour`

`PrepToAgenda`. Le **plan** est pur : les lignes cochées de `RESTÉ SANS RÉPONSE`, préfixées selon
leur source (`Promesse : `, `Sujet : `, `Demande : ` — sans quoi l'ordre du jour de la séance
suivante afficherait une phrase sans dire d'où elle sort), puis les sujets voulus non décochés,
tels que je les ai écrits.

`apply` retrouve par le **texte** ou crée, rattache à la séance préparée, et numérote `0…n-1`
**dans l'ordre du plan** ; les autres sujets de la séance sont renumérotés à la suite, sans quoi
un sujet voulu — qui existait déjà avec un rang bas — devancerait les lignes sans réponse dès le
premier clic. Les demandes gardent leurs rangs : les deux cartes de la séance filtrent des listes
séparées (ce que documente déjà `CollaboratorSessionModel.moveTopics`). Idempotent, donc un second
clic ne duplique rien ; le bouton se désactive alors sur `Ordre du jour prêt · n sujets`.

Tout est créé `private` (spec §6.1 : côté collaborateur le défaut n'est pas négociable).
`Partager les sujets à <Prénom>` est le geste explicite du critère n° 2 : il verse (idempotent)
puis passe **ces lignes-là** en `shared`, après une confirmation qui n'affiche que leur **compte** —
la seule chose qu'on veut relire avant de rendre visible ce qu'on avait écrit pour soi. Une ligne
`escalated` ne redescend jamais vers le manager par ce geste (D9).

Un sujet déjà versé est retiré de `CE QUE JE VEUX OBTENIR` : les lignes créées sont des sujets
privés `todo`, et sans cela la carte du bas les reprendrait toutes après le premier clic.

### Ouverture la veille

Le pré-rappel d'une réunion `kind == .manager` prend une **catégorie propre**
(`MEETING_PRE_START_1TO1`) dont la première action est `Préparer`. Une catégorie et non une action
de plus sur `MEETING_PRE_START` : les actions d'une notification sont figées par sa catégorie, et
un « Préparer » sur une réunion de projet ouvrirait un écran qui n'existe pas pour elle.
`preStartCategory(for:)` est **pure et `nonisolated`** — la présence de l'action ne dépend d'aucun
réglage. L'action **impose le mode par la clé mémorisée** (`MeetingScreenModel.modeKey`) avant de
poster le même avis d'ouverture que « Ouvrir » : c'est le chemin qu'emploient déjà le crochet de
recette et `MeetingSpaceView.appliquerModeInitial`, pas un second chemin. Aucun test n'instancie
`UNUserNotificationCenter`.

### Fichiers

**Services (purs, testés) :** `Services/OneOnOne/Prep/{CollaboratorUnansweredItems,
CollaboratorWantedItems, CollaboratorPrepModel, CollaboratorPrepToAgenda,
CollaboratorPrepStore}.swift`.

**Vues :** `Views/Meeting/OneOnOne/CollaboratorPrep/{CollaboratorPrepView, CollabPrepHeader,
CollabPrepCheckbox, UnansweredCard, DeliveredSinceCard, WantedCard}.swift`.

**Pas de `RefonteDemoSeed+Lot14.swift`** : le périmètre le prévoyait « seulement si une donnée
manque », et rien ne manque — les deux lignes sans réponse, les quatre livrés et les deux sujets
voulus de la capture sortent tous du jeu des lots 10 et 13. Un semis de plus serait un doublon à
tenir en phase.

**Fichiers partagés touchés, en blocs localisés :** `MeetingSpaceRouting.swift` (une fonction +
la garde de `initialMode`), `MeetingSpaceView.swift` (une branche), `OneOnOneScreenState.swift`
(`collabPrepCheckedUnanswered`, `collabPrepDroppedWanted`, **en fin de type**),
`RecetteScreen.swift` (code `5b`), `MeetingNotificationService.swift` (la catégorie, l'action, la
fonction pure et une branche du gestionnaire). `MeetingTopChromeBar.swift`, `MeetingView.swift`,
`MeetingScreenModel.swift`, `OneToOneApp.swift` : **rien**.

**Tests :** `Tests/CollaboratorPrepBuildersTests.swift` (9 cas) et
`Tests/CollaboratorPrepAgendaTests.swift` (18 cas). Trois suites existantes ajustées d'une ou deux
lignes : `RefonteVague5IntegrationTests` (onzième code de recette, cinquième branche exclusive),
`ManagerPrepRoutingTests` (`.manager` sort de la liste des types qui gardent leur mode
d'ouverture), `MeetingNotificationCategoriesTests` (dixième catégorie).

### Les critères

- **Chantier 5 n° 4** — `UnansweredItemsBuilder` sur le jeu du lot 13 : la promesse ouverte et
  échue du 24 juillet, reportée deux fois, remonte **seule**, avec son ancienneté. Personne ne l'a
  ressaisie.
- **`PrepToAgenda`** — ordre (les lignes sans réponse préfixées devant les sujets voulus),
  idempotence (un second clic ne crée rien, les rangs ne bougent pas), visibilité privée par tous
  les chemins, passage en `shared` par le second bouton et par lui seul, et l'escalade qui ne
  redescend pas.
- **Cases par défaut** — décochées à gauche, cochées à droite : l'état d'écran ne retient que les
  cases cochées d'un côté et les **refus** de l'autre, donc un sujet ajouté à l'instant naît
  coché.
- **En-tête** — `demain 14:00` avec horloge injectée, plus `aujourd'hui`, le jour de la semaine
  dans les sept jours (`OneOnOneDateFormat.dueDate`, la règle de toutes les échéances du domaine)
  et la date au-delà.
- **Notification** — la catégorie du 1:1 subi porte `Préparer` en tête ; **aucune** autre
  catégorie ne la porte, pour aucun autre type.
- **Aucune zone vide sans invite** — sur un fil neuf, les trois blocs ont leur invite, et chacune
  dit quoi faire.

### Écarts avec la capture, assumés

- **Les libellés reprennent le texte des données, pas celui de la maquette.** La capture écrit
  `Grille d'astreinte promise, 2 reports` là où la promesse semée s'appelle « Grille de
  compensation des astreintes » : le gabarit est celui de la capture, le texte reste celui de la
  donnée. Une table de synonymes pour raccourcir les libellés ne serait tenue par personne.
- **Le compteur d'occurrences est celui du fil.** La capture dit « 3 fois évoquée » ; le jeu de
  démonstration compte **quatre** mentions de la famille `carriere` (deux sujets, deux notes).
- **`5b` ouvre la séance du 4 septembre en mode Préparer**, celle de `5a` : c'est la seule séance
  du fil, et c'est elle qui porte les quatre livrables et les deux lignes sans réponse de la
  capture. L'en-tête y écrit donc sa date réelle et non `demain 14:00` — la règle « demain » est
  tenue et **testée avec une horloge injectée** plutôt que mise en scène par un semis qui
  décalerait la fenêtre de `CE QUE J'AI LIVRÉ DEPUIS`.
- **Le détail d'un livrable suit son libellé sur la même ligne**, comme la capture : une carte qui
  tient en deux minutes ne double pas sa hauteur pour une date.

### Un échec de test préexistant, horaire

`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` (XCTest) échoue **entre 0 h et 2 h du
matin**, indépendamment de tout lot : la suite a été passée à **01:10 CEST le 8 septembre**,
après le rebase sur le lot 13 rebasé, et c'est le **seul** échec. Non corrigé — il n'appartient pas à ce lot.

### Pour la passe de recette

`ONETOONE_SEED_DEMO_SCREEN=5b` (crochet unique, table `RecetteScreen`) sème les fils des lots 10
à 13 et ouvre l'entretien subi **en mode Préparer**. Le menu **Réunion** charge le même jeu.

### Prochaine action

Fait à l'intégration de la vague 7 (section en tête) : la branche est rebasée sur le sommet de
recette `fix/refonte-recette-vagues-1-4`, qui contient déjà le lot 13. Reste à fusionner dans
l'ordre de la pile. La recette visuelle de `5a` et `5b` se fait dans la passe dédiée.

## Intégration vague 6 : la pile redevient linéaire (2026-09-08)

Cinq branches développées en parallèle sur le sommet `feat/refonte-lot-12-1to1-manager-prepa`
(PR #33), remises en pile linéaire :
`#33 → 8 (#38) → 13 (#39) → 15 (#40) → 17 (#41) → recette (#36)`.

### Ce qui a conflicté, et rien de plus

Les quatre premiers maillons n'ont conflicté que sur **`STATUS.md`** — union des sections
en ordre chronologique inverse. Tout le code s'est recousu seul, ce qui n'était pas
acquis : `MeetingTopChromeBar.swift` est touché par les lots 13, 15, 17 **et** la recette,
mais dans des régions disjointes (fil d'Ariane et `Mon récap` pour le 13,
`compatibleTemplates` avec Escalade pour le 15, badge `ATELIER` et titre pour le 17, groupe
de contrôles et pilule de partage pour la recette). Vérifié à la lecture plutôt que sur la
foi du rebase :

- **`MeetingSpaceView.swift`** porte le modificateur `.sessionPill` du lot 8, la branche
  `CollaboratorSessionView` du lot 13 et le rail à 330 px de la recette. Ordre de routage
  conforme à la spec : Atelier → 1:1 mené → 1:1 subi → préparation → Relire → standard.
- **`OneToOneApp.swift`** : hotkeys de la pastille (lot 8) **et** semis / cible
  `.entretienSubi` du lot 13.
- **`MeetingCommands.swift`** : une seule ligne de semis par lot, et
  `seedWorkshopComplete` du lot 17 à la place de l'appel du lot 16.
- **`RecetteScreen`** couvre `1a 1b 1c 2a 2b 3a 3b 4a 5a 6a` (le lot 14 ajoutera `5b`).
- **`Models/OtherModels.swift`** : `acceptedProjectUpdatesJSON` en fin de type. **Aucune
  nouvelle version de schéma.**

### Trois arbitrages

**1. La largeur de la barre du haut — deux correctifs, une règle.** Le lot 17 et la
recette de la vague 1–4 visaient le **même** défaut par deux mécanismes différents : le
lot 17 donnait au titre une `layoutPriority(-1)` et un `fixedSize` au badge `ATELIER` (le
badge était tronqué à 1 616 px) ; la recette extrayait les contrôles de droite dans un
`controlsGroup` à `fixedSize` (à 1 280 px, `Rapport ✓ 6:20` se réduisait à « R », `Capture`
à « C », `● Partage actif · 5 voient` à un carré bleu). Les deux vont dans le même sens —
priorité de compression au **titre**, largeur intrinsèque aux contrôles — et **les deux
sont conservés** : n'en garder qu'une moitié ramène l'un des deux défauts. Ne restaient
incohérents que les commentaires (l'un décrivait encore le `layoutPriority(1)` que l'autre
venait de passer à `-1`) : refondus en une seule explication, moitié « qui cède » sur
`titleField`, moitié « qui ne cède pas » sur `controlsGroup`. Trois tests de lecture
verrouillent la règle entière dans `MeetingTopChromeBarTests`.

**2. Recette contre lots, sur les vues retouchées entre-temps.** Les 14 corrections de
finition datent d'avant les lots 7, 11, 12, 13, 15 et 17, qui ont retouché les mêmes vues.
Règle appliquée : la **finition** l'emporte quand le conflit porte sur un défaut visuel, le
**comportement** des lots quand il est fonctionnel. En pratique aucun conflit fonctionnel
n'est apparu, et les 14 corrections sont intactes : pastille `base` au lieu de `pill` dans
`AvatarStack` (invisible sur `surface`), `lineLimit(1)` sur `Chip` / `Pill` / `InvitePill`,
padding de carte 12 × 10 et cartes de hauteur égale dans `MeetingKPIBand`, « Aucun audio »
seulement quand la frise est vraiment vide, corps 12,5 px et interligne 1,55 dans les notes
et la transcription, rail à 330 px (le filet est prélevé sur la colonne fluide),
`ALERTES · 5`, singulier de « +1 autre », et `ink/4` partout sous 11,5 px.
`SessionNoChromeTests`, `ActionsRailNoModalTests`, `SessionThemeTests` et les tests de
contraste (`One2OneThemeTests`, `One2OneTokensTests`) restent verts.

**3. Le jeu de démonstration avait deux points d'entrée désaccordés.** Le lot 17 avait
remplacé `seedWorkshop` par `seedWorkshopComplete` dans le menu, mais pas dans le semis de
recette de `OneToOneApp` : la capture `6a` aurait montré l'atelier du lot 16, sans les
objets annotés, la pièce ni la capture du lot 17. Les deux points d'entrée sèment
désormais la même chose. `RefonteVague5IntegrationTests.semisEnsemble` reflétait lui aussi
la vague 5 (ni `seedLot13` ni `seedWorkshopComplete`) : il porte maintenant les sept semis,
avec un magasin de planches injecté dans un dossier temporaire — `seedWorkshopComplete`
écrit de vrais fichiers.

### La couture laissée par le lot 15

Le clic sur un timecode du rapport ne déplaçait pas la lecture. Toute la logique était là —
`CitationLinker` écrit les liens `onetoone://`, `MeetingReportPreview` les intercepte,
`QuickLaunchURLHandler.handle` sait déplacer une tête de lecture — mais **personne
n'appelait `handle`** : `MeetingReportSpace` ne recevait aucune `MeetingPlayhead` et le lien
mourait dans le délégué de navigation. Câblage seul, aucune logique nouvelle :
`MeetingReportSpace` reçoit `playhead` et passe `onCitation` à l'aperçu ; `MeetingView`
(l. 609) fournit `screen.playhead`. Deux tests purs, dont un bout à bout qui relit l'URL
**depuis le HTML du rapport** avant de la passer à `handle`.

### Vérifié

- `swift build` propre à chaque maillon. Les avertissements de concurrence Swift 6 sur
  `SessionPillPanelController.shared` et `MoodTrend.historyLength` viennent des branches
  elles-mêmes, pas de l'intégration.
- `swift test` complet et vert à chaque maillon, à l'échec **horaire préexistant**
  `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` près (entre 0 h et 2 h ;
  corrigé par la PR #37 sur `master`, hors pile) — toutes les exécutions de cette session
  sont tombées entre 01 h 02 et 01 h 20 CEST.
- Progression des totaux, chaque fois l'union exacte des apports : 2 714 (base #33) →
  **2 770** (lot 8) → **2 839** (lot 13) → **2 891** (lot 15, dont 2 tests de la couture) →
  **2 949** (lot 17) → **2 952** (recette, dont 3 tests d'arbitrage de largeur).
- `MeetingView.swift` : **2 064 lignes** (plafond 2 100), la seule ligne ajoutée étant
  celle de la couture.
- Un crash SwiftData isolé (`ModelContext.reset`, signal 5) est apparu sur **une**
  exécution du maillon 15, dans la suite `ScreenCaptureService` : c'est le flake que
  l'en-tête de `ScreenCaptureServiceTests` documente déjà (tâche OCR détachée, conteneurs
  en mémoire construits en parallèle). Non reproduit à l'exécution suivante ni sur les
  maillons suivants.

### Non fait

- **Aucune fusion** : la pile est publiée, les cinq PR rebasées et leurs bases corrigées.
- **Aucune recette visuelle** de cette session : pas de lancement de l'app. Les nouveaux
  écrans (5a, 6a complet, rapport avec citations, pastille) restent à voir à l'écran, et
  les nouvelles captures de la recette des vagues 1–4 restent à reprendre — les PNG
  versionnés sont **antérieurs** aux 14 corrections, comme leur fichier le documente.
- `feat/refonte-lot-14-1to1-collab-prepa` (sur le lot 13) et
  `fix/refonte-session-fullscreen-content` (sur #33) se rebaseront elles-mêmes sur cette
  pile ; elles n'ont pas été touchées.

## Recette visuelle des vagues 1 à 4 — écrans 1a, 1b, 1c, 3a, 3b (2026-09-08)

Branche `fix/refonte-recette-vagues-1-4`, sur
`fix/refonte-1to1-window-crash` (PR #31), donc au **sommet** de la pile
linéaire `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31`. Recette complète :
`docs/superpowers/specs/refonte-2026-09/recette/2026-09-07-recette-vagues-1-4.md`
(tableau zone par zone pour les cinq écrans).

**État : neuf captures produites, 14 corrections de finition livrées en
6 commits, 18 écarts assumés confirmés, 12 écarts fonctionnels à traiter.
`swift build` propre, `swift test` complet à 2 402 tests. Recapture d'après
correction encore due — l'écran s'est verrouillé.**

### Captures produites

Dans `docs/superpowers/specs/refonte-2026-09/recette/` : `1a-1280.png`,
`1a-1920.png`, `1b-1920.png`, `1c-1280.png`, `1c-1920.png`, `3a-1280.png`,
`3a-1920.png`, `3b-1920.png` et **`3b-edition-1920.png`** — le mode Édition de
la fiche projet, que le lot 9 n'avait pas pu atteindre, est vu pour la première
fois. `lot-9-1280.png` est conservée.

Toutes sont prises dans la **fenêtre dédiée** `1to1-meeting` (celle du
correctif #31), donc sans la barre latérale de l'application, contrairement à
`lot-9-1280.png`. Store isolé (`HOME` **et** `CFFIXED_USER_HOME` jetables),
isolation vérifiée par `lsof` à chaque lancement : **zéro descripteur** sur le
store de production.

⚠️ **Les `*-1920.png` mesurent 1 728 × 1 023 pt, pas 1 920 × 1 080.** L'écran
de ce poste fait 1 728 × 1 117 pt et AppKit borne une fenêtre au cadre visible.
Un mode d'affichage à 2 056 × 1 285 pt existe, mais changer la résolution d'une
session de travail active n'est pas une décision à prendre seul (CLAUDE.md,
règle 6). Les `*-1280.png` sont, eux, exactement 1 280 × 800 pt.

⚠️ **Les captures livrées sont antérieures aux corrections** : l'écran s'est
verrouillé avant que le binaire corrigé ne soit empaqueté. Elles valent comme
constat, pas comme démonstration du résultat.

### Corrections de finition livrées

| Commit | Écran(s) | Correction |
| --- | --- | --- |
| `pilules et chips : une seule ligne` | 1a, 1c, 3a, 3b | `Chip`, `InvitePill` et `Pill` prennent `lineLimit(1)` + `fixedSize` : `＋ Pierre-Yves` se repliait en « ＋ Pierre- / Yves », `/décision` en « / décisio / n », `● Partage actif · 5 voient` en carré bleu. Même défaut que la chip « PostgreS / QL » du lot 9, remonté dans les primitives. |
| `1a : bandeau d'indicateurs et pile d'avatars` | 1a | **Les six pastilles d'avatar étaient invisibles** (`pill` = `surface` = `#ffffff` en clair, soit le fond de la carte) → fond `base`. Padding de carte désinversé (10 vertical × 12 horizontal, §2.3). Les 4 cartes reprennent une hauteur égale (`fixedSize` vertical + `maxHeight: .infinity`). |
| `barre du haut : libellés préservés, pilule de partage` | 1a, 3a, 3b | `Rapport ✓ 6:20` se réduisait à « R », `Capture` à « C » : le titre (`layoutPriority(1)`) gagnait l'arbitrage contre les contrôles, alors que §2.1 en fait la colonne fluide. Les contrôles passent en `fixedSize`. La pilule de partage passe de `radiusButton` (6) à `Capsule` (§4.2 + §1.2). |
| `notes ↔ transcription : corps 12,5 px, plus de recouvrement` | 1a, 3a | À 1 280 px, la décision de 11:03 recouvrait la note de 15:20 : le préfixe était un `HStack` aligné sur la première ligne de base, qui gardait la hauteur d'une ligne → un seul `Text` concaténé. Corps passé de 12 à **12,5 px** avec `line-height 1.55` (§1.2). |
| `frise audio lisible et rail d'actions à 330 px` | 1a, 1c, 3a | « Aucun audio » était écrit **par-dessus** les marqueurs sur les cinq captures → réservé à la frise sans marqueur. Bornes de frise en 10 px (§1.2). Le rail mesurait **329 px** : le filet est désormais prélevé sur la colonne fluide, pas sur le rail que §1.2 fixe à 330. |
| `1c : « ALERTES · 5 » et le singulier de « +1 autre »` | 1c | Point médian devant le compteur, comme `DÉCISIONS PRISES · 3` et `RISQUES · 5` ; singulier ; `ink/4`. |
| `contraste des textes sous 11,5 px` | 1a, 1c, 3a | Cinq emplois de `ink/muted` sous le seuil de §1.2 (« réservé aux placeholders de 11,5 px et plus ») passent en `ink/4` : compléments d'onglet, détail de risque, mention de la bande épinglée, légende d'aperçu, `⌘⇧V` de la zone de dépôt. |

Aucune couleur hors `One2OneToken`, aucune fonctionnalité nouvelle, aucun
service ni modèle touché, `MeetingView.swift` intact.

### Écarts assumés confirmés visibles (18)

Tous relevés sur les captures et **non touchés** : pile d'avatars triée par nom
et initiales `PY` (lot 1 n° 2 et n° 3) ; chips `/…` alignées à droite (lot 2
n° 2) ; `À ASSIGNER — 9` au lieu de 3 (lot 4) ; bouton `Capture` dans la barre
du haut (lot 1 n° 5) ; `Notes 6` au lieu de 5, compléments de `Synthèse` et
`Assistant`, sélecteur de mode et dock d'assistant dans le poste de pilotage,
titres du bloc `ALERTES`, nom de projet sans « Chaîne », cartes empilées sous
900 px (lot 5 n° 1, 2, 3, 6, 7, 10) ; groupe `DÉLÉGUÉES` (lot 3 n° 2) ;
`4 séance` comptant le lien (lot 6 n° 4) ; **barre de budget verte à 65,6 %**,
budget en champs inline, chevrons de réordonnancement des jalons, chips de
thèmes en grille adaptative (lot 9 n° 1, 3, 4, 6) ; rond ambre du risque sur la
frise (lot 2 n° 5) ; `Documents 4` au lieu de `Documents ＋`.

### Écarts fonctionnels à traiter (12) — détail dans le fichier de recette

1. **L'écran 1b n'est pas atteignable.** Le plein écran s'active (la barre de
   titre disparaît, donc `SessionWindowSwapper.presenter` a bien été
   parcouru) mais **le contenu n'est pas substitué** : le cockpit clair reste
   affiché, `Clore la séance` et `TRANSCRIPTION LIVE` sont absents de l'arbre
   d'accessibilité. Reproduit deux fois, par le bouton de la pilule audio et
   par l'item de menu. Piste : `WindowReader` fournit-il bien la fenêtre de la
   scène `1to1-meeting` ? **Bloque un écran entier de la spec → correctif au
   lot 4.**
2. Crash Auto Layout de la fenêtre dédiée, reproduit cinq fois en début de
   session — **avec un bundle empaqueté par erreur depuis un binaire périmé**
   (cf. n° 12). Plus aucun crash après reconstruction du bundle. À reverifier
   à la recapture.
3. Le **titre de réunion n'est pas un titre** : `EditableTextField` force
   `NSFont.systemFont` et un `bezelStyle` arrondi, et ignore le
   `.font(.plexSans(13, .semibold))` de la barre. → lot 19.
4. La barre du haut **reste affichée en mode Relire**, que la maquette 1c ne
   montre pas. Arbitrage (accès au type, au template, au `⋯`) → lot 19 + D0.
5. La bascule `Speakers` ne s'affiche jamais : le semis ne pose pas de
   locuteur sur ses segments. → lot 19 ou complément de semis, à trancher.
6. Les niveaux de risque bas sortent en **bleu et gris** ; la maquette
   n'emploie que `report` et `warn`. → lot 19 (décision de charte).
7. ⚠️ **La fenêtre de l'instance de production de l'utilisateur (pid 16538,
   « NPA/LDB ») a changé de géométrie** — 40,40 / 1 542 × 800 au début de
   session, 0,33 / 1 720 × 1 024 ensuite. Elle n'a pas été touchée après le
   constat. Parade durable : donner au bundle de recette un
   `CFBundleIdentifier` distinct dans `Scripts/recette-app.sh`, ce qui rendrait
   impossible la confusion de processus dont AppleScript est capable.
8. `Citer` et `Envoyer` n'apparaissent que sur la pièce présentée (§4.1 les
   veut par vignette). → lot 15 ou 19.
9. En édition, la carte `STATUT` perd son point coloré et met son chevron à
   gauche. → lot 19.
10. Le pied de la fiche projet (visibilité, `Annuler`, `Enregistrer`) n'existe
    qu'en édition ; §4.3 le liste sans condition. → lot 19.
11. La fiche projet en édition **tronque sans ellipsis** (risques,
    interlocuteurs) — même cause que le n° 3. → lot 19.
12. **`Scripts/recette-app.sh` peut empaqueter un binaire périmé sans le
    dire.** Le premier bundle de la session a été construit depuis un
    `.build/release/OneToOne` antérieur au build en cours ; il lui manquait les
    lots 4, 5 et 6, ce qui a produit deux heures d'observations fausses (mode
    Relire rendu comme au lot 1, ressources absentes) avant que la comparaison
    des chaînes du binaire ne le révèle. Le script devrait afficher `mtime` et
    taille du binaire copié, ou le comparer au dernier commit touchant
    `OneToOne/`. → lot 19.

### Conditions rencontrées

- **Écran** : déverrouillé pendant toute la série de captures (19 h 50 –
  20 h 30), verrouillé ensuite — c'est ce qui a empêché la recapture d'après
  correction. L'attente réglementaire a été tenue : sondage toutes les 50 s
  de **00:09 à 00:49 CEST**, soit 40 minutes, l'écran est resté verrouillé.
  La procédure de recapture, outillage compris, est écrite en fin du fichier
  de recette.
- **Teams** : aucune réunion en cours ; la seule fenêtre du processus `MSTeams`
  portait « Calendar | APRIL | … », vérifié avant chaque série.
- **Instance de l'utilisateur** : jamais d'événement envoyé, jamais arrêtée.
  Tout le pilotage passe par `AXUIElementCreateApplication(<mon pid>)` et
  `CGWindowListCopyWindowInfo` filtré sur `kCGWindowOwnerPID`, jamais par
  AppleScript ni par nom d'application ; `kill` ne cible que les pid dont la
  ligne de commande est le chemin du bundle de recette. Cf. écart n° 7.
- **Store de production** : jamais ouvert (vérifié par `lsof` à chaque
  lancement).

### Vérification

`swift build` propre. `swift test` complet, `exit 0` : **1 041 XCTest**
(1 ignoré) + **1 361 Swift Testing** en 177 suites = **2 402 tests**, le
chiffre exact du sommet de la pile.

**Un seul échec XCTest, préexistant et dépendant de l'heure d'exécution** :
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, suite lancée à
**00:04 CEST le 2026-09-08**. Le test place ses réunions « passées » à
`startOfDay + 1 h` et `+ 2 h` et attend qu'elles soient révolues — entre
minuit et 2 h du matin, elles sont dans le futur et `tempsPasseSeconds` vaut 0.
Rejoué **sur les sources du commit de base** (`1fe3f0a`, restauration de
`OneToOne/` seul) : échec à l'identique. Le diff de cette branche ne touche
aucun `Services/` ni `Models/`, et `TodayStatsCalculator` n'y figure pas.
**Non corrigé ici** — une PR de recette n'a pas à toucher un test de
statistiques ; à reprendre au lot 19 en injectant l'heure de référence, comme
le font déjà les autres tests de la suite. Le même échec est constaté par le
lot 8 à 00:33 CEST, sur une autre base.

### Prochaine action

1. **Recapturer les neuf écrans** avec le binaire corrigé, écran déverrouillé,
   et remplacer les fichiers de `recette/`.
2. **Ouvrir le correctif de l'écart n° 1** (mode séance plein écran
   inatteignable) : c'est le seul qui prive la spec d'un écran entier.
3. Traiter les autres écarts (c), et trancher les deux questions restées
   ouvertes du lot 9 (teinte de la barre de budget, lignes de démonstration
   dans le store de production).

## Lot 17 — Atelier : modes Schéma et Manuscrit, pièces et captures (6a complet) (2026-09-08)

Branche `feat/refonte-lot-17-atelier-modes`, développée sur
`feat/refonte-lot-16-atelier-socle` (SHA `1d99a02` mémorisé dans
`.lot17-base-sha`) puis **rebasée** sur `feat/refonte-lot-12-1to1-manager-prepa`
une fois l'intégration de la vague 5 terminée — **aucun conflit**, le lot 16
avait déjà absorbé les points de couture. Plan :
`docs/superpowers/plans/2026-09-07-refonte-lot-17-atelier-modes.md`.
Tout reste derrière `AppSettings.workshopEnabled`.

### Trois modes, trois palettes — et c'est une table pure

`WorkshopPalette.tools(for:)` est le critère n° 2 du chantier 6 en une fonction :
Croquis = crayon, rectangle, ellipse, flèche, ligne, texte, **post-it**, image,
gomme ; Schéma = sélection, connecteur, texte, gomme **plus** les cinq formes de
la bibliothèque (`shapes(for:)`) ; Manuscrit = stylo, surligneur, gomme, règle,
lasso. Le catalogue `WhiteboardTool` perd `frame`, qui n'apparaît dans aucune
palette de la spec §7.1. Changer de mode **rearme l'outil par défaut** du
nouveau mode : garder un crayon dans une palette qui n'en a pas est le genre de
détail qui fait douter de tout le reste.

### Ce qui a été calculé en Swift plutôt que délégué au moteur

Deux décisions, prises sur pièces :

1. **L'alignement** (`BoardAlignment`, 8 opérations). L'objet impératif
   d'Excalidraw 0.18.1 — vérifié dans le bundle embarqué — n'expose **pas**
   `actionManager` : `let E={updateScene…,registerAction:…}` ne contient que
   `registerAction`. Les actions `alignLeft`, `distributeHorizontally`… du moteur
   sont donc hors d'atteinte du pont. Trente lignes de géométrie pure les
   remplacent, et **se testent sans WebKit** (13 tests) ; le pont ne transporte
   qu'un dictionnaire de positions, appliqué avec `captureUpdate: "IMMEDIATELY"`
   pour que `↺` défasse un alignement comme n'importe quel geste.
2. **La bibliothèque de formes** (`BoardShapeLibrary`). Les cinq formes —
   serveur, base de données, file, acteur, zone — sont dessinées en JSON
   Excalidraw **par l'application**, jamais téléchargées (la bibliothèque
   publique du moteur est neutralisée en `file:///` depuis le lot 16). En Swift
   et non inlinée dans le bundle JavaScript : une forme est une donnée, elle se
   compte et se vérifie en test, et corriger un tracé ne demande pas de
   reconstruire 3,7 Mo. Chaque forme est un **groupe** — sans `groupIds` commun,
   la déplacer la démonterait.

### Pression du stylet — implémentée, non vérifiable ici

Dans un `WKWebView`, les `PointerEvent` de macOS **n'apportent pas** la pression
d'une tablette : le moteur retombe sur `simulatePressure`, qui déduit l'épaisseur
de la vitesse du geste. `StylusPressureMonitor` lit donc la vraie pression dans
les `NSEvent` (`.pressure`, `.tabletPoint`, `.leftMouseDragged`) et la pousse
dans la page pendant le geste ; à la levée du stylet, la page rééchantillonne la
série sur les points du tracé, écrit `pressures` et pose
`simulatePressure = false`. Une souris ne rapporte **aucune** pression
exploitable (une constante) : `InkPressure.normalized` rend alors `nil` et
l'épaisseur reste celle de la barre d'outils, comme le veut la spec (« pression
si disponible »).

**Procédure de vérification, à faire en recette avec une tablette :**
1. brancher un stylet (Wacom, iPad + Sidecar, ou trackpad Force Touch) ;
2. ouvrir une planche en mode **Manuscrit**, outil `Stylo` ;
3. tracer un trait en variant l'appui, puis relâcher ;
4. dans `recordings/<uuid>/boards/<stableID>.excalidraw.json`, l'élément
   `freedraw` doit porter `"simulatePressure": false` et un tableau `pressures`
   de la **même longueur** que `points`, aux valeurs non constantes.
   Un `pressures` absent, ou `simulatePressure: true`, signifie qu'aucun
   `NSEvent` de tablette n'est arrivé — c'est le seul mode d'échec attendu.

### Dock : `SUR CETTE PLANCHE` et `PIÈCES & CAPTURES`

L'annotation vit dans `customData.one2oneKind` de l'élément — le seul champ que
le moteur transporte sans y toucher, donc elle survit à la sauvegarde, à la
duplication d'une planche et à l'export. `BoardAnnotation.list` la relit, y
compris quand le texte est porté par l'élément **lié** (`containerId`) et pas par
la boîte. Le menu contextuel est **natif** : `BoardWebView` remplace celui de
WebKit (« Recharger », « Inspecter » n'ont rien à faire sur une planche) par
« Marquer comme question / risque » et « Retirer l'annotation ».

`＋ Action depuis la sélection` crée l'action **tout de suite**, via
`ActionComposerService` — le rail n'est pas monté en atelier (le dock le
remplace), personne ne consommerait un brouillon posé dans
`pendingActionDraft`. Son titre vient des libellés sélectionnés
(`BoardScene.labels`, retours à la ligne aplatis). `Épingler à mm:ss` pose une
note `sourceRef board` (« ◫ Planche n · titre ») ; `MeetingTimelineMarkers+Boards`
en fait un repère **carré** et retire le rond que la note produirait — sans quoi
la même planche porterait deux repères superposés.

`PIÈCES & CAPTURES` réutilise `ResourceItem` (lot 6), `ResourceTypeIcon` (lot 6)
et `CaptureThumbnailCache` (lot 7, branché après rebase : une capture montre ce
qu'elle a capturé). Les onglets `Captures` et `Pièces` portent enfin du contenu ;
leur invite ne sert plus que pour une liste vide, et les compteurs comptent **ce
que l'onglet montre** — le lot de captures (`MeetingAttachment` de type `slides`)
est un conteneur, pas une pièce.

`Insérer` : l'image est copiée dans
`recordings/<uuid>/boards/assets/<stableID>.png`, **bornée à 2 048 px** sur le
grand côté (spec §7.4), et posée comme élément `image` **verrouillé** avec une
`data:` URL — la scène ne contient aucun chemin de disque. Le critère n° 3 a son
test : le fichier d'origine est supprimé, la planche tient. L'élément est
fabriqué **en Swift** et non dans la page : `locked: true` vit ainsi à un seul
endroit, celui que le test inspecte. Un fichier déposé sur la zone du dock est
copié dans la réunion (`AttachmentImporter.Bucket.meetingDocuments`) **puis**
inséré — deux gestes en un, comme le promet le libellé de la capture.

### Bundle Excalidraw régénéré

Versions **inchangées** (Excalidraw 0.18.1, React 18.3.1, esbuild 0.28.2,
Node 22.23.2) : seule l'entrée `Scripts/excalidraw-entry.jsx` change, avec huit
fonctions de plus (`setLibrary`, `insertShape`, `getSelection`, `select`,
`moveElements`, `setSelectionKind`, `insertImage`, `setPressure`). Le mode Schéma
arme `isBindingEnabled` et `objectsSnapModeEnabled` — connecteurs liés et
magnétisme viennent alors du moteur, gratuitement.

`excalidraw.bundle.js` : **3 718 038 octets** contre 3 715 102 (**+2 936**) ;
`excalidraw.bundle.css` inchangée à 253 200. `WhiteboardHTMLTests` reste vert :
CSP intacte, aucune adresse réseau apparue, aucune fonte non-`data:`.

### Défaut du lot 16 corrigé : le badge `ATELIER`

Il apparaissait **tronqué** à 1 616 px. Cause : `titleField` portait
`layoutPriority(1)`, donc `HStack` le servait le **premier** et il absorbait
toute la largeur restante — ses voisins étaient mesurés sur ce qui restait, soit
rien. Correctif : priorité **négative** au titre (c'est lui qui doit céder, il
porte une ellipse) et `fixedSize()` sur le badge. Rien d'autre n'est touché dans
`MeetingTopChromeBar`.

### Présence (D11)

Vérifié : aucun reliquat n'affiche la pilule `YP CA 2 personnes dessinent` — il
ne reste que le commentaire de `WorkshopSpaceView` qui explique son absence.

### Jeu de démonstration

`RefonteDemoSeed+Lot17.swift`, en **extension** — ni `RefonteDemoSeed.swift` ni
`+Lot16` ne sont modifiés. `seedWorkshopComplete` appelle le semis du lot 16 puis
réécrit les scènes : `Flux réseau` devient un vrai Schéma (boîtes bleues,
**connecteurs liés** `startBinding`/`endBinding`), `Notes de Patrice` un vrai
Manuscrit (trois `freedraw` avec `pressures` et `simulatePressure: false`), la
planche active porte ses deux objets annotés (`Jenkins…` risque, `Qui porte…`
question), et la réunion gagne la pièce `Archi_cible_Cléva.pdf` de Yann et la
capture Teams de `21:10`. Idempotent. Une seule ligne change dans
`MeetingCommands` : la commande de recette appelle la version complète.

### Tests

`swift build` vert. `swift test` : **1 731 tests Swift Testing verts** (216
suites) et **1 041 XCTest, 1 ignoré, 1 échec** — soit 2 772 contre 2 714 sur la
base, **+58**. L'unique échec est
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, **préexistant et
horaire** : il échoue entre 0 h et 2 h du matin, indépendamment de tout lot, et
la suite a été lancée à **00:54 CEST**. Aucun test ne charge WebKit (plan §8) :
le pont est un protocole, `WhiteboardBridgeDouble` enregistre les huit nouveaux
appels.

### Écarts assumés

- **Lasso** : Excalidraw 0.18.1 n'a **pas** d'outil lasso (`grep lasso` sur le
  bundle : zéro occurrence). L'outil `Lasso` de la palette Manuscrit retombe donc
  sur la sélection **rectangulaire**. À reprendre si le moteur monte de version.
- **Pression** : implémentée, non vérifiée (aucune recette graphique dans ce
  lot ; procédure ci-dessus).
- **Alignement** : recalculé en Swift au lieu de l'`actionManager` d'Excalidraw,
  qui n'est pas exposé — cf. ci-dessus.
- **Calques** (mentionnés dans la table §7.1 du mode Schéma) : **non faits**.
  Ni la capture 6a ni les critères d'acceptation ne les demandent ; à arbitrer.
- **Dépôt sur la toile** : le dépôt de fichier est branché sur la **zone du
  dock**, pas sur la toile elle-même — un `onDrop` par-dessus le `WKWebView`
  entrerait en concurrence avec le glisser interne du moteur. À reprendre en
  recette si le geste manque.
- **Point de dépôt** d'une forme ou d'une image : décalage constant depuis le
  coin haut-gauche de la vue, et non le centre exact du cadre (la page ignore la
  taille de son propre cadre). L'objet est déposé **sélectionné**, donc
  immédiatement déplaçable.
- **Recette visuelle** : aucune, par consigne. La capture de référence
  `6a-atelier-planche.png` n'a donc pas été recomparée après ces ajouts.

**Prochaine action** : lot 18 (planche de séance 6b et rapport d'atelier), qui
dépend de ce lot et du lot 15.

## Refonte de l'écran de réunion — lot 15 : rapport, blocs optionnels, citations (2026-09-08)

Branche `feat/refonte-lot-15-rapport`, **rebasée** sur
`feat/refonte-lot-12-1to1-manager-prepa` (sommet de la pile après l'intégration de la
vague 5). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-15-rapport.md` (14 tâches, toutes faites).

**État : livré, `swift build` propre, `swift test` complet vert — 1 054 XCTest (1 ignoré) +
1 710 Swift Testing (213 suites) = 2 764 tests, contre 2 714 sur la base. Unique échec :
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, préexistant et **horaire**
(échoue entre 0 h et 2 h ; constaté à 00:40 CEST), indépendant du lot et non corrigé ici.
Aucune recette graphique, aucun lancement d'application, aucun appel réseau.**

### Ce qui est en place

**L'audience de confidentialité descend du gabarit, plus du type de réunion.**
`ReportTemplateKind.audience` est une table exhaustive et sans `default` (`.oneToOne` →
`.collaborator`, `.manager` → `.manager`, `.escalade` → `.hr`, tout le reste →
`.projectTeam`), et `ReportAudience.forTemplate` retombe sur
`ConfidentialityFilter.audience(for:)` quand aucun gabarit n'est choisi. Avant ce lot,
`assembleTemplatePrompt` et `ReportHTMLBuilder` la déduisaient tous deux du `MeetingKind` :
une ligne `escalated` d'un 1:1 était écartée **jusque dans l'export Escalade**, ce que le
test `ligneEscaladeeSeulementEnEscalade` a d'abord constaté en rouge. La règle de sortie,
elle, reste `ConfidentialityFilter.isExportable` — jamais réécrite.

**Cinq blocs optionnels, une sélection, deux rendus.** `Services/Report/ReportOptionalBlocks.swift`
choisit et ordonne ; `…Markdown` alimente le prompt (via les variables `{{…}}`), `…HTML`
écrit une annexe **déterministe** du rapport. Deux rendus et non un seul parce qu'un rapport
dont les pièces ne figurent que si le modèle a bien voulu les reprendre ne satisfait pas le
critère n° 3 du chantier 3, qui demande qu'une pièce épinglée soit citée *automatiquement*.

| Variable | Source | Ordre |
| --- | --- | --- |
| `{{pieces_epinglees}}` | `Meeting.pinnedAttachments` (lot 6), case `attachPinned` du pied | `t` croissant |
| `{{captures_jointes}}` | `SlideCapture.includeInReport` (lot 7), 1re ligne d'OCR | `t` puis `index` |
| `{{planches}}` | `Meeting.boards` | `t` puis `index` |
| `{{engagements}}` | `Commitment` du fil pris dans la séance, par côté | côté, puis échéance |
| `{{fiche_projet.maj}}` | `Meeting.acceptedProjectUpdates` (neuf, cf. plus bas) | ordre d'acceptation |

**La page `p.n` se relit dans la puce du lot 6, elle n'est pas persistée.** Une pièce n'a pas
« une » page : on en a cité une à un moment donné. Le bloc cherche donc ` · p.(\d+)` dans les
notes dont le `sourceRef` désigne la pièce, plutôt que d'ajouter une colonne qui inventerait
une vérité. Une capture prise hors enregistrement garde `t == nil` et n'hérite pas de `00:00`
— même refus qu'au lot 7.

**Les engagements se lisent sans rien écrire.** `OneOnOneThreadStore.existingThread` et non
`thread(for:in:)`, qui *crée* un fil : générer un rapport ne doit toucher à rien en base.

**La chaîne de citation porte sur le balisage, pas sur le texte.** `CitationLinker` reconnaît
`<code>mm:ss</code>` (avec un `data-note` facultatif) et non `\b\d{1,2}:\d{2}\b` dans la
prose : « le point est reporté à 14:30 » est un horaire, et en faire un lien enverrait la
tête de lecture à la 870ᵉ seconde d'une séance qui n'en compte peut-être pas tant. La passe
est appliquée aux **seuls** fragments écrits par l'app — notes, pièces, captures, planches,
plan d'actions — jamais à `bodyHTML`, qui vient du modèle. En aperçu, le timecode devient
`onetoone://meeting/<uuid>?t=252&note=<uuid>` ; en `.outlook` (PDF, mail, Apple Notes) il
redevient du texte nu, un schéma privé n'ayant aucun sens hors machine.

**Le clic est intercepté dans l'aperçu, pas par macOS.** `MeetingReportPreview` a désormais un
délégué de navigation : `onetoone://` appelle `onCitation`, un lien externe part dans le
navigateur, et rien ne navigue *dans* la WKWebView (elle n'a ni barre d'adresse ni bouton
retour). **Aucun `CFBundleURLTypes` n'a été ajouté** : le schéma reste interne, comme les
mentions `onetoone://collaborator/…` de l'éditeur markdown.
`QuickLaunchURLHandler.parseCitation` est pur ; `handle(url:router:context:playhead:)` reçoit
la tête de lecture au lieu d'aller la chercher — cf. écart n° 1.

**Les révisions de gabarits sont versionnées par nom.** `BuiltInTemplates.revisions:
[String: Int]` généralise le marqueur ciblé `d2OneToOneRevision` du 2026-05-23 : une ligne est
réalignée sur son seed **une fois par révision**, et l'édition faite ensuite reste intacte —
la règle que `test_seedIfNeeded_doesNotOverwriteEditedBuiltIn` gardait déjà. Le marqueur est
posé même quand la ligne vient d'être insérée : la repousser au lancement suivant écraserait
une édition faite entre-temps. Six gabarits révisés (`d1_global`, `d2_oneToOne` — révision 4,
`d3_manager`, `d4_copil`, `d5_cosui`, `d9_workshop`) ; `d2` gagne aussi la mention « Les notes
privées ne sont jamais incluses. » du pied `CLÔTURER` de la capture 2a.

**Nouveau gabarit `d11_escalade`** (décision D9) : l'unique sortie d'audience `.hr`, donc la
seule qui emporte les lignes `escalated` et qui laisse celles qui n'étaient que `shared`. Son
préambule interdit explicitement ressenti, cran de moral et appréciation de motivation — ce
que quelqu'un dit de son propre état à son manager ne remonte pas à la hiérarchie au détour
d'une escalade. Il est proposé juste après le gabarit du type, et **seulement** sur les deux
types de tête-à-tête.

**Les trois cases du pied agissent enfin, et au moment de l'envoi.**
`Services/Report/ReportSendPreparation.swift` : pièces épinglées + PDF des captures cochées
en annexe, participants **présents** (`participantStatus == .present`) en destinataires,
et versement effectif via `AttachmentImporter.Bucket.project(code:)` + `ProjectAttachment`.
Le lot 6 ne faisait que *persister* ces cases. À l'envoi et pas à la génération : générer est
un geste qu'on répète pour ajuster un gabarit, et verser à chaque essai remplirait la fiche de
doublons. Idempotent par nom de fichier, original intact (D5, vérifié sur disque avec une
racine de stockage injectée dans un dossier temporaire).

**Un bloc vide devient une invite, pas une section vide.** `MeetingReportSpaceInvites` est
sortie de la vue pour être vérifiable sans monter SwiftUI : « Aucune pièce épinglée — épinglez
depuis Ressources. » s'affiche une fois en tête de l'espace Rapport. Une case décochée n'invite
à rien — l'utilisateur a déjà répondu. Le libellé `Rapport ✓ (m:ss)` est inchangé.

### Écarts avec le plan

1. **Le clic sur un timecode ne déplace pas encore la tête de lecture d'un écran ouvert.**
   `MeetingReportSpace` est monté dans `MeetingView.swift:606`, fichier que les conventions
   anti-conflit du lot 15 réservent (« `MeetingView.swift` (rien) »), et une `MeetingPlayhead`
   appartient à l'état d'un écran monté (`MeetingScreenModel`) sans qu'aucun registre ne
   l'expose — celui du lot 0B a justement été retiré. Le lien est **rendu, parsé et testé**
   (`CitationLinkerTests`, `CitationURLHandlingTests`), et `handle` sait faire le `seek` :
   il manque **un argument** — `playhead: screen.playhead` sur `MeetingReportSpace`, puis
   `onCitation:` sur `MeetingReportPreview`. À poser dans la passe qui a la main sur
   `MeetingView.swift`.
2. **`Ce que j'ai livré` (spec §6.2) reste sans variable.** `DeliveredItemsBuilder` (lot 13)
   n'est pas encore sur la pile ; aucune variable n'a été inventée pour l'occuper.
   `d3_manager` porte `{{engagements}}` (« ce qu'il m'a promis ») mais pas les livrables.
3. **`{{planches}}` rend titre, mode, auteur et timecode, sans légende.** La légende textuelle
   générée par l'assistant (`BoardCaptionBuilder`) est au lot 18 ; la variable existe et rend
   déjà l'ordre du temps, testé avec trois `Board` insérés à contretemps.
4. **`Models/OtherModels.swift` gagne une colonne** — `acceptedProjectUpdatesJSON`, la seule
   autorisée. Le lot 9 ne persistait rien de l'acceptation : `accept` mute un
   `ProjectCardDraft`, puis `apply(to:in:)` écrit dans le `Project` ; après `Enregistrer`,
   plus rien ne distingue une valeur validée d'une valeur saisie à la main. Colonne
   **optionnelle à valeur par défaut**, migration légère, aucune version de schéma.
5. **Trois lignes dans `Views/Project/**`** au-delà de l'extension autorisée : la feuille
   d'acceptation gagne une propriété `meeting: Meeting? = nil` et l'appel à
   `recordAcceptance`, et `ProjectCardPanel` passe son `meeting` (qu'il possède déjà, l. 84).
   Sans ce câblage, `{{fiche_projet.maj}}` serait resté vide en pratique. Toute la logique
   vit bien dans `Services/Project/ProjectCardSuggestions+Log.swift`.
6. **Neuf commits pour quatorze tâches.** Les quatre blocs de `ReportOptionalBlocks` vivent
   dans un même fichier : quatre commits successifs y auraient réécrit la même zone.
7. **`ReportOptionalBlocks.escape` duplique `ReportHTMLBuilder.escape`**, qui est `private`.
   L'exposer aurait élargi la surface d'un type dont le rôle est d'assembler un document,
   pas de prêter ses outils.

### Fichiers partagés touchés

`Services/AIReportService.swift` (assemblage seulement : audience, repli des blocs),
`Services/ReportTemplating.swift` (paramètre `audience`, branchement du `default`),
`Services/BuiltInTemplates.swift`, `Services/ExportService.swift` (`composeMeetingMail`),
`Services/QuickLaunchURLHandler.swift` (extension), `Models/ReportTemplate.swift`
(cas `escalade` + audience), `Models/OtherModels.swift` (**une** colonne),
`Views/Settings/ReportTemplateEditorView.swift` (palette), `Views/Meeting/MeetingReportPreview.swift`,
`Views/Meeting/Spaces/MeetingReportSpace.swift`, `Views/Meeting/MeetingTopChromeBar.swift`
(**seulement** `compatibleTemplates`), `Views/Project/{ProjectCardSuggestionsSheet,ProjectCardPanel}.swift`
(trois lignes, écart n° 5), `Services/Report/ReportThemeCSS.swift` (classe `a.tc`).
Aucun fichier de `Views/Meeting/OneOnOne/**`, `Services/OneOnOne/**` (lus seulement),
`Views/Capture/**`, `Services/Capture/**`, `Workshop/**`, `Rail/**`, `Notes/**`, `Review/**`,
`Resources/**`, `Session/**` ni `MeetingView.swift`.

### Prochaine action

Faire relire et fusionner la PR du lot 15 après `#33`. Puis, dans la passe qui a la main sur
`MeetingView.swift`, poser l'argument `playhead` de l'écart n° 1 — c'est la dernière ligne
entre un timecode cliquable et un timecode qui déplace la lecture. Le lot 18 alimentera la
légende de `{{planches}}` ; le lot 13 pourra brancher `Ce que j'ai livré` sur `d3_manager`.

## Refonte de l'écran de réunion — lot 13 : 1:1 collaborateur, écran de séance (5a) (2026-09-08)

Branche `feat/refonte-lot-13-1to1-collab-seance`, **rebasée sur
`feat/refonte-lot-12-1to1-manager-prepa`** (sommet de la pile après l'intégration de la vague 5).
Plan du lot dans `docs/superpowers/plans/2026-09-07-refonte-lot-13-1to1-collab-seance.md`.

**État : livré, `swift build` propre, `swift test` vert (1 742 Swift Testing + 1 041 XCTest,
un seul échec, préexistant et horaire — cf. plus bas), PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** ; le crochet est prêt
(`ONETOONE_SEED_DEMO_SCREEN=5a`).

### L'écran

`kind == .manager` + mode **En séance** → `CollaboratorSessionView`, grille `308 | 1fr | 356`,
**sans** rail d'actions, sans bandeau d'indicateurs, sans présence (spec §3.1, qui vaut pour les
deux types 1:1). Une branche dans `MeetingSpaceView.contenu`, gardée par
`MeetingSpaceRouting.usesOneOnOneCollaboratorSession` — exclusive des trois autres branches 1:1,
ce que `RefonteVague5IntegrationTests` vérifie type par type et mode par mode.

Même parti que le lot 11 : l'instant de référence est la **date de la séance**, pas `Date()`.

| Colonne | Contenu |
| --- | --- |
| Gauche 308 | `MyTopicsCard` (`CE QUE JE VEUX DIRE · ● privé`, sujets numérotés, poignée `⠿`, glisser-réordonner, composeur `Ajouter un sujet…`, mention « Visible de vous seul… »), `MyRequestsCard` (`MES DEMANDES EN COURS`, statut + historique court), barre assistant contexte = fil, question `« Qu'ai-je livré depuis <mois> ? »` |
| Centre 1fr | `Notes de l'entretien`, pilules `● Privé par défaut` (état) / `Partager la ligne` (bouton), sections `CE QU'IL M'A DIT` / `CE QUE J'AI DIT`, bloc `● POUR MOI SEUL`, composeur `Écrire… /promesse /demande /preuve` |
| Droite 356 | `CE QUE J'AI LIVRÉ · auto · depuis le <date>` avec `Citer`, `CE QU'IL M'A PROMIS · n en retard` avec `Promise le …` / `n reports` / `Relancer`, `EN SORTANT` |

Barre du haut, bloc `.manager` : segment `Mes 1:1`, en-tête dérivé `Avec <Manager> — <jour>` en
**placeholder** du titre, et le bouton `Mon récap` — autonome, donc `MeetingView` n'est pas touché.

### La règle « ce que j'ai livré »

`DeliveredItemsBuilder` (pur, 20 tests). Trois sources, et **aucune saisie** :

1. **actions closes** dans `]1:1 précédent, séance]` ;
2. **réunions à rôle actif** dans la même fenêtre, **hors tête-à-tête** (mes 1:1 ne sont pas un
   livrable), portant une décision ou une note de moi ;
3. **actions bloquées** — ouvertes, reportées ou commentées « Bloqué par… » —, **sans borne de
   date** : un blocage est un état présent, pas un événement de la fenêtre.

**« Mes » actions = `destinataire == .moi` ET `collaborator == nil`.** L'utilisateur de
l'application n'est pas un `Collaborator` : il n'a pas de fiche, donc `assignedTasks` ne le
désigne jamais, et `ActionAudience.moi` est la seule désignation qui existe. La seconde condition
est indispensable : `destinataireRaw` vaut `moi` par défaut, et le semis du lot 10 — comme
l'extraction LLM — affecte un responsable sans y toucher. Sans elle, les deux livrables de Laurent
entreraient dans **mes** preuves.

`Citer` **propage** la chaîne de citation au lieu d'en inventer une : `SourceRef.Kind` n'a pas de
cas pour une action et `ActionTask` n'a pas de `stableID` à viser. Une ligne d'action reprend donc
le `sourceRef` de l'action ; une ligne de réunion vise la note qui l'a justifiée. Aucun modèle
n'est modifié. La note de preuve est écrite à `t = 0` : elle cite un fait **antérieur** à
l'entretien.

### Fichiers

**Services (purs, testés) :** `Services/OneOnOne/DeliveredItemsBuilder.swift`,
`Services/OneOnOne/Collaborator/{CollaboratorSessionModel, CollaboratorTopBarModel,
CollaboratorNotePrivacy, PromiseReminders}.swift`.

**Vues :** `Views/Meeting/OneOnOne/Collaborator/{CollaboratorSessionView, MyTopicsCard,
MyRequestsCard, CollaboratorNotesColumn, DeliveredCard, PromisesCard, CollaboratorClosingCard,
MyRecapPreview}.swift`, `Views/Meeting/Spaces/Notes/TimedNotesColumn+Collaborator.swift`.

**Jeu de démonstration :** `Services/Debug/Seed/RefonteDemoSeed+Lot13.swift` — extension, ni
`RefonteDemoSeed.swift` ni `+Lot10` ne sont touchés. Complète le fil de Yann PENVEN (déjà semé par
le lot 10 : 3 demandes, 3 sujets privés, 3 promesses, 5 notes) avec les **quatre lignes** de
`CE QUE J'AI LIVRÉ` : deux actions closes (29 août avec `2 j`, 2 sept.), la réunion de projet du
1er sept. portant sa décision, et l'action bloquée par les comptes GitLab.

**Fichiers partagés touchés, en blocs localisés :** `MeetingSpaceLayout.swift` (deux constantes +
`collaboratorColumns`), `MeetingSpaceRouting.swift` (une fonction), `MeetingSpaceView.swift` (une
branche), `MeetingTopChromeBar.swift` (bloc `.manager`), `OneOnOneScreenState.swift`
(`collabSelectedNoteID`, **en fin de type**), `OneOnOneDateFormat+Views.swift`
(`dayMonthOrdinal`), `RecetteScreen.swift` (code `5a`), `MeetingCommands.swift` (une ligne de
semis). `MeetingView.swift` : **rien**.

### Les trois critères du chantier 5

1. **Rôle visible en permanence** — `CollaboratorTopBarModel.breadcrumbSegments(for:)` est un
   modèle **pur** : la liste des segments ne dépend que du type, donc aucune largeur, aucun
   réglage et aucun état d'écran ne peut masquer la pilule `Je suis le collaborateur`. Testé pour
   `.manager` (présente) et pour tous les autres types (absente).
2. **Aucune ligne partagée sans geste explicite** — `CollaboratorNotePrivacy`. Le défaut est
   `private` par **tous** les chemins d'écriture (composeur nu, `/promesse`, `/demande`,
   `/preuve`, sujet ajouté à la main), et `Partager la ligne` change **une** ligne, jamais la
   séance : c'est pourquoi `● Privé par défaut` est un **état** et non une bascule de séance
   comme au lot 11 — une bascule ici ouvrirait la porte à un « tout partager » d'un clic. Une
   ligne `escalated` ne redescend jamais vers le manager par ce geste (D9).
3. **La liste se remplit sans saisie et se cite en un clic** — `DeliveredItemsBuilder` +
   `DeliveredCard.citer`, qui écrit une note `kind: .proof` portant le `sourceRef` propagé.

Également couverts : tri des promesses par retard décroissant, `> 60 jours` → `report`
(règle du lot 10, `AgendaCarryover.requestLevel`), compte des lignes exclues sur les trois
familles (notes + engagements + sujets → `3 lignes privées seront exclues.`), largeurs à 1 280 /
1 920 / 1 000 / 800 px avec plancher fluide de 520 px, et une invite pour chaque zone vide.

### Écarts avec la capture, assumés

- **La barre du haut garde ses contrôles** (pilule de partage, capture, menu de type, template,
  `Rapport 1:1`). La capture 5a montre une barre réduite à l'audio, `Mon récap` et `⋯` ; les
  retirer rendrait un entretien mal typé à l'import impossible à corriger. `Mon récap` a été
  **ajouté** avant `⋯`.
- **Un titre de section désigne la section d'écriture.** Le parseur du lot 10 déduit l'auteur
  d'une ligne de la **section**, pas de la commande : sans ce clic, une seule des deux sections
  serait accessible au clavier. Même mécanique que `FeedbackCards` au lot 11 ; la capture ne
  montre pas l'affordance. `Citer` écrit directement, donc une preuve tombe toujours dans
  `CE QUE J'AI DIT`.
- **`n reports` au pluriel régulier.** La capture écrit `2 reports` sur une carte et `3ᵉ report`
  sur une autre ; la spec §6.2 dit `n reports`, et c'est cette écriture-là qui est retenue.
- **La question de l'assistant est datée du dernier point tenu** (`depuis août` sur le jeu de
  démonstration) et non figée à `juillet` : la capture n'est pas cohérente avec son propre
  `depuis le 21 août`, et une question figée deviendrait fausse six mois plus tard.
- **`Relancer` ≠ reporter.** `deferralCount` compte les fois où le **manager** a repoussé sa
  parole ; la relance est mon geste, et son compteur vit sur le sujet d'ordre du jour privé créé
  pour la séance suivante. Idempotent par le texte.

### Un échec de test préexistant, horaire

`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` (XCTest) échoue **entre 0 h et 2 h du
matin**, indépendamment de tout lot : la suite a été passée à **00:35 CEST le 8 septembre**, et
c'est le **seul** échec. Non corrigé — il n'appartient pas à ce lot.

### Pour la passe de recette

`ONETOONE_SEED_DEMO_SCREEN=5a` (crochet unique, table `RecetteScreen`) sème les fils et les
quatre livrables, puis ouvre la séance du 4 septembre en mode En séance. Le menu **Réunion**
charge le même jeu.

### Prochaine action

Lot 14 — 1:1 collaborateur, préparation en 2 minutes (5b), qui dépend de ce lot. Le critère
chantier 5 n° 4 (« une promesse du manager non tenue remonte automatiquement à la préparation
suivante ») lui appartient.

## Refonte de l'écran de réunion — lot 8 : pastille flottante (4b) (2026-09-08)

Branche `feat/refonte-lot-8-pastille`, rebasée sur
`feat/refonte-lot-12-1to1-manager-prepa` (sommet de l'intégration de la vague 5). Plan
d'exécution : `docs/superpowers/plans/2026-09-07-refonte-lot-8-pastille.md`.

**État : livré, `swift build` propre, `swift test` complet vert — 1 041 XCTest
(1 ignoré) + 1 729 Swift Testing (215 suites) = 2 770 tests après rebase, contre 2 714
au sommet du lot 12 : **+ 56 tests**. Aucune recette graphique (consigne du 2026-09-07 :
un seul agent pilote le bureau) ; la procédure de recette est écrite plus bas.**

⚠️ **Un échec XCTest préexistant et horaire** : `MenuBarStatsTests`
`test_todayStats_passedOnlyAndNoProject` échoue entre 0 h et 2 h du matin (les réunions
du test sont posées à `startOfDay + 1 h`). Constaté à **00:33 CEST le 2026-09-08**, seul
échec de la suite avant comme après rebase, indépendant de ce lot — non corrigé ici
(une PR = une intention).

### Ce qui a été porté de Teams-Capture (programme §2.5)

Copié **avec ses tests**, jamais lié :

| Élément | Devenu | Ce qu'il apporte |
| --- | --- | --- |
| `CaptureDesign/ScreenCorner.swift` + ses 5 tests | `Views/Capture/Pill/ScreenCorner.swift`, `Tests/ScreenCornerTests.swift` | magnétisation aux 4 coins, coin persisté et non la position, borné sur un écran plus petit que la pastille |
| `CaptureCore/PillMode.swift` (l'idée) | `SessionPillPresentation.swift` | la décision d'affichage est une **fonction pure**, pas un `if` dans le contrôleur |
| `Pill/PillPanelController.swift` | `SessionPillPanelController.swift` | `NSPanel` `.borderless + .nonactivatingPanel`, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground`, débounce 250 ms sur `didMoveNotification`, garde anti-boucle dans `snap`, **un seul panneau agrandi**, `withObservationTracking` réarmé |
| `Pill/FloatingPill.swift` | `FloatingPill.swift` | capsule 300 × 40, séparateur, `TimelineView` pour le chrono, point pulsant **réarmé à chaque transition** |
| `GlobalHotKey.swift` (leçons) | `Services/Capture/CaptureHotkeys.swift` | l'échec d'enregistrement est **publié** et affiché ; le service Carbon de OneToOne (`GlobalHotkeyService`, signature `ONET`) est réutilisé tel quel |

**Propre à OneToOne**, absent de Teams-Capture : `ActiveMeetingRegistry` (Teams-Capture
n'a qu'une session, OneToOne a des réunions), le chrono depuis `MeetingPlayhead`,
l'insertion de la vignette dans les notes, `✎ Note` avec son champ et `⌘⏎`,
`＋ Action depuis la capture`, la première ligne d'OCR qui arrive **après** l'écriture,
le tracé de zone, et le panneau qui accepte le clavier **le temps d'une note**.

### Ce qui est en place

**La « réunion active » est une notion globale, avec une règle pure.**
`ActiveMeetingRegistry.activeID(recording:sessions:)` : celle qui **enregistre**
(`AudioRecorderService.activeMeetingID`) d'abord, sinon la **dernière entrée en séance**.
Une réunion qui enregistre mais dont aucun écran n'est ouvert ne l'emporte pas : elle ne
donne aucune prise, et la désigner ferait disparaître la pastille de la séance qu'on a
sous les yeux. Le registre porte des **poignées** (`ActiveMeetingHandle` : réunion,
modèle d'écran, coordinateur de capture, contexte) parce que la pastille vit dans un
`NSPanel`, sans environnement SwiftUI, sans `@Query` et sans le `@StateObject` de
`MeetingView` qui porte le `ScreenCaptureService`.

**Le critère n° 2 du chantier 4 est testé, pas espéré.** `SessionPillModel` parle à un
protocole `SessionPillTarget` ; la doublure compte les activations d'application, et le
compte attendu est **zéro** sur tout le chemin d'une capture. La chaîne réelle
(`captureNow` → `SlideCapture(t)` → `CaptureNoteInsertion` → confirmation) est testée sur
une vraie réunion en mémoire avec une source d'images doublée : la capture est écrite au
`t` du `MeetingPlayhead`, la note porte un `sourceRef {capture}` au même instant, et
l'ouverture du sélecteur — seul chemin qui ramène dans la fenêtre — n'est jamais
appelée.

**Un seul panneau, agrandi.** La hauteur est une fonction pure
(`sessionPillPanelHeight`) et le contrôleur, seul, redimensionne la fenêtre : c'est le
défaut corrigé dans Teams-Capture (une carte dessinée sous une pastille de 40 px dans une
fenêtre de 40 px est invisible, coupée par le bord). Confirmation et champ de note se
**cumulent** — capturer pendant qu'une note est en cours dessine les deux.

**L'OCR arrive après l'écriture.** La carte part sur « Texte en cours d'extraction… »,
un sondage borné (10 essais de 400 ms, en **parallèle** des 4 s de la carte et non
avant) la complète dès que Vision a rendu, et le quota épuisé elle cesse de promettre un
texte à venir (« Aucun texte extrait »). Copier le texte n'aurait rien réglé : il n'existe
pas encore au moment de la confirmation.

**Une capture impossible se voit.** `SessionPillCaptureResult` distingue « écrite »,
« aucune source » et « échec » : l'échec s'affiche là où la réussite s'afficherait
(`CAPTURE IMPOSSIBLE` + le message du service), et l'absence de source ouvre le sélecteur
**une seule fois** — un raccourci qui réactiverait l'application à chaque frappe est pire
que rien.

**Le panneau n'accepte le clavier que pendant la saisie d'une note.** Un panneau non
activant qui devient fenêtre clé au premier clic volerait le focus à Teams ; un champ de
texte dans une fenêtre qui ne peut pas devenir clé ne reçoit aucune touche, et `✎ Note`
serait un contrôle mort. D'où `SessionPillPanel.acceptsKey`, basculé exactement pendant
la saisie.

**`⌘⇧S` et `⌘⇧N` sont globaux**, enregistrés dans `registerHotkeys()` par le service
Carbon existant, avec deux cases dans les réglages (défaut activées) et un message
d'échec — « ⌘⇧S est déjà utilisé par une autre application. » — qui **s'efface** au
premier enregistrement réussi (piège 14 de `One2One-specs.md`). `⌥⌘⇧S`, ou l'entrée
`Zone…` du menu contextuel de `◫ Capturer`, ouvre le tracé de zone.

**La zone à la souris comble l'écart n° 3 du lot 7.** `RegionSelection` est pure (origine
haut-gauche comme `NormalizedRect`, refus d'un tracé sous 2 % d'un côté),
`RegionSelectorWindow` n'est qu'un `NSPanel` `.screenSaver` qui capte la souris, et
`CaptureSessionCoordinator.startRegionSession` ouvre la session avec `CaptureSource.region`
et son `crop` — la valeur cesse d'être morte dans le modèle.

**Affichage automatique** : `AppSettings.sessionPillMode` (`toujours` / `séance
seulement` — défaut / `jamais`). En « séance seulement », la pastille apparaît en plein
écran de séance, **ou** quand un enregistrement tourne alors que One2One n'est pas au
premier plan ; enregistrement **et** fenêtre devant, elle se retire (la barre du haut
porte déjà l'état). Elle disparaît à la clôture de la séance et à l'arrêt de
l'enregistrement.

### Écarts assumés

1. **Aucune recette graphique.** Consigne du 2026-09-07. La passe dédiée reprendra la
   comparaison avec `4b-pastille-flottante.png`.
2. **La zone est capturée sur l'écran principal.** `ScreenCaptureService.SessionConfiguration`
   ne porte pas d'identifiant d'écran (`windowID == 0` → `DisplayFrameSource()`), donc une
   zone tracée sur un écran secondaire serait lue sur l'écran principal. Ajouter un
   `displayID` touche le fichier du lot 7 : hors périmètre.
3. **La confirmation n'apparaît que si la pastille est visible.** En mode « jamais »,
   `⌘⇧S` capture et insère quand même (la bande et les notes le montrent), mais la carte
   de 4 s n'a pas de fenêtre où s'afficher. `⌘⇧N`, lui, ouvre la pastille le temps de la
   saisie — sinon le champ n'existerait nulle part.
4. **Le point d'entrée est une ligne dans `MeetingSpaceView`**, comme le lot 4 : c'est le
   seul endroit qui tienne à la fois la réunion, son modèle d'écran et le coordinateur de
   capture. `MeetingView` n'est pas touché (test de balayage).
5. **`MeetingScreenModel` n'a pas gagné de ligne** : l'état de la pastille est un état de
   **fenêtre**, pas d'écran de réunion, et il vit dans `SessionPillModel`.
6. **Le sondage de l'OCR plutôt que l'observation SwiftData** : un `NSHostingView` posé
   dans un `NSPanel` n'a pas d'environnement de conteneur, et compter sur l'observation
   d'un `@Model` depuis cette fenêtre serait un pari. Le sondage est borné et testé.

### Procédure de recette (pour la passe dédiée)

1. `Scripts/bump-and-build.sh dev`, ouvrir la réunion de démonstration, passer en
   **mode séance plein écran** (`⌃⌘F`) : la pastille doit apparaître en bas à droite.
2. Ouvrir Teams **en plein écran** par-dessus : la pastille reste visible (c'est
   `[.canJoinAllSpaces, .fullScreenAuxiliary]` qui le garantit ; sans lui elle disparaît
   au partage).
3. La déplacer vers un autre coin, relâcher : elle s'aimante après ~250 ms, et le coin
   survit à un redémarrage de l'application.
4. `⌘⇧S` depuis Teams : la carte `CAPTURÉ · mm:ss` s'affiche 4 s, avec la vignette, la
   première ligne d'OCR (après une seconde), et `＋ Action depuis la capture`. **Aucune
   fenêtre One2One ne doit passer devant**, et l'espace ne doit pas changer.
5. `⌘⇧N`, taper une ligne, `⌘⏎` : la note apparaît dans la colonne au timecode courant.
   `Esc` referme sans rien créer.
6. `⌥⌘⇧S` : le voile plein écran, tracer une zone, la capture suivante est recadrée.
7. Réglages → Pastille flottante : les trois modes, les deux cases, et — en assignant
   `⌘⇧S` à une autre application — le message d'échec.

### Fichiers partagés touchés

`Views/Meeting/Spaces/MeetingSpaceView.swift` (**une** pose de modificateur),
`OneToOneApp.swift` (`registerSessionPillHotkeys`, appelé par `registerHotkeys()`),
`Models/AppSettings.swift` (4 propriétés à valeur par défaut : mode, coin, deux cases —
migration légère, aucune version de schéma), `Views/SettingsHotkeysSection.swift`
(section `Pastille flottante`), `Views/DesignSystem/One2OneTokens.swift` (jetons de la
pastille). `MeetingView.swift`, `MeetingScreenModel.swift` et tous les fichiers du lot 7
sont **intacts** — `CaptureSessionCoordinator` et `ActionComposerService` sont étendus
depuis `Views/Capture/Pill/`.

### Prochaine action

Faire relire et fusionner après le lot 12. Puis la passe de recette dédiée déroule la
procédure ci-dessus (et l'écart n° 1 tombe).

## Intégration vague 5 : la pile redevient linéaire (2026-09-08)

Les lots **16, 7, 11 et 12** ont été développés **en parallèle** — le lot 16 depuis
`feat/refonte-lot-9-fiche-projet`, les trois autres depuis `fix/refonte-1to1-window-crash`.
Ils sont désormais **empilés** dans cet ordre :

```
… → #26 → #29 → #25 → #31 → 16 → 7 → 11 → 12
                              #32  #34  #35  #33
```

Ordre de fusion : `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31 → #32 → #34 → #35 → #33`. Bases : #32 sur `fix/refonte-1to1-window-crash`,
#34 sur le lot 16, #35 sur le lot 7, #33 sur le lot 11.

### Conflits résolus, maillon par maillon

| Maillon | Fichier | Résolution |
| --- | --- | --- |
| **16** (#32) | `STATUS.md` | union, lot 16 puis correctif de fenêtre |
| **7** (#34) | `STATUS.md` | union, lot 7 puis lot 16 |
| | `MeetingTopChromeBar.swift` | fusion automatique, puis la pilule `Local · hors ligne` déplacée **après** la pilule de capture (ordre des blocs, spec §2.1) |
| **11** (#35) | `MeetingCommands.swift` | union des semis dans un seul item de menu |
| | `STATUS.md` | union, lot 11 puis 7 puis 16 |
| | `MeetingSpaceView.swift` | fusion automatique, puis ordre du routage : **Atelier → 1:1 (mode) → standard (mode)** |
| **12** (#33) | `MeetingSpaceRouting.swift` | union des trois fonctions pures |
| | `MeetingAssistantDock.swift` | **un seul** paramètre de contexte, `threadContext` |
| | `MeetingCommands.swift` | une seule ligne de semis des fils 1:1 |
| | `OneToOneApp.swift` | **un seul** crochet de recette |
| | `STATUS.md` | union, lot 12 puis 11 puis 7 puis 16 |

`MeetingScreenModel.swift` (lignes `capture` du lot 7 et `workshop` du lot 16) et
`OneOnOneScreenState.swift` (`prepHistoryExpanded` du lot 12) se sont fusionnés seuls :
les quatre lots ont écrit **en fin de type**, comme la consigne de l'intégration
précédente le demandait. C'est la seule leçon de la vague 4 qui a évité six conflits.

### Harmonisations 11 / 12 — une seule définition par règle

Le lot 12 n'a pas pu lire le `Shared/**` du lot 11 : trois règles existaient en double, et
la préparation (2b) contredisait la séance (2a) sur les deux mêmes engagements.
`Tests/RefonteVague5IntegrationTests.swift` (10 tests) tient désormais chacune.

1. **Teinte du moral.** Deux tables. Elles divergeaient sur `Bien` : `oneOnOne` (violet)
   au lot 12, `ok` (vert) au lot 11. `MoodHistogramModel.tone(for:)` délègue maintenant à
   `OneOnOneMoodTone` (lot 11, `Shared/`) ; un test parcourt les cinq crans et vérifie que
   `MoodScaleModel.tone` et `MoodHistogramModel.tone` rendent la même chose.
   **Tranché** : la table du lot 11, parce qu'elle vit dans `Shared/` et porte déjà
   `isDeep` pour distinguer `Bien` de `Très bien`.
2. **Identité et avatar.** `PrepHeaderModel` relisait le collaborateur et redessinait la
   pastille. Il appelle maintenant `PersonCardModel.name` / `.initials` / `.role`,
   l'en-tête monte `AvatarSide` (34 px, palette du domaine) et l'ancienneté se lit par
   `OneOnOneSeniority`. Ce qui reste propre à 2b : l'**ordinal** `14ᵉ 1:1`, testé, et la
   date en année pleine. Le filtre « Néant » de `CollaboratorIdentity` est monté dans
   `PersonCardModel.role` — il servait aux deux. Le nom de repli devient
   `PersonCardModel.fallbackName` (« Sans interlocuteur », celui du lot 12) ; il y en avait
   deux, dont « Personne inconnue ».
3. **Échéance d'un engagement.** Deux règles pour la même pilule : le lot 11 comparait les
   **semaines calendaires** (« 9 sept. » pour un mercredi de la semaine suivante), le
   lot 12 une **fenêtre de sept jours** (« Mercredi »). `CommitmentsRailModel.duePill`
   appelle maintenant `OneOnOneDateFormat.dueDate`, la seule règle.
   **Tranché** : la fenêtre de sept jours, parce que `ActionCard.libelleEcheance` (lot 3)
   l'applique déjà aux échéances d'action — la semaine calendaire aurait fait lire deux
   règles sur le même écran. Deux tests du lot 11 changent d'attente en conséquence,
   commentaire compris.
   Les deux extensions `OneOnOneDateFormat+Lot11` et `+Prep`, qui déclaraient chacune
   `weekday(_:)`, sont fondues en **`OneOnOneDateFormat+Views.swift`**.
   Le compteur `n× reporté` venait déjà de `CommitmentLedger.deferralLabel` des deux
   côtés : rien à unifier, un test le fige. Les états `Tenu` / `En retard` / `Manqué`
   n'existent que dans le tableau de 2b (le rail de 2a affiche `✓` / `✗`) : **laissés en
   place**, ce n'est pas un doublon mais deux surfaces.
4. **Historique** du `PrepHeader` et bloc historique : inchangés, comme prévu.

### Un seul crochet de recette

Les lots 11 et 12 avaient chacun câblé le leur dans le même `ContentView` :
`ONETOONE_SEED_DEMO_SCREEN=2a` savait choisir la réunion mais pas le mode,
`ONETOONE_SEED_OPEN=1to1` savait choisir la réunion sans savoir laquelle photographier.
Il n'en reste qu'un, `ONETOONE_SEED_DEMO_SCREEN`, et il **nomme l'écran** — le code de la
capture de référence :

| Code | Écran | Réunion ouverte | Mode |
| --- | --- | --- | --- |
| `1a` | cockpit | démonstration | En séance |
| `1b` | espaces et indicateurs | démonstration | En séance |
| `1c` | poste de pilotage | démonstration | Relire |
| `2a` | 1:1 mené, séance | entretien mené | En séance |
| `2b` | 1:1 mené, préparation | entretien mené | Préparer |
| `3a` | tiroir Ressources | démonstration | En séance |
| `3b` | fiche projet en panneau | démonstration | En séance |
| `4a` | sélecteur de capture | démonstration | En séance |
| `6a` | atelier, planche | atelier | En séance |

La table est `OneToOne/Services/Debug/RecetteScreen.swift`, pure et `CaseIterable` : le
test la parcourt. Le mode est écrit dans `UserDefaults` (`MeetingScreenModel.modeKey`)
**avant** l'ouverture — le seul moyen de l'imposer sans clic et de survivre à la relecture
que fait `attach`. Sans code, rien ne change : le cockpit, au mode qu'il a mémorisé.

```bash
Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen 2b --reset
```

`Scripts/recette-run.sh` gagne `--screen <code>` (qui implique `--seed`), valide le code
avant de lancer et le documente dans son en-tête.

### Le jeu de démonstration, tous les semis ensemble

Les six extensions du semis (`Lot5`, `Lot6`, `Lot7`, `Lot11`, `Lot12`, `seedWorkshop`)
sont appelées **une fois chacune** depuis les deux points d'entrée — l'item de menu et le
crochet de recette. Deux tests d'intégration : semer tout **deux fois** ne change aucun
compte (réunions, engagements, humeurs, actions), et le recalage des dates du lot 12
(`alignLot12SessionDates`) laisse la séance du 4 septembre du lot 11 cohérente — elle
reste la dernière du fil, son entretien précédent reste à quinze jours, la ligne
`✓ Accès environnement recette` reste dans `TENUS DEPUIS LE DERNIER 1:1`, et l'histogramme
de 2b garde ses six dates `12/06 26/06 10/07 24/07 21/08 04/09`.

### Vérifications

`swift build` propre à chaque maillon (avertissements préexistants seuls :
`MoodTrend.swift:78`, `AudioCompressionService.swift:46`, les captures non-`Sendable` de
`ManagerCategoryClassifier` et `ManagerSnippetElaborator`). `swift test` complet à chaque
maillon :

| Maillon | XCTest | Swift Testing | Total |
| --- | --- | --- | --- |
| #31 (référence) | 1 041 | 1 361 | **2 402** |
| + lot 16 | 1 041 | 1 423 | **2 464** |
| + lot 7 | 1 041 | 1 530 | **2 571** |
| + lot 11 | 1 041 | 1 622 | **2 663** |
| + lot 12 et harmonisations | 1 041 | 1 673 | **2 714** |

`MeetingView.swift` : **2 063 lignes**, sous le plafond de 2 100 ; le lot 7 en a retiré
l'ancien `ScreenCaptureConfigView` et n'y a laissé que du câblage.

**Un échec XCTest, préexistant et horaire.**
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` construit des réunions à
`startOfDay + 1 h` et `+ 2 h` et les attend **passées** : entre minuit et 2 h du matin
elles sont à venir, et `tempsPasseSeconds` vaut 0 au lieu de 7 200. La même suite est
verte quand elle tourne avant minuit (vérifié à 23 h 57 sur le maillon 16, `exit 0`), et
aucun des quatre lots ne touche `MenuBarStats` ni `TodayStatsCalculator`. **Non corrigé** :
une PR = une intention, et ce test n'appartient à aucun de ces lots. À reprendre à part —
il suffit d'injecter `now` à midi.

### Ce qu'il reste

La branche de recette visuelle `fix/refonte-recette-vagues-1-4` est à rebaser sur ce
sommet ; les recettes des lots 7, 11 et 12 n'ont pas été faites (un seul agent à la fois
pilote le bureau), et celle du lot 16 est à refaire après ses deux correctifs. La barre du
haut porte maintenant, dans le pire cas, fil d'Ariane + `Mon équipe` + badge de type +
pilule `Privé — vous deux` + titre + audio + partage + capture + type + modèle +
`Rapport 1:1` + `⋯` : **le débordement à 1 280 px n'est pas vérifié** — il n'existe aucun
test de largeur de `MeetingTopChromeBar`, et une largeur de `HStack` SwiftUI ne se mesure
pas depuis `swift test`. Le lot 16 avait déjà vu le badge `ATELIER` tronqué à 1 616 px.
C'est le premier point de la recette à venir.

**Prochaine action :** faire relire et fusionner `#32 → #34 → #35 → #33`, rebaser
`fix/refonte-recette-vagues-1-4` sur ce sommet, puis une passe de recette unique
qui parcourt les neuf codes de `--screen` — en commençant par la largeur de la barre du
haut à 1 280 px.

## Refonte de l'écran de réunion — lot 12 : 1:1 manager, écran de préparation (2b) (2026-09-07)

Branche `feat/refonte-lot-12-1to1-manager-prepa`, **sur**
`fix/refonte-1to1-window-crash` : la PR empile donc les lots 0A, 0B, 1a, 1b, 2, 3, 4, 5, 6,
10a, 10b, 9 et le correctif de fenêtre (PR #19 → … → #31, non fusionnées). Plan
d'exécution : `docs/superpowers/plans/2026-09-07-refonte-lot-12-1to1-manager-prepa.md`.

**État : livré, `swift build` propre (debug et release), `swift test` complet vert
(2 443 tests), PR ouverte, non mergée. Recette visuelle **différée à la passe de recette
dédiée** — plusieurs lots tournaient en parallèle sur le même bureau et se tuaient
mutuellement leurs instances ; une seule passe est désormais autorisée à piloter
l'interface.**

### Ce qui est en place

Le mode **Préparer** d'une réunion `.oneToOne` n'est plus la colonne générique du lot 1 :
c'est l'écran de suivi de `2b-1to1-manager-preparation.png`. Il prend **toute la surface**,
comme le poste de pilotage du lot 5 — ni bandeau d'indicateurs (rien n'a encore été dit),
ni rail d'actions de 330 px (spec §3.1 retire les projets affectés et les vues Kanban d'un
1:1).

**Aucun calcul métier neuf.** Tout vient des services purs du lot 10 : `MoodTrend`,
`OneOnOneObjectiveTone`, `ReminderRules`, `CommitmentLedger`, `RecurringTopicsBuilder`,
`OneOnOneThreadStore`. Ce lot n'ajoute que la traduction de ces calculs en lignes
dessinables, et il la met dans des **modèles de vue purs** — un par carte — parce qu'une
vue SwiftUI ne se teste pas et qu'un histogramme périmé ne se voit pas à la relecture.

| Fichier (`Views/Meeting/OneOnOne/ManagerPrep/`) | Modèle pur | Ce qu'il porte |
| --- | --- | --- |
| `ManagerPrepView.swift` | — | L'assemblage : en-tête, rangée de trois cartes, rangée `1fr \| 320`, dock d'assistant. Aucune règle. |
| `PrepHeader.swift` | `PrepHeaderModel` | `Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026`, l'ordinal français, l'avatar, les badges `1:1`/`Privé`, `Historique`, `Démarrer l'entretien`. |
| `MoodHistogram.swift` | `MoodHistogramModel` | Les six barres, la teinte du dernier cran, la tendance, la phrase. **Critère chantier 2 n° 3.** |
| `ObjectivesCard.swift` | `ObjectivesCardModel` | Les trois barres, le ton par avancement, `Revue prévue le 18 sept.`, l'ajout et l'édition inline. |
| `RemindersCard.swift` | `PrepRemindersModel` | Les trois règles dans leur ordre, la puce colorée, `Mettre à l'ordre du jour` et sa désactivation. |
| `CommitmentsTable.swift` | `CommitmentsTableModel`, `PrepCommitmentFilter` | `20 \| 1fr \| 92 \| 84 \| 96`, le filtre, le badge de retard manager, le taux, le composeur `⌘⏎`. |
| `RecurringTopicsCard.swift` | `RecurringTopicsCardModel`, `ChipFlow` | Les chips `label · n` par famille, sur deux lignes dans 320 px. |
| `ThreadHistoryCard.swift` | `ThreadHistoryModel` | Les quatre dernières séances, date mono + résumé d'une ligne, cliquables. |

### Trois décisions à retenir

1. **Le tableau ne montre pas tout le fil.** La capture affiche quatre lignes pour un fil
   qui en compte quatorze, et son pied dit « 8 tenus sur 11 ». Le tableau montre donc les
   engagements **ouverts** plus ceux **soldés depuis l'entretien précédent** — la même
   borne que `TENUS DEPUIS LE DERNIER 1:1` de la capture 2a, et le même calcul
   (`CommitmentLedger.settledSince`). Le pied, lui, compte l'histoire entière : c'est un
   taux de tenue, pas un décompte d'écran.
2. **Un manquement ne se rouvre pas d'un clic.** La pastille d'état solde un engagement
   ouvert et rouvre un engagement tenu, mais reste sans effet sur un `missed` : le
   manquement est un fait de l'entretien, et l'effacer par inadvertance depuis un écran de
   préparation reviendrait à réécrire l'historique. Il faut passer par la séance.
3. **Le mode d'ouverture est imposé sans toucher à `MeetingScreenModel`.** Spec §3 :
   « `2b` s'ouvre par défaut en mode `Préparer` ». `MeetingSpaceRouting.initialMode` est
   pure et rend `nil` dès qu'un choix est mémorisé ; `MeetingSpaceView` l'applique en
   écrivant **et** la clé `UserDefaults` **et** le mode, parce que l'ordre des `onAppear`
   de SwiftUI ne dit pas si `MeetingScreenModel.attach` a déjà relu ses réglages.

### Écritures — un seul service

`Services/OneOnOne/Prep/OneOnOnePrepStore.swift` porte les trois gestes de l'écran :
nouvel engagement, bascule tenu/rouvert, ajout et édition d'objectif. Un fichier
d'extension et non un ajout dans `CommitmentLedger` ou `OneOnOneObjectiveTone` : le lot 10
les documente comme **purs**, et y glisser un `context.insert` les rendrait intestables et
ferait mentir leur en-tête. Deux autres extensions, pures :
`ReminderRules+Prep.areAllOnAgenda` (le bouton sait qu'il a déjà fait son travail) et
`OneOnOneDateFormat+Prep.dueDate` (la quatrième écriture de date du domaine : le jour de la
semaine d'une échéance imminente).

### Jeu de démonstration — `RefonteDemoSeed+Lot12.swift`

Deux choses manquaient au semis du lot 10, et elles ne se voient que sur un écran.

1. **Les dates.** Le lot 10 pose une cadence parfaitement régulière de quinze jours, soit
   `26/06 10/07 24/07 07/08 21/08 04/09`. La capture écrit
   `12/06 26/06 10/07 24/07 21/08 04/09` : **pas d'entretien la première semaine d'août**,
   et l'`HISTORIQUE` saute la même séance. `alignLot12SessionDates` recale le fil sur cette
   grille — cadence nominale pour les deux dernières séances, une période de plus pour tout
   ce qui précède — et réaligne `MoodEntry.recordedAt` sur la date de sa séance, sans quoi
   l'histogramme, qui se trie sur `recordedAt`, se désordonnerait. Les dates sont
   **assignées** depuis le 4 septembre et non décalées : un décalage relatif appliqué deux
   fois reculerait tout le fil d'un mois, et un semis se clique deux fois. Le rang
   « 14ᵉ 1:1 » est conservé.
2. **Les résumés d'une ligne** de l'`HISTORIQUE` : aucun rapport n'est semé, donc
   `Meeting.shortSummary` est vide et la carte retombe sur sa reconstruction
   (`moral « Bien » · <sujet>`). Les quatre phrases de la capture sont écrites à leur date.

Le semis 1:1 du lot 10 **était orphelin** (point tranché n° 3 de l'intégration de la
vague 4). Il est désormais câblé aux deux points d'entrée : l'item de menu « Charger le jeu
de démonstration (refonte) » et la variable `ONETOONE_SEED_DEMO` de la recette. Quelle
réunion s'ouvre se choisit avec `ONETOONE_SEED_DEMO_SCREEN=<code>` — l'entretien de
démonstration n'était atteignable qu'à la souris, et une recette doit être reproductible
sans clic. *(Ce lot avait écrit une seconde variable, `ONETOONE_SEED_OPEN=1to1` ;
l'intégration de la vague 5 l'a fondue dans le crochet unique — cf. la section en tête.)*

### Fichiers partagés touchés, à la ligne près

- `Services/Meeting/MeetingSpaceRouting.swift` : **deux fonctions pures**
  (`usesOneOnOnePreparation`, `initialMode`). Rien de retiré.
- `Views/Meeting/Spaces/MeetingSpaceView.swift` : **une branche** dans `contenu`, la vue
  `preparation1a1`, et le `onAppear` du mode d'ouverture. Le rail, le bandeau et le tiroir
  sont inchangés pour tous les autres modes.
- `Views/Meeting/Spaces/MeetingAssistantDock.swift` : **un paramètre optionnel**
  `threadContext` (spec §3.3 : « contexte = fil, pas seulement la réunion »). `nil` hors
  1:1, et la barre est alors exactement celle d'avant.
- `Services/OneOnOne/OneOnOneScreenState.swift` : **une propriété en fin de type**,
  `prepHistoryExpanded`. Le filtre du tableau réutilise `commitmentSideFilter` du lot 10 —
  aucune propriété d'état en double.
- `Views/Menus/MeetingCommands.swift` : une ligne (`seedLot12`).
- `OneToOneApp.swift` : le semis de recette appelle `seedLot12` et choisit la réunion à
  ouvrir. Six lignes, additives *(récrites à l'intégration : `RecetteScreen` et le seul
  `ONETOONE_SEED_DEMO_SCREEN`)*.
- **Intacts** : `MeetingScreenModel.swift`, `MeetingTopChromeBar.swift`, `MeetingView.swift`,
  `MeetingPrepareSpace.swift`, `Rail/**`, `Review/**`, `Session/**`, `Resources/**`,
  `Notes/**`, et tous les fichiers existants de `Services/OneOnOne/` sauf la propriété
  d'état ci-dessus.

### Tests

`swift build` propre (mêmes avertissements préexistants, dont `MoodTrend.swift:78` sur
`historyLength`, vérifié présent avant ce lot). `swift test` complet : **1 041 XCTest
(1 ignoré, 0 échec) + 1 402 Swift Testing dans 180 suites, 0 échec** — 2 443 tests, soit
**+41** par rapport à la référence de 2 402.

Trois suites nouvelles :

- `ManagerPrepModelsTests` (20) : en-tête et ordinal, histogramme et **critère chantier 2
  n° 3** (une `MoodEntry` saisie pour la séance courante apparaît aussitôt dans la série, et
  une correction remplace la barre au lieu d'en ajouter une), objectifs et bornes, ordre des
  rappels et désactivation du bouton, chips, historique (quatre lignes, courante exclue,
  déplié, résumé reconstruit, invite), idempotence du semis et des dates.
- `ManagerPrepCommitmentsTableTests` (13) : quatre lignes et non quatorze, tri, porteurs et
  teintes, les cinq écritures de la colonne `ÉCHÉANCE`, fenêtre du jour de la semaine,
  filtre, **critère chantier 2 n° 2** (badge « 1 en retard côté manager » et taux
  « 8 tenus sur 11 · taux 73 % »), composeur, bascule d'état, largeurs de colonnes.
- `ManagerPrepRoutingTests` (8) : aiguillage `(1:1, Préparer)` seul, mode d'ouverture,
  respect d'un choix mémorisé, contexte de fil de la barre d'assistant.

**Aucune zone vide sans invite** : les six modèles portent un `isEmpty` et la vue
correspondante monte un `MeetingEmptyInvite`. Un fil neuf (aucune humeur, aucun objectif,
aucun engagement, aucun sujet, aucune séance antérieure) est couvert test par test.

### Recette visuelle — différée

**Aucune recette n'a été lancée pour ce lot**, et c'est une consigne, pas un oubli :
plusieurs lots de la vague travaillaient en parallèle sur le même bureau et se tuaient
mutuellement leurs instances. Une **passe de recette dédiée** la fera, seule à piloter
l'interface.

Ce qu'elle aura à faire, et tout est prêt pour cela :

```bash
swift build -c release                        # fait, propre
Scripts/recette-app.sh /tmp/recette-lot12
# `--screen 2b` sème tout le jeu et ouvre l'entretien en mode Préparer
Scripts/recette-run.sh --app /tmp/recette-lot12/OneToOne.app --screen 2b --reset
```

Puis capturer `recette/lot-12-1920.png` et `recette/lot-12-1280.png` et les comparer à
`2b-1to1-manager-preparation.png`. Les écarts **déjà connus** — relevés en lisant la
maquette et les données semées, pas un rendu — sont listés ci-dessous : ils servent de
grille de lecture à cette comparaison, qui doit surtout chercher ce que cette liste ne
contient pas (métriques, alignements, hauteurs de carte, retours à la ligne).

### Écarts attendus avec la capture 2b

1. **Le tri met l'engagement en retard en première ligne**, là où la maquette l'affiche en
   deuxième. C'est la règle de la spec §6.2 (« cartes triées par retard décroissant »), et
   c'est aussi la seule qui se défend : ce qu'on doit depuis six semaines se lit avant ce
   qu'on doit vendredi.
2. **L'objectif à 10 % est ambre et non violet.** La spec §3.4 dit « < 30 % `warn` », et
   `OneOnOneObjectiveTone` la porte depuis le lot 10, testée. La maquette colore cette barre
   en violet : elle se contredit elle-même. La spec fait foi.
3. **Les phrases des rappels sont celles de `ReminderRules`**, pas celles de la maquette :
   « Vous lui devez Retour sur la grille d'astreinte — reporté 2 fois. » (la maquette écrit
   « un retour »), « Mobilité archi évoquée 3 fois, jamais tranchée. » (sans « depuis
   avril »), « Féliciter pour la présentation COSUI. » (sans « du 1er sept. »). Les
   corriger demanderait de toucher `Services/OneOnOne/ReminderRules.swift`, hors périmètre
   de ce lot et couvert par les tests du lot 10.
4. **La phrase sous l'histogramme est `MoodTrend.explanation`** : « Cause citée 5 fois :
   Charge de travail. » La maquette écrit « Deuxième séance consécutive sous « Bien ». Cause
   citée deux fois : charge sur la migration AP. » Sa première phrase n'est portée par
   aucune règle du lot 10 — et elle contredit son propre histogramme, où une seule séance
   est sous « Bien » ; son comptage n'est pas celui du fil. La spec §3.4 ne demande que « le
   sujet récurrent le plus cité sur la période », qui est ce qui s'affiche.
5. **`taux 73 %`** avec l'espace de la typographie française (lot 10), là où la maquette
   écrit `taux 73%`.
6. **L'échéance imminente affiche `Samedi` et non `Vendredi`** : le jeu du lot 10 pose cette
   échéance au lendemain du 4 septembre 2026, qui est un samedi. La règle d'affichage est
   bonne, la donnée semée diffère d'un jour ; la corriger touche le semis du lot 10.
7. **La barre du haut de l'application reste au-dessus de l'en-tête violet** (fil d'Ariane,
   barre d'espaces, sélecteur de mode). La maquette ne montre que le composant 2b : c'est le
   même écart que les captures 1a, 3b et 1c, et il est assumé depuis le lot 1.
8. **`MeetingPrepareSpace.swift` n'a pas de branche.** Le programme en prévoyait une ; le
   routage est finalement dans `MeetingSpaceView`, à l'endroit exact où le mode Relire du
   lot 5 est déjà aiguillé. Y passer aurait obligé à traverser `MeetingPrepareSpace` avec
   cinq paramètres (`screen`, `menuActions`, `historique`, `isAssistantOpen`,
   `onOpenMeeting`) dont elle n'a aucun usage — et le programme §8 interdit exactement cela.
   Un fichier partagé de moins touché, aussi, pendant que les lots 7, 11 et 16 tournent.

### Doublons probables avec le lot 11, à harmoniser à l'intégration

Le lot 11 crée `Views/Meeting/OneOnOne/Shared/**` et `Views/Meeting/OneOnOne/Manager/**`
pendant que ce lot vit dans `ManagerPrep/**`, sans les voir. À la passe d'intégration :

- **L'avatar et l'identité** : `PrepHeader.avatar` et le sous-titre `rôle · nᵉ 1:1 · date`
  recouvrent la `PersonCard` et l'`AvatarSide` du lot 11. Le modèle à garder est
  `PrepHeaderModel` (l'ordinal français y est testé) ; le rendu peut passer dans `Shared/`.
- **L'échelle de moral** : `MoodHistogramModel.tone(for: MoodLevel)` et la `MoodScale` du
  lot 11 doivent donner la **même** teinte par cran, sinon la séance et la préparation
  colorent le même « Sous tension » différemment. Une seule table, dans `Shared/`.
- **La ligne d'engagement** : `CommitmentsTableModel.Row` et `CommitmentRow` du lot 11
  portent tous deux le porteur, l'échéance et le compteur de reports. Les libellés
  (`Moi`/`<Prénom>`, `Tenu`, `En retard`, `n× reporté`) doivent être calculés une fois.
- **Le contexte d'assistant** : si le lot 11 ajoute lui aussi un paramètre à
  `MeetingAssistantDock`, il porte le même nom (`threadContext`) — l'union est alors
  triviale.
- **Le semis** : le lot 11 câble peut-être `seedOneOnOneThreads` au même endroit. La ligne
  de `MeetingCommands` et celle d'`OneToOneApp` ne doivent pas être doublées ; `seedLot12`
  appelle déjà `seedOneOnOneThreads`, qui est idempotent.

### Laissé de côté

- La carte `À NE PAS OUBLIER` n'offre pas de retrait ligne par ligne : le bouton verse tout
  ou rien. La spec ne demande pas plus, et un rappel qu'on écarte sans le traiter est
  précisément ce que la carte veut empêcher.
- Le composeur d'engagement ne saisit ni échéance ni porteur : porteur `Moi` par défaut
  (spec §3.4), échéance à poser en séance. Un sélecteur de date dans un pied de tableau
  aurait été un formulaire.
- `Historique` déplie la carte au lieu de naviguer vers `CollaboratorFicheView` : la fiche
  collaborateur n'est pas un panneau de l'écran de réunion, et l'y ouvrir demanderait un
  point d'entrée que ce lot n'a pas à inventer.
- Le mode `.manager` (je suis le collaborateur) garde la préparation générique : son écran
  est la capture 5b, au **lot 14**.

### Prochaine action

Faire relire la PR, puis la fusionner **après** le lot 11 (les deux touchent
`MeetingAssistantDock` et se partagent les composants 1:1) et exécuter la passe
d'harmonisation `ManagerPrep/**` ↔ `Shared/**` décrite ci-dessus. La **recette visuelle du
lot 12 reste due** : elle appartient à la passe de recette dédiée, avec la commande donnée
plus haut.

## Refonte de l'écran de réunion — lot 11 : 1:1 manager, écran de séance (2a) (2026-09-07)

Branche `feat/refonte-lot-11-1to1-manager-seance`, sur `fix/refonte-1to1-window-crash` (sommet de
la pile linéaire). Plan du lot dans
`docs/superpowers/plans/2026-09-07-refonte-lot-11-1to1-manager-seance.md`.

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** (consigne du 7 septembre : plusieurs
agents pilotaient le même bureau et se tuaient mutuellement leurs instances ; une seule passe est
désormais autorisée à piloter l'interface). Le crochet est prêt, cf. « Pour la passe de recette ».

### L'écran

`kind == .oneToOne` + mode **En séance** → `ManagerSessionView`, grille `300 | 1fr | 320`,
**sans** rail d'actions, sans bandeau d'indicateurs, sans présence (spec §3.1). Une branche dans
`MeetingSpaceView.contenu`, gardée par `MeetingSpaceRouting.usesOneOnOneManagerSession`.

L'instant de référence de l'écran est la **date de la séance**, pas `Date()` : « il y a 2 sem. »,
« Vendredi » et « tenus depuis le dernier 1:1 » parlent de l'entretien qu'on tient, pas du jour où
on le relit.

| Colonne | Contenu |
| --- | --- |
| Gauche 300 | `PersonCard` (avatar 34, nom, `Ingénieur CI/CD · dans l'équipe depuis 3 ans`, `DERNIER 1:1` / `RYTHME`), `ManagerAgendaCard` (avatar 16 px du côté ajoutant, barré si traité ou reporté, `→ 18/09`, composeur `Ajouter un sujet…`, glisser-réordonner), `ManagerPendingTopicsCard`, barre assistant contexte = fil |
| Centre 1fr | `Notes de l'entretien · liées à l'audio`, pilules `Partagé` / `Privé`, `MoodScale` (5 crans, cran choisi bordé), `① / ② / ③`, bloc privé isolé, `FeedbackCards`, composeur `Écrire… /engagement /feedback /privé` |
| Droite 320 | `ENGAGEMENTS DE CETTE SÉANCE` (`Moi · n` / `<Prénom> · n`, pilules échéance / charge / criticité / confidentialité), `TENUS DEPUIS LE DERNIER 1:1` (`✓` / `✗ n× reporté`), `CLÔTURER` |

Barre du haut, bloc `.oneToOne` : segment `Mon équipe`, pilule `● Privé — vous deux`,
`Rapport 1:1 ✓`, et l'en-tête dérivé `<Nom> — entretien du <jour>` en **placeholder** du titre.

### Fichiers

**`Views/Meeting/OneOnOne/Shared/**` — lisibles par les lots 12 à 14, qui ne les modifient pas :**
`OneOnOneSeniority`, `OneOnOneMoodTone`, `OneOnOneNoteSections`, `CommitmentsRailModel`,
`PersonCardModel`, `ManagerAgendaModel`, `OneOnOneComposerContext`, `AvatarSide`, `PersonCard`,
`MoodScale`, `CommitmentRow`, `OneOnOneInlineComposer`.

**`Views/Meeting/OneOnOne/Manager/**` :** `ManagerSessionView`, `ManagerAgendaCard` (+
`ManagerPendingTopicsCard`), `ManagerNotesColumn`, `FeedbackCards`, `CommitmentsRail`.

**Ailleurs :** `Views/Meeting/Spaces/Notes/TimedNotesColumn+OneOnOne.swift`
(`OneOnOneNotesSection`, `TimedNotesColumn.swift` **intact**),
`Services/OneOnOne/OneOnOneDateFormat+Lot11.swift`,
`Services/Debug/Seed/RefonteDemoSeed+Lot11.swift`.

### Fichiers partagés touchés, à la ligne près

- `Services/Meeting/MeetingSpaceLayout.swift` : deux constantes (`oneOnOneLeftWidth = 300`,
  `oneOnOneRailWidth = 320`) et `oneOnOneColumns`, qui **délègue** à
  `columns(totalWidth:rail:sideNav:)` — la règle « la colonne fluide ne descend pas sous 520 px »
  reste écrite une seule fois.
- `Services/Meeting/MeetingSpaceRouting.swift` : une fonction.
- `Views/Meeting/Spaces/MeetingSpaceView.swift` : une branche `else if`.
- `Views/Meeting/Spaces/Notes/NoteComposer.swift` : trois paramètres optionnels (`commands`,
  `oneOnOne`, `placeholder`), tous `nil` par défaut — rendu et validation des autres types
  inchangés. Cliquer une pilule **remplace** la commande en tête au lieu de l'empiler.
- `Views/Meeting/Spaces/MeetingAssistantDock.swift` : `Contexte` optionnel ; `nil` laisse la barre
  de la capture 1a mot pour mot.
- `Views/Meeting/MeetingTopChromeBar.swift` : quatre fonctions statiques et trois insertions
  localisées.
- `Models/OneOnOneModels.swift` : `Commitment.blocksOther` (défaut `false`), en fin de type.
- `Models/OtherModels.swift` : `Collaborator.joinedAt` (optionnelle), en fin de type. Les deux sont
  des colonnes à valeur par défaut → migration légère, `CurrentSchema` reste `SchemaV3`.
- `Views/Menus/MeetingCommands.swift` : une ligne (`seedLot11`), qui câble enfin
  `seedOneOnOneThreads` du lot 10.
- `OneToOne/OneToOneApp.swift` : le crochet de recette `ONETOONE_SEED_DEMO_SCREEN`.
- `MeetingView.swift` : **rien**.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 041 XCTest (1 ignoré, 0 échec) + 1 453 Swift Testing dans 187 suites, 0 échec** — 2 494 tests,
soit **+92** par rapport à la référence de 2 402.

Dix suites nouvelles : `OneOnOneSessionLayoutTests` (10), `OneOnOneSeniorityTests` (8),
`CommitmentsRailModelTests` (13), `OneOnOneNoteSectionsTests` (8),
`OneOnOneComposerContextTests` (12), `OneOnOneAgendaCardTests` (12), `OneOnOneMoodScaleTests` (8),
`OneOnOneClosingTests` (5), `OneOnOneTopChromeSessionTests` (5), `RefonteDemoSeedLot11Tests` (11).

### Critères d'acceptation couverts

- **Chantier 2 n° 2** — engagement manqué **côté manager** visible dans le rail avec son compteur
  de reports : `CommitmentsRailModelTests.engagementManqueDuManager` et
  `RefonteDemoSeedLot11Tests.lignesDuLedger` (`✗ Retour sur la grille d'astreinte — YP · 2×
  reporté`, en tête de liste).
- **Chantier 2 n° 3** — le moral saisi écrit un `MoodEntry` de la séance, **remplace** le relevé
  existant (la série de six barres garde sa longueur) et le delta change de sens dans la même
  seconde : `OneOnOneMoodScaleTests`.
- **Sections de notes par nature** — `OneOnOneNoteSectionsTests` : `③` par `kind: feedback`, `①` la
  première ligne, `②` tout le reste ; aucune ligne ne peut n'apparaître dans aucune section.
- **Pilules du composeur par type et par rôle** — `OneOnOneComposerContextTests` : les trois du
  manager, les trois du collaborateur, les quatre du lot 2 ailleurs, et le rôle qui prime sur le
  type.
- **Largeur 1 280 px** — `OneOnOneSessionLayoutTests` : `(300, 660, 320)`, colonne fluide ≥ 520,
  somme exacte, aucune largeur négative de −100 à 1 920 px.
- **Aucune zone vide sans invite** — invites testées pour l'ordre du jour vide, le suspens vide, les
  deux groupes d'engagements vides, le registre vide, les trois sections et les deux cartes de
  feedback ; sans participant, l'écran propose `Gérer les participants` au lieu de trois colonnes
  muettes.
- **Chantier 2 n° 1** (revérifié depuis l'écran qui déclenche l'envoi) — `OneOnOneClosingTests` : la
  note privée `17:30` ne sort pas du récap collaborateur.

### Points tranchés

1. **Le titre d'un entretien reste éditable.** L'en-tête dérivé
   `Laurent NOMINÉ — entretien du 4 septembre` est le **placeholder** du champ de titre, pas son
   remplacement : la barre du haut est le seul point d'entrée de l'application pour renommer une
   réunion, et le retirer pour un type aurait été une perte de fonction. Conséquence sur la
   maquette : le jeu de démonstration affiche son titre semé (`1:1 — Laurent · 14`) et non le texte
   de la capture — cf. écart n° 1.
2. **`ENGAGEMENTS DE CETTE SÉANCE` n'affiche que les engagements ouverts et non en retard.** Un
   engagement soldé ou déjà en retard figure dans le registre juste en dessous ; l'afficher deux
   fois dans la même colonne ferait compter deux paroles là où il n'y en a qu'une. C'est ce que
   montre la capture (`Moi · 2`, la grille d'astreinte étant dans le registre) et c'est un test du
   jeu de démonstration qui l'a établi.
3. **Le registre inclut les retards non soldés, en `✗`.** « Tenus depuis le dernier 1:1 » ne garde
   pas que les soldés : un engagement jamais fermé disparaîtrait de l'écran, ce qui est l'inverse du
   critère n° 2.
4. **La pilule d'échéance dit le jour de la semaine dans la semaine en cours, la date au-delà.**
   « Vendredi » ne veut dire quelque chose que dans la semaine où il est prononcé — c'est la règle
   qui rend les quatre pilules de la capture (`Vendredi`, `9 sept.`, `11 sept.`, `30 sept.`)
   cohérentes entre elles.
5. **`① COMMENT ÇA VA` prend la première ligne de la séance.** La spec décrit une progression, pas
   une colonne « section » : `③` se déduit de `kind: feedback`, et la réponse à la question posée
   est la première chose écrite. Convention assumée, documentée dans `OneOnOneNoteSections`, et
   c'est celle que montre la capture.
6. **La bascule `Partagé` / `Privé` ne repeint pas l'historique.** Elle gouverne les lignes
   **suivantes** ; un changement de défaut qui rendrait publique une note écrite en privé serait le
   pire défaut possible de cet écran. Réglage de séance, en `@State` : le persister mettrait dans un
   backup la trace d'un clic d'interface.
7. **Deux colonnes de données, pas une dérivation.** `Commitment.blocksOther` (`Bloquant pour lui`)
   et `Collaborator.joinedAt` (l'ancienneté) sont des faits dits par les personnes, pas des
   calculs : ni l'échéance ni le porteur ne disent si un retard empêche l'autre d'avancer.

### Écarts assumés

1. **Le titre de la 14ᵉ séance du jeu de démonstration n'est pas celui de la capture.** Le semis du
   lot 10 utilise le titre comme **clef d'idempotence** (`1:1 — Laurent · 14`) : le renommer ferait
   recréer une quinzième séance au semis suivant. Le lot 11 ne touche donc pas aux titres, et
   l'en-tête de la capture apparaît en placeholder d'un entretien sans titre. À trancher au lot 12,
   qui porte l'en-tête de 2b.
2. **`⌘K` n'est pas encore restreint au fil.** `MeetingAssistantDock.Contexte` transporte le
   `threadID`, et la barre affiche `Interroger l'historique des 1:1 de Laurent`, mais le panneau
   ouvert reste `MeetingChatView` à la portée de la réunion. Le câblage de la portée côté chatbot
   appartient au lot 15.
3. **Le glisser-réordonner de l'ordre du jour est fait à la main** (`onDrag` / `onDrop` +
   compactage des rangs) et non avec une `List` : la colonne vit dans une `ScrollView`, et une
   `List` imbriquée y déclenche le `_NSDetectedLayoutRecursion` que le programme §2.4 demande
   d'éviter. Pas d'indicateur d'insertion : la ligne saute à sa nouvelle place au dépôt.
4. **Pas de colonne de transcription en 1:1.** La spec §3.1 retire du type tout ce qui regarde
   ailleurs que la personne, et la capture montre une colonne de notes pleine largeur. La
   transcription reste en mode Relire.
5. **La capture d'écran n'est pas reléguée dans `⋯`.** Le bouton `Capture` de la barre du haut est
   commun à tous les types ; la spec §3.1 demande de le déplacer pour le 1:1. Un geste dans un
   fichier partagé, à faire avec le lot 7 (qui réécrit ce bouton).
6. **`AppSettings.ownerName` porte les initiales de « Moi ».** Il est vide sur une installation
   neuve : les pastilles affichent alors `?`. Le jeu de démonstration le renseigne ; aucune invite
   ne le réclame encore à l'écran.

### Pour la passe de recette dédiée

```bash
swift build -c release
Scripts/recette-app.sh /tmp/recette-lot-11
ONETOONE_SEED_DEMO_SCREEN=2a Scripts/recette-run.sh \
  --app /tmp/recette-lot-11/OneToOne.app --seed --reset
```

La variable ouvre directement la séance de la capture (Laurent NOMINÉ, 4 septembre) en mode En
séance. Captures attendues : `recette/lot-11-1920.png` et `lot-11-1280.png`, à comparer à
`docs/superpowers/specs/refonte-2026-09/ecrans/2a-1to1-manager-seance.png`. Écarts déjà connus : le
titre de la séance (écart n° 1) et le bouton `Capture` encore dans la barre (écart n° 5).

### Prochaine action

Fusionner dans l'ordre de la pile, puis le **lot 12** (1:1 manager, préparation `2b`), qui lit les
composants de `Views/Meeting/OneOnOne/Shared/**` sans les modifier et n'écrit que dans
`Views/Meeting/OneOnOne/ManagerPrep/**`.

## Refonte de l'écran de réunion — lot 7 : captures Teams / Zoom (4a) (2026-09-07)

Branche `feat/refonte-lot-7-captures`, **sur** `fix/refonte-1to1-window-crash` : la PR
empile donc toute la pile linéaire (PR #19 → … → #25 → #31). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-7-captures.md` (14 tâches, toutes faites).

**État : livré, `swift build` propre, `swift test` complet vert — 1 041 XCTest (1 ignoré) +
1 468 Swift Testing (185 suites) = 2 509 tests, contre 2 402 au sommet. Recette visuelle
différée à la passe de recette dédiée (consigne du 2026-09-07 : un seul agent est autorisé
à piloter l'interface).**

### Ce qui a été porté de Teams-Capture (programme §2.5, décision D7)

Copié **avec ses tests**, jamais lié (aucune dépendance SwiftPM) :

| Élément | Devenu | Ce qu'il apporte |
| --- | --- | --- |
| `CaptureCore/MeetingType.swift` (table de profils) | `Services/SlideCapture/CaptureProfile.swift` | `CaptureProfile` par `MeetingKind` + `captureHint` affiché sous les bascules |
| `CaptureSettings.detectsAutomatically/periodicCapture` | `SlideCaptureSettings` (mêmes champs) | les deux bascules du sélecteur |
| `SessionController.TunedField` | `Services/SlideCapture/CaptureTuning.swift` | changer de type n'écrase pas un réglage fait à la main |
| `SlideDetector.acknowledge` | même nom | pas de doublon après une capture manuelle ou périodique |
| `CaptureCoordinator` (périodique, `captureNow`, horloge injectée) | `ScreenCaptureService` | l'échéance **arme**, le premier tick stable écrit |
| `CaptureCoordinatorTests` (785 l.) | `Tests/CapturePortedCoordinatorTests.swift` (17 tests) | dérive lente, tick en vol, détection coupée, périodique |
| `Cockpit/SourcePopover.swift` | `Views/Meeting/Capture/CaptureSourcePopover.swift` | mise en page 346 px, `PrimaryButtonStyle`, libellés |
| `Cockpit/CaptureRail.swift` | `Views/Meeting/Capture/CapturesStrip.swift` | vignettes 132 × 76, tuile manuelle, raccourci hors cellule lazy |
| `Cockpit/TopBar`, `IndicatorStrip` | pilule de `MeetingTopChromeBar` | `● Capture · Teams 3 ⌄`, `Source perdue` |

**Propre à OneToOne**, absent de Teams-Capture : le lien `t` ↔ audio (`MeetingPlayhead`
comme unique axe de référence), la persistance `SlideCapture` en base avec `source` et
`trigger`, l'OCR et son indexation, l'insertion dans les notes, `＋ Note` / `＋ Action`
depuis la bande, Zoom, l'écran entier (`DisplayFrameSource`), et les bascules
**applicables en cours de séance** — Teams-Capture les gelait pendant la capture, alors
que la capture 4a les montre actives avec trois captures déjà prises.

### Ce qui est en place

**La capture a une source, un déclencheur et un instant.** Une session porte désormais
`source` (`teams/zoom/screen/region`), `detectsAutomatically` et `periodicCapture`, et
chaque `SlideCapture` écrite reçoit les trois colonnes du lot 0B. Le `t` vient du
`MeetingPlayhead` de la réunion — **jamais** de l'horloge de la session de capture : une
note et une capture prises au même moment doivent porter le même instant. Sans axe temps
(ni enregistrement, ni lecture), la capture est écrite **sans** `t` plutôt qu'à `00:00`, où
son carré désignerait un instant où rien ne s'est passé.

**L'échéance périodique arme, elle n'écrit pas.** Écrire au moment de l'échéance donnerait
une image floue au milieu d'une transition : le premier tick non `.settling` qui suit
écrit, avec `trigger: .interval`. Une capture manuelle repousse la suivante — l'échéance se
compte depuis la dernière écriture, quelle qu'en soit l'origine. Trois tests transposés le
prouvent, dont celui où huit ticks de mouvement précèdent deux ticks stables : une
implémentation qui n'écrirait *jamais* rien passerait le premier test, pas celui-là.

**`captureNow()` est le seul chemin manuel.** Il acquitte le détecteur **avant** d'écrire :
entre l'acquittement et l'écriture il y a un `await`, et un tick déjà en vol peut s'y
stabiliser sur le même contenu et l'écrire une seconde fois. `snapshot()` y délègue — deux
implémentations du même geste divergeaient sur l'anti-doublon (l'ancienne amorçait le
détecteur *après* l'écriture, ce qui ne résiste pas au tick en vol).

**`Source perdue` est un état, pas un dialogue** (spec §5.2). `pauseCause` distingue la
source disparue (fenêtre fermée, autorisation refusée, écran débranché) d'un échec d'API :
la première fait passer la pilule en `accent/warn` avec un lien de reconfiguration, la
seconde n'est qu'un message. Aucune boîte de dialogue ne s'ouvre en séance. Le message
d'erreur est remis à zéro sur **tous** les chemins de succès, écriture comprise (piège 14
de `One2One-specs.md`).

**Le sélecteur dit la vérité sur chaque source.** `CaptureSourceCatalog` est pur : il reçoit
les fenêtres partageables et rend les trois lignes de la capture 4a. Le titre de la fenêtre
Teams sert **uniquement** à détecter la réunion active (décision D7) ; « un partage est en
cours » vient du détecteur d'image (`isContentMoving`). Le partageur n'est nommé que s'il
est déjà **participant de la réunion** : deviner un prénom depuis un mot du titre
produirait « partage de Réunion en cours ». Zoom est reconnu par son seul bundle
(`us.zoom.xos`), et l'écran entier est toujours proposé — un sélecteur sans aucune ligne
active serait un cul-de-sac.

**Tout se lit sans ouvrir de menu** (critère n° 1). `CaptureState.pill` est une fonction
pure : `idle` → bouton neutre `Capture` ; `armed(source, count, automatic)` → pilule
`● Capture · Teams 3 ⌄` en `accent/ok` bordée, le point vert quand la détection écrit
d'elle-même, gris quand elle attend un geste ; `lost(count)` → `Source perdue`, **compteur
conservé** (les captures déjà prises ne disparaissent pas avec la source). Le chevron fait
ce qu'il annonce : il rouvre le sélecteur.

**La bande de captures est en pied de colonne**, montée par une ligne de
`MeetingLiveSpace`. Vignettes 132 × 76 servies par un cache mémoire **borné** (64 entrées,
éviction LRU, clé = chemin + date de modification) qui décode à la taille demandée via
`CGImageSourceCreateThumbnailAtIndex` : sans lui, la bande redécoderait un PNG plein écran
par vignette et par rendu. La légende affiche l'**intervalle réel** (`2 min`) et non le mot
« périodique ». La colonne d'état ne promet rien de faux : une capture sans OCR annonce
« Aucun texte extrait », une capture sans `t` « Aucun timecode (capture hors séance) ».
`Joindre au rapport` est une case réelle, persistée sur `SlideCapture.includeInReport`
(colonne neuve à valeur par défaut, migration légère, aucune version de schéma).

**La frise porte le carré de 12 px.** Les repères existaient depuis le lot 2 ; ce qui
manquait était **quel** carré est le dernier (`accent/action`) et **quand** la légende
`■ = capture` a un sens — deux fonctions pures dans
`MeetingTimelineMarkers+Captures.swift`, plutôt que deux `if` dans le `Canvas`.

**Une capture s'insère dans les notes** en carte 56 × 36 + titre + première ligne d'OCR +
`Agrandir` (`Notes/TimedNotesColumn+Capture.swift`, aiguillage de trois lignes dans
`TimedNotesColumn`). La note ne copie **pas** l'image ni le texte : elle porte un
`sourceRef {capture, id, t}` et la carte relit la capture — copier l'OCR aurait figé un
texte que Vision met à jour une seconde plus tard. L'insertion est idempotente, et une
référence morte fait retomber la ligne sur son texte plutôt que d'afficher un cadre vide.

**Le texte extrait est cherchable** (critère n° 4) : l'OCR alimente `extractedText` du lot
(`rebuildAttachmentText`, déjà en place), que `reindexAttachment` découpe en
`TranscriptChunk`. Le test le prouve **sans** appeler `reindexAttachment` — son pipeline
d'embeddings exige `default.metallib`, absent de `swift test` : il vérifie la chaîne
observable OCR → `extractedText` → `TextChunker` → `BM25Index`, et que la requête
« chiffrage Reprise AP Marine » désigne bien le chunk de la capture et non la ligne de
transcription concurrente.

### Écarts assumés

1. **La recette visuelle n'est pas faite.** Consigne du 2026-09-07 : plusieurs agents
   pilotaient le même bureau et se tuaient mutuellement leurs instances ; une **passe de
   recette dédiée** la reprendra (`recette/lot-7-1920.png` à comparer à
   `4a-capture-selecteur.png`). À vérifier à ce moment-là : Teams ouvert **sans** réunion
   doit afficher « Fenêtre ouverte · aucune réunion active » (et « Aucune réunion active »
   quand Teams n'est pas lancé), la pilule `● Capture · Teams 3 ⌄`, la bande et la légende
   `■ = capture`.
2. **L'ordre vertical diffère de 4a.** La capture montre la frise **sous** la bande de
   captures ; ici la frise reste au pied de la carte notes ↔ transcription, où le lot 2 l'a
   posée, et la bande vient dessous. Déplacer la frise hors de la carte aurait touché la
   disposition des lots 2, 4 et 5 — hors périmètre, et la consigne du lot 7 est « une
   ligne » dans `MeetingLiveSpace`.
3. **« Zone à la souris » n'est pas sélectionnable.** La ligne `ÉCRAN` porte le sous-titre
   de la capture (« Ou une zone à la souris ») et capture l'écran entier ; le tracé d'une
   zone à la souris demande une fenêtre de sélection plein écran, qui relève de la pastille
   (lot 8). La valeur `CaptureSource.region` reste dans le modèle, personne ne l'écrit.
4. **Changer de source clôt le lot courant** et en ouvre un autre. Une session porte une
   source figée à sa construction ; accepter le changement à chaud donnerait un sélecteur
   qui confirme un choix sans effet (défaut « contrôle sans effet » de `One2One-specs.md`).
5. **`CropSelectionView` a été supprimée** en même temps que `ScreenCaptureConfigView`, son
   seul appelant : le sélecteur ne demande plus de tracer une zone avant de capturer.
   `NormalizedRect` et ses 12 tests restent — le recadrage est toujours appliqué, il n'est
   simplement plus réglé à la main. `MeetingSlidesPopover` est supprimée comme le lot 6
   l'avait prévu.
6. **La pastille flottante est le lot 8**, avec `⌘⇧S` global (Carbon) et le mini-panneau de
   confirmation de 4 s. Ici `⌘⇧S` est le raccourci de menu, actif quand la fenêtre de
   réunion a le focus.

### Fichiers partagés touchés

Au minimum près : `MeetingScreenModel.swift` (**une** ligne, `var capture`),
`MeetingTopChromeBar.swift` (la pilule de capture et son popover seulement),
`MeetingLiveSpace.swift` + `MeetingSpaceView.swift` (montage de la bande, un paramètre
optionnel), `MeetingView.swift` (**retraits** + le coordinateur et deux closures),
`Menus/{MeetingCommands,MeetingMenuActions}.swift` (`⌘⇧S` et l'appel du semis),
`Notes/TimedNotesColumn.swift` (aiguillage de trois lignes),
`Spaces/AudioTimelineStrip.swift` (carré de 12 px, dernier en accent, légende),
`Models/MeetingModels.swift` (`SlideCapture.includeInReport`),
`Views/DesignSystem/One2OneTokens.swift` (`capturePopoverWidth = 346`).
Aucun fichier de `Views/Meeting/OneOnOne/**`, `Services/OneOnOne/**`, `Workshop/**`,
`Rail/**`, `Review/**`, `Session/**`, `Project/**` ni `Resources/**` n'est touché —
`ResourceItem` et le tiroir sont réutilisés tels quels.

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → … → #25 → #31 → (lot 7)`, puis la **passe de
recette dédiée** reprend la comparaison avec `4a-capture-selecteur.png` (écarts n° 1 et
n° 2). Le lot 8 (pastille flottante, `4b`) part de ce sommet : `captureNow()`,
`CaptureState` et la bande lui servent tels quels.

## Lot 16 — Atelier : socle des planches et mode Croquis (6a partiel) (2026-09-07)

Branche `feat/refonte-lot-16-atelier-socle`. Développée depuis
`feat/refonte-lot-3-rail-actions`, **rebasée** sur `feat/refonte-lot-9-fiche-projet`
une fois l'intégration de la vague 4 terminée (quatre conflits attendus, tous des
ajouts « en fin de type » : `MeetingScreenModel`, `StorageStatsService`,
`MeetingSpaceView` — la branche atelier est entrée dans `contenu`, avant le mode
Relire, pour que les modificateurs des lots 4, 5 et 6 restent posés une seule fois —
et `STATUS.md`).
Tout est derrière **`AppSettings.workshopEnabled`, défaut `false`**.
ADR : `docs/adr/2026-09-07-moteur-de-planches-excalidraw-embarque.md` (décision D6).
Plan : `docs/superpowers/plans/2026-09-07-refonte-lot-16-atelier-socle.md`.

### Le moteur : Excalidraw embarqué, 3,5 Mo, aucun réseau

`Scripts/build-excalidraw-bundle.sh` construit le bundle **hors du dépôt** (npm dans un
dossier temporaire) et dépose dans `OneToOne/Resources/Whiteboard/` un fichier IIFE
unique de **3,1 Mo**, sa feuille de style de **248 Ko**, la licence MIT et
`VERSIONS.txt`. Versions épinglées : `@excalidraw/excalidraw` **0.18.1**, `react` et
`react-dom` **18.3.1**, `esbuild` **0.28.2**. Le bundle est **commité**, comme
`mermaid.min.js` (3,4 Mo) : le script ne sert qu'à le régénérer.

Sans trois allègements délibérés (`Scripts/excalidraw-esbuild.mjs`) le fichier ferait
**8,5 Mo** : les 55 traductions d'Excalidraw et le convertisseur Mermaid (mermaid +
chevrotain + langium, ~4 Mo) sont remplacés par des modules vides — l'interface
d'Excalidraw est **masquée**, toute la chrome est native — et la famille CJK Xiaolai
(12,5 Mo) n'est pas inlinée.

**Aucune requête réseau possible.** La page (`WhiteboardHTML.page()`) inline le JS et le
CSS, comme `MermaidRenderer`, et porte
`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:`.
Les 230 fontes `./fonts/**.woff2` du moteur sont réécrites en `data:font/woff2;base64,…`
par le script — `Fonts.createUrls` rend une telle URI telle quelle et ne consulte jamais
son CDN de secours — et les sept bases interrogeables du moteur (esm.sh, unpkg, partage
de scène, bibliothèque publique, IA, collaboration) deviennent des `file:///` morts.

**Écart assumé sur « aucune URL http(s) dans la page ».** Le bundle contient encore des
URL qui ne sont **pas** des ressources chargées : les deux espaces de noms XML du W3C
(`http://www.w3.org/2000/svg`, `.../1999/xhtml`), **indispensables** à `createElementNS`
donc à l'export SVG, et des constantes de liens d'interface (github.com, youtube.com,
plus.excalidraw.com…) qui vivent dans la chrome masquée. Les retirer casserait l'export
SVG et corromprait des littéraux d'expression régulière. `WhiteboardHTML.audit(_:)`
vérifie donc quatre choses, et `WhiteboardHTMLTests` les assène sur le bundle réellement
embarqué : la CSP exacte est présente ; le **balisage** (corps des `<script>`/`<style>`
retiré) ne porte aucune adresse réseau ni `<script src>`/`<link href>`/`@import` ;
aucune URL de fonte n'est autre que `data:` ; aucune des sept bases n'a survécu.

### Le socle

- `WhiteboardResourceLocator` — même structure que `MermaidResourceLocator` :
  `Bundle.module` en développement, disposition du `.app` packagé ensuite. Rappel :
  `.process("Resources")` **aplatit** l'arborescence, le fichier vit à la racine du
  bundle de ressources et non dans `Whiteboard/`.
- `WhiteboardBridge` — un **protocole**, pas une classe, plus `WhiteboardBridgeDouble`.
  Toute la règle métier et tout `BoardStore` se testent sans WebKit (parade du plan §8).
  `WhiteboardWebBridge` en est l'implémentation `WKWebView` ; son gestionnaire de
  messages passe par un **proxy faible**, sans quoi `WKUserContentController.add(_:name:)`
  et la configuration retenue par la vue formeraient un cycle que rien ne casserait.
- `BoardStore` — `recordings/<uuid de la réunion>/boards/<stableID>.excalidraw.json` et
  `.png`, racine **et horloge injectables**, vignette amortie à 5 s (`force` au
  changement de planche). `BoardOrdering` (tri, renumérotation, duplication, libellés du
  compteur et de fraîcheur), `BoardScene` (compte les objets d'une scène sans le moteur,
  et fabrique une scène à partir de boîtes étiquetées), `BoardModeRule` (règle §7.1).
- `StorageStatsService` compte `boards/`, `MaintenanceView` l'affiche en teal.
  `BackupService` gagne un `BoardDTO` (scène et vignette **en base64**, clé `boards`
  optionnelle pour les sauvegardes antérieures) et un `BoardStore` injectable : sans lui
  une restauration de test écrirait dans le `recordings/` de production.

### L'écran 6a

`WorkshopSpaceView` = mode **En séance** du type Atelier, grille `52 | 1fr | 314` sous une
barre d'outils de 32 px. Une seule branche dans `MeetingSpaceView` : le **dock remplace le
rail d'actions**. `WorkshopState` (une ligne en fin de `MeetingScreenModel`) porte la
planche active, la palette, l'onglet du dock et **l'unique `WKWebView` de la réunion** —
la page inline 3,1 Mo que WebKit réanalyse à chaque création, une vue par planche
multiplierait ce coût par 40. Sa fabrique de pont est injectable, donc l'orchestration
entière (créer, dessiner, sauvegarder, changer de mode, dupliquer, réordonner) se teste
contre le double.

Les cinq couleurs sont **dérivées des jetons** (`WorkshopPalette.hexString`) et non
recopiées : le moteur veut un hexadécimal, la règle du programme §7 interdit une couleur
hors `One2OneTokens`, et un test vérifie que les deux coïncident.

### Recette visuelle — partielle, et deux défauts trouvés

`Scripts/recette-app.sh` et `Scripts/recette-run.sh` repris de la branche du lot 9
(la base du lot 3 ne les avait pas). `.app` **debug** empaqueté, lancé avec `HOME` **et**
`CFFIXED_USER_HOME` jetables ; garde-fou d'isolation vert, le store de production n'a
jamais été ouvert. Capture : **`recette/lot-16-atelier-6a.png`** (fenêtre de 1 616 px
logiques — l'écran du poste fait 1 728 px, 1 920 est hors de portée).

Ce que la capture confirme par rapport à `6a-atelier-planche.png` : palette verticale de
52 px avec ses neuf outils et `↺ ↻` en pied ; toile `#fdfcfa` à points de 18 px ; dock de
314 px avec `Planches 4 / Captures 0 / Pièces 0`, les quatre planches
(`CROQUIS Périmètre actuel 08:15 · Yann`, `SCHÉMA Flux réseau 19:40 · Claire-Amélie`,
`CROQUIS Cible d'architecture 34:20 · en cours`, `MANUSCRIT Notes de Patrice 28:05 ·
stylet`), l'active bordée teal sur `#f2f8f7`, `＋ Planche` teal plein et `Dupliquer`,
le pied `L'assistant peut décrire les planches dans le rapport` ; type `Atelier` dans la
barre du haut. Le semis a bien écrit ses **quatre fichiers de scène** dans
`recordings/<uuid>/boards/` — le critère n° 1 (« se crée, se dessine, se sauvegarde,
se retrouve horodatée, sans réseau ») est vérifié dans l'application réelle, pas
seulement en test.

**Deux défauts trouvés par cette recette, corrigés et couverts par un test :**

1. L'écran demandait sa planche **avant** que la page ait fini d'analyser 3,1 Mo de
   JavaScript. Le `load` échouait, un bandeau « Le moteur de planches n'est pas encore
   prêt » s'affichait et la toile restait vide jusqu'au clic suivant. `WorkshopState`
   garde désormais l'intention (`pendingLoad`) et `onReady` la rejoue ; aucune erreur
   n'est posée entre-temps, puisque rien n'est cassé.
   Test : `selectionIsDeferredUntilReady`.
2. Le bandeau d'erreur, posé en `.overlay(alignment: .top)`, **recouvrait la barre
   d'outils** de 32 px : modes, couleurs, épaisseurs, compteur et export disparaissaient.
   Il est passé dans le flux, sous la barre.

**Écarts et limites de la recette, à reprendre :**

- La vérification **après** correctif n'a pas pu être refaite : plusieurs agents pilotaient
  le même bureau au même moment (une passe « recette visuelle des écrans 1a–3b » tournait
  en parallèle) et tuaient les processus `OneToOne`. La capture conservée montre donc
  l'écran **avant** les deux correctifs — barre d'outils masquée par le bandeau, toile
  vide. À refaire au calme.
- Le badge `ATELIER` apparaît **tronqué** dans la barre du haut à 1 616 px : la barre
  porte déjà fil d'Ariane, titre, pilules audio et capture, menus de type et de modèle, et
  le bouton Rapport. À arbitrer (masquer le fil d'Ariane sous une largeur seuil ?).
- Le crash **préexistant** de la fenêtre dédiée est bien là : le semis pose un
  `QuickLaunchRouter.pendingToken`, la fenêtre dédiée s'ouvre et l'application tombe sur
  `NSGenericException` « needing another Update Constraints in Window pass ». La réunion
  s'ouvre sans problème depuis la fenêtre principale, comme consigné.
- Effet de bord sur le poste : l'instance de production (`.build/.../release/OneToOne`,
  fenêtre `NPA/LDB`) a été **redimensionnée** à 0,33 / 1 720 × 1 024 pendant la recette —
  `first application process whose unix id is …` d'AppleScript renvoie le mauvais
  processus quand deux instances partagent l'identifiant de bundle. Aucune donnée touchée,
  seulement la géométrie de la fenêtre. Adressage par itération de la liste depuis.

### Performances

**Non mesurées.** Le rendu à 2 000 objets et le temps de chargement du bundle demandent une
session graphique tranquille ; la contention du bureau (cf. ci-dessus) a empêché la
mesure. Repère indirect seulement : le bundle fait la taille de `mermaid.min.js`, déjà
inliné dans un `WKWebView` par l'éditeur.

### Laissé au lot 17

Modes Schéma et Manuscrit complets (bibliothèque de formes, pression du stylet,
surligneur, lasso), onglets `Captures` et `Pièces` du dock (ils portent une invite non
vide, testée), section `SUR CETTE PLANCHE`, `＋ Action depuis la sélection`,
`Épingler à mm:ss`. Lot 18 : planche de séance 6b et légende d'assistant.

### Vérifications

`swift build` propre (avertissements préexistants seuls). `swift test` complet **vert** :
1 041 XCTest + 1 419 Swift Testing (**2 460**), 0 échec — contre 2 402 au sommet de la
pile après l'intégration de la vague 4.

**Prochaine action :** refaire la recette de 6a après les deux correctifs, sur un bureau
libre, et mesurer le chargement du bundle plus le rendu à 2 000 objets.
## Crash à l'ouverture de la fenêtre de réunion dédiée — corrigé (2026-09-07)

Branche `fix/refonte-1to1-window-crash`, **au sommet de la vague 4** — sur
`feat/refonte-lot-9-fiche-projet` depuis l'intégration (elle était sur le lot 3 quand le
correctif a été écrit). Il est indispensable à toute recette en bundle release, d'où sa
place en dernier maillon : les lots 4, 5, 6, 9, 10a et 10b l'ont donc tous en amont.

**Symptôme.** En **bundle release**, ouvrir une réunion dans la fenêtre dédiée
(`WindowGroup "1to1-meeting"`) tuait l'application ~3 s après l'ouverture :
`NSGenericException` — « The window has been marked as needing another Update Constraints
in Window pass, but it has already had more […] passes than there are views in the
window » — depuis `NSHostingView.updateConstraints()` →
`updateWindowContentSizeExtremaIfNecessary` (pile complète dans les cinq
`~/Library/Logs/DiagnosticReports/OneToOne-2026-09-07-13*.ips`). Pas un plantage
d'affichage : une **boucle de passes Auto Layout**.

**Établi.** `master` (`a3c44f2`) **ne crashe pas** (fenêtre ouverte, application vivante,
release + bundle). La bissection (9 pas, harnais de reproduction en bundle isolé) désigne
`6cc892b` « feat(reunion): barre du haut sur une ligne de 38 px » (lot 1a) comme premier
commit fautif ; `f74ad86` et tout le lot 0A/0B sont sains.

**Cause racine.** La fenêtre de réunion était la seule des trois scènes à ne pas déclarer
d'enveloppe de taille pour son contenu racine. Le `NSHostingView` racine doit alors
**mesurer toute la hiérarchie de l'écran de réunion** pour en déduire
`contentMinSize`/`contentMaxSize`, et il le fait *pendant* la passe de contraintes de la
fenêtre ; la mesure réinvalide le graphe, qui remarque la fenêtre « needs update
constraints », et la passe se relance jusqu'à épuisement du budget d'AppKit. La barre du
haut sur une ligne a rendu cette mesure instable : son titre est `flex:1` (spec §2.1),
donc `maxWidth: .infinity` + `layoutPriority(1)` — avant `6cc892b`, le titre était borné
(`maxWidth: 460` + `fixedSize`).

**Expériences discriminantes** (lot 3, release, fenêtre dédiée) : titre borné à 460 px →
**pas de crash** ; `maxWidth: .infinity` avec `fixedSize` → crash ; `TextField` SwiftUI à
la place du champ AppKit → crash ; simple `Text` → crash. Ce n'est donc pas le champ
AppKit `EditableTextField`, c'est la mesure non bornée de la racine de fenêtre. Enveloppe
déclarée sur la racine → **pas de crash**.

**Correctif** (`OneToOne/OneToOneApp.swift`, 1 fichier) : `MeetingWindowSizing`
(960 × 640 de plancher, 1 280 × 800 à l'ouverture) et
`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)` sur le contenu de
`OneToOneMeetingWindowContent` — la même chose que `PrepWindowView` fait depuis toujours
(600 × 480). Le `.frame(minWidth: 600, minHeight: 400)` du `ProgressView` d'attente
disparaît : c'est l'enveloppe qui gouverne, et un plancher qui changeait au moment où le
contenu se résolvait faisait partie du problème. **Aucune vue de la refonte n'est touchée**
(barre du haut, espaces, rail : inchangés).

**Tests.** `Tests/MeetingWindowSizingTests.swift` (4 tests) : le plancher de largeur garde
le rail d'actions affiché (`MeetingSpaceLayout.showsRail`, colonne fluide ≥ 520), le
plancher de hauteur laisse la place aux deux barres, l'ideal ne descend pas sous le
plancher, et une garde de non-régression vérifie que la fenêtre **applique** l'enveloppe
(retirer le `.frame` fait échouer ce test — vérifié). La passe Auto Layout elle-même n'est
pas observable depuis `swift test`, d'où cette garde.

**Vérifié.** `swift build` propre ; `swift test` complet **1 039 XCTest (1 ignoré, 0 échec)
+ 896 Swift Testing (131 suites, 0 échec)**, soit +4 par rapport au sommet du lot 3.
Reproduction avant/après en bundle release, dans un `HOME`/`CFFIXED_USER_HOME` jetable
(jamais le store de production) : avant → mort à ~3 s avec l'exception au journal ;
après → fenêtre `1:1 — Debug` ouverte et application vivante à 15 s.

**Reste à faire.** Le même défaut guette toute future scène dont le contenu racine ne
borne pas sa taille. Les recettes visuelles des lots 4, 5, 6, 9 et 10 sont maintenant
possibles en bundle release : elles doivent être rejouées depuis ce sommet.

## Intégration vague 4 : la pile redevient linéaire (2026-09-07)

Les lots **4, 5, 6, 10a, 10b et 9** ont été développés **en parallèle** — les cinq premiers
depuis `feat/refonte-lot-3-rail-actions`, le lot 9 depuis
`feat/refonte-lot-1b-espaces-kpi-assistant`. Ils sont désormais **empilés** dans cet ordre :

```
0A/0B → 1a → 1b → 2 → 3 → 4 → 5 → 6 → 10a → 10b → 9 → fix fenêtre
#19–#24              #27  #28  #30  #26   #29   #25   #31
```

Ordre de fusion : `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31` — la PR #31 (correctif du crash Auto Layout de la fenêtre dédiée) est rebasée
au sommet, sur le lot 9.

### Conflits résolus, maillon par maillon

| Maillon | Fichier | Résolution |
| --- | --- | --- |
| **4** (#27) | — | déjà sur le lot 3, aucun conflit |
| **5** (#28) | `MeetingScreenModel.swift` | union : `session` (4) **et** `review` (5) |
| | `MeetingSpaceView.swift` | `body` éclaté en `contenu` (`if .review` du lot 5) + le modificateur `.sessionFullscreen` du lot 4 posé dessus, `estEligible: screen.mode == .live` |
| | `STATUS.md` | sections 5 puis 4 |
| **6** (#30) | `MeetingScreenModel.swift` | union : `session`, `review`, `resources` |
| | `MeetingSpaceView.swift` | `@Environment(\.modelContext)` **rétabli** (le lot 5 l'avait retiré, le tiroir en a besoin), `.onDrop` + `.overlay { tiroirRessources }` posés sur `contenu` — le tiroir s'ouvre donc aussi depuis le mode Relire ; `onShowCaptures` (5) **et** `onImportResources` (6) |
| | `MeetingView.swift` | `onShowCaptures` du lot 5 mène au tiroir filtre `Captures` : le lot 6 a supprimé `showSlidesList` et son popover |
| | `Menus/MeetingCommands.swift` | union : `⌃⌘F` (4), `⌘⇧V` et `Ressources…` (6) ; **un seul** item de démonstration, qui appelle `seedLot5` puis `seedLot6` (tous deux partent de `seed`, idempotent) |
| | `Menus/MeetingMenuActions.swift` | union de `MeetingMenuItem`, des closures et de `isEnabled` |
| | `Tests/SessionNoChromeTests.swift` | le constructeur du lot 4 fournit `pasteResource`/`openResources` |
| | `STATUS.md` | recomposé section par section (une résolution avait laissé le bloc « Tests » du lot 6 dans la section du lot 5) |
| **10a** (#26) | `MeetingScreenModel.swift` | union : + `oneOnOne` |
| **10b** (#29) | `STATUS.md` | section du lot 10 en tête |
| | `Maintenance/StorageStatsService.swift` | union automatique : `documents/` (6) **et** `annual/` (10) |
| **9** (#25) | `MeetingScreenModel.swift` | union : + `showProjectCard` — cinq propriétés d'état, aucune perdue, aucune dupliquée |
| | `MeetingView.swift` | `onShowSlides` (6, tiroir) **et** `onOpenProject` (9, fiche en panneau) |
| | `Services/Debug/RefonteDemoSeed.swift` | union ; le `tags` du lot 5 devient **`tagsLot5`** — le semis de base porte désormais un `tags`, les thèmes du *projet* de la fiche 3b |
| | `Tests/MeetingScreenModelTests.swift` | les trois tests de la fiche ajoutés en fin de suite, ceux des lots 2 et 3 intacts |
| | `STATUS.md` | section du lot 9 en tête |

### Chiffres

`swift build` propre à chaque maillon (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`, `MeetingTagSuggester`, `AppDelegate`).
`swift test` **complet vert** à chaque maillon :

| Maillon | XCTest | Swift Testing | Total | Seul, avant intégration |
| --- | --- | --- | --- | --- |
| lot 3 (référence) | — | — | **1 931** | — |
| 4 | 1 039 | 974 | **2 013** | 2 013 |
| 5 | 1 039 | 1 048 | **2 087** | 2 005 |
| 6 | 1 041 | 1 132 | **2 173** | 2 017 |
| 10a | 1 041 | 1 207 | **2 248** | — |
| 10b | 1 041 | 1 277 | **2 318** | 2 076 |
| 9 | 1 041 | 1 357 | **2 398** | 1 881 (base 1b) |

`MeetingView.swift` : **2 051 lignes** (2 045 après l'intégration 2 + 3, + le câblage des lots
5, 6 et 9 ; aucune logique nouvelle).

### Points tranchés

1. **Le tiroir Ressources s'ouvre en mode Relire.** L'`overlay` du lot 6 est posé sur
   `contenu`, en amont de la bifurcation `.review` : le poste de pilotage garde donc son
   entrée `Documents n/＋`, et le tiroir se superpose à lui comme à la séance.
2. **Le plein écran n'est offert qu'en mode En séance** (`estEligible: screen.mode == .live`) :
   le poste de pilotage relit une réunion terminée, un écran de séance n'y a pas de sens.
3. **`RefonteDemoSeed.seedOneOnOneThreads` (lot 10) n'est pas câblé au menu.** Il ne complète
   pas la réunion de `1a-cockpit.png` : il sème **deux fils 1:1 et dix séances** propres. Le
   lot 10 avait choisi de ne pas le mettre derrière l'item « Charger le jeu de démonstration
   (refonte) », et l'y ajouter changerait ce que cet item produit — décision laissée à la
   relecture. Il reste appelé par `RefonteDemoSeedLot10Tests`, vert.

### Prochaine action

Faire relire les sept PR dans l'ordre de fusion ci-dessus. Les recettes visuelles restent
dues (lots 4, 5, 6, 10) ; cette passe d'intégration n'en a lancé aucune — elles sont
désormais faisables en bundle release, le correctif de la PR #31 étant au sommet.

## Refonte de l'écran de réunion — lot 9 : fiche projet en panneau (3b) (2026-09-07)

Branche `feat/refonte-lot-9-fiche-projet`, **empilée** sur
`feat/refonte-lot-1b-espaces-kpi-assistant` (PR #22), elle-même sur `…-lot-1a-chrome` (#21),
sur 0B (#20) et 0A (#19). La PR **contient donc les lots 0A, 0B, 1a et 1b** tant que #19–#22
ne sont pas fusionnées. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-9-fiche-projet.md`.

**État : livré, `swift build` propre, `swift test` complet vert (1 881 tests), recette
visuelle faite à 1 280 px, PR ouverte, non mergée.** Trois constats à lire avant tout :
un **crash préexistant** de l'écran de réunion en bundle `.app` (§ Recette ci-dessous),
une **pollution du store de production** par le semis de démonstration, et le correctif
d'isolation qui l'empêche de se reproduire.

### ⚠️ À traiter : le store de production contient des lignes de démonstration

Le premier lancement de recette a ouvert le **vrai** store — `HOME` ne suffit pas à isoler
une application en bundle, cf. § Recette. Le semis y a écrit, à 13:19 le 2026-09-07 :

| Ligne | Repère |
| --- | --- |
| 1 projet | `S/D — Modernisation CI/CD`, code **`P25_110_1`** (le code a été dédoublonné à l'ouverture) |
| 1 réunion | `[P25_110] Partage statut final et chiffrage reste à faire`, **4 sept. 2025** 9:15 |
| 12 actions, 5 risques, 4 segments | rattachés à cette réunion |
| 3 jalons, 3 interlocuteurs | rattachés au projet `P25_110_1` |
| 6 collaborateurs | Pierre-Yves Nallet, Nathalie Lefèvre, Cédric Payet, Lucas Sylvain, Camille Aubert, **Laurent Deberti** (créé faute de correspondance avec « DE BERTI Laurent ») |

**Aucune donnée réelle n'a été modifiée** : le vrai projet `P25_110`
(`S/D - Modernisation Chaine CI/CD`, Z_PK 52) est intact — budgets vides, périmètre vide,
tags vides, aucun jalon, aucun interlocuteur. Le semis n'a pas reconnu l'homonyme
(tiret contre cadratin, « Chaine » contre « Chaîne ») et a donc **créé** un projet séparé
au lieu d'écraser le vôtre.

**Rien n'a été supprimé** : effacer des lignes d'un store de production de 32 Mo n'est pas
une décision que je prends seul. La suppression se fait proprement depuis l'application :
la réunion par `Réunion ▸ Supprimer la réunion…` (elle emporte actions, risques et
segments), puis le projet `P25_110_1` (il emporte jalons et interlocuteurs), puis les six
collaborateurs s'ils ne servent à rien d'autre. Dis-moi si tu préfères que je le fasse.

### Ce qui est en place

**La fiche projet s'ouvre en panneau de 430 px** (spec §4.3, capture `3b-fiche-projet.png`) —
`ProjectCardPanel` glisse depuis la droite, ombre `-8px 0 24px rgba(0,0,0,.07)`, la colonne
principale passe à **55 % d'opacité et reste consultable** (aucun `allowsHitTesting(false)` :
la spec insiste). `Esc` — via `onExitCommand`, pour que la touche marche depuis un champ — et
`✕` ferment, avec confirmation si le brouillon porte des modifications. Contenu : en-tête
(`FICHE PROJET`, nom, `P25_110 · 9 réunions · dernière mise à jour aujourd'hui par vous`,
bascule `Édition`, `✕`), cartes `STATUT` (menu à trois valeurs, point coloré) et
`BUDGET CONSOMMÉ` (barre teintée par ratio), `JALONS` avec ligne d'ajout pointillée
`Nouveau jalon… date · statut`, `PÉRIMÈTRE & CONTEXTE` avec chips de thèmes et chip `＋`,
`RISQUES · n` et `INTERLOCUTEURS` sur deux colonnes, encart de l'assistant, pied
`Visible par toute l'équipe projet…` + `Annuler` / `Enregistrer`.

**`ProjectDetailView` n'est pas remplacée** : elle reste l'écran projet complet (portfolio,
mails, pièces jointes). Le panneau est un point d'édition contextuel, ouvert en réunion.

**Trois règles pures, testées avant toute vue** (programme §7) —
`ProjectCardBuilder` (mapping `Green/Yellow/Red/Unknown` ↔ `ok/watch/risk`, budget
`budgetCons / (budgetRev ?? budgetInit)`, teinte par ratio, tri des jalons, jalon en retard
rendu « bloqué », risques `ProjectAlert` du plus grave au plus faible) ;
`ProjectCardDraft` (instantané éditable détaché du modèle, réconciliation par identité) ;
`ProjectCardSuggestions` (prompt, JSON strict, acceptation ligne à ligne).

**Critère d'acceptation n° 4 du chantier 3 tenu structurellement.** « Aucune modification de
la fiche projet n'est écrite sans validation humaine explicite » : le panneau édite une
`struct`, et `Project` ne bouge qu'à l'appel de `ProjectCardDraft.apply(to:in:)`. Deux tests
le prouvent — `draftEditsNeverReachTheModel` modifie le brouillon de bout en bout et vérifie
que le modèle n'a rien vu ; `suggestingAndAcceptingNeverWriteToTheModel` fait la même chose
côté assistant, avec un `AIClientProtocol` factice.

**L'assistant propose, il n'écrit jamais.** Trois garde-fous : rien n'est **demandé** sans
endpoint IA configuré ni sans matière (pas d'encart, pas d'erreur, pas d'appel — deux tests
comptent les appels du client factice) ; rien n'est **levé** (JSON malformé, champ inconnu,
réponse bavarde, client en échec → liste vide) ; rien n'est **deviné** (un jalon inconnu ou un
montant illisible fait rendre `false` à `accept`, et la feuille garde la ligne avec la mention
« Proposition inapplicable en l'état »). La feuille `ProjectCardSuggestionsSheet` montre le
diff `ENREGISTRÉ → PROPOSÉ` avec la citation, `Accepter` / `Ignorer` par ligne.

**Enregistrement optimiste** — `UndoBanner` est une primitive du système de conception, pas un
bout de la fiche : les lots 6, 10 et 15 en auront besoin, et une seconde bannière écrite
ailleurs finirait par ne plus durer cinq secondes. `task` plutôt qu'un `Timer`, pour que
l'expiration ne survienne jamais après la fermeture de la vue.

**Reprise en préparation** — le pied du panneau promet « reprise automatiquement en
préparation de la prochaine réunion » : le mode Préparer tient la promesse avec une section
`FICHE PROJET` (statut, budget, jalons proches, risques élevés) et un lien `Ouvrir la fiche`.
`MeetingPrepareBuilder` gagne trois sorties pures ; la fenêtre est de **trente jours**, et
**tous** les jalons bloqués remontent, datés ou non — un jalon bloqué sans date est
précisément celui qu'on oublie.

**Déclencheur** — le segment projet du fil d'Ariane gagne le chevron `⌄` de la capture et
ouvre la fiche au lieu de la feuille « Détails », qui reste dans le menu `⋯`.
`MeetingScreenModel.showProjectCard` est ajouté **en fin de type**, **non mémorisé** : un
panneau ouvert est un geste, pas un réglage.

**Outillage de recette** — `Scripts/recette-app.sh` empaquette un `.app` depuis
`.build/<config>` du dossier courant sans incrémenter le numéro de build ni installer quoi que
ce soit ; `Scripts/recette-run.sh` le lance avec un `HOME` jetable, `--seed` posant
`ONETOONE_SEED_DEMO=1` que `ContentView` lit au démarrage pour semer et ouvrir la réunion de
démonstration sans clic de menu. Documenté au §7 étape 6 du plan directeur — qui rejoint le
suivi git au passage, il en était encore absent alors que tous les lots s'y réfèrent.

### Créés

`OneToOne/Services/Project/` : `ProjectCardBuilder`, `ProjectCardDraft`,
`ProjectCardSuggestions`. `OneToOne/Views/Project/` : `ProjectCardPanel`,
`ProjectCardSuggestionsSheet`. `OneToOne/Views/DesignSystem/Components/Refonte/UndoBanner`.
`Scripts/recette-app.sh`, `Scripts/recette-run.sh`.
`Tests/` : `ProjectCardBuilderTests`, `ProjectCardDraftTests`, `ProjectCardSuggestionsTests`,
`ProjectCardPanelTests`, `UndoBannerTests`.

### Modifiés

`One2OneTokens` (+4 jetons : ombre de panneau ×3, dépoli 55 %), `MeetingScreenModel`
(`showProjectCard`, en fin de type), `MeetingTopChromeBar` (segment projet seulement),
`MeetingView` (`onOpenProject` + overlay en fin de `mainPanel`), `MeetingSpaceView` (une ligne :
le rappel d'ouverture), `MeetingPrepareSpace` (section `FICHE PROJET`),
`MeetingPrepareBuilder`, `RefonteDemoSeed` (budget 40 000 / 61 000, périmètre, 4 thèmes,
3 jalons, 3 interlocuteurs), `OneToOneApp` (lecture de `ONETOONE_SEED_DEMO`).
**Aucune nouvelle version de schéma, aucune colonne ajoutée, aucune dépendance nouvelle.**

### Tests

`swift build` propre. `swift test` complet **vert** : **1 039 XCTest (1 ignoré, 0 échec) +
842 Swift Testing en 120 suites (0 échec)**, soit **1 881 tests** contre 1 801 après le lot 1
(**+80, +5 suites**), aucune régression.

Nouvelles suites : `ProjectCardBuilderTests` (20), `ProjectCardSuggestionsTests` (23),
`ProjectCardDraftTests` (10), `ProjectCardPanelTests` (9), `UndoBannerTests` (5). Ajouts :
3 dans `MeetingScreenModelTests`, 4 dans `MeetingPrepareBuilderTests`, 3 dans
`RefonteDemoSeedTests`, 2 dans `One2OneTokensTests`, 1 dans `MeetingTopChromeBarTests`.
Aucun test ne touche MLX, le réseau ni une session graphique.

### Recette visuelle

`docs/superpowers/specs/refonte-2026-09/recette/lot-9-1280.png` — fenêtre de 1 280 × 800 pt
(image 2 562 × 1 600, écran Retina), fiche projet **ouverte**, hors édition. Obtenue avec
`Scripts/recette-app.sh` puis `Scripts/recette-run.sh`, sur un store isolé ne contenant que
le jeu de démonstration.

**Ce qui correspond à `3b-fiche-projet.png`** : le segment projet bordé bleu avec son
chevron ; `FICHE PROJET`, le nom, `P25_110 · 1 réunion · dernière mise à jour le 4 sept. par
vous` ; les cartes `STATUT ● À surveiller` et `BUDGET CONSOMMÉ 40 000 € / 61 000 €` avec sa
barre ; les trois jalons avec point vert daté « 30 sept. », point orange `bloqué` en rouge,
cercle vide « 15 nov. » ; `PÉRIMÈTRE & CONTEXTE` + `éditer`, le texte encadré, les chips
`GitLab Nexus PostgreSQL Cléva` ; `RISQUES · 5` et `INTERLOCUTEURS` sur deux colonnes ; la
colonne principale visiblement atténuée ; le panneau à 430 px exactement.

**Écarts avec la maquette relevés sur la capture** :

1. **La barre de budget est verte**, la maquette la dessine orange (cf. écarts assumés n° 1).
2. **La maquette montre le mode Édition actif** (`＋ ajouter`, ligne `Nouveau jalon…`, chip
   `＋`, `＋ Ajouter un risque`, `＋ Ajouter`, pied `Annuler` / `Enregistrer`) ; la capture
   est en **lecture**, où la spec veut que tout cela disparaisse. Le passage en édition n'a
   pas pu être capturé : le clic sur la pilule `Édition` n'a pas abouti par script — AX ne
   résout pas correctement le survol d'un `overlay` SwiftUI — puis la session s'est
   verrouillée. **À vérifier à la main.**
3. **Pas d'encart de l'assistant** : le home de recette repart de zéro, donc aucun endpoint
   IA n'est configuré. C'est le comportement attendu (« sans endpoint : encart absent, pas
   d'erreur ») et la capture en est la démonstration, mais elle ne montre pas l'encart.

**Capture à 1 920 px non faite** : la session s'est verrouillée en cours de recette
(`ioreg -n Root -d1 -r` → `"CGSSessionScreenIsLocked"=Yes`, `IOConsoleLocked = Yes`), les
fenêtres ne sont plus adressables et `screencapture` ne rend plus qu'une image noire. Comme
au lot 1 : rien de faux n'a été déposé.

**Deux défauts trouvés par la recette et corrigés** : la chip « PostgreSQL » se repliait en
« PostgreS / QL » (colonne adaptative trop étroite, `fixedSize` ajouté) et le compteur des
risques s'écrivait `RISQUES 5` au lieu de `RISQUES · 5`.

### 🐛 Crash préexistant de l'écran de réunion en bundle `.app`

**Trouvé par cette recette, présent sur la branche de base, hors périmètre du lot 9.**

Ouvrir une réunion dans la **fenêtre dédiée** (`WindowGroup "1to1-meeting"`, celle
qu'ouvrent le semis de démonstration, `QuickLaunchRouter` et la pastille) fait **crasher
l'application** en build release empaqueté :

```
EXC_BREAKPOINT / +[NSApplication _crashOnException:]
-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]
-[NSView setNeedsUpdateConstraints:]
SwiftUI.NSHostingView.setNeedsUpdate()
SwiftUI.NSHostingView.updateWindowContentSizeExtremaIfNecessary()
SwiftUI.NSHostingView.updateConstraints()
```

C'est la ré-entrance Auto Layout de la famille `_NSDetectedLayoutRecursion` que le programme
§2.4 point 4 signale déjà. **Vérification faite** : la même manipulation, sur
`origin/feat/refonte-lot-1b-espaces-kpi-assistant` recompilée en release et empaquetée avec
les mêmes scripts, crashe **à l'identique** (journaux `OneToOne-2026-09-07-1324*.ips` et
`-1330*.ips`). Le lot 9 n'y est pour rien — les lots 0A à 1b n'ont jamais été lancés en
bundle, la session étant verrouillée à ce moment-là.

**Contournement utilisé pour la recette** : ouvrir la réunion depuis la liste `Réunions` de
la fenêtre principale, où la navigation se fait **en place**. Ce chemin ne crashe pas — c'est
lui qui a produit la capture. `NSApplicationCrashOnExceptions = false` dans les préférences
n'y change rien.

**Prochaine action recommandée** : un lot de correction dédié. La piste la plus probable est
une contrainte de taille minimale que la hiérarchie de `MeetingView` renégocie pendant la
passe de contraintes de la fenêtre — candidats : le `.fixedSize()` du fil d'Ariane dans
`MeetingTopChromeBar`, la `ScrollView` non bornée d'un espace, ou `MeetingSpaceLayout` qui
calcule ses colonnes depuis un `GeometryReader`.

### Écarts assumés

1. **La barre de budget de la capture est orange, la règle chiffrée dit vert.**
   40 000 / 61 000 = 65,6 %, et la spec écrit deux fois « < 70 % ok ». C'est la **règle** qui
   est implémentée, pas la teinte de la maquette : elle est chiffrée, l'autre non. Le test
   `budgetOfCapture` fige ce choix et le commente. À trancher si la maquette fait foi ici.
2. **L'overlay du panneau vit dans `MeetingView.mainPanel`, pas dans `MeetingSpaceView`.**
   Le périmètre du lot désignait `MeetingSpaceView` ; mais celle-ci ne connaît que l'espace
   Réunion, et la spec §4.3 veut que le panneau se superpose à **n'importe quel** espace. Le
   diff dans `MeetingView` est de six lignes, hors des zones des lots 2 et 3
   (`transcriptView`, `ActionsPanel`).
3. **Budget éditable en champs inline, là où la maquette montre du texte statique** malgré la
   bascule `Édition` active. Le périmètre du lot demandait explicitement « en édition, champs
   inline » ; les champs sont stylés à plat pour rester proches de la capture.
4. **Réordonner les jalons passe par deux chevrons, pas par un glisser-déposer.** Le panneau
   n'est pas une `List` : un `onMove` maison sur une `VStack` réclamerait un suivi de geste
   dont le comportement dériverait du reste de l'application.
5. **Un avertissement de compilation nouveau, de classe préexistante** :
   `ProjectCardSuggestions.swift:239` capture `AppSettings` (non `Sendable`) dans la closure
   `@Sendable` du timeout. C'est **exactement** le motif de `MeetingTagSuggester`, qui porte le
   même avertissement depuis son écriture ; le supprimer demanderait de changer la signature de
   `AIClientProtocol`, partagée par quatre services — hors périmètre d'un lot.
6. **Le `＋` des thèmes n'a pas de disposition en flot** : `LazyVGrid` adaptatif au lieu d'un
   `FlowLayout`. Les thèmes d'une fiche tiennent sur une à deux lignes ; un layout maison
   serait à écrire pour tout le programme, pas pour ce lot.
7. **Le plan directeur rejoint le suivi git dans cette PR.**
   `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` était encore hors suivi
   alors que tous les lots s'y réfèrent, et le lot 9 devait en amender le §7 étape 6. Le
   dossier `docs/superpowers/specs/refonte-2026-09/` (spec et treize captures) reste, lui,
   hors suivi : ce n'est pas au lot 9 d'en décider.

### Prochaine action

1. **Trancher la teinte de la barre de budget** : règle chiffrée (vert à 65,6 %) ou maquette
   (orange) ?
2. **Décider du sort des lignes de démonstration dans le store de production** (liste et
   procédure ci-dessus).
3. **Ouvrir un lot de correction du crash de la fenêtre de réunion** : il bloque toute
   recette visuelle des lots ≥ 1 par le chemin normal, et il touchera l'usage réel (le semis,
   `QuickLaunchRouter` et la pastille passent tous par cette fenêtre).
4. Vérifier à la main le mode Édition de la fiche et capturer 1 920 px, session déverrouillée.

## Refonte de l'écran de réunion — lot 10 : socle 1:1 (2026-09-07)

Deux branches empilées sur le lot 3, plan du lot dans
`docs/superpowers/plans/2026-09-07-refonte-lot-10-socle-1to1.md` (la coupe 10a / 10b est celle que
prévoyait le programme §5).

| Branche | PR | Base |
| --- | --- | --- |
| `feat/refonte-lot-10a-socle-1to1` | [#26](https://github.com/ldb2000/One2One/pull/26) | `feat/refonte-lot-3-rail-actions` |
| `feat/refonte-lot-10b-humeur-regles-recap` | [#29](https://github.com/ldb2000/One2One/pull/29) | `feat/refonte-lot-10a-socle-1to1` |

**État : livré, `swift test` complet vert, deux PR ouvertes, non mergées.**

**Lot sans écran.** Aucune recette visuelle n'a été faite et aucune n'est possible : le seul rendu
touché est le badge de la barre du haut, vérifié par test. C'est aussi pourquoi le jeu de
démonstration est **gardé par des tests d'arithmétique** — rien d'autre ne détecterait un jeu de
données qui ne tient pas les nombres des maquettes.

### Entités — colonnes ajoutées (aucune nouvelle version de schéma)

`CurrentSchema` reste `SchemaV3` : les tables du domaine 1:1 sont déclarées depuis le lot 0B, et le
lot 10 n'ajoute que des colonnes à valeur par défaut (migration légère).

- `OneOnOneAgendaItem` : `kindRaw` (`topic`/`request`), `requestStatusRaw`
  (`pending`/`waiting`/`granted`/`refused`), `requestedAt`, `remindedCount`. Une **demande** est un
  sujet d'ordre du jour qui attend une réponse (spec §6.2), pas une table à part : la colonne
  `MES DEMANDES EN COURS` de la capture 5a est un filtre.
- `Commitment` : `settledAt`. Sans elle, `TENUS DEPUIS LE DERNIER 1:1` ne se calcule pas — l'état
  seul ne dit pas *quand*. Repli sur `promisedAt` pour les lignes antérieures.
- Deux énums : `AgendaItemKind`, `RequestStatus`.

Réutilisés tels quels : `OneOnOneThread`, `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`,
`OneOnOneObjective`, `MeetingNote` (dont `kindRaw` porte déjà `feedback`/`promise`/`request`/`proof`),
`ConfidentialityFilter` (`Audience`, `Visibility`, `Confidential`, `isExportable`).

### Services créés — `Services/OneOnOne/`

| Fichier | Rôle |
| --- | --- |
| `OneOnOneThreadStore` | **Le seul du domaine qui écrit en base** : création paresseuse du fil (D3), rôle déduit du type (D4), cadence en miroir de l'annuaire remise en phase à chaque accès, réunions du fil **déduites** de `Meeting.participants` (jamais persistées), séance précédente / suivante, rang de séance, `nextPlannedDate`. |
| `CommitmentLedger` | Pur : filtre par côté, tenus depuis le dernier 1:1, retards, tri par retard décroissant (sans-échéance en fin, tri stable), taux `kept/(kept+missed)`, compteur de reports, `markKept`/`markMissed`/`postpone`. |
| `AgendaCarryover` | Pur : report d'un sujet non traité (copie, ne déplace pas), idempotent ; `RESTÉ EN SUSPENS` ; niveau d'une demande (> 60 jours → `report`), historique, relance. |
| `OneOnOneConfidentiality` | Pur : défaut par rôle, bascule `/privé`, compte et libellé des lignes exclues, audiences de sortie (D9). |
| `OneOnOneScreenState` | `@Observable` : filtre d'engagements et confirmation d'escalade **par réunion** — état d'interface, jamais en base. |
| `OneOnOneDateFormat` | Les quatre écritures de date du domaine, locale `fr_FR` forcée. |
| `MoodTrend` | Pur : cinq crans, série des 6 derniers, delta, tendance au demi-point strict, phrase d'explication, saisie qui **remplace** le relevé de la séance. |
| `OneOnOneObjectiveTone` | `OneOnOneTone` (`warn`/`oneOnOne`/`ok`/`report`) — la seule passerelle du domaine vers la table §1.2 ; seuils <30 / <70 / ≥70, tri, « Revue prévue le … ». |
| `RecurringTopicsBuilder` | Pur, **calculé et non stocké** : cinq familles par lexique FR replié, comptage ordre du jour + notes + thèmes, tri décroissant. |
| `ReminderRules` | Pur : les trois règles dans l'ordre + `toAgendaItems`, idempotent par le texte. |
| `OneOnOneRecapBuilder` | Pur : markdown du récap, **chaque ligne** passée par `ConfidentialityFilter`, compte des lignes exclues en pied. |
| `OneOnOneRecapActions` | Effets : Mail, EventKit, dossier annuel. Aucun dialogue bloquant. |

Ailleurs : `Services/Meeting/NoteCommandParser+OneOnOne.swift` (les six commandes, par extension),
`Services/Meeting/NoteCommandCatalog.swift`, `Services/Debug/Seed/RefonteDemoSeed+Lot10.swift`.

### Fichiers partagés touchés, à la ligne près

- `Views/Meeting/MeetingScreenModel.swift` : **une ligne** (`var oneOnOne = OneOnOneScreenState()`).
- `Views/Meeting/MeetingTopChromeBar.swift` : deux fonctions statiques et deux pilules dans le fil
  d'Ariane (badge `1:1`, `Je suis le collaborateur`). La teinte `#f4f1f6` du lot 1 était déjà
  posée : vérifiée, gardée par un test, non modifiée.
- `Services/ExportService.swift` : une façade `composeMail(subject:html:recipients:)`. Le récap 1:1
  n'a ni gabarit de rapport ni destinataires « participants » ; passer par `composeMeetingMail`
  aurait demandé d'y injecter deux exceptions.
- `Services/Maintenance/StorageStatsService.swift` : une ligne `annualBytes`/`annualCount`. Un
  dossier qu'aucun service ne voit finit par grossir seul.
- `Tests/ConfidentialityFilterTests.swift` : la suite du lot 0B gagne son **sixième flux**.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 039 XCTest (1 ignoré, 0 échec) + 1 037 Swift Testing dans 143 suites, 0 échec** — 2 076 tests,
soit **+145** par rapport à la référence de 1 931.

Douze suites nouvelles : `OneOnOneRequestColumnsTests` (4), `OneOnOneThreadStoreTests` (15),
`CommitmentLedgerTests` (14), `AgendaCarryoverTests` (14), `OneOnOneConfidentialityTests` (11),
`NoteCommandOneOnOneTests` (14), `MeetingTopChromeOneOnOneTests` (3), `MoodTrendTests` (13),
`OneOnOneObjectiveToneTests` (5), `RecurringTopicsBuilderTests` (10), `ReminderRulesTests` (15),
`OneOnOneRecapBuilderTests` (17), `RefonteDemoSeedLot10Tests` (9).

Suites existantes intactes : `EngagementLedgerTests`, `OneToOneRhythmTests`,
`PrepCarryoverServiceTests`, `ConfidentialityFilterTests` (étendue, pas réécrite),
`SchemaV3MigrationTests`, `NoteCommandParserTests`.

### Critères d'acceptation couverts

- **Chantier 2 n° 1** — une note privée n'apparaît dans aucun récap : `OneOnOneRecapBuilderTests` +
  le sixième flux de `NotePriveeHorsDesCinqFluxTests`, pour les trois audiences. Une ligne
  `escalated` est exclue du récap collaborateur et incluse dans l'export `.hr` (D9).
- **Chantier 2 n° 2** — engagement manqué côté manager avec son compteur de reports.
- **Chantier 2 n° 3** — le moral saisi alimente la série de 6 points, tendance « en baisse » sur le
  jeu de la capture 2b.
- **Chantier 2 n° 4** — un item non traité migre vers le 1:1 suivant, idempotent.
- **Chantier 5 n° 1, 2** — rôle visible en permanence, défaut `private` côté collaborateur.
- **Chantier 5 n° 4** — une promesse du manager non tenue est en position 1 ; demande sans réponse
  > 60 jours → `report` (et 56 jours reste en `warn`, comme la capture 5a).

### Écarts assumés

1. **`CommitmentLedger.postpone` et non `defer`** : `defer` est un mot réservé de Swift.
2. **`ReminderRules` règle 2 ignore une famille déjà portée par un sujet `todo`** de l'ordre du
   jour — la carte s'appelle « À NE PAS OUBLIER ». Ce n'est pas dans la lettre de la spec, mais sans
   cela le jeu de la capture 2b sort deux rappels de règle 2 là où la maquette en montre un. Un
   sujet `deferred` continue de rappeler : il n'a justement pas été traité.
3. **`stillOpen` et `explanation` prennent leurs sujets récurrents en paramètre** (`[(label, count)]`)
   au lieu d'appeler `RecurringTopicsBuilder` : les fonctions restent pures et l'écran de
   préparation ne recompte pas deux fois.
4. **L'humeur ne sort jamais vers `.hr` ni `.projectTeam`**, même en escalade. La spec ne le dit pas
   explicitement ; le cran de moral est ce que la personne a dit d'elle-même à son manager, et le
   faire monter à la hiérarchie au détour d'une escalade trahirait la question posée.
5. **`NoteCommandCatalog` n'est pas câblé dans le composeur** : `Views/Meeting/Spaces/Notes/**`
   appartient au lot 2 et est hors périmètre ici. Le helper est pur et testé, les lots 11 à 14 le
   branchent.
6. **`BackupService` n'exporte toujours pas les tables 1:1** (écart n° 3 du lot 0B, inchangé) — mais
   elles se remplissent maintenant, avec le jeu de démonstration. À traiter au lot 6 ou au lot 19,
   en même temps que `OrphanCleanupService` pour `recordings/annual/`.
7. **`planNext` n'a pas de test d'intégration EventKit** : il exigerait une autorisation calendrier.
   La partie décidable (date, titre, absence de dialogue bloquant) est couverte par
   `OneOnOneThreadStore.nextPlannedDate` et `OneOnOneRecapBuilder.nextMeetingTitle`.

### Laissé aux lots 11 à 14

Les grilles `300 | 1fr | 320` et `308 | 1fr | 356`, le glisser-réordonner, l'histogramme rendu, les
chips, le tableau des engagements et son filtre, `DeliveredItemsBuilder` (lot 13), la préparation en
2 minutes (lot 14), le câblage de `NoteCommandCatalog` dans le composeur, l'ouverture automatique la
veille. Toutes les règles qu'ils afficheront sont ici, pures et testées.

### Prochaine action

Fusionner la pile dans l'ordre `0A/0B → 1a → 1b → 2 → 3 → 10a → 10b`, puis attaquer le **lot 11**
(1:1 manager, écran de séance `2a`), qui dépend des lots 2 et 10.

## Refonte de l'écran de réunion — lot 6 : ressources en séance, tiroir et épinglage (2026-09-07)

Branche `feat/refonte-lot-6-ressources`, **sur** `feat/refonte-lot-3-rail-actions` : la PR
**empile** les lots 0A, 0B, 1a, 1b, 2 et 3 (PR #19–#24, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-6-ressources.md` (14 tâches, toutes faites).
ADR : `docs/adr/2026-09-07-pieces-copiees-jamais-referencees.md`.

**État : livré, `swift build` propre, `swift test` complet vert (2 017 tests), PR ouverte, non
mergée. Recette visuelle non faite — voir « Écarts assumés » n° 1.**

### Ce qui est en place

**La politique de stockage a changé de camp (D5).** Une pièce de séance était *référencée* :
`filePath` gardait le chemin d'origine et `bookmarkData` un signet vers lui. Elle disparaissait
donc au premier rangement du disque, la sauvegarde n'était pas autonome, et ni le partage à
l'écran, ni l'annotation, ni l'épinglage n'avaient d'ancre. Elle est désormais **copiée** dans
`recordings/<uuid>/documents/<yyyyMMdd-HHmmss>_<nom>`, à côté de `slides/` de la même réunion.
`MeetingAttachmentService.attachDocument` copie **avant** d'insérer la ligne — une source
illisible ne laisse plus derrière elle une pièce sans fichier, qu'on ne distinguerait pas d'une
orpheline — puis `importDocument` extrait et indexe le texte **de la copie**. La ligne porte
`scope`, `mimeType`, `byteCount`, `addedByName` (`AppSettings.ownerName`) et un `stableID`
(colonne optionnelle neuve, cible des `sourceRef` de citation). `bookmarkData` est explicitement
`nil` : un signet vers une copie interne n'a aucune valeur, et son absence est le signal le plus
simple qu'une pièce relève de D5.

**La migration des anciennes pièces est paresseuse, et ne supprime jamais rien.**
`AttachmentMigration.migrate(meeting:in:)` tourne à l'ouverture de l'espace Ressources — pas au
lancement : migrer 500 réunions au démarrage bloquerait l'app pour un bénéfice nul sur celles
qu'on ne consulte plus. Source présente → copiée, `filePath` réécrit, `byteCount`/`mimeType`
complétés, signet effacé. Source disparue → la pièce **reste visible** et devient *orpheline*
(état **calculé**, pas une colonne : un drapeau mentirait après restauration d'une sauvegarde sur
une autre machine), et sa vignette affiche « Fichier introuvable — relier », qui ouvre un
`NSOpenPanel` et **copie** le fichier redésigné. Le signet sert une dernière fois, en migration
seulement : il donne une chance de retrouver un fichier simplement *déplacé*, ce que le chemin
brut ne sait pas faire. Le passage backfille aussi les `stableID` manquants — sans eux, `Citer`
n'a rien à mettre dans la référence de la puce.

**Les trois services de maintenance connaissent le nouveau dossier** (programme §2.4 point 6).
`StorageStatsService.documentsUsage(inRecordings:)` scanne `recordings/*/documents` — le dossier
fait foi, y compris pour un fichier qu'aucune ligne ne réclame plus, qui est justement celui
qu'on veut voir dans la répartition ; les lignes encore référencées hors de l'app s'y ajoutent
sans double-compte. `OrphanCleanupService.orphanAttachments` **exclut** deux familles : les
pièces copiées (un fichier interne manquant est un incident à signaler, pas une ligne à effacer
avec son texte extrait, ses chunks RAG et ses citations) et les pièces `link`, dont `filePath`
porte une URL — `fileExists` y répond toujours faux, et les proposer aurait supprimé tous les
liens collés en séance. `MeetingAttachmentDTO` transporte les sept colonnes cibles en champs
**optionnels** : une sauvegarde antérieure reste décodable et retombe sur les défauts.

**Un adaptateur, pas trois listes.** `ResourceItem` unifie `MeetingAttachment`,
`ProjectAttachment` et `SlideCapture` — trois modèles sans parenté qui alimentent la même
colonne de 396 px. Structure de valeur, fonctions pures : `all(for:)`, `sorted`,
`filtered(_:by:)`, `counts`, `metadata(calendar:)` (« Ajouté par Sylvain · 09:22 · 84 Ko », chaque
partie disparaissant quand elle est inconnue au lieu de laisser un séparateur orphelin). Trois
décisions y sont inscrites : le **lot** de captures (kind `slides`) est un conteneur à chemin
virtuel, il ne paraît pas comme ressource mais ses PNG oui, un par vignette ; le `t` d'une
capture **est** son épinglage — une capture prise en séance est ancrée dans le temps par
construction ; et les captures ne comptent pas dans « Cette séance », qui annonce `4 séance` sans
elles. L'identité d'une pièce de projet, qui n'a pas de `stableID`, est dérivée de son chemin
(FNV-1a) : aléatoire, SwiftUI remonterait la vignette à chaque rendu.

**Les liens n'appellent personne.** `AttachmentLinkImporter` reconnaît une URL http(s) et refuse
tout le reste (`about:`, `file:`, `mailto:`, un bloc multi-lignes, du texte libre) : coller trois
lignes de notes ne doit pas produire une ressource intitulée « trois lignes de notes ». Le
libellé vient de l'URL seule — dernier segment décodé, à défaut le domaine sans `www.` — parce
qu'aller chercher le `<title>` d'une page ferait sortir l'app de la boucle locale pour un
libellé, ce que le §8 interdit sans le signaler. Les extensions techniques (`.html`, `.php`)
disparaissent du libellé, un `.pdf` distant reste : il dit ce qu'on va ouvrir. La cible vit dans
`filePath` — une colonne `linkURL` dédiée aurait créé deux vérités pour la même information.

**Le tiroir : un seul corps pour deux surfaces.** `ResourcesPanel` porte l'en-tête (compteurs
`n séance` / `n projet`, `＋ Importer` plein `accent/action`), les quatre filtres, les vignettes,
la zone de dépôt permanente et le pied. `ResourcesDrawer` l'emballe à 396 px, superposé, ombre
`-8px 0 24px rgba(0,0,0,.07)`, `Esc` pour fermer — **sans voile** sur la colonne de gauche,
contrairement à la fiche projet du lot 9 : on continue de prendre des notes pendant qu'on cherche
un document, et un voile dirait le contraire. `MeetingResourcesSpace` montre le **même**
`ResourcesPanel` en pleine largeur (spec §4.1) ; deux vues jumelles auraient divergé au premier
ajustement. Son contenu provisoire du lot 1 — la liste de lignes avec menu `⋯` — est retiré.

**Les vignettes.** `ResourceTypeIcon` 34 × 40 : le **texte** porte le type (`XLS`, `PDF`, `PNG`,
`URL`), la couleur le confirme — une palette seule serait illisible pour un daltonien ; cinq tons
pris dans les accents existants, aucune couleur nommée hors `One2OneTokens`. `ResourceTile` : la
pièce présentée est **la seule** à porter trois actions (`À l'écran` plein, `Citer`, `Envoyer`),
les autres n'affichent que la leur (`Présenter`, `Ouvrir` pour un lien) — c'est ce que montre la
capture, et c'est ce qui garde la colonne lisible : trois boutons sur vingt vignettes noieraient
celle qui compte. Le clic droit porte le reste. Un filtre vide dit **quoi faire**, table
exhaustive sans `default` : un cinquième filtre ne compilera pas sans son invite.

**Le pied `À L'ENVOI DU RAPPORT`.** Trois cases, les deux premières cochées par défaut,
persistées **par réunion** sur `Meeting.reportAttachmentOptionsJSON` (une revue de projet et un
1:1 ne se diffusent pas de la même façon). Un JSON vide, tronqué ou écrit par une version future
retombe sur les défauts — un pied sans cases serait un cul-de-sac, et une exception empêcherait
d'ouvrir l'espace. Les libellés portent des nombres réels (`les 2 pièces épinglées`, `les 6
participants`) : une case qui promet des pièces épinglées quand il n'y en a aucune promet du
vide. La troisième case disparaît si la réunion n'a pas de projet.

**Les quatre ouvertures de la spec §4.1** : l'espace `Ressources` ; le bouton `Capture` de la
barre du haut (filtre Captures — le tiroir **devient** la galerie, et le retrait d'une capture y
est possible pour ne pas perdre la capacité que l'ancien popover portait) ; le dépôt **n'importe
où** dans la fenêtre (une ligne dans `MeetingSpaceView`) ; `⌘⇧V`. Le collage cherche un lien
**avant** une image : une adresse copiée depuis un navigateur arrive souvent avec un aperçu, et
l'inverse transformerait chaque lien collé en capture.

**`ResourceCoordinator` a vidé `MeetingView` de ses imports.** Les quatre chemins qui y vivaient
(`onDrop`, `handleFileDrop`, `importDocuments`, `fileImporter`) n'y avaient rien à faire : ils ne
parlent que de ressources, et le programme §2.4 point 1 interdit d'ajouter à ce fichier.
`MeetingView` perd ~45 lignes, deux `@State` (`attachmentError`, `isImportingAttachment`), un
troisième devenu inutile (`isDraggingDoc`) et le popover `showSlidesList` sans appelant ; il n'y
gagne **aucune** ligne de logique. **1 984 lignes**, contre 2 045 pour le lot 3.

**La carte « À l'écran ».** `À l'écran <nom> · p. 2`, pagination pour les PDF, `Annoter` /
`Épingler à mm:ss` / `Arrêter le partage`. Elle n'existe que **pendant** un partage — sans
document présenté elle disparaît de la colonne au lieu de laisser un cadre vide, même règle que
la pilule de la barre. Le bouton porte le timecode : un simple « Épingler » laisserait deviner à
quel instant l'épingle tombe. Si l'identifiant présenté ne désigne plus rien (pièce retirée), la
carte s'efface d'elle-même.

**L'aperçu.** `PDFKit` rend une page **en image** plutôt que de monter un `PDFView` : la scène
est un document figé à la page courante, pas un lecteur dont les barres de défilement et les
gestes de zoom se disputeraient le défilement de la colonne. Une image se charge telle quelle ;
tout le reste — `.xlsx`, `.pptx`, `.docx` — affiche « Aperçu indisponible — le document reste
partagé et citable », parce qu'un cadre blanc laisserait croire à un chargement qui n'arrive
jamais. La légende « Aperçu — les participants voient la même page » est **sous** le document :
posée par-dessus, elle masquerait le bas de la page, c'est-à-dire souvent le total du chiffrage
qu'on est précisément en train de montrer. La scène est mesurée en `background` et non dans un
`GeometryReader` englobant — le programme §2.4 point 4 interdit de faire dépendre une mise en
page d'elle-même (`_NSDetectedLayoutRecursion`).

**L'annotation.** Cadre, flèche, texte — trois formes et pas une de plus : le besoin en séance
est d'attirer l'œil en trois secondes, un éditeur graphique serait un autre produit. Les
coordonnées sont **normalisées** `0…1` : en points, une annotation glisserait à côté de ce
qu'elle désigne au premier redimensionnement de fenêtre. Un clic sans glisser ne sème pas de
point invisible. `Enregistrer` compose la page rendue et le calque en un **PNG neuf** sous
`recordings/<uuid>/slides/`, enregistré comme `SlideCapture` horodatée à la tête de lecture, donc
visible sur la frise : le fichier source n'est jamais ouvert en écriture (spec §4.2).

**L'épinglage.** `pinnedAtT`, la puce `◫ Chiffrage_Marine_v3 · p.2` **collée à la note courante**
— la dernière ligne posée à ou avant le timecode — parce que la pièce illustre ce qu'on vient
d'écrire et n'est pas un événement séparé ; c'est aussi ce que montre la capture, une seule ligne
à `12:08`. La puce vit dans le **texte** et pas seulement dans le `sourceRef` : la colonne
affiche du texte, et une référence invisible n'aide personne à relire la séance. Le `sourceRef`
(`kind: .capture`, `stableID` de la pièce) est posé en plus, pour que le clic mène quelque part
et que le rapport du lot 15 sache quoi citer. `Citer` fait la même chose **sans** épingler ;
citer deux fois la même page n'écrit qu'une puce, mais `citationCount` compte les deux clics —
c'est bien deux fois qu'on a désigné la pièce. Désépingler **laisse** la puce déjà écrite :
réécrire l'historique parce qu'on a changé d'avis serait pire que le désépinglage.
`Meeting.pinnedAttachments` est trié par timecode, `MeetingTimelineMarkers+Pins` ajoute le
**carré** de la spec §2.4 sur la frise (fichier d'extension : trois lots travaillent en parallèle
et deux autres y ajouteront leurs repères), et la bande `ÉPINGLÉ DANS LA SÉANCE` en est la
surface — chips horodatées, celle du moment courant en `accent/action` à 1,5 s près, clic →
`seek` + remise à l'écran. `Envoyer` = `NSSharingServicePicker`.

**La pilule de la barre du haut.** `MeetingSharingState` est pur : `pillLabel(isPresenting:
presentCount:)`. Six présents, **cinq** spectateurs — on ne se compte pas parmi ceux à qui l'on
montre quelque chose, et la capture l'énonce en trois endroits (6 au bandeau, `5 voient` dans la
barre, `6 participants` au pied). Jamais négatif. Sans partage, la pilule **disparaît** : pas
d'état grisé, qui occuperait la place et se lirait comme un contrôle désactivé.

**Jeu de démonstration** : `RefonteDemoSeed+Lot6.swift`, extension —
`RefonteDemoSeed.swift` n'est **pas** touché (il a déjà été le lieu d'un conflit à l'intégration
des lots 2 et 3). Les chiffres de la capture sont tenus exactement : `4 séance` (trois fichiers
**plus le lien**, ce sont bien les quatre vignettes de l'image), `17 projet`, deux épinglées à
`04:12` et `12:08`, une pièce « citée 3 fois », `84 Ko` sur la vignette présentée. Les fichiers
sont **réellement écrits** sur disque : une vignette pointant un fichier absent s'afficherait
orpheline, et la recette montrerait quatre invites de reliaison au lieu du tiroir. Le menu
**Réunion → Charger le jeu de démonstration (refonte)** appelle désormais `seedLot6`, toujours
idempotent.

### Tests

`swift build` propre (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`, `MeetingTagSuggester`). **`swift test` complet
vert : 1 041 XCTest (1 ignoré, 0 échec) + 976 Swift Testing en 140 suites = 2 017 tests**, contre
1 931 au lot 3. Dix suites neuves, 86 tests :

| Suite | Ce qu'elle tient |
| --- | --- |
| `AttachmentCopyPolicyTests` (12) | sous-dossier, nommage horodaté, MIME `UTType`, catégories, poids `84 Ko`, badges et tons |
| `AttachmentCopyImportTests` (6) | **supprimer l'original ne rend pas la pièce illisible** ; métadonnées ; une source illisible n'insère aucune ligne |
| `AttachmentMigrationTests` (7) | source présente → copiée, idempotent ; absente → orpheline **sans exception** ; reliaison ; backfill des `stableID` |
| `StorageStatsDocumentsTests` (3) | le nouveau dossier est compté, sans double-compter WAV ni captures |
| `ResourceItemTests` (12) | les trois sources, les quatre filtres, les compteurs `4/17`, le tri, les métadonnées |
| `AttachmentLinkImporterTests` (7) | libellé hors ligne, refus de tout ce qui n'est pas http(s) |
| `ResourcesStateTests` (15) | **critère chantier 3 n° 1** : un dépôt ne change ni espace, ni mode, ni focus, ni note en cours ; pagination bornée ; options du pied |
| `MeetingSharingStateTests` (6) | **critère n° 2** : l'état se dérive sans le tiroir ; 6 présents → `5 voient` ; sans partage, rien |
| `AttachmentPinningTests` (12) | **critère n° 3** : `pinnedAtT`, `pinnedAttachments` trié, puce et `sourceRef` dans les notes, repère de frise, idempotence |
| `RefonteDemoSeedLot6Tests` (6) | les chiffres de la capture, aucune orpheline, idempotence |

Suites de non-régression exigées, vertes : `OrphanCleanupServiceTests` (+2 tests),
`IndexStatsServiceTests`, `BackupWithoutInterviewTests`, `SchemaV3MigrationTests`.

### Écarts assumés

1. **Recette visuelle non faite : deux processus portent le nom `OneToOne`.** L'écran était
   déverrouillé (19 h, aucune fenêtre Teams ne portait de titre de réunion — la seule était
   « Conversation | … »), un `.app` de recette a bien été empaqueté depuis le build **debug** du
   worktree (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` + `default.metallib`
   repris de `Mickey.app` + signature ad hoc) et **lancé avec `HOME` et `CFFIXED_USER_HOME`
   isolés** dans le scratchpad, garde-fou vérifié : son store est bien
   `…/scratchpad/fakehome-lot6/Library/Application Support/OneToOne/OneToOne.store`, **le store
   de production n'a jamais été touché**. Mais un **second** processus nommé `OneToOne` tournait
   (`.build/arm64-apple-macosx/release/OneToOne`, une bissection d'un autre agent) : `System
   Events` cible un processus **par son nom**, et c'est cette autre instance qu'il a atteinte —
   son menu « Réunion » n'avait ni `Assistant…`, ni `Poser un marqueur`, ni l'entrée de
   démonstration, ce qui l'a trahie (elle est bâtie sur un commit antérieur au lot 1). Piloter
   les menus dans ces conditions revenait à agir au hasard sur l'app d'un autre agent : la
   recette a été **abandonnée**, et l'instance de recette fermée par son PID seul. Rien n'a été
   déposé dans `docs/superpowers/specs/refonte-2026-09/recette/`.
   **À refaire quand aucun autre `OneToOne` ne tourne** (`ps aux | grep [O]neToOne` doit ne
   montrer que le `.app` de recette) : `zsh scratchpad/package-lot6.sh` puis
   `zsh scratchpad/run-lot6.sh` (les deux scripts sont écrits et fonctionnels), menu **Réunion →
   Charger le jeu de démonstration (refonte)**, ouvrir `[P25_110] Partage statut final…` depuis
   la **fenêtre principale** (la fenêtre dédiée `1to1-meeting` a un crash préexistant en bundle,
   traité ailleurs), espace **Ressources** ou bouton **Capture** pour déplier le tiroir,
   `Présenter` sur `Chiffrage_Marine_v3.xlsx`, redimensionner à 1 280 puis 1 920 px,
   `screencapture -x` vers `recette/lot-6-{1280,1920}.png`, comparer à
   `ecrans/3a-tiroir-ressources.png`.
2. **La puce `◫ … · p.n` est du texte, pas une chip bleue.** La capture la montre en pilule
   `accent/action` dans la ligne de note ; ici elle est **écrite dans le texte** de la note et
   `TimedNotesColumn` (lot 2) l'affiche comme le reste. La rendre en pilule demanderait de
   toucher la colonne de notes, que les conventions anti-conflit du lot 6 réservent. Le
   `sourceRef` est bien posé : le rendu en chip est un ajout de vue, pas de donnée, et il peut
   se faire au lot 15 avec le bloc de rapport.
3. **`MeetingAttachment` gagne une colonne `stableID`** alors que le périmètre annonçait
   « uniquement `reportAttachmentOptionsJSON` et l'état orphelin » dans `Models/`. Sans elle, un
   `SourceRef` ne peut pas désigner une pièce — or le critère n° 3 exige que la puce insérée dans
   la note mène à la pièce citée. C'est une colonne **optionnelle à défaut `nil`**, backfillée par
   `ensuredStableID` comme `Meeting` et `Collaborator` le font depuis toujours : lightweight
   migration, aucune version de schéma. `reportAttachmentOptionsJSON` est allée dans
   `OtherModels.swift`, où `Meeting` vit réellement.
4. **Le filtre `Cette séance` compte le lien.** La capture annonce `4 séance` et montre quatre
   vignettes dont l'URL : un lien déposé en séance est une ressource de la séance, exactement
   comme un PDF. Les **captures**, elles, en sont exclues — elles ont leur propre onglet, et les
   compter deux fois aurait fait mentir le compteur.
5. **Une capture ne s'épingle pas ; son `t` **est** son épinglage.** `SlideCapture` n'a pas de
   `pinnedAtT`, et lui en ajouter un aurait créé deux vérités pour la même chose : une capture
   prise pendant la séance est ancrée dans le temps par construction. La bande `ÉPINGLÉ DANS LA
   SÉANCE` liste donc les pièces épinglées **et** les captures horodatées, ce qui est exactement
   ce que la capture montre (`04:12 · Comptes_GitLab.png` à côté d'un document).
6. **`MeetingSlidesPopover` n'a plus d'appelant.** Le bouton `Capture` mène au tiroir, qui est
   devenu la galerie ; le retrait d'une capture y est possible au clic droit, pour ne pas perdre
   la seule capacité que le popover portait. La vue reste dans le dépôt : le lot 7 lui substitue
   sa bande de captures, et la supprimer maintenant aurait empiété sur son périmètre.
7. **`Relier` passe par un `NSOpenPanel`**, pas par un second `.fileImporter` : macOS n'en
   présente pas fiablement deux dans la même hiérarchie de vues — l'un masque l'autre, ce que
   `MeetingView.FileImportTarget` documentait déjà. Le panneau est indépendant de la hiérarchie.

### Fichiers partagés touchés

Conformes aux conventions anti-conflit, au minimum près :
`MeetingScreenModel.swift` (**une** ligne, `var resources`), `MeetingSpaceView.swift` (**deux**
modifications — overlay du tiroir et `onDrop` — plus le paramètre `onImportResources` qu'elles
exigent), `MeetingTopChromeBar.swift` (la pilule de partage et son entrée `resources` seulement),
`MeetingView.swift` (**retraits** + le câblage de trois closures), `MeetingLiveSpace.swift`
(montage de la carte « À l'écran » et `allMarkers`), `Models/MeetingModels.swift` (`stableID`),
`Models/OtherModels.swift` (`reportAttachmentOptionsJSON`), `Menus/{MeetingCommands,
MeetingMenuActions}.swift` (`⌘⇧V` et `Ressources…`), `Services/{AttachmentImporter,
MeetingAttachmentService, BackupService}.swift`, `Services/Maintenance/*`. Aucun fichier de
`Views/Meeting/Session/**` (lot 4), `Spaces/Review/**` (lot 5), `Services/OneOnOne/**` ou
`Models/OneOnOne*`/`Commitment*` (lot 10) n'est touché ; `Rail/**`, `Notes/**` et `Transcript/**`
sont réutilisés sans modification.

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → (lot 6)`, puis
reprendre la **recette visuelle** du lot 6 quand aucun autre `OneToOne` ne tourne (écart n° 1).
Le bloc de rapport « pièces épinglées » — seconde moitié du critère n° 3 — est au **lot 15** et
lira `Meeting.pinnedAttachments`, déjà exposé et testé.

## Refonte de l'écran de réunion — lot 5 : poste de pilotage (mode Relire) (2026-09-07)

Branche `feat/refonte-lot-5-poste-pilotage`, **empilée** sur
`feat/refonte-lot-3-rail-actions` : la PR contient donc les lots 0A, 0B, 1a, 1b, 2 et 3
(PR #19–#24, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-5-poste-pilotage.md` (11 tâches).

**État : livré, `swift build` propre, `swift test` complet vert.**

### Ce qui est en place

**Le mode Relire est le poste de pilotage de `1c-poste-de-pilotage.png`** (décision D0 :
« 1c est la disposition du mode Relire »). `MeetingSpaceView` le route **hors** de sa colonne
fluide : il prend toute la surface, sans bandeau d'indicateurs, sans rail de 330 px et sans
dock injecté — il monte les siens. `MeetingSpacesBar.estMasquee(space:mode:)` lui rend la
barre d'espaces, et **seulement à lui** : en mode Relire, les espaces Rapport et Ressources
n'ont pas de nav latérale, et sans barre on s'y retrouverait sans rien pour en sortir.

**Nav latérale de 190 px** (`Review/ReviewSidebarNav.swift`) — badge `1:1 One2One`, libellé
`SÉANCE`, sept entrées dont **chacune porte un compteur ou un état** : `Synthèse généré/—`,
`Notes n` (les `MeetingNote`), `Transcription mm′`, `Actions n` (compteur en `accent/report`
dès qu'une action n'a pas de porteur), `Rapport ✓/—`, `Documents n/＋`, `Assistant ⌘K`.
L'entrée active est une **carte blanche à ombre de 1 px** (spec §2.7) — pas un soulignement,
qui reste la marque de la barre d'espaces. `Rapport` et `Documents` **changent d'espace**
(Rapport, Ressources), `Notes` et `Transcription` ramènent en mode **En séance** — c'est le
sens de « transcription repliée » (spec §2.2) : elle est à un clic —, `Assistant` ouvre le
dock, et `Synthèse` et `Actions` déplacent le défilement de la colonne principale. En pied,
le bloc `PROJET` (nom + trois dernières réunions antérieures du
projet, cliquables) et le bloc `ALERTES · n` dont la lecture de sévérité et la teinte sont
celles du rail (`ActionsRailRisks.teinte`) — deux définitions finiraient par peindre le même
risque de deux couleurs.

**En-tête** (`Review/ReviewHeader.swift`) — titre sans son préfixe de référence, ligne
`P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants` **sans point médian
orphelin** (une réunion hors projet perd le segment, elle ne le laisse pas vide), puis
`Capture n`, `Exporter ⌄` — les cinq destinations existantes de `MeetingMenuActions`,
regroupées, désactivées sans rapport — et `Rapport ✓ 6:20`. Le sélecteur
`Préparer / En séance / Relire` est ici, en haut à droite : la barre d'espaces étant masquée,
sans lui on entrerait en relecture sans pouvoir en sortir.

**Cartes** — `Review/OneSentenceCard.swift` : `EN UNE PHRASE`, badge `généré`,
`Meeting.shortSummary` rendu **avec son gras** par `AttributedString(markdown:)` (et non
`MarkdownText`, qui imposerait ses fontes là où le corps doit rester en Plex Sans 12,5),
chips de `MeetingTag`, invite « Générer la synthèse » appelant `SummaryCard.generate` — la
**même** fonction que la carte Résumé du dashboard.
`Review/DecisionsCard.swift` : `DÉCISIONS PRISES · n` depuis les `MeetingNote(kind:
.decision)` triées par `t` — ce sont elles qui portent le timecode, et un timecode est ce qui
rend une décision vérifiable. Timecode `accent/report` cliquable → `playhead.seek`. Repli sur
`Meeting.decisions` **sans** timecode pour une réunion importée (`--:--` plutôt que `00:00`,
instant où rien ne s'est passé). `separerPorteur` détache le nom de fin de phrase, au tiret
cadratin comme entre parenthèses, avec trois garde-fous : le segment doit être le dernier,
commencer par une majuscule et ne porter aucune ponctuation interne — sans quoi « — reste à
chiffrer la fin Marine » deviendrait un porteur.

**Tableau d'actions dense** (`Review/ActionsTable.swift`) — sept colonnes aux largeurs de la
spec (`20 | 1fr | 108 | 92 | 62 | 76 | 30`, fixées par un test), lignes alternées
`surface` / `surface/alt`, sélection en `accent/action bg2`. **Édition inline par cellule** :
un clic déplie le sélecteur **sous** la ligne (responsable via `OwnerPickerMenu`, échéance
via raccourcis + `DatePicker` compact, charge), `Tab` avance de champ, `Esc` referme, et
aucune modale (gardé par lecture des sources). Le titre s'édite au double-clic
(`EditableTextField`) ; un intitulé vidé ne supprime pas l'action — c'est le menu `⋯` qui le
fait. Clavier : `↑↓` navigue (borné, jamais cyclique), `Espace` coche, `⌥↑↓` réordonne via
`ActionsTableCommands`, qui **normalise `sortOrder` en 0…n−1** — réécrire seulement les deux
lignes échangées laisserait des égalités que `ActionsRailGrouping.triees` tranche par
échéance, et la ligne déplacée reviendrait à sa place. Sélecteur
`Tableau · Eisenhower · Calendrier` (les deux planches du lot 3 en `compact: true`),
`＋ Action` bleu, badge `n sans responsable`, pied `ActionComposer` **réemployé tel quel** +
`n autres · tout afficher` (repli à 5 lignes).

La colonne `ÉCHÉANCE` porte les quatre états de la capture, dans cet ordre : une date réelle,
puis `Reporté ×n` (`deferralCount`), puis `Urgent` en `accent/report`, puis l'invite
`＋ date`. La colonne `SOURCE` mène au timecode (`04:12 ↗`) ou, à défaut, à la **date de la
réunion d'origine** (`1 sept.` de la capture) : une action reportée a une provenance, pas un
instant.

**Frise audio pleine largeur** (`Review/ReviewAudioTimeline.swift`) — ce n'est pas une
seconde frise : c'est `AudioTimelineStrip` du lot 2 avec `labelled: true`, un nouveau mode
dont le **défaut ne change pas d'un pixel** le rendu de 22 px du mode En séance. Autour,
seulement ce que la capture montre : le bouton `▶` (qui charge le WAV dans le lecteur **de la
tête de lecture**, pas un second — deux lecteurs, ce sont deux positions) et `✂ Éditer`, qui
passe par `MeetingMenuActions.editAudio` : la feuille d'édition audio est présentée par
`MeetingView`, et une seconde présentation ici en ferait deux.

**Étiquettes sans chevauchement** (`Services/Meeting/TimelineLabelLayout.swift`) — deux
passes : les **décisions d'abord**, les notes ensuite dans ce qui reste. À l'étroit, perdre
`DÉCISION` pour garder un timecode nu serait le mauvais échange. Une étiquette qui n'entre
pas est **abandonnée**, jamais décalée : décalée, elle ne désignerait plus son marqueur. Les
captures et les planches n'ont pas d'étiquette — leur carré se lit déjà.

**Passage automatique en Relire après le rapport** — `ReviewState.apresGenerationDuRapport`
remplace le `screen.space = .report` du lot 1 dans le chemin post-génération de
`MeetingView.generateReport` : espace `Réunion`, mode `Relire`, section `Synthèse`, et une
demande de focus sur le champ d'assignation de la première action sans responsable (spec
§2.2). Les demandes sont **jetonnées** — deux générations de suite doivent toutes deux
replacer le curseur, or la seconde écriture d'une valeur identique ne notifie personne.
`ActionsTable` la sert et déplie le tableau si la ligne visée est au-delà des cinq premières :
un curseur sur une ligne qu'on ne voit pas n'est pas un focus.

### Créés

`OneToOne/Services/Meeting/` : `ActionsTableCommands.swift`, `TimelineLabelLayout.swift`.
`OneToOne/Views/Meeting/Spaces/Review/` : `ReviewState`, `ReviewSidebarNav`, `ReviewHeader`,
`OneSentenceCard` (+ `ReviewCard`), `DecisionsCard`, `ActionsTable`, `ReviewAudioTimeline`.
`OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot5.swift`.

### Modifiés

`MeetingReviewSpace.swift` (recomposé, non générique — le contenu provisoire du lot 1
disparaît), `MeetingSpaceView.swift` (routage du mode Relire, deux paramètres ajoutés),
`MeetingSpacesBar.swift` (`estMasquee` + garde de corps), `AudioTimelineStrip.swift`
(`labelled`, `hauteur(labelled:)`, `candidats(_:)`), `MeetingScreenModel.swift` (**une
ligne** : `var review = ReviewState()`), `MeetingView.swift` (ligne post-génération + deux
paramètres au call-site), `MeetingCommands.swift` (le menu de démonstration appelle
`seedLot5`).

### Tests

`swift build` propre (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`). `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 966 Swift Testing en 136 suites = 2 005 tests**, contre
1 931 après l'intégration des lots 2 + 3 (**+74, +6 suites**), aucune régression.

Nouvelles suites : `ActionsTableCommandsTests` (14), `TimelineLabelLayoutTests` (10),
`ReviewStateTests` (10), `ReviewSidebarNavTests` (15), `ReviewCardsInviteTests` (15),
`RefonteDemoSeedLot5Tests` (9).

Critères du lot :

- **Navigation clavier complète du tableau** — `ActionsTableCommandsTests` : `↑↓` borné aux
  deux extrémités, sélection périmée ramenée dans le tableau, `⌥↑↓` refusé aux bords, et la
  preuve qui compte — après `appliquerOrdre`, `ActionsRailGrouping.triees` rend **exactement**
  le nouvel ordre, le lecteur réel étant celui-là.
- **Étiquettes sans chevauchement** — `TimelineLabelLayoutTests` : la propriété est vérifiée
  par paires successives (`début ≥ fin précédente + espacement`), aux deux bords, sur une
  durée nulle (aucun `NaN`) et sur des candidats non triés ; plus la règle de priorité (à
  l'étroit, `DÉCISION` l'emporte).
- **Compteurs de la nav, exhaustivité** — `ReviewSidebarNavTests` : une entrée par
  `ReviewState.Section`, **aucune** sans complément — sur une réunion vide comme sur une
  réunion pleine. Une entrée ajoutée demain fait échouer la suite tant qu'elle n'a pas dit ce
  qu'elle contient.
- **Passage en Relire après rapport et focus posé** — `ReviewStateTests` : la transition, le
  jeton de focus qui avance à chaque demande, la consommation qui l'empêche de se rejouer, et
  une lecture de `MeetingView.swift` qui refuse le retour du `screen.space = .report`.
- **Aucune zone vide sans invite** — `ReviewCardsInviteTests` lit les sources du dossier
  `Review/` : chaque surface porte une invite (`MeetingEmptyInvite`, `InvitePill` ou le `＋`
  de la nav) **ou** se déclare dans une liste fermée avec sa raison. La suite refuse aussi
  toute couleur nommée hors `One2OneToken` et toute modale, et un premier test vérifie que le
  dossier lu est bien celui du mode Relire — sans quoi les autres ne prouveraient rien en
  passant.

### Jeu de démonstration

`RefonteDemoSeed+Lot5.seedLot5` complète le semis du lot 3 **sans modifier son fichier** (les
lots 4, 6 et 10 travaillent sur la même base, et c'est le fichier qu'ils touchent tous) :
trois décisions horodatées `11:03` / `13:40` / `20:15`, la première nommant son porteur ; les
quatre thèmes `Migration AP · Facturation · GitLab / CI-CD · Ressources` ; le résumé de la
capture avec son gras ; et deux réunions de plus dans le fil du projet (`31 août —
Gouvernance`, `26 août — Situation AP`), qui complètent le `1 sept. — COSUI hebdo` du lot 3.
L'idempotence des décisions se joue sur le **timecode** et non sur le texte : la formulation
de 1c n'est pas celle de 1a, et une comparaison sur la chaîne aurait créé une seconde
décision au même instant.

### Recette visuelle — non faite : le poste est occupé

L'écran **n'est pas verrouillé** cette fois (`ioreg -n Root -d1 -r | grep
CGSSessionScreenIsLocked` ne rend aucune clé, contrairement aux lots 1 à 3), mais une
**réunion Teams réelle est en cours d'enregistrement sur ce poste** : lancer une application
graphique, prendre le contrôle du clavier par `osascript` ou déclencher `screencapture`
aurait interrompu la séance ou capturé son contenu. Aucune de ces commandes n'a été lancée,
et rien n'a été déposé dans `docs/superpowers/specs/refonte-2026-09/recette/`.

Ce qui a été vérifié : `swift build -c release` réussit (310 s, aucune erreur).

**À refaire, poste libre, en cinq étapes** — les scripts sont dans le scratchpad de session
(`lot5-package.sh`, `lot5-run.sh`) et n'attendent que d'être exécutés :

1. `swift build -c release` depuis le worktree.
2. `lot5-package.sh` — empaquette `Lot5.app` **hors du dépôt** (binaire, `Info.plist`,
   `PkgInfo`, `OneToOne_OneToOne.bundle`, `default.metallib` repris de `Mickey.app`,
   signature ad hoc). Ne pas passer par `Scripts/bump-and-build.sh`, qui incrémente le numéro
   de build et installe dans `~/Applications`.
3. `lot5-run.sh --reset` — lance avec `HOME` **et `CFFIXED_USER_HOME`** jetables. Les deux :
   `NSHomeDirectory()` ignore `HOME` pour une application en bundle, et une recette lancée le
   7 septembre avec le seul `HOME` a semé le jeu de démonstration dans le store de
   production. Le script tue le processus si le store n'apparaît pas dans le home jetable.
4. Menu **Réunion → Charger le jeu de démonstration (refonte)** (il appelle désormais
   `seedLot5`), puis sélecteur de mode → **Relire**.
5. Redimensionner à 1 280 puis 1 920 px, `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-5-{1280,1920}.png`, comparer à
   `ecrans/1c-poste-de-pilotage.png` et consigner les écarts ici.

⚠️ Un **crash préexistant à l'ouverture de la fenêtre dédiée `1to1-meeting` en bundle
release** est en cours de correction par ailleurs : la recette de ce lot devra attendre ce
correctif, ou ouvrir la réunion depuis la fenêtre principale.

**Rien n'a été écrit dans le store de production** : le semis ne se déclenche que par un clic
de menu, et aucune application n'a été lancée.

### Écarts assumés

1. **`Notes 5` de la capture est arithmétiquement impossible.** `1a-cockpit.png` montre
   quatre notes (`04:12`, `07:48`, `11:03`, `15:20`) et `1c` en annonce cinq — tout en
   listant trois décisions à `11:03`, `13:40` et `20:15`, dont deux n'existent pas dans 1a.
   Quatre notes plus deux décisions font **six**, pas cinq. Le semis tient les données
   (six `MeetingNote`, dont trois décisions) et la nav affiche `Notes 6` : c'est la même
   nature d'incohérence de maquette que celle relevée au lot 3 pour `À ASSIGNER — 9`.
2. **`Synthèse` et `Assistant` portent un complément que la capture ne montre pas** (`généré`
   / `—` et `⌘K`). Le critère du lot exige « jamais d'entrée sans compteur ou état, test
   d'exhaustivité » : deux entrées nues seraient précisément les « onglets vides » que le
   titre de la capture bannit. Le complément est en `plexMono(10)` `ink/4`, discret.
3. **Le sélecteur `Préparer / En séance / Relire` s'ajoute en haut à droite de la colonne
   principale**, alors que la capture n'en montre aucun. C'est la consigne du lot (« garde-le
   visible, comme sur 1a ») et c'est nécessaire : la barre d'espaces est masquée dans ce mode,
   et sans ce sélecteur on entrerait en relecture sans pouvoir en sortir.
4. **`Notes` et `Transcription` ramènent en mode En séance** au lieu de défiler dans la
   colonne. Le poste de pilotage n'a ni carte de notes ni carte de transcription (la capture
   n'en montre aucune, et la synthèse et les décisions *sont* la lecture des notes) : une
   entrée qui ne ferait que déplacer un défilement ne mènerait nulle part, et son compteur
   mentirait. C'est ce que veut dire « transcription repliée » (spec §2.2) : elle est à un
   clic. La carte `TRANSCRIPTION` provisoire du lot 1, avec son bouton « Déplier en séance »,
   disparaît donc — son rôle est passé à la nav.
5. **`＋ Action` ne prend pas le clavier.** Le bouton crée la ligne si le composeur porte déjà
   un texte (même chemin que `⌘⏎`) et, sinon, déplie le tableau pour amener le composeur sous
   les yeux. Il ne peut pas focaliser le champ : `ActionComposer` (lot 3) possède son
   `@FocusState` et n'expose aucun jeton, et `Views/Meeting/Spaces/Rail/**` n'est pas
   modifiable depuis ce lot. À reprendre au lot 19, en ajoutant au composeur un jeton de focus
   comme celui du composeur de notes.
6. **Les cinq titres du bloc `ALERTES` ne sont pas ceux de la capture 1c** (« Corruption base
   de données », « Confusion source de code », …) : le semis du lot 3 a choisi les risques de
   `1a-cockpit.png` (« Comptes GitLab désactivés », « Chiffrage du reste à faire non
   validé », …), et `RefonteDemoSeed.swift` est gelé pour ce lot. Le **nombre** (`ALERTES · 5`)
   et la répartition des teintes (deux critiques, un élevé, deux moindres) tombent juste.
7. **Le nom de projet du semis est `S/D — Modernisation CI/CD`**, la capture écrit
   `S/D — Modernisation Chaîne CI/CD`. Même cause : le nom vient du lot 3.
8. **Le focus d'assignation se pose sur la cellule, pas dans un champ de texte.** La spec §2.2
   dit « champ d'assignation » ; le poste de pilotage n'a pas de champ de saisie de
   responsable — c'est un sélecteur (`OwnerPickerMenu`), et la spec §2.5 interdit la modale.
   Le focus sélectionne donc la ligne et **déplie son sélecteur de responsable**, dépliant le
   tableau si la ligne est au-delà des cinq premières.
9. **Les vues Eisenhower et Calendrier n'ont pas de sélection clavier.** Elles réemploient
   `EisenhowerBoard` et `CalendarBoard` en `compact: true` (décision D10) ; `↑↓`, `Espace` et
   `⌥↑↓` n'ont de sens que dans un tableau ordonné, et la spec §2.7 ne les demande que là.
10. **Deux cartes côte à côte s'empilent sous ~900 px** (`ViewThatFits`) : `EN UNE PHRASE` et
    `DÉCISIONS PRISES` à 420 et 340 px de minimum ne tiennent pas dans la colonne fluide de
    520 px que garantit le critère n° 5 du chantier 1.

### Fichiers partagés touchés malgré les conventions anti-conflit

- `MeetingSpacesBar.swift` — la consigne demandait de masquer la barre depuis
  `MeetingSpaceView`, ce qui est impossible : la barre est montée par `MeetingView.mainPanel`,
  au-dessus. Comme `MeetingView.swift` ne devait recevoir que la ligne post-génération, le
  masquage est une fonction pure du fichier de la barre (`estMasquee(space:mode:)`) plus une
  garde de corps — un seul point de touche, et testé.
- `MeetingView.swift` — **deux** points au lieu d'un : la ligne post-génération, et le
  call-site de `MeetingSpaceView`, qui reçoit `menuActions` et `onShowCaptures`. L'en-tête du
  poste de pilotage a besoin des menus d'export existants et du bouton Rapport, la frise du
  `✂ Éditer` ; tous vivent dans `MeetingMenuActions`, que seule `MeetingView` sait
  construire. `@FocusedValue(\\.meetingMenu)` aurait évité le paramètre, mais rend `nil`
  quand la fenêtre n'a pas le focus — des boutons principaux qui s'éteignent au changement de
  fenêtre.
- `MeetingCommands.swift` — une ligne : le menu de démonstration appelle `seedLot5` au lieu de
  `seed`. `RefonteDemoSeed.swift` étant gelé, il n'y avait pas d'autre moyen de brancher le
  complément de semis.

### Prochaine action

1. **Faire la recette visuelle du lot 5** (procédure ci-dessus), poste libre et une fois le
   crash `1to1-meeting` corrigé, puis consigner les écarts avec
   `1c-poste-de-pilotage.png`.
2. Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → lot 5`.
3. Lots suivants : **6** (ressources en séance, tiroir 396 px) et **7** (captures Teams /
   Zoom). Le lot 5 leur laisse deux points d'ancrage : l'entrée `Documents n/＋` de la nav
   latérale, qui ouvre l'espace Ressources, et le bouton `Capture n` de l'en-tête, qui ouvre
   la galerie de captures.

## Refonte de l'écran de réunion — lot 4 : mode séance plein écran (2026-09-07)

Branche `feat/refonte-lot-4-mode-seance`, sur `feat/refonte-lot-3-rail-actions` : la PR
**empile** les lots 0A, 0B, 1a, 1b, 2 et 3 (PR #19–#24, non fusionnées). Ordre de fusion
`#19 → #20 → #21 → #22 → #23 → #24 → celle-ci`. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-4-mode-seance.md`.

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.
Recette visuelle non faite — voir plus bas.**

### Ce qui est en place

**`SessionFullscreenView` : grille `78 | 1fr | 400`, thème `.session`, aucun chrome.**
La barre d'état est la seule surface de chrome de l'écran (spec §2.6) :
`● En séance · P25_110` — le point pulse **si et seulement si** l'enregistrement de cette
réunion tourne —, `mm:ss / mm:ss` de la tête de lecture, les pastilles des participants,
`CP parle`, et `Clore la séance` en `accent/report` plein. Ni barre d'espaces, ni bandeau
d'indicateurs, ni fil d'Ariane, ni rail de 330 px : en séance, douze actions listées à
droite sont une invitation à faire autre chose qu'écouter. Ce qu'il en reste est le bandeau
`EN ATTENTE`, qui ne parle que de ce qui vient d'être décidé.

**Le locuteur courant vient des segments résolus, pas d'un signal live.**
`LiveTranscriptionService` ne publie **aucun** locuteur : la diarisation est *batch*,
`LiveDiarizationAligner.alignToBlocks` s'exécute après le `stop()`, par recouvrement de
timestamps. `SessionCurrentSpeaker` cherche donc le `TranscriptSegment` qui couvre `t` et
dont le `speaker` est résolu en `Collaborator` ; sans lui, la mention est **masquée** (spec
§2.6 : « sinon masqué ») — `S2 parle` dans une barre d'état est du bruit. Bornes
`début ≤ t < fin`, pour qu'un locuteur ne reste pas affiché pendant le silence qui suit son
tour.

**`TimeRailColumn` : axe 3 px, `#e04b3f` sur la portion écoulée.** Ronds `dark/accent
action` pour les notes, carré de rayon 3 `accent/report` pour les décisions, trait `dark/ink`
pour la position — dessiné **après** les repères, pour qu'on voie où l'on est même quand une
note est posée juste là. Libellés mono à 30 px du rail : ils passent donc légèrement derrière
l'axe, comme sur la capture, où l'on lit `04:1` et non `04:12`. Toute la géométrie est dans
`TimeRailGeometry`, pure et testée — une durée nulle est le cas **courant** de cet écran
(séance qui vient de démarrer), et un `Canvas` à qui l'on passe un `NaN` ne dessine rien sans
rien signaler.

**`⌘M` pose une `MeetingNote(kind: .note, text: "")`** (décision D4.1). Un type « marqueur
pur » aurait demandé une colonne, une migration et un second chemin de repère pour le même
besoin : `MeetingTimelineMarkers` lit déjà `meeting.timedNotes`, donc le repère apparaît sur
l'axe sans rien ajouter. En contrepartie, `TimedNotesColumn` **filtre les lignes vides** —
sinon la colonne afficherait une ligne muette dont seul le timecode se lit, et qu'on ne
saurait pas supprimer.

**`AssignmentQueue` : la file en trois gestes, pure et générique.** `responsable → échéance →
suivante`, `Tab` et `⌘⏎` avancent, `Esc` sort **à n'importe quelle étape**, « Passer » saute
sans rien poser, une file vide est close d'emblée (`Assigner maintenant` sur zéro action est
une impasse, pas un formulaire vide). Générique sur l'identifiant : la vue l'instancie sur
`PersistentIdentifier`, les tests sur `Int`. `AssignmentQueueSheet` réutilise
`OwnerPickerMenu` et `ActionCardEditing.raccourcisEcheance` du lot 3 — trois sélecteurs de
responsable dans l'application finiraient par ne plus proposer les mêmes personnes. Le
bandeau lui-même délègue « sans responsable » à `ActionsRailGrouping` (groupe `À ASSIGNER`) :
deux définitions afficheraient deux nombres pour le même écran.

**`SessionCapturedSummary` compte depuis le début de la séance, et rien avant.** La réunion
porte tout son historique, préparation de la veille comprise : `meeting.tasks.count`
afficherait 12 actions là où la séance en a produit 4. L'origine est `recordingStartedAt`
**même s'il précède** l'ouverture du mode (on passe souvent en plein écran une fois la séance
lancée), sinon l'instant d'ouverture. Un horodatage `nil` ne compte pas — `ActionTask.createdAt`
est optionnel, et ces lignes-là sont justement les anciennes.

**`MeetingAssistantController` : la logique d'envoi sort de la vue.** Le panneau de séance
pose les mêmes questions que `MeetingChatView`, qui **délègue désormais** la construction du
prompt au contrôleur (ses tests continuent de passer par `makePrompt`, qui ne fait plus que
transmettre) — un test vérifie que les deux chemins produisent la même chaîne au caractère
près. Les **sources horodatées** de la capture ne sont pas extraites du texte du modèle (un
modèle qui cite mal produirait des liens morts) mais du contexte qu'on lui a effectivement
donné : les chunks RAG retenus, plus la dernière note de la séance. Les `TranscriptChunk` ne
portent pas de timecode — ils sont découpés par longueur, pas par tour de parole — donc
l'instant est retrouvé par recouvrement de texte avec les segments de la réunion d'origine
(`instant(ofExtract:inSegments:)`), et **`nil` plutôt qu'un instant inventé** quand
l'extrait est trop court ou étranger. Une source dans la séance replace la tête de lecture ;
ailleurs, elle ouvre sa réunion.

**Mention `@Prénom` en pilule.** `SessionMentionRuns` découpe la ligne ; la règle
intéressante n'est pas la pilule mais **ce qui en est une** : `@Yann` oui,
`laurent@april.com` non (le `@` y est au milieu d'un mot), `@Inconnu` non tant qu'aucun
collaborateur ne porte ce nom — peindre en bleu une personne qui n'existe pas promet une
notification qui n'aura pas lieu. La reconnaissance passe par `CollaboratorMentionSource`,
la même que l'éditeur markdown. Un test de non-perte recompose la ligne d'origine au
caractère près. Rendu seulement en thème `.session`, par `MentionFlow` + `WrapLayout` (une
`Layout` de flot minimale) : `AttributedString.backgroundColor` ne donne qu'un rectangle
plein, qui se colle au bord du bloc sur une mention en fin de ligne. Le prix payé est la
sélection du texte, perdue sur les lignes qui portent une mention.

**Entrée et sortie.** Le mode est présenté en **substituant le `contentView` de la fenêtre
courante** (`SessionWindowSwapper`), pas dans une `WindowGroup` de plus et pas par un
`overlay` : un overlay posé sur `MeetingSpaceView` laisse visibles la barre du haut, le badge
de préparation et la barre d'enregistrement de `MeetingView` — donc du chrome. La demande
passe par `SessionFullscreenPresenter`, un objet partagé : la pilule audio de
`MeetingTopChromeBar` et l'item `⌃⌘F` de `MeetingCommands` n'ont ni l'un ni l'autre accès au
`MeetingScreenModel`, et faire descendre un binding jusqu'à eux aurait exigé de modifier
`MeetingView`. Un **jeton** et non un booléen : deux `⌃⌘F` de suite doivent tous deux
basculer. `Esc` suit `SessionExitPolicy` — confirmation si et seulement si l'enregistrement
tourne, et un second `Esc` **referme** le dialogue au lieu de le valider.

**Les composants des lots 2 et 3 lisent le thème, ils ne le choisissent pas.**
`TimedNotesColumn`, `NoteComposer`, `TranscriptColumn`, `Chip` et `sectionLabel()` sont passés
de `One2OneToken.*` à `theme.colors.*`. En `.paper`, les couleurs résolues sont **identiques**
et `SessionThemeTests` le fixe : sans ce test, une seule correspondance erronée repeindrait
discrètement l'espace Réunion en clair sans qu'aucune autre suite s'en aperçoive.
`One2OneColors` gagne les sept champs qui manquaient (`surfaceAlt`, `strongBorder`,
`inkMuted`, `actionInk`, `actionBg`, `reportInk`, `warnInk`) ; `One2OneToken` gagne
`railElapsed` (`#e04b3f`), distinct d'`accent/report` — la spec §2.6 nomme une valeur propre,
et la capture le confirme.

### Créés

`OneToOne/Views/Meeting/Session/` : `SessionFullscreenView`, `SessionFullscreenState`
(+ `SessionExitPolicy`), `SessionFullscreenPresenter` (+ `SessionWindowSwapper`, le
modificateur `sessionFullscreen`), `SessionStatusBar`, `TimeRailColumn`,
`AssignmentQueueSheet` (+ `SessionPendingBand`), `SessionAssistantPanel`
(+ `SessionCapturedBlock`), `SessionCapturedSummary`, `SessionCurrentSpeaker`,
`SessionMentionRuns`, `MentionFlow` (+ `WrapLayout`), `MeetingAssistantController`.
`OneToOne/Services/Meeting/` : `TimeRailGeometry`, `AssignmentQueue` (+ `PendingAssignment`).

### Modifiés

`MeetingScreenModel` : **une ligne** (`var session = SessionFullscreenState()`).
`MeetingSpaceView` : **un modificateur** (le point d'entrée). `MeetingTopChromeBar` :
**la pilule audio seule** (le bouton plein écran, visible quand un écran est en mesure de
présenter). `MeetingMenuActions` / `MeetingCommands` : `⌃⌘F` et son item de menu.
`One2OneTokens`, `One2OneTheme`, `One2OneTypography`, `Chip`, `TimedNotesColumn`,
`NoteComposer`, `TranscriptColumn` : lecture du thème. `MeetingChatView` : délégation du
prompt. **`MeetingView.swift` n'est pas touché — un test le vérifie.**

### Tests

`swift build` propre (avertissements préexistants seuls). `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 974 Swift Testing en 142 suites = 2 013 tests**, contre
1 931 après l'intégration des lots 2+3 (**+82, +12 suites**), aucune régression.

Nouvelles suites : `TimeRailGeometryTests` (13), `AssignmentQueueTests` (10),
`PendingAssignmentTests` (3), `SessionCapturedSummaryTests` (6),
`SessionCurrentSpeakerTests` (5), `SessionExitPolicyTests` (3),
`SessionFullscreenStateTests` (4), `SessionMentionRunsTests` (8), `SessionThemeTests` (6),
`SessionNoChromeTests` (6), `SessionFullscreenEntryTests` (6),
`MeetingAssistantControllerTests` (9).

Le critère « **aucun chrome hors la barre d'état** » ne se vérifie pas par l'état d'un
modèle : un `MeetingKPIBand` recopié demain par distraction passerait toutes les autres
suites. `SessionNoChromeTests` **lit les sources** du dossier `Session/` (chemin dérivé de
`#filePath`, avec un premier test qui garde le chemin lui-même) et refuse
`MeetingSpacesBar`, `MeetingKPIBand`, `MeetingTopChromeBar(`,
`MeetingContextualRecorderBar`, `MeetingPrepBadge`, `MeetingAssistantDock(`, `ActionsRail(`
et `MeetingSpaceLayout`, plus toute couleur nommée hors `One2OneToken`. Deux autres tests
lisent tout `OneToOne/` pour vérifier que le point d'entrée n'est posé **qu'une fois** (deux
poses substitueraient deux fois le contenu de la même fenêtre, et la seconde restauration
rendrait la première) et que `MeetingView` ne mentionne rien du lot.

### Recette visuelle : non faite

`ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` ne rend **aucune clé** : la session
n'est pas verrouillée. Le `.app` a bien été empaqueté depuis le worktree (`Lot4.app`, HOME
**et** `CFFIXED_USER_HOME` jetables, garde-fou d'isolation vérifié : le store atterrit dans
le home jetable). Trois obstacles ont fait renoncer, dans cet ordre :

1. **Premier lancement : crash `EXC_BREAKPOINT` dans `_NSViewUpdateConstraints`** (AppKit,
   exception pendant la mise à jour des contraintes). C'est **la signature exacte** du crash
   qu'une autre session bisecte en parallèle sur la même base (`bisect-step.sh`, « crash de
   la fenêtre 1to1 », `grep "Update Constraints"`) : défaut **préexistant**, pas du lot 4.
2. **Lancements suivants : l'application tourne, crée son store, mais n'ouvre aucune
   fenêtre** (`count windows of process "OneToOne"` = 0, menu `Fenêtre` sans liste, journal
   vide). Le menu `Réunion` est complet et porte bien « Mode séance plein écran » ; l'item
   « Charger le jeu de démonstration (refonte) » a été cliqué, sans fenêtre pour l'afficher.
   Piste non tranchée : l'autorisation d'accessibilité est accordée par **identité de
   signature**, et le bundle de recette est signé ad hoc sur un chemin neuf — l'API AX peut
   donc rendre zéro fenêtre alors qu'il y en a une.
3. **Le poste était en réunion Teams réelle** (« OJ — Comité Urbanisation », 20 participants,
   enregistrement en cours) et deux autres sessions se disputaient le bureau. Prendre l'écran
   pour une capture aurait interrompu une réunion en cours. Processus de recette arrêté.

`docs/superpowers/specs/refonte-2026-09/recette/lot-4-1920.png` **n'existe donc pas**, et
aucun écart avec `1b-mode-seance.png` n'est mesuré. À refaire dès que le crash du point 1 est
corrigé (lot en cours ailleurs) et que le poste est libre.

### Écarts assumés avec la capture

- **`EN ATTENTE  3 actions sans responsable`** : le jeu de démonstration du lot 1 pose
  **9** actions sans responsable (`12 · 9 non assignées` au bandeau, `À ASSIGNER — 9` au
  rail), et son arithmétique est vérifiée par `RefonteDemoSeedTests`. Le bandeau affichera
  donc 9 et non 3. Changer le semis pour faire tomber le 3 casserait les trois nombres de
  `1a-cockpit.png` : le compteur est juste, c'est le jeu de données qui diffère.
- **La ligne `18:42 Formation Admin à planifier`** de la capture est la ligne **en cours de
  saisie** (curseur rouge, aucun repère à 18:42 sur l'axe), pas une note enregistrée. Aucun
  fichier `RefonteDemoSeed+Lot4.swift` n'a donc été ajouté : y semer cette ligne poserait un
  cinquième rond sur l'axe, que la capture ne montre pas.
- **Le composeur en séance n'a pas de cadre pointillé** et suit la dernière note dans le
  flot, là où le mode fenêtré l'ancre en pied d'une colonne courte : la colonne de séance
  occupe toute la hauteur de l'écran, et un composeur collé en bas serait à trente
  centimètres du regard. Le rendu clair du lot 2 est inchangé.
- **`DÉCISION` passe au-dessus du texte** en séance (libellé mono `accent/report`, comme la
  capture) alors qu'il reste inline en 1a. Même raison : la colonne est plus large et la
  ligne respire.
- **Pas de barre de titre** : `titleVisibility` passe à `.hidden` pendant la présentation.
  Une barre de titre est du chrome.

### Fichiers partagés touchés malgré les conventions anti-conflit

`One2OneTheme.swift` (sept champs ajoutés à `One2OneColors`), `One2OneTypography.swift`
(`sectionLabel()` devient un `ViewModifier` pour lire le thème), `Chip.swift`
(`encre(_:)` / `fond(_:)` par thème, les propriétés d'avant conservées),
`Transcript/TranscriptColumn.swift`, `Notes/TimedNotesColumn.swift`, `Notes/NoteComposer.swift`
(lecture du thème), `MeetingChatView.swift` (délégation du prompt). Aucun n'appartient au
périmètre déclaré des lots 5, 6 ou 10 ; tous les changements sont additifs ou neutres en
`.paper`, et `SessionThemeTests` verrouille cette neutralité.

### Prochaine action

Faire relire, puis fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → cette PR`.
Rejouer la recette visuelle du lot 4 une fois le crash `_NSViewUpdateConstraints` corrigé.

## Intégration des lots 2 + 3 : la pile redevient linéaire (2026-09-07)

Les lots 2 et 3 ont été développés **en parallèle** depuis
`feat/refonte-lot-1b-espaces-kpi-assistant` (`a8f8f32`). Le lot 3 a été **rebasé sur le
lot 2** : la pile est de nouveau linéaire — `1b → 2 → 3` — et l'ordre de fusion est
`#19 → #20 → #21 → #22 → #23 → #24`. La branche du lot 3 porte donc ses 11 commits rebasés
plus un commit d'intégration.

**Six fichiers en conflit, six résolutions :**

- `MeetingScreenModel.swift` — les deux lots ajoutaient « en fin de type ». Toutes les
  propriétés des deux sont gardées (`noteFilter`, `noteComposerFocusToken`,
  `lastDiarizationEmbeddings`, `railTab`, `railViewMode`, `newTaskEffortMinutes`), et
  `pendingActionDraft`, déclaré deux fois, n'existe plus qu'une : de type `ActionDraft`
  (lot 3). Le brouillon du lot 2 (`ActionFromPhrase.Draft`, qui portait un *nom* de
  locuteur) **disparaît** au profit d'`ActionDraft`, qui porte un `Collaborator` — le
  composeur doit pouvoir l'affecter, pas seulement l'afficher.
- `MeetingSpaceView.swift` — plus **aucun générique** : le lot 2 avait retiré
  `Notes`/`Transcript`, le lot 3 `Actions`. La vue compose `MeetingLiveSpace` à gauche et
  `ActionsRail` à droite via `MeetingSpaceLayout` ; le placeholder de rail du lot 1 est
  retiré, l'overlay et le dock assistant du lot 1 conservés.
- `MeetingView.swift` — les deux retraits, **aucun ajout** : les ~480 lignes d'UI de
  transcription (lot 2, `runDiarization`/`reidentifySpeakers` restant exposées par
  closures) **et** `actions:` + `addTask` (lot 3). **2 045 lignes**, contre 2 525 pour le
  lot 3 seul.
- `RefonteDemoSeed.swift` — les apports des deux : 4 notes horodatées + `notesMigrated`
  (lot 2), les 12 actions dont 9 non assignées et 3 reportées, et l'année **2026**
  (lot 3). Les chiffres de `1a-cockpit.png` tombent toujours juste : PRÉSENCE 6/6,
  ACTIONS 12 · 9 non assignées, DÉCISIONS 3, RISQUES 5 · 2 critiques.
- `Tests/MeetingScreenModelTests.swift` — union des deux, **un seul** test de
  non-persistance du brouillon (celui du lot 2, qui couvre aussi le filtre de notes).
- `STATUS.md` — les deux sections, lot 3 au-dessus du lot 2, cette section en tête.

**La couture `/action → rail` est branchée.** Le lot 2 posait `pendingActionDraft` sans
que personne ne le consomme et créait l'action par `MeetingView.addTask()`, qui perdait
`sourceRef` ; le lot 3 consommait un brouillon que personne ne posait. Après rebase :

1. `/action <texte>` dans le composeur de notes pose l'intention avec une source de nature
   **`note`** (et non `transcript` : `OwnerSuggestion` ne cherche un locuteur que dans les
   sources `transcript`) horodatée à la tête de lecture. La ligne n'écrit **aucune** note.
2. `＋ Action` sur une phrase de transcription pose l'intention avec la source du segment
   et le locuteur en responsable suggéré. **Il ne crée plus rien** : il créait *et* laissait
   le composeur créer — deux actions pour un clic. `ActionFromPhrase.createAction` est
   supprimée, `ActionComposerService.creer` est le **seul** point de création.
3. `requestAction` préremplit le titre **et** les pilules du responsable
   (`newTaskAudience` + `selectedCollaborator`) : une suggestion qu'on ne voit pas ne se
   refuse pas.
4. `⌘⏎` crée l'`ActionTask` avec `sourceRef` intact, vide le champ sans toucher au focus,
   et l'action paraît en tête d'`À ASSIGNER` (ou du groupe de son responsable).

Nouvelle suite `ActionSeamIntegrationTests` (4 tests, sans aucune vue) : les deux chemins de
bout en bout, la reformulation du titre qui ne coupe pas le lien vers la phrase, et une
lecture des sources amont qui refuse toute autre fabrique d'`ActionTask` ou tout reliquat
d'`addTask`.

**`swift build` propre** (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`). **`swift test` complet vert : 1 039 XCTest
(1 ignoré, 0 échec) + 892 Swift Testing en 130 suites = 1 931 tests**, contre 1 874 pour le
lot 2 seul et 1 855 pour le lot 3 seul (+3 sur l'union attendue : les 4 tests de la nouvelle
suite moins le test de `pendingActionDraft` dédoublonné).

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24`, puis attaquer
le **lot 4** (mode séance plein écran) et le **lot 5** (poste de pilotage).

## Refonte de l'écran de réunion — lot 3 : rail d'actions 330 px permanent (2026-09-07)

Branche `feat/refonte-lot-3-rail-actions`, **rebasée sur**
`feat/refonte-lot-2-notes-transcription` (elle-même sur
`feat/refonte-lot-1b-espaces-kpi-assistant`) : la PR **empile** les lots 0A, 0B, 1a, 1b et 2
(PR #19–#23, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-3-rail-actions.md` (11 tâches).

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

**Le rail est monté une seule fois, par `MeetingSpaceView`** (spec §2.5) : `HStack` sur
`MeetingSpaceLayout.columns(totalWidth:rail:sideNav:)`, colonne fluide à gauche
(indicateurs + contenu du mode + dock assistant), filet, rail de 330 px à droite. Le lot 1
l'avait esquissé dans `MeetingPrepareSpace` — ce placeholder est **retiré**, deux montages
produisant deux rails. **Pas de rail en mode Relire** : la capture
`1c-poste-de-pilotage.png` met les actions en tableau dans sa colonne principale, et c'est
la même `ActionsRailList` qui y sert d'ici au lot 5. En mode Préparer, le rail est
« réduit » (spec §2.2) : le sélecteur de vue disparaît, on ne prépare pas une séance en
matrice d'Eisenhower.

**Trois onglets et trois vues** — `ActionsRail` : `Actions n / Risques n / Historique`,
l'onglet actif sur fond `bg/app` arrondi (le soulignement `accent/report` reste réservé à la
barre d'espaces, deux soulignements sur le même écran ne se hiérarchisent plus) ; sous
`Actions`, `SegmentedMode` sur `ActionsViewMode.railCases` = `Liste · Calendrier ·
Eisenhower`. `ActionsViewMode` a quitté `ActionsPanel.swift` pour `Models/` ; **Kanban et
Post-it restent dans `ActionsListView`** et ne sont pas atteignables depuis le rail (une
valeur mémorisée `kanban` retombe sur `Liste`).

**Groupes ordonnés, purs et testés** — `ActionsRailGrouping` : `À ASSIGNER` (libellé mono
`accent/report`, barre gauche 2 px) → `MES ACTIONS` → `DÉLÉGUÉES` → `REPORTÉES DU <date>`
(rendu en lignes compactes à puce ronde, groupées par date de la réunion d'origine, du plus
récent au plus ancien). Le **report l'emporte** sur « à assigner » : une action n'apparaît
jamais deux fois. Les actions `done`/`dropped` quittent l'onglet Actions pour l'Historique.
Le tri interne passe `sortOrder` **avant** l'échéance — contrairement à l'ancien
`ActionsPanel` — parce que c'est ce qui permet au composeur de mettre une action neuve en
tête sans lui inventer une échéance, et c'est ce qui reproduit l'ordre de la capture.
`dateOrdinale` porte l'ordinal du premier du mois (« 1er sept. »), que `Date.FormatStyle` ne
donne pas en français.

**Cartes à édition inline** — `ActionCard` : titre `plexSans(11.5)` sur 2 lignes, puis les
pilules `InvitePill` — responsable (`＋ assigner`, `＋ Yann` quand une suggestion existe,
vert `accent/ok` quand renseigné, neutre pour un `unresolvedAssigneeName`), échéance,
charge (`30min` / `1h30` / `2h` / `1j`, la journée comptée à 8 h), `!` urgent, et la pilule
de source (`◫ mm:ss` pour une capture, `mm:ss ↗` pour une phrase ou une note → `playhead.seek`).
Un clic **déplie un sélecteur sous le titre**, jamais une modale : `OwnerPickerMenu`
réutilisé, `DatePicker` compact + raccourcis `Demain / Vendredi / +1 sem.`, liste de charges.
`Tab` avance de champ, `Esc` referme. Une invite qui **porte une suggestion assigne en un
clic** ; la pilule devenue verte se reclique pour choisir quelqu'un d'autre.
`ActionCardEditing` (pur) porte toutes ces règles.

**Suggestion de responsable** — `OwnerSuggestion` (pur) applique les trois règles de la spec
dans l'ordre : locuteur du segment source → dernier porteur d'une action de même préfixe de
titre (trois mots normalisés, diacritiques repliés) dans le projet → participant **unique**
n'ayant encore rien à porter. Aucune conclusion rend `nil` : une suggestion fausse coûte plus
cher qu'une absence, puisqu'un seul clic l'accepte.

**Composeur en pied, toujours visible** — `ActionComposer` : champ `Nouvelle action…`,
indice `⌘⏎`, bascules `Moi · Demain · ! · 30min`. La création est un service
(`ActionComposerService.creer`) : c'est ce qui rend vérifiable le « sans perdre le focus »,
un service sans accès au focus ne pouvant pas le prendre. Il consomme
`MeetingScreenModel.pendingActionDraft` (le titre saisi l'emporte sur celui du brouillon,
mais la chaîne de citation survit à la reformulation) et le remet à `nil`. `⌘⏎` est vérifié à
la main (`onKeyPress(keys: [.return])` + `press.modifiers`) plutôt que par un
`keyboardShortcut`, qui serait actif champ non focalisé. Après création, seuls le titre et
l'urgence retombent : un `!` oublié rendrait urgente toute la série suivante. L'insertion
s'anime en **150 ms** (`.animation(.easeOut(duration: 0.15), value: meeting.tasks.count)`).

**Onglets Risques et Historique** — `ActionsRailRisks` : les `ProjectAlert` de la réunion
puis celles du projet non déjà listées, point coloré par sévérité, `＋ Ajouter un risque` qui
déplie un champ **inline** (gravité en pilules, le champ reste ouvert après création : un
risque en amène souvent un second). La lecture de sévérité et la teinte sont celles du
bandeau (`MeetingKPIBuilder.level(fromSeverity:)`, `MeetingKPIBand.teinte(_:)`) — deux
définitions finiraient par peindre le même risque de deux couleurs. `ActionsRailHistory` :
les actions closes, abandonnées et reportées, une ligne datée par entrée.

**`ActionsPanel` est hors de tout chemin actif de l'espace Réunion** (point 8 du périmètre) :
il n'est plus instancié que par `OverviewDashboard`, que le lot 1 ne monte plus (D8) et que
le lot 19 supprimera. `MeetingView` perd sa closure `actions:` **et** sa fonction `addTask`
(−28 lignes ; 2 073 → **2 045** après rebase sur le lot 2, qui en avait déjà retiré 480) ; la
carte RISQUES du bandeau ouvre désormais l'onglet Risques du rail au lieu du rapport.

**`compact: Bool` sur `CalendarBoard` et `EisenhowerBoard`** (décision D10) : ajout dont le
défaut reproduit les métriques d'avant, extraites en fonctions statiques
(`dayCellMinHeight`, `maxChipsPerDay`, `boxMinHeight`) pour être vérifiables — une cellule
rognée sur l'écran Actions plein ne se voit dans aucun test de rendu.

### Créés

`OneToOne/Models/` : `ActionsViewMode.swift`, `ActionDraft.swift`.
`OneToOne/Services/OwnerSuggestion.swift`.
`OneToOne/Views/Meeting/Spaces/Rail/` : `ActionsRailGrouping`, `ActionCard`
(+ `ActionCardEditing`, `ActionCompactRow`), `ActionComposer` (+ `ActionComposerService`),
`ActionsRailList`, `ActionsRailRisks`, `ActionsRailHistory`, `ActionsRail`.

### Tests

`swift build` propre (seul avertissement : celui, préexistant, de `PyannoteDiarizer`).
`swift test` complet **vert** : **1 039 XCTest (1 ignoré, 0 échec) + 816 Swift Testing en
122 suites (0 échec)**, soit **1 855 tests** contre 1 801 après le lot 1 (**+54, +7 suites**),
aucune régression. `EngagementLedgerTests`, `PrepCarryoverServiceTests`,
`MeetingMenuActionsTests` et les suites `ActionsListView` sont vertes.

Nouvelles suites : `ActionsViewModeTests` (4), `ActionsRailGroupingTests` (8),
`OwnerSuggestionTests` (8), `ActionCardEditingTests` (9), `ActionComposerServiceTests` (9),
`ActionsBoardsCompactTests` (5), `ActionsRailNoModalTests` (4). Ajouts : 4 tests dans
`MeetingScreenModelTests`, 3 dans `RefonteDemoSeedTests`.

Critère d'acceptation du chantier 1 **n° 3** (« assigner responsable + échéance sans quitter
le rail ni ouvrir de modale ») : un critère de cette forme ne se vérifie pas par l'état d'un
modèle — une `sheet` ajoutée demain par distraction passerait toutes les autres suites.
`ActionsRailNoModalTests` **lit les sources** du dossier `Rail/` (chemin dérivé de
`#filePath`) et refuse `.sheet(`, `.popover(`, `.alert(`, `.confirmationDialog(`,
`.fullScreenCover(`, toute couleur nommée hors `One2OneToken`, et toute remise à `false` du
`@FocusState` du composeur. Un premier test vérifie que le dossier lu est bien celui du rail,
sans quoi les autres ne prouveraient rien en passant.

### Jeu de démonstration

`RefonteDemoSeed` reproduit maintenant les groupes du rail. L'arithmétique de la maquette
était incohérente (`12 · 9 non assignées` + `À ASSIGNER — 9` + `REPORTÉES — 3` n'admet aucune
solution où une carte assignée figure sous `À ASSIGNER`) : les **trois actions reportées sont
celles qui portent un responsable**, et comme le rendu compact d'un groupe reporté n'affiche
pas de porteur, rien ne le contredit à l'écran — les trois nombres de la capture tombent
juste d'un coup. Échéances, charges (`2h`, `1j`) et chaîne de citation (`04:12 ↗`) complètent
les trois premières cartes. Une réunion « COSUI hebdo » du 1er septembre porte le report et
alimente « DERNIERS POINTS » du mode Préparer, jusque-là vide.

**Défaut du lot 1 corrigé** : le semis datait la réunion du 4 septembre **2025**
(`1 756 970 100`), pas 2026 — la barre d'espaces affichait donc la mauvaise année, le vendredi
de la capture devenait un jeudi, et tout raccourci d'échéance avec lui. Un test fixe désormais
jour, mois et année.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée**, comme au lot 1.
   `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` rend `Yes` ; `screencapture -x` ne
   produit qu'une image noire et `osascript` sur `System Events` est refusé (`-25211`). Rien
   n'a été déposé dans `docs/superpowers/specs/refonte-2026-09/recette/` : une capture noire
   ne prouverait rien. **À refaire écran déverrouillé** : `swift build -c release`, empaqueter
   un `.app` hors du dépôt (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` +
   `default.metallib` repris de `Mickey.app` + signature ad hoc, HOME temporaire), lancer,
   menu **Réunion → Charger le jeu de démonstration (refonte)**, redimensionner à 1 280 puis
   1 920 px, `screencapture -x` vers `recette/lot-3-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis se
   déclenche par un clic de menu.
2. **Un quatrième groupe, `DÉLÉGUÉES`**, s'ajoute aux trois de la spec. Sans lui, une action
   assignée à quelqu'un d'autre et non reportée n'apparaîtrait dans **aucun** groupe : elle
   disparaîtrait du rail sans disparaître de la base, ce qui est la pire des deux options. Le
   discriminant de `MES ACTIONS` étant `destinataire == .moi` (comme le demande le périmètre),
   `À ASSIGNER` doit exclure ce cas, sinon il avalerait toutes mes actions —
   `destinataire == .moi` implique `collaborator == nil` dans le modèle existant.
3. **La capture montre une carte assignée (« Sylvain » en vert) sous `À ASSIGNER`.** C'est
   une incohérence de la maquette, contredite par sa propre carte ACTIONS (`9 non assignées`
   sur 12). Le rail respecte ses règles : une action assignée sort du groupe. La pilule verte
   se voit dès qu'on assigne, elle n'est simplement pas dans l'état semé.
4. **`REPORTÉES DU <date>` n'est pas cliquable vers la réunion d'origine.** La spec ne le
   demande pas et le lot 9 livrera la navigation projet ; la ligne compacte porte le titre et
   le compteur de reports, pas de lien.
5. **Une échéance de la semaine se nomme par son jour** (« Demain », « Vendredi »), la date
   reprenant la main au-delà de six jours **et pour toute échéance passée** (« Mardi » pour un
   mardi révolu serait un piège). C'est ce que montre la capture, mais le libellé est relatif
   à *aujourd'hui* : aucune valeur semée ne peut fixer le mot affiché. Le jeu reproduit la
   forme — une échéance proche et une lointaine côte à côte.
6. **`OwnerPickerMenu` conserve sa feuille « Ajouter un collaborateur… »**, hors du dossier
   `Rail/` et donc hors du périmètre de la garde anti-modale. Assigner un participant ou un
   favori ne passe par aucune modale, ce qu'exige le critère ; *créer* un collaborateur qui
   n'existe pas encore en ouvre une, et c'est une autre intention.
7. **Le composeur ne propose que « Moi » ou « À assigner »**, pas les trois `ActionAudience`.
   Dans 330 px, un menu de trois entrées pour un réglage qu'on change à chaque ligne coûte
   plus qu'il ne rend ; le sélecteur complet est sur la carte.
8. **`newTaskEffortMinutes` s'ajoute au brouillon** à côté de `newTaskPomodoros`, que
   `ActionsPanel` et les vues existantes continuent d'employer. `effortMinutes` est le champ du
   modèle cible (programme §3) ; fusionner les deux aurait touché des écrans hors périmètre.
9. **Le rail n'apparaît pas sous 850 px de largeur** : `MeetingSpaceLayout` retire la colonne
   fixe plutôt que de rogner la fluide sous 520 px (critère n° 5, comportement du lot 1
   inchangé). Le composeur d'action devient alors injoignable dans l'espace Réunion — à
   trancher au lot 19 avec la recette 1 280 px.

### Prochaine action

**Lot 4** — mode séance plein écran (1b) : palette `dark/*`, grille `78 | 1fr | 400`, colonne
temps, bandeau « EN ATTENTE — n actions sans responsable » et sa file d'assignation en trois
clics (elle consomme `ActionsRailGrouping.groupes` et `OwnerSuggestion` livrés ici). Puis
**lot 5** — poste de pilotage = mode Relire : nav latérale de 190 px, tableau d'actions dense
à sept colonnes qui remplacera `ActionsRailList` dans ce mode, frise audio pleine largeur.
## Refonte de l'écran de réunion — lot 2 : notes ↔ transcription, frise audio, action depuis une phrase (2026-09-07)

Branche `feat/refonte-lot-2-notes-transcription`, **empilée** sur
`feat/refonte-lot-1b-espaces-kpi-assistant` (`a8f8f32`) — elle contient donc 0A, 0B, 1a et 1b
(PR #19–#22, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-2-notes-transcription.md` (14 tâches, à la
limite du seuil de coupe fixé par le programme §7 : pas de découpe en 2a/2b).

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

**La carte « Notes & transcription » n'est plus provisoire** (spec §2.4) — `MeetingLiveSpace`
monte lui-même ses composants ; `MeetingView` ne lui injecte plus rien. En-tête du lot 1
inchangé (titre, « synchronisées sur l'audio », `Speakers ON/OFF`, `Résumer`), corps
`1fr 1px 1fr`, **frise audio de 22 px en pied**.

**Colonne MES NOTES** (`Notes/TimedNotesColumn.swift`) — lignes `timecode | texte` depuis
`MeetingNote` (D1), timecode `accent/action` cliquable → `playhead.seek` (chargement paresseux
du WAV), timecode `--:--` quand la réunion n'a aucun axe temps, barre gauche 2 px
`accent/report` (décision) / `accent/warn` (risque), préfixe de nature en gras, édition inline
au double-clic (`EditableTextField`), menu de ligne (nature, visibilité, supprimer) et bandeau
de filtre `kind:décision` avec « tout afficher ». Vider une ligne ne la supprime pas : le menu
le fait.

**Composeur** (`Notes/NoteComposer.swift`) — cadre pointillé, **quatre pilules toujours
visibles** (`/action /décision /risque /citer`) cliquables (elles insèrent la commande et
gardent le clavier), note au **timecode courant** du playhead, `Retour` **et** `⌘⏎` valident
et vident **sans perdre le focus** (champ AppKit `CommandReturnTextField` : `insertNewline`
par le délégué, `⌘⏎` intercepté dans `performKeyEquivalent` avant le menu principal, qui porte
le même raccourci pour « Générer le rapport »), `⌘⇧N` rend le clavier au champ depuis l'écran.
Le texte en cours reste dans `MeetingScreenModel.pendingNoteText` (critère n° 4 du lot 1).

**`NoteCommandParser`** (pur, 13 tests) — `/action /décision /risque /citer /privé /feedback
/promesse /demande /preuve`, insensible à la casse **et aux accents**, commande en début de
ligne seulement, **une commande inconnue n'est pas mangée** (`/décison X` reste du texte).
`/privé` impose la visibilité, `/action` pose l'intention plutôt qu'une note.

**Colonne TRANSCRIPTION** (`Transcript/TranscriptColumn.swift`) — moteur annoncé
(`Cohere MLX` / `Voxtral` / `Qwen3-ASR` selon `AppSettings.transcriptionEngine`), compteur de
segments, **transcription live dans la même colonne** pendant l'enregistrement, segments
`timecode | Locuteur — texte` sur `surface/alt`, survol → fond `accent/action bg` + rangée
`＋ Action` (plein) · `Décision` · `Citer dans la note`, `⌘⇧A` sur le segment survolé (à
défaut le dernier survolé), menu contextuel complet, suppression de passage, **défilement
lié** (`Suivre` / `Reprendre le suivi` ; cliquer un segment le coupe). La transcription sans
segments garde le surlignage du CR manager (`MeetingHighlightableTextView`), seul chemin qui
l'offre sur la transcription.

**`ActionFromPhrase`** (pur + deux fabriques, 13 tests) — nettoyage : hésitations de tête
(`euh`, `donc`, `bah`…), guillemets encadrants, amorce d'obligation → infinitif
(« il faut remettre ça en route » → « Remettre ça en route »), ponctuation finale, majuscule,
coupe au mot à 120 caractères. **Trois garde-fous** : une amorce suivie de `que` n'est pas
retirée (« il faut que le partenaire finalise » reste tel quel), un mot qui n'est pas un
infinitif ne l'est pas non plus (« il faut deux semaines »), et une liste courte de faux amis
(`notre`, `autre`, `ordre`…) évite « Notre accord ». `createAction` conserve
`sourceRef {transcript, stableID, t}`, reprend le locuteur résolu et naît **en tête** du rail
(`sortOrder` minimal − 1) ; `createDecision` produit une `MeetingNote(kind: .decision)` au
timecode du segment, **sans** mise à l'infinitif (une décision se lit comme elle a été
prononcée) ; `quotation` rend `« texte » — Locuteur, mm:ss`.

**Frise audio 22 px** (`Spaces/AudioTimelineStrip.swift`) — onde décimée
(`AudioWaveform` + **`AudioWaveformCache`**, clé fichier × résolution), tête de lecture 2 px
`accent/action`, marqueurs ronds (note), ronds ambre (risque), losanges (décision), carrés
`captureMarker` (capture, dès qu'un `SlideCapture.t` existe), clic **et** glisser
(`DragGesture(minimumDistance: 0)`) → `playhead.seek`. **Sans WAV, la frise reste affichée** :
piste plate, marqueurs et invite « Aucun audio » — c'est l'axe temps de la réunion, pas celui
d'un fichier.

**Services purs du lot** : `TranscriptFollow` (machine à états ; ni la tête de lecture ni les
segments live ne **réactivent** le suivi), `AudioTimelineGeometry` (`t ↔ x` bornés, jamais de
`NaN` dans un `Canvas`, nombre de pics borné), `MeetingTimelineMarkers` (notes + captures
triées ; une capture sans `t` est **ignorée** plutôt que dessinée à `00:00`),
`MeetingNoteStore.timecodeLabel` / `.append` / `.nextOrderIndex`.

**Jeu de démonstration** — `RefonteDemoSeed` sème les **quatre notes horodatées** de la
capture (`04:12`, `07:48`, `11:03` en décision, `15:20`) et pose `notesMigrated` : la reprise
de `liveNotes` n'ajoute pas une cinquième ligne à `t = 0`, alors que le markdown reste rempli
pour l'éditeur historique et les gabarits de rapport.

### Créés

`OneToOne/Services/Meeting/` : `NoteCommandParser`, `ActionFromPhrase`, `TranscriptFollow`,
`AudioTimelineGeometry`, `MeetingTimelineMarkers`. `OneToOne/Services/AudioWaveformCache.swift`.
`OneToOne/Views/Meeting/Spaces/Notes/` : `TimedNotesColumn`, `NoteComposer`.
`OneToOne/Views/Meeting/Spaces/Transcript/` : `TranscriptColumn`, `TranscriptSpeakerTools`.
`OneToOne/Views/Meeting/Spaces/AudioTimelineStrip.swift`.

### `MeetingView.swift`

**2 553 → 2 073 lignes (−480)**, aucun ajout. Sont sortis : `SpeakerMeta`, `isLiveActive`,
`liveTranscriptSection`, `transcriptView`, `transcriptToolbar`, `transcriptSegmentsView`,
`segmentRow`, `playSegmentAudio`, `segmentActionsMenu`, `speakerBadge`, `firstCandidate`,
`acceptSuggestion`, `rejectSuggestion`, `speakerRenamePopover`, `speakerPickerRow`,
`assignSpeaker`, `speakerColor`, et cinq `@State` (`renamingSpeakerID`, `speakerPickerSearch`,
`segmentToDelete`, `segmentDeleteError`, `lastDiarizationEmbeddings`). Y restent
`runDiarization`, `reidentifySpeakers`, `applySpeakerTurns` et `transcriptionPhaseBanner`,
exposées par closures (`onDiarize`, `onReidentify`, `onAddToManagerReport`). Le cache
d'embeddings de diarisation a rejoint `MeetingScreenModel` : il fait le lien entre la
diarisation, restée dans `MeetingView`, et la mise à jour EMA du voiceprint, partie avec le
badge. `MeetingSpaceView` perd ses paramètres génériques `Notes`/`Transcript` et garde
`Actions` (le rail du lot 3 le remplacera). Le KPI Décisions filtre enfin la colonne de notes
(`screen.toggleNoteFilter(.decision)`) au lieu de basculer en mode Relire.

### Tests

`swift build` propre, aucun avertissement nouveau (le seul restant est l'ancien
`PyannoteDiarizer.swift:92`). `swift test` complet **vert** : **1 039 XCTest (1 ignoré,
0 échec) + 835 Swift Testing en 122 suites (0 échec)**, soit **1 874 tests** contre 1 801
après le lot 1 (**+73, +7 suites**), aucune régression.

Nouvelles suites : `NoteCommandParserTests` (13), `ActionFromPhraseTests` (13),
`ActionFromTranscriptCriterionTests` (6), `TranscriptFollowTests` (9),
`AudioTimelineGeometryTests` (8), `MeetingTimelineMarkersTests` (6),
`AudioWaveformCacheTests` (3). Ajouts : 5 tests dans `MeetingScreenModelTests`, 4 dans
`MeetingNoteStoreTests`, 4 dans `RefonteDemoSeedTests`. `MeetingTextualContentTests`,
`NoteFactoryTests`, `PendingEditorTextTests` et `ConfidentialityFilterTests` (lot 0B) restent
verts : les notes privées ne sortent par aucun des cinq flux.

Critères d'acceptation couverts :

- **Chantier 1 n° 2 (une action depuis une phrase)** :
  `ActionFromTranscriptCriterionTests` fait le trajet complet **sans vue** — un seul appel de
  service crée l'action (c'est le clic), `sourceRef` porte `kind = transcript`, le `stableID`
  du segment et son `t`, `MeetingPlayhead.seek` replace la lecture **à ± 1 s** (`04:12`),
  l'action naît en tête du rail, et une source hors de la durée connue (fichier tronqué par
  l'édition audio) ne sort pas de la frise.
- **Défilement lié** : machine à états pure, avec le cas qui compte — `playheadMoved` et
  `segmentsAppended` ne réarment **pas** le suivi.
- **Marqueurs de la frise** : positions calculées depuis `t / duration`, bornées, aller-retour
  stable à 0,01 s ; `duration == 0` rend `0` et non `NaN`.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée** —
   `ioreg -n Root -d1 -r | grep CGSSession` rend `"CGSSessionScreenIsLocked" = Yes`, comme au
   lot 1. Aucune capture n'a été déposée dans
   `docs/superpowers/specs/refonte-2026-09/recette/` : une image noire ne prouverait rien.
   Ce qui a été vérifié : `swift build -c release` réussit.
   **À refaire en une commande, écran déverrouillé** : `swift build -c release`, empaqueter un
   `.app` hors du dépôt (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` +
   `default.metallib` repris de `Mickey.app` + signature ad hoc, **HOME temporaire
   obligatoire** pour ne pas toucher au store de production), lancer, menu **Réunion → Charger
   le jeu de démonstration (refonte)**, redimensionner à 1 280 puis 1 920 px,
   `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-2-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis
   n'est déclenché que par un clic de menu.
2. **Les pilules `/…` sont alignées à droite du composeur**, alors que la capture les montre
   accolées au mot « Tape ». Le champ de saisie doit occuper la largeur restante ; le mettre
   après les pilules le réduirait à rien dès qu'on tape. Les commandes restent **toujours
   visibles**, ce qu'exige la spec.
3. ~~**`/action` dans le composeur de notes ne conserve pas encore `sourceRef` sur l'action
   créée**~~ — **levé à l'intégration des lots 2 + 3** (section en tête) : `/action` pose
   l'intention avec une source de nature `note`, le composeur du rail la consomme et
   `ActionComposerService.creer` conserve `sourceRef`. `＋ Action` sur un segment suit
   désormais le même chemin et ne crée plus l'action directement — il en créait une
   deuxième.
4. **`⌘⇧A` et `⌘⇧N` sont des boutons d'opacité nulle dans les colonnes**, pas des items de
   `MeetingCommands` : le programme §2.4 interdit d'ajouter quoi que ce soit à
   `MeetingView.swift`, et un item de menu y aurait exigé deux closures de plus. Conséquence
   assumée : ils n'agissent que lorsque l'espace Réunion est à l'écran — c'est-à-dire
   exactement là où ils ont un sens. **Non vérifiés à l'exécution** (même cause qu'au n° 1) ;
   `⌘⏎` est le plus exposé, l'item de menu « Générer le rapport » portant le même raccourci —
   d'où l'interception dans `performKeyEquivalent` **et** la validation par `Retour`.
5. **Le risque prend un rond ambre sur la frise**, pas une quatrième forme : la spec ne nomme
   que trois formes (rond, carré, losange) et une quatrième serait illisible à 22 px.
6. **La colonne de transcription affiche les segments même quand `Speakers` est éteint**
   (sans les badges), là où l'ancien écran retombait sur un bloc de texte à plat. Le texte à
   plat reste le rendu des transcriptions **sans** segments, avec son surlignage de CR manager.
7. **Les noms des locuteurs du jeu de démonstration ne sont pas ceux de la capture**
   (`Yann`, `Patrice`, `Sylvain` y désignent des participants nommés autrement dans
   `RefonteDemoSeed`, hérité du lot 1). Écart connu, non traité ici pour ne pas toucher aux
   chiffres que la recette des lots précédents vérifie.

### Prochaine action

**Lot 4** (mode séance plein écran 1b : palette `dark/*`, colonne temps verticale, file
d'assignation) et **lot 5** (poste de pilotage = mode Relire 1c : nav latérale 190 px, tableau
d'actions éditable en place, frise pleine largeur). Le lot 3 (rail d'actions 330 px) tournait
en parallèle ; il est depuis **rebasé sur ce lot** et consomme bien
`MeetingScreenModel.pendingActionDraft` posé ici (cf. la section d'intégration en tête).

## Refonte de l'écran de réunion — lot 1 : barre du haut, trois espaces, modes, bandeau KPI (2026-09-07)

Deux branches **empilées**, parties de l'intégration de 0A + 0B sur `origin/master`
(`a3c44f2`) : `feat/refonte-lot-1a-chrome` (PR #21) puis
`feat/refonte-lot-1b-espaces-kpi-assistant` (PR #22), basée sur la première. Le plan du lot
comptait 15 tâches, au-delà du seuil de 14 fixé par le programme §7 — d'où la coupe, prévue
par le programme lui-même. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-1-espaces.md`.

**État : livré, `swift build` propre, `swift test` complet vert, deux PR ouvertes, non
mergées.** Les PR **incluent 0A et 0B** tant que #19 et #20 ne sont pas fusionnées.

### Ce qui est en place

**Barre du haut sur une ligne de 38 px** (spec §2.1) — `MeetingTopChromeBar` réécrit : fond
`bg/app`, **teinté `accent/oneonone bg` (`#f4f1f6`) pour les deux types 1:1**, bordure basse
`border/card`, padding horizontal 14. Fil d'Ariane dont le segment projet est bordé
`accent/action` et cliquable (il ouvrira la fiche au lot 9 ; il ouvre la feuille Détails d'ici
là), titre `flex:1` en ellipsis éditable, **pilule audio `ink/1` de rayon 16** (`▶ mm:ss /
mm:ss`, marqueur, `✂`, et **saisie directe de timecode** au clic sur le temps —
`TimecodeInput.parse` refuse plutôt que de deviner), état de capture, menu de type portant
le `+` de création, menu de template, bouton `Rapport ✓ (m:ss)` en `accent/report`, `⋯` de
28 px. La **deuxième ligne disparaît** : `MeetingTagEditor` est dans la feuille Détails.

**Barre d'espaces de 34 px** (spec §2.2) — `MeetingSpacesBar` remplace `MeetingTabsUnderline`
(**supprimé**, 93 l.) : `Réunion · Rapport ✓ · Ressources n doc`, soulignement 2 px
`accent/report`, `SegmentedMode` des trois modes, date `4 sept. 2026 · 9:15`.

**Bandeau des quatre indicateurs** (spec §2.3) — `MeetingKPIBuilder` (pur, 11 tests) calcule
présence, actions, décisions et risques ; `MeetingKPIBand` rend quatre cartes 10 × 12 avec
`gap 10`, libellé mono, valeur 20/600 et micro-visualisation (`AvatarStack`, `ProgressBar`,
première décision en ellipsis, points de risque teintés par niveau + `+n`). **Un compteur à
zéro remplace la micro-visualisation par une invite**, jamais une carte vide.

**Trois espaces × trois modes** — `MeetingSpaceRouting` remplace
`MeetingView.visibleSections(for:)` ; `MeetingSpaceView` aiguille sur le mode : En séance =
carte notes ↔ transcription à parts égales (`1fr 1px 1fr`), Relire = résumé + décisions +
actions avec transcription repliée (**D0** : c'est le poste de pilotage 1c), Préparer =
actions reportées + derniers points du projet + alertes + rail réduit de 330 px + composeur
de sujet (`MeetingPrepTab` réutilisé). `OverviewDashboard` et `MeetingChatView` **ne sont
plus instanciés** (D8 ; leur code n'est retiré qu'au lot 19).

**Assistant comme surface** (spec §1.1) — `MeetingAssistantDock` en pied de l'espace Réunion :
`✳` + placeholder de la capture + deux suggestions (la seconde datée de la réunion précédente
du même projet) + `⌘K`. `MeetingAssistantPanel` héberge `MeetingChatView` **telle quelle**.

**La tête de lecture appartient au modèle d'écran** — reprend l'**écart n° 1 du lot 0B** : le
registre statique LRU de `MeetingPlayhead` disparaît, un `MeetingScreenModel` possède la tête
de lecture de sa réunion, `AudioEditorSheet` la reçoit en paramètre.

**`⌘K` et `⌘M`** (spec §1.4) — deux items dans `MeetingMenuActions` / `MeetingCommands`.
`⌘K` est **toujours** actif (c'est une surface, pas un onglet) ; `⌘M` exige un axe temps,
donc jamais sur une note.

**Jeu de démonstration** — `RefonteDemoSeed` sème la réunion de `1a-cockpit.png` (projet
`S/D — Modernisation CI/CD`, 6 participants, 12 actions dont 9 non assignées, 3 décisions dont
une de budget, 5 risques dont 2 critiques, notes et transcription, 23:24), idempotent et
réutilisant un homonyme existant. Commande « Charger le jeu de démonstration (refonte) » dans
le menu **Réunion**.

### Créés

`OneToOne/Views/Meeting/Spaces/` : `MeetingSpacesBar`, `MeetingKPIBand`, `MeetingSpaceView`,
`MeetingLiveSpace`, `MeetingReviewSpace`, `MeetingPrepareSpace`, `MeetingResourcesSpace`,
`MeetingReportSpace`, `MeetingAssistantDock` (+ `MeetingAssistantPanel`), `MeetingEmptyInvite`,
`MeetingSlidesPopover`, `MeetingPrepBadge`.
`OneToOne/Services/Meeting/` : `MeetingKPIBuilder`, `MeetingSpaceLayout`, `MeetingSpaceRouting`,
`MeetingPrepareBuilder`, `MeetingCalendarSync`. `OneToOne/Services/Debug/RefonteDemoSeed.swift`.

### `MeetingView.swift`

**2 948 → 2 553 lignes (−395)**. Sont sortis : `MeetingSection` et `visibleSections(for:)`,
`sectionContent`, `documentsView`, `attachmentRow`, `icon(for:)`, `reportView` +
`decisionsEditor` + `metaHeaderEditor` + `actionsNotice`, `slidesPopover`, le badge de
préparation, l'import et la resynchronisation calendrier, et les deux accesseurs du rapport
manager (`fieldText`, `managerHighlightedRanges`, désormais
`ManagerReportService.sourceText` / `.highlightedRanges`). Les fonctions de transcription et
de locuteurs y restent, comme prévu pour ce lot.

### Tests

`swift build` propre, aucun avertissement nouveau. `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 762 Swift Testing en 115 suites (0 échec)**, soit
**1 801 tests** contre 1 701 après 0A + 0B (**+100, +13 suites**), aucune régression.

Nouvelles suites : `MeetingSpaceLayoutTests` (7), `MeetingSpacesBarTests` (5),
`MeetingTopChromeBarTests` (5), `MeetingEmptyInviteTests` (4), `MeetingKPIBuilderTests` (11),
`MeetingAssistantDockTests` (4), `MeetingPrepareBuilderTests` (5), `RefonteDemoSeedTests` (4).
Ajouts : 5 tests dans `MeetingScreenModelTests`, 2 dans `MeetingMenuActionsTests`, 2 dans
`MeetingPlayheadTests` (les 2 du registre statique remplacés).
`MeetingVisibleSectionsTests` est **adapté** au nouveau routage, pas supprimé.

Critères d'acceptation du chantier 1 :

- **n° 1 (aucune zone vide sans invite)** : `MeetingEmptyInvite.Catalogue` est une table
  **exhaustive** des neuf couples espace × mode ; un espace ou un mode ajouté plus tard fait
  échouer la suite tant qu'il n'a pas son invite. Un test refuse en plus les invites qui se
  contentent de nier (longueur minimale) — c'était le défaut de `ContentUnavailableView`.
- **n° 4 (changement de mode sans perte de saisie)** : `pendingNoteText` rejoint le brouillon
  d'action dans `MeetingScreenModel` ; le test traverse les trois modes **et** les trois
  espaces, et vérifie que rien n'est mémorisé d'une ouverture à l'autre.
- **n° 5 (1 280 px, colonne fluide ≥ 520 px)** : `MeetingSpaceLayout.columns` **retire** une
  colonne fixe (la nav latérale d'abord, le rail ensuite) plutôt que de rogner la fluide — une
  soustraction non bornée produit en SwiftUI une largeur négative, donc un chevauchement
  silencieux. 7 tests, dont l'ajustement exact à 1 040 px.
- n° 2 et n° 3 relèvent des lots 2 et 3, hors périmètre.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée.**
   `ioreg -n Root -d1 -r | grep CGSSession` rend `"CGSSessionScreenIsLocked" = Yes` ;
   `screencapture -x` ne produit qu'une image entièrement noire, et `osascript` sur
   `System Events` est refusé (`-25211`, accès d'assistance non autorisé) — impossible donc de
   redimensionner la fenêtre à 1 280 puis 1 920 px ni de capturer. Aucun fichier n'a été
   déposé dans `docs/superpowers/specs/refonte-2026-09/recette/` : une capture noire ne
   prouverait rien.
   Ce qui a été fait et vérifié : `swift build -c release` **réussit** (226 s) et le binaire
   `.build/release/OneToOne` **démarre**. Lancé nu, il n'ouvre **aucune fenêtre** — un
   exécutable SwiftPM sans bundle `.app` reste un processus accessoire ; c'est exactement ce
   que `Scripts/bump-and-build.sh` répare en empaquetant. Un `.app` de recette a donc été
   empaqueté **hors du dépôt** (scratchpad), sans passer par le script (qui incrémente le
   numéro de build et installe dans `~/Applications`) : binaire + `Info.plist` + `PkgInfo` +
   `OneToOne_OneToOne.bundle` + `default.metallib` repris de `Mickey.app` + signature ad hoc.
   Il démarre, mais l'écran verrouillé empêche toute capture.
   **À refaire en une commande, écran déverrouillé** : `swift build -c release`, puis
   empaqueter comme ci-dessus, lancer le binaire du bundle, menu **Réunion → Charger le jeu de
   démonstration (refonte)**, redimensionner à 1 280 puis 1 920 px, `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-1-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis n'a
   jamais été déclenché (il l'est par un clic de menu).
2. **La pile d'avatars est triée par nom**, et non dans l'ordre de la relation : SwiftData ne
   garantit pas l'ordre d'une relation « à plusieurs », et une pile qui se réordonne d'un
   rendu à l'autre est un défaut visible. La capture ne fixe pas d'ordre significatif ; l'ordre
   rendu est donc `CA CP LD LS NL PY` et non `PY NL CP LS CA LD`. **Écart connu avec la
   capture, à trancher.**
3. **`AvatarStack` reçoit une règle d'initiales optionnelle** (primitive du lot 0A étendue) :
   la capture montre `PY` pour « Pierre-Yves Nallet », là où `Avatar.initiales(de:)` — employé
   par tous les écrans non refondus — donne `PN`. Les deux règles coexistent plutôt que l'une
   n'écrase l'autre ; le défaut du paramètre reste `Avatar.initiales`.
4. **Le bandeau KPI n'est pas affiché en mode Préparer** : la spec §2.2 ne le mentionne que
   pour En séance (« KPI condensés en bandeau ») et, par son contenu, pour Relire. En
   préparation, rien n'a encore été dit.
5. **Un bouton de capture reste dans la barre du haut**, absent du tableau de la spec §2.1 :
   sans lui, la configuration de la capture d'écran deviendrait injoignable. La spec §5.2
   (lot 7) y place précisément une pilule `● Capture · Teams n ⌄` — c'est donc son emplacement
   définitif, en version courte d'ici là.
6. **`SummaryCard.generate` et `.transcriptSource` deviennent statiques** pour que le mode
   Relire emploie **la même** définition du texte de la réunion et le même prompt. Le
   comportement de la carte est inchangé, sans repli sur les notes live.
7. **Le routage minimal des trois espaces est dans la branche 1a**, alors que le programme le
   classe en tâche 4 (donc en 1b) : les sept onglets et les trois espaces ne peuvent pas
   coexister, et 1a livrerait sinon un écran incohérent.
8. **Les cinq chemins d'écran laissés à vérifier de visu par le lot 0A** (composeur d'action
   du rail, bascule « Afficher speakers », dépliage de la barre de lecture, ajout d'un
   participant ad hoc, thèmes proposés) **n'ont pas pu être vérifiés** : même cause qu'au n° 1.
   Le composeur d'action et la bascule des speakers sont désormais tous deux montés par
   l'espace Réunion, donc couverts par la même recette.

### Prochaine action

**Lot 2** — notes ↔ transcription synchronisées sur l'audio : `TimedNotesColumn`,
`NoteComposer` avec les commandes `/` toujours visibles, `TranscriptColumn` et sa rangée
d'actions au survol, `ActionFromPhrase`, `AudioTimelineStrip` (programme §5, lot 2). Il
remplace le contenu provisoire du mode En séance. Puis **lot 3** (rail d'actions 330 px
permanent) et **lot 9** (fiche projet en panneau, déclenchée par le segment projet du fil
d'Ariane livré ici).

## Refonte de l'écran de réunion — lot 0A : socle visuel et état d'écran (2026-09-07)

Branche `feat/refonte-lot-0a-socle-visuel`, partie de `origin/master` (`a3c44f2`). Premier lot
du programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (§5) ; plan
d'exécution dans `docs/superpowers/plans/2026-09-07-refonte-lot-0a-socle-visuel.md`. Lot
**invisible** par construction : rien ne change à l'écran, et aucune vue existante n'utilise
encore les primitives livrées. Le lot 0B tourne en parallèle sur les modèles et les services ;
aucun fichier commun.

### Créés

- **`OneToOne/Views/DesignSystem/One2OneTokens.swift`** : `enum One2OneToken`, copie de
  `Teams-Capture/Sources/CaptureDesign/Tokens.swift` (règle du programme : copier, jamais
  lier), complétée de la **palette `dark/*` complète** du mode séance (`darkBase #1c1a17`,
  `darkTranscript #191714`, `darkCard #221f1b`, `darkCardActive #232019`, `darkPill #2f2b26`,
  `darkInk1…4`, `darkAction #9ab6f0`, **`darkReport #e8b0aa`**, `darkWarn #e8c48a`) et des
  **largeurs fixes** de la spec §1.2 (330 / 320 / 356 / 190 / 52 / 78 / 430 / 396 / 400), plus
  rayons et densités. `Color(hex:)` y est **privé au fichier** : c'est ce qui rend vérifiable
  la règle « seul ce fichier nomme une couleur de la refonte ». `AppTheme`, `MeetingTheme` et
  `FicheTokens` restent en place pour les écrans non refondus.
- **`OneToOne/Views/DesignSystem/ContrastRatio.swift`** : luminance relative et ratio WCAG 2.1
  (fonctions pures, `NSColor.usingColorSpace(.sRGB)`, aucune session graphique). Rend `nil`
  sur une couleur inconvertible plutôt qu'un contraste imaginaire.
- **`OneToOne/Views/DesignSystem/One2OneTypography.swift`** : `PlexWeight`, `PlexFont`,
  `Font.plexSans/plexMono`, `View.sectionLabel()`. Copie de `Typography.swift` de
  Teams-Capture — **noms PostScript abrégés** `IBMPlexSans-Medm` / `-SmBld`, jamais
  `-Medium` / `-SemiBold`, jamais `.weight()` par-dessus — augmentée de l'enregistrement des
  fontes embarquées par `CTFontManagerRegisterFontsForURL` en portée `.process`
  (`static let` = une fois par process), déclenché à la fois par `PlexFont.isInstalled` et
  explicitement au lancement. Localisation calquée sur `MermaidResourceLocator` :
  `Bundle.module`, puis `Contents/Resources/OneToOne_OneToOne.bundle` du `.app` packagé.
  Repli `Font.system` conservé.
- **`OneToOne/Resources/Fonts/`** : IBM Plex Sans 400/500/600 et Plex Mono 500/600 en `.ttf`
  (v3.005, téléchargés du dépôt officiel `IBM/plex`, ~950 Ko au total) + `OFL.txt` (texte de
  la SIL Open Font License 1.1 copié à côté des fichiers). Vérifié : les cinq fichiers
  portent bien les noms PostScript **abrégés** — c'est la condition de tout le reste, une
  version ≥ 6 de Plex utiliserait les noms longs et casserait la résolution en silence.
  `.process("Resources")` aplatit `Fonts/` à la racine du bundle (constaté dans
  `.build/debug/OneToOne_OneToOne.bundle`), d'où la double recherche.
- **`OneToOne/Views/DesignSystem/One2OneTheme.swift`** : `One2OneTheme` (`.paper` / `.session`),
  `One2OneColors` (couleurs résolues : fond, canevas, carte, carte active, pilule, quatre
  encres, quatre accents, deux filets), clé et accesseur `EnvironmentValues.one2OneTheme`
  (défaut `.paper`) et modificateur `View.one2OneTheme(_:)`. Le mode séance est un thème
  **local** : le `.preferredColorScheme(.light)` épinglé sur les trois `WindowGroup` de
  `OneToOneApp` n'est pas touché.
- **`OneToOne/Views/DesignSystem/Components/Refonte/`** : les dix primitives, un `#Preview`
  chacune (papier et séance quand la primitive suit le thème) — `SectionLabel`, `MonoMeta`,
  `TimecodeLabel` (+ `format(_:)` pure), `Chip` (+ `ChipTon`), `Pill`, `InvitePill`
  (+ `Etat`), `RefonteCard`, `AvatarStack` (+ `layout(noms:maxVisibles:)` pure), `ProgressBar`
  (+ `clamp(_:)` pure), `SegmentedMode` (générique).
- **`OneToOne/Views/Meeting/MeetingScreenModel.swift`** : `@Observable` `@MainActor`. `space`
  (`meeting`/`report`/`resources`) et `mode` (`prepare`/`live`/`review`) **mémorisés par
  réunion** dans `UserDefaults` (clés `onetoone.meetingScreen.{space,mode}.<stableID>`,
  `UserDefaults` injectable) ; brouillon d'action, `showSpeakers`, `showPlayback`, `follow`,
  `newAdhocName`, `suggestedTagNames` non persistés. `attach(meetingID:)` idempotent (relire
  sur un second `.onAppear` écraserait le choix que l'utilisateur vient de faire) ; aucune
  écriture avant rattachement.

### Modifiés

- **`OneToOne/Views/MeetingView.swift`** : treize `@State` retirés au profit de
  `@State private var screen = MeetingScreenModel()`, rattaché en tête de `.onAppear`.
  `addTask()` appelle `screen.resetActionDraft()` (six remises à zéro en une).
  `activeSection` **reste** un `@State` (les espaces arrivent au lot 1). Les chemins
  `adoptPendingLiveNotes()` / `discardEmptyNoteIfNeeded()` ne sont pas touchés.
- **`OverviewDashboard.swift`**, **`ActionsPanel.swift`** : les huit `@Binding` du brouillon
  d'action, qui traversaient `OverviewDashboard` sans qu'elle en lise un seul, deviennent un
  `MeetingScreenModel` en paramètre.
- **`MeetingTopChromeBar.swift`** (`suggestedTagNames`), **`ManageParticipantsSheet.swift`**
  (`newAdhocName`) : mêmes remplacements pour leur unique `@Binding` traversant.
  `@Observable` n'ayant pas de projection `$`, les six endroits qui exigent un vrai `Binding`
  (`EditableTextField`, `Toggle`, `TextField`, `iconToggle`, `MeetingTagEditor`) en
  construisent un à la main.
- **`OneToOne/OneToOneApp.swift`** : `PlexFont.ensureRegistered()` en première ligne de
  `init()`. Un enregistrement tardif ferait clignoter la typographie.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet **vert** :
**1 037 XCTest (1 ignoré, 0 échec) + 663 Swift Testing en 100 suites (0 échec)**, soit
1 700 tests contre 1 655 avant le lot (+45, +5 suites) et **aucune régression**. Les suites
que le programme §8 désigne comme garde-fous de `MeetingView` (`NoteFactoryTests`,
`PendingEditorTextTests`, `MeetingScreenRegistryTests`) sont vertes.

- `Tests/One2OneTokensTests.swift` (8 tests) : calibrage de la mesure (noir sur blanc = 21:1),
  **25 paires texte/fond** employées sous 12 px vérifiées à ≥ 4,5:1 (13 en palette claire,
  12 en palette séance), largeurs fixes et rayons de la spec §1.2.
- `Tests/One2OneTypographyTests.swift` (6 tests) : les cinq fichiers présents dans le bundle,
  les cinq noms PostScript qui résolvent après enregistrement, le piège des noms longs
  (`IBMPlexSans-SemiBold` et `-Medium` ne résolvent **pas**), la disposition du `.app`
  packagé, le repli sur un nom inconnu.
- `Tests/One2OneThemeTests.swift` (5 tests) : défaut d'environnement `.paper`, résolution des
  deux palettes sur leurs jetons, contraste du libellé mono ≥ 4,5:1 dans les deux thèmes,
  stabilité des `rawValue`.
- `Tests/One2OnePrimitivesTests.swift` (15 tests) : `mm:ss` toujours (62:03 au-delà d'une
  heure), tronqué et non arrondi, `00:00` sur négatif / `nan` / `infinity` ; états de
  `InvitePill` et tons de `Chip` lisibles sur leur propre fond ; `AvatarStack` — six exactement
  n'affiche pas « +0 », neuf affiche six + « +3 », pile vide muette, géométrie 19 / −6 ;
  `ProgressBar.clamp` bornée, `nan` → 0.
- `Tests/MeetingScreenModelTests.swift` (11 tests) : défauts `meeting`/`live`, mémorisation
  par réunion, cloisonnement entre deux réunions, repli sur valeur mémorisée illisible,
  idempotence d'`attach`, **changer de mode ne touche pas au brouillon** (critère du lot 1,
  figé avant la vue), brouillon non persisté, `resetActionDraft` qui garde le destinataire,
  défauts des bascules identiques aux `@State` retirés, rien d'écrit avant rattachement.

### Écarts assumés

1. **Constat sur la table §1.2 : `ok/deep` (`#2f7d4e`) sur `ok/bg` (`#e8f3ec`) mesure
   4,43:1**, soit 0,07 sous le seuil de 4,5:1 que la spec impose sous 12 px. `accent/ok` ne
   publie que deux encres et celle-ci est la plus profonde : il n'y a pas de couple conforme
   dans la table. Le jeton n'a **pas** été retouché (la table fait foi) ; la mesure est figée
   par un test dédié (`okDeepOnOkBackgroundIsJustBelowThreshold`) pour que l'écart soit connu
   et qu'un futur assombrissement soit une décision explicite. `InvitePill.Etat.renseignee` et
   `ChipTon.ok` emploient ce couple, conformément à la capture 1a (pilule « Sylvain » verte),
   et leurs tests attendent 4,4 en renvoyant à ce constat. **À trancher avec la spec.**
2. L'énumération s'appelle **`One2OneToken`** et non `Token` comme dans Teams-Capture :
   `Token` est trop générique dans un module unique de cette taille, et le nom suit celui du
   fichier imposé par le programme (`One2OneTokens.swift`).
3. **`newAdhocName` et `suggestedTagNames` ont rejoint le modèle** en plus de la liste du
   programme : ce sont les seuls `@Binding` traversants de `ManageParticipantsSheet` et
   `MeetingTopChromeBar`, les deux vues que le lot devait justement libérer. De même,
   `showNewTaskDueDate` et `didApplyActionDefaults` (ex-`didSetActionDefaults`) ont suivi le
   reste du brouillon d'action, dont ils sont indissociables.
4. **`AvatarStack`** et **`RefonteCard`** : noms retenus pour ne pas heurter
   `MeetingAvatarStack` ni les cartes de dashboard existantes, que ce lot ne remplace pas.
5. **`One2OneTheme.session.ok` retombe sur `dark/accent action`** : la palette `dark/*` de la
   spec §1.2 ne publie pas d'encre « tenu », le vert de la palette claire n'est pas lisible sur
   `#1c1a17`, et la capture 1b utilise déjà le bleu clair comme teinte positive (bouton
   `＋ Action`). Les deux filets du thème séance sont des opacités de blanc, nommées dans le
   système de conception et non dans une vue.
6. **Recette à l'écran non faite.** `Scripts/bump-and-build.sh dev` incrémente le numéro de
   build, installe dans `~/Applications` et lance l'app : le faire depuis un worktree
   remplacerait la copie de développement par un build de branche et polluerait la branche
   d'un changement de version. Le lot étant invisible et le vrai risque étant « les fontes ne
   voyagent pas dans le `.app` », ce risque est couvert par un test qui monte la disposition
   réelle du bundle packagé (`Contents/Resources/OneToOne_OneToOne.bundle`, ligne 93 du
   script) dans un dossier temporaire. **Reste à vérifier de visu au lot 1** : le composeur
   d'action du rail, la bascule « Afficher speakers », le dépliage de la barre de lecture,
   l'ajout d'un participant ad hoc et l'affichage des thèmes proposés — les cinq chemins que
   la migration a touchés.
7. Le test « les cinq noms PostScript résolvent » ne distingue pas, sur ce poste, une
   résolution par le bundle d'une résolution par les Plex `.otf` déjà installés dans
   `~/Library/Fonts`. C'est `bundledFontFilesArePresent` + `packagedLayoutIsFound` qui
   couvrent le bundle.

### Prochaine action

**Lot 1** — chantier 1 socle : barre du haut une ligne 38 px, trois espaces, sélecteur de
mode, bandeau 4 KPI (programme §5, écran `1a-cockpit.png` partie haute). Il consomme
`One2OneToken`, les primitives et `MeetingScreenModel.space/mode` de ce lot, et le schéma V3
du lot 0B. C'est lui qui câble les primitives : à sa fin, la recette à l'écran devient
comparable à la capture de référence.
## Refonte de l'écran de réunion — lot 0B : schéma V3, tête de lecture, confidentialité (2026-09-07)

Branche `feat/refonte-lot-0b-socle-donnees`, sur `master` (`a3c44f2`). Premier lot de données du
programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (§5 « Lot 0B ») ;
plan du lot dans `docs/superpowers/plans/2026-09-07-refonte-lot-0b-socle-donnees.md`. Le lot 0A
tourne en parallèle sur le socle visuel — `MeetingView.swift` n'est touché ici qu'en trois
endroits (le lecteur audio, `recordingStartedAt`, l'appel d'import des notes).

**État : livré, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

- **`Models/SchemaVersions.swift`** : `SchemaV3` (3.0.0), `CurrentSchema` pointe dessus,
  `schemas` à trois versions. `stages` reste **vide** : V2→V3 n'ajoute que des tables et des
  colonnes à valeur par défaut, donc lightweight migration automatique — même convention que
  V1→V2, raisonnement documenté dans le plan de migration.
- **Neuf `@Model` nouveaux** (tables vides, coût nul) : `MeetingNote` (D1 — notes horodatées
  adressables : `t`, `text`, `kindRaw` parmi note/décision/risque/feedback/promesse/demande/preuve,
  `visibilityRaw`, `authorSideRaw`, `sourceRef`, `orderIndex`), `Board` (D5/D6 — scène et vignette
  **sur disque**, la base ne garde que les chemins), `ProjectMilestone` et `ProjectContact`
  (fiche projet ; les risques restent les `ProjectAlert` existants), et le domaine 1:1 (D3) :
  `OneOnOneThread` + `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`, `OneOnOneObjective` en
  cascade depuis le fil. Tous avec `stableID: UUID?` + `ensuredStableID`, énums en `…Raw`.
- **Colonnes ajoutées** : `ActionTask` (`priorityRaw`/`statusRaw` en **miroirs requêtables** de
  `isUrgent`/`isCompleted` qui restent la source de vérité, `dropped` n'existant que dans la
  colonne ; `effortMinutes`, trois colonnes de source, `deferralCount`, `carriedFromMeeting`),
  `MeetingAttachment` (`scopeRaw`, `mimeType`, `byteCount`, `addedByName`, `pinnedAtT`,
  `citationCount`), `SlideCapture` (`t` sur l'axe **audio**, `sourceRaw`, `triggerRaw`),
  `Project` (`scopeText`, `tagsJSON` + façade `tags`, relations `milestones`/`contacts`),
  `Meeting` (`recordingStartedAt`, `notesMigrated`, relations `timedNotes`/`boards`).
- **`MeetingKind.workshop`** (« Atelier »), mappé vers le gabarit `.workshop` dans
  `compatibleTemplates` et `AIReportService.defaultTemplate`. Les six valeurs brutes historiques
  sont inchangées (test de garde).
- **`Models/SourceRef.swift`** : `SourceRef {kind, stableID, t}` + protocole `SourceRefCarrying`
  portant l'accesseur `sourceRef` au-dessus de trois colonnes plates (requêtables par
  `#Predicate`, contrairement à un JSON), adopté par `ActionTask` et `MeetingNote`.
- **`Services/Live/MeetingPlayhead.swift`** : `@Observable @MainActor`, une instance par réunion,
  propriétaire de l'**unique** `AudioPlayerService` (il était instancié deux fois, sans position
  commune). `t` depuis `recordingStartedAt` en séance (horloge injectable) ou depuis le lecteur en
  relecture, `duration`, `isPlaying`, `follow`, `markers` triés, `seek` borné,
  `marker(at:tolerance:)`, `mmss`. `MeetingView` et `AudioWaveformEditor`
  (via `AudioEditorSheet`) le consomment ; comportement visible inchangé.
- **`Services/ConfidentialityFilter.swift`** : `Audience`, `Visibility`, protocole `Confidential`
  (adopté par `MeetingNote`, `Commitment`, `OneOnOneAgendaItem`), `isExportable(_:for:)` en table
  exhaustive sans `default`, `isIndexable` et `audience(for kind:)`.
- **`Services/MeetingNoteStore.swift`** : fonctions pures (`sorted`, `filtered`, `grouped`,
  `exportable`, `indexable`, `markdown`, `contextBlock`, `defaultVisibility`) et
  `importLiveNotesIfNeeded` — reprise unique de `liveNotes` en une note `t = 0` (drapeau
  `notesMigrated`, `liveNotes` **conservé**), branchée au `onAppear` de `MeetingView`.
- **Les cinq lecteurs de texte filtrés** : prompt de rapport
  (`AIReportService.assembleTemplatePrompt`, couture extraite pour être vérifiable sans réseau),
  HTML (`ReportHTMLBuilder`, bloc « Notes de séance »), export markdown (`ExportService`),
  index RAG (`RAGIndexer.sourceText`, couture pure sans embedding — filtrage **à l'écriture** de
  l'index), contexte des deux chats (`MeetingChatView.makePrompt`,
  `ChatbotView.meetingNotesContext`). `Meeting.textualContent` déclare les notes horodatées et
  `NoteFactory.isDiscardableEmptyNote` les retient.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 037 XCTest (1 ignoré, 0 échec) + 664 Swift Testing dans 102 suites, 0 échec** — soit
+46 tests et +7 suites par rapport à la référence du 2026-09-06 (618 / 95). Nouvelles suites :
`SchemaV3MigrationTests` (6), `MeetingPlayheadTests` (9), `MeetingNoteStoreTests` (12),
`ConfidentialityFilterTests` (6) + `SourceRefTests` (3) + `NotePriveeHorsDesCinqFluxTests` (8),
`MeetingKindWorkshopTests` (2).

**Migration vérifiée sur une copie du store de production** (32 Mo, hors suite de tests, script
temporaire supprimé) : ouverture avec `CurrentSchema` + `OneToOneMigrationPlan` sans erreur, les
neuf tables `ZMEETINGNOTE`/`ZBOARD`/`ZCOMMITMENT`/`ZONEONONE*`/`ZMOODENTRY`/`ZPROJECTMILESTONE`/
`ZPROJECTCONTACT` créées, comptages **identiques** avant/après (189 réunions, 420 actions,
63 projets, 34 pièces jointes, 372 collaborateurs, 3 793 chunks) et tous les nouveaux champs à
leur défaut.

### Écarts assumés

1. **Registre du playhead à références fortes, borné LRU à 4** au lieu du cache faible prévu au
   plan : un cache faible se viderait aussitôt, `MeetingView` étant une `struct` qui ne peut
   retenir l'instance sans initialiseur explicite — et ce fichier est réécrit en parallèle par le
   lot 0A. L'éviction met le lecteur en pause. À revoir au lot 1, quand `MeetingScreenModel`
   pourra porter la tête de lecture.
2. **Test de migration sans snapshot *nested* de V2** : les types Swift sont partagés entre
   `SchemaV1/V2/V3` (aucun snapshot nested n'a jamais été écrit dans ce dépôt, cf. l'en-tête de
   `SchemaVersions.swift`), donc écrire le store avec `SchemaV2` crée déjà les colonnes de V3. La
   suite vérifie ce qui reste vérifiable (réouverture sans perte, défauts sur des lignes créées
   avant les champs) ; la preuve réelle est la vérification sur la copie du store de production
   ci-dessus.
3. **`BackupService` n'exporte pas les neuf nouvelles tables** : ses DTO sont manuels et le lot
   aurait dérivé. Sans conséquence aujourd'hui (tables vides) ; à traiter au lot où elles se
   remplissent (lot 9 pour la fiche projet, lot 10 pour le 1:1, lot 16 pour les planches), en
   même temps que `StorageStatsService`/`OrphanCleanupService` pour les dossiers `boards/`.
4. **Aucune vue ne lit encore les nouvelles données** : c'est le propos du lot (socle). Rien n'est
   donc visible à l'écran, aucune recette visuelle n'a été faite.
5. `MoodEntry` et `OneOnOneObjective` bornent leur valeur à la construction **et** exposent
   `clampedValue`/`clampedProgress` : la colonne brute reste lisible pour une restauration.

### Prochaine action

**Lot 1** — chantier 1 socle : barre du haut sur une ligne, trois espaces, sélecteur de mode,
bandeau KPI (`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5, lot 1). Il
dépend des lots 0A et 0B, tous deux livrés. Fusionner d'abord les deux PR de socle.

## Chatbot — persistance de l'historique des conversations (2026-09-06)

Branche `feat/chatbot-history-persistence`, sur `master` (+0 commit avant cette session).
`ChatbotView` stockait ses messages dans un simple `@State [ChatMessage]` — perdu à chaque
fermeture de l'app, message de bienvenue réinitialisé. `MeetingChatView` reste **volontairement**
éphémère (décision de design antérieure), cette PR ne touche que `ChatbotView`.

- **`OneToOne/Models/ChatSession.swift`** (nouveau) : `@Model ChatSession` (id, createdAt,
  updatedAt, title dérivé du 1er message user tronqué à 60 car., relation cascade vers ses
  messages) et `@Model ChatMessageEntity` (id, role brut `"user"`/`"assistant"`, content,
  orderIndex, createdAt, session). `ChatMessage.Role` n'étant pas `String`-backed (hors
  périmètre — pas de modification de `ChatMessage.swift`), la conversion se fait à la main
  plutôt que via `.rawValue`. Mapper `ChatMessageEntity.from(_:orderIndex:)` /
  `.asChatMessage`.
- **`OneToOne/Models/SchemaVersions.swift`** : `SchemaV2` ajouté (modèles V1 + les deux
  nouveaux types), `CurrentSchema` pointe dessus. Ajout de table pur, pas de
  `MigrationStage` custom — lightweight migration automatique.
- **`OneToOne/Services/ChatSessionStore.swift`** (nouveau) : règle de rétention isolée de
  la vue pour rester testable — `sessionsToPrune(from:limit:)` (pure) + `enforceLimit(...)`
  (supprime + save + log). Limite 100 sessions, les plus anciennes par `updatedAt` sautent.
- **`ChatbotView`** : `@State messages: [ChatMessage]` devient une copie RAM rechargée à
  chaque changement de session (`loadSession`), plus une source de vérité. Nouveaux
  `@Query sessions`, `@State currentSession`/`sidebarSelection`/`hasInitializedSessions`
  (garde contre la recréation en boucle d'une session de bienvenue à chaque re-render) et
  `showSidebar`. `sendMessage()` route chaque `messages.append` via `appendMessage(_:to:)`
  qui persiste (insert `ChatMessageEntity` + `session.updatedAt` + titre au 1er message user
  + save). Sidebar ajoutée dans la vue (colonne 200px, collapsible via bouton
  `sidebar.left` dans l'en-tête) : liste triée par `updatedAt` desc, titre ou "Nouvelle
  conversation", date relative (`RelativeDateTimeFormatter` fr_FR), aperçu du dernier
  message, sélection surlignée (`Color.accentColor`), bouton `+`
  (`square.and.pencil` → `newConversation()`) et suppression par ligne (`trash` +
  `confirmationDialog`). `MeetingChatView` : **aucune modification**.
- **Écart avec la commande initiale** : la tâche demandait `func search()` — comme déjà
  noté en B-x-ui, la fonction réelle s'appelle `sendMessage()` ; c'est elle qui a été
  modifiée.
- **Non fait / limites v1** : pas de debounce sur les saves successifs (append+save reste
  peu fréquent : au plus 2 saves par échange, pas de boucle rapide observée) ; backup/
  restore avec sessions orphelines non testé spécifiquement (relation `session` sur
  `ChatMessageEntity` est `nullify` par défaut côté cascade parent→enfants, comportement
  accepté pour une v1 selon la consigne) ; pas de toggle "Historique" exposé dans
  `SettingsView` (les sessions sont toujours actives, comme demandé).
- **Tests** : `Tests/ChatSessionTests.swift` (nouveau, 4 tests) — roundtrip 3 messages via
  un nouveau `ModelContext`, cascade delete, mapper `ChatMessage`↔`ChatMessageEntity`,
  limite 100 sessions (105 créées → 5 plus anciennes supprimées).
- **Vérifié** : `swift build` propre (mêmes avertissements préexistants) ; `swift test`
  complet — **1 037 XCTest (1 ignoré, 0 échec) + 618 Swift Testing (95 suites, 0 échec)**,
  dont les 4 nouveaux tests `ChatSessionTests`. Un crash isolé (signal 11) est apparu sur
  une exécution parallèle de `swift test` sur un test `NoteFactoryTests` sans rapport avec
  cette PR ; non reproduit sur une exécution suivante (flaky, à surveiller si ça persiste).
- **Non vérifié à l'écran** : rendu réel de la sidebar dans l'app (ni
  `Scripts/bump-and-build.sh` ni capture d'écran effectués cette session).

## Chats — polish UX : tableaux markdown + indicateur de phase (B-x-ui) (2026-09-06)

Branche `feat/rag-chat-polish-ui`, sur `master` (+0 commit avant cette session). Les chats
(`ChatbotView`, `MeetingChatView`, branchés par B1/B2/B2-ui) affichaient déjà les réponses
via `MarkdownText` (headings, listes, code, quotes), mais sans support des tableaux GFM que
le LLM produit souvent ; et `isLoading: Bool` ne distinguait pas construction du prompt et
appel réseau, alors que ce dernier peut prendre plusieurs minutes sur Ollama sans aucun retour.

- **`OneToOne/Views/MarkdownText.swift`** : nouveau cas `Block.table(headers:rows:alignments:)`.
  Détection dans `blocks()` : ligne contenant `|` suivie d'une ligne de séparateurs valide
  (`isTableSeparatorLine`, avec ou sans pipes de bordure, `:` optionnels aux extrémités pour
  l'alignement) ; les lignes suivantes contenant `|` sont consommées comme rows jusqu'à la
  première ligne vide ou sans `|`. Rendu (`tableView`) : `ScrollView(.horizontal)`, header
  teinté `Color.accentColor.opacity(0.08)` en gras, séparateurs 1px `Color.gray.opacity(0.15)`
  entre les rows, zebra striping toutes les 2 rows (`opacity(0.04)`), alignement par colonne
  (`.frame(alignment:)` + `.multilineTextAlignment`), inline (`**`, `` ` ``, liens) délégué à
  `inlineText(_:)` existant. Backward-compatible : un texte avec des `|` mais sans ligne de
  séparateurs reste un paragraphe (testé). Deux accesseurs `ForTesting` (pattern déjà utilisé
  dans le repo, ex. `SlashDatePickerPresenter`) exposent le résultat du parsing sans dépendre
  du rendu SwiftUI : `blockKindsForTesting()` et `parsedTablesForTesting()`.
- **`OneToOne/Models/LoadingPhase.swift`** (nouveau) : enum partagé `idle`/`loadingContext`/
  `waitingLLM` (libellé + icône SF Symbols par cas). Le pré-fetch RAG n'est volontairement
  **pas** une phase séparée (trop rapide en usage normal pour justifier un indicateur dédié,
  cf. consigne de la tâche).
- **`ChatbotView`/`MeetingChatView`** : `@State private var isLoading: Bool` remplacé par
  `@State private var phase: LoadingPhase`, `isLoading` redevenu une propriété calculée
  (`phase != .idle`) pour ne pas toucher la logique existante des boutons/spinner. Une bulle
  inline (icône + libellé + `ProgressView` sobre, pas d'animation agressive) s'affiche dans la
  liste de messages pendant `loadingContext` (construction du prompt : contexte base, pré-fetch
  RAG, historique) puis `waitingLLM` (juste avant `AIClient.send`/`sendWithToolLoop`), avec
  auto-scroll vers cette bulle. `ChatbotView.statusBadge` affiche désormais le libellé de phase
  au lieu de "Analyse...". Les deux vues utilisaient déjà `MarkdownText` pour les bulles
  assistant (branché par B2-ui) — le support tableau en profite automatiquement, aucun
  changement supplémentaire nécessaire sur ce point.
- **Écart avec la commande initiale** : la tâche nommait la fonction d'envoi `search()` —
  inexistante dans les deux vues ; la méthode réelle est `sendMessage()`, modifiée à cet
  emplacement (même écart déjà noté pour B2-ui/`handleFreeQuestion`).
- **Tests** : `Tests/MarkdownTextTableTests.swift` (6 tests) — tableau 3 colonnes avec headers
  et 2 rows, alignements `:---`/`:---:`/`---:`, défaut sans `:`, paragraphes adjacents avant/
  après un tableau (ordre des blocs vérifié), faux positif (pipes sans ligne de séparateurs →
  reste un paragraphe), tableau sans pipes de bordure.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de concurrence dans
  `PyannoteDiarizer.swift`) ; `swift test` complet — **1 037 XCTest (1 ignoré, 0 échec) + 614
  Swift Testing (94 suites, 0 échec)**, dont les 6 nouveaux tests de tableaux.
- **Non vérifié à l'écran** : rendu réel des tableaux et de l'indicateur de phase dans l'app
  (ni `Scripts/bump-and-build.sh` ni capture d'écran effectués cette session).
- **Limites connues (hors périmètre volontaire)** : pas de streaming de la réponse (la
  structure `phase = .waitingLLM` s'y prête mais ce n'est pas implémenté ici) ; cellules avec
  pipes échappés non gérées (rare, écarté explicitement par la consigne) ; `RAGChatView` non
  touchée (rendu tableau/phase réservé aux 2 chats visés).
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran (poser une question dont la réponse contient un
tableau GFM, observer l'indicateur de phase pendant un appel Ollama long), puis revue/PR de
cette livraison.

## RAG — batch d'indexation globale au démarrage (D) (2026-09-05)

Branche `feat/rag-batch-reindex-d`, sur `master` (+0 commit avant cette
session). Jusqu'ici rien ne rattrapait les chunks jamais indexés ou devenus
obsolètes (changement de modèle d'embedding, bug d'indexation passé, restore
de backup). Cf. ADR `docs/adr/2026-09-05-rag-pipeline-inventaire.md`
(section D).

- **`Services/RAGIndexingSweep.swift`** (nouveau) : `RAGIndexingSweep.shared
  .runIfNeeded(context:)` fetch tous les `TranscriptChunk`, retient ceux dont
  `embeddingData` est vide, `embeddingModel` diffère du modèle courant
  (`RAGService.embeddingModel`), ou dont le modèle d'embedding a changé
  globalement depuis le dernier sweep complet (`UserDefaults
  .lastIndexedEmbeddingModel`, qui force alors même les chunks au modèle déjà
  à jour — vecteurs sinon incompatibles). Les chunks à traiter sont regroupés
  par parent (relation `attachment` / `mail` / `meeting`, testées dans cet
  ordre car un chunk d'attachment porte aussi un `meeting`) : un seul
  reindex par parent distinct, pas un par chunk.
  - Meeting/note → `RAGIndexer.reindex`/`reindexNote` (kind == .note).
  - Attachment → `MeetingAttachmentService.reindexAttachment` (réutilisé tel
    quel — pas dans le libellé de la tâche mais c'est la seule fonction
    existante qui régénère les chunks d'un attachment ; `RAGIndexer.reindex`
    ne les touche pas).
  - Mail → `ProjectMailStore.reindex(mail:)` (idem).
  - Chunk orphelin (aucune relation) : ignoré, loggé.
  - Pas de persistance de « qui a été traité » : idempotent par construction,
    un re-run sans changement ne relance rien (vérifié par test).
  - Handlers (`reindexMeetingHandler`/`reindexAttachmentHandler`
    /`reindexMailHandler`) et `userDefaults` sont des `static var`
    injectables — même pattern que `NoteIndexingCoordinator.reindexHandler`,
    pour tester sans MLX (`swift test` n'embarque pas `default.metallib`).
- **`Services/RAGService.swift`** : ajout de `enum RAGService { static var
  embeddingModel }`, wrapper de `EmbeddingService.model`.
- **`OneToOneApp.swift`** : `ContentView.onAppear` appelle
  `runRAGIndexingSweep()`, qui lance `Task { await RAGIndexingSweep.shared
  .runIfNeeded(context:) }` — non bloquant, la vue s'affiche immédiatement.
- **Tests** : `Tests/RAGIndexingSweepTests.swift` (5 tests) — chunk à jour
  → no-op ; chunk sans embedding → reindex ; chunk au mauvais modèle →
  reindex ; 3 chunks du même meeting → un seul appel ; deuxième passage sans
  changement → pas de second appel (idempotence).
- **Vérifié** : `swift build` propre ; `swift test` complet (608 tests), 0
  échec.
- **Limites connues (documentées, hors périmètre volontaire)** :
  - Pas de coordination avec `NoteIndexingCoordinator` : un debounce en cours
    et le sweep peuvent en théorie retraiter la même note en parallèle
    (accepté — double-work bénin, cf. tâche).
  - Le sweep peut être long sur un gros volume (embedding séquentiel par
    parent) ; s'il est interrompu (quit app), il reprend au prochain
    lancement sans état à nettoyer.
  - Pas de migration de métadonnées : un meeting dont le `kind` a changé
    (note ↔ projet) est ré-indexé avec le bon routage (`reindex` vs
    `reindexNote`), mais aucune donnée du meeting n'est modifiée.
- **Prochaine action** : rien d'identifié pour cette tâche ; PR prête.

## RAG — chat inline dans MeetingView (B2-ui MeetingView) (2026-09-05)

Branche `feat/rag-meeting-tool-calling`, sur `master` (+0 commit avant cette
session). Jusqu'ici, seuls les rapports (`AIReportService.generate`) et
l'assistant global (`ChatbotView`) parlaient au LLM ; aucune conversation
n'était possible pendant la réunion elle-même. Cf. ADR
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section MeetingView).

- **`Models/ChatMessage.swift`** (nouveau) : `ChatMessage` extrait de
  `ChatbotView.swift` (inchangé), pour être partagé avec `MeetingChatView`
  sans dupliquer le type.
- **`Views/Meeting/MeetingChatView.swift`** (nouveau) : widget de chat
  éphémère (messages en `@State`, RAM uniquement — disparaît à la fermeture
  de la réunion). À chaque question :
  - pré-fetch RAG historique (`RAGQuery.search`, scope selon `meeting.kind` —
    projet, collaborateur ou manager — avec `excludeMeetingPID` pour ne pas
    se nourrir de la réunion en cours) ;
  - historique de conversation sérialisé, limité aux 5 derniers tours ;
  - lit `settings.chatbotToolCallingEnabled` (même toggle global que
    `ChatbotView`, persisté dans `AppSettings`) pour choisir entre
    `AIClient.sendWithToolLoop` (B2, `ToolCatalog.all`) et `AIClient.send`
    (B1, pré-fetch seul). Le choix est extrait dans une fonction statique
    pure `shouldUseToolCalling(settingsList:)` pour rester testable sans
    environnement SwiftUI complet.
- **`Views/MeetingView.swift`** : nouvel onglet `.chat` (« Chat ») ajouté à
  `MeetingSection` — visible pour tous les kinds sauf `.note` (pas de sens
  pour un pot-pourri de notes libres). Structure des onglets existants
  inchangée, juste un cas de plus dans le `switch` et dans `allCases`.
- **Tests** : `Tests/MeetingChatViewTests.swift` — toggle actif → tool
  loop, inactif (ou aucun `AppSettings`) → chemin simple, et deux tests sur
  la construction du prompt (sections « Contexte historique » /
  « Conversation antérieure » présentes seulement si non vides).
- **Vérifié** : `swift build` propre ; `swift test` complet, 0 échec.
- **Hors périmètre** (volontaire) : pas de mock réseau pour le tool loop
  réel, pas de persistance de la conversation, `AIReportService` et
  `fetchHistoricalContext` (privée à `MeetingView`) non modifiés — le pattern
  RAG est dupliqué en privé dans `MeetingChatView` plutôt que partagé, faute
  d'API publique exploitable sans élargir le périmètre.

**Prochaine action** : si l'onglet Chat s'avère utile en usage réel, évaluer
l'exposition d'un historique persistant (actuellement volontairement
éphémère) et le partage effectif de `fetchHistoricalContext` entre
`MeetingView` et `MeetingChatView` (actuellement dupliqué).

## RAG — persistance du toggle tool calling (B2-ui v2) (2026-09-05)

Branche `feat/rag-tool-calling-toggle-persist`, sur `master` (+0 commit avant
cette session). Corrige B2-ui (PR #10) : le toggle « Recherche active » de
`ChatbotView` était un `@State private var useToolCalling: Bool = false`, donc
revenait à `off` à chaque réouverture de la vue.

- Nouveau champ `AppSettings.chatbotToolCallingEnabled: Bool = false`, à côté
  des autres toggles IA (`useAIForWeeklyExport`, etc.) — pas de migration
  SwiftData nécessaire (nouveau champ optionnel-like avec défaut, pas de bump
  de `SchemaVersions.swift`).
- `ChatbotView` : `useToolCalling` devient une propriété calculée qui lit
  `settings.chatbotToolCallingEnabled` ; le `Toggle` écrit désormais via un
  `Binding` explicite (`settings.chatbotToolCallingEnabled = $0; try?
  context.save()`) au lieu de `$useToolCalling`.
- **Corrigé au passage** : `ChatbotView.settings` faisait
  `settingsList.canonicalSettings ?? AppSettings()` — si aucun `AppSettings`
  n'existait encore en base (l'app ne force sa création qu'à l'ouverture de
  `SettingsView`), l'instance de repli n'était jamais insérée dans le
  `modelContext` et toute écriture (dont ce nouveau toggle) était perdue en
  silence. `settings` insère désormais et sauvegarde un `AppSettings` de
  secours si besoin, comme `SettingsView.settings` le fait déjà.
- **Tests** : `Tests/ChatbotViewTests.swift` —
  `toolCallingTogglePersistsInAppSettings` (round-trip SwiftData : un
  `AppSettings` avec `chatbotToolCallingEnabled = true` sauvegardé, puis relu
  depuis un second `ModelContext` sur le même conteneur, reste `true`).
- **Vérifié** : `swift build` propre ; `swift test` complet — 604 tests
  Swift Testing (92 suites), 0 échec.
- **Hors périmètre** (volontaire) : le toggle n'est pas exposé dans
  `SettingsView` — il reste local à `ChatbotView` mais persisté via
  `AppSettings`. Une future PR pourra l'y exposer pour cohérence avec les
  autres toggles IA.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : décider si le toggle doit apparaître dans
`SettingsView` (cohérence avec les autres réglages IA), sinon poursuivre sur
D (batch d'indexation globale) selon priorisation de l'ADR RAG.

## RAG — hybrid search BM25 + cosine via RRF (B3) (2026-09-05)

Branche `feat/rag-hybrid-search-b3`, sur `master` (C déjà fusionné, PR #11). ADR :
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section « B3 »).

- **Livré** : nouveau `Services/BM25Index.swift` — index lexical BM25 in-memory
  (`k1=1.5`, `b=0.75` par défaut), tokenisation minuscule + split Unicode
  alphanumérique (préserve les accents), ~80 stop-words français/anglais.
  IDF Robertson-Sparck Jones variante `+1` (jamais négatif). Reconstruit à
  chaque requête (pas de persistance), acceptable tant que le corpus reste
  modéré — cf. note déjà présente sur `RAGQuery.filtered`.
- `RAGQuery.searchHybrid(query:topK:scope:context:rrfK:cosineWeight:bm25Weight:)`
  (async, embedde la requête puis délègue) et sa variante testable
  `searchHybrid(queryVec:queryText:...)` (synchrone, vecteur pré-calculé —
  évite l'appel MLX réel dans les tests, cf. CLAUDE.md). Algorithme : rang
  cosine (chunks avec embedding non vide) + rang BM25 (chunks avec au moins
  un terme en commun), fusionnés par Reciprocal Rank Fusion
  (`poids * 1/(rrfK + rang)`, `rrfK=60` non paramétrable). Un chunk sans
  embedding ne participe qu'au rang BM25 ; un chunk sans texte (score BM25
  nul) ne participe qu'au rang cosine. `Result.similarity` porte le score RRF
  fusionné pour ce chemin (pas une similarité cosine brute). `RAGQuery.search`
  (cosine seul) reste inchangée, non réimplémentée en wrapper — les deux
  coexistent tel qu'autorisé par la consigne.
- `ToolRouter` : `search_knowledge` accepte un paramètre optionnel
  `use_hybrid` (booléen, défaut `false`) — absent ou `false` garde le
  comportement B2 (cosine seul, aucune régression) ; `true` route vers
  `RAGQuery.searchHybrid`. `SearchKnowledgeRequest` et le parsing exposent le
  champ ; `ToolSpec` documente le paramètre au LLM (FR/EN).
- **Tests** : `Tests/BM25IndexTests.swift` (tokenisation, filtrage stop-words,
  IDF favorise les termes rares, déterminisme, requête uniquement stop-words)
  et `Tests/RAGHybridSearchTests.swift` (un chunk pertinent lexicalement +
  sémantiquement remonte devant le meilleur score cosine seul ; un nom propre
  inventé sans embedding n'apparaît jamais en cosine seul mais remonte en
  hybride via BM25 ; une paraphrase sans recouvrement lexical retombe
  exactement sur le classement cosine — BM25 ne contribue rien). Plus
  parsing `use_hybrid` et forme JSON du paramètre côté `ToolSpec`.
- **Mesuré** : BM25 sur 3 500 chunks synthétiques (texte aléatoire ~40 mots +
  suffixe identifiant) pour une requête de 5 mots : **~2.6 ms** (build debug,
  banc temporaire non committé), très en dessous du seuil de 100 ms. Aucun
  log d'alerte déclenché en usage normal.
- **Vérifié** : `swift build` propre ; `swift test` complet — 1 032 XCTest
  (1 ignoré, 0 échec) + 603 Swift Testing (92 suites, 0 échec), dont 13
  nouveaux tests B3. Pas de régression sur B1/B2/C (`ChatbotViewTests`,
  `AIEndpointToolTests`, `RAGNoteIndexingTests`).
- **Limites actées** : pas de branchement UX (`RAGChatView`/`ChatbotView`
  n'exposent pas encore le choix hybride à l'utilisateur — hors périmètre de
  cette PR) ; `rrfK=60` figé en dur, non paramétrable via UI ; le score
  `Result.similarity` change de sens selon le chemin emprunté (cosine brute
  vs RRF fusionné) — à documenter si un appelant affiche cette valeur telle
  quelle.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : brancher `use_hybrid`/le choix hybride dans
`ChatbotView`/`RAGChatView` (PR séparée), ou enchaîner sur D (batch
d'indexation globale) selon priorisation de l'ADR.

## RAG — auto-indexation des notes live (C) (2026-09-05)

Branche `feat/rag-note-autoindex-c`, 3 commits sur `master`. ADR :
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section « C »).

- **Livré** : `RAGIndexer.reindex` lisait uniquement `mergedTranscript`/`rawTranscript` —
  toujours vides pour une note (`kind == .note`, ni audio ni transcription), donc le pipeline
  existant n'indexait jamais son contenu. Bascule la source sur `meeting.liveNotes` pour ce
  cas précis. Ajoute `RAGIndexer.reindexNote(meeting:context:)`, gate no-op silencieux hors
  notes, et `Task.checkCancellation()` à deux points de coupure du reindex (avant le clear des
  chunks, après l'embedding). Nouveau `Services/NoteIndexingCoordinator.swift` (singleton
  `@MainActor`) : débounce 2 s par note (`persistentModelID`), annule le débounce en cours à
  chaque frappe, et annule un reindex déjà en vol avant d'en démarrer un nouveau. Branché dans
  `MeetingView` aux deux endroits où `meeting.liveNotes` est effectivement modifié : le binding
  de l'éditeur (`.liveNotes` section) et `adoptPendingLiveNotes()` (reprise du texte en attente
  au démontage de l'écran).
- **Point d'injection ajouté pour les tests** : `NoteIndexingCoordinator.reindexHandler` (var,
  défaut `RAGIndexer.reindexNote`) et `debounceDelay` (var, défaut 2 s), substitués dans les
  tests par un double contrôlable — `swift test` n'embarque pas `default.metallib` (cf.
  CLAUDE.md), appeler le pipeline MLX réel y crasherait au premier accès GPU.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de
  `PyannoteDiarizer.swift`) ; `swift test` complet — 1 032 tests, 1 ignoré, 0 échec, dont 2
  nouveaux (`Tests/RAGNoteIndexingTests.swift`) qui couvrent le débounce (3 appels rapprochés
  → 1 seul reindex) et l'annulation d'un reindex en vol par une nouvelle édition.
- **Limite actée (hors scope, cf. ADR tâche D)** : si l'app se ferme pendant un débounce en
  cours, le reindex programmé est perdu — pas de rattrapage au démarrage suivant.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran (éditer une note, vérifier en base l'apparition des
`TranscriptChunk` après ~2 s d'inactivité) ; ou enchaîner sur B3 (hybrid search) / D (batch
d'indexation globale) selon priorisation de l'ADR.

## RAG — tool calling branché dans ChatbotView (B2-ui) (2026-09-05)

Branche `feat/rag-tool-calling-b2-ui`, 2 commits sur `master` (B2 déjà fusionné, PR #9).
Fichiers touchés : `OneToOne/Views/ChatbotView.swift`, `Tests/ChatbotViewTests.swift` uniquement.

- **Livré** : bascule `useToolCalling` (`@State`, non persistée) dans la zone de saisie —
  « Recherche active ». Par défaut B1 (pré-fetch RAG, 4 chunks max) reste utilisé ; activée,
  `sendMessage` appelle `AIClient.sendWithToolLoop` (`ToolCatalog.all`, `maxTurns: 5`,
  `onProgress: nil`) à la place de `AIClient.send`. La construction du prompt est extraite
  dans `makePrompt(question:databaseContext:ragBlock:history:)`, partagée par les deux
  chemins ; en mode tool calling `ragBlock` est vide, donc le bloc « Extraits pertinents »
  disparaît du prompt mais le contexte base et l'historique de conversation restent identiques.
  Le contrôle de joignabilité Ollama reste commun aux deux modes (il précède le branchement).
- **Écart avec la commande initiale** : le fichier visé nommait `handleFreeQuestion` —
  inexistant ; la méthode réelle est `sendMessage`, modifiée à cet emplacement.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de
  `PyannoteDiarizer.swift`) ; `swift test` complet — **1 030 XCTest (1 ignoré, 0 échec) +
  590 Swift Testing (88 suites, 0 échec)**, dont 1 nouveau test
  (`toolCallingOmitsRAGBlockFromPrompt`) qui vérifie sur `makePrompt` directement que le
  bloc RAG disparaît sans toucher au reste du prompt — pas de mock d'`AIClient` (hors
  périmètre de cette PR, `AIClient.swift` figé).
- **Non vérifié à l'écran** : le toggle et l'appel réel à `sendWithToolLoop` contre un
  vrai LM Studio/Ollama/OpenRouter.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran du toggle avec un endpoint compatible OpenAI réel,
puis PR ; ou enchaîner sur B3 (hybrid search BM25 + cosine) / C (indexation live) selon
priorisation de l'ADR.

## RAG — tool calling `search_knowledge` (B2) (2026-09-05)

Branche `feat/rag-tool-calling-b2`, 4 commits sur `master`. Suite de B1 (pre-fetch RAG,
`feat/rag-prefetch-b1`, déjà fusionnée). ADR : `docs/adr/2026-09-05-rag-pipeline-inventaire.md`
(section « B2 — Tool calling »).

- **Livré** : `OpenAICompatibleClient` décode et accepte enfin `tool_calls` (anti-pattern
  décrit par l'ADR — le transport refusait toute réponse en contenant) ; `stop`/`tool_calls`/
  `function_call` sont désormais des fins de tour normales, seul `content_filter` reste un
  refus. Nouvelle API `sendWithTools(messages:configuration:tools:)` (non-streamée) et
  `requestBody(messages:tools:)`. Nouveau `Services/AI/ToolRouter.swift` : `ToolSpec`/
  `ToolCatalog` (un seul outil pour cette PR, `search_knowledge`, description FR+EN) et
  `ToolRouter.execute` qui route vers `RAGQuery.search` (scope `meeting`/`attachment`/`mail`,
  `top_k` clampé `[1, 20]`) et retourne toujours un JSON exploitable — jamais une erreur Swift,
  un outil inconnu ou des arguments invalides deviennent `{"error": ...}`. `AIClient.
  sendWithToolLoop` orchestre la boucle (appel → tool_calls → exécution locale → réappel),
  plafonnée à 5 tours par défaut ; réservée aux endpoints compatibles OpenAI (LM Studio,
  OpenRouter, Ollama) — Anthropic et Gemini OAuth sont refusés immédiatement (`AIToolLoopError`),
  avant tout réseau.
- **Écart avec la commande initiale** : le fichier visé était `Services/AI/AIClient.swift` —
  inexistant ; l'`AIClient` réel vit à `Services/AIClient.swift` (fichier historique, pas dans
  `Services/AI/`), modifié à cet emplacement.
- **Limite actée** : pendant les tours d'outils, tout est non-streamé (l'API text/tool_calls
  d'un serveur compatible OpenAI ne l'est pas proprement dans ce cas) — `onProgress` n'est
  appelé qu'une fois, avec le texte final. Le niveau de raisonnement du profil (`AIReasoningLevel`)
  n'est pas propagé aux tours d'outils (hors périmètre de cette PR, seuls modèle et limite de
  sortie le sont).
- **Non branché** : `ChatbotView` n'utilise pas encore `sendWithToolLoop` — seules les briques
  bas niveau sont livrées ici ; le branchement UI est un chantier séparé (B2-ui).
- **Vérifié** : `swift build` propre ; `swift test` complet — **1 030 XCTest (1 ignoré, 0
  échec) + 589 Swift Testing (88 suites, 0 échec)**, dont 17 nouveaux tests
  (`Tests/AIEndpointToolTests.swift`) couvrant l'encodage `ToolSpec`, le parsing/dispatch/
  sérialisation de `ToolRouter` (sans jamais appeler le vrai pipeline d'embedding) et
  l'orchestration de `AIClient.runToolLoop` (réponse directe, tool_call puis texte, outil
  inconnu, plafond de tours, `onProgress` unique). Un test existant de `AIEndpointTests.swift`
  a été corrigé : il simulait un `finish_reason: "tool_calls"` sans tableau `tool_calls` réel,
  devenu `emptyResponse` (et non plus `refused`) depuis que `tool_calls` n'est plus
  systématiquement un refus.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : proposer B2-ui (brancher `sendWithToolLoop` dans `ChatbotView`), ou
enchaîner sur B3 (hybrid search BM25 + cosine) / C (indexation live des notes) selon
priorisation de l'ADR.

## Niveau de raisonnement par profil et limite de sortie relevée (2026-09-05)

Investigation du rapport LM Studio « toujours en raisonnement après 645 s » avec
`qwen3.8-27b` (mlx-community/Qwen3.8-27B-8bit), puis réglage ajouté après discussion.
ADR : [`2026-09-05-raisonnement-configurable.md`](docs/adr/2026-09-05-raisonnement-configurable.md).

- **Cause confirmée** : le `chat_template.jinja` du modèle injecte « Reasoning effort is
  set to xhigh » par défaut (prompt rendu vu dans `lms log stream`). LM Studio génère à
  8,4 tokens/s : un rapport long raisonne des milliers de tokens avant d’écrire, et la
  limite de 8 192 tokens couvrait réflexion et rapport ensemble.
- **LM Studio 0.4.23** ignore `reasoning_effort`, `reasoning: {effort}` et
  `chat_template_kwargs` sur `/v1/chat/completions` (prompt rendu identique) ;
  `/api/v1/chat` refuse `reasoning` pour ce modèle (HTTP 400) ; `/v1/responses` ignore
  `reasoning.effort` ; `/no_think` aggrave (511 tokens, tronqué). Leviers mesurés : consigne
  système « low » du template → 679/514 → 167/167 tokens de raisonnement ; préremplissage
  assistant `\n</think>\n\n` → 0 token, aussi en SSE.
- **Ollama 0.33.2** (`qwen3.8:27b-mlx`, nvfp4) honore `reasoning_effort` : xhigh/high/max
  injectent l’instruction xhigh, medium aucune, low la sienne, none désactive. Débit ≈ 30
  tokens/s. `gemma4:26b-mlx` plante dans le runner MLX d’Ollama (HTTP 500), hors sujet.
- **Livré** : `AIReasoningLevel` (défaut, désactivé, faible, moyen, élevé, maximal) dans
  `AIEndpointProfile.reasoning`. Ollama → `reasoning_effort`, OpenRouter → `reasoning.effort`
  (documenté, non testé : payant), LM Studio → consigne système reprise du template Qwen
  (`high` aligné sur `xhigh` comme Ollama ; `medium` rédigé, non mesuré) et désactivation
  par préremplissage, proposée seulement si l’identifiant contient « qwen ». Défaut =
  requête strictement inchangée. Sélecteur « Raisonnement » sous la limite de sortie.
- **Limite de sortie** : défaut 24 576 (3 × 8 192). Un profil sans clé `reasoning` et à
  exactement 8 192 est relevé une fois au décodage, puis réécrit par la migration ; toute
  autre valeur est conservée. Un niveau inconnu retombe sur le défaut sans invalider le profil.
- **Vérifié** : tests unitaires (décodage ancien JSON, migration idempotente, corps par
  fournisseur/niveau, capacités) ; test réel facultatif `liveReasoning`
  (`ONETOONE_AI_LIVE_REASONING=1`) : Ollama xhigh raisonne / off ne raisonne pas, LM Studio
  défaut raisonne / off ne raisonne pas, texte « OK » partout. Suite complète : **1 030 XCTest (1 ignoré), 570 Swift Testing en
  82 suites, 0 échec**. Aucun fichier LM Studio/Ollama modifié.
- **Serveur LM Studio** : authentification désactivée par l’utilisateur pour les tests, à
  réactiver (Developer > Server Settings). Le serveur et le modèle ont été relancés via
  `lms server start` / `lms load` pour le test réel.

- **Application de recette** : `.build/ai-endpoints-preview-v4/OneToOne.app` (build debug,
  ressources et bibliothèque Metal embarquées, signature ad hoc vérifiée, non installée
  ni lancée). Quitter l’ancienne instance avant ouverture.

**Prochaine action** : ouvrir l’app v4, régler le niveau sur le profil (Ollama ou
LM Studio), vérifier « Tester la connexion » puis un rapport complet ; réactiver
l’authentification LM Studio. Changements locaux non commités.

## Suivi de génération des rapports (2026-09-05)

Après un essai LM Studio interrompu à environ 6 min 46 : les journaux serveur
montraient une entrée de 6 457 tokens traitée en 17 secondes, puis un flux actif
jusqu’à l’annulation. Une longue phase de raisonnement est plausible, pas prouvée
par le journal de cet essai ; le petit test de connexion avait bien retourné du
`reasoning_content` séparément de `content`.

- Suivi distinct préparation, attente, raisonnement, rédaction, extraction.
  Les deltas `reasoning` / `reasoning_content` sont comptés, jamais affichés ni
  conservés dans le rapport. Le suivi seul active aussi le streaming de l’extraction.
- Après deux minutes sur la même phase : avertissement visible dans la réunion
  et la file des tâches, distinguant activité récente et silence de plus d’une minute.
  Pas d’arrêt automatique ni de modification du modèle ou de son raisonnement.
- Le markdown terminé est sauvegardé et affiché avant la seconde requête.
  L’annulation de l’extraction conserve ce texte. Une seule révision est créée ;
  les faits arrivent ensuite sans réécrire le texte éventuellement édité entre-temps.
- Les deux boutons de génération utilisent le même parcours avec propagation
  des erreurs et de l’annulation. Aucun rapport réel n’est relancé automatiquement.
- Validation : **1 030 XCTest (1 ignoré), 563 Swift Testing en 82 suites, aucun
  échec**. Tests ajoutés pour les deux champs de raisonnement, le SSE avec callback
  d’activité seul, les alertes temporisées, l’ordre publication/extraction, la
  conservation après annulation et l’échec de sauvegarde.
- Application de recette : `.build/ai-endpoints-preview-v3/OneToOne.app`, signée
  ad hoc et vérifiée. Quitter l’ancienne instance avant ouverture. Essai de rapport
  complet avec LM Studio encore à refaire ; la vitesse du modèle n’est pas modifiée.

## Correction des catalogues et retrait de Direct (2026-09-05)

Suite à la recette utilisateur du premier écran :

- Recherche, modèle, URL et jeton utilisent désormais `EditableTextField` AppKit
  (`NSSecureTextField` pour le jeton). Le coordinateur renouvelle son binding lors
  du changement de profil ; liste de modèles à hauteur fixe et textes explicatifs
  repliables sur plusieurs lignes.
- Catalogue chargé automatiquement au choix du fournisseur. OpenRouter se consulte
  sans clé ; la génération exige toujours la clé. Le message d’erreur de catalogue
  reste visible à côté de la liste. Les catalogues ont un délai de 20 secondes.
- **Constat réel LM Studio** : le serveur écoute sur 1234 et répond HTTP 401 sans
  jeton. L’écran invite désormais à le renseigner. Aucun secret n’a été lu ni modifié
  dans le serveur pendant cette vérification.
- **Ollama** devient un endpoint principal avec catalogue et chat compatibles OpenAI,
  au même niveau que LM Studio/OpenRouter.
- **Direct retiré** : suppression de `DirectLLMClient.swift`, du lien direct MLXLLM,
  de Gemma4Swift et de son profiler transitif dans les dépendances. Les anciennes
  configurations Direct migrent vers LM Studio sans inventer de nom de modèle ;
  un profil LM Studio précédemment enregistré est préservé. Les champs historiques
  restent lisibles. Les caches partagés de poids ne sont pas supprimés. MLXLLM reste
  transitif via la transcription ; les composants audio/embeddings sont conservés.
- **Validation** : catalogue réel OpenRouter décodé par le client Swift sans clé,
  **431 modèles**. Tests natifs des champs et du binding lors du changement de profil,
  tests Ollama et migration Direct ; suite complète : **1 030 XCTest, 1 ignoré,
  0 échec ; 557 Swift Testing en 81 suites, 0 échec**.
- Nouvelle app de recette : `.build/ai-endpoints-preview-v2/OneToOne.app`.
  La première app de recette est conservée ; les instances ouvertes ne sont pas arrêtées.

ADR complémentaire : [`2026-09-05-catalogues-ia-retrait-direct.md`](docs/adr/2026-09-05-catalogues-ia-retrait-direct.md).
**Prochaine action** : ouvrir la nouvelle app après fermeture de l’ancienne, renseigner
le jeton LM Studio puis actualiser ; vérifier le choix et la génération avec les modèles
souhaités. Changements locaux non commités.

## Endpoints IA — LM Studio / OpenRouter (2026-09-05)

Branche `refactor/ai-endpoints-lmstudio-openrouter`, créée depuis `master` à `a388fb8`.
Plan et audit du code/documentations officielles dans
[`docs/superpowers/plans/2026-09-05-architecture-ia-endpoints.md`](docs/superpowers/plans/2026-09-05-architecture-ia-endpoints.md).

- **Livré après accord utilisateur** : lots 1 à 4. Profils séparés par fournisseur,
  nouvel écran `AISettingsView` (choix endpoint puis modèle, catalogue avec recherche,
  identifiant manuel, test sur brouillon, enregistrement explicite), transport HTTP
  commun pour LM Studio et OpenRouter avec annulation et erreurs SSE. `AIClient`
  fige le profil avant l’inférence ; les services métier existants passent par cette façade.
- **Migration** : champs SwiftData additifs, fournisseur historique préservé, clés au
  Trousseau avec vérification avant effacement du champ historique. Les nouveaux
  backups omettent clés et références ; les anciens exports restent lisibles. Le
  classement distant des mails doit être réactivé après restauration.
- **Mails et Teams** : classement via le client commun, option explicite pour les
  endpoints hors boucle locale, repli heuristique ; disponibilité des rapports Teams
  vérifiée avec le profil et sa clé, et non l’ancien champ `cloudToken`.
- **Vérifié** : `swift build`, puis `swift test` complet : **1 030 XCTest, 1 ignoré,
  0 échec ; 550 Swift Testing en 80 suites, 0 échec**. Nouveaux tests de migration,
  Trousseau simulé, réouverture disque, sauvegardes, HTTP, SSE multiligne/UTF-8,
  erreurs après HTTP 200, troncature et annulation. Le test HTTP a révélé puis validé
  le correctif d’`AsyncBytes.lines`, qui omet les lignes vides SSE. Avertissement
  préexistant de concurrence dans `PyannoteDiarizer.swift`.
- **Application préparée** : `.build/ai-endpoints-preview/OneToOne.app`, ressources et
  bibliothèque Metal embarquées, signature ad hoc vérifiée. Ni installée ni lancée.
- **Recette restante** : interface native, Trousseau réel et génération avec les modèles
  choisis sur LM Studio/OpenRouter. Aucun serveur ne répondait sur le port local 1234
  lors de la vérification ; aucun appel OpenRouter payant effectué.
- **Différé** : embeddings sur API et réindexation, retrait des anciens fournisseurs,
  transcription distante et runtime d’agent. Audio, OCR, embeddings locaux et Claude CLI
  conservent leur fonctionnement. ADR :
  [`2026-09-05-endpoints-ia-configurables.md`](docs/adr/2026-09-05-endpoints-ia-configurables.md).

**Prochaine action** : recette dans l’application avec un modèle LM Studio et un modèle
OpenRouter, puis revue/PR de cette première livraison. Changements locaux non commités.
Les validations manuelles de capture de slides ci-dessous restent à effectuer.

## Capture automatique de slides (2026-09-02)

Branche `feat/capture-auto-slides`, code de la fonctionnalité à **`3574054`**, puis
correctifs de la revue finale (ce commit), basée sur `master` à `553458f`.
Huit tâches livrées (Task 8 = cette section) plus la vague de correctifs. Spec :
`docs/superpowers/specs/2026-09-02-capture-auto-slides-design.md`. ADR :
`docs/adr/2026-09-02-capture-slides-polling-empreinte.md`.

- **Livré** : nouveau module pur `OneToOne/Services/SlideCapture/` (`SlideFingerprint`,
  `NormalizedRect`, `SlideCaptureSettings` à deux seuils, `SlideDetector`,
  `FrameSource`/`ShareableWindow`/`SlideCaptureError`, `WindowCatalog`, `WindowFrameSource`,
  `ScreenRecordingSettingsLink`) ; `ScreenCaptureService` réécrit (états
  idle/running/paused/stopped, arrêter conserve la session, reprendre, terminer clôt, jeton
  de session revérifié après chaque `await`, tâche OCR gardée par un contrôle de vivacité,
  ajout à un lot précédent avec réamorçage du détecteur, noms de fichiers à 4 chiffres) ;
  `ScreenCaptureConfigView` réécrit en trois faces plus la face de refus d'autorisation ;
  `CropSelectionView` nouveau ; `PerceptualHasher.swift` et `RectSelectorOverlay.swift`
  supprimés ; `AppSettings.slideCaptureSensitivityRaw` ajouté (migration légère) ;
  `Info.plist` reçoit `NSScreenCaptureUsageDescription` ; les barres et `MeetingView`
  affichent l'état réel avec Reprendre/Terminer, et `onDisappear` clôt une session ouverte
  après les gardes de suppression.
- **Correctifs de la revue finale** : `finish()` ne jette plus le texte d'un OCR qui se
  termine pendant l'attente (la tâche OCR écrit dans **son** slide et **son** attachment,
  gardée par la vivacité des modèles et non par le jeton) ; après chaque `await`, tick et
  écriture exigent jeton **et** état actif (`sessionIsLive`) — un tick relâché après `stop()`
  ne publie plus `.paused` par-dessus `.stopped` ni n'écrit de slide ; `resume()` et
  `updateSource()` exigent un jeton non nul et `finish()` annule toute boucle relancée
  pendant son attente (plus de boucle fantôme qui bloquait la session suivante) ;
  `abandon()` ajouté et appelé par `onDisappear` sur le chemin « réunion supprimée » (rien
  sauvegardé, rien réindexé) ; `WindowCatalog` passe à `onScreenWindowsOnly: false` et
  filtre calque `0` + hors-écran non-réunion, donc une fenêtre Teams en plein écran sur un
  autre Space est enfin proposée et reprise ; « Commencer » est désactivé sur
  `selectedWindow == nil` et un rafraîchissement oublie une sélection disparue ; la
  numérotation d'un lot repris part du **maximum** des index et non de leur nombre ;
  `SessionError.noOpenSession` (inutilisée) remplacée par
  `attachmentBelongsToAnotherMeeting`, levée par `beginSession(appendTo:)`.
- **Tests** : `SlideFingerprintTests` (8), `NormalizedRectTests` (12), `SlideDetectorTests`
  (10), `SlideCaptureErrorTests` (4), `WindowCatalogTests` (3), `ScreenRecordingSettingsLinkTests`
  (3), `ScreenCaptureServiceTests` (23, dont 7 écrits en rouge pour la revue finale : OCR
  conservé à la clôture, tick en vol pendant `stop()` — publication et écriture —, `resume()`
  refusé pendant la clôture, `abandon()`, `appendTo` d'une autre réunion, numérotation sur le
  maximum des index). Preuves de mutation faites sur l'axe Y, la dérive lente et le jeton de
  tick (Test A). Suite complète après les correctifs : **XCTest 1030 exécutés, 1 ignoré, 0
  échec ; Swift Testing 529 tests en 77 suites, 0 échec** ; `swift build` propre à part
  l'avertissement préexistant dans `PyannoteDiarizer.swift`.
- **Points ouverts mineurs** (revue différée à la revue finale) : `fromDrag` avec une vue de
  taille nulle renvoie `.full` au lieu de `current` ; balayage anti-doublon linéaire ;
  `onScreenWindowsOnly: false` dans `WindowFrameSource` **et** désormais dans le catalogue
  (délibéré : capturer une fenêtre occultée est la prémisse de la fonctionnalité) ; la tâche
  d'instantané n'est pas attendue par `finish()` ; écrire la sensibilité est un no-op si
  aucune ligne `AppSettings` n'existe
  encore ; `MeetingView` réinitialise toujours `lastError` directement pour fermer le
  bandeau (accepté).
- **Build** : `Scripts/bump-and-build.sh dev` exécuté pour la Task 8 ; `swift build` propre
  après les correctifs de la revue finale.

### Validation manuelle — à faire par l'utilisateur

Aucune validation manuelle n'a été effectuée. À dérouler sur une vraie présentation (Teams,
Zoom ou Meet, ou un Keynote/PowerPoint en plein écran dans une autre fenêtre) :

- [ ] Ouvrir une réunion → « Capture » → autorisation demandée la première fois ; refuser
      une fois pour voir l'écran de refus et le bouton « Ouvrir les Réglages » ; accorder ;
      relancer.
- [ ] Choisir la fenêtre, tracer une zone : vérifier que **le haut et le bas** du slide
      écrit correspondent au tracé (ouvrir le PNG dans
      `~/Library/Application Support/OneToOne/recordings/<uuid>/slides/`).
- [ ] Faire défiler trois slides : trois fichiers, pas plus. Revenir sur le premier : rien
      de plus.
- [ ] Déplacer puis redimensionner la fenêtre source : la zone suit.
- [ ] Fermer la fenêtre source : pastille orange « En pause » ; la rouvrir : bleu, reprise
      seule.
- [ ] Arrêter → « Arrêtée · N » ; Reprendre → numérotation continue ; Terminer → OCR, texte
      agrégé visible dans la galerie, lot clos.
- [ ] Rouvrir « Capture » : « Ajouter au lot précédent » proposé ; un slide déjà présent
      n'est pas réécrit ; un nouveau l'est avec l'index suivant.
- [ ] Fenêtre source **entièrement** recouverte par une autre : la capture continue-t-elle ?
      Noter le résultat (non couvert par la sonde du prototype).
- [ ] Fenêtre Teams en plein écran (autre Space) : proposée dans la liste, capture et reprise
      fonctionnent.

**Prochaine action** : validation manuelle des neuf points ci-dessus, puis push et PR.
Chantier séparé en attente : auto-start avec l'auto-record Teams.

## Le dépôt n'a plus qu'une branche (2026-09-02, fin de session)

`master` est à **`ee8a4b3`**, écart 0 avec `origin/master`. **18 branches locales et 11
distantes ont été supprimées** : il ne reste plus que `master`, local et distant, et plus
aucun worktree hors la copie principale. Toutes ont été vérifiées entièrement contenues dans
`master` avant suppression, **sauf quatre**, supprimées en connaissance de cause — trois
dépassées par du code plus récent (voir plus bas) et `worktree-agenda-project-picker-search`,
détruite sur décision explicite avec un apport réel dedans, décrit ci-dessous pour qu'il
puisse être réécrit.

- **Dernière fusion de code : `fix/code-review-data-safety-perf`** (`ee8a4b3`). ⚠️ **La
  prémisse de ce fichier était fausse** : il présentait cette branche comme la seule copie de
  huit correctifs jamais repris. En réalité `master` avait déjà implémenté les mêmes
  correctifs, **en mieux**. Les quatre conflits ont donc été résolus **en gardant `master`** :
  `TranscriptEditService` (master sauvegarde le contexte partagé *avant* toute coupe audio et
  documente son rollback), `AudioFileEditor` (master factorise la garde d'allocation dans
  `tamponDeLecture(format:capacite:operation:)`), `AIClient` (la branche réintroduisait
  `callClaudeCLI`, supprimé depuis) et `MeetingView` (la branche portait l'ancienne API
  `onStartRecording` / `onRetranscribe`, refactorisée depuis en `makeMenuActions()` — la
  prendre aurait cassé la compilation).
- **Six correctifs sont quand même entrés**, réellement absents de `master` et sans
  régression : déduplication des `TranscriptChunk` au démarrage, lecture texte avec repli
  CP1252 / ISO Latin-1, mention explicite de troncature dans le bloc « documents joints » du
  rapport, `ImageCache` (`CachedNSImage.swift`) pour les photos de collaborateurs, recherche
  **debouncée** dans la barre latérale, et construction du contexte du chatbot sortie du
  chemin synchrone.
- **Vérifié sur la fusion** : `swift test`, build à froid — **1030 XCTest (1 ignoré, 0 échec)
  + 466 tests Swift Testing en 70 suites**, code de sortie 0, **aucune erreur de
  compilation**, et **zéro avertissement sur les sept fichiers touchés**. Les 698
  avertissements du log sont ceux, préexistants, que tout build à froid réémet.
- **Écartées comme dépassées, sans perte** : `feat/agent-taches-claude` (sa spec est sur
  `master` à l'identique, son commit Spotlight est une variante plus ancienne de ce que
  `master` porte), `feat/agent-taches-claude-wip` (seize fichiers identiques à l'octet près)
  et `fix/meeting-stable-id-optional` (`master` porte `stableID: UUID?` plus le backfill
  `ensuredStableID`, généralisé à tous les modèles).
- **`worktree-agenda-project-picker-search` supprimée** (locale, `origin` et son worktree),
  sur décision explicite : nettoyage net. Elle figeait 784 lignes commitées nulle part.
  L'essentiel du chantier « affectation événement d'agenda → projet » est **déjà sur
  `master`, à l'identique** : `AgendaProjectRule`, `AgendaProjectResolver` et ses 159 lignes
  de tests, la relation `Project.agendaRules`, la version de schéma, la liste de gestion des
  règles dans `SettingsView`.
- **⚠️ Ce qui a été détruit avec elle, et qu'il faudra réécrire si on le veut.** Son seul
  apport réel — celui que son nom annonce — était le **sélecteur de projet du panneau
  Agenda**. Sur `master`, la pastille de projet ouvre un `Menu` listant **tous** les projets
  à plat, sans filtre : pénible passé quelques dizaines de projets. La branche le remplaçait
  par un popover de 300 pt dans `AgendaInspectorPanel.swift` : champ « Filtrer les projets… »
  insensible à la casse, confirmation en un clic de la suggestion automatique en tête, liste
  filtrée dans un `ScrollView` borné à 320 pt, état vide distinguant « aucun projet dans la
  base » de « aucun résultat », et « Ignorer ce titre » / « Retirer la règle » en pied.
  Environ cent lignes. Ce n'était **pas** fusionnable tel quel : le fichier de la branche
  (364 lignes) partait d'une base antérieure à la version actuelle de `master` (283 lignes),
  il aurait fallu reporter le popover, pas remplacer le fichier.
- **Worktrees retirés** : `agent-claude`, `pastille-participant`, `teams-autorecord-popup`
  (tous propres) et `paperclip/-issue` (outil tiers, son dossier `web/` non suivi est perdu —
  suppression demandée). La copie de travail principale est passée sur `master` et est propre.

## Tout le travail local est sur `origin` (2026-09-02)

Session sans code : mise à jour du dépôt distant, qui n'avait rien reçu depuis le
2026-08-28. `origin/master` est à **`8548b8d`**, écart 0 avec le `master` local.

- **16 commits poussés sur `master`** : les 13 qui étaient en retard (double piste audio,
  frontières de chunks sur les silences, vague de correction de la revue, clés d'usage
  calendrier) et trois commits de fusion — `feat/pastille-participant-fil-ariane` (spec),
  `feat/teams-audio-double-piste` (spec « détection d'appel universelle »)
  et `feat/agent-claude` (noyau du service d'agent Claude, son dossier de travail,
  sept fichiers de tests, la spec).
- **Cinq branches créées sur `origin`**, sauvegardées telles quelles avant toute fusion :
  `feat/agent-claude`, `feat/agent-taches-claude`, `feat/agent-taches-claude-wip`,
  `feat/pastille-participant-fil-ariane`, `feat/teams-audio-double-piste`. Les autres
  branches locales sont entièrement contenues dans `master` — les pousser n'aurait ajouté
  que des étiquettes.
- **`feat/agent-taches-claude` n'a PAS été fusionnée**, seul écart à la consigne « tout
  fusionner », et il est délibéré : elle conflictait sur `MeetingView.swift` et
  `SpotlightMeetingIndexTests.swift`, et son commit Spotlight est une variante **plus
  ancienne** de ce que `master` a déjà reçu par `feat/fusion-note-reunion` (`indexAll` avec
  réunions et notes, `makeMeetingItem`, exclusion des transcriptions). Résoudre les conflits
  revenait à écraser du code plus récent. Sa spec est entrée par `feat/agent-claude`.
  `feat/agent-taches-claude-wip` était, elle, intégralement absorbée : ses seize fichiers
  sont sur `master`, identiques à l'octet près. Les deux branches restent sur `origin`.
- **Vérifié** : `swift test` complet sur la fusion, build à froid dans un worktree jetable —
  **1030 XCTest (1 ignoré, 0 échec) + 466 tests Swift Testing en 70 suites**, code de sortie 0.
  Le `--skip CalendarImportEventTests` reste inutile. La copie de travail n'a pas été touchée.
- **Quatorze documents versés** qui ne vivaient que sur le disque, dans aucun commit :
  `design_handoff_editor_blocs/` (handoff de design des blocs `/tableau` et `/diagramme` :
  README de spec visuelle, cinq captures, maquette HTML de référence) — **ce fichier-ci le
  citait déjà** comme point de départ du chantier éditeur, le lien pointait vers un dossier
  absent du dépôt ; les specs `2026-08-05-commandes-slash-manquantes.md` (inventaire des
  commandes slash d'AppFlowy, 364 lignes) et `2026-08-10-json-canonique-notes-design.md`
  (étude Markdown → JSON canonique, 591 lignes, aucune décision prise) ; `docs/adr/README.md`
  (convention de nommage des ADR) ; et `docs/architecture/` (`branch-status.md`,
  `cartographie.docx`, `diagram.html`). `branch-status.md` est un instantané du 10 août
  devenu faux — il décrit `feat/fusion-note-reunion` comme active alors qu'elle est
  fusionnée : versé tel quel, avec une ligne d'archivage en tête qui le dit. Aucun de ces
  fichiers ne tombe dans un répertoire de cible SwiftPM (`OneToOne/`, `Tests/`,
  `Vendor/BeautifulMermaidSwift/Sources`) : le build n'est pas touché.
- **Restent non suivis dans la copie de travail, et c'est sans conséquence** : quinze
  fichiers `OneToOne/Services/Agent/*.swift` et `Tests/Agent*.swift`, copies **identiques à
  l'octet près** de ce que `master` porte désormais. Ils peuvent être supprimés.
- **Ce que ce push ne change pas** : rien n'a été vérifié à l'écran. Les treize scénarios des
  deux plans Teams auto-record restent dus (voir les deux sections suivantes), l'attribution
  « moi » / « distant » n'est toujours câblée nulle part, et la spec « détection d'appel
  universelle » (2026-08-31, statut « à valider ») n'a **pas de plan écrit**.

## Teams auto-record — double piste audio (plan 2/2) (2026-08-31)

Branche `feat/teams-audio-double-piste`, **fusionnée dans `master` et poussée le 2026-09-02**
(voir la section du jour en tête de ce fichier) — voir le
[plan](docs/superpowers/plans/2026-08-28-teams-autorecord-double-piste-audio.md). Suite du
plan 1 ci-dessous.

- **État** : plan 2 « double piste audio », **les cinq tâches sont implémentées, revues et
  closes** sur `feat/teams-audio-double-piste` — mixeur pur avec provenance
  (`AudioTrackMixer`), capture système `SCStream` audio-only (`SystemAudioCapture`),
  intégration dans `AudioRecorderService` (flux STT verrouillé sur l'horloge micro,
  **WAV mixé** — toute retranscription entend les deux voix, spec §5 amendée), bandeau de
  repli micro seul, frontières de chunks sur les silences. La revue de branche a été suivie
  d'une vague de correction unique : livraison des blocs système directement depuis la file
  `SCStream` (le détour par le main actor figeait le retard de la voix distante quand le
  main thread bouchonnait), horodatage de la provenance sur l'horloge des échantillons
  publiés (une horloge murale se décalait de toute la durée d'une pause), bandeau de repli
  restreint à la réunion qui enregistre, et **une seule transcription en vol** —
  `maxConcurrent` ramené de 2 à 1, deux `model.generate` simultanés partageant un état
  `MLXArray` que mlx-swift documente comme non thread-safe.
- **Ce que la branche ne livre PAS — l'attribution « moi » / « distant »** : la chronologie
  d'énergie par piste est **produite** (`provenanceTimeline` se remplit, la fonction de
  décision `AudioTrackMixer.provenance` existe et est testée) mais **n'est consommée par
  personne**. Aucun segment transcrit ne porte de provenance, rien ne l'affiche, et la
  chronologie ne vit qu'en mémoire : elle est perdue à la fin de l'enregistrement. La spec
  §6.1(4) et D-7 le disent désormais explicitement. Le câblage (segments → `speakerID`) est
  un **chantier de suite**, avec la question de persistance qui vient avec : le WAV étant
  mixé, la provenance y est détruite et une retranscription du fichier ne la retrouvera
  jamais.
- **Vérifié cette session** : suite complète verte — `swift test` (sans `--skip`) :
  **366 tests Swift Testing (63 suites) + 1030 tests XCTest (1 ignoré), aucun échec** ;
  aucun nouvel avertissement de compilation sur les quatre fichiers touchés par la vague de
  correction (`AudioRecorderService`, `SystemAudioCapture`, `TranscriptionService`,
  `MeetingView`). Le bump de `CFBundleVersion` laissé par un run du script de build a été
  rendu à son état committé — `Info.plist` n'est pas modifié par ce chantier.
- **Vérifié à la session précédente** (tâche 4, toujours valable) : app construite
  via `Scripts/bump-and-build.sh dev`, sans `sudo` ni invite, build **761** ; process actif
  20 s après lancement (`pgrep`) ; `log show --last 1m --predicate 'subsystem ==
  "com.onetoone.app"'` ne remonte **aucune** entrée (donc aucune erreur) ; quittée
  proprement (process disparu après coupure) ; aucun rapport dans
  `~/Library/Logs/DiagnosticReports/`. **Attention** : `Scripts/bump-and-build.sh` tue
  **tout** processus nommé `OneToOne` (`pkill -x`, non scopé par chemin) — l'instance
  homonyme d'une autre session a été tuée puis relancée pendant cette vérification
  (changement de PID observé). Les contrôles de lancement/arrêt de cette vérification-là ont, eux,
  été scopés par chemin d'exécutable et ciblés par PID. Risque résiduel connu : lancer ce
  script pendant qu'une autre instance tourne l'interrompt ; un `pkill` scopé par chemin
  dans le script est à faire (report).
- **Prochaine action — partenaire, à l'écran** (aucun scénario faisable par un agent) :
  1. **Double piste nominale** : permission écran accordée, vrai appel Teams, accepter le
     popup, faire parler l'interlocuteur puis soi-même → la transcription contient les
     deux voix ; **retranscrire ensuite le WAV** (« Retenter le STT ») → les deux voix
     encore. Pas de bandeau jaune.
  2. **Permission refusée** : retirer l'app de Réglages Système → Enregistrement de
     l'écran, relancer, enregistrement Teams → démarre quand même, bandeau jaune, voix
     locale seule, aucune erreur bloquante.
  3. **Non-régression classique** : réunion sans lien Teams → une seule piste, aucun
     bandeau, aucune chronologie de provenance.
  4. **Appel long (> 20 min)** : deux choses observables, et deux seulement.
     (a) Le log unique « reliquat audio systeme plafonne » apparaît-il (dérive d'horloge
     système) ? Il ne doit jamais se répéter. (b) En fin d'appel, la voix distante est-elle
     toujours **synchrone** dans la transcription, ou a-t-elle pris du retard sur la
     locale ? Ne pas chercher d'attribution moi/distant : elle n'existe pas encore
     (voir plus haut).
  5. **Vumètre** : pendant que seul l'interlocuteur distant parle, le vumètre reste plat
     (il ne lit que le micro) — juger si c'est acceptable ou s'il faut l'alimenter du mix
     (à noter comme report si gênant).
  6. **Import audio > 5 min** : timestamps des segments qui suivent les coupes, barre
     « Segment n / N ».
- **Reports connus** (issus des revues, non bloquants) : vumètre micro seul (il ne lit que
  le micro, pas le mix) ; test `idleTimelineIsEmpty` assert sur l'état partagé du singleton ;
  `writeToFile` avale son `guard` en silence ; la branche double piste engagée (mix +
  écriture) n'a pas de test unitaire — c'est la vérification à l'écran qui la couvre ;
  `chunksTileTheSignal` ne vérifie pas la non-vacuité du **dernier** intervalle ; fenêtre
  étroite (65,0 s ; 65,2 s] où le dernier morceau peut tomber à ~0,2 s ; `pkill -x` non
  scopé par chemin dans `Scripts/bump-and-build.sh`. Repliés par la vague de correction et
  donc retirés de cette liste : `provenanceTimeline` publié sans lecteur, doc `TapSink` en
  retard sur son contrat, commentaires « chunks 60s » périmés.

## Teams auto-record — détection & orchestration (plan 1/2) (2026-08-28)

- **État — livré en production.** `master` à `69ceabf` (fast-forward de `bbad581` : les 23
  commits du chantier y sont), build **754** (release) dans `/Applications`. ~~Rien n'est
  poussé sur `origin`~~ — **résolu le 2026-09-02** : tout est sur `origin/master`, voir la
  section en tête de ce fichier. Les tâches 1 à 8
  du plan `docs/superpowers/plans/2026-08-28-teams-autorecord-detection-orchestration.md`
  sont implémentées et revues — détection pure,
  appariement agenda, moniteur `NSWorkspace` + énumération opportuniste, cinq catégories de
  notification Teams (neuf enregistrées au total), machine à états pure, icône de barre de
  menus, coordinateur (trois déclencheurs + horloge 30 s gardée sur Teams en cours
  d'exécution), `MeetingView` qui consomme les demandes et rend compte,
  concurrence (liaison), garde provider IA, popup STT indisponible avec « Retenter le STT »
  qui relance la transcription. Micro seul : la double piste est le plan 2. La revue de branche
  a été soldée par une vague de correction unique (identité par occurrence pour les réunions
  récurrentes, popup remplacé plutôt que bloquant, horloge gardée sur Teams, tick lent au
  repos) — voir le « Journal d'exécution » du plan.
- **Vérifié** : `swift test` complet — **le `--skip CalendarImportEventTests` n'est plus
  nécessaire** depuis que `MeetingNotificationService` n'instancie `UNUserNotificationCenter`
  que dans un bundle `.app` (`Bundle.main.bundleURL.pathExtension == "app"`, sinon `center`
  reste `nil`) ; l'app se construit, se lance et quitte sans crash. Confirmé cette session :
  `Scripts/bump-and-build.sh dev` sans `sudo` ni invite, build 749 ; process `OneToOne` actif
  après 20 s ; `log show` sur `subsystem == "com.onetoone.app"` (niveaux info/debug inclus,
  catégories `teams`, `teams-autorecord`, `capture` en particulier) ne remonte **aucune**
  entrée pour le process `OneToOne` — donc aucune erreur ; l'app quitte proprement via
  `osascript` (`pgrep` négatif ensuite) ; aucun rapport dans
  `~/Library/Logs/DiagnosticReports/`. **À la livraison** : suite complète repassée sur
  `69ceabf` — 335 Swift Testing + 1030 XCTest, aucun échec ; `Scripts/bump-and-build.sh prod`
  sans `sudo` ni invite (`/Applications` écrivable), build 754, `default.metallib` MLX embarqué
  depuis `Mickey.app`, copie de développement de `~/Applications` retirée par le script, app
  relancée depuis `/Applications` et vivante, toujours aucun rapport de crash.
- **⚠️ Livré sans avoir jamais été vu à l'écran.** Ce qui est prouvé : ça compile, la suite
  passe, l'app se lance, tourne et quitte sans erreur ni crash. Ce qui ne l'est pas : qu'un
  vrai appel déclenche le popup, que « Démarrer » enregistre, que « Arrêter et finaliser »
  transcrive, que le rapport se génère. Le parcours complet reste à éprouver.
- **Prochaine action — partenaire, à l'écran** (sept scénarios, aucun n'est faisable par un
  agent — il faut un vrai appel Microsoft Teams et un calendrier vivant) :
  0a. Réunion récurrente, deuxième occurrence : le popup est proposé et « Démarrer » crée une
     nouvelle réunion (pas d'écrasement de la précédente).
  0b. Bannière ignorée : laisser expirer le popup, attendre l'appel suivant → il est proposé
     (le précédent est remplacé).
  1. Détection + démarrage : événement Teams à +1 min dans le calendrier, fenêtre Teams au
     premier plan avec « Réunion » dans le titre, 5 s → popup ; « Démarrer » crée, ouvre,
     enregistre, icône rouge pulsante.
  2. Refus : « Ignorer » → rien de créé, pas de re-popup pour le même événement.
  3. Fin d'appel : `killall Teams`, 30 s → popup « Appel Teams terminé » ; « Arrêter et
     finaliser » → capture arrêtée, transcription lancée, icône normale.
  4. Rapport : popup « Transcription prête (N segments) » ; « Générer le rapport » →
     rapport dans la réunion, éditable.
  5. Sans permission d'enregistrement d'écran : « Rejoindre Teams » depuis OneToOne → le
     déclencheur 2 propose quand même (D-11).
  Puis : plan 2 (`2026-08-28-teams-autorecord-double-piste-audio.md`).
- **Défauts connus / reports** (issus des revues, non bloquants) : l'icône de barre de menus
  est pilotée par le coordinateur, pas par l'état réel du recorder ; aucun timeout si la
  fenêtre ne rend jamais compte ; `TeamsCallMonitor.stop()` n'annule pas un tick en vol ; le
  mode dégradé sans `UNUserNotificationCenter` (binaire hors `.app`) reste invisible pour
  l'utilisateur — il n'est tracé qu'en `.warning` dans le log système ; la trace
  « Source : Outlook Calendar » de la spec §5 n'est pas écrite (`summary` est le corps du
  rapport, écrasé à la génération — `calendarEventID`/`calendarEventTitle` portent le lien).

## Synthèse

**Fiche collaborateur v3 — livrée en production.** `master` à `70c268d`, build 730 (release)
dans `/Applications`. 997 XCTest (1 ignoré) + 270 Swift Testing, aucun échec. La copie de
développement de `~/Applications` a été retirée par le script : il n'y a plus qu'une app.

**Couvert** : fil chronologique unifié à quatre types, colonne d'état fixe (prochain 1:1 avec
ses points de préparation cochables, engagements soldables, actions, rythme, projets), en-tête
adaptatif, feuille d'édition `⌘I` complète avec puits photo à cinq entrées, sélecteur d'année,
export du fil, suppression, navigation clavier (`↑↓`, `␣`, `⏎`, `⌘1`…`⌘5`).

**Trois manques réels**, tous à la charge d'un prochain chantier :

1. le **tri « Pas vu depuis » du dashboard** n'existe pas — critère d'acceptation n° 9 de la
   spec ; la cadence n'est lue que par la fiche ;
2. **`⎋` ne demande jamais confirmation** : la feuille d'édition ne sait pas si elle est
   modifiée (critère n° 10) ;
3. **`⌘⌥←/→`** demande de toucher à la barre latérale, donc un autre écran.

**Deux écarts assumés** : `⏎` ouvre la réunion dans sa fenêtre dédiée et non en poussant dans
la pile — la navigation programmée depuis ce panneau est ce qui avait fait crasher AppKit au
build 715 ; et les squelettes de chargement n'ont rien à masquer, `@Query` résolvant avant le
premier rendu.

**⚠️ La plus grande part n'a jamais été vue à l'écran.** Vérifiés par l'auteur : l'affichage,
la colonne d'état qui ne défile pas, l'ouverture d'une réunion, le retour, l'absence de crash
au double-clic, la feuille d'édition. **Non vérifiés** : graphe d'écart, cases de préparation,
sélecteur d'année, export, suppression, tous les raccourcis clavier, et le glisser-déposer
d'une photo. Prochaine action : une passe à l'écran, spec en main.

**Réparations de données passées au démarrage**, toutes idempotentes et vérifiées sur le store
réel : 38 rôles portant une adresse mail déplacée vers le champ `email` (0 perte, dont 16 où
l'adresse n'existait que là), et les réunions dont le drapeau de report de préparation avait
été posé sans que rien n'ait été versé.

**Deux branches en attente.** `feat/pastille-participant-fil-ariane` : spec validée, plan
jamais écrit. `feat/fusion-note-reunion` : fusionnée dans `master` ; sa tâche 13 garde huit
contrôles non déroulés, passés en vérification à l'usage.

**Fusion Note / Réunion — code terminé, vérification sur données réelles due.** Branche
`feat/fusion-note-reunion`, 43 commits. Les douze tâches de code du
[plan](docs/superpowers/plans/2026-08-10-fusion-note-reunion.md) sont livrées ; la
treizième — sauvegarde du store, migration, dix contrôles à l'écran — **n'a pas eu lieu**.
Voir la section datée du 2026-08-10 ci-dessous. Prochaine action : cette tâche 13.

**Réécriture de l'éditeur — décidée, verdict du prototype en attente.** La
réécriture de l'éditeur en reprenant l'architecture d'appflowy-editor
(AGPL-3.0 acceptée) est décidée, voir
[l'ADR de licence](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
Un prototype jetable (`Prototypes/BlockEditorProbe/`) a sondé le risque
central — une vue éditable par bloc en AppKit — et existe toujours ; son
verdict est **en attente** de la vérification à l'écran, qui n'a pas eu
lieu, voir [l'ADR de verdict](docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md).
Le chantier ci-dessous (`feat/editeur-slash-blocs`) reste **en l'état** :
ni fusionné, ni abandonné ; sa propre vérification à l'écran reste due,
indépendamment du prototype. Prochaine action : la session de vérification
à l'écran du prototype.

**Vitrine `ActionsListView` — mise en page de la capture adoptée, écran dû.** Chantier
ouvert à partir de huit captures de design. Voir la
[spec](docs/superpowers/specs/2026-08-09-habillage-visuel-design.md), le
[plan d'habillage](docs/superpowers/plans/2026-08-09-habillage-vitrine-actions.md) et le
[plan correctif](docs/superpowers/plans/2026-08-09-vitrine-actions-mise-en-page-capture.md).
Branche `feat/habillage-vitrine-actions`, 17 commits.

**Correction de cap en cours de route.** Le premier plan a appliqué le *vocabulaire visuel*
de la capture aux informations existantes sans adopter sa *mise en page* : à l'écran, la
maquette n'était pas reconnaissable. Erreur d'interprétation, pas d'exécution — toutes les
revues étaient vertes. Le second plan corrige : la barre principale est devenue celle de la
capture, les contrôles secondaires sont montés en barre d'outils, la ligne s'est réduite à
cinq éléments avec un menu `⋮` au survol.

Livré : jetons `AppTheme` ; deux règles de date testées — `Urgence` (couleur, seuil sept
jours, 8 tests) et `Portee` (filtrage, 9 tests) ; composants `Avatar`, `MetaValue`,
`SegmentedFilter` (7 tests) ; « Grouper par » branché sur la vue liste avec un axe
« Échéance », les sections réutilisant la même fonction que le kanban.

**Rien n'a été vérifié à l'écran, sauf un survol de l'auteur qui a révélé deux défauts** —
« Grouper par » inopérant en liste (corrigé) et, trouvé dans la foulée par la revue, les
actions terminées rendues invisibles par la portée (corrigé). Une vingtaine de contrôles
restent dus. Trois sont prioritaires :

1. **cliquer `⋮`** — le mécanisme censé l'empêcher de déplier aussi la ligne n'a jamais été
   vérifié ; s'il bloque l'ouverture du menu, Modifier, Commentaires et Supprimer deviennent
   inatteignables sur les actions ouvertes ;
2. **survoler le titre et la case à cocher** — l'apparition de `⋮` dépend d'un `onHover`
   posé sur une vue de fond ; si le suivi ne porte pas au-dessus des sous-vues, même
   conséquence ;
3. **« Filtres → Terminées »** — vérifier que les actions terminées apparaissent bien.

Trois règles de date coexistent : `Urgence` (couleur), `Portee` (filtrage) et les seuils
propres de `taskStatus` (forme de la puce et infobulle, aujourd'hui/demain/48 h). Une action
due demain porte donc une puce « imminente » coloriée en gris « à venir ».

Dettes et arbitrages dus : `ListRow`, nommé par la spec, jamais extrait ; la spec interdit
toute fonction nouvelle alors que le filtre de portée et le groupement en liste en sont ;
l'axe « Échéance » ajouté à `ActionGrouping` fait apparaître un quatrième segment dans
`ActionsPanel`, écran non visé ; onze des vingt jetons d'`AppTheme` n'ont aucun consommateur
(catalogue publié d'avance pour la propagation) ; `CLAUDE.md` ligne 99 impose l'anglais pour
les symboles alors que `Views/DesignSystem/` est en français par décision explicite —
correction impossible tant que `CLAUDE.md` porte des changements non commités du chantier
éditeur ; et **aucun test n'exerce la chaîne de filtres**, où trois défauts ont pourtant été
trouvés.

Prochaine action de ce chantier : la session de vérification à l'écran, en commençant par
les trois contrôles prioritaires ci-dessus.

Le chantier actif est la refonte de l'éditeur Markdown en éditeur de blocs,
à partir du handoff [`design_handoff_editor_blocs/README.md`](design_handoff_editor_blocs/README.md).

- Branche : `feat/editeur-slash-blocs`
- Avance sur `master` : 113 commits
- Source de vérité : le Markdown reste le format stocké
- Moteur d'édition : AppKit / TextKit 1
- État du worktree : plusieurs changements de l'éditeur sont encore non
  commités ; ils ne doivent pas être mélangés avec les changements de
  migration de `OneToOneApp.swift`

## Fusion Note / Réunion (2026-08-10)

Branche `feat/fusion-note-reunion`, 43 commits, **fusionnée dans `master` et poussée** —
constaté le 2026-09-02 : elle n'a plus aucun commit hors `master`.

**Livré.** `MeetingKind.note` et l'exclusion des statistiques (`MeetingStatsScope`) ;
`NoteFactory` ; les onglets et le chrome de `MeetingView` filtrés par kind ; l'indexation
Spotlight des réunions et des notes, avec l'ouverture depuis un résultat ; l'écran « Notes »
et la `NotesSection` des fiches réécrits sur `Meeting` ; la note rapide, la recherche
latérale et le gabarit de rapport repointés ; les commandes `/ajout-*` vers leur modèle
naturel ; `MailProjectMatcher` sur les participants des réunions. **Quatre modèles
supprimés** : `Note`, `NoteAttachment`, `ProjectInfoEntry`, `ProjectCollaboratorEntry` —
sans `SchemaV2`, la prémisse étant que `ZNOTE` est à zéro dans le store réel, ce qui reste
à vérifier (tâche 13, étape 2).

**Huit correctifs issus d'une revue à effort `xhigh`** (14 constats vérifiés, 6 réfutés),
tous en TDD, tous sur le prédicat qui supprime une note vide à la fermeture de l'écran —
suppression *sans* confirmation, là où la suppression explicite passe par un
`confirmationDialog` :

1. le contenu du 1:1 manager (`ManagerMeetingReport`, `ManagerReportItem`,
   `ActionTask.managerMeeting`) était invisible au prédicat, faute de relation inverse sur
   `Meeting` : un 1:1 rapporté basculé sur « Note » était supprimé avec son CR ;
2. le texte tapé dans les 0,3 s avant la fermeture n'atteignait jamais le modèle (débounce de
   l'éditeur non vidé au démontage) : la note était jugée vide et supprimée avec ce qu'on
   venait d'y écrire ;
3. les participants ad hoc, saisis à la main, et les statuts de présence ne comptaient pas ;
4. les colonnes JSON du rapport étaient lues par leurs façades, dont le getter avale toute
   erreur de décodage en `[]` ;
5. `isBeingDeleted` était un `@State` : deux écrans sur la même réunion se supprimaient le
   modèle sous les pieds (`MeetingScreenRegistry` porte désormais le compte et la
   suppression) ;
6. les quatre gardes de relation en cascade n'étaient couvertes par aucun test (table ajoutée,
   vérifiée par mutation) ;
7. l'ordre des gardes faisait fauter toute la transcription avant d'atteindre un scalaire ;
8. cinq commentaires promettaient plus que le code ne tient.

**Non appliqué, à arbitrer.** Le prédicat reste une liste blanche entretenue à la main sur
une partie des propriétés de `Meeting` : une propriété ajoutée demain tombe hors de la garde
sans qu'aucun test n'échoue. Le correctif de fond serait de conditionner la suppression
silencieuse à la **provenance** (« cet écran a créé cette note et rien ne l'a touchée »)
plutôt qu'au contenu. Choix structurant → à proposer en ADR, pas à décider en revue. La
moitié « texte » de la dérive est fermée par `Meeting.textualContent` et son test.

**Vérifié.** `swift test --skip CalendarImportEventTests` : **997 tests XCTest** (1 ignoré,
`CalendarImportEventTests`, crash d'environnement connu) **+ 301 tests Swift Testing, aucun
échec**.

### Tâche 13 — données réelles (2026-08-10, soir)

**Étapes 1, 2, 3 et 5 faites. L'étape 4 — les dix contrôles à l'écran — n'a pas eu lieu.**

**Sauvegarde.** `~/Library/Application Support/OneToOne.backup-2026-08-10-fusion-note`
(`.store` de 33 Mo, dossier complet de 8,7 Go avec enregistrements et pièces jointes).

**La migration avait déjà eu lieu, sans témoin.** Le store réel ne portait plus les quatre
tables au moment du contrôle : `ZNOTE`, `ZNOTEATTACHMENT`, `ZPROJECTINFOENTRY` et
`ZPROJECTCOLLABORATORENTRY` sont **absentes** de `sqlite_master` et de `Z_PRIMARYKEY`, et
`ZMEETING` porte déjà une réunion de kind `note`. L'app avait donc été lancée sur le schéma
de la branche avant cette session (mtime du store : 19:08). Le contrôle de l'étape 2, prévu
comme un préalable, est devenu **rétrospectif**.

**La prémisse tient, établie sur trois instantanés antérieurs à la fusion :**

| Instantané | `ZNOTE` | `ZNOTEATTACHMENT` | `ZPROJECTINFOENTRY` | `ZPROJECTCOLLABORATORENTRY` | `ZMEETING` |
|---|---|---|---|---|---|
| `~/Documents/OneToOne-sauvegarde-notes-2026-08-05` | 0 | 0 | 0 | 0 | 162 |
| `OneToOne.backup-2026-06-06` | 0 | — | 0 | 0 | 108 |
| `OneToOne.backup-2026-04-24` | table absente | — | 0 | 0 | 5 |
| store actuel | table supprimée | table supprimée | table supprimée | table supprimée | 164 |

La sauvegarde du 5 août précède le chantier de cinq jours : les quatre tables étaient vides,
il n'y avait donc **rien à perdre**, et les 162 réunions d'alors sont devenues 164 sans perte.
C'est ce que la note de `SchemaVersions.swift` affirmait ; c'est vérifié indépendamment.

**Étape 3 — la version commitée ouvre le store réel.** `Scripts/bump-and-build.sh dev`,
build 690, lancé après avoir mis de côté la modification non commitée de `OneToOneApp.swift`
(celle qui retire `migrationPlan`), et **restituée aussitôt après**. L'app démarre et tient :
aucune trace de migration ni d'erreur CoreData dans `log show`, le store n'a pas été mis de
côté par la récupération destructive, et les 164 réunions sont toujours là après ouverture.
Effet de bord du script : `Info.plist` passe de `629` à `690` — c'est un fichier que porte
déjà le chantier étranger.

**Étape 5 — suite de tests.** 997 XCTest (1 ignoré) + 301 Swift Testing. **Un échec, horaire
et préexistant** : `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` construit une
réunion à `now + 1h` et la compte dans « aujourd'hui » ; lancé après 23 h, ce `+1h` tombe le
lendemain et le décompte passe de 2 à 1. La même commande passait à 22 h sur le même code, et
aucun commit de la branche ne touche `TodayStatsCalculator`. À corriger un jour en injectant
l'horloge — c'est le second test horaire du fichier après `test_badge_twelve_compact`.

**Étape 4 — trois contrôles déroulés sur onze, le 2026-08-10 au soir.**

| # | Contrôle | Résultat |
|---|---|---|
| 1 | note rapide du menubar → apparaît dans « Notes » | conforme |
| 2 | l'ouvrir → deux onglets, pas de barre d'enregistrement | conforme |
| 3 | bascule vers « One-to-One » → les six onglets reviennent | conforme, **mais** |
| 4–11 | temps passé, fiche collab, fiche projet, Spotlight, nouvelle note, frappe puis fermeture, deux fenêtres, backup/restore | **non déroulés** |

Le contrôle 3 a révélé un manque : la bascule produit un 1:1 **sans interlocuteur**, et rien
dans le fil d'Ariane ne permet de le rattacher à quelqu'un — le seul chemin est Vue
d'ensemble → Présence → « Gérer les participants ». Le manque préexiste à cette branche (le
badge de type était déjà un `Picker` sur tous les types). Traité à part, sur
`feat/pastille-participant-fil-ariane`, voir
[la spec](docs/superpowers/specs/2026-08-11-pastille-participant-fil-ariane-design.md).

**Les contrôles 4 à 11 passent en vérification à l'usage**, décision de l'auteur le
2026-08-11. La tâche 13 n'est donc **pas close** : ce qu'ils couvrent — dont la fermeture
immédiatement après la frappe, seul contrôle qui tranche l'ordre `.onDisappear` /
`dismantleNSView`, et la même note ouverte dans les deux fenêtres — reste non vérifié. Ne
pas écrire ailleurs que ces points sont acquis.

## `master` ne compilait plus depuis le 2026-08-08 (constaté le 2026-08-11)

Constaté en créant un worktree partant de `master` : **42 erreurs de compilation**.
`OneToOne/Markdown/Core/EditorTextView.swift`, commité le 8 août (`8d88197`), appelle une API
dont les définitions étaient restées **non commitées** dans l'arbre de travail de l'auteur —
`TableControlLayout.footerGeometry`, `MermaidBlockLayout.columnWidth`,
`BlockMoveCommands.dragRewrite`, `TableEditCommands.Gesture.addColumnLeft`, entre autres.
Toutes les branches en héritaient : **le seul état compilable du dépôt était cet arbre de
travail**. Conséquence rétrospective à connaître : toutes les suites de tests vertes citées
plus haut ont été lancées sur cet arbre — code de la branche **plus** le chantier éditeur non
commité. Aucun commit n'a jamais été compilé isolément ; ce n'était pas possible.

Réparé sur `fix/build-editeur-mermaid-tables`, partie de `master`, en deux commits : le
vendoring de BeautifulMermaidSwift (MIT) + `elk-swift` (81 fichiers), puis les onze fichiers
de `OneToOne/Markdown/`, `NativeMermaidRenderer.swift` et onze fichiers de test
(+1606 −339). Contenu repris sans modification de l'arbre de l'auteur ; jeu minimal
déterminé par ajouts successifs. Vérifié : `swift build` passe, et
`swift test --skip CalendarImportEventTests` donne 990 XCTest (1 ignoré) + 138 Swift Testing,
aucun échec.

**Fusionné dans `master`** le 2026-08-11 (`4577048..9f18a73`), puis `master` fusionné dans
`feat/fusion-note-reunion` (`8d77c18`). L'arbre de travail est passé de 24 fichiers modifiés
à trois — `CLAUDE.md`, `Info.plist` (bump du script de build) et la modification de
`OneToOneApp.swift` sur `migrationPlan` — le reste étant désormais commité à l'identique.
Contenu vérifié octet à octet contre une sauvegarde prise avant l'opération. La branche
fusion compile pour la première fois seule : 997 XCTest (1 ignoré) + 301 Swift Testing,
aucun échec.

**Ce qui reste ouvert par ailleurs**, laissé tel quel par la spec : le sort de `Meeting.notes`
(champ distinct de `liveNotes`, encore lu par les gabarits de rapport) et le renommage
éventuel de `liveNotes`, dont le nom est un héritage des réunions enregistrées.

**Arbre de travail.** Il porte un chantier étranger non commité (éditeur de blocs, Mermaid
natif, `Services/Agent/`, `Vendor/`) : tous les commits de cette branche sont faits à chemins
explicites.

## Sûreté des données — axe 1 de la revue de mai appliqué (2026-08-09)

Six commits sur `master` (`8401536..d806a4b`), suite verte vérifiée par le coordinateur :
990 tests XCTest (1 ignoré, `CalendarImportEventTests`, crash d'environnement connu)
+ 138 tests Swift Testing, aucun échec.

Applique les trois correctifs de l'axe « sûreté des données » de la
[spec de reprise](docs/superpowers/specs/2026-08-09-revue-code-data-safety-perf-design.md),
issue de la branche `fix/code-review-data-safety-perf` (fusionnée et supprimée le 2026-09-02) :

1. **Dédoublonnage d'identifiants UUID au démarrage.** La règle vit dans
   `Services/IdentifierRepair.swift` (testée hors SwiftData) ; `repairStoreIfNeeded()`
   n'en est que le branchement. `TranscriptChunk.chunkId` est désormais couvert ;
   `SlideCapture.id` l'était déjà.
2. **La désynchronisation audio/transcription est nommée et affichée.**
   `TranscriptEditError.saveFailedAfterAudioCut` remonte jusqu'au bandeau d'erreurs de
   `MeetingView`. Auparavant l'erreur mourait dans un `print`.
3. **Le fichier temporaire est nettoyé sur échec** dans `AudioFileEditor.trim` et `.cut`,
   sur le modèle du `catch` que `split` avait déjà.

**Trois points à connaître, tous relevés en revue :**

**La réparation des identifiants arrive à temps par circonstance, pas par construction.**
`repairStoreIfNeeded()` tourne dans le `onAppear` de `ContentView`, donc après
`applicationDidFinishLaunching`. Elle tient parce qu'aucun code de démarrage ne lit ces
identifiants aujourd'hui. **Le premier qui le fera cassera l'invariant en silence, sans
qu'aucun test ne s'en aperçoive.**

**`deleteSegment` sauvegarde le contexte partagé avant de couper l'audio.** C'est
volontaire et cela fait deux choses : le `rollback()` de fin ne peut plus emporter la
saisie en cours d'un autre champ (`MeetingView` a une sauvegarde différée de 0,6 s sur
`summary`, `referencedAbsent`, `nextDeadline`), et un store non inscriptible est découvert
**avant** la coupe irréversible.

**Le chemin d'échec de `context.save()` n'est couvert par aucun test.** Un test sur store
fichier rendu non inscriptible serait possible mais fragile (WAL SQLite). Le comportement
du `rollback` n'est vérifié que par lecture de code.

**Reste dû :** les huit autres correctifs de la spec (axes « fil principal » et
« robustesse des entrées »), volontairement non traités à l'époque. **Soldé le 2026-09-02** :
la branche `fix/code-review-data-safety-perf` a été fusionnée (`ee8a4b3`) puis supprimée.
Six de ces correctifs sont entrés dans `master` ; les autres avaient été **dépassés** par du
code écrit depuis, en mieux — voir la section en tête de ce fichier pour le détail de la
résolution, conflit par conflit.

---

## Éditeur de blocs

### Diagrammes Mermaid

Le cycle complet est implémenté :

1. placeholder de chargement compact ;
2. diagramme rendu dans une carte sobre ;
3. barre d'actions au survol avec modification et duplication ;
4. source ouvert dans un cadre avec en-tête, numéros de ligne et bouton
   « Terminé » ;
5. carte d'erreur avec message et bouton « Ouvrir le source ».

Le rendu Mermaid a été repris pour un résultat plus professionnel : thème
clair/sombre dédié, espacements cohérents, libellés SVG natifs compatibles
avec `NSImage`, connecteurs fins et pointes de flèche stables dans AppKit.

Le chemin principal utilise désormais une copie locale modifiable de
BeautifulMermaidSwift 1.0.4 (`Vendor/BeautifulMermaidSwift`, licence MIT,
commit amont documenté dans son `README.md`) et ELK Swift 1.0.2. Le rendu est
natif AppKit/CoreGraphics, sans WebView pour les six familles prises en
charge. Le moteur Mermaid JavaScript emballé reste le fallback des syntaxes
non reconnues par le parseur natif. Une correction locale retourne le
contexte bitmap AppKit : l'amont produisait sinon une image verticalement
inversée sur macOS.

Défauts corrigés :

- `-->` n'est plus transformé en tiret cadratin par AppKit ;
- le source est masqué pendant l'aperçu ;
- seule la première ligne réserve la hauteur de l'image ;
- la hauteur est recalculée après le rendu asynchrone ;
- l'ancien cadre est invalidé immédiatement puis au cycle AppKit suivant
  lors du passage aperçu/source ;
- le hit-test suit maintenant le rectangle réellement peint au lieu du
  caractère TextKit sous la souris. Le bouton « Ouvrir le source » reste donc
  cliquable même lorsque l'image déborde encore de sa ligne réservée ;
- la borne de fin d'un bloc ouvert est désormais **incluse**
  (`MermaidBlockLayout.selectionTouches`) : flèche droite, Fin ou un clic en
  bout de ligne laissent le bloc en édition et une frappe s'ajoute à la fin
  du source ; « Terminé » place le curseur au-delà du séparateur (un `\n`
  est inséré si le bloc clôt le document) et reste le seul geste qui
  referme le bloc — l'ancien contournement souris (`openSelectionLocation`)
  est supprimé, devenu inutile ;
- la carte Mermaid terminée, le placeholder et l'erreur utilisent désormais
  la largeur de colonne commune (960 pt) et le SVG est centré à l'intérieur ;
- la première ligne du source Mermaid utilise une hauteur TextKit normale :
  l'en-tête est réservé par l'espacement de paragraphe, ce qui évite un
  curseur vertical surdimensionné ;
- l'en-tête d'un bloc Mermaid ouvert élargit temporairement le clip de dessin
  au conteneur TextKit : celui du second bloc reste visible lorsqu'il suit une
  carte Mermaid haute ;
- les parseurs natifs vendored (flowchart/state, sequence, class, er,
  xychart) **jettent** désormais sur toute ligne non consommée
  (`autonumber`, `activate` seul, `click`, notes, `style`…, commentaires
  `%%` exceptés) au lieu de l'ignorer en silence : le rendu natif échoue et
  `MermaidRenderer` retombe sur le moteur JavaScript compatible — plus
  d'image incomplète mise en cache (patch local documenté dans
  `Vendor/BeautifulMermaidSwift/README.md`) ;
- la barre d'actions du diagramme fermé expose « Modifier » et « Dupliquer » ;
  la duplication conserve le bloc Markdown complet et ses attributs visuels ;
- `/diagramme` insère un squelette complet et valide :

  ```mermaid
  flowchart TD
      A[Début] --> B[Fin]
  ```
- le squelette inséré n'est plus sélectionné en entier : le curseur est placé
  après le bloc, qui se rend immédiatement, et une première frappe ne peut
  plus effacer tout le source ;
- les frappes caractère par caractère, le remplacement d'une sélection
  interne et l'édition près du dernier caractère conservent désormais
  strictement le reste du source et le Markdown sérialisé ;
- le bloc mermaid **ouvert** affiche son propre diagramme dans son cadre, au-dessus
  du source (bande plafonnée à 240 pt, `MermaidSourceLayout.previewMaximumHeight`) :
  l'image est celle de la dernière fermeture, **jamais** un rendu relancé à la
  frappe — le correctif de superposition du 2026-08-08 reste intact.

**Double liseré de l'aperçu.** L'image de l'attachment porte déjà son propre
cadre arrondi et son liseré, à la largeur de la colonne ; ils tombent donc
exactement sur ceux de la carte. C'est **systématique**, pour le diagramme
rendu, le cadre d'erreur et le placeholder — ce n'est pas une hypothèse.
Point d'esthétique laissé au jugement de l'auteur.

**Cause racine de la carte peinte par-dessus le bloc précédent — trouvée et
corrigée (2026-08-08).** Une revue finale a jugé le chantier non fusionnable
et a cherché plus loin : la cause est un défaut **antérieur au chantier**.
Fait mesuré (script conservé :
`docs/mesures/mesure-textkit.swift`) :
en TextKit 1, `lineFragmentRect` **inclut** l'espace réservé par
`paragraphSpacingBefore` et `paragraphSpacing` ; c'est `lineFragmentUsedRect`
qui commence au sommet du texte. Toute la géométrie de la carte d'un bloc
mermaid ouvert s'ancrait sur le rect de fragment, et se peignait donc
au-dessus du bloc précédent, d'un montant égal à la bande réservée. Ce défaut
précède le chantier : avec l'ancienne bande de 43 pt, l'en-tête remontait
déjà de 43 pt dans le bloc du dessus. C'est l'explication du constat qui a
lancé le chantier (« on ne voit pas qui appartient à qui »), que la
spécification avait mal diagnostiqué comme un simple problème d'écart.

Second fait mesuré (`mesure-f2-leviers.swift`, `mesure-f2-delegue.swift`) :
TextKit 1 **ignore** `paragraphSpacingBefore` sur le premier paragraphe du
conteneur. Un bloc mermaid en tête de note ne réservait donc rien : en-tête
invisible, bouton « Terminé » incliquable — également un défaut préexistant.
Corrigé par un délégué `paragraphSpacingBeforeGlyphAt` **passe-plat**, qui
relit l'attribut dans le storage et le renvoie : mesuré neutre partout
ailleurs. À noter, car contre-intuitif : le délégué **remplace** la valeur de
l'attribut au lieu de s'y ajouter.

Six correctifs, tous relus :

1. `1ea10a4` — toute la géométrie de la carte ouverte ancrée sur
   `lineFragmentUsedRect` (cadre, en-tête, aperçu, bouton « Terminé », numéro
   de ligne de la gouttière). Mesures : distance bas du cadre → bas du
   source 38 → 10 pt ; écart visible sous la carte −10 → +18 pt. Emporte
   aussi deux défauts de même cause : la puce du dernier item d'une liste
   voisine d'une carte décrochait d'environ 9 pt, et le filet de citation
   courait jusqu'à 28 pt sous sa dernière ligne.
2. `c009c64` — bande réservée pour un bloc mermaid ouvert en tête de note
   (délégué ci-dessus).
3. `72a4bd6` — le restylage inclut désormais le bloc **précédent**, qui
   porte l'écart inter-blocs : sans cela, `/tableau` et `/diagramme`
   n'aéraient pas le bloc au-dessus d'eux jusqu'au prochain restylage.
4. `b5aa506` — la bande réservée est recalculée quand un rendu aboutit sur
   un bloc **ouvert** : la réservation était calculée sur le placeholder
   pendant que le dessin utilisait le diagramme livré entre-temps (144 pt de
   débord).
5. `96c1119` — l'écart visible sous une carte vaut désormais celui du
   dessus (28 pt des deux côtés ; auparavant 18 en dessous, le `max`
   absorbant le padding intérieur).
6. `8d88197` — quatre points de solidité : le hit-test des cases à cocher
   s'ancre sur le texte (avant : cliquer dans le **vide** sous le dernier
   item d'une checklist voisine d'une carte cochait la case) ; la somme
   `headerHeight + previewHeight + bodyTopPadding` a un point d'entrée
   unique, `MermaidSourceLayout.reservedBandHeight` ; la fabrique de test de
   géométrie est refermée derrière `#if DEBUG` ; le test de mise en page
   passe par le vrai chemin de dessin.

Le test qui manquait, et qui a été ajouté : sur un éditeur réellement mis en
page (`ensureLayout`), le cadre calculé doit tenir dans l'espace vertical du
bloc et ne jamais remonter au-dessus du bloc précédent. Les tests antérieurs
étaient tous algébriquement auto-cohérents et ne mettaient jamais en page un
storage réel — c'est pour cela que le défaut est passé. Vérifié : en
revenant au rect de fragment, quatre assertions repassent au rouge.

**La vérification à l'écran n'a pas eu lieu.** L'application n'a pas été
lancée, aucun rendu n'a été observé. Tout ce chantier repose sur des mesures
de mise en page. Contrôles restants à l'écran : les deux blocs mermaid
encadrant un bloc ouvert, un bloc en tête de note, un source invalide (cadre
d'erreur dans la bande), la frappe longue dans un bloc ouvert sans
superposition, le clic sur « Terminé », le redimensionnement de fenêtre bloc
ouvert, la densité générale d'une note enchaînant plusieurs cartes, et le
confort de lecture d'un diagramme réduit au plafond de 240 pt.

**Superposition carte/source pendant l'édition — cause racine trouvée et
corrigée (2026-08-08).** Constat d'écran : la carte rendue (ou le cadre
d'erreur « Parse error ») se peignait par-dessus/sous le source ouvert
pendant la frappe, sans laisser le temps de cliquer « Terminé ». Mécanisme
mesuré : chaque frappe dans un bloc ouvert relançait un rendu du source
**incomplet** (le natif strict jette → `WKWebView` à chaque caractère) et
chaque completion en vol rejouait `refreshClosedMermaidGeometry` avec une
plage **capturée au lancement** — périmée dès que le bloc avait grandi, la
garde « bloc encore ouvert ? » échouait et la géométrie fermée s'appliquait
sur le bloc en édition. Double correctif :

1. `StyleRenderer.applyMermaidAttachment` ne crée plus d'attachment ni ne
   lance de rendu tant que le bloc est ouvert — l'attachment existant est
   reposé tel quel (même instance, run uniforme) et le rendu du source
   final part à la fermeture ;
2. `refreshClosedMermaidGeometry` retrouve le bloc par l'**identité** de
   son attachment au moment où le rendu aboutit (attachment absent = rendu
   périmé, no-op) — plus jamais par une plage figée.

Trois tests de régression dans `StyleRendererMermaidTests` (identité de
l'attachment pendant l'édition, completion périmée après croissance du
bloc, attachment remplacé). L'effacement visuel de l'ancienne carte doit
encore être confirmé à l'écran après relance complète de l'application.

### Tableaux

`/tableau` insère une grille de trois colonnes, une rangée d'en-tête et deux
rangées de corps. Les libellés `Colonne 1`, `Colonne 2`, `Colonne 3` sont des
placeholders visuels et ne sont pas sérialisés.

Fonctions disponibles :

- grille `NSTextTable` à colonnes fixes et cellules de hauteur stable ;
- curseur placé dans la première cellule ;
- ajout d'une ligne sous la ligne active ;
- suppression de la ligne active ; si l'en-tête est sélectionné, suppression
  de la dernière ligne de corps ;
- ajout d'une colonne à gauche ou à droite ;
- suppression d'une colonne avec garde sur la dernière colonne ;
- permutation de lignes et colonnes avec annulation/rétablissement ;
- barre de pied `+` / `-`, compteur lignes/colonnes et action d'ajout de
  colonne ;
- menu de colonne depuis l'en-tête.

Le tri ascendant et descendant apparaît dans le menu, mais reste un `TODO`
dans `EditorTextView`.

En lecture seule (`.markdownReadOnly(true)`), les contrôles de tableau sont
entièrement inertes : `activeTableInView` (point d'entrée partagé
dessin/interaction) refuse un éditeur non éditable — ni pied `+`/`−`, ni
menu de colonne — et `keyDown` écarte les raccourcis ⌘⌥/⌘⌥⇧/⌘⌥⌃ + flèche
avant d'atteindre les handlers (P2 revue Codex).

### Manipulation des blocs

La gouttière gauche appartient désormais au bloc et ne recouvre plus ses
contrôles internes.

Implémenté dans le worktree :

- apparition au survol des boutons d'insertion et de poignée ;
- clic sur `+` : insertion d'une ligne `/` au-dessus du bloc ;
- clic sur la poignée : sélection du bloc et menu contextuel ;
- menu Monter, Descendre, Dupliquer, Modifier le source et Supprimer ;
- clic droit routé par le menu contextuel natif AppKit, ancré au point du
  clic même lorsque l'éditeur est décalé dans sa fenêtre ;
- déplacement clavier avec `⌥↑` / `⌥↓` ;
- glisser-déposer avec bloc atténué et trait bleu entre les blocs ;
- cadre bleu distinct de la sélection textuelle.
- espacement vertical de 10 pt à la fin de chaque bloc logique, porté à 28 pt
  (`BlockGutterLayout.cardBlockSpacing`) dès qu'un des deux blocs voisins dessine
  un cadre — mermaid, tableau, image, bloc de code. Seul `paragraphSpacing` le
  porte : y ajouter `paragraphSpacingBefore` doublerait l'écart, TextKit
  additionnant les deux.

Correctifs issus de la revue Codex du 2026-08-08 (P1) :

- la réécriture du glisser-déposer est extraite en fonction pure
  (`BlockMoveCommands.dragRewrite`) qui normalise le séparateur : déplacer
  le **dernier** bloc (sans `\n` final) ou déposer **en fin** de document
  ne colle plus deux blocs sur la même ligne (`"A\nB"` → `"BA\n"`, corrigé
  et couvert par 5 tests) ;
- le constat « pas d'undo sur les mutations de bloc » est **réfuté par
  l'expérience** : le bracket `shouldChangeText`(remplacement non
  nil)/`didChangeText` avec `allowsUndo` enregistre nativement l'inverse
  **attribué** (`md*` compris) — suppression, duplication, insertion `/` et
  drag avaient déjà un ⌘Z fonctionnel. Mesuré et verrouillé par
  `EditorTextViewBlockMutationUndoTests` (6 tests) ; le patron est
  centralisé dans `EditorTextView.replaceBlockCharactersRegisteringUndo`,
  dont la doc explique pourquoi il ne faut **pas** ajouter de
  `registerUndo` manuel par-dessus (inverse enregistré en double, mesuré).
  `swapAdjacentBlocks`/`applyTaskToggle` restent des cas différents : ils
  n'appellent pas le bracket.

Correctifs P2 de la même revue (lecture seule) :

- clic droit : menu natif d'AppKit, jamais le menu de bloc mutable ;
- gouttière : `blockGutterHit` refuse un éditeur non éditable (poignée `⠿`
  et `+` inertes) et le survol ne peint plus les affordances d'édition ;
- `BlockMoveCommands.moveUp/moveDown` portent la garde d'éditabilité
  (couvre ⌥↑/⌥↓ **et** Monter/Descendre du menu, qui mutent sans bracket
  `shouldChangeText`).

Côté images (P2) : `ImageAttachmentFactory.maxWidth` revient à **480 pt**
(limite des images ordinaires, jamais réajustées au conteneur par TextKit)
et la colonne mermaid a sa propre constante
`MermaidBlockLayout.columnWidth = 960` consommée par
`MermaidAttachmentFactory` — le passage global à 960 clippait les images
dans les éditeurs de 300–600 pt et cassait
`ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
(reverdi par ce découplage).

Le déplacement clavier est couvert par les tests existants. Le glisser-déposer
réel et le menu de bloc doivent encore être vérifiés dans une fenêtre AppKit,
notamment le dépôt après le dernier bloc et la conservation de la sélection.

## Fonctions Markdown déjà livrées

| Fonction | État |
|---|---|
| Menu `/` | 17 commandes, panneau limité à huit lignes visibles |
| Raccourcis à la frappe | `# `, `- `, `1. `, `> `, `[] `, `---` |
| Listes | marqueurs, cases cliquables, ⏎, Tab, ⇧Tab et ⌫ |
| Mentions `@` | recherche, création et ouverture de la fiche |
| Citations | filet vertical |
| Images | affichage, collage et déplacement |
| Liens | liens externes et routage interne injecté |
| Dates | popover avec date et heure |
| Blocs | sélection, menu, clavier et drag en cours de validation |

L'aller-retour Markdown a été vérifié auparavant sur 119 notes réelles,
sauvegardées dans `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`.

## Validation du 2026-08-08

Commandes passées sur le code actuel :

- `swift build` : **réussi** ;
- vérification ad hoc temporaire : **code de sortie 0**, script supprimé
  automatiquement ;
- `swift test --filter MermaidBlockLayoutTests/test_openSelectionLocation_atExclusiveEnd_isMovedBackInsideBlock` :
  **1 test, 0 échec** ;
- `swift test --filter MermaidSourceLayoutTests` : **8 tests, 0 échec** ;
- `swift test --filter Mermaid` : **82 tests, 0 échec** ;
- `swift test --filter Mermaid` après intégration native : **88 tests,
  0 échec**, dont 3 scénarios d'édition sans perte et le rendu bitmap natif ;
- `swift test --filter EditorTextViewMermaidClickTests` : **11 tests,
  0 échec** ;
- `swift test --filter SlashControllerTests` : **81 tests, 0 échec**, dont
  le nouveau test du squelette `/diagramme` ;
- `swift test --filter BlockGutterLayoutTests` : **4 tests, 0 échec**, dont
  le menu contextuel dans une fenêtre décalée ;
- `swift test --filter BlockGutterLayoutTests --filter StyleRendererTests
  --filter MarkdownTableRenderingTests --filter TableControlLayoutTests
  --filter SlashControllerTests` : **158 tests, 0 échec** ;
- capture native générée et inspectée : orientation corrigée, « Début » au-
  dessus de « Fin », flèche descendante, texte lisible ;
- `BuiltInTemplatesTests` : **4 tests, 0 échec** lorsqu'ils sont lancés avec
  la suite Slash.

Prochaine action : vérifier visuellement dans l'application la visibilité de
l'en-tête du second bloc et le clic sur le dernier caractère sans passage au
rendu ; « Terminé » doit rester l'action explicite.

## Validation du 2026-08-08 (correctifs P1 revue Codex)

- `swift test --filter Mermaid --filter BlockMoveCommandsTests
  --filter BlockGutterLayoutTests --filter EditorTextViewBlockMutationUndoTests` :
  **139 tests, 0 échec** (dont 5 `dragRewrite`, 6 undo, 7 parseurs stricts,
  4 `openBlockRange`, 2 `doneCaretPlacement`) ;
- balayage éditeur large (`SlashControllerTests`, `StyleRendererTests`,
  `TableControlLayoutTests`, `TableEditCommandsTests`,
  `MarkdownTableRenderingTests`, `ListEditingCommandsTests`,
  `EditorTextView*`, `EditorRepresentable*`, `BlockRangeTests`) :
  **312 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : la partie Swift Testing
  passe (**138 tests, 24 suites**) et, contrairement au constat précédent,
  l'exécution globale XCTest est allée au bout (pas de signal 6) avec
  **2 échecs préexistants étrangers aux correctifs** :
  `ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
  (échec introduit par le changement **non commité** de `maxWidth` dans
  `ImageAttachmentFactory.swift` — vérifié : le test passe sur HEAD une
  fois le worktree remisé) et `MenuBarStatsTests.test_badge_twelve_compact`
  (test de barre de menu dépendant de l'heure, limite déjà connue).

## Validation du 2026-08-08 (correctifs P2 revue Codex)

- suites lecture seule et largeurs (`TableControlLayoutTests`,
  `TableEditCommandsTests`, `BlockGutterLayoutTests`,
  `BlockMoveCommandsTests`, `MermaidAttachmentFactoryTests`,
  `ImageAttachmentFactoryTests`, `StyleRendererTests`) : **0 échec**, dont
  6 nouveaux tests lecture seule et le `test_scaledHeight` reverdi ;
- balayage éditeur large (mêmes suites que la validation P1) :
  **325 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : exécution globale au bout,
  **un seul échec restant**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, limite connue hors chantier).

Séparation du hunk de migration (P2) : le retrait du
`OneToOneMigrationPlan` explicite dans `OneToOneApp.swift` reste dans le
worktree mais ne doit **pas** partir avec la PR éditeur — au moment du
commit, exclure `OneToOneApp.swift` (et le porter ensuite sur une branche
dédiée, ex. `git stash push -- OneToOne/OneToOneApp.swift` puis pop sur la
nouvelle branche). Une PR = une intention.

Prochaine action : vérifier en fenêtre réelle le nouveau geste « Terminé »
(curseur au-delà du séparateur, insertion du `\n` en fin de document), la
frappe en fin de source d'un bloc ouvert, et l'apparence d'une note en
lecture seule (aucune affordance de bloc/tableau) ; puis découper les
commits de la branche en excluant `OneToOneApp.swift`.

Correctif superposition/rendu en cours de frappe : validé par
`StyleRendererMermaidTests` (17 tests) et un balayage éditeur de 311 tests,
0 échec ; app dev reconstruite et installée (build 573) pour vérification à
l'écran du scénario exact (frappe longue dans un bloc ouvert, puis
« Terminé »).

Dernière mise à jour : 2026-08-08 09:14 CEST.

La commande globale `swift test` ne fournit pas actuellement un verdict
exploitable : le processus `xctest` termine avec le signal 6 pendant
l'exécution globale, sans assertion en échec dans les suites de l'éditeur.
Le phénomène est reproductible hors sandbox. Les suites voisines
`BuiltInTemplatesTests`, `SlashControllerTests` et toutes les suites Mermaid
passent lorsqu'elles sont lancées séparément.

Autres limites historiques du harnais :

- `CalendarImportEventTests` peut planter dans l'environnement de test
  (`bundleProxyForCurrentProcess is nil`) ;
- `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` dépend de l'heure :
  il place un créneau entre +2 h et +3 h après minuit et échoue donc si la suite
  est lancée entre minuit et 3 h du matin ;
- `MenuBarStatsTests.test_badge_twelve_compact` **a été supprimé le 2026-08-09**.
  Il était décrit ici comme dépendant de l'heure : c'était faux. Il affirmait
  `" ●12"` pour `hasOverdue: true`, alors que `MenubarBadgeText.suffix` rend
  volontairement `" ⚠12"` — son commentaire de code documente ce choix. Attente
  périmée, pas problème d'horloge. Conséquence à connaître : le glyphe `⚠` du cas
  « au moins une action en retard » n'a plus aucun test ;
- un test de montage de transcription est intermittent.

## Validation du 2026-08-08 (tâche 6 — aération des blocs-cartes et aperçu figé du bloc mermaid ouvert)

- `swift test --skip CalendarImportEventTests` : suite Swift Testing —
  **138 tests, 24 suites, 0 échec** ; suite XCTest — **940 tests, 1 test
  ignoré, 1 seul échec**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, préexistant, déjà documenté ci-dessus). Aucune
  régression du chantier.

**Étape 2 (`Scripts/bump-and-build.sh dev`) et étape 3 (vérification à
l'écran) n'ont pas été exécutées dans cette session** : elles demandent une
session graphique et un œil humain. Le chantier n'est donc **pas** validé
visuellement. Reste à faire, dans une note contenant, dans l'ordre, un
paragraphe, un bloc mermaid valide, un second bloc mermaid valide, un
tableau, après rendu des deux diagrammes puis clic dans le source du
**second** bloc :

1. les deux cartes rendues et le tableau sont nettement séparés (28 pt) ;
   deux paragraphes de texte restent serrés ;
2. le bloc ouvert affiche, dans son propre cadre : en-tête `mermaid` +
   « Terminé » en haut, puis son diagramme, puis un filet, puis le source
   numéroté ;
3. l'en-tête ne touche plus le cadre du bloc précédent ;
4. frapper plusieurs caractères dans le source : l'aperçu ne bouge pas et
   aucune carte ne se superpose au source ;
5. cliquer « Terminé » : le bloc se referme et le diagramme se met à jour ;
6. répéter avec un bloc mermaid placé en tout début de document ;
7. répéter avec un source volontairement invalide (`flowchart TD` puis
   `((((`) : le cadre d'erreur doit s'afficher dans la bande d'aperçu ;
8. redimensionner la fenêtre pendant qu'un bloc est ouvert et noter le
   comportement (limite connue ci-dessus).

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener les huit contrôles ci-dessus à
l'écran.

Dernière mise à jour : 2026-08-08 11:49 CEST.

## Validation du 2026-08-08 (revue finale — cause racine de la bande réservée)

Une revue finale a jugé le chantier non fusionnable et trouvé la cause
racine décrite dans « Diagrammes Mermaid » ci-dessus. Six correctifs
(`1ea10a4`, `c009c64`, `72a4bd6`, `b5aa506`, `96c1119`, `8d88197`), tous
relus.

- `swift test --skip CalendarImportEventTests` : **957 tests exécutés, 1
  ignoré, 1 seul échec** — `MenuBarStatsTests.test_badge_twelve_compact`,
  préexistant et dépendant de l'heure (documenté plus haut) ;
- `swift build -c release` : **réussi**.

**La vérification à l'écran n'a toujours pas eu lieu.** Elle reste entière,
avec les huit contrôles listés dans la section « Validation du 2026-08-08
(tâche 6) » ci-dessus, complétés par : la frappe longue dans un bloc ouvert
sans superposition, le clic sur « Terminé », et la densité générale d'une
note enchaînant plusieurs cartes.

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener à l'écran, dans l'ordre, les
huit contrôles de la section « tâche 6 » et les trois contrôles ajoutés
ci-dessus. C'est la seule chose qui manque avant de considérer ce chantier
fusionnable ; tout le reste (géométrie, tests, build release) est déjà
vérifié.

Dernière mise à jour : 2026-08-08 16:32 CEST.

## Dette immédiate

1. Vérifier à l'écran, après relance, le scénario exact de la dernière
   capture : carte d'erreur, clic sur « Ouvrir le source », disparition de la
   carte et édition du source.
2. Tester le glisser-déposer réel de blocs dans une `NSWindow`, y compris les
   première et dernière positions.
3. Implémenter ou retirer les commandes de tri du menu de colonne.
4. Ajouter les tests manquants de `/sommaire` : document sans titre, doublons,
   niveaux, aller-retour et héritage des attributs de frappe.
5. Stabiliser l'exécution globale XCTest + Swift Testing avant de considérer
   la suite complète comme verte.
6. Tester les diagrammes Mermaid hors des six familles natives (ou utilisant
   HTML, callbacks, tooltips et styles avancés) pour confirmer visuellement
   le fallback JavaScript sur un corpus de notes réelles.

## Défauts connus hors chantier

- le rappel choisi dans le popover de date n'est pas encore persisté ni
  déclenché ;
- mentions et dates utilisent encore largement le rendu des liens ordinaires ;
- `InlineHTML` n'est pas pris en charge par le parser ;
- l'emphase imbriquée complexe ne fait pas toujours un aller-retour strict ;
- le dépôt « à droite pour créer des colonnes de blocs » n'a pas d'équivalent
  Markdown et n'est pas prévu ;
- la poignée de gouttière d'un bloc mermaid **ouvert** s'aligne sur la première
  ligne de source, donc à côté du source et non en haut du cadre : elle se cale
  sur les rects de ligne, et la bande en-tête/aperçu vit dans l'espacement de
  paragraphe, hors ligne ;
- la hauteur réservée à la bande d'aperçu est calculée avec la largeur de colonne
  connue **au moment du stylage** : redimensionner la fenêtre pendant qu'un bloc
  est ouvert peut laisser un léger vide (ou un léger recouvrement) sous l'aperçu
  jusqu'au prochain restylage du bloc.

Issus des six correctifs de la revue finale (2026-08-08) :

- `MainActor.assumeIsolated` **élargi** : l'assertion d'isolation s'exécute
  désormais à chaque restylage ciblé, non plus seulement quand un bloc
  mermaid figure dans la plage. Aucun appelant actuel n'est hors fil
  principal, mais la surface d'exposition a grandi ;
- coût du restylage étendu : chaque frappe restyle aussi le bloc précédent.
  Sous un tableau, cela reconstruit son `NSTextTable` ; sous un bloc mermaid
  fermé, cela re-pose l'attachment. Le cache d'attachments évite le rendu,
  sauf éviction du `NSCache` — auquel cas un rendu peut repartir, pour un
  bloc **fermé** uniquement ;
- couverture : le cas tableau de l'écart sous une carte n'a pas de test de
  garde, et la symétrie 28/28 est prouvée en deux morceaux dont l'un pose la
  valeur à la main ;
- état mixte au chargement : ouvrir une note qui se termine par un bloc
  mermaid le style « fermé » alors que le curseur le touche. Antérieur à ce
  chantier ; l'effet net des correctifs y est positif (la bande est enfin
  réservée), mais l'état mérite un passage.

## Décisions structurantes

1. ~~Le Markdown reste la source de vérité ; aucun modèle de blocs persistant
   séparé n'est introduit.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
2. ~~TextKit 1 est conservé. Les marqueurs de liste et les contrôles sont
   dessinés par les composants AppKit existants.~~ **Annulée le 2026-08-08**
   par [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
3. Les couleurs libres ne sont pas sérialisées : pas de HTML inline ajouté
   uniquement pour la présentation.
4. ~~Aucun code AppFlowy n'est repris ; la référence sert uniquement au design
   et aux comportements.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
5. Les liens internes restent routés par une closure injectée dans l'éditeur.
6. BeautifulMermaidSwift est vendored comme cible SwiftPM locale afin de
   permettre les correctifs macOS et l'évolution du style dans ce dépôt ;
   ELK Swift reste une dépendance distante verrouillée en 1.0.2.
