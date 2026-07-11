# Transcription en temps réel — Design

**Date** : 2026-07-09
**Statut** : validé (brainstorming), en attente de plan d'implémentation

## Objectif

Afficher le transcript **au fil de la réunion** (entretien 1:1) pendant l'enregistrement,
là où aujourd'hui la transcription est intégralement faite en batch après le `stop()`.

Usage cible : **réassurance visuelle** (« ça capte bien ») + support secondaire de prise de
notes. Latence de 15-30 s acceptable. Le texte live, une fois nettoyé et diarisé après coup,
**devient le transcript final** (pas de double passe STT).

## Contexte technique (état actuel, vérifié)

- **Capture** : `AudioRecorderService` (singleton `@MainActor .shared`) utilise `AVAudioRecorder`
  → WAV PCM Int16 / 16 kHz / mono écrit par l'OS dans
  `~/Library/Application Support/OneToOne/recordings/<UUID>.wav`. **Aucun échantillon PCM
  n'est accessible avant `stop()`** ; seul flux live actuel = metering dB (`averagePower`/`peakPower`).
- **STT** : deux moteurs derrière le protocole `STTEngine` (batch `transcribe(clip: MLXArray) -> String`),
  dont **`VoxtralEngine`** wrappant `VoxtralRealtimeModel` (`mlx-audio-swift`,
  `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`), in-process MLX/Metal. Utilisé aujourd'hui
  en **pur batch** (chunks 60 s ou clip par tour de parole).
- **Diarisation** : Pyannote (`speech-swift`), **intrinsèquement batch** (clustering global) →
  l'identification des locuteurs en direct n'est pas atteignable.
