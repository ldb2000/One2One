# Audio editing — design

> **Status:** Draft (à valider par l'utilisateur avant plan d'implémentation)
> **Date:** 2026-05-18
> **Owner:** Laurent De Berti

## Objet

Trois fonctionnalités sur les fichiers audio des réunions :

1. **Notification au démarrage de l'enregistrement** — confirmer visuellement que la capture tourne.
2. **Diviser un audio en 2** et réaffecter le second morceau soit à une réunion existante, soit à une nouvelle réunion créée à la volée.
3. **Couper le début** d'un audio (banalités, faux départ) en réécrivant définitivement le WAV.

Aucune nouvelle table SwiftData, aucune migration.

## Architecture

```
Services/
  AudioFileEditor.swift     (NEW)   — trim() / split() sur les WAV via AVAudioFile
  AudioWaveform.swift       (NEW)   — décimation PCM → peaks pour rendu
  MeetingNotificationService.swift  (EXTEND) — notif "enregistrement en cours"
  AudioRecorderService.swift        (EXTEND) — hook start → notif

Views/
  AudioWaveformEditor.swift (NEW)   — Canvas SwiftUI + marqueur draggable
  AudioEditorSheet.swift    (NEW)   — Sheet modal lancée depuis MeetingView
  MeetingView.swift         (EXTEND) — 2 boutons : "Couper début" / "Diviser"
```

### Flux split

```
MeetingView → bouton "Diviser"
  → AudioEditorSheet(mode: .split)
  → AudioWaveformEditor : utilisateur place le marqueur → "Diviser ici"
  → AudioFileEditor.split(url, at:) → (urlA, urlB)
  → 2e étape sheet : choix de la cible
      [●] Nouvelle réunion  /  [○] Réunion existante (picker)
  → wav B attaché à la cible, durées recalculées, original supprimé.
```

### Flux trim

```
MeetingView → bouton "Couper début"
  → AudioEditorSheet(mode: .trim)
  → utilisateur place le marqueur "garder à partir de X"
  → AudioFileEditor.trim(url, from: X) → réécrit le fichier en place
  → meeting.durationSeconds mis à jour.
```

## Données & modèles

Aucun changement de schéma. Tout passe par les champs existants :

- `Meeting.wavFilePath: String?`
- `Meeting.durationSeconds: Int`
- `Meeting.transcriptSegments` — purgés après édition (offsets périmés)
- `Meeting.rawTranscript`, `mergedTranscript`, `summary` — vidés après édition
- `Meeting.reportRevisions` — conservés mais visuellement marqués obsolètes

**Création d'une réunion à la volée (split → Option C — nouvelle):**

