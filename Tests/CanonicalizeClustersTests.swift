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
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: [:])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].clusterID, 0)
        XCTAssertEqual(out[1].clusterID, 1)
    }

    func test_canonicalize_twoClustersOneCollab_unifiesToCanonical() throws {
        let alice = Collaborator(name: "Alice")
        context.insert(alice)
        try context.save()

        let svc = TranscriptionService.shared
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.85, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: assignments)
        XCTAssertEqual(out.count, 1, "Adjacent same-collab clusters should merge")
        XCTAssertEqual(out[0].startSec, 0)
        XCTAssertEqual(out[0].endSec, 10)
        XCTAssertEqual(out[0].text, "a b")
    }

    func test_canonicalize_distinctCollabs_doesNotMerge() throws {
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)
        try context.save()

        let svc = TranscriptionService.shared
        let aligned = [
            TurnAligner.AlignedSegment(startSec: 0, endSec: 5, text: "a", clusterID: 0),
            TurnAligner.AlignedSegment(startSec: 5, endSec: 10, text: "b", clusterID: 1)
        ]
        let assignments: [Int: SpeakerMatcher.Assignment] = [
            0: SpeakerMatcher.Assignment(collaborator: alice, confidence: 0.9, auto: true, candidates: [], ambiguous: false),
            1: SpeakerMatcher.Assignment(collaborator: bob, confidence: 0.9, auto: true, candidates: [], ambiguous: false)
        ]
        let out = svc.canonicalizeClustersForTest(aligned, assignments: assignments)
        XCTAssertEqual(out.count, 2)
        XCTAssertNotEqual(out[0].clusterID, out[1].clusterID)
    }
}
