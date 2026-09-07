# Lot 2 — Notes ↔ transcription, frise audio, action depuis une phrase

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> (exécution en session, points de contrôle) ou `superpowers:subagent-driven-development`.
> Les étapes sont des cases à cocher (`- [ ]`).

**But :** remplacer le contenu provisoire du mode En séance par la carte double colonne
« Notes & transcription · synchronisées sur l'audio » de `1a-cockpit.png` : notes horodatées
éditables, composeur à commandes `/` toujours visibles, transcription à rangée d'actions au
survol, création d'action en un clic depuis une phrase, frise audio de 22 px en pied.

**Architecture :** tout ce qui décide (nettoyage de phrase, parsing de commande, machine à
états du défilement, géométrie de la frise, marqueurs) est **pur et testé** dans
`OneToOne/Services/Meeting/` ; les vues de `OneToOne/Views/Meeting/Spaces/{Notes,Transcript}/`
n'assemblent. `MeetingLiveSpace` est réécrit : il ne reçoit plus de colonnes injectées par
`MeetingView`, il monte lui-même ses composants et lit le `ModelContext` de l'environnement.
L'UI de transcription et de locuteurs quitte `MeetingView.swift` (objectif −300 lignes).

**Pile :** SwiftUI + SwiftData, macOS 15, exécutable SwiftPM. Tests Swift Testing (`@Suite`,
`@Test`, `#expect`) — aucun test ne dépend de MLX ni d'une session graphique.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §2.4 (et §1.4, critère
d'acceptation n° 2 du chantier 1). Plan directeur :
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 2 ».
Capture qui fait foi : `docs/superpowers/specs/refonte-2026-09/ecrans/1a-cockpit.png`.

## Contraintes globales

- **Aucune couleur hors `One2OneToken`** ; les vues refondues lisent `\.one2OneTheme` quand
  elles peuvent être affichées en mode séance (lot 4).
- **Aucune dépendance nouvelle.**
- **Rien n'est ajouté à `MeetingView.swift`** : on en retire (programme §2.4 point 1). Seules
  exceptions tolérées : remplacer une closure existante par une autre d'une ligne, et
  supprimer des arguments d'appel.
- **Fichiers interdits** (lots 3 et 9 en parallèle) : `Views/Meeting/Spaces/Rail/**`,
  `Views/Shared/OwnerPickerMenu.swift`, `Models/ActionsViewMode.swift`,
  `Views/Meeting/Sidebar/ActionsPanel.swift`, `Views/ActionsListView.swift`,
  `Views/CalendarBoard.swift`, `Views/EisenhowerBoard.swift`, `Views/Project/**`,
  `Models/Project*`, `Services/ProjectCard*`, `Scripts/recette-app.sh`,
  `MeetingTopChromeBar.swift`.
- `MeetingScreenModel.swift` est partagé : les propriétés nouvelles s'ajoutent **en fin de
  type**, sans réordonner l'existant.
- Énums persistées : `…Raw: String` + wrapper calculé. Commentaires et libellés en français,
  symboles en anglais. Commits conventionnels, `swift build` avant chaque commit.
- `MeetingNoteKind`, `Visibility`, `SourceRef`, `MeetingNote`, `MeetingPlayhead`,
  `MeetingNoteStore`, `ConfidentialityFilter` existent (lot 0B) : **on ne change pas leur
  schéma**, on s'en sert.

---

## Structure des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Services/Meeting/NoteCommandParser.swift` (créé) | `/action /décision /risque /citer /privé …` → nature, texte, intention. Pur. |
| `Services/Meeting/ActionFromPhrase.swift` (créé) | Phrase → titre d'action nettoyé + `SourceRef` + responsable ; décision depuis un segment ; texte de citation. Pur + une fabrique `@MainActor`. |
| `Services/Meeting/TranscriptFollow.swift` (créé) | Machine à états `Suivre` / `Reprendre le suivi` + cible de défilement. Pur. |
| `Services/Meeting/AudioTimelineGeometry.swift` (créé) | `t ↔ x` de la frise, positions des marqueurs, hauteur 22. Pur. |
| `Services/Meeting/MeetingTimelineMarkers.swift` (créé) | Notes + captures → `[MeetingPlayhead.Marker]`. Pur. |
| `Services/AudioWaveformCache.swift` (créé) | Cache des pics d'onde par URL (une décimation par réunion, pas une par rendu). |
| `Views/Meeting/Spaces/Notes/TimedNotesColumn.swift` (créé) | Colonne MES NOTES : lignes `timecode | texte`, barre de nature, édition inline, menu de ligne, filtre. |
| `Views/Meeting/Spaces/Notes/NoteComposer.swift` (créé) | Composeur au timecode courant, pilules `/…` permanentes, `NoteComposerField` (Retour et ⌘⏎). |
| `Views/Meeting/Spaces/Transcript/TranscriptColumn.swift` (créé) | Colonne TRANSCRIPTION : moteur, live, segments, survol + rangée d'actions, défilement lié. |
| `Views/Meeting/Spaces/Transcript/TranscriptSpeakerTools.swift` (créé) | Badge de locuteur, popover de renommage, accept/reject de suggestion, couleur de cluster, menu de segment — **déplacés** de `MeetingView`. |
| `Views/Meeting/Spaces/AudioTimelineStrip.swift` (créé) | Frise 22 px : onde, tête de lecture, marqueurs, clic et glisser. |
| `Views/Meeting/Spaces/MeetingLiveSpace.swift` (réécrit) | Assemble en-tête + deux colonnes + frise. Plus de vues injectées. |
| `Views/Meeting/MeetingScreenModel.swift` (modifié, en fin de type) | `pendingActionDraft`, `noteFilter`, `noteComposerFocusToken`, `lastDiarizationEmbeddings`. |
| `Views/Meeting/Spaces/MeetingSpaceView.swift` (modifié) | Perd les paramètres génériques `Notes`/`Transcript`, garde `Actions`. |
| `Views/MeetingView.swift` (modifié, **retraits**) | `transcriptView`, `liveTranscriptSection`, `transcriptToolbar`, `transcriptSegmentsView`, `segmentRow`, `segmentActionsMenu`, `playSegmentAudio`, `speakerBadge`, `speakerRenamePopover`, `speakerPickerRow`, `firstCandidate`, `acceptSuggestion`, `rejectSuggestion`, `assignSpeaker`, `speakerColor`, `SpeakerMeta` et leurs `@State` sortent. |
| `Services/Debug/RefonteDemoSeed.swift` (modifié) | Sème les quatre `MeetingNote` horodatées de la capture et complète les segments. |
| `Tests/*` (créés) | `NoteCommandParserTests`, `ActionFromPhraseTests`, `TranscriptFollowTests`, `AudioTimelineGeometryTests`, `MeetingTimelineMarkersTests`, `ActionFromTranscriptCriterionTests` ; ajouts dans `MeetingScreenModelTests`, `MeetingNoteStoreTests`, `RefonteDemoSeedTests`. |

