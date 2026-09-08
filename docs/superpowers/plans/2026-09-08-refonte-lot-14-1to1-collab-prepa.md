# Lot 14 — 1:1 collaborateur, préparation en 2 minutes (5b)

> **Pour les agents :** exécution task par task (`superpowers:executing-plans`).
> Les cases `- [ ]` suivent l'avancement.

**But :** monter le mode **Préparer** du type `1:1 Manager` — la carte étroite de
`5b-1to1-collaborateur-preparation.png` : ce qui est resté sans réponse, ce que j'ai livré
depuis, ce que je veux obtenir, et un bouton qui transforme la liste en ordre du jour privé.

**Architecture :** une branche de routage de plus (`kind == .manager && mode == .prepare`), une
vue `CollaboratorPrepView` qui n'assemble que des **modèles purs** posés dans
`Services/OneOnOne/Prep/Collaborator*.swift`, et **aucune donnée nouvelle** — les trois blocs se
déduisent du fil semé par les lots 10 et 13.

**Pile technique :** SwiftUI + SwiftData, Swift Testing (`Tests/`), exécutable SwiftPM
(`swift build`, `swift test`).

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §6.3 (les trois blocs, les
deux actions, la mention de provenance), §6.1 (défaut privé côté collaborateur), critère
d'acceptation chantier 5 n° 4. Plan directeur : `2026-09-07-refonte-reunion-programme.md` §5
« Lot 14 ». Capture qui fait foi :
`docs/superpowers/specs/refonte-2026-09/ecrans/5b-1to1-collaborateur-preparation.png`.

## Contraintes globales

- Base : `feat/refonte-lot-13-1to1-collab-seance` (lot 13). SHA de départ dans `.lot14-base-sha`.
- Commentaires et libellés d'interface **en français**, symboles en anglais.
- Énums persistées SwiftData en `…Raw: String` + wrapper calculé. **Aucun modèle n'est modifié
  par ce lot.**
- Services : `enum` namespace de fonctions statiques pures ; une seule exception par service, la
  fonction qui écrit (même parti que `ReminderRules.toAgendaItems`).
- Fichiers du lot : `Views/Meeting/OneOnOne/CollaboratorPrep/**`,
  `Services/OneOnOne/Prep/Collaborator*.swift`, mes tests. **Interdits :**
  `Collaborator/**`, `Manager/**`, `ManagerPrep/**`, `Shared/**`, `Services/Report/**`,
  `BuiltInTemplates`, `Workshop/**`, `Capture/**`, `Rail/**`, `Notes/**`, `Review/**`,
  `Resources/**`, `Project/**`, `Session/**`, `MeetingTopChromeBar.swift`, `MeetingView.swift`,
  `MeetingScreenModel.swift`.
- Fichiers partagés, en blocs localisés : `MeetingSpaceRouting.swift` (une branche),
  `MeetingSpaceView.swift` (une branche), `OneOnOneScreenState.swift` (propriétés **en fin de
  type**, préfixées `collabPrep`), `RecetteScreen.swift` (un cas),
  `MeetingNotificationService.swift` (un bloc).
- `swift build` avant chaque commit ; `swift test` complet **vert** avant la PR.
- **Aucune recette graphique, aucun lancement d'application.**

---

## Ce que la capture montre, et d'où chaque ligne sort

Carte étroite (~940 px), centrée, en-tête violet pâle. Le jeu de démonstration des lots 10 et 13
(fil « Yann PENVEN me manage », séance du 4 septembre 2026) produit **exactement** les blocs de la
capture, sans un semis de plus :

| Bloc | Ligne de la capture | Source dans le jeu du lot 10/13 |
| --- | --- | --- |
| `RESTÉ SANS RÉPONSE` | `Mobilité archi — n fois évoquée, jamais tranchée · depuis le 10 juil.` | famille `carriere` de `RecurringTopicsBuilder` (≥ 3) + demande `Mobilité vers l'architecture` (`pending`, 10 juil.) |
| `RESTÉ SANS RÉPONSE` | `… promise, 2 reports · depuis le 24 juil.` | promesse manager `Grille de compensation des astreintes` (`open`, échéance 24 juil., 2 reports) + demande `Compensation des astreintes` (`waiting`, 24 juil.) |
| `CE QUE J'AI LIVRÉ DEPUIS` | 4 lignes (`✓ ×3`, `◐ ×1`) | `DeliveredItemsBuilder` du lot 13, fenêtre `]21 août, maintenant]` |
| `CE QUE JE VEUX OBTENIR` | 2 lignes cochées | sujets privés `todo` du fil, moins ceux qu'une ligne « sans réponse » porte déjà |

