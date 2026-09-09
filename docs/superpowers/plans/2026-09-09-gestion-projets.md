# Refonte de la gestion des projets — plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan lot by lot (one implementer per lot, Opus, isolated worktree, stacked PRs).
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** livrer les six écrans du handoff (2b, 1a, 1c, 1d, 1f, 2a) dans OneToOne, au pixel près,
sur un routeur de navigation nouveau, sans casser les 3 111 tests existants.

**Architecture:** un `MainRouter` observable remplace les `NavigationLink` inline de la sidebar ;
chaque écran est une vue mince sur un *builder* pur testé (`PortfolioBuilder`, `AtRiskBuilder`,
`ProjectPilotageBuilder`) ; les recherches, filtres et opérations en lot sont des services purs
partagés (`ProjectSearch`, `ProjectBatchActions`) ; l'édition passe par `ProjectCardDraft` étendu.

**Tech Stack:** SwiftUI + SwiftData (macOS 14+), SwiftPM, Swift Testing (suites en français),
IBM Plex embarqué (`Font.plexSans/plexMono`, `NSFont.plexSans`), `One2OneToken`, Scripts de recette
(`Scripts/recette-app.sh`, `Scripts/recette-run.sh --screen p<code>`).

**Spec:** `docs/superpowers/specs/2026-09-09-gestion-projets-design.md` (décisions D0–D18) ;
rendu de référence : `docs/superpowers/specs/gestion-projets-2026-09/handoff/README.md` et
`handoff/screenshots/*.png` (2×).

## Global Constraints

- Le handoff est l'autorité sur le rendu ; la spec sur l'intégration ; en conflit, la spec gagne
  (D2, D3, D8, D12, D13 la corrigent explicitement).
- Aucune couleur hors `One2OneToken`, aucune fonte hors `Font.plexSans/.plexMono` /
  `NSFont.plexSans` dans `Views/Navigation/`, `Views/Sidebar/`, `Views/Portfolio/`,
  `Views/Palette/`, `Views/Project/`, `Views/AtRisk/` (test de lecture des sources, D17).
  `inkMuted` jamais sous 11,5 pt.
- Toute règle métier est une fonction pure testée **avant** sa vue ; les vues ne calculent pas
  dans `body` (D11).
- `Project.phase/status/riskLevel/projectType` restent des `String` persistées ; les enums D14 ne
  sont pas persistées ; toute valeur inconnue s'affiche en neutre, jamais ne plante.
- Aucun `SchemaV4` : seuls des champs à valeur par défaut sont ajoutés (`Project.pinned`,
  `AppSettings.portfolioSavedViewsJSON`).
- Le semis de démonstration n'écrit que dans le home jetable (`CFFIXED_USER_HOME`) ; il est
  idempotent par `Project.code` ; il ne modifie jamais un projet existant.
- Une PR = un lot = une intention ; branche `feat/projets-lot-N-<slug>` basée sur la PR
  précédente ; commits conventionnels en français ; `swift test` complet vert avant PR ;
  `STATUS.md` mis à jour au dernier lot seulement (les lots intermédiaires ajoutent une ligne au
  `docs/superpowers/specs/gestion-projets-2026-09/journal-des-lots.md`).
- `DocumentationTests` verts à chaque lot : nouveaux modèles → inventaire §5 d'`architecture.md` ;
  nouveaux dossiers de `Views/` → §8 ; le skill `documenter-application` produit le paragraphe
  « Documentation » de la PR.
- Recette visuelle : `swift build -c release && Scripts/recette-app.sh /tmp/recette &&
  Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen p<code> --reset`, capture
  comparée à `handoff/screenshots/<code>-*.png`, un seul agent graphique à la fois, jamais pendant
  une réunion Teams, jamais par nom d'application (pid uniquement). Les captures vont dans
  `docs/superpowers/specs/gestion-projets-2026-09/recette/lot-N-p<code>.png`.
- Modèle des agents : implémenteurs et relecture finale sur **Opus** (demande de Laurent) ;
  relecteurs de lot sur Sonnet ; re-relectures ciblées sur Haiku.

