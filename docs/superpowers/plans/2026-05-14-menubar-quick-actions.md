# Menubar Quick Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing `MenuBarController` into a productivity hub with quick-start meeting actions (ad-hoc, 1:1 favourite, 1:1 manager), inline action/note popovers, an "urgent actions" section with a click-to-detail popover, a per-day stats footer (past time + meetings without a project), a search popover, and a count badge on the menubar icon.

**Architecture:** Pure helpers (`UrgentActionsSelector`, `TodayStatsCalculator`, `MenubarBadgeText`) live in a new `MenuBarStats.swift` and are XCTest-covered. `MenuBarController` consumes those helpers, owns four `NSPopover` instances (each backed by an SwiftUI host view under `Views/Menubar/`), and observes `ModelContext` saves to refresh the badge + urgent section idempotently. `QuickLaunchRouter` gains `startAdHocMeeting` and `startManagerMeeting` to reuse the existing 1:1-meeting WindowGroup pipeline.

**Tech Stack:** Swift 5.9, AppKit (`NSStatusItem`, `NSPopover`, `NSHostingController`), SwiftUI, SwiftData, XCTest. Tests in `Tests/` target (`swift test`).

**Spec:** [docs/superpowers/specs/2026-05-14-menubar-quick-actions-design.md](../specs/2026-05-14-menubar-quick-actions-design.md).

**Pre-flight (once):**
```bash
git status
swift test 2>&1 | tail -10
```

---

## Task 1: `MenuBarStats` helpers (pure, XCTest-covered)

**Files:**
- Create: `OneToOne/Services/MenuBarStats.swift`
- Test: `Tests/MenuBarStatsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MenuBarStatsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `swift test --filter MenuBarStatsTests 2>&1 | tail -20`
Expected: compile failure — `UrgentActionsSelector`, `TodayStatsCalculator`, `MenubarBadgeText` undefined.

- [ ] **Step 3: Implement the helpers**

Create `OneToOne/Services/MenuBarStats.swift`:

```swift
import Foundation
import SwiftData

// MARK: - Urgent actions selector

enum UrgentActionsSelector {

    /// Returns ActionTasks that should appear in the menubar urgent
    /// section, sorted (overdue → today → old-no-date). See spec §5.
    @MainActor
    static func qualifying(in context: ModelContext, now: Date = Date()) -> [ActionTask] {
        let descriptor = FetchDescriptor<ActionTask>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        let filtered = all.filter { task in
            guard !task.isCompleted else { return false }
            if let due = task.dueDate {
                return due < endOfToday
            }
            // no due date: only stale (>= 30d) tasks qualify
            if let createdAt = task.createdAt {
                return createdAt <= thirtyDaysAgo
            }
            return false
        }

        return filtered.sorted { lhs, rhs in
            let lb = bucket(for: lhs, startOfToday: startOfToday, endOfToday: endOfToday)
            let rb = bucket(for: rhs, startOfToday: startOfToday, endOfToday: endOfToday)
            if lb != rb { return lb < rb }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
    }

    /// Bucket order: 0 = overdue, 1 = today, 2 = stale-no-date.
    private static func bucket(for task: ActionTask, startOfToday: Date, endOfToday: Date) -> Int {
        if let due = task.dueDate {
            if due < startOfToday { return 0 }
            return 1
        }
        return 2
    }
}

// MARK: - Today stats

struct TodayStats: Equatable {
    let tempsPasseSeconds: TimeInterval
    let sansProjet: Int
}

enum TodayStatsCalculator {

    @MainActor
    static func compute(in context: ModelContext, now: Date = Date()) -> TodayStats {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        var passed: TimeInterval = 0
        var withoutProject = 0

        for meeting in all {
            // "Within today": prefer scheduledStart, fall back to .date.
            let anchor = meeting.scheduledStart ?? meeting.date
            guard anchor >= startOfToday && anchor < endOfToday else { continue }

            if meeting.project == nil { withoutProject += 1 }

            let endRef = meeting.scheduledEnd ?? meeting.date
            if endRef < now {
                passed += meeting.effectiveDuration
            }
        }

        return TodayStats(tempsPasseSeconds: passed, sansProjet: withoutProject)
    }
}

// MARK: - Badge text

enum MenubarBadgeText {

