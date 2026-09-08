# Lot 4 — Mode séance plein écran (écran 1b)

**Branche :** `feat/refonte-lot-4-mode-seance`, sur `feat/refonte-lot-3-rail-actions`.
**Capture qui fait foi :** `docs/superpowers/specs/refonte-2026-09/ecrans/1b-mode-seance.png`.
**Spec :** §2.6 (mode séance), §1.2 (jetons `dark/*`), §1.4 (`⌘M`, `⌘K`, `⌘⇧A`).
**Programme :** §5 « Lot 4 », §7 (protocole), §8 (risques).

## Ce que la capture impose

Grille `78 | 1fr | 400`, palette sombre, **aucun chrome** hors la barre d'état :

| Zone | Contenu |
| --- | --- |
| Barre d'état | `● En séance · P25_110` · `18:42 / 23:24` mono · avatars `PY NL CP LS CA LD` · `CP parle` · `Clore la séance` (plein `accent/report`) |
| Colonne TEMPS 78 px | libellé `TEMPS`, axe 3 px (écoulé `#e04b3f`), ronds `dark/accent action` = notes, carré r3 `accent/report` = décision, trait `dark/ink` = position, libellés mono à 30 px du rail, `⊕ Marquer ⌘M` en pied |
| Colonne NOTES 1fr | `NOTES  enregistrement auto · liées au temps`, lignes `mm:ss \| texte`, bloc `DÉCISION` (barre rouge + libellé mono), mention `@Yann` en pilule, composeur avec `/action /décision /risque /citer` ; bandeau bas `EN ATTENTE  n actions sans responsable` + `Assigner maintenant` |
| Colonne droite 400 px | `TRANSCRIPTION LIVE` + `Suivre`, segment actif encadré (`＋ Action` `Décision` `Citer` `⌘⇧A`), `✳ ASSISTANT ⌘K` (question gras, réponse, puces de sources horodatées), champ `Poser une question…`, `CAPTURÉ CETTE SÉANCE` : `4 ACTIONS · 1 DÉCISION · 2 RISQUES` |

## Décisions de ce lot

- **D4.1 — Le marqueur `⌘M` est une `MeetingNote(kind: .note, text: "")`.** Une note vide
  n'apparaît pas dans la colonne (elle est filtrée à l'affichage) mais **porte un repère**
  sur l'axe temps via `MeetingTimelineMarkers`, qui lit déjà `meeting.timedNotes`. Un type
  « marqueur pur » de plus aurait exigé une colonne, une migration et un second chemin de
  repère pour le même besoin.
- **D4.2 — Présentation par substitution du `contentView` de la fenêtre courante.**
  `SessionFullscreenPresenter` retient l'ancien `contentView`, installe un
  `NSHostingView(SessionFullscreenView)`, appelle `NSWindow.toggleFullScreen`, et restaure
  à la sortie. Pas de `WindowGroup` de plus (le chrome de `MeetingView` resterait visible
  avec un simple `overlay`, ce que la spec §2.6 interdit).
- **D4.3 — L'entrée passe par un présentateur partagé, pas par un `@Binding` de plus.**
  La pilule audio de `MeetingTopChromeBar` n'a pas accès au `MeetingScreenModel` ; le
  présentateur est `@Observable` et sert de rendez-vous entre la pilule (qui demande) et le
  modificateur posé sur `MeetingSpaceView` (qui héberge). `MeetingView` n'est pas touché.
