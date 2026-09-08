# Lot 3 — Rail d'actions 330 px permanent — plan d'exécution

> **Pour l'exécutant :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans` ou
> `superpowers:subagent-driven-development`. Les étapes sont cochables (`- [ ]`).

**But :** remplacer `ActionsPanel` par un rail permanent de 330 px à droite de l'espace
Réunion — onglets `Actions n / Risques n / Historique`, vues `Liste · Calendrier ·
Eisenhower`, groupes ordonnés, cartes à édition inline et composeur en pied validé par `⌘⏎`.

**Architecture :** toute règle métier est une fonction pure testée avant sa vue
(`ActionsRailGrouping`, `OwnerSuggestion`, `ActionCardEditing`, `ActionComposerService`) ;
les vues (`ActionsRail`, `ActionsRailList`, `ActionCard`, `ActionComposer`) ne font que
rendre et brancher. Le rail est monté **une seule fois**, par `MeetingSpaceView`, à côté de
la colonne fluide, via `MeetingSpaceLayout.columns` ; il n'est pas monté en mode Relire, qui
a sa propre disposition (capture `1c`, lot 5). `MeetingView` perd sa closure `actions:`.

**Pile :** SwiftUI + SwiftData, macOS 15, exécutable SwiftPM. Tests Swift Testing.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §2.5 (+ §1.4 `⌘⏎`,
critère chantier 1 n° 3) ; programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`
§5 « Lot 3 », §3, §4 (D10) ; capture qui fait foi
`docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png` (colonne de droite).

## Contraintes globales

- Aucune couleur hors `One2OneToken` ; aucune dépendance SwiftPM nouvelle.
- Libellés UI et commentaires en **français**, symboles en anglais.
- Énums persistées : `…Raw: String` + wrapper calculé.
- `swift build` propre avant chaque commit ; `swift test` complet vert avant la PR
  (référence : **1 801 tests** après le lot 1).
- **Fichiers interdits (lot 2 en parallèle)** : `Spaces/MeetingLiveSpace.swift`,
  `Spaces/Notes/**`, `Spaces/Transcript/**`, `Spaces/AudioTimelineStrip.swift`,
  `Services/ActionFromPhrase.swift`, `Services/NoteCommandParser.swift`. Dans
  `MeetingView.swift`, une seule modification : le retrait de la closure `actions:`.
- **Fichiers interdits (lot 9)** : `Views/Project/**`, `Models/Project*`,
  `Services/ProjectCard*`, `Scripts/recette-app.sh`, `MeetingTopChromeBar`.
- Aucun test ne touche MLX, ScreenCaptureKit ni une session graphique.

## Carte des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Models/ActionsViewMode.swift` **(créé)** | l'enum sortie de `ActionsPanel.swift` + `railCases` |
| `OneToOne/Models/ActionDraft.swift` **(créé)** | `ActionDraft {title, sourceRef, suggestedOwner}` — contrat partagé avec le lot 2 |
| `OneToOne/Services/OwnerSuggestion.swift` **(créé)** | les trois règles de suggestion de responsable (pur) |
| `OneToOne/Views/Meeting/Spaces/Rail/ActionsRailGrouping.swift` **(créé)** | groupes ordonnés + historique (pur) |
| `.../Rail/ActionCard.swift` **(créé)** | carte d'action + `ActionCardEditing` (pur) |
| `.../Rail/ActionComposer.swift` **(créé)** | composeur de pied + `ActionComposerService` |
| `.../Rail/ActionsRailList.swift` **(créé)** | l'onglet Actions en vue Liste, réutilisé par le mode Relire |
| `.../Rail/ActionsRailRisks.swift` **(créé)** | l'onglet Risques (`ProjectAlert` + ajout inline) |
| `.../Rail/ActionsRailHistory.swift` **(créé)** | l'onglet Historique |
| `.../Rail/ActionsRail.swift` **(créé)** | la coquille : onglets, sélecteur de vue, pied |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | `railTab`, `railViewMode` (mémorisés), `pendingActionDraft` |
| `OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift` | monte le rail à droite de la colonne fluide |
| `OneToOne/Views/Meeting/Spaces/MeetingPrepareSpace.swift` | perd son `railReduit` (doublon) |
| `OneToOne/Views/MeetingView.swift` | perd la closure `actions:` (`ActionsPanel` hors chemin) |
| `OneToOne/Views/CalendarBoard.swift`, `EisenhowerBoard.swift` | paramètre `compact: Bool = false` |
| `OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift` | l'enum en sort ; le fichier reste pour `OverviewDashboard` |
| `OneToOne/Services/Debug/RefonteDemoSeed.swift` | échéances, charges, source, 3 reportées du 1er sept. |

---

### Tâche 1 : `ActionsViewMode` déménage dans `Models/`

**Fichiers :** créer `OneToOne/Models/ActionsViewMode.swift` ; modifier
`OneToOne/Views/Meeting/Sidebar/ActionsPanel.swift:1-25` (retrait) ;
`Tests/ActionsViewModeTests.swift` (créé).

**Interfaces produites :** `enum ActionsViewMode: String, CaseIterable` (cas inchangés
`liste, kanban, calendar, eisenhower, sticky`, `label`, `systemImage`) et
`static let railCases: [ActionsViewMode] = [.liste, .calendar, .eisenhower]`.

- [ ] **Étape 1 — test rouge** : `Tests/ActionsViewModeTests.swift` vérifie que
  `railCases == [.liste, .calendar, .eisenhower]`, que `allCases` garde les cinq cas
  (`ActionsListView` en dépend) et que les `rawValue` sont inchangés.
- [ ] **Étape 2** : `swift test --filter ActionsViewMode` → échec de compilation.
- [ ] **Étape 3** : couper l'enum de `ActionsPanel.swift` vers `Models/ActionsViewMode.swift`,
  ajouter `railCases` et son commentaire (Kanban et Post-it restent hors du contexte réunion,
  programme §5).
- [ ] **Étape 4** : `swift build` puis `swift test --filter ActionsViewMode` → vert.
- [ ] **Étape 5** : commit `refactor(actions): sortir ActionsViewMode dans Models`.

---

### Tâche 2 : `ActionsRailGrouping` — les groupes ordonnés (pur)

**Fichiers :** créer `.../Rail/ActionsRailGrouping.swift`, `Tests/ActionsRailGroupingTests.swift`.

**Interfaces produites :**

```swift
@MainActor
enum ActionsRailGrouping {
    enum Identite: Hashable { case aAssigner, mesActions, deleguees, reportees(Date?) }
    enum Rendu { case cartes, lignes }
    struct Groupe: Identifiable {
        let identite: Identite
        let libelle: String          // « À assigner — 9 » (SectionLabel met en capitales)
        let actions: [ActionTask]
        let rendu: Rendu
        var id: Identite { identite }
    }
    struct Entree: Identifiable {    // Historique
        enum Motif { case close, reportee }
        let id: PersistentIdentifier
        let titre: String
        let date: Date?
        let motif: Motif
    }
    static func groupes(for tasks: [ActionTask], calendar: Calendar = .current) -> [Groupe]
    static func historique(for tasks: [ActionTask]) -> [Entree]
    static func dateOrdinale(_ date: Date, calendar: Calendar = .current) -> String
}
```

**Règles (à écrire dans le test avant le code) :**

1. Les actions `done` ou `dropped` sont exclues des groupes d'`Actions` (elles sont dans
   l'Historique).
2. `REPORTÉES DU <date>` capte d'abord : `carriedFromMeeting != nil || deferralCount > 0`,
   groupées par la date de la réunion d'origine (`carriedFromMeeting?.date`, `nil` sinon),
   rendu `.lignes`, du plus récent au plus ancien.
3. Puis `À ASSIGNER` : `collaborator == nil && destinataire != .moi`, rendu `.cartes`.
4. Puis `MES ACTIONS` : `destinataire == .moi`, rendu `.cartes`.
5. Puis `DÉLÉGUÉES` : le reste (`collaborator != nil`), rendu `.cartes`.
6. Ordre des groupes rendus : `À ASSIGNER`, `MES ACTIONS`, `DÉLÉGUÉES`, puis les
   `REPORTÉES DU …`. Un groupe vide n'est pas rendu.
7. Tri interne : `sortOrder` croissant, puis `dueDate` (sans échéance en dernier), puis
   titre. C'est `sortOrder` qui reproduit l'ordre de la capture et qui permet au composeur
   de placer une action neuve **en tête** de son groupe.
8. `dateOrdinale` : jour 1 → `1er sept.`, sinon `11 sept.` (locale `fr_FR`).

- [ ] **Étape 1 — test rouge** : `Tests/ActionsRailGroupingTests.swift`, container en
  mémoire comme `MeetingKPIBuilderTests`. Cas : ordre des quatre groupes ; action cochée
  absente ; deux dates de report = deux groupes ; report prioritaire sur « à assigner » ;
  `dateOrdinale` (1er, 11) ; tri par `sortOrder` ; libellés exacts (`"À assigner — 9"`).
- [ ] **Étape 2** : `swift test --filter ActionsRailGrouping` → échec.
- [ ] **Étape 3** : écrire `ActionsRailGrouping`.
- [ ] **Étape 4** : `swift build && swift test --filter ActionsRailGrouping` → vert.
- [ ] **Étape 5** : commit `feat(rail): grouper les actions du rail (pur, testé)`.

---

### Tâche 3 : `OwnerSuggestion` — les trois règles (pur)

**Fichiers :** créer `OneToOne/Services/OwnerSuggestion.swift`, `Tests/OwnerSuggestionTests.swift`.

**Interfaces produites :**

```swift
@MainActor
enum OwnerSuggestion {
    static func prefixe(_ titre: String) -> String            // 3 premiers mots normalisés
    static func suggestion(for task: ActionTask,
                           in meeting: Meeting,
                           projectTasks: [ActionTask]) -> Collaborator?
}
```

**Règles, dans l'ordre :**

1. Locuteur de la phrase source : `task.sourceRef?.kind == .transcript` → le
   `TranscriptSegment` de `meeting.transcriptSegments` dont `stableID == ref.stableID` →
   son `speaker`.
2. Dernier porteur d'une action de même `prefixe(title)` dans `projectTasks` (hors la tâche
   elle-même, `collaborator != nil`), le plus récent par `createdAt`.
3. Participant unique restant : `meeting.participants` moins ceux qui portent déjà une
   action de la réunion ; si **exactement un** reste, c'est lui.
4. Sinon `nil`.

`prefixe` : minuscules, diacritiques repliés, ponctuation retirée, trois premiers mots
joints par une espace.

- [ ] **Étape 1 — test rouge** : `Tests/OwnerSuggestionTests.swift` — une règle par test,
  plus « aucun candidat rend nil », plus `prefixe` (« Vérifier l'état des comptes GitLab »
  → `verifier l etat`), plus la priorité de la règle 1 sur la règle 2.
- [ ] **Étape 2** : `swift test --filter OwnerSuggestion` → échec.
- [ ] **Étape 3** : écrire le service.
- [ ] **Étape 4** : `swift build && swift test --filter OwnerSuggestion` → vert.
- [ ] **Étape 5** : commit `feat(rail): suggérer un responsable en trois règles`.

---

### Tâche 4 : état du rail dans `MeetingScreenModel` + `ActionDraft`

**Fichiers :** créer `OneToOne/Models/ActionDraft.swift` ; modifier
`MeetingScreenModel.swift` ; ajouter des tests à `Tests/MeetingScreenModelTests.swift`.

**Interfaces produites :**

```swift
@MainActor struct ActionDraft {
    var title: String
    var sourceRef: SourceRef?
    var suggestedOwner: Collaborator?
}

extension MeetingScreenModel {
    enum RailTab: String, CaseIterable, Sendable { case actions, risques, historique }
}
// var railTab: RailTab          — mémorisé par réunion
// var railViewMode: ActionsViewMode — mémorisé par réunion, ramené à .liste si hors railCases
// var pendingActionDraft: ActionDraft?  — en FIN de type (le lot 2 ajoute au même endroit)
```

- [ ] **Étape 1 — test rouge** : dans `MeetingScreenModelTests`, quatre tests — défauts
  (`.actions`, `.liste`) ; mémorisation par réunion des deux ; une valeur mémorisée hors
  `railCases` (`"kanban"`) retombe sur `.liste` ; `pendingActionDraft` n'est **pas** persisté.
- [ ] **Étape 2** : `swift test --filter MeetingScreenModel` → échec.
- [ ] **Étape 3** : implémenter (clés `onetoone.meetingScreen.railTab.<id>` et
  `.railView.<id>`, relecture dans `attach`, `isRestoring` respecté).
- [ ] **Étape 4** : `swift build && swift test --filter MeetingScreenModel` → vert.
- [ ] **Étape 5** : commit `feat(rail): mémoriser l'onglet et la vue du rail`.

---

### Tâche 5 : `ActionCardEditing` puis `ActionCard`

**Fichiers :** créer `.../Rail/ActionCard.swift`, `Tests/ActionCardEditingTests.swift`.

**Interfaces produites :**

```swift
enum ActionCardEditing {
    enum Champ: Int, CaseIterable, Hashable { case responsable, echeance, charge }
    static func suivant(_ champ: Champ) -> Champ                    // cycle, pour Tab
    static func chargeLabel(_ minutes: Int) -> String               // 30 → "30min", 120 → "2h", 480 → "1j"
    static let chargesProposees: [Int]                              // [30, 60, 120, 240, 480]
    static func raccourcisEcheance(depuis: Date, calendar: Calendar) -> [(libelle: String, date: Date)]
    // « Demain », « Vendredi », « +1 sem. »
    static func etatResponsable(_ task: ActionTask) -> InvitePill.Etat
    static func libelleResponsable(_ task: ActionTask, suggestion: Collaborator?) -> String
}

struct ActionCard: View { /* task, participants, allCollaborators, suggestion, onSeek, onSave */ }
```

Rendu (capture 1a) : barre gauche 2 px `accent/report` quand personne ne porte l'action,
titre `plexSans(11.5)` sur 2 lignes max, puis les pilules — responsable, échéance, charge,
`!` urgent, source (`◫ mm:ss` pour une capture, `mm:ss ↗` pour une transcription ou une
note, clic → `onSeek`). Une pilule vide est une `InvitePill` en `.invite`, renseignée elle
passe en `.renseignee` (responsable) ou `.neutre` (échéance, charge). Le clic ouvre un
**sélecteur inline** sous les pilules : `OwnerPickerMenu` pour le responsable, `DatePicker`
`.compact` + les trois raccourcis pour l'échéance, la liste des charges pour la charge.
`Tab` avance de champ. **Aucune `sheet`, aucune `popover`, aucune `alert`** dans ce fichier.

- [ ] **Étape 1 — test rouge** : `Tests/ActionCardEditingTests.swift` — `chargeLabel`
  (30/60/90/120/480/960, 0 → `"＋ charge"`… non : 0 est traité par l'appelant, tester 30, 60,
  90, 120, 480) ; `suivant` fait le tour des trois champs ; `raccourcisEcheance` depuis un
  mercredi donne demain = jeudi, vendredi = le vendredi suivant, +1 sem. = +7 j ; un vendredi
  donne « Vendredi » = le vendredi **suivant**, jamais aujourd'hui ; `etatResponsable`
  (`nil` → `.invite`, renseigné → `.renseignee`) ; `libelleResponsable` avec suggestion
  (`"＋ Yann"`) et sans (`"＋ assigner"`).
- [ ] **Étape 2** : `swift test --filter ActionCardEditing` → échec.
- [ ] **Étape 3** : écrire `ActionCardEditing` puis `ActionCard`.
- [ ] **Étape 4** : `swift build && swift test --filter ActionCardEditing` → vert.
- [ ] **Étape 5** : commit `feat(rail): carte d'action à édition inline`.

