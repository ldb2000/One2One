import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TranscriptEditServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func insertSegments(_ tuples: [(Int, Double, Double, String)],
                                 meeting: Meeting) {
        for (idx, start, end, text) in tuples {
            let s = TranscriptSegment(orderIndex: idx, startSeconds: start,
                                      endSeconds: end, text: text, speakerID: 1)
            s.meeting = meeting
            context.insert(s)
        }
    }

    func test_delete_shiftsLaterSegmentsByRemovedDuration() async throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        insertSegments([
            (0, 0, 5, "a"),
            (1, 5, 15, "b"),
            (2, 15, 20, "c"),
            (3, 20, 25, "d")
        ], meeting: m)
        try context.save()

        let target = m.transcriptSegments.first { $0.text == "b" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: context)

        let remaining = m.transcriptSegments.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(remaining.count, 3)
        XCTAssertEqual(remaining[0].text, "a")
        XCTAssertEqual(remaining[0].startSeconds, 0)
        XCTAssertEqual(remaining[1].text, "c")
        XCTAssertEqual(remaining[1].startSeconds, 5, "c shifted from 15 to 5")
        XCTAssertEqual(remaining[1].endSeconds, 10, "c shifted from 20 to 10")
        XCTAssertEqual(remaining[2].text, "d")
        XCTAssertEqual(remaining[2].startSeconds, 10)
    }

    func test_delete_doesNotShiftEarlierSegments() async throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        insertSegments([
            (0, 0, 5, "a"),
            (1, 5, 10, "b"),
            (2, 10, 15, "c")
        ], meeting: m)
        try context.save()

        let target = m.transcriptSegments.first { $0.text == "c" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: context)

        let remaining = m.transcriptSegments.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].startSeconds, 0)
        XCTAssertEqual(remaining[1].startSeconds, 5, "earlier segments unchanged")
    }

    func test_delete_removesTargetSegment() async throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        insertSegments([(0, 0, 5, "a"), (1, 5, 10, "b")], meeting: m)
        try context.save()

        let target = m.transcriptSegments.first { $0.text == "a" }!
        try await TranscriptEditService.deleteSegment(target, in: m, context: context)

        XCTAssertEqual(m.transcriptSegments.count, 1)
        XCTAssertFalse(m.transcriptSegments.contains { $0.text == "a" })
    }

    func test_delete_audioMissing_deletesTextOnly_noThrow() async throws {
        let m = Meeting(title: "M", date: Date())
        context.insert(m)
        insertSegments([(0, 0, 5, "a")], meeting: m)
        try context.save()

        let target = m.transcriptSegments.first!
        try await TranscriptEditService.deleteSegment(target, in: m, context: context)
        XCTAssertEqual(m.transcriptSegments.count, 0)
    }
}