    /// Returns the title suffix to append to the status item, or "" if none.
    static func suffix(urgentCount: Int, hasOverdue: Bool) -> String {
        guard urgentCount > 0 else { return "" }
        return " ●\(urgentCount)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MenuBarStatsTests 2>&1 | tail -20`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MenuBarStats.swift Tests/MenuBarStatsTests.swift
git commit -m "feat(menubar): pure helpers — UrgentActionsSelector + TodayStatsCalculator + MenubarBadgeText"
```

---

## Task 2: Extend `QuickLaunchRouter` with ad-hoc + manager starters

**Files:**
- Modify: `OneToOne/Services/QuickLaunchRouter.swift`

- [ ] **Step 1: Locate the existing `startOneToOne` method**

Run: `grep -n "func startOneToOne\|^}" OneToOne/Services/QuickLaunchRouter.swift | head -10`
Expected: `func startOneToOne(...)` around line 30.

- [ ] **Step 2: Add the two new methods**

In `OneToOne/Services/QuickLaunchRouter.swift`, after `startOneToOne(...)`, add:

```swift
    /// Creates a `kind=.global` meeting with no participants and publishes
    /// a launch token that opens the 1to1-meeting window with recording on.
    @discardableResult
    func startAdHocMeeting(in context: ModelContext) -> Meeting {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let meeting = Meeting(
            title: "Réunion ad-hoc \(formatter.string(from: Date()))",
            date: Date()
        )
        meeting.kind = .global
        context.insert(meeting)
        do { try context.save() } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp?.activate(ignoringOtherApps: true)
        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: true
        )
        return meeting
    }

    /// Same as `startOneToOne` but stamps `kind=.manager`. Caller provides
    /// the manager collaborator (resolved from `AppSettings.managerEmail`).
    @discardableResult
    func startManagerMeeting(collaborator: Collaborator,
                              in context: ModelContext) -> Meeting {
        let meeting = Meeting(
            title: "1:1 Manager — \(collaborator.name)",
            date: Date()
        )
        meeting.kind = .manager
        context.insert(meeting)
        meeting.participants = [collaborator]
        do { try context.save() } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp?.activate(ignoringOtherApps: true)
        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: true
        )
        return meeting
    }
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/QuickLaunchRouter.swift
git commit -m "feat(router): startAdHocMeeting + startManagerMeeting"
```

---

## Task 3: `QuickActionPopover` view (Q4 — new action)

**Files:**
- Create: `OneToOne/Views/Menubar/QuickActionPopover.swift`

- [ ] **Step 1: Create the SwiftUI host view**

Create the directory + file:
```bash
mkdir -p OneToOne/Views/Menubar
```

`OneToOne/Views/Menubar/QuickActionPopover.swift`:

```swift
import SwiftUI
import SwiftData

/// Compact popover anchored on the menubar icon — creates an ActionTask.
struct QuickActionPopover: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]

    @State private var title: String = ""
    @State private var project: Project?
    @State private var collaborator: Collaborator?
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nouvelle action").font(.headline)
            TextField("Titre de l'action…", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Picker("", selection: $project) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in
                        Text(p.name).tag(p as Project?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                Picker("", selection: $collaborator) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            HStack {
                Toggle("Échéance", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Annuler") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = ActionTask(title: trimmed, dueDate: hasDueDate ? dueDate : nil)
        task.project = project
        task.collaborator = collaborator
        context.insert(task)
        try? context.save()
        onDismiss()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Menubar/QuickActionPopover.swift
git commit -m "feat(menubar): QuickActionPopover — create ActionTask from menubar"
```

---

## Task 4: `QuickNotePopover` view (Q5 — quick note)

**Files:**
- Create: `OneToOne/Views/Menubar/QuickNotePopover.swift`

- [ ] **Step 1: Inspect `Note` init to know how it attaches**

Run: `grep -n "init\|var project\|var collaborator" OneToOne/Models/Note.swift | head -10`
Expected: `Note` has optional `project: Project?` and `collaborator: Collaborator?` relationships. Confirm field names before writing the view; adapt below if they differ.

- [ ] **Step 2: Create the view**

`OneToOne/Views/Menubar/QuickNotePopover.swift`:

```swift
import SwiftUI
import SwiftData

/// Compact note-capture popover.
struct QuickNotePopover: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]

    enum LinkTarget: Hashable {
        case none
        case project(PersistentIdentifier)
        case collaborator(PersistentIdentifier)
    }

    @State private var text: String = ""
    @State private var linkTarget: LinkTarget = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note rapide").font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Picker("Lié à", selection: $linkTarget) {
                    Text("Aucun").tag(LinkTarget.none)
                    Divider()
                    Section("Projets") {
                        ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in
                            Text("📁 \(p.name)").tag(LinkTarget.project(p.persistentModelID))
                        }
                    }
                    Section("Collaborateurs") {
                        ForEach(collaborators.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                            Text("👤 \(c.name)").tag(LinkTarget.collaborator(c.persistentModelID))
                        }
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Annuler") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sauver") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(content: trimmed)
        context.insert(note)
        switch linkTarget {
        case .none: break
        case .project(let pid):
            if let p = projects.first(where: { $0.persistentModelID == pid }) {
                note.project = p
            }
        case .collaborator(let cid):
            if let c = collaborators.first(where: { $0.persistentModelID == cid }) {
                note.collaborator = c
            }
        }
        try? context.save()
        onDismiss()
    }
}
```

If `Note(content:)` is not the available init, run `grep -n "init" OneToOne/Models/Note.swift` and adapt — e.g. `Note(content: trimmed, project: nil, collaborator: nil)` or use property assignment after a no-arg init.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Menubar/QuickNotePopover.swift
git commit -m "feat(menubar): QuickNotePopover — capture standalone notes from menubar"
```

