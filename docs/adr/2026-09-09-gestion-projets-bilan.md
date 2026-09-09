# Refonte de la gestion des projets — bilan des décisions D0 à D18

- **Statut** : accepté, 2026-09-09.
- **Portée** : les sept lots de la refonte de la gestion des projets (0 → 6).
- **Références** : handoff (autorité sur le rendu)
  `docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md`, sept captures 2× sous
  `handoff/screenshots/` ; spécification d'exécution (autorité sur l'intégration), constats §2
  et décisions D0–D18 §3 : `docs/superpowers/specs/2026-09-09-gestion-projets-design.md` ;
  plan par lots `docs/superpowers/plans/2026-09-09-gestion-projets.md` ; comptes rendus de
  session `docs/superpowers/specs/gestion-projets-2026-09/journal-des-lots.md` ; captures de
  recette sous `docs/superpowers/specs/gestion-projets-2026-09/recette/`. Trois ADR de détail :
  [`2026-09-09-routeur-de-navigation.md`](2026-09-09-routeur-de-navigation.md) (D0),
  [`2026-09-09-palette-commande-k.md`](2026-09-09-palette-commande-k.md) (D1),
  [`2026-09-09-edition-in-place-fiche-projet.md`](2026-09-09-edition-in-place-fiche-projet.md)
  (D9).

## Contexte et problème

La barre latérale **était** le catalogue des projets : un `DisclosureGroup` « Projets par
Entité », un sous-groupe par entité, une ligne par projet, un groupe « Sans Entité », deux
boutons « Ajouter un projet » et un glisser-déposer par `code` pour changer l'entité. Soixante
projets s'y dépliaient sur huit entités ; retrouver le sien demandait de savoir sous quelle
entité il vivait. La fiche d'un projet était `ProjectDetailView`, un formulaire ; il n'existait
ni écran de portefeuille, ni recherche transverse, ni vue des projets en alerte.

Un handoff de sept captures haute fidélité décrivait un autre écran : une barre latérale réduite
à un **point d'accès** (variante 2a), un Portfolio filtrable, une palette `⌘K`, un écran projet
de pilotage à six onglets et une vue « À risque » groupée par motif. Dix-neuf décisions
d'intégration ont été posées avant le premier lot, six validées par Laurent le 2026-09-09.

Cet ADR consigne **ce qui a réellement été fait**, décision par décision, puis les écarts
assumés avec les captures, les défauts trouvés en chemin, et ce que le chantier laisse.

## Les décisions, telles qu'appliquées

