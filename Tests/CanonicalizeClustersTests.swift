import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CanonicalizeClustersTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_canonicalize_noAssignments_returnsInputUnchanged() {
        let svc = TranscriptionService.shared
        let blocks = [
            TurnMerger.Block(speaker: 0, start: 0, end: 5, text: "a"),
            TurnMerger.Block(speaker: 1, start: 5, end: 10, text: "b")
        ]
        let out = svc.canonicalizeBlocksForTest(blocks, assignments: [:])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].speaker, 0)
        XCTAssertEqual(out[1].speaker, 1)
    }

    func test_canonicalize_twoClustersOneCollab_unifiesToCanonical() throws {
        let alice = Collaborator(name: "Alice")
        context.insert(alice)
        try context.save()

        let svc = TranscriptionService.shared
        let blocks = [
            TurnMerger.Block(speaker: 0, start: 0, end: 5, text: "a"),
            TurnMerger.Block(speaker: 1, start: 5, end: 10, text: "b")
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.85, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeBlocksForTest(blocks, assignments: assignments)
        XCTAssertEqual(out.count, 1, "Adjacent same-collab clusters should merge")
        XCTAssertEqual(out[0].start, 0)
        XCTAssertEqual(out[0].end, 10)
        XCTAssertEqual(out[0].text, "a b")
    }

    func test_canonicalize_distinctCollabs_doesNotMerge() throws {
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)
        try context.save()

        let svc = TranscriptionService.shared
        let blocks = [
            TurnMerger.Block(speaker: 0, start: 0, end: 5, text: "a"),
            TurnMerger.Block(speaker: 1, start: 5, end: 10, text: "b")
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: bob, confidence: 0.9, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeBlocksForTest(blocks, assignments: assignments)
        XCTAssertEqual(out.count, 2)
        XCTAssertNotEqual(out[0].speaker, out[1].speaker)
    }
}