---

## Task 1 : `NoteCommandParser` — les commandes `/` du composeur

**Fichiers :**
- Créer : `OneToOne/Services/Meeting/NoteCommandParser.swift`
- Test : `Tests/NoteCommandParserTests.swift`

**Interfaces produites :**

```swift
enum NoteCommandParser {
    enum Command: String, CaseIterable, Sendable {
        case action, decision, risk, quote, secret, feedback, promise, request, proof
        /// Libellé de la pilule (`/action`, `/décision`…).
        var pill: String { get }
        /// Nature de note produite ; `nil` pour `.action` (qui ne crée pas de note).
        var noteKind: MeetingNoteKind? { get }
    }
    struct Parsed: Equatable, Sendable {
        var command: Command?
        var kind: MeetingNoteKind      // .note par défaut
        var text: String
        var visibility: Visibility?    // renseigné seulement par /privé
        var opensActionComposer: Bool  // vrai seulement pour /action
    }
    /// Les quatre pilules **toujours visibles** du composeur (spec §2.4).
    static let visiblePills: [Command] = [.action, .decision, .risk, .quote]
    static func parse(_ raw: String) -> Parsed
}
```

Règles : la commande doit être en **début de ligne** (après trim) ; reconnaissance
insensible à la casse **et aux accents** (`folding(options: [.diacriticInsensitive,
.caseInsensitive])`) ; une commande inconnue n'est pas mangée (texte rendu tel quel,
`command == nil`) ; `/décision` seul rend `text == ""` avec `kind == .decision`.

- [ ] **Étape 1 : écrire les tests qui échouent** (`Tests/NoteCommandParserTests.swift`) —
      au moins ces douze cas :

```swift
import Testing
@testable import OneToOne

@Suite("Commandes / du composeur de notes")
struct NoteCommandParserTests {

    @Test("/décision donne la nature decision et retire la commande")
    func decision() {
        let p = NoteCommandParser.parse("/décision le partenaire finalise la migration")
        #expect(p.command == .decision)
        #expect(p.kind == .decision)
        #expect(p.text == "le partenaire finalise la migration")
        #expect(p.opensActionComposer == false)
    }

    @Test("Sans accent et en majuscules, la commande est reconnue")
    func sansAccent() {
        #expect(NoteCommandParser.parse("/decision X").kind == .decision)
        #expect(NoteCommandParser.parse("/DÉCISION X").kind == .decision)
        #expect(NoteCommandParser.parse("/Risque X").kind == .risk)
    }

    @Test("/action pose l'intention d'ouvrir le composeur d'action, pas une note")
    func action() {
        let p = NoteCommandParser.parse("/action Vérifier l'état des comptes GitLab")
        #expect(p.command == .action)
        #expect(p.opensActionComposer)
        #expect(p.kind == .note)
        #expect(p.text == "Vérifier l'état des comptes GitLab")
    }

    @Test("Un texte sans commande passe intact")
    func texteSimple() {
        let p = NoteCommandParser.parse("40k déjà payés, rien de finalisé")
        #expect(p.command == nil)
        #expect(p.kind == .note)
        #expect(p.text == "40k déjà payés, rien de finalisé")
        #expect(p.visibility == nil)
    }

    @Test("/privé ne change pas la nature mais impose la visibilité")
    func prive() {
        let p = NoteCommandParser.parse("/privé à ne pas mettre dans le CR")
        #expect(p.command == .secret)
        #expect(p.kind == .note)
        #expect(p.visibility == .private)
        #expect(p.text == "à ne pas mettre dans le CR")
    }

    @Test("Une commande seule garde la nature et rend un texte vide")
    func commandeSeule() {
        let p = NoteCommandParser.parse("/décision")
        #expect(p.kind == .decision)
        #expect(p.text.isEmpty)
    }

    @Test("Les espaces de tête sont tolérés")
    func espaces() {
        #expect(NoteCommandParser.parse("   /risque compte désactivé").kind == .risk)
    }

    @Test("Une barre au milieu du texte n'est pas une commande")
    func barreAuMilieu() {
        let p = NoteCommandParser.parse("prod/preprod à aligner")
        #expect(p.command == nil)
        #expect(p.text == "prod/preprod à aligner")
    }

    @Test("Une commande inconnue n'est pas mangée")
    func commandeInconnue() {
        let p = NoteCommandParser.parse("/inconnu texte")
        #expect(p.command == nil)
        #expect(p.text == "/inconnu texte")
    }

    @Test("/citer conserve le texte cité en nature note")
    func citer() {
        let p = NoteCommandParser.parse("/citer « il faut vérifier les droits » — Laurent, 04:12")
        #expect(p.command == .quote)
        #expect(p.kind == .note)
        #expect(p.text == "« il faut vérifier les droits » — Laurent, 04:12")
    }

    @Test("Les natures 1:1 sont reconnues, elles existent déjà dans MeetingNoteKind")
    func natures1a1() {
        #expect(NoteCommandParser.parse("/feedback bon réflexe").kind == .feedback)
        #expect(NoteCommandParser.parse("/promesse je relance").kind == .promise)
        #expect(NoteCommandParser.parse("/demande une revue").kind == .request)
        #expect(NoteCommandParser.parse("/preuve le lien du livrable").kind == .proof)
    }

    @Test("Les quatre pilules visibles sont celles de la capture")
    func pilules() {
        #expect(NoteCommandParser.visiblePills.map(\.pill)
                == ["/action", "/décision", "/risque", "/citer"])
    }
}
```

