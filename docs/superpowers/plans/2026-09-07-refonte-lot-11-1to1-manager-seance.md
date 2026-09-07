# Lot 11 — 1:1 manager, écran de séance (2a) — plan d'implémentation

> **Pour les sessions d'exécution :** TDD, `swift build` avant chaque commit,
> `swift test` complet vert avant la PR. Cases à cocher pour le suivi.

**Objectif :** rendre la capture `2a-1to1-manager-seance.png` — le mode **En séance** du type
`1:1` (rôle manager) — en grille `300 | 1fr | 320`, sans rail d'actions, sans KPI, sans présence.

**Architecture :** une branche unique dans `MeetingSpaceView` route `kind == .oneToOne` + `mode ==
.live` vers `ManagerSessionView`, qui monte trois colonnes. Toute la logique d'affichage décidable
vit dans des **modèles de vue purs** de `Views/Meeting/OneOnOne/Shared/` (lisibles par les lots 12
à 14, jamais modifiés par eux) ; les vues ne font que rendre. Aucun service du lot 10 n'est
modifié : ce qui manque est ajouté par fichier d'extension.

**Pile technique :** SwiftUI + SwiftData, jetons `One2OneToken`, composants
`Views/DesignSystem/Components/Refonte/*`, services 1:1 du lot 10, Swift Testing.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §3.1, §3.2, §3.3 et critères
chantier 2 n° 2 et 3 ; programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`
§5 « Lot 11 ».

## Contraintes globales

- Branche `feat/refonte-lot-11-1to1-manager-seance` sur `origin/fix/refonte-1to1-window-crash`
  (2 402 tests de référence).
- **Mes fichiers** : `Views/Meeting/OneOnOne/Manager/**`, `Views/Meeting/OneOnOne/Shared/**`,
  `Views/Meeting/Spaces/Notes/TimedNotesColumn+OneOnOne.swift`,
  `Services/OneOnOne/OneOnOneDateFormat+Lot11.swift`,
  `Services/Debug/Seed/RefonteDemoSeed+Lot11.swift`, `Tests/*Lot11*`, mes suites.
- **Interdits** : `Views/Meeting/Capture/**`, `Services/SlideCapture/**`,
  `Views/Meeting/Workshop/**`, `Services/Workshop/**`, `Views/Meeting/OneOnOne/ManagerPrep/**`,
  `Rail/**`, `Review/**`, `Session/**`, `Resources/**`, `Project/**`, et le **contenu existant**
  de `Services/OneOnOne/**` (extension par fichier neuf seulement).
- **Fichiers partagés, à la ligne près** : `MeetingSpaceLayout` (constantes + une fonction),
  `MeetingSpaceRouting` (une fonction), `MeetingSpaceView` (une branche), `NoteComposer` (deux
  paramètres optionnels, défaut = comportement actuel), `MeetingAssistantDock` (un paramètre de
  contexte optionnel), `MeetingTopChromeBar` (bloc `.oneToOne` localisé),
  `Models/OneOnOneModels.swift` (une colonne en fin de type), `Models/OtherModels.swift` (une
  colonne en fin de `Collaborator`), `OneToOneApp.swift` (crochet de recette),
  `Views/Menus/MeetingCommands.swift` (une ligne). `MeetingView.swift` : **rien**.
- Colonnes SwiftData ajoutées : optionnelles ou à valeur par défaut → migration légère, pas de
  `SchemaV4`.
- Libellés en français, symboles en anglais. Une couleur ne se nomme que dans `One2OneTokens.swift`.

---

## Structure de fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Shared/OneOnOneSeniority.swift` | Pur : `dans l'équipe depuis 3 ans` depuis `joinedAt`. |
| `Shared/OneOnOneMoodTone.swift` | Pur : le ton des cinq crans. |
| `Shared/OneOnOneNoteSections.swift` | Pur : les trois sections `①②③`, le feedback par côté, « 1:1 complet ». |
| `Shared/CommitmentsRailModel.swift` | Pur : groupes `Moi · n` / `<Prénom> · n`, lignes `✓ / ✗ n× reporté`, pilules d'échéance, criticité, confidentialité, invites de vide. |
| `Shared/AvatarSide.swift` | Vue : pastille d'avatar 16 / 34 px d'un côté du fil. |
| `Shared/PersonCard.swift` | Vue : carte personne (avatar 34, nom, rôle · ancienneté, `DERNIER 1:1`, `RYTHME`). |
| `Shared/MoodScale.swift` | Vue : les cinq crans + delta ; écrit `MoodEntry` via `MoodTrend.record`. |
| `Shared/CommitmentRow.swift` | Vue : une carte d'engagement (texte + pilules). |
| `Shared/OneOnOneComposerContext.swift` | Effets du composeur 1:1 (note / engagement / sujet), hors de `NoteComposer`. |
| `Manager/ManagerSessionView.swift` | La grille `300 \| 1fr \| 320` et la colonne gauche. |
| `Manager/ManagerAgendaCard.swift` | `ORDRE DU JOUR · co-construit` + `RESTÉ EN SUSPENS`. |
| `Manager/ManagerNotesColumn.swift` | Colonne centrale : en-tête, bascule de visibilité, `MoodScale`, sections, composeur. |
| `Manager/FeedbackCards.swift` | `CE QUE JE LUI DIS` / `CE QU'IL ME DIT` + indicateur « complet ». |
| `Manager/CommitmentsRail.swift` | Rail 320 px : engagements de la séance, tenus depuis, `CLÔTURER`. |
| `Spaces/Notes/TimedNotesColumn+OneOnOne.swift` | Rendu des lignes de notes 1:1, bloc privé isolé. |
| `Services/OneOnOne/OneOnOneDateFormat+Lot11.swift` | `Vendredi`, `4 septembre` — deux écritures de plus, au même endroit que les quatre autres. |
| `Services/Debug/Seed/RefonteDemoSeed+Lot11.swift` | Complète le jeu du lot 10 avec ce que 2a montre en plus. |

---

### Task 1 — Largeurs, routage, formats de date

**Fichiers :** modifier `Services/Meeting/MeetingSpaceLayout.swift`,
`Services/Meeting/MeetingSpaceRouting.swift` ; créer
`Services/OneOnOne/OneOnOneDateFormat+Lot11.swift`,
`Tests/OneOnOneSessionLayoutTests.swift`.

**Produit :** `MeetingSpaceLayout.oneOnOneLeftWidth = 300`, `oneOnOneRailWidth = 320`,
`oneOnOneColumns(totalWidth:) -> (left: CGFloat, center: CGFloat, rail: CGFloat)` ;
`MeetingSpaceRouting.usesOneOnOneManagerSession(kind:mode:) -> Bool` ;
`OneOnOneDateFormat.weekday(_:)`, `OneOnOneDateFormat.dayFullMonth(_:)`.

- [ ] **Étape 1** — test : à 1 280 px, `(300, 660, 320)` ; à 1 000 px la colonne gauche cède
      (`left == 0`) ; à 700 px le rail cède aussi ; jamais de largeur négative ;
      `usesOneOnOneManagerSession(.oneToOne, .live) == true` et faux pour `.manager`, `.global`,
      `.prepare`, `.review` ; `weekday` rend `Vendredi`, `dayFullMonth` rend `4 septembre`.
- [ ] **Étape 2** — `swift test --filter OneOnOneSessionLayout` : échoue.
- [ ] **Étape 3** — implémentation : `oneOnOneColumns` **délègue** à
      `columns(totalWidth:rail:sideNav:)` (`rail = 320`, `sideNav = 300`) pour que la règle
      « la fluide ne descend pas sous 520 » reste écrite une seule fois.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): largeurs et routage de l'écran de séance 1:1`.

### Task 2 — Colonnes SwiftData manquantes

**Fichiers :** modifier `Models/OtherModels.swift` (`Collaborator.joinedAt`),
`Models/OneOnOneModels.swift` (`Commitment.blocksOther`) ; créer
`Shared/OneOnOneSeniority.swift`, `Tests/OneOnOneSeniorityTests.swift`.

**Produit :** `Collaborator.joinedAt: Date?`, `Commitment.blocksOther: Bool` (défaut `false`),
`OneOnOneSeniority.label(joinedAt:now:) -> String?`.

- [ ] **Étape 1** — test : `label` rend `dans l'équipe depuis 3 ans` à 3 ans et 2 mois,
      `depuis 8 mois` à 8 mois, `depuis 1 an` à 13 mois, `nil` sans date, `nil` pour une date
      future ; les deux colonnes existent et gardent leur défaut.
- [ ] **Étape 2** — `swift test --filter OneOnOneSeniority` : échoue.
- [ ] **Étape 3** — implémentation. Les colonnes vont **en fin de type**, avec leur commentaire.
- [ ] **Étape 4** — tests verts + `swift test --filter SchemaV3Migration` vert.
- [ ] **Étape 5** — commit `feat(refonte): ancienneté et criticité d'engagement`.

### Task 3 — `CommitmentsRailModel` (critère chantier 2 n° 2)

**Fichiers :** créer `Shared/CommitmentsRailModel.swift`,
`Tests/CommitmentsRailModelTests.swift`.

**Consomme :** `CommitmentLedger`, `OneOnOneThreadStore`, `OneOnOneDateFormat`, `Commitment`.

**Produit :**
```swift
enum CommitmentsRailModel {
    struct Group: Identifiable { var side: OneOnOneSide; var title: String
                                 var initials: String; var commitments: [Commitment] }
    struct LedgerLine: Identifiable { var symbol: String; var text: String
                                      var initials: String; var isMissed: Bool
                                      var deferralLabel: String? }
    static func groups(for meeting: Meeting, in thread: OneOnOneThread) -> [Group]
    static func duePill(_ c: Commitment, now: Date) -> String?
    static func criticalityPill(_ c: Commitment) -> String?
    static func privacyPill(_ c: Commitment) -> String?
    static func effortPill(_ c: Commitment) -> String?
    static func ledgerLines(for meeting: Meeting, in thread: OneOnOneThread, now: Date) -> [LedgerLine]
    static func emptyInvite(for side: OneOnOneSide, thread: OneOnOneThread) -> String
    static func ledgerEmptyInvite() -> String
}
```

- [ ] **Étape 1** — tests : deux groupes titrés `Moi · 2` / `Laurent · 2` dans cet ordre (le manager
      d'abord, comme la capture) ; un engagement d'une **autre** séance n'y figure pas ; un groupe
      vide rend son invite au lieu d'une liste vide ; `duePill` rend le **jour de la semaine** dans
      la semaine calendaire de référence (`Vendredi`) et `9 sept.` au-delà, `nil` sans échéance ;
      `criticalityPill` rend `Bloquant pour lui` côté manager, `Bloquant pour moi` côté
      collaborateur, `nil` si `blocksOther == false` ; `privacyPill` rend `● privé` pour une ligne
      privée seulement ; `effortPill` rend `4h` depuis `linkedAction.effortMinutes == 240` ;
      `ledgerLines` rend `✓` pour un tenu depuis la séance précédente, **et** `✗` avec
      `2× reporté` pour un engagement **du manager** en retard non soldé — critère n° 2.
- [ ] **Étape 2** — `swift test --filter CommitmentsRailModel` : échoue.
- [ ] **Étape 3** — implémentation, pure et `@MainActor`.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): modèle de vue du rail d'engagements 1:1`.

### Task 4 — Sections de notes, feedback, « 1:1 complet », ton du moral

**Fichiers :** créer `Shared/OneOnOneNoteSections.swift`, `Shared/OneOnOneMoodTone.swift`,
`Tests/OneOnOneNoteSectionsTests.swift`.

**Produit :**
```swift
enum OneOnOneNoteSections {
    enum Section: String, CaseIterable { case howAreYou, topics, feedback
                                        var label: String }   // ① COMMENT ÇA VA…
    static func notes(_ meeting: Meeting, in section: Section) -> [MeetingNote]
    static func feedback(_ meeting: Meeting, _ s: NoteCommandParser.FeedbackSection) -> [MeetingNote]
    static func isComplete(_ meeting: Meeting) -> Bool
    static func completenessLabel(_ meeting: Meeting) -> String?
    static func emptyInvite(for section: Section) -> String
    static let privateLabel = "● NOTE PRIVÉE — VOUS SEUL"
}
enum OneOnOneMoodTone { static func tone(_ level: MoodLevel) -> OneOnOneTone }
```

- [ ] **Étape 1** — tests : les deux notes `kind: .feedback` vont en `③` et se répartissent
      `given` / `received` par `authorSide` ; la **première** note chronologique va en `①`, les
      suivantes en `②` (règle documentée : la première ligne répond à la question posée) ; une note
      `private` reste dans sa section ; `isComplete` est vrai seulement quand les deux cartes sont
      renseignées, et le libellé est `1:1 complet` ; chaque section vide rend une invite non vide ;
      les tons : `difficile → .report`, `sousTension → .warn`, `caVa → .oneOnOne`,
      `bien → .ok`, `tresBien → .ok`.
- [ ] **Étape 2** — `swift test --filter OneOnOneNoteSections` : échoue.
- [ ] **Étape 3** — implémentation.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): sections de notes et complétude du 1:1`.

### Task 5 — Composeur : catalogue de commandes et effets (critère n° 3 partiel)

**Fichiers :** créer `Shared/OneOnOneComposerContext.swift`,
`Tests/OneOnOneComposerContextTests.swift` ; modifier
`Views/Meeting/Spaces/Notes/NoteComposer.swift` (deux paramètres optionnels).

**Produit :** `struct OneOnOneComposerContext { let thread: OneOnOneThread; let role: OneOnOneSide;
var section: NoteCommandParser.FeedbackSection; var defaultVisibility: Visibility;
func apply(_ ligne: String, at t: Double, to meeting: Meeting, in context: ModelContext) -> Applied }`
avec `struct Applied { var note: MeetingNote?; var commitment: Commitment?; var agenda: OneOnOneAgendaItem?; var togglesPrivacy: Bool }`.

- [ ] **Étape 1** — tests : `NoteCommandCatalog.commands(for: .oneToOne, role: .manager)` rend
      exactement `/engagement /feedback /privé` (et `/promesse /demande /preuve` côté
      collaborateur, les quatre du lot 2 pour `.global`) ; `apply("/engagement Arbitrer le renfort")`
      crée **un** `Commitment` côté manager rattaché au fil, et **aucune** note ;
      `apply("/feedback Présentation claire")` crée une note `kind: .feedback` d'`authorSide`
      conforme à la section ; `apply("/privé Risque de départ")` crée une note `visibility:
      .private` ; une ligne nue prend la visibilité par défaut du rôle (`.shared` côté manager) ;
      une ligne vide n'écrit rien.
- [ ] **Étape 2** — `swift test --filter OneOnOneComposerContext` : échoue.
- [ ] **Étape 3** — implémentation, puis les deux paramètres de `NoteComposer` :
      `var commands: [NoteCommandCatalog.Entry]? = nil` et `var oneOnOne: OneOnOneComposerContext? = nil`.
      Défaut `nil` = rendu et validation **inchangés** pour tous les autres types.
- [ ] **Étape 4** — tests verts, `swift test --filter NoteComposer` vert.
- [ ] **Étape 5** — commit `feat(refonte): câbler le catalogue de commandes dans le composeur`.

### Task 6 — Colonne gauche : carte personne, ordre du jour, suspens, assistant

**Fichiers :** créer `Shared/AvatarSide.swift`, `Shared/PersonCard.swift`,
`Manager/ManagerAgendaCard.swift`, `Tests/OneOnOneAgendaCardTests.swift` ; modifier
`Views/Meeting/Spaces/MeetingAssistantDock.swift` (contexte optionnel).

**Produit :** `AvatarSide`, `PersonCard`, `ManagerAgendaCard`, `ManagerPendingTopicsCard`,
`MeetingAssistantDock.Contexte { placeholder, threadID }` +
`Contexte.fil(prenom:threadID:) -> Contexte`, `ManagerAgendaCard.Model` (pur : lignes, barré,
`→ 18/09`, invite de vide, réordonnancement).

- [ ] **Étape 1** — tests : `Model.rows` trie par `order` ; un item `done` est barré ; un item
      `deferred` porte `→ 18/09` (`AgendaCarryover.deferredLabel`) ; `move(from:to:)` réécrit les
      `order` de 0 à n−1 et les sauvegarde ; un ordre du jour vide rend l'invite
      `Ajoutez le premier sujet…` ; `RESTÉ EN SUSPENS` rend les deux entrées de la capture avec
      leur compte ; `Contexte.fil` rend le placeholder
      `Interroger l'historique des 1:1 de Laurent`.
- [ ] **Étape 2** — `swift test --filter OneOnOneAgendaCard` : échoue.
- [ ] **Étape 3** — implémentation des vues et du modèle.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): colonne gauche du 1:1 de séance`.

### Task 7 — Colonne centrale : moral, sections, feedback (critère n° 3)

**Fichiers :** créer `Shared/MoodScale.swift`, `Manager/ManagerNotesColumn.swift`,
`Manager/FeedbackCards.swift`, `Views/Meeting/Spaces/Notes/TimedNotesColumn+OneOnOne.swift`,
`Tests/OneOnOneMoodScaleTests.swift`.

- [ ] **Étape 1** — tests : `MoodTrend.record` depuis l'échelle crée **un** `MoodEntry` rattaché à
      la séance et au fil ; un second choix **remplace** au lieu d'ajouter (la série garde sa
      longueur) ; le cran choisi est celui relu ; `MoodTrend.deltaLabel` rend
      `↓ vs 21 août (Bien)` sur le jeu de démonstration — critère n° 3.
- [ ] **Étape 2** — `swift test --filter OneOnOneMoodScale` : échoue.
- [ ] **Étape 3** — implémentation : `MoodScale` (5 crans, cran choisi bordé de son ton),
      `OneOnOneNotesSection` (bloc privé : fond `bg/canvas`, barre gauche 2 px
      `accent/oneonone`, libellé `● NOTE PRIVÉE — VOUS SEUL`), `FeedbackCards`,
      `ManagerNotesColumn` (en-tête `Notes de l'entretien · liées à l'audio`, pilules
      `Partagé` / `Privé`, composeur avec les trois pilules du catalogue).
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): colonne centrale du 1:1 de séance`.

### Task 8 — Rail des engagements et clôture

**Fichiers :** créer `Shared/CommitmentRow.swift`, `Manager/CommitmentsRail.swift`,
`Tests/OneOnOneClosingTests.swift`.

- [ ] **Étape 1** — tests : le compte de lignes exclues du pied vient de
      `OneOnOneRecapBuilder.excludedLinesCount(for:thread:audience:)` et vaut **1** sur le jeu de
      démonstration (la note privée `17:30`) ; le libellé de clôture est
      `Envoyer le récap à Laurent` ; `Planifier le prochain — 18 sept.` vient de
      `OneOnOneThreadStore.nextPlannedDate` ; la mention
      `Les notes privées ne sont jamais incluses` est présente sans condition.
- [ ] **Étape 2** — `swift test --filter OneOnOneClosing` : échoue.
- [ ] **Étape 3** — implémentation. Le bouton primaire appelle
      `OneOnOneRecapActions.sendRecap(for:thread:audience: OneOnOneConfidentiality.recapAudience(for: .manager))`,
      le second `planNext`.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): rail des engagements et clôture du 1:1`.

### Task 9 — Assemblage, barre du haut, branche de routage

**Fichiers :** créer `Manager/ManagerSessionView.swift`,
`Tests/OneOnOneTopChromeSessionTests.swift` ; modifier
`Views/Meeting/Spaces/MeetingSpaceView.swift` (une branche),
`Views/Meeting/MeetingTopChromeBar.swift` (bloc `.oneToOne`).

**Produit :** `MeetingTopChromeBar.teamSegmentLabel(for:)`, `.privacyPillLabel(for:)`,
`.reportBaseLabel(for:)`, `.oneOnOneSessionHeading(person:date:)`.

- [ ] **Étape 1** — tests : `teamSegmentLabel(.oneToOne) == "Mon équipe"` et `nil` ailleurs ;
      `privacyPillLabel(.oneToOne) == "● Privé — vous deux"` et `nil` ailleurs ;
      `reportBaseLabel(.oneToOne) == "Rapport 1:1"`, `"Rapport"` ailleurs ;
      `oneOnOneSessionHeading` rend `Laurent NOMINÉ — entretien du 4 septembre`.
- [ ] **Étape 2** — `swift test --filter OneOnOneTopChromeSession` : échoue.
- [ ] **Étape 3** — implémentation + la branche
      `if MeetingSpaceRouting.usesOneOnOneManagerSession(kind: meeting.kind, mode: screen.mode)`
      dans `contenu`.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): assembler l'écran de séance 1:1 et sa barre du haut`.

### Task 10 — Jeu de démonstration et crochet de recette

**Fichiers :** créer `Services/Debug/Seed/RefonteDemoSeed+Lot11.swift`,
`Tests/RefonteDemoSeedLot11Tests.swift` ; modifier `Views/Menus/MeetingCommands.swift` (une ligne),
`OneToOne/OneToOneApp.swift` (crochet `ONETOONE_SEED_DEMO_SCREEN`).

- [ ] **Étape 1** — tests : `seedLot11` appelle `seedOneOnOneThreads`, puis complète — quatre
      cartes d'engagement de la séance (deux par côté), `blocksOther` sur l'arbitrage, `4h` sur la
      formation, `joinedAt` de Laurent à trois ans, trois lignes de `TENUS DEPUIS LE DERNIER 1:1`
      (deux ✓, un ✗ `2× reporté`) ; **semer deux fois ne duplique rien** (compte des réunions,
      des engagements et des notes identique).
- [ ] **Étape 2** — `swift test --filter RefonteDemoSeedLot11` : échoue.
- [ ] **Étape 3** — implémentation ; le menu gagne `_ = RefonteDemoSeed.seedLot11(in: demoContext)`.
- [ ] **Étape 4** — tests verts.
- [ ] **Étape 5** — commit `feat(refonte): jeu de démonstration du 1:1 de séance`.

### Task 11 — `swift test` complet, recette, STATUS, PR

- [ ] **Étape 1** — `swift build` propre.
- [ ] **Étape 2** — `swift test` complet vert, chiffres relevés (référence 2 402).
- [ ] **Étape 3** — recette : `Scripts/recette-app.sh` + `Scripts/recette-run.sh --seed` avec
      `ONETOONE_SEED_DEMO_SCREEN=2a`, captures `recette/lot-11-1920.png` et `lot-11-1280.png`,
      comparaison à `2a-1to1-manager-seance.png`.
- [ ] **Étape 4** — section `STATUS.md` en tête (état, écarts, prochaine action, date).
- [ ] **Étape 5** — push + `gh pr create --base fix/refonte-1to1-window-crash`.

---

## Revue du plan

- **Couverture de la spec §3.3** : carte personne (T6), ordre du jour co-construit + réordonnancement
  + barré + `→ date` (T6), resté en suspens (T6), assistant contexte = fil (T6), échelle de moral +
  delta (T7), notes horodatées + bloc privé isolé (T7), feedback deux cartes + « complet » (T4, T7),
  composeur `/engagement /feedback /privé` (T5), groupes d'engagements + pilules (T3, T8), tenus
  depuis + `n× reporté` y compris manager (T3), `CLÔTURER` + compte des exclus (T8), barre du haut
  (T9), grille `300 | 1fr | 320` (T1, T9), retraits (rail, KPI, présence) par la branche de T9.
- **Critères** : n° 2 → T3 ; n° 3 → T7 ; « aucune zone vide sans invite » → T3, T4, T6 ; largeur
  1 280 → T1.
- **Cohérence des types** : `OneOnOneTone` (lot 10) pour les tons, `NoteCommandParser.FeedbackSection`
  pour les côtés de feedback, `Visibility` pour la confidentialité — aucun type parallèle créé.
