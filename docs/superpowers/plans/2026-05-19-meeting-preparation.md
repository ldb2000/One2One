# Meeting preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow preparing a meeting via markdown checkboxes attached either to a Collaborator (1:1/manager) or a Project ("standing prep"), with auto-drain into the upcoming Meeting and auto-carryover of unchecked items back to the pool after the meeting.

**Architecture:** Add `standingPrepNotes` on `Collaborator` and `Project` as the persistent pool; add `prepNotes` + `prepCarryoverDone` on `Meeting` as in-flight snapshot. New `PrepCarryoverService` handles bidirectional flow (drain at meeting open, carryover at transcription end). New SwiftUI surfaces: MeetingView tab `.preparation`, sections in `CollaboratorDetailView` / `ProjectDetailView`, menubar submenu "Préparer…", standalone `PrepWindow`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation (transcribed elsewhere), XCTest, AppKit (NSMenu for menubar).

---

## File map

| Path | Responsibility |
|---|---|
| `OneToOne/Models/OtherModels.swift` (modify) | `Collaborator.standingPrepNotes/UpdatedAt`, `Meeting.prepNotes/prepGeneratedAt/prepCarryoverDone` |
| `OneToOne/Models/Project.swift` (modify) | `Project.standingPrepNotes/UpdatedAt` |
| `OneToOne/Models/AppSettings.swift` (modify) | `prepAutoCarryover: Bool = true` |
| `OneToOne/Services/PrepCarryoverService.swift` (new) | Pure helpers + drain/carryover routines |
| `OneToOne/Services/AIReportService.swift` (extend) | `generatePrep(collab:project:meeting:settings:)` |
| `OneToOne/Views/MeetingView.swift` (modify) | Add `.preparation` to `MeetingSection`, wire tab, badge, drain trigger |
| `OneToOne/Views/MeetingPrepTab.swift` (new) | Split editor + context panel |
| `OneToOne/Views/MeetingPrepContextPanel.swift` (new) | Actions / past meetings / alerts |
| `OneToOne/Views/DetailsViews.swift` (modify) | Section "Préparation" in `CollaboratorDetailView` and `ProjectDetailView` |
| `OneToOne/Views/PrepWindow.swift` (new) | Standalone window for menubar entry |
| `OneToOne/Views/CalendarMeetingPicker.swift` (new) | Sheet to pick future meeting for global/work |
| `OneToOne/Services/MenuBarController.swift` (modify) | Submenu "Préparer…" |
| `OneToOne/OneToOneApp.swift` (modify) | New `WindowGroup` for `PrepWindow` + token type |
| `Tests/PrepCarryoverServiceTests.swift` (new) | Unit tests for extraction, drain, carryover |

Total: 4 new files, 7 modifications.

---

### Task 1: Model extensions — Collaborator / Project / Meeting / AppSettings

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift`
- Modify: `OneToOne/Models/Project.swift`
- Modify: `OneToOne/Models/AppSettings.swift`

- [ ] **Step 1: Add fields to Collaborator**

In `OneToOne/Models/OtherModels.swift`, locate the `@Model final class Collaborator` block (around line 25). Add inside the class body, near other simple properties:
```swift
/// Notes de préparation persistantes pour la prochaine 1:1 / manager.
/// Drainées dans `Meeting.prepNotes` à la création d'une meeting 1:1/manager
/// avec ce collab ; repeuplées au carryover des items non cochés post-meeting.
var standingPrepNotes: String = ""
var standingPrepUpdatedAt: Date?
```

- [ ] **Step 2: Add fields to Meeting**

In the same file, locate `@Model final class Meeting` (around line 248). Add inside the class body:
```swift
/// Snapshot in-flight de la préparation pour cette meeting précise.
/// Pour les kinds .oneToOne/.manager/.project, alimenté par drain depuis
/// le pool standing du collab/projet. Pour .global/.work, édité directement.
var prepNotes: String = ""
var prepGeneratedAt: Date?
/// Flag à double usage (idempotence) : true = drain initial OU carryover
/// post-meeting déjà effectué.
var prepCarryoverDone: Bool = false
```

- [ ] **Step 3: Add fields to Project**

In `OneToOne/Models/Project.swift`, locate `@Model final class Project`. Add:
```swift
/// Notes de préparation persistantes pour la prochaine réunion projet.
var standingPrepNotes: String = ""
var standingPrepUpdatedAt: Date?
```

- [ ] **Step 4: Add setting**

In `OneToOne/Models/AppSettings.swift`, locate the block near other notification toggles. Add at the end of the `AppSettings` class:
```swift
/// Active le carryover automatique des items non cochés vers le pool
/// standing (collab ou projet) à la fin d'une meeting.
var prepAutoCarryover: Bool = true
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

SwiftData lightweight migration applies automatically for new fields with defaults — no migration plan changes.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Models/OtherModels.swift OneToOne/Models/Project.swift OneToOne/Models/AppSettings.swift
git commit -m "feat(prep): model fields for standing + in-flight prep"
```

---

### Task 2: PrepCarryoverService — extractUncheckedItems()

**Files:**
- Create: `OneToOne/Services/PrepCarryoverService.swift`
- Create: `Tests/PrepCarryoverServiceTests.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/PrepCarryoverServiceTests.swift`:
```swift
import XCTest
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PrepCarryoverServiceTests/test_extractUncheckedItems 2>&1 | tail -10`
Expected: FAIL `cannot find 'PrepCarryoverService' in scope`.

- [ ] **Step 3: Create the service file**

In `OneToOne/Services/PrepCarryoverService.swift`:
```swift
import Foundation
import SwiftData
import os

private let prepLog = Logger(subsystem: "com.onetoone.app", category: "prep-carryover")

/// Bidirectional flow between meeting-attached `prepNotes` and the standing
/// pool (`Collaborator.standingPrepNotes` or `Project.standingPrepNotes`).
///
/// - `drainStandingIntoMeeting(_:in:)` — at meeting creation / 1st prep tab open:
///   moves the pool content into `meeting.prepNotes` and clears the pool.
/// - `carryoverUncheckedFromMeeting(_:settings:in:)` — at transcription end:
///   pushes unchecked `[ ]` items from `meeting.prepNotes` back to the pool.
///
/// Both operations are idempotent via `meeting.prepCarryoverDone`.
enum PrepCarryoverService {

