import Testing
import CoreSpotlight
import Foundation
@testable import OneToOne

@Suite("Spotlight collaborator indexing")
struct SpotlightCollaboratorIndexTests {

    @Test("makeCollaboratorItem yields stable identifier prefixed with 'collaborator-'")
    func itemIdentifierFormat() {
        let collab = Collaborator(name: "Alice", role: "Architecte")
        let item = SpotlightIndexService.shared.makeCollaboratorItemForTesting(collab)
        #expect(item.uniqueIdentifier == "collaborator-\(collab.stableID.uuidString)")
        #expect(item.domainIdentifier == "collaborators")
    }

    @Test("makeCollaboratorItem populates display name and OneToOne keyword")
    func itemAttributes() {
        let collab = Collaborator(name: "Alice", role: "Architecte")
        let item = SpotlightIndexService.shared.makeCollaboratorItemForTesting(collab)
        let attrs = item.attributeSet
        #expect(attrs.displayName == "Alice")
        #expect(attrs.title?.contains("1:1") == true)
        #expect(attrs.keywords?.contains("OneToOne") == true)
        #expect(attrs.keywords?.contains("Alice") == true)
    }
}
