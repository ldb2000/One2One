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
        XCTAssertTrue(meeting.prepDrainDone)
        XCTAssertFalse(meeting.prepCarryoverDone,
                       "Drain must NOT set carryover flag — would block end-of-meeting carryover")
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
        XCTAssertTrue(meeting.prepDrainDone)
    }

    @MainActor
    func test_drain_doesNotBlockSubsequentCarryover() throws {
        // Régression : avant le split prepDrainDone/prepCarryoverDone, le
        // drain marquait `prepCarryoverDone = true`, ce qui faisait sauter
        // le carryover de fin de meeting (items non cochés perdus).
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        collab.standingPrepNotes = "- [ ] from pool"

        PrepCarryoverService.drainStandingIntoMeeting(meeting, in: ctx)
        // L'utilisateur coche un item, en ajoute un nouveau non coché
        meeting.prepNotes = "- [x] from pool\n- [ ] new question"
        let settings = AppSettings()
        ctx.insert(settings)

        PrepCarryoverService.carryoverUncheckedFromMeeting(meeting, settings: settings, in: ctx)

        XCTAssertTrue(collab.standingPrepNotes.contains("- [ ] new question"),
                      "Carryover doit s'exécuter même après un drain antérieur")
    }


    @MainActor
    func test_carryover_oneToOne_pushesUncheckedToCollabPool() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        meeting.prepNotes = """
        - [ ] Not done
        - [x] Done
        - [ ] Also not done
        """
        meeting.prepCarryoverDone = false
        let settings = AppSettings()
        ctx.insert(settings)

        PrepCarryoverService.carryoverUncheckedFromMeeting(meeting, settings: settings, in: ctx)

        XCTAssertTrue(collab.standingPrepNotes.contains("- [ ] Not done"))
        XCTAssertTrue(collab.standingPrepNotes.contains("- [ ] Also not done"))
        XCTAssertFalse(collab.standingPrepNotes.contains("- [x] Done"))
        XCTAssertTrue(collab.standingPrepNotes.contains("<!-- reporté"))
        XCTAssertTrue(meeting.prepCarryoverDone)
    }

    @MainActor
    func test_carryover_skipsWhenSettingDisabled() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        meeting.prepNotes = "- [ ] Should stay"
        let settings = AppSettings()
        settings.prepAutoCarryover = false
        ctx.insert(settings)

        PrepCarryoverService.carryoverUncheckedFromMeeting(meeting, settings: settings, in: ctx)

        XCTAssertEqual(collab.standingPrepNotes, "")
        XCTAssertFalse(meeting.prepCarryoverDone)
    }

    @MainActor
    func test_carryover_globalKind_skipsAndMarksDone() throws {
        let (ctx, meeting) = try makeGlobalFixture()
        meeting.prepNotes = "- [ ] Lost item"
        let settings = AppSettings()
        ctx.insert(settings)

        PrepCarryoverService.carryoverUncheckedFromMeeting(meeting, settings: settings, in: ctx)

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
