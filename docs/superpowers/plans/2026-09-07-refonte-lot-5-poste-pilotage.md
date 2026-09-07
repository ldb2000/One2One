# Lot 5 — Poste de pilotage (mode Relire) — plan d'exécution

> **Pour l'exécutant :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> (exécution en session) ou `superpowers:subagent-driven-development`. Les étapes
> sont des cases à cocher (`- [ ]`).

**But :** faire du mode **Relire** de l'espace Réunion la disposition exacte de
`ecrans/1c-poste-de-pilotage.png` — nav latérale 190 px à compteurs, en-tête à
métadonnées, cartes `EN UNE PHRASE` / `DÉCISIONS PRISES`, tableau d'actions dense
à sept colonnes navigable au clavier, frise audio étiquetée pleine largeur — et y
basculer automatiquement après génération du rapport.

**Architecture :** un dossier `Views/Meeting/Spaces/Review/` porte toutes les
surfaces ; toute règle métier en sort en fonction pure testée
(`Services/Meeting/ActionsTableCommands.swift`,
`Services/Meeting/TimelineLabelLayout.swift`, et les `static` des vues). L'état
d'écran du mode vit dans un unique `ReviewState` `@Observable`, accroché à
`MeetingScreenModel` par une seule ligne. Rien n'est réécrit du lot 3 : l'édition
inline (`ActionCardEditing`), la suggestion de responsable (`OwnerSuggestion`) et
la création (`ActionComposerService`) sont **réemployées**.

**Pile technique :** SwiftUI (macOS), SwiftData, Swift Testing + XCTest,
exécutable SwiftPM (`swift build`, `swift test`).

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §2.7 (+ §2.2,
§1.2) ; plan directeur `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`
§1 (D0), §5 « Lot 5 », §7 ; capture qui fait foi
`docs/superpowers/specs/refonte-2026-09/ecrans/1c-poste-de-pilotage.png`.

## Contraintes globales

- Branche `feat/refonte-lot-5-poste-pilotage`, basée sur
  `origin/feat/refonte-lot-3-rail-actions` (pile `0A/0B → 1a → 1b → 2 → 3`).
- **Aucune dépendance SwiftPM nouvelle.**
- **Aucune couleur hors `One2OneToken`** ; largeurs fixes de la spec §1.2
  (`One2OneToken.sideNavWidth == 190`).
- Libellés UI et commentaires **en français**, symboles en anglais.
- Rien n'est **ajouté** à `MeetingView.swift` hors la ligne post-génération.
- **Fichiers interdits** (lots 4, 6, 10 en parallèle) :
  `Views/Meeting/Session/**`, `Views/Meeting/Resources/**`,
  `MeetingResourcesSpace.swift`, `Services/Attachment*`, `Services/OneOnOne/**`,
  `Models/OneOnOne*`, `Models/Commitment*`, `Views/Meeting/Spaces/Rail/**`
  (réemploi sans modification ; si une API manque, créer
  `Rail/ActionCardEditing+Table.swift`).
- Fichiers partagés autorisés, **un seul point de touche chacun** :
  `MeetingSpaceView.swift` (routage du mode Relire), `AudioTimelineStrip.swift`
  (mode étiqueté, rendu par défaut inchangé), `MeetingSpacesBar.swift` (masquage
  en Relire), `MeetingScreenModel.swift` (`var review = ReviewState()`),
  `MeetingView.swift` (ligne post-génération + câblage du call-site).
  `MeetingTopChromeBar.swift` : **rien**.
- `swift build` avant chaque commit ; `swift test` complet vert avant la PR
  (référence : **1 931 tests**).
