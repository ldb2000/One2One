# Teams auto-record & popup — Design spec

**Date** : 2026-08-28
**Branche** : `feat/teams-autorecord-popup` (à créer à l'implémentation)
**Spec de référence** : [`2026-05-12-calendar-teams-integration-design.md`](2026-05-12-calendar-teams-integration-design.md) (v1, approuvée)
**Auteur** : laurent.deberti
**Statut** : v2.1 — amendée le 2026-08-28 après vérification dans le code.
Journal des amendements en §15.

## 0. Résumé

Quand l'utilisateur rejoint un appel Microsoft Teams, OneToOne lui propose
automatiquement, via une notification système macOS, de créer une réunion
OneToOne pré-remplie (titre, type, interlocuteurs depuis l'événement
calendrier EventKit), de l'ouvrir et de démarrer la capture micro + audio
système + transcription STT Whisper + diarisation on-device. Pendant
l'enregistrement, l'icône de menu bar passe en rouge (pulse). À la fin de
l'appel Teams, un popup propose d'arrêter et de finaliser la transcription ;
une fois la transcription finalisée, un autre popup propose de générer un
rapport via le provider IA configuré. Le rapport emprunte le chemin
existant (`AIReportService`), au même titre qu'une réunion enregistrée
à la main.

Cette spec **réutilise intégralement** les fondations calendrier / Teams de
la spec v1 (EventKit, `CalendarMeetingImportService`, `ProjectMatchService`,
`MeetingNotificationService`, `MenuBarController`, `TeamsLauncher`) et
**annule trois décisions v1** documentées au §17 (« out of scope future
work »). Voir §2.

## 1. Goals & non-goals

### Goals v2

1. Détecter qu'un appel Teams est en cours, sans API Microsoft — trois
   déclencheurs locaux convergents (§3).
2. Faire correspondre cet appel à un événement EventKit à ±2 min.
3. Proposer un popup système `UNUserNotificationCenter` qui, à l'acceptation,
   crée une réunion OneToOne liée à l'événement, ouvre sa fenêtre, démarre
   la capture micro + audio système + STT Whisper MLX + diarisation.
4. Pendant l'enregistrement, signaler visuellement via l'icône de menu bar
   (rouge + pulse).
5. Détecter la fin de l'appel Teams → popup « Arrêter et finaliser la
   transcription » → à la fin, popup « Générer le rapport ».
6. Le rapport est produit par `AIReportService`, avec le provider IA
   configuré (`DirectLLM`/`Ollama`/`OpenAI`) et le `ReportTemplate` par
   défaut du `kind` de la réunion.

### Non-goals v2 (explicites)

- L'auto-record est **opt-out par réunion** (refus du popup) mais **pas
  opt-out global** en v2. Pas de réglage pour désactiver entièrement
  l'intégration. C'est un choix à confirmer en usage et à proposer en v3.
- L'audio système capturé est l'audio sortant de Teams
  (`SCStream.captureAudio`). Pas d'enregistrement multi-fenêtres, pas de
  routage inter-applications.
- Pas de transcription d'un meeting Teams terminé *après coup* (lecture d'un
  `.mp4` exporté Teams). Le STT n'opère que sur les flux capturés en direct.
- Pas de capture d'écran de Teams.
- Pas d'intégration au chat Teams (lecture/envoi de messages).
- Pas d'appel sortant via Teams (`TeamsLauncher` reste pour rejoindre
  manuellement, comme dans la spec v1).
- Pas de balayage périodique des fenêtres. L'énumération
  `SCShareableContent` n'est consultée que si la permission
  d'enregistrement d'écran est **déjà** accordée ; sans elle, la
  surveillance se limite au premier plan. Voir §3.

## 2. Décisions (et rapport à la spec v1)

### Décisions héritées de la spec v1

| Ref v1 | Décision | Conséquence v2 |
|---|---|---|
| T-A | Pas de MS Graph | Maintenu. Détection purement locale. |
| N-A | Notifications système uniquement | **Annulé** : on garde les notifications, on n'ajoute pas de popup flottant custom, mais on autorise un parcours auto-record déclenché par surveillance locale. |
| R-A | Pas d'auto-record | **Annulé** : auto-record par défaut, opt-out par refus du popup. |
| D-D | Agenda trailing inspector | Maintenu. |
| S-A | Stats sur `effectiveDuration` | Maintenu. |
| §7 | `NSStatusItem` avec prochain meeting | Maintenu et étendu (état `RECORDING`). |

### Décisions nouvelles v2

| Ref v2 | Décision | Valeur |
|---|---|---|
| D-1 | Surveillance Teams | Trois déclencheurs convergents : `NSWorkspace` + titre, clic « Rejoindre Teams », horloge calendrier (voir §3) |
| D-2 | Tolérance de correspondance EventKit | `±2 min` autour du `startDate` |
| D-3 | Forme du popup | `UNUserNotificationCenter` avec boutons d'action |
| D-4 | Permissions notifications | Demande au premier lancement, onboarding |
| D-5 | Source audio | Micro interne + SystemAudio Teams, deux pistes |
| D-6 | Fallback SystemAudio | Bandeau d'erreur non bloquant, micro seul |
| D-7 | STT/diarisation | Whisper MLX sur flux mixé ; provenance « moi » / « distant » par chronologie d'énergie, pas par diarisation (voir §6.1) |
| D-8 | Rapport IA | **Annulée** : pas de section dédiée. `AIReportService` écrit dans les champs de rapport existants, déjà modifiables |
| D-9 | Provider IA obligatoire | Si absent, la fonctionnalité rapport est désactivée et la popup l'indique |
| D-10 | Concurrence | Si une réunion est en cours d'édition, proposer de lier au lieu de créer |
| D-11 | Détection Teams en arrière-plan | Oui si la permission écran est déjà accordée ; dégradé au premier plan sinon |

### Faux positifs / faux négatifs documentés (D-1)

Voir §3.

