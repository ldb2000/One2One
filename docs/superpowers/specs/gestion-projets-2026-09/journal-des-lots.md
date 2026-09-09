# Journal des lots — refonte de la gestion des projets (2026-09)

Un compte rendu par lot, du plus ancien au plus récent. `STATUS.md` n'est mis à jour qu'au
dernier lot du chantier : ce fichier tient l'état intermédiaire, pour que la synthèse ne soit
pas réécrite sept fois.

- Handoff (autorité sur le rendu) :
  `docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md`, sept captures 2× sous
  `handoff/screenshots/`.
- Spécification d'exécution (autorité sur l'intégration), constats §2 et décisions D0–D18 §3 :
  `docs/superpowers/specs/2026-09-09-gestion-projets-design.md`.
- Plan par lots : `docs/superpowers/plans/2026-09-09-gestion-projets.md`.
- Décisions structurantes : `docs/adr/2026-09-09-routeur-de-navigation.md` (D0).

---

## Lot 0 — Routeur, socle et semis (2026-09-09)

Branche `feat/projets-lot-0-routeur`, sur `master` (`15c6c2f`). **Aucun rendu changé** : ce lot
n'a pas d'écran de recette, et la comparaison au pixel commence au lot 1.

**État : livré, `swift build` propre (aucun avertissement nouveau), `swift test` complet vert —
**2 125 Swift Testing / 264 suites + 1 057 XCTest (1 ignoré) = 3 182**, 0 échec, soit **+71
tests et +6 suites** sur les 3 111 du 2026-09-08, aucun retiré.

### Commits

| Commit | Intention |
| --- | --- |
| `800fc5a` | `feat(design)` — les trois jetons D12 : `paletteShadow` (+ son rayon), `highlight`, `dashedBorder` |
| `cb82456` | `feat(projets)` — socle : `Project.pinned`, `AppSettings.portfolioSavedViewsJSON`, les quatre enums D14, `RecentProjects` |
| `c07d1ab` | `feat(navigation)` — `MainRoute` / `MainRouter` / `MainDetailView`, barre latérale à sélection, largeur D13, `MenuBarController` |
| `5094a33` | `feat(projets)` — semis Portfolio : 62 actifs, 14 archivés, 8 entités |
| `fc7d484` | `feat(recette)` — `RecetteScreen.Cible.fenetrePrincipale` et les six codes préfixés `p` |
| `75ef9b5` | `docs` — ADR D0, §8 d'`architecture.md`, manifeste, registre, ce journal |
| `222056c` | `test(recette)` — le garde-fou des douze codes ne compte que les écrans de réunion |
| `1343405` | `fix(recette)` — `portfolioPaletteQuery` en `nonisolated`, comme l'identifiant du projet |

### Ce qui est en place

- **`OneToOne/Views/Navigation/`** : `MainRoute` (16 cas), `MainRouter` (`@Observable`,
  `.shared`, histoire bornée à 20, récents, terme de palette en attente), `MainDetailView`
  (`switch` total, invites « Bientôt : … » pour les cinq écrans à venir).
- **`Views/Sidebar.swift`** : les onze `NavigationLink` sont devenus des lignes taguées d'une
  `MainRoute` dans une liste à sélection. Contenu et rendu inchangés. `ContentView` injecte le
  routeur et passe la colonne à `170 / 250 / 320` (D13).
- **`MenuBarController`** : `SearchPopover.onSelectProject`, jusqu'ici un no-op commenté
  « future: deep-link », ouvre le projet.
- **`Services/Project/`** : `ProjectPhase`, `ProjectStatus`, `ProjectType`, `RiskLevel` (D14,
  non persistées, `init?(raw:)` insensible à la casse et aux accents) ; `RecentProjects` (D4) ;
  `PortfolioSavedView` / `PortfolioFilters` / `PortfolioSort` (D4, `Codable`).
- **Modèles** : `Project.pinned: Bool = false` et
  `AppSettings.portfolioSavedViewsJSON: String = "[]"` + accesseur à repli `[]`. **Aucun
  `SchemaV4`** : deux colonnes à valeur par défaut, migration légère (constat §2.23).
