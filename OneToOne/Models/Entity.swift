import Foundation
import SwiftData

/// Entité métier (organisation, BU, client…) à laquelle des projets peuvent
/// être rattachés. Persistée via SwiftData.
@Model
final class Entity {
    var name: String
    /// Description libre optionnelle de l'entité (contexte, périmètre…).
    var summary: String?

    @Relationship(deleteRule: .nullify, inverse: \Project.entity)
    var projects: [Project] = []

    init(name: String, summary: String? = nil) {
        self.name = name
        self.summary = summary
    }
}