---

## Lot 0 — Routeur, socle et semis (aucun rendu changé)

**Branche** `feat/projets-lot-0-routeur`, base `master`.

**Files:**
- Create: `OneToOne/Views/Navigation/MainRoute.swift`, `MainRouter.swift`, `MainDetailView.swift`
- Modify: `OneToOne/OneToOneApp.swift` (`ContentView` : `NavigationSplitView` avec
  `MainDetailView`, injection de `MainRouter`, largeur `min 170 / ideal 250 / max 320` — D13) ;
  `OneToOne/Views/Sidebar.swift` (`List(selection: $router.route)`, chaque `NavigationLink`
  devient une ligne `.tag(MainRoute.x)` ; `projectRow` sélectionne `.project(id, .pilotage)` qui
  affiche `ProjectDetailView` tant que le lot 4 n'existe pas) ; `OneToOne/Services/MenuBarController.swift:555`
  (`onSelectProject` → `router.open(.project(…))`)
- Create: `OneToOne/Services/Project/ProjectPhase.swift` (enums D14 : `ProjectPhase`,
  `ProjectStatus`, `ProjectType`, `RiskLevel`, chacune `init?(raw:)` tolérant + `label` +
  `allLabels`), `OneToOne/Services/Project/RecentProjects.swift`, `OneToOne/Models/Project.swift`
  (`var pinned: Bool = false`), `OneToOne/Models/AppSettings.swift`
  (`portfolioSavedViewsJSON: String = "[]"` + accesseur, struct `PortfolioSavedView: Codable`)
- Modify: `OneToOne/Views/DesignSystem/One2OneTokens.swift` (D12 : `paletteShadow`,
  `highlight`, `dashedBorder`) ; `Tests/One2OneTokensTests.swift` (contraste du surlignage)
- Modify: `OneToOne/Services/Debug/RecetteScreen.swift` (`Cible.fenetrePrincipale(MainRoute)`,
  cas `p2b`, `p1a`, `p1c`, `p1d`, `p1f`, `p2a` ajoutés dès maintenant avec leur route ; les écrans
  non encore livrés pointent sur `.portfolio` et sont marqués `enAttente`) ;
  `OneToOne/OneToOneApp.swift` `ouvrirEcranDeRecette` (fenêtre principale + `router.open`)
- Create: `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Portfolio.swift` — 62 projets actifs
  sur 8 entités (ASP, RH, FIN, SI, LOG, COM, JUR, DSI), 14 archivés, codes `P25_001…P25_076`,
  noms et valeurs de la capture 1a en tête (`ASP – BLOOM P25_112`, `AE – Gestion des services IO
  pour l'association ALP P25_193`, `ASP – Installation nouvelle GED P25_087`, `ASP – Sécurisation
  des flux inter-sites P25_140`, `ASP – Intégration « NEVIDIS » Filiale P25_155`, `ASP – Mise en
  place d'une infrastructure de sauvegarde P25_061`, `ASP – Obsolescence de la VM applicative
  P25_099`, `ASP – Sécurisation IBMi Netserver P25_121`, `RH – TIME & APPLI`, `FIN – Refonte
  facturation fournisseurs`, `RH – Migration GED documentaire P24_211`), phases / risques / chefs
  de projet **liés** (`projectManager`) aux collaborateurs de la capture (RIGAUT Manuel, PENVEN
  Yann, THEDREZ Wilfried, ORSET Jean-Baptiste, PAOLI Nicolas, NOMINE Laurent, ZANNETTINI
  François-Louis), 3 projets épinglés, réunions datées pour « Dernière réunion » (il y a 3 j, hier,
  8 j, 2 sem., jamais, 5 j, 4 j, 1 mois), jalons (J−4, J−21, retard, J−35…), actions ouvertes /
  en retard pour `P25_193` (6 dont 2 en retard, libellés de la capture 1d), 2 jalons dépassés, 3
  projets sans réunion depuis 30 j, 2 fiches incomplètes (capture 1f), mails liés (2) et 3
  `MailIndexSuggestion` pour `P25_193`.
- Test: `Tests/MainRouterTests.swift`, `Tests/ProjectPhaseTests.swift`,
  `Tests/RecentProjectsTests.swift`, `Tests/PortfolioSavedViewTests.swift`,
  `Tests/RefonteDemoSeedPortfolioTests.swift`, `Tests/RecetteScreenTests.swift` (codes uniques,
  préfixe `p`), `Tests/RefonteTypographieTests.swift` (périmètres étendus, D17)

**Interfaces (produites, exactes) :**

```swift
enum ProjectTab: String, CaseIterable, Sendable { case pilotage, meetings, actions, mails, documents, fiche }
enum MainRoute: Hashable, Sendable {
    case dashboard, assistant, actions, meetings, notes, manager, collaborators, settings
    case portfolio, atRisk, projectMeetings, projectActions, searchReports(String)
    case project(UUID, ProjectTab), collaborator(UUID), entity(UUID)
}
@MainActor @Observable final class MainRouter {
    var route: MainRoute? = .dashboard
    private(set) var history: [MainRoute] = []      // max 20
    func open(_ route: MainRoute)                   // pousse l'ancienne dans history
    func back()
    func openProject(_ project: Project, tab: ProjectTab = .pilotage)   // ensuredStableID + RecentProjects.push
}
enum RecentProjects {
    static let key = "projects.recentIDs"; static let max = 5
    static func push(_ id: UUID, into raw: String) -> String   // FIFO, sans doublon, séparateur ","
    static func ids(from raw: String) -> [UUID]
}
struct PortfolioSavedView: Codable, Equatable, Identifiable { var id: UUID; var name: String; var filters: PortfolioFilters; var sort: PortfolioSort }
struct PortfolioFilters: Codable, Equatable { var entities: Set<String>; var phases: Set<String>; var statuses: Set<String>; var riskAtLeast: String?; var managers: Set<String>; var text: String }
struct PortfolioSort: Codable, Equatable { enum Column: String, Codable { case name, entity, phase, risk, manager, milestone, lastMeeting }; var column: Column; var ascending: Bool }
enum ProjectPhase: String, CaseIterable { case cadrage = "Cadrage", design = "Design", build = "Build", run = "Run"; init?(raw: String) /* insensible casse/accents */ }
// ProjectStatus (Green/Yellow/Red/Unknown), ProjectType (Métier/Transverse/Technique), RiskLevel (Faible/Modéré/Élevé/Critique) : même forme.
```

- [ ] **Tests d'abord** : `MainRouterTests` (open pousse dans history, back dépile, history bornée
  à 20, `openProject` pousse dans les récents) ; `RecentProjectsTests` (FIFO 5, doublon remonté en
  tête, chaîne vide) ; `ProjectPhaseTests` (`init?(raw: "cadrage")`, `"Réalisation"` → nil) ;
  `PortfolioSavedViewTests` (aller-retour JSON, accesseur d'`AppSettings` tolère un JSON corrompu →
  `[]`) ; `RefonteDemoSeedPortfolioTests` (62 actifs + 14 archivés, idempotent, ne touche pas un
  projet homonyme existant, `P25_193` a 6 actions ouvertes dont 2 en retard) ; `RecetteScreenTests`
  (rawValues uniques, tous `[0-9a-z]+`).
