# Spécifications — Page Maintenance (batch jobs + cleanup audio)

| | |
|---|---|
| **Version** | 0.2 |
| **Auteur** | Lolo |
| **Date** | 22 mai 2026 |
| **Projet** | OneToOne |
| **Statut** | Pré-validation utilisateur |

---

## 1. Objet

Ajouter une page **Maintenance** dans les Réglages, regroupant :

1. **Traitements en lot** — lancer rapport / transcription / diarisation sur toutes les réunions qui n'en ont pas.
2. **Cleanup audio** — réduire la taille des WAV anciens (compression AAC) puis les supprimer après une période de rétention plus longue, sous la condition qu'un rapport existe.
3. **Nettoyage fichiers** — attachements orphelins, `.tmp.wav` périmés.
4. **Compaction base** — `VACUUM` SwiftData.
5. **Statistiques disque** — visualiser ce qui prend de la place.

Toutes les opérations longues passent par `JobQueue` (kind `.maintenance` ou kinds existants `.report` / `.transcription` / `.diarization`) pour visibilité et annulation.

---

## 2. Décisions actées

| Choix | Valeur |
|---|---|
| Format compression cible | **AAC LC** `.m4a` mono 32 kbps 16 kHz (~250 KB/min) |
| Trigger cleanup | Manuel (bouton) **et** auto opt-in (toggle, off par défaut) |
| Override par réunion | Toggle simple `keepWavForever: Bool` |
| Délai compression par défaut | 7 jours (configurable) |
| Délai suppression par défaut | 30 jours (configurable) |
| Pré-condition cleanup | `meeting.summary` non vide (rapport généré) |
| Fonctions additionnelles | Batch transcribe + Stats disque + Cleanup orphelins + VACUUM |

---

## 3. Architecture

### 3.1 Services

```
OneToOne/Services/Maintenance/
  AudioCompressionService.swift     — AVAssetExportSession → .m4a AAC mono 32 kbps
  WavRetentionService.swift         — Filtrage meetings + orchestration compress/delete
  BatchJobsService.swift            — Enumérations "meetings sans X"
  StorageStatsService.swift         — Tailles disque (WAV / attachements / DB / slides)
  OrphanCleanupService.swift        — Attachements rows → fichiers manquants ; .tmp.wav
  DatabaseVacuumService.swift       — SwiftData VACUUM via SQLite
```

### 3.2 Modèle SwiftData (extensions)

```swift
// Meeting
var keepWavForever: Bool = false       // exclus du cleanup
var wavIsCompressed: Bool = false      // .m4a (vs .wav)

// AppSettings
var wavCompressionDays: Int = 7
var wavDeletionDays: Int = 30
var autoCleanupOnLaunch: Bool = false
var lastCleanupAt: Date?
```

Aucun nouveau modèle. Migration lightweight automatique.

### 3.3 État de disponibilité audio (centralisé sur Meeting)

```swift
extension Meeting {
    enum AudioAvailability {
        case original     // .wav présent
        case compressed   // .m4a présent
        case deleted      // wavFilePath nil ou fichier absent
    }
    var audioAvailability: AudioAvailability { ... }
    var hasPlayableAudio: Bool { audioAvailability != .deleted }
}
```

Tous les call-sites du player et des actions audio utilisent `.disabled(!meeting.hasPlayableAudio)` et un badge correspondant dans le header.

### 3.4 Intégration JobQueue

- Nouveau `JobKind.maintenance` (cap = 1).
- Le bouton "Lancer le cleanup" pousse **1 job parent** `.maintenance` qui orchestre les compressions / suppressions en série interne.
- Les boutons batch (rapport / transcription / diarisation) enqueuent **N jobs** de leur kind respectif ; la concurrence cap = 1 par kind les sérialise déjà.
- Tous visibles + annulables dans la sidebar.

---

## 4. Mise en page (Settings → Maintenance)

