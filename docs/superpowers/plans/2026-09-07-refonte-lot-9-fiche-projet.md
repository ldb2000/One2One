# Lot 9 — Fiche projet en panneau (3b) — plan d'exécution

> **Pour un exécutant sans contexte :** compétence requise
> `superpowers:subagent-driven-development` ou `superpowers:executing-plans`.
> Les étapes sont cochables (`- [ ]`).

**Objectif :** ouvrir la fiche du projet dans un panneau de 430 px glissant depuis la droite,
éditable en séance (statut, budget, jalons, périmètre, tags, risques, interlocuteurs), avec
suggestions de l'assistant **jamais appliquées d'office** et enregistrement optimiste annulable.

**Architecture :** trois couches strictement séparées.
1. **Règles pures, testées d'abord** — `ProjectCardBuilder` (état d'affichage depuis `Project`),
   `ProjectCardDraft` (brouillon détaché du modèle SwiftData), `ProjectCardSuggestions`
   (prompt + parsing JSON strict, `AIClientProtocol` injecté).
2. **Vues** — `ProjectCardPanel` (430 px) et ses sous-vues, plus `UndoBanner` réutilisable.
3. **Câblage** — une propriété en fin de `MeetingScreenModel`, le segment projet du fil
   d'Ariane, un overlay en fin de `mainPanel`, un résumé dans `MeetingPrepareSpace`.