---

### Tâche 6 : `ActionComposerService` puis `ActionComposer`

**Fichiers :** créer `.../Rail/ActionComposer.swift`, `Tests/ActionComposerServiceTests.swift`.

**Interfaces produites :**

```swift
@MainActor
enum ActionComposerService {
    @discardableResult
    static func creer(from screen: MeetingScreenModel,
                      meeting: Meeting,
                      in context: ModelContext,
                      now: Date = Date()) -> ActionTask?
    static func planckerSortOrder(_ tasks: [ActionTask]) -> Int   // min - 1, ou 0
}
struct ActionComposer: View { /* screen, meeting, onCreated */ }
```

`creer` : rend `nil` si le titre (ou le brouillon en attente) est vide ; consomme
`screen.pendingActionDraft` (titre, `sourceRef`, responsable suggéré) puis le remet à `nil` ;
`sortOrder` = plancher pour paraître **en tête** ; applique destinataire, échéance, urgence,
`effortMinutes` ; appelle `screen.resetActionDraft()` — donc vide le titre **sans** toucher
au destinataire ni au collaborateur choisi, et **sans** toucher au focus (le service n'en
connaît pas).

`ActionComposer` : `TextField` « Nouvelle action… », `@FocusState` jamais remis à `false`,
`.onKeyPress(.return)` qui n'agit que si `press.modifiers.contains(.command)`, indice `⌘⏎` à
droite, pilules `Moi · Demain · ! · 30min` en bascules.

