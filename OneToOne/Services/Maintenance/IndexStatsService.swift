import Foundation
import SwiftData

/// Comptages d'état de l'index RAG (mails, suggestions, chunks) pour les vues
/// de réglages. Namespace pur — fetch-all + comptage en mémoire (volume
/// faible ; à revoir si l'index dépasse ~50k chunks).
@MainActor
enum IndexStatsService {

    struct Stats: Equatable {
        var indexedMails: Int = 0
        var pendingSuggestions: Int = 0
        var totalChunks: Int = 0
        var staleChunks: Int = 0
    }

    static func snapshot(in context: ModelContext) -> Stats {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        let suggestions = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let chunks = (try? context.fetch(FetchDescriptor<TranscriptChunk>())) ?? []
        return Stats(
            indexedMails: mails.count,
            pendingSuggestions: suggestions.count,
            totalChunks: chunks.count,
            staleChunks: BatchJobsService.staleChunks(in: context).count
        )
    }
}
