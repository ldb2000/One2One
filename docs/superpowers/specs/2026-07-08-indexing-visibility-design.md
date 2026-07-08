# Spec — Visibilité de la progression d'indexation / vectorisation

> Design validé le 2026-07-08. Complément de la feature « scan auto des mails +
> embeddings MLX » (spec du 2026-07-07) : la progression existe dans la sidebar
> des jobs mais est invisible depuis les vues qui déclenchent les traitements.

## 1. Problème

- « Scanner maintenant » (Réglages → Mails) et « Ré-embedder l'index »
  (Maintenance) ne donnent aucun feedback local : pas de spinner, pas de
  progression, compteurs non rafraîchis pendant/après le job.
- Le job de ré-embedding est de kind `.maintenance` : non identifiable
  proprement depuis une vue (matching sur le titre = fragile).
- Aucune vue ne résume l'état de l'index (mails indexés, suggestions en
  attente, chunks vectorisés / obsolètes).

## 2. Solution

### 2.1 `JobKind.embedding` dédié

- Nouveau case `embedding` dans `JobQueue.JobKind` + entrée
  `maxConcurrentByKind[.embedding] = 1`.
- `JobQueueSidebar` : label « Ré-embedding », icône
  `point.3.connected.trianglepath.dotted` (cohérente avec la section
  Maintenance).
- `MaintenanceView.enqueueReembedStaleChunks` enfile désormais en
  `kind: .embedding` (titre inchangé).

### 2.2 Progression en direct près des boutons

Les deux vues observent la queue via `@ObservedObject var queue: JobQueue = .shared`.

- **`MailSettingsView`** : helper `activeScanJob` = premier job
  `kind == .mailScan` non terminal. S'il existe : la ligne du bouton
  « Scanner maintenant » est remplacée par `ProgressView` (fraction si
  disponible, sinon indéterminée) + `statusText` du job + bouton « Annuler »
  (`queue.cancel(job.id)`). Sinon : bouton normal (comportement actuel).
  Le libellé « Dernière passe » existant reste inchangé.
- **`MaintenanceView` (section EMBEDDINGS / RAG)** : helper
  `activeEmbeddingJob` = premier job `kind == .embedding` non terminal.
  S'il existe : `ProgressView` linéaire + statusText (« N/M chunks ») +
  « Annuler » à la place du `batchRow`. Sinon : `batchRow` actuel.
  Le compteur de chunks obsolètes se rafraîchit naturellement : la vue
  re-rend à chaque `@Published jobs` (fin de job incluse) et `staleChunks`
  est recalculé dans le corps de la vue.

### 2.3 Ligne d'état de l'index (section Mails)

En tête de `MailSettingsView`, une ligne de compteurs :

> « X mails indexés · Y suggestions en attente · Z chunks vectorisés
> (dont W obsolètes) »

- Données : nouveau namespace pur **`IndexStatsService`**
  (`@MainActor enum`, `Services/Maintenance/`) :
  `struct Stats { var indexedMails: Int; var pendingSuggestions: Int; var totalChunks: Int; var staleChunks: Int }`
  et `static func snapshot(in context: ModelContext) -> Stats`
  (fetch-all + comptages ; `staleChunks` réutilise
  `BatchJobsService.staleChunks(in:).count`).
- Rafraîchi au rendu (recalculé quand la vue re-rend, y compris aux
  transitions de jobs via l'observation de la queue). Volume faible —
  pas de cache TTL nécessaire (à revoir si > ~50k chunks, cf. note RAG).

## 3. Hors périmètre (YAGNI)

Dashboard d'indexation dédié, ventilation par projet, notifications de fin
de scan, progression des indexations silencieuses (import de pièces jointes,
RAGIndexer post-rapport).

## 4. Tests

- `IndexStatsServiceTests` (in-memory) : comptages exacts (mails avec/sans
  chunks, suggestions, chunks obsolètes vs à jour), store vide → zéros.
- Pas de test des vues (convention repo) ; `JobKind.embedding` est couvert
  par la compilation des switch exhaustifs.

## 5. Contraintes

- Aucun nouveau modèle SwiftData, aucune migration.
- Libellés UI en français ; conventions services du repo.
- Aucun test n'exerce MLX.
