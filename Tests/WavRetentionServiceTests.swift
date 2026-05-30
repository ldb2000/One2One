import XCTest
import SwiftData
@testable import OneToOne

final class WavRetentionServiceTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_plan_skipsMeetingsWithoutReport() throws {
        let ctx = try makeContext()
        let now = Date()
        let cal = Calendar.current
        let old = cal.date(byAdding: .day, value: -10, to: now)!
        let m = Meeting(title: "no-report", date: old)
        m.wavFilePath = Bundle.main.executablePath ?? "/bin/sh"
        m.summary = ""
        ctx.insert(m)
        try ctx.save()
        let settings = AppSettings()
        let plan = WavRetentionService.plan(in: ctx, settings: settings, now: now)
        XCTAssertTrue(plan.toCompress.isEmpty)
        XCTAssertTrue(plan.toDelete.isEmpty)
    }

    @MainActor
    func test_plan_skipsKeepWavForever() throws {
        let ctx = try makeContext()
        let now = Date()
        let cal = Calendar.current
        let old = cal.date(byAdding: .day, value: -40, to: now)!
        let m = Meeting(title: "kept", date: old)
        m.wavFilePath = Bundle.main.executablePath ?? "/bin/sh"
        m.summary = "résumé"
        m.keepWavForever = true
        ctx.insert(m)
        try ctx.save()
        let settings = AppSettings()
        let plan = WavRetentionService.plan(in: ctx, settings: settings, now: now)
        XCTAssertTrue(plan.toCompress.isEmpty)
        XCTAssertTrue(plan.toDelete.isEmpty)
    }

    @MainActor
    func test_plan_classifiesByAge() throws {
        let ctx = try makeContext()
        let now = Date()
        let cal = Calendar.current

        let mCompress = Meeting(title: "to-compress",
                                date: cal.date(byAdding: .day, value: -10, to: now)!)
        mCompress.wavFilePath = Bundle.main.executablePath ?? "/bin/sh"
        mCompress.summary = "ok"
        mCompress.wavIsCompressed = false
        ctx.insert(mCompress)

        let mDelete = Meeting(title: "to-delete",
                              date: cal.date(byAdding: .day, value: -45, to: now)!)
        mDelete.wavFilePath = Bundle.main.executablePath ?? "/bin/sh"
        mDelete.summary = "ok"
        ctx.insert(mDelete)

        try ctx.save()
        let settings = AppSettings()
        let plan = WavRetentionService.plan(in: ctx, settings: settings, now: now)
        XCTAssertEqual(plan.toCompress.map(\.title), ["to-compress"])
        XCTAssertEqual(plan.toDelete.map(\.title), ["to-delete"])
    }
}
