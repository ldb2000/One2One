import XCTest
import SwiftData
@testable import OneToOne

final class CollaboratorMatcherTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_exactMatchInParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = [alice]
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Alice DUPONT",
            in: meeting,
            all: [alice, bob]
        )
        XCTAssertEqual(res?.name, "Alice DUPONT")
    }

    @MainActor
    func test_accentInsensitive() throws {
        let ctx = try makeContext()
        let zoe = Collaborator(name: "Zoé MERCIER")
        ctx.insert(zoe)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = [zoe]
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "ZOE MERCIER",
            in: meeting,
            all: [zoe]
        )
        XCTAssertEqual(res?.name, "Zoé MERCIER")
    }

    @MainActor
    func test_fallbackToFavorite() throws {
        let ctx = try makeContext()
        let charlie = Collaborator(name: "Charlie BRUN")
        charlie.pinLevel = 2
        ctx.insert(charlie)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = []
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Charlie BRUN",
            in: meeting,
            all: [charlie]
        )
        XCTAssertEqual(res?.name, "Charlie BRUN")
    }

    @MainActor
    func test_fallbackToAll() throws {
        let ctx = try makeContext()
        let dani = Collaborator(name: "Dani ROCHE")
        ctx.insert(dani)
        let meeting = Meeting(title: "M", date: Date())
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Dani ROCHE",
            in: meeting,
            all: [dani]
        )
        XCTAssertEqual(res?.name, "Dani ROCHE")
    }

    @MainActor
    func test_noMatchReturnsNil() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let meeting = Meeting(title: "M", date: Date())
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Inconnu PERSONNE",
            in: meeting,
            all: [alice]
        )
        XCTAssertNil(res)
    }
}
