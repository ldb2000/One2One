import Foundation
import SwiftData

/// Validation / ignore des suggestions du scan automatique. Logique extraite
/// de la vue pour être testable : les accès Mail.app et la matérialisation
/// (ProjectMailStore) sont injectés via `Fetchers`.
@MainActor
enum MailSuggestionService {

    enum ValidationError: LocalizedError {
        case missingProject
        var errorDescription: String? { "Aucun projet sélectionné pour ce mail." }
    }

    struct Fetchers {
        var fetchBody: (MailIndexSuggestion) async throws -> String
        var fetchAttachments: (MailIndexSuggestion) async throws -> [MailAttachmentFile]
        var materialize: (MailSnippet, String, [MailAttachmentFile], Project, ModelContext) async throws -> Void

        static let live = Fetchers(
            fetchBody: { s in
                try await MailService.fetchBody(messageId: s.messageId,
                                                accountName: s.accountName,
                                                mailbox: s.mailbox)
            },
            fetchAttachments: { s in
                try await MailService.saveAttachments(messageId: s.messageId,
                                                      accountName: s.accountName,
                                                      mailbox: s.mailbox)
            },
            materialize: { snippet, body, attachments, project, context in
                _ = try await ProjectMailStore.save(snippet: snippet, body: body,
                                                    attachments: attachments,
                                                    to: project, context: context)
            }
        )
    }

    /// Valide une suggestion : fetch corps + PJ, matérialise un `ProjectMail`
    /// (pipeline chunk + embedding), trace le verdict, supprime la suggestion.
    /// En cas d'échec (fetch, embedding), lève SANS rien supprimer : la
    /// suggestion reste dans la file, re-tentable.
    static func validate(
        _ suggestion: MailIndexSuggestion,
        in context: ModelContext,
        fetchers: Fetchers = .live
    ) async throws {
        guard let project = suggestion.suggestedProject else {
            throw ValidationError.missingProject
        }
        let body = try await fetchers.fetchBody(suggestion)
        let attachments = (try? await fetchers.fetchAttachments(suggestion)) ?? []
        let snippet = MailSnippet(
            messageId: suggestion.messageId,
            accountName: suggestion.accountName,
            mailbox: suggestion.mailbox,
            subject: suggestion.subject,
            sender: suggestion.sender,
            dateReceived: suggestion.dateReceived,
            preview: suggestion.preview,
            body: nil)
        do {
            try await fetchers.materialize(snippet, body, attachments, project, context)
        } catch {
            // ⚠️ ProjectMailStore.save persiste le ProjectMail AVANT
            // l'embedding (reindex) : si l'embedding a échoué, un ProjectMail
            // sans chunks a pu être sauvé — il rendrait le messageId
            // « connu » à jamais sans jamais être indexé. On l'annule
            // explicitement (même nettoyage que MailAutoIndexService.runScan).
            if let halfSaved = ((try? context.fetch(FetchDescriptor<ProjectMail>())) ?? [])
                .first(where: { $0.messageId == suggestion.messageId && $0.chunks.isEmpty }) {
                context.delete(halfSaved)
                try? context.save()
            }
            throw error
        }
        MailScanStore.setVerdict(suggestion.messageId, verdict: .attached, in: context)
        context.delete(suggestion)
        try context.save()
    }

    /// Écarte une suggestion : verdict `.ignored` tracé (dédup conservée),
    /// suggestion supprimée.
    static func ignore(_ suggestion: MailIndexSuggestion, in context: ModelContext) {
        MailScanStore.setVerdict(suggestion.messageId, verdict: .ignored, in: context)
        context.delete(suggestion)
        try? context.save()
    }
}