- **Jetons D12** dans `One2OneTokens.swift`, seul fichier qui nomme une couleur.
- **Recette** : `RecetteScreen.Cible.fenetrePrincipale(MainRoute)` et les six codes `p2b`,
  `p1a`, `p1c`, `p1d`, `p1f`, `p2a` (D6). Le semis du portefeuille est branché sur les **deux**
  points d'entrée : `ouvrirEcranDeRecette` et l'item de menu « Charger le jeu de démonstration
  (refonte) ».
- **Semis** : `RefonteDemoSeed+Portfolio.swift`, idempotent par `Project.code`, dates relatives
  au jour du semis.

### Tests ajoutés

`MainRouterTests` (13), `RecentProjectsTests` (9), `ProjectPhaseTests` (9),
`PortfolioSavedViewTests` (9, dont le JSON corrompu), `RefonteDemoSeedPortfolioTests` (20),
`RecetteScreenTests` (9) — soixante-neuf tests dans six suites nouvelles. Étendus : `One2OneTokensTests` (+2, contraste du surlignage),
`RefonteTypographieTests` (périmètre + `Views/Navigation` et `Views/Project`, D17),
`SchemaV3MigrationTests` (+2, défaut de `pinned`, aucun modèle nouveau).

Un garde-fou existant a dû être **corrigé et non contourné** :
`RefonteVague5IntegrationTests` figeait `RecetteScreen.allCases.count == 12`. Les six écrans de
fenêtre principale le faisaient tomber sans rien dire de faux — ils n'ouvrent aucune réunion,
et c'est ce que le test gouverne. Il filtre désormais sur la cible, et ce qu'il tient reste
exact.

### Écarts et décisions prises

1. **`MainRoute.entity` prend un `PersistentIdentifier`, pas un `UUID`.** `Entity` n'a pas de
   `stableID`, et lui en ajouter un aurait été un changement de modèle dans un lot qui ne
   change aucun rendu. Détaillé dans l'ADR.
2. **`MainRoute.entity` n'a pas encore d'appelant.** La seule destination `EntityDetailView`
   du dépôt est un `NavigationLink` de `SettingsView`, pas de la barre latérale ; le premier
   appelant sera le fil d'Ariane de la capture 1d (lot 4). La route est résolue par
   `MainDetailView` dès maintenant.
3. **`PortfolioSavedView` vit dans `Services/Project/`** et non dans `Models/AppSettings.swift`
   comme le disait le plan du lot : c'est le rangement du §4 de la spec, et ce n'est pas un
   modèle persisté.
4. **Trois écarts au semis**, documentés en tête de `RefonteDemoSeed+Portfolio.swift` : les
   captures 1a, 1d et 1f se contredisent sur le chef de projet et le risque de `P25_193`, sur
   la fiche incomplète de `P25_099` et sur le statut / la dernière réunion de `P25_155`. Les
   décisions **D3** (la relation fait foi) et les **comptes** de 1f (2 + 3 + 2 = 7, comme le
   badge « À risque 7 » de 1a) ont tranché.
5. **Les codes de remplissage sautent les codes réservés.** `P25_061` est à la fois un projet
   nommé par la capture 1a et un numéro de la plage `P25_001…`. Sans ce saut, le portefeuille
   comptait soixante-quinze projets au lieu de soixante-seize.
6. **Le périmètre typographique (D17) ne gagne que `Views/Navigation` et `Views/Project`.**
   `sourcesAreFound` vérifie que le périmètre est bien celui qu'on croit lire : un dossier
   encore inexistant le rendrait vrai à vide. Les autres sont à ajouter par le lot qui crée
   leur premier fichier — commentaire en place dans le test.

### Ce qui reste dû

- Les **projets récents** de la capture 2b (`ASP – Sécurisation des flux`,
  `ASP – Obsolescence VM`, `RH – TIME & APPLI`) vivent dans `@AppStorage`, pas dans le store :
  le semis ne les pose pas. Au lot 1 de décider s'il les préremplit pour la recette.
- Le badge « Mails 12 » de l'onglet Mails de la capture 1d : le semis pose **deux**
  `ProjectMail` et trois `MailIndexSuggestion`, ce que la carte « MAILS LIÉS » montre. Le
  chiffre 12 de l'onglet n'a pas de source ; au lot 4 de dire ce qu'il compte.
