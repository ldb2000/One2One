# Rapport Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement sub-projet C of the rapport manager spec — capture-as-you-go points to discuss with the user's manager, dedicated 1:1 manager meeting flow with checkable agenda + per-item notes, AI-generated CR with action extraction, and a "Suivi manager" sidebar page tracking current items, history, and manager-requested actions.

**Architecture:** SwiftData for two new entities (`ManagerReportItem`, `ManagerMeetingReport`) plus extension fields on `AppSettings`, `ActionTask`, and a new `MeetingKind.manager` case. UI built on a reusable `MeetingHighlightableTextView` (NSViewRepresentable wrapping NSTextView) used everywhere meeting text is rendered, providing context menu + persistent yellow highlights. AI services layered: `ManagerCategoryClassifier` (suggest category at item add) + `ManagerCRGenerator` (single AI call producing markdown summary + JSON action block). All work fully tested at the service layer with in-memory ModelContainer + a `MockAIClient` protocol.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), SwiftData, AppKit (NSTextView interop), Swift Testing framework (`@Suite`/`@Test`/`#expect`), `swift build` / `swift test` from `Package.swift`.

**Spec:** `docs/superpowers/specs/2026-05-05-rapport-manager-design.md`

**Source files map (created in this plan):**
- `OneToOne/Models/ManagerReportModels.swift` — both new `@Model` classes (`ManagerReportItem`, `ManagerMeetingReport`)
- `OneToOne/Services/ManagerReportService.swift` — CRUD on items, archivage, doublon detection
- `OneToOne/Services/ManagerCategoryClassifier.swift` — async category suggestion via AI
- `OneToOne/Services/ManagerCRGenerator.swift` — prompt build + AIClient call + parse + persistence of `ManagerMeetingReport`
- `OneToOne/Services/AIClientProtocol.swift` — minimal protocol so services accept a mock in tests
- `OneToOne/Services/SentenceContextExtractor.swift` — `extractContext(text:range:)` shared utility
- `OneToOne/Views/MeetingHighlightableTextView.swift` — NSViewRepresentable wrapper
- `OneToOne/Views/Meeting/ManagerAgendaSidebar.swift` — agenda sidebar shown when meeting kind == .manager
- `OneToOne/Views/ManagerTrackingView.swift` — sidebar destination "Suivi manager" with 3 tabs
- `OneToOne/Views/ManagerClassificationSheet.swift` — popup at item add
- `OneToOne/Views/ManagerActionReviewSheet.swift` — sheet of AI-extracted actions before materialization
- `OneToOne/Views/ManagerCategoriesEditor.swift` — editable categories list inside Settings
- `Tests/ManagerReportServiceTests.swift`
- `Tests/ManagerCRGeneratorTests.swift`
- `Tests/ManagerCategoryClassifierTests.swift`
- `Tests/SentenceContextExtractorTests.swift`
- `Tests/AppSettingsManagerCategoriesTests.swift`

**Source files modified:**
- `OneToOne/Models/AppSettings.swift` — add `managerName`, `managerEmail`, `managerCategoriesJSON`, `managerReportPrompt`, default categories, default prompt, computed `managerCategories`
- `OneToOne/Models/MeetingModels.swift` — add `MeetingKind.manager` case + label/sfSymbol
- `OneToOne/Models/OtherModels.swift` — add `fromManager`, `managerMeeting` to `ActionTask`
- `OneToOne/Models/SchemaVersions.swift` — register new model types in `SchemaV1.models`
- `OneToOne/Services/BackupService.swift` — add `ManagerReportItemDTO`, `ManagerMeetingReportDTO`, plumb into backup/restore + `SettingsDTO` extension
- `OneToOne/Services/AIClient.swift` — add a `default` static instance conforming to new protocol (pass-through)
- `OneToOne/Views/MeetingView.swift` — swap raw `Text` for `MeetingHighlightableTextView` in transcript & report sections; conditionally swap `MeetingActionsSidebar` for `ManagerAgendaSidebar` when `meeting.kind == .manager`
- `OneToOne/Views/Meeting/MeetingHeaderEditorial.swift` — handle `.manager` kind in dateLabel/icon (fallthrough OK, but smoke check)
- `OneToOne/Views/Sidebar.swift` — add "Suivi manager" entry pointing to `ManagerTrackingView`
- `OneToOne/Views/SettingsView.swift` — new `GroupBox("Manager")` with name, email, categories editor, prompt editor; `onAppear` and `saveSettings` plumbing
- `OneToOne/Views/ActionsListView.swift` — add manager badge to actions where `fromManager == true`
- `OneToOne/Views/MeetingsListView.swift` — pass `.manager` to filter list (kind picker auto-includes via `MeetingKind.allCases`, just visual smoke)
- `OneToOne/Views/MeetingDetailsBlock.swift` — pass `.manager` to filter list (same)

---

## Task 1: Add `MeetingKind.manager` case

**Files:**
- Modify: `OneToOne/Models/MeetingModels.swift:6-31`

- [ ] **Step 1: Open the file and locate the `MeetingKind` enum.**

It currently has 4 cases (`global`, `project`, `oneToOne`, `work`). Add a 5th case and update `label` and `sfSymbol`.

- [ ] **Step 2: Apply the change.**

Replace the entire enum block (lines 6-31) with:

```swift
enum MeetingKind: String, CaseIterable, Identifiable {
    case global   = "global"     // réunion ad-hoc, participants libres
    case project  = "project"    // liée à un projet
    case oneToOne = "oneToOne"   // 1:1 avec un collaborateur
    case work     = "work"       // réunion de travail (équipe)
    case manager  = "manager"    // 1:1 avec le manager direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .global:   return "Globale"
        case .project:  return "Projet"
        case .oneToOne: return "One-to-One"
        case .work:     return "Architecture"
        case .manager:  return "1:1 Manager"
        }
    }

    var sfSymbol: String {
        switch self {
        case .global:   return "person.3.fill"
        case .project:  return "folder.fill"
        case .oneToOne: return "person.2.fill"
        case .work:     return "briefcase.fill"
        case .manager:  return "person.crop.square.filled.and.at.rectangle"
        }
    }
}
```

- [ ] **Step 3: Build to verify compile.**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` (no errors). The compiler will likely emit `switch` exhaustiveness errors for any callers that switch over `MeetingKind` without covering `.manager`. Fix them with explicit `case .manager:` returning a sensible default (e.g. for `weeklyTimeBreakdown` in `Sidebar.swift:802-816`, treat `.manager` like `.oneToOne` — group key `"1:1 Manager (cumul)"`, symbol = `MeetingKind.manager.sfSymbol`).

If build fails on `weeklyTimeBreakdown` switch in `Sidebar.swift`, apply this fix:

```swift
case .manager:
    key = "1:1 Manager (cumul)"
    symbol = MeetingKind.manager.sfSymbol
```

inserted after the `.oneToOne` case. Re-run build.

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Models/MeetingModels.swift OneToOne/Views/Sidebar.swift
git commit -m "feat(meeting): add .manager MeetingKind case"
```

---

## Task 2: Extend `ActionTask` with manager flags

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift:177-192`

- [ ] **Step 1: Read the existing `ActionTask` definition.**

It currently has: `title`, `project`, `interview`, `meeting`, `collaborator`, `dueDate`, `isCompleted`, `reminderID`.

- [ ] **Step 2: Add two new properties.**

Replace lines 177-192 with:

```swift
@Model
final class ActionTask {
    var title: String
    var project: Project?
    var interview: Interview?
    var meeting: Meeting?
    var collaborator: Collaborator?
    var dueDate: Date?
    var isCompleted: Bool = false
    var reminderID: String?

    /// True when the task was extracted from a 1:1 manager CR.
    /// Surfaces a "manager" badge in `ActionsListView` and lets
    /// `ManagerTrackingView` filter to manager-requested actions.
    var fromManager: Bool = false

    /// The 1:1 manager meeting where this action was requested.
    /// Distinct from `meeting` (which can be any meeting source).
    var managerMeeting: Meeting?

    init(title: String, dueDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
    }
}
```

- [ ] **Step 3: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Models/OtherModels.swift
git commit -m "feat(actions): add fromManager + managerMeeting to ActionTask"
```

---

## Task 3: Extend `AppSettings` with manager config + write tests

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift`
- Create: `Tests/AppSettingsManagerCategoriesTests.swift`

- [ ] **Step 1: Write the failing tests first.**

Create `Tests/AppSettingsManagerCategoriesTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("AppSettings — manager categories & defaults")
struct AppSettingsManagerCategoriesTests {

