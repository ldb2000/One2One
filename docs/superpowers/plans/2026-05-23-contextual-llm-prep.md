# Contextual LLM Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Injecter dans le prompt 1:1 LLM le contexte projets dont le collab partenaire est architecte technique ou chef de projet (résumés top-3 + actions ouvertes). Ajouter une colonne `Projet` conditionnelle au tableau canonique "Plan d'actions" quand les actions s'étalent sur plusieurs projets.

**Architecture:** Nouveau `ProjectsContextBuilder` (à côté de `HistoryContextBuilder`) qui assemble un bloc texte structuré par projet. Nouvelle variable template `{{collab.projects_context}}` dans `TemplateVariableResolver`. `AIReportService.generate` détecte le placeholder ; si absent et contexte non-vide, append en queue (pattern existant de `{{historique_n}}`). `ReportHTMLBuilder.renderActionsBlock` gagne un paramètre `includeProjectColumn: Bool` calculé en amont.

**Tech Stack:** Swift 6, SwiftData, XCTest.

---

## File map

| Path | Change |
|---|---|
| `OneToOne/Services/ReportTemplating.swift` (modify) | +`ProjectsContextBuilder` enum + case `collab.projects_context` dans `resolveOne` |
| `OneToOne/Services/AIReportService.swift` (modify) | Détection `{{collab.projects_context}}` + append fallback |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` (modify) | Colonne `Projet` conditionnelle dans `renderActionsBlock` |
| `OneToOne/Services/BuiltInTemplates.swift` (modify) | `d2_oneToOne.promptBody` mis à jour + revision bump 2 → 3 |
| `Tests/ProjectsContextBuilderTests.swift` (new) | Tests TDD du builder |
| `Tests/ReportHTMLBuilderTests.swift` (modify) | +3 tests colonne Projet conditionnelle |

Total : 4 modifs, 1 nouveau test, +3 tests existants.

**Types existants utilisés** :
- `Collaborator.projectsAsArchitect / projectsAsManager` (sub-projet 1)
- `Project.code / name / status / technicalArchitect / projectManager / tasks / isArchived`
- `Meeting.kind / participants / project` ; relation `Meeting.project` existe ✓
- `ActionTask.dueDate / isCompleted / collaborator / unresolvedAssigneeName / project`
- `ProjectStatusPalette.sortedByStatus(_:)` (sub-projet 2a)
- `MeetingKind.oneToOne` ✓
- Pattern existant : `Self.partnerCollaborator(of: meeting)` dans `TemplateVariableResolver`

---

### Task 1: ProjectsContextBuilder (TDD)

**Files:**
- Create: `Tests/ProjectsContextBuilderTests.swift`
- Modify: `OneToOne/Services/ReportTemplating.swift`

- [ ] **Step 1: Écrire les tests failing**

Dans `Tests/ProjectsContextBuilderTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

