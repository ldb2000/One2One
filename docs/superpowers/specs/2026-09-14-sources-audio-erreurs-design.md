# Sources audio et cas d'erreur de capture — spécification

Date : 2026-09-14. Auteur du cadrage : Laurent, à partir du tableau des cas d'erreur
ci-dessous. Ce document confronte le tableau au code de `master` (`4960d81`) et fixe les
décisions prises en brainstorming le 2026-09-14. Il est l'autorité sur l'intégration au code ;
le rendu des feuilles suit les jetons `One2OneToken` et les fontes Plex sans maquette dédiée.

## 1. Ce qui est demandé

| Cas d'erreur | Comportement attendu |
| --- | --- |
| Micro de pré-réunion indisponible | Pop-up au lancement de la réunion demandant à l'utilisateur d'en choisir un autre parmi les sources détectées. |
| iPhone déconnecté en cours de réunion | Fallback immédiat sur le micro du Mac, et notification « Bascule sur le micro MacBook ». |
| Teams fermé ou flux non détecté | Alerte « Aucun flux Teams détecté. Capture micro globale activée ». |
| Refus d'autorisation microphone ou audio système | Modale d'aide guidant vers Réglages Système, Confidentialité et sécurité. |

## 2. Ce que le code impose (constats d'exploration)

1. **Le recorder lit toujours l'entrée par défaut du système.** `AudioRecorderService.start`
   prend `engine.inputNode` tel quel (`Services/AudioRecorderService.swift:197`). Aucun
   sélecteur de micro n'existe, ni dans les réglages ni en mode Préparer. Le seul « sélecteur
   de source » du projet, `CaptureSourceCatalog`, concerne les fenêtres à photographier.
2. **Un changement de périphérique arrête l'enregistrement.** `handleConfigurationChange`
   pose un `lastError`, appelle `stop()` et tue la session live
   (`AudioRecorderService.swift:372-389`). C'est l'inverse du fallback demandé.
3. **La permission écran manquante est déjà gérée.** La seconde piste se dégrade en micro
   seul (`effectiveCaptureMode`, spec D-6) et un bandeau jaune l'annonce dans la réunion
   (`Views/MeetingView.swift:251`). Rien ne détecte en revanche que Teams est fermé au
   démarrage ; `TeamsCallMonitor.isTeamsRunning()` existe mais n'est pas consulté à cet endroit.
4. **Le refus micro est une chaîne d'erreur**, `AudioError.permissionDenied`
   (`AudioRecorderService.swift:652`). Le lien profond vers Réglages Système existe pour l'écran
   (`Services/SlideCapture/ScreenRecordingSettingsLink.swift`), pas pour le micro.
5. **Deux canaux de message existent** : les notifications système `UNUserNotificationCenter`
   de `MeetingNotificationService` (déjà utilisées pour Teams) et le bandeau jaune de la fenêtre
   de réunion. Aucun toast in-app.
6. **`concatenateWAVs(first:second:output:)` existe déjà** dans `AudioRecorderService` et n'a
   plus d'appelant en production : c'est la primitive du fallback par segment.
7. **Le démarrage d'enregistrement vit dans `MeetingView`** (`startRecording()` ligne 1046 et
   un second démarrage ligne 1115), en violation de la règle « rien ne s'ajoute dans
   `MeetingView.swift` ». Ce chantier l'en sort.

## 3. Décisions

| # | Décision | Alternative écartée |
| --- | --- | --- |
| D1 | **Fallback par segment.** À la déconnexion, le WAV courant est fermé, un second est ouvert sur l'entrée de repli, les segments sont concaténés à l'arrêt. | Rebrancher l'engine dans le même fichier : AVAudioEngine impose de réinstaller tap et convertisseur, risque de corrompre le WAV en cours. |
| D2 | **Micro préféré global**, dans `AppSettings`. Le pop-up de pré-réunion n'apparaît que si ce micro est absent des sources détectées. Le choix fait dans le pop-up vaut pour cette réunion seulement. | Choix par réunion en mode Préparer : l'usage réel est un iPhone en Continuité ou le micro du Mac, pas un micro par réunion. Reste ajoutable sans casser D2. |
| D3 | **Contrôle Teams au démarrage seulement.** Teams non lancé à l'instant du démarrage d'une réunion à lien Teams : notification et rétrogradation en micro seul. Aucune surveillance en séance. | Surveiller Teams en séance : une piste système laissée ouverte après la fermeture de Teams capte du silence, sans dommage. |
| D4 | **Notifications système pour les événements en séance** (bascule iPhone, flux Teams absent), via `MeetingNotificationService`. **Feuilles modales in-app** pour le choix de micro et l'aide autorisations. Aucun composant toast créé. | Toast in-app : toujours visible en plein écran, mais un composant de plus à créer et à maintenir. |
| D5 | **Service CoreAudio dédié** qui énumère et observe ; **règle métier pure** qui décide ; le recorder exécute. | Rester sur l'entrée par défaut du système : la première ligne du tableau devient impossible, seul macOS choisit. Déléguer à Réglages Système : l'utilisateur sort de l'app au pire moment. |
| D6 | **Pas de rebascule automatique** au retour de l'iPhone. | Une double bascule au même instant serait pire qu'une voix plus lointaine. |
| D7 | **Le micro intégré est reconnu par son type de transport** (`kAudioDeviceTransportTypeBuiltIn`), jamais par son nom. | Comparer le nom « MacBook » : faux en anglais et sur Mac de bureau. |