    @Test("Default categories returns the 8 expected entries when JSON is empty defaults")
    func defaultCategories() {
        let s = AppSettings()
        let cats = s.managerCategories
        #expect(cats == [
            "Risque", "Décision", "RH", "Projet",
            "Reconnaissance", "Blocage", "Information", "Demande"
        ])
    }

    @Test("Setting categories round-trips via JSON")
    func roundTrip() {
        let s = AppSettings()
        s.managerCategories = ["A", "B", "C"]
        #expect(s.managerCategories == ["A", "B", "C"])
        #expect(s.managerCategoriesJSON.contains("\"A\""))
    }

    @Test("Corrupted JSON falls back to default categories")
    func fallbackOnCorruption() {
        let s = AppSettings()
        s.managerCategoriesJSON = "{not-valid-json"
        #expect(s.managerCategories.count == 8)
        #expect(s.managerCategories.first == "Risque")
    }

    @Test("Empty array is preserved (user explicitly removed all)")
    func emptyArrayPreserved() {
        let s = AppSettings()
        s.managerCategories = []
        #expect(s.managerCategories == [])
    }

    @Test("managerName / managerEmail default empty")
    func defaultNameEmail() {
        let s = AppSettings()
        #expect(s.managerName == "")
        #expect(s.managerEmail == "")
    }

    @Test("managerReportPrompt defaults to non-empty template")
    func defaultPromptNonEmpty() {
        let s = AppSettings()
        #expect(!s.managerReportPrompt.isEmpty)
        #expect(s.managerReportPrompt == AppSettings.defaultManagerReportPrompt)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `swift test --filter AppSettingsManagerCategoriesTests 2>&1 | tail -30`
Expected: compilation failure (`managerCategories`, `managerName`, etc. unknown).

- [ ] **Step 3: Implement the changes in `AppSettings.swift`.**

Insert the following lines **after** line 52 (`var collaboratorHotkeys: [String: String] = [:]`):

```swift

    // MARK: - Rapport Manager (sub-projet C)

    /// Nom du manager direct affiché dans le CR et dans la sidebar Suivi manager.
    /// Vide tant que l'utilisateur n'a pas configuré la fonctionnalité.
    var managerName: String = ""

    /// Email du manager (optionnel, pour export futur — non utilisé en V1).
    var managerEmail: String = ""

    /// Liste des catégories de classification utilisateur (éditable).
    /// Stockée en JSON pour rester migration-friendly.
    var managerCategoriesJSON: String = AppSettings.defaultManagerCategoriesJSON

    /// Prompt utilisateur additionnel injecté en fin du prompt de génération
    /// du CR manager (cf. ManagerCRGenerator).
    var managerReportPrompt: String = AppSettings.defaultManagerReportPrompt
```

Then insert **after** the existing `static let defaultMeetingCollaboratorColorHex` line (line 56):

```swift

    static let defaultManagerCategories: [String] = [
        "Risque", "Décision", "RH", "Projet",
        "Reconnaissance", "Blocage", "Information", "Demande"
    ]

    static var defaultManagerCategoriesJSON: String {
        (try? String(data: JSONEncoder().encode(defaultManagerCategories), encoding: .utf8))
            ?? "[\"Information\"]"
    }

    static let defaultManagerReportPrompt: String = """
    Reste factuel et synthétique. Distingue clairement ce qui a été dit
    par le manager de mes propres notes. Utilise un ton neutre.
    """

    /// Catégories décodées (avec fallback aux défauts si JSON corrompu).
    var managerCategories: [String] {
        get {
            (try? JSONDecoder().decode([String].self,
                from: Data(managerCategoriesJSON.utf8))) ?? Self.defaultManagerCategories
        }
        set {
            managerCategoriesJSON = (try? String(data: JSONEncoder().encode(newValue),
                encoding: .utf8)) ?? Self.defaultManagerCategoriesJSON
        }
    }
```

Note: getter must NOT collapse `[]` to defaults — only do that on **decode failure**. Since `JSONDecoder().decode([String].self, from: ...)` of `"[]"` succeeds and returns `[]`, the empty-array test will pass naturally.

- [ ] **Step 4: Run the test to verify it passes.**

Run: `swift test --filter AppSettingsManagerCategoriesTests 2>&1 | tail -30`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit.**

```bash
git add OneToOne/Models/AppSettings.swift Tests/AppSettingsManagerCategoriesTests.swift
git commit -m "feat(settings): manager name/email/categories/prompt + tests"
```

---

## Task 4: Create `ManagerReportItem` and `ManagerMeetingReport` models

**Files:**
- Create: `OneToOne/Models/ManagerReportModels.swift`
- Modify: `OneToOne/Models/SchemaVersions.swift:22-44`

- [ ] **Step 1: Create the new model file.**

Write to `OneToOne/Models/ManagerReportModels.swift`:

```swift
import Foundation
import SwiftData

// MARK: - ManagerReportItem
//
// Un point à aborder avec mon manager. Créé soit par sélection (item issu d'une
// transcription / rapport / notes) soit manuellement. Coché pendant le 1:1 manager,
// archivé à la génération du CR.

@Model
final class ManagerReportItem {
    var stableID: UUID = UUID()
    var createdAt: Date = Date()

    // Contenu source brut (l'enrichissement IA est différé à la génération du CR)
    var rawSnippet: String = ""           // phrase exacte sélectionnée
    var contextBefore: String = ""        // ~2 phrases avant
    var contextAfter: String = ""         // ~2 phrases après

    // Localisation source pour le highlight jaune
    // sourceField ∈ {"transcript", "mergedTranscript", "summary", "notes", "liveNotes"}
    // (transcript = rawTranscript). Pour ajout manuel : sourceField = "manual".
    var sourceField: String = "manual"
    var sourceRangeStart: Int = 0          // offset UTF-16 (NSRange-compatible)
    var sourceRangeLength: Int = 0

    // Classification
    var category: String = "Information"   // valeur dans AppSettings.managerCategories ou libre
    var tag: String = ""
    var aiSuggestedCategory: String?       // ce que l'IA a proposé (audit)

    // Saisie utilisateur pendant le 1:1 manager
    var userNotes: String = ""

    // État
    var isCompleted: Bool = false
    var archivedAt: Date?                  // != nil → hors du rapport courant
    var manualOrder: Int = 0
    var isManual: Bool = false

    // Doublon possible (cf. décision Q10-D du spec)
    /// PID d'un autre item considéré comme doublon (overlap > 50% sur la même
    /// source). Stocké en string (UUID stableID de l'autre item) pour rester
    /// migration-friendly — PersistentIdentifier ne sérialise pas bien.
    var duplicateOfStableID: String = ""

    // Relations
    var sourceMeeting: Meeting?
    var archivedInMeeting: Meeting?

    init(rawSnippet: String,
         sourceField: String,
         sourceRangeStart: Int,
         sourceRangeLength: Int,
         sourceMeeting: Meeting?) {
        self.rawSnippet = rawSnippet
        self.sourceField = sourceField
        self.sourceRangeStart = sourceRangeStart
        self.sourceRangeLength = sourceRangeLength
        self.sourceMeeting = sourceMeeting
    }

    /// Convenience init pour ajout manuel (pas de sélection source).
    convenience init(manualSnippet: String, category: String) {
        self.init(rawSnippet: manualSnippet,
                  sourceField: "manual",
                  sourceRangeStart: 0,
                  sourceRangeLength: 0,
                  sourceMeeting: nil)
        self.isManual = true
        self.category = category
    }
}

// MARK: - ManagerMeetingReport
//
// Compte-rendu spécifique généré pour une réunion `kind == .manager`.
// Distinct du `summary` standard du Meeting — permet regen sans écrasement.

@Model
final class ManagerMeetingReport {
    var stableID: UUID = UUID()
    var generatedAt: Date = Date()
    var generatedSummary: String = ""        // markdown
    var durationSeconds: Double = 0
    var modelUsed: String = ""

    /// Snapshot JSON figé des items abordés au moment de la génération.
    /// Source de vérité pour la regénération (les items physiques peuvent
    /// avoir bougé depuis).
    var itemsSnapshotJSON: String = "[]"

    /// Actions extraites par l'IA (titre, dueDate ISO). Avant matérialisation
    /// en ActionTask via le sheet de revue.
    var extractedActionsJSON: String = "[]"

    var meeting: Meeting?

    init(meeting: Meeting) {
        self.meeting = meeting
    }
}
```

- [ ] **Step 2: Register the new models in the schema.**

Open `OneToOne/Models/SchemaVersions.swift` and replace the `models` array (lines 22-44) with:

```swift
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            ProjectMail.self,
            ProjectMailAttachment.self,
            ProjectInfoEntry.self,
            ProjectCollaboratorEntry.self,
            ProjectAttachment.self,
            Collaborator.self,
            Interview.self,
            ActionTask.self,
            ProjectAlert.self,
            AppSettings.self,
            Entity.self,
            InterviewAttachment.self,
            Meeting.self,
            MeetingAttachment.self,
            TranscriptChunk.self,
            SlideCapture.self,
            SavedPrompt.self,
            Note.self,
            ManagerReportItem.self,
            ManagerMeetingReport.self
        ]
    }
```

- [ ] **Step 3: Build.**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`. SwiftData lightweight migration handles new models + new fields automatically because everything has defaults / is Optional.

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Models/ManagerReportModels.swift OneToOne/Models/SchemaVersions.swift
git commit -m "feat(models): ManagerReportItem + ManagerMeetingReport entities"
```

---

## Task 5: Implement `SentenceContextExtractor` with tests

**Files:**
- Create: `OneToOne/Services/SentenceContextExtractor.swift`
- Create: `Tests/SentenceContextExtractorTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/SentenceContextExtractorTests.swift`:

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("SentenceContextExtractor")
struct SentenceContextExtractorTests {

    @Test("Extracts 2 sentences before and after middle selection")
    func middleSelection() {
        let text = "First sentence. Second sentence. SELECTED. Fourth sentence. Fifth sentence."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.contains("Second sentence."))
        #expect(result.before.contains("First sentence."))
        #expect(result.after.contains("Fourth sentence."))
        #expect(result.after.contains("Fifth sentence."))
    }

    @Test("Empty before when selection is at the start")
    func startSelection() {
        let text = "SELECTED. After one. After two."
        let range = NSRange(location: 0, length: 8)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before == "")
        #expect(result.after.contains("After one."))
    }

    @Test("Empty after when selection is at the end")
    func endSelection() {
        let text = "Before two. Before one. SELECTED"
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.after == "")
        #expect(result.before.contains("Before one."))
    }

    @Test("Plafond 400 chars on before")
    func plafond400Before() {
        let long = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50) // > 400
        let text = long + "SELECTED. End."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.count <= 400)
    }

    @Test("Plafond 400 chars on after")
    func plafond400After() {
        let long = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50)
        let text = "Start. SELECTED. " + long
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.after.count <= 400)
    }

    @Test("Stops at paragraph boundary (\\n\\n) before")
    func paragraphBoundaryBefore() {
        let text = "Paragraph A first. Paragraph A second.\n\nParagraph B. SELECTED. End."
        let nsText = text as NSString
        let range = nsText.range(of: "SELECTED")
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(!result.before.contains("Paragraph A"))
        #expect(result.before.contains("Paragraph B"))
    }

    @Test("Zero-length range returns valid empty contexts")
    func zeroLength() {
        let text = "Some text here."
        let range = NSRange(location: 5, length: 0)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before.count <= 400)
        #expect(result.after.count <= 400)
    }

    @Test("Range past text length returns empty contexts safely")
    func outOfBounds() {
        let text = "Short."
        let range = NSRange(location: 100, length: 5)
        let result = SentenceContextExtractor.extractContext(text: text, range: range)
        #expect(result.before == "")
        #expect(result.after == "")
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

Run: `swift test --filter SentenceContextExtractorTests 2>&1 | tail -20`
Expected: compile error (`SentenceContextExtractor` undefined).

- [ ] **Step 3: Implement.**

Create `OneToOne/Services/SentenceContextExtractor.swift`:

```swift
import Foundation

/// Extracts ~2 sentences before and ~2 sentences after a selected NSRange in a
/// text. Used by the manager report flow to capture context around a snippet
/// without invoking the AI at selection time.
///
/// Algorithm:
/// - `before` = walk backwards from `range.location`, collecting characters
///   until we have crossed 2 sentence terminators (`.`, `!`, `?`, `…`) OR a
///   paragraph break (`\n\n`) OR reached a hard cap of 400 characters.
/// - `after` = symmetric, walking forward from `range.location + range.length`.
///
/// All ranges are NSRange (UTF-16 offsets) for consistency with NSTextView.
enum SentenceContextExtractor {

    static let maxContextChars = 400
    static let targetSentences = 2

    static func extractContext(text: String, range: NSRange) -> (before: String, after: String) {
        let nsText = text as NSString
        let total = nsText.length
        guard total > 0 else { return ("", "") }
        guard range.location >= 0, range.location <= total else { return ("", "") }

        let safeStart = min(range.location, total)
        let safeEnd = min(range.location + max(range.length, 0), total)

        let before = walkBackward(in: nsText, from: safeStart)
        let after = walkForward(in: nsText, from: safeEnd, total: total)
        return (before, after)
    }

    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    private static func walkBackward(in nsText: NSString, from start: Int) -> String {
        guard start > 0 else { return "" }
        var sentencesSeen = 0
        var idx = start - 1
        var collected: [Character] = []

        while idx >= 0 && collected.count < maxContextChars {
            let charRange = NSRange(location: idx, length: 1)
            let sub = nsText.substring(with: charRange)
            // Detect paragraph break: current char is \n and previous is \n
            if sub == "\n" && idx > 0 {
                let prevSub = nsText.substring(with: NSRange(location: idx - 1, length: 1))
                if prevSub == "\n" { break }
            }
            if let ch = sub.first {
                if terminators.contains(ch) {
                    if sentencesSeen >= targetSentences { break }
                    sentencesSeen += 1
                }
                collected.append(ch)
            }
            idx -= 1
        }
        return String(collected.reversed()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func walkForward(in nsText: NSString, from end: Int, total: Int) -> String {
        guard end < total else { return "" }
        var sentencesSeen = 0
        var idx = end
        var collected: [Character] = []

        while idx < total && collected.count < maxContextChars {
            let sub = nsText.substring(with: NSRange(location: idx, length: 1))
            if sub == "\n" && idx + 1 < total {
                let nextSub = nsText.substring(with: NSRange(location: idx + 1, length: 1))
                if nextSub == "\n" { break }
            }
            if let ch = sub.first {
                collected.append(ch)
                if terminators.contains(ch) {
                    sentencesSeen += 1
                    if sentencesSeen >= targetSentences { break }
                }
            }
            idx += 1
        }
        return String(collected).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests, verify PASS.**

Run: `swift test --filter SentenceContextExtractorTests 2>&1 | tail -15`
Expected: all 8 tests PASS.

- [ ] **Step 5: Commit.**

```bash
git add OneToOne/Services/SentenceContextExtractor.swift Tests/SentenceContextExtractorTests.swift
git commit -m "feat(services): SentenceContextExtractor + tests"
```

---

## Task 6: Define `AIClientProtocol` for testable AI calls

**Files:**
- Create: `OneToOne/Services/AIClientProtocol.swift`
- Modify: `OneToOne/Services/AIClient.swift` (add a default conforming instance)

- [ ] **Step 1: Create the protocol.**

Write `OneToOne/Services/AIClientProtocol.swift`:

```swift
import Foundation

/// Lightweight protocol around `AIClient.send` so manager services can be
/// unit-tested with a mock. The production conformance is `LiveAIClient`,
/// declared in `AIClient.swift` and exposed as `AIClient.live`.
protocol AIClientProtocol: Sendable {
    func send(prompt: String, settings: AppSettings) async throws -> String
}
```

- [ ] **Step 2: Add the default conformance to `AIClient.swift`.**

Append at the end of `OneToOne/Services/AIClient.swift` (before the final `}` of the enum if there is one — `AIClient` is `enum AIClient`, so put it OUTSIDE the enum at file scope):

```swift

/// Production conformance to `AIClientProtocol`.
struct LiveAIClient: AIClientProtocol {
    func send(prompt: String, settings: AppSettings) async throws -> String {
        try await AIClient.send(prompt: prompt, settings: settings)
    }
}