- `MainRouter.pendingPaletteQuery` est une dette assumée du lot 3 : la palette n'existe pas
  encore, et l'écran `p1c` doit pouvoir poser son terme.

---

## Lot 1 — Section « Projets » de la barre latérale, variante 2b (2026-09-09)

Branche `feat/projets-lot-1-sidebar`, sur le lot 0 (`b3bf61d`). Écran de recette `p2b`.

**État : livré, `swift build` propre (aucun avertissement nouveau), `swift test` complet vert —
2 175 Swift Testing / 268 suites + 1 057 XCTest (1 ignoré) = **3 232**, 0 échec, soit **+50
tests et +4 suites** sur les 3 182 du lot 0, aucun retiré. Recette visuelle **non faite** :
écran verrouillé (garde 1 de `recette-run.sh`) — voir « Ce qui reste dû ». **Fix round 1**
appliqué après la relecture (conformité ✅) : place de l'arbre et teinte unique, suite à
**3 233** (+1 test).

### Commits

| Commit | Intention |
| --- | --- |
| `c07eab1` | `refactor(design)` — `StatusIcon` sur les jetons, taille en paramètre (D16) |
| `df254ab` | `feat(projets)` — `ProjectSearch` (D7) et `SidebarProjectCounts` (D11) |
| `d529fb6` | `feat(projets)` — la section « Projets » de la barre latérale (2b) |
| `3637c02` | `feat(recette)` — l'écran `p2b` préremplit les projets récents |
| _ce commit_ | `docs` — §8 d'`architecture.md`, manifeste, ce journal |
| `fix round 1` | `fix(sidebar)` — l'arbre passe sous la section Projets ; teinte unique |

### Ce qui est en place

- **`OneToOne/Views/Sidebar/`** (nouveau dossier, périmètre typographique D17) :
  `ProjectsSidebarSection` (la table `ProjectsSidebarEntry` des quatre entrées — libellé,
  icône, route, badge — et la section `DisclosureGroup`), `PinnedProjectsList` (pastille de
  10 px + nom tronqué), `RecentProjectsList` (nom seul).
- **`Views/DesignSystem/StatusIcon.swift`** : la pastille sort de `ProjectListView.swift`, passe
  sur `ok` / `warn` / `report` / `inkMuted` et prend sa taille en paramètre (9 par défaut, 10
  dans la barre latérale, 12 sur les six appels existants — leur rendu ne change que de teinte).
- **`Services/Project/ProjectSearch.swift`** (D7) : `matches` (nom, code, domaine, sponsor, chef
  de projet, architecte, notes), `rank` (préfixe > mot > sous-chaîne, épinglés, nom),
  `highlightRanges`. `Sidebar.projectMatches` y délègue.
- **`Services/Project/SidebarProjectCounts.swift`** (D11) : `active`, `atRisk`,
  `openProjectActions`. Les trois motifs « à risque » sont un **stub** commenté comme tel.
- **`Views/Sidebar.swift`** : la section s'insère entre « Tous les Collaborateurs » et
  « Collaborateurs » ; deux `@Query` de plus (réunions tenues, actions) pour les compteurs ;
  l'arbre « Projets par Entité » passe à `false` par défaut (D5) et son label gagne la
  sous-ligne « 8 entités · replié par défaut ».
- **Recette** : `RecetteScreen.codesDeProjetsRecents` (seul `p2b` en porte) et
  `MainRouter.rememberRecentProject`, qui inscrit un projet aux récents sans router.

### Tests ajoutés

`ProjectSearchTests` (15), `SidebarProjectCountsTests` (12), `ProjectsSidebarSectionTests` (19),
`StatusIconTests` (4) — cinquante tests dans quatre suites nouvelles, plus trois attentes
dans `RefonteTypographieTests.sourcesAreFound` (le périmètre gagne `Views/Sidebar`).

Les compteurs sont testés **sur le semis** : 62 actifs / 7 à risque / 23 actions ouvertes — les
trois chiffres de la capture, au premier essai, sans retoucher le semis.

### Écarts et décisions prises

