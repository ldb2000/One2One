# ADR : inventaire du pipeline RAG

- **Date** : 2026-09-05
- **Statut** : accepté (lecture seule du code existant — pas de changement)
- **Décision** : cartographier l'existant pour servir de référence aux évolutions RAG
- **Contexte de l'audit** : l'utilisateur rapporte que « l'agent ne retrouve pas les informations » dans les notes / transcript / rapport / documents joints. Le présent ADR décrit **ce qui existe**, **ce qui coince**, et **les pistes d'évolution** (B1, B2, B3, C, D).

## 1. État du pipeline au 2026-09-05

### 1.1 Composants existants

| Couche | Fichier(s) | Rôle |
|---|---|---|
| Chunking | `Services/RAGService.swift` (`TextChunker`) | Découpe 2000 chars / 200 overlap, paragraphes puis phrases |
| Embeddings | `Services/EmbeddingService.swift`, `Services/MLXEmbeddingEngine.swift` | MLX in-process `intfloat/multilingual-e5-base` (préfixes `query:` / `passage:`) ou Ollama legacy (`nomic-embed-text`) |
| Vector store | `Models/MeetingModels.swift` (`@Model TranscriptChunk`) | SwiftData, embedding Float32 stocké dans `Data`, dim 768 |
| Indexation meetings | `Services/RAGService.swift` (`RAGIndexer.reindex`) | Appelé depuis `Views/MeetingView.swift`, `Views/RAGChatView.swift` |
| Indexation attachments | `Services/MeetingAttachmentService.swift` | PDF/PPTX/DOCX/XLSX/TXT/MD → `extractedText` → chunks `sourceType=attachment` |
| Indexation mails | `Services/ProjectMailStore.swift` | Chunks `sourceType=mail` (corps du mail) |
| Search | `Services/RAGService.swift` (`RAGQuery.search`) | Cosine en mémoire, `Scope` multi-critères (project / collaborator / kind / exclude / meetingPID / sourceType) |
| UI RAG | `Views/RAGChatView.swift` | Top-6 → injection prompt → `AIClient.send` → réponse avec citations |
| Transport LLM | `Services/AI/OpenAICompatibleClient.swift` | OpenAI-compatible, LM Studio / OpenRouter / Ollama |

### 1.2 Modèle `TranscriptChunk` (extrait)

```swift
@Model
final class TranscriptChunk {
    var text: String
    var embeddingData: Data?     // Float32 contigu, dim=768 (e5-base)
    var embeddingModel: String   // "intfloat/multilingual-e5-base"
    var embeddingDim: Int
    var sourceType: String       // "meeting" | "attachment" | "mail"
    var meeting: Meeting?
    var attachment: MeetingAttachment?
    var mail: ProjectMail?
    // ...
}
```

### 1.3 Métriques base (backup `2026-08-10-fusion-note`, snapshot représentatif)

```
Total chunks              : 3 507
Avec embedding            : 3 507 (100 %)
Sans embedding            :     0
Modèles d'embedding        : 1 (e5-base multilingue, dim 768)
Répartition sourceType :
  - meeting       : 1 232 chunks (liés à 1 234 meetings)
  - mail          : 2 273 chunks
  - attachment    :     2 chunks  ← très peu, à investiguer
Orphelins (aucune relation):     0
```

> **Note** : 2 attachments indexés seulement — l'ingestion de pièces jointes n'est manifestement **pas** déclenchée systématiquement. Hypothèse : ça n'arrive que via drag-drop explicite, pas sur l'ensemble des documents du dossier `attachments/`.

## 2. Ce qui coince — diagnostic

### 2.1 Le RAG n'est utilisé QUE par une vue dédiée

`RAGChatView.swift` est le seul point d'entrée. L'**agent conversationnel principal** (présumé dans `MeetingView`, dans les notes Markdown, ailleurs) **ne déclenche jamais `RAGQuery.search`**.

Conséquence : si « l'agent » dont parle l'utilisateur est le chat LLM inline (pas la vue Assistant RAG), alors le RAG n'est pas en cause — il n'est tout simplement **pas branché**. La cause est alors l'absence de hook RAG dans le code d'appel LLM général.

### 2.2 Le transport LLM rejette les tool_calls

`OpenAICompatibleClient.swift:83` :

```swift
guard choice.message?.refusal == nil,
      choice.message?.tool_calls?.isEmpty != false else { throw AIEndpointError.refused }
```

Et `requestBody` (ligne 94) ne déclare **aucun tool** dans la requête. Conséquence :

- Le transport **rejette** toute réponse contenant `tool_calls` (anti-pattern).
- Le LLM n'a aucune fonction `search_knowledge` exposée → même s'il voulait chercher, il ne sait pas qu'il peut.

→ **Pas de tool calling fonctionnel aujourd'hui.** Pour l'avoir, il faut :
1. Déclarer un tool dans `requestBody` (champ `tools`).
2. Retirer / inverser le guard anti-`tool_calls`.
3. Implémenter la boucle agentique (appel → résultat tool → 2e tour LLM).

### 2.3 L'injection est manuelle et one-shot

`RAGChatView.search` fait :
1. `RAGQuery.search(query, topK:6)` → top-6
2. Construit un prompt avec les 6 extraits
3. Un seul appel LLM
4. Affiche la réponse + les sources