**Trois décisions qui découlent de ce tableau :**

1. **Une ligne par famille de sujet.** Les trois sources se recoupent (la demande « Compensation
   des astreintes » et la promesse « Grille de compensation des astreintes » sont le même sujet) ;
   sans regroupement l'écran afficherait quatre lignes là où la capture en montre deux. Le
   regroupement se fait par `RecurringTopicFamily`, comme `AgendaCarryover.stillOpen` le fait
   déjà, et une source sans famille reste une ligne à part.
2. **Le libellé de la ligne vient de la source la plus forte** : promesse non tenue > sujet
   récurrent jamais tranché > demande sans réponse. Une parole donnée et non tenue est le fait le
   plus lourd d'un entretien ; le dire à la place du sujet qui l'a fait naître est ce que fait la
   capture (`… promise, 2 reports` pour les astreintes, `n fois évoquée` pour la mobilité).
3. **`depuis le …` est la plus ancienne date des sources regroupées** : c'est l'ancienneté qui
   plaide, et c'est elle qui trie les lignes (la plus vieille en tête).

**La règle 2 de `ReminderRules` est adaptée, pas appelée.** `ReminderRules.reminders` écarte les
familles déjà portées par un sujet `todo` de l'ordre du jour : sur la carte manager
`À NE PAS OUBLIER` c'est juste (un sujet inscrit ne sera pas oublié), sur 5b c'est l'inverse du
propos — un sujet que je porte depuis trois séances **sans obtenir de décision** est précisément
ce que cet écran doit me remettre sous les yeux. Le lot réutilise donc
`RecurringTopicsBuilder.build`, le seuil `ReminderRules.recurringTopicThreshold` et l'exclusion
des familles tranchées par une décision, sans l'exclusion par l'ordre du jour.

## Écarts avec la capture, assumés

- **Les libellés reprennent le texte des données, pas celui de la maquette.** La capture écrit
  `Grille d'astreinte promise, 2 reports` là où la promesse semée s'appelle « Grille de
  compensation des astreintes » ; le gabarit est celui de la capture
  (`<texte> promise, n reports`), le texte reste celui de la donnée. Inventer un libellé court
  demanderait une table de synonymes que personne ne tiendrait.
- **Le compteur d'occurrences est celui du fil.** La capture dit « 3 fois évoquée » ; le jeu de
  démonstration compte **quatre** mentions de la famille `carriere` (deux sujets, deux notes). Le
  chiffre affiché est celui que les données portent.
- **Le code de recette `5b` ouvre la séance du 4 septembre en mode Préparer**, celle de `5a` :
  c'est la seule séance du fil, et c'est elle qui porte les quatre livrables et les deux lignes
  sans réponse de la capture. L'en-tête y écrit donc sa date réelle et non `demain 14:00` — la
  règle « demain » est tenue et **testée avec une horloge injectée**, pas mise en scène par un
  semis qui décalerait la fenêtre de `CE QUE J'AI LIVRÉ DEPUIS`.
- **Pas de `RefonteDemoSeed+Lot14.swift`.** Le périmètre le prévoit « seulement si une donnée
  manque » : les deux sans-réponse, les quatre livrés et les deux sujets voulus sortent tous du
  jeu des lots 10 et 13. Un semis de plus serait un doublon à tenir en phase.

---

## Structure des fichiers

**Créés — services purs (`Services/OneOnOne/Prep/`) :**

- `CollaboratorPrepModel.swift` — `CollabPrepModel` : les intitulés des trois blocs, la mention de
  provenance, les invites de vide, et `CollabPrepHeaderModel` (titre `1:1 avec <Prénom> — demain
  14:00`, méta `Préparation · 2 min · dernier point le <date>`, badge, initiales).
