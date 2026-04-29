import Foundation
import SwiftData

/// A mail ingested for a project (RAG source).
@Model
final class ProjectMail {
    var messageId: String
    var accountName: String
    var mailbox: String
    var subject: String
    var sender: String
    var dateReceived: Date
    var body: String = ""
    var threadTopic: String = ""

    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \ProjectMailAttachment.mail)
    var attachments: [ProjectMailAttachment] = []

    @Relationship(deleteRule: .cascade, inverse: \TranscriptChunk.mail)
    var chunks: [TranscriptChunk] = []

    init(
        messageId: String,
        accountName: String,
        mailbox: String,
        subject: String,
        sender: String,
        dateReceived: Date = Date(),
        body: String = "",
        threadTopic: String = ""
    ) {
        self.messageId = messageId
        self.accountName = accountName
        self.mailbox = mailbox
        self.subject = subject
        self.sender = sender
        self.dateReceived = dateReceived
        self.body = body
        self.threadTopic = threadTopic
    }
}

@Model
final class ProjectMailAttachment {
    var fileName: String
    var filePath: String
    var importedAt: Date = Date()
    var mail: ProjectMail?

    init(fileName: String, filePath: String) {
        self.fileName = fileName
        self.filePath = filePath
    }
}