- Commits conventionnels, `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## Carte des fichiers

**Créés**

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/Meeting/ActionsTableCommands.swift` | Commandes clavier **pures** du tableau : `↑↓`, `Espace`, `⌥↑↓`, index de la première action non assignée, normalisation de `sortOrder`. |
| `OneToOne/Services/Meeting/TimelineLabelLayout.swift` | Placement **pur** des étiquettes de la frise, sans chevauchement. |
| `OneToOne/Views/Meeting/Spaces/Review/ReviewState.swift` | État d'écran du mode Relire (`@Observable`) + la transition post-rapport. |
| `OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift` | Nav latérale 190 px : entrées à compteur (table pure exhaustive), bloc projet, bloc `ALERTES`. |
| `OneToOne/Views/Meeting/Spaces/Review/ReviewHeader.swift` | En-tête : titre, ligne de métadonnées, `Capture` / `Exporter ⌄` / `Rapport ✓ (m:ss)`, sélecteur de mode. |
| `OneToOne/Views/Meeting/Spaces/Review/OneSentenceCard.swift` | Carte `EN UNE PHRASE` : `shortSummary`, badge `généré`, tags, invite + génération. |
| `OneToOne/Views/Meeting/Spaces/Review/DecisionsCard.swift` | Carte `DÉCISIONS PRISES · n` : notes `kind: .decision` triées par `t`, timecode cliquable, porteur détecté. |
| `OneToOne/Views/Meeting/Spaces/Review/ActionsTable.swift` | Tableau dense 7 colonnes, édition inline, clavier, sélecteur de vue, `＋ Action`, pied composeur. |
| `OneToOne/Views/Meeting/Spaces/Review/ReviewAudioTimeline.swift` | Frise pleine largeur : `▶`, `AudioTimelineStrip(labelled: true)`, `✂ Éditer`. |
| `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot5.swift` | Extension de semis : 3 décisions horodatées à porteur, 4 tags, 2 réunions de projet supplémentaires. |
| `Tests/ActionsTableCommandsTests.swift`, `Tests/TimelineLabelLayoutTests.swift`, `Tests/ReviewSidebarNavTests.swift`, `Tests/ReviewStateTests.swift`, `Tests/ReviewCardsInviteTests.swift`, `Tests/RefonteDemoSeedLot5Tests.swift` | Suites du lot. |

**Modifiés**

| Fichier | Modification unique |
| --- | --- |
| `OneToOne/Views/Meeting/Spaces/MeetingReviewSpace.swift` | Recomposition complète autour des composants ci-dessus ; le contenu provisoire du lot 1 disparaît, le générique `Actions` aussi. |
| `OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift` | Le mode Relire route vers `MeetingReviewSpace` en pleine surface (ni bandeau KPI, ni rail, ni dock injecté) ; deux paramètres ajoutés (`menuActions`, `onShowCaptures`). |
| `OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift` | `estMasquee(space:mode:)` + garde de corps : la nav latérale **remplace** la barre en Relire (plan §1, D0). |
| `OneToOne/Views/Meeting/Spaces/AudioTimelineStrip.swift` | `labelled: Bool = false` : bande d'étiquettes au-dessus des marqueurs. Défaut inchangé. |
| `OneToOne/Views/Meeting/MeetingScreenModel.swift` | **Une ligne** : `var review = ReviewState()`. |
| `OneToOne/Views/MeetingView.swift` | Ligne post-génération (`screen.space = .report` → `ReviewState.apresGenerationDuRapport(screen)`) + les deux paramètres du call-site de `MeetingSpaceView`. |

---

## Task 1 — Commandes clavier pures du tableau

**Fichiers :** Créer `OneToOne/Services/Meeting/ActionsTableCommands.swift` ·
Test `Tests/ActionsTableCommandsTests.swift`

**Interfaces produites :**

```swift
@MainActor enum ActionsTableCommands {
    /// Ligne suivante/précédente, bornée (pas de boucle : on ne quitte pas le
    /// tableau par le clavier).
    static func indexSuivant(courant: Int?, nombre: Int, delta: Int) -> Int?
    /// Permutation d'indices après `⌥↑` / `⌥↓`. `nil` = déplacement impossible.
    static func permutation(nombre: Int, index: Int, delta: Int) -> [Int]?
    /// Écrit `sortOrder` selon un ordre de lignes, en 0…n−1.
    static func appliquerOrdre(_ lignes: [ActionTask])
    /// Index de la première action sans responsable, `nil` si toutes le sont.
    static func premiereSansResponsable(_ lignes: [ActionTask]) -> Int?
    /// Les lignes visibles quand le tableau est replié (5 par défaut) et le
    /// nombre restant.
    static func repli(_ lignes: [ActionTask], limite: Int, tout: Bool)
        -> (visibles: [ActionTask], restantes: Int)
}
```

- [ ] **Étape 1 — écrire la suite qui échoue.** Cas : `indexSuivant` depuis
      `nil` rend `0` vers le bas et `nombre−1` vers le haut ; borné aux deux
      extrémités ; `nombre == 0` rend `nil`. `permutation(nombre: 4, index: 2,
      delta: -1) == [0, 2, 1, 3]` ; `index: 0, delta: -1` rend `nil` ;
      `index: 3, delta: 1` rend `nil`. `appliquerOrdre` donne des `sortOrder`
      strictement croissants **et** `ActionsRailGrouping.triees` rend ensuite
      exactement cet ordre (le tri du rail passe `sortOrder` en premier).
      `premiereSansResponsable` ignore un `unresolvedAssigneeName` non vide
      (même règle que `ActionsRailGrouping.aUnPorteur`). `repli` : 12 lignes,
      limite 5 → 5 visibles / 7 restantes ; `tout: true` → 12 / 0.
