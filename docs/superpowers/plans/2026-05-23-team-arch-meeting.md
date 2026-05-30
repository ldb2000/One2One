# Team Arch Meeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Active les réunions de type "Architecture technique d'équipe" (`.work`) avec template dédié, variable `{{team.projects_context}}` injectant l'union des projets archi/PM des participants, ProjectsPanel sidebar et colonne Projet du Plan d'actions étendues à `.work`.

**Architecture:** Refactor `ProjectsContextBuilder.renderProject` (sub-projet 2b) pour extraire le rendu commun summaries+actions, puis ajoute `buildForTeam` qui collecte l'union projets participants. Nouveau case `{{team.projects_context}}` dans `TemplateVariableResolver` + fallback append dans `AIReportService`. `ProjectsPanel` étendu pour `.work`. Nouveau built-in `d10_archTeam`. Pas de RAG sémantique (V3).

**Tech Stack:** Swift 6, SwiftData, XCTest.

---

## File map

| Path | Change |
|---|---|
| `OneToOne/Services/ReportTemplating.swift` (modify) | Refactor `renderProject` → extract `renderProjectSummariesAndActions` ; nouveau `buildForTeam` ; nouveau case `team.projects_context` |
| `OneToOne/Services/AIReportService.swift` (modify) | Fallback append `{{team.projects_context}}` après celui de `{{collab.projects_context}}` |
| `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` (modify) | Branche `.work` (union participants → "Projets de l'équipe") |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` (modify) | `includeProjectColumn` accepte aussi `.work` |
| `OneToOne/Services/BuiltInTemplates.swift` (modify) | Nouveau seed `d10_archTeam` + ajout à `all: [Seed]` |
| `Tests/ProjectsContextBuilderTests.swift` (modify) | +4 tests `buildForTeam` |
| `Tests/ReportHTMLBuilderTests.swift` (modify) | +1 test colonne Projet `.work` |

Total : 5 modifs + 2 tests modifiés.

**Types existants utilisés** :
- `MeetingKind.work` ✓
- `Collaborator.projectsAsArchitect / projectsAsManager` (sub-projet 1) ✓
- `ProjectStatusPalette.sortedByStatus(_:)` (sub-projet 2a) ✓
- `ProjectsContextBuilder` (sub-projet 2b) ✓
- `Meeting.participants` ✓
- `Project.technicalArchitect / projectManager / status / isArchived / code / name` ✓

---

### Task 1: Refactor — extract `renderProjectSummariesAndActions`

**Files:**
- Modify: `OneToOne/Services/ReportTemplating.swift`

Refactor pur du sub-projet 2b : extraire la partie "summaries + actions" qui sera partagée entre `renderProject` (1:1) et le futur `renderTeamProject` (équipe). Aucun changement de comportement.

- [ ] **Step 1: Localiser `renderProject` actuel**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "private static func renderProject\|private static func projectRole" OneToOne/Services/ReportTemplating.swift
```

- [ ] **Step 2: Lire renderProject pour comprendre la structure**

Lire les ~50 lignes du `renderProject` actuel (autour de la ligne 469).

- [ ] **Step 3: Extraire le bloc summaries + actions**

Remplacer le `renderProject(_:partner:in:)` existant par cette version raccourcie + ajouter `renderProjectSummariesAndActions(_:in:)` :

```swift
private static func renderProject(_ p: Project,
                                   partner: Collaborator,
                                   in context: ModelContext) -> String {
    let role = projectRole(p, partner: partner)
    var out = "## \(p.code) · \(p.name) (statut: \(p.status))\n"
    out += "Rôle de \(partner.name) : \(role)\n\n"
    out += renderProjectSummariesAndActions(p, in: context)
    return out
}

/// Rendu commun à 1:1 et équipe : top-3 résumés de meetings sur ce projet
/// + actions ouvertes. Partagé entre `renderProject` (sub-projet 2b) et
/// `renderTeamProject` (sub-projet 3).
private static func renderProjectSummariesAndActions(_ p: Project,
                                                      in context: ModelContext) -> String {
    var out = ""

    // Top 3 résumés de meetings sur ce projet.
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

    // Actions ouvertes (top N par dueDate asc).
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
```

