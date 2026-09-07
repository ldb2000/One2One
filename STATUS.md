# État du projet

Dernière mise à jour : 2026-09-07 CEST

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
3. **`/action` dans le composeur de notes ne conserve pas encore `sourceRef` sur l'action
   créée** : il pose l'intention (`pendingActionDraft`, source comprise) et préremplit le
   composeur existant du rail, dont la création passe par `MeetingView.addTask()`. C'est le
   rail du lot 3 qui consommera l'intention complète. Le chemin du critère n° 2 — `＋ Action`
   sur un segment — crée l'action **immédiatement**, source comprise.
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
d'actions éditable en place, frise pleine largeur). Le lot 3 (rail d'actions 330 px) tourne en
parallèle ; il consommera `MeetingScreenModel.pendingActionDraft` posé ici.

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

## Chatbot — persistance de l'historique des conversations (2026-09-06)

Branche `feat/chatbot-history-persistence`, sur `master` (+0 commit avant cette session).
`ChatbotView` stockait ses messages dans un simple `@State [ChatMessage]` — perdu à chaque
fermeture de l'app, message de bienvenue réinitialisé. `MeetingChatView` reste **volontairement**
éphémère (décision de design antérieure), cette PR ne touche que `ChatbotView`.

- **`OneToOne/Models/ChatSession.swift`** (nouveau) : `@Model ChatSession` (id, createdAt,
  updatedAt, title dérivé du 1er message user tronqué à 60 car., relation cascade vers ses
  messages) et `@Model ChatMessageEntity` (id, role brut `"user"`/`"assistant"`, content,
  orderIndex, createdAt, session). `ChatMessage.Role` n'étant pas `String`-backed (hors
  périmètre — pas de modification de `ChatMessage.swift`), la conversion se fait à la main
  plutôt que via `.rawValue`. Mapper `ChatMessageEntity.from(_:orderIndex:)` /
  `.asChatMessage`.
- **`OneToOne/Models/SchemaVersions.swift`** : `SchemaV2` ajouté (modèles V1 + les deux
  nouveaux types), `CurrentSchema` pointe dessus. Ajout de table pur, pas de
  `MigrationStage` custom — lightweight migration automatique.
- **`OneToOne/Services/ChatSessionStore.swift`** (nouveau) : règle de rétention isolée de
  la vue pour rester testable — `sessionsToPrune(from:limit:)` (pure) + `enforceLimit(...)`
  (supprime + save + log). Limite 100 sessions, les plus anciennes par `updatedAt` sautent.