| # | Décision retenue | Ce qu'elle est devenue | Où le vérifier |
|---|---|---|---|
| **D0** | Routeur de navigation : la barre latérale sélectionne une **route**, `ContentView` monte l'écran par un `switch` | Tenue. `MainRoute` (16 cas), `MainRouter` (`@Observable`, singleton `.shared` parce que `MenuBarController` est un `NSObject`), `MainDetailView`. Les seize routes montent un écran réel : « Mes réunions projets » et « Actions projets » sont `MeetingsListView` et `ActionsListView` filtrées par `projetsSeulement`, comme le §4 de la spec le demande — pas deux écrans de plus. Un mécanisme non prévu s'y est ajouté au lot 3 : `SidebarSelectionGuard` (voir « Défauts trouvés ») | `Views/Navigation/**`, ADR `2026-09-09-routeur-de-navigation.md` |
| **D1** | `⌘K` va à la palette, l'Assistant passe à `⌘⇧K` | Tenue. `MeetingShortcut` est renommé `AppShortcut` — la table n'est plus « de réunion » mais « de l'application » | `Views/Menus/AppShortcut.swift`, ADR `2026-09-09-palette-commande-k.md` |
| **D2** | Table de risque unique ; « Faible » reste `ink4`, pas un vert | Tenue. `RiskLevelTint` sert le Portfolio, l'écran projet et la vue « À risque » | `Views/DesignSystem/RiskLevelTint.swift` |
| **D3** | Chef de projet et architecte : la **relation** fait foi, la chaîne du xlsx ne suffit pas | Tenue. « Non affecté » en italique partout ; `ProjectPeople.suggestedManager` préremplit le sélecteur de l'action « Compléter » | `Services/Project/ProjectPeople.swift` |
| **D4** | `Project.pinned`, récents en `@AppStorage`, vues enregistrées en JSON sur `AppSettings` — aucun nouveau `@Model` | Tenue. Deux champs à valeur par défaut, aucun `SchemaV4` | `Models/Project.swift`, `Services/Project/RecentProjects.swift`, `PortfolioSavedView.swift` |
| **D5** | Nouvelle clé `sidebar.projectsSectionExpanded` (défaut `true`) ; l'arbre garde la sienne et passe à replié, puis disparaît au lot 2a | Tenue en deux temps : replié au lot 1 (variante 2b), **retiré au lot 6** avec sa clé, ses boutons et son glisser-déposer | `Views/Sidebar/ProjectsSidebarSection.swift`, `Views/Sidebar.swift` |
| **D6** | Codes de recette préfixés `p` ; semis de 62 projets actifs sur 8 entités et 14 archivés, dans le home jetable seulement | Tenue. `RefonteDemoSeed+Portfolio` est idempotent par `code` ; les six recettes sont faites (voir « Ce que le chantier laisse »), et l'item de menu qui sème à la main est désormais grisé hors bundle de recette | `Services/Debug/Seed/RefonteDemoSeed+Portfolio.swift`, `Services/Debug/RecetteScreen.swift` |
| **D7** | Une **seule** recherche de projets, partagée par la barre latérale, le Portfolio, la palette et le popover de la barre de menus | Tenue. `ProjectSearch` (correspondance, classement, surlignage) ; `MeetingsProjectFilterPicker` et `SearchPopover` y ont migré | `Services/Project/ProjectSearch.swift` |
| **D8** | « Chercher « x » dans les CR » : recherche lexicale synchrone dans les comptes rendus, **pas** les mails | Tenue. `ReportSearch` balaye `Meeting.textualContent` des réunions hors notes, groupe par projet, découpe un extrait de ±60 caractères | `Services/Project/ReportSearch.swift`, `Views/Search/` |
| **D9** | Édition in-place par champ, `⏎` valide, `esc` annule le champ et non l'écran | Tenue. `EditableInPlace`, `ProjectCardDraft` étendu, `UndoBanner` de 5 s ; `ProjectCardPanel` perd sa dépendance obligatoire à `Meeting` | ADR `2026-09-09-edition-in-place-fiche-projet.md` |
| **D10** | Badges de type de réunion : COPIL par thème ou titre, Atelier et 1:1 par `kind`, rien sinon | Tenue | `Services/Project/MeetingTypeBadge.swift` |
| **D11** | Données dérivées calculées **une fois par affichage**, jamais dans `body` | Tenue, et c'est la décision qui a le plus structuré le chantier : `PortfolioBuilder`, `ProjectPilotageBuilder`, `AtRiskBuilder`, `SidebarProjectCounts`, `PaletteModel`, `PortfolioModel` — chacun testé **avant** sa vue | `Services/Project/**`, `Tests/PortfolioBuilderTests.swift`, `AtRiskBuilderTests.swift` |
| **D12** | Trois jetons ajoutés (`paletteShadow`, `highlight`, `dashedBorder`), `AvatarStack` paramétré | Tenue. `dashedBorder` a coûté un fix round : sous `.menuStyle(.borderlessButton)`, AppKit jetait le bord en tirets (voir « Défauts trouvés ») | `Views/DesignSystem/One2OneTokens.swift` |
| **D13** | Largeur de la barre latérale : `min` 170, `ideal` 250, `max` 320 | Tenue | `OneToOneApp.swift` |
| **D14** | `ProjectPhase`, `ProjectStatus`, `ProjectType`, `RiskLevel` deviennent des `enum` **non persistées** ; une valeur inconnue s'affiche en neutre | Tenue. Les colonnes restent des `String` libres, `init?(raw:)` est tolérant | `Services/Project/ProjectPhase.swift` |
| **D15** | Barre d'actions en lot extraite en service + vue, partagée par la barre latérale et le Portfolio | Tenue. `ProjectBatchActions` (six opérations, identité par `PersistentIdentifier`) et `ProjectBatchBar` ; son menu « Entité » a repris le glisser-déposer retiré au lot 6 | `Views/Portfolio/ProjectBatchBar.swift` |
| **D16** | `StatusIcon` migre sur les jetons et sort de ProjectListView, qui est supprimée | Tenue au lot 2 | `Views/DesignSystem/StatusIcon.swift` |
| **D17** | Périmètre typographique étendu à `Views/Project/`, `Views/Portfolio/`, `Views/Sidebar/` | Tenue, et **élargie** en cours de route à `Views/Navigation/`, `Views/Palette/`, `Views/Search/` et `Views/AtRisk/`. `Sidebar.swift` reste dehors (voir « Ce que le chantier laisse ») | `Tests/RefonteTypographieTests.swift` |
| **D18** | Chaque lot passe `DocumentationTests` ; §5, §8 et §13 d'`architecture.md` corrigés | Tenue. Les tailles de §13 sont désormais relevées au `wc -l` et non estimées ; le glossaire gagne cinq termes | `docs/architecture.md`, `docs/glossaire.md`, `docs/documentation.yml` |