## 4. Architecture

Trois couches, dans l'ordre des dépendances.

### 4.1 Règle métier pure — `Services/Audio/AudioInputRouting.swift`

`enum AudioInputRouting`, fonctions statiques, aucun import CoreAudio. Travaille sur des valeurs
`AudioInputDevice` (`uid: String`, `name: String`, `isBuiltIn: Bool`, `isSystemDefault: Bool`).

```swift
enum StartVerdict: Equatable {
    case use(AudioInputDevice)          // préféré présent, ou réglage « par défaut du système »
    case askUser(candidates: [AudioInputDevice], missingPreferredUID: String)
    case noInput
}
static func resolveStart(preferredUID: String, devices: [AudioInputDevice]) -> StartVerdict

enum FallbackVerdict: Equatable {
    case switchTo(AudioInputDevice)
    case stopRecording                  // plus aucune entrée
    case ignore                         // le périphérique retiré n'était pas celui en cours
}
static func fallback(removedUID: String, currentUID: String, devices: [AudioInputDevice]) -> FallbackVerdict
```

Repli : micro intégré d'abord (D7), sinon l'entrée par défaut du système, sinon `.stopRecording`.

### 4.2 Service CoreAudio — `Services/Audio/AudioInputDeviceService.swift`

Singleton `@MainActor` `.shared`, `@Observable`. Énumère `kAudioHardwarePropertyDevices`, ne
retient que les périphériques ayant des flux d'entrée (`kAudioDevicePropertyStreams`, scope
input), lit l'UID, le nom, le type de transport et l'entrée par défaut. Écoute
`kAudioHardwarePropertyDevices` et `kAudioHardwarePropertyDefaultInputDevice` par
`AudioObjectAddPropertyListenerBlock`. Publie `devices: [AudioInputDevice]` et un
`AsyncStream<AudioInputEvent>` (`.removed(uid)`, `.added(uid)`). Il ne décide rien.

### 4.3 Recorder — modification de `AudioRecorderService`

- `start(meetingID:captureMode:inputUID:)` : si `inputUID` est non nul, force l'entrée sur
  `engine.inputNode.audioUnit` via `kAudioOutputUnitProperty_CurrentDevice` avant d'installer le
  tap. `nil` conserve le comportement actuel.
- `switchInput(to uid: String) throws` : retire le tap, arrête l'engine, `sink.finish()` sur
  le segment courant, empile son URL dans `segmentURLs`, ouvre un nouveau `AVAudioFile`, force
  l'entrée, réinstalle le tap sur le **même** `TapSink` (le flux live et la continuation restent
  ininterrompus), redémarre l'engine. Ajoute une entrée à `provenanceTimeline`.
- `stop()` : si `segmentURLs` a plus d'un élément, concatène par `concatenateWAVs` en chaîne
  vers un fichier final, supprime les segments, rend l'URL finale et la durée cumulée.
- `handleConfigurationChange` : ne stoppe plus par réflexe. Il laisse le coordinateur trancher
  via le flux d'événements du service ; l'arrêt n'a lieu que sur `.stopRecording`.
- Un `switchInput` pendant une pause ferme le segment de la même façon ; le suivant reprend en
  pause.

### 4.4 Coordinateur — `Services/Meeting/MeetingRecordingCoordinator.swift`

`@MainActor`, un par fenêtre de réunion, possédé par `MeetingScreenModel`. Reprend les deux
`startRecording` de `MeetingView` (constat 7), et :

1. vérifie la permission micro ; refusée ou restreinte → `screen.permissionHelp = .microphone`,
   fin ;
2. applique `AudioInputRouting.resolveStart` ; `.askUser` → `screen.audioInputChoice = …`, le
   démarrage reprend au choix, l'annulation ne pose aucune erreur ; `.noInput` → `lastError` ;
3. pour `.microAndSystem` : permission écran absente → comportement actuel (bandeau jaune) ;
   Teams non lancé → `notifyTeamsFlowMissing()` et `.microOnly`, sans bandeau ;