- **VAD** : `speech-swift` embarque **Silero VAD v5 + `StreamingVADProcessor`** (streaming natif,
  non utilisé aujourd'hui) et un VAD Pyannote batch. Un fallback RMS existe déjà dans
  `DiarizationService.detectTurnsFromBuffer`.
- **UI de réunion** : `MeetingView` ; pendant l'enregistrement, l'utilisateur voit la durée
  (`MeetingTopChromeBar`), le VU-mètre (`MeetingContextualRecorderBar`) et l'éditeur de notes live.

## Décisions produit (arbitrées avec l'utilisateur)

| Question | Décision |
|---|---|
| Usage du transcript live | Réassurance visuelle (+ support notes secondaire). Latence 15-30 s OK. |
| Capture audio système / Teams | **Non** — micro seul pour l'instant (chantier séparé). |
| Persistance | Live **réutilisé comme final**, après nettoyage + diarisation. |
| Affichage | **Panneau à côté des notes** (split dans `MeetingView`). |
| Identification des locuteurs | Diarisation **seule après coup** (Pyannote, sans 2ème passe STT). |
| Qualité du final | Live **nettoyé** (`collapseRepetitions`) **puis diarisé**. |
| Backend VAD | **Silero v5 CoreML / Neural Engine** (GPU laissé libre). |
| Activation | **Opt-in** via toggle Réglages → Reconnaissance vocale. |

## Architecture

### Flux global

```
Micro
 │  AVAudioEngine + inputNode.installTap  (remplace AVAudioRecorder)
 │
 ├──► AVAudioConverter → Int16 16 kHz mono → AVAudioFile   (WAV : contrat inchangé)
 │
 └──► AsyncStream<[Float]> (Float32 16 kHz mono)
        │
        ▼
   LiveTranscriptionService (@MainActor .shared)
     │  1. Silero VAD (CoreML) via StreamingVADProcessor → segments aux silences
     │  2. fenêtres ~10-30 s + overlap ~1,5 s → VoxtralRealtimeModel (Task.detached SÉQUENTIEL)
     │  3. déduplication texte de l'overlap → @Published liveTranscript (éphémère, en mémoire)
        │
        ▼
   Panneau transcript live (split avec Notes dans MeetingView)

  ── stop() ──►
   1. collapseRepetitions(liveTranscript) → meeting.rawTranscript
   2. Pyannote seul sur le WAV → attribution locuteurs par timestamps → SpeakerMatcher
      → TranscriptSegment (purge+insert atomique)
```

### Composant 1 — `AudioRecorderService` migré vers `AVAudioEngine`

**Rôle** : capturer le micro, écrire le WAV (contrat identique), exposer un flux audio live.
**Interface publique inchangée** : `start(meetingID:)`, `pause()`, `resume()`, `stop() -> (URL, TimeInterval)`,
`cancel()`, et tous les `@Published` (`isRecording`, `isPaused`, `elapsedSeconds`, `currentFileURL`,
`averagePower`, `peakPower`, `lastError`, `activeMeetingID`).
**Ajout** : un `AsyncStream<[Float]>` (ou callback) exposant les buffers Float32 16 kHz mono pour le live.

**Contrats à préserver** (sinon régression) :

1. **Format WAV** : PCM Int16 little-endian, 16 kHz, mono (jamais Float32 — casserait
   `concatenateWAVs` et doublerait la taille des fichiers).
2. **Emplacement/nommage** : `recordings/<UUID>.wav` (chemin reconstruit à plusieurs endroits).
3. **`start`** : fichier créé immédiatement, permission micro (`AVCaptureDevice.requestAccess(for:.audio)`)
   demandée **avant** `engine.start()`, mêmes `throws`, mêmes notifications.
4. **`pause`/`resume`** : jeter les buffers pendant la pause **sans fermer le fichier** (un seul WAV
   par session) ; geler `elapsedSeconds` et le metering exactement comme aujourd'hui.
5. **`stop`** : **sérialiser `removeTap → engine.stop() → drain converter (.endOfStream) → close()`
   AVANT le `return`** pour que le header RIFF soit finalisé et le WAV relisible immédiatement
   (le sanity check taille > 44 o et durée ≥ 1 s en dépend). Le `sleep(400ms)` post-stop peut rester
   mais ne doit plus être nécessaire.
6. **Concat / append** : `concatenateWAVs` statique conservé ; les deux fichiers doivent partager
   sample rate + canaux.
7. **Metering** : recalculer `averagePower = 20·log10(RMS)`, `peakPower = 20·log10(max|x|)`,
   clampés ≥ −160 dBFS, publiés sur MainActor avec throttle ~0.1 s. Gelés pendant la pause.
8. **Cap 3 h** : `record(forDuration:)` disparaît ; conserver le garde-fou `tickElapsed` qui appelle
   `stop()` à `maxDurationSeconds`.
9. **`cancel`** : fermer l'`AVAudioFile` **avant** `removeItem` (sinon fichier fantôme).
10. **Robustesse périphérique** : observer `.AVAudioEngineConfigurationChange` (changement
    d'entrée : AirPods/dock → l'engine s'arrête, le format d'input peut changer) → redémarrer
    engine + réinstaller le tap + recréer le converter, ou au minimum poser `lastError`.
    **Principal risque de régression** (`AVAudioRecorder` absorbait ça de façon transparente).

**Concurrence** : le tap livre ses buffers sur une queue temps réel → écrire le fichier sur une
queue série dédiée ; ne jamais toucher l'`AVAudioFile` depuis deux threads ; ne jamais appeler MLX
depuis le render callback audio.

### Composant 2 — `LiveTranscriptionService` (nouveau, singleton `@MainActor`)

**Rôle** : transformer le flux audio live en transcript incrémental affichable.
**Dépend de** : le flux `AsyncStream<[Float]>` de `AudioRecorderService`, `SpeechVAD` (Silero),
`VoxtralRealtimeModel` (le même modèle préchargé que le batch).

**Interface** :
- `start()` / `stop() -> String` (retourne le transcript live accumulé, brut).
- `@Published private(set) var liveTranscript: String` (ou liste de segments horodatés).
- `@Published private(set) var isLive: Bool`, `lastError`.

**Pipeline interne** :
1. **VAD** : `SileroVADModel.fromPretrained(engine: .coreml)` + `StreamingVADProcessor.process(samples:)`
   sur les buffers. `minSilenceDuration` ~0.6 s (éviter de hacher les phrases). `reset()` entre
   enregistrements. Rééchantillonnage à 16 kHz assuré en amont (le flux est déjà 16 kHz).
   **Fallback** : si Silero indisponible (hors-ligne, échec download), basculer sur une découpe
   RMS (noise floor glissant, seuil dynamique) inspirée de `DiarizationService.detectTurnsFromBuffer`.
2. **Fenêtrage** : accumuler l'audio d'un segment de parole, borné à ~10-30 s, avec **overlap
   audio ~1,5 s** entre fenêtres consécutives (le modèle n'expose **aucun** contexte inter-fenêtres).
3. **STT** : `VoxtralRealtimeModel.generate(audio:generationParameters:)` en **`Task.detached`
   séquentiel** (jamais deux appels concurrents — état MLX mutable ; stream GPU partagé).
   `maxTokens` dimensionné (~12,5 tok/s + ~49 de padding, ex. ≥ 450 pour 30 s). `language` non
   forçable (auto-détecté).
4. **Déduplication** : fusionner le texte des zones recouvrantes (overlap) avant d'ajouter au
   transcript accumulé. Publier `liveTranscript` sur MainActor (throttle raisonnable).

**Contraintes** :
- MLX mono-GPU in-process : le STT live doit **coexister** avec un éventuel LLM local et être
  **arrêté avant** toute STT batch. Sérialiser les appels ; préchauffer Voxtral 4bit au début de
  la réunion ; surveiller `peakMemoryUsage` (cohabitation avec Gemma 4 26b).
- `generateStream`/`generate` s'exécutent de façon **synchrone** → toujours `Task.detached`,
  jamais sur le MainActor (gèlerait l'UI).
- Silero CoreML : pas de metallib requis, tourne sur le Neural Engine ; télécharge le modèle HF
  (`aufklarer/Silero-VAD-v5-CoreML`) au 1er usage → gérer le cas hors-ligne + progress UI.
- Ni `SileroVADModel` ni `StreamingVADProcessor` ne sont thread-safe : une instance par flux,
  appels sérialisés.

### Composant 3 — UI : panneau transcript live

Dans `MeetingView`, pendant l'enregistrement : **split** éditeur de notes live | panneau transcript
live (auto-scroll, flux de texte). Le panneau observe `LiveTranscriptionService.liveTranscript`.
Masqué / vide quand le live est désactivé.

Cas `kind == .manager` : la sidebar droite est occupée par `ManagerAgendaSidebar` → le split doit
se faire dans la zone centrale (notes), pas dans la sidebar.

### Composant 4 — Réglages

Toggle **Réglages → Reconnaissance vocale** : « Transcription en direct » (opt-in), persisté dans
`AppSettings` (nouvelle clé booléenne). Impact batterie/thermique annoncé dans le libellé.

### Composant 5 — Finalisation au `stop()`

Dans `MeetingView.stopRecordingAndTranscribe()` (ou service dédié), quand le live était actif :
1. `collapseRepetitions(liveTranscript)` (le **même** nettoyage que le pipeline batch) →
   `meeting.rawTranscript` (+ fusion notes live existante, `NoteMergeService`).
2. **Pyannote seul** (pas de STT) sur le WAV → segments de locuteurs → attribution aux segments
   live **par recouvrement de timestamps** → `SpeakerMatcher` → `canonicalizeBlocks` →
   `TranscriptSegment` (purge+insert **atomique**, comme aujourd'hui).
3. Si le live était **désactivé** : comportement batch actuel inchangé (STT + diarisation complètes).

## Ce que le design NE fait PAS (YAGNI)

- Pas de capture audio système / Teams (micro seul).
- Pas de diarisation en direct (Pyannote batch par nature).
- Pas d'IA en séance (suggestions de questions, résumé au fil de l'eau) — extension future.
- Pas de contexte textuel injecté dans Voxtral entre fenêtres (non exposé par le modèle).

## Stratégie de test

- **`AudioRecorderService`** (migration engine) :
  - WAV produit = Int16 / 16 kHz / mono, header valide, durée correcte.
  - WAV **relisible immédiatement après `stop()`** (finalisation header).
  - `pause()`/`resume()` : un seul fichier, `elapsedSeconds` gelé pendant la pause.
  - `concatenateWAVs` (append) sur deux fichiers du nouveau recorder.
  - Recalcul du metering RMS → dBFS (bornes −160).
- **`LiveTranscriptionService`** :
  - Déduplication de l'overlap (deux fenêtres qui se recouvrent → texte fusionné sans doublon).
  - Découpe VAD sur audio synthétique (parole/silence) — événements attendus.
  - Fallback RMS quand Silero indisponible.
- **Finalisation** :
  - `collapseRepetitions` appliqué au texte live.
  - Attribution des locuteurs par recouvrement de timestamps (segments live ↔ tours Pyannote).

## Risques principaux

1. **Changement de périphérique d'entrée** en cours d'enregistrement (`.AVAudioEngineConfigurationChange`) :
   sans gestion, l'enregistrement meurt silencieusement. Régression #1 vs `AVAudioRecorder`.
2. **Finalisation du header WAV** au `stop()` : sérialisation stricte requise.
3. **Contention GPU / mémoire** : Voxtral 4B + éventuel Gemma 4 26b + STT batch — sérialiser,
   préférer 4bit, arrêter le live avant le batch.
4. **Download Silero hors-ligne** : prévoir `offlineMode` + fallback RMS.
5. **`swift build` / debug hors bundle** : le backend MLX crash sans metallib → d'où le choix
   CoreML pour le VAD ; Voxtral reste MLX (déjà géré par `bump-and-build.sh` dans le bundle).
