# Calendar & Teams Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire deeper macOS Calendar + Teams integration into OneToOne — agenda inspector panel, MeetingBar-style menu bar, system notifications, fuzzy project matching, calendar-driven time stats.

**Architecture:** EventKit read-only fetch funnels through a single `CalendarAgendaService` (observable singleton) that feeds the right-side `AgendaInspectorPanel` and `MenuBarController` (NSStatusItem). Imports go through `CalendarMeetingImportService.importEvent`, which calls `ProjectMatchService` (deterministic fuzzy match) to suggest `MeetingKind` + linked entity, then schedules three `UNUserNotificationCenter` notifications per Meeting (start, T-5m, end). `TeamsLauncher` rewrites `https://teams.microsoft.com/l/meetup-join/...` URLs to `msteams:/l/meetup-join/...` so the Teams desktop app handles them. No MS Graph, no OAuth.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData (lightweight migration — optional fields added to existing `SchemaV1`), EventKit, `UNUserNotificationCenter`, `NSStatusItem`, `NSWorkspace`. Tests via XCTest in `Tests/` target (`swift test`).

**Spec reference:** [docs/superpowers/specs/2026-05-12-calendar-teams-integration-design.md](../specs/2026-05-12-calendar-teams-integration-design.md).

**Pre-flight (run once at start):**
```bash
git status                                      # confirm on branch feat/calendar-teams-integration
git log --oneline -1                            # confirm spec commit present
swift test 2>&1 | tail -20                      # baseline: tests pass
```

---

## Task 1: Extend `Meeting` model with calendar fields

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift` (locate `final class Meeting`, add 4 optional fields)
- Modify: `OneToOne/Models/MeetingModels.swift` (add `effectiveDuration` extension)
- Test: `Tests/MeetingEffectiveDurationTests.swift` (new)

**Rationale:** Optional fields trigger SwiftData lightweight migration automatically — no `SchemaV2` needed (see comment block at top of `SchemaVersions.swift`).

- [ ] **Step 1: Write the failing test**

Create `Tests/MeetingEffectiveDurationTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

final class MeetingEffectiveDurationTests: XCTestCase {

    func test_effectiveDuration_usesScheduledWhenBothPresentAndOrdered() {
        let meeting = Meeting(title: "Test", date: Date())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        meeting.scheduledStart = start
        meeting.scheduledEnd = end
        meeting.recordingDuration = 120  // should be ignored
        XCTAssertEqual(meeting.effectiveDuration, 3600, accuracy: 0.01)
    }

    func test_effectiveDuration_fallsBackToRecordingWhenScheduledMissing() {
        let meeting = Meeting(title: "Test", date: Date())
        meeting.recordingDuration = 1800
        XCTAssertEqual(meeting.effectiveDuration, 1800, accuracy: 0.01)
    }