4. démarre le recorder, la transcription live et le playhead exactement comme aujourd'hui ;
5. consomme le flux d'événements du service pendant l'enregistrement et applique
   `AudioInputRouting.fallback` : `.switchTo` → `recorder.switchInput` puis
   `notifyAudioInputFallback(deviceName:)` ; `.stopRecording` → arrêt avec le message actuel.

Le démarrage automatique depuis la notification Teams (`TeamsAutoRecordCoordinator`) passe par
le même coordinateur ; une feuille `.askUser` s'ouvre alors dans la fenêtre qu'il vient d'ouvrir.

### 4.5 Vues

| Fichier | Rôle |
| --- | --- |
| `Views/Settings/AudioInputSettingsSection.swift` | `GroupBox("Entrée audio")` inséré avant « Reconnaissance vocale » dans `SettingsView`. `Picker` sur les entrées détectées plus « Par défaut du système ». |
| `Views/Meeting/Capture/AudioInputChoiceSheet.swift` | Feuille de pré-réunion : nomme le micro préféré absent, liste les sources détectées avec un bouton « Utiliser » par ligne, bouton « Annuler ». |
| `Views/Meeting/Capture/AudioPermissionHelpSheet.swift` | Aide autorisations, paramètre `.microphone` ou `.systemAudio`. Explique le chemin Réglages Système, Confidentialité et sécurité, et ouvre le bon volet. |
| `Services/SlideCapture/ScreenRecordingSettingsLink.swift` | Gagne un pendant `MicrophoneSettingsLink` (`Privacy_Microphone`), même mécanisme de repli d'URL. |

`MeetingView` perd ses deux `startRecording` et gagne deux `.sheet(item:)` branchés sur
`MeetingScreenModel`. Aucune couleur hors `One2OneToken`, aucune fonte hors Plex.

### 4.6 Notifications — `MeetingNotificationService`

- `notifyAudioInputFallback(deviceName: String)` : titre « Bascule sur le micro \(deviceName) »,
  corps « L'entrée audio précédente a été déconnectée. L'enregistrement continue. »
- `notifyTeamsFlowMissing()` : titre « Aucun flux Teams détecté », corps « Capture micro globale
  activée. »

Même catégorie et même autorisation que les notifications Teams existantes.

## 5. Persistance

Un seul champ nouveau sur `AppSettings` : `preferredAudioInputUID: String = ""`, chaîne vide
pour « par défaut du système ». Ajout optionnel avec défaut → migration légère automatique
dans `SchemaV3`, aucun `MigrationStage`. Le nom du périphérique n'est jamais stocké, il est relu
depuis le service. Aucun champ sur `Meeting` : le choix de pré-réunion est éphémère, la bascule
est tracée dans `provenanceTimeline`. Les backups n'exportent rien de plus.

## 6. Tests

Swift Testing, écrits avant l'implémentation.

| Fichier | Couvre |
| --- | --- |
| `Tests/AudioInputRoutingTests.swift` | Les trois verdicts de démarrage ; repli sur le micro intégré par type de transport ; repli sur le défaut système sans micro intégré ; absence totale d'entrée ; retrait d'un périphérique qui n'est pas celui en cours ; réglage « par défaut du système » avec préféré vide. |
| `Tests/AudioRecorderSegmentsTests.swift` | Concaténation de deux et trois segments WAV synthétiques ; suppression des segments ; URL finale ; durée cumulée ; un seul segment rend l'URL inchangée. Patron de `AudioRecorderConverterTests`. |
| `Tests/MeetingRecordingCoordinatorTests.swift` | Doubles du service et du recorder ; feuilles demandées à `MeetingScreenModel` ; notifications postées ; rétrogradation Teams sans bandeau ; annulation du pop-up sans erreur. Patron de `ScreenCaptureServiceTestDoubles`. |
| `Tests/AudioPermissionHelpTests.swift` | Lien profond choisi selon `.microphone` ou `.systemAudio`. |

`AppShortcutsTests`, `DocumentationTests`, `RefonteTypographieTests` restent verts ; aucun
raccourci nouveau. Le service CoreAudio n'est pas testé unitairement : recette manuelle par
branchement et débranchement d'un iPhone pendant un enregistrement, avec vérification de la
notification et du fichier final.

## 7. Hors périmètre

Choix de micro par réunion ; rebascule automatique au retour de l'iPhone ; surveillance de Teams
en séance ; toast in-app ; périphériques de sortie ; sélection du micro depuis la palette ⌘K ;
niveau d'entrée par périphérique dans le vumètre.

## 8. Livraison

Branche `feat/sources-audio-erreurs`, une PR. ADR
`docs/adr/2026-09-14-sources-audio-fallback-par-segment.md` pour D1 et D4. `docs/architecture.md`
et `STATUS.md` mis à jour en fin de chantier. Plan d'implémentation à écrire dans
`docs/superpowers/plans/`.
