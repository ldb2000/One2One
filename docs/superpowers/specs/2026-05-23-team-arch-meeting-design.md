# Team Arch Meeting + Cross-Projets Context — Design

**Date:** 2026-05-23

## 1. Objet

Sub-projet **3 / 3** de la roadmap Project Ownership. Active les réunions de type "Architecture technique d'équipe" (réutilise `MeetingKind.work`) avec :
- Un built-in template dédié orienté revue de portefeuille projets
- Une variable template `{{team.projects_context}}` qui injecte le contexte de tous les projets dont les participants présents sont archi technique ou chef de projet
- Le panneau `ProjectsPanel` adapté pour `.work` (union projets participants)
- La colonne Projet du Plan d'actions étendue à `.work`

Pas de RAG sémantique en V1 (l'infra `RAGService.search` existe mais reste hors scope).

## 2. Décisions actées

1. Pas de nouveau `MeetingKind` : réutilisation de `.work` existant ("réunion de travail (équipe)").
2. Nouveau built-in template `d10_archTeam` ajouté à `BuiltInTemplates.swift` + `all`.
3. Nouvelle variable `{{team.projects_context}}` injecte l'union des projets archi/PM des participants présents. Tri Red→Yellow→Green→Unknown, max 5 projets, top 3 résumés par projet (1500 chars chacun), max 10 actions ouvertes par projet, budget total 15 000 chars.
4. `ProjectsPanel` sidebar : visible pour `.oneToOne` ET `.work`. Pour `.work` : liste unique "Projets de l'équipe" sans séparation archi/PM.
5. Colonne `Projet` du canonical Plan d'actions visible aussi en `.work` (toujours conditionnelle `distinctProjects ≥ 2`).
6. Pas de filtrage favoris ; les participants présents définissent le scope.

## 3. Architecture

### 3.1 `ProjectsContextBuilder.buildForTeam`

Méthode soeur de `build(for:in:)` (sub-projet 2b) :

```swift
@MainActor
extension ProjectsContextBuilder {

    static func buildForTeam(meeting: Meeting, in context: ModelContext) -> String {
        guard meeting.kind == .work else { return "" }

        // Union des projets archi + PM des participants.
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

    private static func renderTeamProject(_ p: Project,
                                           in context: ModelContext) -> String {
        var out = "## \(p.code) · \(p.name) (statut: \(p.status))\n\n"
        // Rôles attribués
        if let archi = p.technicalArchitect {
            out += "Architecte technique : \(archi.name)\n"
        }
        if let pm = p.projectManager {
            out += "Chef de projet : \(pm.name)\n"
        }
        out += "\n"
        // Top 3 résumés + actions ouvertes : MÊME logique que renderProject existant
        // (sub-projet 2b). On factor le rendu summaries/actions dans un helper privé
        // `renderProjectSummariesAndActions(_ p: Project, in: context)`.
        out += renderProjectSummariesAndActions(p, in: context)
        return out
    }

    /// Helper extrait : top-3 résumés + actions ouvertes pour un projet.
    /// Utilisé par `renderProject` (1:1) ET `renderTeamProject` (équipe).
    private static func renderProjectSummariesAndActions(_ p: Project,
                                                          in context: ModelContext) -> String {
        // … code identique à la partie summaries+actions de renderProject existant …
    }
}
```

Le `renderProject` existant (sub-projet 2b) est refactoré pour appeler `renderProjectSummariesAndActions` au lieu de dupliquer.

### 3.2 `TemplateVariableResolver` — nouveau case

Ajout dans `resolveOne` :

```swift
case "team.projects_context":
    return ProjectsContextBuilder.buildForTeam(meeting: meeting, in: context)
```

### 3.3 `AIReportService.generate` — fallback append

Pattern existant pour `{{collab.projects_context}}`. Ajouter :

```swift
let hasTeamPlaceholder = body.contains("{{team.projects_context}}")
if !hasTeamPlaceholder {
    let teamBlock = ProjectsContextBuilder.buildForTeam(meeting: meeting, in: context)
    if !teamBlock.isEmpty {
        historyAppendix += "\n\nContexte projets de l'équipe :\n\(teamBlock)\n"
    }
}
```

Placé juste après le fallback `{{collab.projects_context}}`.

### 3.4 `ProjectsPanel` étendu

Logique mise à jour :

```swift
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
        if meeting.kind == .oneToOne, let p = partner {
            // Comportement existant (sub-projet 2a)
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
```

`partnerProjectsView` factorise la logique 1:1 actuelle (les 2 sous-sections archi/PM).

### 3.5 `ReportHTMLBuilder.renderActionsBlock`

Modifie la condition `includeProjectColumn` :

```swift
let isMultiProjectMeeting = meeting.kind == .oneToOne || meeting.kind == .work
let includeProjectColumn = isMultiProjectMeeting && distinctProjects.count >= 2
```

### 3.6 Built-in template `d10_archTeam`

```swift
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

Ajouter à `all: [Seed]` :
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

Pas de backfill nécessaire — c'est un nouveau template, `seedIfNeeded` détecte le nom manquant et l'insère.

### 3.7 Fichiers impactés

| Path | Change |
|---|---|
| `OneToOne/Services/ReportTemplating.swift` | `ProjectsContextBuilder.buildForTeam` + refactor `renderProjectSummariesAndActions` partagé + case `team.projects_context` dans resolveOne |
| `OneToOne/Services/BuiltInTemplates.swift` | Nouveau seed `d10_archTeam` + `all` array |
| `OneToOne/Services/AIReportService.swift` | Fallback append `{{team.projects_context}}` pour `.work` |
| `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` | Branche `.work` (union participants + section "Projets de l'équipe") |
| `OneToOne/Services/Report/ReportHTMLBuilder.swift` | `includeProjectColumn` étendu `.work` |
| `Tests/ProjectsContextBuilderTests.swift` (modify) | +3 tests team scope |
| `Tests/ReportHTMLBuilderTests.swift` (modify) | +1 test colonne Projet en `.work` |

5 modifs, 2 modifs tests existants. Pas de nouveau fichier.

## 4. UX details

- Réunion `.work` créée sans participant : panneau Projets affiche "Aucun participant n'a de projet affecté."
- Participants présents tous archivés ou sans projets : idem.
- Liste max 5 projets par tri statut Red→Yellow→Green→Unknown.
- Colonne Projet de la table actions : affichée en `.work` uniquement si actions sur ≥2 projets distincts (comportement identique à `.oneToOne`).
- Section "Contexte projets de l'équipe" append automatique si le template ne contient pas `{{team.projects_context}}`.

## 5. Erreurs / edge cases

- Participant archivé : exclu de l'agrégation.
- Projet archivé : exclu.
- Doublon projet (même proj référencé par 2 participants) : `seen` Set évite la duplication.
- Budget caractères dépassé : troncature en queue, ligne complète préservée.
- Aucun résumé sur un projet : sous-section "(aucun historique disponible)".
- Aucune action ouverte : "(aucune action ouverte)".

## 6. Tests

### 6.1 `ProjectsContextBuilderTests` (additions)

```swift
func test_buildForTeam_nonWorkMeeting_returnsEmpty()
func test_buildForTeam_workMeetingWithoutParticipantsProjects_returnsEmpty()
func test_buildForTeam_workMeetingUnionOfParticipantsProjects()
func test_buildForTeam_dedupesProjectsAcrossParticipants()
```

### 6.2 `ReportHTMLBuilderTests` (addition)

```swift
func test_workMeetingMultipleProjects_includesProjectColumn()
```

### 6.3 Smoke manuel

1. Créer une réunion `.work` avec 2 participants archi sur des projets différents → générer rapport → vérifier que `{{team.projects_context}}` (ou append fallback) injecte tous leurs projets dans le prompt.
2. Sidebar Projets visible → section "PROJETS DE L'ÉQUIPE" avec liste union.
3. Plan d'actions affiche colonne Projet si actions sur ≥2 projets.
4. Préfs → Templates → "Architecture technique d'équipe" → vérifier que le seed est créé au premier lancement.
5. Choisir ce template via le toolbar (`MeetingTopChromeBar`) sur une réunion `.work` → re-générer.

## 7. YAGNI

- Pas de RAG sémantique cross-meeting (V3+).
- Pas de nouveau `MeetingKind.archTeam`.
- Pas de modèle "Team" / "Squad" en SwiftData.
- Pas de filtre favoris pour limiter le scope.
- Pas de section dédiée "Risques techniques" séparée de "Alertes & risques".
- Pas de comparaison statuts entre réunions consécutives.
- Pas de génération automatique d'agenda pré-réunion (V2).

## 8. Migration

- `seedIfNeeded` détecte automatiquement le nouveau template `d10_archTeam` (absent du `existingNames` Set) et l'insère au prochain lancement.
- Aucune migration SwiftData.
- Aucun champ ajouté.

## 9. Livrables

- `OneToOne/Services/ReportTemplating.swift` modifié
- `OneToOne/Services/BuiltInTemplates.swift` modifié (+seed)
- `OneToOne/Services/AIReportService.swift` modifié
- `OneToOne/Views/Meeting/Sidebar/ProjectsPanel.swift` modifié
- `OneToOne/Services/Report/ReportHTMLBuilder.swift` modifié
- `Tests/ProjectsContextBuilderTests.swift` modifié (+4 tests)
- `Tests/ReportHTMLBuilderTests.swift` modifié (+1 test)

Spec ready.