- [ ] **Step 4: Build + tests existants**

```bash
swift build 2>&1 | tail -3
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -5
```
Expected: `Build complete!` + PASS 7/7 (les tests de sub-projet 2b doivent passer sans modif).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift
git commit -m "refactor(team-arch): extract renderProjectSummariesAndActions pour partage 1:1 / équipe"
```

---

### Task 2: `ProjectsContextBuilder.buildForTeam` (TDD)

**Files:**
- Modify: `OneToOne/Services/ReportTemplating.swift`
- Modify: `Tests/ProjectsContextBuilderTests.swift`

- [ ] **Step 1: Écrire les tests failing**

Ajouter à la fin de la class `ProjectsContextBuilderTests` (avant la dernière `}`) :

```swift
    @MainActor
    func test_buildForTeam_nonWorkMeeting_returnsEmpty() throws {
        let ctx = try makeContext()
        let m = Meeting(title: "1:1", date: Date())
        m.kindRaw = MeetingKind.oneToOne.rawValue
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.buildForTeam(meeting: m, in: ctx), "")
    }

    @MainActor
    func test_buildForTeam_workMeetingWithoutParticipantsProjects_returnsEmpty() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let m = Meeting(title: "Archi équipe", date: Date())
        m.kindRaw = MeetingKind.work.rawValue
        m.participants = [alice]
        ctx.insert(m)
        try ctx.save()
        XCTAssertEqual(ProjectsContextBuilder.buildForTeam(meeting: m, in: ctx), "")
    }

    @MainActor
    func test_buildForTeam_workMeetingUnionOfParticipantsProjects() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)

        let p1 = Project(code: "NEVIDIS", name: "Projet Névidis", domain: "Infra", phase: "Build")
        p1.status = "Yellow"
        p1.technicalArchitect = alice
        ctx.insert(p1)

        let p2 = Project(code: "COOG", name: "Migration Coog", domain: "Infra", phase: "Run")
        p2.status = "Red"
        p2.projectManager = bob
        ctx.insert(p2)

        let m = Meeting(title: "Archi équipe", date: Date())
        m.kindRaw = MeetingKind.work.rawValue
        m.participants = [alice, bob]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.buildForTeam(meeting: m, in: ctx)
        XCTAssertTrue(out.contains("NEVIDIS"), "Projet d'Alice présent")
        XCTAssertTrue(out.contains("COOG"), "Projet de Bob présent")
        // Red avant Yellow
        if let red = out.range(of: "(statut: Red)")?.lowerBound,
           let yellow = out.range(of: "(statut: Yellow)")?.lowerBound {
            XCTAssertTrue(red < yellow, "Red doit apparaître avant Yellow")
        }
    }

    @MainActor
    func test_buildForTeam_dedupesProjectsAcrossParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)

        // Projet partagé : Alice est archi, Bob est PM.
        let p = Project(code: "SHARED", name: "Projet partagé", domain: "X", phase: "Build")
        p.status = "Green"
        p.technicalArchitect = alice
        p.projectManager = bob
        ctx.insert(p)

        let m = Meeting(title: "Archi équipe", date: Date())
        m.kindRaw = MeetingKind.work.rawValue
        m.participants = [alice, bob]
        ctx.insert(m)
        try ctx.save()

        let out = ProjectsContextBuilder.buildForTeam(meeting: m, in: ctx)
        let occurrences = out.components(separatedBy: "## SHARED").count - 1
        XCTAssertEqual(occurrences, 1, "Le projet partagé ne doit apparaître qu'une fois (dédup)")
    }
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'buildForTeam' in scope`.

- [ ] **Step 3: Implémenter `buildForTeam` + `renderTeamProject`**

Dans `OneToOne/Services/ReportTemplating.swift`, au sein du `enum ProjectsContextBuilder`, ajouter après `build(for:in:)` :

```swift
/// Variante équipe : pour une réunion `.work`, agrège l'union des projets
/// dont les participants présents sont archi technique ou chef de projet.
/// Dédup par projet, tri statut Red→Yellow→Green→Unknown, max 5 projets.
static func buildForTeam(meeting: Meeting, in context: ModelContext) -> String {
    guard meeting.kind == .work else { return "" }

    var seen: Set<PersistentIdentifier> = []
    var projects: [Project] = []
    for participant in meeting.participants {
        for p in participant.projectsAsArchitect + participant.projectsAsManager {
            guard !p.isArchived, seen.insert(p.persistentModelID).inserted else { continue }
            projects.append(p)
        }
    }
    guard !projects.isEmpty else { return "" }

    let sorted = ProjectStatusPalette.sortedByStatus(projects)
    let topProjects = Array(sorted.prefix(maxProjects))

    var pieces: [String] = []
    for p in topProjects {
        pieces.append(renderTeamProject(p, in: context))
    }
    let full = pieces.joined(separator: "\n\n")
    if full.count <= totalBudgetChars { return full }
    let truncated = String(full.prefix(totalBudgetChars))
    if let lastNewline = truncated.lastIndex(of: "\n") {
        return String(truncated[..<lastNewline])
    }
    return truncated
}

