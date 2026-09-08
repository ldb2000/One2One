# Lot 13 — 1:1 collaborateur, écran de séance (5a)

> **Pour un exécutant agentique :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> ou `superpowers:subagent-driven-development`. Les étapes sont cochables (`- [ ]`).

**Objectif :** monter l'écran de séance du 1:1 **subi** (`MeetingKind.manager`, mode En
séance, `OneOnOneThread.myRole == .collaborator`), grille `308 | 1fr | 356`, conforme à la
capture `5a-1to1-collaborateur-seance.png`.

**Architecture :** une branche de plus dans `MeetingSpaceView.contenu`, gardée par
`MeetingSpaceRouting.usesOneOnOneCollaboratorSession`. Toute règle métier est une fonction
**pure et testée** dans `Services/OneOnOne/**` ; les vues de `Views/Meeting/OneOnOne/Collaborator/**`
ne font que rendre. Les composants partagés du lot 11 (`Shared/**`) sont **réutilisés sans
être modifiés**.

**Pile technique :** SwiftUI + SwiftData, SwiftPM (`swift build`, `swift test`), Swift Testing.

**Spécifications :**
- `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §6.1, §6.2, §3.2, critères
  chantier 5 n° 1, 2, 3.
- `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 13 », §4 (D4, D9), §7.
- Capture qui fait foi : `docs/superpowers/specs/refonte-2026-09/ecrans/5a-1to1-collaborateur-seance.png`.

## Contraintes globales

- Commentaires et libellés d'interface en **français**, symboles en anglais.
- Aucune dépendance SwiftPM nouvelle. Aucune couleur hors `One2OneToken`.
- Énums persistées SwiftData en `…Raw: String` + wrapper calculé.
- Grille : `MeetingSpaceLayout.collabLeftWidth = 308`, `collabRailWidth = 356` ; à 1 280 px la
  colonne fluide fait ≥ 520 px et aucune colonne ne se chevauche.
- Défaut de visibilité côté collaborateur : `private`
  (`OneOnOneConfidentiality.defaultVisibility(for: .collaborator)`).
- Aucune zone vide sans invite.
- **Fichiers interdits** : `Views/Meeting/OneOnOne/Shared/**`, `Manager/**`, `ManagerPrep/**`,
  `Views/Capture/**`, `Services/Capture/**`, `Services/Report/**`, `BuiltInTemplates`,
  `Workshop/**`, `Rail/**`, `Review/**`, `Resources/**`, `Project/**`, `Session/**`,
  `MeetingView.swift`, `RefonteDemoSeed.swift`, `RefonteDemoSeed+Lot10.swift`.
- **Aucune recette graphique, aucun lancement d'application.**

---

## Carte des fichiers

### Créés — services purs

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/OneOnOne/DeliveredItemsBuilder.swift` | `CE QUE J'AI LIVRÉ` : actions closes de l'utilisateur + réunions à rôle actif + actions bloquées, depuis le 1:1 précédent. Pur. |
| `OneToOne/Services/OneOnOne/Collaborator/CollaboratorSessionModel.swift` | Tous les intitulés, invites et pilules de l'écran 5a (titres, mention de confidentialité, statuts de demande, promesses, `EN SORTANT`). Pur. |
| `OneToOne/Services/OneOnOne/Collaborator/CollaboratorTopBarModel.swift` | Modèle **pur** du fil d'Ariane de la barre du haut — support du critère n° 1. |
| `OneToOne/Services/OneOnOne/Collaborator/CollaboratorNotePrivacy.swift` | `Partager la ligne` : bascule **une** ligne en `shared`. Support du critère n° 2. |
| `OneToOne/Services/OneOnOne/Collaborator/PromiseReminders.swift` | `Relancer` : sujet privé pour le prochain 1:1, compteur de relances, rappel local (injectable). |

### Créés — vues