## Écarts assumés avec les captures

Ils sont **visibles** et **volontaires** : la spécification a été suivie contre la maquette, ou
la reproduction aurait demandé un changement hors périmètre. Ceux qui restent à trancher sont
signalés.

| Écart | Où | Pourquoi assumé |
|---|---|---|
| Titre « Projets » là où la capture écrit « Portfolio » | en-tête du Portfolio (lot 2) | le tableau du handoff §1a spécifie « Titre `Projets` », la capture affiche « Portfolio » : le tableau spécifie la zone, la capture l'illustre. **À trancher** — c'est une constante, `PortfolioHeader.titre` |
| NEVIDIS annoncé « Aucune réunion enregistrée » et non « il y a 41 j » | vue « À risque » (lot 5) | les captures 1a et 1f se contredisent sur ce projet ; le semis dit « jamais », et les comptes 2 / 3 / 2 du groupe sortent tels quels. Une ligne du semis suffirait à reproduire la capture sans changer le compte |
| Badge « Mails 2 » là où la maquette écrit 12 | onglet Mails de l'écran projet (lot 4) | le 12 n'a **aucune source** : le semis pose deux `ProjectMail`, ce que la carte « MAILS LIÉS » montre, et le badge compte `project.mails.count` |
| Risque « Faible » en `ink4` et non en vert | Portfolio, écran projet (D2) | on ne rouvre pas une décision de la refonte réunion pour un badge que la capture 1a ne montre pas |
| Épinglés triés par nom | barre latérale (lot 1) | la maquette les liste dans l'ordre de son tableau ; aucune colonne du modèle ne porte cet ordre, et un `pinnedOrder` était hors périmètre. Un tri par nom est stable d'un lancement à l'autre |
| « 15 lignes sur 62 » et non « 8 lignes sur 62 » | pied du Portfolio (lot 2) | la vue enregistrée « Mes projets ASP » rend quinze lignes sur ce semis ; les huit de la capture demanderaient une liste de codes, que `PortfolioFilters` n'exprime pas |
| Carte de palette de 560 pt là où la maquette en rend 508 | palette `⌘K` (lot 3) | le handoff **écrit** « 560 px de large » ; son HTML pose un cadre de 560 avec 26 px de marge. La mesure nommée gagne |
| « Chercher « x » dans les CR » et non « dans les CR et mails » | palette `⌘K` (lot 3) | D8, tranchée par Laurent |
| `SearchPopover` classe par pertinence et non par ordre alphabétique | popover de la barre de menus (lot 3) | D7 : une seule recherche, donc un seul classement. La mise en page ne change pas, l'ordre si |
| Ordre du groupe « sans réunion » | vue « À risque » (lot 5) | la capture range IBMi (34 j), FIN (aucune), NEVIDIS (41 j) : ni par urgence, ni par nom, ni par date — un ordre dessiné à la main. Le code range le plus long silence d'abord, comme le groupe des jalons, qui, lui, reproduit la capture |
| Noms de projet du semis, tronqués à une ligne | tous les écrans | « … pour l'association ALP » contre « … pour l'ALP » : ce sont des données de semis, pas du rendu |
| Rôles et sous-lignes en `ink4` et non `inkMuted` | barre latérale, écran projet (lots 1, 4) | à 11 pt, `inkMuted` n'atteint pas 4,5:1 — la règle §1.2 du handoff (« jamais sous 11,5 px ») l'interdit |
| « Replanifier » ouvre la fiche sans mettre le jalon en édition | vue « À risque » (lot 5) | aucune vue de l'onglet « Fiche complète » ne montre les jalons ; `pendingFocusField` est posé et consommé, prêt pour le jour où elle en portera un. Repli explicitement autorisé |

