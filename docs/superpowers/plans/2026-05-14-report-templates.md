# Report Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single hardcoded report prompt with a user-editable `ReportTemplate` system: 8 built-ins, named sections, `{{variable}}` substitution, per-template history context mode, picker on `MeetingView`.

**Architecture:** New `ReportTemplate` SwiftData model (Optional stableID pattern). Pure services `TemplateVariableResolver` + `HistoryContextBuilder` + a static `BuiltInTemplates` dict. `AIReportService` gains a `generate(meeting:settings:onProgress:)` entry that composes (template, history, variables) → prompt → `AIClient`. Settings UI adds a CRUD editor; `MeetingView` adds a picker.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XCTest. Tests in `Tests/` target (`swift test`).

**Spec:** [docs/superpowers/specs/2026-05-14-report-templates-design.md](../specs/2026-05-14-report-templates-design.md).

**Pre-flight (once):**
```bash
git status
swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
```

---

## Task 1: `ReportTemplate` SwiftData model + schema registration

**Files:**
- Create: `OneToOne/Models/ReportTemplate.swift`
- Modify: `OneToOne/Models/SchemaVersions.swift`
- Test: `Tests/ReportTemplateModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ReportTemplateModelTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class ReportTemplateModelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_init_setsDefaults() {
        let t = ReportTemplate(name: "Test", kind: .general)
        XCTAssertEqual(t.name, "Test")
        XCTAssertEqual(t.kindRaw, "general")
        XCTAssertEqual(t.historyModeRaw, "none")
        XCTAssertEqual(t.historyN, 0)
        XCTAssertEqual(t.historyK, 0)
        XCTAssertFalse(t.isBuiltIn)
        XCTAssertFalse(t.isArchived)
        XCTAssertNotNil(t.stableID)
    }

    func test_ensuredStableID_backfillsNil() throws {
        let t = ReportTemplate(name: "Test", kind: .general)
        context.insert(t)
        t.stableID = nil
        let backfilled = t.ensuredStableID
        XCTAssertNotNil(t.stableID)
        XCTAssertEqual(backfilled, t.stableID)
    }

    func test_sections_roundtrip() {
        let t = ReportTemplate(name: "Test", kind: .general)
        t.sections = [
            .init(title: "Résumé", hint: "Synthèse en 3 lignes"),
            .init(title: "Décisions", hint: "")
        ]
        XCTAssertEqual(t.sections.count, 2)
        XCTAssertEqual(t.sections[0].title, "Résumé")
        XCTAssertEqual(t.sections[1].hint, "")
    }

    func test_kind_enum_accessor() {
        let t = ReportTemplate(name: "Test", kind: .copil)
        XCTAssertEqual(t.kind, .copil)
        t.kind = .codir
        XCTAssertEqual(t.kindRaw, "codir")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReportTemplateModelTests 2>&1 | tail -20`
Expected: compile failure — `ReportTemplate` undefined.

- [ ] **Step 3: Create the model**

Create `OneToOne/Models/ReportTemplate.swift`:

```swift
import Foundation
import SwiftData

enum ReportTemplateKind: String, CaseIterable, Identifiable {
    case general, oneToOne, manager
    case copil, cosui, codir
    case preparation, restitution
    case metier, initiative, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:    return "Global"
        case .oneToOne:   return "1:1 Collaborateur"
        case .manager:    return "1:1 Manager"
        case .copil:      return "COPIL"
        case .cosui:      return "COSUI"
        case .codir:      return "CODIR"
        case .preparation: return "Préparation"
        case .restitution: return "Restitution / Démo"
        case .metier:     return "Métier"
        case .initiative: return "Initiative"
        case .custom:     return "Personnalisé"
        }
    }

    var sfSymbol: String {
        switch self {
        case .general:    return "doc.text"
        case .oneToOne:   return "person.2.fill"
        case .manager:    return "person.crop.square.filled.and.at.rectangle"
        case .copil:      return "rectangle.3.group"
        case .cosui:      return "list.bullet.rectangle"
        case .codir:      return "building.columns"
        case .preparation: return "checklist"
        case .restitution: return "play.rectangle"
        case .metier:     return "briefcase"
        case .initiative: return "lightbulb"
        case .custom:     return "slider.horizontal.3"
        }
    }
}

/// Ordered section a ReportTemplate asks the AI to produce.
struct TemplateSection: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var hint: String
}

enum HistoryMode: String, CaseIterable, Identifiable {
    case none, lastN, rag, hybrid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:   return "Aucun"
        case .lastN:  return "N derniers résumés"
        case .rag:    return "RAG sémantique"
        case .hybrid: return "Hybride (résumés + RAG)"
        }
    }
}

@Model
final class ReportTemplate {
    /// Optional — SwiftData migration caveat. Use `ensuredStableID`.
    var stableID: UUID? = nil
    var name: String
    var kindRaw: String
    var promptBody: String
    var sectionsJSON: String
    var historyModeRaw: String = HistoryMode.none.rawValue
    var historyN: Int = 0
    var historyK: Int = 0
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    init(name: String,
         kind: ReportTemplateKind,
         promptBody: String = "",
         sections: [TemplateSection] = [],
         historyMode: HistoryMode = .none,
         historyN: Int = 0,
         historyK: Int = 0,
         isBuiltIn: Bool = false) {
        self.stableID = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.promptBody = promptBody
        self.sectionsJSON = Self.encodeSections(sections)
        self.historyModeRaw = historyMode.rawValue
        self.historyN = historyN
        self.historyK = historyK
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    var kind: ReportTemplateKind {
        get { ReportTemplateKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var historyMode: HistoryMode {
        get { HistoryMode(rawValue: historyModeRaw) ?? .none }
        set { historyModeRaw = newValue.rawValue }
    }

    var sections: [TemplateSection] {
        get { Self.decodeSections(sectionsJSON) }
        set { sectionsJSON = Self.encodeSections(newValue); updatedAt = Date() }
    }

    // MARK: - JSON helpers

    private static func encodeSections(_ items: [TemplateSection]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func decodeSections(_ raw: String) -> [TemplateSection] {
        guard let data = raw.data(using: .utf8),
              let items = try? JSONDecoder().decode([TemplateSection].self, from: data) else {
            return []
        }
        return items
    }
}
```