```
┌─────────────────────────────────────────────────────────────────┐
│  Maintenance                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  📊 STOCKAGE                                          [Actualiser]│
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  4.6 GB total                        │ │
│  │  ● 4.2 GB  Fichiers WAV (134)                              │ │
│  │  ● 380 MB  Attachements (87)                               │ │
│  │  ● 12 MB   Base de données                                 │ │
│  │  ● 8 MB    Slides capturées (12)                           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  🎙 TRAITEMENTS EN LOT                                           │
│                                                                  │
│  ⚠ 18 réunions sans rapport                                     │
│  [ Générer les rapports manquants ]                             │
│                                                                  │
│  ⚠ 7 réunions sans transcription                                │
│  [ Transcrire les réunions sans transcript ]                    │
│                                                                  │
│  ⚠ 23 réunions sans diarisation                                 │
│  [ Diariser les locuteurs ]                                     │
│                                                                  │
│  🧹 NETTOYAGE AUDIO                                              │
│                                                                  │
│  Compresser les WAV (AAC 32 kbps mono) après  [ 7 ] jours       │
│  Supprimer définitivement les WAV après       [ 30 ] jours      │
│  ☐ Lancer automatiquement au démarrage de l'app                 │
│                                                                  │
│  Sera affecté : 12 WAV à compresser (1.8 GB → ~380 MB)          │
│                 3 WAV à supprimer (450 MB)                       │
│                                                                  │
│  [ Aperçu détaillé… ]            [ Lancer le cleanup maintenant ]│
│                                                                  │
│  🗑 NETTOYAGE FICHIERS                                           │
│                                                                  │
│  ⚠ 3 attachements pointent vers des fichiers introuvables       │
│  [ Voir et nettoyer ]                                           │
│                                                                  │
│  ⚠ 2 fichiers .tmp.wav orphelins (412 MB)                       │
│  [ Supprimer ]                                                  │
│                                                                  │
│  💾 BASE DE DONNÉES                                              │
│                                                                  │
│  Dernière compaction : il y a 12 jours                          │
│  [ Compacter la base (VACUUM) ]                                 │
│                                                                  │
│  Dernier cleanup automatique : jamais                           │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Conventions visuelles

- 5 sous-sections, titre en uppercase secondary (pas un `GroupBox` par feature — trop visuellement lourd).
- Stats disque = barre horizontale segmentée + légende colorée (lecture 2 sec).
- Batch jobs : ⚠ orange + nombre + bouton `.borderedProminent` à droite.
- "Aperçu détaillé…" → sheet `List` paginée avec la liste des meetings affectés (titre, date, taille, action prévue, raison de skip).
- Tous les boutons "Lancer …" disabled tant qu'il y a un job `.maintenance` actif (visible dans la sidebar).

---

## 5. Cleanup audio — détails

### 5.1 Format compressé

- Container : `.m4a` (MPEG-4 Audio)
- Codec : AAC LC
- Sample rate : 16 kHz
- Channels : 1 (mono)
- Bitrate : 32 kbps
- Implémentation : `AVAssetExportSession` avec preset `AVAssetExportPresetAppleM4A` + custom output settings via `AVAssetWriter` si le preset ne suffit pas pour le bitrate cible.

### 5.2 Atomicité

1. Écrire `<basename>.compressing.m4a` (temp).
2. Vérifier `AVAudioFile(forReading: tmp).duration` ± 0.5 s vs original.
3. `FileManager.moveItem` → `<basename>.m4a` final.
4. Supprimer le `.wav` original.
5. Si étape 2 échoue : conserver le `.wav`, supprimer le `.m4a` partiel, log warning.

### 5.3 Préconditions cleanup (par meeting)

| Condition | Action si non remplie |
|---|---|
| `meeting.summary` non vide | Skip silencieux + log info |
| `!meeting.keepWavForever` | Skip silencieux |
| `recorder.activeMeetingID != meeting.ensuredStableID` | Skip + log "enregistrement en cours" |
| Aucun job actif sur ce meeting | Skip + log |
| Fichier `wavFilePath` existe | Si nil/absent → row patch `wavFilePath = nil`, pas de cleanup |

### 5.4 Impact UI (audio supprimé / compressé)

| État | Lecteur audio | Boutons audio | Badge header | Tooltip |
|---|---|---|---|---|
| `.original` | actif | tous actifs | — | — |
| `.compressed` | actif (.m4a lisible) | tous actifs | 🗜 "Audio compressé" gris | "Audio compressé (AAC 32 kbps) le DD/MM/YYYY" |
| `.deleted` | grisé | tous disabled | 🗑 "Audio archivé" gris | "Audio supprimé après 30 jours (politique de rétention). Rapport et transcription conservés." |

Boutons concernés à griser quand `.deleted` : Player (`MeetingContextualRecorderBar`), `Éditer l'audio…`, `Révéler le WAV dans Finder`, `Re-transcrire`, `Détecter les speakers`, bouton ▶ HH:MM des segments de transcription.

Bannière dans `MeetingView` si `.compressed` et l'utilisateur clique "Re-transcrire" : *"Audio compressé — qualité STT dégradée. Continuer ?"*

---

## 6. Traitements en lot — détails

### 6.1 Énumérations

| Énumération | Critères |
|---|---|
| Sans rapport | `summary.isEmpty && !rawTranscript.isEmpty && !isArchived` |
| Sans transcription | `rawTranscript.isEmpty && wavFilePath != nil && hasPlayableAudio && !isArchived` |
| Sans diarisation | `speakerAssignmentsJSON == "{}" && !transcriptSegments.isEmpty && hasPlayableAudio && !isArchived` |