1. **L'arbre « Projets par Entité » est passé sous la section « Projets »** (fix round 1). Il
   vivait après « Collaborateurs » et « Archives » ; le handoff §2b dit « conservé **sous** la
   section Projets » et la capture le montre juste après « RÉCENTS ». L'ordre est désormais :
   section « Projets », arbre par entité, « Collaborateurs », « Archives », « Projets
   Archivés », « Paramètres » — le reste n'a pas bougé. Un test de lecture des sources
   (`ordreDeLaBarreLaterale`) le tient : l'ordre des lignes d'une `List` ne s'observe pas
   autrement.
2. **Les trois épinglés sont triés par nom**, donc dans l'ordre AE / ASP – BLOOM / ASP –
   Installation, là où la maquette les liste dans l'ordre de son tableau (BLOOM / AE /
   Installation). Aucune colonne du modèle ne porte cet ordre — l'implémenter demanderait un
   `pinnedOrder`, hors périmètre. Un tri par nom est stable d'un lancement à l'autre.
3. **Les récents sont bornés à trois à l'affichage**, cinq en mémoire : le handoff écrit « les 3
   derniers projets ouverts » et la file de D4 en retient cinq. Les deux plus anciens serviront
   à la palette du lot 3.
4. **Le badge est en `ink4`, pas en `inkMuted`.** À 11 pt, `inkMuted` n'atteint pas 4,5:1 — la
   règle §1.2 (« jamais sous 11,5 px ») l'interdit. `ink4` est ce que `.sectionLabel()` emploie
   déjà à 9,5 pt.
