# Spec — Indexation automatique des mails (RAG) + embeddings MLX in-process

> Design validé le 2026-07-07. Périmètre : scan automatique de boîtes Mail.app
> sélectionnées, rattachement projet automatique/assisté, vectorisation via
> MLX in-process (remplace Ollama par défaut), matching ambigu délégué à
> Gemma 4 (`DirectLLMClient`).

## 1. Objectif & besoin

Aujourd'hui l'indexation de mails est **manuelle** : un mail à la fois, rattaché
à un projet via `MailBrowserView` → `ProjectMailStore.save` (chunk + embedding
→ `TranscriptChunk(sourceType: "mail")`).

Besoin validé :

- **Scan périodique en arrière-plan** des boîtes choisies, **mails lus
  uniquement**, historique limité configurable (défaut 90 jours).
- **Matchs projet sûrs** → rattachés et indexés automatiquement.
- **Matchs incertains** → file de validation utilisateur.
- **Mails sans match** → ignorés (non indexés), marqués évalués.
- **Vectorisation sans Ollama** : modèle d'embedding MLX in-process.
- **Gemma 4 MLX** (le moteur des rapports en mode « Directe ») classe les cas
  ambigus.

Hors périmètre (YAGNI) : indexation de mails sans projet, écoute temps réel de
Mail.app, autres clients mail qu'Apple Mail, ré-évaluation des mails déjà
traités.

## 2. Modèles de données (SwiftData, migration lightweight)

Deux nouveaux `@Model` dans `SchemaV1` (ajouts compatibles lightweight) :

### `MailIndexSuggestion`

Un match incertain en attente de validation. **Sans corps ni embedding** : le
corps (fetch AppleScript lent) n'est récupéré qu'à la validation.

| Champ | Type | Note |
|---|---|---|
| `messageId` | `String` | Clé de dédup (même sémantique que `ProjectMail.messageId`) |
| `accountName`, `mailbox` | `String` | Localisation Mail.app |
| `subject`, `sender`, `preview` | `String` | Affichage file de validation |
| `dateReceived` | `Date` | |
| `suggestedProject` | `Project?` | Relation nullify ; suggestion orpheline nettoyée |
| `confidence` | `Double` | Score du matcher (0–1) |
| `createdAt` | `Date` | |

### `MailScanRecord`

Trace d'évaluation : garantit qu'un mail n'est jamais re-traité.

| Champ | Type | Note |
|---|---|---|
| `messageId` | `String` | |
| `verdictRaw` | `String` | `attached` / `suggested` / `ignored` (+ wrapper calculé, convention projet) |
| `evaluatedAt` | `Date` | |

Purge : records dont `evaluatedAt` dépasse la fenêtre d'historique + 30 jours
(un mail hors fenêtre ne peut plus réapparaître dans un scan).

### `AppSettings` — nouveaux champs (valeurs par défaut → lightweight)

| Champ | Défaut |
|---|---|
| `mailAutoIndexEnabled: Bool` | `false` |
| `mailAutoIndexMailboxesJSON: String` | `"[]"` (tableau de `MailboxRef` encodés) |
| `mailAutoIndexLookbackDays: Int` | `90` |
| `mailAutoIndexIntervalMinutes: Int` | `60` |
| `mailAutoIndexAutoThreshold: Double` | `0.75` |
| `mailAutoIndexSuggestThreshold: Double` | `0.45` |

La config d'embedding reste dans **`UserDefaults`** (pattern existant
d'`EmbeddingService`, qui est statique et sans `ModelContext`) :

| Clé | Défaut |
|---|---|
| `onetoone_embedding_backend` | `"mlx"` (`mlx` / `ollama`) |
| `onetoone_embedding_model` (existante) | `"nomic-ai/nomic-embed-text-v1.5"` en mode MLX ; `"nomic-embed-text"` en mode Ollama |

## 3. Scan (extension `MailService`)

Nouvelle variante du script AppleScript de `listRecent` avec deux filtres côté
Mail : **`read status is true`** et **date de réception ≥ cutoff**
(`now - lookbackDays`). Retourne des `MailSnippet` **sans corps**, boîte par
boîte parmi celles sélectionnées.

