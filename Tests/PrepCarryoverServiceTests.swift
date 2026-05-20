import XCTest
import SwiftData
@testable import OneToOne

final class PrepCarryoverServiceTests: XCTestCase {

    func test_extractUncheckedItems_returnsOnlyUnchecked() {
        let md = """
        # Prep
        - [ ] First unchecked
        - [x] Already done
          - [ ] Indented unchecked
        Some other line
        - [ ] Last unchecked
        """
        let items = PrepCarryoverService.extractUncheckedItems(from: md)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], "- [ ] First unchecked")
        XCTAssertEqual(items[1], "  - [ ] Indented unchecked")
        XCTAssertEqual(items[2], "- [ ] Last unchecked")
    }

    func test_extractUncheckedItems_ignoresCheckedAndPlainText() {
        let md = """
        - [x] Done
        - Not a checkbox
        Some prose
        """
        XCTAssertTrue(PrepCarryoverService.extractUncheckedItems(from: md).isEmpty)
    }

    @MainActor
    func test_drain_oneToOne_movesStandingIntoMeeting() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        collab.standingPrepNotes = "- [ ] Ask DAT status\n- [ ] Review roadmap"

        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)

        XCTAssertEqual(meeting.prepNotes, "- [ ] Ask DAT status\n- [ ] Review roadmap")
        XCTAssertEqual(collab.standingPrepNotes, "")
        XCTAssertTrue(meeting.prepCarryoverDone)
    }

    @MainActor
    func test_drain_concatenatesWhenMeetingPrepNonEmpty() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        collab.standingPrepNotes = "- [ ] From pool"
        meeting.prepNotes = "- [ ] Already manual"

        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)

        XCTAssertEqual(meeting.prepNotes, "- [ ] From pool\n\n- [ ] Already manual")
        XCTAssertEqual(collab.standingPrepNotes, "")
    }

    @MainActor
    func test_drain_isIdempotent_secondCallNoop() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        collab.standingPrepNotes = "- [ ] One"
        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)
        collab.standingPrepNotes = "- [ ] Should not move"
        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)
        XCTAssertEqual(collab.standingPrepNotes, "- [ ] Should not move")
    }

    @MainActor
    func test_drain_globalKind_skipsAndMarksDone() throws {
        let (ctx, meeting) = try makeGlobalFixture()
        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)
        XCTAssertEqual(meeting.prepNotes, "")
        XCTAssertTrue(meeting.prepCarryoverDone)
    }

    // MARK: - Fixtures

    @MainActor
    private func makeOneToOneFixture() throws -> (ModelContext, Collaborator, Meeting) {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let collab = Collaborator(name: "Bastien", role: "")
        ctx.insert(collab)
        let m = Meeting(title: "1:1 — Bastien", date: Date())
        m.kind = .oneToOne
        m.participants = [collab]
        ctx.insert(m)
        try ctx.save()
        return (ctx, collab, m)
    }

    @MainActor
    private func makeGlobalFixture() throws -> (ModelContext, Meeting) {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let m = Meeting(title: "Global", date: Date())
        m.kind = .global
        ctx.insert(m)
        try ctx.save()
        return (ctx, m)
    }
}