- [ ] Implémenter ; migrer les `NavigationLink` de `Sidebar.swift` un par un en conservant le
  rendu (vérifier à l'œil que Tableau de bord, Actions, Réunions, Collaborateurs, Archives,
  Paramètres s'ouvrent encore) ; `MainDetailView` route `.project(id, _)` vers
  `ProjectDetailView(project:)` résolu par `stableID`.
- [ ] `swift test` complet vert ; `DocumentationTests` : `architecture.md` §8 mentionne
  `Views/Navigation/`, §5 inchangé (aucun modèle nouveau).
- [ ] Journal des lots ; PR `feat(projets): lot 0 — routeur de navigation, socle et semis Portfolio`
  avec ADR `docs/adr/2026-09-09-routeur-de-navigation.md` (D0).

## Lot 1 — Sidebar 2b : section « Projets »

**Branche** `feat/projets-lot-1-sidebar`, base lot 0. **Recette** `p2b` vs
`2b-sidebar-variante-arbre-replie.png`.

**Files:**
- Create: `OneToOne/Views/Sidebar/ProjectsSidebarSection.swift` (section, quatre entrées,
  badges), `PinnedProjectsList.swift`, `RecentProjectsList.swift`,
  `OneToOne/Services/Project/ProjectSearch.swift`, `OneToOne/Services/Project/SidebarProjectCounts.swift`
- Modify: `Sidebar.swift` (insertion de la section entre « Tous les Collaborateurs » et
  « Collaborateurs » ; `@AppStorage("sidebar.projectsSectionExpanded") = true` ; l'arbre passe à
  `false` par défaut ; `projectMatches` délègue à `ProjectSearch`)
- Test: `Tests/ProjectSearchTests.swift`, `Tests/SidebarProjectCountsTests.swift`,
  `Tests/ProjectsSidebarSectionTests.swift` (libellés au mot près : « Portfolio », « À risque »,
  « Mes réunions projets », « Actions projets », « ÉPINGLÉS », « RÉCENTS » ; icônes
  `square.grid.3x3.fill`, `diamond.fill`, `clock`, `line.3.horizontal`)

**Interfaces :**

```swift
enum ProjectSearch {
    static func matches(_ p: Project, query: String, notes: [Meeting] = []) -> Bool   // nom, code, domaine, sponsor, chef de projet (relation puis chaîne), architecte, notes
    static func rank(_ projects: [Project], query: String) -> [Project]                // préfixe > mot > sous-chaîne ; épinglés d'abord ; puis nom
    static func highlightRanges(in text: String, query: String) -> [Range<String.Index>]
}
struct SidebarProjectCounts: Equatable { var active: Int; var atRisk: Int; var openProjectActions: Int
    static func compute(projects: [Project], meetings: [Meeting], tasks: [ActionTask], today: Date) -> SidebarProjectCounts }  // atRisk = AtRiskBuilder.count (lot 5 : stub = jalons dépassés + fiches incomplètes)
```

- [ ] Tests d'abord (recherche : sponsor et chef de projet trouvés ; rang ; compteurs sur le semis).
- [ ] Vue : `Section` + `DisclosureGroup` ; entrée sélectionnée fond `action`, texte blanc,
  radius 6 ; badges mono ; « À risque » badge `report` ; sous-titres `.sectionLabel()` ; pastille
  10 px `StatusIcon` (jetons, lot 2 la migre : ici on réutilise la version existante avec taille
  10 et couleurs jetons — faire la migration de `StatusIcon` **dans ce lot** si plus simple, et le
  dire dans la PR).
- [ ] Récents : `RecentProjects.ids(from:)` résolus par `stableID`, nom seul.
- [ ] Recette `p2b` ; comparer largeur 250, ordre des entrées, badges 62 / 7 / 23.
- [ ] PR `feat(projets): lot 1 — section Projets de la sidebar (variante 2b)`.

## Lot 2 — Portfolio 1a

**Branche** `feat/projets-lot-2-portfolio`, base lot 1. **Recette** `p1a` vs `1a-portfolio.png`
(état : filtre Entité : ASP actif, tri Projet ↑, vue enregistrée « Mes projets ASP »).

**Files:**
- Create: `OneToOne/Services/Project/PortfolioBuilder.swift`, `PortfolioRow.swift`,
  `ProjectBatchActions.swift`, `ProjectPeople.swift`, `OneToOne/Views/Portfolio/PortfolioView.swift`,
  `PortfolioHeader.swift`, `PortfolioFilterBar.swift` (champ 230 px, chips actives / inactives en
  tirets `dashedBorder`, menus de valeurs), `SavedViewMenu.swift`, `PortfolioTable.swift` (en-tête
  30 px `.sectionLabel()`, lignes 44 px alternées `surface`/`surfaceAlt`, colonnes
  `22 | 1fr | 88 | 92 | 88 | 126 | 78`, tri par clic), `PhaseBadge.swift`, `RiskBadge.swift`,
  `ProjectBatchBar.swift`, `PortfolioGroupedView.swift` (segment « Groupé par entité »),
  `OneToOne/Views/DesignSystem/StatusIcon.swift` (migré, D16)
- Delete: `OneToOne/Views/ProjectListView.swift` (après extraction de `StatusIcon`)
- Modify: `Sidebar.swift` (`multiSelectBar` → `ProjectBatchBar` + `ProjectBatchActions`)
- Test: `Tests/PortfolioBuilderTests.swift` (lignes, filtres ET, tri chaque colonne, « Dernière
  réunion » relative : « hier », « il y a 3 j », « il y a 2 sem. », « il y a 1 mois », « jamais » ;
  jalon `J−4` / `retard` / `—`), `Tests/ProjectBatchActionsTests.swift`,
  `Tests/ProjectPeopleTests.swift`, `Tests/PortfolioViewTests.swift` (libellés : « Projets »,
  « actifs · entités · archivés », « Tableau », « Groupé par entité », « ＋ Nouveau projet »,
  « Nom, code, sponsor... », « Vue enregistrée », en-têtes de colonnes, pied « lignes sur »)

**Interfaces :**

```swift
struct PortfolioRow: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier; let stableID: UUID; let name, code, type: String; let entity: String?
    let phase: ProjectPhase?; let phaseRaw: String; let status: ProjectStatus?; let risk: RiskLevel?
    let manager: String?; let nextMilestone: MilestoneCell   // enum: .days(Int) / .late / .none
    let lastMeeting: Date?; let lastMeetingLabel: String; let pinned: Bool
}
enum PortfolioBuilder {
    static func rows(projects: [Project], meetings: [Meeting], today: Date) -> [PortfolioRow]
    static func apply(_ filters: PortfolioFilters, to rows: [PortfolioRow]) -> [PortfolioRow]
    static func sort(_ rows: [PortfolioRow], by sort: PortfolioSort) -> [PortfolioRow]
    static func relativeLabel(from date: Date?, today: Date) -> String
    static func summary(projects: [Project]) -> String   // "62 actifs · 8 entités · 14 archivés"
}
enum ProjectPeople { static func manager(of p: Project) -> String?; static func architect(of p: Project) -> String?
    static func suggestedManager(for p: Project, among: [Collaborator]) -> Collaborator? }   // D3
@MainActor enum ProjectBatchActions {
    static func setPhase(_ raw: String, on: [Project]); static func setStatus(_ raw: String, on: [Project])
    static func setEntity(_ e: Entity?, on: [Project]); static func archive(_:), delete(_:in:) }
```

- [ ] Tests d'abord ; `PortfolioModel` (`@Observable`) recalcule sur changement des `@Query`.
- [ ] Vue ; badges de phase / risque aux couples du handoff (Faible = `ink4` neutre, D2) ; état
  vide « Aucun projet ne correspond » ; ⇧-clic → barre en lot.
- [ ] `SearchPopover` inchangé ici (lot 3).
- [ ] Recette `p1a` ; PR `feat(projets): lot 2 — Portfolio (tableau, facettes, vues enregistrées)`.

## Lot 3 — Palette ⌘K 1c

**Branche** `feat/projets-lot-3-palette`, base lot 2. **Recette** `p1c` vs `1c-palette-cmdk.png`
(terme « ged », première ligne sélectionnée).

**Files:**
- Rename: `OneToOne/Views/Menus/MeetingShortcut.swift` → `AppShortcut.swift` (`enum AppShortcut`,
  cas `palette` ⌘K, `assistant` ⌘⇧K, les autres inchangés ; `typealias MeetingShortcut = AppShortcut`
  le temps du lot puis suppression) ; `Tests/MeetingShortcutsTests.swift` → `AppShortcutsTests.swift`
  (liste des jetons + déclarants mis à jour, suite renommée « Raccourcis de l'application »)
- Modify: `MeetingCommands.swift` (item « Palette… » ⌘K, « Assistant… » ⌘⇧K),
  `SessionAssistantPanel.swift:41` (⌘⇧K), spec réunion amendée par ADR
  `docs/adr/2026-09-09-palette-commande-k.md` (D1)
- Create: `OneToOne/Views/Palette/CommandPalette.swift` (feuille 560 px, champ 44 px / 15 pt,
  pastille `esc`, groupes « PROJETS » / « ACTIONS », lignes, pied), `PaletteRow.swift`,
  `OneToOne/Services/Project/PaletteModel.swift` (résultats : `ProjectSearch.rank` limité à 6,
  actions « Créer un projet « x » », « Chercher « x » dans les CR »), `HighlightedText.swift`
  (surlignage `highlight`), `OneToOne/Views/Search/ReportSearchView.swift` +
  `OneToOne/Services/Project/ReportSearch.swift` (D8 : `Meeting.textualContent`, hors notes,
  groupé par projet, extrait ±60 caractères surligné)
- Modify: `SearchPopover.swift` et `MeetingsListView.MeetingsProjectFilterPicker` → `ProjectSearch`
- Test: `Tests/PaletteModelTests.swift` (résultats, actions, `⌘↩` bascule `pinned`, `↩` ouvre),
  `Tests/ReportSearchTests.swift`, `Tests/CommandPaletteTests.swift` (libellés : « esc », « PROJETS »,
  « ACTIONS », « ↑↓ naviguer · ↩ ouvrir · ⌘↩ épingler »), `AppShortcutsTests`

- [ ] Tests d'abord ; ⌘K depuis n'importe quel écran (`.commands`) ; `esc` ferme ; ↑↓ ; `↩` →
  `router.openProject` ; `⌘↩` épingle sans fermer.
- [ ] Recette `p1c` (ouverture programmée par `RecetteScreen`, terme « ged » injecté).
- [ ] PR `feat(projets): lot 3 — palette ⌘K et recherche dans les CR`.

## Lot 4 — Écran projet 1d

**Branche** `feat/projets-lot-4-ecran-projet`, base lot 3. **Recette** `p1d` vs
`1d-ecran-projet-pilotage.png` (projet `P25_193`, onglet Pilotage).

**Files:**
- Create: `OneToOne/Views/Project/ProjectScreen.swift` (fil d'Ariane mono 11 pt, en-tête 21 pt,
  pilules, boutons « ☆ Épingler » / « Démarrer une réunion » / `···`, onglets 13 pt soulignés 2 px),
  `ProjectHeader.swift`, `ProjectTabs.swift`, `Pilotage/PilotageTab.swift` (grille `1fr / 330`,
  gap 16, padding 16/22), `Pilotage/KPITiles.swift` (Actions ouvertes, Dernière réunion, Rythme
  8 barres 7 px dégradé `okBg → ok`, Charge barre 4 px), `Pilotage/OpenActionsCard.swift`,
  `Pilotage/RecentMeetingsCard.swift`, `Pilotage/ScopeCard.swift` (édition in-place),
  `Pilotage/SideColumn.swift` (Interlocuteurs 26 px, Risque + Modifier, Mails liés + encart
  `MailIndexSuggestion`, Identité + « Voir la fiche complète »), `Tabs/ProjectMeetingsTab.swift`
  (liste des réunions du projet, réutilise les lignes de `MeetingsListView`),
  `Tabs/ProjectActionsTab.swift` (`ActionsListView` filtré par projet), `Tabs/ProjectMailsTab.swift`
  (`Project.mails` triés + bouton « Rattacher des mails » → `MailSuggestionReviewSheet`),
  `Tabs/ProjectDocumentsTab.swift` (bloc pièces jointes extrait de `ProjectDetailView:214-313`),
  `OneToOne/Services/Project/ProjectPilotageBuilder.swift`, `MeetingTypeBadge.swift`,
  `OneToOne/Views/DesignSystem/EditableInPlace.swift` (modificateur D9)
- Modify: `OneToOne/Services/Project/ProjectCardDraft.swift` (champs D9 ; `apply` étendu),
  `ProjectCardPanel.swift` (`meeting: Meeting?`), `DetailsViews.swift` (`ProjectDetailView`
  devient le contenu de l'onglet « Fiche complète » sans sa heatmap ni sa toolbar ; boutons
  Archiver / Supprimer passent dans le menu `···` avec confirmation), `MainDetailView.swift`
  (`.project(id, tab)` → `ProjectScreen`), `AvatarStack` (taille paramétrable)
- Delete: `OneToOne/Views/MeetingHeatmapView.swift` si plus aucun appelant (vérifier
  `CollaboratorFicheView`) ; sinon laisser et le dire.
- Test: `Tests/ProjectPilotageBuilderTests.swift` (tuiles, actions triées retard d'abord, rythme
  12 semaines / 8 barres, charge, dernières réunions 3, mails 3), `Tests/MeetingTypeBadgeTests.swift`,
  `Tests/ProjectCardDraftTests.swift` (nouveaux champs, aller-retour), `Tests/EditableInPlaceTests.swift`,
  `Tests/ProjectScreenTests.swift` (libellés : onglets, « ACTIONS OUVERTES », « DERNIÈRE RÉUNION »,
  « RYTHME », « CHARGE », « ACTIONS EN COURS », « Tout voir », « DERNIÈRES RÉUNIONS »,
  « Historique », « PÉRIMÈTRE & CONTEXTE », « INTERLOCUTEURS », « RISQUE », « MAILS LIÉS »,
  « IDENTITÉ », « Voir la fiche complète », « Épingler », « Démarrer une réunion »)

**Interfaces :**

```swift
struct ProjectPilotageState: Equatable {
    var openActions: Int; var lateActions: Int; var lastMeeting: (date: Date, label: String, kindLine: String)?
    var rhythm: [Int]            // 8 barres, 12 semaines
    var charge: (spent: Double?, planned: Double?)
    var actions: [ActionRow]     // ≤ 4, en retard d'abord
    var meetings: [MeetingRow]   // ≤ 3
    var mails: [MailRow]; var pendingMailSuggestions: Int
    var deadlineAlert: String?   // "Deadline design 09/09/2026 — J−0" si ≤ 7 j
}
enum ProjectPilotageBuilder { static func build(project: Project, meetings: [Meeting], suggestions: [MailIndexSuggestion], today: Date) -> ProjectPilotageState }
enum MeetingTypeBadge { case copil, atelier, oneOnOne; static func from(_ m: Meeting) -> MeetingTypeBadge? }
```

- [ ] Tests d'abord ; « Démarrer une réunion » crée un `Meeting(kind: .project, project:)` et ouvre
  la fenêtre de réunion par `OneToOneLaunchToken` (mécanisme existant) ; « 1:1 ▸ » →
  `router.open(.collaborator(id))` ; « Tout voir » → onglet Actions.
- [ ] Recette `p1d` ; PR `feat(projets): lot 4 — écran projet de pilotage` + ADR
  `docs/adr/2026-09-09-edition-in-place-fiche-projet.md` (D9).

## Lot 5 — Vue « À risque » 1f

**Branche** `feat/projets-lot-5-a-risque`, base lot 4. **Recette** `p1f` vs `1f-vue-a-risque.png`.

**Files:**
- Create: `OneToOne/Services/Project/AtRiskBuilder.swift`, `OneToOne/Views/AtRisk/AtRiskView.swift`,
  `AtRiskGroup.swift` (titre `.sectionLabel()` teinté, carte, bord gauche 3 px)
- Modify: `SidebarProjectCounts` (le stub du lot 1 devient `AtRiskBuilder.count`)
- Test: `Tests/AtRiskBuilderTests.swift` (trois motifs, un projet peut apparaître dans plusieurs
  groupes ; `MilestoneState.late` saisi compte comme dépassé même si `dueAt` futur ; « Aucune
  réunion enregistrée » ; libellés « échue depuis N j », « Dernière réunion il y a N j », « Sponsor
  non renseigné », « Pas de chef de projet · statut inconnu »), `Tests/AtRiskViewTests.swift`
  (« JALON DÉPASSÉ — n », « SANS RÉUNION DEPUIS 30 J — n », « FICHE INCOMPLÈTE — n », « Replanifier »,
  « Planifier », « Compléter », sous-titre « n projets demandent une décision »)

```swift
struct AtRiskItem: Identifiable, Equatable { let id: String; let project: PersistentIdentifier; let stableID: UUID; let title: String; let detail: String; let action: AtRiskAction }
enum AtRiskAction { case replan(milestone: PersistentIdentifier), schedule, complete(field: IncompleteField) }
enum IncompleteField { case sponsor, manager, status }
struct AtRiskReport: Equatable { var overdueMilestones: [AtRiskItem]; var silent30Days: [AtRiskItem]; var incomplete: [AtRiskItem]; var projectCount: Int }
enum AtRiskBuilder { static func build(projects: [Project], meetings: [Meeting], today: Date) -> AtRiskReport }
```

- [ ] Tests d'abord ; « Replanifier » ouvre l'écran projet, onglet Fiche complète, jalon en édition
  (via `ProjectCardDraft`) ; « Planifier » crée une réunion projet datée à aujourd'hui + 7 j et
  ouvre l'écran projet ; « Compléter » ouvre l'écran projet avec le champ ciblé actif et, pour le
  chef de projet, `ProjectPeople.suggestedManager` prérempli (D3).
- [ ] Recette `p1f` ; PR `feat(projets): lot 5 — vue À risque`.

## Lot 6 — Bascule 2a et clôture

**Branche** `feat/projets-lot-6-bascule-2a`, base lot 5. **Recette** `p2a` vs
`2a-sidebar-section-projets.png`.

- [ ] Retirer le `DisclosureGroup` « Projets par Entité » (`Sidebar.swift:333-397`), la clé
  `sidebar.projectsExpanded`, `expandedEntityNames`, `moveProjects(codes:)`,
  `moveProjectsToNone`, `.draggable(project.code)` ; « Déplacer vers une entité » dans
  `ProjectBatchBar` (déjà présent : vérifier) ; `EntityDetailView` reste atteignable par
  `.entity(id)` depuis le Portfolio groupé.
- [ ] `RefonteTypographieTests` : `Sidebar.swift` entre dans le périmètre s'il ne reste plus de
  fonte système (sinon dire ce qui reste).
- [ ] `docs/architecture.md` §8 / §13 réalignés (tailles réelles, `ProjectListView` retirée,
  `MailBrowserView` sortie du code mort), `docs/glossaire.md` (Portfolio, Palette, À risque),
  `STATUS.md` section en tête, ADR de clôture `docs/adr/2026-09-09-gestion-projets-bilan.md`.
- [ ] Recette des six écrans sur le binaire final (`recette/finale/`), tableau des écarts.
- [ ] PR `feat(projets): lot 6 — bascule sidebar 2a et clôture`.

## Protocole d'exécution (rappel)

1. Un lot = un agent implémenteur Opus dans un worktree `.claude/worktrees/projets-lot-N`, base
   = tête de la PR précédente ; brief = section du lot + spec + handoff ; il ne dispatch pas de
   sous-agent ; il ne fait **jamais** de capture pendant qu'un autre agent en fait.
2. Relecture par lot (Sonnet) : conformité au handoff (capture côte à côte), tests, contraintes
   globales ; jusqu'à cinq tours de correction.
3. Passe d'intégration si `master` a bougé : rebase de la pile, `swift test`.
4. Fusion : `gh pr edit N --base master` puis `gh pr merge N --merge`, une commande par PR, dans
   l'ordre des lots, après validation de Laurent.