- [ ] **Étape 1 — test rouge** : `Tests/ActionComposerServiceTests.swift` — titre vide rend
  `nil` et n'insère rien ; création vide le titre mais garde destinataire et collaborateur ;
  `sortOrder` strictement inférieur au minimum existant ; `pendingActionDraft` consommé
  (titre, `sourceRef`, responsable) et remis à `nil` ; `effortMinutes` et échéance appliqués.
- [ ] **Étape 2** : `swift test --filter ActionComposerService` → échec.
- [ ] **Étape 3** : écrire le service puis la vue.
- [ ] **Étape 4** : `swift build && swift test --filter ActionComposerService` → vert.
- [ ] **Étape 5** : commit `feat(rail): composeur d'action validé par ⌘⏎`.

---

### Tâche 7 : rendus compacts de `CalendarBoard` et `EisenhowerBoard`

**Fichiers :** modifier `OneToOne/Views/CalendarBoard.swift`,
`OneToOne/Views/EisenhowerBoard.swift` ; créer `Tests/ActionsBoardsCompactTests.swift`.

**Interfaces produites :**

```swift
extension CalendarBoard {
    static func dayCellMinHeight(fillsAvailableSpace: Bool, compact: Bool) -> CGFloat  // 46 / 84 / 34
    static func maxChipsPerDay(fillsAvailableSpace: Bool, compact: Bool) -> Int        // 2 / 6 / 1
}
extension EisenhowerBoard {
    static func boxMinHeight(fillsAvailableSpace: Bool, compact: Bool) -> CGFloat?     // 90 / nil / 54
}
// var compact: Bool = false  sur les deux vues
```

