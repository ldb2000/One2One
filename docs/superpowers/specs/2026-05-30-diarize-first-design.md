# Diarize-first transcription — design

Date: 2026-05-30
Branche cible: à créer depuis `master`.

## Problème

Cohere Transcribe **et** Voxtral local renvoient du texte brut **sans timestamps
mot/segment**. Le chemin actuel (`STT 60s → timestamps bidons → align par
recouvrement temporel texte↔locuteur` dans `TurnAligner`) attribue donc les
locuteurs par chevauchement approximatif : des mots débordent entre locuteurs.

Solution : **diariser d'abord**, puis transcrire chaque tour de parole
indépendamment. Chaque bloc de texte hérite du locuteur de son tour → attribution
exacte, zéro débordement.

## Objectifs

1. Deux modes de transcription configurables :
   - **Transcription seule** — moteur Cohere **ou** Voxtral (sans diarisation).
   - **Diarize-first** — Pyannote diarise, puis **Voxtral** transcrit chaque tour.
2. Moteur STT pluggable derrière un protocole commun.
3. Variante Voxtral (`4bit` / `fp16`) sélectionnable dans les réglages.
4. Les **deux** modes tournent en asynchrone dans `JobQueue` (kind
   `.transcription`), visibles et annulables dans `JobQueueSidebar`.
5. Remplacement **total** de l'ancien chemin d'alignement par recouvrement.

## Non-objectifs (YAGNI)

- Pas de mode diarize-first avec Cohere (Voxtral seul, décision produit).
- Pas d'exposition UI de `maxGap` / `minTurnDuration` / `maxTokens` (constantes,
  exposables plus tard).
- Pas de variante Voxtral Mini-3B offline (seul VoxtralRealtime est exposé par
  `mlx-audio-swift` linké).
- Streaming Voxtral non utilisé (on transcrit des clips bornés par tour).

## Architecture

### Abstraction moteur — `STTEngine`

Nouveau protocole. Les deux modèles MLX conforment déjà `STTGenerationModel`
(`generate(audio: MLXArray, generationParameters:) -> STTOutput`, `fromDirectory`),
donc les wrappers sont fins.

```swift
protocol STTEngine: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    /// Transcrit un clip 16 kHz mono déjà découpé. Retourne le texte trimmé.
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) -> String
}
```

Deux implémentations :

- `CohereEngine` — wrappe `CohereTranscribeModel`. Reprend la résolution de
  dossier actuelle (`huggingFaceSnapshotsDir` + `managedModelDirectory` + chemin
  manuel) déjà dans `TranscriptionService`.
- `VoxtralEngine` — wrappe `VoxtralRealtimeModel`. Même logique de résolution,
  repo HF dépendant de la variante :
  - `4bit` → `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`
  - `fp16` → `mlx-community/Voxtral-Mini-4B-Realtime-2602`

`STTGenerateParameters` greedy : `temperature 0`, `topP 1`, `topK 0`.

### Modes & sélection (réglages)

```swift
enum TranscriptionMode: String, Codable { case transcriptionOnly, diarizeFirst }
enum STTEngineKind: String, Codable { case cohere, voxtral }
enum VoxtralVariant: String, Codable { case realtime4bit, realtimeFP16 }
```

`AppSettings` :
- `transcriptionMode: TranscriptionMode` — **remplace** `speakerIdEnabled: Bool`
  (migration : `true → diarizeFirst`, `false → transcriptionOnly`).
- `transcriptionEngine: STTEngineKind` — moteur du mode transcription-seule.
- `voxtralVariant: VoxtralVariant` — variante utilisée dès que Voxtral est actif.
- Seuils diarisation existants (`diarizationClusterThreshold`,
  `speakerIdAutoThreshold`, `speakerIdSuggestThreshold`) → conservés, utilisés
  par le mode diarize-first.