## Défauts trouvés en chemin

Aucun n'était dans le périmètre d'un lot ; tous ont été corrigés dans le lot qui les a
rencontrés.

- **`List(selection:)` réécrivait la route sans que personne ne clique** — le défaut le plus
  coûteux du chantier, **trois** recettes pour en venir à bout. La barre latérale était une
  `List(selection: $mainRouter.route)`. `NSTableView`, sous une `List` SwiftUI, conserve un
  **index** de ligne : quand il redispose ses lignes, l'index est retraduit en tag d'une
  **autre** ligne, que SwiftUI écrit dans le binding. Observé à `p1a` (fiche du premier projet
  archivé), à `p1c` (fiche de `P25_155`) et à `p1f` (deux projets ouverts sur un simple
  redimensionnement de fenêtre, vingt secondes après le lancement). Ce n'est pas un défaut de
  recette : tout utilisateur dont les lignes bougent est dérouté de la même façon.
  **Trois règles successives.** Le focus clavier, réfuté à l'écran — l'accessibilité
  (`AXSelected`, VoiceOver) sélectionne sans focus, et une sélection légitime refusée est pire
  que le défaut. Puis le délai de 300 ms après un changement de lignes, réfuté par `p1f` : un
  redimensionnement remappe les index sans qu'aucune ligne ne naisse ni ne meure, à n'importe
  quel moment de la vie de la fenêtre. Enfin la règle retenue : la route n'est écrite que
  pendant le traitement d'un **événement d'entrée** de l'utilisateur (`NSApp.currentEvent`, clic
  ou touche de moins d'une seconde), le chemin sans événement restant ouvert pour
  l'accessibilité sous deux garde-fous — fenêtre active **et** lignes posées.
- **Un projet épinglé *et* récent perdait sa pastille de statut.** Les deux sous-sections
  identifiaient leurs lignes par le `persistentModelID` du projet : deux lignes de même
  identité dans une seule `List`, ce que SwiftUI ne définit pas. Vu à `p1f` sur les deux projets
  concernés, le troisième épinglé — absent des récents — gardant la sienne : la signature exacte
  d'une collision d'identité. `SidebarProjectRow` préfixe l'identité par la sous-section.
- **Réaffecter `Project.entity` puis enregistrer perd la valeur** environ une fois sur trois sur
  un conteneur en mémoire. `Entity.projects` est le seul inverse déclaré du modèle.
  `ProjectRelationWriter` relit après le `save` et répare ; `ProjectCardDraft.apply` et
  `ProjectBatchActions.setEntity` y passent tous les deux. La cause n'est pas établie et la
  sonde sur un store fichier n'a pas abouti : il se peut que le contournement ne serve qu'aux
  tests.
- **Les préférences du bundle de recette ne sont pas isolées par `CFFIXED_USER_HOME`.**
  `cfprefsd` sert `com.onetoone.app.recette` depuis les préférences **réelles** du poste ; un
  cadre de fenêtre hérité d'une session précédente y pointait hors écran (x = 2048, écran
  absent). Combiné à la restauration d'état macOS, le bundle rouvrait la dernière fenêtre de
  réunion et l'application semblait bloquée sur un `ProgressView`. Une demi-journée
  d'observations fausses. Correctifs : `-ApplePersistenceIgnoreState YES` au lancement, purge du
  domaine `.recette` sous `--reset`, garde-fou d'isolation lisant le journal WAL du store.