- [ ] **Étape 2 — `swift test --filter ActionsTableCommandsTests`** : échoue
      (type inconnu).
- [ ] **Étape 3 — implémenter** le fichier, en documentant en français pourquoi
      la navigation ne boucle pas et pourquoi `appliquerOrdre` normalise à
      partir de 0 (un `sortOrder` négatif hérité du composeur ferait remonter
      une ligne déplacée à sa place d'origine au prochain rendu).
- [ ] **Étape 4 — `swift build` puis `swift test --filter ActionsTableCommandsTests`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): commandes clavier pures du tableau d'actions`.

---

## Task 2 — Étiquettes de frise sans chevauchement

**Fichiers :** Créer `OneToOne/Services/Meeting/TimelineLabelLayout.swift` ·
Test `Tests/TimelineLabelLayoutTests.swift`

**Interfaces produites :**

```swift
enum TimelineLabelLayout {
    struct Candidat: Equatable { var t: Double; var texte: String; var estDecision: Bool }
    struct Etiquette: Equatable, Identifiable {
        var id: Int          // index dans les candidats
        var texte: String
        var estDecision: Bool
        var centre: CGFloat  // x du centre, borné à l'intérieur de la piste
        var largeur: CGFloat
    }
    static let espacement: CGFloat = 6
    static func largeur(_ texte: String) -> CGFloat
    static func placer(_ candidats: [Candidat], duration: Double, width: CGFloat) -> [Etiquette]
}
```

- [ ] **Étape 1 — écrire la suite qui échoue.** Cas : deux marqueurs proches
      (`252 s` et `468 s` sur 1 404 s / 300 px) → **une seule** étiquette, la
      première ; les mêmes sur 1 200 px → deux, et les cadres ne se recouvrent
      pas (`centre − largeur/2 ≥ précédent.centre + précédent.largeur/2 +
      espacement`) ; une étiquette de bord est **rentrée** dans la piste
      (`centre − largeur/2 ≥ 0`, `centre + largeur/2 ≤ width`) ; `duration == 0`
      ou `width == 0` rend `[]` (jamais de `NaN`) ; candidats non triés → sortie
      triée par `t`. Un test dédié : sur les quatre notes du jeu de démo
      (252, 468, 663, 920) et 1 200 px, les étiquettes retenues sont `04:12`,
      `DÉCISION` et `15:20` — celles de la capture.
- [ ] **Étape 2 — `swift test --filter TimelineLabelLayoutTests`** : échoue.
- [ ] **Étape 3 — implémenter.** Largeur estimée depuis Plex Mono 9,5 px
      (`5.9` px/caractère + 12 px de padding), gloutonne de gauche à droite :
      une étiquette qui n'entre pas est **abandonnée**, pas décalée — décalée,
      elle ne désignerait plus son marqueur.
- [ ] **Étape 4 — `swift build` + `swift test --filter TimelineLabelLayoutTests`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): placement pur des étiquettes de frise`.

---

## Task 3 — `ReviewState` et la bascule post-rapport

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/ReviewState.swift` ·
Modifier `OneToOne/Views/Meeting/MeetingScreenModel.swift` (une ligne) ·
Test `Tests/ReviewStateTests.swift`

**Interfaces produites :**

```swift
@MainActor @Observable final class ReviewState {
    enum Section: String, CaseIterable, Sendable {
        case synthese, notes, transcription, actions, rapport, documents, assistant
    }
    enum Cible: Equatable, Sendable { case responsablePremiereActionNonAssignee }
    struct DemandeDeFocus: Equatable, Sendable { var cible: Cible; var jeton: Int }

    var section: Section = .synthese
    var toutAfficher = false
    var vue: ActionsViewMode = .liste          // Tableau (liste) · Eisenhower · Calendrier
    var ligneSelectionnee: PersistentIdentifier?
    private(set) var focusRequest: DemandeDeFocus?
    func demanderFocus(_ cible: Cible)         // incrémente le jeton
    func focusServi()                          // remet à nil
    static func apresGenerationDuRapport(_ screen: MeetingScreenModel)
}
```

- [ ] **Étape 1 — écrire la suite qui échoue.** Cas : `demanderFocus` deux fois
      de suite change le `jeton` (deux demandes identiques doivent toutes deux
      être servies) ; `focusServi` remet `focusRequest` à `nil` ;
      `apresGenerationDuRapport` pose `space == .meeting`, `mode == .review`,
      `section == .synthese` et une demande de focus sur
      `.responsablePremiereActionNonAssignee` ; un `MeetingScreenModel` neuf a
      un `review` non nil et `focusRequest == nil`.
