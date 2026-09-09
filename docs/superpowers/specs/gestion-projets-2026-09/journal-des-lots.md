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

### Compléments hors périmètre Portfolio

Cinq commits demandés en cours de lot, tous issus du diagnostic du coordinateur sur la
recette `p2b` : `0595283` et `c446dc6` (`recette-run.sh` — `-ApplePersistenceIgnoreState
YES`, effacement du domaine de préférences sous `--reset` derrière un garde-fou sur le
suffixe `.recette`, témoin de rendu par comptage des gabarits intégrés en lisant le store
**avec son `-wal`** ; pièges n° 6 et n° 7 documentés, `CLAUDE.md` passe à sept pièges),
`1dd8c02` (`MainRouterTests` n'écrit plus dans les préférences réelles — 65 fichiers
retirés), `f7ad875` (collaborateurs du semis en favoris) et `2b8fc70`
(`MainWindowPlacement.corrige`, six tests : une fenêtre restaurée hors écran est
recentrée, quelle que soit la clé d'où vient son cadre).

### Ce qui reste dû

- **La recette `p1a` n'a pas été faite** : un enregistrement de Laurent était en cours
  (`.wav` qui grossit, garde du dispatch) et l'instance de OneToOne lancée à 06:39 hors
  bundle — celle qui a coûté trois heures au diagnostic — tournait encore, sans droit de
  l'arrêter. L'écran n'était pas verrouillé et aucune réunion Teams n'a été détectée.
  Détail et commande de reprise dans le rapport de lot.
- **Les deux points non demandés du diagnostic** restent dus : la garde « un seul
  OneToOne à la fois » (elle supposerait de tuer un processus) et l'identifiant de bundle
  unique par dossier de sortie de `recette-app.sh`.
- **Le pied affichera « 15 lignes sur 62 »** et non « 8 lignes sur 62 » (écart n° 2) : si
  Laurent veut la capture au chiffre près, il faut soit huit projets ASP actifs au semis, soit
  une vue enregistrée sur une liste de codes — ce que `PortfolioFilters` ne sait pas exprimer.
- **La sélection multiple par ⇧-clic n'est prouvée par aucun test de rendu** : le modèle est
  testé, le geste (`TapGesture().modifiers(.shift)` en `highPriorityGesture` devant un
  `onTapGesture`) ne l'est pas. C'est le premier point que la recette doit vérifier.
- **Le tri de la capture est « PROJET ↑ » mais ses lignes ne sont pas alphabétiques** (elles
  suivent l'ordre de déclaration du semis). Le tableau les triera par nom : « AE – Gestion… »
  passera en tête. Écart inévitable, sauf à ne pas trier.

---

## Lot 3 — Palette ⌘K (1c), recherche dans les CR, unification D7 (2026-09-09)

Branche `feat/projets-lot-3-palette`, **base `88916de`** (tête du lot 2 après ses deux
commits de correction et de captures ; le lot a démarré sur `c092442` et a été rebasé en fin
de course, sans conflit). Rien poussé, arbre propre, aucun `git stash`, aucun lancement
graphique, aucun build release — la recette `p1c` est prise par le coordinateur depuis un
autre checkout.

`swift test` : **2 345 Swift Testing / 276 suites + 1 057 XCTest (1 ignoré) = 3 402**,
0 échec, **+56 tests et +3 suites** sur le lot 2. Aucun avertissement nouveau ;
`DocumentationTests` et `RefonteTypographieTests` verts.

### Ce que le lot livre

**La table des raccourcis change de portée (D1).**
`Views/Menus/MeetingShortcut.swift` devient `AppShortcut.swift` (`git mv`, l'historique suit) :
`⌘K` va à la palette, l'assistant de réunion passe à `⌘⇧K`, et un neuvième cas `palette` arrive
en tête. Aucun `typealias` de compatibilité — les cinq appelants sont renommés, et
`Tests/AppShortcutsTests.swift` refuse toute trace du nom retiré. ADR
`docs/adr/2026-09-09-palette-commande-k.md` ; le §1.4 de la spec réunion porte une note datée
qui y renvoie.

**La palette** (`Views/Palette/`, `Services/Project/PaletteModel.swift`) : une carte de 560 pt
posée en superposition de la fenêtre principale, ouverte par `⌘K` depuis n'importe quel écran
(item de menu natif) et au lancement par la recette `p1c`. Six projets au plus, classés par
`ProjectSearch.rank`, puis les deux actions « Créer un projet « x » » et « Chercher « x » dans
les CR » (D8 : pas de mails). `↑`/`↓` bornés, `↩` ouvre, `⌘↩` épingle **sans fermer**, `esc`
referme.

**La recherche dans les CR** (`Views/Search/ReportSearchView.swift`,
`Services/Project/ReportSearch.swift`) remplace l'invite `.searchReports` du lot 0 :
`localizedStandardContains` sur `Meeting.textualContent` hors notes, un résultat par réunion
étiqueté par le champ trouvé, groupé par projet avec « Sans projet » en dernier, extrait de
±60 caractères aplati et surligné, clic → réunion par `QuickLaunchRouter.pendingToken`.

**L'unification D7 est faite.** `SearchPopover` et `MeetingsProjectFilterPicker` perdent leurs
prédicats propres pour `ProjectSearch`. Il n'en reste **aucun** dans le dépôt.

### Commits

| Hash | Intention |
| --- | --- |
| `2ed1b14` | `refactor(raccourcis)` — `AppShortcut`, la palette prend ⌘K et l'assistant ⌘⇧K (D1) |
| `15cf4cb` | `feat(projets)` — `PaletteModel` et `ReportSearch`, deux règles pures avant leurs vues |
| `2d12123` | `feat(projets)` — lot 3, la palette ⌘K et la recherche dans les CR |

### Décisions prises en cours de lot

1. **L'entité entre dans les champs de `ProjectSearch`.** Elle n'était que dans le prédicat de
   `MeetingsProjectFilterPicker`, qui migre : une recherche unique doit être l'**union** de ce
   qu'elle remplace, pas leur intersection. Sans cela, D7 aurait retiré une capacité.
2. **Un terme vide n'affiche ni projet ni action.** Le brief dit « vide → « Aucun projet » + les
   deux actions » ; c'est le cas d'un terme **cherché sans résultat**. Rien de frappé n'est pas
   « aucun résultat » : on ne crée pas un projet sans nom et on ne cherche pas le vide. Les deux
   états sont distincts (`estVide` / `aucunProjet`) et tous deux testés.
3. **La palette montre les projets archivés.** La capture 1c fait remonter « RH – Migration GED
   documentaire », qui est archivé. Le Portfolio, lui, ne montre que les actifs.
4. **`⌘↩` ne recharge pas la liste.** Épingler remonte un projet dans `rank` : réordonner ferait
   sauter sous le curseur la ligne qu'on vient d'épingler, et la palette reste ouverte.
5. **Ni feuille ni panneau flottant** : une superposition. Une `.sheet` macOS descend du haut
   avec son propre fond et ne sait pas dessiner une carte bordée et ombrée ; un `NSPanel`
   demanderait une fenêtre à gérer pour le même rendu.
6. **`MeetingMenuItem` gagne `.palette`.** Le cas décrit la surface de déclaration, pas une
   dépendance à une réunion — l'item n'est jamais grisé, et un test le vérifie.
7. **`AppIntents.AppShortcut` est qualifié** dans `StartOneToOneIntent.swift` : le nom arrêté par
   D1 collisionne avec un type du framework, et aucun des deux n'est renommable.
8. **`ProjectCreation.creer` gagne `nom:`**, avec la chaîne vide pour défaut et non
   `nomParDefaut` — un argument par défaut est évalué hors acteur, et y lire une propriété
   statique d'un `enum` `@MainActor` produit un avertissement de concurrence.

### Écarts avec la capture `1c-palette-cmdk.png`

Constatés **par lecture** ; la recette n'est pas de ce lot.

1. **La carte fait 560 pt, la maquette en rend 508.** Le handoff écrit « 560 px de large » ; son
   HTML pose un cadre de 560 avec 26 px de marge, donc une carte de 508. La mesure **nommée**
   gagne.
2. **« Chercher « ged » dans les CR »** et non « dans les CR et mails », que la capture affiche.
   C'est **D8**, tranchée par Laurent le 2026-09-09.
3. **La sous-ligne de « RH – Migration GED documentaire » portera « · PENVEN Yann ».** La capture
   s'arrête à « P24_211 · RH · Run », mais le semis lie un chef de projet à ce projet, et D3 dit
   que la relation fait foi. Corriger demanderait de changer le semis du lot 0.
4. **Le pied est rendu en trois segments espacés de 14 pt**, comme la maquette les dessine ; la
   constante testée reste la phrase du handoff, séparée par des points médians.
5. **Aucun voile derrière la carte.** La maquette la pose sur un fond uni de cadre, pas sur un
   tapis assombri ; la superposition est transparente et se contente d'avaler les clics.

### Ce qui reste dû

- **La recette `p1c` n'a pas été faite** (hors périmètre du lot, prise par le coordinateur).
  Cinq points à regarder : les touches `↑`/`↓` avec un `TextField` focalisé, `⌘↩` face à l'item
  de menu « Générer le rapport » qui porte la même combinaison, la position verticale de la
  carte (96 pt), le rendu de l'ombre (`radius: 40` sur un flou CSS de 40) et la troncature des
  noms de projet à 560 pt.
- **`MeetingShortcutsSheet` garde son nom** alors qu'elle rend une table qui n'est plus
  seulement de réunion : hors intention de ce lot.

---

## Lot 4 — Écran projet de pilotage (1d) (2026-09-09)

Branche `feat/projets-lot-4-ecran-projet`, base `ceaa026` (tête du lot 3), **rebasée en fin de
course sur `feat/projets-lot-3-palette`** après les correctifs de barre latérale, de palette et
de recette du coordinateur. Rien poussé, arbre propre, aucun `git stash`, aucun lancement
graphique, aucun build release — la recette `p1d` est prise par le coordinateur depuis un autre
checkout.

### Ce que le lot livre

**Deux règles pures, écrites et testées avant la moindre vue (D10, D11).**
`ProjectPilotageBuilder.build(project:meetings:suggestions:today:)` rend un
`ProjectPilotageState` : les quatre tuiles, les quatre lignes d'actions (retards d'abord, puis
l'ordre manuel de la liste — c'est celui de la capture), les trois réunions, les trois mails et
leur invite de rattachement, les trois interlocuteurs, le risque et les cinq lignes d'identité,
plus l'alerte de deadline. Aucune vue de l'onglet ne recompte quoi que ce soit.
`MeetingTypeBadge` porte D10 : un COPIL se reconnaît à un thème ou à un titre — `MeetingKind`
n'en a pas et n'en aura pas —, un atelier et un 1:1 à leur `kind`, et toute autre réunion n'a
pas de badge.

**L'édition in-place (D9, ADR `docs/adr/2026-09-09-edition-in-place-fiche-projet.md`).**
`EditableInPlace` : clic sur la valeur → champ actif, `⏎` (une ligne) ou `⌘⏎` (un paragraphe)
valide, `esc` referme le champ **et rien d'autre**. `EditableTextField` et `EditableTextEditor`
gagnent `onSubmit` / `onCancel`, `nil` par défaut — les vingt-cinq usages historiques et le
`.onExitCommand` de `ProjectCardPanel` sont intacts, ce qu'un test fige. `ProjectCardDraft`
couvre désormais nom, sponsor, phase, type, risque, jours, fin de design, entité et les deux
relations de rôle ; son statut passe en `statusRaw`, ce qui met fin à un défaut réel — un
enregistrement réétiquetait « Yellow » les soixante-deux projets du store dont le statut est
« Unknown ». `ProjectCardPanel.meeting` devient optionnel.

**L'écran (`Views/Project/`).** `ProjectScreen` est un routeur : en-tête, six onglets, contenu.
`ProjectHeader` porte le fil d'Ariane `Portfolio / <entité> / <code>`, le nom en 21 pt, les
pilules (statut, phase, type, entité, alerte de deadline) et les trois commandes ;
`ProjectTabs` les six onglets soulignés, badgés des actions ouvertes et des mails. `Pilotage/`
tient les cartes — `KPITiles`, `OpenActionsCard`, `RecentMeetingsCard`, `ScopeCard`,
`SideColumn` — et `Tabs/` les quatre onglets secondaires, dont `ProjectDocumentsTab`, sorti de
`ProjectDetailView`.

**La heatmap devient une tuile.** `MeetingHeatmapView` quitte la fiche projet pour la tuile
« RYTHME » (huit barres sur douze semaines, dégradé `okBg → ok`) mais **n'est pas supprimée** :
le tableau de bord l'emploie encore, à deux endroits. `ProjectDetailView` devient l'onglet
« Fiche complète » et perd sa barre d'outils : Archiver et Supprimer passent dans le menu `···`
de l'en-tête, avec confirmation pour la seconde ; Enregistrer descend dans le corps de la fiche.

### Décisions prises

1. **Le résumé d'une réunion est sa première décision, à défaut son résumé court.** La carte
   s'appelle « résumé de décision » (handoff §1d) et le coordinateur l'a tranché ainsi. Sur le
   semis, la ligne COPIL affichera donc « Le lot « annuaire » sort du périmètre v1 » là où la
   maquette écrit le résumé complet — écart visible, un `swap` de deux lignes pour l'inverser.
2. **Les actions non en retard suivent `sortOrder`, pas l'échéance.** La capture montre
   « Planifier l'atelier sécurité », sans échéance, en quatrième ligne, devant deux actions
   datées de la semaine suivante : c'est l'ordre de la liste d'actions du projet.
3. **Une origine d'action n'est affichée que si la réunion porte un badge.** « Issue de la
   réunion projet du 08/09 » n'apprend rien sur un écran qui ne montre que ce projet.
4. **`ProjectStatus.displayLabel` et non `ProjectCardStatus`** pour le libellé de la pilule de
   statut : c'est l'énumération D14, posée au lot 0 pour cette rangée précise, et elle sait
   dire « Statut inconnu ». Conséquence : « En alerte » au lieu de « En risque » pour un projet
   rouge.
5. **Les pilules réutilisent les tables de teintes du lot 2, pas leurs géométries.** Le
   Portfolio dessine des badges de rayon 4 à 11,5 pt, la capture 1d des capsules de 12 pt.
6. **La résolution d'une identité SwiftData passe par une requête**, jamais par
   `ModelContext.model(for:)` : celui-ci rend un objet faulté quand l'identité vient d'un autre
   conteneur, et la suite complète en ouvre un par cas — le test des relations passait isolément
   et échouait en suite.
7. **`⌘⏎` valide un paragraphe**, `⏎` y insère un retour à la ligne. Le handoff écrit `⏎` sans
   distinguer ; un périmètre de trois phrases doit pouvoir en contenir. Le champ actif l'annonce.

**Un défaut SwiftData trouvé en route, et réparé.** Le test des relations du brouillon passait
seul et tombait **une fois sur huit** en suite complète. Sonde de 200 tours : réaffecter
`Project.entity` — passer d'une entité à une autre — puis appeler `save()` perd la nouvelle
valeur **70 fois sur 200** ; la même réaffectation *sans* `save` n'échoue jamais, et une
première affectation non plus. `Entity.projects` est le seul inverse déclaré du modèle, et
lire cette collection juste après le même `save` lève « Fatal error: Never access a full future
backing data » — c'est aussi ce qui faisait sortir la suite complète en `SIGTRAP` de temps en
temps. `ProjectRelationWriter` affecte, enregistre, **relit et répare** : 0 perte sur 200.
`ProjectBatchActions.setEntity` (lot 2) portait le même défaut et y passe désormais ;
`Tests/ProjectRelationWriterTests.swift` répète chaque scénario trente fois, parce qu'un tour
unique ne prouve rien contre un défaut à une chance sur trois.

### Écarts avec la capture `1d-ecran-projet-pilotage.png`

Constatés **par lecture** ; la recette n'est pas de ce lot.

1. **Le badge « Mails 12 » affichera 2.** Le semis pose deux `ProjectMail` — ce que la carte
   « MAILS LIÉS » montre — et le coordinateur a fixé le badge à `project.mails.count`. Le 12 de
   la maquette n'a aucune source (réserve n° 5 du lot 0, toujours ouverte).
2. **Le résumé de la ligne COPIL** (décision n° 1 ci-dessus).
3. **Le pied du périmètre s'arrêtera à « Cliquer pour éditer ».** La maquette écrit « dernière
   mise à jour par RIGAUT Manuel, hier » ; le modèle ne garde pas **qui** a touché le périmètre,
   et `scopeUpdatedAt` est `nil` sur le semis — il ne se remplit qu'à la première édition.
4. **Les hauteurs des barres de rythme ne sont pas celles de la maquette.** Elles sont
   proportionnelles au nombre de réunions par tranche de dix jours et demi ; la maquette dessine
   huit hauteurs décoratives. Le compte, lui, est juste : neuf réunions.
5. **Le rôle d'un interlocuteur et la sous-ligne d'un mail sont en `ink4`, pas `inkMuted`** : à
   11 pt, `inkMuted` n'atteint pas 4,5:1 (§1.2 des contraintes globales). Même arbitrage qu'au
   lot 1, invisible à l'œil.
6. **La piste de la jauge de charge est en `hair`** là où la maquette écrit `#EFEBE3`, et le
   bord d'une case à cocher non en retard en `dashedBorder` (22 %) là où elle écrit 24 % : ce
   sont les jetons les plus proches, et aucune couleur ne se nomme hors `One2OneToken`.
7. **Les noms de projet sont ceux du semis, tronqués à une ligne** — même remarque qu'aux
   lots 1, 2 et 3.

### Ce qui reste dû

- **La recette `p1d`** (hors périmètre du lot). Six points à regarder : le rendu du menu `···`
  et des deux menus de la colonne latérale (le piège `.borderlessButton` du lot 2), le
  soulignement de 2 px des onglets, la largeur réelle de la colonne principale à 1242 pt, le
  champ d'édition in-place au clic (aucun pixel observé), la bannière d'annulation en
  superposition basse, et le `⌘⏎` du périmètre face aux raccourcis de menu.
- **Les pilules de l'en-tête ne sont pas éditables au clic**, alors que le brouillon porte leurs
  champs : la capture ne montre aucune affordance d'édition dessus, et l'onglet « Fiche
  complète » les couvre. À rouvrir si Laurent veut éditer une phase depuis l'en-tête.

---

## Lot 5 — Vue « À risque » (1f) (2026-09-09)

Branche `feat/projets-lot-5-a-risque`, base `7c50de8` puis **rebasée** sur la tête corrigée du
lot 4 (`faf4538`) — sans conflit. Deux commits : `AtRiskBuilder` d'abord, la vue ensuite.
`swift test` complet vert : **2 511 Swift Testing / 284 suites + 1 057 XCTest (1 ignoré) =
3 568**, +42 tests, +2 suites, aucun retiré. **Recette `p1f` non faite** (hors périmètre du lot).

### Ce que le lot livre

- `Services/Project/AtRiskBuilder.swift` — la règle **unique** des trois motifs (D11) :
  `build(projects:meetings:today:)` rend un `AtRiskReport` (trois listes d'`AtRiskItem`, le
  nombre de projets **distincts**, le sous-titre accordé). Sur le semis : **2 / 3 / 2, sept
  projets**, sans recoupement — exactement la capture.
- `Views/AtRisk/AtRiskView.swift` et `AtRiskGroup.swift` — l'écran 1f : en-tête, trois groupes
  teintés (`report` / `warn` / `inkMuted`), une carte à bord gauche de 3 pt, une ligne par
  projet (nom 13 pt/500, détail 12 pt `inkMuted`, action à droite en `action`).
- Le mécanisme de **champ actif** : `ProjectField` (`Views/Navigation/MainRoute.swift`),
  `MainRouter.pendingFocusField` + `consumePendingFocusField()`, `openProject(_:tab:focus:)`.
  `ProjectScreen` le consomme à l'apparition et la carte concernée l'honore une fois.
- Les trois cibles de « Compléter » : `EditableInPlace` gagne une **ouverture externe** (le
  sponsor), la carte Interlocuteurs un `ManagerPicker` **prérempli** par
  `ProjectPeople.suggestedManager` (D3), l'en-tête un `StatusPicker` — la pilule de statut
  devient cliquable au passage. Deux `popover` et non deux `Menu` : un menu ne s'ouvre pas par
  programme, et c'est justement ce que « Compléter » demande.
- `SidebarProjectCounts` **cesse de répéter la règle** : son badge appelle `AtRiskBuilder.count`
  (le stub du lot 1 disparaît). `sectionLabel(_:)` accepte une teinte. `Views/AtRisk/` entre au
  périmètre typographique (D17) et au manifeste de documentation.

### Décisions du lot

1. **Le semis n'a pas été touché.** Les comptes 2 / 3 / 2 sortent tels quels, comme le dispatch
   l'exigeait.
2. **Une ligne par projet et par groupe**, et le jalon nommé est **le plus ancien** des
   dépassés : la capture ne montre jamais deux lignes pour un même projet.
3. **Le plus urgent en tête**, puis l'ordre alphabétique. Le groupe des jalons reproduit la
   capture (6 j avant 2 j) ; celui des silences non (écart n° 2 ci-dessous).
4. **La majuscule ne va qu'au premier fragment** d'un détail : « Pas de chef de projet · statut
   inconnu », comme la capture — et « Statut inconnu » quand il est seul.
5. **`.milestone` est consommé sans effet** : voir « Ce qui reste dû ».

### Écarts avec la capture `1f-vue-a-risque.png`

Constatés **par lecture** ; la recette n'est pas de ce lot.

1. **L'ordre du groupe « sans réunion » diffère.** La capture range IBMi (34 j), FIN (aucune),
   NEVIDIS (41 j) — ni par urgence, ni par nom, ni par date. Le code range le plus long silence
   d'abord : NEVIDIS, FIN, puis IBMi.
2. **NEVIDIS affichera « Aucune réunion enregistrée » et non « il y a 41 j ».** Le semis du
   lot 0 ne lui donne aucune réunion (`derniereReunion: nil`), et le dispatch interdit de le
   modifier tant que les comptes sortent. Une ligne du semis à changer (`derniereReunion: 41`)
   si la capture doit primer — le compte resterait 3.
3. **Les noms de projet sont ceux du semis, tronqués à une ligne** — même remarque qu'aux
   lots 1 à 4 (« AE – Gestion des services IO pour l'association ALP » contre « … pour l'ALP »).

### Ce qui reste dû

- **La recette `p1f`.** Cinq points : le bord gauche de 3 pt sous le `clipShape` de la carte,
  les séparateurs de 1 px entre lignes, la teinte réellement posée sur les trois titres
  (`sectionLabel(_:)` est neuf), le `popover` du sélecteur de chef ancré sur la bonne ligne, et
  l'ouverture automatique du champ sponsor à l'arrivée depuis « Compléter ».
- **« Replanifier » ouvre l'onglet « Fiche complète » sans mettre le jalon en édition.** Aucune
  vue de cet onglet ne montre les jalons : seul `ProjectCardPanel` (la fiche de 430 px de la
  refonte réunion) en a un éditeur, derrière sa bascule globale `Édition`. Le repli explicitement
  autorisé par le dispatch. `pendingFocusField = .milestone(stableID)` est bien posé et consommé :
  le jour où l'onglet portera un panneau de jalons, il n'y aura qu'à l'honorer.

### Correctif transverse porté par ce lot (origine : lot 3)

La recette `p1f` a rejoué le remappage de sélection de la barre latérale, cette fois déclenché
par un **redimensionnement** de la fenêtre vingt secondes après le lancement : deux projets
ouverts sans clic, « À risque » non surligné. `NSTableView` remappe ses index quand il
redispose ses lignes, pas seulement quand leur nombre change — la liste noire temporelle du
lot 3 ne pouvait pas le couvrir. La garde repose désormais sur l'**événement d'entrée en cours
de traitement** (`NSApp.currentEvent`, âge maximal 1 s), le chemin sans événement restant
ouvert pour l'accessibilité sous deux garde-fous. La même capture a révélé un **second**
défaut, indépendant : un projet à la fois épinglé et récent apparaissait deux fois dans la
même `List` sous la même identité, ce qui lui faisait perdre sa pastille de statut ;
`SidebarProjectRow` préfixe désormais l'identité par la sous-section. Détail complet dans
`lot-3-report.md`, section « Correction 3 » — le défaut vient du lot 3, c'est la pile du lot 5
qui le porte.