- [ ] **Étape 2 : lancer et vérifier l'échec**
      `swift test --filter NoteCommandParserTests` → échec de compilation
      (`NoteCommandParser` inconnu).
- [ ] **Étape 3 : écrire `NoteCommandParser`** — table `Command` → alias acceptés
      (`action`; `decision`/`décision`; `risk`/`risque`; `quote`/`citer`;
      `secret`/`privé`/`prive`; `feedback`; `promise`/`promesse`; `request`/`demande`;
      `proof`/`preuve`), comparaison sur la forme repliée.
- [ ] **Étape 4 : `swift test --filter NoteCommandParserTests`** → vert.
- [ ] **Étape 5 : commit** `feat(reunion): parseur des commandes / des notes`

---

## Task 2 : `ActionFromPhrase` — une phrase devient une action

**Fichiers :**
- Créer : `OneToOne/Services/Meeting/ActionFromPhrase.swift`
- Test : `Tests/ActionFromPhraseTests.swift`

**Interfaces produites :**

```swift
enum ActionFromPhrase {
    struct Draft: Equatable, Sendable {
        var title: String
        var sourceRef: SourceRef
        var ownerName: String?
    }
    /// Longueur maximale d'un titre : au-delà, coupe au mot et ajoute « … ».
    static let maxTitleLength = 120
    static func title(from phrase: String) -> String
    static func draft(phrase: String, segmentID: UUID, t: Double, speakerName: String?) -> Draft
    /// Texte inséré par `Citer dans la note` : `« texte » — Locuteur, mm:ss`.
    static func quotation(phrase: String, speakerName: String?, t: Double) -> String
    @MainActor static func draft(from segment: TranscriptSegment) -> Draft
    @MainActor @discardableResult
    static func createAction(from segment: TranscriptSegment, in meeting: Meeting,
                             context: ModelContext) -> ActionTask
    @MainActor @discardableResult
    static func createDecision(from segment: TranscriptSegment, in meeting: Meeting,
                               context: ModelContext) -> MeetingNote
}
```

`title(from:)` : trim → retire les hésitations de tête (`euh`, `bah`, `ben`, `donc`, `alors`,
`hein`, `voilà`, `du coup`, `en fait`, répétées, suivies d'une virgule éventuelle) → retire
les guillemets encadrants (`« »`, `" "`, `' '`) → si la phrase commence par une amorce
d'obligation (`il faut`, `il faudrait`, `faut`, `on doit`, `on devrait`, `je dois`,
`tu dois`, `il faut que`, `on va`, `on peut`) **et** que le mot suivant ressemble à un
infinitif (suffixe `er`, `ir`, `re`, `oir`), l'amorce est retirée ; une amorce suivie de
`que`/`qu'` **n'est pas** retirée (ce n'est pas une construction infinitive) → retire la
ponctuation finale (`.`, `…`, `,`, `;`, `:`, `!`, `?`) → majuscule initiale → coupe à
`maxTitleLength` sur une frontière de mot avec `…`.