final class ProjectsContextBuilderTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_nonOneToOneMeeting_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "COPIL", date: Date())
        m.kindRaw = MeetingKind.project.rawValue
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_oneToOneWithoutPartner_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "1:1 vide", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = []
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_partnerWithoutProjects_returnsEmpty() throws {
        let ctx = try makeContext()
        let p = Collaborator(name: "Alice DUPONT")
        ctx.insert(p)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [p]
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.build(for: m, in: ctx), "")
    }

    @MainActor
    func test_oneArchitectProject_includesHeaderAndRole() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "NEVIDIS", name: "Projet Névidis", domain: "Infra")
        proj.status = "Yellow"
        proj.technicalArchitect = alice
        ctx.insert(proj)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        XCTAssertTrue(out.contains("## NEVIDIS · Projet Névidis (statut: Yellow)"))
        XCTAssertTrue(out.contains("Architecte technique"))
        XCTAssertTrue(out.contains("Alice DUPONT"))
    }

    @MainActor
    func test_includesTop3SummariesAndOpenActions() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "COOG", name: "Migration Coog", domain: "Infra")
        proj.status = "Red"
        proj.technicalArchitect = alice
        ctx.insert(proj)

        let cal = Calendar.current
        for i in 0..<4 {
            let date = cal.date(byAdding: .day, value: -i * 7, to: Date())!
            let m = Meeting(title: "Comité semaine \(i)", date: date)
            m.kindRaw = MeetingKind.project.rawValue
            m.project = proj
            m.summary = "Résumé semaine \(i)"
            ctx.insert(m)
        }

        let open = ActionTask(title: "Migrer DD", dueDate: nil)
        open.project = proj
        open.collaborator = alice
        ctx.insert(open)
        let done = ActionTask(title: "Action close", dueDate: nil)
        done.isCompleted = true
        done.project = proj
        ctx.insert(done)

        let current = Meeting(title: "1:1 Alice", date: Date())
        current.kindRaw = MeetingKind.oneToOne.rawValue
        current.participants = [alice]
        ctx.insert(current)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: current, in: ctx)
        // 3 derniers résumés présents
        XCTAssertTrue(out.contains("Résumé semaine 0"))
        XCTAssertTrue(out.contains("Résumé semaine 1"))
        XCTAssertTrue(out.contains("Résumé semaine 2"))
        XCTAssertFalse(out.contains("Résumé semaine 3"))
        // Action ouverte présente, action close absente
        XCTAssertTrue(out.contains("Migrer DD"))
        XCTAssertFalse(out.contains("Action close"))
    }

    @MainActor
    func test_archivedProjectExcluded() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let proj = Project(code: "OLD", name: "Vieux projet", domain: "Legacy")
        proj.technicalArchitect = alice
        proj.isArchived = true
        ctx.insert(proj)
        let m = Meeting(title: "1:1 Alice", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        XCTAssertEqual(out, "")
    }

    @MainActor
    func test_sortRedYellowGreenAndTruncatesAtFive() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let statuses = ["Green", "Red", "Yellow", "Unknown", "Red", "Green", "Yellow"]
        for (i, s) in statuses.enumerated() {
            let p = Project(code: "P\(i)", name: "Projet \(i)", domain: "X")
            p.status = s
            p.technicalArchitect = alice
            ctx.insert(p)
        }
        let m = Meeting(title: "1:1", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.build(for: m, in: ctx)
        // Max 5 projets injectés
        let countHeaders = out.components(separatedBy: "## P").count - 1
        XCTAssertLessThanOrEqual(countHeaders, 5)
        // Premier projet listé doit être Red
        let firstRedIdx = out.range(of: "(statut: Red)")?.lowerBound
        let firstYellowIdx = out.range(of: "(statut: Yellow)")?.lowerBound
        XCTAssertNotNil(firstRedIdx)
        if let r = firstRedIdx, let y = firstYellowIdx {
            XCTAssertTrue(r < y, "Red doit apparaître avant Yellow")
        }
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'ProjectsContextBuilder' in scope`.

- [ ] **Step 3: Implémenter ProjectsContextBuilder dans ReportTemplating.swift**

Ajouter en fin de fichier `OneToOne/Services/ReportTemplating.swift`, après `HistoryContextBuilder` :

```swift
// MARK: - Projects context (sub-projet 2b)

/// Construit le bloc de contexte projets pour une réunion 1:1. Pour chaque
/// projet où le partenaire est architecte technique ou chef de projet :
/// statut + top-3 résumés de réunions sur ce projet + actions ouvertes.
///
/// Tronqué à ~15 000 caractères au global, max 5 projets, top 3 résumés par
/// projet (1500 chars chacun), max 10 actions ouvertes par projet.
@MainActor
enum ProjectsContextBuilder {

    private static let maxProjects: Int = 5
    private static let summariesPerProject: Int = 3
    private static let summaryMaxChars: Int = 1500
    private static let actionsPerProject: Int = 10
    private static let totalBudgetChars: Int = 15_000

    static func build(for meeting: Meeting, in context: ModelContext) -> String {
        guard meeting.kind == .oneToOne,
              let partner = meeting.participants.first else {
            return ""
        }

        // Dédup projets archi + PM via persistentModelID.
        var seen = Set<PersistentIdentifier>()
        var projects: [Project] = []
        for p in partner.projectsAsArchitect + partner.projectsAsManager {
            guard !p.isArchived else { continue }
            if seen.insert(p.persistentModelID).inserted {
                projects.append(p)
            }
        }
        guard !projects.isEmpty else { return "" }

        // Tri Red → Yellow → Green → Unknown, puis alpha.
        let sorted = ProjectStatusPalette.sortedByStatus(projects)
        let topProjects = Array(sorted.prefix(maxProjects))

        var pieces: [String] = []
        for p in topProjects {
            pieces.append(renderProject(p, partner: partner, in: context))
        }
        let full = pieces.joined(separator: "\n\n")
        if full.count <= totalBudgetChars { return full }
        // Coupe en queue, ligne complète.
        let truncated = String(full.prefix(totalBudgetChars))
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[..<lastNewline])
        }
        return truncated
    }

    @MainActor
    private static func renderProject(_ p: Project,
                                       partner: Collaborator,
                                       in context: ModelContext) -> String {
        let role = projectRole(p, partner: partner)
        var out = "## \(p.code) · \(p.name) (statut: \(p.status))\n"
        out += "Rôle de \(partner.name) : \(role)\n\n"

        // Top 3 résumés de réunions sur ce projet (récents, summary non-vide).
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allMeetings = (try? context.fetch(descriptor)) ?? []
        let projectMeetings = allMeetings.filter {
            $0.project?.persistentModelID == p.persistentModelID
                && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let topSummaries = Array(projectMeetings.prefix(summariesPerProject))
        out += "### \(summariesPerProject) derniers points discutés sur ce projet\n"
        if topSummaries.isEmpty {
            out += "(aucun historique disponible)\n"
        } else {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "d MMM yyyy"
            for m in topSummaries {
                out += "--- \(fmt.string(from: m.date)) · \(m.title) ---\n"
                let truncated = truncateAtBoundary(m.summary, max: summaryMaxChars)
                out += truncated + "\n\n"
            }
        }

        // Actions ouvertes du projet (top 10 par échéance ascendante).
        let openActions = p.tasks
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(actionsPerProject)
        out += "### Actions ouvertes sur ce projet (\(openActions.count))\n"
        if openActions.isEmpty {
            out += "(aucune action ouverte)\n"
        } else {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "d MMM yyyy"
            for t in openActions {
                let who = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
                let when = t.dueDate.map { fmt.string(from: $0) } ?? "—"
                out += "- \(t.title) — \(who), \(when)\n"
            }
        }
        return out
    }

    @MainActor
    private static func projectRole(_ p: Project, partner: Collaborator) -> String {
        let isArchi = p.technicalArchitect?.persistentModelID == partner.persistentModelID
        let isPM = p.projectManager?.persistentModelID == partner.persistentModelID
        switch (isArchi, isPM) {
        case (true, true):  return "Architecte technique et chef de projet"
        case (true, false): return "Architecte technique"
        case (false, true): return "Chef de projet"
        default:            return "—"
        }
    }

    private static func truncateAtBoundary(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        let cut = String(s.prefix(max))
        if let dot = cut.lastIndex(of: ".") {
            return String(cut[...dot]) + "…"
        }
        if let nl = cut.lastIndex(of: "\n") {
            return String(cut[..<nl]) + "…"
        }
        return cut + "…"
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -15
```
Expected: PASS 7/7.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift Tests/ProjectsContextBuilderTests.swift
git commit -m "feat(contextual-prep): ProjectsContextBuilder — résumés top-3 + actions ouvertes par projet"
```

---

### Task 2: Wire `{{collab.projects_context}}` dans TemplateVariableResolver

**Files:**
- Modify: `OneToOne/Services/ReportTemplating.swift`

- [ ] **Step 1: Localiser le switch dans resolveOne**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "case \"collab.actions_ouvertes\"\|case \"collab.dernier_1to1\"" OneToOne/Services/ReportTemplating.swift
```

- [ ] **Step 2: Ajouter le case**

Juste après le case `"collab.actions_ouvertes"` (ligne ~79), ajouter :

```swift
case "collab.projects_context":
    return ProjectsContextBuilder.build(for: meeting, in: context)
```

- [ ] **Step 3: Build + run tests existants**

```bash
swift build 2>&1 | tail -3
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -5
```
Expected: PASS 7/7.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift
git commit -m "feat(contextual-prep): variable template {{collab.projects_context}}"
```

---

### Task 3: AIReportService — fallback append si placeholder absent

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Localiser la section history append fallback**

```bash
grep -n "hasHistoryPlaceholder\|historyAppendix" OneToOne/Services/AIReportService.swift
```

- [ ] **Step 2: Ajouter le fallback projects_context**

Trouver le bloc :
```swift
let hasHistoryPlaceholder = resolved.contains("{{historique_n}}")
    || resolved.contains("{{project.historique_n}}")
…
var historyAppendix = ""
if !history.isEmpty, !hasHistoryPlaceholder {
    historyAppendix = "\n\nContexte historique (extraits de réunions précédentes) :\n\(history)\n"
}
if !additionalContext.isEmpty {
    historyAppendix += "\n\nContexte sémantique (RAG, extraits pertinents) :\n\(additionalContext)\n"
}
```

Juste après cette logique d'historyAppendix (et avant le `// 3. Documents joints` ou équivalent qui suit), ajouter :

```swift
// Fallback append du contexte projets si le template ne contient pas
// `{{collab.projects_context}}`. Si présent, TemplateVariableResolver
// a déjà fait la substitution dans `resolved`.
let hasProjectsPlaceholder = body.contains("{{collab.projects_context}}")
if !hasProjectsPlaceholder {
    let projectsBlock = ProjectsContextBuilder.build(for: meeting, in: context)
    if !projectsBlock.isEmpty {
        historyAppendix += "\n\nContexte projets affectés au collaborateur :\n\(projectsBlock)\n"
    }
}
```

**Note** : `body` est la variable locale qui stocke `template?.promptBody ?? ""`. Vérifier qu'elle est en scope à cet endroit.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(contextual-prep): fallback append projets si placeholder absent dans template"
```

---

### Task 4: ReportHTMLBuilder — colonne Projet conditionnelle (TDD)

**Files:**
- Modify: `OneToOne/Services/Report/ReportHTMLBuilder.swift`
- Modify: `Tests/ReportHTMLBuilderTests.swift`

- [ ] **Step 1: Ajouter les 3 nouveaux tests**

Dans `Tests/ReportHTMLBuilderTests.swift`, ajouter à la fin de la classe :

```swift
@MainActor
func test_oneToOneActionsTable_singleProject_noProjectColumn() throws {
    let ctx = try makeContext()
    let alice = Collaborator(name: "Alice DUPONT")
    ctx.insert(alice)
    let proj = Project(code: "P1", name: "Projet 1", domain: "X")
    ctx.insert(proj)
    let meeting = Meeting(title: "1:1 Alice", date: Date())
    meeting.kindRaw = MeetingKind.oneToOne.rawValue
    meeting.participants = [alice]
    meeting.summary = "x"
    ctx.insert(meeting)
    let t1 = ActionTask(title: "Tâche 1", dueDate: nil)
    t1.meeting = meeting
    t1.project = proj
    ctx.insert(t1)
    try ctx.save()

    let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
    XCTAssertTrue(html.contains("<th>Action</th>"))
    XCTAssertFalse(html.contains("<th>Projet</th>"),
                   "Single project → colonne Projet absente")
}

@MainActor
func test_oneToOneActionsTable_multipleProjects_includesProjectColumn() throws {
    let ctx = try makeContext()
    let alice = Collaborator(name: "Alice DUPONT")
    ctx.insert(alice)
    let p1 = Project(code: "P1", name: "Projet 1", domain: "X")
    let p2 = Project(code: "P2", name: "Projet 2", domain: "Y")
    ctx.insert(p1); ctx.insert(p2)
    let meeting = Meeting(title: "1:1 Alice", date: Date())
    meeting.kindRaw = MeetingKind.oneToOne.rawValue
    meeting.participants = [alice]
    meeting.summary = "x"
    ctx.insert(meeting)
    let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
    t1.meeting = meeting
    t1.project = p1
    ctx.insert(t1)
    let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
    t2.meeting = meeting
    t2.project = p2
    ctx.insert(t2)
    try ctx.save()

    let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
    XCTAssertTrue(html.contains("<th>Projet</th>"),
                  "Multi projets en 1:1 → colonne Projet présente")
    XCTAssertTrue(html.contains("P1"))
    XCTAssertTrue(html.contains("P2"))
}

@MainActor
func test_nonOneToOneActionsTable_noProjectColumn() throws {
    let ctx = try makeContext()
    let p1 = Project(code: "P1", name: "Projet 1", domain: "X")
    let p2 = Project(code: "P2", name: "Projet 2", domain: "Y")
    ctx.insert(p1); ctx.insert(p2)
    let meeting = Meeting(title: "COPIL", date: Date())
    meeting.kindRaw = MeetingKind.project.rawValue
    meeting.summary = "x"
    ctx.insert(meeting)
    let t1 = ActionTask(title: "Tâche P1", dueDate: nil)
    t1.meeting = meeting; t1.project = p1
    ctx.insert(t1)
    let t2 = ActionTask(title: "Tâche P2", dueDate: nil)
    t2.meeting = meeting; t2.project = p2
    ctx.insert(t2)
    try ctx.save()

    let html = ReportHTMLBuilder.build(meeting: meeting, template: nil, includeTranscript: false)
    XCTAssertFalse(html.contains("<th>Projet</th>"),
                   "Non-1:1 → pas de colonne Projet même si multi projets")
}
```

- [ ] **Step 2: Confirmer RED (au moins le test multi-projets doit échouer)**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift test --filter ReportHTMLBuilderTests 2>&1 | tail -15
```
Expected: au moins le test `test_oneToOneActionsTable_multipleProjects_includesProjectColumn` échoue (FAIL).

- [ ] **Step 3: Modifier `dedupeAndInject` pour passer le flag**

Repérer `dedupeAndInject` (~ligne 377) :

```bash
grep -n "dedupeAndInject\|private static func renderActionsBlock" OneToOne/Services/Report/ReportHTMLBuilder.swift
```

Dans le call à `dedupeAndInject` (autour de la ligne 29), ce dernier est appelé avec `meeting.decisions` et `meeting.tasks`. Mais on n'a pas accès à `meeting.kind`. Approche : passer `meeting` directement plutôt que `tasks`.

Modifier la signature de `dedupeAndInject` :

```swift
private static func dedupeAndInject(bodyHTML: String,
                                    decisions: [String],
                                    tasks: [ActionTask],
                                    alerts: [ProjectAlert] = [],
                                    meeting: Meeting) -> String {
    var html = bodyHTML
    let decisionsBlock = decisions.isEmpty ? nil : renderDecisionsBlock(decisions)
    let actionsBlock = tasks.isEmpty ? nil : renderActionsBlock(tasks, meeting: meeting)
    // … reste inchangé …
}
```

Et le call dans `build(...)` :
```swift
var assembled = dedupeAndInject(
    bodyHTML: bodyHTML,
    decisions: meeting.decisions,
    tasks: meeting.tasks,
    alerts: meeting.meetingAlerts,
    meeting: meeting
)
```

- [ ] **Step 4: Modifier `renderActionsBlock` pour la colonne conditionnelle**

Remplacer le corps de `renderActionsBlock(_:)` (~ligne 413) par :

```swift
private static func renderActionsBlock(_ tasks: [ActionTask], meeting: Meeting) -> String {
    let sorted = tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "fr_FR")
    fmt.dateFormat = "d MMM yyyy"

    // Colonne Projet : uniquement en 1:1 avec actions sur ≥2 projets distincts.
    let distinctProjects = Set(sorted.compactMap { $0.project?.persistentModelID })
    let includeProjectColumn = meeting.kind == .oneToOne && distinctProjects.count >= 2

    var rows = ""
    for (idx, t) in sorted.enumerated() {
        let porteur = t.collaborator?.name ?? t.unresolvedAssigneeName ?? "—"
        let dueRaw = t.dueDate.map(fmt.string(from:)) ?? "—"
        if includeProjectColumn {
            let proj = t.project?.code ?? "—"
            rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(proj))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
        } else {
            rows += "<tr><td>A\(idx + 1)</td><td>\(escape(t.title))</td><td>\(escape(porteur))</td><td>\(escape(dueRaw))</td></tr>\n"
        }
    }
    let header = includeProjectColumn
        ? "<thead><tr><th>#</th><th>Action</th><th>Projet</th><th>Porteur</th><th>Échéance</th></tr></thead>"
        : "<thead><tr><th>#</th><th>Action</th><th>Porteur</th><th>Échéance</th></tr></thead>"
    return """
    <h2>Plan d'actions</h2>
    <table>
    \(header)
    <tbody>
    \(rows)</tbody>
    </table>
    """
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter ReportHTMLBuilderTests 2>&1 | tail -10
```
Expected: PASS tous les tests dont les 3 nouveaux.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/Report/ReportHTMLBuilder.swift Tests/ReportHTMLBuilderTests.swift
git commit -m "feat(contextual-prep): colonne Projet conditionnelle dans Plan d'actions (1:1 multi-projets)"
```

---

### Task 5: BuiltInTemplates — d2_oneToOne body update + revision bump

**Files:**
- Modify: `OneToOne/Services/BuiltInTemplates.swift`

- [ ] **Step 1: Localiser le body actuel**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "d2_oneToOne\|promptBody:" OneToOne/Services/BuiltInTemplates.swift | head
```

- [ ] **Step 2: Mettre à jour le body**

Remplacer le `promptBody` du seed `d2_oneToOne` par :

```swift
promptBody: """
1:1 avec {{collab.name}} ({{collab.role}}) — {{date}}

Tu rédiges le compte-rendu de ce 1:1. Le manager est le rédacteur.

Actions ouvertes héritées de {{collab.name}} :
{{collab.actions_ouvertes}}

Projets dont {{collab.name}} est architecte ou chef de projet :
{{collab.projects_context}}

Derniers 1:1 (pour suivi des actions précédentes) :
{{historique_n}}

{{custom_prompt}}

Transcription audio (peut contenir des erreurs STT) :
{{transcript}}

Notes prises en live (sources fiables) :
{{notes}}
"""
```

- [ ] **Step 3: Bump revision marker 2 → 3**

Localiser :
```bash
grep -n "d2Target\|d2OneToOneRevision" OneToOne/Services/BuiltInTemplates.swift
```

Trouver `let d2Target = 2` et le passer à `let d2Target = 3`. Le backfill écrasera le row existant au prochain lancement.

- [ ] **Step 4: Build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -3
```
Expected: `Build complete!` ; tests passent (les tests built-in seed devraient encore passer).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/BuiltInTemplates.swift
git commit -m "feat(contextual-prep): d2_oneToOne promptBody intègre {{collab.projects_context}} + revision 3"
```

---

### Task 6: Final build + smoke

**Files:** (aucun)

- [ ] **Step 1: Run tous les tests**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -10
```
Expected: tous PASS, dont les 7 nouveaux `ProjectsContextBuilderTests` et les 3 nouveaux dans `ReportHTMLBuilderTests`.

- [ ] **Step 2: Full build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Smoke test manuel**

Lance `swift run` (ou Cmd+R Xcode) :

1. Préfs → Templates → 1:1 Collaborateur → vérifier que `{{collab.projects_context}}` est présent dans le promptBody.
2. Ouvrir une réunion 1:1 avec un partenaire archi sur 2+ projets (sub-projet 1 doit être déployé). Générer rapport.
3. Vérifier dans le log que le prompt contient `## <CODE> · <Nom> (statut: …)` pour chaque projet du partenaire.
4. Inspecter le rapport rendu : "Plan d'actions" affiche bien la colonne `Projet` si les actions s'étalent sur ≥2 projets.
5. Réunion 1:1 sans projets affectés au partenaire → pas de section "Contexte projets affectés" dans le prompt.
6. Réunion COPIL (kind .project) → pas de variable injectée ni de colonne Projet.

- [ ] **Step 4: Historique commits**

```bash
git log --oneline -8
```
Attendu : 5 commits `feat(contextual-prep):` pour Tasks 1-5.

---

## Self-review

**Spec coverage** :
- §2.1 variable `{{collab.projects_context}}` + fallback append → Tasks 1 + 2 + 3. ✓
- §2.2 format texte structuré → Task 1 (`renderProject`). ✓
- §2.3 top-3 résumés, §2.4 max 10 actions, §2.5 max 5 projets, §2.6 budget 15k → Task 1 (constantes). ✓
- §2.7 colonne Projet conditionnelle → Task 4. ✓
- §2.8 d2_oneToOne body update + revision 3 → Task 5. ✓
- §3.1 extension TemplateVariableResolver → Task 2. ✓
- §3.2 ProjectsContextBuilder.build → Task 1. ✓
- §3.3 fallback append → Task 3. ✓
- §3.4 colonne Projet → Task 4. ✓
- §3.5 body d2 → Task 5. ✓
- §3.6 file map → all tasks. ✓
- §4 UX details (état vide, "aucun historique", outlook 5 colonnes) → Tasks 1 + 4 (le mode outlook reproduit automatiquement les `<th>` / `<td>` car le pipeline outlook style tag-agnostique). ✓
- §5 erreurs (partenaire archivé inclus, projet archivé exclu, troncature, budget) → Task 1. ✓
- §6 tests → Tasks 1 (7 tests) + 4 (3 tests). ✓
- §7 YAGNI → respecté.
- §8 migration → Task 5 (revision bump). ✓

**Placeholder scan** :
- Aucun "TBD" / "implement later".
- Task 3 Step 2 « vérifier que `body` est en scope » est explicite et facile à vérifier (la variable existe dans la fonction `generate` actuelle). Acceptable.
- Task 4 Step 3 modifie une signature : `dedupeAndInject` + `renderActionsBlock`. Tous les call-sites internes sont listés.

**Type consistency** :
- `ProjectsContextBuilder.build(for: meeting, in: context) -> String` — défini Task 1, utilisé Tasks 2, 3.
- `dedupeAndInject(bodyHTML:decisions:tasks:alerts:meeting:)` — Task 4 (signature évoluée), call-site Task 4 aussi.
- `renderActionsBlock(_ tasks: [ActionTask], meeting: Meeting)` — Task 4 (signature évoluée).
- `MeetingKind.oneToOne` / `meeting.kind == .oneToOne` — utilisé Tasks 1, 4. ✓
- `Collaborator.projectsAsArchitect / projectsAsManager` (sub-projet 1) — Task 1. ✓
- `Project.tasks` (inverse relation via ActionTask.project) — confirmé existant lors du sub-projet 2a (Task 7 trouvé `p.tasks`). ✓
- `ProjectStatusPalette.sortedByStatus(_:)` (sub-projet 2a) — Task 1. ✓

Aucune correction inline nécessaire.