5. **La sélection est peinte en `listRowBackground`** et non laissée à la surbrillance système :
   la capture montre le jeton `action` (#2563D9), et la couleur d'accent de macOS est réglable.
   **C'est le point que la recette doit vérifier** — si le système repeint par-dessus, il faudra
   `.listItemTint` ou un `List` sans sélection sur ces lignes.
6. **Le libellé de l'arbre garde `.subheadline.weight(.semibold)`** : `Sidebar.swift` n'est pas
   dans le périmètre Plex, et le passer en `plexSans` aurait changé le rendu d'une ligne que ce
   lot n'a pas mission de retoucher. Seule la sous-ligne ajoutée est en Plex Mono.
7. **`MainRouter` gagne une méthode** (`rememberRecentProject`) et `RecetteScreen` une propriété
   (`codesDeProjetsRecents`), sur le modèle de `termeDePalette` : la table des écrans reste
   l'autorité sur ce que chaque code prépare, et un test vérifie que **seul** `p2b` en porte.
8. **`architecture.md` §8 annonçait 225 fichiers de `Views/`** ; il y en a 241. Le compte est
   corrigé au passage (il l'était déjà avant ce lot).

### Ce qui reste dû

- **La recette `p2b` n'a pas été faite** : `Scripts/recette-run.sh` a refusé sur la garde 1
  (« Session graphique verrouillée »), et les contournements (`--ignore-lock`, `--ignore-teams`)
  sont interdits. Le binaire release et le bundle `/tmp/recette/OneToOne.app` sont prêts
  (md5 `f1e26b9f41140913994faff884208b42`, 2026-09-09 13:21). Reste à photographier, à comparer
  à `handoff/screenshots/2b-sidebar-variante-arbre-replie.png` et à ranger dans
  `recette/lot-1-p2b.png`. **Trois points à regarder en priorité** : la surbrillance de
  sélection (écart n° 5), l'absence de chevron parasite et la navigation clavier (réserve n° 1
  du lot 0), et le rendu des sous-sections « ÉPINGLÉS » / « RÉCENTS » — un `View` qui rend
  plusieurs lignes dans une `List` est censé se déplier en autant de lignes, ce qu'aucun test
  ne prouve.
- **Le stub « à risque »** de `SidebarProjectCounts` : le lot 5 doit le remplacer par le
  constructeur de la vue dédiée, et rendre les mêmes 7.
- **Deux `@Query` globales de plus dans la barre latérale** (réunions tenues, actions). Sur le
  semis (82 réunions, 76 projets) rien ne se voit ; sur le store réel de Laurent, le coût
  n'est pas mesuré. Réserve n° 9 du lot 0, toujours ouverte.

---

## Lot 2 — Écran Portfolio (1a) (2026-09-09)

Branche `feat/projets-lot-2-portfolio`, sur le lot 1 (`a0ae22a`). Écran de recette `p1a`.

**État : livré, `swift build` propre (aucun avertissement nouveau dans les fichiers du lot),
`swift test` complet vert. Recette visuelle : voir « Ce qui reste dû ».**

### Commits

| Commit | Intention |
| --- | --- |
| `7aaea0b` | `feat(projets)` — `PortfolioBuilder`, `ProjectPeople`, `ProjectBatchActions` (D3, D11, D15) |
| `3835db4` | `feat(projets)` — l'écran Portfolio : tableau, facettes, vues enregistrées |
| _ce commit_ | `docs` — §8 d'`architecture.md`, manifeste, ce journal |

### Ce qui est en place

- **`Services/Project/`** : `PortfolioRow` + `MilestoneCell` (une ligne calculée d'avance,
  D11), `PortfolioBuilder` (`rows`, `apply`, `sort`, `values`, `relativeLabel`, `summary`,
  `footer`, `groups`) et `PortfolioFacet` ; `ProjectPeople` (D3) ; `ProjectBatchActions` +
  `ProjectCreation` (D15).
- **`Views/Portfolio/`** (nouveau dossier, périmètre typographique D17) : `PortfolioView`,
  `PortfolioModel` + `PortfolioSavedViewStore`, `PortfolioHeader`, `PortfolioFilterBar`,
  `SavedViewMenu`, `PortfolioTable`, `PortfolioGroupedView`, `PhaseBadge`, `RiskBadge`,
  `ProjectBatchBar`.
- **`MainDetailView`** monte `PortfolioView` sur `.portfolio` : le placeholder du lot 0 est
  remplacé.
- **`Sidebar.swift`** : `multiSelectBar` devient `ProjectBatchBar`, ses six méthodes `batch*`
  disparaissent, `nextProjectCode` délègue à `ProjectCreation`. La suppression demande
  désormais confirmation.
- **`ProjectListView.swift` supprimée** (D16) : orpheline, sans appelant, elle ne portait plus
  que `StatusIcon`, migré au lot 1.
- **Dédoublonnages** : `MeetingStatsScope.lastHeldByProject` remplace le calcul privé de
  `SidebarProjectCounts`, dont le motif « fiche incomplète » lit désormais
  `ProjectPeople.manager` ; `ProjectSearch.matches(fields:query:)` sert le filtrage de lignes
  sans écrire une seconde comparaison (D7).
- **Recette** : `RecetteScreen.vueEnregistreeDeRecette` (seul `p1a` en porte) et
  `MainRouter.pendingPortfolioSavedView`, consommée par `PortfolioView` à son apparition.

### Tests ajoutés

`PortfolioBuilderTests` (41), `ProjectPeopleTests` (13), `ProjectBatchActionsTests` (15),
`PortfolioViewTests` (31) — **cent tests dans quatre suites nouvelles**, plus six attentes de
plus dans `RefonteTypographieTests.sourcesAreFound` (le périmètre gagne `Views/Portfolio`) et
son titre passé à « sept périmètres ».

Les huit lignes que la capture nomme sont vérifiées une par une **sur le semis** : entité,
phase, type, risque, chef de projet, statut, cellule de jalon (`J−4`, `J−21`, `retard`,
`J−35`, `—`, `J−60`, `J−12`, `J−90`) et libellé relatif (`il y a 3 j`, `hier`, `il y a 8 j`,
`il y a 2 sem.`, `jamais`, `il y a 5 j`, `il y a 4 j`, `il y a 1 mois`) — tous justes au
premier essai, sans retoucher le semis.

### Écarts et décisions prises

1. **Le titre est « Projets », la capture écrit « Portfolio ».** Le tableau du handoff §1a dit
   « Titre `Projets` » et « sous-titre `62 actifs · 8 entités · 14 archivés` » ; la capture
   affiche « Portfolio » et s'arrête à « 62 projets actifs · 8 entités ». Le tableau gagne :
   c'est lui qui spécifie la zone, et « Portfolio » est déjà le libellé de l'entrée de barre
   latérale qui mène ici. **À trancher si la capture doit primer** — c'est une constante,
   `PortfolioHeader.titre`.
2. **L'écran `p1a` n'active que « Entité : ASP », pas « Risque ≥ Modéré ».** La capture affiche
   les deux chips, mais quatre de ses huit lignes portent un risque « — » : la maquette montre
   une chip qu'elle **n'applique pas**. Sur le semis, ASP seul rend **15 lignes** (les 8 nommées
   + 7 projets de remplissage) et ASP + Risque ≥ Modéré n'en rend que **5**. Aucune combinaison
   ne donne les 8 de la capture. Le repli prévu par le dispatch est retenu : entité seule, et le
   pied affichera « 15 lignes sur 62 » au lieu de « 8 lignes sur 62 ».
3. **La colonne « Jalon » est la huitième colonne.** Le handoff donne sept largeurs
   (`22 | 1fr | 88 | 92 | 88 | 126 | 78`) et la capture montre huit colonnes. Les six premières
   largeurs sont celles du handoff ; « Jalon » (72) et « Dernière réu. » (92) sont mesurées sur
   la capture 2×.
4. **Le menu de vues enregistrées est sur sa propre ligne**, aligné à droite sous les chips :
   c'est ce que montre la capture, là où le tableau du handoff le place « à droite » de la barre
   de filtres — qui est déjà pleine à cinq chips.
5. **`RiskBadge.fond(.faible)` est `surfaceAlt`, pas `okBg`.** D2 dit que « Faible » reste
   `ink4` ; un fond vert sous une encre neutre n'aurait aucun sens. Aucun projet « Faible »
   n'apparaît sur la capture.
6. **`Font.plexSansItalic` est ajoutée à `One2OneTypography`.** « Non affecté » est en italique
   sur la capture, aucune italique Plex n'est embarquée (l'italique est donc synthétisée), et
   `.italic()` est dans l'interdit de `RefonteTypographieTests` — le poser dans le fichier de
   typographie, hors périmètre, respecte la règle sans l'affaiblir.