`createAction` pose `sourceRef = SourceRef(kind: .transcript, stableID: segment.ensuredStableID,
t: segment.startSeconds)`, `collaborator = segment.speaker`, `sortOrder` = le plus petit de la
réunion − 1 (l'action apparaît **en tête** du rail, spec §2.4), insère et sauvegarde.
`createDecision` crée `MeetingNote(t: segment.startSeconds, text: title(from:) sans mise à
l'infinitif — le texte brut nettoyé de sa ponctuation, kind: .decision,
visibility: MeetingNoteStore.defaultVisibility(for: meeting.kind))` avec le même `sourceRef`.

- [ ] **Étape 1 : écrire les tests qui échouent** (`Tests/ActionFromPhraseTests.swift`) —
      au moins ces douze cas :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Une action depuis une phrase de transcription")
struct ActionFromPhraseTests {

    @Test("« il faut » devient un infinitif en tête")
    func ilFaut() {
        #expect(ActionFromPhrase.title(from: "il faut remettre ça en route et vérifier les droits.")
                == "Remettre ça en route et vérifier les droits")
    }

    @Test("« on doit » aussi")
    func onDoit() {
        #expect(ActionFromPhrase.title(from: "on doit chiffrer la fin de migration.")
                == "Chiffrer la fin de migration")
    }

    @Test("Les hésitations de tête tombent")
    func hesitations() {
        #expect(ActionFromPhrase.title(from: "euh, donc il faut vérifier l'état des comptes GitLab.")
                == "Vérifier l'état des comptes GitLab")
        #expect(ActionFromPhrase.title(from: "bah euh donc on doit valider") == "Valider")
    }

    @Test("Les guillemets encadrants tombent")
    func guillemets() {
        #expect(ActionFromPhrase.title(from: "« Synchroniser les pipelines »")
                == "Synchroniser les pipelines")
    }

    @Test("Sans amorce d'obligation, la phrase est seulement nettoyée et capitalisée")
    func sansAmorce() {
        #expect(ActionFromPhrase.title(from: "tous les comptes ont été désactivés")
                == "Tous les comptes ont été désactivés")
    }

    @Test("« il faudrait » et « faut » sont reconnus")
    func variantes() {
        #expect(ActionFromPhrase.title(from: "il faudrait relancer Alexis") == "Relancer Alexis")
        #expect(ActionFromPhrase.title(from: "faut planifier la formation")
                == "Planifier la formation")
    }

    @Test("Une amorce suivie de « que » n'est pas retirée : ce n'est pas un infinitif")
    func amorceAvecQue() {
        #expect(ActionFromPhrase.title(from: "il faut que le partenaire finalise")
                == "Il faut que le partenaire finalise")
    }

    @Test("Une phrase vide ne produit pas de titre")
    func vide() {
        #expect(ActionFromPhrase.title(from: "   ").isEmpty)
    }

    @Test("Un titre trop long est coupé au mot")
    func trop_long() {
        let phrase = String(repeating: "reprendre l'état des lieux ", count: 20)
        let titre = ActionFromPhrase.title(from: phrase)
        #expect(titre.count <= ActionFromPhrase.maxTitleLength + 1)
        #expect(titre.hasSuffix("…"))
        #expect(!titre.contains("  "))
    }

    @Test("Le brouillon conserve la source et le locuteur")
    func brouillon() {
        let id = UUID()
        let d = ActionFromPhrase.draft(phrase: "il faut vérifier les droits.",
                                       segmentID: id, t: 252, speakerName: "Laurent Deberti")
        #expect(d.title == "Vérifier les droits")
        #expect(d.sourceRef.kind == .transcript)
        #expect(d.sourceRef.stableID == id)
        #expect(d.sourceRef.t == 252)
        #expect(d.ownerName == "Laurent Deberti")
    }

    @Test("Sans locuteur résolu, le responsable reste vide plutôt que devineté")
    func sansLocuteur() {
        let d = ActionFromPhrase.draft(phrase: "chiffrer la fin", segmentID: UUID(),
                                       t: 0, speakerName: nil)
        #expect(d.ownerName == nil)
    }

    @Test("La citation reprend le texte, le locuteur et le timecode")
    func citation() {
        #expect(ActionFromPhrase.quotation(phrase: "il faut vérifier les droits.",
                                           speakerName: "Laurent", t: 252)
                == "« il faut vérifier les droits. » — Laurent, 04:12")
        #expect(ActionFromPhrase.quotation(phrase: "texte", speakerName: nil, t: 0)
                == "« texte » — 00:00")
    }
}
```

- [ ] **Étape 2 : lancer et vérifier l'échec** — `swift test --filter ActionFromPhraseTests`.
- [ ] **Étape 3 : écrire `ActionFromPhrase`** (partie pure d'abord, puis les deux fabriques
      `@MainActor`).
- [ ] **Étape 4 : `swift test --filter ActionFromPhraseTests`** → vert.
- [ ] **Étape 5 : replier le critère d'acceptation n° 2 du chantier 1** dans
      `Tests/ActionFromTranscriptCriterionTests.swift` — un test de bout en bout **sans vue** :
      segment → `ActionFromPhrase.createAction` (un seul appel = le clic) → `sourceRef`
      conservé (`kind == .transcript`, `stableID` du segment, `t`) →
      `MeetingPlayhead.seek(to: sourceRef.t!)` replace la lecture à ± 1 s → l'action est en
      tête du rail (`sortOrder` minimal) → `createDecision` produit une
      `MeetingNote(kind: .decision)` au `t` du segment avec la même source.
- [ ] **Étape 6 : `swift test --filter ActionFromTranscriptCriterionTests`** → vert.
- [ ] **Étape 7 : commit** `feat(reunion): une action depuis une phrase de transcription`

---

## Task 3 : l'état d'écran du lot — `MeetingScreenModel`

**Fichiers :**
- Modifier : `OneToOne/Views/Meeting/MeetingScreenModel.swift` (**en fin de type**)
- Test : `Tests/MeetingScreenModelTests.swift` (ajouts)

**Interfaces consommées :** `ActionFromPhrase.Draft` (Task 2).
**Interfaces produites :**

```swift
// en fin de MeetingScreenModel
var noteFilter: MeetingNoteKind?           // filtre de la colonne de notes (KPI Décisions)
var pendingActionDraft: ActionFromPhrase.Draft?  // intention « ouvrir le composeur prérempli »
private(set) var noteComposerFocusToken = 0
var lastDiarizationEmbeddings: [Int: [Float]] = [:]
func focusNoteComposer()                   // incrémente le jeton
func requestAction(from draft: ActionFromPhrase.Draft)  // pose l'intention + préremplit newTaskTitle
func toggleNoteFilter(_ kind: MeetingNoteKind)          // même nature deux fois = plus de filtre
```

- [ ] **Étape 1 : écrire les tests qui échouent** dans `Tests/MeetingScreenModelTests.swift` :

```swift
@Test("Le filtre de notes bascule sur la même nature")
func filtreDeNotes() {
    let m = MeetingScreenModel(defaults: UserDefaults(suiteName: "test.filtre")!)
    #expect(m.noteFilter == nil)
    m.toggleNoteFilter(.decision)
    #expect(m.noteFilter == .decision)
    m.toggleNoteFilter(.decision)
    #expect(m.noteFilter == nil)
    m.toggleNoteFilter(.risk)
    #expect(m.noteFilter == .risk)
}

@Test("Une action demandée depuis une phrase préremplit le composeur du rail")
func intentionDAction() {
    let m = MeetingScreenModel(defaults: UserDefaults(suiteName: "test.intention")!)
    let d = ActionFromPhrase.draft(phrase: "il faut vérifier les droits.",
                                   segmentID: UUID(), t: 252, speakerName: "Laurent")
    m.requestAction(from: d)
    #expect(m.pendingActionDraft == d)
    #expect(m.newTaskTitle == "Vérifier les droits")
    #expect(m.pendingActionDraft?.sourceRef.t == 252)
}

@Test("Le focus du composeur de notes passe par un jeton, pas par un booléen")
func jetonDeFocus() {
    let m = MeetingScreenModel(defaults: UserDefaults(suiteName: "test.focus")!)
    let depart = m.noteComposerFocusToken
    m.focusNoteComposer()
    m.focusNoteComposer()
    #expect(m.noteComposerFocusToken == depart + 2)
}
```

  (Un booléen ne permettrait pas deux `⌘⇧N` de suite : la deuxième pression ne changerait
  rien et le composeur ne reprendrait pas le focus.)

- [ ] **Étape 2 : lancer et vérifier l'échec** — `swift test --filter MeetingScreenModelTests`.
- [ ] **Étape 3 : ajouter les propriétés et méthodes en fin de type**, avec les commentaires
      qui disent pourquoi elles vivent là (état d'écran, non persisté).
- [ ] **Étape 4 : `swift test --filter MeetingScreenModelTests`** → vert.
- [ ] **Étape 5 : commit** `feat(reunion): filtre de notes, intention d'action, jeton de focus`

---

## Task 4 : timecode `--:--` et fabrique de note au timecode courant

**Fichiers :**
- Modifier : `OneToOne/Services/MeetingNoteStore.swift`
- Test : `Tests/MeetingNoteStoreTests.swift` (ajouts)

**Interfaces produites :**