- `CollaboratorUnansweredItems.swift` — `UnansweredItemsBuilder` : les trois sources, le
  regroupement par famille, le tri par ancienneté, les libellés.
- `CollaboratorWantedItems.swift` — `WantedItemsBuilder` : les sujets privés `todo` du fil, moins
  ceux qu'une ligne sans réponse porte déjà.
- `CollaboratorPrepToAgenda.swift` — `PrepToAgenda` : le plan (pur), sa matérialisation en
  `OneOnOneAgendaItem` privés (idempotente), le passage en `shared`, et le libellé du bouton.
- `CollaboratorPrepStore.swift` — `CollaboratorPrepStore` : la **seule** écriture du composeur
  `Ajouter…` (un sujet privé `kind: .topic`).

**Créés — vues (`Views/Meeting/OneOnOne/CollaboratorPrep/`) :**

- `CollaboratorPrepView.swift` — la carte étroite centrée, l'assemblage, les deux boutons.
- `CollabPrepHeader.swift` — l'en-tête violet pâle (avatar, titre, méta, badge bordé).
- `UnansweredCard.swift` — `RESTÉ SANS RÉPONSE`, cases décochées.
- `DeliveredSinceCard.swift` — `CE QUE J'AI LIVRÉ DEPUIS`, sans bouton `Citer`.
- `WantedCard.swift` — `CE QUE JE VEUX OBTENIR`, cases cochées + composeur `Ajouter…`.

**Modifiés, en blocs localisés :** `Services/Meeting/MeetingSpaceRouting.swift`,
`Views/Meeting/Spaces/MeetingSpaceView.swift`, `Services/OneOnOne/OneOnOneScreenState.swift`,
`Services/Debug/RecetteScreen.swift`, `Services/MeetingNotificationService.swift`.

**Tests créés :** `Tests/CollaboratorPrepBuildersTests.swift` (les trois modèles, l'en-tête, les
invites), `Tests/CollaboratorPrepAgendaTests.swift` (`PrepToAgenda`, le composeur, le routage, la
notification).

