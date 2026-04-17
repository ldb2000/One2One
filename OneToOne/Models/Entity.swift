import Foundation
import SwiftData

@Model
final class Entity {
    var name: String
    var summary: String?

    @Relationship(deleteRule: .nullify, inverse: \Project.entity)
    var projects: [Project] = []

    init(name: String, summary: String? = nil) {
        self.name = name
        self.summary = summary
    }
}