```swift
extension MeetingNoteStore {
    /// `04:12`, ou `--:--` quand la réunion n'a aucun axe temps (spec : « en dehors de
    /// tout audio, t = 0 et le timecode s'affiche --:-- »).
    static func timecodeLabel(t: Double, hasTimeline: Bool) -> String
    /// Crée la ligne à `t`, avec la nature, la visibilité par défaut du type de réunion
    /// (ou celle imposée par `/privé`) et l'ordre de fin de liste.
    @MainActor @discardableResult
    static func append(_ parsed: NoteCommandParser.Parsed, at t: Double,
                       to meeting: Meeting, in context: ModelContext) -> MeetingNote?
}
```

`append` rend `nil` si le texte est vide après parsing (une ligne vide n'est pas une note) ;
`orderIndex` = max des notes à `t` égal + 1.

- [ ] **Étape 1 : écrire les tests qui échouent** :

```swift
@Test("Sans axe temps, le timecode se lit --:--")
func timecodeSansAudio() {
    #expect(MeetingNoteStore.timecodeLabel(t: 0, hasTimeline: false) == "--:--")
    #expect(MeetingNoteStore.timecodeLabel(t: 0, hasTimeline: true) == "00:00")
    #expect(MeetingNoteStore.timecodeLabel(t: 252, hasTimeline: true) == "04:12")
    // Un t non nul est un axe temps réel, même si l'appelant l'a oublié.
    #expect(MeetingNoteStore.timecodeLabel(t: 252, hasTimeline: false) == "04:12")
}

@Test("Une commande de composeur devient une ligne horodatée")
@MainActor
func ajoutDepuisComposeur() throws {
    let container = try ModelContainer(
        for: Schema(CurrentSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    let reunion = Meeting(title: "R", date: Date(), notes: "")
    context.insert(reunion)

    let note = MeetingNoteStore.append(NoteCommandParser.parse("/décision on y va"),
                                       at: 663, to: reunion, in: context)
    #expect(note?.kind == .decision)
    #expect(note?.t == 663)
    #expect(note?.text == "on y va")
    #expect(note?.visibility == .shared)

    #expect(MeetingNoteStore.append(NoteCommandParser.parse("/décision   "),
                                    at: 10, to: reunion, in: context) == nil)

    let prive = MeetingNoteStore.append(NoteCommandParser.parse("/privé pour moi"),
                                        at: 12, to: reunion, in: context)
    #expect(prive?.visibility == .private)
    #expect(reunion.timedNotes.count == 2)
}

@Test("Deux notes au même timecode gardent leur ordre de saisie")
@MainActor
func ordreAMemeTimecode() throws { /* deux append à t identique → orderIndex croissant */ }
```

- [ ] **Étape 2 : lancer et vérifier l'échec.**
- [ ] **Étape 3 : implémenter les deux fonctions** dans `MeetingNoteStore`.
- [ ] **Étape 4 : `swift test --filter MeetingNoteStoreTests`** → vert.
- [ ] **Étape 5 : commit** `feat(reunion): fabrique de note horodatée depuis le composeur`

---

## Task 5 : `TranscriptFollow` — le défilement lié

**Fichiers :**
- Créer : `OneToOne/Services/Meeting/TranscriptFollow.swift`
- Test : `Tests/TranscriptFollowTests.swift`

**Interfaces produites :**

```swift
enum TranscriptFollow {
    enum Event: Sendable { case manualScroll, resumeRequested, playheadMoved, segmentsAppended }
    static func next(following: Bool, on event: Event) -> Bool
    static func label(following: Bool) -> String   // "Suivre" / "Reprendre le suivi"
    /// Segment sur lequel se caler : le dernier commencé avant `t`.
    static func target(startTimes: [Double], t: Double) -> Int?
}
```

- [ ] **Étape 1 : écrire les tests qui échouent** — au moins : le suivi part actif ;
      `manualScroll` le désactive ; `resumeRequested` le réactive ; `playheadMoved` et
      `segmentsAppended` ne le réactivent **jamais** (c'est le défaut que la spec nomme :
      « toute interaction manuelle la désactive ») ; libellés exacts ; `target` rend `nil`
      avant le premier segment, l'index du dernier segment commencé sinon, le dernier index
      au-delà de la fin, et `nil` sur une liste vide.
- [ ] **Étape 2 : lancer et vérifier l'échec.**
- [ ] **Étape 3 : implémenter.**
- [ ] **Étape 4 : `swift test --filter TranscriptFollowTests`** → vert.
- [ ] **Étape 5 : commit** `feat(reunion): machine à états du défilement lié`

---

## Task 6 : géométrie de la frise et marqueurs

**Fichiers :**
- Créer : `OneToOne/Services/Meeting/AudioTimelineGeometry.swift`,
  `OneToOne/Services/Meeting/MeetingTimelineMarkers.swift`
- Test : `Tests/AudioTimelineGeometryTests.swift`, `Tests/MeetingTimelineMarkersTests.swift`

**Interfaces produites :**

```swift
enum AudioTimelineGeometry {
    static let height: CGFloat = 22          // spec §2.4
    static let playheadWidth: CGFloat = 2
    static let markerSize: CGFloat = 7
    static func x(t: Double, duration: Double, width: CGFloat) -> CGFloat
    static func t(x: CGFloat, duration: Double, width: CGFloat) -> Double
}

@MainActor
enum MeetingTimelineMarkers {
    /// Notes (rond), décisions (losange), risques (rond `warn`), captures (carré).
    static func markers(for meeting: Meeting) -> [MeetingPlayhead.Marker]
    static func kind(for noteKind: MeetingNoteKind) -> MeetingPlayhead.Marker.Kind
}
```

`x` : `duration <= 0` → 0 (jamais de division par zéro, jamais de NaN dans un `Canvas`) ;
borné à `0…width`. `t` : inverse borné à `0…duration`.

- [ ] **Étape 1 : écrire les tests qui échouent** — `x(t:0)==0`, `x(t:duration)==width`,
      `x` borné au-delà, `duration == 0 → 0`, aller-retour `t(x(t)) == t` à 0,01 s près,
      `t` borné ; marqueurs : une note → `.note`, une décision → `.decision`, un risque →
      `.risk`, une capture avec `t` → `.capture`, une capture sans `t` **ignorée**, tri par
      timecode croissant.
- [ ] **Étape 2 : lancer et vérifier l'échec.**
- [ ] **Étape 3 : implémenter.**
- [ ] **Étape 4 : `swift test --filter AudioTimelineGeometryTests`,
      `swift test --filter MeetingTimelineMarkersTests`** → vert.
- [ ] **Étape 5 : commit** `feat(reunion): géométrie et marqueurs de la frise audio`

---



## Task 7 : `TimedNotesColumn`

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Notes/TimedNotesColumn.swift`

```swift
struct TimedNotesColumn: View {
    let meeting: Meeting
    let screen: MeetingScreenModel
    @Environment(\.modelContext) private var context
}
```

Contenu (capture `1a-cockpit.png`, colonne gauche) :
- `MeetingNoteStore.sorted` puis `MeetingNoteStore.filtered(_, kind: screen.noteFilter)`.
- Ligne : `TimecodeLabel`-like en `accent/action` **cliquable** → `screen.playhead.seek(to:)`
  (et `beginPlayback()` si un WAV est chargé) ; texte `plexSans(12)` `ink2` ; barre gauche de
  2 px `accent/report` pour `.decision`, `accent/warn` pour `.risk`, rien sinon ; préfixe
  `Décision — ` en gras pour une décision (capture) ; timecode `--:--` via
  `MeetingNoteStore.timecodeLabel(t:hasTimeline:)`.
- Édition inline : double-clic (ou item de menu « Modifier ») → `EditableTextField` lié à
  `note.text`, `context.save()` à la sortie.
- Menu de ligne (`.contextMenu` + `⋯` au survol) : nature (les sept `MeetingNoteKind`),
  visibilité (les trois `Visibility`), « Supprimer ».
- Bandeau de filtre quand `screen.noteFilter != nil` : `Chip("kind:décision", ton: .report)`
  + « tout afficher » → `screen.noteFilter = nil`.
- Vide → `MeetingEmptyInvite(space: .meeting, mode: .live)` (critère n° 1, invite existante).
- `NoteComposer` en pied de colonne.

- [ ] **Étape 1 : écrire la vue.**
- [ ] **Étape 2 : `swift build`** → propre, aucun avertissement nouveau.
- [ ] **Étape 3 : commit** `feat(reunion): colonne des notes horodatées`

---

## Task 8 : `NoteComposer`

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Notes/NoteComposer.swift`

```swift
struct NoteComposer: View {
    let meeting: Meeting
    let screen: MeetingScreenModel
    @Environment(\.modelContext) private var context
}
/// Champ AppKit du composeur : Retour et ⌘⏎ valident, le jeton de focus rend
/// le clavier au champ sans le vider.
private struct NoteComposerField: NSViewRepresentable { … }
```

- Cadre en pointillés (capture) : `RoundedRectangle(cornerRadius: radiusButton)
  .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))` en `One2OneToken.hair`.
- `Tape` en `ink4` puis les **quatre pilules toujours visibles**
  (`NoteCommandParser.visiblePills`, `Chip(ton:)` : action, report, warn, neutre) — cliquer
  une pilule insère la commande dans le champ.
- Texte lié à `screen.pendingNoteText` (critère n° 4 du lot 1 : la saisie survit au
  changement de mode).
- Validation : `NoteCommandParser.parse` →
  - `parsed.opensActionComposer` → `screen.requestAction(from: ActionFromPhrase.draft(
    phrase: parsed.text, segmentID: meeting.ensuredStableID, t: screen.playhead.t,
    speakerName: nil))` (le rail arrive au lot 3 ; l'intention et le préremplissage sont
    posés dès maintenant) ;
  - sinon `MeetingNoteStore.append(parsed, at: t, to: meeting, in: context)` avec
    `t = screen.playhead.t` — le composeur horodate au timecode courant, `0` hors audio.
  Puis `screen.pendingNoteText = ""` **sans perdre le focus**.
- `screen.noteComposerFocusToken` observé (`.onChange`) → `makeFirstResponder`.

- [ ] **Étape 1 : écrire la vue et le champ AppKit.**
- [ ] **Étape 2 : `swift build`** → propre.
- [ ] **Étape 3 : commit** `feat(reunion): composeur de notes à commandes visibles`

---

## Task 9 : `TranscriptSpeakerTools` — déménagement depuis `MeetingView`

**Fichiers :**
- Créer : `OneToOne/Views/Meeting/Spaces/Transcript/TranscriptSpeakerTools.swift`
- Modifier (**retraits**) : `OneToOne/Views/MeetingView.swift`

Déplacer **sans changer le comportement** : `SpeakerMeta`, `speakerBadge(for:)`,
`speakerRenamePopover(speakerID:)`, `speakerPickerRow(_:speakerID:highlighted:)`,
`firstCandidate(stableIDs:)`, `acceptSuggestion(_:for:)`, `rejectSuggestion(for:)`,
`assignSpeaker(speakerID:to:)`, `speakerColor(_:)`, `segmentActionsMenu(_:)`.

Forme cible : `struct TranscriptSpeakerBadge: View` (état local : `renamingSpeakerID`,
`speakerPickerSearch`) + `enum TranscriptSpeakerTools` pour les fonctions pures/`@MainActor`
(`speakerColor`, `assignSpeaker`, `acceptSuggestion`, `rejectSuggestion`, `firstCandidate`).
Le cache d'embeddings de diarisation passe de `@State` de `MeetingView` à
`MeetingScreenModel.lastDiarizationEmbeddings` (Task 3) : la mise à jour EMA du voiceprint
doit continuer de fonctionner après le déménagement.

`MeetingView` **garde** `runDiarization`, `reidentifySpeakers`, `applySpeakerTurns`,
`transcriptionPhaseBanner` et les expose au besoin par closures.

- [ ] **Étape 1 : créer le fichier** avec le code déplacé, adapté aux jetons de la refonte
      **là seulement où la capture l'impose** (badge de locuteur : `plexSans(11.5, .semibold)`
      `ink1`, pastille de cluster inchangée).
