import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

final class SpotlightIndexService {
    static let shared = SpotlightIndexService()

    /// Re-index all projects + collaborators at once (call on app startup).
    func indexAll(projects: [Project], collaborators: [Collaborator]) {
        var items: [CSSearchableItem] = []
        for project in projects {
            items.append(makeProjectItem(project))
            items.append(contentsOf: project.infoEntries.map { makeInfoItem($0, project: project) })
            items.append(contentsOf: project.collaboratorEntries.map { makeCollaboratorEntryItem($0, project: project) })
        }
        for collab in collaborators where !collab.isArchived {
            items.append(makeCollaboratorItem(collab))
        }
        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[Spotlight] Bulk indexing failed: \(error)")
            } else {
                print("[Spotlight] Indexed \(items.count) items (\(projects.count) projects, \(collaborators.count) collaborators)")
            }
        }
    }

    /// Check how many items are currently indexed (for diagnostics).
    func fetchIndexedItemCount(completion: @escaping (Int) -> Void) {
        let queryContext = CSSearchQueryContext()
        queryContext.fetchAttributes = ["displayName"]
        let query = CSSearchQuery(queryString: "domainIdentifier == 'projects' || domainIdentifier == 'project-info' || domainIdentifier == 'project-collaborator-info' || domainIdentifier == 'collaborators'", queryContext: queryContext)
        var count = 0
        query.foundItemsHandler = { items in
            count += items.count
        }
        query.completionHandler = { error in
            if let error {
                print("[Spotlight] Query failed: \(error)")
            }
            DispatchQueue.main.async { completion(count) }
        }
        query.start()
    }

    func index(project: Project) {
        var items: [CSSearchableItem] = [makeProjectItem(project)]
        items.append(contentsOf: project.infoEntries.map { makeInfoItem($0, project: project) })
        items.append(contentsOf: project.collaboratorEntries.map { makeCollaboratorEntryItem($0, project: project) })

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[Spotlight] Indexing failed: \(error)")
            }
        }
    }

    func remove(project: Project) {
        let identifiers = [projectIdentifier(project)] + project.infoEntries.map { infoIdentifier($0) } + project.collaboratorEntries.map { collaboratorEntryIdentifier($0) }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
            if let error {
                print("[Spotlight] Delete failed: \(error)")
            }
        }
    }

    private func makeProjectItem(_ project: Project) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "OneToOne - \(project.name)"
        attributes.displayName = project.name
        attributes.contentDescription = [
            project.code,
            project.phase,
            project.status,
            project.comment ?? "",
            project.additionalInfo ?? "",
            project.followUpNotes ?? "",
            project.buildRetex ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " | ")
        attributes.keywords = [
            "OneToOne",
            "projet",
            project.name,
            project.code,
            project.phase,
            project.status
        ]
        return CSSearchableItem(uniqueIdentifier: projectIdentifier(project), domainIdentifier: "projects", attributeSet: attributes)
    }

    private func makeInfoItem(_ info: ProjectInfoEntry, project: Project) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let dateString = info.date.formatted(date: .abbreviated, time: .omitted)
        attributes.title = "OneToOne - \(project.name) - \(info.category)"
        attributes.displayName = "\(project.name) - \(info.category)"
        attributes.contentDescription = "\(dateString) - \(info.content)"
        attributes.keywords = [
            "OneToOne",
            "projet",
            "information",
            "rex",
            project.name,
            project.code,
            info.category
        ]
        return CSSearchableItem(uniqueIdentifier: infoIdentifier(info), domainIdentifier: "project-info", attributeSet: attributes)
    }

    private func makeCollaboratorEntryItem(_ entry: ProjectCollaboratorEntry, project: Project) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let dateString = entry.date.formatted(date: .abbreviated, time: .omitted)
        let collaboratorName = entry.collaborator?.name ?? "Collaborateur"
        attributes.title = "OneToOne - \(project.name) - \(collaboratorName) - \(entry.kind)"
        attributes.displayName = "\(project.name) - \(collaboratorName)"
        attributes.contentDescription = "\(dateString) - \(entry.content)"
        attributes.keywords = [
            "OneToOne",
            "projet",
            "information",
            "action",
            project.name,
            project.code,
            collaboratorName,
            entry.kind
        ]
        return CSSearchableItem(uniqueIdentifier: collaboratorEntryIdentifier(entry), domainIdentifier: "project-collaborator-info", attributeSet: attributes)
    }

    private func projectIdentifier(_ project: Project) -> String {
        "project-\(project.persistentModelID)"
    }

    private func infoIdentifier(_ info: ProjectInfoEntry) -> String {
        "project-info-\(info.persistentModelID)"
    }

    private func collaboratorEntryIdentifier(_ entry: ProjectCollaboratorEntry) -> String {
        "project-collaborator-entry-\(entry.persistentModelID)"
    }

    private func makeCollaboratorItem(_ collab: Collaborator) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .contact)
        attributes.title = "OneToOne — 1:1 avec \(collab.name)"
        attributes.displayName = collab.name
        attributes.contentDescription = collab.role
        var keywords = ["OneToOne", "1:1", "entretien", collab.name]
        if !collab.role.isEmpty { keywords.append(collab.role) }
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: collaboratorIdentifier(collab),
            domainIdentifier: "collaborators",
            attributeSet: attributes
        )
    }

    private func collaboratorIdentifier(_ collab: Collaborator) -> String {
        "collaborator-\(collab.stableID.uuidString)"
    }

    /// Test hook only.
    func makeCollaboratorItemForTesting(_ collab: Collaborator) -> CSSearchableItem {
        makeCollaboratorItem(collab)
    }

    func index(collaborator: Collaborator) {
        let item = makeCollaboratorItem(collaborator)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error { print("[Spotlight] Indexing collaborator failed: \(error)") }
        }
    }

    func remove(collaborator: Collaborator) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [collaboratorIdentifier(collaborator)]) { error in
            if let error { print("[Spotlight] Delete collaborator failed: \(error)") }
        }
    }
}