C'est de la **RAG manuelle single-shot**. Pas de raffinement itératif, pas de re-query si le LLM dit « je n'ai pas assez d'info ».

### 2.4 Indexation des notes Markdown : pas de hook visible

L'éditeur de blocs vit dans `OneToOne/Markdown/`. Aucun fichier de ce module ne référence `RAGIndexer.reindex`, `EmbeddingService`, ni `TranscriptChunk`. Les notes live ne sont donc **pas indexées automatiquement** au fil de l'eau — l'export Markdown doit probablement être branché à la main (et la fonction n'est peut-être pas implémentée).

### 2.5 100 % cosine — pas de recherche lexicale

Aucune trace de BM25, FTS5, ni hybrid search. Pour les noms propres, acronymes, identifiants techniques, cosine seule rate souvent la cible. C'est précisément ce que fait open-notebook (BM25 + cosine via Reciprocal Rank Fusion).

## 3. Évolutions proposées

### B1 — Pre-fetch RAG automatique dans l'agent (rapide)

**Périmètre** : avant chaque `AIClient.send(prompt:)` issu de l'agent conversationnel principal, déclencher `RAGQuery.search(query, topK:6)` et préfixer le prompt avec les 6 extraits.

**Où brancher** : point d'entrée unique du transport (ex. wrapper autour de `AIClient.send`, ou hook ajouté directement dans `OpenAICompatibleClient`).

**Effort** : ~30-50 lignes, 1 fichier modifié + tests. Risque : injections contexte qui pourraient diluer le signal si la requête n'est pas RAG-friendly. Mitigation : ne déclencher le pre-fetch que si l'appel provient de l'agent conversationnel (pas des outils internes type résumé).

**Critère d'acceptation** : ouvrir MeetingView → poser une question sur un meeting passé → la réponse cite des extraits de transcripts indexés.

### B2 — Tool calling `search_knowledge` (structurant)

**Périmètre** : transformer `OpenAICompatibleClient` pour accepter un cycle tool-call. Déclarer un tool `search_knowledge(query: str, scope: optional[Scope]) -> [chunks]`. Implémenter le routage LLM → tool → LLM.

**Effort** : 150-250 lignes (transport + handler tool + tests), 3-4 fichiers touchés (`OpenAICompatibleClient.swift`, `AIClient.swift`?, nouveau `Services/AI/ToolRouter.swift`?, modèles de tools). ~1 journée.

**Critère d'acceptation** : l'agent peut effectuer plusieurs recherches successives dans un même tour, raffiner sa requête, et synthétiser une réponse multi-sources.

### B3 — Hybrid search (BM25 + cosine via RRF)

**Périmètre** : ajouter un index lexical (SQLite FTS5 sur `ZTRANSCRIPTCHUNK.ZTEXT` par exemple, ou tokenizer Swift en mémoire), combiner avec cosine via Reciprocal Rank Fusion (poids 0.5/0.5 ou 0.7 cosine / 0.3 BM25).

**Effort** : 80-150 lignes, 1-2 fichiers. Compatible avec B1 et B2.

**Critère d'acceptation** : recherche d'un acronyme ou nom propre retourne des chunks pertinents même si la similarité cosine est faible (parce que la requête lexicale matche exactement).

### C — Hook d'indexation des notes Markdown live

**Périmètre** : à chaque save du document Markdown (debounce ~2s), extraire les blocs texte (pas les images, pas les diagrammes Mermaid), passer dans `TextChunker` + `EmbeddingService`, persister en `TranscriptChunk(sourceType: "note")` avec relation vers un nouveau modèle `Note` ou vers `Meeting`/`Project` selon le contexte.

**Effort** : 100-200 lignes, 1-2 fichiers (hook dans `Markdown/`, extension `RAGIndexer`). Indépendant de B1/B2.

### D — Batch d'indexation globale

**Périmètre** : utiliser le `BatchJobsService` existant pour scanner périodiquement (ou à la demande) les sources non indexées et déclencher un `reindex` en masse. Utile après import, après restore, après changement de modèle.

**Effort** : ~50 lignes, branchement sur `BatchJobsService`. Indépendant de B1/B2/B3/C.

## 4. Priorisation recommandée

| # | Action | Pourquoi | Effort |
|---|---|---|---|
| 1 | Diagnostic base live | Confirmer ce que contient la base actuelle vs le backup 2026-08-10 | 5 min, read-only |
| 2 | B1 | Quick win, débloque 80 % des usages conversationnels | ~1 h |
| 3 | C | Sans indexation des notes, le RAG est incomplet | ~1-2 j |
| 4 | B2 | Permet recherche multi-tour et raffinement | ~1 j |
| 5 | B3 | Qualité sur noms propres / acronymes | ~0.5-1 j |
| 6 | D | Assurance qualité après import/restore | ~0.5 j |

## 5. Annexes

### 5.1 Référence open-notebook

`https://github.com/lfnovo/open-notebook` — Python, base de stack différente (FastAPI + SurrealDB + embeddings multiples). Les **idées transférables** : hybrid search, multi-source indexing, citations structurées, scope dynamique. Pas la stack.

### 5.2 ADR liées
- `2026-09-05-endpoints-ia-configurables.md` — endpoints LLM configurables
- `2026-09-05-raisonnement-configurable.md` — niveau de raisonnement par profil
- `2026-09-05-catalogues-ia-retrait-direct.md` — retrait du moteur Direct / Gemma4Swift