| Fichier | Responsabilité |
| --- | --- |
| `Views/Meeting/OneOnOne/Collaborator/CollaboratorSessionView.swift` | La grille `308 \| 1fr \| 356` et les trois colonnes. |
| `Views/Meeting/OneOnOne/Collaborator/MyTopicsCard.swift` | `CE QUE JE VEUX DIRE` — items numérotés, poignée `⠿`, composeur, mention. |
| `Views/Meeting/OneOnOne/Collaborator/MyRequestsCard.swift` | `MES DEMANDES EN COURS`. |
| `Views/Meeting/OneOnOne/Collaborator/CollaboratorNotesColumn.swift` | En-tête, pilules `● Privé par défaut` / `Partager la ligne`, deux sections, composeur. |
| `Views/Meeting/OneOnOne/Collaborator/DeliveredCard.swift` | `CE QUE J'AI LIVRÉ` + bouton `Citer`. |
| `Views/Meeting/OneOnOne/Collaborator/PromisesCard.swift` | `CE QU'IL M'A PROMIS`. |
| `Views/Meeting/OneOnOne/Collaborator/CollaboratorClosingCard.swift` | `EN SORTANT`. |
| `Views/Meeting/OneOnOne/Collaborator/MyRecapPreview.swift` | L'aperçu du récap filtré `.manager` (bouton `Mon récap`). |
| `Views/Meeting/Spaces/Notes/TimedNotesColumn+Collaborator.swift` | `CollaboratorNotesSection` : lignes d'une section, bloc privé `● POUR MOI SEUL`, sélection de la ligne courante. |
| `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot13.swift` | Le jeu de démonstration 5a (extension). |

### Modifiés — blocs localisés

| Fichier | Modification |
| --- | --- |
| `Services/Meeting/MeetingSpaceLayout.swift` | deux constantes + `collaboratorColumns(totalWidth:)`. |
| `Services/Meeting/MeetingSpaceRouting.swift` | `usesOneOnOneCollaboratorSession(kind:mode:)`. |
| `Views/Meeting/Spaces/MeetingSpaceView.swift` | une branche `kind == .manager`. |
| `Views/Meeting/MeetingTopChromeBar.swift` | bloc `.manager` : segment `Mes 1:1`, en-tête `Avec <Manager> — <date>`, bouton `Mon récap`. |
| `Services/OneOnOne/OneOnOneScreenState.swift` | `collabSelectedNoteID` **en fin de type**. |
| `OneToOne/OneToOneApp.swift` | crochet `ONETOONE_SEED_DEMO_SCREEN=5a`. |
| `STATUS.md` | section du lot 13 **en tête**. |

### Tests

`Tests/DeliveredItemsBuilderTests.swift`, `Tests/CollaboratorSessionLayoutTests.swift`,
`Tests/CollaboratorSessionModelTests.swift`, `Tests/CollaboratorNotePrivacyTests.swift`,
`Tests/PromiseRemindersTests.swift`.

---

## Décisions prises dans ce lot

**« Ce que j'ai livré » — la règle retenue.** L'utilisateur de l'application n'est **pas** un
`Collaborator` : il n'a pas de fiche d'annuaire, donc `assignedTasks` ne le concerne pas. Ses
actions sont celles dont `destinataire == .moi` (`ActionAudience.moi`, le défaut du modèle).
Trois sources, dans cet ordre d'affichage :

1. **Actions closes** : `destinataire == .moi`, `isCompleted`, `completedAt` dans
   `]1:1 précédent, séance]`. Détail : `Action close le <j mois>` + la charge quand
   `effortMinutes` la porte (`2 j` à partir de 480 min/jour).
2. **Réunions à rôle actif** : réunion dans la même fenêtre, **hors tête-à-tête**
   (`OneOnOneThreadStore.faceToFace` : mes 1:1 ne sont pas un livrable), portant soit une
   décision (`MeetingNote.kind == .decision`), soit une note de moi
   (`authorSide == .me`). Détail : `Réunion du <j mois> · a débloqué la décision`, ou
   `· notes prises`.
3. **Actions bloquées** : `destinataire == .moi`, `status == .open`, et soit
   `deferralCount > 0`, soit un `ActionComment` dont le texte replié commence par `bloqu`.
   Rendues en `warn` avec leur cause (`En cours · bloqué par les comptes GitLab`), **sans
   borne de date** : un blocage est un état présent, pas un événement de la fenêtre.

`Citer` **propage la chaîne de citation** au lieu d'en inventer une : `SourceRef.Kind` n'a pas
de cas pour une action, et `ActionTask` n'a pas de `stableID` qu'un `SourceRef` pourrait viser.
Une ligne issue d'une action reprend donc le `sourceRef` de l'action (l'endroit d'où elle est
née) ; une ligne issue d'une réunion vise la note qui l'a justifiée
(`SourceRef(kind: .note, stableID:, t:)`). Aucun modèle n'est modifié.

---

## Task 1 — Grille, routage, modèle de barre

