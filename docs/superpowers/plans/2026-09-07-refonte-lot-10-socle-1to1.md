# Refonte — lot 10 : socle 1:1 (fil, engagements, ordre du jour, humeur, confidentialité)

> **Pour les exécutants :** ce plan s'exécute par tâches, en TDD. `swift build` avant chaque
> commit, `swift test --filter <Suite>` en cours de route, `swift test` complet avant chaque PR.

**Objectif :** livrer le **domaine 1:1** — le fil, les engagements réciproques, l'ordre du jour
reportable, l'humeur, les objectifs, les sujets récurrents, les règles « à ne pas oublier », la
confidentialité par ligne et le récap — en **fonctions pures testées**, sans aucun écran nouveau.

**Architecture :** les entités existent déjà (lot 0B, `Models/OneOnOneModels.swift`,
`SchemaV3`). Ce lot ajoute (a) quatre colonnes à valeur par défaut sur
`OneOnOneAgendaItem` (demandes), (b) un magasin `OneOnOneThreadStore` (le seul service à écrire
en base), (c) sept services **purs** sous `Services/OneOnOne/`, (d) une extension du parseur de
commandes, (e) le récap markdown filtré par `ConfidentialityFilter` et ses trois sorties
(Mail, EventKit, dossier annuel).

**Pile technique :** Swift 6 / SwiftUI / SwiftData, Swift Testing (`@Suite` / `@Test` / `#expect`),
EventKit, `ExportService` (AppleScript + EML).

**Spécification :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §1.3, §3.1–3.4,
§6.1–6.3, §8 ; programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §3, §4
(D3, D4, D9), §5 « Lot 10 ». Captures : `ecrans/2a`, `2b`, `5a`, `5b`.

## Contraintes globales

- **Aucune nouvelle version de schéma.** `CurrentSchema = SchemaV3` reste tel quel ; on n'ajoute
  que des colonnes à valeur par défaut sur des tables déclarées en V3 (migration légère).
- **Aucune dépendance SwiftPM nouvelle.**
- Libellés d'interface et commentaires en **français**, symboles en anglais.
- Énums persistées en `…Raw: String` + wrapper calculé.
- Services : `enum` namespace de fonctions statiques pures, ou `class` `@MainActor` `.shared`.
- Toute couleur passe par `One2OneToken` ; un service ne nomme pas de couleur, il rend un **ton**.
- **Fichiers interdits** (lots 4, 5, 6 en parallèle) : `Views/Meeting/Session/**`,
  `Views/Meeting/Spaces/Review/**`, `Views/Meeting/Resources/**`, `Services/Attachment*`,
  `Services/BackupService.swift`, `Views/Meeting/Spaces/Notes/**`, `Rail/**`, `Transcript/**`,
  `MeetingView.swift`, `MeetingSpaceView.swift`, `Services/Debug/RefonteDemoSeed.swift`.
- **Fichiers partagés autorisés, à la ligne près** : `Views/Meeting/MeetingScreenModel.swift`
  (une ligne), `Views/Meeting/MeetingTopChromeBar.swift` (badge/pilule 1:1),
  `Services/Maintenance/StorageStatsService.swift` (une ligne de dossier),
  `Services/ExportService.swift` (une façade publique de composition de mail),
  `Tests/ConfidentialityFilterTests.swift` (extension de la suite du lot 0B).
- **Aucune recette visuelle** : le lot est invisible. À noter dans `STATUS.md`.

## Découpage en deux PR empilées

| PR | Contenu | Base |
| --- | --- | --- |
| **10a** | Tâches 1 → 7 : colonnes de demande, `OneOnOneThreadStore`, `CommitmentLedger`, `AgendaCarryover`, confidentialité par rôle, parseur + catalogue, badge de barre | `feat/refonte-lot-3-rail-actions` |
| **10b** | Tâches 8 → 13 : `MoodTrend`, objectifs, `RecurringTopicsBuilder`, `ReminderRules`, récap + trois sorties, jeu de démonstration | `feat/refonte-lot-10a-socle-1to1` |

---

## Carte des fichiers

### Créés — lot 10a

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/OneOnOne/OneOnOneThreadStore.swift` | Le **seul** service qui écrit le fil : création paresseuse, rôle par type, cadence, réunions du fil, dates. |
| `OneToOne/Services/OneOnOne/CommitmentLedger.swift` | Pur : tenus depuis le dernier 1:1, en retard, taux, tri, transitions `markKept/markMissed/defer`. |
| `OneToOne/Services/OneOnOne/AgendaCarryover.swift` | Pur : report d'un item non traité vers le 1:1 suivant, « resté en suspens », niveau d'une demande. |
| `OneToOne/Services/OneOnOne/OneOnOneConfidentiality.swift` | Pur : défaut par rôle, compte des lignes exclues par audience, audience d'une sortie. |
| `OneToOne/Services/OneOnOne/OneOnOneScreenState.swift` | `@Observable` : sélection du fil, filtre d'engagements, confirmation d'escalade par réunion. |
| `OneToOne/Services/Meeting/NoteCommandParser+OneOnOne.swift` | Les six commandes 1:1 → note / engagement / sujet, sans toucher au parseur de base. |
| `OneToOne/Services/Meeting/NoteCommandCatalog.swift` | Pur : les pilules visibles par type de réunion et par rôle. |

### Créés — lot 10b

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/OneOnOne/MoodTrend.swift` | Pur : série des 6 derniers, delta, tendance, phrase d'explication. |
| `OneToOne/Services/OneOnOne/OneOnOneObjectiveTone.swift` | Pur : ton d'un objectif par seuil de progression. |
| `OneToOne/Services/OneOnOne/RecurringTopicsBuilder.swift` | Pur : familles par lexique FR, comptage sur le fil. |
| `OneToOne/Services/OneOnOne/ReminderRules.swift` | Pur : les trois règles « à ne pas oublier », dans l'ordre, et leur conversion en sujets. |
| `OneToOne/Services/OneOnOne/OneOnOneRecapBuilder.swift` | Pur : markdown du récap, filtré, avec le compte des lignes exclues. |
| `OneToOne/Services/OneOnOne/OneOnOneRecapActions.swift` | Effets : Mail, EventKit, dossier annuel. |
| `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot10.swift` | Les deux fils de démonstration (2a/2b et 5a/5b). |

### Modifiés