| Mode | Moteur | Chemin | Phases JobQueue |
|---|---|---|---|
| `transcriptionOnly` | Cohere ou Voxtral | chunks 60s, pluggable | `.loadingModel` → `.transcribing` |
| `diarizeFirst` | Voxtral seul | diarize → clip/tour → STT | `.loadingModel` → `.diarizing` → `.transcribing` → `.matching` |

## Point d'entrée unique

`TranscriptionService.runTranscription(audioURL:meeting:settings:in:onPhase:onProgress:)`
(renomme l'actuel `transcribeWithDiarization`). Branche sur `settings.transcriptionMode` :

- `transcriptionOnly` → boucle chunks 60s avec le moteur choisi → persiste les
  segments en locuteur unique (`speakerID = 1`), pas de diarisation/matching.
- `diarizeFirst` → orchestre `DiarizeFirstTranscriber` ci-dessous.

Les deux branches sont appelées **dans** `JobQueue.start(kind: .transcription)`
par les call sites existants (`MeetingView` ×2, `MaintenanceView`). Concurrence 1,
annulable, progression remontée à `JobQueueSidebar` — comportement inchangé.

## Flux diarize-first

Nouveau module orchestrateur `DiarizeFirstTranscriber` (ou méthode privée de
`TranscriptionService`) :

```
1. PyannoteDiarizer.diarize(audioURL) → turns + perClusterEmbedding   (existant)
2. trier turns par start croissant
3. TurnMerger.mergeAdjacent(turns, maxGap = 0.5s)        ← NOUVEAU helper pur
4. charger audio 16 kHz mono UNE fois → MLXArray (réutilise loadAudioArray)
   pour chaque tour fusionné (index i / N) :
     - skip si (end - start) < minTurnDuration (0.6s)
     - a = max(0, floor(start*sr)) ; b = min(count, floor(end*sr))
     - clip = audio[a..<b] ; skip si b <= a (clip vide)
     - texte = VoxtralEngine.transcribe(clip, language, maxTokens = 1024).trim()
     - skip si texte vide
     - Block{speaker: clusterID, start, end, text}
     - onProgress(i/N, "Tour i / N") ; Task.checkCancellation()
5. SpeakerMatcher.match(perClusterEmbedding, …) → assignments collaborateurs  (existant)
6. canonicalize: clusters mappés au même collaborateur → cluster canonique,
   puis re-merge des blocs adjacents même locuteur (TurnMerger.mergeConsecutiveBlocks)
7. persist Blocks → TranscriptSegment (speakerID = cluster+1, speaker = collab si auto)
   + speakerAssignmentsJSON / speakerMatchMetaJSON  (logique existante réutilisée)
```

### Modèle de données

```swift
struct Block {            // sortie d'un tour transcrit
    let speaker: Int      // clusterID pyannote (0-indexé)
    let start: Double
    let end: Double
    let text: String
}
```

`Block` se persiste en `TranscriptSegment` exactement comme les `AlignedSegment`
aujourd'hui (`speakerID = speaker + 1`).

### Helper pur — `TurnMerger`

Remplace `TurnAligner`. Pas de dépendance audio/modèle → testable.

```swift
enum TurnMerger {
    /// Fusionne les tours consécutifs du même locuteur séparés de ≤ maxGap.
    /// Entrée supposée triable ; trie défensivement par start. maxGap inclusif.
    static func mergeAdjacent(_ turns: [DiarTurn], maxGap: Double) -> [DiarTurn]

    /// Re-merge des blocs adjacents même locuteur (post-canonicalisation).
    static func mergeConsecutiveBlocks(_ blocks: [Block]) -> [Block]
}
```

`mergeAdjacent` (règle exacte) :
```
si turns vide → []
trier par start croissant
merged = [turns[0]]
pour t dans turns[1...]:
    last = merged.dernier
    si t.clusterID == last.clusterID ET (t.start - last.end) <= maxGap:
        last.end = max(last.end, t.end)      // gère tours contenus/chevauchants
    sinon:
        merged.append(t)
retourner merged
```

## Suppressions (remplacement total)

- `TurnAligner.align`, `clusterIDForChunk` (mapping par recouvrement) — supprimés.
- `TurnAligner.mergeConsecutive` — repris dans `TurnMerger.mergeConsecutiveBlocks`.
- `canonicalizeClusters` de `TranscriptionService` — réécrit pour opérer sur
  `[Block]` (la logique « unifier 2 clusters → 1 collaborateur » reste utile).
- Génération de `STTSegment` à timestamps 60s bidons dans le chemin diarisation
  (le chemin transcription-seule garde les chunks 60s).
- `DiarizationService` (VAD énergie legacy) — **supprimer si confirmé non
  référencé** (vérifier les usages avant suppression).
- `TurnAlignerTests`, `CanonicalizeClustersTests` — réécrits pour `TurnMerger`.

## Réglages (SettingsView)

- Picker **Mode** : « Transcription seule » / « Diarisation ».
- Si transcription seule : picker **Moteur** Cohere / Voxtral.
- Picker **Variante Voxtral** : 4-bit / fp16 (actif dès que Voxtral est utilisé).
- Seuils diarisation existants → restent, visibles en mode diarisation.

## Résolution & téléchargement modèles

- Cohere : inchangé.
- Voxtral : même stratégie (cache HF partagé + dossier managed + chemin manuel),
  `repoId` dérivé de `voxtralVariant`. Non gated → pas de token. Si modèle absent →
  même erreur `STTError.modelMissing(searched:)` listant les chemins testés.

## Gestion d'erreurs

- Modèle STT absent → `STTError.modelMissing`.
- Diarisation échoue en mode diarize-first → fallback **transcription seule
  anonyme** (`speakerID = 1`) au lieu de planter (comme l'actuel fallback
  anonyme). Loggé.
- Clip vide / tour trop court → skip silencieux (jamais envoyé au modèle).
- Annulation → `Task.checkCancellation` entre tours/chunks ; segments existants
  préservés (purge atomique juste avant insertion, logique existante conservée).

## Async / JobQueue

Aucune nouvelle plomberie : les deux modes passent par le `JobQueue.start(
kind: .transcription)` déjà en place aux call sites. `onPhase`/`onProgress`
remontent à la sidebar. En diarize-first, la progression STT devient
`fraction = i / nbTours`, label « Tour i / N ».

## Tests

- `TurnMerger.mergeAdjacent` : vide ; un seul tour ; gap `== maxGap` (fusionne,
  inclusif) ; gap `> maxGap` (sépare) ; locuteurs différents (sépare) ; tour
  contenu/chevauchant (`max(end)`) ; entrée non triée (triée avant fusion).
- `TurnMerger.mergeConsecutiveBlocks` : concat texte + bornes étendues.
- Découpe clip : bornes hors-plage clampées ; clip vide → skip ;
  `minTurnDuration` → skip.
- Canonicalisation sur `[Block]` : 2 clusters → même collab → re-merge.
- Sélection moteur selon mode/réglages.
- Migration `speakerIdEnabled` → `transcriptionMode`.

## Étapes d'implémentation (ordre)

1. `STTEngine` protocole + `CohereEngine` / `VoxtralEngine` (extraire la
   résolution de dossier de `TranscriptionService`).
2. `AppSettings` : enums + champs + migration `speakerIdEnabled`.
3. `TurnMerger` + tests (TDD).
4. `DiarizeFirstTranscriber` (orchestration) + canonicalize sur `[Block]`.
5. Renommer/brancher `runTranscription` sur le mode ; chemin transcription-seule
   pluggable.
6. Supprimer `TurnAligner` overlap + adapter call sites.
7. SettingsView : pickers mode / moteur / variante.
8. Vérifier/suppr. `DiarizationService` legacy.
9. Tests d'intégration + run app.