### 6.2 Exécution

- Bouton clic → confirm modal "Lancer X jobs ? Cela peut prendre N minutes."
- Enqueue N jobs du kind correspondant via `JobQueue.start(...)`.
- Le cap=1 par kind les sérialise. Visible en sidebar.
- Compteur live mis à jour à chaque fin de job.

---

## 7. Nettoyage fichiers

### 7.1 Attachements orphelins

- Énumération : tous les `MeetingAttachment` (+ `InterviewAttachment`, `NoteAttachment`, etc.) dont `!FileManager.default.fileExists(atPath: filePath)`.
- Sheet liste + bouton "Supprimer N rows" → `context.delete(row)`.

### 7.2 `.tmp.wav` orphelins

- Énumération : `~/Library/Application Support/OneToOne/recordings/*.tmp.wav` avec `mtime > 5 min`.
- Bouton suppression directe (sans sheet, le contenu n'a pas de valeur).

---

## 8. Compaction base

- `DatabaseVacuumService.vacuum()` : ferme proprement le store SwiftData, exécute `PRAGMA optimize; VACUUM;` via SQLite direct sur le fichier `.store`, rouvre.
- Affiche le delta de taille avant / après.
- Disabled si un job actif (transcription/rapport/maintenance).

---

## 9. Stats disque

- `StorageStatsService.compute()` énumère récursivement :
  - WAV + M4A : `~/Library/Application Support/OneToOne/recordings/`
  - Attachements : tous les `filePath` des modèles `*Attachment`
  - Slides : `~/Library/Application Support/OneToOne/slides/`
  - DB : `~/Library/Application Support/OneToOne/default.store` + WAL + SHM
- Mis en cache 60 s. Bouton "Actualiser" force.

---

## 10. Erreurs gérées

| Cas | Comportement |
|---|---|
| Compression échoue (codec, disque plein) | `.wav` préservé, ligne rouge dans la sheet aperçu post-run |
| Suppression échoue | `wavFilePath` conservé, retry au prochain cleanup |
| Stats disque échouent | Section "—" + bouton Actualiser |
| VACUUM échoue | Alert error, base intacte |
| Orphan attachement → fichier réapparu entre énumération et delete | Skip (idempotent) |
| Cleanup auto à <24h depuis le dernier | Skip silencieux |

---

## 11. Tests

### 11.1 Unitaires

| Suite | Périmètre |
|---|---|
| `AudioCompressionServiceTests` | Compress WAV synthétique → .m4a ; durée ±0.5s ; .wav supprimé après succès ; conservé en cas d'échec |
| `WavRetentionServiceTests` | Skip si `keepWavForever`, `summary` vide, audio nil ; respect des seuils |
| `BatchJobsServiceTests` | `meetingsWithoutReport/Transcript/Diarisation` cohérents |
| `StorageStatsServiceTests` | Somme correcte avec mock FileManager |
| `OrphanCleanupServiceTests` | Détecte rows pointant vers fichiers absents + `.tmp.wav` > 5 min |

### 11.2 Intégration

- Cleanup auto launch après 24h → `lastCleanupAt` MAJ, jobs enqueued.
- Cleanup auto launch dans les 24h → skip.
- 5 meetings éligibles compression → 5 jobs `.maintenance` enqueued sérialisés.
- Cancel pendant compression #3 → #1-#2 compressés, #3-#5 intacts.

### 11.3 Manuels

- Réunion 8j + rapport → `.wav` → `.m4a`, taille ÷ ~4.
- Même réunion, `keepWavForever = true` → skip.
- Réunion 31j sans rapport → skip (pas de delete sans rapport).
- Réunion 31j + rapport → wav supprimé, header affiche 🗑 "Audio archivé".
- Player audio disabled correctement, tooltip explicatif.

---

## 12. YAGNI / hors scope

- Pas de planification dans le calendrier (cron-style à H:M) — auto-launch suffit.
- Pas d'export ZIP des meetings (peut s'ajouter v2).
- Pas de cleanup voiceprints inutilisés (rare, faible impact disque).
- Pas de re-encoder vers Opus (gain marginal vs AAC, dep externe).
- Pas de progress par fichier dans la barre de stats (animation = bruit).

---

## 13. Livrables

| Livrable | État |
|---|---|
| Validation décisions §2 | À faire avant plan |
| Spec UI/UX validée (§4) | OK utilisateur |
| Spec techniques (§3, §5-§9) | À détailler dans le plan |
| Tests + fixtures | À définir dans le plan |
| Plan d'implémentation | Via `writing-plans` après validation utilisateur |