- [ ] **Étape 2 — `swift test --filter ReviewStateTests`** : échoue.
- [ ] **Étape 3 — implémenter** `ReviewState`, puis ajouter **une seule ligne** en
      fin de `MeetingScreenModel` :
      `/// L'état d'écran du mode Relire (lot 5).` + `var review = ReviewState()`.
- [ ] **Étape 4 — `swift build` + `swift test --filter "ReviewStateTests"` puis
      `--filter MeetingScreenModelTests`** : vert (aucune régression du modèle).
- [ ] **Étape 5 — commit** `feat(refonte): état d'écran du mode Relire`.

---

## Task 4 — Nav latérale 190 px

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/ReviewSidebarNav.swift` ·
Test `Tests/ReviewSidebarNavTests.swift`

**Interfaces produites :**

```swift
struct ReviewSidebarNav: View {
    struct Entree: Identifiable, Equatable {
        enum Complement: Equatable {
            case compte(Int)        // « 5 », « 12 »
            case minutes(Int)       // « 23′ »
            case etat(String)       // « ✓ », « — », « ⌘K », « généré »
            case invite             // « ＋ » (Documents vide)
        }
        var section: ReviewState.Section
        var libelle: String
        var complement: Complement
        var alerte: Bool            // compteur en `accent/report`
        var id: ReviewState.Section { section }
    }
    /// Table **exhaustive** : une entrée par `ReviewState.Section`, jamais sans
    /// compteur ni état (critère n° 1 du chantier 1).
    @MainActor static func entrees(for meeting: Meeting) -> [Entree]
    /// Les trois dernières réunions du même projet, hors celle-ci.
    @MainActor static func dernieresDuProjet(_ meeting: Meeting,
                                             dans historique: [Meeting],
                                             limite: Int = 3) -> [Meeting]
    /// `1 sept. — COSUI hebdo`
    static func libelleReunion(_ meeting: Meeting) -> String
}
```

Paramètres de la vue : `meeting`, `screen: MeetingScreenModel`,
`historique: [Meeting]`, `onOpenMeeting: (PersistentIdentifier) -> Void`,
`onSelect: (ReviewState.Section) -> Void`.

- [ ] **Étape 1 — écrire la suite qui échoue.** Cas : `entrees` couvre
      `ReviewState.Section.allCases` **exactement une fois** (test
      d'exhaustivité) ; **aucune** entrée n'a un `complement` vide — pour
      chaque entrée, le libellé de complément rendu par une fonction
      `texte(_ complement:)` est non vide ; `Notes` porte le nombre de
      `meeting.timedNotes` ; `Transcription` porte
      `Int((duration / 60).rounded())` minutes ; `Actions` porte
      `meeting.tasks.count` et `alerte == true` dès qu'une action est sans
      responsable ; `Rapport` porte `✓` quand `summary` est non vide et `—`
      sinon ; `Documents` porte `.invite` à zéro pièce jointe et `.compte(n)`
      au-delà ; `dernieresDuProjet` rend au plus 3 réunions du **même** projet,
      antérieures, de la plus récente à la plus ancienne, et jamais la réunion
      courante ; `libelleReunion` rend `1 sept. — COSUI hebdo` (ordinal du
      premier du mois, via `ActionsRailGrouping.dateOrdinale`).
- [ ] **Étape 2 — `swift test --filter ReviewSidebarNavTests`** : échoue.
- [ ] **Étape 3 — implémenter** la table pure puis la vue : largeur
      `One2OneToken.sideNavWidth`, fond `One2OneToken.bgApp`, badge `1:1` +
      `One2One` en tête, libellé de section `SÉANCE`, entrée active en **carte
      blanche** (`surface`, `radiusButton`, bordure `hair` 1 px), bloc `PROJET`
      (nom + réunions cliquables → `onOpenMeeting`), bloc `ALERTES · n` en pied
      (points `ActionsRailRisks.teinte(_:)`, au plus 4 titres puis `+n`).
      `Rapport` et `Documents` changent d'espace (`screen.space = .report` /
      `.resources`), `Assistant` ouvre le dock, les autres posent
      `screen.review.section`.
- [ ] **Étape 4 — `swift build` + `swift test --filter ReviewSidebarNavTests`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): nav latérale 190 px du poste de pilotage`.

---

