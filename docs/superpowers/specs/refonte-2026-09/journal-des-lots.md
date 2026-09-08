# Journal des lots — refonte de l'écran de réunion (2026-09)

Les comptes rendus de session des lots 0A à 19a, déplacés de `STATUS.md` par le lot 19c :
4 460 lignes et vingt-neuf sections qui rendaient `STATUS.md` illisible. **Texte inchangé**,
ordre chronologique (le plus ancien d'abord), là où `STATUS.md` les empilait du plus récent au
plus ancien.

Ce qui reste dans `STATUS.md` : la synthèse, la pile de fusion, les décisions en attente, les
dettes et la prochaine action — section « Refonte de l'écran de réunion — état au 2026-09-08 ».

- Spécification : `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` (branche
  `docs/refonte-reunion-programme`).
- Plan directeur et décisions D0–D11 :
  `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`, §4 et §5.
- Bilan : `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`.
- Recette des vagues 1 à 4 :
  `docs/superpowers/specs/refonte-2026-09/recette/2026-09-07-recette-vagues-1-4.md`.

---

## Refonte de l'écran de réunion — lot 0B : schéma V3, tête de lecture, confidentialité (2026-09-07)

Branche `feat/refonte-lot-0b-socle-donnees`, sur `master` (`a3c44f2`). Premier lot de données du
programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (§5 « Lot 0B ») ;
plan du lot dans `docs/superpowers/plans/2026-09-07-refonte-lot-0b-socle-donnees.md`. Le lot 0A
tourne en parallèle sur le socle visuel — `MeetingView.swift` n'est touché ici qu'en trois
endroits (le lecteur audio, `recordingStartedAt`, l'appel d'import des notes).

**État : livré, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

- **`Models/SchemaVersions.swift`** : `SchemaV3` (3.0.0), `CurrentSchema` pointe dessus,
  `schemas` à trois versions. `stages` reste **vide** : V2→V3 n'ajoute que des tables et des
  colonnes à valeur par défaut, donc lightweight migration automatique — même convention que
  V1→V2, raisonnement documenté dans le plan de migration.
- **Neuf `@Model` nouveaux** (tables vides, coût nul) : `MeetingNote` (D1 — notes horodatées
  adressables : `t`, `text`, `kindRaw` parmi note/décision/risque/feedback/promesse/demande/preuve,
  `visibilityRaw`, `authorSideRaw`, `sourceRef`, `orderIndex`), `Board` (D5/D6 — scène et vignette
  **sur disque**, la base ne garde que les chemins), `ProjectMilestone` et `ProjectContact`
  (fiche projet ; les risques restent les `ProjectAlert` existants), et le domaine 1:1 (D3) :
  `OneOnOneThread` + `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`, `OneOnOneObjective` en
  cascade depuis le fil. Tous avec `stableID: UUID?` + `ensuredStableID`, énums en `…Raw`.
- **Colonnes ajoutées** : `ActionTask` (`priorityRaw`/`statusRaw` en **miroirs requêtables** de
  `isUrgent`/`isCompleted` qui restent la source de vérité, `dropped` n'existant que dans la
  colonne ; `effortMinutes`, trois colonnes de source, `deferralCount`, `carriedFromMeeting`),
  `MeetingAttachment` (`scopeRaw`, `mimeType`, `byteCount`, `addedByName`, `pinnedAtT`,
  `citationCount`), `SlideCapture` (`t` sur l'axe **audio**, `sourceRaw`, `triggerRaw`),
  `Project` (`scopeText`, `tagsJSON` + façade `tags`, relations `milestones`/`contacts`),
  `Meeting` (`recordingStartedAt`, `notesMigrated`, relations `timedNotes`/`boards`).
- **`MeetingKind.workshop`** (« Atelier »), mappé vers le gabarit `.workshop` dans
  `compatibleTemplates` et `AIReportService.defaultTemplate`. Les six valeurs brutes historiques
  sont inchangées (test de garde).
- **`Models/SourceRef.swift`** : `SourceRef {kind, stableID, t}` + protocole `SourceRefCarrying`
  portant l'accesseur `sourceRef` au-dessus de trois colonnes plates (requêtables par
  `#Predicate`, contrairement à un JSON), adopté par `ActionTask` et `MeetingNote`.
- **`Services/Live/MeetingPlayhead.swift`** : `@Observable @MainActor`, une instance par réunion,
  propriétaire de l'**unique** `AudioPlayerService` (il était instancié deux fois, sans position
  commune). `t` depuis `recordingStartedAt` en séance (horloge injectable) ou depuis le lecteur en
  relecture, `duration`, `isPlaying`, `follow`, `markers` triés, `seek` borné,
  `marker(at:tolerance:)`, `mmss`. `MeetingView` et `AudioWaveformEditor`
  (via `AudioEditorSheet`) le consomment ; comportement visible inchangé.
- **`Services/ConfidentialityFilter.swift`** : `Audience`, `Visibility`, protocole `Confidential`
  (adopté par `MeetingNote`, `Commitment`, `OneOnOneAgendaItem`), `isExportable(_:for:)` en table
  exhaustive sans `default`, `isIndexable` et `audience(for kind:)`.
- **`Services/MeetingNoteStore.swift`** : fonctions pures (`sorted`, `filtered`, `grouped`,
  `exportable`, `indexable`, `markdown`, `contextBlock`, `defaultVisibility`) et
  `importLiveNotesIfNeeded` — reprise unique de `liveNotes` en une note `t = 0` (drapeau
  `notesMigrated`, `liveNotes` **conservé**), branchée au `onAppear` de `MeetingView`.
- **Les cinq lecteurs de texte filtrés** : prompt de rapport
  (`AIReportService.assembleTemplatePrompt`, couture extraite pour être vérifiable sans réseau),
  HTML (`ReportHTMLBuilder`, bloc « Notes de séance »), export markdown (`ExportService`),
  index RAG (`RAGIndexer.sourceText`, couture pure sans embedding — filtrage **à l'écriture** de
  l'index), contexte des deux chats (`MeetingChatView.makePrompt`,
  `ChatbotView.meetingNotesContext`). `Meeting.textualContent` déclare les notes horodatées et
  `NoteFactory.isDiscardableEmptyNote` les retient.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 037 XCTest (1 ignoré, 0 échec) + 664 Swift Testing dans 102 suites, 0 échec** — soit
+46 tests et +7 suites par rapport à la référence du 2026-09-06 (618 / 95). Nouvelles suites :
`SchemaV3MigrationTests` (6), `MeetingPlayheadTests` (9), `MeetingNoteStoreTests` (12),
`ConfidentialityFilterTests` (6) + `SourceRefTests` (3) + `NotePriveeHorsDesCinqFluxTests` (8),
`MeetingKindWorkshopTests` (2).

**Migration vérifiée sur une copie du store de production** (32 Mo, hors suite de tests, script
temporaire supprimé) : ouverture avec `CurrentSchema` + `OneToOneMigrationPlan` sans erreur, les
neuf tables `ZMEETINGNOTE`/`ZBOARD`/`ZCOMMITMENT`/`ZONEONONE*`/`ZMOODENTRY`/`ZPROJECTMILESTONE`/
`ZPROJECTCONTACT` créées, comptages **identiques** avant/après (189 réunions, 420 actions,
63 projets, 34 pièces jointes, 372 collaborateurs, 3 793 chunks) et tous les nouveaux champs à
leur défaut.

### Écarts assumés

1. **Registre du playhead à références fortes, borné LRU à 4** au lieu du cache faible prévu au
   plan : un cache faible se viderait aussitôt, `MeetingView` étant une `struct` qui ne peut
   retenir l'instance sans initialiseur explicite — et ce fichier est réécrit en parallèle par le
   lot 0A. L'éviction met le lecteur en pause. À revoir au lot 1, quand `MeetingScreenModel`
   pourra porter la tête de lecture.
2. **Test de migration sans snapshot *nested* de V2** : les types Swift sont partagés entre
   `SchemaV1/V2/V3` (aucun snapshot nested n'a jamais été écrit dans ce dépôt, cf. l'en-tête de
   `SchemaVersions.swift`), donc écrire le store avec `SchemaV2` crée déjà les colonnes de V3. La
   suite vérifie ce qui reste vérifiable (réouverture sans perte, défauts sur des lignes créées
   avant les champs) ; la preuve réelle est la vérification sur la copie du store de production
   ci-dessus.
3. **`BackupService` n'exporte pas les neuf nouvelles tables** : ses DTO sont manuels et le lot
   aurait dérivé. Sans conséquence aujourd'hui (tables vides) ; à traiter au lot où elles se
   remplissent (lot 9 pour la fiche projet, lot 10 pour le 1:1, lot 16 pour les planches), en
   même temps que `StorageStatsService`/`OrphanCleanupService` pour les dossiers `boards/`.
4. **Aucune vue ne lit encore les nouvelles données** : c'est le propos du lot (socle). Rien n'est
   donc visible à l'écran, aucune recette visuelle n'a été faite.
5. `MoodEntry` et `OneOnOneObjective` bornent leur valeur à la construction **et** exposent
   `clampedValue`/`clampedProgress` : la colonne brute reste lisible pour une restauration.

### Prochaine action

**Lot 1** — chantier 1 socle : barre du haut sur une ligne, trois espaces, sélecteur de mode,
bandeau KPI (`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5, lot 1). Il
dépend des lots 0A et 0B, tous deux livrés. Fusionner d'abord les deux PR de socle.

## Refonte de l'écran de réunion — lot 0A : socle visuel et état d'écran (2026-09-07)

Branche `feat/refonte-lot-0a-socle-visuel`, partie de `origin/master` (`a3c44f2`). Premier lot
du programme `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (§5) ; plan
d'exécution dans `docs/superpowers/plans/2026-09-07-refonte-lot-0a-socle-visuel.md`. Lot
**invisible** par construction : rien ne change à l'écran, et aucune vue existante n'utilise
encore les primitives livrées. Le lot 0B tourne en parallèle sur les modèles et les services ;
aucun fichier commun.

### Créés

- **`OneToOne/Views/DesignSystem/One2OneTokens.swift`** : `enum One2OneToken`, copie de
  `Teams-Capture/Sources/CaptureDesign/Tokens.swift` (règle du programme : copier, jamais
  lier), complétée de la **palette `dark/*` complète** du mode séance (`darkBase #1c1a17`,
  `darkTranscript #191714`, `darkCard #221f1b`, `darkCardActive #232019`, `darkPill #2f2b26`,
  `darkInk1…4`, `darkAction #9ab6f0`, **`darkReport #e8b0aa`**, `darkWarn #e8c48a`) et des
  **largeurs fixes** de la spec §1.2 (330 / 320 / 356 / 190 / 52 / 78 / 430 / 396 / 400), plus
  rayons et densités. `Color(hex:)` y est **privé au fichier** : c'est ce qui rend vérifiable
  la règle « seul ce fichier nomme une couleur de la refonte ». `AppTheme`, `MeetingTheme` et
  `FicheTokens` restent en place pour les écrans non refondus.
- **`OneToOne/Views/DesignSystem/ContrastRatio.swift`** : luminance relative et ratio WCAG 2.1
  (fonctions pures, `NSColor.usingColorSpace(.sRGB)`, aucune session graphique). Rend `nil`
  sur une couleur inconvertible plutôt qu'un contraste imaginaire.
- **`OneToOne/Views/DesignSystem/One2OneTypography.swift`** : `PlexWeight`, `PlexFont`,
  `Font.plexSans/plexMono`, `View.sectionLabel()`. Copie de `Typography.swift` de
  Teams-Capture — **noms PostScript abrégés** `IBMPlexSans-Medm` / `-SmBld`, jamais
  `-Medium` / `-SemiBold`, jamais `.weight()` par-dessus — augmentée de l'enregistrement des
  fontes embarquées par `CTFontManagerRegisterFontsForURL` en portée `.process`
  (`static let` = une fois par process), déclenché à la fois par `PlexFont.isInstalled` et
  explicitement au lancement. Localisation calquée sur `MermaidResourceLocator` :
  `Bundle.module`, puis `Contents/Resources/OneToOne_OneToOne.bundle` du `.app` packagé.
  Repli `Font.system` conservé.
- **`OneToOne/Resources/Fonts/`** : IBM Plex Sans 400/500/600 et Plex Mono 500/600 en `.ttf`
  (v3.005, téléchargés du dépôt officiel `IBM/plex`, ~950 Ko au total) + `OFL.txt` (texte de
  la SIL Open Font License 1.1 copié à côté des fichiers). Vérifié : les cinq fichiers
  portent bien les noms PostScript **abrégés** — c'est la condition de tout le reste, une
  version ≥ 6 de Plex utiliserait les noms longs et casserait la résolution en silence.
  `.process("Resources")` aplatit `Fonts/` à la racine du bundle (constaté dans
  `.build/debug/OneToOne_OneToOne.bundle`), d'où la double recherche.
- **`OneToOne/Views/DesignSystem/One2OneTheme.swift`** : `One2OneTheme` (`.paper` / `.session`),
  `One2OneColors` (couleurs résolues : fond, canevas, carte, carte active, pilule, quatre
  encres, quatre accents, deux filets), clé et accesseur `EnvironmentValues.one2OneTheme`
  (défaut `.paper`) et modificateur `View.one2OneTheme(_:)`. Le mode séance est un thème
  **local** : le `.preferredColorScheme(.light)` épinglé sur les trois `WindowGroup` de
  `OneToOneApp` n'est pas touché.
- **`OneToOne/Views/DesignSystem/Components/Refonte/`** : les dix primitives, un `#Preview`
  chacune (papier et séance quand la primitive suit le thème) — `SectionLabel`, `MonoMeta`,
  `TimecodeLabel` (+ `format(_:)` pure), `Chip` (+ `ChipTon`), `Pill`, `InvitePill`
  (+ `Etat`), `RefonteCard`, `AvatarStack` (+ `layout(noms:maxVisibles:)` pure), `ProgressBar`
  (+ `clamp(_:)` pure), `SegmentedMode` (générique).
- **`OneToOne/Views/Meeting/MeetingScreenModel.swift`** : `@Observable` `@MainActor`. `space`
  (`meeting`/`report`/`resources`) et `mode` (`prepare`/`live`/`review`) **mémorisés par
  réunion** dans `UserDefaults` (clés `onetoone.meetingScreen.{space,mode}.<stableID>`,
  `UserDefaults` injectable) ; brouillon d'action, `showSpeakers`, `showPlayback`, `follow`,
  `newAdhocName`, `suggestedTagNames` non persistés. `attach(meetingID:)` idempotent (relire
  sur un second `.onAppear` écraserait le choix que l'utilisateur vient de faire) ; aucune
  écriture avant rattachement.

### Modifiés

- **`OneToOne/Views/MeetingView.swift`** : treize `@State` retirés au profit de
  `@State private var screen = MeetingScreenModel()`, rattaché en tête de `.onAppear`.
  `addTask()` appelle `screen.resetActionDraft()` (six remises à zéro en une).
  `activeSection` **reste** un `@State` (les espaces arrivent au lot 1). Les chemins
  `adoptPendingLiveNotes()` / `discardEmptyNoteIfNeeded()` ne sont pas touchés.
- **`OverviewDashboard.swift`**, **`ActionsPanel.swift`** : les huit `@Binding` du brouillon
  d'action, qui traversaient `OverviewDashboard` sans qu'elle en lise un seul, deviennent un
  `MeetingScreenModel` en paramètre.
- **`MeetingTopChromeBar.swift`** (`suggestedTagNames`), **`ManageParticipantsSheet.swift`**
  (`newAdhocName`) : mêmes remplacements pour leur unique `@Binding` traversant.
  `@Observable` n'ayant pas de projection `$`, les six endroits qui exigent un vrai `Binding`
  (`EditableTextField`, `Toggle`, `TextField`, `iconToggle`, `MeetingTagEditor`) en
  construisent un à la main.
- **`OneToOne/OneToOneApp.swift`** : `PlexFont.ensureRegistered()` en première ligne de
  `init()`. Un enregistrement tardif ferait clignoter la typographie.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet **vert** :
**1 037 XCTest (1 ignoré, 0 échec) + 663 Swift Testing en 100 suites (0 échec)**, soit
1 700 tests contre 1 655 avant le lot (+45, +5 suites) et **aucune régression**. Les suites
que le programme §8 désigne comme garde-fous de `MeetingView` (`NoteFactoryTests`,
`PendingEditorTextTests`, `MeetingScreenRegistryTests`) sont vertes.

- `Tests/One2OneTokensTests.swift` (8 tests) : calibrage de la mesure (noir sur blanc = 21:1),
  **25 paires texte/fond** employées sous 12 px vérifiées à ≥ 4,5:1 (13 en palette claire,
  12 en palette séance), largeurs fixes et rayons de la spec §1.2.
- `Tests/One2OneTypographyTests.swift` (6 tests) : les cinq fichiers présents dans le bundle,
  les cinq noms PostScript qui résolvent après enregistrement, le piège des noms longs
  (`IBMPlexSans-SemiBold` et `-Medium` ne résolvent **pas**), la disposition du `.app`
  packagé, le repli sur un nom inconnu.
- `Tests/One2OneThemeTests.swift` (5 tests) : défaut d'environnement `.paper`, résolution des
  deux palettes sur leurs jetons, contraste du libellé mono ≥ 4,5:1 dans les deux thèmes,
  stabilité des `rawValue`.
- `Tests/One2OnePrimitivesTests.swift` (15 tests) : `mm:ss` toujours (62:03 au-delà d'une
  heure), tronqué et non arrondi, `00:00` sur négatif / `nan` / `infinity` ; états de
  `InvitePill` et tons de `Chip` lisibles sur leur propre fond ; `AvatarStack` — six exactement
  n'affiche pas « +0 », neuf affiche six + « +3 », pile vide muette, géométrie 19 / −6 ;
  `ProgressBar.clamp` bornée, `nan` → 0.
- `Tests/MeetingScreenModelTests.swift` (11 tests) : défauts `meeting`/`live`, mémorisation
  par réunion, cloisonnement entre deux réunions, repli sur valeur mémorisée illisible,
  idempotence d'`attach`, **changer de mode ne touche pas au brouillon** (critère du lot 1,
  figé avant la vue), brouillon non persisté, `resetActionDraft` qui garde le destinataire,
  défauts des bascules identiques aux `@State` retirés, rien d'écrit avant rattachement.

### Écarts assumés

1. **Constat sur la table §1.2 : `ok/deep` (`#2f7d4e`) sur `ok/bg` (`#e8f3ec`) mesure
   4,43:1**, soit 0,07 sous le seuil de 4,5:1 que la spec impose sous 12 px. `accent/ok` ne
   publie que deux encres et celle-ci est la plus profonde : il n'y a pas de couple conforme
   dans la table. Le jeton n'a **pas** été retouché (la table fait foi) ; la mesure est figée
   par un test dédié (`okDeepOnOkBackgroundIsJustBelowThreshold`) pour que l'écart soit connu
   et qu'un futur assombrissement soit une décision explicite. `InvitePill.Etat.renseignee` et
   `ChipTon.ok` emploient ce couple, conformément à la capture 1a (pilule « Sylvain » verte),
   et leurs tests attendent 4,4 en renvoyant à ce constat. **À trancher avec la spec.**
2. L'énumération s'appelle **`One2OneToken`** et non `Token` comme dans Teams-Capture :
   `Token` est trop générique dans un module unique de cette taille, et le nom suit celui du
   fichier imposé par le programme (`One2OneTokens.swift`).
3. **`newAdhocName` et `suggestedTagNames` ont rejoint le modèle** en plus de la liste du
   programme : ce sont les seuls `@Binding` traversants de `ManageParticipantsSheet` et
   `MeetingTopChromeBar`, les deux vues que le lot devait justement libérer. De même,
   `showNewTaskDueDate` et `didApplyActionDefaults` (ex-`didSetActionDefaults`) ont suivi le
   reste du brouillon d'action, dont ils sont indissociables.
4. **`AvatarStack`** et **`RefonteCard`** : noms retenus pour ne pas heurter
   `MeetingAvatarStack` ni les cartes de dashboard existantes, que ce lot ne remplace pas.
5. **`One2OneTheme.session.ok` retombe sur `dark/accent action`** : la palette `dark/*` de la
   spec §1.2 ne publie pas d'encre « tenu », le vert de la palette claire n'est pas lisible sur
   `#1c1a17`, et la capture 1b utilise déjà le bleu clair comme teinte positive (bouton
   `＋ Action`). Les deux filets du thème séance sont des opacités de blanc, nommées dans le
   système de conception et non dans une vue.
6. **Recette à l'écran non faite.** `Scripts/bump-and-build.sh dev` incrémente le numéro de
   build, installe dans `~/Applications` et lance l'app : le faire depuis un worktree
   remplacerait la copie de développement par un build de branche et polluerait la branche
   d'un changement de version. Le lot étant invisible et le vrai risque étant « les fontes ne
   voyagent pas dans le `.app` », ce risque est couvert par un test qui monte la disposition
   réelle du bundle packagé (`Contents/Resources/OneToOne_OneToOne.bundle`, ligne 93 du
   script) dans un dossier temporaire. **Reste à vérifier de visu au lot 1** : le composeur
   d'action du rail, la bascule « Afficher speakers », le dépliage de la barre de lecture,
   l'ajout d'un participant ad hoc et l'affichage des thèmes proposés — les cinq chemins que
   la migration a touchés.
7. Le test « les cinq noms PostScript résolvent » ne distingue pas, sur ce poste, une
   résolution par le bundle d'une résolution par les Plex `.otf` déjà installés dans
   `~/Library/Fonts`. C'est `bundledFontFilesArePresent` + `packagedLayoutIsFound` qui
   couvrent le bundle.

### Prochaine action

**Lot 1** — chantier 1 socle : barre du haut une ligne 38 px, trois espaces, sélecteur de
mode, bandeau 4 KPI (programme §5, écran `1a-cockpit.png` partie haute). Il consomme
`One2OneToken`, les primitives et `MeetingScreenModel.space/mode` de ce lot, et le schéma V3
du lot 0B. C'est lui qui câble les primitives : à sa fin, la recette à l'écran devient
comparable à la capture de référence.

## Refonte de l'écran de réunion — lot 1 : barre du haut, trois espaces, modes, bandeau KPI (2026-09-07)

Deux branches **empilées**, parties de l'intégration de 0A + 0B sur `origin/master`
(`a3c44f2`) : `feat/refonte-lot-1a-chrome` (PR #21) puis
`feat/refonte-lot-1b-espaces-kpi-assistant` (PR #22), basée sur la première. Le plan du lot
comptait 15 tâches, au-delà du seuil de 14 fixé par le programme §7 — d'où la coupe, prévue
par le programme lui-même. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-1-espaces.md`.

**État : livré, `swift build` propre, `swift test` complet vert, deux PR ouvertes, non
mergées.** Les PR **incluent 0A et 0B** tant que #19 et #20 ne sont pas fusionnées.

### Ce qui est en place

**Barre du haut sur une ligne de 38 px** (spec §2.1) — `MeetingTopChromeBar` réécrit : fond
`bg/app`, **teinté `accent/oneonone bg` (`#f4f1f6`) pour les deux types 1:1**, bordure basse
`border/card`, padding horizontal 14. Fil d'Ariane dont le segment projet est bordé
`accent/action` et cliquable (il ouvrira la fiche au lot 9 ; il ouvre la feuille Détails d'ici
là), titre `flex:1` en ellipsis éditable, **pilule audio `ink/1` de rayon 16** (`▶ mm:ss /
mm:ss`, marqueur, `✂`, et **saisie directe de timecode** au clic sur le temps —
`TimecodeInput.parse` refuse plutôt que de deviner), état de capture, menu de type portant
le `+` de création, menu de template, bouton `Rapport ✓ (m:ss)` en `accent/report`, `⋯` de
28 px. La **deuxième ligne disparaît** : `MeetingTagEditor` est dans la feuille Détails.

**Barre d'espaces de 34 px** (spec §2.2) — `MeetingSpacesBar` remplace `MeetingTabsUnderline`
(**supprimé**, 93 l.) : `Réunion · Rapport ✓ · Ressources n doc`, soulignement 2 px
`accent/report`, `SegmentedMode` des trois modes, date `4 sept. 2026 · 9:15`.

**Bandeau des quatre indicateurs** (spec §2.3) — `MeetingKPIBuilder` (pur, 11 tests) calcule
présence, actions, décisions et risques ; `MeetingKPIBand` rend quatre cartes 10 × 12 avec
`gap 10`, libellé mono, valeur 20/600 et micro-visualisation (`AvatarStack`, `ProgressBar`,
première décision en ellipsis, points de risque teintés par niveau + `+n`). **Un compteur à
zéro remplace la micro-visualisation par une invite**, jamais une carte vide.

**Trois espaces × trois modes** — `MeetingSpaceRouting` remplace
`MeetingView.visibleSections(for:)` ; `MeetingSpaceView` aiguille sur le mode : En séance =
carte notes ↔ transcription à parts égales (`1fr 1px 1fr`), Relire = résumé + décisions +
actions avec transcription repliée (**D0** : c'est le poste de pilotage 1c), Préparer =
actions reportées + derniers points du projet + alertes + rail réduit de 330 px + composeur
de sujet (`MeetingPrepTab` réutilisé). `OverviewDashboard` et `MeetingChatView` **ne sont
plus instanciés** (D8 ; leur code n'est retiré qu'au lot 19).

**Assistant comme surface** (spec §1.1) — `MeetingAssistantDock` en pied de l'espace Réunion :
`✳` + placeholder de la capture + deux suggestions (la seconde datée de la réunion précédente
du même projet) + `⌘K`. `MeetingAssistantPanel` héberge `MeetingChatView` **telle quelle**.

**La tête de lecture appartient au modèle d'écran** — reprend l'**écart n° 1 du lot 0B** : le
registre statique LRU de `MeetingPlayhead` disparaît, un `MeetingScreenModel` possède la tête
de lecture de sa réunion, `AudioEditorSheet` la reçoit en paramètre.

**`⌘K` et `⌘M`** (spec §1.4) — deux items dans `MeetingMenuActions` / `MeetingCommands`.
`⌘K` est **toujours** actif (c'est une surface, pas un onglet) ; `⌘M` exige un axe temps,
donc jamais sur une note.

**Jeu de démonstration** — `RefonteDemoSeed` sème la réunion de `1a-cockpit.png` (projet
`S/D — Modernisation CI/CD`, 6 participants, 12 actions dont 9 non assignées, 3 décisions dont
une de budget, 5 risques dont 2 critiques, notes et transcription, 23:24), idempotent et
réutilisant un homonyme existant. Commande « Charger le jeu de démonstration (refonte) » dans
le menu **Réunion**.

### Créés

`OneToOne/Views/Meeting/Spaces/` : `MeetingSpacesBar`, `MeetingKPIBand`, `MeetingSpaceView`,
`MeetingLiveSpace`, `MeetingReviewSpace`, `MeetingPrepareSpace`, `MeetingResourcesSpace`,
`MeetingReportSpace`, `MeetingAssistantDock` (+ `MeetingAssistantPanel`), `MeetingEmptyInvite`,
`MeetingSlidesPopover`, `MeetingPrepBadge`.
`OneToOne/Services/Meeting/` : `MeetingKPIBuilder`, `MeetingSpaceLayout`, `MeetingSpaceRouting`,
`MeetingPrepareBuilder`, `MeetingCalendarSync`. `OneToOne/Services/Debug/RefonteDemoSeed.swift`.

### `MeetingView.swift`

**2 948 → 2 553 lignes (−395)**. Sont sortis : `MeetingSection` et `visibleSections(for:)`,
`sectionContent`, `documentsView`, `attachmentRow`, `icon(for:)`, `reportView` +
`decisionsEditor` + `metaHeaderEditor` + `actionsNotice`, `slidesPopover`, le badge de
préparation, l'import et la resynchronisation calendrier, et les deux accesseurs du rapport
manager (`fieldText`, `managerHighlightedRanges`, désormais
`ManagerReportService.sourceText` / `.highlightedRanges`). Les fonctions de transcription et
de locuteurs y restent, comme prévu pour ce lot.

### Tests

`swift build` propre, aucun avertissement nouveau. `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 762 Swift Testing en 115 suites (0 échec)**, soit
**1 801 tests** contre 1 701 après 0A + 0B (**+100, +13 suites**), aucune régression.

Nouvelles suites : `MeetingSpaceLayoutTests` (7), `MeetingSpacesBarTests` (5),
`MeetingTopChromeBarTests` (5), `MeetingEmptyInviteTests` (4), `MeetingKPIBuilderTests` (11),
`MeetingAssistantDockTests` (4), `MeetingPrepareBuilderTests` (5), `RefonteDemoSeedTests` (4).
Ajouts : 5 tests dans `MeetingScreenModelTests`, 2 dans `MeetingMenuActionsTests`, 2 dans
`MeetingPlayheadTests` (les 2 du registre statique remplacés).
`MeetingVisibleSectionsTests` est **adapté** au nouveau routage, pas supprimé.

Critères d'acceptation du chantier 1 :

- **n° 1 (aucune zone vide sans invite)** : `MeetingEmptyInvite.Catalogue` est une table
  **exhaustive** des neuf couples espace × mode ; un espace ou un mode ajouté plus tard fait
  échouer la suite tant qu'il n'a pas son invite. Un test refuse en plus les invites qui se
  contentent de nier (longueur minimale) — c'était le défaut de `ContentUnavailableView`.
- **n° 4 (changement de mode sans perte de saisie)** : `pendingNoteText` rejoint le brouillon
  d'action dans `MeetingScreenModel` ; le test traverse les trois modes **et** les trois
  espaces, et vérifie que rien n'est mémorisé d'une ouverture à l'autre.
- **n° 5 (1 280 px, colonne fluide ≥ 520 px)** : `MeetingSpaceLayout.columns` **retire** une
  colonne fixe (la nav latérale d'abord, le rail ensuite) plutôt que de rogner la fluide — une
  soustraction non bornée produit en SwiftUI une largeur négative, donc un chevauchement
  silencieux. 7 tests, dont l'ajustement exact à 1 040 px.
- n° 2 et n° 3 relèvent des lots 2 et 3, hors périmètre.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée.**
   `ioreg -n Root -d1 -r | grep CGSSession` rend `"CGSSessionScreenIsLocked" = Yes` ;
   `screencapture -x` ne produit qu'une image entièrement noire, et `osascript` sur
   `System Events` est refusé (`-25211`, accès d'assistance non autorisé) — impossible donc de
   redimensionner la fenêtre à 1 280 puis 1 920 px ni de capturer. Aucun fichier n'a été
   déposé dans `docs/superpowers/specs/refonte-2026-09/recette/` : une capture noire ne
   prouverait rien.
   Ce qui a été fait et vérifié : `swift build -c release` **réussit** (226 s) et le binaire
   `.build/release/OneToOne` **démarre**. Lancé nu, il n'ouvre **aucune fenêtre** — un
   exécutable SwiftPM sans bundle `.app` reste un processus accessoire ; c'est exactement ce
   que `Scripts/bump-and-build.sh` répare en empaquetant. Un `.app` de recette a donc été
   empaqueté **hors du dépôt** (scratchpad), sans passer par le script (qui incrémente le
   numéro de build et installe dans `~/Applications`) : binaire + `Info.plist` + `PkgInfo` +
   `OneToOne_OneToOne.bundle` + `default.metallib` repris de `Mickey.app` + signature ad hoc.
   Il démarre, mais l'écran verrouillé empêche toute capture.
   **À refaire en une commande, écran déverrouillé** : `swift build -c release`, puis
   empaqueter comme ci-dessus, lancer le binaire du bundle, menu **Réunion → Charger le jeu de
   démonstration (refonte)**, redimensionner à 1 280 puis 1 920 px, `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-1-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis n'a
   jamais été déclenché (il l'est par un clic de menu).
2. **La pile d'avatars est triée par nom**, et non dans l'ordre de la relation : SwiftData ne
   garantit pas l'ordre d'une relation « à plusieurs », et une pile qui se réordonne d'un
   rendu à l'autre est un défaut visible. La capture ne fixe pas d'ordre significatif ; l'ordre
   rendu est donc `CA CP LD LS NL PY` et non `PY NL CP LS CA LD`. **Écart connu avec la
   capture, à trancher.**
3. **`AvatarStack` reçoit une règle d'initiales optionnelle** (primitive du lot 0A étendue) :
   la capture montre `PY` pour « Pierre-Yves Nallet », là où `Avatar.initiales(de:)` — employé
   par tous les écrans non refondus — donne `PN`. Les deux règles coexistent plutôt que l'une
   n'écrase l'autre ; le défaut du paramètre reste `Avatar.initiales`.
4. **Le bandeau KPI n'est pas affiché en mode Préparer** : la spec §2.2 ne le mentionne que
   pour En séance (« KPI condensés en bandeau ») et, par son contenu, pour Relire. En
   préparation, rien n'a encore été dit.
5. **Un bouton de capture reste dans la barre du haut**, absent du tableau de la spec §2.1 :
   sans lui, la configuration de la capture d'écran deviendrait injoignable. La spec §5.2
   (lot 7) y place précisément une pilule `● Capture · Teams n ⌄` — c'est donc son emplacement
   définitif, en version courte d'ici là.
6. **`SummaryCard.generate` et `.transcriptSource` deviennent statiques** pour que le mode
   Relire emploie **la même** définition du texte de la réunion et le même prompt. Le
   comportement de la carte est inchangé, sans repli sur les notes live.
7. **Le routage minimal des trois espaces est dans la branche 1a**, alors que le programme le
   classe en tâche 4 (donc en 1b) : les sept onglets et les trois espaces ne peuvent pas
   coexister, et 1a livrerait sinon un écran incohérent.
8. **Les cinq chemins d'écran laissés à vérifier de visu par le lot 0A** (composeur d'action
   du rail, bascule « Afficher speakers », dépliage de la barre de lecture, ajout d'un
   participant ad hoc, thèmes proposés) **n'ont pas pu être vérifiés** : même cause qu'au n° 1.
   Le composeur d'action et la bascule des speakers sont désormais tous deux montés par
   l'espace Réunion, donc couverts par la même recette.

### Prochaine action

**Lot 2** — notes ↔ transcription synchronisées sur l'audio : `TimedNotesColumn`,
`NoteComposer` avec les commandes `/` toujours visibles, `TranscriptColumn` et sa rangée
d'actions au survol, `ActionFromPhrase`, `AudioTimelineStrip` (programme §5, lot 2). Il
remplace le contenu provisoire du mode En séance. Puis **lot 3** (rail d'actions 330 px
permanent) et **lot 9** (fiche projet en panneau, déclenchée par le segment projet du fil
d'Ariane livré ici).

## Refonte de l'écran de réunion — lot 2 : notes ↔ transcription, frise audio, action depuis une phrase (2026-09-07)

Branche `feat/refonte-lot-2-notes-transcription`, **empilée** sur
`feat/refonte-lot-1b-espaces-kpi-assistant` (`a8f8f32`) — elle contient donc 0A, 0B, 1a et 1b
(PR #19–#22, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-2-notes-transcription.md` (14 tâches, à la
limite du seuil de coupe fixé par le programme §7 : pas de découpe en 2a/2b).

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

**La carte « Notes & transcription » n'est plus provisoire** (spec §2.4) — `MeetingLiveSpace`
monte lui-même ses composants ; `MeetingView` ne lui injecte plus rien. En-tête du lot 1
inchangé (titre, « synchronisées sur l'audio », `Speakers ON/OFF`, `Résumer`), corps
`1fr 1px 1fr`, **frise audio de 22 px en pied**.

**Colonne MES NOTES** (`Notes/TimedNotesColumn.swift`) — lignes `timecode | texte` depuis
`MeetingNote` (D1), timecode `accent/action` cliquable → `playhead.seek` (chargement paresseux
du WAV), timecode `--:--` quand la réunion n'a aucun axe temps, barre gauche 2 px
`accent/report` (décision) / `accent/warn` (risque), préfixe de nature en gras, édition inline
au double-clic (`EditableTextField`), menu de ligne (nature, visibilité, supprimer) et bandeau
de filtre `kind:décision` avec « tout afficher ». Vider une ligne ne la supprime pas : le menu
le fait.

**Composeur** (`Notes/NoteComposer.swift`) — cadre pointillé, **quatre pilules toujours
visibles** (`/action /décision /risque /citer`) cliquables (elles insèrent la commande et
gardent le clavier), note au **timecode courant** du playhead, `Retour` **et** `⌘⏎` valident
et vident **sans perdre le focus** (champ AppKit `CommandReturnTextField` : `insertNewline`
par le délégué, `⌘⏎` intercepté dans `performKeyEquivalent` avant le menu principal, qui porte
le même raccourci pour « Générer le rapport »), `⌘⇧N` rend le clavier au champ depuis l'écran.
Le texte en cours reste dans `MeetingScreenModel.pendingNoteText` (critère n° 4 du lot 1).

**`NoteCommandParser`** (pur, 13 tests) — `/action /décision /risque /citer /privé /feedback
/promesse /demande /preuve`, insensible à la casse **et aux accents**, commande en début de
ligne seulement, **une commande inconnue n'est pas mangée** (`/décison X` reste du texte).
`/privé` impose la visibilité, `/action` pose l'intention plutôt qu'une note.

**Colonne TRANSCRIPTION** (`Transcript/TranscriptColumn.swift`) — moteur annoncé
(`Cohere MLX` / `Voxtral` / `Qwen3-ASR` selon `AppSettings.transcriptionEngine`), compteur de
segments, **transcription live dans la même colonne** pendant l'enregistrement, segments
`timecode | Locuteur — texte` sur `surface/alt`, survol → fond `accent/action bg` + rangée
`＋ Action` (plein) · `Décision` · `Citer dans la note`, `⌘⇧A` sur le segment survolé (à
défaut le dernier survolé), menu contextuel complet, suppression de passage, **défilement
lié** (`Suivre` / `Reprendre le suivi` ; cliquer un segment le coupe). La transcription sans
segments garde le surlignage du CR manager (`MeetingHighlightableTextView`), seul chemin qui
l'offre sur la transcription.

**`ActionFromPhrase`** (pur + deux fabriques, 13 tests) — nettoyage : hésitations de tête
(`euh`, `donc`, `bah`…), guillemets encadrants, amorce d'obligation → infinitif
(« il faut remettre ça en route » → « Remettre ça en route »), ponctuation finale, majuscule,
coupe au mot à 120 caractères. **Trois garde-fous** : une amorce suivie de `que` n'est pas
retirée (« il faut que le partenaire finalise » reste tel quel), un mot qui n'est pas un
infinitif ne l'est pas non plus (« il faut deux semaines »), et une liste courte de faux amis
(`notre`, `autre`, `ordre`…) évite « Notre accord ». `createAction` conserve
`sourceRef {transcript, stableID, t}`, reprend le locuteur résolu et naît **en tête** du rail
(`sortOrder` minimal − 1) ; `createDecision` produit une `MeetingNote(kind: .decision)` au
timecode du segment, **sans** mise à l'infinitif (une décision se lit comme elle a été
prononcée) ; `quotation` rend `« texte » — Locuteur, mm:ss`.

**Frise audio 22 px** (`Spaces/AudioTimelineStrip.swift`) — onde décimée
(`AudioWaveform` + **`AudioWaveformCache`**, clé fichier × résolution), tête de lecture 2 px
`accent/action`, marqueurs ronds (note), ronds ambre (risque), losanges (décision), carrés
`captureMarker` (capture, dès qu'un `SlideCapture.t` existe), clic **et** glisser
(`DragGesture(minimumDistance: 0)`) → `playhead.seek`. **Sans WAV, la frise reste affichée** :
piste plate, marqueurs et invite « Aucun audio » — c'est l'axe temps de la réunion, pas celui
d'un fichier.

**Services purs du lot** : `TranscriptFollow` (machine à états ; ni la tête de lecture ni les
segments live ne **réactivent** le suivi), `AudioTimelineGeometry` (`t ↔ x` bornés, jamais de
`NaN` dans un `Canvas`, nombre de pics borné), `MeetingTimelineMarkers` (notes + captures
triées ; une capture sans `t` est **ignorée** plutôt que dessinée à `00:00`),
`MeetingNoteStore.timecodeLabel` / `.append` / `.nextOrderIndex`.

**Jeu de démonstration** — `RefonteDemoSeed` sème les **quatre notes horodatées** de la
capture (`04:12`, `07:48`, `11:03` en décision, `15:20`) et pose `notesMigrated` : la reprise
de `liveNotes` n'ajoute pas une cinquième ligne à `t = 0`, alors que le markdown reste rempli
pour l'éditeur historique et les gabarits de rapport.

### Créés

`OneToOne/Services/Meeting/` : `NoteCommandParser`, `ActionFromPhrase`, `TranscriptFollow`,
`AudioTimelineGeometry`, `MeetingTimelineMarkers`. `OneToOne/Services/AudioWaveformCache.swift`.
`OneToOne/Views/Meeting/Spaces/Notes/` : `TimedNotesColumn`, `NoteComposer`.
`OneToOne/Views/Meeting/Spaces/Transcript/` : `TranscriptColumn`, `TranscriptSpeakerTools`.
`OneToOne/Views/Meeting/Spaces/AudioTimelineStrip.swift`.

### `MeetingView.swift`

**2 553 → 2 073 lignes (−480)**, aucun ajout. Sont sortis : `SpeakerMeta`, `isLiveActive`,
`liveTranscriptSection`, `transcriptView`, `transcriptToolbar`, `transcriptSegmentsView`,
`segmentRow`, `playSegmentAudio`, `segmentActionsMenu`, `speakerBadge`, `firstCandidate`,
`acceptSuggestion`, `rejectSuggestion`, `speakerRenamePopover`, `speakerPickerRow`,
`assignSpeaker`, `speakerColor`, et cinq `@State` (`renamingSpeakerID`, `speakerPickerSearch`,
`segmentToDelete`, `segmentDeleteError`, `lastDiarizationEmbeddings`). Y restent
`runDiarization`, `reidentifySpeakers`, `applySpeakerTurns` et `transcriptionPhaseBanner`,
exposées par closures (`onDiarize`, `onReidentify`, `onAddToManagerReport`). Le cache
d'embeddings de diarisation a rejoint `MeetingScreenModel` : il fait le lien entre la
diarisation, restée dans `MeetingView`, et la mise à jour EMA du voiceprint, partie avec le
badge. `MeetingSpaceView` perd ses paramètres génériques `Notes`/`Transcript` et garde
`Actions` (le rail du lot 3 le remplacera). Le KPI Décisions filtre enfin la colonne de notes
(`screen.toggleNoteFilter(.decision)`) au lieu de basculer en mode Relire.

### Tests

`swift build` propre, aucun avertissement nouveau (le seul restant est l'ancien
`PyannoteDiarizer.swift:92`). `swift test` complet **vert** : **1 039 XCTest (1 ignoré,
0 échec) + 835 Swift Testing en 122 suites (0 échec)**, soit **1 874 tests** contre 1 801
après le lot 1 (**+73, +7 suites**), aucune régression.

Nouvelles suites : `NoteCommandParserTests` (13), `ActionFromPhraseTests` (13),
`ActionFromTranscriptCriterionTests` (6), `TranscriptFollowTests` (9),
`AudioTimelineGeometryTests` (8), `MeetingTimelineMarkersTests` (6),
`AudioWaveformCacheTests` (3). Ajouts : 5 tests dans `MeetingScreenModelTests`, 4 dans
`MeetingNoteStoreTests`, 4 dans `RefonteDemoSeedTests`. `MeetingTextualContentTests`,
`NoteFactoryTests`, `PendingEditorTextTests` et `ConfidentialityFilterTests` (lot 0B) restent
verts : les notes privées ne sortent par aucun des cinq flux.

Critères d'acceptation couverts :

- **Chantier 1 n° 2 (une action depuis une phrase)** :
  `ActionFromTranscriptCriterionTests` fait le trajet complet **sans vue** — un seul appel de
  service crée l'action (c'est le clic), `sourceRef` porte `kind = transcript`, le `stableID`
  du segment et son `t`, `MeetingPlayhead.seek` replace la lecture **à ± 1 s** (`04:12`),
  l'action naît en tête du rail, et une source hors de la durée connue (fichier tronqué par
  l'édition audio) ne sort pas de la frise.
- **Défilement lié** : machine à états pure, avec le cas qui compte — `playheadMoved` et
  `segmentsAppended` ne réarment **pas** le suivi.
- **Marqueurs de la frise** : positions calculées depuis `t / duration`, bornées, aller-retour
  stable à 0,01 s ; `duration == 0` rend `0` et non `NaN`.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée** —
   `ioreg -n Root -d1 -r | grep CGSSession` rend `"CGSSessionScreenIsLocked" = Yes`, comme au
   lot 1. Aucune capture n'a été déposée dans
   `docs/superpowers/specs/refonte-2026-09/recette/` : une image noire ne prouverait rien.
   Ce qui a été vérifié : `swift build -c release` réussit.
   **À refaire en une commande, écran déverrouillé** : `swift build -c release`, empaqueter un
   `.app` hors du dépôt (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` +
   `default.metallib` repris de `Mickey.app` + signature ad hoc, **HOME temporaire
   obligatoire** pour ne pas toucher au store de production), lancer, menu **Réunion → Charger
   le jeu de démonstration (refonte)**, redimensionner à 1 280 puis 1 920 px,
   `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-2-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis
   n'est déclenché que par un clic de menu.
2. **Les pilules `/…` sont alignées à droite du composeur**, alors que la capture les montre
   accolées au mot « Tape ». Le champ de saisie doit occuper la largeur restante ; le mettre
   après les pilules le réduirait à rien dès qu'on tape. Les commandes restent **toujours
   visibles**, ce qu'exige la spec.
3. ~~**`/action` dans le composeur de notes ne conserve pas encore `sourceRef` sur l'action
   créée**~~ — **levé à l'intégration des lots 2 + 3** (section en tête) : `/action` pose
   l'intention avec une source de nature `note`, le composeur du rail la consomme et
   `ActionComposerService.creer` conserve `sourceRef`. `＋ Action` sur un segment suit
   désormais le même chemin et ne crée plus l'action directement — il en créait une
   deuxième.
4. **`⌘⇧A` et `⌘⇧N` sont des boutons d'opacité nulle dans les colonnes**, pas des items de
   `MeetingCommands` : le programme §2.4 interdit d'ajouter quoi que ce soit à
   `MeetingView.swift`, et un item de menu y aurait exigé deux closures de plus. Conséquence
   assumée : ils n'agissent que lorsque l'espace Réunion est à l'écran — c'est-à-dire
   exactement là où ils ont un sens. **Non vérifiés à l'exécution** (même cause qu'au n° 1) ;
   `⌘⏎` est le plus exposé, l'item de menu « Générer le rapport » portant le même raccourci —
   d'où l'interception dans `performKeyEquivalent` **et** la validation par `Retour`.
5. **Le risque prend un rond ambre sur la frise**, pas une quatrième forme : la spec ne nomme
   que trois formes (rond, carré, losange) et une quatrième serait illisible à 22 px.
6. **La colonne de transcription affiche les segments même quand `Speakers` est éteint**
   (sans les badges), là où l'ancien écran retombait sur un bloc de texte à plat. Le texte à
   plat reste le rendu des transcriptions **sans** segments, avec son surlignage de CR manager.
7. **Les noms des locuteurs du jeu de démonstration ne sont pas ceux de la capture**
   (`Yann`, `Patrice`, `Sylvain` y désignent des participants nommés autrement dans
   `RefonteDemoSeed`, hérité du lot 1). Écart connu, non traité ici pour ne pas toucher aux
   chiffres que la recette des lots précédents vérifie.

### Prochaine action

**Lot 4** (mode séance plein écran 1b : palette `dark/*`, colonne temps verticale, file
d'assignation) et **lot 5** (poste de pilotage = mode Relire 1c : nav latérale 190 px, tableau
d'actions éditable en place, frise pleine largeur). Le lot 3 (rail d'actions 330 px) tournait
en parallèle ; il est depuis **rebasé sur ce lot** et consomme bien
`MeetingScreenModel.pendingActionDraft` posé ici (cf. la section d'intégration en tête).

## Refonte de l'écran de réunion — lot 3 : rail d'actions 330 px permanent (2026-09-07)

Branche `feat/refonte-lot-3-rail-actions`, **rebasée sur**
`feat/refonte-lot-2-notes-transcription` (elle-même sur
`feat/refonte-lot-1b-espaces-kpi-assistant`) : la PR **empile** les lots 0A, 0B, 1a, 1b et 2
(PR #19–#23, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-3-rail-actions.md` (11 tâches).

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**

### Ce qui est en place

**Le rail est monté une seule fois, par `MeetingSpaceView`** (spec §2.5) : `HStack` sur
`MeetingSpaceLayout.columns(totalWidth:rail:sideNav:)`, colonne fluide à gauche
(indicateurs + contenu du mode + dock assistant), filet, rail de 330 px à droite. Le lot 1
l'avait esquissé dans `MeetingPrepareSpace` — ce placeholder est **retiré**, deux montages
produisant deux rails. **Pas de rail en mode Relire** : la capture
`1c-poste-de-pilotage.png` met les actions en tableau dans sa colonne principale, et c'est
la même `ActionsRailList` qui y sert d'ici au lot 5. En mode Préparer, le rail est
« réduit » (spec §2.2) : le sélecteur de vue disparaît, on ne prépare pas une séance en
matrice d'Eisenhower.

**Trois onglets et trois vues** — `ActionsRail` : `Actions n / Risques n / Historique`,
l'onglet actif sur fond `bg/app` arrondi (le soulignement `accent/report` reste réservé à la
barre d'espaces, deux soulignements sur le même écran ne se hiérarchisent plus) ; sous
`Actions`, `SegmentedMode` sur `ActionsViewMode.railCases` = `Liste · Calendrier ·
Eisenhower`. `ActionsViewMode` a quitté `ActionsPanel.swift` pour `Models/` ; **Kanban et
Post-it restent dans `ActionsListView`** et ne sont pas atteignables depuis le rail (une
valeur mémorisée `kanban` retombe sur `Liste`).

**Groupes ordonnés, purs et testés** — `ActionsRailGrouping` : `À ASSIGNER` (libellé mono
`accent/report`, barre gauche 2 px) → `MES ACTIONS` → `DÉLÉGUÉES` → `REPORTÉES DU <date>`
(rendu en lignes compactes à puce ronde, groupées par date de la réunion d'origine, du plus
récent au plus ancien). Le **report l'emporte** sur « à assigner » : une action n'apparaît
jamais deux fois. Les actions `done`/`dropped` quittent l'onglet Actions pour l'Historique.
Le tri interne passe `sortOrder` **avant** l'échéance — contrairement à l'ancien
`ActionsPanel` — parce que c'est ce qui permet au composeur de mettre une action neuve en
tête sans lui inventer une échéance, et c'est ce qui reproduit l'ordre de la capture.
`dateOrdinale` porte l'ordinal du premier du mois (« 1er sept. »), que `Date.FormatStyle` ne
donne pas en français.

**Cartes à édition inline** — `ActionCard` : titre `plexSans(11.5)` sur 2 lignes, puis les
pilules `InvitePill` — responsable (`＋ assigner`, `＋ Yann` quand une suggestion existe,
vert `accent/ok` quand renseigné, neutre pour un `unresolvedAssigneeName`), échéance,
charge (`30min` / `1h30` / `2h` / `1j`, la journée comptée à 8 h), `!` urgent, et la pilule
de source (`◫ mm:ss` pour une capture, `mm:ss ↗` pour une phrase ou une note → `playhead.seek`).
Un clic **déplie un sélecteur sous le titre**, jamais une modale : `OwnerPickerMenu`
réutilisé, `DatePicker` compact + raccourcis `Demain / Vendredi / +1 sem.`, liste de charges.
`Tab` avance de champ, `Esc` referme. Une invite qui **porte une suggestion assigne en un
clic** ; la pilule devenue verte se reclique pour choisir quelqu'un d'autre.
`ActionCardEditing` (pur) porte toutes ces règles.

**Suggestion de responsable** — `OwnerSuggestion` (pur) applique les trois règles de la spec
dans l'ordre : locuteur du segment source → dernier porteur d'une action de même préfixe de
titre (trois mots normalisés, diacritiques repliés) dans le projet → participant **unique**
n'ayant encore rien à porter. Aucune conclusion rend `nil` : une suggestion fausse coûte plus
cher qu'une absence, puisqu'un seul clic l'accepte.

**Composeur en pied, toujours visible** — `ActionComposer` : champ `Nouvelle action…`,
indice `⌘⏎`, bascules `Moi · Demain · ! · 30min`. La création est un service
(`ActionComposerService.creer`) : c'est ce qui rend vérifiable le « sans perdre le focus »,
un service sans accès au focus ne pouvant pas le prendre. Il consomme
`MeetingScreenModel.pendingActionDraft` (le titre saisi l'emporte sur celui du brouillon,
mais la chaîne de citation survit à la reformulation) et le remet à `nil`. `⌘⏎` est vérifié à
la main (`onKeyPress(keys: [.return])` + `press.modifiers`) plutôt que par un
`keyboardShortcut`, qui serait actif champ non focalisé. Après création, seuls le titre et
l'urgence retombent : un `!` oublié rendrait urgente toute la série suivante. L'insertion
s'anime en **150 ms** (`.animation(.easeOut(duration: 0.15), value: meeting.tasks.count)`).

**Onglets Risques et Historique** — `ActionsRailRisks` : les `ProjectAlert` de la réunion
puis celles du projet non déjà listées, point coloré par sévérité, `＋ Ajouter un risque` qui
déplie un champ **inline** (gravité en pilules, le champ reste ouvert après création : un
risque en amène souvent un second). La lecture de sévérité et la teinte sont celles du
bandeau (`MeetingKPIBuilder.level(fromSeverity:)`, `MeetingKPIBand.teinte(_:)`) — deux
définitions finiraient par peindre le même risque de deux couleurs. `ActionsRailHistory` :
les actions closes, abandonnées et reportées, une ligne datée par entrée.

**`ActionsPanel` est hors de tout chemin actif de l'espace Réunion** (point 8 du périmètre) :
il n'est plus instancié que par `OverviewDashboard`, que le lot 1 ne monte plus (D8) et que
le lot 19 supprimera. `MeetingView` perd sa closure `actions:` **et** sa fonction `addTask`
(−28 lignes ; 2 073 → **2 045** après rebase sur le lot 2, qui en avait déjà retiré 480) ; la
carte RISQUES du bandeau ouvre désormais l'onglet Risques du rail au lieu du rapport.

**`compact: Bool` sur `CalendarBoard` et `EisenhowerBoard`** (décision D10) : ajout dont le
défaut reproduit les métriques d'avant, extraites en fonctions statiques
(`dayCellMinHeight`, `maxChipsPerDay`, `boxMinHeight`) pour être vérifiables — une cellule
rognée sur l'écran Actions plein ne se voit dans aucun test de rendu.

### Créés

`OneToOne/Models/` : `ActionsViewMode.swift`, `ActionDraft.swift`.
`OneToOne/Services/OwnerSuggestion.swift`.
`OneToOne/Views/Meeting/Spaces/Rail/` : `ActionsRailGrouping`, `ActionCard`
(+ `ActionCardEditing`, `ActionCompactRow`), `ActionComposer` (+ `ActionComposerService`),
`ActionsRailList`, `ActionsRailRisks`, `ActionsRailHistory`, `ActionsRail`.

### Tests

`swift build` propre (seul avertissement : celui, préexistant, de `PyannoteDiarizer`).
`swift test` complet **vert** : **1 039 XCTest (1 ignoré, 0 échec) + 816 Swift Testing en
122 suites (0 échec)**, soit **1 855 tests** contre 1 801 après le lot 1 (**+54, +7 suites**),
aucune régression. `EngagementLedgerTests`, `PrepCarryoverServiceTests`,
`MeetingMenuActionsTests` et les suites `ActionsListView` sont vertes.

Nouvelles suites : `ActionsViewModeTests` (4), `ActionsRailGroupingTests` (8),
`OwnerSuggestionTests` (8), `ActionCardEditingTests` (9), `ActionComposerServiceTests` (9),
`ActionsBoardsCompactTests` (5), `ActionsRailNoModalTests` (4). Ajouts : 4 tests dans
`MeetingScreenModelTests`, 3 dans `RefonteDemoSeedTests`.

Critère d'acceptation du chantier 1 **n° 3** (« assigner responsable + échéance sans quitter
le rail ni ouvrir de modale ») : un critère de cette forme ne se vérifie pas par l'état d'un
modèle — une `sheet` ajoutée demain par distraction passerait toutes les autres suites.
`ActionsRailNoModalTests` **lit les sources** du dossier `Rail/` (chemin dérivé de
`#filePath`) et refuse `.sheet(`, `.popover(`, `.alert(`, `.confirmationDialog(`,
`.fullScreenCover(`, toute couleur nommée hors `One2OneToken`, et toute remise à `false` du
`@FocusState` du composeur. Un premier test vérifie que le dossier lu est bien celui du rail,
sans quoi les autres ne prouveraient rien en passant.

### Jeu de démonstration

`RefonteDemoSeed` reproduit maintenant les groupes du rail. L'arithmétique de la maquette
était incohérente (`12 · 9 non assignées` + `À ASSIGNER — 9` + `REPORTÉES — 3` n'admet aucune
solution où une carte assignée figure sous `À ASSIGNER`) : les **trois actions reportées sont
celles qui portent un responsable**, et comme le rendu compact d'un groupe reporté n'affiche
pas de porteur, rien ne le contredit à l'écran — les trois nombres de la capture tombent
juste d'un coup. Échéances, charges (`2h`, `1j`) et chaîne de citation (`04:12 ↗`) complètent
les trois premières cartes. Une réunion « COSUI hebdo » du 1er septembre porte le report et
alimente « DERNIERS POINTS » du mode Préparer, jusque-là vide.

**Défaut du lot 1 corrigé** : le semis datait la réunion du 4 septembre **2025**
(`1 756 970 100`), pas 2026 — la barre d'espaces affichait donc la mauvaise année, le vendredi
de la capture devenait un jeudi, et tout raccourci d'échéance avec lui. Un test fixe désormais
jour, mois et année.

### Écarts assumés

1. **Recette visuelle non faite : la session graphique est verrouillée**, comme au lot 1.
   `ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` rend `Yes` ; `screencapture -x` ne
   produit qu'une image noire et `osascript` sur `System Events` est refusé (`-25211`). Rien
   n'a été déposé dans `docs/superpowers/specs/refonte-2026-09/recette/` : une capture noire
   ne prouverait rien. **À refaire écran déverrouillé** : `swift build -c release`, empaqueter
   un `.app` hors du dépôt (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` +
   `default.metallib` repris de `Mickey.app` + signature ad hoc, HOME temporaire), lancer,
   menu **Réunion → Charger le jeu de démonstration (refonte)**, redimensionner à 1 280 puis
   1 920 px, `screencapture -x` vers `recette/lot-3-{1280,1920}.png`, comparer à
   `ecrans/1a-cockpit.png`. **Rien n'a été écrit dans le store de production** : le semis se
   déclenche par un clic de menu.
2. **Un quatrième groupe, `DÉLÉGUÉES`**, s'ajoute aux trois de la spec. Sans lui, une action
   assignée à quelqu'un d'autre et non reportée n'apparaîtrait dans **aucun** groupe : elle
   disparaîtrait du rail sans disparaître de la base, ce qui est la pire des deux options. Le
   discriminant de `MES ACTIONS` étant `destinataire == .moi` (comme le demande le périmètre),
   `À ASSIGNER` doit exclure ce cas, sinon il avalerait toutes mes actions —
   `destinataire == .moi` implique `collaborator == nil` dans le modèle existant.
3. **La capture montre une carte assignée (« Sylvain » en vert) sous `À ASSIGNER`.** C'est
   une incohérence de la maquette, contredite par sa propre carte ACTIONS (`9 non assignées`
   sur 12). Le rail respecte ses règles : une action assignée sort du groupe. La pilule verte
   se voit dès qu'on assigne, elle n'est simplement pas dans l'état semé.
4. **`REPORTÉES DU <date>` n'est pas cliquable vers la réunion d'origine.** La spec ne le
   demande pas et le lot 9 livrera la navigation projet ; la ligne compacte porte le titre et
   le compteur de reports, pas de lien.
5. **Une échéance de la semaine se nomme par son jour** (« Demain », « Vendredi »), la date
   reprenant la main au-delà de six jours **et pour toute échéance passée** (« Mardi » pour un
   mardi révolu serait un piège). C'est ce que montre la capture, mais le libellé est relatif
   à *aujourd'hui* : aucune valeur semée ne peut fixer le mot affiché. Le jeu reproduit la
   forme — une échéance proche et une lointaine côte à côte.
6. **`OwnerPickerMenu` conserve sa feuille « Ajouter un collaborateur… »**, hors du dossier
   `Rail/` et donc hors du périmètre de la garde anti-modale. Assigner un participant ou un
   favori ne passe par aucune modale, ce qu'exige le critère ; *créer* un collaborateur qui
   n'existe pas encore en ouvre une, et c'est une autre intention.
7. **Le composeur ne propose que « Moi » ou « À assigner »**, pas les trois `ActionAudience`.
   Dans 330 px, un menu de trois entrées pour un réglage qu'on change à chaque ligne coûte
   plus qu'il ne rend ; le sélecteur complet est sur la carte.
8. **`newTaskEffortMinutes` s'ajoute au brouillon** à côté de `newTaskPomodoros`, que
   `ActionsPanel` et les vues existantes continuent d'employer. `effortMinutes` est le champ du
   modèle cible (programme §3) ; fusionner les deux aurait touché des écrans hors périmètre.
9. **Le rail n'apparaît pas sous 850 px de largeur** : `MeetingSpaceLayout` retire la colonne
   fixe plutôt que de rogner la fluide sous 520 px (critère n° 5, comportement du lot 1
   inchangé). Le composeur d'action devient alors injoignable dans l'espace Réunion — à
   trancher au lot 19 avec la recette 1 280 px.

### Prochaine action

**Lot 4** — mode séance plein écran (1b) : palette `dark/*`, grille `78 | 1fr | 400`, colonne
temps, bandeau « EN ATTENTE — n actions sans responsable » et sa file d'assignation en trois
clics (elle consomme `ActionsRailGrouping.groupes` et `OwnerSuggestion` livrés ici). Puis
**lot 5** — poste de pilotage = mode Relire : nav latérale de 190 px, tableau d'actions dense
à sept colonnes qui remplacera `ActionsRailList` dans ce mode, frise audio pleine largeur.

## Intégration des lots 2 + 3 : la pile redevient linéaire (2026-09-07)

Les lots 2 et 3 ont été développés **en parallèle** depuis
`feat/refonte-lot-1b-espaces-kpi-assistant` (`a8f8f32`). Le lot 3 a été **rebasé sur le
lot 2** : la pile est de nouveau linéaire — `1b → 2 → 3` — et l'ordre de fusion est
`#19 → #20 → #21 → #22 → #23 → #24`. La branche du lot 3 porte donc ses 11 commits rebasés
plus un commit d'intégration.

**Six fichiers en conflit, six résolutions :**

- `MeetingScreenModel.swift` — les deux lots ajoutaient « en fin de type ». Toutes les
  propriétés des deux sont gardées (`noteFilter`, `noteComposerFocusToken`,
  `lastDiarizationEmbeddings`, `railTab`, `railViewMode`, `newTaskEffortMinutes`), et
  `pendingActionDraft`, déclaré deux fois, n'existe plus qu'une : de type `ActionDraft`
  (lot 3). Le brouillon du lot 2 (`ActionFromPhrase.Draft`, qui portait un *nom* de
  locuteur) **disparaît** au profit d'`ActionDraft`, qui porte un `Collaborator` — le
  composeur doit pouvoir l'affecter, pas seulement l'afficher.
- `MeetingSpaceView.swift` — plus **aucun générique** : le lot 2 avait retiré
  `Notes`/`Transcript`, le lot 3 `Actions`. La vue compose `MeetingLiveSpace` à gauche et
  `ActionsRail` à droite via `MeetingSpaceLayout` ; le placeholder de rail du lot 1 est
  retiré, l'overlay et le dock assistant du lot 1 conservés.
- `MeetingView.swift` — les deux retraits, **aucun ajout** : les ~480 lignes d'UI de
  transcription (lot 2, `runDiarization`/`reidentifySpeakers` restant exposées par
  closures) **et** `actions:` + `addTask` (lot 3). **2 045 lignes**, contre 2 525 pour le
  lot 3 seul.
- `RefonteDemoSeed.swift` — les apports des deux : 4 notes horodatées + `notesMigrated`
  (lot 2), les 12 actions dont 9 non assignées et 3 reportées, et l'année **2026**
  (lot 3). Les chiffres de `1a-cockpit.png` tombent toujours juste : PRÉSENCE 6/6,
  ACTIONS 12 · 9 non assignées, DÉCISIONS 3, RISQUES 5 · 2 critiques.
- `Tests/MeetingScreenModelTests.swift` — union des deux, **un seul** test de
  non-persistance du brouillon (celui du lot 2, qui couvre aussi le filtre de notes).
- `STATUS.md` — les deux sections, lot 3 au-dessus du lot 2, cette section en tête.

**La couture `/action → rail` est branchée.** Le lot 2 posait `pendingActionDraft` sans
que personne ne le consomme et créait l'action par `MeetingView.addTask()`, qui perdait
`sourceRef` ; le lot 3 consommait un brouillon que personne ne posait. Après rebase :

1. `/action <texte>` dans le composeur de notes pose l'intention avec une source de nature
   **`note`** (et non `transcript` : `OwnerSuggestion` ne cherche un locuteur que dans les
   sources `transcript`) horodatée à la tête de lecture. La ligne n'écrit **aucune** note.
2. `＋ Action` sur une phrase de transcription pose l'intention avec la source du segment
   et le locuteur en responsable suggéré. **Il ne crée plus rien** : il créait *et* laissait
   le composeur créer — deux actions pour un clic. `ActionFromPhrase.createAction` est
   supprimée, `ActionComposerService.creer` est le **seul** point de création.
3. `requestAction` préremplit le titre **et** les pilules du responsable
   (`newTaskAudience` + `selectedCollaborator`) : une suggestion qu'on ne voit pas ne se
   refuse pas.
4. `⌘⏎` crée l'`ActionTask` avec `sourceRef` intact, vide le champ sans toucher au focus,
   et l'action paraît en tête d'`À ASSIGNER` (ou du groupe de son responsable).

Nouvelle suite `ActionSeamIntegrationTests` (4 tests, sans aucune vue) : les deux chemins de
bout en bout, la reformulation du titre qui ne coupe pas le lien vers la phrase, et une
lecture des sources amont qui refuse toute autre fabrique d'`ActionTask` ou tout reliquat
d'`addTask`.

**`swift build` propre** (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`). **`swift test` complet vert : 1 039 XCTest
(1 ignoré, 0 échec) + 892 Swift Testing en 130 suites = 1 931 tests**, contre 1 874 pour le
lot 2 seul et 1 855 pour le lot 3 seul (+3 sur l'union attendue : les 4 tests de la nouvelle
suite moins le test de `pendingActionDraft` dédoublonné).

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24`, puis attaquer
le **lot 4** (mode séance plein écran) et le **lot 5** (poste de pilotage).

## Refonte de l'écran de réunion — lot 4 : mode séance plein écran (2026-09-07)

Branche `feat/refonte-lot-4-mode-seance`, sur `feat/refonte-lot-3-rail-actions` : la PR
**empile** les lots 0A, 0B, 1a, 1b, 2 et 3 (PR #19–#24, non fusionnées). Ordre de fusion
`#19 → #20 → #21 → #22 → #23 → #24 → celle-ci`. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-4-mode-seance.md`.

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.
Recette visuelle non faite — voir plus bas.**

### Ce qui est en place

**`SessionFullscreenView` : grille `78 | 1fr | 400`, thème `.session`, aucun chrome.**
La barre d'état est la seule surface de chrome de l'écran (spec §2.6) :
`● En séance · P25_110` — le point pulse **si et seulement si** l'enregistrement de cette
réunion tourne —, `mm:ss / mm:ss` de la tête de lecture, les pastilles des participants,
`CP parle`, et `Clore la séance` en `accent/report` plein. Ni barre d'espaces, ni bandeau
d'indicateurs, ni fil d'Ariane, ni rail de 330 px : en séance, douze actions listées à
droite sont une invitation à faire autre chose qu'écouter. Ce qu'il en reste est le bandeau
`EN ATTENTE`, qui ne parle que de ce qui vient d'être décidé.

**Le locuteur courant vient des segments résolus, pas d'un signal live.**
`LiveTranscriptionService` ne publie **aucun** locuteur : la diarisation est *batch*,
`LiveDiarizationAligner.alignToBlocks` s'exécute après le `stop()`, par recouvrement de
timestamps. `SessionCurrentSpeaker` cherche donc le `TranscriptSegment` qui couvre `t` et
dont le `speaker` est résolu en `Collaborator` ; sans lui, la mention est **masquée** (spec
§2.6 : « sinon masqué ») — `S2 parle` dans une barre d'état est du bruit. Bornes
`début ≤ t < fin`, pour qu'un locuteur ne reste pas affiché pendant le silence qui suit son
tour.

**`TimeRailColumn` : axe 3 px, `#e04b3f` sur la portion écoulée.** Ronds `dark/accent
action` pour les notes, carré de rayon 3 `accent/report` pour les décisions, trait `dark/ink`
pour la position — dessiné **après** les repères, pour qu'on voie où l'on est même quand une
note est posée juste là. Libellés mono à 30 px du rail : ils passent donc légèrement derrière
l'axe, comme sur la capture, où l'on lit `04:1` et non `04:12`. Toute la géométrie est dans
`TimeRailGeometry`, pure et testée — une durée nulle est le cas **courant** de cet écran
(séance qui vient de démarrer), et un `Canvas` à qui l'on passe un `NaN` ne dessine rien sans
rien signaler.

**`⌘M` pose une `MeetingNote(kind: .note, text: "")`** (décision D4.1). Un type « marqueur
pur » aurait demandé une colonne, une migration et un second chemin de repère pour le même
besoin : `MeetingTimelineMarkers` lit déjà `meeting.timedNotes`, donc le repère apparaît sur
l'axe sans rien ajouter. En contrepartie, `TimedNotesColumn` **filtre les lignes vides** —
sinon la colonne afficherait une ligne muette dont seul le timecode se lit, et qu'on ne
saurait pas supprimer.

**`AssignmentQueue` : la file en trois gestes, pure et générique.** `responsable → échéance →
suivante`, `Tab` et `⌘⏎` avancent, `Esc` sort **à n'importe quelle étape**, « Passer » saute
sans rien poser, une file vide est close d'emblée (`Assigner maintenant` sur zéro action est
une impasse, pas un formulaire vide). Générique sur l'identifiant : la vue l'instancie sur
`PersistentIdentifier`, les tests sur `Int`. `AssignmentQueueSheet` réutilise
`OwnerPickerMenu` et `ActionCardEditing.raccourcisEcheance` du lot 3 — trois sélecteurs de
responsable dans l'application finiraient par ne plus proposer les mêmes personnes. Le
bandeau lui-même délègue « sans responsable » à `ActionsRailGrouping` (groupe `À ASSIGNER`) :
deux définitions afficheraient deux nombres pour le même écran.

**`SessionCapturedSummary` compte depuis le début de la séance, et rien avant.** La réunion
porte tout son historique, préparation de la veille comprise : `meeting.tasks.count`
afficherait 12 actions là où la séance en a produit 4. L'origine est `recordingStartedAt`
**même s'il précède** l'ouverture du mode (on passe souvent en plein écran une fois la séance
lancée), sinon l'instant d'ouverture. Un horodatage `nil` ne compte pas — `ActionTask.createdAt`
est optionnel, et ces lignes-là sont justement les anciennes.

**`MeetingAssistantController` : la logique d'envoi sort de la vue.** Le panneau de séance
pose les mêmes questions que `MeetingChatView`, qui **délègue désormais** la construction du
prompt au contrôleur (ses tests continuent de passer par `makePrompt`, qui ne fait plus que
transmettre) — un test vérifie que les deux chemins produisent la même chaîne au caractère
près. Les **sources horodatées** de la capture ne sont pas extraites du texte du modèle (un
modèle qui cite mal produirait des liens morts) mais du contexte qu'on lui a effectivement
donné : les chunks RAG retenus, plus la dernière note de la séance. Les `TranscriptChunk` ne
portent pas de timecode — ils sont découpés par longueur, pas par tour de parole — donc
l'instant est retrouvé par recouvrement de texte avec les segments de la réunion d'origine
(`instant(ofExtract:inSegments:)`), et **`nil` plutôt qu'un instant inventé** quand
l'extrait est trop court ou étranger. Une source dans la séance replace la tête de lecture ;
ailleurs, elle ouvre sa réunion.

**Mention `@Prénom` en pilule.** `SessionMentionRuns` découpe la ligne ; la règle
intéressante n'est pas la pilule mais **ce qui en est une** : `@Yann` oui,
`laurent@april.com` non (le `@` y est au milieu d'un mot), `@Inconnu` non tant qu'aucun
collaborateur ne porte ce nom — peindre en bleu une personne qui n'existe pas promet une
notification qui n'aura pas lieu. La reconnaissance passe par `CollaboratorMentionSource`,
la même que l'éditeur markdown. Un test de non-perte recompose la ligne d'origine au
caractère près. Rendu seulement en thème `.session`, par `MentionFlow` + `WrapLayout` (une
`Layout` de flot minimale) : `AttributedString.backgroundColor` ne donne qu'un rectangle
plein, qui se colle au bord du bloc sur une mention en fin de ligne. Le prix payé est la
sélection du texte, perdue sur les lignes qui portent une mention.

**Entrée et sortie.** Le mode est présenté en **substituant le `contentView` de la fenêtre
courante** (`SessionWindowSwapper`), pas dans une `WindowGroup` de plus et pas par un
`overlay` : un overlay posé sur `MeetingSpaceView` laisse visibles la barre du haut, le badge
de préparation et la barre d'enregistrement de `MeetingView` — donc du chrome. La demande
passe par `SessionFullscreenPresenter`, un objet partagé : la pilule audio de
`MeetingTopChromeBar` et l'item `⌃⌘F` de `MeetingCommands` n'ont ni l'un ni l'autre accès au
`MeetingScreenModel`, et faire descendre un binding jusqu'à eux aurait exigé de modifier
`MeetingView`. Un **jeton** et non un booléen : deux `⌃⌘F` de suite doivent tous deux
basculer. `Esc` suit `SessionExitPolicy` — confirmation si et seulement si l'enregistrement
tourne, et un second `Esc` **referme** le dialogue au lieu de le valider.

**Les composants des lots 2 et 3 lisent le thème, ils ne le choisissent pas.**
`TimedNotesColumn`, `NoteComposer`, `TranscriptColumn`, `Chip` et `sectionLabel()` sont passés
de `One2OneToken.*` à `theme.colors.*`. En `.paper`, les couleurs résolues sont **identiques**
et `SessionThemeTests` le fixe : sans ce test, une seule correspondance erronée repeindrait
discrètement l'espace Réunion en clair sans qu'aucune autre suite s'en aperçoive.
`One2OneColors` gagne les sept champs qui manquaient (`surfaceAlt`, `strongBorder`,
`inkMuted`, `actionInk`, `actionBg`, `reportInk`, `warnInk`) ; `One2OneToken` gagne
`railElapsed` (`#e04b3f`), distinct d'`accent/report` — la spec §2.6 nomme une valeur propre,
et la capture le confirme.

### Créés

`OneToOne/Views/Meeting/Session/` : `SessionFullscreenView`, `SessionFullscreenState`
(+ `SessionExitPolicy`), `SessionFullscreenPresenter` (+ `SessionWindowSwapper`, le
modificateur `sessionFullscreen`), `SessionStatusBar`, `TimeRailColumn`,
`AssignmentQueueSheet` (+ `SessionPendingBand`), `SessionAssistantPanel`
(+ `SessionCapturedBlock`), `SessionCapturedSummary`, `SessionCurrentSpeaker`,
`SessionMentionRuns`, `MentionFlow` (+ `WrapLayout`), `MeetingAssistantController`.
`OneToOne/Services/Meeting/` : `TimeRailGeometry`, `AssignmentQueue` (+ `PendingAssignment`).

### Modifiés

`MeetingScreenModel` : **une ligne** (`var session = SessionFullscreenState()`).
`MeetingSpaceView` : **un modificateur** (le point d'entrée). `MeetingTopChromeBar` :
**la pilule audio seule** (le bouton plein écran, visible quand un écran est en mesure de
présenter). `MeetingMenuActions` / `MeetingCommands` : `⌃⌘F` et son item de menu.
`One2OneTokens`, `One2OneTheme`, `One2OneTypography`, `Chip`, `TimedNotesColumn`,
`NoteComposer`, `TranscriptColumn` : lecture du thème. `MeetingChatView` : délégation du
prompt. **`MeetingView.swift` n'est pas touché — un test le vérifie.**

### Tests

`swift build` propre (avertissements préexistants seuls). `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 974 Swift Testing en 142 suites = 2 013 tests**, contre
1 931 après l'intégration des lots 2+3 (**+82, +12 suites**), aucune régression.

Nouvelles suites : `TimeRailGeometryTests` (13), `AssignmentQueueTests` (10),
`PendingAssignmentTests` (3), `SessionCapturedSummaryTests` (6),
`SessionCurrentSpeakerTests` (5), `SessionExitPolicyTests` (3),
`SessionFullscreenStateTests` (4), `SessionMentionRunsTests` (8), `SessionThemeTests` (6),
`SessionNoChromeTests` (6), `SessionFullscreenEntryTests` (6),
`MeetingAssistantControllerTests` (9).

Le critère « **aucun chrome hors la barre d'état** » ne se vérifie pas par l'état d'un
modèle : un `MeetingKPIBand` recopié demain par distraction passerait toutes les autres
suites. `SessionNoChromeTests` **lit les sources** du dossier `Session/` (chemin dérivé de
`#filePath`, avec un premier test qui garde le chemin lui-même) et refuse
`MeetingSpacesBar`, `MeetingKPIBand`, `MeetingTopChromeBar(`,
`MeetingContextualRecorderBar`, `MeetingPrepBadge`, `MeetingAssistantDock(`, `ActionsRail(`
et `MeetingSpaceLayout`, plus toute couleur nommée hors `One2OneToken`. Deux autres tests
lisent tout `OneToOne/` pour vérifier que le point d'entrée n'est posé **qu'une fois** (deux
poses substitueraient deux fois le contenu de la même fenêtre, et la seconde restauration
rendrait la première) et que `MeetingView` ne mentionne rien du lot.

### Recette visuelle : non faite

`ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` ne rend **aucune clé** : la session
n'est pas verrouillée. Le `.app` a bien été empaqueté depuis le worktree (`Lot4.app`, HOME
**et** `CFFIXED_USER_HOME` jetables, garde-fou d'isolation vérifié : le store atterrit dans
le home jetable). Trois obstacles ont fait renoncer, dans cet ordre :

1. **Premier lancement : crash `EXC_BREAKPOINT` dans `_NSViewUpdateConstraints`** (AppKit,
   exception pendant la mise à jour des contraintes). C'est **la signature exacte** du crash
   qu'une autre session bisecte en parallèle sur la même base (`bisect-step.sh`, « crash de
   la fenêtre 1to1 », `grep "Update Constraints"`) : défaut **préexistant**, pas du lot 4.
2. **Lancements suivants : l'application tourne, crée son store, mais n'ouvre aucune
   fenêtre** (`count windows of process "OneToOne"` = 0, menu `Fenêtre` sans liste, journal
   vide). Le menu `Réunion` est complet et porte bien « Mode séance plein écran » ; l'item
   « Charger le jeu de démonstration (refonte) » a été cliqué, sans fenêtre pour l'afficher.
   Piste non tranchée : l'autorisation d'accessibilité est accordée par **identité de
   signature**, et le bundle de recette est signé ad hoc sur un chemin neuf — l'API AX peut
   donc rendre zéro fenêtre alors qu'il y en a une.
3. **Le poste était en réunion Teams réelle** (« OJ — Comité Urbanisation », 20 participants,
   enregistrement en cours) et deux autres sessions se disputaient le bureau. Prendre l'écran
   pour une capture aurait interrompu une réunion en cours. Processus de recette arrêté.

`docs/superpowers/specs/refonte-2026-09/recette/lot-4-1920.png` **n'existe donc pas**, et
aucun écart avec `1b-mode-seance.png` n'est mesuré. À refaire dès que le crash du point 1 est
corrigé (lot en cours ailleurs) et que le poste est libre.

### Écarts assumés avec la capture

- **`EN ATTENTE  3 actions sans responsable`** : le jeu de démonstration du lot 1 pose
  **9** actions sans responsable (`12 · 9 non assignées` au bandeau, `À ASSIGNER — 9` au
  rail), et son arithmétique est vérifiée par `RefonteDemoSeedTests`. Le bandeau affichera
  donc 9 et non 3. Changer le semis pour faire tomber le 3 casserait les trois nombres de
  `1a-cockpit.png` : le compteur est juste, c'est le jeu de données qui diffère.
- **La ligne `18:42 Formation Admin à planifier`** de la capture est la ligne **en cours de
  saisie** (curseur rouge, aucun repère à 18:42 sur l'axe), pas une note enregistrée. Aucun
  fichier `RefonteDemoSeed+Lot4.swift` n'a donc été ajouté : y semer cette ligne poserait un
  cinquième rond sur l'axe, que la capture ne montre pas.
- **Le composeur en séance n'a pas de cadre pointillé** et suit la dernière note dans le
  flot, là où le mode fenêtré l'ancre en pied d'une colonne courte : la colonne de séance
  occupe toute la hauteur de l'écran, et un composeur collé en bas serait à trente
  centimètres du regard. Le rendu clair du lot 2 est inchangé.
- **`DÉCISION` passe au-dessus du texte** en séance (libellé mono `accent/report`, comme la
  capture) alors qu'il reste inline en 1a. Même raison : la colonne est plus large et la
  ligne respire.
- **Pas de barre de titre** : `titleVisibility` passe à `.hidden` pendant la présentation.
  Une barre de titre est du chrome.

### Fichiers partagés touchés malgré les conventions anti-conflit

`One2OneTheme.swift` (sept champs ajoutés à `One2OneColors`), `One2OneTypography.swift`
(`sectionLabel()` devient un `ViewModifier` pour lire le thème), `Chip.swift`
(`encre(_:)` / `fond(_:)` par thème, les propriétés d'avant conservées),
`Transcript/TranscriptColumn.swift`, `Notes/TimedNotesColumn.swift`, `Notes/NoteComposer.swift`
(lecture du thème), `MeetingChatView.swift` (délégation du prompt). Aucun n'appartient au
périmètre déclaré des lots 5, 6 ou 10 ; tous les changements sont additifs ou neutres en
`.paper`, et `SessionThemeTests` verrouille cette neutralité.

### Prochaine action

Faire relire, puis fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → cette PR`.
Rejouer la recette visuelle du lot 4 une fois le crash `_NSViewUpdateConstraints` corrigé.

## Refonte de l'écran de réunion — lot 5 : poste de pilotage (mode Relire) (2026-09-07)

Branche `feat/refonte-lot-5-poste-pilotage`, **empilée** sur
`feat/refonte-lot-3-rail-actions` : la PR contient donc les lots 0A, 0B, 1a, 1b, 2 et 3
(PR #19–#24, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-5-poste-pilotage.md` (11 tâches).

**État : livré, `swift build` propre, `swift test` complet vert.**

### Ce qui est en place

**Le mode Relire est le poste de pilotage de `1c-poste-de-pilotage.png`** (décision D0 :
« 1c est la disposition du mode Relire »). `MeetingSpaceView` le route **hors** de sa colonne
fluide : il prend toute la surface, sans bandeau d'indicateurs, sans rail de 330 px et sans
dock injecté — il monte les siens. `MeetingSpacesBar.estMasquee(space:mode:)` lui rend la
barre d'espaces, et **seulement à lui** : en mode Relire, les espaces Rapport et Ressources
n'ont pas de nav latérale, et sans barre on s'y retrouverait sans rien pour en sortir.

**Nav latérale de 190 px** (`Review/ReviewSidebarNav.swift`) — badge `1:1 One2One`, libellé
`SÉANCE`, sept entrées dont **chacune porte un compteur ou un état** : `Synthèse généré/—`,
`Notes n` (les `MeetingNote`), `Transcription mm′`, `Actions n` (compteur en `accent/report`
dès qu'une action n'a pas de porteur), `Rapport ✓/—`, `Documents n/＋`, `Assistant ⌘K`.
L'entrée active est une **carte blanche à ombre de 1 px** (spec §2.7) — pas un soulignement,
qui reste la marque de la barre d'espaces. `Rapport` et `Documents` **changent d'espace**
(Rapport, Ressources), `Notes` et `Transcription` ramènent en mode **En séance** — c'est le
sens de « transcription repliée » (spec §2.2) : elle est à un clic —, `Assistant` ouvre le
dock, et `Synthèse` et `Actions` déplacent le défilement de la colonne principale. En pied,
le bloc `PROJET` (nom + trois dernières réunions antérieures du
projet, cliquables) et le bloc `ALERTES · n` dont la lecture de sévérité et la teinte sont
celles du rail (`ActionsRailRisks.teinte`) — deux définitions finiraient par peindre le même
risque de deux couleurs.

**En-tête** (`Review/ReviewHeader.swift`) — titre sans son préfixe de référence, ligne
`P25_110 · Projet · 4 sept. 2026 · 9:15 · 23 min · 6 participants` **sans point médian
orphelin** (une réunion hors projet perd le segment, elle ne le laisse pas vide), puis
`Capture n`, `Exporter ⌄` — les cinq destinations existantes de `MeetingMenuActions`,
regroupées, désactivées sans rapport — et `Rapport ✓ 6:20`. Le sélecteur
`Préparer / En séance / Relire` est ici, en haut à droite : la barre d'espaces étant masquée,
sans lui on entrerait en relecture sans pouvoir en sortir.

**Cartes** — `Review/OneSentenceCard.swift` : `EN UNE PHRASE`, badge `généré`,
`Meeting.shortSummary` rendu **avec son gras** par `AttributedString(markdown:)` (et non
`MarkdownText`, qui imposerait ses fontes là où le corps doit rester en Plex Sans 12,5),
chips de `MeetingTag`, invite « Générer la synthèse » appelant `SummaryCard.generate` — la
**même** fonction que la carte Résumé du dashboard.
`Review/DecisionsCard.swift` : `DÉCISIONS PRISES · n` depuis les `MeetingNote(kind:
.decision)` triées par `t` — ce sont elles qui portent le timecode, et un timecode est ce qui
rend une décision vérifiable. Timecode `accent/report` cliquable → `playhead.seek`. Repli sur
`Meeting.decisions` **sans** timecode pour une réunion importée (`--:--` plutôt que `00:00`,
instant où rien ne s'est passé). `separerPorteur` détache le nom de fin de phrase, au tiret
cadratin comme entre parenthèses, avec trois garde-fous : le segment doit être le dernier,
commencer par une majuscule et ne porter aucune ponctuation interne — sans quoi « — reste à
chiffrer la fin Marine » deviendrait un porteur.

**Tableau d'actions dense** (`Review/ActionsTable.swift`) — sept colonnes aux largeurs de la
spec (`20 | 1fr | 108 | 92 | 62 | 76 | 30`, fixées par un test), lignes alternées
`surface` / `surface/alt`, sélection en `accent/action bg2`. **Édition inline par cellule** :
un clic déplie le sélecteur **sous** la ligne (responsable via `OwnerPickerMenu`, échéance
via raccourcis + `DatePicker` compact, charge), `Tab` avance de champ, `Esc` referme, et
aucune modale (gardé par lecture des sources). Le titre s'édite au double-clic
(`EditableTextField`) ; un intitulé vidé ne supprime pas l'action — c'est le menu `⋯` qui le
fait. Clavier : `↑↓` navigue (borné, jamais cyclique), `Espace` coche, `⌥↑↓` réordonne via
`ActionsTableCommands`, qui **normalise `sortOrder` en 0…n−1** — réécrire seulement les deux
lignes échangées laisserait des égalités que `ActionsRailGrouping.triees` tranche par
échéance, et la ligne déplacée reviendrait à sa place. Sélecteur
`Tableau · Eisenhower · Calendrier` (les deux planches du lot 3 en `compact: true`),
`＋ Action` bleu, badge `n sans responsable`, pied `ActionComposer` **réemployé tel quel** +
`n autres · tout afficher` (repli à 5 lignes).

La colonne `ÉCHÉANCE` porte les quatre états de la capture, dans cet ordre : une date réelle,
puis `Reporté ×n` (`deferralCount`), puis `Urgent` en `accent/report`, puis l'invite
`＋ date`. La colonne `SOURCE` mène au timecode (`04:12 ↗`) ou, à défaut, à la **date de la
réunion d'origine** (`1 sept.` de la capture) : une action reportée a une provenance, pas un
instant.

**Frise audio pleine largeur** (`Review/ReviewAudioTimeline.swift`) — ce n'est pas une
seconde frise : c'est `AudioTimelineStrip` du lot 2 avec `labelled: true`, un nouveau mode
dont le **défaut ne change pas d'un pixel** le rendu de 22 px du mode En séance. Autour,
seulement ce que la capture montre : le bouton `▶` (qui charge le WAV dans le lecteur **de la
tête de lecture**, pas un second — deux lecteurs, ce sont deux positions) et `✂ Éditer`, qui
passe par `MeetingMenuActions.editAudio` : la feuille d'édition audio est présentée par
`MeetingView`, et une seconde présentation ici en ferait deux.

**Étiquettes sans chevauchement** (`Services/Meeting/TimelineLabelLayout.swift`) — deux
passes : les **décisions d'abord**, les notes ensuite dans ce qui reste. À l'étroit, perdre
`DÉCISION` pour garder un timecode nu serait le mauvais échange. Une étiquette qui n'entre
pas est **abandonnée**, jamais décalée : décalée, elle ne désignerait plus son marqueur. Les
captures et les planches n'ont pas d'étiquette — leur carré se lit déjà.

**Passage automatique en Relire après le rapport** — `ReviewState.apresGenerationDuRapport`
remplace le `screen.space = .report` du lot 1 dans le chemin post-génération de
`MeetingView.generateReport` : espace `Réunion`, mode `Relire`, section `Synthèse`, et une
demande de focus sur le champ d'assignation de la première action sans responsable (spec
§2.2). Les demandes sont **jetonnées** — deux générations de suite doivent toutes deux
replacer le curseur, or la seconde écriture d'une valeur identique ne notifie personne.
`ActionsTable` la sert et déplie le tableau si la ligne visée est au-delà des cinq premières :
un curseur sur une ligne qu'on ne voit pas n'est pas un focus.

### Créés

`OneToOne/Services/Meeting/` : `ActionsTableCommands.swift`, `TimelineLabelLayout.swift`.
`OneToOne/Views/Meeting/Spaces/Review/` : `ReviewState`, `ReviewSidebarNav`, `ReviewHeader`,
`OneSentenceCard` (+ `ReviewCard`), `DecisionsCard`, `ActionsTable`, `ReviewAudioTimeline`.
`OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot5.swift`.

### Modifiés

`MeetingReviewSpace.swift` (recomposé, non générique — le contenu provisoire du lot 1
disparaît), `MeetingSpaceView.swift` (routage du mode Relire, deux paramètres ajoutés),
`MeetingSpacesBar.swift` (`estMasquee` + garde de corps), `AudioTimelineStrip.swift`
(`labelled`, `hauteur(labelled:)`, `candidats(_:)`), `MeetingScreenModel.swift` (**une
ligne** : `var review = ReviewState()`), `MeetingView.swift` (ligne post-génération + deux
paramètres au call-site), `MeetingCommands.swift` (le menu de démonstration appelle
`seedLot5`).

### Tests

`swift build` propre (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`). `swift test` complet **vert** :
**1 039 XCTest (1 ignoré, 0 échec) + 966 Swift Testing en 136 suites = 2 005 tests**, contre
1 931 après l'intégration des lots 2 + 3 (**+74, +6 suites**), aucune régression.

Nouvelles suites : `ActionsTableCommandsTests` (14), `TimelineLabelLayoutTests` (10),
`ReviewStateTests` (10), `ReviewSidebarNavTests` (15), `ReviewCardsInviteTests` (15),
`RefonteDemoSeedLot5Tests` (9).

Critères du lot :

- **Navigation clavier complète du tableau** — `ActionsTableCommandsTests` : `↑↓` borné aux
  deux extrémités, sélection périmée ramenée dans le tableau, `⌥↑↓` refusé aux bords, et la
  preuve qui compte — après `appliquerOrdre`, `ActionsRailGrouping.triees` rend **exactement**
  le nouvel ordre, le lecteur réel étant celui-là.
- **Étiquettes sans chevauchement** — `TimelineLabelLayoutTests` : la propriété est vérifiée
  par paires successives (`début ≥ fin précédente + espacement`), aux deux bords, sur une
  durée nulle (aucun `NaN`) et sur des candidats non triés ; plus la règle de priorité (à
  l'étroit, `DÉCISION` l'emporte).
- **Compteurs de la nav, exhaustivité** — `ReviewSidebarNavTests` : une entrée par
  `ReviewState.Section`, **aucune** sans complément — sur une réunion vide comme sur une
  réunion pleine. Une entrée ajoutée demain fait échouer la suite tant qu'elle n'a pas dit ce
  qu'elle contient.
- **Passage en Relire après rapport et focus posé** — `ReviewStateTests` : la transition, le
  jeton de focus qui avance à chaque demande, la consommation qui l'empêche de se rejouer, et
  une lecture de `MeetingView.swift` qui refuse le retour du `screen.space = .report`.
- **Aucune zone vide sans invite** — `ReviewCardsInviteTests` lit les sources du dossier
  `Review/` : chaque surface porte une invite (`MeetingEmptyInvite`, `InvitePill` ou le `＋`
  de la nav) **ou** se déclare dans une liste fermée avec sa raison. La suite refuse aussi
  toute couleur nommée hors `One2OneToken` et toute modale, et un premier test vérifie que le
  dossier lu est bien celui du mode Relire — sans quoi les autres ne prouveraient rien en
  passant.

### Jeu de démonstration

`RefonteDemoSeed+Lot5.seedLot5` complète le semis du lot 3 **sans modifier son fichier** (les
lots 4, 6 et 10 travaillent sur la même base, et c'est le fichier qu'ils touchent tous) :
trois décisions horodatées `11:03` / `13:40` / `20:15`, la première nommant son porteur ; les
quatre thèmes `Migration AP · Facturation · GitLab / CI-CD · Ressources` ; le résumé de la
capture avec son gras ; et deux réunions de plus dans le fil du projet (`31 août —
Gouvernance`, `26 août — Situation AP`), qui complètent le `1 sept. — COSUI hebdo` du lot 3.
L'idempotence des décisions se joue sur le **timecode** et non sur le texte : la formulation
de 1c n'est pas celle de 1a, et une comparaison sur la chaîne aurait créé une seconde
décision au même instant.

### Recette visuelle — non faite : le poste est occupé

L'écran **n'est pas verrouillé** cette fois (`ioreg -n Root -d1 -r | grep
CGSSessionScreenIsLocked` ne rend aucune clé, contrairement aux lots 1 à 3), mais une
**réunion Teams réelle est en cours d'enregistrement sur ce poste** : lancer une application
graphique, prendre le contrôle du clavier par `osascript` ou déclencher `screencapture`
aurait interrompu la séance ou capturé son contenu. Aucune de ces commandes n'a été lancée,
et rien n'a été déposé dans `docs/superpowers/specs/refonte-2026-09/recette/`.

Ce qui a été vérifié : `swift build -c release` réussit (310 s, aucune erreur).

**À refaire, poste libre, en cinq étapes** — les scripts sont dans le scratchpad de session
(`lot5-package.sh`, `lot5-run.sh`) et n'attendent que d'être exécutés :

1. `swift build -c release` depuis le worktree.
2. `lot5-package.sh` — empaquette `Lot5.app` **hors du dépôt** (binaire, `Info.plist`,
   `PkgInfo`, `OneToOne_OneToOne.bundle`, `default.metallib` repris de `Mickey.app`,
   signature ad hoc). Ne pas passer par `Scripts/bump-and-build.sh`, qui incrémente le numéro
   de build et installe dans `~/Applications`.
3. `lot5-run.sh --reset` — lance avec `HOME` **et `CFFIXED_USER_HOME`** jetables. Les deux :
   `NSHomeDirectory()` ignore `HOME` pour une application en bundle, et une recette lancée le
   7 septembre avec le seul `HOME` a semé le jeu de démonstration dans le store de
   production. Le script tue le processus si le store n'apparaît pas dans le home jetable.
4. Menu **Réunion → Charger le jeu de démonstration (refonte)** (il appelle désormais
   `seedLot5`), puis sélecteur de mode → **Relire**.
5. Redimensionner à 1 280 puis 1 920 px, `screencapture -x` vers
   `docs/superpowers/specs/refonte-2026-09/recette/lot-5-{1280,1920}.png`, comparer à
   `ecrans/1c-poste-de-pilotage.png` et consigner les écarts ici.

⚠️ Un **crash préexistant à l'ouverture de la fenêtre dédiée `1to1-meeting` en bundle
release** est en cours de correction par ailleurs : la recette de ce lot devra attendre ce
correctif, ou ouvrir la réunion depuis la fenêtre principale.

**Rien n'a été écrit dans le store de production** : le semis ne se déclenche que par un clic
de menu, et aucune application n'a été lancée.

### Écarts assumés

1. **`Notes 5` de la capture est arithmétiquement impossible.** `1a-cockpit.png` montre
   quatre notes (`04:12`, `07:48`, `11:03`, `15:20`) et `1c` en annonce cinq — tout en
   listant trois décisions à `11:03`, `13:40` et `20:15`, dont deux n'existent pas dans 1a.
   Quatre notes plus deux décisions font **six**, pas cinq. Le semis tient les données
   (six `MeetingNote`, dont trois décisions) et la nav affiche `Notes 6` : c'est la même
   nature d'incohérence de maquette que celle relevée au lot 3 pour `À ASSIGNER — 9`.
2. **`Synthèse` et `Assistant` portent un complément que la capture ne montre pas** (`généré`
   / `—` et `⌘K`). Le critère du lot exige « jamais d'entrée sans compteur ou état, test
   d'exhaustivité » : deux entrées nues seraient précisément les « onglets vides » que le
   titre de la capture bannit. Le complément est en `plexMono(10)` `ink/4`, discret.
3. **Le sélecteur `Préparer / En séance / Relire` s'ajoute en haut à droite de la colonne
   principale**, alors que la capture n'en montre aucun. C'est la consigne du lot (« garde-le
   visible, comme sur 1a ») et c'est nécessaire : la barre d'espaces est masquée dans ce mode,
   et sans ce sélecteur on entrerait en relecture sans pouvoir en sortir.
4. **`Notes` et `Transcription` ramènent en mode En séance** au lieu de défiler dans la
   colonne. Le poste de pilotage n'a ni carte de notes ni carte de transcription (la capture
   n'en montre aucune, et la synthèse et les décisions *sont* la lecture des notes) : une
   entrée qui ne ferait que déplacer un défilement ne mènerait nulle part, et son compteur
   mentirait. C'est ce que veut dire « transcription repliée » (spec §2.2) : elle est à un
   clic. La carte `TRANSCRIPTION` provisoire du lot 1, avec son bouton « Déplier en séance »,
   disparaît donc — son rôle est passé à la nav.
5. **`＋ Action` ne prend pas le clavier.** Le bouton crée la ligne si le composeur porte déjà
   un texte (même chemin que `⌘⏎`) et, sinon, déplie le tableau pour amener le composeur sous
   les yeux. Il ne peut pas focaliser le champ : `ActionComposer` (lot 3) possède son
   `@FocusState` et n'expose aucun jeton, et `Views/Meeting/Spaces/Rail/**` n'est pas
   modifiable depuis ce lot. À reprendre au lot 19, en ajoutant au composeur un jeton de focus
   comme celui du composeur de notes.
6. **Les cinq titres du bloc `ALERTES` ne sont pas ceux de la capture 1c** (« Corruption base
   de données », « Confusion source de code », …) : le semis du lot 3 a choisi les risques de
   `1a-cockpit.png` (« Comptes GitLab désactivés », « Chiffrage du reste à faire non
   validé », …), et `RefonteDemoSeed.swift` est gelé pour ce lot. Le **nombre** (`ALERTES · 5`)
   et la répartition des teintes (deux critiques, un élevé, deux moindres) tombent juste.
7. **Le nom de projet du semis est `S/D — Modernisation CI/CD`**, la capture écrit
   `S/D — Modernisation Chaîne CI/CD`. Même cause : le nom vient du lot 3.
8. **Le focus d'assignation se pose sur la cellule, pas dans un champ de texte.** La spec §2.2
   dit « champ d'assignation » ; le poste de pilotage n'a pas de champ de saisie de
   responsable — c'est un sélecteur (`OwnerPickerMenu`), et la spec §2.5 interdit la modale.
   Le focus sélectionne donc la ligne et **déplie son sélecteur de responsable**, dépliant le
   tableau si la ligne est au-delà des cinq premières.
9. **Les vues Eisenhower et Calendrier n'ont pas de sélection clavier.** Elles réemploient
   `EisenhowerBoard` et `CalendarBoard` en `compact: true` (décision D10) ; `↑↓`, `Espace` et
   `⌥↑↓` n'ont de sens que dans un tableau ordonné, et la spec §2.7 ne les demande que là.
10. **Deux cartes côte à côte s'empilent sous ~900 px** (`ViewThatFits`) : `EN UNE PHRASE` et
    `DÉCISIONS PRISES` à 420 et 340 px de minimum ne tiennent pas dans la colonne fluide de
    520 px que garantit le critère n° 5 du chantier 1.

### Fichiers partagés touchés malgré les conventions anti-conflit

- `MeetingSpacesBar.swift` — la consigne demandait de masquer la barre depuis
  `MeetingSpaceView`, ce qui est impossible : la barre est montée par `MeetingView.mainPanel`,
  au-dessus. Comme `MeetingView.swift` ne devait recevoir que la ligne post-génération, le
  masquage est une fonction pure du fichier de la barre (`estMasquee(space:mode:)`) plus une
  garde de corps — un seul point de touche, et testé.
- `MeetingView.swift` — **deux** points au lieu d'un : la ligne post-génération, et le
  call-site de `MeetingSpaceView`, qui reçoit `menuActions` et `onShowCaptures`. L'en-tête du
  poste de pilotage a besoin des menus d'export existants et du bouton Rapport, la frise du
  `✂ Éditer` ; tous vivent dans `MeetingMenuActions`, que seule `MeetingView` sait
  construire. `@FocusedValue(\\.meetingMenu)` aurait évité le paramètre, mais rend `nil`
  quand la fenêtre n'a pas le focus — des boutons principaux qui s'éteignent au changement de
  fenêtre.
- `MeetingCommands.swift` — une ligne : le menu de démonstration appelle `seedLot5` au lieu de
  `seed`. `RefonteDemoSeed.swift` étant gelé, il n'y avait pas d'autre moyen de brancher le
  complément de semis.

### Prochaine action

1. **Faire la recette visuelle du lot 5** (procédure ci-dessus), poste libre et une fois le
   crash `1to1-meeting` corrigé, puis consigner les écarts avec
   `1c-poste-de-pilotage.png`.
2. Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → lot 5`.
3. Lots suivants : **6** (ressources en séance, tiroir 396 px) et **7** (captures Teams /
   Zoom). Le lot 5 leur laisse deux points d'ancrage : l'entrée `Documents n/＋` de la nav
   latérale, qui ouvre l'espace Ressources, et le bouton `Capture n` de l'en-tête, qui ouvre
   la galerie de captures.

## Refonte de l'écran de réunion — lot 6 : ressources en séance, tiroir et épinglage (2026-09-07)

Branche `feat/refonte-lot-6-ressources`, **sur** `feat/refonte-lot-3-rail-actions` : la PR
**empile** les lots 0A, 0B, 1a, 1b, 2 et 3 (PR #19–#24, non fusionnées). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-6-ressources.md` (14 tâches, toutes faites).
ADR : `docs/adr/2026-09-07-pieces-copiees-jamais-referencees.md`.

**État : livré, `swift build` propre, `swift test` complet vert (2 017 tests), PR ouverte, non
mergée. Recette visuelle non faite — voir « Écarts assumés » n° 1.**

### Ce qui est en place

**La politique de stockage a changé de camp (D5).** Une pièce de séance était *référencée* :
`filePath` gardait le chemin d'origine et `bookmarkData` un signet vers lui. Elle disparaissait
donc au premier rangement du disque, la sauvegarde n'était pas autonome, et ni le partage à
l'écran, ni l'annotation, ni l'épinglage n'avaient d'ancre. Elle est désormais **copiée** dans
`recordings/<uuid>/documents/<yyyyMMdd-HHmmss>_<nom>`, à côté de `slides/` de la même réunion.
`MeetingAttachmentService.attachDocument` copie **avant** d'insérer la ligne — une source
illisible ne laisse plus derrière elle une pièce sans fichier, qu'on ne distinguerait pas d'une
orpheline — puis `importDocument` extrait et indexe le texte **de la copie**. La ligne porte
`scope`, `mimeType`, `byteCount`, `addedByName` (`AppSettings.ownerName`) et un `stableID`
(colonne optionnelle neuve, cible des `sourceRef` de citation). `bookmarkData` est explicitement
`nil` : un signet vers une copie interne n'a aucune valeur, et son absence est le signal le plus
simple qu'une pièce relève de D5.

**La migration des anciennes pièces est paresseuse, et ne supprime jamais rien.**
`AttachmentMigration.migrate(meeting:in:)` tourne à l'ouverture de l'espace Ressources — pas au
lancement : migrer 500 réunions au démarrage bloquerait l'app pour un bénéfice nul sur celles
qu'on ne consulte plus. Source présente → copiée, `filePath` réécrit, `byteCount`/`mimeType`
complétés, signet effacé. Source disparue → la pièce **reste visible** et devient *orpheline*
(état **calculé**, pas une colonne : un drapeau mentirait après restauration d'une sauvegarde sur
une autre machine), et sa vignette affiche « Fichier introuvable — relier », qui ouvre un
`NSOpenPanel` et **copie** le fichier redésigné. Le signet sert une dernière fois, en migration
seulement : il donne une chance de retrouver un fichier simplement *déplacé*, ce que le chemin
brut ne sait pas faire. Le passage backfille aussi les `stableID` manquants — sans eux, `Citer`
n'a rien à mettre dans la référence de la puce.

**Les trois services de maintenance connaissent le nouveau dossier** (programme §2.4 point 6).
`StorageStatsService.documentsUsage(inRecordings:)` scanne `recordings/*/documents` — le dossier
fait foi, y compris pour un fichier qu'aucune ligne ne réclame plus, qui est justement celui
qu'on veut voir dans la répartition ; les lignes encore référencées hors de l'app s'y ajoutent
sans double-compte. `OrphanCleanupService.orphanAttachments` **exclut** deux familles : les
pièces copiées (un fichier interne manquant est un incident à signaler, pas une ligne à effacer
avec son texte extrait, ses chunks RAG et ses citations) et les pièces `link`, dont `filePath`
porte une URL — `fileExists` y répond toujours faux, et les proposer aurait supprimé tous les
liens collés en séance. `MeetingAttachmentDTO` transporte les sept colonnes cibles en champs
**optionnels** : une sauvegarde antérieure reste décodable et retombe sur les défauts.

**Un adaptateur, pas trois listes.** `ResourceItem` unifie `MeetingAttachment`,
`ProjectAttachment` et `SlideCapture` — trois modèles sans parenté qui alimentent la même
colonne de 396 px. Structure de valeur, fonctions pures : `all(for:)`, `sorted`,
`filtered(_:by:)`, `counts`, `metadata(calendar:)` (« Ajouté par Sylvain · 09:22 · 84 Ko », chaque
partie disparaissant quand elle est inconnue au lieu de laisser un séparateur orphelin). Trois
décisions y sont inscrites : le **lot** de captures (kind `slides`) est un conteneur à chemin
virtuel, il ne paraît pas comme ressource mais ses PNG oui, un par vignette ; le `t` d'une
capture **est** son épinglage — une capture prise en séance est ancrée dans le temps par
construction ; et les captures ne comptent pas dans « Cette séance », qui annonce `4 séance` sans
elles. L'identité d'une pièce de projet, qui n'a pas de `stableID`, est dérivée de son chemin
(FNV-1a) : aléatoire, SwiftUI remonterait la vignette à chaque rendu.

**Les liens n'appellent personne.** `AttachmentLinkImporter` reconnaît une URL http(s) et refuse
tout le reste (`about:`, `file:`, `mailto:`, un bloc multi-lignes, du texte libre) : coller trois
lignes de notes ne doit pas produire une ressource intitulée « trois lignes de notes ». Le
libellé vient de l'URL seule — dernier segment décodé, à défaut le domaine sans `www.` — parce
qu'aller chercher le `<title>` d'une page ferait sortir l'app de la boucle locale pour un
libellé, ce que le §8 interdit sans le signaler. Les extensions techniques (`.html`, `.php`)
disparaissent du libellé, un `.pdf` distant reste : il dit ce qu'on va ouvrir. La cible vit dans
`filePath` — une colonne `linkURL` dédiée aurait créé deux vérités pour la même information.

**Le tiroir : un seul corps pour deux surfaces.** `ResourcesPanel` porte l'en-tête (compteurs
`n séance` / `n projet`, `＋ Importer` plein `accent/action`), les quatre filtres, les vignettes,
la zone de dépôt permanente et le pied. `ResourcesDrawer` l'emballe à 396 px, superposé, ombre
`-8px 0 24px rgba(0,0,0,.07)`, `Esc` pour fermer — **sans voile** sur la colonne de gauche,
contrairement à la fiche projet du lot 9 : on continue de prendre des notes pendant qu'on cherche
un document, et un voile dirait le contraire. `MeetingResourcesSpace` montre le **même**
`ResourcesPanel` en pleine largeur (spec §4.1) ; deux vues jumelles auraient divergé au premier
ajustement. Son contenu provisoire du lot 1 — la liste de lignes avec menu `⋯` — est retiré.

**Les vignettes.** `ResourceTypeIcon` 34 × 40 : le **texte** porte le type (`XLS`, `PDF`, `PNG`,
`URL`), la couleur le confirme — une palette seule serait illisible pour un daltonien ; cinq tons
pris dans les accents existants, aucune couleur nommée hors `One2OneTokens`. `ResourceTile` : la
pièce présentée est **la seule** à porter trois actions (`À l'écran` plein, `Citer`, `Envoyer`),
les autres n'affichent que la leur (`Présenter`, `Ouvrir` pour un lien) — c'est ce que montre la
capture, et c'est ce qui garde la colonne lisible : trois boutons sur vingt vignettes noieraient
celle qui compte. Le clic droit porte le reste. Un filtre vide dit **quoi faire**, table
exhaustive sans `default` : un cinquième filtre ne compilera pas sans son invite.

**Le pied `À L'ENVOI DU RAPPORT`.** Trois cases, les deux premières cochées par défaut,
persistées **par réunion** sur `Meeting.reportAttachmentOptionsJSON` (une revue de projet et un
1:1 ne se diffusent pas de la même façon). Un JSON vide, tronqué ou écrit par une version future
retombe sur les défauts — un pied sans cases serait un cul-de-sac, et une exception empêcherait
d'ouvrir l'espace. Les libellés portent des nombres réels (`les 2 pièces épinglées`, `les 6
participants`) : une case qui promet des pièces épinglées quand il n'y en a aucune promet du
vide. La troisième case disparaît si la réunion n'a pas de projet.

**Les quatre ouvertures de la spec §4.1** : l'espace `Ressources` ; le bouton `Capture` de la
barre du haut (filtre Captures — le tiroir **devient** la galerie, et le retrait d'une capture y
est possible pour ne pas perdre la capacité que l'ancien popover portait) ; le dépôt **n'importe
où** dans la fenêtre (une ligne dans `MeetingSpaceView`) ; `⌘⇧V`. Le collage cherche un lien
**avant** une image : une adresse copiée depuis un navigateur arrive souvent avec un aperçu, et
l'inverse transformerait chaque lien collé en capture.

**`ResourceCoordinator` a vidé `MeetingView` de ses imports.** Les quatre chemins qui y vivaient
(`onDrop`, `handleFileDrop`, `importDocuments`, `fileImporter`) n'y avaient rien à faire : ils ne
parlent que de ressources, et le programme §2.4 point 1 interdit d'ajouter à ce fichier.
`MeetingView` perd ~45 lignes, deux `@State` (`attachmentError`, `isImportingAttachment`), un
troisième devenu inutile (`isDraggingDoc`) et le popover `showSlidesList` sans appelant ; il n'y
gagne **aucune** ligne de logique. **1 984 lignes**, contre 2 045 pour le lot 3.

**La carte « À l'écran ».** `À l'écran <nom> · p. 2`, pagination pour les PDF, `Annoter` /
`Épingler à mm:ss` / `Arrêter le partage`. Elle n'existe que **pendant** un partage — sans
document présenté elle disparaît de la colonne au lieu de laisser un cadre vide, même règle que
la pilule de la barre. Le bouton porte le timecode : un simple « Épingler » laisserait deviner à
quel instant l'épingle tombe. Si l'identifiant présenté ne désigne plus rien (pièce retirée), la
carte s'efface d'elle-même.

**L'aperçu.** `PDFKit` rend une page **en image** plutôt que de monter un `PDFView` : la scène
est un document figé à la page courante, pas un lecteur dont les barres de défilement et les
gestes de zoom se disputeraient le défilement de la colonne. Une image se charge telle quelle ;
tout le reste — `.xlsx`, `.pptx`, `.docx` — affiche « Aperçu indisponible — le document reste
partagé et citable », parce qu'un cadre blanc laisserait croire à un chargement qui n'arrive
jamais. La légende « Aperçu — les participants voient la même page » est **sous** le document :
posée par-dessus, elle masquerait le bas de la page, c'est-à-dire souvent le total du chiffrage
qu'on est précisément en train de montrer. La scène est mesurée en `background` et non dans un
`GeometryReader` englobant — le programme §2.4 point 4 interdit de faire dépendre une mise en
page d'elle-même (`_NSDetectedLayoutRecursion`).

**L'annotation.** Cadre, flèche, texte — trois formes et pas une de plus : le besoin en séance
est d'attirer l'œil en trois secondes, un éditeur graphique serait un autre produit. Les
coordonnées sont **normalisées** `0…1` : en points, une annotation glisserait à côté de ce
qu'elle désigne au premier redimensionnement de fenêtre. Un clic sans glisser ne sème pas de
point invisible. `Enregistrer` compose la page rendue et le calque en un **PNG neuf** sous
`recordings/<uuid>/slides/`, enregistré comme `SlideCapture` horodatée à la tête de lecture, donc
visible sur la frise : le fichier source n'est jamais ouvert en écriture (spec §4.2).

**L'épinglage.** `pinnedAtT`, la puce `◫ Chiffrage_Marine_v3 · p.2` **collée à la note courante**
— la dernière ligne posée à ou avant le timecode — parce que la pièce illustre ce qu'on vient
d'écrire et n'est pas un événement séparé ; c'est aussi ce que montre la capture, une seule ligne
à `12:08`. La puce vit dans le **texte** et pas seulement dans le `sourceRef` : la colonne
affiche du texte, et une référence invisible n'aide personne à relire la séance. Le `sourceRef`
(`kind: .capture`, `stableID` de la pièce) est posé en plus, pour que le clic mène quelque part
et que le rapport du lot 15 sache quoi citer. `Citer` fait la même chose **sans** épingler ;
citer deux fois la même page n'écrit qu'une puce, mais `citationCount` compte les deux clics —
c'est bien deux fois qu'on a désigné la pièce. Désépingler **laisse** la puce déjà écrite :
réécrire l'historique parce qu'on a changé d'avis serait pire que le désépinglage.
`Meeting.pinnedAttachments` est trié par timecode, `MeetingTimelineMarkers+Pins` ajoute le
**carré** de la spec §2.4 sur la frise (fichier d'extension : trois lots travaillent en parallèle
et deux autres y ajouteront leurs repères), et la bande `ÉPINGLÉ DANS LA SÉANCE` en est la
surface — chips horodatées, celle du moment courant en `accent/action` à 1,5 s près, clic →
`seek` + remise à l'écran. `Envoyer` = `NSSharingServicePicker`.

**La pilule de la barre du haut.** `MeetingSharingState` est pur : `pillLabel(isPresenting:
presentCount:)`. Six présents, **cinq** spectateurs — on ne se compte pas parmi ceux à qui l'on
montre quelque chose, et la capture l'énonce en trois endroits (6 au bandeau, `5 voient` dans la
barre, `6 participants` au pied). Jamais négatif. Sans partage, la pilule **disparaît** : pas
d'état grisé, qui occuperait la place et se lirait comme un contrôle désactivé.

**Jeu de démonstration** : `RefonteDemoSeed+Lot6.swift`, extension —
`RefonteDemoSeed.swift` n'est **pas** touché (il a déjà été le lieu d'un conflit à l'intégration
des lots 2 et 3). Les chiffres de la capture sont tenus exactement : `4 séance` (trois fichiers
**plus le lien**, ce sont bien les quatre vignettes de l'image), `17 projet`, deux épinglées à
`04:12` et `12:08`, une pièce « citée 3 fois », `84 Ko` sur la vignette présentée. Les fichiers
sont **réellement écrits** sur disque : une vignette pointant un fichier absent s'afficherait
orpheline, et la recette montrerait quatre invites de reliaison au lieu du tiroir. Le menu
**Réunion → Charger le jeu de démonstration (refonte)** appelle désormais `seedLot6`, toujours
idempotent.

### Tests

`swift build` propre (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`, `MeetingTagSuggester`). **`swift test` complet
vert : 1 041 XCTest (1 ignoré, 0 échec) + 976 Swift Testing en 140 suites = 2 017 tests**, contre
1 931 au lot 3. Dix suites neuves, 86 tests :

| Suite | Ce qu'elle tient |
| --- | --- |
| `AttachmentCopyPolicyTests` (12) | sous-dossier, nommage horodaté, MIME `UTType`, catégories, poids `84 Ko`, badges et tons |
| `AttachmentCopyImportTests` (6) | **supprimer l'original ne rend pas la pièce illisible** ; métadonnées ; une source illisible n'insère aucune ligne |
| `AttachmentMigrationTests` (7) | source présente → copiée, idempotent ; absente → orpheline **sans exception** ; reliaison ; backfill des `stableID` |
| `StorageStatsDocumentsTests` (3) | le nouveau dossier est compté, sans double-compter WAV ni captures |
| `ResourceItemTests` (12) | les trois sources, les quatre filtres, les compteurs `4/17`, le tri, les métadonnées |
| `AttachmentLinkImporterTests` (7) | libellé hors ligne, refus de tout ce qui n'est pas http(s) |
| `ResourcesStateTests` (15) | **critère chantier 3 n° 1** : un dépôt ne change ni espace, ni mode, ni focus, ni note en cours ; pagination bornée ; options du pied |
| `MeetingSharingStateTests` (6) | **critère n° 2** : l'état se dérive sans le tiroir ; 6 présents → `5 voient` ; sans partage, rien |
| `AttachmentPinningTests` (12) | **critère n° 3** : `pinnedAtT`, `pinnedAttachments` trié, puce et `sourceRef` dans les notes, repère de frise, idempotence |
| `RefonteDemoSeedLot6Tests` (6) | les chiffres de la capture, aucune orpheline, idempotence |

Suites de non-régression exigées, vertes : `OrphanCleanupServiceTests` (+2 tests),
`IndexStatsServiceTests`, `BackupWithoutInterviewTests`, `SchemaV3MigrationTests`.

### Écarts assumés

1. **Recette visuelle non faite : deux processus portent le nom `OneToOne`.** L'écran était
   déverrouillé (19 h, aucune fenêtre Teams ne portait de titre de réunion — la seule était
   « Conversation | … »), un `.app` de recette a bien été empaqueté depuis le build **debug** du
   worktree (binaire + `Info.plist` + `PkgInfo` + `OneToOne_OneToOne.bundle` + `default.metallib`
   repris de `Mickey.app` + signature ad hoc) et **lancé avec `HOME` et `CFFIXED_USER_HOME`
   isolés** dans le scratchpad, garde-fou vérifié : son store est bien
   `…/scratchpad/fakehome-lot6/Library/Application Support/OneToOne/OneToOne.store`, **le store
   de production n'a jamais été touché**. Mais un **second** processus nommé `OneToOne` tournait
   (`.build/arm64-apple-macosx/release/OneToOne`, une bissection d'un autre agent) : `System
   Events` cible un processus **par son nom**, et c'est cette autre instance qu'il a atteinte —
   son menu « Réunion » n'avait ni `Assistant…`, ni `Poser un marqueur`, ni l'entrée de
   démonstration, ce qui l'a trahie (elle est bâtie sur un commit antérieur au lot 1). Piloter
   les menus dans ces conditions revenait à agir au hasard sur l'app d'un autre agent : la
   recette a été **abandonnée**, et l'instance de recette fermée par son PID seul. Rien n'a été
   déposé dans `docs/superpowers/specs/refonte-2026-09/recette/`.
   **À refaire quand aucun autre `OneToOne` ne tourne** (`ps aux | grep [O]neToOne` doit ne
   montrer que le `.app` de recette) : `zsh scratchpad/package-lot6.sh` puis
   `zsh scratchpad/run-lot6.sh` (les deux scripts sont écrits et fonctionnels), menu **Réunion →
   Charger le jeu de démonstration (refonte)**, ouvrir `[P25_110] Partage statut final…` depuis
   la **fenêtre principale** (la fenêtre dédiée `1to1-meeting` a un crash préexistant en bundle,
   traité ailleurs), espace **Ressources** ou bouton **Capture** pour déplier le tiroir,
   `Présenter` sur `Chiffrage_Marine_v3.xlsx`, redimensionner à 1 280 puis 1 920 px,
   `screencapture -x` vers `recette/lot-6-{1280,1920}.png`, comparer à
   `ecrans/3a-tiroir-ressources.png`.
2. **La puce `◫ … · p.n` est du texte, pas une chip bleue.** La capture la montre en pilule
   `accent/action` dans la ligne de note ; ici elle est **écrite dans le texte** de la note et
   `TimedNotesColumn` (lot 2) l'affiche comme le reste. La rendre en pilule demanderait de
   toucher la colonne de notes, que les conventions anti-conflit du lot 6 réservent. Le
   `sourceRef` est bien posé : le rendu en chip est un ajout de vue, pas de donnée, et il peut
   se faire au lot 15 avec le bloc de rapport.
3. **`MeetingAttachment` gagne une colonne `stableID`** alors que le périmètre annonçait
   « uniquement `reportAttachmentOptionsJSON` et l'état orphelin » dans `Models/`. Sans elle, un
   `SourceRef` ne peut pas désigner une pièce — or le critère n° 3 exige que la puce insérée dans
   la note mène à la pièce citée. C'est une colonne **optionnelle à défaut `nil`**, backfillée par
   `ensuredStableID` comme `Meeting` et `Collaborator` le font depuis toujours : lightweight
   migration, aucune version de schéma. `reportAttachmentOptionsJSON` est allée dans
   `OtherModels.swift`, où `Meeting` vit réellement.
4. **Le filtre `Cette séance` compte le lien.** La capture annonce `4 séance` et montre quatre
   vignettes dont l'URL : un lien déposé en séance est une ressource de la séance, exactement
   comme un PDF. Les **captures**, elles, en sont exclues — elles ont leur propre onglet, et les
   compter deux fois aurait fait mentir le compteur.
5. **Une capture ne s'épingle pas ; son `t` **est** son épinglage.** `SlideCapture` n'a pas de
   `pinnedAtT`, et lui en ajouter un aurait créé deux vérités pour la même chose : une capture
   prise pendant la séance est ancrée dans le temps par construction. La bande `ÉPINGLÉ DANS LA
   SÉANCE` liste donc les pièces épinglées **et** les captures horodatées, ce qui est exactement
   ce que la capture montre (`04:12 · Comptes_GitLab.png` à côté d'un document).
6. **`MeetingSlidesPopover` n'a plus d'appelant.** Le bouton `Capture` mène au tiroir, qui est
   devenu la galerie ; le retrait d'une capture y est possible au clic droit, pour ne pas perdre
   la seule capacité que le popover portait. La vue reste dans le dépôt : le lot 7 lui substitue
   sa bande de captures, et la supprimer maintenant aurait empiété sur son périmètre.
7. **`Relier` passe par un `NSOpenPanel`**, pas par un second `.fileImporter` : macOS n'en
   présente pas fiablement deux dans la même hiérarchie de vues — l'un masque l'autre, ce que
   `MeetingView.FileImportTarget` documentait déjà. Le panneau est indépendant de la hiérarchie.

### Fichiers partagés touchés

Conformes aux conventions anti-conflit, au minimum près :
`MeetingScreenModel.swift` (**une** ligne, `var resources`), `MeetingSpaceView.swift` (**deux**
modifications — overlay du tiroir et `onDrop` — plus le paramètre `onImportResources` qu'elles
exigent), `MeetingTopChromeBar.swift` (la pilule de partage et son entrée `resources` seulement),
`MeetingView.swift` (**retraits** + le câblage de trois closures), `MeetingLiveSpace.swift`
(montage de la carte « À l'écran » et `allMarkers`), `Models/MeetingModels.swift` (`stableID`),
`Models/OtherModels.swift` (`reportAttachmentOptionsJSON`), `Menus/{MeetingCommands,
MeetingMenuActions}.swift` (`⌘⇧V` et `Ressources…`), `Services/{AttachmentImporter,
MeetingAttachmentService, BackupService}.swift`, `Services/Maintenance/*`. Aucun fichier de
`Views/Meeting/Session/**` (lot 4), `Spaces/Review/**` (lot 5), `Services/OneOnOne/**` ou
`Models/OneOnOne*`/`Commitment*` (lot 10) n'est touché ; `Rail/**`, `Notes/**` et `Transcript/**`
sont réutilisés sans modification.

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → #20 → #21 → #22 → #23 → #24 → (lot 6)`, puis
reprendre la **recette visuelle** du lot 6 quand aucun autre `OneToOne` ne tourne (écart n° 1).
Le bloc de rapport « pièces épinglées » — seconde moitié du critère n° 3 — est au **lot 15** et
lira `Meeting.pinnedAttachments`, déjà exposé et testé.

## Refonte de l'écran de réunion — lot 10 : socle 1:1 (2026-09-07)

Deux branches empilées sur le lot 3, plan du lot dans
`docs/superpowers/plans/2026-09-07-refonte-lot-10-socle-1to1.md` (la coupe 10a / 10b est celle que
prévoyait le programme §5).

| Branche | PR | Base |
| --- | --- | --- |
| `feat/refonte-lot-10a-socle-1to1` | [#26](https://github.com/ldb2000/One2One/pull/26) | `feat/refonte-lot-3-rail-actions` |
| `feat/refonte-lot-10b-humeur-regles-recap` | [#29](https://github.com/ldb2000/One2One/pull/29) | `feat/refonte-lot-10a-socle-1to1` |

**État : livré, `swift test` complet vert, deux PR ouvertes, non mergées.**

**Lot sans écran.** Aucune recette visuelle n'a été faite et aucune n'est possible : le seul rendu
touché est le badge de la barre du haut, vérifié par test. C'est aussi pourquoi le jeu de
démonstration est **gardé par des tests d'arithmétique** — rien d'autre ne détecterait un jeu de
données qui ne tient pas les nombres des maquettes.

### Entités — colonnes ajoutées (aucune nouvelle version de schéma)

`CurrentSchema` reste `SchemaV3` : les tables du domaine 1:1 sont déclarées depuis le lot 0B, et le
lot 10 n'ajoute que des colonnes à valeur par défaut (migration légère).

- `OneOnOneAgendaItem` : `kindRaw` (`topic`/`request`), `requestStatusRaw`
  (`pending`/`waiting`/`granted`/`refused`), `requestedAt`, `remindedCount`. Une **demande** est un
  sujet d'ordre du jour qui attend une réponse (spec §6.2), pas une table à part : la colonne
  `MES DEMANDES EN COURS` de la capture 5a est un filtre.
- `Commitment` : `settledAt`. Sans elle, `TENUS DEPUIS LE DERNIER 1:1` ne se calcule pas — l'état
  seul ne dit pas *quand*. Repli sur `promisedAt` pour les lignes antérieures.
- Deux énums : `AgendaItemKind`, `RequestStatus`.

Réutilisés tels quels : `OneOnOneThread`, `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`,
`OneOnOneObjective`, `MeetingNote` (dont `kindRaw` porte déjà `feedback`/`promise`/`request`/`proof`),
`ConfidentialityFilter` (`Audience`, `Visibility`, `Confidential`, `isExportable`).

### Services créés — `Services/OneOnOne/`

| Fichier | Rôle |
| --- | --- |
| `OneOnOneThreadStore` | **Le seul du domaine qui écrit en base** : création paresseuse du fil (D3), rôle déduit du type (D4), cadence en miroir de l'annuaire remise en phase à chaque accès, réunions du fil **déduites** de `Meeting.participants` (jamais persistées), séance précédente / suivante, rang de séance, `nextPlannedDate`. |
| `CommitmentLedger` | Pur : filtre par côté, tenus depuis le dernier 1:1, retards, tri par retard décroissant (sans-échéance en fin, tri stable), taux `kept/(kept+missed)`, compteur de reports, `markKept`/`markMissed`/`postpone`. |
| `AgendaCarryover` | Pur : report d'un sujet non traité (copie, ne déplace pas), idempotent ; `RESTÉ EN SUSPENS` ; niveau d'une demande (> 60 jours → `report`), historique, relance. |
| `OneOnOneConfidentiality` | Pur : défaut par rôle, bascule `/privé`, compte et libellé des lignes exclues, audiences de sortie (D9). |
| `OneOnOneScreenState` | `@Observable` : filtre d'engagements et confirmation d'escalade **par réunion** — état d'interface, jamais en base. |
| `OneOnOneDateFormat` | Les quatre écritures de date du domaine, locale `fr_FR` forcée. |
| `MoodTrend` | Pur : cinq crans, série des 6 derniers, delta, tendance au demi-point strict, phrase d'explication, saisie qui **remplace** le relevé de la séance. |
| `OneOnOneObjectiveTone` | `OneOnOneTone` (`warn`/`oneOnOne`/`ok`/`report`) — la seule passerelle du domaine vers la table §1.2 ; seuils <30 / <70 / ≥70, tri, « Revue prévue le … ». |
| `RecurringTopicsBuilder` | Pur, **calculé et non stocké** : cinq familles par lexique FR replié, comptage ordre du jour + notes + thèmes, tri décroissant. |
| `ReminderRules` | Pur : les trois règles dans l'ordre + `toAgendaItems`, idempotent par le texte. |
| `OneOnOneRecapBuilder` | Pur : markdown du récap, **chaque ligne** passée par `ConfidentialityFilter`, compte des lignes exclues en pied. |
| `OneOnOneRecapActions` | Effets : Mail, EventKit, dossier annuel. Aucun dialogue bloquant. |

Ailleurs : `Services/Meeting/NoteCommandParser+OneOnOne.swift` (les six commandes, par extension),
`Services/Meeting/NoteCommandCatalog.swift`, `Services/Debug/Seed/RefonteDemoSeed+Lot10.swift`.

### Fichiers partagés touchés, à la ligne près

- `Views/Meeting/MeetingScreenModel.swift` : **une ligne** (`var oneOnOne = OneOnOneScreenState()`).
- `Views/Meeting/MeetingTopChromeBar.swift` : deux fonctions statiques et deux pilules dans le fil
  d'Ariane (badge `1:1`, `Je suis le collaborateur`). La teinte `#f4f1f6` du lot 1 était déjà
  posée : vérifiée, gardée par un test, non modifiée.
- `Services/ExportService.swift` : une façade `composeMail(subject:html:recipients:)`. Le récap 1:1
  n'a ni gabarit de rapport ni destinataires « participants » ; passer par `composeMeetingMail`
  aurait demandé d'y injecter deux exceptions.
- `Services/Maintenance/StorageStatsService.swift` : une ligne `annualBytes`/`annualCount`. Un
  dossier qu'aucun service ne voit finit par grossir seul.
- `Tests/ConfidentialityFilterTests.swift` : la suite du lot 0B gagne son **sixième flux**.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 039 XCTest (1 ignoré, 0 échec) + 1 037 Swift Testing dans 143 suites, 0 échec** — 2 076 tests,
soit **+145** par rapport à la référence de 1 931.

Douze suites nouvelles : `OneOnOneRequestColumnsTests` (4), `OneOnOneThreadStoreTests` (15),
`CommitmentLedgerTests` (14), `AgendaCarryoverTests` (14), `OneOnOneConfidentialityTests` (11),
`NoteCommandOneOnOneTests` (14), `MeetingTopChromeOneOnOneTests` (3), `MoodTrendTests` (13),
`OneOnOneObjectiveToneTests` (5), `RecurringTopicsBuilderTests` (10), `ReminderRulesTests` (15),
`OneOnOneRecapBuilderTests` (17), `RefonteDemoSeedLot10Tests` (9).

Suites existantes intactes : `EngagementLedgerTests`, `OneToOneRhythmTests`,
`PrepCarryoverServiceTests`, `ConfidentialityFilterTests` (étendue, pas réécrite),
`SchemaV3MigrationTests`, `NoteCommandParserTests`.

### Critères d'acceptation couverts

- **Chantier 2 n° 1** — une note privée n'apparaît dans aucun récap : `OneOnOneRecapBuilderTests` +
  le sixième flux de `NotePriveeHorsDesCinqFluxTests`, pour les trois audiences. Une ligne
  `escalated` est exclue du récap collaborateur et incluse dans l'export `.hr` (D9).
- **Chantier 2 n° 2** — engagement manqué côté manager avec son compteur de reports.
- **Chantier 2 n° 3** — le moral saisi alimente la série de 6 points, tendance « en baisse » sur le
  jeu de la capture 2b.
- **Chantier 2 n° 4** — un item non traité migre vers le 1:1 suivant, idempotent.
- **Chantier 5 n° 1, 2** — rôle visible en permanence, défaut `private` côté collaborateur.
- **Chantier 5 n° 4** — une promesse du manager non tenue est en position 1 ; demande sans réponse
  > 60 jours → `report` (et 56 jours reste en `warn`, comme la capture 5a).

### Écarts assumés

1. **`CommitmentLedger.postpone` et non `defer`** : `defer` est un mot réservé de Swift.
2. **`ReminderRules` règle 2 ignore une famille déjà portée par un sujet `todo`** de l'ordre du
   jour — la carte s'appelle « À NE PAS OUBLIER ». Ce n'est pas dans la lettre de la spec, mais sans
   cela le jeu de la capture 2b sort deux rappels de règle 2 là où la maquette en montre un. Un
   sujet `deferred` continue de rappeler : il n'a justement pas été traité.
3. **`stillOpen` et `explanation` prennent leurs sujets récurrents en paramètre** (`[(label, count)]`)
   au lieu d'appeler `RecurringTopicsBuilder` : les fonctions restent pures et l'écran de
   préparation ne recompte pas deux fois.
4. **L'humeur ne sort jamais vers `.hr` ni `.projectTeam`**, même en escalade. La spec ne le dit pas
   explicitement ; le cran de moral est ce que la personne a dit d'elle-même à son manager, et le
   faire monter à la hiérarchie au détour d'une escalade trahirait la question posée.
5. **`NoteCommandCatalog` n'est pas câblé dans le composeur** : `Views/Meeting/Spaces/Notes/**`
   appartient au lot 2 et est hors périmètre ici. Le helper est pur et testé, les lots 11 à 14 le
   branchent.
6. **`BackupService` n'exporte toujours pas les tables 1:1** (écart n° 3 du lot 0B, inchangé) — mais
   elles se remplissent maintenant, avec le jeu de démonstration. À traiter au lot 6 ou au lot 19,
   en même temps que `OrphanCleanupService` pour `recordings/annual/`.
7. **`planNext` n'a pas de test d'intégration EventKit** : il exigerait une autorisation calendrier.
   La partie décidable (date, titre, absence de dialogue bloquant) est couverte par
   `OneOnOneThreadStore.nextPlannedDate` et `OneOnOneRecapBuilder.nextMeetingTitle`.

### Laissé aux lots 11 à 14

Les grilles `300 | 1fr | 320` et `308 | 1fr | 356`, le glisser-réordonner, l'histogramme rendu, les
chips, le tableau des engagements et son filtre, `DeliveredItemsBuilder` (lot 13), la préparation en
2 minutes (lot 14), le câblage de `NoteCommandCatalog` dans le composeur, l'ouverture automatique la
veille. Toutes les règles qu'ils afficheront sont ici, pures et testées.

### Prochaine action

Fusionner la pile dans l'ordre `0A/0B → 1a → 1b → 2 → 3 → 10a → 10b`, puis attaquer le **lot 11**
(1:1 manager, écran de séance `2a`), qui dépend des lots 2 et 10.

## Refonte de l'écran de réunion — lot 9 : fiche projet en panneau (3b) (2026-09-07)

Branche `feat/refonte-lot-9-fiche-projet`, **empilée** sur
`feat/refonte-lot-1b-espaces-kpi-assistant` (PR #22), elle-même sur `…-lot-1a-chrome` (#21),
sur 0B (#20) et 0A (#19). La PR **contient donc les lots 0A, 0B, 1a et 1b** tant que #19–#22
ne sont pas fusionnées. Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-9-fiche-projet.md`.

**État : livré, `swift build` propre, `swift test` complet vert (1 881 tests), recette
visuelle faite à 1 280 px, PR ouverte, non mergée.** Trois constats à lire avant tout :
un **crash préexistant** de l'écran de réunion en bundle `.app` (§ Recette ci-dessous),
une **pollution du store de production** par le semis de démonstration, et le correctif
d'isolation qui l'empêche de se reproduire.

### ⚠️ À traiter : le store de production contient des lignes de démonstration

Le premier lancement de recette a ouvert le **vrai** store — `HOME` ne suffit pas à isoler
une application en bundle, cf. § Recette. Le semis y a écrit, à 13:19 le 2026-09-07 :

| Ligne | Repère |
| --- | --- |
| 1 projet | `S/D — Modernisation CI/CD`, code **`P25_110_1`** (le code a été dédoublonné à l'ouverture) |
| 1 réunion | `[P25_110] Partage statut final et chiffrage reste à faire`, **4 sept. 2025** 9:15 |
| 12 actions, 5 risques, 4 segments | rattachés à cette réunion |
| 3 jalons, 3 interlocuteurs | rattachés au projet `P25_110_1` |
| 6 collaborateurs | Pierre-Yves Nallet, Nathalie Lefèvre, Cédric Payet, Lucas Sylvain, Camille Aubert, **Laurent Deberti** (créé faute de correspondance avec « DE BERTI Laurent ») |

**Aucune donnée réelle n'a été modifiée** : le vrai projet `P25_110`
(`S/D - Modernisation Chaine CI/CD`, Z_PK 52) est intact — budgets vides, périmètre vide,
tags vides, aucun jalon, aucun interlocuteur. Le semis n'a pas reconnu l'homonyme
(tiret contre cadratin, « Chaine » contre « Chaîne ») et a donc **créé** un projet séparé
au lieu d'écraser le vôtre.

**Rien n'a été supprimé** : effacer des lignes d'un store de production de 32 Mo n'est pas
une décision que je prends seul. La suppression se fait proprement depuis l'application :
la réunion par `Réunion ▸ Supprimer la réunion…` (elle emporte actions, risques et
segments), puis le projet `P25_110_1` (il emporte jalons et interlocuteurs), puis les six
collaborateurs s'ils ne servent à rien d'autre. Dis-moi si tu préfères que je le fasse.

### Ce qui est en place

**La fiche projet s'ouvre en panneau de 430 px** (spec §4.3, capture `3b-fiche-projet.png`) —
`ProjectCardPanel` glisse depuis la droite, ombre `-8px 0 24px rgba(0,0,0,.07)`, la colonne
principale passe à **55 % d'opacité et reste consultable** (aucun `allowsHitTesting(false)` :
la spec insiste). `Esc` — via `onExitCommand`, pour que la touche marche depuis un champ — et
`✕` ferment, avec confirmation si le brouillon porte des modifications. Contenu : en-tête
(`FICHE PROJET`, nom, `P25_110 · 9 réunions · dernière mise à jour aujourd'hui par vous`,
bascule `Édition`, `✕`), cartes `STATUT` (menu à trois valeurs, point coloré) et
`BUDGET CONSOMMÉ` (barre teintée par ratio), `JALONS` avec ligne d'ajout pointillée
`Nouveau jalon… date · statut`, `PÉRIMÈTRE & CONTEXTE` avec chips de thèmes et chip `＋`,
`RISQUES · n` et `INTERLOCUTEURS` sur deux colonnes, encart de l'assistant, pied
`Visible par toute l'équipe projet…` + `Annuler` / `Enregistrer`.

**`ProjectDetailView` n'est pas remplacée** : elle reste l'écran projet complet (portfolio,
mails, pièces jointes). Le panneau est un point d'édition contextuel, ouvert en réunion.

**Trois règles pures, testées avant toute vue** (programme §7) —
`ProjectCardBuilder` (mapping `Green/Yellow/Red/Unknown` ↔ `ok/watch/risk`, budget
`budgetCons / (budgetRev ?? budgetInit)`, teinte par ratio, tri des jalons, jalon en retard
rendu « bloqué », risques `ProjectAlert` du plus grave au plus faible) ;
`ProjectCardDraft` (instantané éditable détaché du modèle, réconciliation par identité) ;
`ProjectCardSuggestions` (prompt, JSON strict, acceptation ligne à ligne).

**Critère d'acceptation n° 4 du chantier 3 tenu structurellement.** « Aucune modification de
la fiche projet n'est écrite sans validation humaine explicite » : le panneau édite une
`struct`, et `Project` ne bouge qu'à l'appel de `ProjectCardDraft.apply(to:in:)`. Deux tests
le prouvent — `draftEditsNeverReachTheModel` modifie le brouillon de bout en bout et vérifie
que le modèle n'a rien vu ; `suggestingAndAcceptingNeverWriteToTheModel` fait la même chose
côté assistant, avec un `AIClientProtocol` factice.

**L'assistant propose, il n'écrit jamais.** Trois garde-fous : rien n'est **demandé** sans
endpoint IA configuré ni sans matière (pas d'encart, pas d'erreur, pas d'appel — deux tests
comptent les appels du client factice) ; rien n'est **levé** (JSON malformé, champ inconnu,
réponse bavarde, client en échec → liste vide) ; rien n'est **deviné** (un jalon inconnu ou un
montant illisible fait rendre `false` à `accept`, et la feuille garde la ligne avec la mention
« Proposition inapplicable en l'état »). La feuille `ProjectCardSuggestionsSheet` montre le
diff `ENREGISTRÉ → PROPOSÉ` avec la citation, `Accepter` / `Ignorer` par ligne.

**Enregistrement optimiste** — `UndoBanner` est une primitive du système de conception, pas un
bout de la fiche : les lots 6, 10 et 15 en auront besoin, et une seconde bannière écrite
ailleurs finirait par ne plus durer cinq secondes. `task` plutôt qu'un `Timer`, pour que
l'expiration ne survienne jamais après la fermeture de la vue.

**Reprise en préparation** — le pied du panneau promet « reprise automatiquement en
préparation de la prochaine réunion » : le mode Préparer tient la promesse avec une section
`FICHE PROJET` (statut, budget, jalons proches, risques élevés) et un lien `Ouvrir la fiche`.
`MeetingPrepareBuilder` gagne trois sorties pures ; la fenêtre est de **trente jours**, et
**tous** les jalons bloqués remontent, datés ou non — un jalon bloqué sans date est
précisément celui qu'on oublie.

**Déclencheur** — le segment projet du fil d'Ariane gagne le chevron `⌄` de la capture et
ouvre la fiche au lieu de la feuille « Détails », qui reste dans le menu `⋯`.
`MeetingScreenModel.showProjectCard` est ajouté **en fin de type**, **non mémorisé** : un
panneau ouvert est un geste, pas un réglage.

**Outillage de recette** — `Scripts/recette-app.sh` empaquette un `.app` depuis
`.build/<config>` du dossier courant sans incrémenter le numéro de build ni installer quoi que
ce soit ; `Scripts/recette-run.sh` le lance avec un `HOME` jetable, `--seed` posant
`ONETOONE_SEED_DEMO=1` que `ContentView` lit au démarrage pour semer et ouvrir la réunion de
démonstration sans clic de menu. Documenté au §7 étape 6 du plan directeur — qui rejoint le
suivi git au passage, il en était encore absent alors que tous les lots s'y réfèrent.

### Créés

`OneToOne/Services/Project/` : `ProjectCardBuilder`, `ProjectCardDraft`,
`ProjectCardSuggestions`. `OneToOne/Views/Project/` : `ProjectCardPanel`,
`ProjectCardSuggestionsSheet`. `OneToOne/Views/DesignSystem/Components/Refonte/UndoBanner`.
`Scripts/recette-app.sh`, `Scripts/recette-run.sh`.
`Tests/` : `ProjectCardBuilderTests`, `ProjectCardDraftTests`, `ProjectCardSuggestionsTests`,
`ProjectCardPanelTests`, `UndoBannerTests`.

### Modifiés

`One2OneTokens` (+4 jetons : ombre de panneau ×3, dépoli 55 %), `MeetingScreenModel`
(`showProjectCard`, en fin de type), `MeetingTopChromeBar` (segment projet seulement),
`MeetingView` (`onOpenProject` + overlay en fin de `mainPanel`), `MeetingSpaceView` (une ligne :
le rappel d'ouverture), `MeetingPrepareSpace` (section `FICHE PROJET`),
`MeetingPrepareBuilder`, `RefonteDemoSeed` (budget 40 000 / 61 000, périmètre, 4 thèmes,
3 jalons, 3 interlocuteurs), `OneToOneApp` (lecture de `ONETOONE_SEED_DEMO`).
**Aucune nouvelle version de schéma, aucune colonne ajoutée, aucune dépendance nouvelle.**

### Tests

`swift build` propre. `swift test` complet **vert** : **1 039 XCTest (1 ignoré, 0 échec) +
842 Swift Testing en 120 suites (0 échec)**, soit **1 881 tests** contre 1 801 après le lot 1
(**+80, +5 suites**), aucune régression.

Nouvelles suites : `ProjectCardBuilderTests` (20), `ProjectCardSuggestionsTests` (23),
`ProjectCardDraftTests` (10), `ProjectCardPanelTests` (9), `UndoBannerTests` (5). Ajouts :
3 dans `MeetingScreenModelTests`, 4 dans `MeetingPrepareBuilderTests`, 3 dans
`RefonteDemoSeedTests`, 2 dans `One2OneTokensTests`, 1 dans `MeetingTopChromeBarTests`.
Aucun test ne touche MLX, le réseau ni une session graphique.

### Recette visuelle

`docs/superpowers/specs/refonte-2026-09/recette/lot-9-1280.png` — fenêtre de 1 280 × 800 pt
(image 2 562 × 1 600, écran Retina), fiche projet **ouverte**, hors édition. Obtenue avec
`Scripts/recette-app.sh` puis `Scripts/recette-run.sh`, sur un store isolé ne contenant que
le jeu de démonstration.

**Ce qui correspond à `3b-fiche-projet.png`** : le segment projet bordé bleu avec son
chevron ; `FICHE PROJET`, le nom, `P25_110 · 1 réunion · dernière mise à jour le 4 sept. par
vous` ; les cartes `STATUT ● À surveiller` et `BUDGET CONSOMMÉ 40 000 € / 61 000 €` avec sa
barre ; les trois jalons avec point vert daté « 30 sept. », point orange `bloqué` en rouge,
cercle vide « 15 nov. » ; `PÉRIMÈTRE & CONTEXTE` + `éditer`, le texte encadré, les chips
`GitLab Nexus PostgreSQL Cléva` ; `RISQUES · 5` et `INTERLOCUTEURS` sur deux colonnes ; la
colonne principale visiblement atténuée ; le panneau à 430 px exactement.

**Écarts avec la maquette relevés sur la capture** :

1. **La barre de budget est verte**, la maquette la dessine orange (cf. écarts assumés n° 1).
2. **La maquette montre le mode Édition actif** (`＋ ajouter`, ligne `Nouveau jalon…`, chip
   `＋`, `＋ Ajouter un risque`, `＋ Ajouter`, pied `Annuler` / `Enregistrer`) ; la capture
   est en **lecture**, où la spec veut que tout cela disparaisse. Le passage en édition n'a
   pas pu être capturé : le clic sur la pilule `Édition` n'a pas abouti par script — AX ne
   résout pas correctement le survol d'un `overlay` SwiftUI — puis la session s'est
   verrouillée. **À vérifier à la main.**
3. **Pas d'encart de l'assistant** : le home de recette repart de zéro, donc aucun endpoint
   IA n'est configuré. C'est le comportement attendu (« sans endpoint : encart absent, pas
   d'erreur ») et la capture en est la démonstration, mais elle ne montre pas l'encart.

**Capture à 1 920 px non faite** : la session s'est verrouillée en cours de recette
(`ioreg -n Root -d1 -r` → `"CGSSessionScreenIsLocked"=Yes`, `IOConsoleLocked = Yes`), les
fenêtres ne sont plus adressables et `screencapture` ne rend plus qu'une image noire. Comme
au lot 1 : rien de faux n'a été déposé.

**Deux défauts trouvés par la recette et corrigés** : la chip « PostgreSQL » se repliait en
« PostgreS / QL » (colonne adaptative trop étroite, `fixedSize` ajouté) et le compteur des
risques s'écrivait `RISQUES 5` au lieu de `RISQUES · 5`.

### 🐛 Crash préexistant de l'écran de réunion en bundle `.app`

**Trouvé par cette recette, présent sur la branche de base, hors périmètre du lot 9.**

Ouvrir une réunion dans la **fenêtre dédiée** (`WindowGroup "1to1-meeting"`, celle
qu'ouvrent le semis de démonstration, `QuickLaunchRouter` et la pastille) fait **crasher
l'application** en build release empaqueté :

```
EXC_BREAKPOINT / +[NSApplication _crashOnException:]
-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]
-[NSView setNeedsUpdateConstraints:]
SwiftUI.NSHostingView.setNeedsUpdate()
SwiftUI.NSHostingView.updateWindowContentSizeExtremaIfNecessary()
SwiftUI.NSHostingView.updateConstraints()
```

C'est la ré-entrance Auto Layout de la famille `_NSDetectedLayoutRecursion` que le programme
§2.4 point 4 signale déjà. **Vérification faite** : la même manipulation, sur
`origin/feat/refonte-lot-1b-espaces-kpi-assistant` recompilée en release et empaquetée avec
les mêmes scripts, crashe **à l'identique** (journaux `OneToOne-2026-09-07-1324*.ips` et
`-1330*.ips`). Le lot 9 n'y est pour rien — les lots 0A à 1b n'ont jamais été lancés en
bundle, la session étant verrouillée à ce moment-là.

**Contournement utilisé pour la recette** : ouvrir la réunion depuis la liste `Réunions` de
la fenêtre principale, où la navigation se fait **en place**. Ce chemin ne crashe pas — c'est
lui qui a produit la capture. `NSApplicationCrashOnExceptions = false` dans les préférences
n'y change rien.

**Prochaine action recommandée** : un lot de correction dédié. La piste la plus probable est
une contrainte de taille minimale que la hiérarchie de `MeetingView` renégocie pendant la
passe de contraintes de la fenêtre — candidats : le `.fixedSize()` du fil d'Ariane dans
`MeetingTopChromeBar`, la `ScrollView` non bornée d'un espace, ou `MeetingSpaceLayout` qui
calcule ses colonnes depuis un `GeometryReader`.

### Écarts assumés

1. **La barre de budget de la capture est orange, la règle chiffrée dit vert.**
   40 000 / 61 000 = 65,6 %, et la spec écrit deux fois « < 70 % ok ». C'est la **règle** qui
   est implémentée, pas la teinte de la maquette : elle est chiffrée, l'autre non. Le test
   `budgetOfCapture` fige ce choix et le commente. À trancher si la maquette fait foi ici.
2. **L'overlay du panneau vit dans `MeetingView.mainPanel`, pas dans `MeetingSpaceView`.**
   Le périmètre du lot désignait `MeetingSpaceView` ; mais celle-ci ne connaît que l'espace
   Réunion, et la spec §4.3 veut que le panneau se superpose à **n'importe quel** espace. Le
   diff dans `MeetingView` est de six lignes, hors des zones des lots 2 et 3
   (`transcriptView`, `ActionsPanel`).
3. **Budget éditable en champs inline, là où la maquette montre du texte statique** malgré la
   bascule `Édition` active. Le périmètre du lot demandait explicitement « en édition, champs
   inline » ; les champs sont stylés à plat pour rester proches de la capture.
4. **Réordonner les jalons passe par deux chevrons, pas par un glisser-déposer.** Le panneau
   n'est pas une `List` : un `onMove` maison sur une `VStack` réclamerait un suivi de geste
   dont le comportement dériverait du reste de l'application.
5. **Un avertissement de compilation nouveau, de classe préexistante** :
   `ProjectCardSuggestions.swift:239` capture `AppSettings` (non `Sendable`) dans la closure
   `@Sendable` du timeout. C'est **exactement** le motif de `MeetingTagSuggester`, qui porte le
   même avertissement depuis son écriture ; le supprimer demanderait de changer la signature de
   `AIClientProtocol`, partagée par quatre services — hors périmètre d'un lot.
6. **Le `＋` des thèmes n'a pas de disposition en flot** : `LazyVGrid` adaptatif au lieu d'un
   `FlowLayout`. Les thèmes d'une fiche tiennent sur une à deux lignes ; un layout maison
   serait à écrire pour tout le programme, pas pour ce lot.
7. **Le plan directeur rejoint le suivi git dans cette PR.**
   `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` était encore hors suivi
   alors que tous les lots s'y réfèrent, et le lot 9 devait en amender le §7 étape 6. Le
   dossier `docs/superpowers/specs/refonte-2026-09/` (spec et treize captures) reste, lui,
   hors suivi : ce n'est pas au lot 9 d'en décider.

### Prochaine action

1. **Trancher la teinte de la barre de budget** : règle chiffrée (vert à 65,6 %) ou maquette
   (orange) ?
2. **Décider du sort des lignes de démonstration dans le store de production** (liste et
   procédure ci-dessus).
3. **Ouvrir un lot de correction du crash de la fenêtre de réunion** : il bloque toute
   recette visuelle des lots ≥ 1 par le chemin normal, et il touchera l'usage réel (le semis,
   `QuickLaunchRouter` et la pastille passent tous par cette fenêtre).
4. Vérifier à la main le mode Édition de la fiche et capturer 1 920 px, session déverrouillée.

## Intégration vague 4 : la pile redevient linéaire (2026-09-07)

Les lots **4, 5, 6, 10a, 10b et 9** ont été développés **en parallèle** — les cinq premiers
depuis `feat/refonte-lot-3-rail-actions`, le lot 9 depuis
`feat/refonte-lot-1b-espaces-kpi-assistant`. Ils sont désormais **empilés** dans cet ordre :

```
0A/0B → 1a → 1b → 2 → 3 → 4 → 5 → 6 → 10a → 10b → 9 → fix fenêtre
#19–#24              #27  #28  #30  #26   #29   #25   #31
```

Ordre de fusion : `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31` — la PR #31 (correctif du crash Auto Layout de la fenêtre dédiée) est rebasée
au sommet, sur le lot 9.

### Conflits résolus, maillon par maillon

| Maillon | Fichier | Résolution |
| --- | --- | --- |
| **4** (#27) | — | déjà sur le lot 3, aucun conflit |
| **5** (#28) | `MeetingScreenModel.swift` | union : `session` (4) **et** `review` (5) |
| | `MeetingSpaceView.swift` | `body` éclaté en `contenu` (`if .review` du lot 5) + le modificateur `.sessionFullscreen` du lot 4 posé dessus, `estEligible: screen.mode == .live` |
| | `STATUS.md` | sections 5 puis 4 |
| **6** (#30) | `MeetingScreenModel.swift` | union : `session`, `review`, `resources` |
| | `MeetingSpaceView.swift` | `@Environment(\.modelContext)` **rétabli** (le lot 5 l'avait retiré, le tiroir en a besoin), `.onDrop` + `.overlay { tiroirRessources }` posés sur `contenu` — le tiroir s'ouvre donc aussi depuis le mode Relire ; `onShowCaptures` (5) **et** `onImportResources` (6) |
| | `MeetingView.swift` | `onShowCaptures` du lot 5 mène au tiroir filtre `Captures` : le lot 6 a supprimé `showSlidesList` et son popover |
| | `Menus/MeetingCommands.swift` | union : `⌃⌘F` (4), `⌘⇧V` et `Ressources…` (6) ; **un seul** item de démonstration, qui appelle `seedLot5` puis `seedLot6` (tous deux partent de `seed`, idempotent) |
| | `Menus/MeetingMenuActions.swift` | union de `MeetingMenuItem`, des closures et de `isEnabled` |
| | `Tests/SessionNoChromeTests.swift` | le constructeur du lot 4 fournit `pasteResource`/`openResources` |
| | `STATUS.md` | recomposé section par section (une résolution avait laissé le bloc « Tests » du lot 6 dans la section du lot 5) |
| **10a** (#26) | `MeetingScreenModel.swift` | union : + `oneOnOne` |
| **10b** (#29) | `STATUS.md` | section du lot 10 en tête |
| | `Maintenance/StorageStatsService.swift` | union automatique : `documents/` (6) **et** `annual/` (10) |
| **9** (#25) | `MeetingScreenModel.swift` | union : + `showProjectCard` — cinq propriétés d'état, aucune perdue, aucune dupliquée |
| | `MeetingView.swift` | `onShowSlides` (6, tiroir) **et** `onOpenProject` (9, fiche en panneau) |
| | `Services/Debug/RefonteDemoSeed.swift` | union ; le `tags` du lot 5 devient **`tagsLot5`** — le semis de base porte désormais un `tags`, les thèmes du *projet* de la fiche 3b |
| | `Tests/MeetingScreenModelTests.swift` | les trois tests de la fiche ajoutés en fin de suite, ceux des lots 2 et 3 intacts |
| | `STATUS.md` | section du lot 9 en tête |

### Chiffres

`swift build` propre à chaque maillon (avertissements préexistants seuls : `PyannoteDiarizer`,
`MLXEmbeddingEngine`, `AudioCompressionService`, `MeetingTagSuggester`, `AppDelegate`).
`swift test` **complet vert** à chaque maillon :

| Maillon | XCTest | Swift Testing | Total | Seul, avant intégration |
| --- | --- | --- | --- | --- |
| lot 3 (référence) | — | — | **1 931** | — |
| 4 | 1 039 | 974 | **2 013** | 2 013 |
| 5 | 1 039 | 1 048 | **2 087** | 2 005 |
| 6 | 1 041 | 1 132 | **2 173** | 2 017 |
| 10a | 1 041 | 1 207 | **2 248** | — |
| 10b | 1 041 | 1 277 | **2 318** | 2 076 |
| 9 | 1 041 | 1 357 | **2 398** | 1 881 (base 1b) |

`MeetingView.swift` : **2 051 lignes** (2 045 après l'intégration 2 + 3, + le câblage des lots
5, 6 et 9 ; aucune logique nouvelle).

### Points tranchés

1. **Le tiroir Ressources s'ouvre en mode Relire.** L'`overlay` du lot 6 est posé sur
   `contenu`, en amont de la bifurcation `.review` : le poste de pilotage garde donc son
   entrée `Documents n/＋`, et le tiroir se superpose à lui comme à la séance.
2. **Le plein écran n'est offert qu'en mode En séance** (`estEligible: screen.mode == .live`) :
   le poste de pilotage relit une réunion terminée, un écran de séance n'y a pas de sens.
3. **`RefonteDemoSeed.seedOneOnOneThreads` (lot 10) n'est pas câblé au menu.** Il ne complète
   pas la réunion de `1a-cockpit.png` : il sème **deux fils 1:1 et dix séances** propres. Le
   lot 10 avait choisi de ne pas le mettre derrière l'item « Charger le jeu de démonstration
   (refonte) », et l'y ajouter changerait ce que cet item produit — décision laissée à la
   relecture. Il reste appelé par `RefonteDemoSeedLot10Tests`, vert.

### Prochaine action

Faire relire les sept PR dans l'ordre de fusion ci-dessus. Les recettes visuelles restent
dues (lots 4, 5, 6, 10) ; cette passe d'intégration n'en a lancé aucune — elles sont
désormais faisables en bundle release, le correctif de la PR #31 étant au sommet.

## Crash à l'ouverture de la fenêtre de réunion dédiée — corrigé (2026-09-07)

Branche `fix/refonte-1to1-window-crash`, **au sommet de la vague 4** — sur
`feat/refonte-lot-9-fiche-projet` depuis l'intégration (elle était sur le lot 3 quand le
correctif a été écrit). Il est indispensable à toute recette en bundle release, d'où sa
place en dernier maillon : les lots 4, 5, 6, 9, 10a et 10b l'ont donc tous en amont.

**Symptôme.** En **bundle release**, ouvrir une réunion dans la fenêtre dédiée
(`WindowGroup "1to1-meeting"`) tuait l'application ~3 s après l'ouverture :
`NSGenericException` — « The window has been marked as needing another Update Constraints
in Window pass, but it has already had more […] passes than there are views in the
window » — depuis `NSHostingView.updateConstraints()` →
`updateWindowContentSizeExtremaIfNecessary` (pile complète dans les cinq
`~/Library/Logs/DiagnosticReports/OneToOne-2026-09-07-13*.ips`). Pas un plantage
d'affichage : une **boucle de passes Auto Layout**.

**Établi.** `master` (`a3c44f2`) **ne crashe pas** (fenêtre ouverte, application vivante,
release + bundle). La bissection (9 pas, harnais de reproduction en bundle isolé) désigne
`6cc892b` « feat(reunion): barre du haut sur une ligne de 38 px » (lot 1a) comme premier
commit fautif ; `f74ad86` et tout le lot 0A/0B sont sains.

**Cause racine.** La fenêtre de réunion était la seule des trois scènes à ne pas déclarer
d'enveloppe de taille pour son contenu racine. Le `NSHostingView` racine doit alors
**mesurer toute la hiérarchie de l'écran de réunion** pour en déduire
`contentMinSize`/`contentMaxSize`, et il le fait *pendant* la passe de contraintes de la
fenêtre ; la mesure réinvalide le graphe, qui remarque la fenêtre « needs update
constraints », et la passe se relance jusqu'à épuisement du budget d'AppKit. La barre du
haut sur une ligne a rendu cette mesure instable : son titre est `flex:1` (spec §2.1),
donc `maxWidth: .infinity` + `layoutPriority(1)` — avant `6cc892b`, le titre était borné
(`maxWidth: 460` + `fixedSize`).

**Expériences discriminantes** (lot 3, release, fenêtre dédiée) : titre borné à 460 px →
**pas de crash** ; `maxWidth: .infinity` avec `fixedSize` → crash ; `TextField` SwiftUI à
la place du champ AppKit → crash ; simple `Text` → crash. Ce n'est donc pas le champ
AppKit `EditableTextField`, c'est la mesure non bornée de la racine de fenêtre. Enveloppe
déclarée sur la racine → **pas de crash**.

**Correctif** (`OneToOne/OneToOneApp.swift`, 1 fichier) : `MeetingWindowSizing`
(960 × 640 de plancher, 1 280 × 800 à l'ouverture) et
`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)` sur le contenu de
`OneToOneMeetingWindowContent` — la même chose que `PrepWindowView` fait depuis toujours
(600 × 480). Le `.frame(minWidth: 600, minHeight: 400)` du `ProgressView` d'attente
disparaît : c'est l'enveloppe qui gouverne, et un plancher qui changeait au moment où le
contenu se résolvait faisait partie du problème. **Aucune vue de la refonte n'est touchée**
(barre du haut, espaces, rail : inchangés).

**Tests.** `Tests/MeetingWindowSizingTests.swift` (4 tests) : le plancher de largeur garde
le rail d'actions affiché (`MeetingSpaceLayout.showsRail`, colonne fluide ≥ 520), le
plancher de hauteur laisse la place aux deux barres, l'ideal ne descend pas sous le
plancher, et une garde de non-régression vérifie que la fenêtre **applique** l'enveloppe
(retirer le `.frame` fait échouer ce test — vérifié). La passe Auto Layout elle-même n'est
pas observable depuis `swift test`, d'où cette garde.

**Vérifié.** `swift build` propre ; `swift test` complet **1 039 XCTest (1 ignoré, 0 échec)
+ 896 Swift Testing (131 suites, 0 échec)**, soit +4 par rapport au sommet du lot 3.
Reproduction avant/après en bundle release, dans un `HOME`/`CFFIXED_USER_HOME` jetable
(jamais le store de production) : avant → mort à ~3 s avec l'exception au journal ;
après → fenêtre `1:1 — Debug` ouverte et application vivante à 15 s.

**Reste à faire.** Le même défaut guette toute future scène dont le contenu racine ne
borne pas sa taille. Les recettes visuelles des lots 4, 5, 6, 9 et 10 sont maintenant
possibles en bundle release : elles doivent être rejouées depuis ce sommet.

## Lot 16 — Atelier : socle des planches et mode Croquis (6a partiel) (2026-09-07)

Branche `feat/refonte-lot-16-atelier-socle`. Développée depuis
`feat/refonte-lot-3-rail-actions`, **rebasée** sur `feat/refonte-lot-9-fiche-projet`
une fois l'intégration de la vague 4 terminée (quatre conflits attendus, tous des
ajouts « en fin de type » : `MeetingScreenModel`, `StorageStatsService`,
`MeetingSpaceView` — la branche atelier est entrée dans `contenu`, avant le mode
Relire, pour que les modificateurs des lots 4, 5 et 6 restent posés une seule fois —
et `STATUS.md`).
Tout est derrière **`AppSettings.workshopEnabled`, défaut `false`**.
ADR : `docs/adr/2026-09-07-moteur-de-planches-excalidraw-embarque.md` (décision D6).
Plan : `docs/superpowers/plans/2026-09-07-refonte-lot-16-atelier-socle.md`.

### Le moteur : Excalidraw embarqué, 3,5 Mo, aucun réseau

`Scripts/build-excalidraw-bundle.sh` construit le bundle **hors du dépôt** (npm dans un
dossier temporaire) et dépose dans `OneToOne/Resources/Whiteboard/` un fichier IIFE
unique de **3,1 Mo**, sa feuille de style de **248 Ko**, la licence MIT et
`VERSIONS.txt`. Versions épinglées : `@excalidraw/excalidraw` **0.18.1**, `react` et
`react-dom` **18.3.1**, `esbuild` **0.28.2**. Le bundle est **commité**, comme
`mermaid.min.js` (3,4 Mo) : le script ne sert qu'à le régénérer.

Sans trois allègements délibérés (`Scripts/excalidraw-esbuild.mjs`) le fichier ferait
**8,5 Mo** : les 55 traductions d'Excalidraw et le convertisseur Mermaid (mermaid +
chevrotain + langium, ~4 Mo) sont remplacés par des modules vides — l'interface
d'Excalidraw est **masquée**, toute la chrome est native — et la famille CJK Xiaolai
(12,5 Mo) n'est pas inlinée.

**Aucune requête réseau possible.** La page (`WhiteboardHTML.page()`) inline le JS et le
CSS, comme `MermaidRenderer`, et porte
`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:`.
Les 230 fontes `./fonts/**.woff2` du moteur sont réécrites en `data:font/woff2;base64,…`
par le script — `Fonts.createUrls` rend une telle URI telle quelle et ne consulte jamais
son CDN de secours — et les sept bases interrogeables du moteur (esm.sh, unpkg, partage
de scène, bibliothèque publique, IA, collaboration) deviennent des `file:///` morts.

**Écart assumé sur « aucune URL http(s) dans la page ».** Le bundle contient encore des
URL qui ne sont **pas** des ressources chargées : les deux espaces de noms XML du W3C
(`http://www.w3.org/2000/svg`, `.../1999/xhtml`), **indispensables** à `createElementNS`
donc à l'export SVG, et des constantes de liens d'interface (github.com, youtube.com,
plus.excalidraw.com…) qui vivent dans la chrome masquée. Les retirer casserait l'export
SVG et corromprait des littéraux d'expression régulière. `WhiteboardHTML.audit(_:)`
vérifie donc quatre choses, et `WhiteboardHTMLTests` les assène sur le bundle réellement
embarqué : la CSP exacte est présente ; le **balisage** (corps des `<script>`/`<style>`
retiré) ne porte aucune adresse réseau ni `<script src>`/`<link href>`/`@import` ;
aucune URL de fonte n'est autre que `data:` ; aucune des sept bases n'a survécu.

### Le socle

- `WhiteboardResourceLocator` — même structure que `MermaidResourceLocator` :
  `Bundle.module` en développement, disposition du `.app` packagé ensuite. Rappel :
  `.process("Resources")` **aplatit** l'arborescence, le fichier vit à la racine du
  bundle de ressources et non dans `Whiteboard/`.
- `WhiteboardBridge` — un **protocole**, pas une classe, plus `WhiteboardBridgeDouble`.
  Toute la règle métier et tout `BoardStore` se testent sans WebKit (parade du plan §8).
  `WhiteboardWebBridge` en est l'implémentation `WKWebView` ; son gestionnaire de
  messages passe par un **proxy faible**, sans quoi `WKUserContentController.add(_:name:)`
  et la configuration retenue par la vue formeraient un cycle que rien ne casserait.
- `BoardStore` — `recordings/<uuid de la réunion>/boards/<stableID>.excalidraw.json` et
  `.png`, racine **et horloge injectables**, vignette amortie à 5 s (`force` au
  changement de planche). `BoardOrdering` (tri, renumérotation, duplication, libellés du
  compteur et de fraîcheur), `BoardScene` (compte les objets d'une scène sans le moteur,
  et fabrique une scène à partir de boîtes étiquetées), `BoardModeRule` (règle §7.1).
- `StorageStatsService` compte `boards/`, `MaintenanceView` l'affiche en teal.
  `BackupService` gagne un `BoardDTO` (scène et vignette **en base64**, clé `boards`
  optionnelle pour les sauvegardes antérieures) et un `BoardStore` injectable : sans lui
  une restauration de test écrirait dans le `recordings/` de production.

### L'écran 6a

`WorkshopSpaceView` = mode **En séance** du type Atelier, grille `52 | 1fr | 314` sous une
barre d'outils de 32 px. Une seule branche dans `MeetingSpaceView` : le **dock remplace le
rail d'actions**. `WorkshopState` (une ligne en fin de `MeetingScreenModel`) porte la
planche active, la palette, l'onglet du dock et **l'unique `WKWebView` de la réunion** —
la page inline 3,1 Mo que WebKit réanalyse à chaque création, une vue par planche
multiplierait ce coût par 40. Sa fabrique de pont est injectable, donc l'orchestration
entière (créer, dessiner, sauvegarder, changer de mode, dupliquer, réordonner) se teste
contre le double.

Les cinq couleurs sont **dérivées des jetons** (`WorkshopPalette.hexString`) et non
recopiées : le moteur veut un hexadécimal, la règle du programme §7 interdit une couleur
hors `One2OneTokens`, et un test vérifie que les deux coïncident.

### Recette visuelle — partielle, et deux défauts trouvés

`Scripts/recette-app.sh` et `Scripts/recette-run.sh` repris de la branche du lot 9
(la base du lot 3 ne les avait pas). `.app` **debug** empaqueté, lancé avec `HOME` **et**
`CFFIXED_USER_HOME` jetables ; garde-fou d'isolation vert, le store de production n'a
jamais été ouvert. Capture : **`recette/lot-16-atelier-6a.png`** (fenêtre de 1 616 px
logiques — l'écran du poste fait 1 728 px, 1 920 est hors de portée).

Ce que la capture confirme par rapport à `6a-atelier-planche.png` : palette verticale de
52 px avec ses neuf outils et `↺ ↻` en pied ; toile `#fdfcfa` à points de 18 px ; dock de
314 px avec `Planches 4 / Captures 0 / Pièces 0`, les quatre planches
(`CROQUIS Périmètre actuel 08:15 · Yann`, `SCHÉMA Flux réseau 19:40 · Claire-Amélie`,
`CROQUIS Cible d'architecture 34:20 · en cours`, `MANUSCRIT Notes de Patrice 28:05 ·
stylet`), l'active bordée teal sur `#f2f8f7`, `＋ Planche` teal plein et `Dupliquer`,
le pied `L'assistant peut décrire les planches dans le rapport` ; type `Atelier` dans la
barre du haut. Le semis a bien écrit ses **quatre fichiers de scène** dans
`recordings/<uuid>/boards/` — le critère n° 1 (« se crée, se dessine, se sauvegarde,
se retrouve horodatée, sans réseau ») est vérifié dans l'application réelle, pas
seulement en test.

**Deux défauts trouvés par cette recette, corrigés et couverts par un test :**

1. L'écran demandait sa planche **avant** que la page ait fini d'analyser 3,1 Mo de
   JavaScript. Le `load` échouait, un bandeau « Le moteur de planches n'est pas encore
   prêt » s'affichait et la toile restait vide jusqu'au clic suivant. `WorkshopState`
   garde désormais l'intention (`pendingLoad`) et `onReady` la rejoue ; aucune erreur
   n'est posée entre-temps, puisque rien n'est cassé.
   Test : `selectionIsDeferredUntilReady`.
2. Le bandeau d'erreur, posé en `.overlay(alignment: .top)`, **recouvrait la barre
   d'outils** de 32 px : modes, couleurs, épaisseurs, compteur et export disparaissaient.
   Il est passé dans le flux, sous la barre.

**Écarts et limites de la recette, à reprendre :**

- La vérification **après** correctif n'a pas pu être refaite : plusieurs agents pilotaient
  le même bureau au même moment (une passe « recette visuelle des écrans 1a–3b » tournait
  en parallèle) et tuaient les processus `OneToOne`. La capture conservée montre donc
  l'écran **avant** les deux correctifs — barre d'outils masquée par le bandeau, toile
  vide. À refaire au calme.
- Le badge `ATELIER` apparaît **tronqué** dans la barre du haut à 1 616 px : la barre
  porte déjà fil d'Ariane, titre, pilules audio et capture, menus de type et de modèle, et
  le bouton Rapport. À arbitrer (masquer le fil d'Ariane sous une largeur seuil ?).
- Le crash **préexistant** de la fenêtre dédiée est bien là : le semis pose un
  `QuickLaunchRouter.pendingToken`, la fenêtre dédiée s'ouvre et l'application tombe sur
  `NSGenericException` « needing another Update Constraints in Window pass ». La réunion
  s'ouvre sans problème depuis la fenêtre principale, comme consigné.
- Effet de bord sur le poste : l'instance de production (`.build/.../release/OneToOne`,
  fenêtre `NPA/LDB`) a été **redimensionnée** à 0,33 / 1 720 × 1 024 pendant la recette —
  `first application process whose unix id is …` d'AppleScript renvoie le mauvais
  processus quand deux instances partagent l'identifiant de bundle. Aucune donnée touchée,
  seulement la géométrie de la fenêtre. Adressage par itération de la liste depuis.

### Performances

**Non mesurées.** Le rendu à 2 000 objets et le temps de chargement du bundle demandent une
session graphique tranquille ; la contention du bureau (cf. ci-dessus) a empêché la
mesure. Repère indirect seulement : le bundle fait la taille de `mermaid.min.js`, déjà
inliné dans un `WKWebView` par l'éditeur.

### Laissé au lot 17

Modes Schéma et Manuscrit complets (bibliothèque de formes, pression du stylet,
surligneur, lasso), onglets `Captures` et `Pièces` du dock (ils portent une invite non
vide, testée), section `SUR CETTE PLANCHE`, `＋ Action depuis la sélection`,
`Épingler à mm:ss`. Lot 18 : planche de séance 6b et légende d'assistant.

### Vérifications

`swift build` propre (avertissements préexistants seuls). `swift test` complet **vert** :
1 041 XCTest + 1 419 Swift Testing (**2 460**), 0 échec — contre 2 402 au sommet de la
pile après l'intégration de la vague 4.

**Prochaine action :** refaire la recette de 6a après les deux correctifs, sur un bureau
libre, et mesurer le chargement du bundle plus le rendu à 2 000 objets.

## Refonte de l'écran de réunion — lot 7 : captures Teams / Zoom (4a) (2026-09-07)

Branche `feat/refonte-lot-7-captures`, **sur** `fix/refonte-1to1-window-crash` : la PR
empile donc toute la pile linéaire (PR #19 → … → #25 → #31). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-7-captures.md` (14 tâches, toutes faites).

**État : livré, `swift build` propre, `swift test` complet vert — 1 041 XCTest (1 ignoré) +
1 468 Swift Testing (185 suites) = 2 509 tests, contre 2 402 au sommet. Recette visuelle
différée à la passe de recette dédiée (consigne du 2026-09-07 : un seul agent est autorisé
à piloter l'interface).**

### Ce qui a été porté de Teams-Capture (programme §2.5, décision D7)

Copié **avec ses tests**, jamais lié (aucune dépendance SwiftPM) :

| Élément | Devenu | Ce qu'il apporte |
| --- | --- | --- |
| `CaptureCore/MeetingType.swift` (table de profils) | `Services/SlideCapture/CaptureProfile.swift` | `CaptureProfile` par `MeetingKind` + `captureHint` affiché sous les bascules |
| `CaptureSettings.detectsAutomatically/periodicCapture` | `SlideCaptureSettings` (mêmes champs) | les deux bascules du sélecteur |
| `SessionController.TunedField` | `Services/SlideCapture/CaptureTuning.swift` | changer de type n'écrase pas un réglage fait à la main |
| `SlideDetector.acknowledge` | même nom | pas de doublon après une capture manuelle ou périodique |
| `CaptureCoordinator` (périodique, `captureNow`, horloge injectée) | `ScreenCaptureService` | l'échéance **arme**, le premier tick stable écrit |
| `CaptureCoordinatorTests` (785 l.) | `Tests/CapturePortedCoordinatorTests.swift` (17 tests) | dérive lente, tick en vol, détection coupée, périodique |
| `Cockpit/SourcePopover.swift` | `Views/Meeting/Capture/CaptureSourcePopover.swift` | mise en page 346 px, `PrimaryButtonStyle`, libellés |
| `Cockpit/CaptureRail.swift` | `Views/Meeting/Capture/CapturesStrip.swift` | vignettes 132 × 76, tuile manuelle, raccourci hors cellule lazy |
| `Cockpit/TopBar`, `IndicatorStrip` | pilule de `MeetingTopChromeBar` | `● Capture · Teams 3 ⌄`, `Source perdue` |

**Propre à OneToOne**, absent de Teams-Capture : le lien `t` ↔ audio (`MeetingPlayhead`
comme unique axe de référence), la persistance `SlideCapture` en base avec `source` et
`trigger`, l'OCR et son indexation, l'insertion dans les notes, `＋ Note` / `＋ Action`
depuis la bande, Zoom, l'écran entier (`DisplayFrameSource`), et les bascules
**applicables en cours de séance** — Teams-Capture les gelait pendant la capture, alors
que la capture 4a les montre actives avec trois captures déjà prises.

### Ce qui est en place

**La capture a une source, un déclencheur et un instant.** Une session porte désormais
`source` (`teams/zoom/screen/region`), `detectsAutomatically` et `periodicCapture`, et
chaque `SlideCapture` écrite reçoit les trois colonnes du lot 0B. Le `t` vient du
`MeetingPlayhead` de la réunion — **jamais** de l'horloge de la session de capture : une
note et une capture prises au même moment doivent porter le même instant. Sans axe temps
(ni enregistrement, ni lecture), la capture est écrite **sans** `t` plutôt qu'à `00:00`, où
son carré désignerait un instant où rien ne s'est passé.

**L'échéance périodique arme, elle n'écrit pas.** Écrire au moment de l'échéance donnerait
une image floue au milieu d'une transition : le premier tick non `.settling` qui suit
écrit, avec `trigger: .interval`. Une capture manuelle repousse la suivante — l'échéance se
compte depuis la dernière écriture, quelle qu'en soit l'origine. Trois tests transposés le
prouvent, dont celui où huit ticks de mouvement précèdent deux ticks stables : une
implémentation qui n'écrirait *jamais* rien passerait le premier test, pas celui-là.

**`captureNow()` est le seul chemin manuel.** Il acquitte le détecteur **avant** d'écrire :
entre l'acquittement et l'écriture il y a un `await`, et un tick déjà en vol peut s'y
stabiliser sur le même contenu et l'écrire une seconde fois. `snapshot()` y délègue — deux
implémentations du même geste divergeaient sur l'anti-doublon (l'ancienne amorçait le
détecteur *après* l'écriture, ce qui ne résiste pas au tick en vol).

**`Source perdue` est un état, pas un dialogue** (spec §5.2). `pauseCause` distingue la
source disparue (fenêtre fermée, autorisation refusée, écran débranché) d'un échec d'API :
la première fait passer la pilule en `accent/warn` avec un lien de reconfiguration, la
seconde n'est qu'un message. Aucune boîte de dialogue ne s'ouvre en séance. Le message
d'erreur est remis à zéro sur **tous** les chemins de succès, écriture comprise (piège 14
de `One2One-specs.md`).

**Le sélecteur dit la vérité sur chaque source.** `CaptureSourceCatalog` est pur : il reçoit
les fenêtres partageables et rend les trois lignes de la capture 4a. Le titre de la fenêtre
Teams sert **uniquement** à détecter la réunion active (décision D7) ; « un partage est en
cours » vient du détecteur d'image (`isContentMoving`). Le partageur n'est nommé que s'il
est déjà **participant de la réunion** : deviner un prénom depuis un mot du titre
produirait « partage de Réunion en cours ». Zoom est reconnu par son seul bundle
(`us.zoom.xos`), et l'écran entier est toujours proposé — un sélecteur sans aucune ligne
active serait un cul-de-sac.

**Tout se lit sans ouvrir de menu** (critère n° 1). `CaptureState.pill` est une fonction
pure : `idle` → bouton neutre `Capture` ; `armed(source, count, automatic)` → pilule
`● Capture · Teams 3 ⌄` en `accent/ok` bordée, le point vert quand la détection écrit
d'elle-même, gris quand elle attend un geste ; `lost(count)` → `Source perdue`, **compteur
conservé** (les captures déjà prises ne disparaissent pas avec la source). Le chevron fait
ce qu'il annonce : il rouvre le sélecteur.

**La bande de captures est en pied de colonne**, montée par une ligne de
`MeetingLiveSpace`. Vignettes 132 × 76 servies par un cache mémoire **borné** (64 entrées,
éviction LRU, clé = chemin + date de modification) qui décode à la taille demandée via
`CGImageSourceCreateThumbnailAtIndex` : sans lui, la bande redécoderait un PNG plein écran
par vignette et par rendu. La légende affiche l'**intervalle réel** (`2 min`) et non le mot
« périodique ». La colonne d'état ne promet rien de faux : une capture sans OCR annonce
« Aucun texte extrait », une capture sans `t` « Aucun timecode (capture hors séance) ».
`Joindre au rapport` est une case réelle, persistée sur `SlideCapture.includeInReport`
(colonne neuve à valeur par défaut, migration légère, aucune version de schéma).

**La frise porte le carré de 12 px.** Les repères existaient depuis le lot 2 ; ce qui
manquait était **quel** carré est le dernier (`accent/action`) et **quand** la légende
`■ = capture` a un sens — deux fonctions pures dans
`MeetingTimelineMarkers+Captures.swift`, plutôt que deux `if` dans le `Canvas`.

**Une capture s'insère dans les notes** en carte 56 × 36 + titre + première ligne d'OCR +
`Agrandir` (`Notes/TimedNotesColumn+Capture.swift`, aiguillage de trois lignes dans
`TimedNotesColumn`). La note ne copie **pas** l'image ni le texte : elle porte un
`sourceRef {capture, id, t}` et la carte relit la capture — copier l'OCR aurait figé un
texte que Vision met à jour une seconde plus tard. L'insertion est idempotente, et une
référence morte fait retomber la ligne sur son texte plutôt que d'afficher un cadre vide.

**Le texte extrait est cherchable** (critère n° 4) : l'OCR alimente `extractedText` du lot
(`rebuildAttachmentText`, déjà en place), que `reindexAttachment` découpe en
`TranscriptChunk`. Le test le prouve **sans** appeler `reindexAttachment` — son pipeline
d'embeddings exige `default.metallib`, absent de `swift test` : il vérifie la chaîne
observable OCR → `extractedText` → `TextChunker` → `BM25Index`, et que la requête
« chiffrage Reprise AP Marine » désigne bien le chunk de la capture et non la ligne de
transcription concurrente.

### Écarts assumés

1. **La recette visuelle n'est pas faite.** Consigne du 2026-09-07 : plusieurs agents
   pilotaient le même bureau et se tuaient mutuellement leurs instances ; une **passe de
   recette dédiée** la reprendra (`recette/lot-7-1920.png` à comparer à
   `4a-capture-selecteur.png`). À vérifier à ce moment-là : Teams ouvert **sans** réunion
   doit afficher « Fenêtre ouverte · aucune réunion active » (et « Aucune réunion active »
   quand Teams n'est pas lancé), la pilule `● Capture · Teams 3 ⌄`, la bande et la légende
   `■ = capture`.
2. **L'ordre vertical diffère de 4a.** La capture montre la frise **sous** la bande de
   captures ; ici la frise reste au pied de la carte notes ↔ transcription, où le lot 2 l'a
   posée, et la bande vient dessous. Déplacer la frise hors de la carte aurait touché la
   disposition des lots 2, 4 et 5 — hors périmètre, et la consigne du lot 7 est « une
   ligne » dans `MeetingLiveSpace`.
3. **« Zone à la souris » n'est pas sélectionnable.** La ligne `ÉCRAN` porte le sous-titre
   de la capture (« Ou une zone à la souris ») et capture l'écran entier ; le tracé d'une
   zone à la souris demande une fenêtre de sélection plein écran, qui relève de la pastille
   (lot 8). La valeur `CaptureSource.region` reste dans le modèle, personne ne l'écrit.
4. **Changer de source clôt le lot courant** et en ouvre un autre. Une session porte une
   source figée à sa construction ; accepter le changement à chaud donnerait un sélecteur
   qui confirme un choix sans effet (défaut « contrôle sans effet » de `One2One-specs.md`).
5. **`CropSelectionView` a été supprimée** en même temps que `ScreenCaptureConfigView`, son
   seul appelant : le sélecteur ne demande plus de tracer une zone avant de capturer.
   `NormalizedRect` et ses 12 tests restent — le recadrage est toujours appliqué, il n'est
   simplement plus réglé à la main. `MeetingSlidesPopover` est supprimée comme le lot 6
   l'avait prévu.
6. **La pastille flottante est le lot 8**, avec `⌘⇧S` global (Carbon) et le mini-panneau de
   confirmation de 4 s. Ici `⌘⇧S` est le raccourci de menu, actif quand la fenêtre de
   réunion a le focus.

### Fichiers partagés touchés

Au minimum près : `MeetingScreenModel.swift` (**une** ligne, `var capture`),
`MeetingTopChromeBar.swift` (la pilule de capture et son popover seulement),
`MeetingLiveSpace.swift` + `MeetingSpaceView.swift` (montage de la bande, un paramètre
optionnel), `MeetingView.swift` (**retraits** + le coordinateur et deux closures),
`Menus/{MeetingCommands,MeetingMenuActions}.swift` (`⌘⇧S` et l'appel du semis),
`Notes/TimedNotesColumn.swift` (aiguillage de trois lignes),
`Spaces/AudioTimelineStrip.swift` (carré de 12 px, dernier en accent, légende),
`Models/MeetingModels.swift` (`SlideCapture.includeInReport`),
`Views/DesignSystem/One2OneTokens.swift` (`capturePopoverWidth = 346`).
Aucun fichier de `Views/Meeting/OneOnOne/**`, `Services/OneOnOne/**`, `Workshop/**`,
`Rail/**`, `Review/**`, `Session/**`, `Project/**` ni `Resources/**` n'est touché —
`ResourceItem` et le tiroir sont réutilisés tels quels.

### Prochaine action

Faire relire et fusionner dans l'ordre `#19 → … → #25 → #31 → (lot 7)`, puis la **passe de
recette dédiée** reprend la comparaison avec `4a-capture-selecteur.png` (écarts n° 1 et
n° 2). Le lot 8 (pastille flottante, `4b`) part de ce sommet : `captureNow()`,
`CaptureState` et la bande lui servent tels quels.

## Refonte de l'écran de réunion — lot 11 : 1:1 manager, écran de séance (2a) (2026-09-07)

Branche `feat/refonte-lot-11-1to1-manager-seance`, sur `fix/refonte-1to1-window-crash` (sommet de
la pile linéaire). Plan du lot dans
`docs/superpowers/plans/2026-09-07-refonte-lot-11-1to1-manager-seance.md`.

**État : livré, `swift build` propre, `swift test` complet vert, PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** (consigne du 7 septembre : plusieurs
agents pilotaient le même bureau et se tuaient mutuellement leurs instances ; une seule passe est
désormais autorisée à piloter l'interface). Le crochet est prêt, cf. « Pour la passe de recette ».

### L'écran

`kind == .oneToOne` + mode **En séance** → `ManagerSessionView`, grille `300 | 1fr | 320`,
**sans** rail d'actions, sans bandeau d'indicateurs, sans présence (spec §3.1). Une branche dans
`MeetingSpaceView.contenu`, gardée par `MeetingSpaceRouting.usesOneOnOneManagerSession`.

L'instant de référence de l'écran est la **date de la séance**, pas `Date()` : « il y a 2 sem. »,
« Vendredi » et « tenus depuis le dernier 1:1 » parlent de l'entretien qu'on tient, pas du jour où
on le relit.

| Colonne | Contenu |
| --- | --- |
| Gauche 300 | `PersonCard` (avatar 34, nom, `Ingénieur CI/CD · dans l'équipe depuis 3 ans`, `DERNIER 1:1` / `RYTHME`), `ManagerAgendaCard` (avatar 16 px du côté ajoutant, barré si traité ou reporté, `→ 18/09`, composeur `Ajouter un sujet…`, glisser-réordonner), `ManagerPendingTopicsCard`, barre assistant contexte = fil |
| Centre 1fr | `Notes de l'entretien · liées à l'audio`, pilules `Partagé` / `Privé`, `MoodScale` (5 crans, cran choisi bordé), `① / ② / ③`, bloc privé isolé, `FeedbackCards`, composeur `Écrire… /engagement /feedback /privé` |
| Droite 320 | `ENGAGEMENTS DE CETTE SÉANCE` (`Moi · n` / `<Prénom> · n`, pilules échéance / charge / criticité / confidentialité), `TENUS DEPUIS LE DERNIER 1:1` (`✓` / `✗ n× reporté`), `CLÔTURER` |

Barre du haut, bloc `.oneToOne` : segment `Mon équipe`, pilule `● Privé — vous deux`,
`Rapport 1:1 ✓`, et l'en-tête dérivé `<Nom> — entretien du <jour>` en **placeholder** du titre.

### Fichiers

**`Views/Meeting/OneOnOne/Shared/**` — lisibles par les lots 12 à 14, qui ne les modifient pas :**
`OneOnOneSeniority`, `OneOnOneMoodTone`, `OneOnOneNoteSections`, `CommitmentsRailModel`,
`PersonCardModel`, `ManagerAgendaModel`, `OneOnOneComposerContext`, `AvatarSide`, `PersonCard`,
`MoodScale`, `CommitmentRow`, `OneOnOneInlineComposer`.

**`Views/Meeting/OneOnOne/Manager/**` :** `ManagerSessionView`, `ManagerAgendaCard` (+
`ManagerPendingTopicsCard`), `ManagerNotesColumn`, `FeedbackCards`, `CommitmentsRail`.

**Ailleurs :** `Views/Meeting/Spaces/Notes/TimedNotesColumn+OneOnOne.swift`
(`OneOnOneNotesSection`, `TimedNotesColumn.swift` **intact**),
`Services/OneOnOne/OneOnOneDateFormat+Lot11.swift`,
`Services/Debug/Seed/RefonteDemoSeed+Lot11.swift`.

### Fichiers partagés touchés, à la ligne près

- `Services/Meeting/MeetingSpaceLayout.swift` : deux constantes (`oneOnOneLeftWidth = 300`,
  `oneOnOneRailWidth = 320`) et `oneOnOneColumns`, qui **délègue** à
  `columns(totalWidth:rail:sideNav:)` — la règle « la colonne fluide ne descend pas sous 520 px »
  reste écrite une seule fois.
- `Services/Meeting/MeetingSpaceRouting.swift` : une fonction.
- `Views/Meeting/Spaces/MeetingSpaceView.swift` : une branche `else if`.
- `Views/Meeting/Spaces/Notes/NoteComposer.swift` : trois paramètres optionnels (`commands`,
  `oneOnOne`, `placeholder`), tous `nil` par défaut — rendu et validation des autres types
  inchangés. Cliquer une pilule **remplace** la commande en tête au lieu de l'empiler.
- `Views/Meeting/Spaces/MeetingAssistantDock.swift` : `Contexte` optionnel ; `nil` laisse la barre
  de la capture 1a mot pour mot.
- `Views/Meeting/MeetingTopChromeBar.swift` : quatre fonctions statiques et trois insertions
  localisées.
- `Models/OneOnOneModels.swift` : `Commitment.blocksOther` (défaut `false`), en fin de type.
- `Models/OtherModels.swift` : `Collaborator.joinedAt` (optionnelle), en fin de type. Les deux sont
  des colonnes à valeur par défaut → migration légère, `CurrentSchema` reste `SchemaV3`.
- `Views/Menus/MeetingCommands.swift` : une ligne (`seedLot11`), qui câble enfin
  `seedOneOnOneThreads` du lot 10.
- `OneToOne/OneToOneApp.swift` : le crochet de recette `ONETOONE_SEED_DEMO_SCREEN`.
- `MeetingView.swift` : **rien**.

### Tests

`swift build` propre (mêmes avertissements préexistants). `swift test` complet :
**1 041 XCTest (1 ignoré, 0 échec) + 1 453 Swift Testing dans 187 suites, 0 échec** — 2 494 tests,
soit **+92** par rapport à la référence de 2 402.

Dix suites nouvelles : `OneOnOneSessionLayoutTests` (10), `OneOnOneSeniorityTests` (8),
`CommitmentsRailModelTests` (13), `OneOnOneNoteSectionsTests` (8),
`OneOnOneComposerContextTests` (12), `OneOnOneAgendaCardTests` (12), `OneOnOneMoodScaleTests` (8),
`OneOnOneClosingTests` (5), `OneOnOneTopChromeSessionTests` (5), `RefonteDemoSeedLot11Tests` (11).

### Critères d'acceptation couverts

- **Chantier 2 n° 2** — engagement manqué **côté manager** visible dans le rail avec son compteur
  de reports : `CommitmentsRailModelTests.engagementManqueDuManager` et
  `RefonteDemoSeedLot11Tests.lignesDuLedger` (`✗ Retour sur la grille d'astreinte — YP · 2×
  reporté`, en tête de liste).
- **Chantier 2 n° 3** — le moral saisi écrit un `MoodEntry` de la séance, **remplace** le relevé
  existant (la série de six barres garde sa longueur) et le delta change de sens dans la même
  seconde : `OneOnOneMoodScaleTests`.
- **Sections de notes par nature** — `OneOnOneNoteSectionsTests` : `③` par `kind: feedback`, `①` la
  première ligne, `②` tout le reste ; aucune ligne ne peut n'apparaître dans aucune section.
- **Pilules du composeur par type et par rôle** — `OneOnOneComposerContextTests` : les trois du
  manager, les trois du collaborateur, les quatre du lot 2 ailleurs, et le rôle qui prime sur le
  type.
- **Largeur 1 280 px** — `OneOnOneSessionLayoutTests` : `(300, 660, 320)`, colonne fluide ≥ 520,
  somme exacte, aucune largeur négative de −100 à 1 920 px.
- **Aucune zone vide sans invite** — invites testées pour l'ordre du jour vide, le suspens vide, les
  deux groupes d'engagements vides, le registre vide, les trois sections et les deux cartes de
  feedback ; sans participant, l'écran propose `Gérer les participants` au lieu de trois colonnes
  muettes.
- **Chantier 2 n° 1** (revérifié depuis l'écran qui déclenche l'envoi) — `OneOnOneClosingTests` : la
  note privée `17:30` ne sort pas du récap collaborateur.

### Points tranchés

1. **Le titre d'un entretien reste éditable.** L'en-tête dérivé
   `Laurent NOMINÉ — entretien du 4 septembre` est le **placeholder** du champ de titre, pas son
   remplacement : la barre du haut est le seul point d'entrée de l'application pour renommer une
   réunion, et le retirer pour un type aurait été une perte de fonction. Conséquence sur la
   maquette : le jeu de démonstration affiche son titre semé (`1:1 — Laurent · 14`) et non le texte
   de la capture — cf. écart n° 1.
2. **`ENGAGEMENTS DE CETTE SÉANCE` n'affiche que les engagements ouverts et non en retard.** Un
   engagement soldé ou déjà en retard figure dans le registre juste en dessous ; l'afficher deux
   fois dans la même colonne ferait compter deux paroles là où il n'y en a qu'une. C'est ce que
   montre la capture (`Moi · 2`, la grille d'astreinte étant dans le registre) et c'est un test du
   jeu de démonstration qui l'a établi.
3. **Le registre inclut les retards non soldés, en `✗`.** « Tenus depuis le dernier 1:1 » ne garde
   pas que les soldés : un engagement jamais fermé disparaîtrait de l'écran, ce qui est l'inverse du
   critère n° 2.
4. **La pilule d'échéance dit le jour de la semaine dans la semaine en cours, la date au-delà.**
   « Vendredi » ne veut dire quelque chose que dans la semaine où il est prononcé — c'est la règle
   qui rend les quatre pilules de la capture (`Vendredi`, `9 sept.`, `11 sept.`, `30 sept.`)
   cohérentes entre elles.
5. **`① COMMENT ÇA VA` prend la première ligne de la séance.** La spec décrit une progression, pas
   une colonne « section » : `③` se déduit de `kind: feedback`, et la réponse à la question posée
   est la première chose écrite. Convention assumée, documentée dans `OneOnOneNoteSections`, et
   c'est celle que montre la capture.
6. **La bascule `Partagé` / `Privé` ne repeint pas l'historique.** Elle gouverne les lignes
   **suivantes** ; un changement de défaut qui rendrait publique une note écrite en privé serait le
   pire défaut possible de cet écran. Réglage de séance, en `@State` : le persister mettrait dans un
   backup la trace d'un clic d'interface.
7. **Deux colonnes de données, pas une dérivation.** `Commitment.blocksOther` (`Bloquant pour lui`)
   et `Collaborator.joinedAt` (l'ancienneté) sont des faits dits par les personnes, pas des
   calculs : ni l'échéance ni le porteur ne disent si un retard empêche l'autre d'avancer.

### Écarts assumés

1. **Le titre de la 14ᵉ séance du jeu de démonstration n'est pas celui de la capture.** Le semis du
   lot 10 utilise le titre comme **clef d'idempotence** (`1:1 — Laurent · 14`) : le renommer ferait
   recréer une quinzième séance au semis suivant. Le lot 11 ne touche donc pas aux titres, et
   l'en-tête de la capture apparaît en placeholder d'un entretien sans titre. À trancher au lot 12,
   qui porte l'en-tête de 2b.
2. **`⌘K` n'est pas encore restreint au fil.** `MeetingAssistantDock.Contexte` transporte le
   `threadID`, et la barre affiche `Interroger l'historique des 1:1 de Laurent`, mais le panneau
   ouvert reste `MeetingChatView` à la portée de la réunion. Le câblage de la portée côté chatbot
   appartient au lot 15.
3. **Le glisser-réordonner de l'ordre du jour est fait à la main** (`onDrag` / `onDrop` +
   compactage des rangs) et non avec une `List` : la colonne vit dans une `ScrollView`, et une
   `List` imbriquée y déclenche le `_NSDetectedLayoutRecursion` que le programme §2.4 demande
   d'éviter. Pas d'indicateur d'insertion : la ligne saute à sa nouvelle place au dépôt.
4. **Pas de colonne de transcription en 1:1.** La spec §3.1 retire du type tout ce qui regarde
   ailleurs que la personne, et la capture montre une colonne de notes pleine largeur. La
   transcription reste en mode Relire.
5. **La capture d'écran n'est pas reléguée dans `⋯`.** Le bouton `Capture` de la barre du haut est
   commun à tous les types ; la spec §3.1 demande de le déplacer pour le 1:1. Un geste dans un
   fichier partagé, à faire avec le lot 7 (qui réécrit ce bouton).
6. **`AppSettings.ownerName` porte les initiales de « Moi ».** Il est vide sur une installation
   neuve : les pastilles affichent alors `?`. Le jeu de démonstration le renseigne ; aucune invite
   ne le réclame encore à l'écran.

### Pour la passe de recette dédiée

```bash
swift build -c release
Scripts/recette-app.sh /tmp/recette-lot-11
ONETOONE_SEED_DEMO_SCREEN=2a Scripts/recette-run.sh \
  --app /tmp/recette-lot-11/OneToOne.app --seed --reset
```

La variable ouvre directement la séance de la capture (Laurent NOMINÉ, 4 septembre) en mode En
séance. Captures attendues : `recette/lot-11-1920.png` et `lot-11-1280.png`, à comparer à
`docs/superpowers/specs/refonte-2026-09/ecrans/2a-1to1-manager-seance.png`. Écarts déjà connus : le
titre de la séance (écart n° 1) et le bouton `Capture` encore dans la barre (écart n° 5).

### Prochaine action

Fusionner dans l'ordre de la pile, puis le **lot 12** (1:1 manager, préparation `2b`), qui lit les
composants de `Views/Meeting/OneOnOne/Shared/**` sans les modifier et n'écrit que dans
`Views/Meeting/OneOnOne/ManagerPrep/**`.

## Refonte de l'écran de réunion — lot 12 : 1:1 manager, écran de préparation (2b) (2026-09-07)

Branche `feat/refonte-lot-12-1to1-manager-prepa`, **sur**
`fix/refonte-1to1-window-crash` : la PR empile donc les lots 0A, 0B, 1a, 1b, 2, 3, 4, 5, 6,
10a, 10b, 9 et le correctif de fenêtre (PR #19 → … → #31, non fusionnées). Plan
d'exécution : `docs/superpowers/plans/2026-09-07-refonte-lot-12-1to1-manager-prepa.md`.

**État : livré, `swift build` propre (debug et release), `swift test` complet vert
(2 443 tests), PR ouverte, non mergée. Recette visuelle **différée à la passe de recette
dédiée** — plusieurs lots tournaient en parallèle sur le même bureau et se tuaient
mutuellement leurs instances ; une seule passe est désormais autorisée à piloter
l'interface.**

### Ce qui est en place

Le mode **Préparer** d'une réunion `.oneToOne` n'est plus la colonne générique du lot 1 :
c'est l'écran de suivi de `2b-1to1-manager-preparation.png`. Il prend **toute la surface**,
comme le poste de pilotage du lot 5 — ni bandeau d'indicateurs (rien n'a encore été dit),
ni rail d'actions de 330 px (spec §3.1 retire les projets affectés et les vues Kanban d'un
1:1).

**Aucun calcul métier neuf.** Tout vient des services purs du lot 10 : `MoodTrend`,
`OneOnOneObjectiveTone`, `ReminderRules`, `CommitmentLedger`, `RecurringTopicsBuilder`,
`OneOnOneThreadStore`. Ce lot n'ajoute que la traduction de ces calculs en lignes
dessinables, et il la met dans des **modèles de vue purs** — un par carte — parce qu'une
vue SwiftUI ne se teste pas et qu'un histogramme périmé ne se voit pas à la relecture.

| Fichier (`Views/Meeting/OneOnOne/ManagerPrep/`) | Modèle pur | Ce qu'il porte |
| --- | --- | --- |
| `ManagerPrepView.swift` | — | L'assemblage : en-tête, rangée de trois cartes, rangée `1fr \| 320`, dock d'assistant. Aucune règle. |
| `PrepHeader.swift` | `PrepHeaderModel` | `Ingénieur CI/CD · 14ᵉ 1:1 · 4 sept. 2026`, l'ordinal français, l'avatar, les badges `1:1`/`Privé`, `Historique`, `Démarrer l'entretien`. |
| `MoodHistogram.swift` | `MoodHistogramModel` | Les six barres, la teinte du dernier cran, la tendance, la phrase. **Critère chantier 2 n° 3.** |
| `ObjectivesCard.swift` | `ObjectivesCardModel` | Les trois barres, le ton par avancement, `Revue prévue le 18 sept.`, l'ajout et l'édition inline. |
| `RemindersCard.swift` | `PrepRemindersModel` | Les trois règles dans leur ordre, la puce colorée, `Mettre à l'ordre du jour` et sa désactivation. |
| `CommitmentsTable.swift` | `CommitmentsTableModel`, `PrepCommitmentFilter` | `20 \| 1fr \| 92 \| 84 \| 96`, le filtre, le badge de retard manager, le taux, le composeur `⌘⏎`. |
| `RecurringTopicsCard.swift` | `RecurringTopicsCardModel`, `ChipFlow` | Les chips `label · n` par famille, sur deux lignes dans 320 px. |
| `ThreadHistoryCard.swift` | `ThreadHistoryModel` | Les quatre dernières séances, date mono + résumé d'une ligne, cliquables. |

### Trois décisions à retenir

1. **Le tableau ne montre pas tout le fil.** La capture affiche quatre lignes pour un fil
   qui en compte quatorze, et son pied dit « 8 tenus sur 11 ». Le tableau montre donc les
   engagements **ouverts** plus ceux **soldés depuis l'entretien précédent** — la même
   borne que `TENUS DEPUIS LE DERNIER 1:1` de la capture 2a, et le même calcul
   (`CommitmentLedger.settledSince`). Le pied, lui, compte l'histoire entière : c'est un
   taux de tenue, pas un décompte d'écran.
2. **Un manquement ne se rouvre pas d'un clic.** La pastille d'état solde un engagement
   ouvert et rouvre un engagement tenu, mais reste sans effet sur un `missed` : le
   manquement est un fait de l'entretien, et l'effacer par inadvertance depuis un écran de
   préparation reviendrait à réécrire l'historique. Il faut passer par la séance.
3. **Le mode d'ouverture est imposé sans toucher à `MeetingScreenModel`.** Spec §3 :
   « `2b` s'ouvre par défaut en mode `Préparer` ». `MeetingSpaceRouting.initialMode` est
   pure et rend `nil` dès qu'un choix est mémorisé ; `MeetingSpaceView` l'applique en
   écrivant **et** la clé `UserDefaults` **et** le mode, parce que l'ordre des `onAppear`
   de SwiftUI ne dit pas si `MeetingScreenModel.attach` a déjà relu ses réglages.

### Écritures — un seul service

`Services/OneOnOne/Prep/OneOnOnePrepStore.swift` porte les trois gestes de l'écran :
nouvel engagement, bascule tenu/rouvert, ajout et édition d'objectif. Un fichier
d'extension et non un ajout dans `CommitmentLedger` ou `OneOnOneObjectiveTone` : le lot 10
les documente comme **purs**, et y glisser un `context.insert` les rendrait intestables et
ferait mentir leur en-tête. Deux autres extensions, pures :
`ReminderRules+Prep.areAllOnAgenda` (le bouton sait qu'il a déjà fait son travail) et
`OneOnOneDateFormat+Prep.dueDate` (la quatrième écriture de date du domaine : le jour de la
semaine d'une échéance imminente).

### Jeu de démonstration — `RefonteDemoSeed+Lot12.swift`

Deux choses manquaient au semis du lot 10, et elles ne se voient que sur un écran.

1. **Les dates.** Le lot 10 pose une cadence parfaitement régulière de quinze jours, soit
   `26/06 10/07 24/07 07/08 21/08 04/09`. La capture écrit
   `12/06 26/06 10/07 24/07 21/08 04/09` : **pas d'entretien la première semaine d'août**,
   et l'`HISTORIQUE` saute la même séance. `alignLot12SessionDates` recale le fil sur cette
   grille — cadence nominale pour les deux dernières séances, une période de plus pour tout
   ce qui précède — et réaligne `MoodEntry.recordedAt` sur la date de sa séance, sans quoi
   l'histogramme, qui se trie sur `recordedAt`, se désordonnerait. Les dates sont
   **assignées** depuis le 4 septembre et non décalées : un décalage relatif appliqué deux
   fois reculerait tout le fil d'un mois, et un semis se clique deux fois. Le rang
   « 14ᵉ 1:1 » est conservé.
2. **Les résumés d'une ligne** de l'`HISTORIQUE` : aucun rapport n'est semé, donc
   `Meeting.shortSummary` est vide et la carte retombe sur sa reconstruction
   (`moral « Bien » · <sujet>`). Les quatre phrases de la capture sont écrites à leur date.

Le semis 1:1 du lot 10 **était orphelin** (point tranché n° 3 de l'intégration de la
vague 4). Il est désormais câblé aux deux points d'entrée : l'item de menu « Charger le jeu
de démonstration (refonte) » et la variable `ONETOONE_SEED_DEMO` de la recette. Quelle
réunion s'ouvre se choisit avec `ONETOONE_SEED_DEMO_SCREEN=<code>` — l'entretien de
démonstration n'était atteignable qu'à la souris, et une recette doit être reproductible
sans clic. *(Ce lot avait écrit une seconde variable, `ONETOONE_SEED_OPEN=1to1` ;
l'intégration de la vague 5 l'a fondue dans le crochet unique — cf. la section en tête.)*

### Fichiers partagés touchés, à la ligne près

- `Services/Meeting/MeetingSpaceRouting.swift` : **deux fonctions pures**
  (`usesOneOnOnePreparation`, `initialMode`). Rien de retiré.
- `Views/Meeting/Spaces/MeetingSpaceView.swift` : **une branche** dans `contenu`, la vue
  `preparation1a1`, et le `onAppear` du mode d'ouverture. Le rail, le bandeau et le tiroir
  sont inchangés pour tous les autres modes.
- `Views/Meeting/Spaces/MeetingAssistantDock.swift` : **un paramètre optionnel**
  `threadContext` (spec §3.3 : « contexte = fil, pas seulement la réunion »). `nil` hors
  1:1, et la barre est alors exactement celle d'avant.
- `Services/OneOnOne/OneOnOneScreenState.swift` : **une propriété en fin de type**,
  `prepHistoryExpanded`. Le filtre du tableau réutilise `commitmentSideFilter` du lot 10 —
  aucune propriété d'état en double.
- `Views/Menus/MeetingCommands.swift` : une ligne (`seedLot12`).
- `OneToOneApp.swift` : le semis de recette appelle `seedLot12` et choisit la réunion à
  ouvrir. Six lignes, additives *(récrites à l'intégration : `RecetteScreen` et le seul
  `ONETOONE_SEED_DEMO_SCREEN`)*.
- **Intacts** : `MeetingScreenModel.swift`, `MeetingTopChromeBar.swift`, `MeetingView.swift`,
  `MeetingPrepareSpace.swift`, `Rail/**`, `Review/**`, `Session/**`, `Resources/**`,
  `Notes/**`, et tous les fichiers existants de `Services/OneOnOne/` sauf la propriété
  d'état ci-dessus.

### Tests

`swift build` propre (mêmes avertissements préexistants, dont `MoodTrend.swift:78` sur
`historyLength`, vérifié présent avant ce lot). `swift test` complet : **1 041 XCTest
(1 ignoré, 0 échec) + 1 402 Swift Testing dans 180 suites, 0 échec** — 2 443 tests, soit
**+41** par rapport à la référence de 2 402.

Trois suites nouvelles :

- `ManagerPrepModelsTests` (20) : en-tête et ordinal, histogramme et **critère chantier 2
  n° 3** (une `MoodEntry` saisie pour la séance courante apparaît aussitôt dans la série, et
  une correction remplace la barre au lieu d'en ajouter une), objectifs et bornes, ordre des
  rappels et désactivation du bouton, chips, historique (quatre lignes, courante exclue,
  déplié, résumé reconstruit, invite), idempotence du semis et des dates.
- `ManagerPrepCommitmentsTableTests` (13) : quatre lignes et non quatorze, tri, porteurs et
  teintes, les cinq écritures de la colonne `ÉCHÉANCE`, fenêtre du jour de la semaine,
  filtre, **critère chantier 2 n° 2** (badge « 1 en retard côté manager » et taux
  « 8 tenus sur 11 · taux 73 % »), composeur, bascule d'état, largeurs de colonnes.
- `ManagerPrepRoutingTests` (8) : aiguillage `(1:1, Préparer)` seul, mode d'ouverture,
  respect d'un choix mémorisé, contexte de fil de la barre d'assistant.

**Aucune zone vide sans invite** : les six modèles portent un `isEmpty` et la vue
correspondante monte un `MeetingEmptyInvite`. Un fil neuf (aucune humeur, aucun objectif,
aucun engagement, aucun sujet, aucune séance antérieure) est couvert test par test.

### Recette visuelle — différée

**Aucune recette n'a été lancée pour ce lot**, et c'est une consigne, pas un oubli :
plusieurs lots de la vague travaillaient en parallèle sur le même bureau et se tuaient
mutuellement leurs instances. Une **passe de recette dédiée** la fera, seule à piloter
l'interface.

Ce qu'elle aura à faire, et tout est prêt pour cela :

```bash
swift build -c release                        # fait, propre
Scripts/recette-app.sh /tmp/recette-lot12
# `--screen 2b` sème tout le jeu et ouvre l'entretien en mode Préparer
Scripts/recette-run.sh --app /tmp/recette-lot12/OneToOne.app --screen 2b --reset
```

Puis capturer `recette/lot-12-1920.png` et `recette/lot-12-1280.png` et les comparer à
`2b-1to1-manager-preparation.png`. Les écarts **déjà connus** — relevés en lisant la
maquette et les données semées, pas un rendu — sont listés ci-dessous : ils servent de
grille de lecture à cette comparaison, qui doit surtout chercher ce que cette liste ne
contient pas (métriques, alignements, hauteurs de carte, retours à la ligne).

### Écarts attendus avec la capture 2b

1. **Le tri met l'engagement en retard en première ligne**, là où la maquette l'affiche en
   deuxième. C'est la règle de la spec §6.2 (« cartes triées par retard décroissant »), et
   c'est aussi la seule qui se défend : ce qu'on doit depuis six semaines se lit avant ce
   qu'on doit vendredi.
2. **L'objectif à 10 % est ambre et non violet.** La spec §3.4 dit « < 30 % `warn` », et
   `OneOnOneObjectiveTone` la porte depuis le lot 10, testée. La maquette colore cette barre
   en violet : elle se contredit elle-même. La spec fait foi.
3. **Les phrases des rappels sont celles de `ReminderRules`**, pas celles de la maquette :
   « Vous lui devez Retour sur la grille d'astreinte — reporté 2 fois. » (la maquette écrit
   « un retour »), « Mobilité archi évoquée 3 fois, jamais tranchée. » (sans « depuis
   avril »), « Féliciter pour la présentation COSUI. » (sans « du 1er sept. »). Les
   corriger demanderait de toucher `Services/OneOnOne/ReminderRules.swift`, hors périmètre
   de ce lot et couvert par les tests du lot 10.
4. **La phrase sous l'histogramme est `MoodTrend.explanation`** : « Cause citée 5 fois :
   Charge de travail. » La maquette écrit « Deuxième séance consécutive sous « Bien ». Cause
   citée deux fois : charge sur la migration AP. » Sa première phrase n'est portée par
   aucune règle du lot 10 — et elle contredit son propre histogramme, où une seule séance
   est sous « Bien » ; son comptage n'est pas celui du fil. La spec §3.4 ne demande que « le
   sujet récurrent le plus cité sur la période », qui est ce qui s'affiche.
5. **`taux 73 %`** avec l'espace de la typographie française (lot 10), là où la maquette
   écrit `taux 73%`.
6. **L'échéance imminente affiche `Samedi` et non `Vendredi`** : le jeu du lot 10 pose cette
   échéance au lendemain du 4 septembre 2026, qui est un samedi. La règle d'affichage est
   bonne, la donnée semée diffère d'un jour ; la corriger touche le semis du lot 10.
7. **La barre du haut de l'application reste au-dessus de l'en-tête violet** (fil d'Ariane,
   barre d'espaces, sélecteur de mode). La maquette ne montre que le composant 2b : c'est le
   même écart que les captures 1a, 3b et 1c, et il est assumé depuis le lot 1.
8. **`MeetingPrepareSpace.swift` n'a pas de branche.** Le programme en prévoyait une ; le
   routage est finalement dans `MeetingSpaceView`, à l'endroit exact où le mode Relire du
   lot 5 est déjà aiguillé. Y passer aurait obligé à traverser `MeetingPrepareSpace` avec
   cinq paramètres (`screen`, `menuActions`, `historique`, `isAssistantOpen`,
   `onOpenMeeting`) dont elle n'a aucun usage — et le programme §8 interdit exactement cela.
   Un fichier partagé de moins touché, aussi, pendant que les lots 7, 11 et 16 tournent.

### Doublons probables avec le lot 11, à harmoniser à l'intégration

Le lot 11 crée `Views/Meeting/OneOnOne/Shared/**` et `Views/Meeting/OneOnOne/Manager/**`
pendant que ce lot vit dans `ManagerPrep/**`, sans les voir. À la passe d'intégration :

- **L'avatar et l'identité** : `PrepHeader.avatar` et le sous-titre `rôle · nᵉ 1:1 · date`
  recouvrent la `PersonCard` et l'`AvatarSide` du lot 11. Le modèle à garder est
  `PrepHeaderModel` (l'ordinal français y est testé) ; le rendu peut passer dans `Shared/`.
- **L'échelle de moral** : `MoodHistogramModel.tone(for: MoodLevel)` et la `MoodScale` du
  lot 11 doivent donner la **même** teinte par cran, sinon la séance et la préparation
  colorent le même « Sous tension » différemment. Une seule table, dans `Shared/`.
- **La ligne d'engagement** : `CommitmentsTableModel.Row` et `CommitmentRow` du lot 11
  portent tous deux le porteur, l'échéance et le compteur de reports. Les libellés
  (`Moi`/`<Prénom>`, `Tenu`, `En retard`, `n× reporté`) doivent être calculés une fois.
- **Le contexte d'assistant** : si le lot 11 ajoute lui aussi un paramètre à
  `MeetingAssistantDock`, il porte le même nom (`threadContext`) — l'union est alors
  triviale.
- **Le semis** : le lot 11 câble peut-être `seedOneOnOneThreads` au même endroit. La ligne
  de `MeetingCommands` et celle d'`OneToOneApp` ne doivent pas être doublées ; `seedLot12`
  appelle déjà `seedOneOnOneThreads`, qui est idempotent.

### Laissé de côté

- La carte `À NE PAS OUBLIER` n'offre pas de retrait ligne par ligne : le bouton verse tout
  ou rien. La spec ne demande pas plus, et un rappel qu'on écarte sans le traiter est
  précisément ce que la carte veut empêcher.
- Le composeur d'engagement ne saisit ni échéance ni porteur : porteur `Moi` par défaut
  (spec §3.4), échéance à poser en séance. Un sélecteur de date dans un pied de tableau
  aurait été un formulaire.
- `Historique` déplie la carte au lieu de naviguer vers `CollaboratorFicheView` : la fiche
  collaborateur n'est pas un panneau de l'écran de réunion, et l'y ouvrir demanderait un
  point d'entrée que ce lot n'a pas à inventer.
- Le mode `.manager` (je suis le collaborateur) garde la préparation générique : son écran
  est la capture 5b, au **lot 14**.

### Prochaine action

Faire relire la PR, puis la fusionner **après** le lot 11 (les deux touchent
`MeetingAssistantDock` et se partagent les composants 1:1) et exécuter la passe
d'harmonisation `ManagerPrep/**` ↔ `Shared/**` décrite ci-dessus. La **recette visuelle du
lot 12 reste due** : elle appartient à la passe de recette dédiée, avec la commande donnée
plus haut.

## Intégration vague 5 : la pile redevient linéaire (2026-09-08)

Les lots **16, 7, 11 et 12** ont été développés **en parallèle** — le lot 16 depuis
`feat/refonte-lot-9-fiche-projet`, les trois autres depuis `fix/refonte-1to1-window-crash`.
Ils sont désormais **empilés** dans cet ordre :

```
… → #26 → #29 → #25 → #31 → 16 → 7 → 11 → 12
                              #32  #34  #35  #33
```

Ordre de fusion : `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31 → #32 → #34 → #35 → #33`. Bases : #32 sur `fix/refonte-1to1-window-crash`,
#34 sur le lot 16, #35 sur le lot 7, #33 sur le lot 11.

### Conflits résolus, maillon par maillon

| Maillon | Fichier | Résolution |
| --- | --- | --- |
| **16** (#32) | `STATUS.md` | union, lot 16 puis correctif de fenêtre |
| **7** (#34) | `STATUS.md` | union, lot 7 puis lot 16 |
| | `MeetingTopChromeBar.swift` | fusion automatique, puis la pilule `Local · hors ligne` déplacée **après** la pilule de capture (ordre des blocs, spec §2.1) |
| **11** (#35) | `MeetingCommands.swift` | union des semis dans un seul item de menu |
| | `STATUS.md` | union, lot 11 puis 7 puis 16 |
| | `MeetingSpaceView.swift` | fusion automatique, puis ordre du routage : **Atelier → 1:1 (mode) → standard (mode)** |
| **12** (#33) | `MeetingSpaceRouting.swift` | union des trois fonctions pures |
| | `MeetingAssistantDock.swift` | **un seul** paramètre de contexte, `threadContext` |
| | `MeetingCommands.swift` | une seule ligne de semis des fils 1:1 |
| | `OneToOneApp.swift` | **un seul** crochet de recette |
| | `STATUS.md` | union, lot 12 puis 11 puis 7 puis 16 |

`MeetingScreenModel.swift` (lignes `capture` du lot 7 et `workshop` du lot 16) et
`OneOnOneScreenState.swift` (`prepHistoryExpanded` du lot 12) se sont fusionnés seuls :
les quatre lots ont écrit **en fin de type**, comme la consigne de l'intégration
précédente le demandait. C'est la seule leçon de la vague 4 qui a évité six conflits.

### Harmonisations 11 / 12 — une seule définition par règle

Le lot 12 n'a pas pu lire le `Shared/**` du lot 11 : trois règles existaient en double, et
la préparation (2b) contredisait la séance (2a) sur les deux mêmes engagements.
`Tests/RefonteVague5IntegrationTests.swift` (10 tests) tient désormais chacune.

1. **Teinte du moral.** Deux tables. Elles divergeaient sur `Bien` : `oneOnOne` (violet)
   au lot 12, `ok` (vert) au lot 11. `MoodHistogramModel.tone(for:)` délègue maintenant à
   `OneOnOneMoodTone` (lot 11, `Shared/`) ; un test parcourt les cinq crans et vérifie que
   `MoodScaleModel.tone` et `MoodHistogramModel.tone` rendent la même chose.
   **Tranché** : la table du lot 11, parce qu'elle vit dans `Shared/` et porte déjà
   `isDeep` pour distinguer `Bien` de `Très bien`.
2. **Identité et avatar.** `PrepHeaderModel` relisait le collaborateur et redessinait la
   pastille. Il appelle maintenant `PersonCardModel.name` / `.initials` / `.role`,
   l'en-tête monte `AvatarSide` (34 px, palette du domaine) et l'ancienneté se lit par
   `OneOnOneSeniority`. Ce qui reste propre à 2b : l'**ordinal** `14ᵉ 1:1`, testé, et la
   date en année pleine. Le filtre « Néant » de `CollaboratorIdentity` est monté dans
   `PersonCardModel.role` — il servait aux deux. Le nom de repli devient
   `PersonCardModel.fallbackName` (« Sans interlocuteur », celui du lot 12) ; il y en avait
   deux, dont « Personne inconnue ».
3. **Échéance d'un engagement.** Deux règles pour la même pilule : le lot 11 comparait les
   **semaines calendaires** (« 9 sept. » pour un mercredi de la semaine suivante), le
   lot 12 une **fenêtre de sept jours** (« Mercredi »). `CommitmentsRailModel.duePill`
   appelle maintenant `OneOnOneDateFormat.dueDate`, la seule règle.
   **Tranché** : la fenêtre de sept jours, parce que `ActionCard.libelleEcheance` (lot 3)
   l'applique déjà aux échéances d'action — la semaine calendaire aurait fait lire deux
   règles sur le même écran. Deux tests du lot 11 changent d'attente en conséquence,
   commentaire compris.
   Les deux extensions `OneOnOneDateFormat+Lot11` et `+Prep`, qui déclaraient chacune
   `weekday(_:)`, sont fondues en **`OneOnOneDateFormat+Views.swift`**.
   Le compteur `n× reporté` venait déjà de `CommitmentLedger.deferralLabel` des deux
   côtés : rien à unifier, un test le fige. Les états `Tenu` / `En retard` / `Manqué`
   n'existent que dans le tableau de 2b (le rail de 2a affiche `✓` / `✗`) : **laissés en
   place**, ce n'est pas un doublon mais deux surfaces.
4. **Historique** du `PrepHeader` et bloc historique : inchangés, comme prévu.

### Un seul crochet de recette

Les lots 11 et 12 avaient chacun câblé le leur dans le même `ContentView` :
`ONETOONE_SEED_DEMO_SCREEN=2a` savait choisir la réunion mais pas le mode,
`ONETOONE_SEED_OPEN=1to1` savait choisir la réunion sans savoir laquelle photographier.
Il n'en reste qu'un, `ONETOONE_SEED_DEMO_SCREEN`, et il **nomme l'écran** — le code de la
capture de référence :

| Code | Écran | Réunion ouverte | Mode |
| --- | --- | --- | --- |
| `1a` | cockpit | démonstration | En séance |
| `1b` | espaces et indicateurs | démonstration | En séance |
| `1c` | poste de pilotage | démonstration | Relire |
| `2a` | 1:1 mené, séance | entretien mené | En séance |
| `2b` | 1:1 mené, préparation | entretien mené | Préparer |
| `3a` | tiroir Ressources | démonstration | En séance |
| `3b` | fiche projet en panneau | démonstration | En séance |
| `4a` | sélecteur de capture | démonstration | En séance |
| `6a` | atelier, planche | atelier | En séance |

La table est `OneToOne/Services/Debug/RecetteScreen.swift`, pure et `CaseIterable` : le
test la parcourt. Le mode est écrit dans `UserDefaults` (`MeetingScreenModel.modeKey`)
**avant** l'ouverture — le seul moyen de l'imposer sans clic et de survivre à la relecture
que fait `attach`. Sans code, rien ne change : le cockpit, au mode qu'il a mémorisé.

```bash
Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen 2b --reset
```

`Scripts/recette-run.sh` gagne `--screen <code>` (qui implique `--seed`), valide le code
avant de lancer et le documente dans son en-tête.

### Le jeu de démonstration, tous les semis ensemble

Les six extensions du semis (`Lot5`, `Lot6`, `Lot7`, `Lot11`, `Lot12`, `seedWorkshop`)
sont appelées **une fois chacune** depuis les deux points d'entrée — l'item de menu et le
crochet de recette. Deux tests d'intégration : semer tout **deux fois** ne change aucun
compte (réunions, engagements, humeurs, actions), et le recalage des dates du lot 12
(`alignLot12SessionDates`) laisse la séance du 4 septembre du lot 11 cohérente — elle
reste la dernière du fil, son entretien précédent reste à quinze jours, la ligne
`✓ Accès environnement recette` reste dans `TENUS DEPUIS LE DERNIER 1:1`, et l'histogramme
de 2b garde ses six dates `12/06 26/06 10/07 24/07 21/08 04/09`.

### Vérifications

`swift build` propre à chaque maillon (avertissements préexistants seuls :
`MoodTrend.swift:78`, `AudioCompressionService.swift:46`, les captures non-`Sendable` de
`ManagerCategoryClassifier` et `ManagerSnippetElaborator`). `swift test` complet à chaque
maillon :

| Maillon | XCTest | Swift Testing | Total |
| --- | --- | --- | --- |
| #31 (référence) | 1 041 | 1 361 | **2 402** |
| + lot 16 | 1 041 | 1 423 | **2 464** |
| + lot 7 | 1 041 | 1 530 | **2 571** |
| + lot 11 | 1 041 | 1 622 | **2 663** |
| + lot 12 et harmonisations | 1 041 | 1 673 | **2 714** |

`MeetingView.swift` : **2 063 lignes**, sous le plafond de 2 100 ; le lot 7 en a retiré
l'ancien `ScreenCaptureConfigView` et n'y a laissé que du câblage.

**Un échec XCTest, préexistant et horaire.**
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` construit des réunions à
`startOfDay + 1 h` et `+ 2 h` et les attend **passées** : entre minuit et 2 h du matin
elles sont à venir, et `tempsPasseSeconds` vaut 0 au lieu de 7 200. La même suite est
verte quand elle tourne avant minuit (vérifié à 23 h 57 sur le maillon 16, `exit 0`), et
aucun des quatre lots ne touche `MenuBarStats` ni `TodayStatsCalculator`. **Non corrigé** :
une PR = une intention, et ce test n'appartient à aucun de ces lots. À reprendre à part —
il suffit d'injecter `now` à midi.

### Ce qu'il reste

La branche de recette visuelle `fix/refonte-recette-vagues-1-4` est à rebaser sur ce
sommet ; les recettes des lots 7, 11 et 12 n'ont pas été faites (un seul agent à la fois
pilote le bureau), et celle du lot 16 est à refaire après ses deux correctifs. La barre du
haut porte maintenant, dans le pire cas, fil d'Ariane + `Mon équipe` + badge de type +
pilule `Privé — vous deux` + titre + audio + partage + capture + type + modèle +
`Rapport 1:1` + `⋯` : **le débordement à 1 280 px n'est pas vérifié** — il n'existe aucun
test de largeur de `MeetingTopChromeBar`, et une largeur de `HStack` SwiftUI ne se mesure
pas depuis `swift test`. Le lot 16 avait déjà vu le badge `ATELIER` tronqué à 1 616 px.
C'est le premier point de la recette à venir.

**Prochaine action :** faire relire et fusionner `#32 → #34 → #35 → #33`, rebaser
`fix/refonte-recette-vagues-1-4` sur ce sommet, puis une passe de recette unique
qui parcourt les neuf codes de `--screen` — en commençant par la largeur de la barre du
haut à 1 280 px.

## Refonte de l'écran de réunion — lot 8 : pastille flottante (4b) (2026-09-08)

Branche `feat/refonte-lot-8-pastille`, rebasée sur
`feat/refonte-lot-12-1to1-manager-prepa` (sommet de l'intégration de la vague 5). Plan
d'exécution : `docs/superpowers/plans/2026-09-07-refonte-lot-8-pastille.md`.

**État : livré, `swift build` propre, `swift test` complet vert — 1 041 XCTest
(1 ignoré) + 1 729 Swift Testing (215 suites) = 2 770 tests après rebase, contre 2 714
au sommet du lot 12 : **+ 56 tests**. Aucune recette graphique (consigne du 2026-09-07 :
un seul agent pilote le bureau) ; la procédure de recette est écrite plus bas.**

⚠️ **Un échec XCTest préexistant et horaire** : `MenuBarStatsTests`
`test_todayStats_passedOnlyAndNoProject` échoue entre 0 h et 2 h du matin (les réunions
du test sont posées à `startOfDay + 1 h`). Constaté à **00:33 CEST le 2026-09-08**, seul
échec de la suite avant comme après rebase, indépendant de ce lot — non corrigé ici
(une PR = une intention).

### Ce qui a été porté de Teams-Capture (programme §2.5)

Copié **avec ses tests**, jamais lié :

| Élément | Devenu | Ce qu'il apporte |
| --- | --- | --- |
| `CaptureDesign/ScreenCorner.swift` + ses 5 tests | `Views/Capture/Pill/ScreenCorner.swift`, `Tests/ScreenCornerTests.swift` | magnétisation aux 4 coins, coin persisté et non la position, borné sur un écran plus petit que la pastille |
| `CaptureCore/PillMode.swift` (l'idée) | `SessionPillPresentation.swift` | la décision d'affichage est une **fonction pure**, pas un `if` dans le contrôleur |
| `Pill/PillPanelController.swift` | `SessionPillPanelController.swift` | `NSPanel` `.borderless + .nonactivatingPanel`, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground`, débounce 250 ms sur `didMoveNotification`, garde anti-boucle dans `snap`, **un seul panneau agrandi**, `withObservationTracking` réarmé |
| `Pill/FloatingPill.swift` | `FloatingPill.swift` | capsule 300 × 40, séparateur, `TimelineView` pour le chrono, point pulsant **réarmé à chaque transition** |
| `GlobalHotKey.swift` (leçons) | `Services/Capture/CaptureHotkeys.swift` | l'échec d'enregistrement est **publié** et affiché ; le service Carbon de OneToOne (`GlobalHotkeyService`, signature `ONET`) est réutilisé tel quel |

**Propre à OneToOne**, absent de Teams-Capture : `ActiveMeetingRegistry` (Teams-Capture
n'a qu'une session, OneToOne a des réunions), le chrono depuis `MeetingPlayhead`,
l'insertion de la vignette dans les notes, `✎ Note` avec son champ et `⌘⏎`,
`＋ Action depuis la capture`, la première ligne d'OCR qui arrive **après** l'écriture,
le tracé de zone, et le panneau qui accepte le clavier **le temps d'une note**.

### Ce qui est en place

**La « réunion active » est une notion globale, avec une règle pure.**
`ActiveMeetingRegistry.activeID(recording:sessions:)` : celle qui **enregistre**
(`AudioRecorderService.activeMeetingID`) d'abord, sinon la **dernière entrée en séance**.
Une réunion qui enregistre mais dont aucun écran n'est ouvert ne l'emporte pas : elle ne
donne aucune prise, et la désigner ferait disparaître la pastille de la séance qu'on a
sous les yeux. Le registre porte des **poignées** (`ActiveMeetingHandle` : réunion,
modèle d'écran, coordinateur de capture, contexte) parce que la pastille vit dans un
`NSPanel`, sans environnement SwiftUI, sans `@Query` et sans le `@StateObject` de
`MeetingView` qui porte le `ScreenCaptureService`.

**Le critère n° 2 du chantier 4 est testé, pas espéré.** `SessionPillModel` parle à un
protocole `SessionPillTarget` ; la doublure compte les activations d'application, et le
compte attendu est **zéro** sur tout le chemin d'une capture. La chaîne réelle
(`captureNow` → `SlideCapture(t)` → `CaptureNoteInsertion` → confirmation) est testée sur
une vraie réunion en mémoire avec une source d'images doublée : la capture est écrite au
`t` du `MeetingPlayhead`, la note porte un `sourceRef {capture}` au même instant, et
l'ouverture du sélecteur — seul chemin qui ramène dans la fenêtre — n'est jamais
appelée.

**Un seul panneau, agrandi.** La hauteur est une fonction pure
(`sessionPillPanelHeight`) et le contrôleur, seul, redimensionne la fenêtre : c'est le
défaut corrigé dans Teams-Capture (une carte dessinée sous une pastille de 40 px dans une
fenêtre de 40 px est invisible, coupée par le bord). Confirmation et champ de note se
**cumulent** — capturer pendant qu'une note est en cours dessine les deux.

**L'OCR arrive après l'écriture.** La carte part sur « Texte en cours d'extraction… »,
un sondage borné (10 essais de 400 ms, en **parallèle** des 4 s de la carte et non
avant) la complète dès que Vision a rendu, et le quota épuisé elle cesse de promettre un
texte à venir (« Aucun texte extrait »). Copier le texte n'aurait rien réglé : il n'existe
pas encore au moment de la confirmation.

**Une capture impossible se voit.** `SessionPillCaptureResult` distingue « écrite »,
« aucune source » et « échec » : l'échec s'affiche là où la réussite s'afficherait
(`CAPTURE IMPOSSIBLE` + le message du service), et l'absence de source ouvre le sélecteur
**une seule fois** — un raccourci qui réactiverait l'application à chaque frappe est pire
que rien.

**Le panneau n'accepte le clavier que pendant la saisie d'une note.** Un panneau non
activant qui devient fenêtre clé au premier clic volerait le focus à Teams ; un champ de
texte dans une fenêtre qui ne peut pas devenir clé ne reçoit aucune touche, et `✎ Note`
serait un contrôle mort. D'où `SessionPillPanel.acceptsKey`, basculé exactement pendant
la saisie.

**`⌘⇧S` et `⌘⇧N` sont globaux**, enregistrés dans `registerHotkeys()` par le service
Carbon existant, avec deux cases dans les réglages (défaut activées) et un message
d'échec — « ⌘⇧S est déjà utilisé par une autre application. » — qui **s'efface** au
premier enregistrement réussi (piège 14 de `One2One-specs.md`). `⌥⌘⇧S`, ou l'entrée
`Zone…` du menu contextuel de `◫ Capturer`, ouvre le tracé de zone.

**La zone à la souris comble l'écart n° 3 du lot 7.** `RegionSelection` est pure (origine
haut-gauche comme `NormalizedRect`, refus d'un tracé sous 2 % d'un côté),
`RegionSelectorWindow` n'est qu'un `NSPanel` `.screenSaver` qui capte la souris, et
`CaptureSessionCoordinator.startRegionSession` ouvre la session avec `CaptureSource.region`
et son `crop` — la valeur cesse d'être morte dans le modèle.

**Affichage automatique** : `AppSettings.sessionPillMode` (`toujours` / `séance
seulement` — défaut / `jamais`). En « séance seulement », la pastille apparaît en plein
écran de séance, **ou** quand un enregistrement tourne alors que One2One n'est pas au
premier plan ; enregistrement **et** fenêtre devant, elle se retire (la barre du haut
porte déjà l'état). Elle disparaît à la clôture de la séance et à l'arrêt de
l'enregistrement.

### Écarts assumés

1. **Aucune recette graphique.** Consigne du 2026-09-07. La passe dédiée reprendra la
   comparaison avec `4b-pastille-flottante.png`.
2. **La zone est capturée sur l'écran principal.** `ScreenCaptureService.SessionConfiguration`
   ne porte pas d'identifiant d'écran (`windowID == 0` → `DisplayFrameSource()`), donc une
   zone tracée sur un écran secondaire serait lue sur l'écran principal. Ajouter un
   `displayID` touche le fichier du lot 7 : hors périmètre.
3. **La confirmation n'apparaît que si la pastille est visible.** En mode « jamais »,
   `⌘⇧S` capture et insère quand même (la bande et les notes le montrent), mais la carte
   de 4 s n'a pas de fenêtre où s'afficher. `⌘⇧N`, lui, ouvre la pastille le temps de la
   saisie — sinon le champ n'existerait nulle part.
4. **Le point d'entrée est une ligne dans `MeetingSpaceView`**, comme le lot 4 : c'est le
   seul endroit qui tienne à la fois la réunion, son modèle d'écran et le coordinateur de
   capture. `MeetingView` n'est pas touché (test de balayage).
5. **`MeetingScreenModel` n'a pas gagné de ligne** : l'état de la pastille est un état de
   **fenêtre**, pas d'écran de réunion, et il vit dans `SessionPillModel`.
6. **Le sondage de l'OCR plutôt que l'observation SwiftData** : un `NSHostingView` posé
   dans un `NSPanel` n'a pas d'environnement de conteneur, et compter sur l'observation
   d'un `@Model` depuis cette fenêtre serait un pari. Le sondage est borné et testé.

### Procédure de recette (pour la passe dédiée)

1. `Scripts/bump-and-build.sh dev`, ouvrir la réunion de démonstration, passer en
   **mode séance plein écran** (`⌃⌘F`) : la pastille doit apparaître en bas à droite.
2. Ouvrir Teams **en plein écran** par-dessus : la pastille reste visible (c'est
   `[.canJoinAllSpaces, .fullScreenAuxiliary]` qui le garantit ; sans lui elle disparaît
   au partage).
3. La déplacer vers un autre coin, relâcher : elle s'aimante après ~250 ms, et le coin
   survit à un redémarrage de l'application.
4. `⌘⇧S` depuis Teams : la carte `CAPTURÉ · mm:ss` s'affiche 4 s, avec la vignette, la
   première ligne d'OCR (après une seconde), et `＋ Action depuis la capture`. **Aucune
   fenêtre One2One ne doit passer devant**, et l'espace ne doit pas changer.
5. `⌘⇧N`, taper une ligne, `⌘⏎` : la note apparaît dans la colonne au timecode courant.
   `Esc` referme sans rien créer.
6. `⌥⌘⇧S` : le voile plein écran, tracer une zone, la capture suivante est recadrée.
7. Réglages → Pastille flottante : les trois modes, les deux cases, et — en assignant
   `⌘⇧S` à une autre application — le message d'échec.

### Fichiers partagés touchés

`Views/Meeting/Spaces/MeetingSpaceView.swift` (**une** pose de modificateur),
`OneToOneApp.swift` (`registerSessionPillHotkeys`, appelé par `registerHotkeys()`),
`Models/AppSettings.swift` (4 propriétés à valeur par défaut : mode, coin, deux cases —
migration légère, aucune version de schéma), `Views/SettingsHotkeysSection.swift`
(section `Pastille flottante`), `Views/DesignSystem/One2OneTokens.swift` (jetons de la
pastille). `MeetingView.swift`, `MeetingScreenModel.swift` et tous les fichiers du lot 7
sont **intacts** — `CaptureSessionCoordinator` et `ActionComposerService` sont étendus
depuis `Views/Capture/Pill/`.

### Prochaine action

Faire relire et fusionner après le lot 12. Puis la passe de recette dédiée déroule la
procédure ci-dessus (et l'écart n° 1 tombe).

## Refonte de l'écran de réunion — lot 13 : 1:1 collaborateur, écran de séance (5a) (2026-09-08)

Branche `feat/refonte-lot-13-1to1-collab-seance`, **rebasée sur
`feat/refonte-lot-12-1to1-manager-prepa`** (sommet de la pile après l'intégration de la vague 5).
Plan du lot dans `docs/superpowers/plans/2026-09-07-refonte-lot-13-1to1-collab-seance.md`.

**État : livré, `swift build` propre, `swift test` vert (1 742 Swift Testing + 1 041 XCTest,
un seul échec, préexistant et horaire — cf. plus bas), PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** ; le crochet est prêt
(`ONETOONE_SEED_DEMO_SCREEN=5a`).

### L'écran

`kind == .manager` + mode **En séance** → `CollaboratorSessionView`, grille `308 | 1fr | 356`,
**sans** rail d'actions, sans bandeau d'indicateurs, sans présence (spec §3.1, qui vaut pour les
deux types 1:1). Une branche dans `MeetingSpaceView.contenu`, gardée par
`MeetingSpaceRouting.usesOneOnOneCollaboratorSession` — exclusive des trois autres branches 1:1,
ce que `RefonteVague5IntegrationTests` vérifie type par type et mode par mode.

Même parti que le lot 11 : l'instant de référence est la **date de la séance**, pas `Date()`.

| Colonne | Contenu |
| --- | --- |
| Gauche 308 | `MyTopicsCard` (`CE QUE JE VEUX DIRE · ● privé`, sujets numérotés, poignée `⠿`, glisser-réordonner, composeur `Ajouter un sujet…`, mention « Visible de vous seul… »), `MyRequestsCard` (`MES DEMANDES EN COURS`, statut + historique court), barre assistant contexte = fil, question `« Qu'ai-je livré depuis <mois> ? »` |
| Centre 1fr | `Notes de l'entretien`, pilules `● Privé par défaut` (état) / `Partager la ligne` (bouton), sections `CE QU'IL M'A DIT` / `CE QUE J'AI DIT`, bloc `● POUR MOI SEUL`, composeur `Écrire… /promesse /demande /preuve` |
| Droite 356 | `CE QUE J'AI LIVRÉ · auto · depuis le <date>` avec `Citer`, `CE QU'IL M'A PROMIS · n en retard` avec `Promise le …` / `n reports` / `Relancer`, `EN SORTANT` |

Barre du haut, bloc `.manager` : segment `Mes 1:1`, en-tête dérivé `Avec <Manager> — <jour>` en
**placeholder** du titre, et le bouton `Mon récap` — autonome, donc `MeetingView` n'est pas touché.

### La règle « ce que j'ai livré »

`DeliveredItemsBuilder` (pur, 20 tests). Trois sources, et **aucune saisie** :

1. **actions closes** dans `]1:1 précédent, séance]` ;
2. **réunions à rôle actif** dans la même fenêtre, **hors tête-à-tête** (mes 1:1 ne sont pas un
   livrable), portant une décision ou une note de moi ;
3. **actions bloquées** — ouvertes, reportées ou commentées « Bloqué par… » —, **sans borne de
   date** : un blocage est un état présent, pas un événement de la fenêtre.

**« Mes » actions = `destinataire == .moi` ET `collaborator == nil`.** L'utilisateur de
l'application n'est pas un `Collaborator` : il n'a pas de fiche, donc `assignedTasks` ne le
désigne jamais, et `ActionAudience.moi` est la seule désignation qui existe. La seconde condition
est indispensable : `destinataireRaw` vaut `moi` par défaut, et le semis du lot 10 — comme
l'extraction LLM — affecte un responsable sans y toucher. Sans elle, les deux livrables de Laurent
entreraient dans **mes** preuves.

`Citer` **propage** la chaîne de citation au lieu d'en inventer une : `SourceRef.Kind` n'a pas de
cas pour une action et `ActionTask` n'a pas de `stableID` à viser. Une ligne d'action reprend donc
le `sourceRef` de l'action ; une ligne de réunion vise la note qui l'a justifiée. Aucun modèle
n'est modifié. La note de preuve est écrite à `t = 0` : elle cite un fait **antérieur** à
l'entretien.

### Fichiers

**Services (purs, testés) :** `Services/OneOnOne/DeliveredItemsBuilder.swift`,
`Services/OneOnOne/Collaborator/{CollaboratorSessionModel, CollaboratorTopBarModel,
CollaboratorNotePrivacy, PromiseReminders}.swift`.

**Vues :** `Views/Meeting/OneOnOne/Collaborator/{CollaboratorSessionView, MyTopicsCard,
MyRequestsCard, CollaboratorNotesColumn, DeliveredCard, PromisesCard, CollaboratorClosingCard,
MyRecapPreview}.swift`, `Views/Meeting/Spaces/Notes/TimedNotesColumn+Collaborator.swift`.

**Jeu de démonstration :** `Services/Debug/Seed/RefonteDemoSeed+Lot13.swift` — extension, ni
`RefonteDemoSeed.swift` ni `+Lot10` ne sont touchés. Complète le fil de Yann PENVEN (déjà semé par
le lot 10 : 3 demandes, 3 sujets privés, 3 promesses, 5 notes) avec les **quatre lignes** de
`CE QUE J'AI LIVRÉ` : deux actions closes (29 août avec `2 j`, 2 sept.), la réunion de projet du
1er sept. portant sa décision, et l'action bloquée par les comptes GitLab.

**Fichiers partagés touchés, en blocs localisés :** `MeetingSpaceLayout.swift` (deux constantes +
`collaboratorColumns`), `MeetingSpaceRouting.swift` (une fonction), `MeetingSpaceView.swift` (une
branche), `MeetingTopChromeBar.swift` (bloc `.manager`), `OneOnOneScreenState.swift`
(`collabSelectedNoteID`, **en fin de type**), `OneOnOneDateFormat+Views.swift`
(`dayMonthOrdinal`), `RecetteScreen.swift` (code `5a`), `MeetingCommands.swift` (une ligne de
semis). `MeetingView.swift` : **rien**.

### Les trois critères du chantier 5

1. **Rôle visible en permanence** — `CollaboratorTopBarModel.breadcrumbSegments(for:)` est un
   modèle **pur** : la liste des segments ne dépend que du type, donc aucune largeur, aucun
   réglage et aucun état d'écran ne peut masquer la pilule `Je suis le collaborateur`. Testé pour
   `.manager` (présente) et pour tous les autres types (absente).
2. **Aucune ligne partagée sans geste explicite** — `CollaboratorNotePrivacy`. Le défaut est
   `private` par **tous** les chemins d'écriture (composeur nu, `/promesse`, `/demande`,
   `/preuve`, sujet ajouté à la main), et `Partager la ligne` change **une** ligne, jamais la
   séance : c'est pourquoi `● Privé par défaut` est un **état** et non une bascule de séance
   comme au lot 11 — une bascule ici ouvrirait la porte à un « tout partager » d'un clic. Une
   ligne `escalated` ne redescend jamais vers le manager par ce geste (D9).
3. **La liste se remplit sans saisie et se cite en un clic** — `DeliveredItemsBuilder` +
   `DeliveredCard.citer`, qui écrit une note `kind: .proof` portant le `sourceRef` propagé.

Également couverts : tri des promesses par retard décroissant, `> 60 jours` → `report`
(règle du lot 10, `AgendaCarryover.requestLevel`), compte des lignes exclues sur les trois
familles (notes + engagements + sujets → `3 lignes privées seront exclues.`), largeurs à 1 280 /
1 920 / 1 000 / 800 px avec plancher fluide de 520 px, et une invite pour chaque zone vide.

### Écarts avec la capture, assumés

- **La barre du haut garde ses contrôles** (pilule de partage, capture, menu de type, template,
  `Rapport 1:1`). La capture 5a montre une barre réduite à l'audio, `Mon récap` et `⋯` ; les
  retirer rendrait un entretien mal typé à l'import impossible à corriger. `Mon récap` a été
  **ajouté** avant `⋯`.
- **Un titre de section désigne la section d'écriture.** Le parseur du lot 10 déduit l'auteur
  d'une ligne de la **section**, pas de la commande : sans ce clic, une seule des deux sections
  serait accessible au clavier. Même mécanique que `FeedbackCards` au lot 11 ; la capture ne
  montre pas l'affordance. `Citer` écrit directement, donc une preuve tombe toujours dans
  `CE QUE J'AI DIT`.
- **`n reports` au pluriel régulier.** La capture écrit `2 reports` sur une carte et `3ᵉ report`
  sur une autre ; la spec §6.2 dit `n reports`, et c'est cette écriture-là qui est retenue.
- **La question de l'assistant est datée du dernier point tenu** (`depuis août` sur le jeu de
  démonstration) et non figée à `juillet` : la capture n'est pas cohérente avec son propre
  `depuis le 21 août`, et une question figée deviendrait fausse six mois plus tard.
- **`Relancer` ≠ reporter.** `deferralCount` compte les fois où le **manager** a repoussé sa
  parole ; la relance est mon geste, et son compteur vit sur le sujet d'ordre du jour privé créé
  pour la séance suivante. Idempotent par le texte.

### Un échec de test préexistant, horaire

`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` (XCTest) échoue **entre 0 h et 2 h du
matin**, indépendamment de tout lot : la suite a été passée à **00:35 CEST le 8 septembre**, et
c'est le **seul** échec. Non corrigé — il n'appartient pas à ce lot.

### Pour la passe de recette

`ONETOONE_SEED_DEMO_SCREEN=5a` (crochet unique, table `RecetteScreen`) sème les fils et les
quatre livrables, puis ouvre la séance du 4 septembre en mode En séance. Le menu **Réunion**
charge le même jeu.

### Prochaine action

Lot 14 — 1:1 collaborateur, préparation en 2 minutes (5b), qui dépend de ce lot. Le critère
chantier 5 n° 4 (« une promesse du manager non tenue remonte automatiquement à la préparation
suivante ») lui appartient.

## Refonte de l'écran de réunion — lot 15 : rapport, blocs optionnels, citations (2026-09-08)

Branche `feat/refonte-lot-15-rapport`, **rebasée** sur
`feat/refonte-lot-12-1to1-manager-prepa` (sommet de la pile après l'intégration de la
vague 5). Plan d'exécution :
`docs/superpowers/plans/2026-09-07-refonte-lot-15-rapport.md` (14 tâches, toutes faites).

**État : livré, `swift build` propre, `swift test` complet vert — 1 054 XCTest (1 ignoré) +
1 710 Swift Testing (213 suites) = 2 764 tests, contre 2 714 sur la base. Unique échec :
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, préexistant et **horaire**
(échoue entre 0 h et 2 h ; constaté à 00:40 CEST), indépendant du lot et non corrigé ici.
Aucune recette graphique, aucun lancement d'application, aucun appel réseau.**

### Ce qui est en place

**L'audience de confidentialité descend du gabarit, plus du type de réunion.**
`ReportTemplateKind.audience` est une table exhaustive et sans `default` (`.oneToOne` →
`.collaborator`, `.manager` → `.manager`, `.escalade` → `.hr`, tout le reste →
`.projectTeam`), et `ReportAudience.forTemplate` retombe sur
`ConfidentialityFilter.audience(for:)` quand aucun gabarit n'est choisi. Avant ce lot,
`assembleTemplatePrompt` et `ReportHTMLBuilder` la déduisaient tous deux du `MeetingKind` :
une ligne `escalated` d'un 1:1 était écartée **jusque dans l'export Escalade**, ce que le
test `ligneEscaladeeSeulementEnEscalade` a d'abord constaté en rouge. La règle de sortie,
elle, reste `ConfidentialityFilter.isExportable` — jamais réécrite.

**Cinq blocs optionnels, une sélection, deux rendus.** `Services/Report/ReportOptionalBlocks.swift`
choisit et ordonne ; `…Markdown` alimente le prompt (via les variables `{{…}}`), `…HTML`
écrit une annexe **déterministe** du rapport. Deux rendus et non un seul parce qu'un rapport
dont les pièces ne figurent que si le modèle a bien voulu les reprendre ne satisfait pas le
critère n° 3 du chantier 3, qui demande qu'une pièce épinglée soit citée *automatiquement*.

| Variable | Source | Ordre |
| --- | --- | --- |
| `{{pieces_epinglees}}` | `Meeting.pinnedAttachments` (lot 6), case `attachPinned` du pied | `t` croissant |
| `{{captures_jointes}}` | `SlideCapture.includeInReport` (lot 7), 1re ligne d'OCR | `t` puis `index` |
| `{{planches}}` | `Meeting.boards` | `t` puis `index` |
| `{{engagements}}` | `Commitment` du fil pris dans la séance, par côté | côté, puis échéance |
| `{{fiche_projet.maj}}` | `Meeting.acceptedProjectUpdates` (neuf, cf. plus bas) | ordre d'acceptation |

**La page `p.n` se relit dans la puce du lot 6, elle n'est pas persistée.** Une pièce n'a pas
« une » page : on en a cité une à un moment donné. Le bloc cherche donc ` · p.(\d+)` dans les
notes dont le `sourceRef` désigne la pièce, plutôt que d'ajouter une colonne qui inventerait
une vérité. Une capture prise hors enregistrement garde `t == nil` et n'hérite pas de `00:00`
— même refus qu'au lot 7.

**Les engagements se lisent sans rien écrire.** `OneOnOneThreadStore.existingThread` et non
`thread(for:in:)`, qui *crée* un fil : générer un rapport ne doit toucher à rien en base.

**La chaîne de citation porte sur le balisage, pas sur le texte.** `CitationLinker` reconnaît
`<code>mm:ss</code>` (avec un `data-note` facultatif) et non `\b\d{1,2}:\d{2}\b` dans la
prose : « le point est reporté à 14:30 » est un horaire, et en faire un lien enverrait la
tête de lecture à la 870ᵉ seconde d'une séance qui n'en compte peut-être pas tant. La passe
est appliquée aux **seuls** fragments écrits par l'app — notes, pièces, captures, planches,
plan d'actions — jamais à `bodyHTML`, qui vient du modèle. En aperçu, le timecode devient
`onetoone://meeting/<uuid>?t=252&note=<uuid>` ; en `.outlook` (PDF, mail, Apple Notes) il
redevient du texte nu, un schéma privé n'ayant aucun sens hors machine.

**Le clic est intercepté dans l'aperçu, pas par macOS.** `MeetingReportPreview` a désormais un
délégué de navigation : `onetoone://` appelle `onCitation`, un lien externe part dans le
navigateur, et rien ne navigue *dans* la WKWebView (elle n'a ni barre d'adresse ni bouton
retour). **Aucun `CFBundleURLTypes` n'a été ajouté** : le schéma reste interne, comme les
mentions `onetoone://collaborator/…` de l'éditeur markdown.
`QuickLaunchURLHandler.parseCitation` est pur ; `handle(url:router:context:playhead:)` reçoit
la tête de lecture au lieu d'aller la chercher — cf. écart n° 1.

**Les révisions de gabarits sont versionnées par nom.** `BuiltInTemplates.revisions:
[String: Int]` généralise le marqueur ciblé `d2OneToOneRevision` du 2026-05-23 : une ligne est
réalignée sur son seed **une fois par révision**, et l'édition faite ensuite reste intacte —
la règle que `test_seedIfNeeded_doesNotOverwriteEditedBuiltIn` gardait déjà. Le marqueur est
posé même quand la ligne vient d'être insérée : la repousser au lancement suivant écraserait
une édition faite entre-temps. Six gabarits révisés (`d1_global`, `d2_oneToOne` — révision 4,
`d3_manager`, `d4_copil`, `d5_cosui`, `d9_workshop`) ; `d2` gagne aussi la mention « Les notes
privées ne sont jamais incluses. » du pied `CLÔTURER` de la capture 2a.

**Nouveau gabarit `d11_escalade`** (décision D9) : l'unique sortie d'audience `.hr`, donc la
seule qui emporte les lignes `escalated` et qui laisse celles qui n'étaient que `shared`. Son
préambule interdit explicitement ressenti, cran de moral et appréciation de motivation — ce
que quelqu'un dit de son propre état à son manager ne remonte pas à la hiérarchie au détour
d'une escalade. Il est proposé juste après le gabarit du type, et **seulement** sur les deux
types de tête-à-tête.

**Les trois cases du pied agissent enfin, et au moment de l'envoi.**
`Services/Report/ReportSendPreparation.swift` : pièces épinglées + PDF des captures cochées
en annexe, participants **présents** (`participantStatus == .present`) en destinataires,
et versement effectif via `AttachmentImporter.Bucket.project(code:)` + `ProjectAttachment`.
Le lot 6 ne faisait que *persister* ces cases. À l'envoi et pas à la génération : générer est
un geste qu'on répète pour ajuster un gabarit, et verser à chaque essai remplirait la fiche de
doublons. Idempotent par nom de fichier, original intact (D5, vérifié sur disque avec une
racine de stockage injectée dans un dossier temporaire).

**Un bloc vide devient une invite, pas une section vide.** `MeetingReportSpaceInvites` est
sortie de la vue pour être vérifiable sans monter SwiftUI : « Aucune pièce épinglée — épinglez
depuis Ressources. » s'affiche une fois en tête de l'espace Rapport. Une case décochée n'invite
à rien — l'utilisateur a déjà répondu. Le libellé `Rapport ✓ (m:ss)` est inchangé.

### Écarts avec le plan

1. **Le clic sur un timecode ne déplace pas encore la tête de lecture d'un écran ouvert.**
   `MeetingReportSpace` est monté dans `MeetingView.swift:606`, fichier que les conventions
   anti-conflit du lot 15 réservent (« `MeetingView.swift` (rien) »), et une `MeetingPlayhead`
   appartient à l'état d'un écran monté (`MeetingScreenModel`) sans qu'aucun registre ne
   l'expose — celui du lot 0B a justement été retiré. Le lien est **rendu, parsé et testé**
   (`CitationLinkerTests`, `CitationURLHandlingTests`), et `handle` sait faire le `seek` :
   il manque **un argument** — `playhead: screen.playhead` sur `MeetingReportSpace`, puis
   `onCitation:` sur `MeetingReportPreview`. À poser dans la passe qui a la main sur
   `MeetingView.swift`.
2. **`Ce que j'ai livré` (spec §6.2) reste sans variable.** `DeliveredItemsBuilder` (lot 13)
   n'est pas encore sur la pile ; aucune variable n'a été inventée pour l'occuper.
   `d3_manager` porte `{{engagements}}` (« ce qu'il m'a promis ») mais pas les livrables.
3. **`{{planches}}` rend titre, mode, auteur et timecode, sans légende.** La légende textuelle
   générée par l'assistant (`BoardCaptionBuilder`) est au lot 18 ; la variable existe et rend
   déjà l'ordre du temps, testé avec trois `Board` insérés à contretemps.
4. **`Models/OtherModels.swift` gagne une colonne** — `acceptedProjectUpdatesJSON`, la seule
   autorisée. Le lot 9 ne persistait rien de l'acceptation : `accept` mute un
   `ProjectCardDraft`, puis `apply(to:in:)` écrit dans le `Project` ; après `Enregistrer`,
   plus rien ne distingue une valeur validée d'une valeur saisie à la main. Colonne
   **optionnelle à valeur par défaut**, migration légère, aucune version de schéma.
5. **Trois lignes dans `Views/Project/**`** au-delà de l'extension autorisée : la feuille
   d'acceptation gagne une propriété `meeting: Meeting? = nil` et l'appel à
   `recordAcceptance`, et `ProjectCardPanel` passe son `meeting` (qu'il possède déjà, l. 84).
   Sans ce câblage, `{{fiche_projet.maj}}` serait resté vide en pratique. Toute la logique
   vit bien dans `Services/Project/ProjectCardSuggestions+Log.swift`.
6. **Neuf commits pour quatorze tâches.** Les quatre blocs de `ReportOptionalBlocks` vivent
   dans un même fichier : quatre commits successifs y auraient réécrit la même zone.
7. **`ReportOptionalBlocks.escape` duplique `ReportHTMLBuilder.escape`**, qui est `private`.
   L'exposer aurait élargi la surface d'un type dont le rôle est d'assembler un document,
   pas de prêter ses outils.

### Fichiers partagés touchés

`Services/AIReportService.swift` (assemblage seulement : audience, repli des blocs),
`Services/ReportTemplating.swift` (paramètre `audience`, branchement du `default`),
`Services/BuiltInTemplates.swift`, `Services/ExportService.swift` (`composeMeetingMail`),
`Services/QuickLaunchURLHandler.swift` (extension), `Models/ReportTemplate.swift`
(cas `escalade` + audience), `Models/OtherModels.swift` (**une** colonne),
`Views/Settings/ReportTemplateEditorView.swift` (palette), `Views/Meeting/MeetingReportPreview.swift`,
`Views/Meeting/Spaces/MeetingReportSpace.swift`, `Views/Meeting/MeetingTopChromeBar.swift`
(**seulement** `compatibleTemplates`), `Views/Project/{ProjectCardSuggestionsSheet,ProjectCardPanel}.swift`
(trois lignes, écart n° 5), `Services/Report/ReportThemeCSS.swift` (classe `a.tc`).
Aucun fichier de `Views/Meeting/OneOnOne/**`, `Services/OneOnOne/**` (lus seulement),
`Views/Capture/**`, `Services/Capture/**`, `Workshop/**`, `Rail/**`, `Notes/**`, `Review/**`,
`Resources/**`, `Session/**` ni `MeetingView.swift`.

### Prochaine action

Faire relire et fusionner la PR du lot 15 après `#33`. Puis, dans la passe qui a la main sur
`MeetingView.swift`, poser l'argument `playhead` de l'écart n° 1 — c'est la dernière ligne
entre un timecode cliquable et un timecode qui déplace la lecture. Le lot 18 alimentera la
légende de `{{planches}}` ; le lot 13 pourra brancher `Ce que j'ai livré` sur `d3_manager`.

## Lot 17 — Atelier : modes Schéma et Manuscrit, pièces et captures (6a complet) (2026-09-08)

Branche `feat/refonte-lot-17-atelier-modes`, développée sur
`feat/refonte-lot-16-atelier-socle` (SHA `1d99a02` mémorisé dans
`.lot17-base-sha`) puis **rebasée** sur `feat/refonte-lot-12-1to1-manager-prepa`
une fois l'intégration de la vague 5 terminée — **aucun conflit**, le lot 16
avait déjà absorbé les points de couture. Plan :
`docs/superpowers/plans/2026-09-07-refonte-lot-17-atelier-modes.md`.
Tout reste derrière `AppSettings.workshopEnabled`.

### Trois modes, trois palettes — et c'est une table pure

`WorkshopPalette.tools(for:)` est le critère n° 2 du chantier 6 en une fonction :
Croquis = crayon, rectangle, ellipse, flèche, ligne, texte, **post-it**, image,
gomme ; Schéma = sélection, connecteur, texte, gomme **plus** les cinq formes de
la bibliothèque (`shapes(for:)`) ; Manuscrit = stylo, surligneur, gomme, règle,
lasso. Le catalogue `WhiteboardTool` perd `frame`, qui n'apparaît dans aucune
palette de la spec §7.1. Changer de mode **rearme l'outil par défaut** du
nouveau mode : garder un crayon dans une palette qui n'en a pas est le genre de
détail qui fait douter de tout le reste.

### Ce qui a été calculé en Swift plutôt que délégué au moteur

Deux décisions, prises sur pièces :

1. **L'alignement** (`BoardAlignment`, 8 opérations). L'objet impératif
   d'Excalidraw 0.18.1 — vérifié dans le bundle embarqué — n'expose **pas**
   `actionManager` : `let E={updateScene…,registerAction:…}` ne contient que
   `registerAction`. Les actions `alignLeft`, `distributeHorizontally`… du moteur
   sont donc hors d'atteinte du pont. Trente lignes de géométrie pure les
   remplacent, et **se testent sans WebKit** (13 tests) ; le pont ne transporte
   qu'un dictionnaire de positions, appliqué avec `captureUpdate: "IMMEDIATELY"`
   pour que `↺` défasse un alignement comme n'importe quel geste.
2. **La bibliothèque de formes** (`BoardShapeLibrary`). Les cinq formes —
   serveur, base de données, file, acteur, zone — sont dessinées en JSON
   Excalidraw **par l'application**, jamais téléchargées (la bibliothèque
   publique du moteur est neutralisée en `file:///` depuis le lot 16). En Swift
   et non inlinée dans le bundle JavaScript : une forme est une donnée, elle se
   compte et se vérifie en test, et corriger un tracé ne demande pas de
   reconstruire 3,7 Mo. Chaque forme est un **groupe** — sans `groupIds` commun,
   la déplacer la démonterait.

### Pression du stylet — implémentée, non vérifiable ici

Dans un `WKWebView`, les `PointerEvent` de macOS **n'apportent pas** la pression
d'une tablette : le moteur retombe sur `simulatePressure`, qui déduit l'épaisseur
de la vitesse du geste. `StylusPressureMonitor` lit donc la vraie pression dans
les `NSEvent` (`.pressure`, `.tabletPoint`, `.leftMouseDragged`) et la pousse
dans la page pendant le geste ; à la levée du stylet, la page rééchantillonne la
série sur les points du tracé, écrit `pressures` et pose
`simulatePressure = false`. Une souris ne rapporte **aucune** pression
exploitable (une constante) : `InkPressure.normalized` rend alors `nil` et
l'épaisseur reste celle de la barre d'outils, comme le veut la spec (« pression
si disponible »).

**Procédure de vérification, à faire en recette avec une tablette :**
1. brancher un stylet (Wacom, iPad + Sidecar, ou trackpad Force Touch) ;
2. ouvrir une planche en mode **Manuscrit**, outil `Stylo` ;
3. tracer un trait en variant l'appui, puis relâcher ;
4. dans `recordings/<uuid>/boards/<stableID>.excalidraw.json`, l'élément
   `freedraw` doit porter `"simulatePressure": false` et un tableau `pressures`
   de la **même longueur** que `points`, aux valeurs non constantes.
   Un `pressures` absent, ou `simulatePressure: true`, signifie qu'aucun
   `NSEvent` de tablette n'est arrivé — c'est le seul mode d'échec attendu.

### Dock : `SUR CETTE PLANCHE` et `PIÈCES & CAPTURES`

L'annotation vit dans `customData.one2oneKind` de l'élément — le seul champ que
le moteur transporte sans y toucher, donc elle survit à la sauvegarde, à la
duplication d'une planche et à l'export. `BoardAnnotation.list` la relit, y
compris quand le texte est porté par l'élément **lié** (`containerId`) et pas par
la boîte. Le menu contextuel est **natif** : `BoardWebView` remplace celui de
WebKit (« Recharger », « Inspecter » n'ont rien à faire sur une planche) par
« Marquer comme question / risque » et « Retirer l'annotation ».

`＋ Action depuis la sélection` crée l'action **tout de suite**, via
`ActionComposerService` — le rail n'est pas monté en atelier (le dock le
remplace), personne ne consommerait un brouillon posé dans
`pendingActionDraft`. Son titre vient des libellés sélectionnés
(`BoardScene.labels`, retours à la ligne aplatis). `Épingler à mm:ss` pose une
note `sourceRef board` (« ◫ Planche n · titre ») ; `MeetingTimelineMarkers+Boards`
en fait un repère **carré** et retire le rond que la note produirait — sans quoi
la même planche porterait deux repères superposés.

`PIÈCES & CAPTURES` réutilise `ResourceItem` (lot 6), `ResourceTypeIcon` (lot 6)
et `CaptureThumbnailCache` (lot 7, branché après rebase : une capture montre ce
qu'elle a capturé). Les onglets `Captures` et `Pièces` portent enfin du contenu ;
leur invite ne sert plus que pour une liste vide, et les compteurs comptent **ce
que l'onglet montre** — le lot de captures (`MeetingAttachment` de type `slides`)
est un conteneur, pas une pièce.

`Insérer` : l'image est copiée dans
`recordings/<uuid>/boards/assets/<stableID>.png`, **bornée à 2 048 px** sur le
grand côté (spec §7.4), et posée comme élément `image` **verrouillé** avec une
`data:` URL — la scène ne contient aucun chemin de disque. Le critère n° 3 a son
test : le fichier d'origine est supprimé, la planche tient. L'élément est
fabriqué **en Swift** et non dans la page : `locked: true` vit ainsi à un seul
endroit, celui que le test inspecte. Un fichier déposé sur la zone du dock est
copié dans la réunion (`AttachmentImporter.Bucket.meetingDocuments`) **puis**
inséré — deux gestes en un, comme le promet le libellé de la capture.

### Bundle Excalidraw régénéré

Versions **inchangées** (Excalidraw 0.18.1, React 18.3.1, esbuild 0.28.2,
Node 22.23.2) : seule l'entrée `Scripts/excalidraw-entry.jsx` change, avec huit
fonctions de plus (`setLibrary`, `insertShape`, `getSelection`, `select`,
`moveElements`, `setSelectionKind`, `insertImage`, `setPressure`). Le mode Schéma
arme `isBindingEnabled` et `objectsSnapModeEnabled` — connecteurs liés et
magnétisme viennent alors du moteur, gratuitement.

`excalidraw.bundle.js` : **3 718 038 octets** contre 3 715 102 (**+2 936**) ;
`excalidraw.bundle.css` inchangée à 253 200. `WhiteboardHTMLTests` reste vert :
CSP intacte, aucune adresse réseau apparue, aucune fonte non-`data:`.

### Défaut du lot 16 corrigé : le badge `ATELIER`

Il apparaissait **tronqué** à 1 616 px. Cause : `titleField` portait
`layoutPriority(1)`, donc `HStack` le servait le **premier** et il absorbait
toute la largeur restante — ses voisins étaient mesurés sur ce qui restait, soit
rien. Correctif : priorité **négative** au titre (c'est lui qui doit céder, il
porte une ellipse) et `fixedSize()` sur le badge. Rien d'autre n'est touché dans
`MeetingTopChromeBar`.

### Présence (D11)

Vérifié : aucun reliquat n'affiche la pilule `YP CA 2 personnes dessinent` — il
ne reste que le commentaire de `WorkshopSpaceView` qui explique son absence.

### Jeu de démonstration

`RefonteDemoSeed+Lot17.swift`, en **extension** — ni `RefonteDemoSeed.swift` ni
`+Lot16` ne sont modifiés. `seedWorkshopComplete` appelle le semis du lot 16 puis
réécrit les scènes : `Flux réseau` devient un vrai Schéma (boîtes bleues,
**connecteurs liés** `startBinding`/`endBinding`), `Notes de Patrice` un vrai
Manuscrit (trois `freedraw` avec `pressures` et `simulatePressure: false`), la
planche active porte ses deux objets annotés (`Jenkins…` risque, `Qui porte…`
question), et la réunion gagne la pièce `Archi_cible_Cléva.pdf` de Yann et la
capture Teams de `21:10`. Idempotent. Une seule ligne change dans
`MeetingCommands` : la commande de recette appelle la version complète.

### Tests

`swift build` vert. `swift test` : **1 731 tests Swift Testing verts** (216
suites) et **1 041 XCTest, 1 ignoré, 1 échec** — soit 2 772 contre 2 714 sur la
base, **+58**. L'unique échec est
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, **préexistant et
horaire** : il échoue entre 0 h et 2 h du matin, indépendamment de tout lot, et
la suite a été lancée à **00:54 CEST**. Aucun test ne charge WebKit (plan §8) :
le pont est un protocole, `WhiteboardBridgeDouble` enregistre les huit nouveaux
appels.

### Écarts assumés

- **Lasso** : Excalidraw 0.18.1 n'a **pas** d'outil lasso (`grep lasso` sur le
  bundle : zéro occurrence). L'outil `Lasso` de la palette Manuscrit retombe donc
  sur la sélection **rectangulaire**. À reprendre si le moteur monte de version.
- **Pression** : implémentée, non vérifiée (aucune recette graphique dans ce
  lot ; procédure ci-dessus).
- **Alignement** : recalculé en Swift au lieu de l'`actionManager` d'Excalidraw,
  qui n'est pas exposé — cf. ci-dessus.
- **Calques** (mentionnés dans la table §7.1 du mode Schéma) : **non faits**.
  Ni la capture 6a ni les critères d'acceptation ne les demandent ; à arbitrer.
- **Dépôt sur la toile** : le dépôt de fichier est branché sur la **zone du
  dock**, pas sur la toile elle-même — un `onDrop` par-dessus le `WKWebView`
  entrerait en concurrence avec le glisser interne du moteur. À reprendre en
  recette si le geste manque.
- **Point de dépôt** d'une forme ou d'une image : décalage constant depuis le
  coin haut-gauche de la vue, et non le centre exact du cadre (la page ignore la
  taille de son propre cadre). L'objet est déposé **sélectionné**, donc
  immédiatement déplaçable.
- **Recette visuelle** : aucune, par consigne. La capture de référence
  `6a-atelier-planche.png` n'a donc pas été recomparée après ces ajouts.

**Prochaine action** : lot 18 (planche de séance 6b et rapport d'atelier), qui
dépend de ce lot et du lot 15.

## Recette visuelle des vagues 1 à 4 — écrans 1a, 1b, 1c, 3a, 3b (2026-09-08)

Branche `fix/refonte-recette-vagues-1-4`, sur
`fix/refonte-1to1-window-crash` (PR #31), donc au **sommet** de la pile
linéaire `#19 → #20 → #21 → #22 → #23 → #24 → #27 → #28 → #30 → #26 → #29 →
#25 → #31`. Recette complète :
`docs/superpowers/specs/refonte-2026-09/recette/2026-09-07-recette-vagues-1-4.md`
(tableau zone par zone pour les cinq écrans).

**État : neuf captures produites, 14 corrections de finition livrées en
6 commits, 18 écarts assumés confirmés, 12 écarts fonctionnels à traiter.
`swift build` propre, `swift test` complet à 2 402 tests. Recapture d'après
correction encore due — l'écran s'est verrouillé.**

### Captures produites

Dans `docs/superpowers/specs/refonte-2026-09/recette/` : `1a-1280.png`,
`1a-1920.png`, `1b-1920.png`, `1c-1280.png`, `1c-1920.png`, `3a-1280.png`,
`3a-1920.png`, `3b-1920.png` et **`3b-edition-1920.png`** — le mode Édition de
la fiche projet, que le lot 9 n'avait pas pu atteindre, est vu pour la première
fois. `lot-9-1280.png` est conservée.

Toutes sont prises dans la **fenêtre dédiée** `1to1-meeting` (celle du
correctif #31), donc sans la barre latérale de l'application, contrairement à
`lot-9-1280.png`. Store isolé (`HOME` **et** `CFFIXED_USER_HOME` jetables),
isolation vérifiée par `lsof` à chaque lancement : **zéro descripteur** sur le
store de production.

⚠️ **Les `*-1920.png` mesurent 1 728 × 1 023 pt, pas 1 920 × 1 080.** L'écran
de ce poste fait 1 728 × 1 117 pt et AppKit borne une fenêtre au cadre visible.
Un mode d'affichage à 2 056 × 1 285 pt existe, mais changer la résolution d'une
session de travail active n'est pas une décision à prendre seul (CLAUDE.md,
règle 6). Les `*-1280.png` sont, eux, exactement 1 280 × 800 pt.

⚠️ **Les captures livrées sont antérieures aux corrections** : l'écran s'est
verrouillé avant que le binaire corrigé ne soit empaqueté. Elles valent comme
constat, pas comme démonstration du résultat.

### Corrections de finition livrées

| Commit | Écran(s) | Correction |
| --- | --- | --- |
| `pilules et chips : une seule ligne` | 1a, 1c, 3a, 3b | `Chip`, `InvitePill` et `Pill` prennent `lineLimit(1)` + `fixedSize` : `＋ Pierre-Yves` se repliait en « ＋ Pierre- / Yves », `/décision` en « / décisio / n », `● Partage actif · 5 voient` en carré bleu. Même défaut que la chip « PostgreS / QL » du lot 9, remonté dans les primitives. |
| `1a : bandeau d'indicateurs et pile d'avatars` | 1a | **Les six pastilles d'avatar étaient invisibles** (`pill` = `surface` = `#ffffff` en clair, soit le fond de la carte) → fond `base`. Padding de carte désinversé (10 vertical × 12 horizontal, §2.3). Les 4 cartes reprennent une hauteur égale (`fixedSize` vertical + `maxHeight: .infinity`). |
| `barre du haut : libellés préservés, pilule de partage` | 1a, 3a, 3b | `Rapport ✓ 6:20` se réduisait à « R », `Capture` à « C » : le titre (`layoutPriority(1)`) gagnait l'arbitrage contre les contrôles, alors que §2.1 en fait la colonne fluide. Les contrôles passent en `fixedSize`. La pilule de partage passe de `radiusButton` (6) à `Capsule` (§4.2 + §1.2). |
| `notes ↔ transcription : corps 12,5 px, plus de recouvrement` | 1a, 3a | À 1 280 px, la décision de 11:03 recouvrait la note de 15:20 : le préfixe était un `HStack` aligné sur la première ligne de base, qui gardait la hauteur d'une ligne → un seul `Text` concaténé. Corps passé de 12 à **12,5 px** avec `line-height 1.55` (§1.2). |
| `frise audio lisible et rail d'actions à 330 px` | 1a, 1c, 3a | « Aucun audio » était écrit **par-dessus** les marqueurs sur les cinq captures → réservé à la frise sans marqueur. Bornes de frise en 10 px (§1.2). Le rail mesurait **329 px** : le filet est désormais prélevé sur la colonne fluide, pas sur le rail que §1.2 fixe à 330. |
| `1c : « ALERTES · 5 » et le singulier de « +1 autre »` | 1c | Point médian devant le compteur, comme `DÉCISIONS PRISES · 3` et `RISQUES · 5` ; singulier ; `ink/4`. |
| `contraste des textes sous 11,5 px` | 1a, 1c, 3a | Cinq emplois de `ink/muted` sous le seuil de §1.2 (« réservé aux placeholders de 11,5 px et plus ») passent en `ink/4` : compléments d'onglet, détail de risque, mention de la bande épinglée, légende d'aperçu, `⌘⇧V` de la zone de dépôt. |

Aucune couleur hors `One2OneToken`, aucune fonctionnalité nouvelle, aucun
service ni modèle touché, `MeetingView.swift` intact.

### Écarts assumés confirmés visibles (18)

Tous relevés sur les captures et **non touchés** : pile d'avatars triée par nom
et initiales `PY` (lot 1 n° 2 et n° 3) ; chips `/…` alignées à droite (lot 2
n° 2) ; `À ASSIGNER — 9` au lieu de 3 (lot 4) ; bouton `Capture` dans la barre
du haut (lot 1 n° 5) ; `Notes 6` au lieu de 5, compléments de `Synthèse` et
`Assistant`, sélecteur de mode et dock d'assistant dans le poste de pilotage,
titres du bloc `ALERTES`, nom de projet sans « Chaîne », cartes empilées sous
900 px (lot 5 n° 1, 2, 3, 6, 7, 10) ; groupe `DÉLÉGUÉES` (lot 3 n° 2) ;
`4 séance` comptant le lien (lot 6 n° 4) ; **barre de budget verte à 65,6 %**,
budget en champs inline, chevrons de réordonnancement des jalons, chips de
thèmes en grille adaptative (lot 9 n° 1, 3, 4, 6) ; rond ambre du risque sur la
frise (lot 2 n° 5) ; `Documents 4` au lieu de `Documents ＋`.

### Écarts fonctionnels à traiter (12) — détail dans le fichier de recette

1. **L'écran 1b n'est pas atteignable.** Le plein écran s'active (la barre de
   titre disparaît, donc `SessionWindowSwapper.presenter` a bien été
   parcouru) mais **le contenu n'est pas substitué** : le cockpit clair reste
   affiché, `Clore la séance` et `TRANSCRIPTION LIVE` sont absents de l'arbre
   d'accessibilité. Reproduit deux fois, par le bouton de la pilule audio et
   par l'item de menu. Piste : `WindowReader` fournit-il bien la fenêtre de la
   scène `1to1-meeting` ? **Bloque un écran entier de la spec → correctif au
   lot 4.**
2. Crash Auto Layout de la fenêtre dédiée, reproduit cinq fois en début de
   session — **avec un bundle empaqueté par erreur depuis un binaire périmé**
   (cf. n° 12). Plus aucun crash après reconstruction du bundle. À reverifier
   à la recapture.
3. Le **titre de réunion n'est pas un titre** : `EditableTextField` force
   `NSFont.systemFont` et un `bezelStyle` arrondi, et ignore le
   `.font(.plexSans(13, .semibold))` de la barre. → lot 19.
4. La barre du haut **reste affichée en mode Relire**, que la maquette 1c ne
   montre pas. Arbitrage (accès au type, au template, au `⋯`) → lot 19 + D0.
5. La bascule `Speakers` ne s'affiche jamais : le semis ne pose pas de
   locuteur sur ses segments. → lot 19 ou complément de semis, à trancher.
6. Les niveaux de risque bas sortent en **bleu et gris** ; la maquette
   n'emploie que `report` et `warn`. → lot 19 (décision de charte).
7. ⚠️ **La fenêtre de l'instance de production de l'utilisateur (pid 16538,
   « NPA/LDB ») a changé de géométrie** — 40,40 / 1 542 × 800 au début de
   session, 0,33 / 1 720 × 1 024 ensuite. Elle n'a pas été touchée après le
   constat. Parade durable : donner au bundle de recette un
   `CFBundleIdentifier` distinct dans `Scripts/recette-app.sh`, ce qui rendrait
   impossible la confusion de processus dont AppleScript est capable.
8. `Citer` et `Envoyer` n'apparaissent que sur la pièce présentée (§4.1 les
   veut par vignette). → lot 15 ou 19.
9. En édition, la carte `STATUT` perd son point coloré et met son chevron à
   gauche. → lot 19.
10. Le pied de la fiche projet (visibilité, `Annuler`, `Enregistrer`) n'existe
    qu'en édition ; §4.3 le liste sans condition. → lot 19.
11. La fiche projet en édition **tronque sans ellipsis** (risques,
    interlocuteurs) — même cause que le n° 3. → lot 19.
12. **`Scripts/recette-app.sh` peut empaqueter un binaire périmé sans le
    dire.** Le premier bundle de la session a été construit depuis un
    `.build/release/OneToOne` antérieur au build en cours ; il lui manquait les
    lots 4, 5 et 6, ce qui a produit deux heures d'observations fausses (mode
    Relire rendu comme au lot 1, ressources absentes) avant que la comparaison
    des chaînes du binaire ne le révèle. Le script devrait afficher `mtime` et
    taille du binaire copié, ou le comparer au dernier commit touchant
    `OneToOne/`. → lot 19.

### Conditions rencontrées

- **Écran** : déverrouillé pendant toute la série de captures (19 h 50 –
  20 h 30), verrouillé ensuite — c'est ce qui a empêché la recapture d'après
  correction. L'attente réglementaire a été tenue : sondage toutes les 50 s
  de **00:09 à 00:49 CEST**, soit 40 minutes, l'écran est resté verrouillé.
  La procédure de recapture, outillage compris, est écrite en fin du fichier
  de recette.
- **Teams** : aucune réunion en cours ; la seule fenêtre du processus `MSTeams`
  portait « Calendar | APRIL | … », vérifié avant chaque série.
- **Instance de l'utilisateur** : jamais d'événement envoyé, jamais arrêtée.
  Tout le pilotage passe par `AXUIElementCreateApplication(<mon pid>)` et
  `CGWindowListCopyWindowInfo` filtré sur `kCGWindowOwnerPID`, jamais par
  AppleScript ni par nom d'application ; `kill` ne cible que les pid dont la
  ligne de commande est le chemin du bundle de recette. Cf. écart n° 7.
- **Store de production** : jamais ouvert (vérifié par `lsof` à chaque
  lancement).

### Vérification

`swift build` propre. `swift test` complet, `exit 0` : **1 041 XCTest**
(1 ignoré) + **1 361 Swift Testing** en 177 suites = **2 402 tests**, le
chiffre exact du sommet de la pile.

**Un seul échec XCTest, préexistant et dépendant de l'heure d'exécution** :
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, suite lancée à
**00:04 CEST le 2026-09-08**. Le test place ses réunions « passées » à
`startOfDay + 1 h` et `+ 2 h` et attend qu'elles soient révolues — entre
minuit et 2 h du matin, elles sont dans le futur et `tempsPasseSeconds` vaut 0.
Rejoué **sur les sources du commit de base** (`1fe3f0a`, restauration de
`OneToOne/` seul) : échec à l'identique. Le diff de cette branche ne touche
aucun `Services/` ni `Models/`, et `TodayStatsCalculator` n'y figure pas.
**Non corrigé ici** — une PR de recette n'a pas à toucher un test de
statistiques ; à reprendre au lot 19 en injectant l'heure de référence, comme
le font déjà les autres tests de la suite. Le même échec est constaté par le
lot 8 à 00:33 CEST, sur une autre base.

### Prochaine action

1. **Recapturer les neuf écrans** avec le binaire corrigé, écran déverrouillé,
   et remplacer les fichiers de `recette/`.
2. **Ouvrir le correctif de l'écart n° 1** (mode séance plein écran
   inatteignable) : c'est le seul qui prive la spec d'un écran entier.
3. Traiter les autres écarts (c), et trancher les deux questions restées
   ouvertes du lot 9 (teinte de la barre de budget, lignes de démonstration
   dans le store de production).

## Intégration vague 6 : la pile redevient linéaire (2026-09-08)

Cinq branches développées en parallèle sur le sommet `feat/refonte-lot-12-1to1-manager-prepa`
(PR #33), remises en pile linéaire :
`#33 → 8 (#38) → 13 (#39) → 15 (#40) → 17 (#41) → recette (#36)`.

### Ce qui a conflicté, et rien de plus

Les quatre premiers maillons n'ont conflicté que sur **`STATUS.md`** — union des sections
en ordre chronologique inverse. Tout le code s'est recousu seul, ce qui n'était pas
acquis : `MeetingTopChromeBar.swift` est touché par les lots 13, 15, 17 **et** la recette,
mais dans des régions disjointes (fil d'Ariane et `Mon récap` pour le 13,
`compatibleTemplates` avec Escalade pour le 15, badge `ATELIER` et titre pour le 17, groupe
de contrôles et pilule de partage pour la recette). Vérifié à la lecture plutôt que sur la
foi du rebase :

- **`MeetingSpaceView.swift`** porte le modificateur `.sessionPill` du lot 8, la branche
  `CollaboratorSessionView` du lot 13 et le rail à 330 px de la recette. Ordre de routage
  conforme à la spec : Atelier → 1:1 mené → 1:1 subi → préparation → Relire → standard.
- **`OneToOneApp.swift`** : hotkeys de la pastille (lot 8) **et** semis / cible
  `.entretienSubi` du lot 13.
- **`MeetingCommands.swift`** : une seule ligne de semis par lot, et
  `seedWorkshopComplete` du lot 17 à la place de l'appel du lot 16.
- **`RecetteScreen`** couvre `1a 1b 1c 2a 2b 3a 3b 4a 5a 6a` (le lot 14 ajoutera `5b`).
- **`Models/OtherModels.swift`** : `acceptedProjectUpdatesJSON` en fin de type. **Aucune
  nouvelle version de schéma.**

### Trois arbitrages

**1. La largeur de la barre du haut — deux correctifs, une règle.** Le lot 17 et la
recette de la vague 1–4 visaient le **même** défaut par deux mécanismes différents : le
lot 17 donnait au titre une `layoutPriority(-1)` et un `fixedSize` au badge `ATELIER` (le
badge était tronqué à 1 616 px) ; la recette extrayait les contrôles de droite dans un
`controlsGroup` à `fixedSize` (à 1 280 px, `Rapport ✓ 6:20` se réduisait à « R », `Capture`
à « C », `● Partage actif · 5 voient` à un carré bleu). Les deux vont dans le même sens —
priorité de compression au **titre**, largeur intrinsèque aux contrôles — et **les deux
sont conservés** : n'en garder qu'une moitié ramène l'un des deux défauts. Ne restaient
incohérents que les commentaires (l'un décrivait encore le `layoutPriority(1)` que l'autre
venait de passer à `-1`) : refondus en une seule explication, moitié « qui cède » sur
`titleField`, moitié « qui ne cède pas » sur `controlsGroup`. Trois tests de lecture
verrouillent la règle entière dans `MeetingTopChromeBarTests`.

**2. Recette contre lots, sur les vues retouchées entre-temps.** Les 14 corrections de
finition datent d'avant les lots 7, 11, 12, 13, 15 et 17, qui ont retouché les mêmes vues.
Règle appliquée : la **finition** l'emporte quand le conflit porte sur un défaut visuel, le
**comportement** des lots quand il est fonctionnel. En pratique aucun conflit fonctionnel
n'est apparu, et les 14 corrections sont intactes : pastille `base` au lieu de `pill` dans
`AvatarStack` (invisible sur `surface`), `lineLimit(1)` sur `Chip` / `Pill` / `InvitePill`,
padding de carte 12 × 10 et cartes de hauteur égale dans `MeetingKPIBand`, « Aucun audio »
seulement quand la frise est vraiment vide, corps 12,5 px et interligne 1,55 dans les notes
et la transcription, rail à 330 px (le filet est prélevé sur la colonne fluide),
`ALERTES · 5`, singulier de « +1 autre », et `ink/4` partout sous 11,5 px.
`SessionNoChromeTests`, `ActionsRailNoModalTests`, `SessionThemeTests` et les tests de
contraste (`One2OneThemeTests`, `One2OneTokensTests`) restent verts.

**3. Le jeu de démonstration avait deux points d'entrée désaccordés.** Le lot 17 avait
remplacé `seedWorkshop` par `seedWorkshopComplete` dans le menu, mais pas dans le semis de
recette de `OneToOneApp` : la capture `6a` aurait montré l'atelier du lot 16, sans les
objets annotés, la pièce ni la capture du lot 17. Les deux points d'entrée sèment
désormais la même chose. `RefonteVague5IntegrationTests.semisEnsemble` reflétait lui aussi
la vague 5 (ni `seedLot13` ni `seedWorkshopComplete`) : il porte maintenant les sept semis,
avec un magasin de planches injecté dans un dossier temporaire — `seedWorkshopComplete`
écrit de vrais fichiers.

### La couture laissée par le lot 15

Le clic sur un timecode du rapport ne déplaçait pas la lecture. Toute la logique était là —
`CitationLinker` écrit les liens `onetoone://`, `MeetingReportPreview` les intercepte,
`QuickLaunchURLHandler.handle` sait déplacer une tête de lecture — mais **personne
n'appelait `handle`** : `MeetingReportSpace` ne recevait aucune `MeetingPlayhead` et le lien
mourait dans le délégué de navigation. Câblage seul, aucune logique nouvelle :
`MeetingReportSpace` reçoit `playhead` et passe `onCitation` à l'aperçu ; `MeetingView`
(l. 609) fournit `screen.playhead`. Deux tests purs, dont un bout à bout qui relit l'URL
**depuis le HTML du rapport** avant de la passer à `handle`.

### Vérifié

- `swift build` propre à chaque maillon. Les avertissements de concurrence Swift 6 sur
  `SessionPillPanelController.shared` et `MoodTrend.historyLength` viennent des branches
  elles-mêmes, pas de l'intégration.
- `swift test` complet et vert à chaque maillon, à l'échec **horaire préexistant**
  `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` près (entre 0 h et 2 h ;
  corrigé par la PR #37 sur `master`, hors pile) — toutes les exécutions de cette session
  sont tombées entre 01 h 02 et 01 h 20 CEST.
- Progression des totaux, chaque fois l'union exacte des apports : 2 714 (base #33) →
  **2 770** (lot 8) → **2 839** (lot 13) → **2 891** (lot 15, dont 2 tests de la couture) →
  **2 949** (lot 17) → **2 952** (recette, dont 3 tests d'arbitrage de largeur).
- `MeetingView.swift` : **2 064 lignes** (plafond 2 100), la seule ligne ajoutée étant
  celle de la couture.
- Un crash SwiftData isolé (`ModelContext.reset`, signal 5) est apparu sur **une**
  exécution du maillon 15, dans la suite `ScreenCaptureService` : c'est le flake que
  l'en-tête de `ScreenCaptureServiceTests` documente déjà (tâche OCR détachée, conteneurs
  en mémoire construits en parallèle). Non reproduit à l'exécution suivante ni sur les
  maillons suivants.

### Non fait

- **Aucune fusion** : la pile est publiée, les cinq PR rebasées et leurs bases corrigées.
- **Aucune recette visuelle** de cette session : pas de lancement de l'app. Les nouveaux
  écrans (5a, 6a complet, rapport avec citations, pastille) restent à voir à l'écran, et
  les nouvelles captures de la recette des vagues 1–4 restent à reprendre — les PNG
  versionnés sont **antérieurs** aux 14 corrections, comme leur fichier le documente.
- `feat/refonte-lot-14-1to1-collab-prepa` (sur le lot 13) et
  `fix/refonte-session-fullscreen-content` (sur #33) se rebaseront elles-mêmes sur cette
  pile ; elles n'ont pas été touchées.

## Refonte de l'écran de réunion — lot 14 : 1:1 collaborateur, préparation en 2 minutes (5b) (2026-09-08)

Branche `feat/refonte-lot-14-1to1-collab-prepa`, **rebasée sur
`feat/refonte-lot-13-1to1-collab-seance`** (sommet de la pile après le rebase du lot 13 sur le
lot 8). Plan du lot dans
`docs/superpowers/plans/2026-09-08-refonte-lot-14-1to1-collab-prepa.md`.

**État : livré, `swift build` propre, `swift test` vert (1 823 Swift Testing + 1 041 XCTest, un
seul échec, préexistant et horaire — cf. plus bas), PR ouverte, non mergée.**
**Recette visuelle différée à la passe de recette dédiée** ; le crochet est prêt
(`ONETOONE_SEED_DEMO_SCREEN=5b`).

### L'écran

`kind == .manager` + mode **Préparer** → `CollaboratorPrepView` : une **carte étroite de 940 px,
centrée**, et rien d'autre — ni rail d'actions, ni bandeau d'indicateurs, ni barre d'assistant.
Deux minutes veut dire dix lignes qu'on lit d'un coup d'œil ; une colonne de plus et l'écran
devient un tableau de bord qu'on remet à plus tard. Une branche dans `MeetingSpaceView.contenu`,
gardée par `MeetingSpaceRouting.usesOneOnOneCollaboratorPreparation` — exclusive des quatre autres
branches, ce que vérifie `CollaboratorPrepAgendaTests.routageExclusif` type par type et mode par
mode.

C'est aussi le **mode d'ouverture par défaut** d'un entretien subi sans enregistrement :
`initialMode` accepte désormais les **deux** types de tête-à-tête (`OneOnOneThreadStore.faceToFace`)
et non le seul `.oneToOne`.

| Bloc | Contenu |
| --- | --- |
| En-tête (`CollabPrepHeader`) | avatar `YP`, `1:1 avec Yann — demain 14:00`, `Préparation · 2 min · dernier point le <date>`, badge **bordé** `Collaborateur`. **Sans bouton** : un entretien subi ne se démarre pas depuis chez moi. |
| `RESTÉ SANS RÉPONSE` (`UnansweredCard`, `accent/report`) | cases **décochées**, libellé + `depuis le <date>` |
| `CE QUE J'AI LIVRÉ DEPUIS` (`DeliveredSinceCard`, `accent/ok`) | `DeliveredItemsBuilder` du lot 13, lignes `✓ … · date` et `◐ … · cause`, **sans bouton `Citer`** |
| `CE QUE JE VEUX OBTENIR` (`WantedCard`, `accent/oneonone`) | cases **cochées**, composeur pointillé `Ajouter…` |
| Pied | `En faire mon ordre du jour` (violet plein), `Partager les sujets à Yann` (bordé, confirmation légère), mention de provenance |

### La règle « resté sans réponse » — critère chantier 5 n° 4

`UnansweredItemsBuilder` (pur). Trois sources, **aucune saisie** :

1. **les promesses du manager non tenues** — manquées, ou ouvertes et échues (`CommitmentLedger`,
   la définition de la règle 1 de `ReminderRules`) ;
2. **les sujets évoqués ≥ 3 fois qu'aucune décision ne tranche** (`RecurringTopicsBuilder`, seuil
   `ReminderRules.recurringTopicThreshold`) ;
3. **les demandes `pending`/`waiting`** du fil (`AgendaCarryover.requests`, la liste même de
   `MyRequestsCard` au lot 13).

**La règle 2 du lot 10 est adaptée, pas appelée.** `ReminderRules.reminders` écarte les familles
déjà portées par un sujet `todo` de l'ordre du jour : sur la carte manager `À NE PAS OUBLIER`
c'est juste — un sujet inscrit ne risque pas d'être oublié. Ici c'est l'inverse du propos : un
sujet que je porte depuis trois séances **sans obtenir de décision** est exactement ce que cet
écran doit me remettre sous les yeux. Le seuil, le lexique et l'exclusion par décision sont
repris ; celle par l'ordre du jour ne l'est pas.

**Une ligne par famille de lexique.** Les trois sources se recoupent — la demande « Compensation
des astreintes » et la promesse « Grille de compensation des astreintes » sont le même sujet.
Sans regroupement l'écran afficherait quatre lignes là où la capture en montre deux, et cocher les
deux moitiés du même sujet le porterait deux fois à l'ordre du jour. Dans un groupe, **la source
la plus forte parle** (promesse > sujet récurrent > demande : une parole donnée et non tenue est
le fait le plus lourd d'un entretien), et `depuis le …` prend la **plus ancienne** date du groupe —
c'est l'ancienneté qui plaide, et c'est elle qui trie les lignes.

Sur le jeu des lots 10 et 13, cela donne exactement les deux lignes de la capture :
`Mobilité archi — 4 fois évoquée, jamais tranchée · depuis le 10 juil.` et
`Grille de compensation des astreintes promise, 2 reports · depuis le 24 juil.`

### `En faire mon ordre du jour`

`PrepToAgenda`. Le **plan** est pur : les lignes cochées de `RESTÉ SANS RÉPONSE`, préfixées selon
leur source (`Promesse : `, `Sujet : `, `Demande : ` — sans quoi l'ordre du jour de la séance
suivante afficherait une phrase sans dire d'où elle sort), puis les sujets voulus non décochés,
tels que je les ai écrits.

`apply` retrouve par le **texte** ou crée, rattache à la séance préparée, et numérote `0…n-1`
**dans l'ordre du plan** ; les autres sujets de la séance sont renumérotés à la suite, sans quoi
un sujet voulu — qui existait déjà avec un rang bas — devancerait les lignes sans réponse dès le
premier clic. Les demandes gardent leurs rangs : les deux cartes de la séance filtrent des listes
séparées (ce que documente déjà `CollaboratorSessionModel.moveTopics`). Idempotent, donc un second
clic ne duplique rien ; le bouton se désactive alors sur `Ordre du jour prêt · n sujets`.

Tout est créé `private` (spec §6.1 : côté collaborateur le défaut n'est pas négociable).
`Partager les sujets à <Prénom>` est le geste explicite du critère n° 2 : il verse (idempotent)
puis passe **ces lignes-là** en `shared`, après une confirmation qui n'affiche que leur **compte** —
la seule chose qu'on veut relire avant de rendre visible ce qu'on avait écrit pour soi. Une ligne
`escalated` ne redescend jamais vers le manager par ce geste (D9).

Un sujet déjà versé est retiré de `CE QUE JE VEUX OBTENIR` : les lignes créées sont des sujets
privés `todo`, et sans cela la carte du bas les reprendrait toutes après le premier clic.

### Ouverture la veille

Le pré-rappel d'une réunion `kind == .manager` prend une **catégorie propre**
(`MEETING_PRE_START_1TO1`) dont la première action est `Préparer`. Une catégorie et non une action
de plus sur `MEETING_PRE_START` : les actions d'une notification sont figées par sa catégorie, et
un « Préparer » sur une réunion de projet ouvrirait un écran qui n'existe pas pour elle.
`preStartCategory(for:)` est **pure et `nonisolated`** — la présence de l'action ne dépend d'aucun
réglage. L'action **impose le mode par la clé mémorisée** (`MeetingScreenModel.modeKey`) avant de
poster le même avis d'ouverture que « Ouvrir » : c'est le chemin qu'emploient déjà le crochet de
recette et `MeetingSpaceView.appliquerModeInitial`, pas un second chemin. Aucun test n'instancie
`UNUserNotificationCenter`.

### Fichiers

**Services (purs, testés) :** `Services/OneOnOne/Prep/{CollaboratorUnansweredItems,
CollaboratorWantedItems, CollaboratorPrepModel, CollaboratorPrepToAgenda,
CollaboratorPrepStore}.swift`.

**Vues :** `Views/Meeting/OneOnOne/CollaboratorPrep/{CollaboratorPrepView, CollabPrepHeader,
CollabPrepCheckbox, UnansweredCard, DeliveredSinceCard, WantedCard}.swift`.

**Pas de `RefonteDemoSeed+Lot14.swift`** : le périmètre le prévoyait « seulement si une donnée
manque », et rien ne manque — les deux lignes sans réponse, les quatre livrés et les deux sujets
voulus de la capture sortent tous du jeu des lots 10 et 13. Un semis de plus serait un doublon à
tenir en phase.

**Fichiers partagés touchés, en blocs localisés :** `MeetingSpaceRouting.swift` (une fonction +
la garde de `initialMode`), `MeetingSpaceView.swift` (une branche), `OneOnOneScreenState.swift`
(`collabPrepCheckedUnanswered`, `collabPrepDroppedWanted`, **en fin de type**),
`RecetteScreen.swift` (code `5b`), `MeetingNotificationService.swift` (la catégorie, l'action, la
fonction pure et une branche du gestionnaire). `MeetingTopChromeBar.swift`, `MeetingView.swift`,
`MeetingScreenModel.swift`, `OneToOneApp.swift` : **rien**.

**Tests :** `Tests/CollaboratorPrepBuildersTests.swift` (9 cas) et
`Tests/CollaboratorPrepAgendaTests.swift` (18 cas). Trois suites existantes ajustées d'une ou deux
lignes : `RefonteVague5IntegrationTests` (onzième code de recette, cinquième branche exclusive),
`ManagerPrepRoutingTests` (`.manager` sort de la liste des types qui gardent leur mode
d'ouverture), `MeetingNotificationCategoriesTests` (dixième catégorie).

### Les critères

- **Chantier 5 n° 4** — `UnansweredItemsBuilder` sur le jeu du lot 13 : la promesse ouverte et
  échue du 24 juillet, reportée deux fois, remonte **seule**, avec son ancienneté. Personne ne l'a
  ressaisie.
- **`PrepToAgenda`** — ordre (les lignes sans réponse préfixées devant les sujets voulus),
  idempotence (un second clic ne crée rien, les rangs ne bougent pas), visibilité privée par tous
  les chemins, passage en `shared` par le second bouton et par lui seul, et l'escalade qui ne
  redescend pas.
- **Cases par défaut** — décochées à gauche, cochées à droite : l'état d'écran ne retient que les
  cases cochées d'un côté et les **refus** de l'autre, donc un sujet ajouté à l'instant naît
  coché.
- **En-tête** — `demain 14:00` avec horloge injectée, plus `aujourd'hui`, le jour de la semaine
  dans les sept jours (`OneOnOneDateFormat.dueDate`, la règle de toutes les échéances du domaine)
  et la date au-delà.
- **Notification** — la catégorie du 1:1 subi porte `Préparer` en tête ; **aucune** autre
  catégorie ne la porte, pour aucun autre type.
- **Aucune zone vide sans invite** — sur un fil neuf, les trois blocs ont leur invite, et chacune
  dit quoi faire.

### Écarts avec la capture, assumés

- **Les libellés reprennent le texte des données, pas celui de la maquette.** La capture écrit
  `Grille d'astreinte promise, 2 reports` là où la promesse semée s'appelle « Grille de
  compensation des astreintes » : le gabarit est celui de la capture, le texte reste celui de la
  donnée. Une table de synonymes pour raccourcir les libellés ne serait tenue par personne.
- **Le compteur d'occurrences est celui du fil.** La capture dit « 3 fois évoquée » ; le jeu de
  démonstration compte **quatre** mentions de la famille `carriere` (deux sujets, deux notes).
- **`5b` ouvre la séance du 4 septembre en mode Préparer**, celle de `5a` : c'est la seule séance
  du fil, et c'est elle qui porte les quatre livrables et les deux lignes sans réponse de la
  capture. L'en-tête y écrit donc sa date réelle et non `demain 14:00` — la règle « demain » est
  tenue et **testée avec une horloge injectée** plutôt que mise en scène par un semis qui
  décalerait la fenêtre de `CE QUE J'AI LIVRÉ DEPUIS`.
- **Le détail d'un livrable suit son libellé sur la même ligne**, comme la capture : une carte qui
  tient en deux minutes ne double pas sa hauteur pour une date.

### Un échec de test préexistant, horaire

`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` (XCTest) échoue **entre 0 h et 2 h du
matin**, indépendamment de tout lot : la suite a été passée à **01:10 CEST le 8 septembre**,
après le rebase sur le lot 13 rebasé, et c'est le **seul** échec. Non corrigé — il n'appartient pas à ce lot.

### Pour la passe de recette

`ONETOONE_SEED_DEMO_SCREEN=5b` (crochet unique, table `RecetteScreen`) sème les fils des lots 10
à 13 et ouvre l'entretien subi **en mode Préparer**. Le menu **Réunion** charge le même jeu.

### Prochaine action

Fait à l'intégration de la vague 7 (section en tête) : la branche est rebasée sur le sommet de
recette `fix/refonte-recette-vagues-1-4`, qui contient déjà le lot 13. Reste à fusionner dans
l'ordre de la pile. La recette visuelle de `5a` et `5b` se fait dans la passe dédiée.

## Correctif : le mode séance plein écran (écran 1b) est enfin affiché (2026-09-08)

Branche `fix/refonte-session-fullscreen-content`, **rebasée à l'intégration de la vague 7 sur le
lot 14** (#43), lui-même sur le sommet de recette — elle était partie du lot 12 (#33). Corrige
l'écart fonctionnel n° 1 de la recette des vagues 1 à 4 (PR #36) : « le plein
écran s'active mais le contenu n'est pas substitué — le cockpit clair reste
affiché, `Clore la séance` absent de l'arbre d'accessibilité ».

**Cause racine.** `SessionWindowSwapper` substituait le `contentView` de la
`NSWindow`. Or `NSWindow.contentView = …` détache l'ancienne racine
**synchroniquement, dans l'affectation elle-même**, et SwiftUI fait aussitôt
partir le `onDisappear` de la vue détachée — c'est-à-dire celui du modificateur
`sessionFullscreen` posé sur `MeetingSpaceView`, dont le `sortir()` restaure le
`contentView` d'origine. La restauration s'exécutait donc **avant** le
`toggleFullScreen(nil)` de la ligne suivante : la fenêtre partait en plein écran
sur le cockpit, barre de titre masquée par les deux lignes qui suivaient encore
la restauration. Reproduit hors application (`NSHostingView` + affectation de
`contentView` : `onDisappear` part avant même que l'affectation ne rende la
main).

**Correctif.** La présentation passe dans la hiérarchie SwiftUI. L'écran
*publie* son mode séance — `screen.session` et la vue — au
`SessionFullscreenPresenter` ; la **racine de la fenêtre** (`.sessionFullscreenHost()`,
posé sur les deux scènes à réunion dans `OneToOneApp`) monte ce qui est publié,
par-dessus son contenu et hors de l'arbre d'accessibilité. AppKit ne fait plus
que le plein écran (`SessionWindowFullscreen`) : plus aucune vue n'est déplacée,
donc plus rien ne s'auto-annule. `SessionWindowSwapper` est supprimé.

Deux effets de bord voulus : la fenêtre qui part en plein écran **par une autre
voie** (l'item natif « Activer le mode plein écran » du menu Affichage porte le
même `⌃⌘F` que la spec §2.6, et AppKit cherche ses équivalents clavier dans
l'ordre des menus ; le bouton vert aussi) entre désormais en mode séance au lieu
d'agrandir le cockpit ; et en sortir referme le mode.

**Preuve.** Par lecture + reproduction hors application + tests
(`Tests/SessionFullscreenRootTests.swift`, 7 tests : machine d'état → racine,
identité de fenêtre, et lecture des sources). **La recette en bundle n'a pas pu
être refaite : l'écran de la session est verrouillé depuis 21 h 02** (`ioreg`
rend `"CGSSessionScreenIsLocked"=Yes` — attention, la forme sans espaces autour
du `=` ne correspond pas au motif `grep` de la consigne, qui répond donc « rien »
à tort). Reste à vérifier écran déverrouillé : que `⌃⌘F` ouvre bien 1b dans la
fenêtre `1to1-meeting`, et la capture `1b-1920.png` d'après correction.

`swift build` propre (debug + release), `swift test` à **2 721 tests** — seul
échec `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`, préexistant et
horaire (lancé à 01 h 03 CEST).

## Lot 18 — Atelier : planche de séance et rapport (6b) (2026-09-08)

Branche `feat/refonte-lot-18-planche-de-seance`, développée sur
`feat/refonte-lot-17-atelier-modes` et **rebasée** en cours de route sur le
sommet `78624e9` une fois l'intégration de la vague 6 terminée — c'est ce rebase
qui a fait entrer le lot 15 (`{{planches}}`, `ReportOptionalBlocks`) dans la
base, donc rendu la tâche 6 possible dans le même lot. Plan :
`docs/superpowers/plans/2026-09-08-refonte-lot-18-planche-de-seance.md`. Tout
reste derrière `AppSettings.workshopEnabled`.

### La frise est un modèle pur, pas une vue

`WorkshopTimelineModel.rows(for:)` rend une ligne par élément produit — planche,
capture, pièce épinglée — triée par timecode, avec son pied (`Type — titre ·
auteur`) et sa mention de droite (`stylet`, `texte extrait`…). Aucun `View`
n'entre dans le calcul : les 246 lignes de `Tests/WorkshopTimelineTests.swift`
tournent sans WebKit et sans fenêtre. `WorkshopSessionSheetView` ne fait que
poser la carte de 920 px, la colonne de timecodes de 40 px et l'aperçu de 92 px
par-dessus ce modèle.

### La légende est calculée, l'assistant ne fait que la reformuler

`BoardCaptionBuilder.caption(mode:scene:)` lit la scène Excalidraw et compte ce
qu'elle contient (formes, tracés, notes, connecteurs, textes) : `Manuscrit —
3 tracés · « 3 runners → autoscale ? »`. C'est **la** légende, disponible hors
ligne et sans modèle ; `refined(...)` la donne à l'assistant, borne sa réponse
en durée et en longueur, et **conserve la légende calculée** si la réponse
manque, tarde ou dépasse. Le contraire — un modèle dans le chemin nominal —
aurait fait dépendre l'affichage de 6b d'un endpoint IA joignable, ce que
« local d'abord » interdit.

### Deux écarts assumés à la maquette

1. **`.drawio` n'apparaît pas**, ni dans l'encart de clôture ni dans
   `index.md` : hors v1 (décision D6). Un test l'interdit explicitement plutôt
   que de l'oublier par accident.
2. **`Décrire les planches`** est un bouton secondaire *absent* de la maquette.
   Sans lui, le raffinement par l'assistant (spec §7.2) n'aurait aucun point
   d'entrée ; le poser sur `Joindre au rapport` aurait fait partir une requête
   réseau depuis une action que la spec veut locale.

### Ce que le semis de recette gagne

`RefonteDemoSeed.seedWorkshopSession` enveloppe celui du lot 17 et ajoute les
trois éléments que 6b montre : les deux lignes manuscrites lisibles de `Notes de
Patrice`, le texte extrait de la capture Teams — dont la tête devient le titre
de sa carte — et l'épinglage de la pièce de Yann à `05:00`. Les légendes sont
calculées au semis, donc reproductibles sans réseau. Les **deux** points
d'entrée (raccourci `6a`/`6b` et menu Réunion) passent au même semis : les
faire diverger rendrait une capture incomplète selon la porte empruntée.
`RecetteScreen` compte **douze** codes après l'intégration de la vague 7, qui a
fait entrer le `5b` du lot 14 à côté du `6b` de ce lot.

### État

`swift build` propre, `swift test` **vert : 1943 tests, 242 suites** (lancé à
05:06, hors de la fenêtre 0 h–2 h qui fait échouer
`MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`). PR ouverte sur
`feat/refonte-lot-17-atelier-modes`, **non fusionnée**.

**Prochaine action** : faire relire la PR du lot 18. Elle est empilée depuis
l'intégration de la vague 7 (section en tête) derrière
`fix/refonte-session-fullscreen-content`, et non plus derrière le lot 17. Le
raffinement de légende par l'assistant n'a pas de test d'intégration réseau —
seuls ses replis sont couverts ; à confirmer sur un endpoint réel lors de la
recette de 6b.

## Intégration vague 7 : la pile redevient linéaire (2026-09-08)

Trois branches développées en parallèle sous le sommet de recette
`fix/refonte-recette-vagues-1-4` (PR #36), remises en pile linéaire :
`#36 → 14 (#43) → 42 → 18 (#44)`.

| Maillon | Branche | Base après intégration | `swift test` |
| --- | --- | --- | --- |
| 1 | `feat/refonte-lot-14-1to1-collab-prepa` (#43) | `fix/refonte-recette-vagues-1-4` | 1 923 ST + 1 054 XCT = **2 977**, vert (05:13 CEST) |
| 2 | `fix/refonte-session-fullscreen-content` (#42) | lot 14 | 1 930 ST + 1 054 XCT = **2 984**, vert (05:18 CEST) |
| 3 | `feat/refonte-lot-18-planche-de-seance` (#44) | correctif du plein écran | 1 978 ST + 1 054 XCT = **3 032**, vert (05:26 CEST) |

### Maillon 1 — lot 14 sur la recette

Rebase `--onto origin/fix/refonte-recette-vagues-1-4 origin/feat/refonte-lot-13-1to1-collab-seance`.
**Un seul conflit : `STATUS.md`** — union, la section du lot 14 en tête de celle de
l'intégration de la vague 6. Tout le code s'est recousu seul, et la lecture le confirme
plutôt que le rebase :

- `MeetingSpaceRouting.swift` — la recette n'y avait pas touché ; les cinq prédicats de
  1:1 (11, 12, 13, 14) cohabitent, `initialMode` couvre les deux types de tête-à-tête.
- `MeetingSpaceView.contenu` — l'ordre voulu est en place : Atelier en séance → 1:1 mené
  (séance, préparation) → 1:1 subi (séance, préparation) → Relire → standard. Les
  prédicats restent exclusifs deux à deux (`RefonteVague5IntegrationTests.routageExclusif`).
- `RecetteScreen` — onze codes, `1a 1b 1c 2a 2b 3a 3b 4a 5a 5b 6a`.
- `OneToOneApp.ouvrirEcranDeRecette` et `MeetingCommands` — mêmes semis, chacun appelé une
  fois : lots 5, 6, 7, 11, 12, 13 puis `seedWorkshopComplete` pour l'atelier.

`Scripts/recette-run.sh` a été **corrigé au passage** : sa liste `SCREENS` et sa table
d'en-tête ignoraient `5a` et `5b`, ajoutés aux lots 13 et 14 sans que le script suive
(`6b` a suivi au maillon 3). Aucun test ne lisait ce fichier — c'est la recette manuelle
qui aurait buté sur « code inconnu ».

### Maillon 2 — le correctif du plein écran sur le lot 14

Rebase `--onto lot14 origin/feat/refonte-lot-12-1to1-manager-prepa`. **Un seul conflit :
`STATUS.md`** — union, la section du correctif au-dessus de celle du lot 14. Le code du
correctif s'est appliqué tel quel, et pour une bonne raison : `Views/Meeting/Session/**`
est **identique** entre le lot 12 et le sommet de recette (différence vide), donc la
finition visuelle de la recette n'a jamais touché `SessionFullscreenView` ni
`SessionStatusBar` — il n'y avait rien à réconcilier, contrairement à ce que la consigne
d'intégration redoutait. Vérifié après coup :

- `.sessionFullscreenHost()` posé **deux fois** dans `OneToOneApp` (fenêtre principale et
  scène `1to1-meeting`) — c'est ce que compte `SessionFullscreenRootTests.windowRootsHostTheMode`.
- `SessionWindowSwapper` n'existe plus que dans le test qui interdit son retour, et la
  seule occurrence de `contentView =` dans `Session/**` est une ligne de commentaire
  (`///`), que le test écarte. Les deux assertions de `noAppKitViewSwapLeft` tiennent.
- `SessionNoChromeTests`, `SessionThemeTests`, `SessionFullscreenTests` et
  `SessionFullscreenRootTests` verts ensemble.

**Un plantage non reproductible** est survenu au premier `swift test` du maillon, *après*
la dernière suite (`ScreenCaptureService` verte) : `SwiftData/BackingData.swift:835: Fatal
error: This model instance was destroyed by calling ModelContext.reset`, signal 5, sans
qu'aucun test n'échoue. Aucun `reset()` n'existe dans le dépôt : c'est la destruction d'un
conteneur en mémoire à la fin du processus pendant qu'une instance de `Meeting` est encore
retenue. Relance immédiate **verte, sans le moindre message** — flottement de fin de
processus, indépendant du correctif, à ressortir s'il revient.

### Maillon 3 — le lot 18 sur le correctif

Rebase `--onto fix42 origin/feat/refonte-lot-17-atelier-modes`. **Quatre conflits**, tous
sur des fichiers que le lot 14 et le lot 18 ajoutent au même endroit :

| Fichier | Choix |
| --- | --- |
| `MeetingSpaceRouting.swift` | Union : les cinq prédicats de 1:1 **et** `usesWorkshopReview`. Le lot 18 arrivait sur une base sans `usesOneOnOneCollaboratorPreparation`. |
| `RecetteScreen.swift` | Union du `switch mode` : `.posteDePilotage` et `.atelierPlancheDeSeance` en Relire, `.oneOnOnePreparation` et `.collaboratorPreparation` en Préparer. **Douze codes.** |
| `MeetingSpaceView.contenu` | Union, mais **pas** dans l'ordre du lot 18 : la branche 6b remonte auprès de l'atelier en séance, pour tenir l'ordre voulu Atelier (séance, Relire) → 1:1 mené → 1:1 subi → standard. Le commentaire d'en-tête dit désormais que 6b est la seule vraie priorité du routage. |
| `Tests/RefonteVague5IntegrationTests.swift` | Union : `5b` **et** `6b` dans la table, douze codes attendus. |

Trois retouches que ni l'une ni l'autre branche ne pouvait faire seule :

1. **`routageExclusif`** comptait `mode == .review` comme une branche. Avec 6b, l'atelier en
   Relire faisait deux prétendants et le test tombait. Le poste de pilotage est désormais
   écrit pour ce qu'il est dans la vue : `mode == .review && !usesWorkshopReview(…)` — sept
   branches, toujours au plus une allumée.
2. **`semisEnsemble`** appelait encore `seedWorkshopComplete` (lot 17). Il passe à
   `seedWorkshopSession`, comme les deux points d'entrée de production ; le lot 14 n'ajoute
   rien, il n'a pas de semis propre.
3. **`WorkshopSessionRoutingTests.screenPredicatesStayMutuallyExclusive`** ignorait le
   prédicat du lot 14, qui n'existait pas dans sa base. Ajouté.

### Ce que l'union donne

`RecetteScreen` : `1a 1b 1c 2a 2b 3a 3b 4a 5a 5b 6a 6b` — douze codes, tous dans
`Scripts/recette-run.sh`. Un seul semis par point d'entrée, les deux identiques :
lots 5, 6, 7, 11, 12, 13 puis `seedWorkshopSession`. `MeetingView.swift` à 2 064 lignes.

### L'ordre de fusion, de bout en bout

Rien n'est fusionné : les vingt-quatre PR de la refonte forment une seule chaîne, à
prendre dans cet ordre.

`#19` (0b) → `#20` (0a) → `#21` (1a) → `#22` (1b) → `#23` (2) → `#24` (3) → `#27` (4) →
`#28` (5) → `#30` (6) → `#26` (10a) → `#29` (10b) → `#25` (9) → `#31` (correctif fenêtre
1:1) → `#32` (16) → `#34` (7) → `#35` (11) → `#33` (12) → `#38` (8) → `#39` (13) →
`#40` (15) → `#41` (17) → `#36` (recette 1–4) → **`#43` (14) → `#42` (plein écran) →
`#44` (18)**.

Hors chaîne : `#18` (programme, docs) et `#37` (test horaire de la pastille), tous deux
sur `master`. `#45` (lot 19a, clôture) se rebasera lui-même sur `#44`.

**Prochaine action** : faire relire les trois PR de la vague, puis fusionner la chaîne
dans l'ordre ci-dessus. La recette visuelle de `5b` et `6b` reste à faire dans la passe
dédiée, avec `Scripts/recette-run.sh --screen 5b` puis `--screen 6b`.

## Lot 19a : retrait du code que la refonte a laissé derrière elle (2026-09-08)

La refonte a remplacé l'écran de réunion sans rien supprimer : la décision **D8** du
programme a débranché le dashboard et la sidebar configurable dès le lot 1, en renvoyant
le retrait de leur code au lot 19. Ce lot solde cette dette, et **elle seule** — aucun
comportement ne change, aucune vue vivante n'est retouchée autrement que dans ses
commentaires. **2 823 lignes retirées, 146 ajoutées.**

### Comment le code mort a été identifié

Pas à la lecture de la liste du programme, qui nomme trois symboles (`PanelLayoutEntry`,
`DashboardGridLayout`, `CollaboratorDetailView`) sur les onze fichiers concernés, mais par
un **point fixe** : pour chaque type déclaré dans `OneToOne/`, compter ses citations dans
les autres fichiers **hors commentaires et chaînes**, retirer les fichiers dont aucun type
n'est cité, et **recommencer** — un fichier mort ne compte plus comme référent. Trois
enseignements, qu'aucune recherche simple ne donnait :

1. **Les commentaires maintenaient le mort en vie.** `OverviewDashboard` est cité par
   quatre fichiers vivants (`MeetingView`, `MeetingScreenModel`, `ActionsRail`,
   `ActionsPanel`) — **uniquement dans des commentaires**. Un `grep` sur le nom aurait
   conclu que la vue servait encore.
2. **La cascade compte plus que la première passe.** `DashboardCard` n'apparaît mort
   qu'après le retrait des quatre cartes qui l'employaient ; `MeetingAvatarStack` qu'après
   celui de `PresenceCard`, son dernier hôte ; `ProjectStatusPalette.color(_:)` qu'après
   celui de l'ancienne fiche collaborateur **et** de `ProjectsPanel`, ses deux appelants.
3. **L'analyse par noms de types produit des faux positifs.**
   `TimedNotesColumn+Capture.swift` en est un : aucun de ses deux types n'est cité
   ailleurs, mais ses **membres d'extension** (`carteDeCapture`, `estCarteDeCapture`) sont
   appelés en `TimedNotesColumn.swift:120‑121`. Le fichier est bien vivant, et n'a pas été
   supprimé. C'est pourquoi le compilateur, et non le script, a le dernier mot.

### Ce qui est parti

**Onze fichiers, 1 853 lignes, supprimés intégralement** — les deux dossiers
`Views/Meeting/Dashboard/` et `Views/Meeting/Sidebar/` disparaissent :

| Fichier | Lignes | Pourquoi mort |
| --- | --- | --- |
| `Sidebar/ActionsPanel.swift` | 645 | monté seulement par `OverviewDashboard` |
| `ManagerAgendaSidebar.swift` | 326 | plus aucun hôte depuis le lot 1 |
| `Dashboard/OverviewDashboard.swift` | 255 | débranché par D8 au lot 1 |
| `Sidebar/ProjectsPanel.swift` | 146 | panneau de la sidebar configurable |
| `Dashboard/DashboardGridLayout.swift` | 91 | `Layout` du seul dashboard |
| `Dashboard/PresenceCard.swift` | 82 | carte du dashboard |
| `Sidebar/CapturePanel.swift` | 74 | panneau de la sidebar configurable |
| `Sidebar/PanelLayoutEntry.swift` | 66 | modèle de la disposition de la sidebar |
| `Dashboard/DashboardCard.swift` | 57 | **cascade** : cadre des quatre cartes |
| `Dashboard/TranscriptionCard.swift` | 57 | carte du dashboard |
| `Sidebar/RightSidebarPanelID.swift` | 54 | identifiants des panneaux |

**Et cinq retraits partiels :**

- **`CollaboratorDetailView`, 618 lignes** (`Views/DetailsViews.swift` l. 626‑1242).
  L'ancienne fiche collaborateur, remplacée par `CollaboratorFicheView` aux lots 12 à 14 :
  plus une seule présentation dans l'application. `ProjectDetailView` et `KeyPointAdder`,
  ses voisins de fichier, restent — `KeyPointAdder` est employé l. 167.
- **`SummaryCard` scindée.** La carte est morte avec le dashboard, mais ses deux fonctions
  statiques ne l'étaient pas : `generate(meeting:settings:)` et `transcriptSource(for:)`
  sont **les seules définitions** du résumé court et du « texte de la réunion », appelées
  par `MeetingView`, `MeetingLiveSpace` et `OneSentenceCard`. Elles emménagent dans
  `Services/Meeting/MeetingSummaryService.swift` (espace de noms `enum`, convention de
  `Services/`) plutôt que de garder une vue en vie pour ses membres statiques.
- **`MeetingAvatarStack`, 55 lignes**, morte avec `PresenceCard`. Son fichier hébergeait
  aussi `AvatarCircle` et `AvatarMini`, bien vivantes (huit appels dans les écrans hors
  refonte) : seule la pile est retirée, et le fichier prend le nom de ce qu'il contient,
  `MeetingAvatars.swift`.
- **`MeetingView.currentSlides`**, 13 lignes : dernier lecteur parti avec `CapturePanel`.
- **`ProjectStatusPalette.color(_:)`** : ses deux appelants étaient la fiche et
  `ProjectsPanel`. Seul le tri survit, employé par `ReportTemplating`.

**Un test supprimé** : `Tests/PanelLayoutEntryTests.swift` (80 lignes), qui ne couvrait que
`PanelLayoutEntry` et `RightSidebarPanelID`.

### Ce qui reste, et pourquoi

- **`ActionsViewMode.kanban` et `.sticky` restent.** Non par oubli : `ActionsListView` —
  l'écran Actions, hors refonte — emploie les cinq cas, et `ActionsRail.swift:143` fait
  retomber sur `Liste` une valeur `kanban` mémorisée par l'ancien panneau plutôt que
  d'afficher un écran vide. Deux tests verrouillent la règle
  (`ActionsViewModeTests`, `MeetingScreenModelTests.railViewModeRejectsNonRailCases`) ;
  ils citent `ActionsPanel` dans leurs commentaires, au passé, et restent justes.
- **`AppSettings.rightSidebarLayoutJSON` garde sa colonne, sans lecteur.** Ses deux
  lecteurs sont partis (`PanelLayoutEntry`, `OverviewDashboard`) ; la retirer demanderait
  une version de schéma et une migration pour une chaîne que plus rien ne relit — prix payé
  par tous les stores existants, gain nul. **Pas de migration**, `CurrentSchema` reste
  `SchemaV3`. La colonne partira avec la prochaine migration qui a, elle, une raison d'être.
- **Les commentaires qui nomment le code retiré ont été relus un par un**, pas effacés en
  masse : ceux qui racontent l'histoire au passé (« l'ancien `ActionsPanel` », « a quitté
  `ActionsPanel.swift` ») sont justes et restent ; huit qui décrivaient le mort au présent
  ont été refondus. Deux **mentaient déjà** avant ce lot : `EditableTextField` et
  `MarkdownNoteEditor` annonçaient présenter `CollaboratorDetailView` en feuille alors
  qu'ils présentent `CollaboratorFicheView` depuis les lots 12‑14 ; `NotesSection` se
  disait embarquée dans deux fiches alors qu'il n'en reste qu'une.

### Vérification

`swift build` puis `swift test` : **1 898 tests Swift Testing en 234 suites et 1 047 tests
XCTest passent**, un seul saut (`AudioImportServiceTests.test_smokeRealFile_ifConfigured`,
préexistant, attend `ONETOONE_SMOKE_AUDIO`). Aucun test n'a eu à être adapté hors celui qui
a été supprimé — le signe que ce lot ne change aucun comportement.

**L'échec horaire de `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` ne s'est
pas reproduit** : la suite a tourné à **05:19 CEST**, hors de la fenêtre 0 h–2 h identifiée
par les lots 8 à 17. Le diagnostic tient donc, et le correctif (injecter l'heure de
référence) reste dû.

### Écarts assumés

1. **Aucune recette visuelle.** Ce lot ne touche à aucun pixel : les onze fichiers
   n'étaient montés par aucun écran, et les vues vivantes ne changent que dans leurs
   commentaires. La recapture des neuf écrans, due depuis la recette des vagues 1‑4, reste
   due — et n'est pas de ce lot.
2. **`MeetingScreenModel.newTaskPomodoros` n'est pas retiré.** Le lot 3 l'avait conservé
   « parce qu'`ActionsPanel` l'emploie encore » (écart assumé n° 8) ; ce panneau vient de
   partir, et la propriété n'a plus un seul lecteur en production. Elle reste néanmoins :
   trois tests de `MeetingScreenModelTests` l'écrivent et vérifient sa remise à zéro, et
   toucher au modèle d'écran dépasse l'intention annoncée de ce lot. **À retirer au 19b**,
   avec les trois assertions.
3. **Le dossier `Views/Meeting/Dashboard/` disparaît, `Views/Shared/` reste bancal** :
   `ProjectStatusPalette` ne contient plus qu'une fonction de tri sans SwiftUI et
   n'appartient plus à `Views/`. Déplacer le fichier serait une seconde intention ; laissé
   en place, signalé ici.
4. **Le plan `docs/superpowers/plans/2026-09-08-refonte-lot-19a-cloture.md` n'existe pas.**
   Ce lot a été déroulé depuis le périmètre du lot 19 du plan directeur (l. 457) et les
   consignes de la coordination, l'analyse des appelants ayant été refaite de zéro.
5. **Du code mort sans lien avec la refonte a été trouvé, et laissé.** Le point fixe signale
   aussi 22 fichiers morts hors périmètre : `Services/Agent/` (7 fichiers, ~900 lignes,
   couverts par 6 suites de tests qui les maintiennent seuls en vie), `MailBrowserView`
   (574 l.), `AnthropicOAuthClient` (264 l.), `RAGChatView` (262 l.), `ManagerCRGenerator`
   (268 l.), `MickeyIntegration` (244 l.), `ReportThemeCSS` (184 l.),
   `MailSuggestionService` + `MailSuggestionReviewSheet`, `ManagerActionReviewSheet`,
   `CollaboratorEntity` / `StartOneToOneIntent` (App Intents), `ExternalServices`,
   `SessionPillHost`, `CollaboratorTopBarModel`. **Rien n'a été touché** : ce sont des
   fonctionnalités anciennes, pas des restes de la refonte, et certaines peuvent être des
   points d'entrée du système (App Intents) que l'analyse statique ne voit pas. À arbitrer
   dans un lot dédié — le chiffre est de l'ordre de **3 000 lignes**.

### Prochaine action

**Lot 19b**, le reste du périmètre du lot 19 (plan directeur l. 457), qui n'est **pas**
du code mort et n'a donc pas sa place ici : table complète des raccourcis §1.4
(`⌘K ⌘M ⌘⇧A ⌘⇧S ⌘⇧N ⌘⇧V ⌘⏎`) dans `MeetingCommands` et l'aide — `⌘⇧A` et `⌘⇧N` sont
aujourd'hui des boutons d'opacité nulle, jamais vérifiés à l'exécution ; réécriture de
`docs/architecture.md` (§5 modèles, §8 vues, §9 flux), de `docs/cleanup-report.md` et de la
section « écran de réunion » de `CLAUDE.md`, aucun des dix-sept lots ne les ayant touchés
(le plan directeur l. 527 le leur interdisait) ; `BackupService`, qui n'exporte toujours pas
huit des neuf tables ajoutées au lot 0B (seul `Board` l'est, depuis le lot 16) ;
`newTaskPomodoros` ci-dessus.