- Titre proposé : `"<source.title> — partie 2"`
- Date : `source.date + offsetCoupure`
- `kind` : copié depuis la source
- `project` + `participants` : copiés depuis la source (l'utilisateur ajuste après)

**Fichiers WAV — atomicité :**

- **Trim** : écrit `<wav>.tmp.wav`, puis `FileManager.replaceItemAt(original, withItemAt: tmp)` (atomique sur APFS). Si l'étape replace échoue, le tmp est supprimé et l'original reste intact.
- **Split** : écrit `<wav>_A.wav` et `<wav>_B.wav` dans le même dossier. Si l'un échoue, les deux sont supprimés et l'original reste intact. Si OK, update SwiftData (`wavFilePath` des deux meetings), puis supprime l'original. Si SwiftData save échoue, les fichiers A et B sont supprimés.

## Composants

### `AudioFileEditor.swift`

```swift
@MainActor
struct AudioFileEditor {
    /// Réécrit le WAV en gardant uniquement à partir de `fromSec`. Atomique
    /// via fichier tmp + replace. Throws si `fromSec >= duration` ou si
    /// l'écriture échoue (disque plein, permission).
    static func trim(url: URL, from fromSec: Double) async throws

    /// Split au temps `cutSec`. Renvoie `(urlA, urlB)` ; supprime l'original
    /// après succès. Throws si `cutSec < 1s` ou `cutSec > duration - 1s`.
    static func split(url: URL, at cutSec: Double) async throws -> (URL, URL)

    /// Durée totale via AVAudioFile.length / sampleRate.
    static func duration(url: URL) -> Double
}
```

Implémentation : `AVAudioFile` lecture par buffers de 8192 frames, écriture WAV 16-bit PCM (même format que `AudioRecorderService`). Exécution dans `Task.detached(priority: .userInitiated)`.

### `AudioWaveform.swift`

```swift
struct AudioWaveform {
    /// Décime le WAV en `count` peaks (max amplitude absolue par bucket).
    /// Cap implicite `count ≤ 2000` pour limiter le rendu. Cache LRU
    /// mémoire keyed par `(url, mtime, count)`.
    static func peaks(url: URL, count: Int) async throws -> [Float]
}
```

Lecture par buffers de 4096 frames, accumulation `max(abs(sample))` par bucket. Renvoyé sous forme `[Float]` (0.0–1.0).

### `AudioWaveformEditor.swift` (SwiftUI Canvas)

États :
- `@State markerSeconds: Double` — position du curseur (en secondes).
- `@State peaks: [Float]` — chargé en async via `AudioWaveform.peaks(...)`.
- `@StateObject player: AudioPlayerService` (instance dédiée à l'éditeur).

Rendu :
- `Canvas` SwiftUI dessine des barres verticales (haut + miroir bas), couleur `.secondary`.
- Marqueur : ligne verticale `accentColor`, draggable via `DragGesture`.
- Sous la waveform : boutons play/pause + `Slider` synchronisé au marker.
- Tap sur la waveform = move marker au X correspondant.
- Affichage `HH:MM:SS` à droite du temps marker.

### `AudioEditorSheet.swift`

Modal Sheet (`.sheet(item:)`) lancée depuis MeetingView.

- Header : titre de la réunion + durée totale formatée.
- Corps : `AudioWaveformEditor`.
- Mode `.trim` :
  - Bouton **"Couper le début à HH:MM:SS"** (rouge, destructif).
  - Disabled si `markerSeconds < 1` ou `>= duration`.
- Mode `.split` :
  - Bouton **"Diviser ici"** → ouvre la 2e étape de la sheet.
  - 2e étape :
    - Radio `[●] Nouvelle réunion` / `[○] Réunion existante`
    - Si existante : `Picker` avec les meetings du même jour ± 1 jour, ordonnés date desc.
    - Bouton **"Confirmer"** (rouge).

### Extensions `AudioRecorderService`

Dans `start()`, après création réussie de l'`AVAudioRecorder` :

```swift
Task { @MainActor in
    if settings.notifRecordingStart {
        MeetingNotificationService.shared.notifyRecordingStarted(
            meetingTitle: meeting.title
        )
    }
}
```

### Extensions `MeetingNotificationService`

```swift
/// Notification locale immédiate "Enregistrement en cours — <titre>".
/// Catégorie RECORDING_STARTED, sans action, dismiss auto.
func notifyRecordingStarted(meetingTitle: String)
```

Implémentation : `UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)` (≈ instant). Catégorie enregistrée dans `registerCategories()`.

### Extensions `AppSettings`

```swift
/// Notification de confirmation au démarrage de l'enregistrement.
var notifRecordingStart: Bool = true
```

Toggle ajouté dans `SettingsView` à côté de `notifMeetingStart`.

### Extensions `MeetingView`

Toolbar (au-dessus du transcript ou du player) :

```
[ ✂︎ Couper début ]  [ ⌥ Diviser ]
```

Boutons disabled si :
- `meeting.wavFileURL == nil` (pas de fichier)
- Enregistrement en cours sur ce meeting
- Job actif sur ce meeting (transcription ou rapport)

## Effets de bord après édition audio

Après chaque trim ou split réussi, sur les meetings impactés :

- `rawTranscript = ""`
- `mergedTranscript = ""`
- `summary = ""`
- `transcriptSegments` : supprimés via cascade delete.
- `reportRevisions` : conservés mais une bannière s'affiche dans le tab Rapport : *"Transcription supprimée après édition audio — re-transcrire pour mettre à jour le rapport."*
- `durationSeconds` : recalculée via `AudioFileEditor.duration(newURL)`.

## Erreurs gérées

| Cas | Comportement |
|---|---|
| Fichier wav introuvable | Sheet refuse d'ouvrir, alert "Fichier audio manquant" |
| Trim avec `fromSec >= duration` | Bouton désactivé, hint "Position invalide" |
| Split trop proche d'un bord (<1 s) | Bouton désactivé, hint "Trop proche du début/fin" |
| Écriture WAV échoue | Restore original, alert avec `error.localizedDescription` |
| Enregistrement en cours sur le wav | Boutons désactivés, hint "Arrête l'enregistrement avant" |
| Transcription/rapport en cours | Boutons désactivés tant que job actif sur ce meeting |
| Crash pendant trim (tmp orphelin) | Au prochain ouverture de la sheet : cleanup `<wav>.tmp.wav` vieux de > 5 min |

## Intégration JobQueue

Trim et split passent par `JobQueue.shared.start(...)` :

- `kind: .audioEdit` (à ajouter à `JobQueue.JobKind`).
- Annulable via la sidebar (`Task.checkCancellation()` entre buffers de 8192 frames).
- Statut texte : `"Trim 12% · 4.2 MB écrits"` ou `"Split 67%"`.

## Tests

### Unitaires

`AudioFileEditorTests`:
- Génère un WAV synthétique de 60 s (sine wave 440 Hz, 16-bit PCM, 16 kHz mono).
- `trim(url, from: 10)` → durée = 50 s ± 0.05 s.
- `split(url, at: 30)` → 2 fichiers de 30 s ± 0.05 s.
- Somme RMS conservée à ±2 % (vérifie qu'on ne perd pas de samples).

`AudioWaveformTests`:
- `peaks(synthWav, 100)` renvoie un array de 100 `Float` dans [0.0, 1.0].
- Max approximé à l'amplitude générée (±0.05).

### Manuels (non automatisés)

- Ouvrir trim sur une vraie réunion, vérifier rendu waveform et marker draggable.
- Split + créer nouvelle réunion : cohérence dates, titre, kind hérités.
- Split + réunion existante : picker rempli, attachement OK, original supprimé.
- Notification au démarrage de l'enregistrement : banner visible, son joué.

## YAGNI / hors scope

- Pas de waveform multi-canal (toujours mono recorded).
- Pas de zoom/scroll horizontal dans la waveform (sample décimé sur largeur écran).
- Pas d'undo après trim/split (irréversible — c'est le choix B).
- Pas de fondu enchaîné aux bords du split (cut net).
- Pas de support multi-format (WAV uniquement, c'est ce que produit le recorder).

## Plan d'implémentation

À détailler dans `docs/superpowers/plans/<date>-audio-editing-plan.md` via la skill `writing-plans` après validation de ce spec.