**Fichiers :**
- Modifier : `OneToOne/Services/Meeting/MeetingSpaceLayout.swift`
- Modifier : `OneToOne/Services/Meeting/MeetingSpaceRouting.swift`
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`
- Créer : `OneToOne/Services/OneOnOne/Collaborator/CollaboratorTopBarModel.swift`
- Test : `Tests/CollaboratorSessionLayoutTests.swift`

**Interfaces produites :**
- `MeetingSpaceLayout.collabLeftWidth: CGFloat = 308`, `collabRailWidth: CGFloat = 356`
- `MeetingSpaceLayout.collaboratorColumns(totalWidth: CGFloat) -> (left: CGFloat, center: CGFloat, rail: CGFloat)`
- `MeetingSpaceRouting.usesOneOnOneCollaboratorSession(kind: MeetingKind, mode: MeetingScreenModel.Mode) -> Bool`
- `MeetingTopChromeBar.myOneOnOnesSegmentLabel(for: MeetingKind) -> String?`
- `MeetingTopChromeBar.collaboratorSessionHeading(person: String, date: Date) -> String`
- `CollaboratorTopBarModel.breadcrumbSegments(for: MeetingKind) -> [String]`

- [ ] **Étape 1 — écrire les tests qui échouent** : largeurs à 1 280 / 1 920 / 1 000 / 700 px,
      jamais de largeur négative, routage réservé à `.manager` + `.live`, segments du fil
      d'Ariane (`Mes 1:1` et la pilule de rôle présentes pour `.manager`, absentes pour
      `.oneToOne`), en-tête `Avec Yann PENVEN — 4 septembre`.
- [ ] **Étape 2** — `swift test --filter CollaboratorSessionLayoutTests` : échec attendu
      (symboles inconnus).
- [ ] **Étape 3** — implémenter les deux constantes, `collaboratorColumns` (délègue à
      `columns(totalWidth:rail:sideNav:)`, la colonne gauche cède la première), le routage,
      les deux statiques de la barre et `CollaboratorTopBarModel`.
- [ ] **Étape 4** — `swift test --filter CollaboratorSessionLayoutTests` : vert.
- [ ] **Étape 5** — `swift build` puis commit
      `feat(refonte): lot 13 — grille 308|1fr|356, routage et fil d'Ariane du 1:1 subi`.

## Task 2 — `DeliveredItemsBuilder`

**Fichiers :**
- Créer : `OneToOne/Services/OneOnOne/DeliveredItemsBuilder.swift`
- Test : `Tests/DeliveredItemsBuilderTests.swift`

**Interfaces produites :**
```swift
@MainActor enum DeliveredItemsBuilder {
    enum Status: Sendable, Equatable { case delivered, blocked }
    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        var symbol: String          // "✓" livré, "◐" bloqué
        var text: String
        var detail: String
        var status: Status
        var reference: SourceRef?
        var date: Date
    }
    static let title: String                       // "CE QUE J'AI LIVRÉ"
    static let autoBadge: String                   // "auto"
    static let emptyInvite: String
    static let quoteButtonLabel: String            // "Citer"
    static func sinceLabel(_ since: Date?) -> String
    static func effortLabel(minutes: Int?) -> String?
    static func build(actions: [ActionTask], meetings: [Meeting],
                      since: Date?, now: Date) -> [Item]
    static func quoteText(_ item: Item) -> String
}
```

- [ ] **Étape 1 — tests qui échouent** : une action close dans la fenêtre est reprise avec
      `Action close le 29 août · 2 j` ; une action close **avant** la fenêtre est écartée ;
      une action `destinataire == .collaborateur` est écartée ; une réunion portant une
      décision donne `Réunion du 1er sept. · a débloqué la décision` ; un 1:1 est écarté ;
      une action ouverte reportée donne `◐` + `En cours · reporté 2 fois` ; une action ouverte
      avec commentaire `Bloqué par les comptes GitLab` donne
      `En cours · bloqué par les comptes GitLab` ; le tri met les livrés d'abord, par date
      croissante, les bloqués ensuite ; `sinceLabel` rend `depuis le 21 août` et, sans borne,
      `depuis le début du fil` ; `build` sans rien rendre laisse `emptyInvite` à l'écran
      (liste vide).