- **D4.4 — Le locuteur courant vient des segments résolus, pas d'un signal live.**
  `LiveTranscriptionService` ne publie aucun locuteur (la diarisation est *batch*,
  `LiveDiarizationAligner` s'exécute après le `stop()`). `SessionCurrentSpeaker` cherche donc
  le segment qui couvre `t` et dont le `speaker` est résolu ; sans lui, la mention est
  **masquée** (spec §2.6 : « locuteur courant … sinon masqué »).
- **D4.5 — Les composants du lot 2 lisent le thème, ils ne le choisissent pas.**
  `TimedNotesColumn`, `NoteComposer`, `TranscriptColumn`, `Chip` et `sectionLabel()`
  remplacent leurs `One2OneToken.*` par `theme.colors.*`. En `.paper`, les valeurs résolues
  sont **identiques** : le rendu clair ne change pas. `One2OneColors` gagne les champs
  qui manquaient (`surfaceAlt`, `strongBorder`, `inkMuted`, `actionInk`, `actionBg`,
  `reportInk`, `warnInk`).

## Carte des fichiers

**Créés — `OneToOne/Views/Meeting/Session/`**
`SessionFullscreenState.swift`, `SessionFullscreenPresenter.swift`, `SessionFullscreenView.swift`,
`SessionStatusBar.swift`, `TimeRailColumn.swift`, `SessionNotesColumn.swift`,
`SessionAssistantPanel.swift`, `SessionCapturedSummary.swift`, `AssignmentQueueSheet.swift`,
`SessionCurrentSpeaker.swift`, `SessionMentionRuns.swift`, `MeetingAssistantController.swift`.

**Créés — services purs**
`OneToOne/Services/Meeting/TimeRailGeometry.swift`, `OneToOne/Services/Meeting/AssignmentQueue.swift`.

**Modifiés (au strict minimum)**
`One2OneTokens.swift` (+`railElapsed` `#e04b3f`), `One2OneTheme.swift` (champs manquants),
`One2OneTypography.swift` (`sectionLabel()` thématique), `Components/Refonte/Chip.swift`,
`Notes/TimedNotesColumn.swift`, `Notes/NoteComposer.swift`, `Transcript/TranscriptColumn.swift`,
`MeetingScreenModel.swift` (**une ligne**), `MeetingSpaceView.swift` (**un modificateur**),
`MeetingTopChromeBar.swift` (**la pilule audio seule**), `MeetingMenuActions.swift`,
`MeetingCommands.swift`, `MeetingChatView.swift` (délégation du prompt au contrôleur).

## Tâches (TDD : test d'abord)

1. **`TimeRailGeometry`** — `y(t:)`, `elapsedHeight(t:)`, `labels(markers:)`, formes par
   nature, épaisseurs, offset 30 px. Tests : positions bornées (durée nulle, `t > durée`),
   libellés dans l'ordre, aucune division par zéro.
2. **`AssignmentQueue`** — file pure : `Etape { responsable, echeance }`, `avance()`,
   `suivante()`, `sortie()`, `estTerminee`. Tests : ordre responsable → échéance →
   suivante, trois gestes par action, file vide, `Esc` sort à n'importe quelle étape.
3. **`SessionCapturedSummary`** — compteurs depuis `debutDeSeance`. Tests : une action créée
   avant le début n'est pas comptée, une note `decision` l'est, un risque non résolu l'est.
4. **`SessionCurrentSpeaker`** — initiales + libellé `CP parle`, `nil` hors segment.
5. **`SessionMentionRuns`** — découpage texte / mention, `@Yann` reconnu, `@inconnu` non.
6. **`SessionExitPolicy`** — machine à états pure : `Esc` demande confirmation si et
   seulement si l'enregistrement tourne.
7. **Jetons et thème** — `railElapsed`, champs de `One2OneColors`, `Chip` et
   `sectionLabel()` thématiques. Test : le thème `.paper` résout les mêmes couleurs qu'avant.
8. **Vues** — barre d'état, colonne temps, colonne notes, colonne droite, bandeau,
   `AssignmentQueueSheet`, assemblage `SessionFullscreenView`.
9. **Assistant** — `MeetingAssistantController` (envoi + sources horodatées), branchement
   `MeetingChatView` sur ses fonctions pures, `SessionAssistantPanel`.
10. **Entrée/sortie** — présentateur, pilule audio, `⌃⌘F` dans `MeetingCommands`,
    `screen.session`. Tests : `MeetingMenuActions.isEnabled(.sessionFullscreen)`.
11. **Test de non-chrome** — lecture des sources de `Session/` : aucun `MeetingSpacesBar`,
    aucun `MeetingKPIBand`, aucune couleur nommée hors `One2OneToken`.
12. **`swift test` complet**, recette, `STATUS.md`, PR.