## 3. Surveillance locale de Teams

### Trois déclencheurs, une seule machine à états

`callStarted` peut être émis par trois sources indépendantes qui
alimentent la même machine à états. Le cooldown de 30 s et
`lastMatchedEventID` décrits plus bas les dédoublonnent — le mécanisme
existe déjà, il sert simplement trois sources au lieu d'une.

1. **Surveillance `NSWorkspace`** — l'heuristique décrite ci-dessous.
   Couvre le cas où l'utilisateur rejoint depuis Teams sans passer par
   OneToOne. C'est la source la moins fiable, et la seule qui puisse
   produire un faux positif.
2. **Clic « Rejoindre Teams »** — `TeamsLauncher.open` est déjà le point
   de passage unique de l'action `JOIN_TEAMS` d'une notification et de
   l'entrée correspondante du menu bar. L'utilisateur a explicitement
   rejoint un événement connu : zéro faux positif, et l'événement EventKit
   étant déjà identifié, l'appariement de §3 est court-circuité.
3. **Horloge calendrier** — la notification `MEETING_START` que
   `MeetingNotificationService.schedule` programme déjà pour toute réunion
   ayant un `scheduledStart`. Couvre le cas où Teams est ouvert avant
   l'heure, ou n'est jamais mis au premier plan.

Seule la source 1 demande du code d'observation nouveau. Les sources 2 et
3 sont des points d'émission greffés sur du code existant.

### Ce qu'on observe (source 1)

- `NSWorkspace.didActivateApplicationNotification`
- `NSWorkspace.didDeactivateApplicationNotification`
- `NSWorkspace.didLaunchApplicationNotification`
- `NSWorkspace.didTerminateApplicationNotification`
- Titre de la fenêtre key de Teams (`NSWorkspace.frontmostApplication`)
- `SCShareableContent.current`, **uniquement si**
  `CGPreflightScreenCaptureAccess()` répond déjà vrai. Le preflight ne
  déclenche aucune demande de permission. L'énumération donne le titre et
  l'app propriétaire de toutes les fenêtres, arrière-plan compris, ce qui
  lève la restriction « Teams au premier plan ». `ScreenCaptureConfigView`
  utilise déjà cette API.

### Ce qu'on ne peut PAS observer sans API Microsoft

- Si Teams est en train de passer un appel (vs simplement avoir la fenêtre
  ouverte).
- Si l'utilisateur est en sourdine.
- Le nombre de participants.
- L'état de la caméra.

### Heuristique « appel actif »

On considère qu'il y a un appel actif si toutes ces conditions sont réunies :

1. Une fenêtre Teams (`com.microsoft.teams` ou `com.microsoft.teams2`)
   est au premier plan — ou, si l'énumération `SCShareableContent` est
   disponible, existe quelque part.
2. Son titre contient l'un des motifs
   `/\b(call|meeting|appel|réunion|conference|meet|visio)\b/i`
   (français et anglais). Cette liste reste **en dur** dans le code :
   voir §14 Q12.
3. La condition tient depuis au moins 5 secondes consécutives
   (anti-faux-positif sur un simple clic).

### Cooldown et déduplication

- `callStarted` n'est émis qu'après 5 s d'état stable.
- Deux `callStarted` à moins de 30 s d'écart sont fusionnés.
- `callEnded` n'est émis qu'après 30 s pendant lesquelles Teams n'est plus
  au premier plan ou le titre ne match plus.
- Un `lastMatchedEventID` empêche le re-popup si le même appel est détecté
  à nouveau.

### Faux positifs connus (documentés)

- Teams ouvert sur la liste des chats, un titre de chat contient « meeting »
  → mitigation : 5 s + 30 s.
- Un event Teams planifié dans 10 min, l'utilisateur ouvre Teams en avance
  → mitigation : `TeamsCallMatchService` ne déclenche le popup que si un
  event EventKit a un `startDate` dans `±2 min`.

### Faux négatifs connus (documentés)

- Teams en arrière-plan pendant tout l'appel **et** permission écran pas
  encore accordée → la source 1 ne voit rien. Les sources 2 et 3 restent
  opérantes. Dès le premier enregistrement à deux pistes la permission est
  acquise, et le cas disparaît de lui-même.
- Teams Web (Safari/Chrome) au lieu de Teams Desktop → non détecté
  (non-goal explicite).
- Mode « picture-in-picture » Teams → détecté (la fenêtre reste key).
  Comportement souhaité.

### Philosophie

Pas de popup **vaut mieux qu'un faux positif**. Un popup non sollicité qui
crée une réunion OneToOne et démarre un enregistrement est coûteux (bruit
micro, dérangement, nettoyage à faire). Les seuils de cette section sont
à la hausse par défaut ; les abaisser est une décision à prendre après
usage réel.

### Implémentation

`TeamsCallMonitor` est un `NSObject` qui s'inscrit aux notifications
`NSWorkspace` au démarrage et les désinscrit au shutdown. Il maintient un
état interne :

```swift
struct TeamsCallState {
    enum Phase { case idle, observing, stable, ended }
    var phase: Phase
    var stableSince: Date?
    var lastEmittedAt: Date?
    var lastMatchedEventID: String?
}
```

La logique de matching et la machine à états sont dans des fonctions pures
`TeamsObservationInput → TeamsObservationDecision` testables sans UI. La
classe `NSObject` se contente d'observer `NSWorkspace` — et, le cas
échéant, d'interroger `SCShareableContent` — puis d'appeler la fonction
pure. Les sources 2 et 3 entrent par le même point avec une décision déjà
tranchée. Tests unitaires couvrent : titre vide, titre français, titre
anglais, 5 s pile, 30 s pile, app non-Teams, double détection rapide, et
deux sources différentes dans la fenêtre de cooldown.

## 4. Architecture

### Nouveaux modules