| Fichier | Modification |
| --- | --- |
| `OneToOne/Models/OneOnOneModels.swift` | `AgendaItemKind`, `RequestStatus`, quatre colonnes à défaut sur `OneOnOneAgendaItem`. |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | Badge `1:1` + pilule `Je suis le collaborateur`. |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | Une ligne : `var oneOnOne = OneOnOneScreenState()`. |
| `OneToOne/Services/ExportService.swift` | Une façade `composeMail(subject:html:recipients:)`. |
| `OneToOne/Services/Maintenance/StorageStatsService.swift` | Une ligne : dossier `recordings/annual/`. |
| `Tests/ConfidentialityFilterTests.swift` | Extension : récap 1:1 aux trois audiences. |

---

## Task 1 : colonnes de demande sur `OneOnOneAgendaItem`

**Fichiers :** Modifier `OneToOne/Models/OneOnOneModels.swift` · Test
`Tests/OneOnOneRequestColumnsTests.swift`

**Interfaces produites :**
- `enum AgendaItemKind: String { case topic = "topic"; case request = "request" }`, `label`
- `enum RequestStatus: String { case pending = "pending"; case waiting = "waiting";
  case granted = "granted"; case refused = "refused" }`, `label` (`Sans réponse`, `En attente`,
  `Accordé`, `Refusé`)
- `OneOnOneAgendaItem.kindRaw/kind`, `.requestStatusRaw/.requestStatus`, `.requestedAt: Date?`,
  `.remindedCount: Int`

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Ordre du jour — les colonnes de demande (spec §6.2)")
@MainActor
struct OneOnOneRequestColumnsTests {
    @Test("Un sujet est un `topic` sans statut de demande par défaut")
    func defautTopic() throws { /* insertion en mémoire, kind == .topic, requestStatus == .pending, requestedAt == nil */ }

    @Test("Les valeurs brutes sont celles de la spécification")
    func valeursBrutes() { /* "topic"/"request"; "pending"/"waiting"/"granted"/"refused" */ }

    @Test("Une demande écrite puis relue conserve son statut et ses relances")
    func allerRetour() throws { /* requestStatus = .waiting, remindedCount = 2, save, relecture */ }
}
```

- [ ] **Étape 2 :** `swift test --filter OneOnOneRequestColumnsTests` → échec de compilation.
- [ ] **Étape 3 :** ajouter les deux énums et les quatre colonnes (valeurs par défaut
      obligatoires : `kindRaw = "topic"`, `requestStatusRaw = "pending"`, `requestedAt = nil`,
      `remindedCount = 0`), plus un initialiseur `kind:`/`requestStatus:` avec valeurs par défaut
      pour ne pas casser les appelants existants.
- [ ] **Étape 4 :** `swift test --filter OneOnOneRequestColumnsTests` → vert. `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): colonnes de demande sur l'ordre du jour`.

---

## Task 2 : `OneOnOneThreadStore`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/OneOnOneThreadStore.swift` · Test
`Tests/OneOnOneThreadStoreTests.swift`

**Interfaces produites :**

```swift
@MainActor
enum OneOnOneThreadStore {
    static let faceToFace: Set<MeetingKind> = [.oneToOne, .manager]
    static func role(for kind: MeetingKind) -> OneOnOneSide?          // .oneToOne → .manager, .manager → .collaborator
    static func cadenceDays(for collaborator: Collaborator) -> Int    // 0 si aucune cadence
    @discardableResult
    static func thread(for collaborator: Collaborator, kind: MeetingKind, in context: ModelContext) -> OneOnOneThread?
    static func thread(for meeting: Meeting, in context: ModelContext) -> OneOnOneThread?
    static func meetings(of thread: OneOnOneThread, now: Date) -> [Meeting]      // triées, croissantes
    static func previousMeeting(before meeting: Meeting, in thread: OneOnOneThread) -> Meeting?
    static func lastMeetingDate(of thread: OneOnOneThread, now: Date) -> Date?
    static func nextPlannedDate(of thread: OneOnOneThread, now: Date) -> Date?   // dernier + cadence
    static func sessionNumber(of meeting: Meeting, in thread: OneOnOneThread) -> Int  // « 14ᵉ 1:1 »
}
```

