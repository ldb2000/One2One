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