```
OneToOne/
  Services/
    TeamsCallMonitor.swift              [NEW] — surveillance locale (source 1)
    TeamsCallMatchService.swift         [NEW] — appariement call ↔ EventKit
    TeamsAutoRecordCoordinator.swift    [NEW] — machine à états du cycle de vie
    AudioRecorderService.swift          [MODIFIER] — 2e piste + mixage (§6.1)
    MeetingNotificationService.swift    [MODIFIER] — 4 catégories de plus
    TeamsLauncher.swift                 [MODIFIER] — émet le déclencheur 2
    MenuBarController.swift             [MODIFIER] — état RECORDING rouge/pulse
  Models/
    (pas de nouveau modèle, MeetingKind existant suffit ; aucun champ d'état)
  Views/
    (pas de nouvelle vue ; MeetingView étendu)
  App/
    AppSettings.swift                   [MODIFIER] — 2 nouvelles clés
```

### Cycle de vie (machine à états)

```
                    ┌──────────────┐
                    │     IDLE     │  (Teams non actif, ou hors fenêtre cal.)
                    └──────┬───────┘
                           │ NSWorkspace détecte fenêtre Teams
                           │ avec titre matchant (cf. §3) ET
                           │ TeamsCallMatchService trouve un event EK ±2 min
                           ▼
              ┌────────────────────────────┐
              │   DETECTED (popup émis)    │ → UNUserNotificationCenter
              └──────────┬─────────────────┘   3 boutons : Démarrer / Ignorer / Dans 5 min
                         │
            ┌────────────┼────────────┐
            │            │            │
            ▼            ▼            ▼
       ┌────────┐  ┌──────────┐  ┌──────────┐
       │STARTED │  │ DISMISSED│  │ SNOOZED  │
       └────┬───┘  └──────────┘  └─────┬────┘
            │                          │ (timer 5 min)
            │                          ▼
            │                       DETECTED (à nouveau)
            │
            │ → crée Meeting (chemin importEvent-like)
            │ → ouvre MeetingView en fenêtre
            │ → démarre capture micro + SystemAudio
            │ → démarre STT Whisper + diarisation
            │ → MenuBarController.statusItem passe en rouge+pulse
            ▼
      ┌──────────────┐
      │  RECORDING   │
      └──────┬───────┘
             │ NSWorkspace détecte fermeture de la fenêtre Teams
             │ (ou changement de titre hors patterns)
             ▼
      ┌──────────────┐
      │  CALL_ENDED  │ → UNUserNotificationCenter
      └──────┬───────┘   2 boutons : Arrêter et finaliser / Continuer
             │
             │ (bouton « Arrêter et finaliser »)
             ▼
      ┌──────────────────┐
      │ FINALIZING       │ → arrête capture, fige STT,
      │ (transcription)  │   attend la fin de la diarisation
      └──────┬───────────┘
             │ (transcription complète, y compris diarisation)
             ▼
      ┌──────────────┐
      │ READY_FOR_AI │ → UNUserNotificationCenter
      └──────┬───────┘   2 boutons : Générer le rapport / Plus tard
             │
             │ (bouton « Générer le rapport »)
             ▼
      ┌──────────────┐
      │ REPORTING    │ → AIReportService.generate, template par défaut
      └──────┬───────┘   du kind — le chemin exact du bouton existant
             │           « Générer le rapport »
             ▼
      ┌──────────────┐
      │     DONE     │ → menu bar redevient normal,
      └──────────────┘   notification succès silencieuse (log only)
```

### Responsabilités par module

- **`TeamsCallMonitor` (singleton, `@MainActor`)** : observe `NSWorkspace`
  (source 1), publie `callStarted` / `callEnded`. Logique pure testable.
  Les sources 2 et 3 s'adressent directement au coordinateur.
- **`TeamsCallMatchService` (enum namespace, fonctions statiques pures)** :
  étant donné un instant T, parcourt les events EventKit du jour (via le
  cache de `CalendarAgendaService.eventsForDay`) et retourne l'event dont
  `startDate` est dans `[T − 2 min, T + 2 min]`. Si plusieurs events
  matchent, erreur `ambiguousMatch([EKEvent])` gérée par le popup de choix.
- **`TeamsAutoRecordCoordinator` (singleton, `@MainActor`)** : la machine
  à états. Reçoit les événements de `TeamsCallMonitor`, parle à
  `MeetingNotificationService` (spec v1 §8) pour émettre les popups UN, et
  déclenche la création de la Meeting + l'orchestration de la capture.
  Reçoit aussi les taps sur les boutons de notification (via
  `UNUserNotificationCenterDelegate`).
- **`AIReportService` (existant, non modifié)** : le coordinateur appelle
  `generate` comme le fait déjà le bouton « Générer le rapport ». Aucun
  module ni prompt nouveau — voir §6.4.
- **`MenuBarController` (MODIFIER)** : ajoute 2 états visuels :
  `RECORDING` (icône rouge fixe) et `RECORDING_PULSE` (icône rouge avec
  animation pulse 0.8 Hz). Click sur l'icône en mode `RECORDING` →
  `NSApp.activate` + navigation vers la Meeting en cours (extension du
  click handler de la spec v1 §7).

### Capture audio (deux pistes)

- **Micro interne** : `Services/AudioRecorderService.swift`, singleton
  `@MainActor .shared`. `AVAudioEngine` + `TapSink` (conversion 16 kHz
  mono), pause/reprise, et `makeAudioStream() -> AsyncStream<[Float]>`
  que `LiveTranscriptionService.begin(audioStream:)` consomme déjà.
- **System Audio (Teams)** : via `ScreenCaptureKit` (`SCStream` avec
  `SCStreamConfiguration.captureAudio = true`), audio uniquement, pas de
  vidéo. macOS 13+ requis ; `Package.swift` déclare `.macOS("15.0")`, la
  contrainte est satisfaite.
- **Aucune clé `Info.plist` à ajouter** : `NSScreenCaptureUsageDescription`
  n'est pas le mécanisme TCC de ScreenCaptureKit, dont le prompt est émis
  par le système. `ScreenCaptureService` capture déjà des fenêtres
  aujourd'hui sans cette clé. Voir §8.
