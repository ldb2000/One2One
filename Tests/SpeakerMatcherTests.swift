import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class SpeakerMatcherTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func enrolled(_ name: String, embedding: [Float]) -> Collaborator {
        let c = Collaborator(name: name)
        c.voicePrint = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        c.voicePrintSamples = 1
        context.insert(c)
        return c
    }

    private func meeting(participants: [Collaborator]) -> Meeting {
        let m = Meeting(title: "M", date: Date())
        for p in participants { m.participants.append(p) }
        context.insert(m)
        return m
    }

    private func vec(_ value: Float, _ count: Int = 256) -> [Float] {
        Array(repeating: value, count: count)
    }

    private func vec2(_ a: Float, _ b: Float) -> [Float] {
        var v = [Float](repeating: 0, count: 256)
        v[0] = a; v[1] = b
        return v
    }

    func test_cosine_identicalVectors_is_one() {
        let v: [Float] = [3, 4, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(v, v), 1.0, accuracy: 1e-6)
    }

    func test_cosine_orthogonal_is_zero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(a, b), 0.0, accuracy: 1e-6)
    }

    func test_pass1_findsParticipantAboveAutoThreshold() throws {
        let alice = enrolled("Alice", embedding: vec2(1, 0))
        let m = meeting(participants: [alice])
        try context.save()

        let clusterEmbedding = vec2(1, 0)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: clusterEmbedding],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Alice")
        XCTAssertEqual(assignments[0]?.confidence ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertTrue(assignments[0]?.auto ?? false)
        XCTAssertFalse(assignments[0]?.ambiguous ?? true)
    }

    func test_pass1_suggestion_belowAutoThreshold() throws {
        let alice = enrolled("Alice", embedding: [1, 0])
        let m = meeting(participants: [alice])
        try context.save()
        // cos([1,0], [1, 1.17]) = 1/sqrt(1 + 1.17^2) ~ 0.65
        let cluster: [Float] = [1, 1.17]
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Alice")
        XCTAssertFalse(assignments[0]?.auto ?? true)
        XCTAssertGreaterThan(assignments[0]?.confidence ?? 0, 0.6)
        XCTAssertLessThan(assignments[0]?.confidence ?? 1, 0.75)
    }

    func test_pass1_empty_pass2_findsNonParticipant() throws {
        let bob = enrolled("Bob", embedding: vec(1))
        let m = meeting(participants: [])
        try context.save()

        let cluster = vec(1)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertEqual(assignments[0]?.collaborator?.name, "Bob")
        XCTAssertTrue(assignments[0]?.auto ?? false)
    }

    func test_ambiguous_twoCandidatesCloseAboveAuto() throws {
        let alice = enrolled("Alice", embedding: vec(1))
        let bob = enrolled("Bob", embedding: vec(1))
        let m = meeting(participants: [alice, bob])
        try context.save()

        let cluster = vec(1)
        let assignments = SpeakerMatcher.match(
            clusterEmbeddings: [0: cluster],
            meeting: m,
            in: context
        )
        XCTAssertTrue(assignments[0]?.ambiguous ?? false)
        XCTAssertFalse(assignments[0]?.auto ?? true)
    }

    func test_ema_voicePrintUpdate_firstSample() throws {
        let alice = enrolled("Alice", embedding: vec(0))
        alice.voicePrint = nil
        alice.voicePrintSamples = 0
        try context.save()

        let newEmbedding = vec(0.5)
        SpeakerMatcher.applyEMAUpdate(to: alice, newEmbedding: newEmbedding, in: context)

        let stored: [Float] = alice.voicePrint!.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(stored.first ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertEqual(alice.voicePrintSamples, 1)
        XCTAssertNotNil(alice.voicePrintUpdatedAt)
    }

    func test_ema_voicePrintUpdate_runningAverage() throws {
        // old=0.0 (n=3), new=1.0 → expected (0*3 + 1)/4 = 0.25
        let alice = enrolled("Alice", embedding: vec(0))
        alice.voicePrintSamples = 3
        try context.save()

        SpeakerMatcher.applyEMAUpdate(to: alice, newEmbedding: vec(1), in: context)

        let stored: [Float] = alice.voicePrint!.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(stored.first ?? 0, 0.25, accuracy: 1e-6)
        XCTAssertEqual(alice.voicePrintSamples, 4)
    }
}
