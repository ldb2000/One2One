import AppIntents
import SwiftData
import Foundation

/// Représentation d'un `Collaborator` exposée à App Intents / Shortcuts.
/// Identifiée par `Collaborator.stableID` (UUID stable, sûr à exposer).
struct CollaboratorEntity: AppEntity, Identifiable {
    var id: UUID
    var name: String
    var role: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: role.isEmpty ? nil : "\(role)"
        )
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Collaborateur")
    }

    static var defaultQuery = CollaboratorEntityQuery()
}

struct CollaboratorEntityQuery: EntityQuery, EntityStringQuery {

    @MainActor
    func entities(for ids: [CollaboratorEntity.ID]) async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { ids.contains($0.stableID) }
        )
        let collabs = (try? context.fetch(descriptor)) ?? []
        return collabs.map(Self.toEntity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? context.fetch(descriptor)) ?? []
        let q = string.lowercased()
        return all
            .filter { !$0.isArchived }
            .filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) }
            .map(Self.toEntity)
    }

    @MainActor
    func suggestedEntities() async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>(
            sortBy: [SortDescriptor(\.pinLevel, order: .reverse), SortDescriptor(\.name)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !$0.isArchived }.prefix(20).map(Self.toEntity)
    }

    private static func toEntity(_ c: Collaborator) -> CollaboratorEntity {
        CollaboratorEntity(id: c.stableID, name: c.name, role: c.role)
    }
}
