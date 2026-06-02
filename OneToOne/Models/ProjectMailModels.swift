import Foundation
import SwiftData

/// A mail ingested for a project (RAG source).
/// Dédupliqué sur `messageId` (identifiant Mail.app, supposé unique) : un
/// réimport du même message fait un upsert plutôt qu'un doublon (cf.
/// `ProjectMailStore.save`). Le corps est indexé en chunks pour le RAG.
@Model
final class ProjectMail {
    /// Identifiant du message tel que fourni par Mail.app. Clé de déduplication.
    var messageId: String
    var accountName: String
    var mailbox: String
    var subject: String
    var sender: String
    var dateReceived: Date
    var body: String = ""
    /// Sujet normalisé (préfixes Re:/Fwd: retirés) servant à regrouper les
    /// messages d'une même conversation.
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

/// Pièce jointe d'un `ProjectMail`. Le fichier est extrait de Mail.app et copié
/// sur disque par `MailService.saveAttachments` ; `filePath` pointe vers cette
/// copie locale (et sert aussi de clé d'unicité lors de la synchro). Aucun
/// security-scoped bookmark : le fichier appartient au container de l'app.
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