Règles :
- `role(for:)` rend `nil` pour tout type non face à face — un fil ne se crée que pour un 1:1 (D4).
- `thread(for:kind:in:)` est **idempotent** : deux appels rendent le même objet. Un fil existant
  ne change pas de rôle, mais sa `cadenceDays` est **remise en phase** avec l'annuaire à chaque
  appel (l'annuaire est la source de vérité).
- `meetings(of:)` filtre `collaborator.meetings` par `faceToFace` **et** par le type qui
  correspond au rôle du fil (un fil manager ne compte pas mes 1:1 subis), `date <= now`, tri
  croissant.
- `nextPlannedDate` rend `nil` sans cadence ou sans dernier 1:1 : rien n'est jamais en retard sans
  rythme convenu (même règle que `OneToOneRhythm`).

- [ ] **Étape 1 : le test qui échoue** — `Tests/OneOnOneThreadStoreTests.swift`

```swift
@Suite("Fil 1:1 — création paresseuse et dates (D4)")
@MainActor
struct OneOnOneThreadStoreTests {
    @Test("Le rôle se déduit du type de réunion")
    func roleParType() {
        #expect(OneOnOneThreadStore.role(for: .oneToOne) == .manager)
        #expect(OneOnOneThreadStore.role(for: .manager) == .collaborator)
        for kind in [MeetingKind.global, .project, .work, .note, .workshop] {
            #expect(OneOnOneThreadStore.role(for: kind) == nil)
        }
    }

    @Test("Créer le fil deux fois rend le même fil")
    func creationIdempotente() throws { /* même persistentModelID, un seul fil en base */ }

    @Test("Aucun fil pour une réunion qui n'est pas un 1:1")
    func pasDeFilHorsFaceAFace() throws { /* kind .project → nil */ }

    @Test("La cadence du fil suit l'annuaire")
    func cadenceMiroir() throws { /* .bimensuelle → 14 ; passage à .mensuelle → 30 au rappel */ }

    @Test("La prochaine date est le dernier 1:1 plus la cadence")
    func prochaineDate() throws { /* 21 août + 14 j = 4 sept. */ }

    @Test("Sans cadence convenue, il n'y a pas de prochaine date")
    func sansCadencePasDeDate() throws { /* .aucune → nil */ }

    @Test("Le fil ne compte que les réunions de son propre côté")
    func reunionsDuBonCote() throws { /* un .manager n'entre pas dans un fil de rôle manager */ }

    @Test("La séance précédente est la dernière antérieure du fil")
    func seancePrecedente() throws { /* trois réunions, la 2e rend la 1re */ }
}
```

- [ ] **Étape 2 :** `swift test --filter OneOnOneThreadStoreTests` → échec.
- [ ] **Étape 3 :** écrire le service.
- [ ] **Étape 4 :** vert. `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): magasin du fil avec création paresseuse`.

---

## Task 3 : `CommitmentLedger`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/CommitmentLedger.swift` · Test
`Tests/CommitmentLedgerTests.swift`

**Interfaces produites :**

```swift
enum CommitmentLedger {
    static func all(_ thread: OneOnOneThread, side: OneOnOneSide?) -> [Commitment]   // nil = les deux
    static func settledSince(_ date: Date?, in thread: OneOnOneThread) -> [Commitment]  // kept|missed depuis
    static func overdue(_ thread: OneOnOneThread, now: Date) -> [Commitment]         // open && dueAt < now
    static func byLatenessDescending(_ commitments: [Commitment], now: Date) -> [Commitment]
    static func keptRate(_ thread: OneOnOneThread) -> Double?                        // kept / (kept+missed), nil si 0
    static func counts(_ thread: OneOnOneThread) -> (kept: Int, missed: Int, open: Int)
    static func rateLabel(_ thread: OneOnOneThread) -> String?                       // « 8 tenus sur 11 · taux 73 % »
    static func markKept(_ c: Commitment, on: Date)                                  // état + rien d'autre
    static func markMissed(_ c: Commitment)
    static func defer_(_ c: Commitment, to newDue: Date?)                            // deferralCount += 1, reste open
    static func deferralLabel(_ c: Commitment) -> String?                            // « 2× reporté », nil si 0
}
```

Règles :
- `settledSince(nil, …)` = tous les soldés (aucun 1:1 précédent).
- `byLatenessDescending` : le plus en retard d'abord ; un engagement sans échéance passe après
  tous les datés ; tri **stable** par `promisedAt` à retard égal.
- `keptRate` rend `nil` quand `kept + missed == 0` : un taux de 0 % sur zéro engagement est un
  mensonge.
- `defer_` **n'endort pas** l'engagement : il reste `open`, seul le compteur monte. Le nom porte le
  souligné final parce que `defer` est un mot réservé.
- Les anciens engagements dérivés (`EngagementLedger.pending`) ne sont **ni lus ni convertis** ici.

- [ ] **Étape 1 : le test qui échoue** — points obligatoires :

```swift
@Suite("Engagements — le registre du fil (spec §3.3, §3.4)")
@MainActor
struct CommitmentLedgerTests {
    @Test("Un engagement manqué côté manager sort avec son compteur de reports")   // critère chantier 2 n° 2
    @Test("Le taux de tenue est kept / (kept + missed)")                            // 8/11 → « taux 73 % »
    @Test("Sans engagement soldé, il n'y a pas de taux")
    @Test("Les engagements en retard sont ceux qui sont ouverts et dont l'échéance est passée")
    @Test("Le tri met le plus en retard d'abord, les sans-échéance à la fin")
    @Test("Tenus depuis le dernier 1:1 : rien avant cette date")
    @Test("Reporter ne solde pas : l'engagement reste ouvert, le compteur monte")
    @Test("Le filtre par côté rend Moi, l'autre, ou les deux")
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** implémenter. **Étape 4 :** vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): registre pur des engagements réciproques`.

---

## Task 4 : `AgendaCarryover`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/AgendaCarryover.swift` · Test
`Tests/AgendaCarryoverTests.swift`

**Interfaces produites :**

```swift
enum AgendaCarryover {
    static let unansweredRequestDays = 60
    static func sorted(_ items: [OneOnOneAgendaItem]) -> [OneOnOneAgendaItem]        // order, puis createdAt
    static func pending(_ items: [OneOnOneAgendaItem]) -> [OneOnOneAgendaItem]       // state == .todo
    @discardableResult
    static func carryOver(from closing: Meeting, to next: Meeting?, in thread: OneOnOneThread,
                          in context: ModelContext) -> [OneOnOneAgendaItem]
    static func deferredLabel(_ item: OneOnOneAgendaItem) -> String?                 // « → 18/09 »
    static func stillOpen(_ thread: OneOnOneThread,
                          recurringTopics: [RecurringTopic]) -> [StillOpenEntry]     // « Resté en suspens »
    static func requestLevel(_ item: OneOnOneAgendaItem, now: Date) -> RequestLevel  // .ok/.warn/.report
    static func requestHistoryLabel(_ item: OneOnOneAgendaItem) -> String            // « Demandé le 10 juil. · relancé 2 fois »
    @discardableResult
    static func remind(_ item: OneOnOneAgendaItem) -> Int                            // remindedCount += 1
}

enum RequestLevel: Equatable, Sendable { case ok, warn, report }

struct StillOpenEntry: Equatable, Sendable {
    var text: String
    var occurrences: Int          // 1 pour un item reporté, le comptage pour un sujet récurrent
    var isRecurringTopic: Bool
}
```

Règles de `carryOver` :
1. Chaque item `todo` du fil rattaché à `closing` (ou sans réunion) passe `state = .deferred` et
   reçoit `deferredToMeeting = next`.
2. Une **copie** `todo` est insérée, rattachée à `next`, même texte, même `addedBySide`, même
   visibilité, même `kind`/statut de demande, `order` conservé, `deferredToMeeting = nil`.
3. **Idempotent** : rejouer l'appel ne recrée rien. Garde : un item déjà `deferred` n'est pas
   retraité, et une copie identique (même texte, même réunion cible, `state == .todo`) n'est pas
   dupliquée.
4. `next == nil` (aucune séance suivante planifiée) : l'item passe quand même `deferred` sans
   cible ; la copie est créée au prochain appel avec une cible.

`requestLevel` : `.granted` → `.ok` ; `.refused` → `.report` ; `.pending`/`.waiting` → `.report`
si `requestedAt` a plus de 60 jours, sinon `.warn`.

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Ordre du jour — report vers le 1:1 suivant (critère chantier 2 n° 4)")
@MainActor
struct AgendaCarryoverTests {
    @Test("Un item non traité migre vers le 1:1 suivant")                // ancien deferred + copie todo
    @Test("Rejouer le report ne duplique rien")                          // idempotence
    @Test("Un item traité ne migre pas")
    @Test("L'item reporté affiche la date de sa cible")                  // « → 18/09 »
    @Test("Resté en suspens mêle les items reportés et les sujets récurrents non tranchés")
    @Test("Une demande sans réponse depuis plus de 60 jours passe en report")  // 65 j → .report, 56 j → .warn
    @Test("Une demande refusée est en report, une demande accordée est neutre")
    @Test("Relancer une demande incrémente son compteur")
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** implémenter (`RecurringTopic` étant défini en tâche 10,
      déclarer ici le **type** `RecurringTopic` dans `RecurringTopicsBuilder.swift` créerait un
      cycle de tâches : le déclarer dans `AgendaCarryover.swift` et le **consommer** en tâche 10).
- [ ] **Étape 4 :** vert + `swift build`. **Étape 5 :** commit
      `feat(1to1): report automatique des sujets non traités`.

---

## Task 5 : confidentialité par rôle et état d'écran

**Fichiers :** Créer `OneToOne/Services/OneOnOne/OneOnOneConfidentiality.swift` et
`OneToOne/Services/OneOnOne/OneOnOneScreenState.swift` · Modifier
`OneToOne/Views/Meeting/MeetingScreenModel.swift` (une ligne) · Test
`Tests/OneOnOneConfidentialityTests.swift`

**Interfaces produites :**

```swift
enum OneOnOneConfidentiality {
    static func defaultVisibility(for role: OneOnOneSide) -> Visibility     // manager → .shared, collaborator → .private
    static func defaultVisibility(for thread: OneOnOneThread?) -> Visibility  // nil → .shared
    static func toggledPrivacy(_ current: Visibility, role: OneOnOneSide) -> Visibility
    static func excludedLinesCount(_ items: [any Confidential], for audience: Audience) -> Int
    static func excludedLinesLabel(_ count: Int) -> String?                 // « 3 lignes privées seront exclues. »
    static func recapAudience(for role: OneOnOneSide) -> Audience           // manager → .collaborator, collaborator → .manager
    static let escalationAudience: Audience = .hr                           // export « Escalade » (D9)
}

@Observable
@MainActor
final class OneOnOneScreenState {
    var commitmentSideFilter: OneOnOneSide?          // nil = « Les deux »
    var selectedThreadID: UUID?
    private(set) var escalationConfirmedMeetingIDs: Set<UUID>
    func isEscalationConfirmed(for meeting: Meeting) -> Bool
    func confirmEscalation(for meeting: Meeting)     // clé d'état `screen.oneOnOne.escalationConfirmed`
    func needsEscalationConfirmation(for meeting: Meeting) -> Bool
}
```

Règles :
- `toggledPrivacy` : `/privé` bascule **entre** `private` et le défaut du rôle. Depuis
  `escalated`, la bascule ramène à `private` (on ne dé-escalade jamais vers `shared` par accident).
- `excludedLinesCount` compte les lignes **non exportables** vers `audience`.
- La confirmation d'escalade est **par réunion** (D9) et vit dans l'état d'écran, pas en base :
  c'est une confirmation d'interface, pas une donnée d'entretien. Persistée par réunion dans
  `UserDefaults` sous `screen.oneOnOne.escalationConfirmed`.

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Confidentialité 1:1 — défaut par rôle et compte des exclusions (spec §3.2, §6.1)")
@MainActor
struct OneOnOneConfidentialityTests {
    @Test("Le manager partage par défaut, le collaborateur garde pour lui")
    @Test("La bascule /privé va et revient au défaut du rôle")
    @Test("Depuis escaladé, la bascule ramène au privé")
    @Test("Le compte des lignes exclues suit l'audience")     // 5a : « 3 lignes privées seront exclues. »
    @Test("Le récap va au collaborateur côté manager, au manager côté collaborateur")  // D9
    @Test("La confirmation d'escalade est demandée une fois par réunion")
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** implémenter les deux fichiers, puis ajouter **en fin de**
      `MeetingScreenModel` la ligne `var oneOnOne = OneOnOneScreenState()` avec un commentaire
      d'une ligne renvoyant au lot 10.
- [ ] **Étape 4 :** vert + `swift build`. **Étape 5 :** commit
      `feat(1to1): confidentialité par rôle et état d'écran du fil`.

---

## Task 6 : parseur 1:1 et catalogue de commandes

**Fichiers :** Créer `OneToOne/Services/Meeting/NoteCommandParser+OneOnOne.swift` et
`OneToOne/Services/Meeting/NoteCommandCatalog.swift` · Test
`Tests/NoteCommandOneOnOneTests.swift`

**Interfaces produites :**

```swift
extension NoteCommandParser {
    /// Les commandes 1:1 qui n'écrivent pas de note (le parseur de base ne peut
    /// pas gagner de cas : c'est un `enum` figé d'un fichier qu'on ne touche pas).
    enum OneOnOneCommand: String, CaseIterable, Sendable {
        case engagement
        var pill: String { "/engagement" }
        var aliases: [String] { ["engagement"] }
    }

    /// Dans quelle section du centre la ligne est saisie (spec §3.3 ③, §6.2).
    enum FeedbackSection: Sendable { case given, received }

    struct NoteDraft: Equatable, Sendable {
        var kind: MeetingNoteKind
        var text: String
        var visibility: Visibility?
        var authorSide: MeetingSide
    }
    struct CommitmentDraft: Equatable, Sendable {
        var text: String
        var ownerSide: OneOnOneSide
        var visibility: Visibility?
    }
    struct AgendaDraft: Equatable, Sendable {
        var text: String
        var addedBySide: OneOnOneSide
        var kind: AgendaItemKind
        var visibility: Visibility?
    }
    struct OneOnOneParsed: Equatable, Sendable {
        var basePill: Command?
        var oneOnOnePill: OneOnOneCommand?
        var note: NoteDraft?
        var commitment: CommitmentDraft?
        var agenda: AgendaDraft?
        var togglesPrivacy = false
        var opensActionComposer = false
    }

    static func parseOneOnOne(_ raw: String,
                              role: OneOnOneSide,
                              section: FeedbackSection = .given) -> OneOnOneParsed
}

enum NoteCommandCatalog {
    enum Entry: Equatable, Sendable, Identifiable {
        case base(NoteCommandParser.Command)
        case oneOnOne(NoteCommandParser.OneOnOneCommand)
        var pill: String
        var id: String { pill }
    }
    static func commands(for kind: MeetingKind, role: OneOnOneSide?) -> [Entry]
}
```

Table de correspondance (accents et casse ignorés, comme le parseur de base) :

| Commande | Sortie |
| --- | --- |
| `/engagement` | `CommitmentDraft(ownerSide: role)` — « Moi » par défaut, le porteur reste modifiable |
| `/promesse` | `CommitmentDraft(ownerSide: .manager)` **toujours** (spec §6.2) + note `kind: .promise` |
| `/feedback` | note `kind: .feedback`, `authorSide` = `.me` en `.given`, l'autre côté en `.received` |
| `/privé` | note `kind: .note`, `visibility: .private`, `togglesPrivacy = true` |
| `/demande` | note `kind: .request` **et** `AgendaDraft(kind: .request)` |
| `/preuve` | note `kind: .proof` |

- `commands(for: .oneToOne, role: .manager)` → `[/engagement, /feedback, /privé]` (capture 2a).
- `commands(for: .manager, role: .collaborator)` → `[/promesse, /demande, /preuve]` (capture 5a).
- Tout autre type → `NoteCommandParser.visiblePills` inchangées (`/action /décision /risque /citer`).
- Une commande inconnue reste du **texte** : rien n'est mangé (même règle que le parseur de base).
- Une commande **sans texte** ne produit ni note ni engagement (`nil` partout), mais garde sa
  pilule : le composeur affiche la commande, il n'insère rien.

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Commandes 1:1 — les six commandes du composeur (spec §1.4, §3.3, §6.2)")
struct NoteCommandOneOnOneTests {
    @Test("/engagement crée un engagement porté par mon côté")
    @Test("/promesse crée un engagement porté par le manager, quel que soit mon rôle")
    @Test("/feedback prend le côté de sa section")
    @Test("/privé rend la ligne privée")
    @Test("/demande crée une note et un sujet de type demande")
    @Test("/preuve crée une note de preuve")
    @Test("Accents et casse sont ignorés")            // /PRIVE, /Privé, /demande, /DEMANDE
    @Test("Une commande inconnue reste du texte")     // « /engagemnt X » → texte intact
    @Test("Une commande sans texte ne produit rien")
    @Test("Le catalogue dépend du type de réunion et du rôle")
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** implémenter (repli des accents recopié localement,
      `fold` étant privé dans le parseur de base — un `internal` de plus sur un fichier du lot 2
      créerait un conflit de fusion).
- [ ] **Étape 4 :** vert + `swift build`. **Étape 5 :** commit
      `feat(1to1): six commandes de composeur et catalogue par type`.

---

## Task 7 : badge `1:1` et pilule de rôle dans la barre du haut

**Fichiers :** Modifier `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` · Test
`Tests/MeetingTopChromeOneOnOneTests.swift`

La teinte `#f4f1f6` existe déjà (`tint(for:)`, lot 1) : **vérifiée, rien à faire**. Manquent le
badge de type et la pilule de rôle, tous deux dans le fil d'Ariane (captures 2a et 5a).

**Interfaces produites :**

```swift
extension MeetingTopChromeBar {
    /// Libellé du badge de type, `nil` pour les types qui n'en portent pas.
    static func typeBadge(for kind: MeetingKind) -> String?      // .oneToOne/.manager → "1:1", sinon nil
    /// Vrai quand la pilule « Je suis le collaborateur » est obligatoire (D4).
    static func showsCollaboratorPill(for kind: MeetingKind) -> Bool   // .manager seulement
}
```

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Barre du haut — signalétique 1:1 (spec §3.1, §6.1, D4)")
struct MeetingTopChromeOneOnOneTests {
    @Test("Les deux types 1:1 portent le badge 1:1, les autres n'en portent pas")
    @Test("La pilule « Je suis le collaborateur » n'apparaît que pour le 1:1 manager")
    @Test("La barre est teintée #f4f1f6 pour les deux types 1:1")   // garde de la teinte du lot 1
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** ajouter les deux fonctions statiques et les rendre dans
      `breadcrumb`, après le chevron : badge `Text("1:1")` en `oneOnOneInk` sur `oneOnOneBg`,
      bordure `oneOnOne.opacity(0.35)`, rayon `radiusButton` ; puis, pour `.manager`, une
      `Pill("Je suis le collaborateur")` bordée `oneOnOne`.
- [ ] **Étape 4 :** vert + `swift build`. **Étape 5 :** commit
      `feat(1to1): badge de type et pilule de rôle dans la barre du haut`.

- [ ] **Étape 6 : `swift test` complet, puis PR 10a.**

```bash
swift test 2>&1 | tail -20
git push -u origin feat/refonte-lot-10a-socle-1to1
gh pr create --base feat/refonte-lot-3-rail-actions \
  --title "feat(refonte): lot 10a — socle 1:1 : fil, engagements, ordre du jour, confidentialité"
```

---

## Task 8 : `MoodTrend`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/MoodTrend.swift` · Test
`Tests/MoodTrendTests.swift`

**Interfaces produites :**

```swift
enum MoodLevel: Int, CaseIterable, Sendable {
    case difficile = 1, sousTension = 2, caVa = 3, bien = 4, tresBien = 5
    var label: String   // Difficile · Sous tension · Ça va · Bien · Très bien
}

enum MoodTrend {
    static let historyLength = 6
    enum Direction: Equatable, Sendable { case enBaisse, stable, enHausse
        var label: String?   // « en baisse » / nil / « en hausse »
    }
    struct Point: Equatable, Sendable { var value: Int; var recordedAt: Date }

    static func series(_ thread: OneOnOneThread, limit: Int = historyLength) -> [Point]
    static func direction(_ values: [Int]) -> Direction
    static func delta(_ thread: OneOnOneThread) -> (current: MoodLevel, previous: MoodLevel, previousAt: Date)?
    static func deltaLabel(_ thread: OneOnOneThread) -> String?     // « ↓ vs 21 août (Bien) »
    static func explanation(_ topics: [RecurringTopic]) -> String?  // sujet le plus cité
    @discardableResult
    static func record(_ value: Int, for meeting: Meeting, in thread: OneOnOneThread,
                       in context: ModelContext) -> MoodEntry       // une entrée par réunion, remplacement
}
```

Règles :
- `direction` : `.enBaisse` si `moyenne(2 derniers) < moyenne(3 précédents) − 0,5` ; `.enHausse`
  si `>` + 0,5 ; `.stable` sinon. Moins de 5 points → `.stable` : la règle est définie sur 5.
- `series` rend les **6 derniers** par `recordedAt` croissant (l'histogramme se lit de gauche à
  droite, capture 2b).
- `record` **remplace** l'entrée de la réunion s'il en existe une : une humeur est un cran, pas un
  journal — une deuxième saisie corrige, elle n'empile pas.

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Humeur — série, delta et tendance (spec §3.4, critère chantier 2 n° 3)")
@MainActor
struct MoodTrendTests {
    @Test("La série du jeu de la capture 2b est en baisse")     // [3,4,5,4,4,2] → .enBaisse
    @Test("Une remontée symétrique est en hausse")              // [2,2,3,4,5]
    @Test("Une série plate est stable")
    @Test("Moins de cinq points : pas de tendance")
    @Test("La série garde les six derniers, dans l'ordre chronologique")
    @Test("Le delta nomme le cran précédent et sa date")        // « ↓ vs 21 août (Bien) »
    @Test("Le moral saisi en séance remplace celui de la même réunion")   // critère n° 3
    @Test("Les cinq crans portent les libellés de la spécification")
}
```

- [ ] **Étapes 2 à 4 :** échec, implémenter, vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): série d'humeur, delta et tendance`.

---

## Task 9 : ton des objectifs

**Fichiers :** Créer `OneToOne/Services/OneOnOne/OneOnOneObjectiveTone.swift` · Test
`Tests/OneOnOneObjectiveToneTests.swift`

**Interfaces produites :**

```swift
enum OneOnOneObjectiveTone: Equatable, Sendable {
    case warn, oneOnOne, ok
    var color: Color        // One2OneToken.warn / .oneOnOne / .ok — le seul endroit qui nomme la couleur
}

extension OneOnOneObjective {
    static func tone(forProgress progress: Int) -> OneOnOneObjectiveTone   // <30 warn, <70 oneOnOne, ≥70 ok
    var tone: OneOnOneObjectiveTone
}

enum OneOnOneObjectiveList {
    static func sorted(_ objectives: [OneOnOneObjective]) -> [OneOnOneObjective]   // order, puis createdAt
    static func reviewLabel(_ objectives: [OneOnOneObjective]) -> String?           // « Revue prévue le 18 sept. »
}
```

- [ ] **Étape 1 : le test qui échoue** — seuils exacts (`0`, `29`, `30`, `69`, `70`, `100`),
      bornage d'une progression hors bornes (`-5` → `warn`, `140` → `ok`), tri, libellé de revue
      (la **plus proche** date de revue, `nil` si aucune).
- [ ] **Étapes 2 à 4 :** échec, implémenter, vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): ton des objectifs par seuil de progression`.

---

## Task 10 : `RecurringTopicsBuilder`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/RecurringTopicsBuilder.swift` · Test
`Tests/RecurringTopicsBuilderTests.swift`

**Interfaces produites :** (`RecurringTopic` est déclaré en tâche 4)

```swift
enum RecurringTopicFamily: String, CaseIterable, Sendable {
    case charge, carriere, reconnaissance, formation, astreinte
    var label: String     // Charge de travail · Mobilité et carrière · Reconnaissance · Formation · Astreintes
    var lexicon: [String] // formes repliées, sans accent
    var tone: OneOnOneObjectiveTone  // charge → warn, carriere → oneOnOne, reconnaissance → ok, …
}

struct RecurringTopic: Equatable, Sendable {
    var label: String
    var count: Int
    var family: RecurringTopicFamily
}

enum RecurringTopicsBuilder {
    static func build(_ thread: OneOnOneThread, now: Date, since: Date?) -> [RecurringTopic]
    static func family(of text: String) -> RecurringTopicFamily?
    static func fold(_ text: String) -> String
}
```

Lexiques (formes repliées, ce sont des **sous-chaînes** cherchées dans le texte replié) :

| Famille | Lexique |
| --- | --- |
| `charge` | `charge`, `surcharge`, `sature`, `rythme`, `surcharge de travail`, `deux migrations`, `capacite` |
| `carriere` | `carriere`, `mobilite`, `evolution`, `promotion`, `archi`, `poste` |
| `reconnaissance` | `reconnaissance`, `felicit`, `merci`, `valorisation`, `visibilite` |
| `formation` | `formation`, `monter en competence`, `certification`, `former`, `tutorat` |
| `astreinte` | `astreinte`, `garde`, `week-end`, `weekend`, `compensation`, `permanence` |

Sources comptées, dans cet ordre de priorité de libellé : les `OneOnOneAgendaItem` du fil, les
`MeetingNote` des réunions du fil, les `MeetingTag` de ces réunions. Un texte qui touche deux
familles compte pour la **première** famille du `allCases` — trancher plutôt que compter deux fois.
Sortie triée par `count` décroissant puis `label` croissant (ordre stable).

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Sujets récurrents — familles par lexique FR (spec §3.4)")
@MainActor
struct RecurringTopicsBuilderTests {
    @Test("Les cinq familles se reconnaissent sans accent ni casse")
    @Test("Le comptage additionne ordre du jour, notes et thèmes")
    @Test("La sortie est triée par comptage décroissant")
    @Test("Le jeu de la capture 2b donne Charge de travail · 5 en tête")
    @Test("Un texte hors lexique n'entre dans aucune famille")
    @Test("Le filtre de période exclut ce qui précède `since`")
}
```

- [ ] **Étapes 2 à 4 :** échec, implémenter, vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): familles de sujets récurrents par lexique`.

---

## Task 11 : `ReminderRules`

**Fichiers :** Créer `OneToOne/Services/OneOnOne/ReminderRules.swift` · Test
`Tests/ReminderRulesTests.swift`

**Interfaces produites :**

```swift
enum ReminderRules {
    enum Rule: Int, Sendable { case managerCommitmentLate = 1, undecidedRecurringTopic = 2, unrecognisedWin = 3 }
    struct Reminder: Equatable, Sendable, Identifiable {
        var id: String
        var rule: Rule
        var text: String                 // le libellé de la capture 2b
        var tone: OneOnOneObjectiveTone  // report ← rule 1, warn ← 2, ok ← 3
    }

    static let recurringTopicThreshold = 3

    static func reminders(for thread: OneOnOneThread, now: Date) -> [Reminder]
    static func toAgendaItems(_ reminders: [Reminder], for thread: OneOnOneThread,
                              role: OneOnOneSide, in context: ModelContext) -> [OneOnOneAgendaItem]
}
```

Les trois règles, **dans cet ordre** (spec §3.4) :
1. **Engagement du manager en retard** : `Commitment` de `ownerSide == .manager`, `state == .open`
   avec `dueAt < now`, **ou** `state == .missed`. Libellé : `« Vous lui devez <texte> — reporté n
   fois. »` (sans le suffixe quand `deferralCount == 0`). Tri par retard décroissant.
2. **Sujet évoqué ≥ 3 fois sans décision** : un `RecurringTopic` de comptage ≥ 3 dont aucune
   `MeetingNote(kind: .decision)` du fil ne mentionne un mot de sa famille. Libellé :
   `« <label> évoqué n fois, jamais tranché. »`
3. **Réussite récente non reconnue** : une `ActionTask` du collaborateur, `isCompleted`, avec
   `completedAt` postérieur au dernier 1:1, dont le titre n'est cité par aucune
   `MeetingNote(kind: .feedback)` du fil. Libellé : `« Féliciter pour <titre>. »`

`toAgendaItems` crée un `OneOnOneAgendaItem` par rappel : `addedBySide = role`, `state = .todo`,
`kind = .topic`, visibilité = défaut du rôle, `order` à la suite des items existants. Idempotent
par le texte : un rappel déjà à l'ordre du jour n'est pas ajouté deux fois.

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("À ne pas oublier — les trois règles dans l'ordre (critère chantier 5 n° 4)")
@MainActor
struct ReminderRulesTests {
    @Test("Une promesse du manager non tenue est en position 1")     // critère chantier 5 n° 4
    @Test("Un sujet évoqué trois fois sans décision suit en position 2")
    @Test("Un sujet tranché par une décision ne remonte pas")
    @Test("Une réussite récente non citée en feedback vient en position 3")
    @Test("Une réussite déjà citée en feedback ne remonte pas")
    @Test("Mettre à l'ordre du jour crée un sujet par rappel, sans doublon")
    @Test("Le jeu de la capture 2b rend les trois rappels dans l'ordre de la maquette")
}
```

- [ ] **Étapes 2 à 4 :** échec, implémenter, vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): règles « à ne pas oublier » et mise à l'ordre du jour`.

---

## Task 12 : récap, envoi, planification, dossier annuel

**Fichiers :** Créer `OneToOne/Services/OneOnOne/OneOnOneRecapBuilder.swift` et
`OneToOne/Services/OneOnOne/OneOnOneRecapActions.swift` · Modifier
`OneToOne/Services/ExportService.swift` (une façade), `OneToOne/Services/Maintenance/StorageStatsService.swift`
(une ligne), `Tests/ConfidentialityFilterTests.swift` (extension) · Test
`Tests/OneOnOneRecapBuilderTests.swift`

**Interfaces produites :**

```swift
enum OneOnOneRecapBuilder {
    static func markdown(for meeting: Meeting, thread: OneOnOneThread,
                         audience: Audience, now: Date) -> String
    static func excludedLinesCount(for meeting: Meeting, thread: OneOnOneThread,
                                   audience: Audience) -> Int
    static func subject(for meeting: Meeting, thread: OneOnOneThread) -> String   // « Récap 1:1 — <Prénom> — 4 sept. 2026 »
    static func nextMeetingTitle(for thread: OneOnOneThread) -> String            // « 1:1 — <Prénom> »
    static func annualFolderURL(year: Int, collaborator: String) -> URL           // recordings/annual/<année>/<collab>/
    static func annualFileName(for date: Date) -> String                          // « 2026-09-04.md »
}

@MainActor
enum OneOnOneRecapActions {
    static func sendRecap(for meeting: Meeting, thread: OneOnOneThread, audience: Audience) -> Bool
    static func planNext(for thread: OneOnOneThread, now: Date, store: EKEventStore) async -> Bool
    @discardableResult
    static func archiveToAnnualFolder(for meeting: Meeting, thread: OneOnOneThread) throws -> URL
}

extension ExportService {
    /// Ouvre une composition Mail avec un corps HTML déjà construit.
    func composeMail(subject: String, html: String, recipients: [String]) -> Bool
}
```

Sections du markdown, dans cet ordre :

```markdown
# Récap 1:1 — Laurent NOMINÉ — 4 sept. 2026

## Sujets abordés
- [06:15] Charge AP — …

## Engagements
### Moi
- ☐ Arbitrer renfort ou décalage du Webcast — vendredi
### Laurent
- ☑ Reprise du périmètre Nexus

## Comment ça va
Sous tension (↓ vs 21 août (Bien))

## Feedback
- Ce que je lui dis : …
- Ce qu'il me dit : …

---
2 lignes privées ont été exclues de ce récap.
```

Règles **non négociables** :
- Chaque ligne passe par `ConfidentialityFilter.isExportable(_:for:)` — notes, engagements **et**
  sujets. Une note `private` ne sort pour aucune audience autre que `.me`.
- L'humeur n'est rendue **que** si `audience == .me` ou si l'entrée de la réunion est accompagnée
  d'au moins une ligne `shared` : le cran de moral appartient à la personne, pas au récap. Décision
  d'implémentation : le bloc « Comment ça va » est rendu pour `.me` et `.collaborator`, jamais pour
  `.hr` ni `.projectTeam`.
- Le pied porte **toujours** le compte des lignes exclues quand il est non nul (spec §3.2 : « le
  bouton de clôture affiche systématiquement le compte des lignes exclues »).
- `planNext` : date = dernier 1:1 + cadence (`OneOnOneThreadStore.nextPlannedDate`), titre
  `1:1 — <Prénom>`, durée 30 min ; rend `false` sans cadence, sans autorisation calendrier ou
  sans calendrier par défaut — **jamais** de dialogue bloquant.
- `archiveToAnnualFolder` écrit le markdown d'audience `.me` (mon dossier, donc tout) dans
  `Application Support/OneToOne/recordings/annual/<année>/<collaborateur>/<yyyy-MM-dd>.md`.
  Nom de dossier assaini (`/` et `:` remplacés). Écriture atomique, écrasement autorisé : deux
  clôtures du même entretien produisent un fichier, pas deux.

- [ ] **Étape 1 : le test qui échoue** — `Tests/OneOnOneRecapBuilderTests.swift`

```swift
@Suite("Récap 1:1 — markdown filtré et sorties (spec §3.3, §6.2, D9)")
@MainActor
struct OneOnOneRecapBuilderTests {
    @Test("Le récap collaborateur ne contient aucune note privée")
    @Test("Le récap collaborateur exclut aussi les lignes escaladées")     // D9
    @Test("L'export RH contient les lignes escaladées et pas les partagées seules")
    @Test("Le récap au manager (côté collaborateur) part avec l'audience .manager")
    @Test("Le pied annonce le nombre de lignes exclues")
    @Test("Les engagements sont groupés par côté, cochés selon leur état")
    @Test("L'humeur n'apparaît pas dans un export RH")
    @Test("Le titre du prochain entretien est « 1:1 — <Prénom> »")
    @Test("Le chemin du dossier annuel porte l'année et le nom du collaborateur")
    @Test("Le nom de fichier est la date ISO du jour de l'entretien")
}
```

- [ ] **Étape 2 :** échec. **Étape 3 :** implémenter le constructeur, puis les actions, puis les
      trois modifications d'une ligne (façade `ExportService`, dossier annuel dans
      `StorageStatsService.Stats` : `annualBytes`/`annualCount` + scan du sous-dossier `annual`).
- [ ] **Étape 4 :** vert + `swift build`.
- [ ] **Étape 5 : étendre `Tests/ConfidentialityFilterTests.swift`** — ajouter au
      `@Suite NotePriveeHorsDesCinqFluxTests` un sixième flux :

```swift
@Test("6. Le récap 1:1, pour les trois audiences")
func fluxRecap1a1() throws {
    // .me contient la ligne privée ; .collaborator, .manager et .hr ne la contiennent jamais.
}
```

- [ ] **Étape 6 :** commit `feat(1to1): récap markdown filtré, envoi, planification, dossier annuel`.

---

## Task 13 : jeu de démonstration des deux fils

**Fichiers :** Créer `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot10.swift` · Test
`Tests/RefonteDemoSeedLot10Tests.swift`

`RefonteDemoSeed.swift` **n'est pas modifié** : le lot 10 ajoute une extension avec son propre
point d'entrée.

**Interfaces produites :**

```swift
@MainActor
extension RefonteDemoSeed {
    static let managerThreadCollaborator = "Laurent NOMINÉ"
    static let collaboratorThreadManager = "Yann PENVEN"
    @discardableResult
    static func seedOneOnOneThreads(in context: ModelContext) -> (manager: OneOnOneThread, collaborator: OneOnOneThread)
}
```

Fil **manager** (captures 2a / 2b), collaborateur `Laurent NOMINÉ`, `Ingénieur CI/CD`, cadence
`.bimensuelle` :
- 14 réunions `.oneToOne`, la dernière le 4 septembre 2026 (« 14ᵉ 1:1 »).
- 6 humeurs sur les 6 dernières séances : `12/06 → 3`, `26/06 → 4`, `10/07 → 5`, `24/07 → 4`,
  `21/08 → 4`, `04/09 → 2`. Tendance attendue : **en baisse** (moyenne 3,0 contre 4,33 − 0,5).
- 3 objectifs S2 : `Industrialiser la CI/CD` 70 %, `Monter en compétence archi` 25 %,
  `Transmettre (formation Admin)` 10 %, revue le 18 septembre 2026.
- 11 engagements : 8 `kept`, 3 non tenus dont `Retour sur la grille d'astreinte`
  (`ownerSide = .manager`, `state = .open`, `dueAt` = 24 juillet, `deferralCount = 2`) →
  `taux 73 %`.
- 4 sujets d'ordre du jour : `Charge de travail sur la migration AP — je sature` (collaborateur),
  `Retour sur la présentation COSUI du 1er sept.` (manager), `Formation Admin : est-ce que je peux
  la porter ?` (collaborateur), `Point objectifs S2` (manager, `deferred` vers le 18 septembre).
- Sujets récurrents attendus : `Charge de travail · 5`, `Mobilité archi · 3`, `Astreintes · 3`,
  `Formation · 2`, `Reconnaissance · 2`.

Fil **collaborateur** (captures 5a / 5b), manager `Yann PENVEN`, cadence `.bimensuelle` :
- 3 demandes : `Mobilité vers l'architecture` (`pending`, demandée le 10 juillet, `remindedCount = 2`
  — 56 jours, donc `warn` et non `report`), `Compensation des astreintes` (`waiting`, 24 juillet),
  `Budget formation Terraform` (`granted`, 21 août).
- 3 promesses du manager : `Grille de compensation des astreintes` (24 juillet, 2 reports, en
  retard), `Arbitrage renfort / décalage Webcast` (échéance vendredi, prise ce jour),
  `Point mobilité avec Claire-Amélie` (janvier, 3 reports).

- [ ] **Étape 1 : le test qui échoue**

```swift
@Suite("Jeu de démonstration — les deux fils 1:1 des captures")
@MainActor
struct RefonteDemoSeedLot10Tests {
    @Test("Semer deux fois ne duplique aucun fil")
    @Test("Le fil manager tient l'arithmétique de la capture 2b")   // 14ᵉ, 8/11, taux 73 %, en baisse
    @Test("Les sujets récurrents du fil manager sont ceux des chips de 2b")
    @Test("Les trois rappels « à ne pas oublier » sortent dans l'ordre de 2b")
    @Test("Le fil collaborateur tient les trois demandes et les trois promesses de 5a")
    @Test("La demande du 10 juillet reste en warn : 56 jours, pas 60")
}
```

- [ ] **Étapes 2 à 4 :** échec, implémenter, vert + `swift build`.
- [ ] **Étape 5 :** commit `feat(1to1): jeu de démonstration des deux fils`.

- [ ] **Étape 6 : `swift test` complet, `STATUS.md`, PR 10b.**

```bash
swift test 2>&1 | tail -20
git push -u origin feat/refonte-lot-10b-humeur-regles-recap
gh pr create --base feat/refonte-lot-10a-socle-1to1 \
  --title "feat(refonte): lot 10b — humeur, objectifs, règles, récap"
```

---

## Revue du plan contre la spécification

| Exigence | Tâche |
| --- | --- |
| §1.3 `OneOnOneThread` (rôle, cadence, réunions) | 2 |
| §1.3 `Commitment` (états, reports, visibilité) | 3 |
| §1.3 `AgendaItem` (ordre, côté, état, visibilité) | 1, 4 |
| §1.3 `moodHistory` | 8 |
| §1.3 `objectives` | 9 |
| §1.3 `recurringTopics` (calculé) | 10 |
| §1.4 `/engagement /feedback /privé /promesse /demande /preuve` | 6 |
| §3.1 badge `1:1`, fond `#f4f1f6` | 7 |
| §3.2 trois niveaux, défaut par rôle, `escalated`, compte des exclusions | 5, 12 |
| §3.3 tenus depuis le dernier 1:1, clôture, prochain | 3, 12 |
| §3.4 histogramme, tendance, objectifs, à ne pas oublier, taux, chips | 8, 9, 10, 11 |
| §6.1 inversion des défauts, pilule de rôle | 5, 7 |
| §6.2 demandes et statuts, > 60 jours, promesses triées par retard | 1, 3, 4 |
| §6.3 « en faire mon ordre du jour » | 11 (`toAgendaItems`) |
| §8 filtre unique | 12 |
| Critères chantier 2 n° 1, 2, 3, 4 | 12, 3, 8, 4 |
| Critère chantier 5 n° 4 | 11 |

**Laissé aux lots 11 à 14** (hors périmètre, aucun écran ici) : les grilles `300 | 1fr | 320` et
`308 | 1fr | 356`, le glisser-réordonner, l'histogramme rendu, les chips, le tableau des
engagements et son filtre, `DeliveredItemsBuilder` (lot 13), la préparation en 2 minutes (lot 14),
le câblage de `NoteCommandCatalog` dans le composeur (`Views/Meeting/Spaces/Notes/**`, interdit
ici), l'ouverture automatique la veille.