## Task 5 — En-tête du poste de pilotage

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/ReviewHeader.swift` ·
Test : deux cas ajoutés à `Tests/ReviewSidebarNavTests.swift` (même suite, même
sujet : les libellés de l'écran).

**Interfaces produites :**

```swift
struct ReviewHeader: View {
    /// `P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants`
    static func metadonnees(for meeting: Meeting, locale: Locale = .current) -> String
    /// `Rapport ✓ 6:20`, `Rapport`, `Transcrire + Rapport` — même règle que
    /// `MeetingTopChromeBar`.
    static func libelleRapport(for meeting: Meeting) -> String
    /// `Capture`, `Capture 4`
    static func libelleCapture(count: Int) -> String
}
```

- [ ] **Étape 1 — écrire les cas qui échouent.** `metadonnees` sur le jeu de
      démo rend exactement
      `P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants`
      (locale `fr_FR`, `Europe/Paris`) ; sans projet, le segment de référence
      **disparaît** sans laisser de `·` orphelin. `libelleRapport` :
      transcription vide → `Transcrire + Rapport` ; transcription pleine et
      `summary` vide → `Rapport` ; `summary` plein et
      `reportGenerationDurationSeconds == 380` → `Rapport ✓ 6:20`.
- [ ] **Étape 2 — `swift test --filter ReviewSidebarNavTests`** : échoue.
- [ ] **Étape 3 — implémenter** la vue : titre `plexSans(14, .semibold)` sur une
      ligne, ligne de métadonnées `plexSans(11.5)` `ink4`, à droite `Capture`
      (bouton neutre → `onShowCaptures`), `Exporter ⌄` (Menu qui reprend les
      entrées d'export de `MeetingMenuActions`, désactivé sans rapport),
      `Rapport ✓ (m:ss)` (bouton plein `report` → `menuActions.generateReport`),
      et **au-dessus**, aligné à droite, le `SegmentedMode` `Préparer / En séance
      / Relire` (le sélecteur reste accessible, la barre d'espaces étant masquée
      en Relire).
- [ ] **Étape 4 — `swift build` + `swift test --filter ReviewSidebarNavTests`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): en-tête du mode Relire`.

---

## Task 6 — Cartes `EN UNE PHRASE` et `DÉCISIONS PRISES`

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/OneSentenceCard.swift`,
`OneToOne/Views/Meeting/Spaces/Review/DecisionsCard.swift` ·
Test `Tests/ReviewCardsInviteTests.swift`

**Interfaces produites :**

```swift
struct OneSentenceCard: View { /* meeting, settings, isSummarizing, onSummarize */ }

struct DecisionsCard: View {
    struct Ligne: Identifiable, Equatable {
        var id: PersistentIdentifier
        var t: Double
        var texte: String
        var porteur: String?
    }
    /// Les notes `kind: .decision` triées par `t`, porteur détaché.
    @MainActor static func lignes(for meeting: Meeting) -> [Ligne]
    /// « Le partenaire finalise la migration — Olivier Freund »
    ///   → (texte, « Olivier Freund »)
    static func separerPorteur(_ texte: String) -> (texte: String, porteur: String?)
}
```

- [ ] **Étape 1 — écrire la suite qui échoue.** `separerPorteur` : tiret cadratin
      final suivi d'un nom de 1 à 4 mots capitalisés → porteur détaché, texte
      nettoyé ; un tiret **au milieu** de la phrase n'est pas un porteur ; un
      segment final en minuscules (« — à confirmer ») n'est pas un porteur ; une
      parenthèse finale (« (Olivier Freund) ») est aussi acceptée, la forme du
      jeu de démo du lot 3. `lignes` trie par `t` croissant et ne retient que
      `.decision`. Puis un test « aucune zone vide sans invite » (critère n° 1)
      qui **lit les sources** de `Views/Meeting/Spaces/Review/` : chaque fichier
      de carte qui teste un `isEmpty` contient une `MeetingEmptyInvite` — et un
      premier test vérifie que le dossier lu est bien celui du mode Relire, sans
      quoi les autres ne prouveraient rien en passant.
- [ ] **Étape 2 — `swift test --filter ReviewCardsInviteTests`** : échoue.
- [ ] **Étape 3 — implémenter.** `OneSentenceCard` : libellé `EN UNE PHRASE`,
      `Chip("généré", ton: .action)` quand `shortSummary` est non vide, corps en
      `MarkdownText` (le résumé porte du gras dans la capture), `Chip` par
      `MeetingTag`, invite « Générer la synthèse » appelant
      `SummaryCard.generate(meeting:settings:)` sinon. `DecisionsCard` :
      `DÉCISIONS PRISES · n`, timecode `plexMono(10)` `report` cliquable →
      `onSeek`, texte `ink2`, porteur `ink4` précédé d'un tiret cadratin, invite
      si vide.
- [ ] **Étape 4 — `swift build` + `swift test --filter ReviewCardsInviteTests`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): cartes Synthèse et Décisions du mode Relire`.

---