extension AIClient {
    /// Default live client used by services that accept an `AIClientProtocol`.
    static let live: AIClientProtocol = LiveAIClient()
}
```

- [ ] **Step 3: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Services/AIClientProtocol.swift OneToOne/Services/AIClient.swift
git commit -m "feat(ai): AIClientProtocol for testable services"
```

---

## Task 7: Implement `ManagerCategoryClassifier` with tests

**Files:**
- Create: `OneToOne/Services/ManagerCategoryClassifier.swift`
- Create: `Tests/ManagerCategoryClassifierTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/ManagerCategoryClassifierTests.swift`:

```swift
import Testing
import Foundation
@testable import OneToOne

private struct StubAIClient: AIClientProtocol {
    let response: String
    let throwError: Bool
    init(_ response: String, throwError: Bool = false) {
        self.response = response
        self.throwError = throwError
    }
    func send(prompt: String, settings: AppSettings) async throws -> String {
        if throwError {
            throw NSError(domain: "stub", code: -1, userInfo: [NSLocalizedDescriptionKey: "stub error"])
        }
        return response
    }
}

@Suite("ManagerCategoryClassifier")
struct ManagerCategoryClassifierTests {

    @Test("Exact match (case-insensitive) against settings categories")
    func exactMatch() async throws {
        let s = AppSettings()  // default 8 categories
        let client = StubAIClient("Risque")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "Risque")
    }

    @Test("Case-insensitive match")
    func caseInsensitive() async throws {
        let s = AppSettings()
        let client = StubAIClient("rh")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "RH")
    }

    @Test("Strips punctuation and quotes from response")
    func stripsPunctuation() async throws {
        let s = AppSettings()
        let client = StubAIClient("\"Décision\".")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "Décision")
    }

    @Test("Hors-liste returns nil")
    func unknownCategory() async throws {
        let s = AppSettings()
        let client = StubAIClient("Banana")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }

    @Test("Network/IA error returns nil")
    func errorReturnsNil() async throws {
        let s = AppSettings()
        let client = StubAIClient("", throwError: true)
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }

    @Test("Empty categories list returns nil even if response valid")
    func emptyCategories() async throws {
        let s = AppSettings()
        s.managerCategories = []
        let client = StubAIClient("Risque")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

Run: `swift test --filter ManagerCategoryClassifierTests 2>&1 | tail -15`
Expected: compile error.

- [ ] **Step 3: Implement.**

Create `OneToOne/Services/ManagerCategoryClassifier.swift`:

```swift
import Foundation
import os

private let classifierLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// Suggests a category for a manager-report item by asking the configured AI
/// provider to pick from `AppSettings.managerCategories`. Always non-throwing:
/// errors / timeouts / out-of-list responses return `nil` so the UI can fall
/// back to the default "Information" category.
enum ManagerCategoryClassifier {

    /// Maximum time allowed for the AI call; UI should also treat the call as
    /// non-blocking (sheet opens immediately with placeholder).
    static let timeout: TimeInterval = 3

    static func classify(
        snippet: String,
        projectName: String?,
        settings: AppSettings,
        client: AIClientProtocol = AIClient.live
    ) async -> String? {
        let categories = settings.managerCategories
        guard !categories.isEmpty else {
            classifierLog.info("classify: empty categories, skip")
            return nil
        }

        let prompt = buildPrompt(snippet: snippet, projectName: projectName, categories: categories)

        do {
            let raw = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            return match(response: raw, categories: categories)
        } catch {
            classifierLog.error("classify: failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func buildPrompt(snippet: String, projectName: String?, categories: [String]) -> String {
        let projectLine = projectName.map { "Contexte projet : \($0)" } ?? "Contexte projet : n/a"
        return """
        Classe ce passage parmi les catégories suivantes :
        \(categories.joined(separator: ", "))

        Passage : "\(snippet)"
        \(projectLine)

        Réponds UNIQUEMENT par le nom exact d'une catégorie de la liste.
        """
    }

    /// Matches the AI response against the category list (case- + diacritic-insensitive,
    /// stripping surrounding punctuation/quotes). Returns the canonical
    /// category string from the list, or nil if no match.
    static func match(response: String, categories: [String]) -> String? {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,!?:;«»"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        for category in categories {
            if category.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return category
            }
        }
        return nil
    }

    // MARK: - Timeout helper

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
```

- [ ] **Step 4: Run tests, verify PASS.**

Run: `swift test --filter ManagerCategoryClassifierTests 2>&1 | tail -15`
Expected: 6 PASS.

- [ ] **Step 5: Commit.**

```bash
git add OneToOne/Services/ManagerCategoryClassifier.swift Tests/ManagerCategoryClassifierTests.swift
git commit -m "feat(ai): ManagerCategoryClassifier with timeout + tests"
```

---

## Task 8: Implement `ManagerReportService` with tests

**Files:**
- Create: `OneToOne/Services/ManagerReportService.swift`
- Create: `Tests/ManagerReportServiceTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/ManagerReportServiceTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ManagerReportService — CRUD, archivage, dédup")
struct ManagerReportServiceTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, Collaborator.self, Interview.self, ActionTask.self,
            AppSettings.self, Entity.self, Meeting.self, MeetingAttachment.self,
            TranscriptChunk.self, SlideCapture.self, ProjectAlert.self,
            ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, ProjectMail.self, ProjectMailAttachment.self,
            InterviewAttachment.self, SavedPrompt.self, Note.self,
            ManagerReportItem.self, ManagerMeetingReport.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true)
        ])
    }

    @Test("Add nominal item from selection")
    func addNominal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)

        let item = try ManagerReportService.add(
            snippet: "Hello world",
            sourceField: "transcript",
            range: NSRange(location: 10, length: 11),
            sourceMeeting: meeting,
            contextBefore: "Before.",
            contextAfter: "After.",
            category: "Information",
            tag: "",
            aiSuggestedCategory: "Information",
            in: context
        )
        try context.save()

        #expect(item.rawSnippet == "Hello world")
        #expect(item.sourceRangeStart == 10)
        #expect(item.sourceRangeLength == 11)
        #expect(item.sourceField == "transcript")
        #expect(item.sourceMeeting?.title == "M")
        let all = try context.fetch(FetchDescriptor<ManagerReportItem>())
        #expect(all.count == 1)
    }

    @Test("Add manual item has isManual=true and no source meeting")
    func addManual() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ManagerReportService.addManual(
            snippet: "Préparer point budget",
            category: "Demande",
            tag: "",
            in: context
        )
        try context.save()

        #expect(item.isManual)
        #expect(item.sourceField == "manual")
        #expect(item.sourceMeeting == nil)
        #expect(item.category == "Demande")
    }

    @Test("Duplicate detection: overlap > 50% on same source field+meeting marks both")
    func duplicateDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)

        let first = try ManagerReportService.add(
            snippet: "abcdefghij",
            sourceField: "transcript",
            range: NSRange(location: 0, length: 10),
            sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        // Overlap from 5..15 → overlap chars = 5 over min(10,10)=10 → 50% — must be > 50% to flag.
        // Use 4..14 → overlap = 6 / 10 = 60% → flagged.
        let second = try ManagerReportService.add(
            snippet: "efghijklmn",
            sourceField: "transcript",
            range: NSRange(location: 4, length: 10),
            sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        #expect(second.duplicateOfStableID == first.stableID.uuidString)
        #expect(first.duplicateOfStableID == second.stableID.uuidString)
    }

    @Test("Different source meeting does NOT flag duplicate")
    func notDuplicateAcrossMeetings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m1 = Meeting(title: "A", date: Date(), notes: "")
        let m2 = Meeting(title: "B", date: Date(), notes: "")
        context.insert(m1); context.insert(m2)

        let first = try ManagerReportService.add(
            snippet: "abcdefghij", sourceField: "transcript",
            range: NSRange(location: 0, length: 10), sourceMeeting: m1,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        let second = try ManagerReportService.add(
            snippet: "efghijklmn", sourceField: "transcript",
            range: NSRange(location: 4, length: 10), sourceMeeting: m2,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()
        #expect(first.duplicateOfStableID == "")
        #expect(second.duplicateOfStableID == "")
    }

    @Test("Delete item removes it from context")
    func deleteItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)
        let item = try ManagerReportService.add(
            snippet: "x", sourceField: "transcript",
            range: NSRange(location: 0, length: 1), sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        ManagerReportService.delete(item: item, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<ManagerReportItem>())
        #expect(all.isEmpty)
    }

    @Test("archiveCheckedItems archives only checked + non-archived items")
    func archiveOnlyChecked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "MgrMeeting", date: Date(), notes: "")
        meeting.kindRaw = MeetingKind.manager.rawValue
        context.insert(meeting)

        let a = ManagerReportService.addManual(snippet: "checked", category: "Information", tag: "", in: context)
        a.isCompleted = true
        let b = ManagerReportService.addManual(snippet: "unchecked", category: "Information", tag: "", in: context)
        let c = ManagerReportService.addManual(snippet: "already archived", category: "Information", tag: "", in: context)
        c.isCompleted = true
        c.archivedAt = Date.distantPast
        try context.save()

        let archived = ManagerReportService.archiveCheckedItems(in: meeting, context: context)
        try context.save()

        #expect(archived.count == 1)
        #expect(archived.first?.rawSnippet == "checked")
        #expect(archived.first?.archivedInMeeting?.title == "MgrMeeting")
        #expect(archived.first?.archivedAt != nil)
        // b unchanged
        #expect(b.archivedAt == nil)
        // c unchanged (already archived)
        #expect(c.archivedAt == .distantPast)
    }

    @Test("currentItems excludes archived")
    func currentItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let a = ManagerReportService.addManual(snippet: "live", category: "Information", tag: "", in: context)
        let b = ManagerReportService.addManual(snippet: "old", category: "Information", tag: "", in: context)
        b.archivedAt = Date()
        try context.save()

        let current = try ManagerReportService.currentItems(in: context)
        #expect(current.contains { $0.rawSnippet == "live" })
        #expect(!current.contains { $0.rawSnippet == "old" })
    }

    @Test("archivedItems excludes current")
    func archivedItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let a = ManagerReportService.addManual(snippet: "live", category: "Information", tag: "", in: context)
        let b = ManagerReportService.addManual(snippet: "old", category: "Information", tag: "", in: context)
        b.archivedAt = Date()
        try context.save()

        let archived = try ManagerReportService.archivedItems(in: context)
        #expect(archived.contains { $0.rawSnippet == "old" })
        #expect(!archived.contains { $0.rawSnippet == "live" })
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

Run: `swift test --filter ManagerReportServiceTests 2>&1 | tail -20`
Expected: compile error.

- [ ] **Step 3: Implement the service.**

Create `OneToOne/Services/ManagerReportService.swift`:

