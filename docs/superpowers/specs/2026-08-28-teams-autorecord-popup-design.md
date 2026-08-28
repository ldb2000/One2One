# Teams auto-record & popup — Design spec

**Date** : 2026-08-28
**Branche** : `feat/teams-autorecord-popup` (à créer à l'implémentation)
**Spec de référence** : [`2026-05-12-calendar-teams-integration-design.md`](2026-05-12-calendar-teams-integration-design.md) (v1, approuvée)
**Auteur** : laurent.deberti
**Statut** : à valider (spec écrite depuis le brainstorming)

## 0. Résumé

Quand l'utilisateur rejoint un appel Microsoft Teams, OneToOne lui propose
automatiquement, via une notification système macOS, de créer une réunion
OneToOne pré-remplie (titre, type, interlocuteurs depuis l'événement
calendrier EventKit), de l'ouvrir et de démarrer la capture micro + audio
système + transcription STT Whisper + diarisation on-device. Pendant
l'enregistrement, l'icône de menu bar passe en rouge (pulse). À la fin de
l'appel Teams, un popup propose d'arrêter et de finaliser la transcription ;
une fois la transcription finalisée, un autre popup propose de générer un
rapport via le provider IA configuré. Le rapport est inséré comme une
section « Rapport » modifiable en bas de la réunion.

Cette spec **réutilise intégralement** les fondations calendrier / Teams de
la spec v1 (EventKit, `CalendarMeetingImportService`, `ProjectMatchService`,
`MeetingNotificationService`, `MenuBarController`, `TeamsLauncher`) et
**annule trois décisions v1** documentées au §17 (« out of scope future
work »). Voir §2.

## 1. Goals & non-goals

### Goals v2

1. Détecter qu'un appel Teams est en cours — surveillance locale
   `NSWorkspace` (sans API Microsoft).
2. Faire correspondre cet appel à un événement EventKit à ±2 min.
3. Proposer un popup système `UNUserNotificationCenter` qui, à l'acceptation,
   crée une réunion OneToOne liée à l'événement, ouvre sa fenêtre, démarre
   la capture micro + audio système + STT Whisper MLX + diarisation.
4. Pendant l'enregistrement, signaler visuellement via l'icône de menu bar
   (rouge + pulse).
5. Détecter la fin de l'appel Teams → popup « Arrêter et finaliser la
   transcription » → à la fin, popup « Générer le rapport ».
6. Le rapport est produit par le provider IA configuré
   (`DirectLLM`/`Ollama`/`OpenAI`) avec un prompt prédéfini
   « Synthèse réunion OneToOne ».

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
- Pas de détection des NSWindow Teams en arrière-plan (Teams doit être au
  premier plan pour être détecté). Voir §3.

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
| D-1 | Surveillance Teams | `NSWorkspace` + titre de fenêtre key (heuristique, voir §3) |
| D-2 | Tolérance de correspondance EventKit | `±2 min` autour du `startDate` |
| D-3 | Forme du popup | `UNUserNotificationCenter` avec boutons d'action |
| D-4 | Permissions notifications | Demande au premier lancement, onboarding |
| D-5 | Source audio | Micro interne + SystemAudio Teams, deux pistes |
| D-6 | Fallback SystemAudio | Bandeau d'erreur non bloquant, micro seul |
| D-7 | STT/diarisation | Whisper MLX + diarisation 3 locuteurs (moi / Teams distant / interlocuteur en présentiel) |
| D-8 | Rapport IA | Insertion dans une section « Rapport » modifiable de la Meeting |
| D-9 | Provider IA obligatoire | Si absent, la fonctionnalité rapport est désactivée et la popup l'indique |
| D-10 | Concurrence | Si une réunion est en cours d'édition, proposer de lier au lieu de créer |
| D-11 | Détection teams en arrière-plan | Non (v2). Doit être au premier plan |

### Faux positifs / faux négatifs documentés (D-1)

Voir §3.

## 3. Surveillance locale de Teams

### Ce qu'on observe

- `NSWorkspace.didActivateApplicationNotification`
- `NSWorkspace.didDeactivateApplicationNotification`
- `NSWorkspace.didLaunchApplicationNotification`
- `NSWorkspace.didTerminateApplicationNotification`
- Titre de la fenêtre key de Teams (`NSWorkspace.frontmostApplication`)

### Ce qu'on ne peut PAS observer sans API Microsoft

- Si Teams est en train de passer un appel (vs simplement avoir la fenêtre
  ouverte).
- Si l'utilisateur est en sourdine.
- Le nombre de participants.
- L'état de la caméra.

### Heuristique « appel actif »

On considère qu'il y a un appel actif si toutes ces conditions sont réunies :

1. Teams est l'application au premier plan
   (`com.microsoft.teams` ou `com.microsoft.teams2`).
2. Le titre de la fenêtre key contient l'un des patterns
   `/\b(call|meeting|appel|réunion|conference|meet|visio)\b/i`
   (français et anglais).
3. Teams est resté au premier plan au moins 5 secondes consécutives
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

- Teams en arrière-plan pendant tout l'appel → pas de popup. Mitigation
  future : observer aussi les `NSWindow` de Teams (v3).
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
classe `NSObject` se contente d'observer `NSWorkspace` et d'appeler la
fonction pure. Tests unitaires couvrent : titre vide, titre français, titre
anglais, 5 s pile, 30 s pile, app non-Teams, double détection rapide.

## 4. Architecture

### Nouveaux modules

```
OneToOne/
  Services/
    TeamsCallMonitor.swift              [NEW] — surveillance locale NSWorkspace
    TeamsCallMatchService.swift         [NEW] — appariement call ↔ EventKit
    TeamsAutoRecordCoordinator.swift    [NEW] — machine à états du cycle de vie
    TeamsReportGenerator.swift          [NEW] — appel LLM pour le rapport
  Models/
    (pas de nouveau modèle, MeetingKind existant suffit)
  Views/
    (pas de nouvelle vue ; MeetingView étendu)
  Controllers/
    MenuBarController.swift             [MODIFIER] — état RECORDING rouge/pulse
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
      │ REPORTING    │ → TeamsReportGenerator appelle LLMProviderRegistry,
      └──────┬───────┘   prompt « Synthèse réunion OneToOne »
             │           résultat injecté dans section « Rapport »
             │           en bas de la Meeting (Markdown modifiable)
             ▼
      ┌──────────────┐
      │     DONE     │ → menu bar redevient normal,
      └──────────────┘   notification succès silencieuse (log only)
```

### Responsabilités par module

- **`TeamsCallMonitor` (singleton, `@MainActor`)** : observe `NSWorkspace`,
  publie `callStarted` / `callEnded`. Logique pure testable.
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
- **`TeamsReportGenerator` (enum namespace, fonctions statiques)** : étant
  donné une `Meeting` (transcription + métadonnées), construit le prompt
  et appelle `LLMProviderRegistry.shared.activeProvider`. Pas
  d'orchestration, pas d'état.
- **`MenuBarController` (MODIFIER)** : ajoute 2 états visuels :
  `RECORDING` (icône rouge fixe) et `RECORDING_PULSE` (icône rouge avec
  animation pulse 0.8 Hz). Click sur l'icône en mode `RECORDING` →
  `NSApp.activate` + navigation vers la Meeting en cours (extension du
  click handler de la spec v1 §7).

### Capture audio (deux pistes)

- **Micro interne** : via `AVAudioEngine` existant (déjà supporté pour
  l'enregistrement des réunions OneToOne classiques). Le code de capture
  existe déjà dans `Services/AudioRecorder.swift` (ou équivalent, à
  confirmer à l'implémentation).
- **System Audio (Teams)** : via `ScreenCaptureKit` (`SCStream` avec
  `SCStreamConfiguration.captureAudio = true`), audio uniquement, pas de
  vidéo. macOS 13+ requis — vérifier la deployment target de OneToOne à
  l'implémentation.
- Permission `NSScreenCaptureUsageDescription` à ajouter dans
  `Info.plist` (actuellement absente — découverte de cette spec).
  Si refusée, fallback automatique sur micro seul avec un bandeau
  d'erreur non bloquant dans `MeetingView`.

### STT + diarisation

Brique existante (cf. AGENTS.md, Whisper MLX + diarisation on-device). Le
coordinateur la déclenche au moment où la Meeting passe en `RECORDING`,
avec l'audio de la réunion capturée. Si le STT échoue au démarrage
(modèle pas chargé, RAM saturée), la Meeting continue en audio seul ;
l'utilisateur peut retenter via un menu dans la fenêtre (cf. §6 edge
cases).

Diarisation étendue à 3 locuteurs : « moi » (micro interne),
« Teams distant » (audio système), « interlocuteur en présentiel » (le
cas échéant). Le label « Teams distant » est un nouveau tag du modèle
de diarisation — à ajouter au modèle et aux tests.

### Rapport IA

Le résultat est inséré en bas de la Meeting comme une **section
« Rapport » modifiable** (Markdown). L'utilisateur peut le corriger à la
main. Le prompt est stocké en dur dans `TeamsReportGenerator` (pas de
prompt engineering dynamique en v2).

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
- `transcript: [TranscriptChunk]` (déjà utilisé pour STT).
- `summary: String` (champ texte libre Markdown).

**Aucun ajout** de `callDetectedAt: Date?`, `audioSystemTrack: Data?`, etc.
Justification : le moment de détection vit dans les logs du
`TeamsAutoRecordCoordinator`, pas dans la Meeting. L'audio SystemAudio est
écrit comme un `RecordingAttachment` (modèle déjà existant) au même titre
que la piste micro. C'est la même structure de fichiers que la réunion
OneToOne classique.

### Lien visuel avec l'event EventKit

La ligne « Source : Outlook Calendar » est ajoutée à la première ligne du
champ `summary` de la Meeting (ou dans une note d'en-tête si `summary`
est vide). C'est purement visuel, pas un champ SwiftData. Évite une
migration de schéma.

L'`calendarEventID` (déjà spécifié v1 §4) reste le lien structurel entre
l'event et la Meeting.

### Popups UNUserNotificationCenter — 4 catégories

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
`meeting.persistentModelID.storeIdentifier + suffix`. Si on émet la même
catégorie deux fois pour la même Meeting, la seconde écrase la première
(comportement `UNUserNotificationCenter.add(_:)` par `requestIdentifier`).
On évite ainsi les popups en double.

## 6. Cycle d'enregistrement (4 phases techniques)

### 6.1 Démarrage

`MeetingViewController.startRecording(mode: .teamsAutoRecord)` (méthode à
ajouter, suit le pattern existant de l'enregistrement manuel) :

1. Crée un `Recording` SwiftData lié à la Meeting (modèle déjà existant
   pour les réunions classiques).
2. Démarre `AVAudioEngine` pour la piste micro.
3. Démarre `SCStream` en mode audio-only pour la piste SystemAudio. Si
   la permission est refusée, on continue sans cette piste, on log un
   warning, et un bandeau d'erreur non bloquant apparaît dans
   `MeetingView` (déjà supporté pour d'autres erreurs).
4. Démarre le STT Whisper + diarisation sur le flux fusionné. La
   diarisation distingue « moi » / « Teams distant » / « interlocuteur
   en présentiel » (3 locuteurs).

### 6.2 Arrêt

`MeetingViewController.stopRecording()` :

1. Arrête `AVAudioEngine` et `SCStream`.
2. Demande au STT de finir la transcription en cours. La transcription
   finale contient tous les chunks validés + le chunk résiduel.
3. Sauvegarde la `Meeting` (`ModelContext.save`).
4. Passe la Meeting en `state = .readyForFinalize` (nouvelle valeur de
   l'enum d'état — à ajouter au modèle).

### 6.3 Finalisation

`TeamsAutoRecordCoordinator.transcriptionFinalized(meeting:)` :

- Émet la notification `TEAMS_TRANSCRIPT_READY`.
- Attend l'action utilisateur.

### 6.4 Rapport

`TeamsReportGenerator.generate(for: meeting, in: context)` :

- Construit le prompt : « Tu reçois la transcription et les métadonnées
  d'une réunion OneToOne. Produis une synthèse structurée avec : (1)
  Points clés discutés, (2) Décisions prises, (3) Actions à mener (avec
  owner si mentionné), (4) Points en suspens. Sois concis. Utilise des
  puces. » (Prompt en français, à raffiner à l'implémentation.)
- Appelle `LLMProviderRegistry.shared.activeProvider.complete(prompt:)`.
- Le résultat est inséré dans la section « Rapport » de la Meeting
  (champ `summary` étendu avec un séparateur, ou nouveau champ à
  arbitrer à l'implémentation — le plan d'implémentation tranchera).
- En cas d'échec du provider IA, on notifie l'utilisateur avec un
  message d'erreur non bloquant (« Le provider IA n'a pas pu générer le
  rapport. Tu peux le retenter plus tard depuis la réunion. »).

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

### Info.plist à modifier

- Ajouter `NSScreenCaptureUsageDescription` (nouveau, pour la capture
  audio système). Wording à arrêter à l'implémentation.
- Vérifier que `NSMicrophoneUsageDescription` est bien présent (déjà le
  cas pour l'enregistrement classique, à confirmer à l'implémentation).
- Vérifier que `NSCalendarsFullAccessUsageDescription` couvre le nouveau
  use-case (déjà le cas, pas de changement de wording nécessaire).

## 9. Stratégie de test

### Unit (XCTest, ~25 tests)

- **`TeamsCallMonitor`** : titre vide → `idle`, titre matchant FR/EN →
  `stable` après 5 s, titre qui match puis plus pendant 30 s → `ended`,
  cooldown 30 s, app non-Teams ignorée, `lastMatchedEventID` empêche
  re-popup.
- **`TeamsCallMatchService`** : event à T−1 min → match, T−3 min →
  pas de match, T+2 min → match, plusieurs events → `ambiguousMatch`,
  pas d'event → `nil`.
- **`TeamsAutoRecordCoordinator`** : transitions
  `IDLE → DETECTED → STARTED → RECORDING → CALL_ENDED → FINALIZING → READY_FOR_AI → REPORTING → DONE`,
  bouton `DISMISS` → retour `IDLE`, bouton `SNOOZE_5MIN` → re-détection
  après 5 min, bouton `CONTINUE_RECORDING` → retour `RECORDING`,
  concurrence (réunion existante) → proposition de liaison.
- **`TeamsReportGenerator`** : prompt construit avec les bons champs
  (titre, transcription, attendees), provider `DirectLLM` → appel
  effectif, provider absent → erreur explicite, résultat vide/mal
  formé → erreur remontée sans insertion.

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
- **Crash de OneToOne pendant l'enregistrement** → limitation v2 : pas
  de recovery automatique. Documenter.
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
   - Catégories UNUserNotification + tests.

2. **Orchestration** (1 commit, intégrable) :
   - `TeamsAutoRecordCoordinator` + machine à états + tests unitaires.
   - Branchement au menu bar (état `RECORDING`) + click handler.

3. **Capture audio** (1-2 commits, le plus risqué) :
   - Permission `ScreenCaptureKit` + demande.
   - Intégration `SCStream` audio-only au pipeline d'enregistrement
     existant.
   - Tests d'intégration avec un mock `SCStream` (ou un test manuel si
     trop complexe à mocker).

4. **STT** (1 commit) :
   - Extension de la diarisation à 3 locuteurs.
   - Branchement au flux audio fusionné.

5. **Rapport IA** (1 commit) :
   - `TeamsReportGenerator` + prompt.
   - Insertion dans la Meeting.

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
- Commit de migration SwiftData : **aucun** (pas de nouveau champ).
- Commit Info.plist : isoler le bump de `NSScreenCaptureUsageDescription`.

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

- Détection des NSWindow Teams en arrière-plan (cf. §3).
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
| 2 | Déclencheur du popup | 3 déclencheurs combinés (Teams key + click Rejoindre + horloge calendrier) |
| 3 | Contenu du popup | Choix entre 3 modes : note texte / note + audio / audio seul |
| 4 | Source calendrier | EventKit natif |
| 5 | Forme du popup | Notification système macOS |
| 6 | Devenir si pas démarré | Réunion OneToOne, pas une note |
| 7 | Capture audio Teams | Oui, lié à la réunion OneToOne |
| 8 | Comment | Audio système Teams en parallèle, double piste |
| 9 | Transcription | STT Whisper MLX + diarisation on-device |
| 10 | Fréquence | Toujours afficher le popup, opt-out par refus |
| 11 | Type de réunion | Inférence calendrier, mots-clés, fallback |
| 12 | Liste mots-clés | Configurable dans Réglages, défauts fournis |
| 13 | Lien avec event calendrier | Ligne « Source : Outlook Calendar » dans le summary |
| 14 | Action du bouton Démarrer | Crée, ouvre, démarre capture micro + SystemAudio + STT |
| 15 | Premier plan | OneToOne passe au premier plan |
| 16 | Fin d'appel Teams | Notification éphémère |
| 17 | Provider IA | Nécessaire, sinon rapport désactivé |
| 18 | Insertion du rapport | Section « Rapport » modifiable en bas |