## Task 7 — Tableau d'actions dense

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/ActionsTable.swift` ·
Test : cas ajoutés à `Tests/ActionsTableCommandsTests.swift` (largeurs de
colonnes) et `Tests/ReviewCardsInviteTests.swift` (invite du tableau vide).

**Interfaces produites :**

```swift
struct ActionsTable: View {
    /// `20 | 1fr | 108 | 92 | 62 | 76 | 30` (spec §2.7).
    static let colonnes: (etat: CGFloat, responsable: CGFloat, echeance: CGFloat,
                          charge: CGFloat, source: CGFloat, menu: CGFloat)
    static let lignesRepliees = 5
}
```

- [ ] **Étape 1 — écrire les cas qui échouent.** Les six largeurs fixes valent
      exactement `20, 108, 92, 62, 76, 30` (une colonne rognée ne se voit dans
      aucun test de rendu) ; `lignesRepliees == 5` ; l'invite du tableau vide est
      présente dans le fichier (garde de sources de la Task 6).
- [ ] **Étape 2 — `swift test --filter "ActionsTableCommandsTests|ReviewCardsInviteTests"`** : échoue.
- [ ] **Étape 3 — implémenter.** En-tête de carte : `Actions`, badge
      `n sans responsable` en `report`, `SegmentedMode` sur
      `ActionsViewMode.railCases` **libellé `Tableau · Eisenhower · Calendrier`**
      (`liste` → « Tableau » dans ce mode), bouton `＋ Action` plein `action`.
      En vue Tableau : ligne d'en-tête mono `INTITULÉ RESPONSABLE ÉCHÉANCE CHARGE
      SOURCE`, lignes alternées `surface` / `surfaceAlt`, `tableRowPaddingV`,
      cellules réemployant `ActionCardEditing` (`libelleResponsable`,
      `libelleEcheance`, `chargeLabel`, `libelleSource`) et `InvitePill` pour
      `＋ assigner` / `＋ date` ; `Urgent` en `report` à la place de l'échéance
      quand `isUrgent && dueDate == nil` ; `Reporté ×n` depuis `deferralCount` ;
      `⋯` en menu (marquer faite, abandonner, reporter, supprimer). Édition
      inline : un clic sur une cellule déplie **sous la ligne** le sélecteur du
      lot 3 (`OwnerPickerMenu`, `DatePicker` compact + raccourcis, charges) —
      jamais de modale. Clavier sur la carte : `↑↓` → `indexSuivant`, `Espace` →
      bascule `isCompleted`, `⌥↑↓` → `permutation` + `appliquerOrdre` + `save`.
      `.onChange(of: screen.review.focusRequest)` : sélectionne
      `premiereSansResponsable` et déplie sa cellule de responsable, puis
      `focusServi()`. Pied : `ActionComposer` réemployé tel quel, et à droite
      `n autres · tout afficher` basculant `screen.review.toutAfficher`. Les vues
      Eisenhower et Calendrier réemploient `EisenhowerBoard`/`CalendarBoard` en
      `compact: true`.
- [ ] **Étape 4 — `swift build` + `swift test --filter "ActionsTableCommandsTests|ReviewCardsInviteTests"`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): tableau d'actions dense du mode Relire`.

---

## Task 8 — Frise audio étiquetée pleine largeur

**Fichiers :** Créer `OneToOne/Views/Meeting/Spaces/Review/ReviewAudioTimeline.swift` ·
Modifier `OneToOne/Views/Meeting/Spaces/AudioTimelineStrip.swift` ·
Test : cas ajouté à `Tests/TimelineLabelLayoutTests.swift`

**Interfaces produites :**

```swift
struct AudioTimelineStrip: View {
    /// Bande d'étiquettes au-dessus des marqueurs (spec §2.7). Défaut `false` :
    /// le rendu du lot 2 est inchangé.
    var labelled: Bool = false
    /// Hauteur totale, étiquettes comprises.
    static func hauteur(labelled: Bool) -> CGFloat
    /// Les candidats d'étiquette d'une réunion, dans l'ordre du temps.
    @MainActor static func candidats(_ markers: [MeetingPlayhead.Marker]) -> [TimelineLabelLayout.Candidat]
}

struct ReviewAudioTimeline: View { /* meeting, screen, menuActions */ }
```

- [ ] **Étape 1 — écrire les cas qui échouent.** `AudioTimelineStrip.hauteur(labelled: false)`
      vaut `AudioTimelineGeometry.height + 12` (inchangé) et
      `hauteur(labelled: true)` est strictement plus grande ; `candidats` rend
      `DÉCISION` pour un marqueur `.decision` et le timecode `mm:ss` pour les
      autres, et **ignore** les marqueurs `.capture` (la capture a son propre
      carré, une étiquette de plus saturerait la frise).