    /// Extracts lines matching `- [ ] ...` (with optional leading whitespace).
    /// Used by carryover. Preserves indentation and original text.
    static func extractUncheckedItems(from md: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\s*)- \[ \] (.+)$"#,
            options: [.anchorsMatchLines]
        ) else { return [] }
        let ns = md as NSString
        let matches = regex.matches(in: md, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PrepCarryoverServiceTests/test_extractUncheckedItems 2>&1 | tail -10`
Expected: PASS 2/2.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/PrepCarryoverService.swift Tests/PrepCarryoverServiceTests.swift
git commit -m "feat(prep): PrepCarryoverService.extractUncheckedItems"
```

---

### Task 3: PrepCarryoverService — drainStandingIntoMeeting()

**Files:**
- Modify: `OneToOne/Services/PrepCarryoverService.swift`
- Modify: `Tests/PrepCarryoverServiceTests.swift`

- [ ] **Step 1: Append failing tests**

Insert just before the closing `}` of `PrepCarryoverServiceTests`:
```swift

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
```

Add `import SwiftData` at the top of `Tests/PrepCarryoverServiceTests.swift`.

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter PrepCarryoverServiceTests/test_drain 2>&1 | tail -10`
Expected: FAIL `static member 'drainStandingIntoMeeting' …`.

- [ ] **Step 3: Implement drain**

Append to `OneToOne/Services/PrepCarryoverService.swift`:
```swift

extension PrepCarryoverService {

    /// Drains the standing pool of the relevant collab/project into the
    /// meeting's `prepNotes` and clears the pool. Idempotent via
    /// `meeting.prepCarryoverDone`.
    /// - For `.global` / `.work`: no pool exists; sets the flag and returns.
    @MainActor
    static func drainStandingIntoMeeting(_ meeting: Meeting, in context: ModelContext) {
        guard !meeting.prepCarryoverDone else { return }

        switch meeting.kind {
        case .oneToOne, .manager:
            if let collab = meeting.participants.first, !collab.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(
                    standing: collab.standingPrepNotes,
                    existing: meeting.prepNotes
                )
                collab.standingPrepNotes = ""
                collab.standingPrepUpdatedAt = Date()
            }
        case .project:
            if let project = meeting.project, !project.standingPrepNotes.isEmpty {
                meeting.prepNotes = mergePrep(
                    standing: project.standingPrepNotes,
                    existing: meeting.prepNotes
                )
                project.standingPrepNotes = ""
                project.standingPrepUpdatedAt = Date()
            }
        case .global, .work:
            break
        }

        meeting.prepCarryoverDone = true
        try? context.save()
        prepLog.info("drain done kind=\(meeting.kind.rawValue, privacy: .public) bytes=\(meeting.prepNotes.count)")
    }

    private static func mergePrep(standing: String, existing: String) -> String {
        if existing.isEmpty { return standing }
        return standing + "\n\n" + existing
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PrepCarryoverServiceTests/test_drain 2>&1 | tail -10`
Expected: PASS 4/4.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/PrepCarryoverService.swift Tests/PrepCarryoverServiceTests.swift
git commit -m "feat(prep): drainStandingIntoMeeting + tests"
```

---

### Task 4: PrepCarryoverService — carryoverUncheckedFromMeeting()

**Files:**
- Modify: `OneToOne/Services/PrepCarryoverService.swift`
- Modify: `Tests/PrepCarryoverServiceTests.swift`

- [ ] **Step 1: Append failing tests**

Insert before the `MARK: - Fixtures` section:
```swift

    @MainActor
    func test_carryover_oneToOne_pushesUncheckedToCollabPool() throws {
        let (ctx, collab, meeting) = try makeOneToOneFixture()
        meeting.prepNotes = """
        - [ ] Not done
        - [x] Done
        - [ ] Also not done
        """
        meeting.prepCarryoverDone = false  // simulate a fresh meeting after re-edit
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
```

- [ ] **Step 2: Confirm RED**

Run: `swift test --filter PrepCarryoverServiceTests/test_carryover 2>&1 | tail -10`
Expected: FAIL `static member 'carryoverUncheckedFromMeeting'`.

- [ ] **Step 3: Implement carryover**

Append to `OneToOne/Services/PrepCarryoverService.swift`:
```swift

extension PrepCarryoverService {

    /// At meeting end (transcription finished or manual close): extract unchecked
    /// `[ ]` items from `meeting.prepNotes` and prepend them to the relevant
    /// standing pool (`collab` for .oneToOne/.manager, `project` for .project).
    /// Idempotent via `meeting.prepCarryoverDone`.
    @MainActor
    static func carryoverUncheckedFromMeeting(
        _ meeting: Meeting,
        settings: AppSettings,
        in context: ModelContext
    ) {
        guard settings.prepAutoCarryover else { return }
        guard !meeting.prepCarryoverDone else { return }

        let unchecked = extractUncheckedItems(from: meeting.prepNotes)
        guard !unchecked.isEmpty else {
            meeting.prepCarryoverDone = true
            try? context.save()
            return
        }

        let block = "<!-- reporté de la réunion \(formatCarryDate(meeting.date)) -->\n"
            + unchecked.joined(separator: "\n")
            + "\n\n"

        switch meeting.kind {
        case .oneToOne, .manager:
            if let collab = meeting.participants.first {
                collab.standingPrepNotes = block + collab.standingPrepNotes
                collab.standingPrepUpdatedAt = Date()
            }
        case .project:
            if let project = meeting.project {
                project.standingPrepNotes = block + project.standingPrepNotes
                project.standingPrepUpdatedAt = Date()
            }
        case .global, .work:
            break  // pool absent — items perdus (cf. spec, intentionnel)
        }

        meeting.prepCarryoverDone = true
        try? context.save()
        prepLog.info("carryover done count=\(unchecked.count) kind=\(meeting.kind.rawValue, privacy: .public)")
    }

    private static func formatCarryDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PrepCarryoverServiceTests 2>&1 | tail -10`
Expected: PASS 7/7 (the original 2 + drain 4 + carryover 3 = 9 total; if XCTest reports a different total because of fixture-only methods, accept the actual count).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/PrepCarryoverService.swift Tests/PrepCarryoverServiceTests.swift
git commit -m "feat(prep): carryoverUncheckedFromMeeting + tests"
```

---

### Task 5: Add `.preparation` to MeetingSection + tab visibility

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Extend the enum**

Locate (around line 143):
```swift
    enum MeetingSection: String, CaseIterable, Identifiable {
        case liveNotes = "Notes live"
        case transcript = "Transcription"
        case report = "Rapport"
        case documents = "Documents"
```
Replace with:
```swift
    enum MeetingSection: String, CaseIterable, Identifiable {
        case preparation = "Préparation"
        case liveNotes = "Notes live"
        case transcript = "Transcription"
        case report = "Rapport"
        case documents = "Documents"
```

(Adding the case at the start of `allCases` so it appears first in the tab bar.)

- [ ] **Step 2: Add `.preparation` to sectionContent switch**

In `MeetingView.swift`, locate `sectionContent` switch (around line 432-445). It currently has cases `.liveNotes`, `.transcript`, `.report`, `.documents`. Add a NEW case at the top:
```swift
case .preparation:
    MeetingPrepTab(meeting: meeting)
        .onAppear {
            PrepCarryoverService.drainStandingIntoMeeting(meeting, in: context)
        }
```

- [ ] **Step 3: Build (RED for now — `MeetingPrepTab` not yet defined)**

Run: `swift build 2>&1 | tail -5`
Expected: error `cannot find 'MeetingPrepTab' in scope`. This is expected — Task 6 creates the view.

- [ ] **Step 4: Stub MeetingPrepTab quickly so the build passes**

Create `OneToOne/Views/MeetingPrepTab.swift` with a placeholder:
```swift
import SwiftUI

struct MeetingPrepTab: View {
    let meeting: Meeting
    var body: some View {
        Text("Préparation — placeholder (Task 6)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/MeetingPrepTab.swift
git commit -m "feat(prep): add .preparation tab + drain trigger (stub view)"
```

---

### Task 6: MeetingPrepTab — editor + Generate button

**Files:**
- Modify: `OneToOne/Views/MeetingPrepTab.swift`

- [ ] **Step 1: Replace placeholder with real implementation**

Overwrite `OneToOne/Views/MeetingPrepTab.swift`:
```swift
import SwiftUI
import SwiftData

/// Tab "Préparation" d'une réunion. Split 60/40 entre l'éditeur markdown et
/// le panneau contexte. Bouton "Générer brouillon" en bas.
struct MeetingPrepTab: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @State private var showOverwriteConfirm = false
    @State private var isGenerating = false
    @State private var generationError: String?

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        HStack(spacing: 0) {
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            MeetingPrepContextPanel(meeting: meeting)
                .frame(width: 320)
        }
        .alert("Remplacer la préparation actuelle ?", isPresented: $showOverwriteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Remplacer", role: .destructive) { Task { await runGenerate(force: true) } }
        } message: {
            Text("Le brouillon IA va écraser le contenu actuel.")
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        VStack(spacing: 0) {
            MarkdownEditorView(
                text: Binding(
                    get: { meeting.prepNotes },
                    set: { meeting.prepNotes = $0; saveCtx() }
                ),
                textViewID: "meetingPrep.\(meeting.persistentModelID.hashValue)"
            )
            if let err = generationError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            HStack {
                Spacer()
                Button {
                    if meeting.prepNotes.isEmpty {
                        Task { await runGenerate(force: false) }
                    } else {
                        showOverwriteConfirm = true
                    }
                } label: {
                    Label(isGenerating ? "Génère…" : "Générer brouillon IA",
                          systemImage: "wand.and.stars")
                }
                .disabled(isGenerating)
            }
            .padding(8)
        }
    }

    @MainActor
    private func runGenerate(force: Bool) async {
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            let md = try await AIReportService.generatePrep(
                collab: (meeting.kind == .oneToOne || meeting.kind == .manager)
                    ? meeting.participants.first : nil,
                project: meeting.kind == .project ? meeting.project : nil,
                meeting: meeting,
                in: context,
                settings: settings
            )
            meeting.prepNotes = md
            meeting.prepGeneratedAt = Date()
            saveCtx()
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func saveCtx() {
        try? context.save()
    }
}
```

- [ ] **Step 2: Build (RED — `generatePrep` not yet defined, `MeetingPrepContextPanel` not yet defined)**

Run: `swift build 2>&1 | tail -8`
Expected: compile errors for `generatePrep` and `MeetingPrepContextPanel`. Tasks 7 + 8 cover these.

- [ ] **Step 3: Stub `generatePrep` and `MeetingPrepContextPanel` so build passes**

Append to `OneToOne/Services/AIReportService.swift`:
```swift
extension AIReportService {
    /// Génère un brouillon de préparation. Implémentation complète au Task 7.
    @MainActor
    static func generatePrep(
        collab: Collaborator?,
        project: Project?,
        meeting: Meeting?,
        in context: ModelContext,
        settings: AppSettings
    ) async throws -> String {
        return "## Points à aborder\n- [ ] (brouillon vide — implémentation Task 7)\n"
    }
}
```

Create `OneToOne/Views/MeetingPrepContextPanel.swift`:
```swift
import SwiftUI

struct MeetingPrepContextPanel: View {
    let meeting: Meeting
    var body: some View {
        Text("Contexte — placeholder (Task 8)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/MeetingPrepTab.swift OneToOne/Services/AIReportService.swift OneToOne/Views/MeetingPrepContextPanel.swift
git commit -m "feat(prep): MeetingPrepTab editor + Generate button (stub services)"
```

---

### Task 7: AIReportService.generatePrep — real implementation

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Replace the stub with the real implementation**

In `OneToOne/Services/AIReportService.swift`, find the existing `generatePrep` extension from Task 6 and REPLACE the whole `extension AIReportService { … generatePrep(…) … }` block with:
```swift
extension AIReportService {

    /// Génère un brouillon de préparation en markdown depuis l'historique des
    /// 3 dernières meetings, les actions ouvertes et alertes. Sortie = markdown
    /// avec sections `## Points à aborder` / `## Questions à poser` / etc., chaque
    /// item étant une checkbox `- [ ] ...`.
    @MainActor
    static func generatePrep(
        collab: Collaborator?,
        project: Project?,
        meeting: Meeting?,
        in context: ModelContext,
        settings: AppSettings
    ) async throws -> String {
        var ctxLines: [String] = []

        if let m = meeting {
            ctxLines.append("Réunion : \(m.title)")
            if let start = m.scheduledStart {
                let df = DateFormatter()
                df.locale = Locale(identifier: "fr_FR")
                df.dateFormat = "d MMM yyyy HH:mm"
                ctxLines.append("Date : \(df.string(from: start))")
            }
        }
        if let c = collab {
            ctxLines.append("Participant : \(c.name)\(c.role.isEmpty ? "" : " (\(c.role))")")
        }
        if let p = project {
            ctxLines.append("Projet : \(p.name) (\(p.code))")
        }

        // Historique : 3 dernières meetings du couple/projet, résumé court
        var historyBlock = ""
        if let c = collab {
            let collabID = c.persistentModelID
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { m in
                    m.participants.contains(where: { $0.persistentModelID == collabID })
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let past = ((try? context.fetch(descriptor)) ?? []).prefix(3)
            historyBlock = past.map { m -> String in
                let f = DateFormatter()
                f.locale = Locale(identifier: "fr_FR")
                f.dateFormat = "d MMM"
                let when = f.string(from: m.date)
                let snippet = String(m.summary.prefix(200))
                return "- \(when) — \(m.title) : \(snippet)"
            }.joined(separator: "\n")
        } else if let p = project {
            let projectID = p.persistentModelID
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { m in
                    m.project?.persistentModelID == projectID
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let past = ((try? context.fetch(descriptor)) ?? []).prefix(3)
            historyBlock = past.map { m -> String in
                let f = DateFormatter()
                f.locale = Locale(identifier: "fr_FR")
                f.dateFormat = "d MMM"
                let when = f.string(from: m.date)
                let snippet = String(m.summary.prefix(200))
                return "- \(when) — \(m.title) : \(snippet)"
            }.joined(separator: "\n")
        }

        // Actions ouvertes
        var actionsBlock = ""
        if let c = collab {
            let collabID = c.persistentModelID
            let desc = FetchDescriptor<ActionTask>(
                predicate: #Predicate { t in
                    !t.isCompleted && t.collaborator?.persistentModelID == collabID
                }
            )
            let open = ((try? context.fetch(desc)) ?? []).prefix(8)
            actionsBlock = open.map { "- \($0.title)" }.joined(separator: "\n")
        } else if let p = project {
            let projectID = p.persistentModelID
            let desc = FetchDescriptor<ActionTask>(
                predicate: #Predicate { t in
                    !t.isCompleted && t.project?.persistentModelID == projectID
                }
            )
            let open = ((try? context.fetch(desc)) ?? []).prefix(8)
            actionsBlock = open.map { "- \($0.title)" }.joined(separator: "\n")
        }

        // Alertes
        var alertsBlock = ""
        if let p = project {
            let projectID = p.persistentModelID
            let desc = FetchDescriptor<ProjectAlert>(
                predicate: #Predicate { $0.project?.persistentModelID == projectID }
            )
            let alerts = ((try? context.fetch(desc)) ?? [])
                .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
                .prefix(5)
            alertsBlock = alerts.map { "- [\($0.severity)] \($0.title)" }.joined(separator: "\n")
        }

        let prompt = """
        Tu prépares la réunion ci-dessous. Produis une PRÉPARATION en markdown
        organisée en sections (omets celles vides) :
          ## Points à aborder
          ## Questions à poser
          ## Décisions à obtenir
          ## Infos à partager
        Chaque item = puce checkbox `- [ ] ...`. Reste concis, factuel.

        Contexte :
        \(ctxLines.joined(separator: "\n"))

        Historique récent :
        \(historyBlock.isEmpty ? "(aucun)" : historyBlock)

        Actions ouvertes :
        \(actionsBlock.isEmpty ? "(aucune)" : actionsBlock)

        Alertes en cours :
        \(alertsBlock.isEmpty ? "(aucune)" : alertsBlock)

        Ne réécris pas les actions ouvertes verbatim ; sélectionne celles qui
        méritent une discussion. N'invente rien.
        """

        let raw = try await AIClient.send(prompt: prompt, settings: settings)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(prep): generatePrep — real implementation"
```

---

### Task 8: MeetingPrepContextPanel — real implementation

**Files:**
- Modify: `OneToOne/Views/MeetingPrepContextPanel.swift`

- [ ] **Step 1: Replace stub with real panel**

Overwrite `OneToOne/Views/MeetingPrepContextPanel.swift`:
```swift
import SwiftUI
import SwiftData

/// Panneau latéral droit du tab Préparation. Affiche actions ouvertes,
/// dernières meetings, alertes — toutes scoped au collab/projet de la meeting.
struct MeetingPrepContextPanel: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var context
    @State private var openActions: [ActionTask] = []
    @State private var pastMeetings: [Meeting] = []
    @State private var alerts: [ProjectAlert] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Actions ouvertes", icon: "checklist") {
                    if openActions.isEmpty {
                        Text("(aucune)").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(openActions, id: \.persistentModelID) { a in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle").font(.caption2).foregroundStyle(.tertiary)
                                Text(a.title).font(.caption).lineLimit(2)
                            }
                            .contentShape(Rectangle())
                            .help("Cliquer pour copier dans l'éditeur")
                            .onDrag {
                                NSItemProvider(object: "- [ ] \(a.title)\n" as NSString)
                            }
                        }
                    }
                }

                section("Derniers points", icon: "clock.arrow.circlepath") {
                    if pastMeetings.isEmpty {
                        Text("(aucun)").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(pastMeetings, id: \.persistentModelID) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(formatDate(m.date)) — \(m.title)")
                                    .font(.caption.bold())
                                Text(String(m.summary.prefix(140)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                section("Alertes", icon: "exclamationmark.triangle") {
                    if alerts.isEmpty {
                        Text("(aucune)").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(alerts, id: \.persistentModelID) { al in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(al.severity == "Critique" ? .red : .orange)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(al.title).font(.caption).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task { await loadContext() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, icon: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            }
            content()
        }
    }

    @MainActor
    private func loadContext() async {
        // Actions
        if let c = meeting.participants.first, meeting.kind == .oneToOne || meeting.kind == .manager {
            let cid = c.persistentModelID
            let d = FetchDescriptor<ActionTask>(
                predicate: #Predicate { !$0.isCompleted && $0.collaborator?.persistentModelID == cid }
            )
            openActions = Array(((try? context.fetch(d)) ?? []).prefix(8))
        } else if let p = meeting.project, meeting.kind == .project {
            let pid = p.persistentModelID
            let d = FetchDescriptor<ActionTask>(
                predicate: #Predicate { !$0.isCompleted && $0.project?.persistentModelID == pid }
            )
            openActions = Array(((try? context.fetch(d)) ?? []).prefix(8))
        }

        // Past meetings (excluding self)
        let selfID = meeting.persistentModelID
        if let c = meeting.participants.first, meeting.kind == .oneToOne || meeting.kind == .manager {
            let cid = c.persistentModelID
            let d = FetchDescriptor<Meeting>(
                predicate: #Predicate { m in
                    m.persistentModelID != selfID &&
                    m.participants.contains(where: { $0.persistentModelID == cid })
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            pastMeetings = Array(((try? context.fetch(d)) ?? []).prefix(3))
        } else if let p = meeting.project, meeting.kind == .project {
            let pid = p.persistentModelID
            let d = FetchDescriptor<Meeting>(
                predicate: #Predicate { m in
                    m.persistentModelID != selfID &&
                    m.project?.persistentModelID == pid
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            pastMeetings = Array(((try? context.fetch(d)) ?? []).prefix(3))
        }

        // Alerts
        if let p = meeting.project {
            let pid = p.persistentModelID
            let d = FetchDescriptor<ProjectAlert>(
                predicate: #Predicate { $0.project?.persistentModelID == pid }
            )
            alerts = ((try? context.fetch(d)) ?? [])
                .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
                .prefix(5)
                .map { $0 }
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/MeetingPrepContextPanel.swift
git commit -m "feat(prep): MeetingPrepContextPanel real impl (actions/history/alerts)"
```

---

### Task 9: Hook carryover at transcription end

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Locate transcription success branch**

In `MeetingView.swift`, find the `retranscribe(wavURL:)` function. Inside its `onProgress` / success path, locate the block where the transcription finishes successfully (look for `meeting.rawTranscript = result.text` or similar — there should be a `await MainActor.run { … }` block after `transcribeWithDiarization` returns).

- [ ] **Step 2: Insert carryover call after the rawTranscript assignment**

Inside that `MainActor.run` success block, after the line that assigns `meeting.rawTranscript = result.text`, append:
```swift
PrepCarryoverService.carryoverUncheckedFromMeeting(
    self.meeting,
    settings: self.settings,
    in: self.context
)
```

(If `self.settings` is not in scope, replace with the local `settings` variable used elsewhere — verify by reading nearby code.)

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(prep): carryover unchecked items at transcription end"
```

---

### Task 10: Badge "À préparer" in MeetingView header

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Add helper for badge state**

In `MeetingView`, find a logical location for a computed property (near other helpers like `canEditAudio`). Add:
```swift
/// État de préparation pour le badge affiché dans l'en-tête.
private enum PrepBadge { case none, toPrepare, prepared }

private var prepBadgeState: PrepBadge {
    let standingNonEmpty: Bool = {
        switch meeting.kind {
        case .oneToOne, .manager:
            return !(meeting.participants.first?.standingPrepNotes.isEmpty ?? true)
        case .project:
            return !(meeting.project?.standingPrepNotes.isEmpty ?? true)
        case .global, .work:
            return false
        }
    }()
    let isFuture = (meeting.scheduledStart ?? meeting.date) > Date()
    let hasContent = !meeting.prepNotes.isEmpty || standingNonEmpty
    if isFuture && !hasContent { return .toPrepare }
    if hasContent { return .prepared }
    return .none
}
```

- [ ] **Step 2: Render the badge in the meeting header**

In `MeetingView.swift`, find where the meeting title is displayed in the top chrome / header block (search for `meeting.title` or `MeetingTopChromeBar`). Locate the `HStack` that contains the title text. Just after the title `Text(meeting.title)`, add:
```swift
prepBadgeView
```

Then add this `@ViewBuilder` near other view helpers:
```swift
@ViewBuilder
private var prepBadgeView: some View {
    switch prepBadgeState {
    case .toPrepare:
        Label("À préparer", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange))
    case .prepared:
        Label("Préparée", systemImage: "checkmark.seal.fill")
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.green))
    case .none:
        EmptyView()
    }
}
```

If the title lives inside a separate sub-view (`MeetingTopChromeBar`), insert the badge directly in that file's body next to the title, and pass the badge state via a parameter or recompute it inline using `meeting.prepNotes.isEmpty`.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(prep): À préparer / Préparée badge in meeting header"
```

---

### Task 11: CollaboratorDetailView — "Préparation prochaine 1:1" section

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift`

- [ ] **Step 1: Locate CollaboratorDetailView**

Open `OneToOne/Views/DetailsViews.swift`. Find `struct CollaboratorDetailView: View {` (around line 746). Inside its `body`, locate a logical insertion point — typically inside the main `ScrollView { VStack { … } }` between two existing sections (e.g. after the header info, before the meetings list).

- [ ] **Step 2: Add the section**

Insert this `GroupBox` block at the chosen location:
```swift
GroupBox {
    DisclosureGroup(isExpanded: .constant(!collab.standingPrepNotes.isEmpty)) {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownEditorView(
                text: Binding(
                    get: { collab.standingPrepNotes },
                    set: {
                        collab.standingPrepNotes = $0
                        collab.standingPrepUpdatedAt = Date()
                        try? context.save()
                    }
                ),
                textViewID: "collabPrep.\(collab.persistentModelID.hashValue)"
            )
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button {
                    Task { await generatePrepForCollab() }
                } label: {
                    Label("Générer brouillon IA", systemImage: "wand.and.stars")
                }
            }
        }
    } label: {
        HStack {
            Image(systemName: "checklist")
            Text("Préparation prochaine 1:1").font(.headline)
            Spacer()
            if let dt = collab.standingPrepUpdatedAt {
                Text("maj \(relativeDate(dt))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: Add the helper functions**

Inside `CollaboratorDetailView`, near other private helpers, add:
```swift
@Environment(\.modelContext) private var context
@Query private var settingsList: [AppSettings]

@MainActor
private func generatePrepForCollab() async {
    let settings = settingsList.canonicalSettings ?? AppSettings()
    do {
        let md = try await AIReportService.generatePrep(
            collab: collab, project: nil, meeting: nil,
            in: context, settings: settings
        )
        collab.standingPrepNotes = md
        collab.standingPrepUpdatedAt = Date()
        try? context.save()
    } catch {
        // Silent fail for now — user re-tries.
        print("[CollabPrep] generation failed: \(error)")
    }
}

private func relativeDate(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "fr_FR")
    return f.localizedString(for: d, relativeTo: Date())
}
```

If `context` or `settingsList` is already declared in this struct, skip the duplicate declarations.

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(prep): collab detail — section Préparation prochaine 1:1"
```

---

### Task 12: ProjectDetailView — "Préparation prochaine réunion" section

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift`

- [ ] **Step 1: Find ProjectDetailView**

In `OneToOne/Views/DetailsViews.swift`, find `struct ProjectDetailView: View {` (around line 25). Locate a logical insertion point in its `body`.

- [ ] **Step 2: Insert section + helpers**

Insert this block at the chosen location (similar pattern to Task 11):
```swift
GroupBox {
    DisclosureGroup(isExpanded: .constant(!project.standingPrepNotes.isEmpty)) {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownEditorView(
                text: Binding(
                    get: { project.standingPrepNotes },
                    set: {
                        project.standingPrepNotes = $0
                        project.standingPrepUpdatedAt = Date()
                        try? context.save()
                    }
                ),
                textViewID: "projectPrep.\(project.persistentModelID.hashValue)"
            )
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button {
                    Task { await generatePrepForProject() }
                } label: {
                    Label("Générer brouillon IA", systemImage: "wand.and.stars")
                }
            }
        }
    } label: {
        HStack {
            Image(systemName: "checklist")
            Text("Préparation prochaine réunion").font(.headline)
            Spacer()
            if let dt = project.standingPrepUpdatedAt {
                Text("maj \(relativeProjPrepDate(dt))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

Add inside `ProjectDetailView` (skip if duplicate):
```swift
@Environment(\.modelContext) private var context
@Query private var settingsList: [AppSettings]

@MainActor
private func generatePrepForProject() async {
    let settings = settingsList.canonicalSettings ?? AppSettings()
    do {
        let md = try await AIReportService.generatePrep(
            collab: nil, project: project, meeting: nil,
            in: context, settings: settings
        )
        project.standingPrepNotes = md
        project.standingPrepUpdatedAt = Date()
        try? context.save()
    } catch {
        print("[ProjectPrep] generation failed: \(error)")
    }
}

private func relativeProjPrepDate(_ d: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "fr_FR")
    return f.localizedString(for: d, relativeTo: Date())
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git commit -m "feat(prep): project detail — section Préparation prochaine réunion"
```

---

### Task 13: PrepWindow standalone — for menubar entry

**Files:**
- Create: `OneToOne/Views/PrepWindow.swift`
- Modify: `OneToOne/OneToOneApp.swift`

- [ ] **Step 1: Create the window content**

In `OneToOne/Views/PrepWindow.swift`:
```swift
import SwiftUI
import SwiftData

/// Token passed to the `prep-standalone` window to identify the prep target.
/// Carries either a Collaborator stableID or a Project stableID (exactly one).
struct PrepWindowToken: Codable, Hashable {
    let collabID: UUID?
    let projectID: UUID?
}

/// Fenêtre standalone d'édition d'une prep "standing" lancée depuis le menubar.
struct PrepWindowView: View {
    let token: PrepWindowToken
    @Environment(\.modelContext) private var context
    @Query private var collabs: [Collaborator]
    @Query private var projects: [Project]
    @Query private var settingsList: [AppSettings]
    @State private var isGenerating = false
    @State private var error: String?

    private var collab: Collaborator? {
        guard let id = token.collabID else { return nil }
        return collabs.first { $0.stableID == id }
    }
    private var project: Project? {
        guard let id = token.projectID else { return nil }
        return projects.first { $0.stableID == id }
    }
    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            footer
        }
        .padding(14)
        .frame(minWidth: 600, minHeight: 480)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: "checklist")
            if let c = collab {
                Text("Préparation 1:1 — \(c.name)").font(.headline)
            } else if let p = project {
                Text("Préparation projet — \(p.name)").font(.headline)
            } else {
                Text("Préparation").font(.headline)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let c = collab {
            MarkdownEditorView(
                text: Binding(
                    get: { c.standingPrepNotes },
                    set: { c.standingPrepNotes = $0; c.standingPrepUpdatedAt = Date(); try? context.save() }
                ),
                textViewID: "prepWindow.collab.\(c.persistentModelID.hashValue)"
            )
        } else if let p = project {
            MarkdownEditorView(
                text: Binding(
                    get: { p.standingPrepNotes },
                    set: { p.standingPrepNotes = $0; p.standingPrepUpdatedAt = Date(); try? context.save() }
                ),
                textViewID: "prepWindow.project.\(p.persistentModelID.hashValue)"
            )
        } else {
            Text("Cible introuvable.").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                Task { await runGenerate() }
            } label: {
                Label(isGenerating ? "Génère…" : "Générer brouillon IA",
                      systemImage: "wand.and.stars")
            }
            .disabled(isGenerating)
        }
    }

    @MainActor
    private func runGenerate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let md = try await AIReportService.generatePrep(
                collab: collab, project: project, meeting: nil,
                in: context, settings: settings
            )
            if let c = collab {
                c.standingPrepNotes = md; c.standingPrepUpdatedAt = Date()
            } else if let p = project {
                p.standingPrepNotes = md; p.standingPrepUpdatedAt = Date()
            }
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Register the WindowGroup**

In `OneToOne/OneToOneApp.swift`, locate the existing `WindowGroup(id: "1to1-meeting", for: OneToOneLaunchToken.self) { … }`. Just after that block, add:
```swift
WindowGroup(id: "prep-standalone", for: PrepWindowToken.self) { $token in
    if let t = token {
        PrepWindowView(token: t)
            .preferredColorScheme(.light)
    }
}
.modelContainer(container)
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/PrepWindow.swift OneToOne/OneToOneApp.swift
git commit -m "feat(prep): standalone PrepWindow + WindowGroup token"
```

---

### Task 14: Menubar submenu "Préparer…"

**Files:**
- Modify: `OneToOne/Services/MenuBarController.swift`

- [ ] **Step 1: Add submenu builder**

In `MenuBarController.buildMenu(settings:)`, find a logical insertion point (after the existing "Quick actions" / "Notes" items, before separator + Quit). Add:
```swift
let prepItem = NSMenuItem(title: "Préparer…", action: nil, keyEquivalent: "")
prepItem.submenu = buildPrepSubmenu()
menu.addItem(prepItem)
```

- [ ] **Step 2: Build the submenu**

Add as a private function inside `MenuBarController`:
```swift
private func buildPrepSubmenu() -> NSMenu {
    let submenu = NSMenu()
    guard let container = OneToOneApp.sharedContainer else {
        let empty = NSMenuItem(title: "Indisponible", action: nil, keyEquivalent: "")
        empty.isEnabled = false
        submenu.addItem(empty)
        return submenu
    }
    let ctx = container.mainContext

    // 1:1 — pinned collabs alpha
    let collabDesc = FetchDescriptor<Collaborator>(
        predicate: #Predicate { !$0.isArchived && $0.pinLevel > 0 },
        sortBy: [SortDescriptor(\.name)]
    )
    let collabs = ((try? ctx.fetch(collabDesc)) ?? []).prefix(10)
    if !collabs.isEmpty {
        let header = NSMenuItem(title: "1:1", action: nil, keyEquivalent: "")
        header.isEnabled = false
        submenu.addItem(header)
        for c in collabs {
            let mi = NSMenuItem(title: c.name, action: #selector(openCollabPrep(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = c.ensuredStableID.uuidString
            submenu.addItem(mi)
        }
    }

    // Projets : 5 récents (activité < 14j) ou pinned
    let projDesc = FetchDescriptor<Project>(
        predicate: #Predicate { !$0.isArchived },
        sortBy: [SortDescriptor(\.name)]
    )
    let allProjects = (try? ctx.fetch(projDesc)) ?? []
    let cal = Calendar.current
    let cutoff = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
    let recentProjects: [Project] = allProjects.filter { p in
        if p.pinLevel > 0 { return true }
        return p.meetings.contains(where: { $0.date >= cutoff })
    }
    let projects = Array(recentProjects.prefix(5))
    if !projects.isEmpty {
        submenu.addItem(.separator())
        let header = NSMenuItem(title: "Projets", action: nil, keyEquivalent: "")
        header.isEnabled = false
        submenu.addItem(header)
        for p in projects {
            let mi = NSMenuItem(title: p.name, action: #selector(openProjectPrep(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.ensuredStableID.uuidString
            submenu.addItem(mi)
        }
    }

    submenu.addItem(.separator())
    let pickerItem = NSMenuItem(title: "Choisir réunion calendrier…",
                                action: #selector(openCalendarMeetingPicker),
                                keyEquivalent: "")
    pickerItem.target = self
    submenu.addItem(pickerItem)

    return submenu
}

@objc private func openCollabPrep(_ sender: NSMenuItem) {
    guard let idString = sender.representedObject as? String,
          let id = UUID(uuidString: idString) else { return }
    let token = PrepWindowToken(collabID: id, projectID: nil)
    NSApp.activate(ignoringOtherApps: true)
    // Open via SwiftUI WindowGroup id.
    if let url = URL(string: "onetoone://open-prep?collab=\(id.uuidString)") {
        _ = url  // placeholder if URL scheme used; otherwise rely on token-based WindowGroup activation
    }
    NotificationCenter.default.post(name: .openPrepWindow,
                                    object: nil,
                                    userInfo: ["token": token])
}

@objc private func openProjectPrep(_ sender: NSMenuItem) {
    guard let idString = sender.representedObject as? String,
          let id = UUID(uuidString: idString) else { return }
    let token = PrepWindowToken(collabID: nil, projectID: id)
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(name: .openPrepWindow,
                                    object: nil,
                                    userInfo: ["token": token])
}

@objc private func openCalendarMeetingPicker() {
    NSApp.activate(ignoringOtherApps: true)
    NotificationCenter.default.post(name: .openCalendarMeetingPicker, object: nil)
}
```

- [ ] **Step 3: Declare the notification names**

At the top of `MenuBarController.swift` (or inside an extension), add:
```swift
extension Notification.Name {
    static let openPrepWindow = Notification.Name("OneToOne.openPrepWindow")
    static let openCalendarMeetingPicker = Notification.Name("OneToOne.openCalendarMeetingPicker")
}
```

- [ ] **Step 4: Bridge notification → openWindow in ContentView**

In `OneToOne/OneToOneApp.swift`, inside `ContentView.body` `.onAppear`, append at the end:
```swift
NotificationCenter.default.addObserver(
    forName: .openPrepWindow,
    object: nil,
    queue: .main
) { note in
    if let token = note.userInfo?["token"] as? PrepWindowToken {
        Task { @MainActor in
            openWindow(id: "prep-standalone", value: token)
        }
    }
}
```

`openWindow` is the `@Environment(\.openWindow)` injected at the top of `ContentView`.

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

If `Project.meetings` doesn't exist (verify), replace the `recentProjects` filter with a simpler one — sort `allProjects` by `name` and take first 5. Adjust if the model has a different relationship name.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/MenuBarController.swift OneToOne/OneToOneApp.swift
git commit -m "feat(prep): menubar submenu Préparer + window opener bridge"
```

---

### Task 15: CalendarMeetingPicker sheet

**Files:**
- Create: `OneToOne/Views/CalendarMeetingPicker.swift`
- Modify: `OneToOne/OneToOneApp.swift` (observer + sheet binding)

- [ ] **Step 1: Create the picker**

In `OneToOne/Views/CalendarMeetingPicker.swift`:
```swift
import SwiftUI
import SwiftData

/// Sheet listant les réunions futures (kind .global/.work surtout) pour
/// ouvrir leur tab Préparation directement.
struct CalendarMeetingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.date, order: .forward) private var allMeetings: [Meeting]
    let onPick: (Meeting) -> Void

    private var futureMeetings: [Meeting] {
        let now = Date()
        return allMeetings.filter { ($0.scheduledStart ?? $0.date) >= now }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choisir une réunion à préparer").font(.headline)
                Spacer()
                Button("Annuler") { dismiss() }
            }
            if futureMeetings.isEmpty {
                Text("Aucune réunion future planifiée.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(futureMeetings, id: \.persistentModelID) { m in
                    Button {
                        onPick(m)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(m.title).font(.body.bold())
                            Text("\(formatDate(m.scheduledStart ?? m.date)) — \(m.kind.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 240)
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 320)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}
```

- [ ] **Step 2: Wire the sheet in ContentView**

In `OneToOne/OneToOneApp.swift`, inside `ContentView`, add:
```swift
@State private var showMeetingPicker: Bool = false
```

Inside `body`, attach a sheet modifier at the same level as the existing sheets:
```swift
.sheet(isPresented: $showMeetingPicker) {
    CalendarMeetingPicker { meeting in
        // Open the 1to1-meeting window for this meeting via QuickLaunchRouter.
        router.pendingToken = OneToOneLaunchToken(
            meetingID: meeting.ensuredStableID,
            autoStartRecording: false
        )
    }
}
.onReceive(NotificationCenter.default.publisher(for: .openCalendarMeetingPicker)) { _ in
    showMeetingPicker = true
}
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/CalendarMeetingPicker.swift OneToOne/OneToOneApp.swift
git commit -m "feat(prep): CalendarMeetingPicker sheet for menubar"
```

---

### Task 16: Final build + tests + commit log audit

**Files:** (none)

- [ ] **Step 1: Run the prep test filter**

Run: `swift test --filter PrepCarryoverServiceTests 2>&1 | tail -10`
Expected: PASS all PrepCarryoverServiceTests.

- [ ] **Step 2: Full build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`.

- [ ] **Step 3: Confirm tasks 1–15 committed**

Run:
```
git log --oneline -16
```
Expect commits with prefix `feat(prep):` for tasks 1 through 15.

---

## Self-review

**Spec coverage:**

- Model fields (collab/project/meeting/settings) → Task 1. ✓
- `extractUncheckedItems` → Task 2. ✓
- `drainStandingIntoMeeting` (incl. concat behavior + idempotence + global skip) → Task 3. ✓
- `carryoverUncheckedFromMeeting` (incl. setting respect + global skip) → Task 4. ✓
- Tab `.preparation` in MeetingView with drain trigger on appear → Task 5. ✓
- MeetingPrepTab editor + Generate button + confirm overwrite → Task 6. ✓
- `AIReportService.generatePrep` full prompt + history + actions + alerts → Task 7. ✓
- MeetingPrepContextPanel (actions / past meetings / alerts + drag) → Task 8. ✓
- Carryover hook at transcription end → Task 9. ✓
- Badge "À préparer" / "Préparée" → Task 10. ✓
- CollaboratorDetailView section → Task 11. ✓
- ProjectDetailView section → Task 12. ✓
- PrepWindow standalone + WindowGroup → Task 13. ✓
- Menubar submenu "Préparer…" → Task 14. ✓
- CalendarMeetingPicker sheet → Task 15. ✓
- Final verification → Task 16. ✓

No gaps.

**Type consistency:**

- `standingPrepNotes` / `standingPrepUpdatedAt` field names consistent across Collaborator, Project, ProjectDetailView, CollaboratorDetailView, PrepWindow, MenuBarController, PrepCarryoverService. ✓
- `prepNotes` / `prepGeneratedAt` / `prepCarryoverDone` on Meeting — consistent across MeetingView, MeetingPrepTab, PrepCarryoverService. ✓
- `PrepCarryoverService.extractUncheckedItems(from:)`, `drainStandingIntoMeeting(_:in:)`, `carryoverUncheckedFromMeeting(_:settings:in:)` — same signatures across definition (Tasks 2-4), call sites (Tasks 5, 9). ✓
- `AIReportService.generatePrep(collab:project:meeting:in:settings:)` — same signature in stub (Task 6) and real impl (Task 7), called from MeetingPrepTab, CollabDetail, ProjectDetail, PrepWindow. ✓
- `PrepWindowToken(collabID:projectID:)` consistent between definition (Task 13), creation (Task 14), and resolution (Task 13). ✓
- `Notification.Name.openPrepWindow` / `.openCalendarMeetingPicker` consistent between post (Task 14) and observe (Tasks 14, 15). ✓

**Placeholder scan:**

- No "TBD", "TODO", "fill in later" markers.
- All code blocks complete.
- The "stub" placeholders intentionally inserted in Tasks 5/6 are replaced in Tasks 6/7/8 — this is explicit incremental dev, not a placeholder failure.
- Helper functions like `relativeDate` are repeated inside `CollabDetail` and `ProjectDetail` with distinct names (`relativeDate` vs `relativeProjPrepDate`) to avoid duplicate-name errors. Intentional.