- **`.menuStyle(.borderlessButton)` jette l'étiquette qu'on lui donne.** AppKit **extrait** un
  titre et une image du `Menu`, puis les redessine lui-même, image en tête : marges, fond et
  `strokeBorder` en tirets sont perdus, et le chevron passe devant le libellé. C'est pourquoi la
  chip active — dont l'étiquette est un `Text` nu — était conforme et les chips inactives non.
  Les deux ont été redessinées à la main.
- **`MainRouterTests` écrivait une soixantaine de plists dans les préférences réelles.** Chaque
  test créait un domaine `onetoone.tests.router.*` sans jamais le retirer ; corrigé par un
  `removePersistentDomain` en sortie.

## Ce que le chantier laisse

**Recette visuelle : faite, et conforme.** Les six écrans ont été photographiés lot par lot
(`recette/lot-N-p<code>.png`) **puis** repris ensemble sur le binaire de la pile complète
(`recette/finale/{p2a,p2b,p1a,p1c,p1d,p1f}.png`) — c'est cette seconde série qui fait foi. `p2a`,
le seul écran que le chantier n'avait jamais vu, est conforme : l'arbre a disparu, le chevron est
devant « Projets » comme la maquette le dessine, il n'y a pas de trou entre « RÉCENTS » et
« Collaborateurs » là où le `Section` a été retiré, les pastilles de statut sont présentes, et la
route reste stable après un redimensionnement de fenêtre — le défaut que `p1f` avait révélé ne
revient pas.

**Décisions produit, en attente de Laurent** : le titre « Projets » contre « Portfolio » ; la
ligne du semis qui donnerait « il y a 41 j » à NEVIDIS ; l'ordre des épinglés ; le badge « Mails 12 » sans source ; l'ordre alphabétique de
`SearchPopover` ; les pilules de l'en-tête de l'écran projet, non éditables au clic ; les deux
gestes qui ne demandent rien (« Démarrer une réunion » et « Planifier » créent une réunion vide
au deuxième clic accidentel).

**Dettes techniques** — la table complète est dans `docs/architecture.md` §13. Les principales :

- **Le coût des écrans sur le store réel n'est pas mesuré** : quatre `@Query` globales dans
  `PortfolioView`, trois de plus dans `ProjectScreen`, et trois constructeurs qui traversent
  toutes les réunions du store à chaque rechargement. Sur le semis (76 projets, 82 réunions)
  c'est instantané ; sur le portefeuille réel de Laurent, personne n'a chronométré.
- **`ReportSearch` n'a pas d'index** : il balaye les transcriptions de toutes les réunions à
  chaque ouverture de l'écran.
- **`ProjectCardDraft.apply` requête toute la table à chaque édition** — `Entity`, puis
  `Collaborator` deux fois — même quand aucune relation n'a changé.
- **`try? context.save()` avale ses erreurs** dans `ProjectCardDraft`, `ProjectRelationWriter` et
  `ProjectBatchActions` : la bannière propose d'annuler ce qui n'a peut-être pas eu lieu. C'est
  le style de tout le dossier ; un chantier dédié les prendrait ensemble.
- **`MilestoneCell.none` est un piège de nom** : derrière un optionnel, `== .none` se résout en
  `Optional.none`. `.aucun` serait plus sûr.
- **Deux clés de préférences** : `sidebar.projectsExpanded` n'a plus de lecteur mais reste
  écrite chez les utilisateurs existants ; `sidebar.projectsSectionExpanded` applique son défaut
  à qui n'a jamais rien exprimé — l'absence de clé est indistinguable d'un choix.
- **`MainRoute.entity` porte un `PersistentIdentifier`** et non un identifiant stable, faute de
  `stableID` sur `Entity` : la route ne survit pas à un relancement.
- **`Sidebar.swift` reste hors du périmètre typographique** : 2 004 lignes dont 59 fontes
  système, réparties dans `DashboardView`, `EntityDetailView` et les vues Gantt qui cohabitent
  dans le fichier. Les entrées historiques de la barre (« Tableau de bord », « Actions »…) sont
  donc en fonte système à côté d'une section « Projets » en Plex — le handoff les déclare
  « inchangées ». Le découpage du fichier est la condition de la bascule.
