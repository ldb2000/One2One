# Sub-projet 4 — Transcript Editing & Reporting Hints

**Date :** 2026-05-23
**Statut :** Design validé

## 1. Contexte

Le tab Transcript de `MeetingView` affiche les segments produits par Cohere STT + Pyannote diarization + SpeakerMatcher. Trois limitations actuelles motivent ce sub-projet :

1. **Sur-segmentation diarization** : Pyannote produit parfois plusieurs `clusterID` distincts pour la même voix réelle. `SpeakerMatcher` les remappe vers le même `Collaborator` (labels affichés identiques) mais `TurnAligner.align` ne fusionne pas car il compare par `clusterID` brut. Résultat : segments redondants de ~60s pour le même speaker.
2. **Pas de delete** : impossible de retirer un passage off-topic (vie privée, transcript erroné) avant génération du rapport.
3. **Pas de highlight** : l'utilisateur ne peut pas signaler explicitement au LLM les passages clés à privilégier dans le rapport.

## 2. Objectifs

- Réduire la sur-segmentation en réécrivant les `clusterID` post-matching vers un cluster canonique par collaborateur résolu, puis remerge.
- Permettre la suppression atomique d'un segment de transcript + splice de la portion correspondante du wav.
- Permettre de marquer un segment comme "important" pour le reporting, avec injection dans le prompt LLM via variable dédiée + marqueur inline.

## 3. Non-objectifs

- Edit du texte d'un segment (V2).
- Highlight sous-segment / range NSRange (V2 — granularité segment entier suffit).
- Undo de la suppression (V2 — confirmation préalable suffit).
- Re-clustering Pyannote au-delà du threshold actuel.

## 4. Architecture

### 4.1 Trois capabilités indépendantes

| # | Capability | Couche | Touchant |
|---|---|---|---|
| 1 | Canonicalize clusters | Backend transcription | `TurnAligner`, `TranscriptionService` |
| 2 | Delete segment | Service + UI + Audio | `TranscriptEditService` (nouveau), `AudioFileEditor`, `MeetingView` |
| 3 | Highlight segment | Model + UI + Templating | `TranscriptSegment`, `MeetingView`, `ReportTemplating`, `TranscriptHighlightsBuilder` (nouveau) |

Les capabilities 2 et 3 partagent l'entry point UI : menu contextuel du badge speaker (option clic droit) dans `segmentRow`. Pas de conflit avec `.textSelection(.enabled)` car le clic droit sur le badge n'est pas absorbé par la sélection de texte.

### 4.2 Pourquoi un seul sub-projet

Les 3 features touchent toutes le `TranscriptSegment`, son rendu dans `MeetingView.segmentRow`, et son flux vers `AIReportService`. Les regrouper évite trois migrations de modèle distinctes et trois passes UI sur le même row.

## 5. Modèle

### 5.1 `TranscriptSegment`

Ajout d'un champ :
```swift
var isHighlighted: Bool = false
```

SwiftData non-Optional Bool avec default. Pas de migration explicite — la colonne est ajoutée transparente au prochain ouverture du store.

### 5.2 `AppSettings`