- [ ] **Étape 2 : retirer les membres correspondants de `MeetingView.swift`** et brancher le
      cache d'embeddings sur `screen`.
- [ ] **Étape 3 : `swift build`** → propre ; `git diff --stat OneToOne/Views/MeetingView.swift`
      doit montrer un solde **négatif**.
- [ ] **Étape 4 : commit** `refactor(reunion): les outils de locuteurs quittent MeetingView`

---

## Task 10 : `TranscriptColumn`

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Transcript/TranscriptColumn.swift`

```swift
struct TranscriptColumn: View {
    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let onDiarize: () -> Void
    let onReidentify: () -> Void
    @Environment(\.modelContext) private var context
}
extension STTEngineKind { var refonteLabel: String }   // "Cohere MLX" | "Voxtral" | "Qwen3-ASR"
```

- En-tête de colonne : `SectionLabel("transcription")` + `MonoMeta(settings.transcriptionEngine
  .refonteLabel)` (capture : `TRANSCRIPTION  Cohere MLX`) ; à droite, quand
  `settings.transcriptionMode == .diarizeFirst` : `Suivre` / `Reprendre le suivi`
  (`TranscriptFollow.label`), `Détecter les speakers`, `Ré-identifier`.
- Fond `surface/alt` (déjà posé par `MeetingLiveSpace`).
- **Live** : si `LiveTranscriptionService.shared.isLive || !liveTranscript.isEmpty`, une
  première ligne « ● en direct » + le texte live, dans la **même** colonne.
- Segments triés par `orderIndex` : `TimecodeLabel(seconds:)` cliquable (charge le WAV,
  `playhead.beginPlayback()`, `seek`, `play` — l'ancien `playSegmentAudio`), badge de
  locuteur (`TranscriptSpeakerBadge`) quand `screen.showSpeakers`, texte `plexSans(12)`
  sélectionnable.
- **Survol** : fond `accent/action bg`, coins `radiusButton`, et rangée d'actions révélée :
  `＋ Action` (plein `accent/action`, encre `onFilledButton`), `Décision`, `Citer dans la
  note` (contour `strongBorder`). Actions :
  - `＋ Action` → `ActionFromPhrase.createAction(from:in:context:)` **et**
    `screen.requestAction(from: ActionFromPhrase.draft(from: segment))` (le rail du lot 3
    animera l'insertion) ;
  - `Décision` → `ActionFromPhrase.createDecision(from:in:context:)` ;
  - `Citer dans la note` → `screen.pendingNoteText = ActionFromPhrase.quotation(...)` +
    `screen.focusNoteComposer()`.
- `⌘⇧A` : bouton d'opacité nulle en `.overlay`, actif sur le segment survolé (à défaut, le
  dernier survolé). Aucun raccourci n'est ajouté à `MeetingCommands` : `⌘⇧A` et `⌘⇧N` vivent
  dans l'espace qui les rend possibles, ce qui évite d'ajouter des closures à `MeetingView`.
- **Défilement lié** : `ScrollViewReader` ; `screen.follow` piloté par `TranscriptFollow.next` ;
  `.onChange(of: screen.playhead.t)` → `scrollTo(TranscriptFollow.target(...))` si
  `screen.follow` ; un `DragGesture` / une molette / un clic de segment → `.manualScroll`.
- Vide et hors live → invite (« Démarre un enregistrement… ») via `MeetingEmptyInvite`.
- Alerte de suppression de segment (l'ancienne de `transcriptSegmentsView`) rattachée ici.

- [ ] **Étape 1 : écrire la vue.**
- [ ] **Étape 2 : `swift build`** → propre.
- [ ] **Étape 3 : commit** `feat(reunion): colonne de transcription et rangée d'actions au survol`