- **`MainRouter.back()` et `history` n'ont aucun appelant applicatif** : seuls les tests les
  exercent. L'histoire est écrite à chaque `open` et bornée à vingt écrans, pour un retour que
  rien ne déclenche — ni raccourci, ni bouton, ni geste. Soit on livre le geste, soit on retire
  les deux.
- **Deux fenêtres principales partageraient `MainRouter.shared`.** `⌘N` n'est pas neutralisé et
  le `WindowGroup` de `ContentView` en accepte plusieurs : la seconde fenêtre afficherait la
  route de la première et la lui volerait au premier clic. Le singleton était le prix de
  `MenuBarController`, qui est un `NSObject` sans environnement ; `MainWindowRegistry` a le même
  présupposé — une fenêtre principale.
- **`AtRiskView` journalise par `print`** (`AtRiskView.swift:169`, création de réunion échouée),
  là où le reste du dossier avale ses erreurs en silence : deux politiques, aucune des deux
  n'étant celle du reste de l'application (`os.Logger`). À prendre avec le chantier « les
  écritures projet disent quand elles échouent ».
- **Le hook `documentation-apres-pr` n'a jamais déclenché** dans les sessions de ce chantier
  (il a été enregistré après leur démarrage) : son test de bout en bout dans une session neuve
  reste dû.

## Conséquences

**Positives.** La navigation de la fenêtre principale est une **valeur** et non une pile de
destinations inline ; toute règle métier du domaine projet est une fonction pure testée avant sa
vue ; il n'y a plus qu'une recherche de projets, plus qu'une table de risque, plus qu'un service
d'opérations en lot ; la barre latérale a cessé d'être un catalogue et tient en un écran ; sept
lots ont porté la suite de 3 111 à 3 582 tests (+471), sans en retirer aucun.

**Négatives.** `Sidebar.swift` reste un fichier de 2 004 lignes malgré 154 lignes retirées ;
trois écrans reconstruisent tout leur contenu à chaque changement de `@Query`, sans mesure sur
un store réel ; la fiche d'une entité n'a plus qu'un seul chemin depuis la fenêtre principale, et
si ce chemin est bien **rendu** dans `p1a`, personne ne l'a **cliqué**.

## Alternatives étudiées

- **Garder l'arbre par entité** (variante 2b du handoff, « à retenir si la suppression est jugée
  trop brutale pour la première livraison »). Elle a été livrée au lot 1 et **tenue quatre
  lots** : le temps de construire le Portfolio, la palette et les épinglés, c'est-à-dire les
  chemins qui devaient la remplacer. Écartée sur ce constat — deux navigations projets
  concurrentes, dont une que les trois autres rendaient inutile —, non sur une comparaison
  visuelle : 2a n'avait alors jamais été rendue à l'écran. La recette finale l'a confirmée
  **après** la décision.
- **Un `pinnedOrder` sur `Project`** pour reproduire l'ordre des épinglés de la maquette :
  écarté, une colonne de plus pour un ordre que rien d'autre ne lit.
- **Étendre `PortfolioFilters` à une liste de codes** pour que le pied affiche « 8 lignes sur
  62 » comme la capture : écarté, un modèle de filtre élargi pour une seule photographie.
- **`ModelContext.model(for:)` au lieu des `fetch`** de `ProjectCardDraft.apply` : écarté après
  essai — il rend un objet faulté quand l'identité vient d'un autre conteneur, ce qui rendait le
  test des relations vert isolément et rouge en suite complète.

## Suite

La fusion des huit PR (#53 → #60) dans l'ordre de la pile, après validation de Laurent. Puis deux
vérifications que ce chantier n'a pas pu faire : le **hook de documentation**, à éprouver de bout
en bout dans une session Claude Code neuve, et le **Portfolio sur le store réel** de Laurent,
dont le coût des `@Query` n'a été mesuré que sur le semis. Les décisions produit listées ci-dessus
attendent Laurent ; aucune ne bloque la fusion.