---

## Task 5: `UrgentActionPopover` view (U1c — action detail)

**Files:**
- Create: `OneToOne/Views/Menubar/UrgentActionPopover.swift`

- [ ] **Step 1: Create the view**

`OneToOne/Views/Menubar/UrgentActionPopover.swift`:

```swift
import SwiftUI
import SwiftData

/// Read-only popover with two write actions: complete the task or open the
/// source Meeting (if any). Edits remain in ActionsListView.
struct UrgentActionPopover: View {
    @Bindable var task: ActionTask
    let onComplete: () -> Void
    let onOpenMeeting: (Meeting) -> Void
    let onDismiss: () -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(.headline)

            HStack(spacing: 12) {
                if let project = task.project { Label(project.name, systemImage: "folder").font(.caption) }
                if let collab = task.collaborator { Label(collab.name, systemImage: "person.fill").font(.caption) }
                if let due = task.dueDate {
                    Label(Self.dateFmt.string(from: due), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(due < Date() ? .red : .secondary)
                }
            }
            .foregroundColor(.secondary)

            if !task.comments.isEmpty {
                Divider()
                Text("Commentaires").font(.caption.bold()).foregroundColor(.secondary)
                let recent = task.comments.sorted { $0.date > $1.date }.prefix(3)
                ForEach(Array(recent), id: \.persistentModelID) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Text(Self.dateFmt.string(from: c.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(c.text).font(.caption)
                    }
                }
            }

            Divider()
            HStack {
                Button("Terminer ✓") {
                    onComplete()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                Button("Ouvrir Meeting ↗") {
                    if let m = task.meeting { onOpenMeeting(m) }
                    onDismiss()
                }
                .disabled(task.meeting == nil)
                Spacer()
                Button("Fermer") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Menubar/UrgentActionPopover.swift
git commit -m "feat(menubar): UrgentActionPopover — read-only detail + complete / open meeting"
```

---

## Task 6: `SearchPopover` view (R1)

**Files:**
- Create: `OneToOne/Views/Menubar/SearchPopover.swift`

- [ ] **Step 1: Create the view**

`OneToOne/Views/Menubar/SearchPopover.swift`:

```swift
import SwiftUI
import SwiftData

/// Compact cross-entity search popover. Returns the chosen target via
/// `onSelectMeeting` / `onSelectCollaborator` / `onSelectProject`.
struct SearchPopover: View {
    let onSelectMeeting: (Meeting) -> Void
    let onSelectCollaborator: (Collaborator) -> Void
    let onSelectProject: (Project) -> Void
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var meetings: [Meeting] = []
    @State private var collaborators: [Collaborator] = []
    @State private var projects: [Project] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Rechercher…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }

            if debouncedQuery.isEmpty {
                ContentUnavailableView("Tapez pour rechercher",
                                       systemImage: "magnifyingglass",
                                       description: Text("Réunions · Collaborateurs · Projets"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !meetings.isEmpty {
                            section(title: "Réunions") {
                                ForEach(meetings) { m in
                                    row(label: rowLabelMeeting(m), icon: "person.3.fill") {
                                        onSelectMeeting(m); onDismiss()
                                    }
                                }
                            }
                        }
                        if !collaborators.isEmpty {
                            section(title: "Collaborateurs") {
                                ForEach(collaborators) { c in
                                    row(label: c.pinLevel >= 1 ? "⭐ \(c.name)" : c.name,
                                        icon: "person.fill") {
                                        onSelectCollaborator(c); onDismiss()
                                    }
                                }
                            }
                        }
                        if !projects.isEmpty {
                            section(title: "Projets") {
                                ForEach(projects) { p in
                                    row(label: p.name, icon: "folder.fill") {
                                        onSelectProject(p); onDismiss()
                                    }
                                }
                            }
                        }
                        if meetings.isEmpty && collaborators.isEmpty && projects.isEmpty {
                            Text("Aucun résultat").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(width: 440, height: 360)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundColor(.secondary)
            content()
        }
    }

    private func row(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundColor(.secondary)
                Text(label).font(.body)
                Spacer()
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowLabelMeeting(_ m: Meeting) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: m.date)) — \(m.title)"
    }

    private func scheduleSearch(_ raw: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled { await runSearch(raw) }
        }
    }

    @MainActor
    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debouncedQuery = q
        guard !q.isEmpty else {
            meetings = []; collaborators = []; projects = []; return
        }

        var meetingDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { $0.title.localizedStandardContains(q) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        meetingDescriptor.fetchLimit = 5
        meetings = (try? context.fetch(meetingDescriptor)) ?? []

        var collabDescriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate<Collaborator> { !$0.isArchived && $0.name.localizedStandardContains(q) }
        )
        collabDescriptor.fetchLimit = 20
        let rawCollabs = (try? context.fetch(collabDescriptor)) ?? []
        collaborators = rawCollabs
            .sorted { lhs, rhs in
                if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }

        var projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> {
                !$0.isArchived && ($0.name.localizedStandardContains(q) || $0.code.localizedStandardContains(q))
            },
            sortBy: [SortDescriptor(\.name)]
        )
        projectDescriptor.fetchLimit = 5
        projects = (try? context.fetch(projectDescriptor)) ?? []
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean. If a `#Predicate` line fails because `localizedStandardContains` isn't allowed in SwiftData predicates on your toolchain, fall back to `$0.name.contains(q)` (case-sensitive substring) — accept the regression for v1.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Menubar/SearchPopover.swift
git commit -m "feat(menubar): SearchPopover — cross-entity quick search"
```

---

## Task 7: Wire popovers + new menu items into `MenuBarController`

**Files:**
- Modify: `OneToOne/Services/MenuBarController.swift`

This is the integration task. Touches the menu builder, adds popover instances, and wires actions.

- [ ] **Step 1: Add popover ivars + show helpers**

In `MenuBarController`, just after the existing `cancellables` property, add:

```swift
    private lazy var quickActionPopover = makePopover()
    private lazy var quickNotePopover = makePopover()
    private lazy var urgentActionPopover = makePopover()
    private lazy var searchPopover = makePopover()
    private var urgentTaskForPopover: ActionTask?
    private var dbChangeObserver: NSObjectProtocol?

    private func makePopover() -> NSPopover {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        return p
    }

    private func show(_ popover: NSPopover, content: NSViewController) {
        popover.contentViewController = content
        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func hostingController<V: View>(_ view: V) -> NSViewController {
        guard let container = container else {
            return NSHostingController(rootView: AnyView(Text("Container unavailable")))
        }
        let host = NSHostingController(rootView:
            AnyView(view
                .environment(\.modelContext, container.mainContext)
            )
        )
        host.view.frame.size = NSSize(width: 360, height: 220)
        return host
    }
```

- [ ] **Step 2: Subscribe to DB change notifications inside `install(container:)`**

In `install(container:)`, after the existing `CalendarAgendaService` Combine sink, add:

```swift
        dbChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
```

And in `uninstall()`, before the existing cleanup, add:

```swift
        if let obs = dbChangeObserver { NotificationCenter.default.removeObserver(obs) }
        dbChangeObserver = nil
```

- [ ] **Step 3: Replace `buildMenu(settings:)` with the new sectioned version**

Locate `private func buildMenu(settings: AppSettings?) -> NSMenu` and replace it entirely with:

```swift
    private func buildMenu(settings: AppSettings?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // --- Header
        let header = NSMenuItem(title: dayHeader(Date()), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // --- Quick actions
        appendQuickActions(to: menu, settings: settings)
        menu.addItem(.separator())

        // --- Today section
        appendTodaySection(to: menu)
        menu.addItem(.separator())

        // --- Urgent actions
        appendUrgentSection(to: menu)

        // --- Search
        let searchItem = NSMenuItem(title: "🔍 Rechercher…",
                                    action: #selector(showSearch),
                                    keyEquivalent: "f")
        searchItem.target = self
        menu.addItem(searchItem)

        // --- Stats footer
        appendStatsFooter(to: menu)

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Ouvrir OneToOne",
                                  action: #selector(openMainWindow),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let quitItem = NSMenuItem(title: "Quitter",
                                  action: #selector(NSApp.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }
```

- [ ] **Step 4: Add the `appendQuickActions` method**

Insert this method into `MenuBarController` (next to `buildMenu`):

```swift
    private func appendQuickActions(to menu: NSMenu, settings: AppSettings?) {
        let newMeeting = NSMenuItem(title: "+  Nouvelle réunion",
                                    action: #selector(startAdHoc),
                                    keyEquivalent: "")
        newMeeting.target = self
        menu.addItem(newMeeting)

        // 1:1 submenu
        let one2one = NSMenuItem(title: "+  Démarrer 1:1", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let favorites = favoriteCollaborators()
        if favorites.isEmpty {
            let none = NSMenuItem(title: "(aucun favori — épinglez depuis Collaborateurs)",
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for c in favorites {
                let item = NSMenuItem(title: c.name,
                                      action: #selector(startOneToOneFromMenubar(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = c.ensuredStableID.uuidString
                sub.addItem(item)
            }
        }
        one2one.submenu = sub
        menu.addItem(one2one)

        // Manager
        let mgr = NSMenuItem(title: "+  1:1 Manager",
                             action: #selector(startManager),
                             keyEquivalent: "")
        mgr.target = self
        mgr.isEnabled = managerCollaborator(settings: settings) != nil
        if !mgr.isEnabled { mgr.toolTip = "Manager non configuré dans Préférences" }
        menu.addItem(mgr)

        // Action + Note (popovers)
        let action = NSMenuItem(title: "+  Nouvelle action",
                                action: #selector(showQuickAction),
                                keyEquivalent: "")
        action.target = self
        menu.addItem(action)

        let note = NSMenuItem(title: "+  Note rapide",
                              action: #selector(showQuickNote),
                              keyEquivalent: "")
        note.target = self
        menu.addItem(note)
    }
```

- [ ] **Step 5: Replace the existing Aujourd'hui block with `appendTodaySection`**

```swift
    private func appendTodaySection(to menu: NSMenu) {
        let events = CalendarAgendaService.shared.eventsToday
        let remaining = events.filter { $0.endDate > Date() && !$0.isCancelled }.count
        let header = NSMenuItem(
            title: "Aujourd'hui — \(remaining) restante(s)",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if events.isEmpty {
            let none = NSMenuItem(title: "(aucune réunion)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for event in events {
                menu.addItem(makeEventItem(event))
            }
        }
    }
```

(`makeEventItem` already exists from before — no change.)

- [ ] **Step 6: Add `appendUrgentSection` + `appendStatsFooter`**

```swift
    private func appendUrgentSection(to menu: NSMenu) {
        guard let container = container else { return }
        let urgent = UrgentActionsSelector.qualifying(in: container.mainContext)
        guard !urgent.isEmpty else { return }

        let header = NSMenuItem(title: "⚠  Actions urgentes (\(urgent.count))",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for task in urgent.prefix(3) {
            let item = NSMenuItem(title: urgentLabel(for: task),
                                  action: #selector(showUrgent(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = task.ensuredStableID.uuidString
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func urgentLabel(for task: ActionTask) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let truncate = max(10, (currentSettings()?.menubarMaxTitleChars ?? 25))
        let truncated = task.title.count > truncate
            ? String(task.title.prefix(truncate - 1)) + "…"
            : task.title

        let suffix: String
        if let due = task.dueDate {
            if due < startOfToday { suffix = "(échéance \(fmt.string(from: due)))" }
            else { suffix = "(aujourd'hui)" }
        } else {
            suffix = "(sans date)"
        }
        return "●  \(truncated) \(suffix)"
    }

    private func appendStatsFooter(to menu: NSMenu) {
        guard let container = container else { return }
        let stats = TodayStatsCalculator.compute(in: container.mainContext)
        let hasTime = stats.tempsPasseSeconds > 0
        let hasNoProj = stats.sansProjet > 0
        guard hasTime || hasNoProj else { return }

        menu.addItem(.separator())
        let line: String
        let h = Int(stats.tempsPasseSeconds) / 3600
        let m = (Int(stats.tempsPasseSeconds) % 3600) / 60
        let timeStr = h > 0 ? "\(h)h\(String(format: "%02d", m)) passées" : "\(m) min passées"
        if hasTime && hasNoProj {
            line = "\(timeStr) · \(stats.sansProjet) sans projet"
        } else if hasTime {
            line = timeStr
        } else {
            line = "Pas encore de réunion terminée · \(stats.sansProjet) sans projet"
        }
        let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
```

- [ ] **Step 7: Add the action selectors + helpers**

```swift
    @objc private func startAdHoc() {
        guard let container = container else { return }
        QuickLaunchRouter.shared.startAdHocMeeting(in: container.mainContext)
    }

    @objc private func startOneToOneFromMenubar(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let uuid = UUID(uuidString: raw),
              let container = container else { return }
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        if let collab = (try? container.mainContext.fetch(descriptor))?.first {
            QuickLaunchRouter.shared.startOneToOne(
                collaborator: collab,
                autoStartRecording: true,
                in: container.mainContext
            )
        }
    }

    @objc private func startManager() {
        guard let container = container,
              let collab = managerCollaborator(settings: currentSettings()) else { return }
        QuickLaunchRouter.shared.startManagerMeeting(collaborator: collab, in: container.mainContext)
    }

    @objc private func showQuickAction() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(QuickActionPopover { [weak self] in
            self?.quickActionPopover.performClose(nil)
        })
        show(quickActionPopover, content: host)
    }

    @objc private func showQuickNote() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(QuickNotePopover { [weak self] in
            self?.quickNotePopover.performClose(nil)
        })
        show(quickNotePopover, content: host)
    }

    @objc private func showSearch() {
        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(SearchPopover(
            onSelectMeeting: { [weak self] meeting in self?.openMeeting(meeting) },
            onSelectCollaborator: { _ in /* future: deep-link to CollaboratorDetail */ },
            onSelectProject: { _ in /* future: deep-link to ProjectDetail */ },
            onDismiss: { [weak self] in self?.searchPopover.performClose(nil) }
        ))
        show(searchPopover, content: host)
    }

    @objc private func showUrgent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let uuid = UUID(uuidString: raw),
              let container = container else { return }
        let descriptor = FetchDescriptor<ActionTask>()
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        guard let task = all.first(where: { $0.ensuredStableID == uuid }) else { return }
        urgentTaskForPopover = task

        NSApp.activate(ignoringOtherApps: true)
        let host = hostingController(UrgentActionPopover(
            task: task,
            onComplete: { [weak self] in
                task.isCompleted = true
                task.completedAt = Date()
                try? self?.container?.mainContext.save()
            },
            onOpenMeeting: { [weak self] meeting in self?.openMeeting(meeting) },
            onDismiss: { [weak self] in self?.urgentActionPopover.performClose(nil) }
        ))
        show(urgentActionPopover, content: host)
    }

    private func openMeeting(_ meeting: Meeting) {
        NSApp.activate(ignoringOtherApps: true)
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: false
        )
    }

    private func favoriteCollaborators() -> [Collaborator] {
        guard let container = container else { return [] }
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { !$0.isArchived && $0.pinLevel >= 1 }
        )
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        return all.sorted { lhs, rhs in
            if lhs.pinLevel != rhs.pinLevel { return lhs.pinLevel > rhs.pinLevel }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func managerCollaborator(settings: AppSettings?) -> Collaborator? {
        guard let email = settings?.managerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty,
              let container = container else { return nil }
        let needle = email.lowercased()
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        return all.first { $0.email.lowercased() == needle }
    }
```

- [ ] **Step 8: Update the badge logic in `refresh()` / `statusTitle(for:settings:)`**

Locate `statusTitle(for:settings:)` and add the badge suffix. Replace the function's body's final `return "..."` lines so they all funnel through:

```swift
        let baseTitle: String
        // ... existing logic computing baseTitle (rename the previous local "title") ...
        return baseTitle + badgeSuffix()
```

Easier: append the badge at the end of `refresh()` itself. Replace the line `item.button?.title = statusTitle(for: upcoming, settings: settings)` with:

```swift
        let base = statusTitle(for: upcoming, settings: settings)
        item.button?.title = base + badgeSuffix()
```

And add the helper:

```swift
    private func badgeSuffix() -> String {
        guard let container = container else { return "" }
        let urgent = UrgentActionsSelector.qualifying(in: container.mainContext)
        let hasOverdue = urgent.contains { task in
            guard let due = task.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
        return MenubarBadgeText.suffix(urgentCount: urgent.count, hasOverdue: hasOverdue)
    }
```

- [ ] **Step 9: Build + run tests**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

Run: `swift test --filter MenuBarStatsTests 2>&1 | tail -10`
Expected: 6 tests still pass.

- [ ] **Step 10: Commit**

```bash
git add OneToOne/Services/MenuBarController.swift
git commit -m "feat(menubar): wire quick actions, urgent section, search, stats footer + badge"
```

---

## Task 8: Manual verification

**Files:** none.

- [ ] **Step 1: Launch the app and exercise every entry**

```bash
swift run 2>&1 | head -20
```

Then click the menubar icon and walk the checklist:

| # | Check |
|---|-------|
| 1 | Header shows "Aujourd'hui · <today>" |
| 2 | "Nouvelle réunion" → opens a meeting window with recording on |
| 3 | "Démarrer 1:1" submenu lists only favourite/pinned collabs |
| 4 | Clicking a 1:1 favourite opens the meeting window with that collab |
| 5 | "1:1 Manager" disabled when settings.managerEmail empty; enabled otherwise; click creates `kind=.manager` |
| 6 | "Nouvelle action" → popover; Créer → ActionTask appears in ActionsListView |
| 7 | "Note rapide" → popover; Sauver → Note appears in AllNotesView |
| 8 | Aujourd'hui counter matches remaining events |
| 9 | Actions urgentes shows ≤ 3 rows; click opens UrgentActionPopover; Terminer marks task done and refreshes menu |
| 10 | Rechercher… → popover; type "iPMI" → results split into Réunions/Collaborateurs/Projets |
| 11 | Stats footer matches manual sum of today's past meetings; "N sans projet" matches a manual count |
| 12 | Icon shows ` ●N` suffix when ≥ 1 urgent action; updates within ~1 s of completing one in the app |

- [ ] **Step 2: Note defects**

For each failure, file a small follow-up commit. Don't bundle them with this plan's commits unless the failure is a direct regression from these tasks.

---

## Out-of-scope notes

- Inline editing inside UrgentActionPopover — deliberately read-only per spec §10.
- "Demain" / "Cette semaine" submenus — rejected in brainstorming (D1/D2).
- Top-level Projects submenu — rejected (R2).
- Image/attachment drop into QuickNotePopover — text only for v1.

---

## Self-review notes (author)

- **Spec coverage**: §2 layout → tasks 7 builds it; §3 quick actions → tasks 2/3/4/7; §4 today counter → task 7 step 5; §5 urgent → tasks 1 + 5 + 7; §6 search → task 6; §7 stats → tasks 1 + 7 step 6; §8 refresh triggers → task 7 step 2; §10 edge cases addressed in task 7 (managerCollaborator nil guard, empty favourites disabled state, container nil guards); §12 testing covered by MenuBarStatsTests + Task 8 manual checklist.
- **No placeholders**: every step shows the actual code. The one conditional in Task 4 step 2 (Note init signature) instructs the implementer to verify a specific grep and adapt — concrete and bounded.
- **Type consistency**: `UrgentActionsSelector.qualifying(in:now:)`, `TodayStatsCalculator.compute(in:now:)`, `MenubarBadgeText.suffix(urgentCount:hasOverdue:)`, `QuickLaunchRouter.startAdHocMeeting(in:)` / `startManagerMeeting(collaborator:in:)`, and the four popovers' constructors are referenced identically across Task 1, 2 and 7.