Le corps + pièces jointes ne sont récupérés (`fetchBody`, `saveAttachments`)
que dans deux cas : rattachement automatique, ou validation d'une suggestion.

## 4. Matching — pipeline à deux étages

### Étage 1 : heuristiques (`MailProjectMatcher`, `enum` pur, testable)

Trois signaux, le meilleur score gagne :

1. **Continuité de fil** (confiance 0,95) : un `ProjectMail` existant avec le
   même `threadTopic` normalisé (`ProjectMailStore.normalizedThreadTopic`) →
   même projet.
2. **Sujet ↔ projet** : tokens + Jaro-Winkler sur nom/code projet, en
   réutilisant la logique de `ProjectMatchService.bestProjectMatch`.
3. **Expéditeur ↔ collaborateurs du projet** : email expéditeur comparé aux
   emails des collaborateurs rattachés (`collaboratorEntries`, chef de projet,
   architecte technique) → bonus sur un match sujet, ou match faible seul.

Fonction pure : reçoit des entrées préparées (projets avec tokens/emails,
carte `threadTopic → Project` des fils déjà rattachés) — testable sans
`ModelContext`.

Si le score heuristique ≥ `autoThreshold` → rattachement direct **sans appel
LLM** (rapide, gratuit).

### Étage 2 : Gemma 4 pour les cas ambigus (`DirectLLMClient`)

Pour les mails sous le seuil auto : prompt de classification avec sujet +
expéditeur + aperçu + liste des projets candidats (code, nom, collaborateurs).
Réponse attendue en JSON strict :

```json
{"projectCode": "ABC123" | null, "confidence": 0.0}
```

- Parsing/normalisation de la réponse = fonction pure testée (tolérante aux
  fences markdown, JSON invalide → verdict `ignored` + log).
- Le verdict LLM alimente les **mêmes seuils** auto / suggestion / ignoré.
- Le modèle est chargé **une fois pour tout le lot** de mails ambigus de la
  passe ; s'il n'y a aucun mail ambigu, Gemma 4 n'est pas chargé.

### Décision finale

| Confiance (heuristique ou LLM) | Action |
|---|---|
| ≥ `autoThreshold` (0,75) | fetch corps + PJ → `ProjectMailStore.save` → record `attached` |
| ≥ `suggestThreshold` (0,45) | `MailIndexSuggestion` → record `suggested` |
| sinon | record `ignored` |

## 5. Orchestration (`MailAutoIndexService`, singleton `@MainActor`)

- **Déclenchement** : timer selon `mailAutoIndexIntervalMinutes` (app ouverte)
  + bouton « Scanner maintenant » (Réglages). Chaque passe = un job `JobQueue`
  (nouveau `JobKind.mailScan`, concurrence 1, progression + annulation).
- **Pipeline par boîte** :
  1. `listRecent` (lus, ≥ cutoff) ;
  2. exclusion des `messageId` déjà connus (`ProjectMail`,
     `MailIndexSuggestion`, `MailScanRecord`) ;
  3. matching étage 1 puis étage 2 ;
  4. décision (tableau ci-dessus).
- **Échec d'embedding** (modèle MLX absent, Ollama down en mode legacy) :
  `ProjectMailStore.save` propage → **pas de scan record écrit** → le mail est
  re-tenté à la passe suivante. Job en `failed(message)` explicite. Rien n'est
  perdu silencieusement.
- **Permission Automation refusée** : job `failed` avec le message d'aide de
  `MailError` existant.

## 6. UI

- **Réglages → section « Mails »** : toggle d'activation, sélection des boîtes
  (via `MailService.listMailboxes`), profondeur (jours), intervalle, seuils,
  bouton « Scanner maintenant », statut/date de la dernière passe.
- **File de validation** : sheet accessible depuis `MailBrowserView` (bouton
  avec badge = nombre de suggestions), pattern `ManagerActionReviewSheet` :
  liste groupée par projet suggéré, tri par date. Actions par suggestion :
  - **Valider** → fetch corps + PJ → `ProjectMailStore.save` → suppression de
    la suggestion + record `attached` ;
  - **Changer de projet** (picker) puis valider ;
  - **Ignorer** → suppression + record `ignored`.