- [ ] **Étape 2 — `swift test --filter TimelineLabelLayoutTests`** : échoue.
- [ ] **Étape 3 — implémenter.** Dans `AudioTimelineStrip`, ajouter la propriété
      `labelled` avec valeur par défaut et, quand elle est vraie, un `Canvas`
      d'étiquettes au-dessus de la piste (fond `actionBg` / `reportBg`, encre
      `actionInk` / `reportInk`, `plexMono(9.5)`), positionné par
      `TimelineLabelLayout.placer`. `ReviewAudioTimeline` : bouton `▶` rond
      (`ink1`, `onFilledButton`) qui charge `meeting.wavFileURL` dans
      `playhead.player`, appelle `beginPlayback()` puis `toggle()` ; `00:00` à
      gauche, la frise étiquetée au centre, la durée à droite, et
      `✂ Éditer` → `menuActions.editAudio()` (désactivé sans audio relisible).
- [ ] **Étape 4 — `swift build` + `swift test --filter "TimelineLabelLayoutTests|AudioTimelineGeometryTests|MeetingTimelineMarkersTests"`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): frise audio étiquetée du mode Relire`.

---

## Task 9 — Recomposition de `MeetingReviewSpace` et routage

**Fichiers :** Modifier `OneToOne/Views/Meeting/Spaces/MeetingReviewSpace.swift`,
`OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift`,
`OneToOne/Views/Meeting/Spaces/MeetingSpacesBar.swift`,
`OneToOne/Views/MeetingView.swift` · Test : cas ajoutés à
`Tests/ReviewStateTests.swift`

- [ ] **Étape 1 — écrire les cas qui échouent.**
      `MeetingSpacesBar.estMasquee(space: .meeting, mode: .review) == true` ;
      fausse pour les autres couples (`.report`/`.review`,
      `.meeting`/`.live`, `.meeting`/`.prepare`) — sinon on se retrouverait
      dans l'espace Rapport sans barre pour en sortir. Et un test de sources sur
      `MeetingView.swift` : plus aucune occurrence de `screen.space = .report`
      dans le chemin post-génération de `generateReport`, remplacée par
      `ReviewState.apresGenerationDuRapport`.
- [ ] **Étape 2 — `swift test --filter ReviewStateTests`** : échoue.
- [ ] **Étape 3 — implémenter.** `MeetingReviewSpace` devient non générique :
      `HStack(spacing: 0) { ReviewSidebarNav ; filet ; colonne principale }`, la
      colonne principale empilant `ReviewHeader`, un `ScrollView`
      (`OneSentenceCard` + `DecisionsCard` côte à côte en `HStack`, puis
      `ActionsTable`) avec ancres de défilement par section
      (`.id(ReviewState.Section…)` + `ScrollViewReader` piloté par
      `screen.review.section`), `MeetingAssistantDock`, puis
      `ReviewAudioTimeline` en pied. `MeetingSpaceView` : le mode Relire sort du
      `switch` et prend toute la surface (ni bandeau KPI, ni rail, ni dock
      injecté), avec deux paramètres ajoutés (`menuActions`, `onShowCaptures`).
      `MeetingSpacesBar` : `estMasquee` + garde de corps. `MeetingView` : la
      ligne post-génération et les deux paramètres du call-site.
- [ ] **Étape 4 — `swift build` + `swift test --filter "ReviewStateTests|MeetingVisibleSectionsTests|MeetingScreenModelTests"`** : vert.
- [ ] **Étape 5 — commit** `feat(refonte): recomposer le mode Relire autour du poste de pilotage`.

---

## Task 10 — Jeu de démonstration du lot

**Fichiers :** Créer `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot5.swift` ·
Test `Tests/RefonteDemoSeedLot5Tests.swift`

**Interfaces produites :**

```swift
extension RefonteDemoSeed {
    static let decisionsHorodatees: [(t: Double, texte: String)]  // 11:03, 13:40, 20:15
    static let tags: [String]        // Migration AP, Facturation, GitLab / CI-CD, Ressources
    static let reunionsPrecedentes: [(titre: String, jours: Int)]  // 31 août, 26 août
    /// Complète le semis du lot 3 pour la capture 1c. Idempotent.
    @discardableResult static func seedLot5(in context: ModelContext) -> Meeting
}
```

- [ ] **Étape 1 — écrire la suite qui échoue.** Après `seedLot5` : la réunion
      porte **3** notes `kind: .decision` aux timecodes `663`, `820`, `1215` ;
      `DecisionsCard.lignes` en rend trois, la première portant
      `porteur == "Olivier Freund"` ; `meeting.tags.count == 4` et leurs noms
      sont ceux de la capture ; `ReviewSidebarNav.dernieresDuProjet` en rend
      **3** (`1 sept. — COSUI hebdo`, `31 août — Gouvernance`,
      `26 août — Situation AP`) ; `shortSummary` est celui de la capture ;
      `ReviewHeader.metadonnees` rend la ligne de la capture ; un second appel ne
      duplique rien (idempotence).
- [ ] **Étape 2 — `swift test --filter RefonteDemoSeedLot5Tests`** : échoue.
- [ ] **Étape 3 — implémenter** l'extension, **sans toucher**
      `RefonteDemoSeed.swift` : `seedLot5` appelle `seed(in:)` puis complète.
      Câbler l'appel dans le point d'entrée existant du menu de démonstration si
      et seulement si cela ne modifie pas un fichier interdit ; sinon, appeler
      `seedLot5` depuis `seed` est impossible (fichier gelé) et le menu est
      pointé sur `seedLot5` — vérifier quel fichier porte l'item de menu avant
      de choisir.
- [ ] **Étape 4 — `swift build` + `swift test --filter "RefonteDemoSeedLot5Tests|RefonteDemoSeedTests"`** : vert
      (le semis du lot 3 reste intact).
- [ ] **Étape 5 — commit** `feat(refonte): jeu de démonstration du poste de pilotage`.

---

## Task 11 — Vérification, recette, documentation, PR

- [ ] **Étape 1 — `swift build`** : propre (seuls les avertissements
      préexistants `PyannoteDiarizer`, `MLXEmbeddingEngine`,
      `AudioCompressionService`).
- [ ] **Étape 2 — `swift test`** complet : **vert**, ≥ 1 931 tests, aucune
      régression. Consigner les chiffres exacts.
- [ ] **Étape 3 — recette visuelle.**
      `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` :
      - `Yes` → documenter l'impossibilité dans `STATUS.md` (comme aux lots 1–3),
        ne rien déposer dans `recette/`.
      - `No` → empaqueter avec `package-recette.sh` / `run-recette.sh` du
        scratchpad (adapter `WT`, HOME temporaire), semer le jeu de démo, passer
        en mode Relire, `screencapture -x` vers
        `docs/superpowers/specs/refonte-2026-09/recette/lot-5-{1280,1920}.png`,
        comparer à `ecrans/1c-poste-de-pilotage.png`, lister les écarts.
- [ ] **Étape 4 — `STATUS.md`** : section du lot 5 **en tête**, avec ce qui est en
      place, les fichiers créés, les chiffres de test, les écarts assumés et la
      prochaine action. Date du jour.
- [ ] **Étape 5 — commit** `docs(status): consigner le lot 5`, `git push -u`,
      puis `gh pr create --base feat/refonte-lot-3-rail-actions --title
      "feat(refonte): lot 5 — poste de pilotage (mode Relire)"` avec, en corps,
      les critères d'acceptation cochés, les chiffres de `swift test`, l'état de
      la recette et l'ordre de fusion `#19 → … → #24 → cette PR`. **Ne pas
      fusionner.**