- Si la permission écran est refusée, fallback automatique sur micro seul
  avec un bandeau d'erreur non bloquant dans `MeetingView`.

### STT + diarisation

Brique existante : Whisper MLX + `PyannoteDiarizer`, on-device. Le
coordinateur la déclenche au moment où la Meeting passe en `RECORDING`,
avec l'audio de la réunion capturée. Si le STT échoue au démarrage
(modèle pas chargé, RAM saturée), la Meeting continue en audio seul ;
l'utilisateur peut retenter via un menu dans la fenêtre (cf. §6 edge
cases).

La provenance des locuteurs ne passe **pas** par la diarisation.
`PyannoteDiarizer` fait du clustering non supervisé et *dérive*
`numSpeakers` : il n'existe aucune taxonomie de labels où ajouter un tag
« Teams distant ». L'attribution « moi » / « distant » vient de la piste
d'origine, conservée sous forme de chronologie d'énergie (§6.1). La
diarisation ne sert donc qu'à séparer les voix *à l'intérieur* de la
piste distante — ce qu'elle sait déjà faire, sans modification.

### Rapport IA

Aucune section nouvelle. `AIReportService.generate` écrit déjà dans
`summary`, `keyPointsJSON`, `decisionsJSON`, `openQuestionsJSON` et
`reportRevisions`, tous modifiables depuis la vue existante. Le prompt
vient du `ReportTemplate` par défaut du `kind` — éditable par
l'utilisateur, donc rien n'est figé dans le binaire.

### Concurrence

Si une réunion OneToOne est déjà active (édition en cours), le popup
propose « Lier l'appel Teams à la réunion en cours » au lieu de
« Démarrer ». Le coordinateur passe la Meeting existante en mode
`RECORDING` (ajout de la piste SystemAudio si pas déjà présente, ajout
de la transcription si pas déjà présente). Si l'utilisateur refuse,
popup « Démarrer quand même une nouvelle réunion » (chemin nominal).

## 5. Modèle de données

### Pas de nouveau modèle SwiftData

`Meeting` a déjà (spec v1 §4) :
- `scheduledStart`, `scheduledEnd`, `teamsJoinURL`, `calendarEventID`.
- `kind: MeetingKind` (`.oneToOne` / `.project` / `.manager` / `.global`).
- `attendees: [Collaborator]`.
- `transcriptChunks: [TranscriptChunk]` et
  `transcriptSegments: [TranscriptSegment]` (STT et diarisation).
- `summary`, `shortSummary`, `keyPointsJSON`, `decisionsJSON`,
  `openQuestionsJSON`, `reportRevisions`, `reportTemplate` — le rapport a
  déjà toute sa structure, et elle est déjà modifiable.

**Aucun ajout** de `callDetectedAt: Date?`, `audioSystemTrack: Data?`, ni
d'un quelconque champ d'état de cycle de vie. `Meeting` n'a aujourd'hui
aucun champ d'état et n'en gagne pas : la machine à états de §4 vit en
mémoire dans `TeamsAutoRecordCoordinator`. Le moment de détection vit dans
les logs du coordinateur. Les deux pistes audio sont écrites comme des
fichiers dans `AudioRecorderService.recordingsDirectory`, au même titre
que la piste micro d'une réunion classique.

Conséquence assumée : un crash de OneToOne pendant l'enregistrement perd
l'état en cours, sans reprise possible. C'est la limitation déjà listée en
§10, ici érigée en choix explicite plutôt que subie.

### Lien visuel avec l'event EventKit

La ligne « Source : Outlook Calendar » est ajoutée à la première ligne du
champ `summary` de la Meeting (ou dans une note d'en-tête si `summary`
est vide). C'est purement visuel, pas un champ SwiftData. Évite une
migration de schéma.

L'`calendarEventID` (déjà spécifié v1 §4) reste le lien structurel entre
l'event et la Meeting.

### Popups UNUserNotificationCenter — 4 catégories

`MeetingNotificationService` déclare **déjà** quatre catégories
(`MEETING_PRE_START`, `MEETING_START`, `MEETING_END`,
`RECORDING_STARTED`) via `center.setNotificationCategories([...])`, appel
qui **remplace** l'ensemble enregistré. Les quatre nouvelles catégories
sont donc à ajouter dans `registerCategories()` du service existant, et
non à enregistrer depuis le coordinateur — sinon elles effacent les
quatre premières.

```swift
// Catégorie 1 : appel Teams détecté, proposition de démarrer
UNNotificationCategory(
    identifier: "TEAMS_CALL_DETECTED",
    actions: [
        UNNotificationAction(identifier: "START_RECORD", title: "Démarrer",
                             options: [.foreground]),
        UNNotificationAction(identifier: "SNOOZE_5MIN", title: "Dans 5 min"),
        UNNotificationAction(identifier: "DISMISS", title: "Ignorer",
                             options: [.destructive])
    ])

// Catégorie 2 : appel Teams terminé, proposition d'arrêter
UNNotificationCategory(
    identifier: "TEAMS_CALL_ENDED",
    actions: [
        UNNotificationAction(identifier: "STOP_AND_FINALIZE",
                             title: "Arrêter et finaliser",
                             options: [.foreground]),
        UNNotificationAction(identifier: "CONTINUE_RECORDING",
                             title: "Continuer l'enregistrement")
    ])

// Catégorie 3 : transcription finalisée, proposition de rapport
UNNotificationCategory(
    identifier: "TEAMS_TRANSCRIPT_READY",
    actions: [
        UNNotificationAction(identifier: "GENERATE_REPORT",
                             title: "Générer le rapport",
                             options: [.foreground]),
        UNNotificationAction(identifier: "SKIP_REPORT", title: "Plus tard")
    ])

// Catégorie 4 : erreur / STT échoué
UNNotificationCategory(
    identifier: "TEAMS_RECORDING_ERROR",
    actions: [
        UNNotificationAction(identifier: "RETRY_STT", title: "Retenter le STT",
                             options: [.foreground]),
        UNNotificationAction(identifier: "OPEN_MEETING", title: "Ouvrir la réunion",
                             options: [.foreground])
    ])
```