**Pile :** Swift 6, SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`) + XCTest existant.
Exécutable SwiftPM : `swift build`, `swift test`.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §4.3 et critère du
chantier 3 n° 4 ; plan directeur
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §2.2, §3, §5 « Lot 9 », §7, §8 ;
capture qui fait foi : `docs/superpowers/specs/refonte-2026-09/ecrans/3b-fiche-projet.png`.

## Contraintes globales

- **Aucune couleur hors `OneToOne/Views/DesignSystem/One2OneTokens.swift`.** C'est le seul
  fichier autorisé à nommer une couleur. L'ombre du panneau (`-8px 0 24px rgba(0,0,0,.07)`)
  y devient trois jetons.
- **Aucune dépendance SwiftPM nouvelle.**
- **Aucune nouvelle version de schéma.** `SchemaV3` du lot 0B porte déjà `ProjectMilestone`,
  `ProjectContact`, `Project.scopeText` et `Project.tagsJSON`. Seules des colonnes à valeur
  par défaut sont admises, et ce lot n'en ajoute aucune.
- **Libellés d'interface et commentaires en français, symboles en anglais.**
- **Jamais d'écriture automatique sur `Project`** : ni depuis l'assistant, ni depuis le
  brouillon. Deux tests le prouvent (critère chantier 3 n° 4).
- **Frontières avec les lots parallèles :** ne pas toucher
  `Views/Meeting/Spaces/MeetingLiveSpace.swift`, `Spaces/Notes/**`, `Spaces/Transcript/**`,
  `Spaces/Rail/**`, `Spaces/AudioTimelineStrip.swift`, `ActionsPanel`, `OwnerPickerMenu`,
  `CalendarBoard`, `EisenhowerBoard`. Dans `MeetingScreenModel.swift`, ajouter **en fin de
  type**. Dans `MeetingView.swift`, deux modifications d'une ligne seulement.
- **Aucun test ne touche MLX, le réseau ou une session graphique.** L'IA passe par un
  `AIClientProtocol` factice.
- Énums persistées SwiftData en `…Raw: String` + wrapper calculé.
- Géométrie de la spec §1.2 : panneau 430 px (`One2OneToken.projectPanelWidth`, déjà présent),
  rayon de panneau 10, cartes 7, chips 5, padding de carte 9–13, `gap` 11–13.

## Carte des fichiers

**Créés**
| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/Project/ProjectCardBuilder.swift` | Règles pures : statut ↔ `ok/watch/risk`, ratio et couleur de budget, tri et rendu des jalons, risques, interlocuteurs. Produit `ProjectCardState`. |
| `OneToOne/Services/Project/ProjectCardDraft.swift` | `struct ProjectCardDraft` : instantané éditable détaché du modèle, `apply(to:)`, `snapshot(of:)`, égalité. |
| `OneToOne/Services/Project/ProjectCardSuggestions.swift` | Prompt, appel `AIClientProtocol`, parsing JSON strict, `ProjectCardUpdate`. Jamais d'écriture. |
| `OneToOne/Views/Project/ProjectCardPanel.swift` | Le panneau 430 px : en-tête, statut, budget, jalons, périmètre, risques, interlocuteurs, encart assistant, pied. |
| `OneToOne/Views/Project/ProjectCardSuggestionsSheet.swift` | Feuille de diff champ par champ, `Accepter` / `Ignorer` par ligne. |
| `OneToOne/Views/DesignSystem/Components/Refonte/UndoBanner.swift` | Bannière `… · Annuler` à durée bornée, réutilisable. |
| `Scripts/recette-app.sh` | Empaquette un `.app` de recette depuis `.build/release`. N'incrémente rien, n'installe rien. |
| `Scripts/recette-run.sh` | Lance ce `.app` avec un `HOME` temporaire ; `--seed` pose `ONETOONE_SEED_DEMO=1`. |
| `Tests/ProjectCardBuilderTests.swift` | Mapping statut, ratio et couleur de budget, jalon bloqué, tri. |
| `Tests/ProjectCardDraftTests.swift` | Annuler restaure, enregistrer applique, instantané d'annulation. |
| `Tests/ProjectCardSuggestionsTests.swift` | Parsing valide/vide/malformé, aucune écriture sans acceptation. |

**Modifiés**
| Fichier | Modification |
| --- | --- |
| `OneToOne/Views/DesignSystem/One2OneTokens.swift` | Trois jetons d'ombre de panneau + un voile de dépoli (55 %). |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | `showProjectCard` **en fin de type**. |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | Segment projet : chevron `⌄` et infobulle « Ouvrir la fiche du projet ». |
| `OneToOne/Views/MeetingView.swift` | `onOpenProject:` pointe la fiche ; overlay du panneau en fin de `mainPanel`. |
| `OneToOne/Views/Meeting/Spaces/MeetingPrepareSpace.swift` | Section « FICHE PROJET » (statut, budget, jalons < 30 j, risques élevés) + `Ouvrir la fiche`. |
| `OneToOne/Services/Meeting/MeetingPrepareBuilder.swift` | `MeetingPrepareContext.projectCard: ProjectCardState?`. |
| `OneToOne/Services/Debug/RefonteDemoSeed.swift` | Budget 40 000 / 61 000, 3 jalons, 3 interlocuteurs, périmètre, 4 tags. |
| `OneToOne/OneToOneApp.swift` | `ONETOONE_SEED_DEMO=1` → semis au démarrage. |
| `Tests/RefonteDemoSeedTests.swift` | Vérifie les nouveaux chiffres de la fiche. |
| `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` | §7 étape 6 : une phrase sur les deux scripts. |
| `STATUS.md` | Section de tête du lot 9. |

---

### Tâche 1 : jetons d'ombre et de dépoli

**Fichiers :** Modifier `OneToOne/Views/DesignSystem/One2OneTokens.swift`,
`Tests/One2OneTokensTests.swift`.

**Interfaces produites :** `One2OneToken.panelShadow: Color`,
`panelShadowRadius: CGFloat`, `panelShadowOffsetX: CGFloat`, `dimmedOpacity: Double`.

- [ ] **Étape 1 :** écrire le test qui échoue dans `Tests/One2OneTokensTests.swift` :
  l'ombre vaut `rgba(0,0,0,.07)`, le rayon 24, le décalage −8, l'opacité de dépoli 0,55.
- [ ] **Étape 2 :** `swift test --filter One2OneTokens` → échec « no member `panelShadow` ».
- [ ] **Étape 3 :** ajouter les quatre jetons dans la section « Cas particuliers », avec le
  commentaire expliquant pourquoi ils vivent là (même raison que `scrim`).
- [ ] **Étape 4 :** `swift test --filter One2OneTokens` → vert.
- [ ] **Étape 5 :** `git commit -m "feat(refonte): jetons d'ombre de panneau et de dépoli"`.

### Tâche 2 : `ProjectCardBuilder`

**Fichiers :** Créer `OneToOne/Services/Project/ProjectCardBuilder.swift`,
`Tests/ProjectCardBuilderTests.swift`.

**Interfaces produites :**

```swift
enum ProjectCardStatus: String, CaseIterable, Sendable { case ok, watch, risk }
// libellés : « Sous contrôle », « À surveiller », « En risque » ;
// `ProjectCardStatus(projectStatus:)` : Green→ok, Yellow→watch, Red→risk, tout autre→watch.
// `projectStatusRaw` : ok→"Green", watch→"Yellow", risk→"Red".

enum BudgetTone: Sendable { case ok, warn, report }   // < 70 %, < 90 %, ≥ 90 %

struct ProjectCardState: Equatable, Sendable {
    var name, reference, statusLabel: String
    var status: ProjectCardStatus
    var statusIsQualified: Bool          // faux quand Project.status == "Unknown"
    var meetingCount: Int
    var lastUpdateText: String           // « dernière mise à jour aujourd'hui par vous »
    var budget: Budget?                  // nil quand aucun total connu
    var milestones: [Milestone]
    var scopeText: String
    var tags: [String]
    var risks: [Risk]
    var contacts: [Contact]

    struct Budget: Equatable, Sendable {
        var spent, total: Double
        var ratio: Double                // borné 0…1 pour la barre
        var tone: BudgetTone
        var text: String                 // « 40 000 € / 61 000 € »
    }
    struct Milestone: Equatable, Sendable, Identifiable {
        var id: UUID
        var label: String
        var state: MilestoneState
        var trailingText: String         // « 30 sept. » ou « bloqué »
        var isBlocked: Bool              // state == .late
    }
    struct Risk: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var level: Int                   // 0 = critique … 3 = faible
    }
    struct Contact: Equatable, Sendable, Identifiable {
        var id: UUID
        var name, role: String
        var text: String                 // « Olivier Freund — partenaire, décideur »
    }
}

enum ProjectCardBuilder {
    @MainActor static func build(project: Project, meetings: [Meeting], now: Date = Date()) -> ProjectCardState
    static func tone(ratio: Double) -> BudgetTone
    static func budgetText(spent: Double, total: Double) -> String
    static func sortedMilestones(_ m: [ProjectMilestone]) -> [ProjectMilestone]
}
```

- [ ] **Étape 1 :** écrire `Tests/ProjectCardBuilderTests.swift` — huit tests :
  mapping des quatre statuts (`Unknown` → `watch` + « À qualifier », `statusIsQualified` faux) ;
  `tone` aux bornes 0,699 / 0,7 / 0,899 / 0,9 ; budget `budgetRev` prioritaire sur `budgetInit` ;
  total nul ou absent → `budget == nil` (jamais de division par zéro) ;
  jalon `.late` → `trailingText == "bloqué"` et `isBlocked` ; jalon sans date → texte vide ;
  tri par `order` puis `dueAt` puis `createdAt` ; texte de budget en euros sans décimale.
- [ ] **Étape 2 :** `swift test --filter ProjectCardBuilder` → échec de compilation.
- [ ] **Étape 3 :** écrire `ProjectCardBuilder.swift`. Le formatage des dates courtes reprend
  `MeetingAssistantDock.dateCourte`. Les euros passent par un `NumberFormatter` `.currency`
  en locale `fr_FR`, sans décimale. Le comptage des réunions filtre sur
  `meeting.project?.persistentModelID`.
- [ ] **Étape 4 :** `swift test --filter ProjectCardBuilder` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): ProjectCardBuilder, l'état d'affichage de la fiche projet"`.

### Tâche 3 : `ProjectCardDraft`

**Fichiers :** Créer `OneToOne/Services/Project/ProjectCardDraft.swift`,
`Tests/ProjectCardDraftTests.swift`.

**Interfaces produites :**

```swift
struct ProjectCardDraft: Equatable, Sendable {
    struct MilestoneDraft: Equatable, Sendable, Identifiable {
        var id: UUID; var label: String; var dueAt: Date?; var state: MilestoneState; var order: Int
    }
    struct ContactDraft: Equatable, Sendable, Identifiable {
        var id: UUID; var name: String; var role: String; var order: Int
    }
    struct RiskDraft: Equatable, Sendable, Identifiable {
        var id: UUID; var title: String; var severity: String
    }
    var status: ProjectCardStatus
    var budgetSpent: Double?
    var budgetTotal: Double?
    var scopeText: String
    var tags: [String]
    var milestones: [MilestoneDraft]
    var contacts: [ContactDraft]
    var risks: [RiskDraft]

    @MainActor static func snapshot(of project: Project) -> ProjectCardDraft
    @MainActor func apply(to project: Project, in context: ModelContext)
    var hasChanges: Bool                 // comparé à l'instantané d'origine, porté par le panneau
}
```

`apply(to:in:)` réconcilie par `stableID` : met à jour les lignes existantes, insère les
nouvelles, supprime celles retirées du brouillon. Les jalons et interlocuteurs reçoivent leur
`order` du rang dans le tableau. Un jalon au libellé vide est ignoré (jamais de ligne fantôme).

- [ ] **Étape 1 :** écrire `Tests/ProjectCardDraftTests.swift` — sept tests :
  `snapshot` lit statut, budgets, périmètre, tags, jalons triés, interlocuteurs, risques ;
  **modifier le brouillon ne modifie pas `Project`** (critère chantier 3 n° 4, versant brouillon) ;
  `apply` écrit statut, budget, périmètre, tags ; `apply` met à jour un jalon existant sans le
  dupliquer ; `apply` insère un jalon neuf et supprime un jalon retiré ; un jalon au libellé
  vide n'est pas inséré ; `apply` puis `snapshot` redonne un brouillon égal (aller-retour).
- [ ] **Étape 2 :** `swift test --filter ProjectCardDraft` → échec de compilation.
- [ ] **Étape 3 :** écrire `ProjectCardDraft.swift`.
- [ ] **Étape 4 :** `swift test --filter ProjectCardDraft` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): ProjectCardDraft, brouillon détaché du modèle SwiftData"`.

### Tâche 4 : `ProjectCardSuggestions`

**Fichiers :** Créer `OneToOne/Services/Project/ProjectCardSuggestions.swift`,
`Tests/ProjectCardSuggestionsTests.swift`.

**Interfaces produites :**

```swift
struct ProjectCardUpdate: Equatable, Sendable, Identifiable {
    enum Field: String, Codable, Sendable, CaseIterable {
        case budgetSpent, milestoneState, status, risk
        var label: String   // « Budget consommé », « Statut d'un jalon », « Statut du projet », « Risque »
    }
    var id: String          // field + label, pour l'itération SwiftUI
    var field: Field
    var label: String       // « jalon Marine »
    var current: String
    var proposed: String
    var evidence: String    // « 15:20 40k engagés, rien de finalisé »
}

enum ProjectCardSuggestions {
    static let timeout: TimeInterval = 8
    static let maxSourceCharacters = 6000
    static let maxUpdates = 6
    @MainActor static func isEndpointConfigured(_ settings: AppSettings) -> Bool
    @MainActor static func sourceText(meeting: Meeting) -> String
    static func buildPrompt(source: String, card: ProjectCardState) -> String
    static func parse(_ raw: String) -> [ProjectCardUpdate]
    @MainActor static func suggest(meeting: Meeting, card: ProjectCardState,
                                   settings: AppSettings,
                                   client: AIClientProtocol = AIClient.live) async -> [ProjectCardUpdate]
    static func summary(_ updates: [ProjectCardUpdate]) -> String
        // « L'assistant propose 2 mises à jour depuis cette séance : budget consommé et statut du jalon Marine. »
    @MainActor static func accept(_ update: ProjectCardUpdate, in draft: inout ProjectCardDraft) -> Bool
}
```

`parse` est **non lançante** : bloc ```` ```json ```` retiré comme dans
`AIReportService.stripCodeFence`, JSON invalide → `[]`, champ inconnu → ligne écartée,
`updates` absent → `[]`. `suggest` est non lançante aussi : endpoint absent, erreur, timeout
→ `[]`, donc **pas d'encart** et aucune erreur affichée. `accept` mute le brouillon, jamais
le modèle.

- [ ] **Étape 1 :** écrire `Tests/ProjectCardSuggestionsTests.swift` avec un `StubAIClient`
  local (sur le modèle de `Tests/ManagerCategoryClassifierTests.swift`) — neuf tests :
  réponse valide à deux entrées → deux `ProjectCardUpdate` ; réponse entourée d'un bloc
  ```` ```json ```` → parsée ; `{"updates":[]}` → `[]` ; JSON malformé → `[]` sans lever ;
  champ `field` inconnu → ligne écartée, les autres conservées ; plus de `maxUpdates`
  entrées → tronqué ; client qui lève → `[]` ; `isEndpointConfigured` faux sans modèle ;
  **`suggest` puis `accept` ne modifient pas `Project`** — seul le brouillon change
  (critère chantier 3 n° 4, versant assistant).
- [ ] **Étape 2 :** `swift test --filter ProjectCardSuggestions` → échec de compilation.
- [ ] **Étape 3 :** écrire `ProjectCardSuggestions.swift`. Le timeout reprend le
  `withThrowingTaskGroup` de `MeetingTagSuggester`.
- [ ] **Étape 4 :** `swift test --filter ProjectCardSuggestions` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): ProjectCardSuggestions, propositions IA jamais appliquées d'office"`.

### Tâche 5 : `UndoBanner`

**Fichiers :** Créer `OneToOne/Views/DesignSystem/Components/Refonte/UndoBanner.swift`,
`Tests/UndoBannerTests.swift`.

**Interfaces produites :**

```swift
struct UndoBanner: View {
    static let duration: TimeInterval = 5
    init(message: String, onUndo: @escaping () -> Void, onExpire: @escaping () -> Void)
}
```

- [ ] **Étape 1 :** écrire `Tests/UndoBannerTests.swift` : la durée vaut 5 s ; le libellé par
  défaut est « Modifications enregistrées » ; la bannière se construit sans session graphique.
- [ ] **Étape 2 :** `swift test --filter UndoBanner` → échec de compilation.
- [ ] **Étape 3 :** écrire la vue : carte `surface`, rayon 7, texte 12 px `ink2`, bouton
  `Annuler` en `accent/action`, `task` qui dort `duration` puis appelle `onExpire`.
- [ ] **Étape 4 :** `swift test --filter UndoBanner` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): UndoBanner, bannière d'annulation à 5 secondes"`.

### Tâche 6 : `ProjectCardPanel`

**Fichiers :** Créer `OneToOne/Views/Project/ProjectCardPanel.swift`,
`OneToOne/Views/Project/ProjectCardSuggestionsSheet.swift`,
`Tests/ProjectCardPanelTests.swift`.

**Interfaces produites :**

```swift
struct ProjectCardPanel: View {
    static let width: CGFloat = One2OneToken.projectPanelWidth   // 430
    init(project: Project, meeting: Meeting, meetings: [Meeting], settings: AppSettings,
         isPresented: Binding<Bool>)
}
```

Contenu, de haut en bas, d'après `3b-fiche-projet.png` : en-tête (`FICHE PROJET`, nom en
14/600, `P25_110 · 9 réunions · dernière mise à jour aujourd'hui par vous` en mono 10, bascule
`Édition` en pilule `accent/action`, `✕`), deux cartes côte à côte `STATUT` (menu à trois
valeurs avec point coloré) et `BUDGET CONSOMMÉ` (valeur / total + `ProgressBar` teintée par
`BudgetTone`), `JALONS` + `＋ ajouter` (point d'état, libellé, date ou `bloqué` en
`accent/report`, ligne d'ajout pointillée `Nouveau jalon…` avec `date · statut` à droite),
`PÉRIMÈTRE & CONTEXTE` + `éditer` (texte encadré + chips de tags + chip `＋`),
`RISQUES · n` et `INTERLOCUTEURS` sur deux colonnes, encart de l'assistant, pied
(mention de visibilité + `Annuler` / `Enregistrer`).

Hors édition : tout est en lecture, les `＋` et les champs disparaissent, le pied aussi.
`Esc` et `✕` ferment ; un brouillon modifié demande confirmation avant fermeture.

- [ ] **Étape 1 :** écrire `Tests/ProjectCardPanelTests.swift` : la largeur vaut 430 ; les
  libellés de section sont exactement ceux de la capture ; les trois entrées du menu de statut
  sont dans l'ordre `ok/watch/risk` ; le texte de pied cite « toute l'équipe projet » et
  « préparation de la prochaine réunion » ; la feuille de diff se construit avec zéro
  proposition sans planter.
- [ ] **Étape 2 :** `swift test --filter ProjectCardPanel` → échec de compilation.
- [ ] **Étape 3 :** écrire les deux vues. Aucune couleur littérale : uniquement
  `One2OneToken`. Le panneau lit `ProjectCardBuilder.build` pour l'affichage et
  `ProjectCardDraft.snapshot` pour l'édition.
- [ ] **Étape 4 :** `swift test --filter ProjectCardPanel` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): ProjectCardPanel, la fiche projet en panneau de 430 px"`.

### Tâche 7 : câblage — déclencheur et overlay

**Fichiers :** Modifier `OneToOne/Views/Meeting/MeetingScreenModel.swift` (fin de type),
`OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (segment projet seulement),
`OneToOne/Views/MeetingView.swift` (deux lignes), `Tests/MeetingScreenModelTests.swift`,
`Tests/MeetingTopChromeBarTests.swift`.

**Interfaces produites :** `MeetingScreenModel.showProjectCard: Bool` (faux par défaut,
non persisté : un panneau ouvert est un geste, pas un réglage).

- [ ] **Étape 1 :** tests — `showProjectCard` est faux à la construction, n'est pas mémorisé
  d'une réunion à l'autre (deux `attach` successifs le laissent faux), et le segment projet
  du fil d'Ariane porte le chevron `⌄` avec l'infobulle « Ouvrir la fiche du projet ».
- [ ] **Étape 2 :** `swift test --filter "MeetingScreenModel|MeetingTopChromeBar"` → échec.
- [ ] **Étape 3 :** ajouter la propriété **en fin de type** ; ajouter le chevron au segment ;
  dans `MeetingView`, remplacer `onOpenProject: { showDetailsSheet = true }` par
  `onOpenProject: { screen.showProjectCard = true }` et poser en fin de `mainPanel` un
  `.overlay(alignment: .trailing)` qui affiche `ProjectCardPanel` quand
  `screen.showProjectCard` est vrai et que `meeting.project` existe. Le contenu passe à
  `One2OneToken.dimmedOpacity` **sans** `.allowsHitTesting(false)` : la colonne reste
  consultable (spec §4.3). L'overlay est en fin de `mainPanel` et non dans
  `MeetingSpaceView` pour que le panneau se superpose aussi aux espaces Rapport et Ressources.
- [ ] **Étape 4 :** `swift test --filter "MeetingScreenModel|MeetingTopChromeBar"` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): ouvrir la fiche projet depuis le fil d'Ariane"`.

### Tâche 8 : reprise en préparation

**Fichiers :** Modifier `OneToOne/Services/Meeting/MeetingPrepareBuilder.swift`,
`OneToOne/Views/Meeting/Spaces/MeetingPrepareSpace.swift`,
`Tests/MeetingPrepareBuilderTests.swift`.

**Interfaces produites :** `MeetingPrepareContext.projectCard: ProjectCardState?` et
`MeetingPrepareBuilder.nearMilestoneWindowDays = 30`, plus
`MeetingPrepareBuilder.nearMilestones(_:now:)` et `.highRisks(_:)` (purs).

- [ ] **Étape 1 :** tests — `projectCard` est `nil` sans projet ; les jalons retenus sont
  ceux dont `dueAt` tombe dans les 30 jours (un jalon à 31 jours est exclu, un jalon en
  retard est retenu, un jalon fait est exclu) ; les risques retenus sont « Critique » et
  « Élevé » seulement.
- [ ] **Étape 2 :** `swift test --filter MeetingPrepareBuilder` → échec.
- [ ] **Étape 3 :** implémenter, puis ajouter dans `MeetingPrepareSpace` une section
  « FICHE PROJET » entre `derniersPoints` et `alertes` : pilule de statut, budget, jalons
  proches, risques élevés, et un bouton `Ouvrir la fiche` qui bascule
  `screen.showProjectCard`. `MeetingPrepareSpace` reçoit pour cela `screen` en paramètre,
  passé par `MeetingSpaceView` — la seule ligne modifiée dans ce dernier fichier.
- [ ] **Étape 4 :** `swift test --filter MeetingPrepareBuilder` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): reprise de la fiche projet dans le mode Préparer"`.

### Tâche 9 : jeu de démonstration

**Fichiers :** Modifier `OneToOne/Services/Debug/RefonteDemoSeed.swift`,
`Tests/RefonteDemoSeedTests.swift`.

- [ ] **Étape 1 :** tests — le projet de démonstration porte `budgetCons == 40_000`,
  `budgetInit == 61_000`, trois jalons (`Migration AP finalisée` fait au 30 sept.,
  `Migration Marine — chiffrage à valider` en retard, `Bascule Jenkins → GitLab CI` prévu au
  15 nov.), trois interlocuteurs (`Olivier Freund — partenaire, décideur`,
  `Claire-Amélie F.-D. — architecte`, `Alexis / Jeff — périmètre Digital`), un périmètre non
  vide et les quatre tags `GitLab Nexus PostgreSQL Cléva` ; le semis reste idempotent
  (rejouer ne crée pas six jalons) ; `ProjectCardBuilder.build` sur ce projet rend
  `À surveiller`, `40 000 € / 61 000 €` et une teinte `warn`.
- [ ] **Étape 2 :** `swift test --filter RefonteDemoSeed` → échec.
- [ ] **Étape 3 :** compléter `seedProject` ; les jalons et interlocuteurs ne sont semés que
  si le projet vient d'être créé, sinon un projet réel homonyme se ferait polluer.
- [ ] **Étape 4 :** `swift test --filter RefonteDemoSeed` → vert.
- [ ] **Étape 5 :** `swift build` puis
  `git commit -m "feat(refonte): compléter le jeu de démonstration pour la fiche projet"`.

### Tâche 10 : scripts de recette

**Fichiers :** Créer `Scripts/recette-app.sh`, `Scripts/recette-run.sh` ; modifier
`OneToOne/OneToOneApp.swift`, `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`.

- [ ] **Étape 1 :** écrire `Scripts/recette-app.sh` — usage en tête du fichier, dossier de
  sortie en `$1` ou `${TMPDIR}`, source `.build/release` du dossier courant (erreur explicite
  si le binaire manque), `Info.plist`, `PkgInfo`, bundle de ressources SwiftPM,
  `default.metallib` récupéré depuis `Mickey.app` s'il est présent, `codesign --force
  --sign -`. N'incrémente aucun numéro de build, n'installe rien.
- [ ] **Étape 2 :** écrire `Scripts/recette-run.sh` — usage en tête, `HOME` temporaire sous le
  dossier de recette, `--seed` qui exporte `ONETOONE_SEED_DEMO=1`, `--home <dir>` pour
  réutiliser un `HOME` de recette, `--app <dir>` pour désigner un autre bundle.
- [ ] **Étape 3 :** dans `OneToOneApp.swift`, lire la variable dans le `.onAppear` de
  `ContentView` (`#if DEBUG` **ou** variable posée), sous garde d'idempotence, et ouvrir la
  réunion semée. Aucun test ne dépend de l'environnement.
- [ ] **Étape 4 :** `swift build` ; `chmod +x` les deux scripts ; `bash -n` sur chacun.
- [ ] **Étape 5 :** ajouter la phrase au §7 étape 6 du plan directeur, puis
  `git commit -m "chore(recette): scripts d'empaquetage et de lancement de recette"`.

### Tâche 11 : recette visuelle, `STATUS.md`, PR

- [ ] **Étape 1 :** `swift test` complet. Consigner les chiffres exacts.
- [ ] **Étape 2 :** `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked`. Si `Yes` :
  ne pas insister, documenter dans `STATUS.md`. Si `No` : `swift build -c release`,
  `Scripts/recette-app.sh`, `Scripts/recette-run.sh --seed`, captures 1 280 et 1 920 px vers
  `docs/superpowers/specs/refonte-2026-09/recette/lot-9-{1280,1920}.png`, comparaison avec
  `3b-fiche-projet.png`.
- [ ] **Étape 3 :** section de tête dans `STATUS.md` : état, ce qui est en place, fichiers,
  chiffres de test réels, écarts avec la capture, prochaine action, date.
- [ ] **Étape 4 :** `git push -u origin feat/refonte-lot-9-fiche-projet`.
- [ ] **Étape 5 :** `gh pr create --base master` — titre
  `feat(refonte): lot 9 — fiche projet en panneau`, corps = critères cochés, `swift test`,
  recette, usage des scripts, mention des PR empilées #19–#22. Ne pas fusionner.