- [ ] **Étape 1 — test rouge** : les valeurs **par défaut** sont celles d'avant
  (46 / 2 / 90 et 84 / 6 / nil) et le mode compact les réduit strictement.
- [ ] **Étape 2** : `swift test --filter ActionsBoardsCompact` → échec.
- [ ] **Étape 3** : extraire les métriques en fonctions statiques, ajouter `compact`.
- [ ] **Étape 4** : `swift build && swift test --filter ActionsBoardsCompact` → vert.
- [ ] **Étape 5** : commit `feat(rail): rendus compacts du calendrier et d'Eisenhower`.

---

### Tâche 8 : `ActionsRailList`, `ActionsRailRisks`, `ActionsRailHistory`, `ActionsRail`

**Fichiers :** créer les quatre vues ; créer `Tests/ActionsRailNoModalTests.swift`.

`ActionsRail` : bandeau d'onglets (`Actions n` actif sur fond `surfaceAlt` arrondi,
`Risques n`, `Historique`), sélecteur `SegmentedMode` des `railCases` sous l'onglet Actions
(masqué si `reduit`, c'est-à-dire en mode Préparer), corps selon l'onglet et la vue,
`ActionComposer` en pied, toujours visible. Largeur imposée par l'appelant.

`ActionsRailRisks` : `meeting.meetingAlerts` puis les `ProjectAlert` du projet non déjà
listés, point coloré par sévérité (`Critique`/`Élevé` → `report`, `Modéré` → `warn`, sinon
`ink4`), `＋ Ajouter un risque` qui déplie un champ inline et crée l'alerte sur la réunion et
le projet.

`ActionsRailHistory` : `ActionsRailGrouping.historique`, une ligne par entrée avec sa date.

- [ ] **Étape 1 — test rouge** : `Tests/ActionsRailNoModalTests.swift` lit les sources du
  dossier `Rail/` (chemin dérivé de `#filePath`) et refuse `.sheet(`, `.popover(`, `.alert(`
  et `.confirmationDialog(` — c'est la forme vérifiable du critère chantier 1 n° 3
  (« sans quitter le rail ni ouvrir de modale »). Un second test refuse une remise à `false`
  du `@FocusState` de `ActionComposer` (« `⌘⏎` crée sans perdre le focus »).
- [ ] **Étape 2** : `swift test --filter ActionsRailNoModal` → échec (fichiers absents).
- [ ] **Étape 3** : écrire les quatre vues.
- [ ] **Étape 4** : `swift build && swift test --filter ActionsRailNoModal` → vert.
- [ ] **Étape 5** : commit `feat(rail): onglets Actions, Risques et Historique du rail`.

---

### Tâche 9 : brancher le rail et sortir `ActionsPanel` du chemin

**Fichiers :** modifier `MeetingSpaceView.swift`, `MeetingPrepareSpace.swift`,
`MeetingView.swift:674-687` (retrait de `actions:`) ; adapter les tests qui montent
`MeetingSpaceView`.

- [ ] **Étape 1** : `MeetingSpaceView` perd son générique `Actions`, gagne
  `@Query private var allCollaborators: [Collaborator]`, enveloppe son `VStack` dans un
  `GeometryReader` + `HStack` avec `MeetingSpaceLayout.columns(totalWidth:rail:sideNav:)`
  où `rail` vaut `One2OneToken.actionsRailWidth` sauf en mode Relire (`nil`), et passe
  `ActionsRailList(...)` à `MeetingReviewSpace(actions:)`.
- [ ] **Étape 2** : `MeetingPrepareSpace` perd `railReduit` et son `GeometryReader`
  (le rail est monté une seule fois, en amont).
- [ ] **Étape 3** : `MeetingView` perd la closure `actions:` (14 lignes). `ActionsPanel`
  n'est plus instancié que par `OverviewDashboard`, hors de l'espace Réunion (D8).
- [ ] **Étape 4** : `swift build` propre ; `swift test --filter MeetingSpace` vert.
- [ ] **Étape 5** : commit `feat(rail): monter le rail dans l'espace Réunion`.

---

### Tâche 10 : jeu de démonstration à la hauteur de la capture

**Fichiers :** modifier `OneToOne/Services/Debug/RefonteDemoSeed.swift` ; adapter
`Tests/RefonteDemoSeedTests.swift`.

- [ ] **Étape 1 — test rouge** : la réunion semée porte 3 actions reportées d'une réunion du
  1er septembre (`carriedFromMeeting != nil`, `deferralCount == 1`), 9 actions sans
  responsable, une action avec `sourceRef.kind == .transcript` au timecode 252,
  des `effortMinutes` (120 et 480) et deux échéances.
- [ ] **Étape 2** : `swift test --filter RefonteDemoSeed` → échec.
- [ ] **Étape 3** : enrichir le semis (réunion d'origine « COSUI hebdo » du 1er sept.,
  échéances, charges, source).
- [ ] **Étape 4** : `swift build && swift test --filter RefonteDemoSeed` → vert.
- [ ] **Étape 5** : commit `test(recette): enrichir le jeu de démonstration du rail`.

---

### Tâche 11 : suite complète, recette, documentation, PR

- [ ] **Étape 1** : `swift test` complet — vert, chiffres notés.
- [ ] **Étape 2** : recette visuelle. Vérifier d'abord
  `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` : si `Yes`, ne pas insister et
  documenter la procédure dans `STATUS.md`. Sinon `swift build -c release`, empaqueter un
  `.app` dans le scratchpad (HOME temporaire), menu **Réunion → Charger le jeu de
  démonstration (refonte)**, captures 1 280 et 1 920 px vers
  `docs/superpowers/specs/refonte-2026-09/recette/lot-3-{1280,1920}.png`, comparaison à
  `1a-cockpit.png`.
- [ ] **Étape 3** : `STATUS.md` — section en tête, chiffres réels, écarts, prochaine action
  = lots 4 et 5.
- [ ] **Étape 4** : push et `gh pr create` vers `master`, titre
  `feat(refonte): lot 3 — rail d'actions 330 px`, corps = critères cochés + `swift test` +
  recette + mention des PR empilées #19–#22. **Ne pas merger.**