/// Rendu d'un projet pour le contexte équipe : header + rôles archi/PM
/// nommés + bloc summaries+actions partagé.
private static func renderTeamProject(_ p: Project,
                                       in context: ModelContext) -> String {
    var out = "## \(p.code) · \(p.name) (statut: \(p.status))\n\n"
    if let archi = p.technicalArchitect {
        out += "Architecte technique : \(archi.name)\n"
    }
    if let pm = p.projectManager {
        out += "Chef de projet : \(pm.name)\n"
    }
    out += "\n"
    out += renderProjectSummariesAndActions(p, in: context)
    return out
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -15
```
Expected: PASS 11/11 (7 existants + 4 nouveaux).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift Tests/ProjectsContextBuilderTests.swift
git commit -m "feat(team-arch): ProjectsContextBuilder.buildForTeam — union projets participants .work"
```

---

### Task 3: Wire `{{team.projects_context}}` dans TemplateVariableResolver

**Files:**
- Modify: `OneToOne/Services/ReportTemplating.swift`

- [ ] **Step 1: Localiser le case `collab.projects_context`**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n 'case "collab.projects_context"' OneToOne/Services/ReportTemplating.swift
```

- [ ] **Step 2: Ajouter le case team**

Juste après le case `"collab.projects_context"`, ajouter :

```swift
case "team.projects_context":
    return ProjectsContextBuilder.buildForTeam(meeting: meeting, in: context)
```

- [ ] **Step 3: Build + tests**

```bash
swift build 2>&1 | tail -3
swift test --filter ProjectsContextBuilderTests 2>&1 | tail -3
```
Expected: `Build complete!` + PASS 11/11.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/ReportTemplating.swift
git commit -m "feat(team-arch): variable template {{team.projects_context}}"
```

---

### Task 4: AIReportService — fallback append `{{team.projects_context}}`

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Localiser le fallback `collab.projects_context`**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "hasProjectsPlaceholder\|hasTeamPlaceholder" OneToOne/Services/AIReportService.swift
```
Le `hasProjectsPlaceholder` est autour de la ligne 125.

- [ ] **Step 2: Ajouter le fallback team**

Juste après le bloc `if !hasProjectsPlaceholder { ... }` existant, ajouter :

```swift
        // Fallback append du contexte projets de l'équipe pour les réunions
        // de travail (.work). Si le template ne contient pas
        // `{{team.projects_context}}` mais que la réunion .work a des
        // participants avec projets affectés, append en queue.
        let hasTeamPlaceholder = body.contains("{{team.projects_context}}")
        if !hasTeamPlaceholder {
            let teamBlock = ProjectsContextBuilder.buildForTeam(meeting: meeting, in: context)
            if !teamBlock.isEmpty {
                historyAppendix += "\n\nContexte projets de l'équipe :\n\(teamBlock)\n"
            }
        }
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`. Si `body` pas en scope, utiliser `(template?.promptBody ?? "")`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(team-arch): fallback append {{team.projects_context}} pour .work meetings"
```

---

### Task 5: ProjectsPanel — branche `.work`

**Files:**
- Modify: `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift`

- [ ] **Step 1: Lire le code actuel**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
cat OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift
```

- [ ] **Step 2: Refactor avec branches kind**

Remplacer le contenu actuel de `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` par :

```swift
import SwiftUI
import SwiftData

/// Panneau "Projets" de la sidebar configurable.
///
/// Visible pour :
/// - `.oneToOne` : projets archi/PM du partenaire (séparés en 2 sous-sections)
/// - `.work` : union des projets archi/PM des participants présents
///   (section unique "Projets de l'équipe")
/// Autres kinds : état vide informatif.
struct ProjectsPanel: View {

    let meeting: Meeting

    private var partner: Collaborator? {
        meeting.kind == .oneToOne ? meeting.participants.first : nil
    }

    private var teamProjects: [Project]? {
        guard meeting.kind == .work else { return nil }
        var seen: Set<PersistentIdentifier> = []
        var projects: [Project] = []
        for participant in meeting.participants {
            for p in participant.projectsAsArchitect + participant.projectsAsManager {
                guard !p.isArchived, seen.insert(p.persistentModelID).inserted else { continue }
                projects.append(p)
            }
        }
        return projects.isEmpty ? nil : ProjectStatusPalette.sortedByStatus(projects)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = partner {
                partnerProjectsView(p)
            } else if meeting.kind == .work {
                if let team = teamProjects {
                    teamProjectsView(team)
                } else {
                    emptyState("Aucun participant n'a de projet affecté.")
                }
            } else {
                emptyState("Visible uniquement en 1:1 ou réunion d'équipe.")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder
    private func partnerProjectsView(_ p: Collaborator) -> some View {
        if p.projectsAsArchitect.isEmpty && p.projectsAsManager.isEmpty {
            emptyState("Pas de projet affecté à \(p.name).")
        } else {
            if !p.projectsAsArchitect.isEmpty {
                section(title: "EN TANT QU'ARCHITECTE",
                        projects: p.projectsAsArchitect)
            }
            if !p.projectsAsManager.isEmpty {
                section(title: "EN TANT QUE CHEF DE PROJET",
                        projects: p.projectsAsManager)
            }
        }
    }

    @ViewBuilder
    private func teamProjectsView(_ projects: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PROJETS DE L'ÉQUIPE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text("(\(projects.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(projects) { p in
                NavigationLink {
                    ProjectDetailView(project: p)
                } label: { projectRow(p) }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ msg: String) -> some View {
        Text(msg)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(title: String, projects: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text("(\(projects.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(ProjectStatusPalette.sortedByStatus(projects)) { p in
                NavigationLink {
                    ProjectDetailView(project: p)
                } label: { projectRow(p) }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        let openTasks = p.tasks.filter { !$0.isCompleted }.count
        HStack(spacing: 6) {
            Circle()
                .fill(ProjectStatusPalette.color(p.status))
                .frame(width: 7, height: 7)
            Text(p.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(p.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            if openTasks > 0 {
                Text("\(openTasks) act")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift
git commit -m "feat(team-arch): ProjectsPanel étendu pour .work (union projets participants)"
```

---

### Task 6: ReportHTMLBuilder — colonne Projet étendue à `.work`

**Files:**
- Modify: `OneToOne/Services/Report/ReportHTMLBuilder.swift`
- Modify: `Tests/ReportHTMLBuilderTests.swift`

- [ ] **Step 1: Ajouter un test**

Dans `Tests/ReportHTMLBuilderTests.swift`, ajouter à la fin de la classe :

```swift
    @MainActor
    func test_workMeetingMultipleProjects_includesProjectColumn() throws {
        let ctx = try makeContext()
        let p1 = Project(code: "P1", name: "Projet 1", domain: "X", phase: "Build")
        let p2 = Project(code: "P2", name: "Projet 2", domain: "Y", phase: "Build")
        ctx.insert(p1); ctx.insert(p2)
        let meeting = Meeting(title: "Archi équipe", date: Date())
        meeting.kindRaw = MeetingKind.work.rawValue
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
                      ".work + multi-projets → colonne Projet présente")
    }
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter ReportHTMLBuilderTests/test_workMeetingMultipleProjects_includesProjectColumn 2>&1 | tail -5
```
Expected: FAIL.

- [ ] **Step 3: Localiser `includeProjectColumn`**

```bash
grep -n "includeProjectColumn" OneToOne/Services/Report/ReportHTMLBuilder.swift
```

- [ ] **Step 4: Modifier la condition**

Trouver la ligne :
```swift
let includeProjectColumn = meeting.kind == .oneToOne && distinctProjects.count >= 2
```

Remplacer par :
```swift
let isMultiProjectMeeting = meeting.kind == .oneToOne || meeting.kind == .work
let includeProjectColumn = isMultiProjectMeeting && distinctProjects.count >= 2
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter ReportHTMLBuilderTests 2>&1 | tail -10
```
Expected: PASS tous, dont le nouveau test.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/Report/ReportHTMLBuilder.swift Tests/ReportHTMLBuilderTests.swift
git commit -m "feat(team-arch): colonne Projet conditionnelle étendue aux réunions .work"
```

---

### Task 7: Built-in template `d10_archTeam`

**Files:**
- Modify: `OneToOne/Services/BuiltInTemplates.swift`

- [ ] **Step 1: Localiser le tableau `all` et un seed récent (ex. d9_workshop) comme modèle**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
grep -n "static let all\|d9_workshop\|d10_" OneToOne/Services/BuiltInTemplates.swift
```

- [ ] **Step 2: Ajouter d10 à la liste `all`**

Trouver le `static let all: [Seed] = [` et ajouter `d10_archTeam` après `d9_workshop` :

```swift
static let all: [Seed] = [
    d1_global,
    d2_oneToOne,
    d3_manager,
    d4_copil,
    d5_cosui,
    d6_codir,
    d7_preparation,
    d8_restitution,
    d9_workshop,
    d10_archTeam
]
```

- [ ] **Step 3: Ajouter la définition `d10_archTeam`**

Ajouter à la fin du fichier `BuiltInTemplates.swift`, après le dernier seed (`d9_workshop`) :

```swift
    // MARK: - D10 Architecture technique d'équipe

    static let d10_archTeam = Seed(
        name: "Architecture technique d'équipe",
        kind: .work,
        preamble: """
        Tu es l'assistant de synthèse de réunions techniques d'équipe d'architecture.
        Ton factuel, opérationnel, en français.

        Règles strictes :
        - N'INVENTE JAMAIS. Si une info est ambiguë, ne pas l'inclure.
        - IGNORE en silence les passages personnels off-topic.
        - Regroupe par PROJET — un H3 par projet revu pendant la réunion.
        - Sois EXHAUSTIF sur les sujets techniques et les décisions d'architecture.
        - Distingue : décisions actées vs idées exploratoires vs sujets ouverts.
        - Action = verbe à l'infinitif + porteur explicite + échéance si mentionnée.
        - Préserve les noms de technos, frameworks, services (Kubernetes, PostgreSQL, etc.)
          tels qu'ils sont prononcés ; corrige silencieusement les évidences (homophones STT).
        """,
        sections: [
            .init(title: "Sujets transversaux",
                  hint: "Sujets touchant plusieurs projets ou l'équipe entière (stack, méthodologie, sécurité)."),
            .init(title: "Revue par projet",
                  hint: "Un H3 par projet discuté en réunion : contexte bref + points abordés + statut atteint."),
            .init(title: "Décisions",
                  hint: "Décisions d'architecture formellement actées en séance. Précise le projet ou le scope."),
            .init(title: "Actions",
                  hint: "Engagements pris. Verbe + porteur + échéance si mentionnée. Lier au projet si applicable."),
            .init(title: "Alertes & risques",
                  hint: "Risques techniques soulevés. Sévérité et projet impacté quand pertinent."),
            .init(title: "Suivi",
                  hint: "Sujets à reprendre lors de la prochaine réunion ou en 1:1 avec les porteurs.")
        ],
        historyMode: .lastN,
        historyN: 2,
        historyK: 0,
        promptBody: """
        Réunion d'architecture technique d'équipe — {{date}}

        Participants : {{participants}}

        Projets de l'équipe (projets dont au moins un participant est archi ou PM) :
        {{team.projects_context}}

        Derniers historiques d'archi équipe (pour suivi) :
        {{historique_n}}

        {{custom_prompt}}

        Transcription audio (peut contenir des erreurs STT) :
        {{transcript}}

        Notes prises en live (sources fiables) :
        {{notes}}
        """
    )
```

- [ ] **Step 4: Build + tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -3
```
Expected: `Build complete!` + tous tests PASS.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/BuiltInTemplates.swift
git commit -m "feat(team-arch): built-in template d10_archTeam (Architecture technique d'équipe)"
```

---

### Task 8: Final build + smoke

**Files:** (aucun)

- [ ] **Step 1: Full build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 2: Tous les tests**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -8
```
Expected: tous PASS dont les 4 nouveaux `buildForTeam` et le test `.work` de colonne Projet.

- [ ] **Step 3: Smoke test manuel**

`swift run` (ou Cmd+R Xcode) :

1. Préfs → Templates → vérifier que "Architecture technique d'équipe" apparaît (seedé au prochain lancement).
2. Créer une réunion `.work` avec 2 participants archi sur des projets différents.
3. Sidebar Projets → section "PROJETS DE L'ÉQUIPE" avec les projets union.
4. Sélectionner le template "Architecture technique d'équipe" via `MeetingTopChromeBar` → Générer.
5. Vérifier dans Console que le prompt LLM contient `## CODE · Nom (statut: …)` pour chaque projet d'équipe.
6. Inspecter le rapport rendu : colonne `Projet` visible dans Plan d'actions si ≥2 projets distincts.
7. Réunion `.work` sans participants avec projets → panneau Projets affiche "Aucun participant n'a de projet affecté.".
8. Réunion `.project` (COPIL) → panneau Projets affiche "Visible uniquement en 1:1 ou réunion d'équipe.".

- [ ] **Step 4: Historique commits**

```bash
git log --oneline -10
```
Attendu : 7 commits `feat(team-arch):` / `refactor(team-arch):` pour Tasks 1-7.

---

## Self-review

**Spec coverage** :
- §2.1 pas de nouveau MeetingKind → réutilise `.work` partout (Tasks 2, 5, 6, 7). ✓
- §2.2 d10_archTeam ajouté à `all` → Task 7. ✓
- §2.3 variable `{{team.projects_context}}` → Tasks 2 + 3. ✓
- §2.4 ProjectsPanel `.work` union → Task 5. ✓
- §2.5 colonne Projet `.work` → Task 6. ✓
- §3.1 buildForTeam + refactor renderProjectSummariesAndActions → Tasks 1 + 2. ✓
- §3.2 case team.projects_context → Task 3. ✓
- §3.3 fallback append AIReportService → Task 4. ✓
- §3.4 ProjectsPanel branches kind → Task 5. ✓
- §3.5 includeProjectColumn étendu → Task 6. ✓
- §3.6 d10_archTeam definition → Task 7. ✓
- §3.7 file map → all tasks. ✓
- §4 UX details (état vide, max 5 projets, fallback append, colonne conditionnelle) → Tasks 1-7. ✓
- §5 erreurs (archive, dédup, budget) → Tasks 1 + 2. ✓
- §6 tests → Tasks 2 (4 buildForTeam) + 6 (1 colonne `.work`). ✓
- §7 YAGNI → respecté.
- §8 migration → Task 7 (seedIfNeeded détecte automatiquement, pas de bump revision nécessaire).

**Placeholder scan** :
- Aucun "TBD" / "implement later".
- Code complet à chaque step.

**Type consistency** :
- `ProjectsContextBuilder.buildForTeam(meeting:in:)` → Task 2 (def), Tasks 3, 4 (usage). ✓
- `ProjectsContextBuilder.renderProjectSummariesAndActions(_:in:)` → Task 1 (def, helper privé). ✓
- `ProjectsContextBuilder.renderTeamProject(_:in:)` → Task 2 (def, helper privé). ✓
- `{{team.projects_context}}` → Tasks 3, 4, 7 (usage). ✓
- `MeetingKind.work` ✓
- `isMultiProjectMeeting` / `includeProjectColumn` → Task 6. ✓
- `partnerProjectsView` / `teamProjectsView` → Task 5. ✓
- `d10_archTeam` → Task 7. ✓

Aucune correction inline nécessaire.