- [ ] **Étape 2** — `swift test --filter DeliveredItemsBuilderTests` : échec.
- [ ] **Étape 3** — implémenter, en documentant la règle « `destinataire == .moi` ».
- [ ] **Étape 4** — `swift test --filter DeliveredItemsBuilderTests` : vert.
- [ ] **Étape 5** — `swift build` puis commit
      `feat(refonte): lot 13 — DeliveredItemsBuilder (ce que j'ai livré, auto)`.

## Task 3 — Intitulés, confidentialité par ligne, relances

**Fichiers :**
- Créer : `OneToOne/Services/OneOnOne/Collaborator/CollaboratorSessionModel.swift`
- Créer : `OneToOne/Services/OneOnOne/Collaborator/CollaboratorNotePrivacy.swift`
- Créer : `OneToOne/Services/OneOnOne/Collaborator/PromiseReminders.swift`
- Modifier : `OneToOne/Services/OneOnOne/OneOnOneScreenState.swift` (fin de type)
- Test : `Tests/CollaboratorSessionModelTests.swift`, `Tests/CollaboratorNotePrivacyTests.swift`,
  `Tests/PromiseRemindersTests.swift`

**Interfaces produites :**
```swift
@MainActor enum CollaboratorSessionModel {
    static let myTopicsTitle, privacyPill, myTopicsMention, myTopicsComposerPlaceholder,
               dragHint, dragHandle, myTopicsEmptyInvite: String
    static let requestsTitle, requestsEmptyInvite: String
    static let notesTitle, defaultPrivacyPill, shareLinePill: String
    static let heardTitle, saidTitle, privateBlockLabel: String
    static let heardEmptyInvite, saidEmptyInvite: String
    static let promisesTitle, promisesEmptyInvite, remindButtonLabel: String
    static let closingTitle, annualFolderButtonLabel: String
    static func requestTone(_ item: OneOnOneAgendaItem, now: Date) -> ChipTon
    static func topicNumber(_ index: Int) -> String
    static func myTopics(_ thread: OneOnOneThread, for meeting: Meeting) -> [OneOnOneAgendaItem]
    static func requests(_ thread: OneOnOneThread) -> [OneOnOneAgendaItem]
    static func promises(_ thread: OneOnOneThread, now: Date) -> [Commitment]
    static func lateBadge(_ thread: OneOnOneThread, now: Date) -> String?
    static func promisedAtPill(_ commitment: Commitment) -> String
    static func deferralPill(_ commitment: Commitment) -> String?
    static func recapButtonLabel(for thread: OneOnOneThread) -> String
    static func excludedLinesLabel(for meeting: Meeting, in thread: OneOnOneThread) -> String?
    static func assistantSuggestion(_ thread: OneOnOneThread, for meeting: Meeting) -> String
    static func heardSectionNotes(_ meeting: Meeting) -> [MeetingNote]
    static func saidSectionNotes(_ meeting: Meeting) -> [MeetingNote]
}

@MainActor enum CollaboratorNotePrivacy {
    static let defaultVisibility: Visibility            // .private
    @discardableResult static func shareLine(_ note: MeetingNote,
                                             in context: ModelContext?) -> Bool
    static func sharedCount(_ notes: [MeetingNote]) -> Int
}

@MainActor enum PromiseReminders {
    static func agendaText(for commitment: Commitment) -> String
    @discardableResult static func remind(_ commitment: Commitment,
                                          in thread: OneOnOneThread,
                                          nextMeeting: Meeting?,
                                          in context: ModelContext,
                                          notify: ((String) -> Void)?) -> OneOnOneAgendaItem
}
```

- [ ] **Étape 1 — tests qui échouent** : `requestTone` (`.warn` pour `pending`/`waiting`,
      `.ok` pour `granted`, `.report` pour `refused` **et** pour une demande sans réponse de
      plus de 60 jours) ; `promises` triées par retard décroissant ;
      `lateBadge` → `1 en retard` ; `promisedAtPill` → `Promise le 24 juil.` ;
      `deferralPill` → `2 reports` / `1 report` / `nil` ; `excludedLinesLabel` sur une
      fixture 1 note + 1 engagement + 1 sujet privés → `3 lignes privées seront exclues.` ;
      `recapButtonLabel` → `Envoyer mon récap à Yann` ; deux sections de notes réparties par
      `authorSide` ; défaut de visibilité `private` ; `shareLine` ne change **qu'une** ligne ;
      `remind` incrémente `remindedCount`, crée **un** sujet privé pour la séance suivante et
      reste idempotent au second appel, avec `notify` appelé une fois par relance.