**Tests modifiés (deux lignes chacun) :** `Tests/RefonteVague5IntegrationTests.swift` (onzième
code de recette, cinquième branche exclusive), `Tests/ManagerPrepRoutingTests.swift` (`.manager`
sort de la liste des types qui gardent leur mode d'ouverture).

---

## Task 1 — `UnansweredItemsBuilder` : la promesse non tenue remonte seule

**Fichiers :**
- Créer : `OneToOne/Services/OneOnOne/Prep/CollaboratorUnansweredItems.swift`
- Créer : `Tests/CollaboratorPrepBuildersTests.swift`

**Interfaces produites :**

```swift
@MainActor
enum UnansweredItemsBuilder {
    static let title = "RESTÉ SANS RÉPONSE"
    static let emptyInvite: String
    enum Source: String, Sendable, Equatable { case promise, topic, request }
    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        var text: String
        var since: Date?
        var source: Source
        var sinceLabel: String   // "depuis le 24 juil." ou ""
    }
    static func build(_ thread: OneOnOneThread, now: Date) -> [Item]
}
```

- [ ] **Étape 1 — le test qui porte le critère chantier 5 n° 4.** Dans
  `Tests/CollaboratorPrepBuildersTests.swift` : un conteneur en mémoire, le jeu du lot 13
  (`RefonteDemoSeed.seedLot13`), `now = RefonteDemoSeed.oneOnOneSeedDate`, puis

```swift
let lignes = UnansweredItemsBuilder.build(fil, now: now)
#expect(lignes.count == 2)
#expect(lignes[0].source == .topic)          // mobilité : le sujet récurrent parle
#expect(lignes[0].sinceLabel == "depuis le 10 juil.")
#expect(lignes[1].source == .promise)        // astreintes : la promesse non tenue parle
#expect(lignes[1].text == "Grille de compensation des astreintes promise, 2 reports")
#expect(lignes[1].sinceLabel == "depuis le 24 juil.")
```

  plus un test « fil neuf » : `build` rend `[]` et `emptyInvite` n'est pas vide.

- [ ] **Étape 2 — vérifier l'échec.** `swift test --filter CollaboratorPrep` → échec de
  compilation (`UnansweredItemsBuilder` inconnu).

- [ ] **Étape 3 — implémenter.** Trois collectes, un regroupement, un tri :

```swift
// 1. Promesses du manager non tenues : missed, ou ouvertes et échues.
let promesses = CommitmentLedger.all(thread, side: .manager).filter {
    $0.state == .missed || CommitmentLedger.isOverdue($0, now: now)
}
// -> texte "<texte> promise" + ", n reports" si deferralCount > 0 ; date = promisedAt.

// 2. Sujets évoqués >= ReminderRules.recurringTopicThreshold qu'aucune décision ne tranche.
//    (pas d'exclusion par l'ordre du jour : cf. « la règle 2 est adaptée » du préambule)
// -> texte "<label> — n fois évoquée, jamais tranchée" ; date = nil.

// 3. Demandes pending/waiting du fil (AgendaCarryover.requests) : texte = celui de la demande,
//    date = requestedAt.
```

  Regroupement : clé = `RecurringTopicsBuilder.family(of:)?.rawValue` sinon
  `"seul-\(id de la source)"`. Par groupe : le libellé de la source la plus forte
  (`promise > topic > request`), la **plus petite** date non nulle, l'identifiant de la source
  retenue. Tri : les lignes datées d'abord, de la plus ancienne à la plus récente ; les lignes
  sans date ensuite, par libellé. `sinceLabel` = `"depuis le \(OneOnOneDateFormat.dayMonth(date))"`
  ou `""`.

- [ ] **Étape 4 — vérifier le vert.** `swift test --filter CollaboratorPrep`.

- [ ] **Étape 5 — `swift build` puis commit.**
  `feat(refonte): UnansweredItemsBuilder — ce qui est resté sans réponse (5b)`

---

## Task 2 — `WantedItemsBuilder` et `CollabPrepModel`

**Fichiers :**
- Créer : `OneToOne/Services/OneOnOne/Prep/CollaboratorWantedItems.swift`
- Créer : `OneToOne/Services/OneOnOne/Prep/CollaboratorPrepModel.swift`
- Modifier : `Tests/CollaboratorPrepBuildersTests.swift`

**Interfaces produites :**

```swift
@MainActor
enum WantedItemsBuilder {
    static let title = "CE QUE JE VEUX OBTENIR"
    static let emptyInvite: String
    static let composerPlaceholder = "Ajouter…"
    static func build(_ thread: OneOnOneThread,
                      excluding unanswered: [UnansweredItemsBuilder.Item]) -> [OneOnOneAgendaItem]
}

@MainActor
enum CollabPrepModel {
    static let deliveredTitle = "CE QUE J'AI LIVRÉ DEPUIS"
    static let deliveredEmptyInvite: String
    static let provenance =
        "Généré depuis vos actions, vos réunions et l'historique des 1:1 — modifiable avant partage."
    static let roleBadge = "Collaborateur"
    static let durationPromise = "2 min"
    static func header(meeting: Meeting, thread: OneOnOneThread, now: Date) -> CollabPrepHeaderModel
    static func deliveredSince(_ meeting: Meeting, in thread: OneOnOneThread) -> Date?
}

struct CollabPrepHeaderModel: Equatable, Sendable {
    var title: String      // "1:1 avec Yann — demain 14:00"
    var meta: String       // "Préparation · 2 min · dernier point le 21 août"
    var badge: String      // "Collaborateur"
    var initials: String   // "YP"
    var identity: String   // "Yann PENVEN", pour la palette d'avatar
}
```

- [ ] **Étape 1 — les tests.**

```swift
// En-tête, horloge injectée : la veille à 14:00 s'écrit "demain 14:00".
let demain = /* lendemain de now, 14:00, calendrier grégorien fr_FR */
#expect(CollabPrepModel.header(meeting: seanceDemain, thread: fil, now: now).title
        == "1:1 avec Yann — demain 14:00")
// Même jour -> "aujourd'hui 14:00" ; au-delà -> l'écriture d'échéance du domaine
// (OneOnOneDateFormat.dueDate) suivie de l'heure.
#expect(header.meta == "Préparation · 2 min · dernier point le 21 août")
#expect(header.badge == "Collaborateur")

// Sujets voulus : les 3 sujets privés du fil, moins celui que la ligne « mobilité » porte déjà.
let voulus = WantedItemsBuilder.build(fil, excluding: lignes)
#expect(voulus.count == 2)
#expect(voulus.map(\.text).contains("Porter la formation Admin"))
#expect(!voulus.contains { $0.text.contains("Mobilité archi") })

// Aucune zone vide sans invite : trois invites non vides sur un fil neuf.
```

- [ ] **Étape 2 — vérifier l'échec.**

- [ ] **Étape 3 — implémenter.** `WantedItemsBuilder.build` : `AgendaCarryover.sorted` sur
  `thread.agendaItems`, filtré `kind == .topic && state == .todo && visibility == .private`, moins
  les items dont la famille figure déjà dans une ligne sans réponse (une famille `nil` ne
  s'exclut jamais). `CollabPrepModel.header` : `Calendar(identifier: .gregorian)` en `fr_FR`,
  `isDateInTomorrow`/`isDate(inSameDayAs:)` **relatifs à `now`** (donc calculés à la main sur les
  jours, `isDateInTomorrow` s'appuyant sur la date du système), heure en `HH:mm` locale `fr_FR`.
  `deliveredSince` = `OneOnOneThreadStore.previousMeeting(before:in:)?.date`.

- [ ] **Étape 4 — vérifier le vert.**

- [ ] **Étape 5 — `swift build` puis commit.**
  `feat(refonte): sujets voulus et en-tête de la préparation collaborateur (5b)`

---

## Task 3 — `PrepToAgenda` : ordre, idempotence, visibilité

**Fichiers :**
- Créer : `OneToOne/Services/OneOnOne/Prep/CollaboratorPrepToAgenda.swift`
- Créer : `OneToOne/Services/OneOnOne/Prep/CollaboratorPrepStore.swift`
- Créer : `Tests/CollaboratorPrepAgendaTests.swift`

**Interfaces produites :**

```swift
@MainActor
enum PrepToAgenda {
    static let agendaButtonLabel = "En faire mon ordre du jour"
    static func shareButtonLabel(for thread: OneOnOneThread) -> String   // "Partager les sujets à Yann"
    static func doneLabel(_ count: Int) -> String                        // "Ordre du jour prêt · 2 sujets"
    static func shareConfirmation(_ count: Int) -> String

    /// Une ligne du plan : le texte de l'item à créer ou à retrouver.
    struct Line: Equatable, Sendable { var text: String; var isNew: Bool }

    /// Pur : l'ordre exact des sujets à porter.
    static func plan(unanswered: [UnansweredItemsBuilder.Item],
                     wanted: [OneOnOneAgendaItem]) -> [Line]
    static func prefix(for source: UnansweredItemsBuilder.Source) -> String

    @discardableResult
    static func apply(_ plan: [Line], for meeting: Meeting, in thread: OneOnOneThread,
                      in context: ModelContext) -> [OneOnOneAgendaItem]
    static func isApplied(_ plan: [Line], for meeting: Meeting, in thread: OneOnOneThread) -> Bool
    @discardableResult
    static func share(_ plan: [Line], for meeting: Meeting, in thread: OneOnOneThread,
                      in context: ModelContext) -> Int
}

@MainActor
enum CollaboratorPrepStore {
    @discardableResult
    static func addWantedTopic(text: String, for meeting: Meeting, in thread: OneOnOneThread,
                               in context: ModelContext) -> OneOnOneAgendaItem?
}
```

- [ ] **Étape 1 — les tests.**

```swift
// Ordre : les cochés de « sans réponse » préfixés, puis les cochés de « je veux obtenir ».
let plan = PrepToAgenda.plan(unanswered: [ligneTopic, lignePromesse], wanted: [sujetCharge])
#expect(plan.map(\.text) == ["Sujet : Mobilité archi — 4 fois évoquée, jamais tranchée",
                             "Promesse : Grille de compensation des astreintes promise, 2 reports",
                             "Charge : deux migrations + astreinte, je ne tiens pas le rythme"])

// Matérialisation : trois sujets privés, rangs 0,1,2, rattachés à la séance.
let items = PrepToAgenda.apply(plan, for: seance, in: fil, in: contexte)
#expect(items.count == 3)
#expect(items.allSatisfy { $0.visibility == .private })
#expect(items.allSatisfy { $0.kind == .topic })
#expect(items.map(\.order) == [0, 1, 2])

// Idempotence : un second appel ne crée rien et ne duplique rien.
let avant = fil.agendaItems.count
_ = PrepToAgenda.apply(plan, for: seance, in: fil, in: contexte)
#expect(fil.agendaItems.count == avant)
#expect(PrepToAgenda.isApplied(plan, for: seance, in: fil))
#expect(PrepToAgenda.doneLabel(3) == "Ordre du jour prêt · 3 sujets")

// Partage : le second bouton passe ces items — et eux seuls — en shared.
#expect(PrepToAgenda.share(plan, for: seance, in: fil, in: contexte) == 3)
#expect(items.allSatisfy { $0.visibility == .shared })
// Une ligne escalated ne redescend pas vers le manager par ce geste (D9).

// Composeur : un texte vide ne crée rien ; un texte crée un sujet privé todo.
#expect(CollaboratorPrepStore.addWantedTopic(text: "  ", for: seance, in: fil, in: contexte) == nil)
```

- [ ] **Étape 2 — vérifier l'échec.**

- [ ] **Étape 3 — implémenter.** `plan` : `prefix(for:)` rend `"Sujet : "`, `"Promesse : "`,
  `"Demande : "` (le vocabulaire d'`AgendaItemKind.label`, plus la promesse que ce modèle ne
  connaît pas) ; les sujets voulus gardent leur texte, ils existent déjà.
  `apply` : pour chaque ligne, retrouver l'item du fil par **texte** (idempotence par le texte,
  même règle qu'`AgendaCarryover.hasCopy` et `ReminderRules.toAgendaItems`) ou le créer
  (`addedBySide: .collaborator`, `state: .todo`, `visibility:
  OneOnOneConfidentiality.defaultVisibility(for: thread.myRole)`, `kind: .topic`), le rattacher au
  fil et à la séance, puis numéroter `0…n-1` **dans l'ordre du plan** ; les autres sujets
  (`kind == .topic`) de la séance sont renumérotés après, dans leur ordre relatif. Les demandes
  gardent leurs rangs : les deux listes sont filtrées séparément (ce que documente déjà
  `CollaboratorSessionModel.moveTopics`), une collision de rang y est sans effet.
  `share` : `apply` (idempotent) puis `visibility = .shared` sur les seuls items du plan **dont la
  visibilité est `.private`**, et rend leur nombre.
  `CollaboratorPrepStore.addWantedTopic` : refuse le vide, rang après le dernier sujet, sauvegarde
  une fois.

- [ ] **Étape 4 — vérifier le vert.**

- [ ] **Étape 5 — `swift build` puis commit.**
  `feat(refonte): PrepToAgenda — la liste devient mon ordre du jour privé (5b)`

---

## Task 4 — Le routage et l'état d'écran

**Fichiers :**
- Modifier : `OneToOne/Services/Meeting/MeetingSpaceRouting.swift`
- Modifier : `OneToOne/Services/OneOnOne/OneOnOneScreenState.swift`
- Modifier : `Tests/ManagerPrepRoutingTests.swift`, `Tests/RefonteVague5IntegrationTests.swift`
- Modifier : `Tests/CollaboratorPrepAgendaTests.swift`

- [ ] **Étape 1 — les tests.** Dans mon fichier : `usesOneOnOneCollaboratorPreparation` vraie
  pour `(.manager, .prepare)` seulement, fausse pour tous les autres couples ; les **cinq**
  branches de routage restent exclusives deux à deux ;
  `initialMode(persistedRaw: nil, kind: .manager, hasRecording: false) == .prepare` et
  `== nil` avec un enregistrement. Dans les deux fichiers partagés : onzième code de recette
  (task 6) et cinquième branche dans `routageExclusif` ; `.manager` sort de la boucle
  `autresTypes` de `ManagerPrepRoutingTests`, avec un commentaire qui dit pourquoi.

- [ ] **Étape 2 — vérifier l'échec.**

- [ ] **Étape 3 — implémenter.** Une fonction de plus dans `MeetingSpaceRouting`, après
  `usesOneOnOnePreparation` :

```swift
/// Vrai quand le mode Préparer doit monter la préparation en deux minutes du
/// 1:1 **subi** (`CollaboratorPrepView`, capture 5b).
static func usesOneOnOneCollaboratorPreparation(kind: MeetingKind,
                                                mode: MeetingScreenModel.Mode) -> Bool {
    kind == .manager && mode == .prepare
}
```

  et, dans `initialMode`, `kind == .oneToOne` devient
  `OneOnOneThreadStore.faceToFace.contains(kind)` : la spec ouvre un 1:1 en Préparer, et un 1:1
  subi sans enregistrement est justement celui qu'on ouvre la veille.
  Dans `OneOnOneScreenState`, **en fin de type** :

```swift
// MARK: - Lot 14 : préparation en deux minutes du 1:1 subi (5b)

/// Les lignes de `RESTÉ SANS RÉPONSE` cochées — décochées par défaut.
var collabPrepCheckedUnanswered: Set<String> = []
/// Les sujets de `CE QUE JE VEUX OBTENIR` **décochés** : la carte les coche par
/// défaut, l'état d'écran ne retient donc que le refus.
var collabPrepDroppedWanted: Set<String> = []
```

- [ ] **Étape 4 — vérifier le vert.**

- [ ] **Étape 5 — `swift build` puis commit.**
  `feat(refonte): router le mode Préparer d'un 1:1 subi vers l'écran 5b`

---

## Task 5 — Les quatre vues et le branchement

**Fichiers :**
- Créer : `OneToOne/Views/Meeting/OneOnOne/CollaboratorPrep/{CollaboratorPrepView, CollabPrepHeader, UnansweredCard, DeliveredSinceCard, WantedCard}.swift`
- Modifier : `OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift` (une branche)

- [ ] **Étape 1 — écrire les vues.** `CollaboratorPrepView` : `ScrollView` centrée,
  `frame(maxWidth: 940)`, en-tête violet pâle collé en tête d'un `RefonteCard`, les trois cartes,
  les deux boutons, la mention de provenance. Le fil est résolu dans `onAppear`
  (`OneOnOneThreadStore.thread(for:in:)` écrit en base — jamais depuis `body`), `now` figé à
  l'apparition, un jeton `revision` pour rejouer les modèles purs après une écriture : mêmes trois
  parties que `ManagerPrepView`. Sans interlocuteur : `MeetingEmptyInvite`.
  `UnansweredCard` / `WantedCard` : case à cocher dessinée
  (`RoundedRectangle` + `Image(systemName: "checkmark")`), 15 px, bordure `oneOnOne`, remplie
  quand cochée ; libellé `plexSans(12)` ; `depuis le …` en `plexSans(11)` `inkMuted`.
  `DeliveredSinceCard` : `DeliveredItemsBuilder.build` avec `since =
  CollabPrepModel.deliveredSince`, `now` = l'instant d'ouverture, lignes `✓`/`◐` (`ok`/`warn`),
  **sans** bouton `Citer` — il n'y a pas de notes à écrire en préparation.
  Le second bouton demande confirmation (`confirmationDialog`) avec le compte des sujets.

- [ ] **Étape 2 — brancher.** Dans `MeetingSpaceView.contenu`, une branche après celle du lot 12 :

```swift
} else if MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation(kind: meeting.kind,
                                                                  mode: screen.mode) {
    // Lot 14, spec §6.3 : la préparation en deux minutes du 1:1 subi est une
    // carte étroite centrée — ni rail, ni bandeau d'indicateurs.
    CollaboratorPrepView(meeting: meeting, screen: screen, historique: historique)
}
```

- [ ] **Étape 3 — `swift build`.**

- [ ] **Étape 4 — `swift test`** (rien ne doit régresser).

- [ ] **Étape 5 — commit.** `feat(refonte): écran 5b — la carte de préparation du 1:1 subi`

---

## Task 6 — Recette `5b` et notification « Préparer »

**Fichiers :**
- Modifier : `OneToOne/Services/Debug/RecetteScreen.swift` (un cas)
- Modifier : `OneToOne/Services/MeetingNotificationService.swift` (un bloc)
- Modifier : `Tests/CollaboratorPrepAgendaTests.swift`, `Tests/RefonteVague5IntegrationTests.swift`

- [ ] **Étape 1 — les tests.**

```swift
// Le code de recette : la séance subie, en mode Préparer.
#expect(RecetteScreen.from(environment: "5b")?.cible == .entretienSubi)
#expect(RecetteScreen.from(environment: "5b")?.mode == .prepare)

// La notification de la veille : une action « Préparer », et pour .manager seulement.
#expect(MeetingNotificationService.preStartCategory(for: .manager)
        == MeetingNotificationService.Category.preStartOneOnOne)
for kind in MeetingKind.allCases where kind != .manager {
    #expect(MeetingNotificationService.preStartCategory(for: kind)
            == MeetingNotificationService.Category.preStart)
}
let categories = MeetingNotificationService.makeCategories()
let subie = categories.first { $0.identifier == MeetingNotificationService.Category.preStartOneOnOne }
#expect(subie?.actions.contains { $0.identifier == MeetingNotificationService.Action.prepare } == true)
#expect(subie?.actions.first?.title == "Préparer")
let standard = categories.first { $0.identifier == MeetingNotificationService.Category.preStart }
#expect(standard?.actions.contains { $0.identifier == MeetingNotificationService.Action.prepare } == false)
```

  Aucun test n'instancie `UNUserNotificationCenter` : `makeCategories` et `preStartCategory` sont
  `nonisolated static` et purs.

- [ ] **Étape 2 — vérifier l'échec.**

- [ ] **Étape 3 — implémenter.** `RecetteScreen` : un cas
  `collaboratorPreparation = "5b"`, `cible = .entretienSubi`, `mode = .prepare`.
  `MeetingNotificationService` : `Category.preStartOneOnOne`, `Action.prepare`, la fonction pure
  `preStartCategory(for:)`, la catégorie dans `makeCategories()` (`[prepareAction, openAction,
  snoozeAction]`), l'appel `category: Self.preStartCategory(for: meeting.kind)` dans le
  pré-rappel, et la branche du gestionnaire : `Action.prepare` **écrit le mode mémorisé**
  (`MeetingScreenModel.modeKey(for:)` ← `prepare`) avant de poster
  `openMeetingNotification` — c'est le routage d'ouverture déjà en place (celui de la recette et
  d'`appliquerModeInitial`), pas un second chemin.

- [ ] **Étape 4 — vérifier le vert.**

- [ ] **Étape 5 — `swift build` puis commit.**
  `feat(refonte): ouvrir 5b depuis le rappel de la veille et le code de recette 5b`

---

## Task 7 — STATUS, rebase, PR

- [ ] **Étape 1 —** `swift test` complet. Consigner l'heure et les deux compteurs
  (référence lot 13 : 1 742 Swift Testing + 1 041 XCTest ; l'échec horaire
  `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` n'est toléré qu'entre 0 h et 2 h et
  seul).
- [ ] **Étape 2 —** section `STATUS.md` **en tête**, datée 2026-09-08 : l'écran, les trois
  sources de `RESTÉ SANS RÉPONSE`, les écarts assumés, les fichiers, les critères, la prochaine
  action.
- [ ] **Étape 3 —** `git fetch origin` ; si le SHA d'`origin/feat/refonte-lot-13-1to1-collab-seance`
  diffère de `.lot14-base-sha` :
  `git rebase --onto origin/feat/refonte-lot-13-1to1-collab-seance $(cat .lot14-base-sha)`,
  résoudre, `swift test`.
- [ ] **Étape 4 —** `git push -u origin feat/refonte-lot-14-1to1-collab-prepa` puis
  `gh pr create --base feat/refonte-lot-13-1to1-collab-seance`. Ne pas merger.