## 7. Embeddings in-process MLX (remplace Ollama par défaut)

`EmbeddingService` devient un **routeur à deux backends**, piloté par la clé
`UserDefaults` `onetoone_embedding_backend` :

- **`.mlx` (défaut)** : `MLXEmbedders` (bibliothèque de `mlx-swift-lm`, déjà en
  dépendance — ajouter le produit dans `Package.swift`). Charge
  `nomic-ai/nomic-embed-text-v1.5` (~137 M params) depuis le cache HuggingFace
  habituel, chargement paresseux (pattern des moteurs STT), mean-pooling +
  normalisation fournis par la lib. **Préfixes nomic** appliqués :
  `search_document:` à l'indexation, `search_query:` à la requête
  (`RAGQuery.search`).
- **`.ollama` (legacy)** : code HTTP actuel conservé tel quel comme secours.

API publique inchangée (`embed`, `embedBatch`, `cosineSimilarity`) →
`RAGIndexer`, `ProjectMailStore`, `RAGQuery` non modifiés dans leurs appels.
`EmbeddingService.model` retourne l'identifiant effectif du backend courant
(stocké dans `TranscriptChunk.embeddingModel` comme aujourd'hui).

> ⚠️ Metal : MLX est déjà utilisé (STT, LLM direct) ; `default.metallib` est
> déjà embarqué par `Scripts/bump-and-build.sh`. Aucun changement de packaging.

## 8. Migration de l'index existant

Chaque chunk stocke son `embeddingModel`. Nouveau job de maintenance
« Ré-embedder l'index » (pattern `BatchJobsService`) : re-vectorise tous les
`TranscriptChunk` dont `embeddingModel` ≠ modèle courant. Idempotent,
relançable, annulable ; exposé dans Réglages → Maintenance avec compteur de
chunks obsolètes.

Nécessaire même à modèle identique : vecteurs Ollama et MLX non bit-à-bit
identiques + introduction des préfixes nomic — on ne mélange pas deux espaces
d'embedding. Tant que la migration n'a pas tourné, les chunks obsolètes restent
interrogeables (dégradé, comme aujourd'hui) ; le compteur rend l'état visible.

## 9. Notes qualité

- `nomic-embed-text-v1.5` est surtout entraîné sur l'anglais ; les contenus
  sont en français. Pas de régression (même modèle qu'avec Ollama), et
  `embeddingModelRepo` permet de tester un modèle multilingue supporté par
  `MLXEmbedders` (ex. `BAAI/bge-m3`) sans changer le code.
- Le scan peut être long (AppleScript ~secondes par lot, LLM si ambigus) :
  concurrence 1 sur `JobKind.mailScan`, progression visible dans
  `JobQueueSidebar`.
- `RAGQuery` charge tout en mémoire (limite documentée ~50k chunks) : la
  fenêtre d'historique limitée maîtrise le volume.

## 10. Tests

- **`MailProjectMatcherTests`** (pur) : continuité de fil, match tokens,
  bonus email expéditeur, seuils, absence de match.
- **Parsing réponse Gemma 4** (pur) : JSON strict, fences markdown, JSON
  invalide, `projectCode` inconnu.
- **Cycle de vie suggestions** (ModelContainer in-memory, pattern
  `SwiftDataTests`) : création, validation → `ProjectMail` + chunks, ignore,
  dédup par `messageId`, nettoyage suggestion orpheline (projet supprimé).
- **`MailScanRecord`** : dédup, purge au-delà de la fenêtre.
- **`EmbeddingService`** : routage backend, identifiant de modèle effectif,
  préfixes nomic appliqués côté indexation vs requête.
- **Job ré-embedding** : détection des chunks obsolètes, idempotence.

## 11. Découpage indicatif des livrables

1. `EmbeddingService` backend MLX + réglages + job de ré-embedding (autonome,
   valeur immédiate pour le RAG existant).
2. Modèles `MailIndexSuggestion` / `MailScanRecord` + extension `MailService`
   (scan lus/cutoff).
3. `MailProjectMatcher` (heuristiques) + étage Gemma 4.
4. `MailAutoIndexService` + `JobKind.mailScan` + timer.
5. UI : section Réglages « Mails » + file de validation.