    func test_effectiveDuration_fallsBackWhenScheduledInverted() {
        let meeting = Meeting(title: "Test", date: Date())
        let start = Date()
        meeting.scheduledStart = start
        meeting.scheduledEnd = start.addingTimeInterval(-60)  // inverted
        meeting.recordingDuration = 500
        XCTAssertEqual(meeting.effectiveDuration, 500, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MeetingEffectiveDurationTests 2>&1 | tail -20`
Expected: compile failure — `scheduledStart`/`scheduledEnd` and `effectiveDuration` don't exist yet.

- [ ] **Step 3: Add the 4 new fields to `Meeting`**

In `OneToOne/Models/OtherModels.swift`, find the `Meeting` class. Add these stored properties next to existing date/title fields (group them together; keep them before relationship declarations):

```swift
    // MARK: - Calendar integration (optional — lightweight migration safe)
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var teamsJoinURL: String?
    var calendarEventID: String?
```

- [ ] **Step 4: Add the `effectiveDuration` extension**

In `OneToOne/Models/MeetingModels.swift`, append at the bottom (after the existing `extension Meeting` block ending at line 226):

```swift
extension Meeting {
    /// Duration to display in stats. Prefers calendar-scheduled duration
    /// (Outlook-style) and falls back to recorded duration for ad-hoc
    /// meetings. Inverted scheduled bounds are treated as invalid.
    var effectiveDuration: TimeInterval {
        if let s = scheduledStart, let e = scheduledEnd, e > s {
            return e.timeIntervalSince(s)
        }
        return recordingDuration
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MeetingEffectiveDurationTests 2>&1 | tail -20`
Expected: 3 tests pass.

- [ ] **Step 6: Run full suite — no regressions**

Run: `swift test 2>&1 | tail -10`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Models/OtherModels.swift OneToOne/Models/MeetingModels.swift Tests/MeetingEffectiveDurationTests.swift
git commit -m "feat(meeting): add scheduledStart/End + teamsJoinURL + calendarEventID + effectiveDuration"
```

---

## Task 2: Teams URL extraction helper

**Files:**
- Create: `OneToOne/Services/TeamsURLExtractor.swift`
- Test: `Tests/TeamsURLExtractorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TeamsURLExtractorTests.swift`:

```swift
import XCTest
@testable import OneToOne

final class TeamsURLExtractorTests: XCTestCase {

    func test_extractsFromEventURL_https() {
        let url = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }

    func test_extractsFromEventURL_msteamsScheme() {
        let url = URL(string: "msteams:/l/meetup-join/19%3aabc%40thread.v2/0")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }

    func test_extractsFromNotes_whenURLAbsent() {
        let notes = """
        Bonjour,
        ________________________________________________________________________________
        Join Microsoft Teams Meeting
        https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=ctx
        Learn more about Teams
        """
        let result = TeamsURLExtractor.extract(url: nil, notes: notes, location: nil)
        XCTAssertEqual(result, "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz%40thread.v2/0?context=ctx")
    }

    func test_extractsFromLocation_lastResort() {
        let location = "Réunion Microsoft Teams https://teams.microsoft.com/l/meetup-join/19%3aloc%40thread.v2/0"
        let result = TeamsURLExtractor.extract(url: nil, notes: nil, location: location)
        XCTAssertEqual(result, "https://teams.microsoft.com/l/meetup-join/19%3aloc%40thread.v2/0")
    }

    func test_returnsNil_whenAbsent() {
        let result = TeamsURLExtractor.extract(url: URL(string: "https://example.com/cal/event"), notes: "no link here", location: "Salle Bercy")
        XCTAssertNil(result)
    }

    func test_ignoresNonTeamsHosts() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertNil(result)
    }

    func test_acceptsTeamsLiveHost() {
        let url = URL(string: "https://teams.live.com/meet/9876543210?p=token")!
        let result = TeamsURLExtractor.extract(url: url, notes: nil, location: nil)
        XCTAssertEqual(result, url.absoluteString)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsURLExtractorTests 2>&1 | tail -20`
Expected: compile failure — `TeamsURLExtractor` undefined.

- [ ] **Step 3: Implement extractor**

Create `OneToOne/Services/TeamsURLExtractor.swift`:

```swift
import Foundation

/// Extracts a Microsoft Teams join URL from an EKEvent's url / notes / location.
/// Priority: event.url → notes → location. Only accepts `msteams://` scheme or
/// `teams.microsoft.com` / `teams.live.com` hosts (Google Meet, Zoom, etc. ignored).
enum TeamsURLExtractor {

    private static let teamsHosts: Set<String> = ["teams.microsoft.com", "teams.live.com"]

    private static let teamsURLPattern: NSRegularExpression = {
        let pattern = #"https://teams\.(?:microsoft|live)\.com/[^\s"'<>]+"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func extract(url: URL?, notes: String?, location: String?) -> String? {
        if let url, isTeams(url) { return url.absoluteString }
        if let notes, let m = firstMatch(in: notes) { return m }
        if let location, let m = firstMatch(in: location) { return m }
        return nil
    }

    private static func isTeams(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "msteams" { return true }
        guard let host = url.host?.lowercased() else { return false }
        return teamsHosts.contains(host)
    }

    private static func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = teamsURLPattern.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TeamsURLExtractorTests 2>&1 | tail -20`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TeamsURLExtractor.swift Tests/TeamsURLExtractorTests.swift
git commit -m "feat(calendar): TeamsURLExtractor — parse join URL from event url/notes/location"
```

---

## Task 3: `TeamsLauncher` (open Teams app)

**Files:**
- Create: `OneToOne/Services/TeamsLauncher.swift`
- Test: `Tests/TeamsLauncherTests.swift`

**Note:** The `open` side effect (NSWorkspace) is not testable; we test only the URL rewrite helper.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeamsLauncherTests.swift`:

```swift
import XCTest
@testable import OneToOne

final class TeamsLauncherTests: XCTestCase {

    func test_rewrite_httpsTeams_toMsteamsScheme() {
        let input = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3aabc%40thread.v2/0?context=ctx")!
        let result = TeamsLauncher.rewriteToMSTeams(input)
        XCTAssertEqual(result?.scheme, "msteams")
        XCTAssertEqual(result?.absoluteString,
                       "msteams:/l/meetup-join/19%3aabc%40thread.v2/0?context=ctx")
    }

    func test_rewrite_msteams_passthrough() {
        let input = URL(string: "msteams:/l/meetup-join/19%3aabc%40thread.v2/0")!
        XCTAssertEqual(TeamsLauncher.rewriteToMSTeams(input), input)
    }

    func test_rewrite_nonTeamsHost_returnsNil() {
        let input = URL(string: "https://meet.google.com/abc-defg-hij")!
        XCTAssertNil(TeamsLauncher.rewriteToMSTeams(input))
    }

    func test_rewrite_teamsButNotMeetupJoinPath_returnsNil() {
        let input = URL(string: "https://teams.microsoft.com/about")!
        XCTAssertNil(TeamsLauncher.rewriteToMSTeams(input))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsLauncherTests 2>&1 | tail -20`
Expected: compile failure — `TeamsLauncher` undefined.

- [ ] **Step 3: Implement launcher**

Create `OneToOne/Services/TeamsLauncher.swift`:

```swift
import Foundation
import AppKit

/// Opens a Microsoft Teams meeting URL using the desktop app if installed,
/// falling back to the web client (browser) via macOS URL handler routing.
/// No MS Graph, no auth — just URL scheme rewriting.
enum TeamsLauncher {

    /// Public entry point — fire-and-forget.
    static func open(_ urlString: String) {
        guard let parsed = URL(string: urlString) else { return }
        let target = rewriteToMSTeams(parsed) ?? parsed
        NSWorkspace.shared.open(target)
    }

    /// Rewrites `https://teams.microsoft.com/l/meetup-join/...` to
    /// `msteams:/l/meetup-join/...` so the desktop app handles it.
    /// Returns nil if the URL is not a Teams meet-join URL.
    static func rewriteToMSTeams(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "msteams" { return url }
        guard let host = url.host?.lowercased(),
              host == "teams.microsoft.com" || host == "teams.live.com",
              url.path.contains("/l/meetup-join/") else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "msteams"
        comps?.host = nil  // msteams: scheme has no host
        return comps?.url
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TeamsLauncherTests 2>&1 | tail -20`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/TeamsLauncher.swift Tests/TeamsLauncherTests.swift
git commit -m "feat(calendar): TeamsLauncher — launch Teams desktop app via msteams:// rewrite"
```

---

## Task 4: Extend `CalendarMeetingEvent` with `teamsJoinURL`

**Files:**
- Modify: `OneToOne/Services/CalendarMeetingImportService.swift`

**Note:** Pure plumbing — no new test file; covered indirectly by Task 7 importEvent tests.

- [ ] **Step 1: Add `teamsJoinURL` to the struct**

In `OneToOne/Services/CalendarMeetingImportService.swift`, modify `CalendarMeetingEvent` (lines 11-18):

```swift
struct CalendarMeetingEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let attendees: [CalendarMeetingAttendee]
    let teamsJoinURL: String?
    let isCancelled: Bool
    let isAllDay: Bool
}
```

- [ ] **Step 2: Populate the new fields in `fetchEvents(start:end:)`**

In the same file, locate the `.map { event in ... }` block (around line 49) and update the construction. Replace the entire `.map { ... }` body with:

```swift
            .map { event in
                CalendarMeetingEvent(
                    id: event.calendarItemIdentifier,
                    title: Self.normalizedTitle(event.title),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarTitle: event.calendar.title,
                    attendees: (event.attendees ?? []).map { attendee in
                        let email = Self.extractEmail(from: attendee.url)
                        let fallbackName = email?.components(separatedBy: "@").first ?? "Participant"
                        let name = Self.normalizedAttendeeName(attendee.name, fallback: fallbackName)
                        return CalendarMeetingAttendee(
                            id: email ?? name.lowercased(),
                            name: name,
                            email: email,
                            status: attendee.participantStatus == .declined ? .absent : .participant
                        )
                    },
                    teamsJoinURL: TeamsURLExtractor.extract(
                        url: event.url,
                        notes: event.notes,
                        location: event.location
                    ),
                    isCancelled: event.status == .canceled,
                    isAllDay: event.isAllDay
                )
            }
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 4: Find existing call sites that pattern-match `CalendarMeetingEvent` init**

Run: `grep -rn "CalendarMeetingEvent(" OneToOne/ Tests/ 2>&1`
Expected: only the one in `CalendarMeetingImportService.swift` (the struct is a value type built only by the service). If other sites exist (e.g., in `CalendarEventImportSheet.swift` previews), update them to pass `teamsJoinURL: nil, isCancelled: false, isAllDay: false`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/CalendarMeetingImportService.swift
git commit -m "feat(calendar): expose teamsJoinURL / isCancelled / isAllDay on CalendarMeetingEvent"
```

---

## Task 5: `ProjectMatchService` — deterministic fuzzy matcher

**Files:**
- Create: `OneToOne/Services/ProjectMatchService.swift`
- Test: `Tests/ProjectMatchServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ProjectMatchServiceTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class ProjectMatchServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    private func makeEvent(title: String,
                           attendees: [(name: String, email: String)] = [],
                           startOffsetMin: Int = 0) -> CalendarMeetingEvent {
        let start = Date().addingTimeInterval(TimeInterval(startOffsetMin * 60))
        return CalendarMeetingEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarTitle: "Work",
            attendees: attendees.map {
                CalendarMeetingAttendee(id: $0.email, name: $0.name, email: $0.email, status: .participant)
            },
            teamsJoinURL: nil,
            isCancelled: false,
            isAllDay: false
        )
    }

    private func makeSettings(userEmail: String? = "me@example.com",
                              managerEmail: String? = nil) -> AppSettings {
        let s = AppSettings()
        s.userEmail = userEmail
        s.managerEmail = managerEmail
        return s
    }

    func test_managerEmailWins_overEverythingElse() {
        let settings = makeSettings(managerEmail: "boss@example.com")
        let event = makeEvent(title: "Sync hebdo",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Boss", "boss@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .manager)
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.001)
    }

    func test_twoAttendees_matchedCollaborator_oneToOne() throws {
        let collab = Collaborator(name: "Sylvain Estellé")
        collab.email = "sylvain@example.com"
        context.insert(collab)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "Entretien Sylvain",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Sylvain", "sylvain@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .oneToOne)
        XCTAssertEqual(s.collaborator?.email, "sylvain@example.com")
        XCTAssertEqual(s.confidence, 1.0, accuracy: 0.001)
    }

    func test_twoAttendees_noCollaborator_oneToOneLowConfidence() {
        let settings = makeSettings()
        let event = makeEvent(title: "Entretien Sylvain",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("Sylvain", "sylvain@example.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .oneToOne)
        XCTAssertNil(s.collaborator)
        XCTAssertLessThan(s.confidence, 0.9)
        XCTAssertFalse(s.autoApply)
    }

    func test_projectFuzzyMatch_highConfidenceAutoApplies() throws {
        let proj = Project(name: "Téléphonie iPMI")
        context.insert(proj)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "[Téléphonie iPMI] Cadrage",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("A", "a@x.com"),
                                ("B", "b@x.com"),
                                ("C", "c@x.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .project)
        XCTAssertEqual(s.project?.name, "Téléphonie iPMI")
        XCTAssertGreaterThanOrEqual(s.confidence, 0.9)
        XCTAssertTrue(s.autoApply)
    }

    func test_projectFuzzyMatch_accentInsensitive() throws {
        let proj = Project(name: "diapason")
        context.insert(proj)
        try context.save()

        let settings = makeSettings()
        let event = makeEvent(title: "diapason : solution préconisée",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("X", "x@y.com"),
                                ("Y", "y@y.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .project)
        XCTAssertEqual(s.project?.name, "diapason")
    }

    func test_noMatch_fallsBackToGlobal() {
        let settings = makeSettings()
        let event = makeEvent(title: "Daily standup",
                              attendees: [
                                ("Me", "me@example.com"),
                                ("X", "x@y.com"),
                                ("Y", "y@y.com")
                              ])
        let s = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        XCTAssertEqual(s.kind, .global)
        XCTAssertLessThan(s.confidence, 0.5)
    }

    func test_normalize_stripsAccentsPunctuationAndCase() {
        XCTAssertEqual(
            ProjectMatchService.normalizedTokens("[Téléphonie iPMI] - Cadrage !"),
            ["telephonie", "ipmi", "cadrage"]
        )
    }
}
```

**Note:** This test references `AppSettings.userEmail` / `managerEmail` and `Collaborator.email`. Verify both exist before running. If `AppSettings.userEmail` doesn't exist yet, complete Task 6 first (settings extensions), then return here.

- [ ] **Step 2: Verify `AppSettings.userEmail` and `Collaborator.email` exist**

Run:
```bash
grep -n "var userEmail\|var managerEmail" OneToOne/Models/AppSettings.swift
grep -n "var email" OneToOne/Models/Entity.swift OneToOne/Models/OtherModels.swift
```

If `userEmail` is missing → jump to Task 6 first, then return here.
If `Collaborator.email` is missing → add it as `var email: String?` to the `Collaborator` model in the same commit as this task and update the test's `Collaborator(name:)` usage accordingly.

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ProjectMatchServiceTests 2>&1 | tail -30`
Expected: compile failure — `ProjectMatchService` undefined.

- [ ] **Step 4: Implement service**

Create `OneToOne/Services/ProjectMatchService.swift`:

```swift
import Foundation
import SwiftData

struct MatchSuggestion {
    let kind: MeetingKind
    let project: Project?
    let collaborator: Collaborator?
    let confidence: Double  // 0..1

    var autoApply: Bool { confidence >= 0.9 }

    static func global(confidence: Double = 0.3) -> MatchSuggestion {
        .init(kind: .global, project: nil, collaborator: nil, confidence: confidence)
    }
}

enum ProjectMatchService {

    // MARK: - Public API

    @MainActor
    static func suggestKind(for event: CalendarMeetingEvent,
                            context: ModelContext,
                            settings: AppSettings) -> MatchSuggestion {

        let userEmail = settings.userEmail?.lowercased()
        let attendees = event.attendees

        // 1. Manager — exact email match
        if let mgrEmail = settings.managerEmail?.lowercased(),
           attendees.contains(where: { $0.email?.lowercased() == mgrEmail }) {
            let collab = findCollaborator(email: mgrEmail, in: context)
            return MatchSuggestion(kind: .manager,
                                   project: nil,
                                   collaborator: collab,
                                   confidence: 1.0)
        }

        // 2. One-to-One — exactly 2 attendees after filtering self
        let others = attendees.filter { $0.email?.lowercased() != userEmail }
        if attendees.count >= 2, others.count == 1 {
            let otherEmail = others[0].email?.lowercased()
            if let email = otherEmail, let collab = findCollaborator(email: email, in: context) {
                return MatchSuggestion(kind: .oneToOne,
                                       project: nil,
                                       collaborator: collab,
                                       confidence: 1.0)
            }
            return MatchSuggestion(kind: .oneToOne,
                                   project: nil,
                                   collaborator: nil,
                                   confidence: 0.6)
        }

        // 3. Project — fuzzy match title vs Project.name
        if let (proj, score) = bestProjectMatch(title: event.title, in: context), score >= 0.7 {
            return MatchSuggestion(kind: .project,
                                   project: proj,
                                   collaborator: nil,
                                   confidence: score)
        }

        // 4. Fallback
        return .global()
    }

    // MARK: - Fuzzy matching (internal, exposed for tests)

    static func normalizedTokens(_ s: String) -> [String] {
        let folded = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let allowed = CharacterSet.alphanumerics
        var current = ""
        var tokens: [String] = []
        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Internals

    @MainActor
    private static func findCollaborator(email: String, in context: ModelContext) -> Collaborator? {
        let needle = email.lowercased()
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.email?.lowercased() == needle }
    }

    @MainActor
    private static func bestProjectMatch(title: String, in context: ModelContext) -> (Project, Double)? {
        let descriptor = FetchDescriptor<Project>()
        let projects = (try? context.fetch(descriptor)) ?? []
        guard !projects.isEmpty else { return nil }

        let titleTokens = normalizedTokens(title)
        let titleSet = Set(titleTokens)
        guard !titleSet.isEmpty else { return nil }

        var best: (Project, Double)?
        for proj in projects {
            let projTokens = normalizedTokens(proj.name)
            let projSet = Set(projTokens)
            guard !projSet.isEmpty else { continue }

            let overlap = Double(titleSet.intersection(projSet).count)
                        / Double(min(titleSet.count, projSet.count))

            let jw = jaroWinkler(titleTokens.joined(separator: " "),
                                  projTokens.joined(separator: " "))

            let score = max(overlap, jw)
            if score > (best?.1 ?? -1) {
                best = (proj, score)
            }
        }
        return best
    }

    /// Jaro-Winkler similarity (0..1). Implementation cribbed from the textbook
    /// description — small, allocation-light, no external dep.
    static func jaroWinkler(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let aChars = Array(a)
        let bChars = Array(b)
        let matchDistance = max(aChars.count, bChars.count) / 2 - 1
        guard matchDistance >= 0 else { return 0.0 }

        var aMatches = [Bool](repeating: false, count: aChars.count)
        var bMatches = [Bool](repeating: false, count: bChars.count)
        var matches = 0
        for i in aChars.indices {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, bChars.count)
            guard start < end else { continue }
            for j in start..<end where !bMatches[j] && aChars[i] == bChars[j] {
                aMatches[i] = true
                bMatches[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0.0 }

        var transpositions = 0
        var k = 0
        for i in aChars.indices where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if aChars[i] != bChars[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        let jaro = (m / Double(aChars.count)
                  + m / Double(bChars.count)
                  + (m - Double(transpositions) / 2.0) / m) / 3.0

        var prefix = 0
        for i in 0..<min(4, aChars.count, bChars.count) {
            if aChars[i] == bChars[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ProjectMatchServiceTests 2>&1 | tail -30`
Expected: 7 tests pass. If `test_projectFuzzyMatch_highConfidenceAutoApplies` confidence is below 0.9, lower threshold not allowed — investigate token overlap (should be 2/2 = 1.0 for `"[Téléphonie iPMI] Cadrage"` vs `"Téléphonie iPMI"`).

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/ProjectMatchService.swift Tests/ProjectMatchServiceTests.swift
git commit -m "feat(calendar): ProjectMatchService — fuzzy match event → MeetingKind"
```

---

## Task 6: Extend `AppSettings` with calendar/menubar/notif keys

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift`

**Note:** `userEmail` and `managerEmail` may already exist (manager work in progress). Skip duplicates; only add what's missing.

- [ ] **Step 1: Inspect current `AppSettings`**

Run: `grep -n "var " OneToOne/Models/AppSettings.swift | head -50`

Identify which of the following are already present:
- `userEmail`
- `managerEmail`
- `menubarEnabled` / `menubarShowNextTitle` / `menubarMaxTitleChars`
- `agendaInspectorOpenByDefault`
- `notifMeetingStart` / `notifMeetingEndWarning` / `notifMeetingEnd`
- `autoImportThreshold`

- [ ] **Step 2: Add only the missing fields**

Append the missing fields inside the `AppSettings` class (before the existing `init`). Use these exact declarations:

```swift
    // MARK: - Calendar integration
    var userEmail: String?
    var menubarEnabled: Bool = true
    var menubarShowNextTitle: Bool = true
    var menubarMaxTitleChars: Int = 25
    var agendaInspectorOpenByDefault: Bool = false
    var notifMeetingStart: Bool = true
    var notifMeetingEndWarning: Bool = true
    var notifMeetingEnd: Bool = true
    var autoImportThreshold: Double = 0.9
```

If `managerEmail` is missing, add:

```swift
    var managerEmail: String?
```

- [ ] **Step 3: Build to verify lightweight migration is acceptable**

Run: `swift build 2>&1 | tail -10`
Expected: build succeeds. All fields have defaults (or are optional) → SwiftData lightweight migration applies automatically (no `SchemaV2` needed).

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Models/AppSettings.swift
git commit -m "feat(settings): calendar/menubar/notification preferences keys"
```

---

## Task 7: `importEvent` on `CalendarMeetingImportService`

**Files:**
- Modify: `OneToOne/Services/CalendarMeetingImportService.swift`
- Test: `Tests/CalendarImportEventTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CalendarImportEventTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class CalendarImportEventTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }
    var service: CalendarMeetingImportService!
    var settings: AppSettings!

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        service = CalendarMeetingImportService()
        settings = AppSettings()
        settings.userEmail = "me@example.com"
        context.insert(settings)
        try context.save()
    }

    private func event(id: String = "evt-1",
                       title: String = "Daily standup",
                       teamsURL: String? = nil) -> CalendarMeetingEvent {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        return CalendarMeetingEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            calendarTitle: "Work",
            attendees: [
                CalendarMeetingAttendee(id: "me@example.com", name: "Me", email: "me@example.com", status: .participant),
                CalendarMeetingAttendee(id: "x@y.com", name: "X", email: "x@y.com", status: .participant),
                CalendarMeetingAttendee(id: "y@y.com", name: "Y", email: "y@y.com", status: .participant)
            ],
            teamsJoinURL: teamsURL,
            isCancelled: false,
            isAllDay: false
        )
    }

    func test_importEvent_populatesScheduledAndTeamsAndCalendarID() throws {
        let evt = event(teamsURL: "https://teams.microsoft.com/l/meetup-join/abc")
        let meeting = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(meeting.title, "Daily standup")
        XCTAssertEqual(meeting.scheduledStart, evt.startDate)
        XCTAssertEqual(meeting.scheduledEnd, evt.endDate)
        XCTAssertEqual(meeting.teamsJoinURL, "https://teams.microsoft.com/l/meetup-join/abc")
        XCTAssertEqual(meeting.calendarEventID, "evt-1")
        XCTAssertEqual(meeting.effectiveDuration, 1800, accuracy: 0.01)
    }

    func test_importEvent_isIdempotent_returnsExistingOnSecondCall() throws {
        let evt = event()
        let first = service.importEvent(evt, context: context, settings: settings)
        try context.save()
        let second = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(first.persistentModelID, second.persistentModelID)

        let count = try context.fetchCount(FetchDescriptor<Meeting>())
        XCTAssertEqual(count, 1)
    }

    func test_importEvent_setsKindFromMatchService_oneToOne() throws {
        let collab = Collaborator(name: "Alice")
        collab.email = "alice@example.com"
        context.insert(collab)
        try context.save()

        let evt = CalendarMeetingEvent(
            id: "evt-2",
            title: "Sync with Alice",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            calendarTitle: "Work",
            attendees: [
                CalendarMeetingAttendee(id: "me@example.com", name: "Me", email: "me@example.com", status: .participant),
                CalendarMeetingAttendee(id: "alice@example.com", name: "Alice", email: "alice@example.com", status: .participant)
            ],
            teamsJoinURL: nil,
            isCancelled: false,
            isAllDay: false
        )
        let meeting = service.importEvent(evt, context: context, settings: settings)
        XCTAssertEqual(meeting.kind, .oneToOne)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalendarImportEventTests 2>&1 | tail -30`
Expected: compile failure — `importEvent` undefined.

- [ ] **Step 3: Implement `importEvent` and dedupe helper**

In `OneToOne/Services/CalendarMeetingImportService.swift`, add inside the `CalendarMeetingImportService` class, after the existing `fetchEvents` methods:

```swift
    /// Imports a calendar event as a Meeting. Idempotent on `calendarEventID`:
    /// re-importing the same event returns the existing Meeting unchanged.
    /// Caller is responsible for `context.save()` after mutation.
    func importEvent(_ event: CalendarMeetingEvent,
                     context: ModelContext,
                     settings: AppSettings) -> Meeting {
        if let existing = findExisting(eventID: event.id, in: context) {
            return existing
        }

        let meeting = Meeting(title: event.title, date: event.startDate)
        meeting.scheduledStart = event.startDate
        meeting.scheduledEnd = event.endDate
        meeting.teamsJoinURL = event.teamsJoinURL
        meeting.calendarEventID = event.id

        let suggestion = ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
        meeting.kind = suggestion.kind
        if let project = suggestion.project {
            meeting.project = project
        }
        if let collab = suggestion.collaborator, !meeting.participants.contains(where: { $0.persistentModelID == collab.persistentModelID }) {
            meeting.participants.append(collab)
        }

        // Materialize attendees as Collaborator (dedup by email).
        let me = settings.userEmail?.lowercased()
        for attendee in event.attendees where attendee.email?.lowercased() != me {
            let collab = upsertCollaborator(for: attendee, in: context)
            if !meeting.participants.contains(where: { $0.persistentModelID == collab.persistentModelID }) {
                meeting.participants.append(collab)
            }
        }

        context.insert(meeting)
        return meeting
    }

    private func findExisting(eventID: String, in context: ModelContext) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func upsertCollaborator(for attendee: CalendarMeetingAttendee,
                                     in context: ModelContext) -> Collaborator {
        if let email = attendee.email?.lowercased() {
            let all = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
            if let match = all.first(where: { $0.email?.lowercased() == email }) {
                return match
            }
        }
        let collab = Collaborator(name: attendee.name)
        collab.email = attendee.email
        context.insert(collab)
        return collab
    }
```

**Verify `Meeting` initializer signature**: `Meeting(title:date:)` may or may not match the current convenience init. Run `grep -n "init(" OneToOne/Models/OtherModels.swift | head` to confirm; adapt the call if signature differs (use whatever convenience init exists, then assign title/date directly).

**Verify `Collaborator.email` and `Collaborator(name:)`**: same check via grep. Adjust if signature differs.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalendarImportEventTests 2>&1 | tail -30`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/CalendarMeetingImportService.swift Tests/CalendarImportEventTests.swift
git commit -m "feat(calendar): importEvent — idempotent Meeting creation with kind matching"
```

---

## Task 8: `CalendarAgendaService` (observable singleton)

**Files:**
- Create: `OneToOne/Services/CalendarAgendaService.swift`

**No unit tests** — service is a thin observable wrapper around `CalendarMeetingImportService` with timer/lifecycle side effects. Covered by manual verification in Task 18.

- [ ] **Step 1: Create the service**

Create `OneToOne/Services/CalendarAgendaService.swift`:

```swift
import Foundation
import EventKit
import Combine
import SwiftUI

@MainActor
final class CalendarAgendaService: ObservableObject {

    static let shared = CalendarAgendaService()

    @Published private(set) var eventsToday: [CalendarMeetingEvent] = []
    @Published private(set) var nextUpcoming: CalendarMeetingEvent?
    @Published private(set) var hasCalendarAccess: Bool = false

    private let importer = CalendarMeetingImportService()
    private var refreshTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?

    private init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    func bootstrap() async {
        hasCalendarAccess = await importer.requestAccess()
        refresh()
        startPeriodicRefresh()
    }

    /// Returns events for an arbitrary day (used by AgendaInspectorPanel).
    func events(for date: Date) -> [CalendarMeetingEvent] {
        guard hasCalendarAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return importer.fetchEvents(start: start, end: end)
            .filter { !$0.isAllDay }
    }

    // MARK: - Internals

    private func refresh() {
        guard hasCalendarAccess else { return }
        eventsToday = events(for: Date())
        nextUpcoming = computeNextUpcoming()
    }

    private func computeNextUpcoming() -> CalendarMeetingEvent? {
        let now = Date()
        let candidates = events(for: now) + events(for: now.addingTimeInterval(86_400))
        return candidates
            .filter { $0.endDate > now && !$0.isCancelled }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
                await MainActor.run { self?.refresh() }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/CalendarAgendaService.swift
git commit -m "feat(calendar): CalendarAgendaService — observable singleton, 30s refresh, EKEventStoreChanged"
```

---

## Task 9: `MeetingNotificationService`

**Files:**
- Create: `OneToOne/Services/MeetingNotificationService.swift`

**No unit tests** — UN scheduling has system side effects. Covered by manual verification in Task 20.

- [ ] **Step 1: Create the service**

Create `OneToOne/Services/MeetingNotificationService.swift`:

```swift
import Foundation
import UserNotifications
import SwiftData
import AppKit

@MainActor
final class MeetingNotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = MeetingNotificationService()

    private let center = UNUserNotificationCenter.current()

    private enum Category {
        static let start = "MEETING_START"
        static let end   = "MEETING_END"
    }

    private enum Action {
        static let open  = "OPEN_MEETING"
    }

    /// Posted when the user taps "Open" on a meeting notification. UserInfo
    /// carries `meetingID` (PersistentIdentifier.storeIdentifier as String).
    static let openMeetingNotification = Notification.Name("OneToOne.MeetingNotificationService.openMeeting")

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Schedules (or re-schedules) start / endWarning / end notifications
    /// for a Meeting that has `scheduledStart` & `scheduledEnd` set.
    func schedule(for meeting: Meeting, settings: AppSettings) {
        guard let start = meeting.scheduledStart,
              let end = meeting.scheduledEnd,
              end > start else { return }

        let baseID = idPrefix(for: meeting)
        cancel(for: meeting)  // idempotent — drop any previous pending

        let userInfo: [AnyHashable: Any] = [
            "meetingID": meeting.persistentModelID.storeIdentifier ?? ""
        ]

        if settings.notifMeetingStart, start > Date() {
            schedule(id: baseID + ".start",
                     title: "Réunion: \(meeting.title)",
                     body: "Démarre maintenant",
                     fireAt: start,
                     category: Category.start,
                     userInfo: userInfo)
        }

        let warning = end.addingTimeInterval(-5 * 60)
        if settings.notifMeetingEndWarning, warning > Date() {
            schedule(id: baseID + ".endWarning",
                     title: "Fin dans 5 min",
                     body: "\(meeting.title) se termine à \(formatTime(end))",
                     fireAt: warning,
                     category: nil,
                     userInfo: userInfo)
        }

        if settings.notifMeetingEnd, end > Date() {
            schedule(id: baseID + ".end",
                     title: "Réunion terminée",
                     body: meeting.title,
                     fireAt: end,
                     category: Category.end,
                     userInfo: userInfo)
        }
    }

    func cancel(for meeting: Meeting) {
        let base = idPrefix(for: meeting)
        center.removePendingNotificationRequests(withIdentifiers: [
            base + ".start",
            base + ".endWarning",
            base + ".end"
        ])
    }

    /// Re-syncs notifications for every future-scheduled Meeting in the store.
    /// Call at app launch for reboot resilience.
    func syncPending(context: ModelContext, settings: AppSettings) {
        let now = Date()
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { meeting in
                meeting.scheduledStart != nil && meeting.scheduledStart! > now
            }
        )
        let upcoming = (try? context.fetch(descriptor)) ?? []
        for meeting in upcoming {
            schedule(for: meeting, settings: settings)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let meetingID = userInfo["meetingID"] as? String, !meetingID.isEmpty else {
            completionHandler()
            return
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: Self.openMeetingNotification,
                                            object: nil,
                                            userInfo: ["meetingID": meetingID])
        }
        completionHandler()
    }

    // MARK: - Internals

    private func registerCategories() {
        let openAction = UNNotificationAction(identifier: Action.open,
                                              title: "Ouvrir",
                                              options: [.foreground])
        let startCat = UNNotificationCategory(identifier: Category.start,
                                              actions: [openAction],
                                              intentIdentifiers: [])
        let endCat = UNNotificationCategory(identifier: Category.end,
                                             actions: [openAction],
                                             intentIdentifiers: [])
        center.setNotificationCategories([startCat, endCat])
    }

    private func schedule(id: String, title: String, body: String,
                          fireAt: Date, category: String?, userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("[MeetingNotificationService] schedule \(id): \(error)") }
        }
    }

    private func idPrefix(for meeting: Meeting) -> String {
        "meeting.\(meeting.persistentModelID.storeIdentifier ?? UUID().uuidString)"
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
```

**Note on `storeIdentifier`:** `PersistentIdentifier.storeIdentifier` returns `String?`. If `nil` we use empty string for `userInfo` (notif still scheduled, but tap → ignored). This is a fail-safe — in practice the identifier is always present after `context.save()`.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: builds clean.

- [ ] **Step 3: Wire scheduling into `importEvent`**

Modify `OneToOne/Services/CalendarMeetingImportService.swift` — at the end of `importEvent`, before `return meeting`, add:

```swift
        context.insert(meeting)
        MeetingNotificationService.shared.schedule(for: meeting, settings: settings)
        return meeting
```

(Replace the existing `context.insert(meeting)` + `return meeting` pair.)

- [ ] **Step 4: Build + run all tests**

Run: `swift test 2>&1 | tail -15`
Expected: green. Existing `CalendarImportEventTests` still pass — scheduling has no effect in test environment (no permission, gracefully ignored).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MeetingNotificationService.swift OneToOne/Services/CalendarMeetingImportService.swift
git commit -m "feat(notif): MeetingNotificationService — schedule start/endWarning/end notifs"
```

---

## Task 10: `WeekStripView` (horizontal day selector)

**Files:**
- Create: `OneToOne/Views/WeekStripView.swift`

- [ ] **Step 1: Create the view**

Create `OneToOne/Views/WeekStripView.swift`:

```swift
import SwiftUI

/// Horizontal week strip à la Outlook mobile: 7 cells (day number + first
/// letter of weekday), selected day shown as a filled pill. Swipe / arrow
/// buttons shift the visible week by ±7 days.
struct WeekStripView: View {

    @Binding var selectedDate: Date
    var accent: Color = .accentColor

    @State private var weekAnchor: Date = Date()

    private let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        return c
    }()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { shiftWeek(by: -7) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    ForEach(weekDays, id: \.self) { day in
                        dayCell(day)
                    }
                }
                .frame(maxWidth: .infinity)

                Button { shiftWeek(by: 7) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            Text(selectedDateHeader)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .onAppear { weekAnchor = selectedDate }
    }

    private var weekDays: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)?.start else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedDateHeader: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE · d MMM ''yy"
        return fmt.string(from: selectedDate).capitalized
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        VStack(spacing: 2) {
            Text(dayLetter(day))
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : (isToday ? accent : .secondary))
            Text("\(calendar.component(.day, from: day))")
                .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(minWidth: 32, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accent : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = day
            weekAnchor = day
        }
    }

    private func dayLetter(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEEE"  // single letter
        return fmt.string(from: day).uppercased()
    }

    private func shiftWeek(by days: Int) {
        if let newAnchor = calendar.date(byAdding: .day, value: days, to: weekAnchor) {
            weekAnchor = newAnchor
            selectedDate = newAnchor
        }
    }
}

#Preview {
    @Previewable @State var date = Date()
    return WeekStripView(selectedDate: $date)
        .frame(width: 320)
        .padding()
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/WeekStripView.swift
git commit -m "feat(view): WeekStripView — horizontal Outlook-style day selector"
```

---

## Task 11: `AgendaInspectorPanel`

**Files:**
- Create: `OneToOne/Views/AgendaInspectorPanel.swift`

- [ ] **Step 1: Create the panel view**

Create `OneToOne/Views/AgendaInspectorPanel.swift`:

```swift
import SwiftUI
import SwiftData

struct AgendaInspectorPanel: View {

    @Environment(\.modelContext) private var context
    @Query private var appSettings: [AppSettings]

    @StateObject private var agenda = CalendarAgendaService.shared
    @State private var selectedDate: Date = Date()
    @State private var events: [CalendarMeetingEvent] = []
    @State private var refreshTrigger: Int = 0

    private let importer = CalendarMeetingImportService()

    private var settings: AppSettings {
        appSettings.first ?? AppSettings()
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekStripView(selectedDate: $selectedDate)
                .padding(.vertical, 8)
                .background(.background.secondary)

            Divider()

            if !agenda.hasCalendarAccess {
                permissionDeniedView
            } else if events.isEmpty {
                ContentUnavailableView("Aucune réunion ce jour",
                                       systemImage: "calendar",
                                       description: Text("Sélectionnez une autre date."))
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 280)
        .task { await agenda.bootstrap() }
        .onChange(of: selectedDate) { _, _ in reload() }
        .onChange(of: agenda.eventsToday) { _, _ in reload() }
        .onAppear { reload() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func eventRow(_ event: CalendarMeetingEvent) -> some View {
        let existing = existingMeeting(for: event.id)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timeRange(event))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if event.isCancelled {
                    Label("Annulé", systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(event.title)
                .font(.body)
                .strikethrough(event.isCancelled)
                .foregroundStyle(event.isCancelled ? .secondary : .primary)
            HStack(spacing: 12) {
                if !event.attendees.isEmpty {
                    Label("\(event.attendees.count)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if event.teamsJoinURL != nil {
                    Label("Teams", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if existing != nil {
                    Label("Importé", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 8) {
                if let url = event.teamsJoinURL {
                    Button {
                        TeamsLauncher.open(url)
                    } label: {
                        Label("Rejoindre Teams", systemImage: "video.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if let meeting = existing {
                    Button {
                        openMeeting(meeting)
                    } label: {
                        Label("Ouvrir", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        let meeting = importer.importEvent(event, context: context, settings: settings)
                        try? context.save()
                        openMeeting(meeting)
                    } label: {
                        Label("Importer", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(rowBackground(event))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Accès au calendrier refusé")
                .font(.headline)
            Button("Ouvrir les réglages système") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                NSWorkspace.shared.open(url)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func rowBackground(_ event: CalendarMeetingEvent) -> Color {
        let now = Date()
        if event.endDate < now { return .secondary.opacity(0.05) }
        if event.startDate <= now && event.endDate >= now { return .accentColor.opacity(0.15) }
        return .background.secondary
    }

    private func timeRange(_ event: CalendarMeetingEvent) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) ─ \(fmt.string(from: event.endDate))"
    }

    private func reload() {
        events = agenda.events(for: selectedDate)
    }

    private func existingMeeting(for eventID: String) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func openMeeting(_ meeting: Meeting) {
        NotificationCenter.default.post(name: .openMeetingFromAgenda,
                                        object: nil,
                                        userInfo: ["meetingID": meeting.persistentModelID.storeIdentifier ?? ""])
    }
}

extension Notification.Name {
    static let openMeetingFromAgenda = Notification.Name("OneToOne.AgendaInspectorPanel.openMeeting")
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/AgendaInspectorPanel.swift
git commit -m "feat(view): AgendaInspectorPanel — daily agenda with join/import actions"
```

---

## Task 12: Wire `AgendaInspectorPanel` into `MeetingsListView`

**Files:**
- Modify: `OneToOne/Views/MeetingsListView.swift`

- [ ] **Step 1: Identify toolbar/inspector insertion point**

Run: `grep -n "toolbar\|NavigationStack\|NavigationSplitView\|\.inspector" OneToOne/Views/MeetingsListView.swift | head -20`

Locate the top-level container view's `.toolbar` (or add one if absent) and the body's outermost view.

- [ ] **Step 2: Add `@State` toggle + `.inspector` modifier**

In `MeetingsListView`, near other `@State` declarations, add:

```swift
    @State private var agendaInspectorOpen: Bool = false
```

If the view has a settings query, default it from `settings.agendaInspectorOpenByDefault` in `.onAppear`.

On the outermost view (the one that owns toolbar), append:

```swift
.inspector(isPresented: $agendaInspectorOpen) {
    AgendaInspectorPanel()
        .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
}
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            agendaInspectorOpen.toggle()
        } label: {
            Label("Agenda", systemImage: "calendar")
        }
    }
}
```

If `.toolbar` already exists, **add only the `ToolbarItem`** inside it (do not duplicate `.toolbar`).

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingsListView.swift
git commit -m "feat(view): MeetingsListView — trailing AgendaInspectorPanel toggle"
```

---

## Task 13: Update time-stats call sites to use `effectiveDuration`

**Files:**
- Modify: identified call sites in `OneToOne/Views/MeetingsListView.swift`, `OneToOne/Services/ExportService.swift`, `OneToOne/Views/ManagerTrackingView.swift` (if applicable)

- [ ] **Step 1: Locate call sites using `recordingDuration`**

Run: `grep -rn "recordingDuration" OneToOne/Views/ OneToOne/Services/ 2>&1 | grep -v "OtherModels.swift\|MeetingModels.swift"`

Expected: list of view/service files that display or aggregate Meeting duration.

- [ ] **Step 2: Substitute `effectiveDuration`**

For each call site **where the value is shown to the user as a meeting duration or rolled into a meeting-time aggregate**, replace `recordingDuration` with `effectiveDuration`.

**Do NOT replace**:
- `recordingDuration` reads inside `effectiveDuration` itself (the fallback).
- Any read inside `BackupService.swift` or transcription/recording infrastructure (these reference actual recorded audio length — keep them as-is).

For each file modified, document the substitution. Example for `MeetingsListView.swift`:

```swift
// before:
Text(formatDuration(meeting.recordingDuration))
// after:
Text(formatDuration(meeting.effectiveDuration))
```

- [ ] **Step 3: Build + run full suite**

Run: `swift test 2>&1 | tail -15`
Expected: green.

- [ ] **Step 4: Manual visual check**

Launch the app, open `MeetingsListView`. For a Meeting with `scheduledStart`/`End` set (or test by editing one in the DB), confirm the displayed duration matches calendar bounds, not recording bounds.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/MeetingsListView.swift OneToOne/Services/ExportService.swift OneToOne/Views/ManagerTrackingView.swift
git commit -m "feat(stats): use effectiveDuration (calendar) for displayed meeting times"
```

(Adjust the `git add` line to match files actually modified.)

---

## Task 14: Surface match suggestion in `CalendarEventImportSheet`

**Files:**
- Modify: `OneToOne/Views/CalendarEventImportSheet.swift`

- [ ] **Step 1: Read current sheet structure**

Run: `wc -l OneToOne/Views/CalendarEventImportSheet.swift && head -60 OneToOne/Views/CalendarEventImportSheet.swift`

Identify where event metadata is rendered and where the "Importer" action button lives.

- [ ] **Step 2: Add a "Suggestion" section above the action button**

Inside the sheet body, before the import button, add:

```swift
    // Computed match suggestion (recomputed on each body render — cheap).
    private var matchSuggestion: MatchSuggestion {
        ProjectMatchService.suggestKind(for: event, context: context, settings: settings)
    }
```

And in the body:

```swift
        Section("Suggestion") {
            let s = matchSuggestion
            HStack {
                Image(systemName: s.kind.sfSymbol)
                VStack(alignment: .leading) {
                    Text(s.kind.label)
                        .font(.headline)
                    if let project = s.project {
                        Text("Projet: \(project.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let collab = s.collaborator {
                        Text("Avec: \(collab.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int(s.confidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(s.autoApply ? .green : .orange)
            }
        }
```

Adapt to the sheet's actual styling (Form vs VStack). Use existing styling patterns from the file.

- [ ] **Step 3: Make the Import button consume the suggestion**

Where the sheet calls into the import path, replace any prior bespoke logic with:

```swift
        Button("Importer") {
            let importer = CalendarMeetingImportService()
            _ = importer.importEvent(event, context: context, settings: settings)
            try? context.save()
            dismiss()
        }
```

(Assuming `context` is `@Environment(\.modelContext)` and `dismiss` is `@Environment(\.dismiss)` — if they aren't already in scope, add them at the top of the view struct.)

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/CalendarEventImportSheet.swift
git commit -m "feat(view): CalendarEventImportSheet — show match suggestion + confidence"
```

---

## Task 15: Settings UI — new "Calendrier & menubar" section

**Files:**
- Modify: `OneToOne/Views/SettingsView.swift`

- [ ] **Step 1: Locate the SettingsView body**

Run: `grep -n "var body\|Section\|Form\|TabView" OneToOne/Views/SettingsView.swift | head -30`

Identify the pattern (likely `Form` with `Section`s, possibly in a `TabView`).

- [ ] **Step 2: Add the section**

Append a new `Section` (or new tab) following the file's existing pattern:

```swift
        Section("Calendrier & menubar") {
            Toggle("Afficher la barre des menus", isOn: $settings.menubarEnabled)
            Toggle("Afficher le titre du prochain meeting", isOn: $settings.menubarShowNextTitle)
                .disabled(!settings.menubarEnabled)
            Stepper(value: $settings.menubarMaxTitleChars, in: 10...60) {
                Text("Longueur max du titre: \(settings.menubarMaxTitleChars)")
            }
            .disabled(!settings.menubarEnabled || !settings.menubarShowNextTitle)

            Divider()

            Toggle("Ouvrir le panneau agenda par défaut", isOn: $settings.agendaInspectorOpenByDefault)

            Divider()

            Toggle("Notification au début de réunion", isOn: $settings.notifMeetingStart)
            Toggle("Notification 5 min avant la fin", isOn: $settings.notifMeetingEndWarning)
            Toggle("Notification à la fin de réunion", isOn: $settings.notifMeetingEnd)

            Divider()

            TextField("Votre email (pour filtrer 'moi' des participants)", text: Binding(
                get: { settings.userEmail ?? "" },
                set: { settings.userEmail = $0.isEmpty ? nil : $0 }
            ))

            Slider(value: $settings.autoImportThreshold, in: 0.5...1.0) {
                Text("Seuil de match auto: \(Int(settings.autoImportThreshold * 100))%")
            }
        }
```

Adjust the surrounding `settings` reference to match how the existing `SettingsView` accesses `AppSettings` (likely `@Query` + `.first`, or an `@Bindable`).

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): Calendrier & menubar section — toggles, threshold, user email"
```

---

## Task 16: `MenuBarController` (NSStatusItem)

**Files:**
- Create: `OneToOne/Services/MenuBarController.swift`

- [ ] **Step 1: Create the controller**

Create `OneToOne/Services/MenuBarController.swift`:

```swift
import AppKit
import SwiftUI
import Combine
import SwiftData

@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private weak var container: ModelContainer?

    func install(container: ModelContainer) {
        self.container = container

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar.badge.clock",
                                            accessibilityDescription: "OneToOne agenda")
        statusItem?.menu = NSMenu()  // populated on refresh

        CalendarAgendaService.shared.$eventsToday
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    func uninstall() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Refresh

    private func refresh() {
        guard let item = statusItem else { return }
        let settings = currentSettings()
        guard settings?.menubarEnabled ?? true else {
            item.button?.title = ""
            item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
            item.menu = buildMenu(settings: settings)
            return
        }

        let upcoming = CalendarAgendaService.shared.nextUpcoming
        item.button?.title = statusTitle(for: upcoming, settings: settings)
        item.menu = buildMenu(settings: settings)
    }

    private func statusTitle(for event: CalendarMeetingEvent?,
                             settings: AppSettings?) -> String {
        guard settings?.menubarShowNextTitle ?? true else { return "" }
        guard let event else { return "" }
        let now = Date()
        let maxChars = settings?.menubarMaxTitleChars ?? 25
        let title = truncated(event.title, to: maxChars)

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        if event.startDate <= now && event.endDate >= now {
            let mins = Int(event.endDate.timeIntervalSince(now) / 60)
            return "● \(title) (\(mins)m)"
        }
        let minutesUntil = Int(event.startDate.timeIntervalSince(now) / 60)
        if minutesUntil < 30 && minutesUntil >= 0 {
            return "Dans \(minutesUntil) min: \(title)"
        }
        return "\(title) · \(fmt.string(from: event.startDate))"
    }

    private func truncated(_ s: String, to max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    private func buildMenu(settings: AppSettings?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: dayHeader(Date()), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let events = CalendarAgendaService.shared.eventsToday
        if events.isEmpty {
            let none = NSMenuItem(title: "(aucune réunion)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for event in events {
                menu.addItem(makeEventItem(event))
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Ouvrir OneToOne",
                                action: #selector(openMainWindow),
                                keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Quitter",
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func makeEventItem(_ event: CalendarMeetingEvent) -> NSMenuItem {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let title = "\(fmt.string(from: event.startDate))  \(event.title)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if event.isCancelled {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: NSColor.secondaryLabelColor]
            )
        }

        let submenu = NSMenu()
        if let url = event.teamsJoinURL {
            let join = NSMenuItem(title: "Rejoindre Teams", action: #selector(joinTeams(_:)), keyEquivalent: "")
            join.target = self
            join.representedObject = url
            submenu.addItem(join)
        } else {
            let none = NSMenuItem(title: "(pas de lien Teams)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        let open = NSMenuItem(title: "Ouvrir dans OneToOne", action: #selector(openEvent(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = event.id
        submenu.addItem(open)
        item.submenu = submenu
        return item
    }

    private func dayHeader(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "'Aujourd''hui · 'EEEE d MMMM"
        return fmt.string(from: date).capitalized
    }

    private func currentSettings() -> AppSettings? {
        guard let context = container?.mainContext else { return nil }
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Actions

    @objc private func joinTeams(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        TeamsLauncher.open(url)
    }

    @objc private func openEvent(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        guard let eventID = sender.representedObject as? String,
              let context = container?.mainContext else { return }
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.calendarEventID == eventID }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            NotificationCenter.default.post(
                name: .openMeetingFromAgenda,
                object: nil,
                userInfo: ["meetingID": existing.persistentModelID.storeIdentifier ?? ""]
            )
        } else if let event = CalendarAgendaService.shared.eventsToday.first(where: { $0.id == eventID }) {
            guard let settings = currentSettings() else { return }
            let importer = CalendarMeetingImportService()
            let meeting = importer.importEvent(event, context: context, settings: settings)
            try? context.save()
            NotificationCenter.default.post(
                name: .openMeetingFromAgenda,
                object: nil,
                userInfo: ["meetingID": meeting.persistentModelID.storeIdentifier ?? ""]
            )
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible == false || $0.title.isEmpty == false }?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/MenuBarController.swift
git commit -m "feat(menubar): MenuBarController — NSStatusItem with next meeting + quick join"
```

---

## Task 17: AppDelegate adoption + service wiring

**Files:**
- Create: `OneToOne/AppDelegate.swift`
- Modify: `OneToOne/OneToOneApp.swift`

- [ ] **Step 1: Create AppDelegate**

Create `OneToOne/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notification permission — non-blocking
        Task { _ = await MeetingNotificationService.shared.requestAuthorization() }

        guard let container = OneToOneApp.sharedContainer else { return }

        menuBar.install(container: container)

        // Re-arm pending notifs on launch (reboot resilience)
        let context = container.mainContext
        if let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            MeetingNotificationService.shared.syncPending(context: context, settings: settings)
        }

        // Bootstrap calendar agenda observer
        Task { await CalendarAgendaService.shared.bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar.uninstall()
    }
}
```

- [ ] **Step 2: Wire AppDelegate into `OneToOneApp`**

In `OneToOne/OneToOneApp.swift`, add inside the `OneToOneApp` struct (near `static var sharedContainer`):

```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

- [ ] **Step 3: Build + run**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

Then launch from Xcode (or `swift run` if applicable for this app): observe the menubar icon appearing.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/AppDelegate.swift OneToOne/OneToOneApp.swift
git commit -m "feat(app): AppDelegate — install MenuBarController + bootstrap agenda + sync notifs"
```

---

## Task 18: "Resync depuis calendrier" button on `MeetingView`

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift` (or `OneToOne/Views/Meeting/MeetingDetailsBlock.swift` — pick the one that displays meeting metadata)

- [ ] **Step 1: Locate the metadata block in MeetingView**

Run: `grep -n "scheduledStart\|date\|title" OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingDetailsBlock.swift 2>&1 | head -20`

Pick the file that shows the editable Meeting header. Likely `MeetingDetailsBlock.swift`.

- [ ] **Step 2: Add a "Resync" button when `calendarEventID != nil`**

In the metadata block view, add (alongside existing edit/save buttons):

```swift
        if meeting.calendarEventID != nil {
            Button {
                resyncFromCalendar()
            } label: {
                Label("Resync depuis calendrier", systemImage: "arrow.triangle.2.circlepath")
            }
        }
```

And the method:

```swift
    @MainActor
    private func resyncFromCalendar() {
        guard let eventID = meeting.calendarEventID else { return }
        // Search a wide window — event may have moved
        let importer = CalendarMeetingImportService()
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 60, to: now) ?? now
        let events = importer.fetchEvents(start: start, end: end)
        guard let match = events.first(where: { $0.id == eventID }) else { return }

        meeting.title = match.title
        meeting.scheduledStart = match.startDate
        meeting.scheduledEnd = match.endDate
        meeting.teamsJoinURL = match.teamsJoinURL
        meeting.date = match.startDate

        try? context.save()
        MeetingNotificationService.shared.schedule(for: meeting, settings: currentSettings)
    }
```

`currentSettings` must be available in scope. If it isn't, add `@Query private var allSettings: [AppSettings]` and use `allSettings.first ?? AppSettings()`.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingDetailsBlock.swift
git commit -m "feat(meeting): Resync from calendar — refresh title/dates/Teams URL from EKEvent"
```

---

## Task 19: Route notification taps to open Meeting

**Files:**
- Modify: `OneToOne/Views/MeetingsListView.swift` (or whatever holds the root navigation state)

- [ ] **Step 1: Identify navigation state holder**

Run: `grep -rn "NavigationSplitView\|@State.*selectedMeeting\|@Published.*selectedMeeting" OneToOne/Views/ | head -10`

Find the component that owns the selected-Meeting state.

- [ ] **Step 2: Subscribe to both notification posts**

In that view's body, attach:

```swift
.onReceive(NotificationCenter.default.publisher(for: MeetingNotificationService.openMeetingNotification)) { note in
    selectMeeting(fromUserInfo: note.userInfo)
}
.onReceive(NotificationCenter.default.publisher(for: .openMeetingFromAgenda)) { note in
    selectMeeting(fromUserInfo: note.userInfo)
}
```

And the helper:

```swift
    private func selectMeeting(fromUserInfo info: [AnyHashable: Any]?) {
        guard let raw = info?["meetingID"] as? String, !raw.isEmpty else { return }
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        // Match by storeIdentifier — PersistentIdentifier.storeIdentifier returns
        // the unique CoreData URI for the row.
        if let target = all.first(where: { $0.persistentModelID.storeIdentifier == raw }) {
            selectedMeeting = target
        }
    }
```

(Replace `selectedMeeting` with the actual navigation binding.)

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingsListView.swift
git commit -m "feat(nav): route notification/agenda taps to open target Meeting"
```

---

## Task 20: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Clean build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -15`
Expected: all green. Note in commit if any pre-existing tests now fail.

- [ ] **Step 3: Manual checklist (launch app)**

Verify each item:

| # | Check | How |
|---|------|-----|
| 1 | Calendar permission prompt | First launch — system dialog appears. |
| 2 | Menubar icon present | Look at status bar top-right. |
| 3 | Menubar shows next meeting title | If you have an upcoming meeting in macOS Calendar. |
| 4 | Menubar dropdown lists today's events | Click the icon. |
| 5 | Quick "Rejoindre Teams" from menubar | Submenu on event with Teams URL → Teams desktop opens. |
| 6 | Agenda inspector toggle | Click calendar toolbar button in MeetingsList → right panel slides in. |
| 7 | WeekStripView nav | Click `<`/`>`, tap days, header updates. |
| 8 | Import from inspector | Click "Importer" on event → Meeting created, "Importé" badge appears. |
| 9 | Re-import idempotent | Click "Importer" again → no duplicate; "Ouvrir" button shown. |
| 10 | Match suggestion in sheet | If sheet is opened via existing flow → confidence + suggested kind visible. |
| 11 | Settings section | Open Settings → "Calendrier & menubar" section present, toggles work. |
| 12 | `effectiveDuration` in stats | Imported Meeting shows duration matching calendar (not recording). |
| 13 | Notif T-0 | Create a calendar event 2 min in future, import, wait — banner fires. |
| 14 | Notif tap → open Meeting | Tap "Ouvrir" action on notif → app foreground, correct Meeting selected. |
| 15 | Notif end-warning | Same event at T-5min-end fires (test with 6-min event imported 1 min before start). |
| 16 | Resync from calendar | Edit the EKEvent title in macOS Calendar, then click Resync in MeetingView → fields update. |
| 17 | Permission denied state | Deny calendar in System Settings → inspector shows "Autoriser" CTA. |

- [ ] **Step 4: Note any defects**

For each failing check, create a small follow-up commit fixing it (not part of this plan — file new tasks if substantial).

- [ ] **Step 5: Final commit (only if any cleanup was done)**

```bash
git status
# if anything changed during verification cleanup:
git add <files>
git commit -m "fix(calendar-teams): manual verification cleanup"
```

- [ ] **Step 6: Branch summary**

Run: `git log --oneline master..HEAD`
Expected: ~17 focused commits, one per task (some tasks may have produced 2 commits if Task 5 needed Task 6 to run first).

---

## Out-of-scope notes

The following are mentioned in the spec but **not implemented** in this plan and are left for future work:
- Conflict-overlap UI for overlapping events (stacked rendering is sufficient v1).
- `SMAppService.mainApp` login-launch toggle.
- Dock-less menubar-only activation policy toggle.
- LLM-based fallback when fuzzy match fails.
- MS Graph integration (transcripts ingestion, chat posting, real attendance).
- Snooze action on `endWarning` notification.
- Multi-account direct OAuth for Google / Outlook (EventKit transparently uses macOS Calendar.app accounts).

---

## Self-review notes (author)

- **Coverage**: every spec section (§3–§14) is mapped to at least one task. §15 testing strategy is satisfied by Task 1/2/3/5/7 unit + integration tests and Task 20 manual checklist.
- **Type consistency**: `MatchSuggestion`, `CalendarMeetingEvent`, `MeetingNotificationService.openMeetingNotification`, `openMeetingFromAgenda` notification name — all referenced consistently across tasks.
- **Ordering risk**: Task 5 (ProjectMatchService) requires `AppSettings.userEmail` which is in Task 6. Task 5 Step 2 documents the dependency and the user is instructed to swap order if needed.
- **`Collaborator.email`**: assumed to exist. Task 5 Step 2 verifies; if missing, the task plan documents adding it inline.
- **`Meeting(title:date:)` initializer**: assumed; Task 7 Step 3 documents verifying signature.
- **No placeholders**: every code step contains the actual code. No "implement appropriately" or "handle edge cases" without specifics.
