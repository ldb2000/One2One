import Foundation
import SwiftData

/// Note libre format markdown rattachée à un Projet OU un Collaborateur
/// (mutuellement exclusif au niveau applicatif). À ne pas confondre avec
/// `ProjectInfoEntry` (entrée datée typée par catégorie) ou
/// `ProjectCollaboratorEntry` (action/info collab dans contexte projet).
@Model
final class Note {
    var stableID: UUID? = nil
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    var project: Project?
    var collaborator: Collaborator?

    @Relationship(deleteRule: .cascade, inverse: \NoteAttachment.note)
    var attachments: [NoteAttachment] = []

    init(title: String = "",
         body: String = "",
         project: Project? = nil,
         collaborator: Collaborator? = nil,
         createdAt: Date = Date()) {
        self.stableID = UUID()
        self.title = title
        self.body = body
        self.project = project
        self.collaborator = collaborator
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

/// Pièce jointe d'une note. Le fichier est COPIÉ dans
/// `~/Library/Application Support/OneToOne/notes/<noteStableID>/...` à l'import,
/// donc `filePath` est un chemin local stable (pas de bookmark dépendant du
/// fichier original).
@Model
final class NoteAttachment {
    /// Optional — see SwiftData migration caveat. Use `ensuredStableID`
    /// when you need a guaranteed non-nil UUID.
    var stableID: UUID? = nil
    var fileName: String = ""
    var filePath: String = ""        // chemin absolu inside Application Support
    var importedAt: Date = Date()
    var note: Note?

    init(fileName: String, filePath: String) {
        self.stableID = UUID()
        self.fileName = fileName
        self.filePath = filePath
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    var url: URL { URL(fileURLWithPath: filePath) }
}