### Titres et corps des notifications

| Catégorie | Titre | Corps |
|---|---|---|
| `TEAMS_CALL_DETECTED` | `Appel Teams détecté : {event.title}` | `Démarrer l'enregistrement dans OneToOne ?` |
| `TEAMS_CALL_ENDED` | `Appel Teams terminé` | `Arrêter l'enregistrement et finaliser la transcription ?` |
| `TEAMS_TRANSCRIPT_READY` | `Transcription prête ({N} segments)` | `Générer le rapport avec le provider IA ?` |
| `TEAMS_RECORDING_ERROR` | `STT indisponible` | `L'enregistrement audio continue. Transcription à retenter.` |

### Stabilité des IDs

Chaque notification a un `requestIdentifier` dérivé de
`meeting.ensuredStableID.uuidString + suffix`, comme le fait déjà
`MeetingNotificationService.idPrefix(for:)`. **Pas**
`persistentModelID.storeIdentifier` : le modèle documente explicitement
que l'identifiant SwiftData n'est pas utilisable comme identifiant
externe. Si on émet la même
catégorie deux fois pour la même Meeting, la seconde écrase la première
(comportement `UNUserNotificationCenter.add(_:)` par `requestIdentifier`).
On évite ainsi les popups en double.

## 6. Cycle d'enregistrement (4 phases techniques)

### 6.1 Démarrage