```swift
import Foundation
import SwiftData
import os

private let mgrLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// CRUD on `ManagerReportItem` plus archivage helpers and duplicate detection.
/// All methods are synchronous and run on the model context's actor (typically
/// the MainActor for SwiftUI).
enum ManagerReportService {

    /// Threshold (exclusive) above which two ranges on the same source are flagged
    /// as possible duplicates. Spec decision Q10-D.
    static let duplicateOverlapThreshold: Double = 0.5

    // MARK: - Add from selection

    /// Adds a new item issued from a text selection. Detects overlap against
    /// existing items on the same `(sourceMeeting, sourceField)` pair and, if
    /// > 50%, marks both items as possible duplicates of each other.
    @discardableResult
    static func add(
        snippet: String,
        sourceField: String,
        range: NSRange,
        sourceMeeting: Meeting?,
        contextBefore: String,
        contextAfter: String,
        category: String,
        tag: String,
        aiSuggestedCategory: String?,
        in context: ModelContext
    ) throws -> ManagerReportItem {
        let item = ManagerReportItem(
            rawSnippet: snippet,
            sourceField: sourceField,
            sourceRangeStart: range.location,
            sourceRangeLength: range.length,
            sourceMeeting: sourceMeeting
        )
        item.contextBefore = contextBefore
        item.contextAfter = contextAfter
        item.category = category
        item.tag = tag
        item.aiSuggestedCategory = aiSuggestedCategory
        context.insert(item)

        // Duplicate detection — only meaningful when we have a source meeting
        // and a non-zero range.
        if let sourceMeeting, range.length > 0 {
            let existing = try fetchItemsForSource(meeting: sourceMeeting, field: sourceField, in: context)
            for other in existing where other.stableID != item.stableID {
                if overlap(rangeA: range, rangeB: NSRange(location: other.sourceRangeStart, length: other.sourceRangeLength)) > duplicateOverlapThreshold {
                    item.duplicateOfStableID = other.stableID.uuidString
                    other.duplicateOfStableID = item.stableID.uuidString
                    mgrLog.info("add: duplicate detected with \(other.stableID.uuidString, privacy: .public)")
                    break
                }
            }
        }

        mgrLog.info("add: item created field=\(sourceField, privacy: .public) snippet=\"\(String(snippet.prefix(40)), privacy: .public)\"")
        return item
    }

    /// Adds a manual item (no source selection). Always non-failing.
    @discardableResult
    static func addManual(
        snippet: String,
        category: String,
        tag: String,
        in context: ModelContext
    ) -> ManagerReportItem {
        let item = ManagerReportItem(manualSnippet: snippet, category: category)
        item.tag = tag
        context.insert(item)
        mgrLog.info("addManual: \"\(String(snippet.prefix(40)), privacy: .public)\"")
        return item
    }

    // MARK: - Delete

    static func delete(item: ManagerReportItem, in context: ModelContext) {
        // If the item participated in a duplicate pair, clear the back-reference
        // so the surviving item no longer carries a stale link.
        if !item.duplicateOfStableID.isEmpty {
            if let other = try? fetchByStableID(item.duplicateOfStableID, in: context) {
                other.duplicateOfStableID = ""
            }
        }
        context.delete(item)
    }

    // MARK: - Archive

    /// Marks all checked, non-archived items as archived in the given meeting.
    /// Returns the items that were archived (for inclusion in the snapshot JSON).
    @discardableResult
    static func archiveCheckedItems(in meeting: Meeting, context: ModelContext) -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.isCompleted == true && $0.archivedAt == nil }
        )
        let toArchive = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        for item in toArchive {
            item.archivedAt = now
            item.archivedInMeeting = meeting
        }
        mgrLog.info("archiveCheckedItems: \(toArchive.count) item(s) archived in meeting \(meeting.title, privacy: .public)")
        return toArchive
    }

    // MARK: - Queries

    static func currentItems(in context: ModelContext) throws -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.manualOrder), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func archivedItems(in context: ModelContext) throws -> [ManagerReportItem] {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt != nil },
            sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func itemsHighlightingSource(meeting: Meeting, field: String, in context: ModelContext) -> [ManagerReportItem] {
        let target = meeting.persistentModelID
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.sourceField == field && $0.archivedAt == nil }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { $0.sourceMeeting?.persistentModelID == target }
    }

    // MARK: - Helpers

    private static func fetchItemsForSource(meeting: Meeting, field: String, in context: ModelContext) throws -> [ManagerReportItem] {
        let target = meeting.persistentModelID
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.sourceField == field }
        )
        let all = try context.fetch(descriptor)
        return all.filter { $0.sourceMeeting?.persistentModelID == target }
    }

    private static func fetchByStableID(_ uuidString: String, in context: ModelContext) throws -> ManagerReportItem? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        return try context.fetch(descriptor).first
    }

    /// Returns overlap ratio in [0, 1] of two NSRanges, normalized by the
    /// smaller range's length. 0 if either range is empty.
    static func overlap(rangeA: NSRange, rangeB: NSRange) -> Double {
        guard rangeA.length > 0, rangeB.length > 0 else { return 0 }
        let aStart = rangeA.location
        let aEnd = rangeA.location + rangeA.length
        let bStart = rangeB.location
        let bEnd = rangeB.location + rangeB.length
        let overlapStart = max(aStart, bStart)
        let overlapEnd = min(aEnd, bEnd)
        let overlap = max(0, overlapEnd - overlapStart)
        let denom = max(1, min(rangeA.length, rangeB.length))
        return Double(overlap) / Double(denom)
    }
}
```

- [ ] **Step 4: Run tests, verify PASS.**

Run: `swift test --filter ManagerReportServiceTests 2>&1 | tail -20`
Expected: 8 PASS.

- [ ] **Step 5: Commit.**

```bash
git add OneToOne/Services/ManagerReportService.swift Tests/ManagerReportServiceTests.swift
git commit -m "feat(services): ManagerReportService CRUD/archivage/dédup + tests"
```

---

## Task 9: Implement `ManagerCRGenerator` with tests

**Files:**
- Create: `OneToOne/Services/ManagerCRGenerator.swift`
- Create: `Tests/ManagerCRGeneratorTests.swift`

- [ ] **Step 1: Write failing tests.**

Create `Tests/ManagerCRGeneratorTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

private struct StubAIClient: AIClientProtocol {
    let response: String
    func send(prompt: String, settings: AppSettings) async throws -> String {
        response
    }
}

@Suite("ManagerCRGenerator — prompt + parse + generate")
struct ManagerCRGeneratorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, Collaborator.self, Interview.self, ActionTask.self,
            AppSettings.self, Entity.self, Meeting.self, MeetingAttachment.self,
            TranscriptChunk.self, SlideCapture.self, ProjectAlert.self,
            ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, ProjectMail.self, ProjectMailAttachment.self,
            InterviewAttachment.self, SavedPrompt.self, Note.self,
            ManagerReportItem.self, ManagerMeetingReport.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true)
        ])
    }

    @Test("buildPrompt includes manager name, items checked snippet, and user prompt")
    func buildPromptIncludesAll() {
        let s = AppSettings()
        s.managerName = "Alice Manager"
        s.managerReportPrompt = "USER_CUSTOM_PROMPT"

        let m = Meeting(title: "1:1 Mai", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        m.mergedTranscript = "TRANSCRIPT_BODY"

        let item = ManagerReportItem(manualSnippet: "Migration K8s", category: "Risque")
        item.userNotes = "Manager OK pour décaler"
        item.tag = "infra"

        let prompt = ManagerCRGenerator.buildPrompt(meeting: m, items: [item], settings: s)
        #expect(prompt.contains("Alice Manager"))
        #expect(prompt.contains("Migration K8s"))
        #expect(prompt.contains("Risque"))
        #expect(prompt.contains("Manager OK pour décaler"))
        #expect(prompt.contains("TRANSCRIPT_BODY"))
        #expect(prompt.contains("USER_CUSTOM_PROMPT"))
    }

    @Test("buildPrompt falls back to rawTranscript when mergedTranscript empty")
    func buildPromptFallback() {
        let s = AppSettings(); s.managerName = "M"
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        m.mergedTranscript = ""
        m.rawTranscript = "RAW_BODY"
        let prompt = ManagerCRGenerator.buildPrompt(meeting: m, items: [], settings: s)
        #expect(prompt.contains("RAW_BODY"))
    }

    @Test("parseResponse splits markdown and JSON actions block")
    func parseSplitsMarkdownAndJSON() {
        let response = """
        ## Points abordés
        - Point 1

        ## Actions
        Action 1 par manager.

        ```json
        { "actions": [{"title": "Faire X", "deadline": "2026-06-01"}, {"title": "Y", "deadline": null}] }
        ```
        """
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown.contains("## Points abordés"))
        #expect(!parsed.markdown.contains("```json"))
        #expect(parsed.actions.count == 2)
        #expect(parsed.actions[0].title == "Faire X")
        #expect(parsed.actions[0].deadlineISO == "2026-06-01")
        #expect(parsed.actions[1].title == "Y")
        #expect(parsed.actions[1].deadlineISO == nil)
    }

    @Test("parseResponse with no fence returns empty actions and full markdown")
    func parseNoFence() {
        let response = "# CR\nbody only"
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown == "# CR\nbody only")
        #expect(parsed.actions.isEmpty)
    }

    @Test("parseResponse with malformed JSON returns empty actions and intact markdown")
    func parseMalformedJSON() {
        let response = """
        # Body

        ```json
        { broken
        ```
        """
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown.contains("# Body"))
        #expect(parsed.actions.isEmpty)
    }

    @Test("generate end-to-end creates a ManagerMeetingReport, archives checked items")
    func generateEndToEnd() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let s = AppSettings(); s.managerName = "Alice"
        context.insert(s)

        let mgrMeeting = Meeting(title: "1:1 Manager", date: Date(), notes: "")
        mgrMeeting.kindRaw = MeetingKind.manager.rawValue
        mgrMeeting.mergedTranscript = "Conversation."
        context.insert(mgrMeeting)

        let item = ManagerReportService.addManual(snippet: "Topic", category: "Information", tag: "", in: context)
        item.isCompleted = true
        try context.save()

        let stub = StubAIClient(response: """
        # Compte-rendu
        Tout va bien.

        ```json
        { "actions": [{"title": "Suivre", "deadline": null}] }
        ```
        """)

        let report = try await ManagerCRGenerator.generate(
            meeting: mgrMeeting,
            items: [item],
            settings: s,
            context: context,
            client: stub
        )

        #expect(report.generatedSummary.contains("# Compte-rendu"))
        #expect(report.extractedActionsJSON.contains("Suivre"))
        #expect(report.itemsSnapshotJSON.contains("Topic"))
        #expect(report.meeting?.title == "1:1 Manager")
        #expect(item.archivedAt != nil)
        #expect(item.archivedInMeeting?.title == "1:1 Manager")

        let saved = try context.fetch(FetchDescriptor<ManagerMeetingReport>())
        #expect(saved.count == 1)
    }

    @Test("generate throws if no items checked")
    func generateNoItems() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let s = AppSettings(); s.managerName = "A"; context.insert(s)
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        context.insert(m)
        let stub = StubAIClient(response: "# x")

        await #expect(throws: ManagerCRGenerator.GenerationError.self) {
            _ = try await ManagerCRGenerator.generate(
                meeting: m, items: [], settings: s,
                context: context, client: stub
            )
        }
    }

    @Test("generate throws if managerName empty")
    func generateEmptyManagerName() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let s = AppSettings(); s.managerName = ""; context.insert(s)
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        context.insert(m)
        let item = ManagerReportService.addManual(snippet: "t", category: "Information", tag: "", in: context)
        item.isCompleted = true
        try context.save()
        let stub = StubAIClient(response: "# x")

        await #expect(throws: ManagerCRGenerator.GenerationError.self) {
            _ = try await ManagerCRGenerator.generate(
                meeting: m, items: [item], settings: s,
                context: context, client: stub
            )
        }
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

Run: `swift test --filter ManagerCRGeneratorTests 2>&1 | tail -20`
Expected: compile error.

- [ ] **Step 3: Implement.**

Create `OneToOne/Services/ManagerCRGenerator.swift`:

```swift
import Foundation
import SwiftData
import os

private let crLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// Generates the dedicated manager 1:1 CR. Builds a prompt from the checked
/// items + their notes + the meeting transcript, calls the AI, parses the
/// markdown/JSON-actions response, archives the items, and persists a
/// `ManagerMeetingReport`.
@MainActor
enum ManagerCRGenerator {

    enum GenerationError: Error, CustomStringConvertible {
        case noItems
        case missingManagerName
        case wrongMeetingKind

        var description: String {
            switch self {
            case .noItems: return "Cochez au moins un point avant de générer le CR."
            case .missingManagerName: return "Configurez le nom de votre manager dans Paramètres."
            case .wrongMeetingKind: return "Le meeting cible doit être de type 1:1 Manager."
            }
        }
    }

    struct ExtractedAction: Codable {
        let title: String
        let deadlineISO: String?

        enum CodingKeys: String, CodingKey {
            case title
            case deadlineISO = "deadline"
        }
    }

    struct Parsed {
        let markdown: String
        let actions: [ExtractedAction]
    }

    // MARK: - Generate

    @discardableResult
    static func generate(
        meeting: Meeting,
        items: [ManagerReportItem],
        settings: AppSettings,
        context: ModelContext,
        client: AIClientProtocol = AIClient.live
    ) async throws -> ManagerMeetingReport {
        guard meeting.kind == .manager else { throw GenerationError.wrongMeetingKind }
        guard !items.isEmpty else { throw GenerationError.noItems }
        guard !settings.managerName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GenerationError.missingManagerName
        }

        let prompt = buildPrompt(meeting: meeting, items: items, settings: settings)
        let started = Date()
        let raw = try await client.send(prompt: prompt, settings: settings)
        let elapsed = Date().timeIntervalSince(started)
        let parsed = parseResponse(raw)

        let report = ManagerMeetingReport(meeting: meeting)
        report.generatedSummary = parsed.markdown
        report.durationSeconds = elapsed
        report.modelUsed = settings.modelName
        report.extractedActionsJSON = encodeActions(parsed.actions)
        report.itemsSnapshotJSON = encodeItemsSnapshot(items)
        context.insert(report)

        // Archive items now (first save in step 6 of spec section 6.3).
        for item in items {
            item.archivedAt = Date()
            item.archivedInMeeting = meeting
        }

        try context.save()
        crLog.info("generate: report saved, items=\(items.count) actions=\(parsed.actions.count) elapsed=\(elapsed)")
        return report
    }

    // MARK: - Materialize actions (called from sheet of review)

    /// Materialize the actions selected by the user into ActionTask rows.
    /// Called after `generate` once the user has confirmed the action review sheet.
    @discardableResult
    static func materializeActions(
        _ actions: [ExtractedAction],
        in meeting: Meeting,
        context: ModelContext
    ) throws -> [ActionTask] {
        var created: [ActionTask] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        for action in actions {
            let task = ActionTask(title: action.title)
            task.fromManager = true
            task.managerMeeting = meeting
            if let iso = action.deadlineISO,
               let d = isoFormatter.date(from: iso) {
                task.dueDate = d
            }
            context.insert(task)
            created.append(task)
        }
        try context.save()
        return created
    }

    // MARK: - Prompt build

    static func buildPrompt(
        meeting: Meeting,
        items: [ManagerReportItem],
        settings: AppSettings
    ) -> String {
        let transcript: String = {
            let merged = meeting.mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty { return merged }
            return meeting.rawTranscript
        }()

        var itemsBlock = ""
        for (idx, item) in items.enumerated() {
            let tag = item.tag.isEmpty ? "" : " · tag: \(item.tag)"
            let projectLine = item.sourceMeeting?.project?.name.map { "Projet: \($0)" } ?? "Projet: n/a"
            let sourceLine = item.sourceMeeting.map {
                "Source: « \($0.title.isEmpty ? "Réunion sans titre" : $0.title) » du \($0.date.formatted(date: .abbreviated, time: .omitted))"
            } ?? "Source: ajout manuel"
            let notesLine = item.userNotes.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Notes prises pendant le 1:1 : (aucune)"
                : "Notes prises pendant le 1:1 : \(item.userNotes)"
            itemsBlock += """
            \(idx + 1). [\(item.category)\(tag)] \(item.rawSnippet)
               \(sourceLine) · \(projectLine)
               Contexte avant: \(item.contextBefore.isEmpty ? "(vide)" : item.contextBefore)
               Contexte après: \(item.contextAfter.isEmpty ? "(vide)" : item.contextAfter)
               \(notesLine)


            """
        }

        return """
        Tu es l'assistant de OneToOne. Tu produis le compte-rendu d'un 1:1
        avec le manager direct de l'utilisateur. Le compte-rendu doit
        distinguer:
        - les points abordés (avec ce qui a été dit / décidé pour chacun)
        - les actions demandées par le manager (à matérialiser ensuite)
        - les décisions prises
        - les sujets à reporter à la prochaine session

        Réponds UNIQUEMENT en markdown structuré, sections H2.
        À la fin, inclus un bloc JSON ```json { "actions": [...] } ```
        listant les actions demandées par le manager (titre court, due date
        ISO YYYY-MM-DD si mentionnée, sinon null).

        [CONTEXTE GLOBAL]
        Manager : \(settings.managerName)
        Date du 1:1 : \(meeting.date.formatted(date: .complete, time: .shortened))
        Durée : \(meeting.durationSeconds)s

        [POINTS PRÉPARÉS — uniquement les COCHÉS]
        \(itemsBlock.isEmpty ? "(aucun)" : itemsBlock)

        [TRANSCRIPTION DU 1:1 MANAGER]
        \(transcript.isEmpty ? "(transcription absente)" : transcript)

        [INSTRUCTIONS]
        - Pour chaque item, restitue ce qui a été dit en t'appuyant en
          priorité sur les notes prises pendant le 1:1, puis en complétant
          avec la transcription.
        - Si un point coché n'a pas de notes ET aucune trace dans la
          transcription, signale-le explicitement ("non couvert dans la
          transcription").
        - N'invente rien. Si l'info manque, dis-le.

        [PROMPT UTILISATEUR ÉDITABLE]
        \(settings.managerReportPrompt)
        """
    }

    // MARK: - Parse response

    static func parseResponse(_ raw: String) -> Parsed {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fenceRange = trimmed.range(of: "```json", options: .caseInsensitive) else {
            return Parsed(markdown: trimmed, actions: [])
        }
        let beforeFence = String(trimmed[..<fenceRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterFenceStart = trimmed.index(fenceRange.upperBound, offsetBy: 0)
        let after = String(trimmed[afterFenceStart...])
        guard let closingRange = after.range(of: "```") else {
            return Parsed(markdown: beforeFence, actions: [])
        }
        let jsonBody = String(after[..<closingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct Wrapper: Codable { let actions: [ExtractedAction]? }
        guard let data = jsonBody.data(using: .utf8) else {
            return Parsed(markdown: beforeFence, actions: [])
        }
        let actions = (try? JSONDecoder().decode(Wrapper.self, from: data))?.actions ?? []
        return Parsed(markdown: beforeFence, actions: actions)
    }

    // MARK: - Encoding helpers

    private static func encodeActions(_ actions: [ExtractedAction]) -> String {
        guard let data = try? JSONEncoder().encode(actions),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func encodeItemsSnapshot(_ items: [ManagerReportItem]) -> String {
        struct Snap: Codable {
            let stableID: String
            let category: String
            let tag: String
            let rawSnippet: String
            let userNotes: String
            let sourceMeetingTitle: String?
        }
        let snaps = items.map {
            Snap(stableID: $0.stableID.uuidString,
                 category: $0.category,
                 tag: $0.tag,
                 rawSnippet: $0.rawSnippet,
                 userNotes: $0.userNotes,
                 sourceMeetingTitle: $0.sourceMeeting?.title)
        }
        guard let data = try? JSONEncoder().encode(snaps),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
```

- [ ] **Step 4: Run tests, verify PASS.**

Run: `swift test --filter ManagerCRGeneratorTests 2>&1 | tail -25`
Expected: 8 PASS.

- [ ] **Step 5: Commit.**

```bash
git add OneToOne/Services/ManagerCRGenerator.swift Tests/ManagerCRGeneratorTests.swift
git commit -m "feat(ai): ManagerCRGenerator + tests"
```

---

## Task 10: Build `MeetingHighlightableTextView` (NSViewRepresentable)

**Files:**
- Create: `OneToOne/Views/MeetingHighlightableTextView.swift`

This task does not have automated tests — `NSTextView` interop is exercised at runtime. We add a smoke build check at the end.

- [ ] **Step 1: Create the file.**

Write `OneToOne/Views/MeetingHighlightableTextView.swift`:

```swift
import SwiftUI
import AppKit

/// Read-only (or editable) text view with persistent yellow highlights and a
/// custom context menu entry "Ajouter au rapport manager" (⇧⌘M).
///
/// Why NSViewRepresentable:
/// - SwiftUI `Text + textSelection(.enabled)` does not expose the active
///   selection nor allow us to inject persistent background-color spans on
///   arbitrary ranges.
/// - We need NSTextView for both: `selectedRange()` access AND
///   `NSTextStorage.addAttribute(.backgroundColor, ...)` on highlight ranges.
///
/// Range validation: any range whose end exceeds the text length is silently
/// ignored at render — covers the case where the source text was edited and
/// stored offsets became invalid (spec decision A1).
struct MeetingHighlightableTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let highlightedRanges: [NSRange]
    let onAddToManagerReport: (NSRange, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.string = text
        context.coordinator.textView = tv

        // Inject custom menu item via delegate `menu(for:)`.
        // The selector below is recognized in `Coordinator`.
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        tv.isEditable = isEditable
        applyHighlights(to: tv)
    }

    private func applyHighlights(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let total = (tv.string as NSString).length
        storage.beginEditing()
        // Reset background on full range.
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: total))
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in highlightedRanges {
            guard range.location >= 0,
                  range.length > 0,
                  range.location + range.length <= total
            else { continue }
            storage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MeetingHighlightableTextView
        weak var textView: NSTextView?

        init(_ parent: MeetingHighlightableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // Always insert our action at the top of the menu, even if no
            // selection — then disable when selection is invalid.
            let item = NSMenuItem(
                title: "Ajouter au rapport manager",
                action: #selector(addToManagerReportAction(_:)),
                keyEquivalent: "M"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.representedObject = view
            let range = view.selectedRange()
            let snippet = (view.string as NSString).substring(with: range)
            let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            item.isEnabled = (range.length >= 3 && !trimmed.isEmpty)
            menu.insertItem(item, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
            return menu
        }

        @objc func addToManagerReportAction(_ sender: NSMenuItem) {
            guard let tv = sender.representedObject as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let snippet = (tv.string as NSString).substring(with: range)
            parent.onAddToManagerReport(range, snippet)
        }
    }
}
```

- [ ] **Step 2: Build to verify compile.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/MeetingHighlightableTextView.swift
git commit -m "feat(view): MeetingHighlightableTextView with persistent yellow highlights"
```

---

## Task 11: Classification sheet (popup at item add)

**Files:**
- Create: `OneToOne/Views/ManagerClassificationSheet.swift`

- [ ] **Step 1: Create the sheet view.**

Write `OneToOne/Views/ManagerClassificationSheet.swift`:

```swift
import SwiftUI

/// Modal sheet shown when an item is being added to the manager report.
/// Displays the snippet, an async-updated category picker (suggestion comes
/// from `ManagerCategoryClassifier`), and a free-form tag field. The sheet
/// opens immediately with `category = "Information"` while the suggestion is
/// fetched in the background.
struct ManagerClassificationSheet: View {
    let snippet: String
    let projectName: String?
    let categories: [String]
    @State var suggestedCategory: String?      // bubbles up from the AI call
    @State var category: String
    @State var tag: String = ""

    let isLoadingSuggestion: Bool
    let onCancel: () -> Void
    let onConfirm: (_ category: String, _ tag: String, _ aiSuggested: String?) -> Void

    init(
        snippet: String,
        projectName: String?,
        categories: [String],
        suggestedCategory: String?,
        isLoadingSuggestion: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String, String, String?) -> Void
    ) {
        self.snippet = snippet
        self.projectName = projectName
        self.categories = categories
        self._suggestedCategory = State(initialValue: suggestedCategory)
        self._category = State(initialValue: suggestedCategory ?? "Information")
        self.isLoadingSuggestion = isLoadingSuggestion
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Classer ce point")
                .font(.headline)

            GroupBox("Aperçu") {
                Text(snippet.count > 280 ? String(snippet.prefix(280)) + "…" : snippet)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Catégorie :")
                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                    if !categories.contains(category) {
                        Text("\(category) (libre)").tag(category)
                    }
                }
                .frame(maxWidth: 240)
                if isLoadingSuggestion {
                    ProgressView().controlSize(.small)
                }
            }

            HStack {
                Text("Tag (optionnel) :")
                TextField("ex. infra, budget", text: $tag)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Ajouter") {
                    onConfirm(category, tag.trimmingCharacters(in: .whitespaces), suggestedCategory)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/ManagerClassificationSheet.swift
git commit -m "feat(view): ManagerClassificationSheet"
```

---

## Task 12: Action review sheet (post-generation)

**Files:**
- Create: `OneToOne/Views/ManagerActionReviewSheet.swift`

- [ ] **Step 1: Create the file.**

Write `OneToOne/Views/ManagerActionReviewSheet.swift`:

```swift
import SwiftUI

/// Sheet shown after `ManagerCRGenerator.generate` returns. Lists the actions
/// extracted by the AI; user can edit titles, set/clear due dates, untick to
/// skip. On confirm, the kept actions are materialized into ActionTask via
/// `ManagerCRGenerator.materializeActions`.
struct ManagerActionReviewSheet: View {
    struct DraftAction: Identifiable {
        let id = UUID()
        var title: String
        var dueDate: Date?
        var keep: Bool
    }

    @State var drafts: [DraftAction]
    let onCancel: () -> Void
    let onConfirm: ([ManagerCRGenerator.ExtractedAction]) -> Void

    init(
        actions: [ManagerCRGenerator.ExtractedAction],
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([ManagerCRGenerator.ExtractedAction]) -> Void
    ) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let initial = actions.map {
            DraftAction(
                title: $0.title,
                dueDate: $0.deadlineISO.flatMap(isoFormatter.date(from:)),
                keep: true
            )
        }
        self._drafts = State(initialValue: initial)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Actions demandées par le manager")
                .font(.headline)
            Text("L'IA a proposé les actions ci-dessous. Décoche celles à ignorer, modifie titre / échéance, puis valide.")
                .font(.caption)
                .foregroundColor(.secondary)

            if drafts.isEmpty {
                Text("Aucune action extraite par l'IA.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($drafts) { $draft in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $draft.keep).labelsHidden()
                                TextField("Titre", text: $draft.title).textFieldStyle(.roundedBorder)
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { draft.dueDate ?? Date() },
                                        set: { draft.dueDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .disabled(!draft.keep)
                                Button {
                                    draft.dueDate = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Retirer la date d'échéance")
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack {
                Spacer()
                Button("Ignorer toutes", action: onCancel)
                Button("Créer les actions") {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withFullDate]
                    let kept: [ManagerCRGenerator.ExtractedAction] = drafts
                        .filter { $0.keep && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { d in
                            ManagerCRGenerator.ExtractedAction(
                                title: d.title,
                                deadlineISO: d.dueDate.map { isoFormatter.string(from: $0) }
                            )
                        }
                    onConfirm(kept)
                }
                .buttonStyle(.borderedProminent)
                .disabled(drafts.allSatisfy { !$0.keep })
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }
}
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/ManagerActionReviewSheet.swift
git commit -m "feat(view): ManagerActionReviewSheet"
```

---

## Task 13: Manager agenda sidebar inside MeetingView

**Files:**
- Create: `OneToOne/Views/Meeting/ManagerAgendaSidebar.swift`

- [ ] **Step 1: Create the file.**

Write `OneToOne/Views/Meeting/ManagerAgendaSidebar.swift`:

```swift
import SwiftUI
import SwiftData

/// Sidebar shown inside MeetingView when `meeting.kind == .manager`.
/// Lists items from the current manager report (archivedAt == nil), separated
/// into "à aborder" / "abordés", with a notes editor per expanded item and a
/// "Générer CR manager" footer button.
struct ManagerAgendaSidebar: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt == nil },
           sort: [SortDescriptor(\.manualOrder), SortDescriptor(\.createdAt, order: .reverse)])
    private var items: [ManagerReportItem]

    @State private var expandedItemID: UUID?
    @State private var filterCategory: String?

    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var pendingActions: [ManagerCRGenerator.ExtractedAction] = []
    @State private var showActionReview = false
    @State private var showAddManual = false
    @State private var manualSnippet = ""
    @State private var manualCategory = "Information"
    @State private var manualTag = ""

    private var unchecked: [ManagerReportItem] {
        items.filter { !$0.isCompleted && passesFilter($0) }
    }
    private var checked: [ManagerReportItem] {
        items.filter { $0.isCompleted && passesFilter($0) }
    }

    private func passesFilter(_ item: ManagerReportItem) -> Bool {
        if let f = filterCategory { return item.category == f }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if unchecked.isEmpty && checked.isEmpty {
                        ContentUnavailableView(
                            "Aucun point à aborder",
                            systemImage: "checklist",
                            description: Text("Ajoute des points depuis tes réunions ou via le bouton ci-dessous.")
                        )
                        .padding(.vertical, 32)
                    } else {
                        if !unchecked.isEmpty {
                            Text("À aborder").font(.caption.bold()).foregroundColor(.secondary)
                            ForEach(unchecked) { item in itemRow(item) }
                        }
                        if !checked.isEmpty {
                            Text("Abordés (\(checked.count))").font(.caption.bold()).foregroundColor(.secondary).padding(.top, 8)
                            ForEach(checked) { item in itemRow(item) }
                        }
                    }
                }
                .padding(12)
            }

            footer
        }
        .frame(minWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showActionReview) {
            ManagerActionReviewSheet(
                actions: pendingActions,
                onCancel: { showActionReview = false },
                onConfirm: { kept in
                    showActionReview = false
                    do {
                        _ = try ManagerCRGenerator.materializeActions(kept, in: meeting, context: context)
                    } catch {
                        generationError = error.localizedDescription
                    }
                }
            )
        }
        .sheet(isPresented: $showAddManual) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter un point").font(.headline)
                TextField("Description", text: $manualSnippet, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                Picker("Catégorie", selection: $manualCategory) {
                    ForEach(settings.managerCategories, id: \.self) { Text($0).tag($0) }
                }
                TextField("Tag (optionnel)", text: $manualTag).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annuler") { showAddManual = false; manualSnippet = ""; manualTag = "" }
                    Button("Ajouter") {
                        let snippet = manualSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !snippet.isEmpty else { return }
                        _ = ManagerReportService.addManual(
                            snippet: snippet, category: manualCategory, tag: manualTag, in: context
                        )
                        try? context.save()
                        manualSnippet = ""; manualTag = ""
                        showAddManual = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: MeetingKind.manager.sfSymbol).foregroundColor(.accentColor)
                Text("Agenda manager").font(.headline)
                Spacer()
            }
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories, id: \.self) {
                        Text($0).tag($0 as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = generationError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button {
                showAddManual = true
            } label: {
                Label("Ajouter point", systemImage: "plus.circle")
            }
            Spacer()
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Génération…")
                    }
                } else {
                    Label("Générer CR manager", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || checked.isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func itemRow(_ item: ManagerReportItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { item.isCompleted },
                    set: { newValue in
                        item.isCompleted = newValue
                        try? context.save()
                    }
                )).labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.category)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                        if !item.tag.isEmpty {
                            Text("#\(item.tag)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Text(item.rawSnippet)
                        .font(.callout)
                        .lineLimit(expandedItemID == item.stableID ? nil : 2)
                    if let src = item.sourceMeeting {
                        Text("• \(src.title.isEmpty ? "Réunion" : src.title) · \(src.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    if expandedItemID == item.stableID {
                        expandedItemID = nil
                    } else {
                        expandedItemID = item.stableID
                    }
                } label: {
                    Image(systemName: expandedItemID == item.stableID ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            if expandedItemID == item.stableID {
                TextEditor(text: Binding(
                    get: { item.userNotes },
                    set: { newValue in
                        item.userNotes = newValue
                        try? context.save()
                    }
                ))
                .font(.callout)
                .frame(minHeight: 70, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func generate() async {
        generationError = nil
        isGenerating = true
        defer { isGenerating = false }

        let toGenerate = checked
        do {
            let report = try await ManagerCRGenerator.generate(
                meeting: meeting, items: toGenerate, settings: settings, context: context
            )
            // Decode actions from the generated report.
            if let data = report.extractedActionsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ManagerCRGenerator.ExtractedAction].self, from: data) {
                pendingActions = decoded
                showActionReview = true
            }
        } catch {
            generationError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/Meeting/ManagerAgendaSidebar.swift
git commit -m "feat(view): ManagerAgendaSidebar in MeetingView"
```

---

## Task 14: Wire `ManagerAgendaSidebar` into `MeetingView`

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift:148-174`

- [ ] **Step 1: Read the current `HSplitView` block and swap based on kind.**

Replace lines 148-174 (currently `HSplitView { mainPanel...; MeetingActionsSidebar(...) }`) with:

```swift
            HSplitView {
                mainPanel.frame(minWidth: 520)
                if meeting.kind == .manager {
                    ManagerAgendaSidebar(meeting: meeting, settings: settings)
                        .frame(minWidth: 320, maxWidth: 460)
                } else {
                    MeetingActionsSidebar(
                        meeting: meeting,
                        settings: settings,
                        allCollaborators: allCollaborators,
                        currentSlides: currentSlides,
                        collapsed: $actionsCollapsed,
                        newTaskTitle: $newTaskTitle,
                        selectedCollaborator: $selectedCollaborator,
                        showNewTaskDueDate: $showNewTaskDueDate,
                        newTaskDueDate: $newTaskDueDate,
                        onAddTask: addTask,
                        onDeleteTask: { task in
                            context.delete(task)
                            saveContext()
                        },
                        onToggleTaskCompletion: { task in
                            task.isCompleted.toggle()
                            saveContext()
                        },
                        onShowSlides:       { showSlidesList = true },
                        onShowCaptureSetup: { showCaptureSetup = true },
                        saveContext: saveContext
                    )
                    .frame(minWidth: actionsCollapsed ? 44 : 300, maxWidth: actionsCollapsed ? 44 : 440)
                }
            }
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): use ManagerAgendaSidebar when kind == .manager"
```

---

## Task 15: Wire highlightable text into MeetingView transcript & report sections

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift:540-610` (transcript view + report summary)

The goal: replace the `Text(meeting.mergedTranscript)` / `Text(meeting.summary)` etc. with `MeetingHighlightableTextView`, plumbing the "add to manager report" callback to a sheet that opens `ManagerClassificationSheet`.

- [ ] **Step 1: Add state on `MeetingView` for the classification sheet.**

Add these properties after line 51 (`@State private var didAutoStart = false`):

```swift
    // MARK: - Manager report sheet
    @State private var pendingMgrSelection: (range: NSRange, snippet: String, field: String)?
    @State private var showMgrClassificationSheet = false
    @State private var mgrSuggestedCategory: String?
    @State private var isMgrSuggestingCategory = false
```

- [ ] **Step 2: Add a helper to launch the classification flow.**

Add this private method inside `MeetingView` (place it next to other `private func` methods, e.g. after `saveContext`):

```swift
    private func startManagerReportFlow(range: NSRange, snippet: String, field: String) {
        pendingMgrSelection = (range, snippet, field)
        mgrSuggestedCategory = nil
        isMgrSuggestingCategory = true
        showMgrClassificationSheet = true

        Task { @MainActor in
            let suggested = await ManagerCategoryClassifier.classify(
                snippet: snippet,
                projectName: meeting.project?.name,
                settings: settings
            )
            mgrSuggestedCategory = suggested
            isMgrSuggestingCategory = false
        }
    }

    private func confirmManagerItem(category: String, tag: String, aiSuggested: String?) {
        guard let pending = pendingMgrSelection else { return }
        let fullText: String
        switch pending.field {
        case "mergedTranscript": fullText = meeting.mergedTranscript
        case "transcript":       fullText = meeting.rawTranscript
        case "summary":          fullText = meeting.summary
        case "notes":            fullText = meeting.notes
        case "liveNotes":        fullText = meeting.liveNotes
        default:                 fullText = ""
        }
        let ctx = SentenceContextExtractor.extractContext(text: fullText, range: pending.range)
        do {
            _ = try ManagerReportService.add(
                snippet: pending.snippet,
                sourceField: pending.field,
                range: pending.range,
                sourceMeeting: meeting,
                contextBefore: ctx.before,
                contextAfter: ctx.after,
                category: category,
                tag: tag,
                aiSuggestedCategory: aiSuggested,
                in: context
            )
            try context.save()
        } catch {
            print("[Manager] add failed: \(error)")
        }
        pendingMgrSelection = nil
        showMgrClassificationSheet = false
    }

    private func managerHighlightedRanges(for field: String) -> [NSRange] {
        ManagerReportService.itemsHighlightingSource(meeting: meeting, field: field, in: context).map {
            NSRange(location: $0.sourceRangeStart, length: $0.sourceRangeLength)
        }
    }
```

- [ ] **Step 3: Replace transcript `Text` with the highlightable view.**

Replace lines 549-558 (the `if !meeting.mergedTranscript.isEmpty { Text(...) } else { Text(...) }` block) with:

```swift
                    if !meeting.mergedTranscript.isEmpty {
                        MeetingHighlightableTextView(
                            text: .constant(meeting.mergedTranscript),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "mergedTranscript"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "mergedTranscript")
                            }
                        )
                        .frame(minHeight: 280)
                    } else {
                        MeetingHighlightableTextView(
                            text: .constant(meeting.rawTranscript),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "transcript"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "transcript")
                            }
                        )
                        .frame(minHeight: 280)
                    }
```

- [ ] **Step 4: Replace summary `Text` with the highlightable view.**

Find line 584: `Text(meeting.summary).font(MeetingTheme.bodySerif).textSelection(.enabled)` and replace with:

```swift
                        MeetingHighlightableTextView(
                            text: .constant(meeting.summary),
                            isEditable: false,
                            highlightedRanges: managerHighlightedRanges(for: "summary"),
                            onAddToManagerReport: { range, snippet in
                                startManagerReportFlow(range: range, snippet: snippet, field: "summary")
                            }
                        )
                        .frame(minHeight: 240)
```

- [ ] **Step 5: Wire the classification sheet.**

Find the existing `.sheet(...)` modifiers near line 178 (`.sheet(isPresented: $showCalendarImporter)`). After that block, add a new sheet:

```swift
        .sheet(isPresented: $showMgrClassificationSheet) {
            if let pending = pendingMgrSelection {
                ManagerClassificationSheet(
                    snippet: pending.snippet,
                    projectName: meeting.project?.name,
                    categories: settings.managerCategories,
                    suggestedCategory: mgrSuggestedCategory,
                    isLoadingSuggestion: isMgrSuggestingCategory,
                    onCancel: {
                        showMgrClassificationSheet = false
                        pendingMgrSelection = nil
                    },
                    onConfirm: { category, tag, aiSuggested in
                        confirmManagerItem(category: category, tag: tag, aiSuggested: aiSuggested)
                    }
                )
            }
        }
```

- [ ] **Step 6: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 7: Commit.**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): wire manager report selection in transcript+summary"
```

---

## Task 16: `ManagerTrackingView` (sidebar destination "Suivi manager")

**Files:**
- Create: `OneToOne/Views/ManagerTrackingView.swift`
- Modify: `OneToOne/Views/Sidebar.swift:125-129`

- [ ] **Step 1: Create the view.**

Write `OneToOne/Views/ManagerTrackingView.swift`:

```swift
import SwiftUI
import SwiftData

/// "Suivi manager" sidebar destination. Three tabs:
/// - Rapport courant: items à aborder (archivedAt == nil)
/// - Historique: items archivés (archivedAt != nil)
/// - Actions demandées: ActionTask.fromManager == true
struct ManagerTrackingView: View {

    @Query private var settingsList: [AppSettings]
    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt == nil },
           sort: [SortDescriptor(\.manualOrder), SortDescriptor(\.createdAt, order: .reverse)])
    private var currentItems: [ManagerReportItem]

    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt != nil },
           sort: [SortDescriptor(\.archivedAt, order: .reverse)])
    private var archivedItems: [ManagerReportItem]

    @Query(filter: #Predicate<ActionTask> { $0.fromManager == true },
           sort: [SortDescriptor(\.dueDate)])
    private var managerActions: [ActionTask]

    @Environment(\.modelContext) private var context

    @State private var selectedTab: Tab = .current
    @State private var filterCategory: String?
    @State private var historySearch: String = ""
    @State private var showAddManual = false
    @State private var manualSnippet = ""
    @State private var manualCategory = "Information"
    @State private var manualTag = ""

    enum Tab: String, Identifiable, CaseIterable {
        case current = "Rapport courant"
        case history = "Historique"
        case actions = "Actions demandées"
        var id: String { rawValue }
    }

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    private var filteredCurrent: [ManagerReportItem] {
        guard let f = filterCategory else { return currentItems }
        return currentItems.filter { $0.category == f }
    }

    private var filteredHistory: [ManagerReportItem] {
        var result = archivedItems
        if let f = filterCategory {
            result = result.filter { $0.category == f }
        }
        let q = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.rawSnippet.lowercased().contains(q) ||
                $0.userNotes.lowercased().contains(q) ||
                $0.tag.lowercased().contains(q)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 12)

            Group {
                switch selectedTab {
                case .current: currentTab
                case .history: historyTab
                case .actions: actionsTab
                }
            }
        }
        .navigationTitle("Suivi manager")
        .sheet(isPresented: $showAddManual) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter un point").font(.headline)
                TextField("Description", text: $manualSnippet, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Picker("Catégorie", selection: $manualCategory) {
                    ForEach(settings.managerCategories, id: \.self) { Text($0).tag($0) }
                }
                TextField("Tag", text: $manualTag).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annuler") { showAddManual = false; manualSnippet = ""; manualTag = "" }
                    Button("Ajouter") {
                        let snippet = manualSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !snippet.isEmpty else { return }
                        _ = ManagerReportService.addManual(snippet: snippet, category: manualCategory, tag: manualTag, in: context)
                        try? context.save()
                        manualSnippet = ""; manualTag = ""; showAddManual = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20).frame(minWidth: 420)
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories, id: \.self) { Text($0).tag($0 as String?) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button {
                    showAddManual = true
                } label: { Label("Ajouter", systemImage: "plus.circle") }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            if filteredCurrent.isEmpty {
                ContentUnavailableView(
                    "Aucun point à aborder",
                    systemImage: "tray",
                    description: Text("Sélectionne du texte dans une réunion pour commencer.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredCurrent) { item in
                        ItemRow(item: item, settings: settings)
                            .swipeActions {
                                Button(role: .destructive) {
                                    ManagerReportService.delete(item: item, in: context)
                                    try? context.save()
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyTab: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories, id: \.self) { Text($0).tag($0 as String?) }
                }
                .pickerStyle(.menu)
                TextField("Recherche", text: $historySearch).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Spacer()
            }
            .padding(16)

            if filteredHistory.isEmpty {
                ContentUnavailableView("Aucun élément archivé", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredHistory) { item in
                        ItemRow(item: item, settings: settings, showArchiveDate: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsTab: some View {
        if managerActions.isEmpty {
            ContentUnavailableView("Aucune action manager", systemImage: "checklist")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("À faire") {
                    ForEach(managerActions.filter { !$0.isCompleted }) { task in
                        actionRow(task)
                    }
                }
                Section("Faites") {
                    ForEach(managerActions.filter { $0.isCompleted }) { task in
                        actionRow(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ task: ActionTask) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { task.isCompleted },
                set: { newValue in task.isCompleted = newValue; try? context.save() }
            )).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.callout)
                if let due = task.dueDate {
                    Text("Échéance \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(due < Date() ? .red : .secondary)
                }
                if let m = task.managerMeeting {
                    Text("1:1 du \(m.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Item row

    private struct ItemRow: View {
        let item: ManagerReportItem
        let settings: AppSettings
        var showArchiveDate: Bool = false
        @Environment(\.modelContext) private var context

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.category)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    if !item.tag.isEmpty {
                        Text("#\(item.tag)").font(.caption2).foregroundColor(.secondary)
                    }
                    if !item.duplicateOfStableID.isEmpty {
                        Label("Doublon possible", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    if showArchiveDate, let d = item.archivedAt {
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(item.rawSnippet).font(.callout)
                if !item.userNotes.isEmpty {
                    Text(item.userNotes).font(.caption).foregroundColor(.secondary)
                }
                if let src = item.sourceMeeting {
                    Text("Source : \(src.title.isEmpty ? "Réunion" : src.title) · \(src.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
```

- [ ] **Step 2: Add the sidebar entry.**

Open `OneToOne/Views/Sidebar.swift`. After the existing "Notes" `NavigationLink` (line 125-129), insert:

```swift
                NavigationLink {
                    ManagerTrackingView()
                } label: {
                    Label("Suivi manager", systemImage: "person.crop.square.filled.and.at.rectangle")
                }
```

- [ ] **Step 3: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Views/ManagerTrackingView.swift OneToOne/Views/Sidebar.swift
git commit -m "feat(view): ManagerTrackingView + sidebar entry"
```

---

## Task 17: Settings UI for manager configuration

**Files:**
- Create: `OneToOne/Views/ManagerCategoriesEditor.swift`
- Modify: `OneToOne/Views/SettingsView.swift`

- [ ] **Step 1: Create the categories editor.**

Write `OneToOne/Views/ManagerCategoriesEditor.swift`:

```swift
import SwiftUI

/// Editable list of manager categories with add/remove/rename and drag-reorder.
struct ManagerCategoriesEditor: View {
    @Binding var categories: [String]
    @State private var newCategory: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nouvelle catégorie", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
                    categories.append(trimmed)
                    newCategory = ""
                } label: { Label("Ajouter", systemImage: "plus.circle") }
                .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if categories.isEmpty {
                Text("Aucune catégorie — utilise « Réinitialiser » pour restaurer les défauts.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                List {
                    ForEach(categories.indices, id: \.self) { idx in
                        HStack {
                            TextField("Catégorie", text: Binding(
                                get: { categories[idx] },
                                set: { categories[idx] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            Spacer()
                            Button {
                                categories.remove(at: idx)
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }
            Button("Réinitialiser aux 8 défauts") {
                categories = AppSettings.defaultManagerCategories
            }
            .font(.caption)
        }
    }
}
```

- [ ] **Step 2: Add the manager section in SettingsView.**

Open `OneToOne/Views/SettingsView.swift`. Add new `@State` properties after line 42 (`@State private var isReindexing = false`):

```swift
    // Manager section
    @State private var managerName: String = ""
    @State private var managerEmail: String = ""
    @State private var managerCategories: [String] = []
    @State private var managerReportPrompt: String = ""
```

In `onAppear` (line 477), append after `weeklyExportPrompt = settings.weeklyExportPrompt`:

```swift
            managerName = settings.managerName
            managerEmail = settings.managerEmail
            managerCategories = settings.managerCategories
            managerReportPrompt = settings.managerReportPrompt
```

In `saveSettings()` (line 642), append before `do { try context.save() ...`:

```swift
        settings.managerName = managerName
        settings.managerEmail = managerEmail
        settings.managerCategories = managerCategories
        settings.managerReportPrompt = managerReportPrompt
```

Add a new `GroupBox` section. Find line 363 (`GroupBox("Entités")`) and insert BEFORE it:

```swift
                GroupBox("Manager (1:1 manager)") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Nom du manager :")
                            TextField("ex. Alice Dupont", text: $managerName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }
                        HStack {
                            Text("Email du manager (optionnel) :")
                            TextField("alice@example.com", text: $managerEmail)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveSettings() }
                        }

                        Divider()

                        Text("Catégories de classification")
                            .font(.caption.bold())
                        ManagerCategoriesEditor(categories: $managerCategories)
                            .onChange(of: managerCategories) { _, _ in saveSettings() }

                        Divider()

                        HStack {
                            Text("Prompt CR manager (instructions personnalisées)")
                                .font(.caption.bold())
                            Spacer()
                            Button("Réinitialiser") {
                                managerReportPrompt = AppSettings.defaultManagerReportPrompt
                                saveSettings()
                            }
                            .font(.caption)
                        }
                        EditableTextEditor(text: $managerReportPrompt)
                            .frame(minHeight: 80)

                        Button("Enregistrer") { saveSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 5)
                }
```

- [ ] **Step 3: Build.**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`

- [ ] **Step 4: Commit.**

```bash
git add OneToOne/Views/ManagerCategoriesEditor.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): manager configuration section"
```

---

## Task 18: Plumb manager fields into BackupService

**Files:**
- Modify: `OneToOne/Services/BackupService.swift`

- [ ] **Step 1: Extend `SettingsDTO`.**

In `BackupService.swift` lines 20-28, replace `SettingsDTO` with:

```swift
    struct SettingsDTO: Codable {
        var cloudToken: String
        var apiEndpoint: String
        var modelName: String
        var provider: String
        var importPrompt: String
        var reformulatePrompt: String
        var weeklyExportPrompt: String
        // Manager (sub-projet C)
        var managerName: String?
        var managerEmail: String?
        var managerCategoriesJSON: String?
        var managerReportPrompt: String?
    }
```

Optionals = backward-compat with old backups.

- [ ] **Step 2: Add `ManagerReportItemDTO` and `ManagerMeetingReportDTO`.**

After the existing DTOs (insert after `InterviewDTO` declaration around line 218), add:

```swift
    struct ManagerReportItemDTO: Codable {
        var stableID: UUID
        var createdAt: Date
        var rawSnippet: String
        var contextBefore: String
        var contextAfter: String
        var sourceField: String
        var sourceRangeStart: Int
        var sourceRangeLength: Int
        var category: String
        var tag: String
        var aiSuggestedCategory: String?
        var userNotes: String
        var isCompleted: Bool
        var archivedAt: Date?
        var manualOrder: Int
        var isManual: Bool
        var duplicateOfStableID: String
        var sourceMeetingStableID: UUID?
        var archivedInMeetingStableID: UUID?
    }

    struct ManagerMeetingReportDTO: Codable {
        var stableID: UUID
        var generatedAt: Date
        var generatedSummary: String
        var durationSeconds: Double
        var modelUsed: String
        var itemsSnapshotJSON: String
        var extractedActionsJSON: String
        var meetingStableID: UUID?
    }
```

- [ ] **Step 3: Extend `BackupPayload`.**

Replace the `BackupPayload` struct (lines 7-18) with:

```swift
    struct BackupPayload: Codable {
        var exportedAt: Date
        var settings: SettingsDTO
        var entities: [EntityDTO]
        var projects: [ProjectDTO]
        var collaborators: [CollaboratorDTO]
        var interviews: [InterviewDTO]
        var meetings: [MeetingDTO]?
        var managerReportItems: [ManagerReportItemDTO]?    // V3 — sub-projet C
        var managerMeetingReports: [ManagerMeetingReportDTO]?
    }
```

- [ ] **Step 4: Extend `backup(...)` to accept and serialize manager entities.**

Find the signature (line 220-227) and replace with:

```swift
    func backup(
        settings: AppSettings,
        entities: [Entity],
        projects: [Project],
        collaborators: [Collaborator],
        interviews: [Interview],
        meetings: [Meeting] = [],
        managerReportItems: [ManagerReportItem] = [],
        managerMeetingReports: [ManagerMeetingReport] = []
    ) throws -> Data {
```

In the `BackupPayload(...)` constructor (line 228 onwards), replace the `SettingsDTO(...)` block with:

```swift
            settings: SettingsDTO(
                cloudToken: settings.cloudToken,
                apiEndpoint: settings.apiEndpoint,
                modelName: settings.modelName,
                provider: settings.provider.rawValue,
                importPrompt: settings.importPrompt,
                reformulatePrompt: settings.reformulatePrompt,
                weeklyExportPrompt: settings.weeklyExportPrompt,
                managerName: settings.managerName,
                managerEmail: settings.managerEmail,
                managerCategoriesJSON: settings.managerCategoriesJSON,
                managerReportPrompt: settings.managerReportPrompt
            ),
```

At the end of the `BackupPayload(...)` constructor (just before the closing `)` at line 429), add:

```swift
            ,
            managerReportItems: managerReportItems.map { item in
                ManagerReportItemDTO(
                    stableID: item.stableID,
                    createdAt: item.createdAt,
                    rawSnippet: item.rawSnippet,
                    contextBefore: item.contextBefore,
                    contextAfter: item.contextAfter,
                    sourceField: item.sourceField,
                    sourceRangeStart: item.sourceRangeStart,
                    sourceRangeLength: item.sourceRangeLength,
                    category: item.category,
                    tag: item.tag,
                    aiSuggestedCategory: item.aiSuggestedCategory,
                    userNotes: item.userNotes,
                    isCompleted: item.isCompleted,
                    archivedAt: item.archivedAt,
                    manualOrder: item.manualOrder,
                    isManual: item.isManual,
                    duplicateOfStableID: item.duplicateOfStableID,
                    sourceMeetingStableID: item.sourceMeeting?.stableID,
                    archivedInMeetingStableID: item.archivedInMeeting?.stableID
                )
            },
            managerMeetingReports: managerMeetingReports.map { report in
                ManagerMeetingReportDTO(
                    stableID: report.stableID,
                    generatedAt: report.generatedAt,
                    generatedSummary: report.generatedSummary,
                    durationSeconds: report.durationSeconds,
                    modelUsed: report.modelUsed,
                    itemsSnapshotJSON: report.itemsSnapshotJSON,
                    extractedActionsJSON: report.extractedActionsJSON,
                    meetingStableID: report.meeting?.stableID
                )
            }
```

- [ ] **Step 5: Extend `restore(...)` to handle manager entities.**

In `restore(...)` near line 437, add fetching and clearing existing manager entities. After line 448 (`let existingMeetings = try context.fetch(...)`), add:

```swift
        let existingMgrItems = try context.fetch(FetchDescriptor<ManagerReportItem>())
        let existingMgrReports = try context.fetch(FetchDescriptor<ManagerMeetingReport>())
        for item in existingMgrItems { context.delete(item) }
        for report in existingMgrReports { context.delete(report) }
```

After restoring settings (around line 465 — after `context.insert(restoredSettings)`), restore manager fields:

```swift
        restoredSettings.managerName = payload.settings.managerName ?? ""
        restoredSettings.managerEmail = payload.settings.managerEmail ?? ""
        restoredSettings.managerCategoriesJSON = payload.settings.managerCategoriesJSON ?? AppSettings.defaultManagerCategoriesJSON
        restoredSettings.managerReportPrompt = payload.settings.managerReportPrompt ?? AppSettings.defaultManagerReportPrompt
```

After all meetings have been restored (find the loop `for meetingDTO in payload.meetings ?? []` ending around line 700, after that loop closes), add manager-item restore. Locate the end of the meeting restore loop and append:

```swift
        // Build a stableID → Meeting map so we can rebind manager item relations.
        let restoredMeetings = try context.fetch(FetchDescriptor<Meeting>())
        let meetingByStableID: [UUID: Meeting] = Dictionary(uniqueKeysWithValues: restoredMeetings.map { ($0.stableID, $0) })

        for itemDTO in payload.managerReportItems ?? [] {
            let item = ManagerReportItem(
                rawSnippet: itemDTO.rawSnippet,
                sourceField: itemDTO.sourceField,
                sourceRangeStart: itemDTO.sourceRangeStart,
                sourceRangeLength: itemDTO.sourceRangeLength,
                sourceMeeting: itemDTO.sourceMeetingStableID.flatMap { meetingByStableID[$0] }
            )
            item.stableID = itemDTO.stableID
            item.createdAt = itemDTO.createdAt
            item.contextBefore = itemDTO.contextBefore
            item.contextAfter = itemDTO.contextAfter
            item.category = itemDTO.category
            item.tag = itemDTO.tag
            item.aiSuggestedCategory = itemDTO.aiSuggestedCategory
            item.userNotes = itemDTO.userNotes
            item.isCompleted = itemDTO.isCompleted
            item.archivedAt = itemDTO.archivedAt
            item.manualOrder = itemDTO.manualOrder
            item.isManual = itemDTO.isManual
            item.duplicateOfStableID = itemDTO.duplicateOfStableID
            item.archivedInMeeting = itemDTO.archivedInMeetingStableID.flatMap { meetingByStableID[$0] }
            context.insert(item)
        }

        for reportDTO in payload.managerMeetingReports ?? [] {
            let mtg = reportDTO.meetingStableID.flatMap { meetingByStableID[$0] }
            let report = ManagerMeetingReport(meeting: mtg ?? Meeting(title: "", date: reportDTO.generatedAt, notes: ""))
            // The init requires a meeting; if missing, the placeholder we created
            // is detached. We still want to preserve the stable ID.
            report.stableID = reportDTO.stableID
            report.generatedAt = reportDTO.generatedAt
            report.generatedSummary = reportDTO.generatedSummary
            report.durationSeconds = reportDTO.durationSeconds
            report.modelUsed = reportDTO.modelUsed
            report.itemsSnapshotJSON = reportDTO.itemsSnapshotJSON
            report.extractedActionsJSON = reportDTO.extractedActionsJSON
            report.meeting = mtg
            context.insert(report)
        }
```

- [ ] **Step 6: Update `DashboardView.executeImport` (and any other call site) to pass the new entities.**

Search for `BackupService().backup(` callers:

Run: `grep -rn "backupService.backup\|BackupService().backup" OneToOne/`
Expected: at least one in `OneToOne/Views/Sidebar.swift` (DashboardView pre-import auto-backup) around line 1373.

For each call site, fetch and pass the new entities. Add before the call:

```swift
            let mgrItems = (try? context.fetch(FetchDescriptor<ManagerReportItem>())) ?? []
            let mgrReports = (try? context.fetch(FetchDescriptor<ManagerMeetingReport>())) ?? []
```

Update the `.backup(` call to include `managerReportItems: mgrItems, managerMeetingReports: mgrReports` arguments at the end (right before `)`).

Repeat for any other location that calls `.backup(`. Do the same for the `SettingsView.swift` Backup/Restore button (search around line 407 — `GroupBox("Backup / Restore")`).

- [ ] **Step 7: Build.**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`. If there are unrelated `backup(` callers that fail, add the two new defaulted params (they have defaults, so existing call sites compile unchanged unless they used positional args after `meetings:` — none should).

- [ ] **Step 8: Commit.**

```bash
git add OneToOne/Services/BackupService.swift OneToOne/Views/Sidebar.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(backup): include manager items + reports + settings in backup/restore"
```

---

## Task 19: Manager badge in `ActionsListView`

**Files:**
- Modify: `OneToOne/Views/ActionsListView.swift:138-141` (title row), `:205-214` (subtitle row)

The action row is composed of two HStacks: title row (line 128-150) and metadata row (line 152-218). Add the manager badge in the title row, immediately after `EditableTextField(...)` at line 138-140.

- [ ] **Step 1: Insert the badge.**

Locate the title row block (line 138-141):

```swift
                EditableTextField(placeholder: "Action...", text: $task.title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 20)

                Spacer()
```

Replace it with:

```swift
                EditableTextField(placeholder: "Action...", text: $task.title)
                    .strikethrough(task.isCompleted)
                    .frame(height: 20)

                if task.fromManager {
                    Label("manager", systemImage: "person.crop.square.filled.and.at.rectangle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                        .help("Action demandée par le manager")
                }

                Spacer()
```

- [ ] **Step 2: Build.**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add OneToOne/Views/ActionsListView.swift
git commit -m "feat(actions): manager badge for ActionTask.fromManager"
```

---

## Task 20: Final smoke build + manual test checklist

**Files:** none modified.

- [ ] **Step 1: Full clean build.**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`

- [ ] **Step 2: Full test suite.**

Run: `swift test 2>&1 | tail -30`
Expected: all tests PASS, including the new manager test suites and the pre-existing ones.

- [ ] **Step 3: Manual smoke checklist.**

Launch the app (`./run.sh` or via Xcode). Verify:

- [ ] Settings → "Manager" section visible, name/email/categories editable, prompt editor present.
- [ ] Sidebar shows new "Suivi manager" entry with the right icon.
- [ ] In any meeting with a non-empty transcript, right-click on the transcription → "Ajouter au rapport manager" is enabled when ≥3 chars selected.
- [ ] Adding an item opens the classification sheet; suggestion picker updates from `Information` to the AI suggestion if the provider is reachable; otherwise stays at `Information`.
- [ ] After confirming, a yellow highlight appears on the selected text in the transcription view.
- [ ] Reopening the meeting shows the highlight still applied.
- [ ] Suivi manager → tab "Rapport courant" lists the item.
- [ ] Create a new meeting, change its kind to `1:1 Manager` via the kind picker (it appears in the picker as a 5th option). The right sidebar swaps to `ManagerAgendaSidebar`.
- [ ] Items from the rapport courant are listed; cocher one + saisir des notes.
- [ ] Click "Générer CR manager" → after the AI call, the action review sheet pops up. Confirm. Items are archived (disappear from current rapport, appear in tab "Historique"). Actions appear in tab "Actions demandées" + globally in `ActionsListView` with the manager badge.
- [ ] Suppression d'un item dans Suivi manager → la prochaine ouverture du meeting source montre que le highlight a disparu.

- [ ] **Step 4: Commit any minor fixes from manual testing as separate commits.**

If issues are found, fix them with focused commits (e.g., `fix(view): xxx`). Do NOT batch unrelated fixes.

---

## Out of scope (V1.1 follow-up)

- Edit transcription / report / vocabulary feedback → sub-projet B
- Diarization → sub-projet D
- Audio editing → sub-projet A
- Index `ManagerMeetingReport` in Spotlight / RAG
- Extend `/cherche` slash to manager corpus
- Sync manager actions onto manager-as-Collaborator profile
- `ManagerCRGenerator.regenerate(report:)` (spec §6.4) — current behavior: user must delete the existing `ManagerMeetingReport` and call `generate()` again. The snapshot JSON is preserved per generation but no helper updates an existing report in-place.
- Inverse cascade `Meeting → ManagerMeetingReport` (spec §7.7): not declared on `Meeting`. Default `.nullify` from the `ManagerMeetingReport.meeting` side leaves dangling reports if a meeting is deleted. They appear under tab "Historique" without a meeting link. Adding the inverse `@Relationship(deleteRule: .cascade)` on `Meeting` is a one-line addition in `OtherModels.swift` but requires re-checking SwiftData lightweight migration on existing user data — deferred until V1.1.
- Bundled SwiftData store snapshot for migration regression test (spec §8.1) — verified manually at startup instead.