---

## Task 11 : `AudioTimelineStrip`

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/AudioTimelineStrip.swift`

```swift
struct AudioTimelineStrip: View {
    let meeting: Meeting
    let screen: MeetingScreenModel
}
```

- Hauteur `AudioTimelineGeometry.height` (22) ; `00:00` à gauche, durée à droite en
  `plexMono(9.5)` `ink4` (capture).
- `Canvas` : barres d'onde `actionBg`/`action.opacity(0.35)` depuis
  `AudioWaveformCache.shared.peaks(url:count:)` (`count` = largeur / 6, borné) ; **sans WAV**,
  une piste plate `hair` de 6 px et l'invite « Aucun audio » en `ink4`.
- Tête de lecture : rectangle de 2 px `accent/action` à `AudioTimelineGeometry.x(t:…)`.
- Marqueurs `MeetingTimelineMarkers.markers(for:)` : rond (note), losange (décision), rond
  `warn` (risque), carré `captureMarker` (capture).
- Clic → `screen.playhead.seek(to: AudioTimelineGeometry.t(x:…))` ; `DragGesture` → balayage
  continu.

- [ ] **Étape 1 : `AudioWaveformCache`** — créer `OneToOne/Services/AudioWaveformCache.swift`
      et `Tests/AudioWaveformCacheTests.swift` :

```swift
@MainActor
final class AudioWaveformCache {
    static let shared = AudioWaveformCache()
    /// Pics décimés pour `url`, calculés une fois par (URL, nombre de pics).
    func peaks(url: URL, count: Int) async -> [Float]
    /// Oublie une URL (fichier réécrit par l'édition audio).
    func invalidate(url: URL)
    var cachedCount: Int { get }   // pour les tests
}
```

      Sans le cache, la frise redécimerait le WAV à chaque rendu. Rend `[]` sur erreur de
      lecture — la frise dessine alors une piste plate, jamais un plantage. Tests : deux
      appels sur la même URL inexistante ne gonflent pas le cache au-delà d'une entrée et
      rendent `[]` ; `invalidate` vide.
- [ ] **Étape 2 : `swift test --filter AudioWaveformCacheTests`** → vert.
- [ ] **Étape 3 : écrire la vue.**
- [ ] **Étape 4 : `swift build`** → propre.
- [ ] **Étape 5 : commit** `feat(reunion): frise audio de 22 px et cache des pics d'onde`

---

## Task 12 : `MeetingLiveSpace` réécrit et câblage

**Fichiers :**
- Réécrire : `OneToOne/Views/Meeting/Spaces/MeetingLiveSpace.swift`
- Modifier : `OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift` (lignes de construction
  de `MeetingLiveSpace` + paramètres génériques `Notes`/`Transcript` retirés,
  `Actions` conservé pour le lot 3)
- Modifier (**retraits**) : `OneToOne/Views/MeetingView.swift`