`MeetingViewController.startRecording(mode: .teamsAutoRecord)` (méthode à
ajouter, suit le pattern existant de l'enregistrement manuel) :

1. Démarre `AVAudioEngine` pour la piste micro (chemin existant).
2. Démarre `SCStream` en mode audio-only pour la piste SystemAudio. Si
   la permission est refusée, on continue sans cette piste, on log un
   warning, et un bandeau d'erreur non bloquant apparaît dans
   `MeetingView` (déjà supporté pour d'autres erreurs).
3. **Mixe les deux pistes** en un seul buffer `[Float]` 16 kHz mono et
   n'expose qu'un `AsyncStream<[Float]>` — celui que
   `LiveTranscriptionService.begin(audioStream:)` consomme déjà. Tout
   l'aval (VAD, Whisper, merger, diarisation) reste inchangé.
4. **Conserve la provenance** : pour chaque bloc mixé, on enregistre
   l'énergie de chacune des deux pistes, horodatée. Cette chronologie
   permet d'attribuer après coup chaque segment transcrit à « moi » ou
   « distant » sans le deviner au timbre.
5. Démarre le STT Whisper sur le flux mixé.

> **Point de risque — c'est ici, pas dans `SCStream`.** Ce mixage
> n'existe pas aujourd'hui : `AudioRecorderService.concatenateWAVs` met
> deux fichiers bout à bout, ce n'est pas un mixage. Et
> `AudioRecorderService.shared` est un singleton à un seul moteur, un
> seul `currentFileURL` et un seul `activeMeetingID` : lui faire
> accepter une seconde source simultanée est la modification la plus
> structurante du chantier.

### 6.2 Arrêt

`MeetingViewController.stopRecording()` :

1. Arrête `AVAudioEngine` et `SCStream`.
2. Demande au STT de finir la transcription en cours. La transcription
   finale contient tous les chunks validés + le chunk résiduel.
3. Sauvegarde la `Meeting` (`ModelContext.save`).
4. Le coordinateur passe **sa propre** machine à états en `READY_FOR_AI`.
   Aucun champ d'état n'est écrit sur la `Meeting` : voir §5.

### 6.3 Finalisation

`TeamsAutoRecordCoordinator.transcriptionFinalized(meeting:)` :

- Émet la notification `TEAMS_TRANSCRIPT_READY`.
- Attend l'action utilisateur.

### 6.4 Rapport

`AIReportService.generate(...)` — le chemin exact du bouton « Générer le
rapport » existant. Le coordinateur ne fait que l'appeler :

- **Pas de module nouveau.** `TeamsReportGenerator` est supprimé de la
  spec.
- **Pas de prompt nouveau.** `AIReportService` sélectionne déjà le
  `ReportTemplate` par défaut du `kind`, et le pipeline existant couvre
  les quatre rubriques visées — points clés, décisions, actions, points
  en suspens — via `keyPointsJSON`, `decisionsJSON`, `openQuestionsJSON`
  et `extractStructured`.
- **Pas d'insertion à inventer.** Le résultat va là où va déjà tout
  rapport, et y est déjà modifiable.
- En cas d'échec du provider IA, on notifie l'utilisateur avec un
  message d'erreur non bloquant (« Le provider IA n'a pas pu générer le
  rapport. Tu peux le retenter plus tard depuis la réunion. »).

Corollaire assumé : une réunion Teams produit exactement le même rapport
qu'une réunion enregistrée à la main. La seule différence entre les deux
parcours est le point d'entrée.

### Lien avec la capture existante

L'enregistrement OneToOne classique (sans Teams, micro seul) **continue
de fonctionner exactement comme aujourd'hui**. Cette spec ne change que
le chemin d'entrée : au lieu que l'utilisateur clique « Rec » dans
`MeetingView`, le popup UN démarre automatiquement. Tous les chemins
existants (édition de la transcription, correction, export, statistiques)
restent valides.

## 7. AppSettings

Deux nouvelles clés dans la section « Calendrier & menubar » :

```swift
var teamsAutoRecordEnabled: Bool = true
var teamsAudioCaptureMode: TeamsAudioCaptureMode = .microAndSystem
// (ou .microOnly si l'utilisateur a refusé la permission ScreenCaptureKit)
```

`teamsAutoRecordEnabled` est consultée par `TeamsAutoRecordCoordinator`
avant d'émettre `TEAMS_CALL_DETECTED`. Si `false`, le popup ne s'affiche
pas (cette clé n'a pas d'UI en v2 mais elle existe pour permettre à un
mainteneur de désactiver le système en cas de besoin ; une UI dans
Réglages est proposée en v3).

## 8. Permissions

| Permission | API | Demandée quand | Refus → comportement |
|---|---|---|---|
| Calendrier (Full Access) | EventKit | Déjà demandée par la spec v1 | Déjà géré v1 |
| Notifications | `UNUserNotificationCenter.requestAuthorization` | Premier lancement, onboarding | Pas de popup système. Le bouton « Démarrer » est déplacé dans une sous-vue de `MeetingView` accessible via clic sur le menu bar. |
| Micro | `AVAudioSession` (déjà géré pour les réunions classiques) | Première utilisation de l'enregistrement | Bandeau d'erreur dans la Meeting, pas d'enregistrement. |
| ScreenCapture (audio) | `CGPreflightScreenCaptureAccess()` + demande explicite | Première fois qu'on instancie `SCStream` en mode audio | Fallback automatique : micro seul, bandeau d'erreur non bloquant. `teamsAudioCaptureMode` passe à `.microOnly`. |

### Info.plist — rien à modifier

- **Pas de `NSScreenCaptureUsageDescription`.** Cette clé n'est pas le
  mécanisme TCC de ScreenCaptureKit : le prompt d'enregistrement d'écran
  est émis par le système. `ScreenCaptureService` capture déjà des
  fenêtres aujourd'hui sans elle. L'ajouter serait un commit sans effet.
- `NSMicrophoneUsageDescription` : **présent**, vérifié dans `Info.plist`.
- `NSCalendarsFullAccessUsageDescription` : couvre le nouveau use-case,
  pas de changement de wording nécessaire.

## 9. Stratégie de test

### Unit (XCTest, ~25 tests)

- **`TeamsCallMonitor`** : titre vide → `idle`, titre matchant FR/EN →
  `stable` après 5 s, titre qui match puis plus pendant 30 s → `ended`,
  cooldown 30 s, app non-Teams ignorée, `lastMatchedEventID` empêche
  re-popup, deux sources distinctes dans la fenêtre de cooldown → un seul
  `callStarted`.
- **`TeamsCallMatchService`** : event à T−1 min → match, T−3 min →
  pas de match, T+2 min → match, plusieurs events → `ambiguousMatch`,
  pas d'event → `nil`.
- **`TeamsAutoRecordCoordinator`** : transitions
  `IDLE → DETECTED → STARTED → RECORDING → CALL_ENDED → FINALIZING → READY_FOR_AI → REPORTING → DONE`,
  bouton `DISMISS` → retour `IDLE`, bouton `SNOOZE_5MIN` → re-détection
  après 5 min, bouton `CONTINUE_RECORDING` → retour `RECORDING`,
  concurrence (réunion existante) → proposition de liaison.
- **Mixeur audio** (fonction pure, sans `SCStream`) : deux buffers de
  même longueur → somme bornée sans saturation ; une seule piste
  présente → passe-plat ; longueurs inégales → alignement sans décalage
  cumulatif ; chronologie d'énergie cohérente sur des pistes alternées ;
  attribution d'un segment à « moi » / « distant » selon la piste
  dominante.

Aucun test de générateur de rapport : `AIReportService` est existant et
déjà couvert.

### Integration (in-memory `ModelContext`)

- Création de Meeting depuis un event EventKit + démarrage
  d'enregistrement (chemin complet).
- Vérifier que la Meeting est créée avec les bons champs (`kind`,
  `attendees`, `calendarEventID`).
- Vérifier que la `transcript` est alimentée au fur et à mesure (test
  réduit à cause de l'asynchronisme STT).
- Lier un appel Teams à une réunion existante : la Meeting reçoit
  l'event mais conserve ses participants d'origine.

### UI (manuel, vérification à l'écran)

- Popup UNUserNotificationCenter s'affiche au bon moment.
- 3 boutons d'action fonctionnent et routent correctement.
- Menu bar passe en rouge pendant l'enregistrement.
- Click sur menu bar rouge → ouvre la Meeting.
- Le bandeau d'erreur en cas de refus ScreenCapture s'affiche.
- Le rapport inséré dans la Meeting est bien éditable.

### Smoke (script bash, manuel)

- Démarrer OneToOne, ouvrir Teams, planifier un event, rejoindre un
  appel factice → vérifier le popup.
- Refuser la permission ScreenCapture au premier essai, vérifier le
  fallback.
- Mettre OneToOne en arrière-plan, accepter le popup → vérifier que
  l'enregistrement démarre quand même.
- Quitter Teams brutalement (`killall Teams`) → vérifier que
  `callEnded` est détecté.

## 10. Edge cases documentés

- **Appel Teams sans event EventKit correspondant** → pas de popup ;
  l'utilisateur peut créer la Meeting manuellement depuis l'inspecteur
  calendrier.
- **Event EventKit sans lien Teams** → pas de popup (on ne sait pas qu'il
  y aura un appel).
- **Meeting déjà en `RECORDING` quand un 2e appel Teams démarre** → on
  propose de lier le 2e appel à la même Meeting, ou d'ignorer.
- **Crash de Teams pendant l'enregistrement** → `callEnded` est émis
  via `NSWorkspace.didTerminateApplicationNotification`, le popup
  `TEAMS_CALL_ENDED` s'affiche, l'utilisateur peut arrêter proprement.
- **Crash de OneToOne pendant l'enregistrement** → pas de reprise
  automatique. Conséquence directe du choix de §5 (aucun état persisté
  sur la `Meeting`), assumée pour la v2.
- **Provider IA échoue au moment du rapport** → la Meeting reste en
  `READY_FOR_AI`, l'utilisateur peut retenter plus tard via un bouton
  « Générer le rapport » dans la vue Rapport de la Meeting.
- **STT échoue au démarrage** → la Meeting continue en audio seul, pas
  de popup `TEAMS_TRANSCRIPT_READY` tant que le STT n'est pas relancé.
  Bandeau d'erreur dans `MeetingView` avec un bouton « Retenter le
  STT ».
- **Permission micro refusée** → la Meeting n'est pas créée du tout,
  message dans `MeetingView` invitant à autoriser le micro.
- **`Meeting` créée depuis le popup est supprimée par l'utilisateur
  pendant l'enregistrement** → le coordinateur détecte la suppression
  (via `ModelContext.didSave` ou un observeur SwiftData) et force l'arrêt
  de la capture.

## 11. Plan d'attaque (à confirmer au plan-writing)

1. **Foundation** (1-2 commits, testable en isolation) :
   - `TeamsCallMonitor` + `TeamsCallState` + tests unitaires.
   - `TeamsCallMatchService` + tests unitaires.
   - Les 4 catégories ajoutées dans
     `MeetingNotificationService.registerCategories()` + tests.

2. **Orchestration** (1 commit, intégrable) :
   - `TeamsAutoRecordCoordinator` + machine à états + tests unitaires.
   - Les trois déclencheurs branchés : `TeamsCallMonitor`,
     `TeamsLauncher.open`, `MEETING_START`.
   - Branchement au menu bar (état `RECORDING`) + click handler.

3. **Capture audio — deuxième piste** (1-2 commits, risqué) :
   - Permission `ScreenCaptureKit` + demande.
   - `SCStream` audio-only branché sur `AudioRecorderService`.
   - Faire accepter au singleton une seconde source simultanée.

4. **Mixage et provenance** (1-2 commits, aussi risqué que l'étape 3) :
   - Mixage des deux pistes en un `AsyncStream<[Float]>` unique.
   - Chronologie d'énergie par piste + attribution des segments.
   - Tests unitaires du mixeur, en fonction pure.

5. **Rapport IA** (1 commit, réduit) :
   - Branchement du coordinateur sur `AIReportService.generate`.
   - Aucun module ni prompt nouveau.

6. **UI menu bar + bandeau d'erreur** (1 commit) :
   - État rouge + pulse.
   - Bandeau d'erreur ScreenCapture refusé.

7. **Polish + tests d'intégration** (1-2 commits) :
   - Smoke tests bash.
   - Vérification à l'écran (cf. STATUS.md — toujours due avant de
     fusionner).

## 12. Branche, commits, critères d'acceptation

- Branche : `feat/teams-autorecord-popup` partant de `master`.
- PR séparée de la spec v1.
- Commit de migration SwiftData : **aucun** — pas de nouveau champ, et
  pas de champ d'état (voir §5).
- Commit Info.plist : **aucun** — voir §8.

**Critères d'acceptation** (gating la PR) :

- `swift test --skip CalendarImportEventTests` (cf. AGENTS.md) passe.
- Tous les tests unitaires nouveaux passent.
- Vérification à l'écran de bout en bout (5 scénarios minimum :
  détection + démarrage, refus permission, fin d'appel, transcription,
  rapport).
- `STATUS.md` mis à jour.
- L'ADR « Décision de ne pas utiliser MS Graph » (à écrire si on en
  crée un pendant le chantier) consolidé.