---

## Auto-revue

**Couverture de la spec §2.7** — nav latérale à compteurs (Task 4) ; en-tête et
métadonnées (Task 5) ; `EN UNE PHRASE` et `DÉCISIONS PRISES` (Task 6) ; tableau
`20 | 1fr | 108 | 92 | 62 | 76 | 30`, édition inline, `↑↓`, `Espace`, `⌥↑↓`,
source `mm:ss ↗`, pied composeur + `n autres` (Tasks 1 et 7) ; frise étiquetée et
`✂ Éditer` (Tasks 2 et 8) ; bascule automatique en Relire et focus
d'assignation (Tasks 3 et 9) ; jeu de démo (Task 10).

**Critères du lot** — navigation clavier : Task 1 ; étiquettes sans
chevauchement : Task 2 ; exhaustivité des compteurs de nav : Task 4 ; bascule et
focus : Tasks 3 et 9 ; « aucune zone vide sans invite » : Task 6 (garde de
sources) ; suites existantes vertes : Task 11.

**Cohérence des types** — `ReviewState.Section` est l'identité des entrées de nav
(Task 4) *et* l'ancre de défilement (Task 9) ; `TimelineLabelLayout.Candidat` est
produit par `AudioTimelineStrip.candidats` (Task 8) et consommé par `placer`
(Task 2) ; `ActionsTableCommands.premiereSansResponsable` (Task 1) est consommé
par le focus du tableau (Task 7) ; `ActionsViewMode.railCases` (lot 3) sert le
sélecteur `Tableau · Eisenhower · Calendrier` (Task 7).
