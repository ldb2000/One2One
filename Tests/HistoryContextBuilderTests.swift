import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class HistoryContextBuilderTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeTemplate(mode: HistoryMode, n: Int) -> ReportTemplate {
        ReportTemplate(name: "T", kind: .general, historyMode: mode, historyN: n)
    }

    func test_none_returnsEmpty() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let out = HistoryContextBuilder.build(for: m, template: makeTemplate(mode: .none, n: 0), in: context)
        XCTAssertEqual(out, "")
    }

    func test_lastN_returnsRecentMeetingsExcludingCurrent() throws {
        let proj = Project(code: "P", name: "P", domain: "D", phase: "Build")
        context.insert(proj)
        let cal = Calendar.current
        // 4 past meetings + current
        for i in 1...4 {
            let m = Meeting(title: "Meeting \(i)", date: cal.date(byAdding: .day, value: -i, to: Date())!)
            m.project = proj
            m.kind = .project
            m.summary = "Summary of meeting \(i)"
            context.insert(m)
        }
        let current = Meeting(title: "Current", date: Date())
        current.project = proj
        current.kind = .project
        context.insert(current)
        try context.save()

        let out = HistoryContextBuilder.build(for: current, template: makeTemplate(mode: .lastN, n: 2), in: context)
        XCTAssertTrue(out.contains("Meeting 1"))
        XCTAssertTrue(out.contains("Meeting 2"))
        XCTAssertFalse(out.contains("Meeting 3"))
        XCTAssertFalse(out.contains("Current"))
    }

    func test_lastN_zero_returnsEmpty() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let out = HistoryContextBuilder.build(for: m, template: makeTemplate(mode: .lastN, n: 0), in: context)
        XCTAssertEqual(out, "")
    }

    func test_lastN_truncatesEachSummary() throws {
        let proj = Project(code: "P", name: "P", domain: "D", phase: "Build")
        context.insert(proj)
        let huge = String(repeating: "x", count: 3000)
        let earlier = Meeting(title: "Earlier", date: Date(timeIntervalSinceNow: -86400))
        earlier.project = proj
        earlier.kind = .project
        earlier.summary = huge
        context.insert(earlier)
        let current = Meeting(title: "Cur", date: Date())
        current.project = proj
        current.kind = .project
        context.insert(current)
        try context.save()

        let out = HistoryContextBuilder.build(for: current, template: makeTemplate(mode: .lastN, n: 1), in: context)
        XCTAssertLessThan(out.count, 2500)
        XCTAssertTrue(out.contains("…"))
    }
}