`diarizationClusterThreshold` existant (Double, default 0.85) — default bascule à **0.70** pour réduire la sur-segmentation. Sémantique speech-swift à confirmer au moment du fix (si "similarity" → 0.70 = plus permissif ; si "distance" → l'inverse).

## 6. Services

### 6.1 `TurnAligner.swift` (refactor)

Extraction du merge en helper public réutilisable :

```swift
static func mergeConsecutive(_ segments: [AlignedSegment]) -> [AlignedSegment]
```

Contient la boucle de fusion actuelle (lignes 36–56). `align(chunks:turns:)` appelle `mergeConsecutive` en fin.

Pas de changement de comportement public sur `align`.

### 6.2 `TranscriptionService.canonicalizeClusters`

Nouveau helper privé :

```swift
private func canonicalizeClusters(
    _ aligned: [TurnAligner.AlignedSegment],
    assignments: [Int: SpeakerMatcher.Assignment]
) -> [TurnAligner.AlignedSegment]
```

Algorithme :
1. Parcours `assignments`. Pour chaque cluster avec `collaborator != nil`, construit `[Collaborator.persistentModelID: Int]` (1er clusterID rencontré pour ce collab → cluster canonique).
2. Pour chaque `AlignedSegment` :
   - Lookup `assignment[seg.clusterID]?.collaborator`. Si trouvé, lookup map canonique → réécrit `seg.clusterID = canonical`.
   - Sinon (cluster non mappé à un collab) : laisse tel quel.
3. Re-merge via `TurnAligner.mergeConsecutive(rewritten)`.

Insertion dans `transcribe()` ligne 350–361 :
```swift
let aligned = TurnAligner.align(chunks: chunks, turns: diarOutput.turns)
let assignments = SpeakerMatcher.match(...)
let canonical = canonicalizeClusters(aligned, assignments: assignments)  // NEW
persistAlignedSegments(aligned: canonical, ...)
```

### 6.3 `AudioFileEditor.cut` (nouveau)

```swift
static func cut(url: URL, from fromSec: Double, to toSec: Double) async throws
```

Supprime in-place la portion `[fromSec, toSec]` du wav. Implémentation :
1. `split(url:at:fromSec)` → `(headURL, tailFullURL)`
2. `split(url: tailFullURL, at: toSec - fromSec)` → `(removedURL, tailURL)`
3. Concat `headURL + tailURL` → fichier temporaire
4. Remplace `url` par le temporaire
5. Cleanup `removedURL`, `tailFullURL`

Alternative plus simple via AVFoundation `AVMutableComposition` (recommandée si dispo dans le projet). À choisir au moment de l'implémentation.

### 6.4 `TranscriptEditService.swift` (nouveau)

```swift
enum TranscriptEditService {
    static func deleteSegment(
        _ seg: TranscriptSegment,
        in meeting: Meeting,
        context: ModelContext
    ) async throws
}
```

Algorithme :
1. `removedDuration = seg.endSeconds - seg.startSeconds`.
2. Si `meeting.wavFileURL` existe et `meeting.audioAvailability == .original` :
   - `try await AudioFileEditor.cut(url: wavURL, from: seg.startSeconds, to: seg.endSeconds)`.
   - Sinon (audio absent/compressé) : skip splice, alerte info "Audio non disponible, suppression texte seul".
3. Pour chaque `TranscriptSegment` `other` de `meeting` où `other.startSeconds >= seg.endSeconds` :
   - `other.startSeconds -= removedDuration`
   - `other.endSeconds -= removedDuration`
4. `context.delete(seg)`.
5. `try context.save()`.

Erreur splice → ne pas delete segment, throw vers caller, transcript intact.

### 6.5 `TranscriptHighlightsBuilder.swift` (nouveau)

```swift
enum TranscriptHighlightsBuilder {
    static func build(meeting: Meeting) -> String
}
```

Format de sortie :
```
[mm:ss · Nom du Speaker] Texte du segment highlighted
[mm:ss · Nom du Speaker] Autre passage
```

Vide → `""`. Pas de title heading (caller wraps si besoin).

### 6.6 `ReportTemplating.swift`

Ajout case dans `TemplateVariableResolver.resolveOne` :
```swift
case "transcript.highlights":
    return TranscriptHighlightsBuilder.build(meeting: meeting)
```

Modification du rendu `{{transcript}}` : pour chaque segment où `isHighlighted == true`, entourer le texte avec `**[IMPORTANT]** ... **[/IMPORTANT]**`. Cherche la fonction qui construit `{{transcript}}` actuellement (probablement dans `TemplateVariableResolver` ou `MeetingTextRenderer`) et applique le wrap.

### 6.7 `AIReportService.swift`

Fallback append pour `{{transcript.highlights}}` symétrique aux fallbacks `collab.projects_context` / `team.projects_context` :
```swift
let hasHighlightsPlaceholder = body.contains("{{transcript.highlights}}")
if !hasHighlightsPlaceholder {
    let highlights = TranscriptHighlightsBuilder.build(meeting: meeting)
    if !highlights.isEmpty {
        historyAppendix += "\n\nPassages marqués importants par l'utilisateur :\n\(highlights)\n"
    }
}
```

## 7. UI

### 7.1 `MeetingView.speakerBadge` — menu étendu

Le `Menu` actuel attaché au badge speaker (existant pour rename speaker) gagne 2 items :

```
[Rename speaker submenu existant]
─────
⭐ Marquer comme important  / ☆ Retirer l'importance  (toggle selon état)
─────
🗑 Supprimer ce passage    [destructive]
```

Le delete déclenche une `Alert` de confirmation :
> "Supprimer ce passage ?"
> "Le texte et la portion audio correspondante seront supprimés définitivement."
> [Annuler] [Supprimer]

Sur confirm → `Task { try await TranscriptEditService.deleteSegment(...) }`.

### 7.2 `MeetingView.segmentRow` — affichage highlighted

Quand `seg.isHighlighted == true` :
- Badge speaker : `.background(Color.yellow.opacity(0.18))` au lieu de la couleur cluster habituelle.
- Texte segment : `.background(Color.yellow.opacity(0.08))` rectangle subtil.
- Icône ⭐ en bout de ligne (avant le `Spacer`).

### 7.3 `SettingsView.swift` — presets threshold

Section diarization existante (autour de la ligne 667) gagne, au-dessus du slider :

```
[Plus de speakers]  [Équilibré]  [Moins de speakers]
   (0.95)            (0.85)         (0.70)
Slider [- - - ● - - -]  0.70
```

Boutons fixent `settings.diarizationClusterThreshold` à 0.95 / 0.85 / 0.70. Label du bouton actif (valeur courante = preset) marqué `.fontWeight(.bold)`.

## 8. Data flow

### 8.1 Transcription run avec canonicalize

```
STT (Cohere) → chunks: [STTChunkInput]
                ↓
Diarization (Pyannote) → turns: [DiarTurn] avec clusterID brut
                ↓
TurnAligner.align(chunks, turns)
                ↓
aligned: [AlignedSegment]   ← clusterID brut Pyannote
                ↓
SpeakerMatcher.match → assignments: [Int: Assignment]
                ↓
canonicalizeClusters(aligned, assignments)  ← NEW
                ↓
canonical: [AlignedSegment]   ← clusterID canonique par collab
                ↓
persistAlignedSegments(canonical)
                ↓
[TranscriptSegment] avec speakerID canonique, mergés
```

### 8.2 Delete segment

```
User clic droit badge → Menu "Supprimer ce passage"
                ↓
Alert confirm → Supprimer
                ↓
Task { TranscriptEditService.deleteSegment(seg) }
                ↓
AudioFileEditor.cut(wav, seg.start, seg.end)        ┐
                ↓                                    │ atomique
shift startSec/endSec des segments postérieurs       │
                ↓                                    │
context.delete(seg) + save()                         ┘
                ↓
@Query refresh → UI update
```

### 8.3 Highlight LLM injection

```
User marque seg → seg.isHighlighted = true → save
   ...
Generate report → AIReportService.generate
                ↓
resolveOne("transcript.highlights") → TranscriptHighlightsBuilder.build(meeting)
   liste formatée [mm:ss · Speaker] texte
                ↓
resolveOne("transcript") → segments rendus, highlighted entourés **[IMPORTANT]**...**[/IMPORTANT]**
                ↓
si template ne contient pas {{transcript.highlights}}:
   fallback append historyAppendix
                ↓
Prompt LLM final avec double signal (variable dédiée + marqueur inline)
```

## 9. Error handling

| Cas | Comportement |
|---|---|
| Delete sans audio (wav purgé maintenance) | Alert info "Audio non disponible, seul le texte est supprimé". Splice skip, delete texte + save. |
| Delete avec audio compressé `.compressed` | Idem ci-dessus. On ne splice pas un m4a (V2). |
| `AudioFileEditor.cut` throw I/O | Pas de delete segment. Alert erreur. Transcript et wav intacts. |
| `canonicalizeClusters` avec assignments vide ou aucun mapping | No-op pass-through, `aligned` retourné inchangé. |
| Highlight toggle | Pas d'erreur possible (bool flip + save). |
| `TranscriptHighlightsBuilder.build` aucun highlighted | Retourne `""`. Fallback append no-op. |

## 10. Testing

### 10.1 Unit tests

**TurnAlignerTests** (nouveau ou ajout) :
- `mergeConsecutive_emptyInput_returnsEmpty`
- `mergeConsecutive_singleSegment_returnsSingle`
- `mergeConsecutive_mergesAdjacentSameCluster`
- `mergeConsecutive_preservesDistinctClusters`

**CanonicalizeClustersTests** (nouveau) — 3 tests critiques :
- `canonicalize_noAssignments_returnsInputUnchanged`
- `canonicalize_twoClustersOneCollab_unifiesToCanonical` : 2 clusters distincts → même collab → segments réécrits avec clusterID canonique unique.
- `canonicalize_twoAdjacentClustersOneCollab_remergesIntoSingleSegment` : le test critique — vérifie qu'après canonicalize + remerge, 2 segments adjacents `00:00-01:00` cluster A et `01:00-02:00` cluster B (même collab) deviennent UN segment `00:00-02:00`.

**TranscriptEditServiceTests** (nouveau) :
- `delete_shiftsLaterSegmentsByRemovedDuration` : segments after shift down by `endSec-startSec`.
- `delete_doesNotShiftEarlierSegments` : segments before unchanged.
- `delete_savesContext_segmentRemoved`
- `delete_audioMissing_deletesTextOnly_noThrow` : `wavFileURL == nil` → delete OK, pas d'appel `cut`.

**TranscriptHighlightsBuilderTests** (nouveau) :
- `build_noHighlights_returnsEmpty`
- `build_oneHighlight_formatsTimestampSpeakerText` : format `[mm:ss · Nom] texte`.
- `build_multipleHighlights_preservesOrderByStartSec`

### 10.2 Tests UI (smoke manuel, hors scope auto)

Smoke checklist dans plan d'implémentation : retranscribe une réunion `.work` 5min avec 2 voix, vérifier réduction du nombre de segments ; clic droit badge → Supprimer → wav raccourci de la durée du segment ; toggle Marquer important → badge jaune ; générer rapport → prompt LLM contient `{{transcript.highlights}}` peuplé.

## 11. Migration

Aucune migration SwiftData explicite. Champ `isHighlighted: Bool = false` ajouté sur `TranscriptSegment` — colonne ajoutée transparente. Pas de bump revision.

## 12. YAGNI

Hors scope :
- Edit du texte d'un segment.
- Highlight range NSRange / sous-segment.
- Undo delete.
- Re-cluster Pyannote (tuning threshold uniquement).
- Splice audio compressé m4a.
- Bulk delete / bulk highlight.

## 13. Dépendances inter-tâches (pour le plan)

```
Task 1 (Refactor TurnAligner.mergeConsecutive)
    ↓
Task 2 (canonicalizeClusters + tests TDD)
    ↓
Task 3 (Wire dans TranscriptionService.transcribe)

Task 4 (TranscriptSegment.isHighlighted field)
    ↓
Task 5 (TranscriptHighlightsBuilder + tests)
    ↓
Task 6 (case transcript.highlights + wrap [IMPORTANT] dans {{transcript}})
    ↓
Task 7 (AIReportService fallback append)
    ↓
Task 8 (UI badge highlighted + menu items toggle highlight)

Task 9 (AudioFileEditor.cut)
    ↓
Task 10 (TranscriptEditService.deleteSegment + tests)
    ↓
Task 11 (UI menu "Supprimer ce passage" + alert)

Task 12 (SettingsView presets threshold + default 0.70)

Task 13 (Final build + smoke)
```

Tasks 1–3, 4–8, 9–11, 12 sont 4 groupes largement indépendants — exécution séquentielle par groupe ou parallèle inter-groupes selon préférence.