- `docs/cleanup-report.md` mis à jour si de nouveaux modules y sont
  listés.

## 13. Hors scope v2, à noter pour v3

- Balayage périodique des fenêtres, pour couvrir le cas « Teams en
  arrière-plan **et** permission écran pas encore accordée » (cf. §3).
- Snooze configurable par l'utilisateur (durée, répétition).
- Capture d'écran de Teams en parallèle de l'audio.
- Lecture d'un `.mp4` exporté de Teams et transcription post-hoc.
- Mode « réunion persistante » qui n'a pas besoin d'un event calendrier.
- UI dans Réglages pour `teamsAutoRecordEnabled` (la clé existe mais
  n'a pas d'UI en v2).
- Multi-comptes Teams (si pertinent un jour).

## 14. Annexe — Inventaire des questions tranchées

Cette section consigne les 18 questions qui ont structuré le
brainstorming, pour traçabilité.

| # | Question | Décision |
|---|---|---|
| 1 | Niveau d'intégration Microsoft | Surveillance locale, pas d'API |
| 2 | Déclencheur du popup | 3 déclencheurs combinés, désormais tous trois spécifiés en §3 |
| 3 | Contenu du popup | **À arbitrer** : §5 ne propose que Démarrer / Dans 5 min / Ignorer. Les trois modes de capture n'apparaissent nulle part ailleurs dans la spec — voir §15 |
| 4 | Source calendrier | EventKit natif |
| 5 | Forme du popup | Notification système macOS |
| 6 | Devenir si pas démarré | Réunion OneToOne, pas une note |
| 7 | Capture audio Teams | Oui, lié à la réunion OneToOne |
| 8 | Comment | Audio système Teams en parallèle, double piste |
| 9 | Transcription | STT Whisper MLX + diarisation on-device |
| 10 | Fréquence | Toujours afficher le popup, opt-out par refus |
| 11 | Type de réunion | `ProjectMatchService.suggestKind` : manager (email), 1:1 (2 participants), projet (titre flou ≥ 0,7), fallback `.global` — sans mots-clés |
| 12 | Liste mots-clés | **Corrigée** : aucune liste configurable. L'inférence de type est structurelle (Q11) ; les motifs de détection d'appel de §3 restent en dur |
| 13 | Lien avec event calendrier | Ligne « Source : Outlook Calendar » dans le summary |
| 14 | Action du bouton Démarrer | Crée, ouvre, démarre capture micro + SystemAudio + STT |
| 15 | Premier plan | OneToOne passe au premier plan |
| 16 | Fin d'appel Teams | Notification éphémère |
| 17 | Provider IA | Nécessaire, sinon rapport désactivé |
| 18 | Insertion du rapport | **Corrigée** : champs de rapport existants via `AIReportService`, déjà modifiables |

