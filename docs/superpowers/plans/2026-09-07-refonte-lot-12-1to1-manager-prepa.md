# Lot 12 — 1:1 côté manager, écran de préparation (2b) — plan d'exécution

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans` ou
> `superpowers:subagent-driven-development`. Les étapes sont des cases à cocher.

**But.** Rendre le mode **Préparer** d'une réunion `kind == .oneToOne` conforme à la
capture `2b-1to1-manager-preparation.png` : en-tête violet pâle, histogramme de moral,
objectifs, « à ne pas oublier », tableau des engagements réciproques, sujets récurrents,
historique du fil et barre d'assistant sur le contexte du fil.

**Architecture.** Aucun calcul métier neuf : tout vient du lot 10
(`Services/OneOnOne/`, pur et testé). Ce lot ajoute (a) des **modèles de vue purs**
(`MoodHistogramModel`, `ObjectivesCardModel`, `PrepRemindersModel`,
`CommitmentsTableModel`, `RecurringTopicsCardModel`, `ThreadHistoryModel`,
`PrepHeaderModel`) qui traduisent le fil en lignes prêtes à dessiner, (b) sept vues
SwiftUI préfixées `Prep`/carte dans `Views/Meeting/OneOnOne/ManagerPrep/`, (c) un unique
service d'écriture `OneOnOnePrepStore` dans `Services/OneOnOne/Prep/` (nouvel engagement,
bascule tenu/réouvrir, ajout et édition d'objectif). Les modèles de vue portent les
critères d'acceptation : ils sont testables sans écran.

**Pile technique.** SwiftUI + SwiftData, jetons `One2OneToken` (spec §1.2), primitives
`Views/DesignSystem/Components/Refonte/*` (`RefonteCard`, `Chip`, `Pill`, `ProgressBar`,
`SegmentedMode`, `MonoMeta`, `MeetingEmptyInvite`), Swift Testing.

**Spécifications.**
- `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §3.4 (écran 2b), §3.1, §1.2,
  critère d'acceptation chantier 2 n° 3.
- `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 12 », §7, §8.
- Capture qui fait foi :
  `docs/superpowers/specs/refonte-2026-09/ecrans/2b-1to1-manager-preparation.png`.

## Contraintes globales

- Branche `feat/refonte-lot-12-1to1-manager-prepa` sur `fix/refonte-1to1-window-crash`.
- **Mes fichiers** : `Views/Meeting/OneOnOne/ManagerPrep/**`,
  `Services/OneOnOne/Prep/**`, `Services/Debug/Seed/RefonteDemoSeed+Lot12.swift`,
  `Tests/ManagerPrep*.swift`.
- **Interdits** (lots 7, 11, 16 en parallèle) : `Views/Meeting/OneOnOne/Manager/**`,
  `Views/Meeting/OneOnOne/Shared/**`, `Views/Meeting/Capture/**`,
  `Services/SlideCapture/**`, `Views/Meeting/Workshop/**`, `Services/Workshop/**`,
  `Spaces/Rail/**`, `Spaces/Review/**`, `Session/**`, `Resources/**`, `Notes/**`,
  les fichiers existants de `Services/OneOnOne/` (extension par
  `Services/OneOnOne/Prep/*.swift` seulement).
- **Fichiers partagés, budget à la ligne** : `MeetingSpaceRouting.swift` (une fonction
  pure), `MeetingSpaceView.swift` (une branche + deux paramètres passés),
  `MeetingPrepareSpace.swift` (une branche + deux paramètres), `MeetingAssistantDock.swift`
  (un paramètre optionnel `threadContext`), `MeetingCommands.swift` (une ligne d'appel de
  semis), `MeetingScreenModel.swift` : **rien** (l'état 1:1 existe déjà),
  `MeetingTopChromeBar.swift` et `MeetingView.swift` : **rien**.
- État d'écran : `screen.oneOnOne` (`OneOnOneScreenState`), propriétés ajoutées **en fin
  de type**, préfixées `prep`.
- Commentaires et libellés en français, symboles en anglais. Aucune couleur nommée hors
  `One2OneToken`. Aucune zone vide sans invite.
- `swift build` avant chaque commit ; `swift test` complet vert avant la PR
  (référence : 2 402 tests).
- Commits conventionnels, `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## Structure des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Views/Meeting/OneOnOne/ManagerPrep/ManagerPrepView.swift` | Assemble l'écran : en-tête, deux rangées de cartes, dock d'assistant. Ne calcule rien. |
| `.../PrepHeader.swift` | `PrepHeaderModel` (initiales, sous-titre `rôle · nᵉ 1:1 · date`) + la barre violet pâle, badges et deux boutons. |
| `.../MoodHistogram.swift` | `MoodHistogramModel` (6 barres, tendance, phrases) + le rendu de l'histogramme. Porte le critère chantier 2 n° 3. |
| `.../ObjectivesCard.swift` | `ObjectivesCardModel` (lignes + `Revue prévue le`) + carte avec édition inline. |
| `.../RemindersCard.swift` | `PrepRemindersModel` (rappels, bouton déjà versé, invite) + carte `À NE PAS OUBLIER`. |
| `.../CommitmentsTable.swift` | `CommitmentsTableModel` (filtre, tri, badge, pied, libellé d'échéance) + tableau `20 \| 1fr \| 92 \| 84 \| 96` et composeur. |
| `.../RecurringTopicsCard.swift` | Chips `label · n` colorées par famille. |
| `.../ThreadHistoryCard.swift` | `ThreadHistoryModel` (4 dernières séances, date + résumé d'une ligne) + carte cliquable. |
| `Services/OneOnOne/Prep/OneOnOnePrepStore.swift` | Les **seules** écritures du lot : nouvel engagement, bascule tenu/réouvrir, ajout et mise à jour d'objectif. |
| `Services/OneOnOne/Prep/ReminderRules+Prep.swift` | `areAllOnAgenda(_:in:)` — le bouton `Mettre à l'ordre du jour` sait qu'il a déjà fait son travail. |
| `Services/Debug/Seed/RefonteDemoSeed+Lot12.swift` | Complète le fil de Laurent NOMINÉ avec ce que la capture montre et que le lot 10 ne sème pas : les résumés d'une ligne de l'`HISTORIQUE`. |
| `Tests/ManagerPrepModelsTests.swift` | Modèles de vue : histogramme (critère n° 3), objectifs, rappels, historique, en-tête. |
| `Tests/ManagerPrepCommitmentsTableTests.swift` | Filtre, tri, badge de retard manager, taux, libellés d'échéance, composeur. |
| `Tests/ManagerPrepRoutingTests.swift` | Routage du mode Préparer 1:1 et invites d'états vides. |

---

## Task 1 : routage — le mode Préparer d'un 1:1 est un écran à part

**Fichiers :**
- Modifier : `OneToOne/Services/Meeting/MeetingSpaceRouting.swift` (une fonction pure)
- Test : `Tests/ManagerPrepRoutingTests.swift`

**Interfaces produites :**
`MeetingSpaceRouting.usesOneOnOnePreparation(kind: MeetingKind, mode: MeetingScreenModel.Mode) -> Bool`
et `MeetingSpaceRouting.defaultMode(for kind: MeetingKind, hasRecording: Bool) -> MeetingScreenModel.Mode`.

- [ ] **Étape 1 : test rouge** — `usesOneOnOnePreparation` vrai pour `(.oneToOne, .prepare)`,
  faux pour `(.oneToOne, .live)`, `(.manager, .prepare)` (lot 14), `(.project, .prepare)` ;
  `defaultMode(for: .oneToOne, hasRecording: false) == .prepare`,
  `defaultMode(for: .oneToOne, hasRecording: true) == .live`,
  `defaultMode(for: .project, hasRecording: false) == .live`.
- [ ] **Étape 2 : `swift test --filter ManagerPrepRoutingTests`** → échec de compilation.
- [ ] **Étape 3 : implémenter** les deux fonctions pures.
- [ ] **Étape 4 : `swift test --filter ManagerPrepRoutingTests`** → vert.
- [ ] **Étape 5 : commit** `feat(refonte): router le mode Préparer d'un 1:1 vers son écran`.

## Task 2 : `PrepHeaderModel` et `PrepHeader`

**Fichiers :** créer `Views/Meeting/OneOnOne/ManagerPrep/PrepHeader.swift` ;
tests dans `Tests/ManagerPrepModelsTests.swift`.

**Interfaces produites :**
```swift
struct PrepHeaderModel: Equatable {
    var name: String; var initials: String; var subtitle: String
    var sessionNumber: Int
    static func build(meeting: Meeting, thread: OneOnOneThread) -> PrepHeaderModel
    static func ordinal(_ n: Int) -> String   // 1 → "1ᵉʳ", 14 → "14ᵉ"
}
struct PrepHeader: View { … onShowHistory: () -> Void, onStart: () -> Void }
```

- [ ] **Étape 1 : test rouge** — sur le fil semé, `subtitle == "Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026"`,
  `initials == "LN"` ; `ordinal(1) == "1ᵉʳ"` ; un fil sans rôle saisi n'affiche pas de
  séparateur orphelin (`"3ᵉ 1:1 · …"`).
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** le modèle puis la vue (avatar 34 px `AvatarPalette`,
  badge `1:1` violet plein, pilule `Privé` bordée, `Historique` secondaire,
  `Démarrer l'entretien` primaire, fond `One2OneToken.oneOnOneBg`).
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): en-tête de préparation 1:1`.

## Task 3 : `MoodHistogramModel` et `MoodHistogram` — critère chantier 2 n° 3

**Fichiers :** créer `Views/Meeting/OneOnOne/ManagerPrep/MoodHistogram.swift`.

**Interfaces produites :**
```swift
struct MoodHistogramModel: Equatable {
    struct Bar: Equatable, Identifiable { var id: Int; var value: Int; var dateLabel: String
                                          var level: MoodLevel; var isLast: Bool }
    var bars: [Bar]
    var direction: MoodTrend.Direction
    var trendLabel: String?          // "en baisse"
    var trendTone: OneOnOneTone?     // .report / .ok / nil
    var streakSentence: String?      // « Deuxième séance consécutive sous « Bien ». »
    var explanation: String?         // MoodTrend.explanation
    var isEmpty: Bool
    static func build(_ thread: OneOnOneThread, now: Date) -> MoodHistogramModel
    static func tone(for level: MoodLevel) -> OneOnOneTone
}
```

- [ ] **Étape 1 : test rouge** — série de la capture (`[3,4,5,4,4,2]`) : 6 barres, dates
  `12/06 … 04/09`, dernière `isLast`, `trendLabel == "en baisse"`, `trendTone == .report`,
  `tone(for: .sousTension) == .warn`, `streakSentence` commence par « Deuxième séance
  consécutive » ; **critère n° 3** : après `MoodTrend.record(5, for: nouvelleSéance, …)`,
  `build` rend la nouvelle valeur en dernière barre sans reconstruire le fil ; fil sans
  humeur → `isEmpty`.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** modèle puis vue (barres pâles, dernière à sa teinte,
  dates `dd/MM` la dernière en gras, invite si vide).
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): histogramme de moral de la préparation 1:1`.

## Task 4 : `ObjectivesCardModel` et `ObjectivesCard`

**Fichiers :** créer `Views/Meeting/OneOnOne/ManagerPrep/ObjectivesCard.swift` et
`Services/OneOnOne/Prep/OneOnOnePrepStore.swift` (partie objectifs).

**Interfaces produites :**
```swift
struct ObjectivesCardModel: Equatable {
    struct Row: Equatable, Identifiable { var id: PersistentIdentifier; var label: String
                                          var progress: Int; var tone: OneOnOneTone }
    var rows: [Row]; var reviewLabel: String?; var isEmpty: Bool
    static func build(_ thread: OneOnOneThread) -> ObjectivesCardModel
}
enum OneOnOnePrepStore {
    static func addObjective(label: String, progress: Int, in thread: OneOnOneThread,
                             in context: ModelContext) -> OneOnOneObjective?
    static func update(_ objective: OneOnOneObjective, label: String?, progress: Int?,
                       in context: ModelContext)
}
```

- [ ] **Étape 1 : test rouge** — trois lignes dans l'ordre semé, tons `ok/warn/warn`
  (`OneOnOneObjectiveTone`), `reviewLabel == "Revue prévue le 18 sept."` ;
  `addObjective` refuse un libellé vide, borne la progression à 0…100 et place la ligne en
  fin d'ordre ; `update` borne aussi.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter**.
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): carte objectifs de la préparation 1:1`.

## Task 5 : `PrepRemindersModel` et `RemindersCard`

**Fichiers :** créer `Views/Meeting/OneOnOne/ManagerPrep/RemindersCard.swift` et
`Services/OneOnOne/Prep/ReminderRules+Prep.swift`.

**Interfaces produites :**
```swift
extension ReminderRules { static func areAllOnAgenda(_ reminders: [Reminder],
                                                     in thread: OneOnOneThread) -> Bool }
struct PrepRemindersModel: Equatable {
    var reminders: [ReminderRules.Reminder]
    var isAgendaButtonEnabled: Bool
    var isEmpty: Bool
    static func build(_ thread: OneOnOneThread, now: Date) -> PrepRemindersModel
}
```

- [ ] **Étape 1 : test rouge** — ordre des règles (1 `report`, 2 `warn`, 3 `ok`) ;
  `isAgendaButtonEnabled` vrai avant versement, **faux** après
  `ReminderRules.toAgendaItems` ; fil sans rappel → `isEmpty` et bouton désactivé.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** (puce 7 px à la teinte du ton, bouton
  `Mettre à l'ordre du jour` en violet pâle, invite « Rien à ne pas oublier »).
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): carte « à ne pas oublier » et mise à l'ordre du jour`.

## Task 6 : `CommitmentsTableModel` et `CommitmentsTable`

**Fichiers :** créer `Views/Meeting/OneOnOne/ManagerPrep/CommitmentsTable.swift` ;
compléter `Services/OneOnOne/Prep/OneOnOnePrepStore.swift` (engagements) ;
test `Tests/ManagerPrepCommitmentsTableTests.swift`.

**Interfaces produites :**
```swift
enum PrepCommitmentFilter: String, CaseIterable, Hashable { case both, mine, theirs
    var side: OneOnOneSide? }
struct CommitmentsTableModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: PersistentIdentifier; var text: String
        var ownerLabel: String; var ownerTone: OneOnOneTone
        var dueLabel: String; var dueTone: OneOnOneTone?
        var promisedLabel: String; var isKept: Bool; var isOverdue: Bool
    }
    var rows: [Row]; var lateBadge: String?; var rateLabel: String?; var isEmpty: Bool
    static func build(_ thread: OneOnOneThread, filter: PrepCommitmentFilter,
                      now: Date) -> CommitmentsTableModel
    static func dueLabel(_ c: Commitment, now: Date) -> (String, OneOnOneTone?)
}
enum OneOnOnePrepStore { … addCommitment(text:ownerSide:dueAt:in:in:) ;
                             toggleKept(_:on:in:) }
```
Largeurs : `PrepColumn.state = 20`, `.owner = 92`, `.due = 84`, `.promised = 96`.

- [ ] **Étape 1 : test rouge** — tri par retard décroissant puis échéance ; filtre `mine`
  ne garde que le côté manager, `theirs` que le collaborateur ; `lateBadge ==
  "1 en retard côté manager"` ; `rateLabel == "8 tenus sur 11 · taux 73 %"` ; un `kept`
  affiche `Tenu` et `isKept` ; un ouvert échu affiche `En retard` en `report` ; une
  échéance dans les six jours donne le jour de la semaine ; `addCommitment` refuse le vide
  et pose `ownerSide = .manager` par défaut ; `toggleKept` solde puis réouvre.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** modèle, écritures, tableau et composeur `⌘⏎`.
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): tableau des engagements réciproques (2b)`.

## Task 7 : `RecurringTopicsCard` et `ThreadHistoryCard`

**Fichiers :** créer `.../RecurringTopicsCard.swift` et `.../ThreadHistoryCard.swift`.

**Interfaces produites :**
```swift
struct RecurringTopicsCardModel: Equatable {
    var topics: [RecurringTopic]; var isEmpty: Bool
    static func build(_ thread: OneOnOneThread, now: Date) -> RecurringTopicsCardModel
}
struct ThreadHistoryModel: Equatable {
    struct Row: Equatable, Identifiable { var id: PersistentIdentifier
        var dateLabel: String; var summary: String }
    var rows: [Row]; var isEmpty: Bool
    static let visibleCount = 4
    static func build(_ thread: OneOnOneThread, current: Meeting?, now: Date,
                      limit: Int = visibleCount) -> ThreadHistoryModel
}
```

- [ ] **Étape 1 : test rouge** — chips triées et colorées (`Charge de travail · 5` en
  `warn`, `Mobilité archi · 3` en `oneOnOne`, `Reconnaissance · 2` en `ok`) ; historique :
  **4** lignes au plus, la séance courante exclue, de la plus récente à la plus ancienne,
  dates `21 août / 24 juil. / 10 juil. / 26 juin`, résumé = `shortSummary` sinon
  `moral « Bien » · <premier sujet>` sinon une phrase d'invite ; fil sans séance
  antérieure → `isEmpty`.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** les deux modèles et les deux cartes.
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): sujets récurrents et historique du fil (2b)`.

## Task 8 : `ManagerPrepView`, câblage et barre d'assistant

**Fichiers :** créer `.../ManagerPrepView.swift` ; modifier
`Views/Meeting/Spaces/MeetingPrepareSpace.swift` (une branche, deux paramètres),
`Views/Meeting/Spaces/MeetingSpaceView.swift` (une branche),
`Views/Meeting/Spaces/MeetingAssistantDock.swift` (paramètre `threadContext`),
`Services/OneOnOne/OneOnOneScreenState.swift` — **non**, l'état va dans
`ManagerPrepView` sauf les deux propriétés `prep*` ajoutées en fin de
`OneOnOneScreenState` (`prepHistoryExpanded`, `prepAgendaFilled`).

- [ ] **Étape 1 : test rouge** — `MeetingAssistantDock.suggestions` rend la seule
  suggestion du fil quand `threadContext` est fourni ; l'invite de la carte vide est
  présente pour chaque carte d'un fil neuf (test sur les six modèles `isEmpty`).
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** l'assemblage (en-tête, rangée 1 de trois cartes, rangée 2
  en `1fr | 320`, dock en pied), la branche de `MeetingPrepareSpace`, le passage de
  `screen`/`menuActions` depuis `MeetingSpaceView` et le retrait du rail et du bandeau
  KPI pour ce mode.
- [ ] **Étape 4 : lancer** → vert. `swift build`.
- [ ] **Étape 5 : commit** `feat(refonte): écran de préparation 1:1 côté manager (2b)`.

## Task 9 : semis, `swift test` complet, recette, `STATUS.md`, PR

**Fichiers :** créer `Services/Debug/Seed/RefonteDemoSeed+Lot12.swift` ; modifier
`Views/Menus/MeetingCommands.swift` (une ligne) et `STATUS.md` (section en tête).

- [ ] **Étape 1 : test rouge** — après `seedLot12`, les quatre lignes d'`HISTORIQUE`
  portent un résumé non vide et `ThreadHistoryModel.build` rend les libellés de la capture.
- [ ] **Étape 2 : lancer** → rouge.
- [ ] **Étape 3 : implémenter** `seedLot12` (idempotent, appelle `seedOneOnOneThreads`)
  et l'appel dans l'item de menu « Charger le jeu de démonstration (refonte) ».
- [ ] **Étape 4 : `swift test`** complet vert.
- [ ] **Étape 5 : recette** `Scripts/recette-app.sh` puis `Scripts/recette-run.sh --seed`,
  captures `recette/lot-12-1920.png` et `recette/lot-12-1280.png`, comparaison à `2b`.
- [ ] **Étape 6 : `STATUS.md`** — section en tête (état, écarts, prochaine action, date).
- [ ] **Étape 7 : commit + push + `gh pr create --base fix/refonte-1to1-window-crash`.**

---

## Auto-relecture

**Couverture de la spec §3.4.** Moral (Task 3), objectifs (Task 4), à ne pas oublier
(Task 5), engagements réciproques avec filtre et pied (Task 6), sujets récurrents et
historique (Task 7), en-tête et boutons (Task 2), assistant sur le fil (Task 8), critère
chantier 2 n° 3 (Task 3), « aucune zone vide sans invite » (Task 8, étape 1).

**Cohérence de types.** `OneOnOneTone` est le seul vocabulaire de couleur des modèles ;
`PersistentIdentifier` est l'identité de toutes les lignes ; `now: Date` est passé
explicitement partout (aucun `Date()` implicite dans un modèle de vue, sinon les tests ne
sont pas reproductibles).

**Écarts connus à documenter dans `STATUS.md`** (la capture et le lot 10 divergent, et le
lot 10 est intouchable ici) : l'objectif à 10 % est `warn` et non violet (spec §3.4 :
« < 30 % warn ») ; les phrases des rappels viennent de `ReminderRules` (« Vous lui devez
Retour sur la grille d'astreinte — reporté 2 fois. ») et non de la maquette ;
`MoodTrend.explanation` compte cinq occurrences là où la maquette en écrit deux ; le tri
du tableau met l'engagement en retard en première ligne.