7. **`PortfolioRow` porte un champ de plus que le brief** (`sponsor`) et son `stableID` est
   optionnel. Le sponsor est là parce que le champ de recherche s'annonce « Nom, code,
   sponsor… » ; `stableID` est optionnel parce qu'un constructeur pur ne peut pas appeler
   `ensuredStableID`, qui écrit dans le store.
8. **`MilestoneCell.none` est un piège de nom** : `ligne?.nextMilestone == .none` se résout en
   `Optional.none` et compare toujours faux. Le nom est celui du brief ; un test l'a attrapé, et
   il faut écrire `MilestoneCell.none` derrière un optionnel.
9. **Le tri met les vides en dernier** (entité, chef de projet, jalon), sauf « Dernière réu. »,
   où « jamais » est le plus ancien des passés et ouvre donc le tri croissant — c'est là que
   l'utilisateur cherche ce qu'il a négligé. Le nom départage toujours, en croissant.
10. **Les menus de facettes ne proposent que des valeurs présentes**, sauf le risque, dont les
    quatre crans sont toujours là : c'est un seuil, et une liste qui change selon le contenu du
    tableau serait illisible. Les valeurs sont calculées sur **toutes** les lignes, pas sur les
    filtrées — sinon filtrer sur ASP interdirait de changer d'entité.
11. **`SidebarProjectCounts.ficheIncomplete` lit `ProjectPeople.manager`** au lieu de
    `projectManager == nil`. Même règle (D3), une seule lecture ; un `Collaborator` au nom
    blanc compte désormais comme non affecté. Les sept projets « à risque » du semis sont
    inchangés.

### Ce qui reste dû

- **La recette `p1a`** : voir le rapport de lot pour son état exact.
- **Le pied affichera « 15 lignes sur 62 »** et non « 8 lignes sur 62 » (écart n° 2) : si
  Laurent veut la capture au chiffre près, il faut soit huit projets ASP actifs au semis, soit
  une vue enregistrée sur une liste de codes — ce que `PortfolioFilters` ne sait pas exprimer.
- **La sélection multiple par ⇧-clic n'est prouvée par aucun test de rendu** : le modèle est
  testé, le geste (`TapGesture().modifiers(.shift)` en `highPriorityGesture` devant un
  `onTapGesture`) ne l'est pas. C'est le premier point que la recette doit vérifier.
- **Le tri de la capture est « PROJET ↑ » mais ses lignes ne sont pas alphabétiques** (elles
  suivent l'ordre de déclaration du semis). Le tableau les triera par nom : « AE – Gestion… »
  passera en tête. Écart inévitable, sauf à ne pas trier.
