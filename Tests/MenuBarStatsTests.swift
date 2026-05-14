import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class MenuBarStatsTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    // MARK: - UrgentActionsSelector

    func test_urgent_overdueBeforeToday_beforeOld() {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let today = cal.date(byAdding: .hour, value: 6, to: cal.startOfDay(for: now))!
        let oldNoDate = cal.date(byAdding: .day, value: -60, to: now)!

        let overdue = ActionTask(title: "Overdue", dueDate: yesterday)
        let todayTask = ActionTask(title: "Today", dueDate: today)
        let stale = ActionTask(title: "Stale")
        stale.createdAt = oldNoDate

        context.insert(overdue); context.insert(todayTask); context.insert(stale)
        try? context.save()

        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        XCTAssertEqual(urgent.map { $0.title }, ["Overdue", "Today", "Stale"])
    }

    func test_urgent_skipsCompletedAndYoungNoDate() {
        let now = Date()
        let done = ActionTask(title: "Done", dueDate: now)
        done.isCompleted = true
        let recent = ActionTask(title: "Recent")
        recent.createdAt = now  // 30 days threshold not crossed

        context.insert(done); context.insert(recent)
        try? context.save()

        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        XCTAssertTrue(urgent.isEmpty)
    }

    // MARK: - TodayStatsCalculator

    func test_todayStats_passedOnlyAndNoProject() {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let past = makeMeeting(title: "Past", scheduledStart: cal.date(byAdding: .hour, value: 1, to: startOfToday)!,
                               scheduledEnd: cal.date(byAdding: .hour, value: 2, to: startOfToday)!)
        let future = makeMeeting(title: "Future", scheduledStart: cal.date(byAdding: .hour, value: 1, to: now)!,
                                 scheduledEnd: cal.date(byAdding: .hour, value: 2, to: now)!)
        let pastNoProject = makeMeeting(title: "PastNoProject",
                                        scheduledStart: cal.date(byAdding: .hour, value: 2, to: startOfToday)!,
                                        scheduledEnd: cal.date(byAdding: .hour, value: 3, to: startOfToday)!)
        // future also has no project, but counts in sansProjet (any status of today)
        context.insert(past); context.insert(future); context.insert(pastNoProject)
        // assign a project to `past`
        let proj = Project(code: "P1", name: "P1", domain: "D", phase: "Build")
        context.insert(proj); past.project = proj
        try? context.save()

        let stats = TodayStatsCalculator.compute(in: context, now: now)
        // `past` 1h + `pastNoProject` 1h = 2h passées
        XCTAssertEqual(stats.tempsPasseSeconds, 2 * 3600, accuracy: 0.5)
        // sansProjet = future + pastNoProject = 2
        XCTAssertEqual(stats.sansProjet, 2)
    }

    // MARK: - MenubarBadgeText

    func test_badge_zero_emptyString() {
        XCTAssertEqual(MenubarBadgeText.suffix(urgentCount: 0, hasOverdue: false), "")
    }

    func test_badge_three_orangeWhenNoOverdue() {
        let r = MenubarBadgeText.suffix(urgentCount: 3, hasOverdue: false)
        XCTAssertEqual(r, " ●3")
    }

    func test_badge_twelve_compact() {
        XCTAssertEqual(MenubarBadgeText.suffix(urgentCount: 12, hasOverdue: true), " ●12")
    }

    // MARK: - Fixture

    private func makeMeeting(title: String, scheduledStart: Date, scheduledEnd: Date) -> Meeting {
        let m = Meeting(title: title, date: scheduledStart)
        m.scheduledStart = scheduledStart
        m.scheduledEnd = scheduledEnd
        return m
    }
}