- **`ChatbotView`** : `@State messages: [ChatMessage]` devient une copie RAM rechargée à
  chaque changement de session (`loadSession`), plus une source de vérité. Nouveaux
  `@Query sessions`, `@State currentSession`/`sidebarSelection`/`hasInitializedSessions`
  (garde contre la recréation en boucle d'une session de bienvenue à chaque re-render) et
  `showSidebar`. `sendMessage()` route chaque `messages.append` via `appendMessage(_:to:)`
  qui persiste (insert `ChatMessageEntity` + `session.updatedAt` + titre au 1er message user
  + save). Sidebar ajoutée dans la vue (colonne 200px, collapsible via bouton
  `sidebar.left` dans l'en-tête) : liste triée par `updatedAt` desc, titre ou "Nouvelle
  conversation", date relative (`RelativeDateTimeFormatter` fr_FR), aperçu du dernier
  message, sélection surlignée (`Color.accentColor`), bouton `+`
  (`square.and.pencil` → `newConversation()`) et suppression par ligne (`trash` +
  `confirmationDialog`). `MeetingChatView` : **aucune modification**.
- **Écart avec la commande initiale** : la tâche demandait `func search()` — comme déjà
  noté en B-x-ui, la fonction réelle s'appelle `sendMessage()` ; c'est elle qui a été
  modifiée.
- **Non fait / limites v1** : pas de debounce sur les saves successifs (append+save reste
  peu fréquent : au plus 2 saves par échange, pas de boucle rapide observée) ; backup/
  restore avec sessions orphelines non testé spécifiquement (relation `session` sur
  `ChatMessageEntity` est `nullify` par défaut côté cascade parent→enfants, comportement
  accepté pour une v1 selon la consigne) ; pas de toggle "Historique" exposé dans
  `SettingsView` (les sessions sont toujours actives, comme demandé).
- **Tests** : `Tests/ChatSessionTests.swift` (nouveau, 4 tests) — roundtrip 3 messages via
  un nouveau `ModelContext`, cascade delete, mapper `ChatMessage`↔`ChatMessageEntity`,
  limite 100 sessions (105 créées → 5 plus anciennes supprimées).
- **Vérifié** : `swift build` propre (mêmes avertissements préexistants) ; `swift test`
  complet — **1 037 XCTest (1 ignoré, 0 échec) + 618 Swift Testing (95 suites, 0 échec)**,
  dont les 4 nouveaux tests `ChatSessionTests`. Un crash isolé (signal 11) est apparu sur
  une exécution parallèle de `swift test` sur un test `NoteFactoryTests` sans rapport avec
  cette PR ; non reproduit sur une exécution suivante (flaky, à surveiller si ça persiste).
- **Non vérifié à l'écran** : rendu réel de la sidebar dans l'app (ni
  `Scripts/bump-and-build.sh` ni capture d'écran effectués cette session).

## Chats — polish UX : tableaux markdown + indicateur de phase (B-x-ui) (2026-09-06)

Branche `feat/rag-chat-polish-ui`, sur `master` (+0 commit avant cette session). Les chats
(`ChatbotView`, `MeetingChatView`, branchés par B1/B2/B2-ui) affichaient déjà les réponses
via `MarkdownText` (headings, listes, code, quotes), mais sans support des tableaux GFM que
le LLM produit souvent ; et `isLoading: Bool` ne distinguait pas construction du prompt et
appel réseau, alors que ce dernier peut prendre plusieurs minutes sur Ollama sans aucun retour.

- **`OneToOne/Views/MarkdownText.swift`** : nouveau cas `Block.table(headers:rows:alignments:)`.
  Détection dans `blocks()` : ligne contenant `|` suivie d'une ligne de séparateurs valide
  (`isTableSeparatorLine`, avec ou sans pipes de bordure, `:` optionnels aux extrémités pour
  l'alignement) ; les lignes suivantes contenant `|` sont consommées comme rows jusqu'à la
  première ligne vide ou sans `|`. Rendu (`tableView`) : `ScrollView(.horizontal)`, header
  teinté `Color.accentColor.opacity(0.08)` en gras, séparateurs 1px `Color.gray.opacity(0.15)`
  entre les rows, zebra striping toutes les 2 rows (`opacity(0.04)`), alignement par colonne
  (`.frame(alignment:)` + `.multilineTextAlignment`), inline (`**`, `` ` ``, liens) délégué à
  `inlineText(_:)` existant. Backward-compatible : un texte avec des `|` mais sans ligne de
  séparateurs reste un paragraphe (testé). Deux accesseurs `ForTesting` (pattern déjà utilisé
  dans le repo, ex. `SlashDatePickerPresenter`) exposent le résultat du parsing sans dépendre
  du rendu SwiftUI : `blockKindsForTesting()` et `parsedTablesForTesting()`.
- **`OneToOne/Models/LoadingPhase.swift`** (nouveau) : enum partagé `idle`/`loadingContext`/
  `waitingLLM` (libellé + icône SF Symbols par cas). Le pré-fetch RAG n'est volontairement
  **pas** une phase séparée (trop rapide en usage normal pour justifier un indicateur dédié,
  cf. consigne de la tâche).
- **`ChatbotView`/`MeetingChatView`** : `@State private var isLoading: Bool` remplacé par
  `@State private var phase: LoadingPhase`, `isLoading` redevenu une propriété calculée
  (`phase != .idle`) pour ne pas toucher la logique existante des boutons/spinner. Une bulle
  inline (icône + libellé + `ProgressView` sobre, pas d'animation agressive) s'affiche dans la
  liste de messages pendant `loadingContext` (construction du prompt : contexte base, pré-fetch
  RAG, historique) puis `waitingLLM` (juste avant `AIClient.send`/`sendWithToolLoop`), avec
  auto-scroll vers cette bulle. `ChatbotView.statusBadge` affiche désormais le libellé de phase
  au lieu de "Analyse...". Les deux vues utilisaient déjà `MarkdownText` pour les bulles
  assistant (branché par B2-ui) — le support tableau en profite automatiquement, aucun
  changement supplémentaire nécessaire sur ce point.
- **Écart avec la commande initiale** : la tâche nommait la fonction d'envoi `search()` —
  inexistante dans les deux vues ; la méthode réelle est `sendMessage()`, modifiée à cet
  emplacement (même écart déjà noté pour B2-ui/`handleFreeQuestion`).
- **Tests** : `Tests/MarkdownTextTableTests.swift` (6 tests) — tableau 3 colonnes avec headers
  et 2 rows, alignements `:---`/`:---:`/`---:`, défaut sans `:`, paragraphes adjacents avant/
  après un tableau (ordre des blocs vérifié), faux positif (pipes sans ligne de séparateurs →
  reste un paragraphe), tableau sans pipes de bordure.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de concurrence dans
  `PyannoteDiarizer.swift`) ; `swift test` complet — **1 037 XCTest (1 ignoré, 0 échec) + 614
  Swift Testing (94 suites, 0 échec)**, dont les 6 nouveaux tests de tableaux.
- **Non vérifié à l'écran** : rendu réel des tableaux et de l'indicateur de phase dans l'app
  (ni `Scripts/bump-and-build.sh` ni capture d'écran effectués cette session).
- **Limites connues (hors périmètre volontaire)** : pas de streaming de la réponse (la
  structure `phase = .waitingLLM` s'y prête mais ce n'est pas implémenté ici) ; cellules avec
  pipes échappés non gérées (rare, écarté explicitement par la consigne) ; `RAGChatView` non
  touchée (rendu tableau/phase réservé aux 2 chats visés).
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran (poser une question dont la réponse contient un
tableau GFM, observer l'indicateur de phase pendant un appel Ollama long), puis revue/PR de
cette livraison.

## RAG — batch d'indexation globale au démarrage (D) (2026-09-05)

Branche `feat/rag-batch-reindex-d`, sur `master` (+0 commit avant cette
session). Jusqu'ici rien ne rattrapait les chunks jamais indexés ou devenus
obsolètes (changement de modèle d'embedding, bug d'indexation passé, restore
de backup). Cf. ADR `docs/adr/2026-09-05-rag-pipeline-inventaire.md`
(section D).

- **`Services/RAGIndexingSweep.swift`** (nouveau) : `RAGIndexingSweep.shared
  .runIfNeeded(context:)` fetch tous les `TranscriptChunk`, retient ceux dont
  `embeddingData` est vide, `embeddingModel` diffère du modèle courant
  (`RAGService.embeddingModel`), ou dont le modèle d'embedding a changé
  globalement depuis le dernier sweep complet (`UserDefaults
  .lastIndexedEmbeddingModel`, qui force alors même les chunks au modèle déjà
  à jour — vecteurs sinon incompatibles). Les chunks à traiter sont regroupés
  par parent (relation `attachment` / `mail` / `meeting`, testées dans cet
  ordre car un chunk d'attachment porte aussi un `meeting`) : un seul
  reindex par parent distinct, pas un par chunk.
  - Meeting/note → `RAGIndexer.reindex`/`reindexNote` (kind == .note).
  - Attachment → `MeetingAttachmentService.reindexAttachment` (réutilisé tel
    quel — pas dans le libellé de la tâche mais c'est la seule fonction
    existante qui régénère les chunks d'un attachment ; `RAGIndexer.reindex`
    ne les touche pas).
  - Mail → `ProjectMailStore.reindex(mail:)` (idem).
  - Chunk orphelin (aucune relation) : ignoré, loggé.
  - Pas de persistance de « qui a été traité » : idempotent par construction,
    un re-run sans changement ne relance rien (vérifié par test).
  - Handlers (`reindexMeetingHandler`/`reindexAttachmentHandler`
    /`reindexMailHandler`) et `userDefaults` sont des `static var`
    injectables — même pattern que `NoteIndexingCoordinator.reindexHandler`,
    pour tester sans MLX (`swift test` n'embarque pas `default.metallib`).
- **`Services/RAGService.swift`** : ajout de `enum RAGService { static var
  embeddingModel }`, wrapper de `EmbeddingService.model`.
- **`OneToOneApp.swift`** : `ContentView.onAppear` appelle
  `runRAGIndexingSweep()`, qui lance `Task { await RAGIndexingSweep.shared
  .runIfNeeded(context:) }` — non bloquant, la vue s'affiche immédiatement.
- **Tests** : `Tests/RAGIndexingSweepTests.swift` (5 tests) — chunk à jour
  → no-op ; chunk sans embedding → reindex ; chunk au mauvais modèle →
  reindex ; 3 chunks du même meeting → un seul appel ; deuxième passage sans
  changement → pas de second appel (idempotence).
- **Vérifié** : `swift build` propre ; `swift test` complet (608 tests), 0
  échec.
- **Limites connues (documentées, hors périmètre volontaire)** :
  - Pas de coordination avec `NoteIndexingCoordinator` : un debounce en cours
    et le sweep peuvent en théorie retraiter la même note en parallèle
    (accepté — double-work bénin, cf. tâche).
  - Le sweep peut être long sur un gros volume (embedding séquentiel par
    parent) ; s'il est interrompu (quit app), il reprend au prochain
    lancement sans état à nettoyer.
  - Pas de migration de métadonnées : un meeting dont le `kind` a changé
    (note ↔ projet) est ré-indexé avec le bon routage (`reindex` vs
    `reindexNote`), mais aucune donnée du meeting n'est modifiée.
- **Prochaine action** : rien d'identifié pour cette tâche ; PR prête.

## RAG — chat inline dans MeetingView (B2-ui MeetingView) (2026-09-05)

Branche `feat/rag-meeting-tool-calling`, sur `master` (+0 commit avant cette
session). Jusqu'ici, seuls les rapports (`AIReportService.generate`) et
l'assistant global (`ChatbotView`) parlaient au LLM ; aucune conversation
n'était possible pendant la réunion elle-même. Cf. ADR
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section MeetingView).

- **`Models/ChatMessage.swift`** (nouveau) : `ChatMessage` extrait de
  `ChatbotView.swift` (inchangé), pour être partagé avec `MeetingChatView`
  sans dupliquer le type.
- **`Views/Meeting/MeetingChatView.swift`** (nouveau) : widget de chat
  éphémère (messages en `@State`, RAM uniquement — disparaît à la fermeture
  de la réunion). À chaque question :
  - pré-fetch RAG historique (`RAGQuery.search`, scope selon `meeting.kind` —
    projet, collaborateur ou manager — avec `excludeMeetingPID` pour ne pas
    se nourrir de la réunion en cours) ;
  - historique de conversation sérialisé, limité aux 5 derniers tours ;
  - lit `settings.chatbotToolCallingEnabled` (même toggle global que
    `ChatbotView`, persisté dans `AppSettings`) pour choisir entre
    `AIClient.sendWithToolLoop` (B2, `ToolCatalog.all`) et `AIClient.send`
    (B1, pré-fetch seul). Le choix est extrait dans une fonction statique
    pure `shouldUseToolCalling(settingsList:)` pour rester testable sans
    environnement SwiftUI complet.
- **`Views/MeetingView.swift`** : nouvel onglet `.chat` (« Chat ») ajouté à
  `MeetingSection` — visible pour tous les kinds sauf `.note` (pas de sens
  pour un pot-pourri de notes libres). Structure des onglets existants
  inchangée, juste un cas de plus dans le `switch` et dans `allCases`.
- **Tests** : `Tests/MeetingChatViewTests.swift` — toggle actif → tool
  loop, inactif (ou aucun `AppSettings`) → chemin simple, et deux tests sur
  la construction du prompt (sections « Contexte historique » /
  « Conversation antérieure » présentes seulement si non vides).
- **Vérifié** : `swift build` propre ; `swift test` complet, 0 échec.
- **Hors périmètre** (volontaire) : pas de mock réseau pour le tool loop
  réel, pas de persistance de la conversation, `AIReportService` et
  `fetchHistoricalContext` (privée à `MeetingView`) non modifiés — le pattern
  RAG est dupliqué en privé dans `MeetingChatView` plutôt que partagé, faute
  d'API publique exploitable sans élargir le périmètre.

**Prochaine action** : si l'onglet Chat s'avère utile en usage réel, évaluer
l'exposition d'un historique persistant (actuellement volontairement
éphémère) et le partage effectif de `fetchHistoricalContext` entre
`MeetingView` et `MeetingChatView` (actuellement dupliqué).

## RAG — persistance du toggle tool calling (B2-ui v2) (2026-09-05)

Branche `feat/rag-tool-calling-toggle-persist`, sur `master` (+0 commit avant
cette session). Corrige B2-ui (PR #10) : le toggle « Recherche active » de
`ChatbotView` était un `@State private var useToolCalling: Bool = false`, donc
revenait à `off` à chaque réouverture de la vue.

- Nouveau champ `AppSettings.chatbotToolCallingEnabled: Bool = false`, à côté
  des autres toggles IA (`useAIForWeeklyExport`, etc.) — pas de migration
  SwiftData nécessaire (nouveau champ optionnel-like avec défaut, pas de bump
  de `SchemaVersions.swift`).
- `ChatbotView` : `useToolCalling` devient une propriété calculée qui lit
  `settings.chatbotToolCallingEnabled` ; le `Toggle` écrit désormais via un
  `Binding` explicite (`settings.chatbotToolCallingEnabled = $0; try?
  context.save()`) au lieu de `$useToolCalling`.
- **Corrigé au passage** : `ChatbotView.settings` faisait
  `settingsList.canonicalSettings ?? AppSettings()` — si aucun `AppSettings`
  n'existait encore en base (l'app ne force sa création qu'à l'ouverture de
  `SettingsView`), l'instance de repli n'était jamais insérée dans le
  `modelContext` et toute écriture (dont ce nouveau toggle) était perdue en
  silence. `settings` insère désormais et sauvegarde un `AppSettings` de
  secours si besoin, comme `SettingsView.settings` le fait déjà.
- **Tests** : `Tests/ChatbotViewTests.swift` —
  `toolCallingTogglePersistsInAppSettings` (round-trip SwiftData : un
  `AppSettings` avec `chatbotToolCallingEnabled = true` sauvegardé, puis relu
  depuis un second `ModelContext` sur le même conteneur, reste `true`).
- **Vérifié** : `swift build` propre ; `swift test` complet — 604 tests
  Swift Testing (92 suites), 0 échec.
- **Hors périmètre** (volontaire) : le toggle n'est pas exposé dans
  `SettingsView` — il reste local à `ChatbotView` mais persisté via
  `AppSettings`. Une future PR pourra l'y exposer pour cohérence avec les
  autres toggles IA.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : décider si le toggle doit apparaître dans
`SettingsView` (cohérence avec les autres réglages IA), sinon poursuivre sur
D (batch d'indexation globale) selon priorisation de l'ADR RAG.

## RAG — hybrid search BM25 + cosine via RRF (B3) (2026-09-05)

Branche `feat/rag-hybrid-search-b3`, sur `master` (C déjà fusionné, PR #11). ADR :
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section « B3 »).

- **Livré** : nouveau `Services/BM25Index.swift` — index lexical BM25 in-memory
  (`k1=1.5`, `b=0.75` par défaut), tokenisation minuscule + split Unicode
  alphanumérique (préserve les accents), ~80 stop-words français/anglais.
  IDF Robertson-Sparck Jones variante `+1` (jamais négatif). Reconstruit à
  chaque requête (pas de persistance), acceptable tant que le corpus reste
  modéré — cf. note déjà présente sur `RAGQuery.filtered`.
- `RAGQuery.searchHybrid(query:topK:scope:context:rrfK:cosineWeight:bm25Weight:)`
  (async, embedde la requête puis délègue) et sa variante testable
  `searchHybrid(queryVec:queryText:...)` (synchrone, vecteur pré-calculé —
  évite l'appel MLX réel dans les tests, cf. CLAUDE.md). Algorithme : rang
  cosine (chunks avec embedding non vide) + rang BM25 (chunks avec au moins
  un terme en commun), fusionnés par Reciprocal Rank Fusion
  (`poids * 1/(rrfK + rang)`, `rrfK=60` non paramétrable). Un chunk sans
  embedding ne participe qu'au rang BM25 ; un chunk sans texte (score BM25
  nul) ne participe qu'au rang cosine. `Result.similarity` porte le score RRF
  fusionné pour ce chemin (pas une similarité cosine brute). `RAGQuery.search`
  (cosine seul) reste inchangée, non réimplémentée en wrapper — les deux
  coexistent tel qu'autorisé par la consigne.
- `ToolRouter` : `search_knowledge` accepte un paramètre optionnel
  `use_hybrid` (booléen, défaut `false`) — absent ou `false` garde le
  comportement B2 (cosine seul, aucune régression) ; `true` route vers
  `RAGQuery.searchHybrid`. `SearchKnowledgeRequest` et le parsing exposent le
  champ ; `ToolSpec` documente le paramètre au LLM (FR/EN).
- **Tests** : `Tests/BM25IndexTests.swift` (tokenisation, filtrage stop-words,
  IDF favorise les termes rares, déterminisme, requête uniquement stop-words)
  et `Tests/RAGHybridSearchTests.swift` (un chunk pertinent lexicalement +
  sémantiquement remonte devant le meilleur score cosine seul ; un nom propre
  inventé sans embedding n'apparaît jamais en cosine seul mais remonte en
  hybride via BM25 ; une paraphrase sans recouvrement lexical retombe
  exactement sur le classement cosine — BM25 ne contribue rien). Plus
  parsing `use_hybrid` et forme JSON du paramètre côté `ToolSpec`.
- **Mesuré** : BM25 sur 3 500 chunks synthétiques (texte aléatoire ~40 mots +
  suffixe identifiant) pour une requête de 5 mots : **~2.6 ms** (build debug,
  banc temporaire non committé), très en dessous du seuil de 100 ms. Aucun
  log d'alerte déclenché en usage normal.
- **Vérifié** : `swift build` propre ; `swift test` complet — 1 032 XCTest
  (1 ignoré, 0 échec) + 603 Swift Testing (92 suites, 0 échec), dont 13
  nouveaux tests B3. Pas de régression sur B1/B2/C (`ChatbotViewTests`,
  `AIEndpointToolTests`, `RAGNoteIndexingTests`).
- **Limites actées** : pas de branchement UX (`RAGChatView`/`ChatbotView`
  n'exposent pas encore le choix hybride à l'utilisateur — hors périmètre de
  cette PR) ; `rrfK=60` figé en dur, non paramétrable via UI ; le score
  `Result.similarity` change de sens selon le chemin emprunté (cosine brute
  vs RRF fusionné) — à documenter si un appelant affiche cette valeur telle
  quelle.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : brancher `use_hybrid`/le choix hybride dans
`ChatbotView`/`RAGChatView` (PR séparée), ou enchaîner sur D (batch
d'indexation globale) selon priorisation de l'ADR.

## RAG — auto-indexation des notes live (C) (2026-09-05)

Branche `feat/rag-note-autoindex-c`, 3 commits sur `master`. ADR :
`docs/adr/2026-09-05-rag-pipeline-inventaire.md` (section « C »).

- **Livré** : `RAGIndexer.reindex` lisait uniquement `mergedTranscript`/`rawTranscript` —
  toujours vides pour une note (`kind == .note`, ni audio ni transcription), donc le pipeline
  existant n'indexait jamais son contenu. Bascule la source sur `meeting.liveNotes` pour ce
  cas précis. Ajoute `RAGIndexer.reindexNote(meeting:context:)`, gate no-op silencieux hors
  notes, et `Task.checkCancellation()` à deux points de coupure du reindex (avant le clear des
  chunks, après l'embedding). Nouveau `Services/NoteIndexingCoordinator.swift` (singleton
  `@MainActor`) : débounce 2 s par note (`persistentModelID`), annule le débounce en cours à
  chaque frappe, et annule un reindex déjà en vol avant d'en démarrer un nouveau. Branché dans
  `MeetingView` aux deux endroits où `meeting.liveNotes` est effectivement modifié : le binding
  de l'éditeur (`.liveNotes` section) et `adoptPendingLiveNotes()` (reprise du texte en attente
  au démontage de l'écran).
- **Point d'injection ajouté pour les tests** : `NoteIndexingCoordinator.reindexHandler` (var,
  défaut `RAGIndexer.reindexNote`) et `debounceDelay` (var, défaut 2 s), substitués dans les
  tests par un double contrôlable — `swift test` n'embarque pas `default.metallib` (cf.
  CLAUDE.md), appeler le pipeline MLX réel y crasherait au premier accès GPU.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de
  `PyannoteDiarizer.swift`) ; `swift test` complet — 1 032 tests, 1 ignoré, 0 échec, dont 2
  nouveaux (`Tests/RAGNoteIndexingTests.swift`) qui couvrent le débounce (3 appels rapprochés
  → 1 seul reindex) et l'annulation d'un reindex en vol par une nouvelle édition.
- **Limite actée (hors scope, cf. ADR tâche D)** : si l'app se ferme pendant un débounce en
  cours, le reindex programmé est perdu — pas de rattrapage au démarrage suivant.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran (éditer une note, vérifier en base l'apparition des
`TranscriptChunk` après ~2 s d'inactivité) ; ou enchaîner sur B3 (hybrid search) / D (batch
d'indexation globale) selon priorisation de l'ADR.

## RAG — tool calling branché dans ChatbotView (B2-ui) (2026-09-05)

Branche `feat/rag-tool-calling-b2-ui`, 2 commits sur `master` (B2 déjà fusionné, PR #9).
Fichiers touchés : `OneToOne/Views/ChatbotView.swift`, `Tests/ChatbotViewTests.swift` uniquement.

- **Livré** : bascule `useToolCalling` (`@State`, non persistée) dans la zone de saisie —
  « Recherche active ». Par défaut B1 (pré-fetch RAG, 4 chunks max) reste utilisé ; activée,
  `sendMessage` appelle `AIClient.sendWithToolLoop` (`ToolCatalog.all`, `maxTurns: 5`,
  `onProgress: nil`) à la place de `AIClient.send`. La construction du prompt est extraite
  dans `makePrompt(question:databaseContext:ragBlock:history:)`, partagée par les deux
  chemins ; en mode tool calling `ragBlock` est vide, donc le bloc « Extraits pertinents »
  disparaît du prompt mais le contexte base et l'historique de conversation restent identiques.
  Le contrôle de joignabilité Ollama reste commun aux deux modes (il précède le branchement).
- **Écart avec la commande initiale** : le fichier visé nommait `handleFreeQuestion` —
  inexistant ; la méthode réelle est `sendMessage`, modifiée à cet emplacement.
- **Vérifié** : `swift build` propre (seul l'avertissement préexistant de
  `PyannoteDiarizer.swift`) ; `swift test` complet — **1 030 XCTest (1 ignoré, 0 échec) +
  590 Swift Testing (88 suites, 0 échec)**, dont 1 nouveau test
  (`toolCallingOmitsRAGBlockFromPrompt`) qui vérifie sur `makePrompt` directement que le
  bloc RAG disparaît sans toucher au reste du prompt — pas de mock d'`AIClient` (hors
  périmètre de cette PR, `AIClient.swift` figé).
- **Non vérifié à l'écran** : le toggle et l'appel réel à `sendWithToolLoop` contre un
  vrai LM Studio/Ollama/OpenRouter.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : recette à l'écran du toggle avec un endpoint compatible OpenAI réel,
puis PR ; ou enchaîner sur B3 (hybrid search BM25 + cosine) / C (indexation live) selon
priorisation de l'ADR.

## RAG — tool calling `search_knowledge` (B2) (2026-09-05)

Branche `feat/rag-tool-calling-b2`, 4 commits sur `master`. Suite de B1 (pre-fetch RAG,
`feat/rag-prefetch-b1`, déjà fusionnée). ADR : `docs/adr/2026-09-05-rag-pipeline-inventaire.md`
(section « B2 — Tool calling »).

- **Livré** : `OpenAICompatibleClient` décode et accepte enfin `tool_calls` (anti-pattern
  décrit par l'ADR — le transport refusait toute réponse en contenant) ; `stop`/`tool_calls`/
  `function_call` sont désormais des fins de tour normales, seul `content_filter` reste un
  refus. Nouvelle API `sendWithTools(messages:configuration:tools:)` (non-streamée) et
  `requestBody(messages:tools:)`. Nouveau `Services/AI/ToolRouter.swift` : `ToolSpec`/
  `ToolCatalog` (un seul outil pour cette PR, `search_knowledge`, description FR+EN) et
  `ToolRouter.execute` qui route vers `RAGQuery.search` (scope `meeting`/`attachment`/`mail`,
  `top_k` clampé `[1, 20]`) et retourne toujours un JSON exploitable — jamais une erreur Swift,
  un outil inconnu ou des arguments invalides deviennent `{"error": ...}`. `AIClient.
  sendWithToolLoop` orchestre la boucle (appel → tool_calls → exécution locale → réappel),
  plafonnée à 5 tours par défaut ; réservée aux endpoints compatibles OpenAI (LM Studio,
  OpenRouter, Ollama) — Anthropic et Gemini OAuth sont refusés immédiatement (`AIToolLoopError`),
  avant tout réseau.
- **Écart avec la commande initiale** : le fichier visé était `Services/AI/AIClient.swift` —
  inexistant ; l'`AIClient` réel vit à `Services/AIClient.swift` (fichier historique, pas dans
  `Services/AI/`), modifié à cet emplacement.
- **Limite actée** : pendant les tours d'outils, tout est non-streamé (l'API text/tool_calls
  d'un serveur compatible OpenAI ne l'est pas proprement dans ce cas) — `onProgress` n'est
  appelé qu'une fois, avec le texte final. Le niveau de raisonnement du profil (`AIReasoningLevel`)
  n'est pas propagé aux tours d'outils (hors périmètre de cette PR, seuls modèle et limite de
  sortie le sont).
- **Non branché** : `ChatbotView` n'utilise pas encore `sendWithToolLoop` — seules les briques
  bas niveau sont livrées ici ; le branchement UI est un chantier séparé (B2-ui).
- **Vérifié** : `swift build` propre ; `swift test` complet — **1 030 XCTest (1 ignoré, 0
  échec) + 589 Swift Testing (88 suites, 0 échec)**, dont 17 nouveaux tests
  (`Tests/AIEndpointToolTests.swift`) couvrant l'encodage `ToolSpec`, le parsing/dispatch/
  sérialisation de `ToolRouter` (sans jamais appeler le vrai pipeline d'embedding) et
  l'orchestration de `AIClient.runToolLoop` (réponse directe, tool_call puis texte, outil
  inconnu, plafond de tours, `onProgress` unique). Un test existant de `AIEndpointTests.swift`
  a été corrigé : il simulait un `finish_reason: "tool_calls"` sans tableau `tool_calls` réel,
  devenu `emptyResponse` (et non plus `refused`) depuis que `tool_calls` n'est plus
  systématiquement un refus.
- **Non poussé, pas de merge** (consigne de la tâche).

**Prochaine action** : proposer B2-ui (brancher `sendWithToolLoop` dans `ChatbotView`), ou
enchaîner sur B3 (hybrid search BM25 + cosine) / C (indexation live des notes) selon
priorisation de l'ADR.

## Niveau de raisonnement par profil et limite de sortie relevée (2026-09-05)

Investigation du rapport LM Studio « toujours en raisonnement après 645 s » avec
`qwen3.8-27b` (mlx-community/Qwen3.8-27B-8bit), puis réglage ajouté après discussion.
ADR : [`2026-09-05-raisonnement-configurable.md`](docs/adr/2026-09-05-raisonnement-configurable.md).

- **Cause confirmée** : le `chat_template.jinja` du modèle injecte « Reasoning effort is
  set to xhigh » par défaut (prompt rendu vu dans `lms log stream`). LM Studio génère à
  8,4 tokens/s : un rapport long raisonne des milliers de tokens avant d’écrire, et la
  limite de 8 192 tokens couvrait réflexion et rapport ensemble.
- **LM Studio 0.4.23** ignore `reasoning_effort`, `reasoning: {effort}` et
  `chat_template_kwargs` sur `/v1/chat/completions` (prompt rendu identique) ;
  `/api/v1/chat` refuse `reasoning` pour ce modèle (HTTP 400) ; `/v1/responses` ignore
  `reasoning.effort` ; `/no_think` aggrave (511 tokens, tronqué). Leviers mesurés : consigne
  système « low » du template → 679/514 → 167/167 tokens de raisonnement ; préremplissage
  assistant `\n</think>\n\n` → 0 token, aussi en SSE.
- **Ollama 0.33.2** (`qwen3.8:27b-mlx`, nvfp4) honore `reasoning_effort` : xhigh/high/max
  injectent l’instruction xhigh, medium aucune, low la sienne, none désactive. Débit ≈ 30
  tokens/s. `gemma4:26b-mlx` plante dans le runner MLX d’Ollama (HTTP 500), hors sujet.
- **Livré** : `AIReasoningLevel` (défaut, désactivé, faible, moyen, élevé, maximal) dans
  `AIEndpointProfile.reasoning`. Ollama → `reasoning_effort`, OpenRouter → `reasoning.effort`
  (documenté, non testé : payant), LM Studio → consigne système reprise du template Qwen
  (`high` aligné sur `xhigh` comme Ollama ; `medium` rédigé, non mesuré) et désactivation
  par préremplissage, proposée seulement si l’identifiant contient « qwen ». Défaut =
  requête strictement inchangée. Sélecteur « Raisonnement » sous la limite de sortie.
- **Limite de sortie** : défaut 24 576 (3 × 8 192). Un profil sans clé `reasoning` et à
  exactement 8 192 est relevé une fois au décodage, puis réécrit par la migration ; toute
  autre valeur est conservée. Un niveau inconnu retombe sur le défaut sans invalider le profil.
- **Vérifié** : tests unitaires (décodage ancien JSON, migration idempotente, corps par
  fournisseur/niveau, capacités) ; test réel facultatif `liveReasoning`
  (`ONETOONE_AI_LIVE_REASONING=1`) : Ollama xhigh raisonne / off ne raisonne pas, LM Studio
  défaut raisonne / off ne raisonne pas, texte « OK » partout. Suite complète : **1 030 XCTest (1 ignoré), 570 Swift Testing en
  82 suites, 0 échec**. Aucun fichier LM Studio/Ollama modifié.
- **Serveur LM Studio** : authentification désactivée par l’utilisateur pour les tests, à
  réactiver (Developer > Server Settings). Le serveur et le modèle ont été relancés via
  `lms server start` / `lms load` pour le test réel.

- **Application de recette** : `.build/ai-endpoints-preview-v4/OneToOne.app` (build debug,
  ressources et bibliothèque Metal embarquées, signature ad hoc vérifiée, non installée
  ni lancée). Quitter l’ancienne instance avant ouverture.

**Prochaine action** : ouvrir l’app v4, régler le niveau sur le profil (Ollama ou
LM Studio), vérifier « Tester la connexion » puis un rapport complet ; réactiver
l’authentification LM Studio. Changements locaux non commités.

## Suivi de génération des rapports (2026-09-05)

Après un essai LM Studio interrompu à environ 6 min 46 : les journaux serveur
montraient une entrée de 6 457 tokens traitée en 17 secondes, puis un flux actif
jusqu’à l’annulation. Une longue phase de raisonnement est plausible, pas prouvée
par le journal de cet essai ; le petit test de connexion avait bien retourné du
`reasoning_content` séparément de `content`.

- Suivi distinct préparation, attente, raisonnement, rédaction, extraction.
  Les deltas `reasoning` / `reasoning_content` sont comptés, jamais affichés ni
  conservés dans le rapport. Le suivi seul active aussi le streaming de l’extraction.
- Après deux minutes sur la même phase : avertissement visible dans la réunion
  et la file des tâches, distinguant activité récente et silence de plus d’une minute.
  Pas d’arrêt automatique ni de modification du modèle ou de son raisonnement.
- Le markdown terminé est sauvegardé et affiché avant la seconde requête.
  L’annulation de l’extraction conserve ce texte. Une seule révision est créée ;
  les faits arrivent ensuite sans réécrire le texte éventuellement édité entre-temps.
- Les deux boutons de génération utilisent le même parcours avec propagation
  des erreurs et de l’annulation. Aucun rapport réel n’est relancé automatiquement.
- Validation : **1 030 XCTest (1 ignoré), 563 Swift Testing en 82 suites, aucun
  échec**. Tests ajoutés pour les deux champs de raisonnement, le SSE avec callback
  d’activité seul, les alertes temporisées, l’ordre publication/extraction, la
  conservation après annulation et l’échec de sauvegarde.
- Application de recette : `.build/ai-endpoints-preview-v3/OneToOne.app`, signée
  ad hoc et vérifiée. Quitter l’ancienne instance avant ouverture. Essai de rapport
  complet avec LM Studio encore à refaire ; la vitesse du modèle n’est pas modifiée.

## Correction des catalogues et retrait de Direct (2026-09-05)

Suite à la recette utilisateur du premier écran :

- Recherche, modèle, URL et jeton utilisent désormais `EditableTextField` AppKit
  (`NSSecureTextField` pour le jeton). Le coordinateur renouvelle son binding lors
  du changement de profil ; liste de modèles à hauteur fixe et textes explicatifs
  repliables sur plusieurs lignes.
- Catalogue chargé automatiquement au choix du fournisseur. OpenRouter se consulte
  sans clé ; la génération exige toujours la clé. Le message d’erreur de catalogue
  reste visible à côté de la liste. Les catalogues ont un délai de 20 secondes.
- **Constat réel LM Studio** : le serveur écoute sur 1234 et répond HTTP 401 sans
  jeton. L’écran invite désormais à le renseigner. Aucun secret n’a été lu ni modifié
  dans le serveur pendant cette vérification.
- **Ollama** devient un endpoint principal avec catalogue et chat compatibles OpenAI,
  au même niveau que LM Studio/OpenRouter.
- **Direct retiré** : suppression de `DirectLLMClient.swift`, du lien direct MLXLLM,
  de Gemma4Swift et de son profiler transitif dans les dépendances. Les anciennes
  configurations Direct migrent vers LM Studio sans inventer de nom de modèle ;
  un profil LM Studio précédemment enregistré est préservé. Les champs historiques
  restent lisibles. Les caches partagés de poids ne sont pas supprimés. MLXLLM reste
  transitif via la transcription ; les composants audio/embeddings sont conservés.
- **Validation** : catalogue réel OpenRouter décodé par le client Swift sans clé,
  **431 modèles**. Tests natifs des champs et du binding lors du changement de profil,
  tests Ollama et migration Direct ; suite complète : **1 030 XCTest, 1 ignoré,
  0 échec ; 557 Swift Testing en 81 suites, 0 échec**.
- Nouvelle app de recette : `.build/ai-endpoints-preview-v2/OneToOne.app`.
  La première app de recette est conservée ; les instances ouvertes ne sont pas arrêtées.

ADR complémentaire : [`2026-09-05-catalogues-ia-retrait-direct.md`](docs/adr/2026-09-05-catalogues-ia-retrait-direct.md).
**Prochaine action** : ouvrir la nouvelle app après fermeture de l’ancienne, renseigner
le jeton LM Studio puis actualiser ; vérifier le choix et la génération avec les modèles
souhaités. Changements locaux non commités.

## Endpoints IA — LM Studio / OpenRouter (2026-09-05)

Branche `refactor/ai-endpoints-lmstudio-openrouter`, créée depuis `master` à `a388fb8`.
Plan et audit du code/documentations officielles dans
[`docs/superpowers/plans/2026-09-05-architecture-ia-endpoints.md`](docs/superpowers/plans/2026-09-05-architecture-ia-endpoints.md).

- **Livré après accord utilisateur** : lots 1 à 4. Profils séparés par fournisseur,
  nouvel écran `AISettingsView` (choix endpoint puis modèle, catalogue avec recherche,
  identifiant manuel, test sur brouillon, enregistrement explicite), transport HTTP
  commun pour LM Studio et OpenRouter avec annulation et erreurs SSE. `AIClient`
  fige le profil avant l’inférence ; les services métier existants passent par cette façade.
- **Migration** : champs SwiftData additifs, fournisseur historique préservé, clés au
  Trousseau avec vérification avant effacement du champ historique. Les nouveaux
  backups omettent clés et références ; les anciens exports restent lisibles. Le
  classement distant des mails doit être réactivé après restauration.
- **Mails et Teams** : classement via le client commun, option explicite pour les
  endpoints hors boucle locale, repli heuristique ; disponibilité des rapports Teams
  vérifiée avec le profil et sa clé, et non l’ancien champ `cloudToken`.
- **Vérifié** : `swift build`, puis `swift test` complet : **1 030 XCTest, 1 ignoré,
  0 échec ; 550 Swift Testing en 80 suites, 0 échec**. Nouveaux tests de migration,
  Trousseau simulé, réouverture disque, sauvegardes, HTTP, SSE multiligne/UTF-8,
  erreurs après HTTP 200, troncature et annulation. Le test HTTP a révélé puis validé
  le correctif d’`AsyncBytes.lines`, qui omet les lignes vides SSE. Avertissement
  préexistant de concurrence dans `PyannoteDiarizer.swift`.
- **Application préparée** : `.build/ai-endpoints-preview/OneToOne.app`, ressources et
  bibliothèque Metal embarquées, signature ad hoc vérifiée. Ni installée ni lancée.
- **Recette restante** : interface native, Trousseau réel et génération avec les modèles
  choisis sur LM Studio/OpenRouter. Aucun serveur ne répondait sur le port local 1234
  lors de la vérification ; aucun appel OpenRouter payant effectué.
- **Différé** : embeddings sur API et réindexation, retrait des anciens fournisseurs,
  transcription distante et runtime d’agent. Audio, OCR, embeddings locaux et Claude CLI
  conservent leur fonctionnement. ADR :
  [`2026-09-05-endpoints-ia-configurables.md`](docs/adr/2026-09-05-endpoints-ia-configurables.md).

**Prochaine action** : recette dans l’application avec un modèle LM Studio et un modèle
OpenRouter, puis revue/PR de cette première livraison. Changements locaux non commités.
Les validations manuelles de capture de slides ci-dessous restent à effectuer.

## Capture automatique de slides (2026-09-02)

Branche `feat/capture-auto-slides`, code de la fonctionnalité à **`3574054`**, puis
correctifs de la revue finale (ce commit), basée sur `master` à `553458f`.
Huit tâches livrées (Task 8 = cette section) plus la vague de correctifs. Spec :
`docs/superpowers/specs/2026-09-02-capture-auto-slides-design.md`. ADR :
`docs/adr/2026-09-02-capture-slides-polling-empreinte.md`.

- **Livré** : nouveau module pur `OneToOne/Services/SlideCapture/` (`SlideFingerprint`,
  `NormalizedRect`, `SlideCaptureSettings` à deux seuils, `SlideDetector`,
  `FrameSource`/`ShareableWindow`/`SlideCaptureError`, `WindowCatalog`, `WindowFrameSource`,
  `ScreenRecordingSettingsLink`) ; `ScreenCaptureService` réécrit (états
  idle/running/paused/stopped, arrêter conserve la session, reprendre, terminer clôt, jeton
  de session revérifié après chaque `await`, tâche OCR gardée par un contrôle de vivacité,
  ajout à un lot précédent avec réamorçage du détecteur, noms de fichiers à 4 chiffres) ;
  `ScreenCaptureConfigView` réécrit en trois faces plus la face de refus d'autorisation ;
  `CropSelectionView` nouveau ; `PerceptualHasher.swift` et `RectSelectorOverlay.swift`
  supprimés ; `AppSettings.slideCaptureSensitivityRaw` ajouté (migration légère) ;
  `Info.plist` reçoit `NSScreenCaptureUsageDescription` ; les barres et `MeetingView`
  affichent l'état réel avec Reprendre/Terminer, et `onDisappear` clôt une session ouverte
  après les gardes de suppression.
- **Correctifs de la revue finale** : `finish()` ne jette plus le texte d'un OCR qui se
  termine pendant l'attente (la tâche OCR écrit dans **son** slide et **son** attachment,
  gardée par la vivacité des modèles et non par le jeton) ; après chaque `await`, tick et
  écriture exigent jeton **et** état actif (`sessionIsLive`) — un tick relâché après `stop()`
  ne publie plus `.paused` par-dessus `.stopped` ni n'écrit de slide ; `resume()` et
  `updateSource()` exigent un jeton non nul et `finish()` annule toute boucle relancée
  pendant son attente (plus de boucle fantôme qui bloquait la session suivante) ;
  `abandon()` ajouté et appelé par `onDisappear` sur le chemin « réunion supprimée » (rien
  sauvegardé, rien réindexé) ; `WindowCatalog` passe à `onScreenWindowsOnly: false` et
  filtre calque `0` + hors-écran non-réunion, donc une fenêtre Teams en plein écran sur un
  autre Space est enfin proposée et reprise ; « Commencer » est désactivé sur
  `selectedWindow == nil` et un rafraîchissement oublie une sélection disparue ; la
  numérotation d'un lot repris part du **maximum** des index et non de leur nombre ;
  `SessionError.noOpenSession` (inutilisée) remplacée par
  `attachmentBelongsToAnotherMeeting`, levée par `beginSession(appendTo:)`.
- **Tests** : `SlideFingerprintTests` (8), `NormalizedRectTests` (12), `SlideDetectorTests`
  (10), `SlideCaptureErrorTests` (4), `WindowCatalogTests` (3), `ScreenRecordingSettingsLinkTests`
  (3), `ScreenCaptureServiceTests` (23, dont 7 écrits en rouge pour la revue finale : OCR
  conservé à la clôture, tick en vol pendant `stop()` — publication et écriture —, `resume()`
  refusé pendant la clôture, `abandon()`, `appendTo` d'une autre réunion, numérotation sur le
  maximum des index). Preuves de mutation faites sur l'axe Y, la dérive lente et le jeton de
  tick (Test A). Suite complète après les correctifs : **XCTest 1030 exécutés, 1 ignoré, 0
  échec ; Swift Testing 529 tests en 77 suites, 0 échec** ; `swift build` propre à part
  l'avertissement préexistant dans `PyannoteDiarizer.swift`.
- **Points ouverts mineurs** (revue différée à la revue finale) : `fromDrag` avec une vue de
  taille nulle renvoie `.full` au lieu de `current` ; balayage anti-doublon linéaire ;
  `onScreenWindowsOnly: false` dans `WindowFrameSource` **et** désormais dans le catalogue
  (délibéré : capturer une fenêtre occultée est la prémisse de la fonctionnalité) ; la tâche
  d'instantané n'est pas attendue par `finish()` ; écrire la sensibilité est un no-op si
  aucune ligne `AppSettings` n'existe
  encore ; `MeetingView` réinitialise toujours `lastError` directement pour fermer le
  bandeau (accepté).
- **Build** : `Scripts/bump-and-build.sh dev` exécuté pour la Task 8 ; `swift build` propre
  après les correctifs de la revue finale.

### Validation manuelle — à faire par l'utilisateur

Aucune validation manuelle n'a été effectuée. À dérouler sur une vraie présentation (Teams,
Zoom ou Meet, ou un Keynote/PowerPoint en plein écran dans une autre fenêtre) :

- [ ] Ouvrir une réunion → « Capture » → autorisation demandée la première fois ; refuser
      une fois pour voir l'écran de refus et le bouton « Ouvrir les Réglages » ; accorder ;
      relancer.
- [ ] Choisir la fenêtre, tracer une zone : vérifier que **le haut et le bas** du slide
      écrit correspondent au tracé (ouvrir le PNG dans
      `~/Library/Application Support/OneToOne/recordings/<uuid>/slides/`).
- [ ] Faire défiler trois slides : trois fichiers, pas plus. Revenir sur le premier : rien
      de plus.
- [ ] Déplacer puis redimensionner la fenêtre source : la zone suit.
- [ ] Fermer la fenêtre source : pastille orange « En pause » ; la rouvrir : bleu, reprise
      seule.
- [ ] Arrêter → « Arrêtée · N » ; Reprendre → numérotation continue ; Terminer → OCR, texte
      agrégé visible dans la galerie, lot clos.
- [ ] Rouvrir « Capture » : « Ajouter au lot précédent » proposé ; un slide déjà présent
      n'est pas réécrit ; un nouveau l'est avec l'index suivant.
- [ ] Fenêtre source **entièrement** recouverte par une autre : la capture continue-t-elle ?
      Noter le résultat (non couvert par la sonde du prototype).
- [ ] Fenêtre Teams en plein écran (autre Space) : proposée dans la liste, capture et reprise
      fonctionnent.

**Prochaine action** : validation manuelle des neuf points ci-dessus, puis push et PR.
Chantier séparé en attente : auto-start avec l'auto-record Teams.

## Le dépôt n'a plus qu'une branche (2026-09-02, fin de session)

`master` est à **`ee8a4b3`**, écart 0 avec `origin/master`. **18 branches locales et 11
distantes ont été supprimées** : il ne reste plus que `master`, local et distant, et plus
aucun worktree hors la copie principale. Toutes ont été vérifiées entièrement contenues dans
`master` avant suppression, **sauf quatre**, supprimées en connaissance de cause — trois
dépassées par du code plus récent (voir plus bas) et `worktree-agenda-project-picker-search`,
détruite sur décision explicite avec un apport réel dedans, décrit ci-dessous pour qu'il
puisse être réécrit.

- **Dernière fusion de code : `fix/code-review-data-safety-perf`** (`ee8a4b3`). ⚠️ **La
  prémisse de ce fichier était fausse** : il présentait cette branche comme la seule copie de
  huit correctifs jamais repris. En réalité `master` avait déjà implémenté les mêmes
  correctifs, **en mieux**. Les quatre conflits ont donc été résolus **en gardant `master`** :
  `TranscriptEditService` (master sauvegarde le contexte partagé *avant* toute coupe audio et
  documente son rollback), `AudioFileEditor` (master factorise la garde d'allocation dans
  `tamponDeLecture(format:capacite:operation:)`), `AIClient` (la branche réintroduisait
  `callClaudeCLI`, supprimé depuis) et `MeetingView` (la branche portait l'ancienne API
  `onStartRecording` / `onRetranscribe`, refactorisée depuis en `makeMenuActions()` — la
  prendre aurait cassé la compilation).
- **Six correctifs sont quand même entrés**, réellement absents de `master` et sans
  régression : déduplication des `TranscriptChunk` au démarrage, lecture texte avec repli
  CP1252 / ISO Latin-1, mention explicite de troncature dans le bloc « documents joints » du
  rapport, `ImageCache` (`CachedNSImage.swift`) pour les photos de collaborateurs, recherche
  **debouncée** dans la barre latérale, et construction du contexte du chatbot sortie du
  chemin synchrone.
- **Vérifié sur la fusion** : `swift test`, build à froid — **1030 XCTest (1 ignoré, 0 échec)
  + 466 tests Swift Testing en 70 suites**, code de sortie 0, **aucune erreur de
  compilation**, et **zéro avertissement sur les sept fichiers touchés**. Les 698
  avertissements du log sont ceux, préexistants, que tout build à froid réémet.
- **Écartées comme dépassées, sans perte** : `feat/agent-taches-claude` (sa spec est sur
  `master` à l'identique, son commit Spotlight est une variante plus ancienne de ce que
  `master` porte), `feat/agent-taches-claude-wip` (seize fichiers identiques à l'octet près)
  et `fix/meeting-stable-id-optional` (`master` porte `stableID: UUID?` plus le backfill
  `ensuredStableID`, généralisé à tous les modèles).
- **`worktree-agenda-project-picker-search` supprimée** (locale, `origin` et son worktree),
  sur décision explicite : nettoyage net. Elle figeait 784 lignes commitées nulle part.
  L'essentiel du chantier « affectation événement d'agenda → projet » est **déjà sur
  `master`, à l'identique** : `AgendaProjectRule`, `AgendaProjectResolver` et ses 159 lignes
  de tests, la relation `Project.agendaRules`, la version de schéma, la liste de gestion des
  règles dans `SettingsView`.
- **⚠️ Ce qui a été détruit avec elle, et qu'il faudra réécrire si on le veut.** Son seul
  apport réel — celui que son nom annonce — était le **sélecteur de projet du panneau
  Agenda**. Sur `master`, la pastille de projet ouvre un `Menu` listant **tous** les projets
  à plat, sans filtre : pénible passé quelques dizaines de projets. La branche le remplaçait
  par un popover de 300 pt dans `AgendaInspectorPanel.swift` : champ « Filtrer les projets… »
  insensible à la casse, confirmation en un clic de la suggestion automatique en tête, liste
  filtrée dans un `ScrollView` borné à 320 pt, état vide distinguant « aucun projet dans la
  base » de « aucun résultat », et « Ignorer ce titre » / « Retirer la règle » en pied.
  Environ cent lignes. Ce n'était **pas** fusionnable tel quel : le fichier de la branche
  (364 lignes) partait d'une base antérieure à la version actuelle de `master` (283 lignes),
  il aurait fallu reporter le popover, pas remplacer le fichier.
- **Worktrees retirés** : `agent-claude`, `pastille-participant`, `teams-autorecord-popup`
  (tous propres) et `paperclip/-issue` (outil tiers, son dossier `web/` non suivi est perdu —
  suppression demandée). La copie de travail principale est passée sur `master` et est propre.

## Tout le travail local est sur `origin` (2026-09-02)

Session sans code : mise à jour du dépôt distant, qui n'avait rien reçu depuis le
2026-08-28. `origin/master` est à **`8548b8d`**, écart 0 avec le `master` local.

- **16 commits poussés sur `master`** : les 13 qui étaient en retard (double piste audio,
  frontières de chunks sur les silences, vague de correction de la revue, clés d'usage
  calendrier) et trois commits de fusion — `feat/pastille-participant-fil-ariane` (spec),
  `feat/teams-audio-double-piste` (spec « détection d'appel universelle »)
  et `feat/agent-claude` (noyau du service d'agent Claude, son dossier de travail,
  sept fichiers de tests, la spec).
- **Cinq branches créées sur `origin`**, sauvegardées telles quelles avant toute fusion :
  `feat/agent-claude`, `feat/agent-taches-claude`, `feat/agent-taches-claude-wip`,
  `feat/pastille-participant-fil-ariane`, `feat/teams-audio-double-piste`. Les autres
  branches locales sont entièrement contenues dans `master` — les pousser n'aurait ajouté
  que des étiquettes.
- **`feat/agent-taches-claude` n'a PAS été fusionnée**, seul écart à la consigne « tout
  fusionner », et il est délibéré : elle conflictait sur `MeetingView.swift` et
  `SpotlightMeetingIndexTests.swift`, et son commit Spotlight est une variante **plus
  ancienne** de ce que `master` a déjà reçu par `feat/fusion-note-reunion` (`indexAll` avec
  réunions et notes, `makeMeetingItem`, exclusion des transcriptions). Résoudre les conflits
  revenait à écraser du code plus récent. Sa spec est entrée par `feat/agent-claude`.
  `feat/agent-taches-claude-wip` était, elle, intégralement absorbée : ses seize fichiers
  sont sur `master`, identiques à l'octet près. Les deux branches restent sur `origin`.
- **Vérifié** : `swift test` complet sur la fusion, build à froid dans un worktree jetable —
  **1030 XCTest (1 ignoré, 0 échec) + 466 tests Swift Testing en 70 suites**, code de sortie 0.
  Le `--skip CalendarImportEventTests` reste inutile. La copie de travail n'a pas été touchée.
- **Quatorze documents versés** qui ne vivaient que sur le disque, dans aucun commit :
  `design_handoff_editor_blocs/` (handoff de design des blocs `/tableau` et `/diagramme` :
  README de spec visuelle, cinq captures, maquette HTML de référence) — **ce fichier-ci le
  citait déjà** comme point de départ du chantier éditeur, le lien pointait vers un dossier
  absent du dépôt ; les specs `2026-08-05-commandes-slash-manquantes.md` (inventaire des
  commandes slash d'AppFlowy, 364 lignes) et `2026-08-10-json-canonique-notes-design.md`
  (étude Markdown → JSON canonique, 591 lignes, aucune décision prise) ; `docs/adr/README.md`
  (convention de nommage des ADR) ; et `docs/architecture/` (`branch-status.md`,
  `cartographie.docx`, `diagram.html`). `branch-status.md` est un instantané du 10 août
  devenu faux — il décrit `feat/fusion-note-reunion` comme active alors qu'elle est
  fusionnée : versé tel quel, avec une ligne d'archivage en tête qui le dit. Aucun de ces
  fichiers ne tombe dans un répertoire de cible SwiftPM (`OneToOne/`, `Tests/`,
  `Vendor/BeautifulMermaidSwift/Sources`) : le build n'est pas touché.
- **Restent non suivis dans la copie de travail, et c'est sans conséquence** : quinze
  fichiers `OneToOne/Services/Agent/*.swift` et `Tests/Agent*.swift`, copies **identiques à
  l'octet près** de ce que `master` porte désormais. Ils peuvent être supprimés.
- **Ce que ce push ne change pas** : rien n'a été vérifié à l'écran. Les treize scénarios des
  deux plans Teams auto-record restent dus (voir les deux sections suivantes), l'attribution
  « moi » / « distant » n'est toujours câblée nulle part, et la spec « détection d'appel
  universelle » (2026-08-31, statut « à valider ») n'a **pas de plan écrit**.

## Teams auto-record — double piste audio (plan 2/2) (2026-08-31)

Branche `feat/teams-audio-double-piste`, **fusionnée dans `master` et poussée le 2026-09-02**
(voir la section du jour en tête de ce fichier) — voir le
[plan](docs/superpowers/plans/2026-08-28-teams-autorecord-double-piste-audio.md). Suite du
plan 1 ci-dessous.

- **État** : plan 2 « double piste audio », **les cinq tâches sont implémentées, revues et
  closes** sur `feat/teams-audio-double-piste` — mixeur pur avec provenance
  (`AudioTrackMixer`), capture système `SCStream` audio-only (`SystemAudioCapture`),
  intégration dans `AudioRecorderService` (flux STT verrouillé sur l'horloge micro,
  **WAV mixé** — toute retranscription entend les deux voix, spec §5 amendée), bandeau de
  repli micro seul, frontières de chunks sur les silences. La revue de branche a été suivie
  d'une vague de correction unique : livraison des blocs système directement depuis la file
  `SCStream` (le détour par le main actor figeait le retard de la voix distante quand le
  main thread bouchonnait), horodatage de la provenance sur l'horloge des échantillons
  publiés (une horloge murale se décalait de toute la durée d'une pause), bandeau de repli
  restreint à la réunion qui enregistre, et **une seule transcription en vol** —
  `maxConcurrent` ramené de 2 à 1, deux `model.generate` simultanés partageant un état
  `MLXArray` que mlx-swift documente comme non thread-safe.
- **Ce que la branche ne livre PAS — l'attribution « moi » / « distant »** : la chronologie
  d'énergie par piste est **produite** (`provenanceTimeline` se remplit, la fonction de
  décision `AudioTrackMixer.provenance` existe et est testée) mais **n'est consommée par
  personne**. Aucun segment transcrit ne porte de provenance, rien ne l'affiche, et la
  chronologie ne vit qu'en mémoire : elle est perdue à la fin de l'enregistrement. La spec
  §6.1(4) et D-7 le disent désormais explicitement. Le câblage (segments → `speakerID`) est
  un **chantier de suite**, avec la question de persistance qui vient avec : le WAV étant
  mixé, la provenance y est détruite et une retranscription du fichier ne la retrouvera
  jamais.
- **Vérifié cette session** : suite complète verte — `swift test` (sans `--skip`) :
  **366 tests Swift Testing (63 suites) + 1030 tests XCTest (1 ignoré), aucun échec** ;
  aucun nouvel avertissement de compilation sur les quatre fichiers touchés par la vague de
  correction (`AudioRecorderService`, `SystemAudioCapture`, `TranscriptionService`,
  `MeetingView`). Le bump de `CFBundleVersion` laissé par un run du script de build a été
  rendu à son état committé — `Info.plist` n'est pas modifié par ce chantier.
- **Vérifié à la session précédente** (tâche 4, toujours valable) : app construite
  via `Scripts/bump-and-build.sh dev`, sans `sudo` ni invite, build **761** ; process actif
  20 s après lancement (`pgrep`) ; `log show --last 1m --predicate 'subsystem ==
  "com.onetoone.app"'` ne remonte **aucune** entrée (donc aucune erreur) ; quittée
  proprement (process disparu après coupure) ; aucun rapport dans
  `~/Library/Logs/DiagnosticReports/`. **Attention** : `Scripts/bump-and-build.sh` tue
  **tout** processus nommé `OneToOne` (`pkill -x`, non scopé par chemin) — l'instance
  homonyme d'une autre session a été tuée puis relancée pendant cette vérification
  (changement de PID observé). Les contrôles de lancement/arrêt de cette vérification-là ont, eux,
  été scopés par chemin d'exécutable et ciblés par PID. Risque résiduel connu : lancer ce
  script pendant qu'une autre instance tourne l'interrompt ; un `pkill` scopé par chemin
  dans le script est à faire (report).
- **Prochaine action — partenaire, à l'écran** (aucun scénario faisable par un agent) :
  1. **Double piste nominale** : permission écran accordée, vrai appel Teams, accepter le
     popup, faire parler l'interlocuteur puis soi-même → la transcription contient les
     deux voix ; **retranscrire ensuite le WAV** (« Retenter le STT ») → les deux voix
     encore. Pas de bandeau jaune.
  2. **Permission refusée** : retirer l'app de Réglages Système → Enregistrement de
     l'écran, relancer, enregistrement Teams → démarre quand même, bandeau jaune, voix
     locale seule, aucune erreur bloquante.
  3. **Non-régression classique** : réunion sans lien Teams → une seule piste, aucun
     bandeau, aucune chronologie de provenance.
  4. **Appel long (> 20 min)** : deux choses observables, et deux seulement.
     (a) Le log unique « reliquat audio systeme plafonne » apparaît-il (dérive d'horloge
     système) ? Il ne doit jamais se répéter. (b) En fin d'appel, la voix distante est-elle
     toujours **synchrone** dans la transcription, ou a-t-elle pris du retard sur la
     locale ? Ne pas chercher d'attribution moi/distant : elle n'existe pas encore
     (voir plus haut).
  5. **Vumètre** : pendant que seul l'interlocuteur distant parle, le vumètre reste plat
     (il ne lit que le micro) — juger si c'est acceptable ou s'il faut l'alimenter du mix
     (à noter comme report si gênant).
  6. **Import audio > 5 min** : timestamps des segments qui suivent les coupes, barre
     « Segment n / N ».
- **Reports connus** (issus des revues, non bloquants) : vumètre micro seul (il ne lit que
  le micro, pas le mix) ; test `idleTimelineIsEmpty` assert sur l'état partagé du singleton ;
  `writeToFile` avale son `guard` en silence ; la branche double piste engagée (mix +
  écriture) n'a pas de test unitaire — c'est la vérification à l'écran qui la couvre ;
  `chunksTileTheSignal` ne vérifie pas la non-vacuité du **dernier** intervalle ; fenêtre
  étroite (65,0 s ; 65,2 s] où le dernier morceau peut tomber à ~0,2 s ; `pkill -x` non
  scopé par chemin dans `Scripts/bump-and-build.sh`. Repliés par la vague de correction et
  donc retirés de cette liste : `provenanceTimeline` publié sans lecteur, doc `TapSink` en
  retard sur son contrat, commentaires « chunks 60s » périmés.

## Teams auto-record — détection & orchestration (plan 1/2) (2026-08-28)

- **État — livré en production.** `master` à `69ceabf` (fast-forward de `bbad581` : les 23
  commits du chantier y sont), build **754** (release) dans `/Applications`. ~~Rien n'est
  poussé sur `origin`~~ — **résolu le 2026-09-02** : tout est sur `origin/master`, voir la
  section en tête de ce fichier. Les tâches 1 à 8
  du plan `docs/superpowers/plans/2026-08-28-teams-autorecord-detection-orchestration.md`
  sont implémentées et revues — détection pure,
  appariement agenda, moniteur `NSWorkspace` + énumération opportuniste, cinq catégories de
  notification Teams (neuf enregistrées au total), machine à états pure, icône de barre de
  menus, coordinateur (trois déclencheurs + horloge 30 s gardée sur Teams en cours
  d'exécution), `MeetingView` qui consomme les demandes et rend compte,
  concurrence (liaison), garde provider IA, popup STT indisponible avec « Retenter le STT »
  qui relance la transcription. Micro seul : la double piste est le plan 2. La revue de branche
  a été soldée par une vague de correction unique (identité par occurrence pour les réunions
  récurrentes, popup remplacé plutôt que bloquant, horloge gardée sur Teams, tick lent au
  repos) — voir le « Journal d'exécution » du plan.
- **Vérifié** : `swift test` complet — **le `--skip CalendarImportEventTests` n'est plus
  nécessaire** depuis que `MeetingNotificationService` n'instancie `UNUserNotificationCenter`
  que dans un bundle `.app` (`Bundle.main.bundleURL.pathExtension == "app"`, sinon `center`
  reste `nil`) ; l'app se construit, se lance et quitte sans crash. Confirmé cette session :
  `Scripts/bump-and-build.sh dev` sans `sudo` ni invite, build 749 ; process `OneToOne` actif
  après 20 s ; `log show` sur `subsystem == "com.onetoone.app"` (niveaux info/debug inclus,
  catégories `teams`, `teams-autorecord`, `capture` en particulier) ne remonte **aucune**
  entrée pour le process `OneToOne` — donc aucune erreur ; l'app quitte proprement via
  `osascript` (`pgrep` négatif ensuite) ; aucun rapport dans
  `~/Library/Logs/DiagnosticReports/`. **À la livraison** : suite complète repassée sur
  `69ceabf` — 335 Swift Testing + 1030 XCTest, aucun échec ; `Scripts/bump-and-build.sh prod`
  sans `sudo` ni invite (`/Applications` écrivable), build 754, `default.metallib` MLX embarqué
  depuis `Mickey.app`, copie de développement de `~/Applications` retirée par le script, app
  relancée depuis `/Applications` et vivante, toujours aucun rapport de crash.
- **⚠️ Livré sans avoir jamais été vu à l'écran.** Ce qui est prouvé : ça compile, la suite
  passe, l'app se lance, tourne et quitte sans erreur ni crash. Ce qui ne l'est pas : qu'un
  vrai appel déclenche le popup, que « Démarrer » enregistre, que « Arrêter et finaliser »
  transcrive, que le rapport se génère. Le parcours complet reste à éprouver.
- **Prochaine action — partenaire, à l'écran** (sept scénarios, aucun n'est faisable par un
  agent — il faut un vrai appel Microsoft Teams et un calendrier vivant) :
  0a. Réunion récurrente, deuxième occurrence : le popup est proposé et « Démarrer » crée une
     nouvelle réunion (pas d'écrasement de la précédente).
  0b. Bannière ignorée : laisser expirer le popup, attendre l'appel suivant → il est proposé
     (le précédent est remplacé).
  1. Détection + démarrage : événement Teams à +1 min dans le calendrier, fenêtre Teams au
     premier plan avec « Réunion » dans le titre, 5 s → popup ; « Démarrer » crée, ouvre,
     enregistre, icône rouge pulsante.
  2. Refus : « Ignorer » → rien de créé, pas de re-popup pour le même événement.
  3. Fin d'appel : `killall Teams`, 30 s → popup « Appel Teams terminé » ; « Arrêter et
     finaliser » → capture arrêtée, transcription lancée, icône normale.
  4. Rapport : popup « Transcription prête (N segments) » ; « Générer le rapport » →
     rapport dans la réunion, éditable.
  5. Sans permission d'enregistrement d'écran : « Rejoindre Teams » depuis OneToOne → le
     déclencheur 2 propose quand même (D-11).
  Puis : plan 2 (`2026-08-28-teams-autorecord-double-piste-audio.md`).
- **Défauts connus / reports** (issus des revues, non bloquants) : l'icône de barre de menus
  est pilotée par le coordinateur, pas par l'état réel du recorder ; aucun timeout si la
  fenêtre ne rend jamais compte ; `TeamsCallMonitor.stop()` n'annule pas un tick en vol ; le
  mode dégradé sans `UNUserNotificationCenter` (binaire hors `.app`) reste invisible pour
  l'utilisateur — il n'est tracé qu'en `.warning` dans le log système ; la trace
  « Source : Outlook Calendar » de la spec §5 n'est pas écrite (`summary` est le corps du
  rapport, écrasé à la génération — `calendarEventID`/`calendarEventTitle` portent le lien).

## Synthèse

**Fiche collaborateur v3 — livrée en production.** `master` à `70c268d`, build 730 (release)
dans `/Applications`. 997 XCTest (1 ignoré) + 270 Swift Testing, aucun échec. La copie de
développement de `~/Applications` a été retirée par le script : il n'y a plus qu'une app.

**Couvert** : fil chronologique unifié à quatre types, colonne d'état fixe (prochain 1:1 avec
ses points de préparation cochables, engagements soldables, actions, rythme, projets), en-tête
adaptatif, feuille d'édition `⌘I` complète avec puits photo à cinq entrées, sélecteur d'année,
export du fil, suppression, navigation clavier (`↑↓`, `␣`, `⏎`, `⌘1`…`⌘5`).

**Trois manques réels**, tous à la charge d'un prochain chantier :

1. le **tri « Pas vu depuis » du dashboard** n'existe pas — critère d'acceptation n° 9 de la
   spec ; la cadence n'est lue que par la fiche ;
2. **`⎋` ne demande jamais confirmation** : la feuille d'édition ne sait pas si elle est
   modifiée (critère n° 10) ;
3. **`⌘⌥←/→`** demande de toucher à la barre latérale, donc un autre écran.

**Deux écarts assumés** : `⏎` ouvre la réunion dans sa fenêtre dédiée et non en poussant dans
la pile — la navigation programmée depuis ce panneau est ce qui avait fait crasher AppKit au
build 715 ; et les squelettes de chargement n'ont rien à masquer, `@Query` résolvant avant le
premier rendu.

**⚠️ La plus grande part n'a jamais été vue à l'écran.** Vérifiés par l'auteur : l'affichage,
la colonne d'état qui ne défile pas, l'ouverture d'une réunion, le retour, l'absence de crash
au double-clic, la feuille d'édition. **Non vérifiés** : graphe d'écart, cases de préparation,
sélecteur d'année, export, suppression, tous les raccourcis clavier, et le glisser-déposer
d'une photo. Prochaine action : une passe à l'écran, spec en main.

**Réparations de données passées au démarrage**, toutes idempotentes et vérifiées sur le store
réel : 38 rôles portant une adresse mail déplacée vers le champ `email` (0 perte, dont 16 où
l'adresse n'existait que là), et les réunions dont le drapeau de report de préparation avait
été posé sans que rien n'ait été versé.

**Deux branches en attente.** `feat/pastille-participant-fil-ariane` : spec validée, plan
jamais écrit. `feat/fusion-note-reunion` : fusionnée dans `master` ; sa tâche 13 garde huit
contrôles non déroulés, passés en vérification à l'usage.

**Fusion Note / Réunion — code terminé, vérification sur données réelles due.** Branche
`feat/fusion-note-reunion`, 43 commits. Les douze tâches de code du
[plan](docs/superpowers/plans/2026-08-10-fusion-note-reunion.md) sont livrées ; la
treizième — sauvegarde du store, migration, dix contrôles à l'écran — **n'a pas eu lieu**.
Voir la section datée du 2026-08-10 ci-dessous. Prochaine action : cette tâche 13.

**Réécriture de l'éditeur — décidée, verdict du prototype en attente.** La
réécriture de l'éditeur en reprenant l'architecture d'appflowy-editor
(AGPL-3.0 acceptée) est décidée, voir
[l'ADR de licence](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
Un prototype jetable (`Prototypes/BlockEditorProbe/`) a sondé le risque
central — une vue éditable par bloc en AppKit — et existe toujours ; son
verdict est **en attente** de la vérification à l'écran, qui n'a pas eu
lieu, voir [l'ADR de verdict](docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md).
Le chantier ci-dessous (`feat/editeur-slash-blocs`) reste **en l'état** :
ni fusionné, ni abandonné ; sa propre vérification à l'écran reste due,
indépendamment du prototype. Prochaine action : la session de vérification
à l'écran du prototype.

**Vitrine `ActionsListView` — mise en page de la capture adoptée, écran dû.** Chantier
ouvert à partir de huit captures de design. Voir la
[spec](docs/superpowers/specs/2026-08-09-habillage-visuel-design.md), le
[plan d'habillage](docs/superpowers/plans/2026-08-09-habillage-vitrine-actions.md) et le
[plan correctif](docs/superpowers/plans/2026-08-09-vitrine-actions-mise-en-page-capture.md).
Branche `feat/habillage-vitrine-actions`, 17 commits.

**Correction de cap en cours de route.** Le premier plan a appliqué le *vocabulaire visuel*
de la capture aux informations existantes sans adopter sa *mise en page* : à l'écran, la
maquette n'était pas reconnaissable. Erreur d'interprétation, pas d'exécution — toutes les
revues étaient vertes. Le second plan corrige : la barre principale est devenue celle de la
capture, les contrôles secondaires sont montés en barre d'outils, la ligne s'est réduite à
cinq éléments avec un menu `⋮` au survol.

Livré : jetons `AppTheme` ; deux règles de date testées — `Urgence` (couleur, seuil sept
jours, 8 tests) et `Portee` (filtrage, 9 tests) ; composants `Avatar`, `MetaValue`,
`SegmentedFilter` (7 tests) ; « Grouper par » branché sur la vue liste avec un axe
« Échéance », les sections réutilisant la même fonction que le kanban.

**Rien n'a été vérifié à l'écran, sauf un survol de l'auteur qui a révélé deux défauts** —
« Grouper par » inopérant en liste (corrigé) et, trouvé dans la foulée par la revue, les
actions terminées rendues invisibles par la portée (corrigé). Une vingtaine de contrôles
restent dus. Trois sont prioritaires :

1. **cliquer `⋮`** — le mécanisme censé l'empêcher de déplier aussi la ligne n'a jamais été
   vérifié ; s'il bloque l'ouverture du menu, Modifier, Commentaires et Supprimer deviennent
   inatteignables sur les actions ouvertes ;
2. **survoler le titre et la case à cocher** — l'apparition de `⋮` dépend d'un `onHover`
   posé sur une vue de fond ; si le suivi ne porte pas au-dessus des sous-vues, même
   conséquence ;
3. **« Filtres → Terminées »** — vérifier que les actions terminées apparaissent bien.

Trois règles de date coexistent : `Urgence` (couleur), `Portee` (filtrage) et les seuils
propres de `taskStatus` (forme de la puce et infobulle, aujourd'hui/demain/48 h). Une action
due demain porte donc une puce « imminente » coloriée en gris « à venir ».

Dettes et arbitrages dus : `ListRow`, nommé par la spec, jamais extrait ; la spec interdit
toute fonction nouvelle alors que le filtre de portée et le groupement en liste en sont ;
l'axe « Échéance » ajouté à `ActionGrouping` fait apparaître un quatrième segment dans
`ActionsPanel`, écran non visé ; onze des vingt jetons d'`AppTheme` n'ont aucun consommateur
(catalogue publié d'avance pour la propagation) ; `CLAUDE.md` ligne 99 impose l'anglais pour
les symboles alors que `Views/DesignSystem/` est en français par décision explicite —
correction impossible tant que `CLAUDE.md` porte des changements non commités du chantier
éditeur ; et **aucun test n'exerce la chaîne de filtres**, où trois défauts ont pourtant été
trouvés.

Prochaine action de ce chantier : la session de vérification à l'écran, en commençant par
les trois contrôles prioritaires ci-dessus.

Le chantier actif est la refonte de l'éditeur Markdown en éditeur de blocs,
à partir du handoff [`design_handoff_editor_blocs/README.md`](design_handoff_editor_blocs/README.md).

- Branche : `feat/editeur-slash-blocs`
- Avance sur `master` : 113 commits
- Source de vérité : le Markdown reste le format stocké
- Moteur d'édition : AppKit / TextKit 1
- État du worktree : plusieurs changements de l'éditeur sont encore non
  commités ; ils ne doivent pas être mélangés avec les changements de
  migration de `OneToOneApp.swift`

## Fusion Note / Réunion (2026-08-10)

Branche `feat/fusion-note-reunion`, 43 commits, **fusionnée dans `master` et poussée** —
constaté le 2026-09-02 : elle n'a plus aucun commit hors `master`.

**Livré.** `MeetingKind.note` et l'exclusion des statistiques (`MeetingStatsScope`) ;
`NoteFactory` ; les onglets et le chrome de `MeetingView` filtrés par kind ; l'indexation
Spotlight des réunions et des notes, avec l'ouverture depuis un résultat ; l'écran « Notes »
et la `NotesSection` des fiches réécrits sur `Meeting` ; la note rapide, la recherche
latérale et le gabarit de rapport repointés ; les commandes `/ajout-*` vers leur modèle
naturel ; `MailProjectMatcher` sur les participants des réunions. **Quatre modèles
supprimés** : `Note`, `NoteAttachment`, `ProjectInfoEntry`, `ProjectCollaboratorEntry` —
sans `SchemaV2`, la prémisse étant que `ZNOTE` est à zéro dans le store réel, ce qui reste
à vérifier (tâche 13, étape 2).

**Huit correctifs issus d'une revue à effort `xhigh`** (14 constats vérifiés, 6 réfutés),
tous en TDD, tous sur le prédicat qui supprime une note vide à la fermeture de l'écran —
suppression *sans* confirmation, là où la suppression explicite passe par un
`confirmationDialog` :

1. le contenu du 1:1 manager (`ManagerMeetingReport`, `ManagerReportItem`,
   `ActionTask.managerMeeting`) était invisible au prédicat, faute de relation inverse sur
   `Meeting` : un 1:1 rapporté basculé sur « Note » était supprimé avec son CR ;
2. le texte tapé dans les 0,3 s avant la fermeture n'atteignait jamais le modèle (débounce de
   l'éditeur non vidé au démontage) : la note était jugée vide et supprimée avec ce qu'on
   venait d'y écrire ;
3. les participants ad hoc, saisis à la main, et les statuts de présence ne comptaient pas ;
4. les colonnes JSON du rapport étaient lues par leurs façades, dont le getter avale toute
   erreur de décodage en `[]` ;
5. `isBeingDeleted` était un `@State` : deux écrans sur la même réunion se supprimaient le
   modèle sous les pieds (`MeetingScreenRegistry` porte désormais le compte et la
   suppression) ;
6. les quatre gardes de relation en cascade n'étaient couvertes par aucun test (table ajoutée,
   vérifiée par mutation) ;
7. l'ordre des gardes faisait fauter toute la transcription avant d'atteindre un scalaire ;
8. cinq commentaires promettaient plus que le code ne tient.

**Non appliqué, à arbitrer.** Le prédicat reste une liste blanche entretenue à la main sur
une partie des propriétés de `Meeting` : une propriété ajoutée demain tombe hors de la garde
sans qu'aucun test n'échoue. Le correctif de fond serait de conditionner la suppression
silencieuse à la **provenance** (« cet écran a créé cette note et rien ne l'a touchée »)
plutôt qu'au contenu. Choix structurant → à proposer en ADR, pas à décider en revue. La
moitié « texte » de la dérive est fermée par `Meeting.textualContent` et son test.

**Vérifié.** `swift test --skip CalendarImportEventTests` : **997 tests XCTest** (1 ignoré,
`CalendarImportEventTests`, crash d'environnement connu) **+ 301 tests Swift Testing, aucun
échec**.

### Tâche 13 — données réelles (2026-08-10, soir)

**Étapes 1, 2, 3 et 5 faites. L'étape 4 — les dix contrôles à l'écran — n'a pas eu lieu.**

**Sauvegarde.** `~/Library/Application Support/OneToOne.backup-2026-08-10-fusion-note`
(`.store` de 33 Mo, dossier complet de 8,7 Go avec enregistrements et pièces jointes).

**La migration avait déjà eu lieu, sans témoin.** Le store réel ne portait plus les quatre
tables au moment du contrôle : `ZNOTE`, `ZNOTEATTACHMENT`, `ZPROJECTINFOENTRY` et
`ZPROJECTCOLLABORATORENTRY` sont **absentes** de `sqlite_master` et de `Z_PRIMARYKEY`, et
`ZMEETING` porte déjà une réunion de kind `note`. L'app avait donc été lancée sur le schéma
de la branche avant cette session (mtime du store : 19:08). Le contrôle de l'étape 2, prévu
comme un préalable, est devenu **rétrospectif**.

**La prémisse tient, établie sur trois instantanés antérieurs à la fusion :**

| Instantané | `ZNOTE` | `ZNOTEATTACHMENT` | `ZPROJECTINFOENTRY` | `ZPROJECTCOLLABORATORENTRY` | `ZMEETING` |
|---|---|---|---|---|---|
| `~/Documents/OneToOne-sauvegarde-notes-2026-08-05` | 0 | 0 | 0 | 0 | 162 |
| `OneToOne.backup-2026-06-06` | 0 | — | 0 | 0 | 108 |
| `OneToOne.backup-2026-04-24` | table absente | — | 0 | 0 | 5 |
| store actuel | table supprimée | table supprimée | table supprimée | table supprimée | 164 |

La sauvegarde du 5 août précède le chantier de cinq jours : les quatre tables étaient vides,
il n'y avait donc **rien à perdre**, et les 162 réunions d'alors sont devenues 164 sans perte.
C'est ce que la note de `SchemaVersions.swift` affirmait ; c'est vérifié indépendamment.

**Étape 3 — la version commitée ouvre le store réel.** `Scripts/bump-and-build.sh dev`,
build 690, lancé après avoir mis de côté la modification non commitée de `OneToOneApp.swift`
(celle qui retire `migrationPlan`), et **restituée aussitôt après**. L'app démarre et tient :
aucune trace de migration ni d'erreur CoreData dans `log show`, le store n'a pas été mis de
côté par la récupération destructive, et les 164 réunions sont toujours là après ouverture.
Effet de bord du script : `Info.plist` passe de `629` à `690` — c'est un fichier que porte
déjà le chantier étranger.

**Étape 5 — suite de tests.** 997 XCTest (1 ignoré) + 301 Swift Testing. **Un échec, horaire
et préexistant** : `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` construit une
réunion à `now + 1h` et la compte dans « aujourd'hui » ; lancé après 23 h, ce `+1h` tombe le
lendemain et le décompte passe de 2 à 1. La même commande passait à 22 h sur le même code, et
aucun commit de la branche ne touche `TodayStatsCalculator`. À corriger un jour en injectant
l'horloge — c'est le second test horaire du fichier après `test_badge_twelve_compact`.

**Étape 4 — trois contrôles déroulés sur onze, le 2026-08-10 au soir.**

| # | Contrôle | Résultat |
|---|---|---|
| 1 | note rapide du menubar → apparaît dans « Notes » | conforme |
| 2 | l'ouvrir → deux onglets, pas de barre d'enregistrement | conforme |
| 3 | bascule vers « One-to-One » → les six onglets reviennent | conforme, **mais** |
| 4–11 | temps passé, fiche collab, fiche projet, Spotlight, nouvelle note, frappe puis fermeture, deux fenêtres, backup/restore | **non déroulés** |

Le contrôle 3 a révélé un manque : la bascule produit un 1:1 **sans interlocuteur**, et rien
dans le fil d'Ariane ne permet de le rattacher à quelqu'un — le seul chemin est Vue
d'ensemble → Présence → « Gérer les participants ». Le manque préexiste à cette branche (le
badge de type était déjà un `Picker` sur tous les types). Traité à part, sur
`feat/pastille-participant-fil-ariane`, voir
[la spec](docs/superpowers/specs/2026-08-11-pastille-participant-fil-ariane-design.md).

**Les contrôles 4 à 11 passent en vérification à l'usage**, décision de l'auteur le
2026-08-11. La tâche 13 n'est donc **pas close** : ce qu'ils couvrent — dont la fermeture
immédiatement après la frappe, seul contrôle qui tranche l'ordre `.onDisappear` /
`dismantleNSView`, et la même note ouverte dans les deux fenêtres — reste non vérifié. Ne
pas écrire ailleurs que ces points sont acquis.

## `master` ne compilait plus depuis le 2026-08-08 (constaté le 2026-08-11)

Constaté en créant un worktree partant de `master` : **42 erreurs de compilation**.
`OneToOne/Markdown/Core/EditorTextView.swift`, commité le 8 août (`8d88197`), appelle une API
dont les définitions étaient restées **non commitées** dans l'arbre de travail de l'auteur —
`TableControlLayout.footerGeometry`, `MermaidBlockLayout.columnWidth`,
`BlockMoveCommands.dragRewrite`, `TableEditCommands.Gesture.addColumnLeft`, entre autres.
Toutes les branches en héritaient : **le seul état compilable du dépôt était cet arbre de
travail**. Conséquence rétrospective à connaître : toutes les suites de tests vertes citées
plus haut ont été lancées sur cet arbre — code de la branche **plus** le chantier éditeur non
commité. Aucun commit n'a jamais été compilé isolément ; ce n'était pas possible.

Réparé sur `fix/build-editeur-mermaid-tables`, partie de `master`, en deux commits : le
vendoring de BeautifulMermaidSwift (MIT) + `elk-swift` (81 fichiers), puis les onze fichiers
de `OneToOne/Markdown/`, `NativeMermaidRenderer.swift` et onze fichiers de test
(+1606 −339). Contenu repris sans modification de l'arbre de l'auteur ; jeu minimal
déterminé par ajouts successifs. Vérifié : `swift build` passe, et
`swift test --skip CalendarImportEventTests` donne 990 XCTest (1 ignoré) + 138 Swift Testing,
aucun échec.

**Fusionné dans `master`** le 2026-08-11 (`4577048..9f18a73`), puis `master` fusionné dans
`feat/fusion-note-reunion` (`8d77c18`). L'arbre de travail est passé de 24 fichiers modifiés
à trois — `CLAUDE.md`, `Info.plist` (bump du script de build) et la modification de
`OneToOneApp.swift` sur `migrationPlan` — le reste étant désormais commité à l'identique.
Contenu vérifié octet à octet contre une sauvegarde prise avant l'opération. La branche
fusion compile pour la première fois seule : 997 XCTest (1 ignoré) + 301 Swift Testing,
aucun échec.

**Ce qui reste ouvert par ailleurs**, laissé tel quel par la spec : le sort de `Meeting.notes`
(champ distinct de `liveNotes`, encore lu par les gabarits de rapport) et le renommage
éventuel de `liveNotes`, dont le nom est un héritage des réunions enregistrées.

**Arbre de travail.** Il porte un chantier étranger non commité (éditeur de blocs, Mermaid
natif, `Services/Agent/`, `Vendor/`) : tous les commits de cette branche sont faits à chemins
explicites.

## Sûreté des données — axe 1 de la revue de mai appliqué (2026-08-09)

Six commits sur `master` (`8401536..d806a4b`), suite verte vérifiée par le coordinateur :
990 tests XCTest (1 ignoré, `CalendarImportEventTests`, crash d'environnement connu)
+ 138 tests Swift Testing, aucun échec.

Applique les trois correctifs de l'axe « sûreté des données » de la
[spec de reprise](docs/superpowers/specs/2026-08-09-revue-code-data-safety-perf-design.md),
issue de la branche `fix/code-review-data-safety-perf` (fusionnée et supprimée le 2026-09-02) :

1. **Dédoublonnage d'identifiants UUID au démarrage.** La règle vit dans
   `Services/IdentifierRepair.swift` (testée hors SwiftData) ; `repairStoreIfNeeded()`
   n'en est que le branchement. `TranscriptChunk.chunkId` est désormais couvert ;
   `SlideCapture.id` l'était déjà.
2. **La désynchronisation audio/transcription est nommée et affichée.**
   `TranscriptEditError.saveFailedAfterAudioCut` remonte jusqu'au bandeau d'erreurs de
   `MeetingView`. Auparavant l'erreur mourait dans un `print`.
3. **Le fichier temporaire est nettoyé sur échec** dans `AudioFileEditor.trim` et `.cut`,
   sur le modèle du `catch` que `split` avait déjà.

**Trois points à connaître, tous relevés en revue :**

**La réparation des identifiants arrive à temps par circonstance, pas par construction.**
`repairStoreIfNeeded()` tourne dans le `onAppear` de `ContentView`, donc après
`applicationDidFinishLaunching`. Elle tient parce qu'aucun code de démarrage ne lit ces
identifiants aujourd'hui. **Le premier qui le fera cassera l'invariant en silence, sans
qu'aucun test ne s'en aperçoive.**

**`deleteSegment` sauvegarde le contexte partagé avant de couper l'audio.** C'est
volontaire et cela fait deux choses : le `rollback()` de fin ne peut plus emporter la
saisie en cours d'un autre champ (`MeetingView` a une sauvegarde différée de 0,6 s sur
`summary`, `referencedAbsent`, `nextDeadline`), et un store non inscriptible est découvert
**avant** la coupe irréversible.

**Le chemin d'échec de `context.save()` n'est couvert par aucun test.** Un test sur store
fichier rendu non inscriptible serait possible mais fragile (WAL SQLite). Le comportement
du `rollback` n'est vérifié que par lecture de code.

**Reste dû :** les huit autres correctifs de la spec (axes « fil principal » et
« robustesse des entrées »), volontairement non traités à l'époque. **Soldé le 2026-09-02** :
la branche `fix/code-review-data-safety-perf` a été fusionnée (`ee8a4b3`) puis supprimée.
Six de ces correctifs sont entrés dans `master` ; les autres avaient été **dépassés** par du
code écrit depuis, en mieux — voir la section en tête de ce fichier pour le détail de la
résolution, conflit par conflit.

---

## Éditeur de blocs

### Diagrammes Mermaid

Le cycle complet est implémenté :

1. placeholder de chargement compact ;
2. diagramme rendu dans une carte sobre ;
3. barre d'actions au survol avec modification et duplication ;
4. source ouvert dans un cadre avec en-tête, numéros de ligne et bouton
   « Terminé » ;
5. carte d'erreur avec message et bouton « Ouvrir le source ».

Le rendu Mermaid a été repris pour un résultat plus professionnel : thème
clair/sombre dédié, espacements cohérents, libellés SVG natifs compatibles
avec `NSImage`, connecteurs fins et pointes de flèche stables dans AppKit.

Le chemin principal utilise désormais une copie locale modifiable de
BeautifulMermaidSwift 1.0.4 (`Vendor/BeautifulMermaidSwift`, licence MIT,
commit amont documenté dans son `README.md`) et ELK Swift 1.0.2. Le rendu est
natif AppKit/CoreGraphics, sans WebView pour les six familles prises en
charge. Le moteur Mermaid JavaScript emballé reste le fallback des syntaxes
non reconnues par le parseur natif. Une correction locale retourne le
contexte bitmap AppKit : l'amont produisait sinon une image verticalement
inversée sur macOS.

Défauts corrigés :

- `-->` n'est plus transformé en tiret cadratin par AppKit ;
- le source est masqué pendant l'aperçu ;
- seule la première ligne réserve la hauteur de l'image ;
- la hauteur est recalculée après le rendu asynchrone ;
- l'ancien cadre est invalidé immédiatement puis au cycle AppKit suivant
  lors du passage aperçu/source ;
- le hit-test suit maintenant le rectangle réellement peint au lieu du
  caractère TextKit sous la souris. Le bouton « Ouvrir le source » reste donc
  cliquable même lorsque l'image déborde encore de sa ligne réservée ;
- la borne de fin d'un bloc ouvert est désormais **incluse**
  (`MermaidBlockLayout.selectionTouches`) : flèche droite, Fin ou un clic en
  bout de ligne laissent le bloc en édition et une frappe s'ajoute à la fin
  du source ; « Terminé » place le curseur au-delà du séparateur (un `\n`
  est inséré si le bloc clôt le document) et reste le seul geste qui
  referme le bloc — l'ancien contournement souris (`openSelectionLocation`)
  est supprimé, devenu inutile ;
- la carte Mermaid terminée, le placeholder et l'erreur utilisent désormais
  la largeur de colonne commune (960 pt) et le SVG est centré à l'intérieur ;
- la première ligne du source Mermaid utilise une hauteur TextKit normale :
  l'en-tête est réservé par l'espacement de paragraphe, ce qui évite un
  curseur vertical surdimensionné ;
- l'en-tête d'un bloc Mermaid ouvert élargit temporairement le clip de dessin
  au conteneur TextKit : celui du second bloc reste visible lorsqu'il suit une
  carte Mermaid haute ;
- les parseurs natifs vendored (flowchart/state, sequence, class, er,
  xychart) **jettent** désormais sur toute ligne non consommée
  (`autonumber`, `activate` seul, `click`, notes, `style`…, commentaires
  `%%` exceptés) au lieu de l'ignorer en silence : le rendu natif échoue et
  `MermaidRenderer` retombe sur le moteur JavaScript compatible — plus
  d'image incomplète mise en cache (patch local documenté dans
  `Vendor/BeautifulMermaidSwift/README.md`) ;
- la barre d'actions du diagramme fermé expose « Modifier » et « Dupliquer » ;
  la duplication conserve le bloc Markdown complet et ses attributs visuels ;
- `/diagramme` insère un squelette complet et valide :

  ```mermaid
  flowchart TD
      A[Début] --> B[Fin]
  ```
- le squelette inséré n'est plus sélectionné en entier : le curseur est placé
  après le bloc, qui se rend immédiatement, et une première frappe ne peut
  plus effacer tout le source ;
- les frappes caractère par caractère, le remplacement d'une sélection
  interne et l'édition près du dernier caractère conservent désormais
  strictement le reste du source et le Markdown sérialisé ;
- le bloc mermaid **ouvert** affiche son propre diagramme dans son cadre, au-dessus
  du source (bande plafonnée à 240 pt, `MermaidSourceLayout.previewMaximumHeight`) :
  l'image est celle de la dernière fermeture, **jamais** un rendu relancé à la
  frappe — le correctif de superposition du 2026-08-08 reste intact.

**Double liseré de l'aperçu.** L'image de l'attachment porte déjà son propre
cadre arrondi et son liseré, à la largeur de la colonne ; ils tombent donc
exactement sur ceux de la carte. C'est **systématique**, pour le diagramme
rendu, le cadre d'erreur et le placeholder — ce n'est pas une hypothèse.
Point d'esthétique laissé au jugement de l'auteur.

**Cause racine de la carte peinte par-dessus le bloc précédent — trouvée et
corrigée (2026-08-08).** Une revue finale a jugé le chantier non fusionnable
et a cherché plus loin : la cause est un défaut **antérieur au chantier**.
Fait mesuré (script conservé :
`docs/mesures/mesure-textkit.swift`) :
en TextKit 1, `lineFragmentRect` **inclut** l'espace réservé par
`paragraphSpacingBefore` et `paragraphSpacing` ; c'est `lineFragmentUsedRect`
qui commence au sommet du texte. Toute la géométrie de la carte d'un bloc
mermaid ouvert s'ancrait sur le rect de fragment, et se peignait donc
au-dessus du bloc précédent, d'un montant égal à la bande réservée. Ce défaut
précède le chantier : avec l'ancienne bande de 43 pt, l'en-tête remontait
déjà de 43 pt dans le bloc du dessus. C'est l'explication du constat qui a
lancé le chantier (« on ne voit pas qui appartient à qui »), que la
spécification avait mal diagnostiqué comme un simple problème d'écart.

Second fait mesuré (`mesure-f2-leviers.swift`, `mesure-f2-delegue.swift`) :
TextKit 1 **ignore** `paragraphSpacingBefore` sur le premier paragraphe du
conteneur. Un bloc mermaid en tête de note ne réservait donc rien : en-tête
invisible, bouton « Terminé » incliquable — également un défaut préexistant.
Corrigé par un délégué `paragraphSpacingBeforeGlyphAt` **passe-plat**, qui
relit l'attribut dans le storage et le renvoie : mesuré neutre partout
ailleurs. À noter, car contre-intuitif : le délégué **remplace** la valeur de
l'attribut au lieu de s'y ajouter.

Six correctifs, tous relus :

1. `1ea10a4` — toute la géométrie de la carte ouverte ancrée sur
   `lineFragmentUsedRect` (cadre, en-tête, aperçu, bouton « Terminé », numéro
   de ligne de la gouttière). Mesures : distance bas du cadre → bas du
   source 38 → 10 pt ; écart visible sous la carte −10 → +18 pt. Emporte
   aussi deux défauts de même cause : la puce du dernier item d'une liste
   voisine d'une carte décrochait d'environ 9 pt, et le filet de citation
   courait jusqu'à 28 pt sous sa dernière ligne.
2. `c009c64` — bande réservée pour un bloc mermaid ouvert en tête de note
   (délégué ci-dessus).
3. `72a4bd6` — le restylage inclut désormais le bloc **précédent**, qui
   porte l'écart inter-blocs : sans cela, `/tableau` et `/diagramme`
   n'aéraient pas le bloc au-dessus d'eux jusqu'au prochain restylage.
4. `b5aa506` — la bande réservée est recalculée quand un rendu aboutit sur
   un bloc **ouvert** : la réservation était calculée sur le placeholder
   pendant que le dessin utilisait le diagramme livré entre-temps (144 pt de
   débord).
5. `96c1119` — l'écart visible sous une carte vaut désormais celui du
   dessus (28 pt des deux côtés ; auparavant 18 en dessous, le `max`
   absorbant le padding intérieur).
6. `8d88197` — quatre points de solidité : le hit-test des cases à cocher
   s'ancre sur le texte (avant : cliquer dans le **vide** sous le dernier
   item d'une checklist voisine d'une carte cochait la case) ; la somme
   `headerHeight + previewHeight + bodyTopPadding` a un point d'entrée
   unique, `MermaidSourceLayout.reservedBandHeight` ; la fabrique de test de
   géométrie est refermée derrière `#if DEBUG` ; le test de mise en page
   passe par le vrai chemin de dessin.

Le test qui manquait, et qui a été ajouté : sur un éditeur réellement mis en
page (`ensureLayout`), le cadre calculé doit tenir dans l'espace vertical du
bloc et ne jamais remonter au-dessus du bloc précédent. Les tests antérieurs
étaient tous algébriquement auto-cohérents et ne mettaient jamais en page un
storage réel — c'est pour cela que le défaut est passé. Vérifié : en
revenant au rect de fragment, quatre assertions repassent au rouge.

**La vérification à l'écran n'a pas eu lieu.** L'application n'a pas été
lancée, aucun rendu n'a été observé. Tout ce chantier repose sur des mesures
de mise en page. Contrôles restants à l'écran : les deux blocs mermaid
encadrant un bloc ouvert, un bloc en tête de note, un source invalide (cadre
d'erreur dans la bande), la frappe longue dans un bloc ouvert sans
superposition, le clic sur « Terminé », le redimensionnement de fenêtre bloc
ouvert, la densité générale d'une note enchaînant plusieurs cartes, et le
confort de lecture d'un diagramme réduit au plafond de 240 pt.

**Superposition carte/source pendant l'édition — cause racine trouvée et
corrigée (2026-08-08).** Constat d'écran : la carte rendue (ou le cadre
d'erreur « Parse error ») se peignait par-dessus/sous le source ouvert
pendant la frappe, sans laisser le temps de cliquer « Terminé ». Mécanisme
mesuré : chaque frappe dans un bloc ouvert relançait un rendu du source
**incomplet** (le natif strict jette → `WKWebView` à chaque caractère) et
chaque completion en vol rejouait `refreshClosedMermaidGeometry` avec une
plage **capturée au lancement** — périmée dès que le bloc avait grandi, la
garde « bloc encore ouvert ? » échouait et la géométrie fermée s'appliquait
sur le bloc en édition. Double correctif :

1. `StyleRenderer.applyMermaidAttachment` ne crée plus d'attachment ni ne
   lance de rendu tant que le bloc est ouvert — l'attachment existant est
   reposé tel quel (même instance, run uniforme) et le rendu du source
   final part à la fermeture ;
2. `refreshClosedMermaidGeometry` retrouve le bloc par l'**identité** de
   son attachment au moment où le rendu aboutit (attachment absent = rendu
   périmé, no-op) — plus jamais par une plage figée.

Trois tests de régression dans `StyleRendererMermaidTests` (identité de
l'attachment pendant l'édition, completion périmée après croissance du
bloc, attachment remplacé). L'effacement visuel de l'ancienne carte doit
encore être confirmé à l'écran après relance complète de l'application.

### Tableaux

`/tableau` insère une grille de trois colonnes, une rangée d'en-tête et deux
rangées de corps. Les libellés `Colonne 1`, `Colonne 2`, `Colonne 3` sont des
placeholders visuels et ne sont pas sérialisés.

Fonctions disponibles :

- grille `NSTextTable` à colonnes fixes et cellules de hauteur stable ;
- curseur placé dans la première cellule ;
- ajout d'une ligne sous la ligne active ;
- suppression de la ligne active ; si l'en-tête est sélectionné, suppression
  de la dernière ligne de corps ;
- ajout d'une colonne à gauche ou à droite ;
- suppression d'une colonne avec garde sur la dernière colonne ;
- permutation de lignes et colonnes avec annulation/rétablissement ;
- barre de pied `+` / `-`, compteur lignes/colonnes et action d'ajout de
  colonne ;
- menu de colonne depuis l'en-tête.

Le tri ascendant et descendant apparaît dans le menu, mais reste un `TODO`
dans `EditorTextView`.

En lecture seule (`.markdownReadOnly(true)`), les contrôles de tableau sont
entièrement inertes : `activeTableInView` (point d'entrée partagé
dessin/interaction) refuse un éditeur non éditable — ni pied `+`/`−`, ni
menu de colonne — et `keyDown` écarte les raccourcis ⌘⌥/⌘⌥⇧/⌘⌥⌃ + flèche
avant d'atteindre les handlers (P2 revue Codex).

### Manipulation des blocs

La gouttière gauche appartient désormais au bloc et ne recouvre plus ses
contrôles internes.

Implémenté dans le worktree :

- apparition au survol des boutons d'insertion et de poignée ;
- clic sur `+` : insertion d'une ligne `/` au-dessus du bloc ;
- clic sur la poignée : sélection du bloc et menu contextuel ;
- menu Monter, Descendre, Dupliquer, Modifier le source et Supprimer ;
- clic droit routé par le menu contextuel natif AppKit, ancré au point du
  clic même lorsque l'éditeur est décalé dans sa fenêtre ;
- déplacement clavier avec `⌥↑` / `⌥↓` ;
- glisser-déposer avec bloc atténué et trait bleu entre les blocs ;
- cadre bleu distinct de la sélection textuelle.
- espacement vertical de 10 pt à la fin de chaque bloc logique, porté à 28 pt
  (`BlockGutterLayout.cardBlockSpacing`) dès qu'un des deux blocs voisins dessine
  un cadre — mermaid, tableau, image, bloc de code. Seul `paragraphSpacing` le
  porte : y ajouter `paragraphSpacingBefore` doublerait l'écart, TextKit
  additionnant les deux.

Correctifs issus de la revue Codex du 2026-08-08 (P1) :

- la réécriture du glisser-déposer est extraite en fonction pure
  (`BlockMoveCommands.dragRewrite`) qui normalise le séparateur : déplacer
  le **dernier** bloc (sans `\n` final) ou déposer **en fin** de document
  ne colle plus deux blocs sur la même ligne (`"A\nB"` → `"BA\n"`, corrigé
  et couvert par 5 tests) ;
- le constat « pas d'undo sur les mutations de bloc » est **réfuté par
  l'expérience** : le bracket `shouldChangeText`(remplacement non
  nil)/`didChangeText` avec `allowsUndo` enregistre nativement l'inverse
  **attribué** (`md*` compris) — suppression, duplication, insertion `/` et
  drag avaient déjà un ⌘Z fonctionnel. Mesuré et verrouillé par
  `EditorTextViewBlockMutationUndoTests` (6 tests) ; le patron est
  centralisé dans `EditorTextView.replaceBlockCharactersRegisteringUndo`,
  dont la doc explique pourquoi il ne faut **pas** ajouter de
  `registerUndo` manuel par-dessus (inverse enregistré en double, mesuré).
  `swapAdjacentBlocks`/`applyTaskToggle` restent des cas différents : ils
  n'appellent pas le bracket.

Correctifs P2 de la même revue (lecture seule) :

- clic droit : menu natif d'AppKit, jamais le menu de bloc mutable ;
- gouttière : `blockGutterHit` refuse un éditeur non éditable (poignée `⠿`
  et `+` inertes) et le survol ne peint plus les affordances d'édition ;
- `BlockMoveCommands.moveUp/moveDown` portent la garde d'éditabilité
  (couvre ⌥↑/⌥↓ **et** Monter/Descendre du menu, qui mutent sans bracket
  `shouldChangeText`).

Côté images (P2) : `ImageAttachmentFactory.maxWidth` revient à **480 pt**
(limite des images ordinaires, jamais réajustées au conteneur par TextKit)
et la colonne mermaid a sa propre constante
`MermaidBlockLayout.columnWidth = 960` consommée par
`MermaidAttachmentFactory` — le passage global à 960 clippait les images
dans les éditeurs de 300–600 pt et cassait
`ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
(reverdi par ce découplage).

Le déplacement clavier est couvert par les tests existants. Le glisser-déposer
réel et le menu de bloc doivent encore être vérifiés dans une fenêtre AppKit,
notamment le dépôt après le dernier bloc et la conservation de la sélection.

## Fonctions Markdown déjà livrées

| Fonction | État |
|---|---|
| Menu `/` | 17 commandes, panneau limité à huit lignes visibles |
| Raccourcis à la frappe | `# `, `- `, `1. `, `> `, `[] `, `---` |
| Listes | marqueurs, cases cliquables, ⏎, Tab, ⇧Tab et ⌫ |
| Mentions `@` | recherche, création et ouverture de la fiche |
| Citations | filet vertical |
| Images | affichage, collage et déplacement |
| Liens | liens externes et routage interne injecté |
| Dates | popover avec date et heure |
| Blocs | sélection, menu, clavier et drag en cours de validation |

L'aller-retour Markdown a été vérifié auparavant sur 119 notes réelles,
sauvegardées dans `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`.

## Validation du 2026-08-08

Commandes passées sur le code actuel :

- `swift build` : **réussi** ;
- vérification ad hoc temporaire : **code de sortie 0**, script supprimé
  automatiquement ;
- `swift test --filter MermaidBlockLayoutTests/test_openSelectionLocation_atExclusiveEnd_isMovedBackInsideBlock` :
  **1 test, 0 échec** ;
- `swift test --filter MermaidSourceLayoutTests` : **8 tests, 0 échec** ;
- `swift test --filter Mermaid` : **82 tests, 0 échec** ;
- `swift test --filter Mermaid` après intégration native : **88 tests,
  0 échec**, dont 3 scénarios d'édition sans perte et le rendu bitmap natif ;
- `swift test --filter EditorTextViewMermaidClickTests` : **11 tests,
  0 échec** ;
- `swift test --filter SlashControllerTests` : **81 tests, 0 échec**, dont
  le nouveau test du squelette `/diagramme` ;
- `swift test --filter BlockGutterLayoutTests` : **4 tests, 0 échec**, dont
  le menu contextuel dans une fenêtre décalée ;
- `swift test --filter BlockGutterLayoutTests --filter StyleRendererTests
  --filter MarkdownTableRenderingTests --filter TableControlLayoutTests
  --filter SlashControllerTests` : **158 tests, 0 échec** ;
- capture native générée et inspectée : orientation corrigée, « Début » au-
  dessus de « Fin », flèche descendante, texte lisible ;
- `BuiltInTemplatesTests` : **4 tests, 0 échec** lorsqu'ils sont lancés avec
  la suite Slash.

Prochaine action : vérifier visuellement dans l'application la visibilité de
l'en-tête du second bloc et le clic sur le dernier caractère sans passage au
rendu ; « Terminé » doit rester l'action explicite.

## Validation du 2026-08-08 (correctifs P1 revue Codex)

- `swift test --filter Mermaid --filter BlockMoveCommandsTests
  --filter BlockGutterLayoutTests --filter EditorTextViewBlockMutationUndoTests` :
  **139 tests, 0 échec** (dont 5 `dragRewrite`, 6 undo, 7 parseurs stricts,
  4 `openBlockRange`, 2 `doneCaretPlacement`) ;
- balayage éditeur large (`SlashControllerTests`, `StyleRendererTests`,
  `TableControlLayoutTests`, `TableEditCommandsTests`,
  `MarkdownTableRenderingTests`, `ListEditingCommandsTests`,
  `EditorTextView*`, `EditorRepresentable*`, `BlockRangeTests`) :
  **312 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : la partie Swift Testing
  passe (**138 tests, 24 suites**) et, contrairement au constat précédent,
  l'exécution globale XCTest est allée au bout (pas de signal 6) avec
  **2 échecs préexistants étrangers aux correctifs** :
  `ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
  (échec introduit par le changement **non commité** de `maxWidth` dans
  `ImageAttachmentFactory.swift` — vérifié : le test passe sur HEAD une
  fois le worktree remisé) et `MenuBarStatsTests.test_badge_twelve_compact`
  (test de barre de menu dépendant de l'heure, limite déjà connue).

## Validation du 2026-08-08 (correctifs P2 revue Codex)

- suites lecture seule et largeurs (`TableControlLayoutTests`,
  `TableEditCommandsTests`, `BlockGutterLayoutTests`,
  `BlockMoveCommandsTests`, `MermaidAttachmentFactoryTests`,
  `ImageAttachmentFactoryTests`, `StyleRendererTests`) : **0 échec**, dont
  6 nouveaux tests lecture seule et le `test_scaledHeight` reverdi ;
- balayage éditeur large (mêmes suites que la validation P1) :
  **325 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : exécution globale au bout,
  **un seul échec restant**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, limite connue hors chantier).

Séparation du hunk de migration (P2) : le retrait du
`OneToOneMigrationPlan` explicite dans `OneToOneApp.swift` reste dans le
worktree mais ne doit **pas** partir avec la PR éditeur — au moment du
commit, exclure `OneToOneApp.swift` (et le porter ensuite sur une branche
dédiée, ex. `git stash push -- OneToOne/OneToOneApp.swift` puis pop sur la
nouvelle branche). Une PR = une intention.

Prochaine action : vérifier en fenêtre réelle le nouveau geste « Terminé »
(curseur au-delà du séparateur, insertion du `\n` en fin de document), la
frappe en fin de source d'un bloc ouvert, et l'apparence d'une note en
lecture seule (aucune affordance de bloc/tableau) ; puis découper les
commits de la branche en excluant `OneToOneApp.swift`.

Correctif superposition/rendu en cours de frappe : validé par
`StyleRendererMermaidTests` (17 tests) et un balayage éditeur de 311 tests,
0 échec ; app dev reconstruite et installée (build 573) pour vérification à
l'écran du scénario exact (frappe longue dans un bloc ouvert, puis
« Terminé »).

Dernière mise à jour : 2026-08-08 09:14 CEST.

La commande globale `swift test` ne fournit pas actuellement un verdict
exploitable : le processus `xctest` termine avec le signal 6 pendant
l'exécution globale, sans assertion en échec dans les suites de l'éditeur.
Le phénomène est reproductible hors sandbox. Les suites voisines
`BuiltInTemplatesTests`, `SlashControllerTests` et toutes les suites Mermaid
passent lorsqu'elles sont lancées séparément.

Autres limites historiques du harnais :

- `CalendarImportEventTests` peut planter dans l'environnement de test
  (`bundleProxyForCurrentProcess is nil`) ;
- `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` dépend de l'heure :
  il place un créneau entre +2 h et +3 h après minuit et échoue donc si la suite
  est lancée entre minuit et 3 h du matin ;
- `MenuBarStatsTests.test_badge_twelve_compact` **a été supprimé le 2026-08-09**.
  Il était décrit ici comme dépendant de l'heure : c'était faux. Il affirmait
  `" ●12"` pour `hasOverdue: true`, alors que `MenubarBadgeText.suffix` rend
  volontairement `" ⚠12"` — son commentaire de code documente ce choix. Attente
  périmée, pas problème d'horloge. Conséquence à connaître : le glyphe `⚠` du cas
  « au moins une action en retard » n'a plus aucun test ;
- un test de montage de transcription est intermittent.

## Validation du 2026-08-08 (tâche 6 — aération des blocs-cartes et aperçu figé du bloc mermaid ouvert)

- `swift test --skip CalendarImportEventTests` : suite Swift Testing —
  **138 tests, 24 suites, 0 échec** ; suite XCTest — **940 tests, 1 test
  ignoré, 1 seul échec**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, préexistant, déjà documenté ci-dessus). Aucune
  régression du chantier.

**Étape 2 (`Scripts/bump-and-build.sh dev`) et étape 3 (vérification à
l'écran) n'ont pas été exécutées dans cette session** : elles demandent une
session graphique et un œil humain. Le chantier n'est donc **pas** validé
visuellement. Reste à faire, dans une note contenant, dans l'ordre, un
paragraphe, un bloc mermaid valide, un second bloc mermaid valide, un
tableau, après rendu des deux diagrammes puis clic dans le source du
**second** bloc :

1. les deux cartes rendues et le tableau sont nettement séparés (28 pt) ;
   deux paragraphes de texte restent serrés ;
2. le bloc ouvert affiche, dans son propre cadre : en-tête `mermaid` +
   « Terminé » en haut, puis son diagramme, puis un filet, puis le source
   numéroté ;
3. l'en-tête ne touche plus le cadre du bloc précédent ;
4. frapper plusieurs caractères dans le source : l'aperçu ne bouge pas et
   aucune carte ne se superpose au source ;
5. cliquer « Terminé » : le bloc se referme et le diagramme se met à jour ;
6. répéter avec un bloc mermaid placé en tout début de document ;
7. répéter avec un source volontairement invalide (`flowchart TD` puis
   `((((`) : le cadre d'erreur doit s'afficher dans la bande d'aperçu ;
8. redimensionner la fenêtre pendant qu'un bloc est ouvert et noter le
   comportement (limite connue ci-dessus).

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener les huit contrôles ci-dessus à
l'écran.

Dernière mise à jour : 2026-08-08 11:49 CEST.

## Validation du 2026-08-08 (revue finale — cause racine de la bande réservée)

Une revue finale a jugé le chantier non fusionnable et trouvé la cause
racine décrite dans « Diagrammes Mermaid » ci-dessus. Six correctifs
(`1ea10a4`, `c009c64`, `72a4bd6`, `b5aa506`, `96c1119`, `8d88197`), tous
relus.

- `swift test --skip CalendarImportEventTests` : **957 tests exécutés, 1
  ignoré, 1 seul échec** — `MenuBarStatsTests.test_badge_twelve_compact`,
  préexistant et dépendant de l'heure (documenté plus haut) ;
- `swift build -c release` : **réussi**.

**La vérification à l'écran n'a toujours pas eu lieu.** Elle reste entière,
avec les huit contrôles listés dans la section « Validation du 2026-08-08
(tâche 6) » ci-dessus, complétés par : la frappe longue dans un bloc ouvert
sans superposition, le clic sur « Terminé », et la densité générale d'une
note enchaînant plusieurs cartes.

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener à l'écran, dans l'ordre, les
huit contrôles de la section « tâche 6 » et les trois contrôles ajoutés
ci-dessus. C'est la seule chose qui manque avant de considérer ce chantier
fusionnable ; tout le reste (géométrie, tests, build release) est déjà
vérifié.

Dernière mise à jour : 2026-08-08 16:32 CEST.

## Dette immédiate

1. Vérifier à l'écran, après relance, le scénario exact de la dernière
   capture : carte d'erreur, clic sur « Ouvrir le source », disparition de la
   carte et édition du source.
2. Tester le glisser-déposer réel de blocs dans une `NSWindow`, y compris les
   première et dernière positions.
3. Implémenter ou retirer les commandes de tri du menu de colonne.
4. Ajouter les tests manquants de `/sommaire` : document sans titre, doublons,
   niveaux, aller-retour et héritage des attributs de frappe.
5. Stabiliser l'exécution globale XCTest + Swift Testing avant de considérer
   la suite complète comme verte.
6. Tester les diagrammes Mermaid hors des six familles natives (ou utilisant
   HTML, callbacks, tooltips et styles avancés) pour confirmer visuellement
   le fallback JavaScript sur un corpus de notes réelles.

## Défauts connus hors chantier

- le rappel choisi dans le popover de date n'est pas encore persisté ni
  déclenché ;
- mentions et dates utilisent encore largement le rendu des liens ordinaires ;
- `InlineHTML` n'est pas pris en charge par le parser ;
- l'emphase imbriquée complexe ne fait pas toujours un aller-retour strict ;
- le dépôt « à droite pour créer des colonnes de blocs » n'a pas d'équivalent
  Markdown et n'est pas prévu ;
- la poignée de gouttière d'un bloc mermaid **ouvert** s'aligne sur la première
  ligne de source, donc à côté du source et non en haut du cadre : elle se cale
  sur les rects de ligne, et la bande en-tête/aperçu vit dans l'espacement de
  paragraphe, hors ligne ;
- la hauteur réservée à la bande d'aperçu est calculée avec la largeur de colonne
  connue **au moment du stylage** : redimensionner la fenêtre pendant qu'un bloc
  est ouvert peut laisser un léger vide (ou un léger recouvrement) sous l'aperçu
  jusqu'au prochain restylage du bloc.

Issus des six correctifs de la revue finale (2026-08-08) :

- `MainActor.assumeIsolated` **élargi** : l'assertion d'isolation s'exécute
  désormais à chaque restylage ciblé, non plus seulement quand un bloc
  mermaid figure dans la plage. Aucun appelant actuel n'est hors fil
  principal, mais la surface d'exposition a grandi ;
- coût du restylage étendu : chaque frappe restyle aussi le bloc précédent.
  Sous un tableau, cela reconstruit son `NSTextTable` ; sous un bloc mermaid
  fermé, cela re-pose l'attachment. Le cache d'attachments évite le rendu,
  sauf éviction du `NSCache` — auquel cas un rendu peut repartir, pour un
  bloc **fermé** uniquement ;
- couverture : le cas tableau de l'écart sous une carte n'a pas de test de
  garde, et la symétrie 28/28 est prouvée en deux morceaux dont l'un pose la
  valeur à la main ;
- état mixte au chargement : ouvrir une note qui se termine par un bloc
  mermaid le style « fermé » alors que le curseur le touche. Antérieur à ce
  chantier ; l'effet net des correctifs y est positif (la bande est enfin
  réservée), mais l'état mérite un passage.

## Décisions structurantes

1. ~~Le Markdown reste la source de vérité ; aucun modèle de blocs persistant
   séparé n'est introduit.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
2. ~~TextKit 1 est conservé. Les marqueurs de liste et les contrôles sont
   dessinés par les composants AppKit existants.~~ **Annulée le 2026-08-08**
   par [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
3. Les couleurs libres ne sont pas sérialisées : pas de HTML inline ajouté
   uniquement pour la présentation.
4. ~~Aucun code AppFlowy n'est repris ; la référence sert uniquement au design
   et aux comportements.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
5. Les liens internes restent routés par une closure injectée dans l'éditeur.
6. BeautifulMermaidSwift est vendored comme cible SwiftPM locale afin de
   permettre les correctifs macOS et l'évolution du style dans ce dépôt ;
   ELK Swift reste une dépendance distante verrouillée en 1.0.2.
