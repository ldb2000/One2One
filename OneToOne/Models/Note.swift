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
