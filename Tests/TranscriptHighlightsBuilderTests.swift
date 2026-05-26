import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TranscriptHighlightsBuilderTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_build_noHighlights_returnsEmpty() throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        let s = TranscriptSegment(orderIndex: 0, startSeconds: 0, endSeconds: 5, text: "hi", speakerID: 1)
        s.meeting = m
        context.insert(s)
        try context.save()
        XCTAssertEqual(TranscriptHighlightsBuilder.build(meeting: m), "")
    }

    func test_build_oneHighlight_formatsTimestampSpeakerText() throws {
        let alice = Collaborator(name: "Alice DUPONT")
        context.insert(alice)
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        let s = TranscriptSegment(orderIndex: 0, startSeconds: 65, endSeconds: 70, text: "point clé", speakerID: 1)
        s.meeting = m
        s.speaker = alice
        s.isHighlighted = true
        context.insert(s)
        try context.save()

        let out = TranscriptHighlightsBuilder.build(meeting: m)
        XCTAssertTrue(out.contains("01:05"), "timestamp 01:05 attendu")
        XCTAssertTrue(out.contains("Alice DUPONT"), "nom speaker attendu")
        XCTAssertTrue(out.contains("point clé"), "texte segment attendu")
    }

    func test_build_multipleHighlights_preservesOrderByStartSec() throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        let s1 = TranscriptSegment(orderIndex: 0, startSeconds: 10, endSeconds: 15, text: "early", speakerID: 1)
        let s2 = TranscriptSegment(orderIndex: 1, startSeconds: 100, endSeconds: 105, text: "late", speakerID: 1)
        s1.meeting = m; s2.meeting = m
        s1.isHighlighted = true; s2.isHighlighted = true
        context.insert(s1); context.insert(s2)
        try context.save()

        let out = TranscriptHighlightsBuilder.build(meeting: m)
        guard let earlyRange = out.range(of: "early"),
              let lateRange = out.range(of: "late") else {
            XCTFail("Both segments should appear"); return
        }
        XCTAssertTrue(earlyRange.lowerBound < lateRange.lowerBound, "early avant late")
    }
}