```swift
struct MeetingLiveSpace: View {   // plus de génériques
    let meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    let showsSpeakerToggle: Bool
    let onSummarize: () -> Void
    let onDiarize: () -> Void
    let onReidentify: () -> Void
    static var headerHeight: CGFloat { 34 }
}
```

En-tête **inchangé** (lot 1) : titre, « synchronisées sur l'audio », `Speakers ON/OFF`,
`Résumer`. Corps : `TimedNotesColumn` | filet | `TranscriptColumn` par
`MeetingSpaceLayout.evenSplit`. Pied : `AudioTimelineStrip`. `⌘⇧N` (bouton d'opacité nulle) →
`screen.focusNoteComposer()`. `.task`/`.onChange` → `screen.playhead.markers =
MeetingTimelineMarkers.markers(for: meeting)` et `duration` calée sur
`meeting.durationSeconds` quand aucun fichier n'est chargé.

Retraits dans `MeetingView` : `transcriptView`, `liveTranscriptSection`, `isLiveActive`,
`transcriptToolbar`, `transcriptSegmentsView`, `segmentRow`, `playSegmentAudio`,
`segmentActionsMenu`, `segmentToDelete`/`renamingSpeakerID`/`speakerPickerSearch`/
`lastDiarizationEmbeddings` (`@State`), et les arguments `notes:`/`transcript:` de
`MeetingSpaceView`. `onFilterDecisions` devient `{ screen.toggleNoteFilter(.decision) }`
(le KPI Décisions filtre enfin les notes, spec §2.3).

- [ ] **Étape 1 : réécrire `MeetingLiveSpace`.**
- [ ] **Étape 2 : adapter `MeetingSpaceView` et `MeetingView`.**
- [ ] **Étape 3 : `swift build`** → propre.
- [ ] **Étape 4 : `swift test`** complet → vert (référence : 1 801 tests après lot 1).
- [ ] **Étape 5 : commit** `feat(reunion): la carte notes ↔ transcription remplace les vues provisoires`

---

## Task 13 : jeu de démonstration

**Fichiers :** Modifier `OneToOne/Services/Debug/RefonteDemoSeed.swift`,
`Tests/RefonteDemoSeedTests.swift`

Semer les **quatre notes horodatées** de la capture (`04:12` = 252, `07:48` = 468,
`11:03` = 663 en `kind: .decision`, `15:20` = 920) et poser `notesMigrated = true` pour que
`importLiveNotesIfNeeded` n'ajoute pas une cinquième ligne à `t = 0` : la recette doit
montrer exactement la capture. `liveNotes` **reste** rempli (l'éditeur markdown des notes et
les gabarits de rapport le lisent).

- [ ] **Étape 1 : tests qui échouent** — quatre `MeetingNote`, celle de `663` est une
      décision, `notesMigrated` vrai, `importLiveNotesIfNeeded` rend `nil` après semis,
      semer deux fois ne duplique pas les notes.
- [ ] **Étape 2 : vérifier l'échec** · **Étape 3 : implémenter** · **Étape 4 : vert**
- [ ] **Étape 5 : commit** `feat(debug): notes horodatées de la capture dans le jeu de démo`

---

## Task 14 : recette, STATUS, PR

- [ ] `swift build` propre puis **`swift test` complet vert** (noter les chiffres exacts).
- [ ] `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` : si `Yes`, documenter dans
      STATUS la procédure de recette (reprendre celle du lot 1) sans insister ; si `No`,
      `swift build -c release`, empaqueter un `.app` de recette dans le scratchpad (HOME
      temporaire **obligatoire**), menu **Réunion → Charger le jeu de démonstration
      (refonte)**, captures 1 280 et 1 920 px vers
      `docs/superpowers/specs/refonte-2026-09/recette/lot-2-{1280,1920}.png`, comparer à
      `ecrans/1a-cockpit.png`, lister les écarts.
- [ ] `STATUS.md` : section **en tête**, chiffres réels, écarts, prochaine action = lots 4 et 5.
- [ ] `git push -u origin feat/refonte-lot-2-notes-transcription` puis `gh pr create` vers
      `master`, titre `feat(refonte): lot 2 — notes ↔ transcription, frise audio, action
      depuis une phrase`, corps = critères cochés + `swift test` + recette + mention des PR
      empilées #19–#22 + `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
      **Ne pas merger.**

---

## Revue du plan (auto-contrôle)

**Couverture de la spec §2.4 :** carte `1fr 1px 1fr` et en-tête → Task 14 (déjà livré au lot 1,
conservé) ; colonne notes (`timecode | texte`, timecode `accent/action` cliquable, barre
`report`/`warn`) → Task 9 ; composeur `/` toujours visibles → Task 10 ; colonne transcription
`surface/alt`, segments, survol `accent/action bg` + rangée `＋ Action · Décision · Citer dans
la note`, `⌘⇧A` → Task 12 ; création depuis une phrase (titre nettoyé, `sourceRef`, owner) →
Tasks 2 et 7 ; frise 22 px (onde, tête 2 px, ronds/carrés/losanges, clic et glisser) →
Tasks 6, 8, 13 ; défilement lié `Suivre`/`Reprendre le suivi` → Tasks 5 et 12 ; `Speakers` et
`Résumer` → en-tête du lot 1, conservé ; transcription live dans la même colonne → Task 12 ;
`⌘⇧N` → Tasks 3, 10, 14 ; filtre `kind:decision` du KPI Décisions (spec §2.3) → Tasks 3, 9, 14.

**Non couvert volontairement :** l'animation d'insertion de 150 ms en tête du rail et le
composeur d'action prérempli sont **au lot 3** (le lot 2 pose l'intention
`pendingActionDraft` et un test) ; les marqueurs de capture apparaissent dès maintenant mais
les captures elles-mêmes restent au lot 7 ; `/engagement` est au lot 10.

**Cohérence des types :** `ActionFromPhrase.Draft` est produit par Task 2 et consommé par
Tasks 3, 10, 12 ; `NoteCommandParser.Parsed` par Task 1, consommé par Tasks 4 et 10 ;
`MeetingPlayhead.Marker` existe (lot 0B) et n'est pas redéfini ; `screen.follow` existe déjà
et reste la seule variable d'état du suivi, `TranscriptFollow` n'en tient pas une seconde.
