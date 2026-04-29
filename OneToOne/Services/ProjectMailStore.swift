import Foundation
import SwiftData

@MainActor
enum ProjectMailStore {
    static func save(
        snippet: MailSnippet,
        body: String,
        attachments: [MailAttachmentFile] = [],
        to project: Project,
        context: ModelContext
    ) async throws -> (mail: ProjectMail, wasInserted: Bool) {
        let descriptor = FetchDescriptor<ProjectMail>()
        let existing = (try? context.fetch(descriptor)) ?? []

        if let mail = existing.first(where: { $0.messageId == snippet.messageId }) {
            mail.accountName = snippet.accountName
            mail.mailbox = snippet.mailbox
            mail.subject = snippet.subject
            mail.sender = snippet.sender
            mail.dateReceived = snippet.dateReceived
            mail.body = body
            mail.threadTopic = normalizedThreadTopic(for: snippet.subject)
            mail.project = project
            syncAttachments(attachments, into: mail, context: context)

            try context.save()
            try await reindex(mail: mail, context: context)
            return (mail, false)
        }

        let mail = ProjectMail(
            messageId: snippet.messageId,
            accountName: snippet.accountName,
            mailbox: snippet.mailbox,
            subject: snippet.subject,
            sender: snippet.sender,
            dateReceived: snippet.dateReceived,
            body: body,
            threadTopic: normalizedThreadTopic(for: snippet.subject)
        )
        mail.project = project
        syncAttachments(attachments, into: mail, context: context)
        context.insert(mail)
        try context.save()
        try await reindex(mail: mail, context: context)
        return (mail, true)
    }

    private static func syncAttachments(_ attachments: [MailAttachmentFile], into mail: ProjectMail, context: ModelContext) {
        guard !attachments.isEmpty else { return }
        let existingPaths = Set(mail.attachments.map(\.filePath))
        for attachment in attachments where !existingPaths.contains(attachment.path) {
            let model = ProjectMailAttachment(fileName: attachment.fileName, filePath: attachment.path)
            model.mail = mail
            context.insert(model)
        }
    }

    static func reindex(mail: ProjectMail, context: ModelContext) async throws {
        for chunk in mail.chunks {
            context.delete(chunk)
        }

        let header = """
        Sujet: \(mail.subject)
        Expéditeur: \(mail.sender)
        Date: \(mail.dateReceived.formatted(date: .abbreviated, time: .shortened))
        Projet: \(mail.project?.name ?? "")
        """
        let text = "\(header)\n\n\(mail.body)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            try context.save()
            return
        }

        let pieces = TextChunker.chunk(text)
        let vectors = try await EmbeddingService.embedBatch(pieces)

        for (index, piece) in pieces.enumerated() {
            let chunk = TranscriptChunk(text: piece, orderIndex: index, sourceType: "mail")
            chunk.mail = mail
            let vector = vectors[safe: index] ?? []
            if !vector.isEmpty {
                chunk.setEmbedding(vector, model: EmbeddingService.model)
            }
            context.insert(chunk)
        }

        try context.save()
    }

    static func normalizedThreadTopic(for subject: String) -> String {
        subject
            .replacingOccurrences(of: #"^(?i)\s*(re|tr|fwd|fw)\s*:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