- [ ] **Step 4: Register `ReportTemplate` in the schema**

Open `OneToOne/Models/SchemaVersions.swift`. Inside `SchemaV1.models` add `ReportTemplate.self` (alphabetically grouped near other models — placement doesn't affect behaviour but keep diff readable):

```swift
            ReportTemplate.self,
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ReportTemplateModelTests 2>&1 | tail -10`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Models/ReportTemplate.swift OneToOne/Models/SchemaVersions.swift Tests/ReportTemplateModelTests.swift
git commit -m "feat(model): ReportTemplate + ReportTemplateKind + TemplateSection + HistoryMode"
```

---

## Task 2: `Meeting.reportTemplate` + `Project.planningText`

**Files:**
- Modify: `OneToOne/Models/OtherModels.swift`
- Modify: `OneToOne/Models/Project.swift`

- [ ] **Step 1: Add the Meeting relationship**

In `OneToOne/Models/OtherModels.swift`, find the `Meeting` class (around line 240). Just before the `init(...)` of `Meeting`, add:

```swift
    // MARK: - Report template (chosen at create, overridable)
    var reportTemplate: ReportTemplate?
```

- [ ] **Step 2: Add Project.planningText**

In `OneToOne/Models/Project.swift`, in the `Project` class body, add:

```swift
    /// Free-text planning notes. Surfaced via {{project.planning}} variable
    /// in report templates.
    var planningText: String = ""
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean (Optional relationship + String with default = lightweight migration).

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Models/OtherModels.swift OneToOne/Models/Project.swift
git commit -m "feat(model): Meeting.reportTemplate + Project.planningText"
```

---

## Task 3: `BuiltInTemplates` static dict + seed-if-needed

**Files:**
- Create: `OneToOne/Services/BuiltInTemplates.swift`
- Modify: `OneToOne/OneToOneApp.swift` (call seed from `repairStoreIfNeeded`)
- Test: `Tests/BuiltInTemplatesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/BuiltInTemplatesTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class BuiltInTemplatesTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_seedIfNeeded_inserts8_onFirstCall() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))
        XCTAssertEqual(count, 8)
    }

    func test_seedIfNeeded_isIdempotent() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))
        XCTAssertEqual(count, 8)
    }

    func test_seedIfNeeded_doesNotOverwriteEditedBuiltIn() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        // Find D1 and mutate
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true && $0.name == "Global" }
        )
        let global = try context.fetch(descriptor).first
        XCTAssertNotNil(global)
        global?.promptBody = "EDITED"
        try context.save()

        // Re-seed should preserve user's edit
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let again = try context.fetch(descriptor).first
        XCTAssertEqual(again?.promptBody, "EDITED")
    }

    func test_dict_contains_all8Names() {
        let names = Set(BuiltInTemplates.dict.keys)
        XCTAssertEqual(names, [
            "Global", "1:1 Collaborateur", "1:1 Manager",
            "COPIL", "COSUI", "CODIR",
            "Préparation", "Restitution / Démo"
        ])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BuiltInTemplatesTests 2>&1 | tail -10`
Expected: compile failure — `BuiltInTemplates` undefined.

- [ ] **Step 3: Implement `BuiltInTemplates`**

Create `OneToOne/Services/BuiltInTemplates.swift`:

```swift
import Foundation
import SwiftData

/// Source-of-truth for the 8 shipped templates. Lives in Swift (not DB)
/// so PRs can review prompt changes diff-side and "Restaurer défaut" has
/// a stable target.
enum BuiltInTemplates {

    struct Seed {
        let name: String
        let kind: ReportTemplateKind
        let sections: [TemplateSection]
        let historyMode: HistoryMode
        let historyN: Int
        let historyK: Int
        let promptBody: String
    }

    /// Keyed by `name` (also the SwiftData lookup key for `seedIfNeeded`).
    static let dict: [String: Seed] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static let all: [Seed] = [
        d1_global,
        d2_oneToOne,
        d3_manager,
        d4_copil,
        d5_cosui,
        d6_codir,
        d7_preparation,
        d8_restitution
    ]

    /// Idempotent seeding. Inserts only missing built-in templates by name.
    /// Never overwrites existing rows (preserves user edits — see spec §8.1).
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existing.map { $0.name })
        for seed in all where !existingNames.contains(seed.name) {
            let t = ReportTemplate(
                name: seed.name,
                kind: seed.kind,
                promptBody: seed.promptBody,
                sections: seed.sections,
                historyMode: seed.historyMode,
                historyN: seed.historyN,
                historyK: seed.historyK,
                isBuiltIn: true
            )
            context.insert(t)
        }
    }

    // MARK: - D1 Global

    static let d1_global = Seed(
        name: "Global",
        kind: .general,
        sections: [
            .init(title: "Contexte général", hint: "Ce qui se passe au moment de la réunion (top actions, alertes, sujets actifs)."),
            .init(title: "Résumé", hint: "Synthèse en 3-5 lignes."),
            .init(title: "Décisions", hint: "Décisions actées avec porteur si possible."),
            .init(title: "Actions", hint: "Liste numérotée avec assignee et échéance."),
            .init(title: "Faits marquants", hint: "Ce qui sort du quotidien.")
        ],
        historyMode: .none,
        historyN: 0,
        historyK: 0,
        promptBody: """
        Type: {{kind}} · Date: {{date}} · Participants: {{participants}}

        Contexte actuel:
        {{contexte_general}}

        {{custom_prompt}}

        Transcription brute (sortie STT + notes live):
        {{transcript}}

        Notes manuelles:
        {{notes}}
        """
    )

    // MARK: - D2 1:1 Collaborateur

    static let d2_oneToOne = Seed(
        name: "1:1 Collaborateur",
        kind: .oneToOne,
        sections: [
            .init(title: "Suivi du précédent", hint: "Reprise des actions du précédent 1:1."),
            .init(title: "Sujets abordés", hint: "Points discutés en synthèse."),
            .init(title: "Décisions", hint: ""),
            .init(title: "Actions pour {{collab.name}}", hint: "Avec échéance."),
            .init(title: "Ressenti / Climat", hint: "Signal faible côté ambiance / motivation.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        1:1 avec {{collab.name}} ({{collab.role}}) · {{date}}

        Actions ouvertes du collaborateur:
        {{collab.actions_ouvertes}}

        Derniers 1:1 (pour suivi):
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D3 1:1 Manager

    static let d3_manager = Seed(
        name: "1:1 Manager",
        kind: .manager,
        sections: [
            .init(title: "Suivi semaine", hint: "Points repris du précédent 1:1 manager."),
            .init(title: "Sujets", hint: "Sujets abordés."),
            .init(title: "Demandes du manager", hint: "Ce que le manager demande / attend."),
            .init(title: "Actions", hint: "Mes engagements avec échéance."),
            .init(title: "Points d'attention", hint: "Risques, signaux faibles.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        1:1 Manager · {{date}}

        Items en cours (suivi manager):
        {{manager.items_actuels}}

        Dernier CR manager:
        {{manager.dernier_cr}}

        Historique:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D4 COPIL

    static let d4_copil = Seed(
        name: "COPIL",
        kind: .copil,
        sections: [
            .init(title: "Contexte projet", hint: "Rappel rapide du contexte."),
            .init(title: "Avancement", hint: "Où on en est sur le planning."),
            .init(title: "Décisions", hint: "Décisions actées par le comité."),
            .init(title: "Risques", hint: "Risques identifiés + niveau."),
            .init(title: "Prochaines étapes", hint: "Avec porteur et échéance.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        COPIL {{project.name}} ({{project.code}}) · {{date}} · Phase: {{project.phase}}

        Planning projet:
        {{project.planning}}

        Actions ouvertes:
        {{project.actions_ouvertes}}

        Dernier COPIL:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D5 COSUI

    static let d5_cosui = Seed(
        name: "COSUI",
        kind: .cosui,
        sections: [
            .init(title: "Avancement par sujet", hint: "Un bloc par sujet abordé."),
            .init(title: "Points bloquants", hint: ""),
            .init(title: "Actions", hint: "Avec porteur et échéance."),
            .init(title: "Indicateurs", hint: "KPIs / chiffres mentionnés.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        COSUI {{project.name}} · {{date}}

        Actions ouvertes:
        {{project.actions_ouvertes}}

        Historique des 2 derniers COSUI:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D6 CODIR

    static let d6_codir = Seed(
        name: "CODIR",
        kind: .codir,
        sections: [
            .init(title: "Synthèse stratégique", hint: "Vision haut niveau."),
            .init(title: "Décisions", hint: ""),
            .init(title: "Arbitrages", hint: "Choix entre options."),
            .init(title: "Suite", hint: "Prochaines étapes au niveau direction.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        CODIR · {{date}}

        Actions overdue (alertes top):
        {{actions_overdue}}

        Dernier CODIR:
        {{historique_n}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )

    // MARK: - D7 Préparation

    static let d7_preparation = Seed(
        name: "Préparation",
        kind: .preparation,
        sections: [
            .init(title: "Objectifs", hint: "Ce qu'on cherche à obtenir."),
            .init(title: "Points à aborder", hint: ""),
            .init(title: "Questions", hint: ""),
            .init(title: "Documents pertinents", hint: "Liens / refs.")
        ],
        historyMode: .lastN,
        historyN: 1,
        historyK: 0,
        promptBody: """
        Préparation: {{title}} · {{date}}

        Dernier rapport pertinent:
        {{historique_n}}

        {{custom_prompt}}

        Notes utilisateur:
        {{notes}}
        """
    )

    // MARK: - D8 Restitution / Démo

    static let d8_restitution = Seed(
        name: "Restitution / Démo",
        kind: .restitution,
        sections: [
            .init(title: "Contexte", hint: "Ce qu'on présente et pourquoi."),
            .init(title: "Démo", hint: "Ce qui a été montré."),
            .init(title: "Feedbacks", hint: "Retours du public."),
            .init(title: "Suite", hint: "Prochaines actions identifiées.")
        ],
        historyMode: .none,
        historyN: 0,
        historyK: 0,
        promptBody: """
        Restitution {{project.name}} · {{date}} · Audience: {{participants}}

        {{custom_prompt}}

        Transcription:
        {{transcript}}

        Notes:
        {{notes}}
        """
    )
}
```

- [ ] **Step 4: Call seed in `repairStoreIfNeeded`**

In `OneToOne/OneToOneApp.swift`, locate `repairStoreIfNeeded()`. Inside the `do` block, just before the closing `}` (after the existing `deduplicate*` calls), add:

```swift
            BuiltInTemplates.seedIfNeeded(in: context)
            try context.save()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter BuiltInTemplatesTests 2>&1 | tail -10`
Expected: 4 tests pass.

- [ ] **Step 6: Run full suite**

Run: `swift test 2>&1 | tail -5`
Expected: green.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Services/BuiltInTemplates.swift OneToOne/OneToOneApp.swift Tests/BuiltInTemplatesTests.swift
git commit -m "feat(template): 8 built-in templates + idempotent startup seeding"
```

---

## Task 4: `TemplateVariableResolver` (pure helper) + tests

**Files:**
- Create: `OneToOne/Services/ReportTemplating.swift`
- Test: `Tests/TemplateVariableResolverTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TemplateVariableResolverTests.swift`:

```swift
import XCTest
import SwiftData
@testable import OneToOne

@MainActor
final class TemplateVariableResolverTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
    }

    func test_substitutes_simpleMeetingFields() {
        let m = Meeting(title: "Sync", date: Date(timeIntervalSince1970: 1_700_000_000))
        m.kind = .oneToOne
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "T:{{title}} K:{{kind}}",
            for: m, in: context
        )
        XCTAssertTrue(resolved.contains("T:Sync"))
        XCTAssertTrue(resolved.contains("K:1:1 Collaborateur") || resolved.contains("K:oneToOne"))
    }

    func test_unknownVariable_isLeftLiteral() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Hello {{not_a_var}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Hello {{not_a_var}}")
    }

    func test_projectVar_emptyWhenNoProject() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Projet:{{project.name}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Projet:")
    }

    func test_projectVar_filledWhenProject() throws {
        let proj = Project(code: "PX", name: "MyProj", domain: "D", phase: "Build")
        context.insert(proj)
        let m = Meeting(title: "X", date: Date())
        m.project = proj
        context.insert(m)
        try context.save()
        let resolved = TemplateVariableResolver.resolve(
            prompt: "Projet:{{project.name}} ({{project.code}})",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "Projet:MyProj (PX)")
    }

    func test_collabVar_emptyWhenNoCollab() {
        let m = Meeting(title: "X", date: Date())
        context.insert(m)
        let resolved = TemplateVariableResolver.resolve(
            prompt: "C:{{collab.name}}",
            for: m, in: context
        )
        XCTAssertEqual(resolved, "C:")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TemplateVariableResolverTests 2>&1 | tail -10`
Expected: compile failure — `TemplateVariableResolver` undefined.

- [ ] **Step 3: Implement the resolver**

Create `OneToOne/Services/ReportTemplating.swift`:

```swift
import Foundation
import SwiftData

/// Resolves `{{variable}}` placeholders against a Meeting + ModelContext.
///
/// Unknown variables are left literal (e.g. `{{foo}}` stays as `{{foo}}`)
/// and logged once per resolve call. Each resolver is responsible for its
/// own truncation cap (see spec §4 table).
enum TemplateVariableResolver {

    private static let pattern: NSRegularExpression = {
        // Allow lowercase letters, digits, underscores, dots inside `{{}}`.
        try! NSRegularExpression(pattern: #"\{\{([a-z0-9_.]+)\}\}"#)
    }()

    @MainActor
    static func resolve(prompt: String,
                        for meeting: Meeting,
                        in context: ModelContext,
                        now: Date = Date()) -> String {
        var unresolved: Set<String> = []
        let range = NSRange(prompt.startIndex..., in: prompt)
        let matches = pattern.matches(in: prompt, range: range)

        // Iterate in reverse so substitutions don't shift earlier indices.
        var output = prompt
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let nameRange = Range(match.range(at: 1), in: output),
                  let fullRange = Range(match.range(at: 0), in: output) else { continue }
            let name = String(output[nameRange])
            if let value = resolveOne(name: name, meeting: meeting, context: context, now: now) {
                output.replaceSubrange(fullRange, with: value)
            } else {
                unresolved.insert(name)
            }
        }

        if !unresolved.isEmpty {
            print("[TemplateVariableResolver] unresolved vars: \(unresolved.sorted())")
        }
        return output
    }

    // MARK: - Per-variable resolution

    @MainActor
    private static func resolveOne(name: String,
                                   meeting: Meeting,
                                   context: ModelContext,
                                   now: Date) -> String? {
        switch name {

        // --- Meeting basics
        case "title":          return meeting.title
        case "date":           return Self.formatDate(meeting.date)
        case "duration":       return Self.formatDuration(meeting.effectiveDuration)
        case "kind":           return meeting.kind.label
        case "participants":   return meeting.participantsDescription
        case "transcript":     return meeting.mergedTranscript
        case "notes":          return meeting.notes
        case "custom_prompt":  return meeting.customPrompt

        // --- Project
        case "project.name":    return meeting.project?.name ?? ""
        case "project.code":    return meeting.project?.code ?? ""
        case "project.entity":  return meeting.project?.entity?.name ?? ""
        case "project.phase":   return meeting.project?.phase ?? ""
        case "project.status":  return meeting.project?.status ?? ""
        case "project.planning": return meeting.project?.planningText ?? ""
        case "project.actions_ouvertes": return Self.actionsList(for: meeting.project, in: context)
        case "project.dernier_rapport":  return Self.dernierRapport(for: meeting.project, excluding: meeting, in: context)
        case "project.historique_n":     return ""  // populated externally by HistoryContextBuilder

        // --- Collab (only for .oneToOne)
        case "collab.name":  return Self.partnerCollaborator(of: meeting)?.name ?? ""
        case "collab.role":  return Self.partnerCollaborator(of: meeting)?.role ?? ""
        case "collab.email": return Self.partnerCollaborator(of: meeting)?.email ?? ""
        case "collab.actions_ouvertes": return Self.actionsList(for: Self.partnerCollaborator(of: meeting), in: context)
        case "collab.dernier_1to1":     return Self.dernier1to1(for: Self.partnerCollaborator(of: meeting), excluding: meeting, in: context)
        case "collab.notes":            return Self.collabNotes(for: Self.partnerCollaborator(of: meeting), in: context)

        // --- Manager
        case "manager.items_actuels": return Self.managerItemsActuels(in: context)
        case "manager.dernier_cr":    return Self.managerDernierCR(in: context)

        // --- Global
        case "actions_overdue":   return Self.actionsOverdue(in: context, now: now)
        case "actions_du_jour":   return Self.actionsDuJour(in: context, now: now)
        case "historique_n":      return ""  // populated externally
        case "contexte_general":  return Self.contexteGeneral(in: context, now: now)
        case "date_now":          return Self.formatDate(now)
        case "semaine":           return Self.formatWeek(now)
        case "mois":              return Self.formatMonth(now)

        default:                  return nil
        }
    }

    // MARK: - Sub-resolvers

    @MainActor
    private static func partnerCollaborator(of meeting: Meeting) -> Collaborator? {
        guard meeting.kind == .oneToOne || meeting.kind == .manager else { return nil }
        return meeting.participants.first
    }

    @MainActor
    private static func actionsList(for project: Project?, in context: ModelContext) -> String {
        guard let project else { return "" }
        let pid = project.persistentModelID
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { !$0.isCompleted && $0.project?.persistentModelID == pid }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(30)))
    }

    @MainActor
    private static func actionsList(for collab: Collaborator?, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let cid = collab.persistentModelID
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { !$0.isCompleted && $0.collaborator?.persistentModelID == cid }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(30)))
    }

    @MainActor
    private static func renderActions(_ tasks: [ActionTask]) -> String {
        guard !tasks.isEmpty else { return "(aucune)" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return tasks.map { t in
            let due = t.dueDate.map { " (échéance \(fmt.string(from: $0)))" } ?? ""
            return "- \(t.title)\(due)"
        }.joined(separator: "\n")
    }

    @MainActor
    private static func dernierRapport(for project: Project?, excluding currentMeeting: Meeting, in context: ModelContext) -> String {
        guard let project else { return "" }
        let pid = project.persistentModelID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.project?.persistentModelID == pid },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard let last = all.first(where: { $0.persistentModelID != currentMeeting.persistentModelID && !$0.summary.isEmpty }) else { return "" }
        return Self.truncate(last.summary, to: 2500)
    }

    @MainActor
    private static func dernier1to1(for collab: Collaborator?, excluding currentMeeting: Meeting, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard let last = all.first(where: { m in
            m.persistentModelID != currentMeeting.persistentModelID
                && m.kind == .oneToOne
                && m.participants.contains(where: { $0.persistentModelID == collab.persistentModelID })
                && !m.summary.isEmpty
        }) else { return "" }
        return Self.truncate(last.summary, to: 2000)
    }

    @MainActor
    private static func collabNotes(for collab: Collaborator?, in context: ModelContext) -> String {
        guard let collab else { return "" }
        let cid = collab.persistentModelID
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.collaborator?.persistentModelID == cid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let notes = (try? context.fetch(descriptor)) ?? []
        return notes.prefix(5).map { "- \(Self.truncate($0.body, to: 200))" }.joined(separator: "\n")
    }

    @MainActor
    private static func managerItemsActuels(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<ManagerReportItem>(
            predicate: #Predicate { $0.archivedAt == nil && !$0.isCompleted },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.prefix(20).map { "- [\($0.category)] \(Self.firstLine($0.elaboratedText.isEmpty ? $0.rawSnippet : $0.elaboratedText))" }
            .joined(separator: "\n")
    }

    @MainActor
    private static func managerDernierCR(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<ManagerMeetingReport>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        let reports = (try? context.fetch(descriptor)) ?? []
        guard let last = reports.first else { return "" }
        return Self.truncate(last.generatedSummary, to: 2500)
    }

    @MainActor
    private static func actionsOverdue(in context: ModelContext, now: Date) -> String {
        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        let overdue = urgent.filter { ($0.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: now) }
        return Self.renderActions(Array(overdue.prefix(10)))
    }

    @MainActor
    private static func actionsDuJour(in context: ModelContext, now: Date) -> String {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let descriptor = FetchDescriptor<ActionTask>(
            predicate: #Predicate { task in
                !task.isCompleted && task.dueDate != nil
                    && task.dueDate! >= startOfToday
                    && task.dueDate! < endOfToday
            }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return Self.renderActions(Array(tasks.prefix(10)))
    }

    @MainActor
    private static func contexteGeneral(in context: ModelContext, now: Date) -> String {
        let urgent = UrgentActionsSelector.qualifying(in: context, now: now)
        let actions = Self.renderActions(Array(urgent.prefix(5)))

        let alertDescriptor = FetchDescriptor<ProjectAlert>()
        let allAlerts = (try? context.fetch(alertDescriptor)) ?? []
        let alerts = allAlerts
            .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
            .prefix(3)
        let alertsText = alerts.isEmpty
            ? "(aucune)"
            : alerts.map { "- [\($0.severity)] \(Self.firstLine($0.title))" }.joined(separator: "\n")

        let cal = Calendar.current
        let fortnightAgo = cal.date(byAdding: .day, value: -14, to: now) ?? now
        let meetingDescriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.date >= fortnightAgo && $0.project != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let recentMeetings = (try? context.fetch(meetingDescriptor)) ?? []
        var seenProjectIDs: Set<PersistentIdentifier> = []
        var topProjects: [Project] = []
        for m in recentMeetings {
            guard let p = m.project else { continue }
            if seenProjectIDs.insert(p.persistentModelID).inserted {
                topProjects.append(p)
                if topProjects.count == 3 { break }
            }
        }
        let projectsText = topProjects.isEmpty
            ? "(aucun)"
            : topProjects.map { "- \($0.name) (\($0.code))" }.joined(separator: "\n")

        return """
        Actions urgentes:
        \(actions)

        Alertes actives:
        \(alertsText)

        Activité récente:
        \(projectsText)
        """
    }

    // MARK: - Formatting

    private static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    private static func formatWeek(_ d: Date) -> String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: d)
        return "S\(week)"
    }

    private static func formatMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }

    private static func truncate(_ s: String, to max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    private static func firstLine(_ s: String) -> String {
        s.components(separatedBy: .newlines).first ?? s
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TemplateVariableResolverTests 2>&1 | tail -10`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift Tests/TemplateVariableResolverTests.swift
git commit -m "feat(template): TemplateVariableResolver — resolves all {{variables}}"
```

---

## Task 5: `HistoryContextBuilder` + tests

**Files:**
- Modify: `OneToOne/Services/ReportTemplating.swift` (append `HistoryContextBuilder`)
- Test: `Tests/HistoryContextBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HistoryContextBuilderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HistoryContextBuilderTests 2>&1 | tail -10`
Expected: compile failure — `HistoryContextBuilder` undefined.

- [ ] **Step 3: Append `HistoryContextBuilder` to ReportTemplating.swift**

At the bottom of `OneToOne/Services/ReportTemplating.swift` (after the closing `}` of `TemplateVariableResolver`), append:

```swift

/// Produces the bloc injected into `{{historique_n}}` according to the
/// template's history mode (none/lastN/rag/hybrid).
enum HistoryContextBuilder {

    @MainActor
    static func build(for meeting: Meeting,
                      template: ReportTemplate,
                      in context: ModelContext) -> String {
        switch template.historyMode {
        case .none:
            return ""
        case .lastN:
            return buildLastN(for: meeting, n: template.historyN, in: context)
        case .rag:
            // Embeddings infra not generalised yet — fallback to lastN(1).
            return buildLastN(for: meeting, n: max(template.historyN, 1), in: context)
        case .hybrid:
            // Same fallback — RAG portion is no-op until embeddings infra is generalised.
            return buildLastN(for: meeting, n: max(template.historyN, 1), in: context)
        }
    }

    // MARK: - lastN

    @MainActor
    private static func buildLastN(for meeting: Meeting, n: Int, in context: ModelContext) -> String {
        guard n > 0 else { return "" }
        let scope = peerMeetings(for: meeting, in: context)
            .filter { $0.persistentModelID != meeting.persistentModelID }
            .filter { !$0.summary.isEmpty }
        let top = Array(scope.prefix(n))
        guard !top.isEmpty else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        return top.map { m in
            let truncated = m.summary.count > 2000
                ? String(m.summary.prefix(1999)) + "…"
                : m.summary
            return "--- \(fmt.string(from: m.date)) · \(m.title) ---\n\(truncated)"
        }.joined(separator: "\n\n")
    }

    /// Returns Meetings in the scope of `meeting.kind`, sorted desc by date.
    @MainActor
    private static func peerMeetings(for meeting: Meeting, in context: ModelContext) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        switch meeting.kind {
        case .project:
            guard let pid = meeting.project?.persistentModelID else { return all }
            return all.filter { $0.project?.persistentModelID == pid }
        case .oneToOne:
            guard let partner = meeting.participants.first else { return [] }
            let cid = partner.persistentModelID
            return all.filter { m in
                m.kind == .oneToOne
                    && m.participants.contains(where: { $0.persistentModelID == cid })
            }
        case .manager:
            return all.filter { $0.kind == .manager }
        case .global, .work:
            return all
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HistoryContextBuilderTests 2>&1 | tail -10`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift Tests/HistoryContextBuilderTests.swift
git commit -m "feat(template): HistoryContextBuilder — lastN scope-aware previous summaries"
```

---

## Task 6: `AIReportService.generate(meeting:settings:onProgress:)` template-aware entry

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Add the new entry**

In `OneToOne/Services/AIReportService.swift`, AFTER the existing `static func generate(mergedTranscript:meetingKind:...)` method, append:

```swift

    /// Template-driven report generation. Resolves `meeting.reportTemplate`
    /// (or default by kind), injects history + variables, then calls
    /// `AIClient`. Returns parsed `MeetingReportData`.
    @MainActor
    static func generate(
        meeting: Meeting,
        in context: ModelContext,
        settings: AppSettings,
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> MeetingReportData {
        let template = meeting.reportTemplate ?? defaultTemplate(for: meeting.kind, in: context)
        let history = template.map { HistoryContextBuilder.build(for: meeting, template: $0, in: context) } ?? ""
        let body = template?.promptBody ?? ""
        let sections = template?.sections ?? []

        // 1. Resolve {{vars}} in the body
        var resolved = TemplateVariableResolver.resolve(prompt: body, for: meeting, in: context)

        // 2. Substitute {{historique_n}} with the history bloc
        resolved = resolved.replacingOccurrences(of: "{{historique_n}}", with: history)
        resolved = resolved.replacingOccurrences(of: "{{project.historique_n}}", with: history)

        // 3. Append the sections schema so the LLM structures its output
        var sectionsBlock = ""
        if !sections.isEmpty {
            sectionsBlock = "\n\n# Sections attendues (respecte cet ordre, un # par titre):\n"
            for (idx, s) in sections.enumerated() {
                sectionsBlock += "\(idx + 1). **\(s.title)** — \(s.hint)\n"
            }
        }

        let finalPrompt = """
        Tu es l'assistant de synthèse de OneToOne.

        \(resolved)
        \(sectionsBlock)

        Produis un compte-rendu en markdown structuré autour des sections demandées,
        en français, concis et factuel.
        """

        reportLog.info("generate(meeting): template=\(template?.name ?? "default", privacy: .public) historyChars=\(history.count)")
        let raw = try await AIClient.send(prompt: finalPrompt, settings: settings, onProgress: onProgress)
        return parse(raw)
    }

    @MainActor
    private static func defaultTemplate(for kind: MeetingKind, in context: ModelContext) -> ReportTemplate? {
        let templateKind: ReportTemplateKind
        switch kind {
        case .global:    templateKind = .general
        case .oneToOne:  templateKind = .oneToOne
        case .manager:   templateKind = .manager
        case .project:   templateKind = .copil
        case .work:      templateKind = .general
        }
        let raw = templateKind.rawValue
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true && $0.kindRaw == raw && !$0.isArchived }
        )
        return (try? context.fetch(descriptor))?.first
    }
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -10`
Expected: clean.

- [ ] **Step 3: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(report): template-driven generate(meeting:settings:) entry"
```

---

## Task 7: Wire MeetingView "Rapport" to the template-driven entry

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Locate the existing generate call**

Run: `grep -n "AIReportService.generate" OneToOne/Views/MeetingView.swift`
Expected: 1+ callsite.

- [ ] **Step 2: Replace the call**

Replace the existing `AIReportService.generate(mergedTranscript: ..., meetingKind: ..., ...)` invocation in MeetingView (likely inside `generateReport()` or similar) with:

```swift
        let report = try await AIReportService.generate(
            meeting: meeting,
            in: context,
            settings: settings,
            onProgress: { delta in onProgress?(delta) }
        )
```

Replace any local progress closure parameter naming accordingly. Keep the surrounding code (`isGeneratingReport`, save, etc.) unchanged.

If the original call passes other params like `customPrompt`, `historicalContext`, `attachmentsContext` — drop them: the new entry pulls them from the meeting + template. Document the removed params in the commit body if you want a clean log.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(view): MeetingView uses template-driven generate"
```

---

## Task 8: MeetingView "Template" picker

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift` (or the appropriate header view if extracted)

- [ ] **Step 1: Locate the meeting header / toolbar area**

Run: `grep -n "Rapport\|generateReport\|.toolbar" OneToOne/Views/MeetingView.swift | head -10`
Identify where the existing "Rapport" button sits.

- [ ] **Step 2: Add a Template picker next to the Rapport button**

Insert a SwiftUI Menu near the Rapport button. The picker shows compatible templates plus a "Tous" submenu:

```swift
@Query private var allTemplates: [ReportTemplate]

private var compatibleTemplates: [ReportTemplate] {
    let mapping: [MeetingKind: ReportTemplateKind] = [
        .global: .general, .oneToOne: .oneToOne, .manager: .manager,
        .project: .copil, .work: .general
    ]
    let preferred = mapping[meeting.kind] ?? .general
    return allTemplates
        .filter { !$0.isArchived }
        .sorted { lhs, rhs in
            let li = lhs.kind == preferred ? 0 : 1
            let ri = rhs.kind == preferred ? 0 : 1
            if li != ri { return li < ri }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
}

@ViewBuilder
private var templatePickerButton: some View {
    Menu {
        Button("Auto (selon type)") {
            meeting.reportTemplate = nil
            saveContext()
        }
        Divider()
        ForEach(compatibleTemplates) { t in
            Button(t.name) {
                meeting.reportTemplate = t
                saveContext()
            }
        }
    } label: {
        Label(meeting.reportTemplate?.name ?? "Auto", systemImage: "doc.text")
            .font(.caption)
    }
    .menuStyle(.borderlessButton)
    .help("Template de rapport — modifie la structure du compte-rendu généré")
}
```

Then place `templatePickerButton` in the same HStack/Toolbar as the existing Rapport button.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(view): MeetingView Template picker — Auto + compatibles"
```

---

## Task 9: Settings — `ReportTemplateEditorView` (CRUD + variables palette)

**Files:**
- Create: `OneToOne/Views/Settings/ReportTemplateEditorView.swift`
- Create: `OneToOne/Views/Settings/ReportTemplateListView.swift`
- Modify: `OneToOne/Views/SettingsView.swift` (add new GroupBox / section linking to the list)

- [ ] **Step 1: Create the list view**

Create `OneToOne/Views/Settings/ReportTemplateListView.swift`:

```swift
import SwiftUI
import SwiftData

/// CRUD list of ReportTemplates with built-in vs custom separation.
struct ReportTemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ReportTemplate.name) private var templates: [ReportTemplate]
    @State private var editing: ReportTemplate?
    @State private var search: String = ""

    private var filtered: [ReportTemplate] {
        guard !search.isEmpty else { return templates.filter { !$0.isArchived } }
        return templates.filter { !$0.isArchived && $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var builtIns: [ReportTemplate] {
        filtered.filter { $0.isBuiltIn }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var customs: [ReportTemplate] {
        filtered.filter { !$0.isBuiltIn }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Rechercher…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let t = ReportTemplate(name: "Nouveau template", kind: .custom)
                    context.insert(t)
                    try? context.save()
                    editing = t
                } label: {
                    Label("Nouveau", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if !builtIns.isEmpty {
                Text("Templates fournis").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(builtIns) { t in row(t) }
            }
            if !customs.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Templates personnalisés").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(customs) { t in row(t) }
            }
        }
        .sheet(item: $editing) { t in
            ReportTemplateEditorView(template: t) { editing = nil }
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    @ViewBuilder
    private func row(_ t: ReportTemplate) -> some View {
        HStack {
            Image(systemName: t.kind.sfSymbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(.body)
                    .italic(t.isBuiltIn)
                Text(t.kind.label).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Modifier") { editing = t }
                .buttonStyle(.bordered).controlSize(.small)
            Button("Dupliquer") {
                let copy = ReportTemplate(
                    name: t.name + " (copie)",
                    kind: t.kind,
                    promptBody: t.promptBody,
                    sections: t.sections,
                    historyMode: t.historyMode,
                    historyN: t.historyN,
                    historyK: t.historyK,
                    isBuiltIn: false
                )
                context.insert(copy)
                try? context.save()
            }
            .buttonStyle(.bordered).controlSize(.small)
            if t.isBuiltIn {
                Button("Restaurer défaut") {
                    if let seed = BuiltInTemplates.dict[t.name] {
                        t.promptBody = seed.promptBody
                        t.sections = seed.sections
                        t.historyMode = seed.historyMode
                        t.historyN = seed.historyN
                        t.historyK = seed.historyK
                        try? context.save()
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button(role: .destructive) {
                    context.delete(t)
                    try? context.save()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Create the editor sheet**

Create `OneToOne/Views/Settings/ReportTemplateEditorView.swift`:

```swift
import SwiftUI
import SwiftData

/// Sheet to edit a ReportTemplate's name, kind, sections, history mode,
/// and prompt body. A clickable variables palette inserts {{var}} at cursor.
struct ReportTemplateEditorView: View {
    @Bindable var template: ReportTemplate
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var sections: [TemplateSection] = []
    @State private var promptBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Nom du template", text: $template.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Picker("Catégorie", selection: Binding(
                    get: { template.kind },
                    set: { template.kind = $0 }
                )) {
                    ForEach(ReportTemplateKind.allCases) { k in
                        Label(k.label, systemImage: k.sfSymbol).tag(k)
                    }
                }
                .frame(maxWidth: 220)
                Spacer()
                Button("Fermer") { save(); onClose() }
                    .keyboardShortcut(.cancelAction)
            }

            historyConfigRow

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Sections").font(.headline)
                    sectionsEditor
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading) {
                    Text("Variables").font(.headline)
                    variablesPalette
                }
                .frame(width: 220)
            }

            Text("Prompt").font(.headline)
            TextEditor(text: $promptBody)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3))
                )
        }
        .padding(16)
        .onAppear {
            sections = template.sections
            promptBody = template.promptBody
        }
        .onDisappear { save() }
    }

    private var historyConfigRow: some View {
        HStack(spacing: 16) {
            Picker("Historique", selection: Binding(
                get: { template.historyMode },
                set: { template.historyMode = $0 }
            )) {
                ForEach(HistoryMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .frame(maxWidth: 280)

            Stepper("N: \(template.historyN)", value: $template.historyN, in: 0...5)
            Stepper("K: \(template.historyK)", value: $template.historyK, in: 0...20)
        }
    }

    private var sectionsEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($sections) { $s in
                HStack {
                    TextField("Titre", text: $s.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    TextField("Indication pour l'IA", text: $s.hint)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        sections.removeAll { $0.id == s.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                sections.append(TemplateSection(title: "Nouvelle section", hint: ""))
            } label: {
                Label("Ajouter une section", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var variablesPalette: some View {
        let groups: [(String, [String])] = [
            ("Réunion", ["title","date","duration","kind","participants","transcript","notes","custom_prompt"]),
            ("Projet", ["project.name","project.code","project.entity","project.phase","project.status","project.planning","project.actions_ouvertes","project.dernier_rapport","project.historique_n"]),
            ("Collab", ["collab.name","collab.role","collab.email","collab.actions_ouvertes","collab.dernier_1to1","collab.notes"]),
            ("Manager", ["manager.items_actuels","manager.dernier_cr"]),
            ("Global", ["actions_overdue","actions_du_jour","historique_n","contexte_general","date_now","semaine","mois"])
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.0) { group in
                    Text(group.0).font(.caption.bold()).foregroundColor(.secondary)
                    ForEach(group.1, id: \.self) { name in
                        Button {
                            promptBody.append("{{\(name)}}")
                        } label: {
                            HStack {
                                Text("{{\(name)}}").font(.caption.monospaced())
                                Spacer()
                                Image(systemName: "plus.circle").foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func save() {
        template.sections = sections
        template.promptBody = promptBody
        template.updatedAt = Date()
        try? context.save()
    }
}
```

- [ ] **Step 3: Add a new GroupBox in `SettingsView`**

In `OneToOne/Views/SettingsView.swift`, near the existing template / IA configuration section, add:

```swift
                GroupBox("Templates de rapport") {
                    ReportTemplateListView()
                        .padding(8)
                }
```

Place it after the "Calendrier & menubar" GroupBox or wherever it fits the existing flow.

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -5`
Expected: clean. If `Stepper` complains about `Int` Bindings or `@Bindable var template` inside a sheet — wrap with explicit `Binding(get:set:)` as shown for `historyMode`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Settings/ReportTemplateListView.swift OneToOne/Views/Settings/ReportTemplateEditorView.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): ReportTemplate CRUD list + editor with variables palette"
```

---

## Task 10: Final integration check + manual verification

**Files:** none.

- [ ] **Step 1: Clean build + full tests**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -10
```

Both clean.

- [ ] **Step 2: Launch the app**

```bash
swift run 2>&1 | head -20
```

At first launch, console should log: `Reparation SwiftData: …` (existing) — and `BuiltInTemplates.seedIfNeeded` should silently insert 8 rows.

- [ ] **Step 3: Manual checklist**

| # | Check |
|---|-------|
| 1 | Settings → "Templates de rapport" → 8 built-in rows visible (italic name) |
| 2 | Open MeetingView → Template picker shows compatible templates first |
| 3 | Select a non-default template → `meeting.reportTemplate` persists across reopen |
| 4 | Generate Rapport → output structured per the selected template's sections |
| 5 | Create a custom template via Settings → appears in custom section + selectable in Meeting |
| 6 | Click "Restaurer défaut" on an edited built-in → promptBody resets |
| 7 | Cannot delete built-in (no trash button) |
| 8 | `{{project.planning}}` populated when Project.planningText is set |
| 9 | Variables palette: clicking inserts `{{name}}` at cursor in editor |
| 10 | Auto choice (no template selected) → falls back to default by kind |

- [ ] **Step 4: Note defects**

For each failure, create a small follow-up commit. Don't bundle them with this plan's commits unless they're a direct regression from these tasks.

---

## Out-of-scope notes

- RAG / hybrid modes: code accepts the setting but currently downgrades to lastN (no embedding scan). Implement when `TranscriptChunk` embedding fetch is generalised (see spec §11).
- Variable pipes/filters (`{{actions | filter(...)}}`) deferred.
- Template import/export JSON deferred.
- `Project.planningText` editor UI is not part of this plan — user edits via Settings → Projects → Project detail (existing Form). If the project detail form doesn't yet expose `planningText`, add a small `TextEditor` for it in a follow-up commit; that's a tiny addition but not required to make templates work.

---

## Self-review notes (author)

- **Spec coverage**: §3 model → Task 1+2; §4 variables → Task 4; §5 history → Task 5; §6 built-ins → Task 3; §7.1 UI Settings → Task 9; §7.2 MeetingView picker → Task 8; §7.3 generation flow → Task 6 + 7; §8 migration/seeding → Task 3 step 4. §10 tests covered by Task 1, 3, 4, 5 + Task 10 manual.
- **Type consistency**: `ReportTemplate`, `ReportTemplateKind`, `TemplateSection`, `HistoryMode`, `BuiltInTemplates.Seed`, `TemplateVariableResolver.resolve(prompt:for:in:now:)`, `HistoryContextBuilder.build(for:template:in:)`, `AIReportService.generate(meeting:in:settings:onProgress:)` — all referenced consistently from Task 1 through Task 9.
- **Placeholder scan**: every step contains the actual code or grep command. The two "if existing field doesn't exist, add it" caveats (project planning UI, original generate arg list in MeetingView) are bounded conditional adjustments, not open-ended.