## 15. Journal des amendements (2026-08-28, v2.1)

La v2.0 avait été écrite depuis le brainstorming, sans relecture du code.
Cinq points ont été vérifiés dans le dépôt, et six décisions prises. Ce
journal existe pour que la relecture porte sur les écarts, pas sur la
spec entière.

### Les deux points « à confirmer » de la v2.0 : tranchés

| Point | Verdict |
|---|---|
| Deployment target ≥ macOS 13 pour `SCStream.captureAudio` | `Package.swift` déclare `.macOS("15.0")`. Aucun risque. |
| Existence de `Services/AudioRecorder.swift` | C'est `AudioRecorderService.swift`, singleton `@MainActor .shared` : `AVAudioEngine` + `TapSink` 16 kHz mono, pause/reprise, `makeAudioStream()`. |

### Les six décisions

| # | Sujet | Décision | Sections touchées |
|---|---|---|---|
| 1 | État de la `Meeting` | Aucun état persisté. La machine à états vit dans `TeamsAutoRecordCoordinator`. | §5, §6.2, §10, §12 |
| 2 | Rapport IA | Réutilisation de `AIReportService`. `TeamsReportGenerator` supprimé, prompt en dur supprimé, D-8 annulée. | §0, §1, §2, §4, §6.4, §9, §11 |
| 3 | Déclencheurs | Les trois de l'annexe Q2 sont retenus et spécifiés. Deux sont des points d'émission sur du code existant. | §3, §4, §9, §11, §14 |
| 4 | Observation | Hybride : `NSWorkspace`, enrichi par `SCShareableContent` quand `CGPreflightScreenCaptureAccess()` est déjà vrai. D-11 passe de « non supporté » à « dégradé ». | §1, §2, §3, §13 |
| 5 | Double piste | Mixage vers un flux STT unique, avec chronologie d'énergie par piste pour la provenance. La diarisation n'est pas modifiée. | §2, §4, §6.1, §9, §11 |
| 6 | Mots-clés | Aucune liste configurable. Inférence structurelle par `ProjectMatchService` ; motifs de §3 en dur. | §3, §7, §14 |

### Les trois incohérences internes de la v2.0

1. **`§5` / `§12` contre `§6.2`** — la v2.0 promettait « aucun ajout au
   modèle » et « migration : aucune », tout en introduisant
   `state = .readyForFinalize`. La vérification a montré que `Meeting`
   n'a **aucun** champ d'état : ce n'était pas une valeur d'énum à
   ajouter mais une machine à états persistée à créer. Résolu par la
   décision 1, en faveur de `§5` et `§12`.
2. **`§3` contre l'annexe Q2** — trois déclencheurs décidés, un seul
   spécifié, deux ni décrits ni renvoyés en v3. Résolu par la décision 3 :
   les trois sont spécifiés, d'autant que les deux manquants existent
   déjà en code.
3. **`§7` contre l'annexe Q12** — une liste de mots-clés « configurable
   dans Réglages » décidée, aucune clé prévue. La vérification a montré
   que `ProjectMatchService.suggestKind` n'utilise aucun mot-clé (règles
   structurelles : email du manager, nombre de participants,
   correspondance floue de titre). Résolu par la décision 6 : Q12 est
   corrigée, il n'y avait rien à construire.

### Corrections factuelles, sans arbitrage

- **`requestIdentifier`** (`§5`) — dérivé de `ensuredStableID.uuidString`,
  pas de `persistentModelID.storeIdentifier`, que le modèle documente
  explicitement comme inutilisable en identifiant externe.
- **Enregistrement des catégories** (`§5`) —
  `center.setNotificationCategories([...])` remplace l'ensemble : les
  quatre nouvelles catégories doivent être fusionnées dans
  `MeetingNotificationService.registerCategories()`, faute de quoi elles
  effacent les quatre existantes.
- **`NSScreenCaptureUsageDescription`** (`§8`, `§12`) — la v2.0 la
  croyait requise et « absente, découverte de cette spec ». Elle est bien
  absente, mais elle n'est pas le mécanisme TCC de ScreenCaptureKit :
  `ScreenCaptureService` capture déjà des fenêtres sans elle. L'ajout et
  son commit dédié sont supprimés.
- **`NSMicrophoneUsageDescription`** — présent, vérifié.
- **Emplacement de `MenuBarController`** (`§4`) — `Services/`, pas
  `Controllers/`.
- **Diarisation** (`§4`, `§6.1`) — la v2.0 annonçait « un nouveau tag
  `Teams distant` à ajouter au modèle de diarisation ». `PyannoteDiarizer`
  fait du clustering non supervisé et *dérive* `numSpeakers` : cette
  taxonomie n'existe pas.

### Ce que le solde change pour l'implémentation

Un module en moins (trois au lieu de quatre), aucune migration SwiftData,
aucun commit `Info.plist`, un faux négatif de détection en moins. Et un
risque de plus, désormais nommé : `§6.1` disait « le flux fusionné »
comme si la fusion existait. Elle n'existe pas —
`AudioRecorderService.concatenateWAVs` concatène deux fichiers, et le
singleton n'admet qu'une source à la fois. Le mixage est le vrai morceau
du chantier, pas `SCStream`.

### Point resté ouvert

L'annexe **Q3** décide que le popup propose « un choix entre 3 modes :
note texte / note + audio / audio seul ». Rien dans le corps de la spec
ne reprend ces modes : `§5` ne déclare que `START_RECORD` / `SNOOZE_5MIN`
/ `DISMISS`, et `§6.1` démarre systématiquement la capture complète.
C'est une quatrième incohérence, repérée pendant l'amendement mais non
tranchée. Deux issues plausibles : corriger Q3 comme périmée, ou ajouter
les modes à la catégorie `TEAMS_CALL_DETECTED`. À arbitrer avant le plan
d'implémentation.