- [ ] **Étape 2** — `swift test --filter Collaborator --filter PromiseReminders` : échec.
- [ ] **Étape 3** — implémenter les trois services + `collabSelectedNoteID` en fin de
      `OneOnOneScreenState`.
- [ ] **Étape 4** — les trois suites vertes.
- [ ] **Étape 5** — `swift build` puis commit
      `feat(refonte): lot 13 — intitulés, partage par ligne et relance des promesses`.

## Task 4 — Les vues et la branche de routage

**Fichiers :** les neuf vues de la carte des fichiers,
`Views/Meeting/Spaces/Notes/TimedNotesColumn+Collaborator.swift`, et la branche dans
`MeetingSpaceView.contenu`.

- [ ] **Étape 1** — `CollaboratorSessionView` : `OneOnOneThreadStore.thread(for:in:)`,
      `MeetingEmptyInvite` quand il n'y a pas de participant, `collaboratorColumns`, filets
      d'un pixel comptés dans la colonne centrale (même règle que `ManagerSessionView`).
- [ ] **Étape 2** — colonne gauche : `MyTopicsCard` (numéros, `⠿`, `onDrag`/`onDrop` à la
      main — jamais de `List` dans une `ScrollView`, cf. programme §2.4 —, composeur,
      mention), `MyRequestsCard`, puis `MeetingAssistantDock` avec un
      `Contexte(placeholder: CollaboratorSessionModel.assistantSuggestion(...), threadID:)`.
- [ ] **Étape 3** — colonne centrale : `CollaboratorNotesColumn` + `CollaboratorNotesSection`
      (bloc privé `● POUR MOI SEUL`, sélection de la ligne courante) + `NoteComposer` avec
      `OneOnOneComposerContext(role: .collaborator)` et
      `NoteCommandCatalog.commands(for: .manager, role: .collaborator)`.
- [ ] **Étape 4** — colonne droite : `DeliveredCard`, `PromisesCard`,
      `CollaboratorClosingCard`.
- [ ] **Étape 5** — barre du haut : bouton `Mon récap` + `MyRecapPreview` (feuille), branche
      de `MeetingSpaceView`.
- [ ] **Étape 6** — `swift build` puis commit
      `feat(refonte): lot 13 — écran de séance du 1:1 collaborateur (5a)`.

## Task 5 — Jeu de démonstration, crochet de recette, STATUS

**Fichiers :** `Services/Debug/Seed/RefonteDemoSeed+Lot13.swift`, `OneToOneApp.swift`,
`STATUS.md`.

- [ ] **Étape 1** — `seedLot13(in:)` : réutilise `seedOneOnOneThreads` (lot 10, non modifié),
      complète les quatre livrables (deux actions closes le 29 août et le 2 sept., une action
      close sans charge, une action ouverte bloquée par les comptes GitLab), la réunion du
      1er sept. avec sa décision, et l'échéance de la promesse d'arbitrage. Idempotent par le
      texte.
- [ ] **Étape 2** — crochet `ONETOONE_SEED_DEMO_SCREEN=5a` dans `maybeSeedRefonteDemo`.
- [ ] **Étape 3** — `swift build`, `swift test` **complet** vert.
- [ ] **Étape 4** — `STATUS.md` : section du lot 13 en tête, datée.
- [ ] **Étape 5** — commit `feat(refonte): lot 13 — jeu de démonstration 5a et crochet de recette`,
      puis `docs(status): consigner le lot 13`.

---

## Revue du plan

- **Couverture de la spec §6.2** : mes sujets (Task 3 + 4), mes demandes (Task 3 + 4), notes
  en deux sections et `/promesse /demande /preuve` (Task 4, catalogue du lot 10), ce que j'ai
  livré + `Citer` (Task 2 + 4), ce qu'il m'a promis + `Relancer` (Task 3 + 4), pied
  `EN SORTANT` (Task 3 + 4). §6.1 : défaut `private` (Task 3), pilule de rôle (Task 1),
  colonnes inversées (Task 4), clôture (Task 3).
- **Critères chantier 5** : n° 1 → `CollaboratorTopBarModel` (Task 1) ; n° 2 →
  `CollaboratorNotePrivacy` (Task 3) ; n° 3 → `DeliveredItemsBuilder` + `Citer` (Task 2 + 4).
- **Hors périmètre** : la préparation 5b (lot 14), la remontée automatique d'une promesse non
  tenue dans la préparation suivante (critère n° 4, lot 14).
