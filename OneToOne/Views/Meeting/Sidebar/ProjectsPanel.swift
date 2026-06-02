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

    /// Partenaire d'un 1:1 (premier participant). `nil` hors `.oneToOne`,
    /// ce qui aiguille `body` vers la branche équipe ou l'état vide.
    private var partner: Collaborator? {
        meeting.kind == .oneToOne ? meeting.participants.first : nil
    }

    /// Union dédupliquée des projets (architecte + chef de projet) de tous les
    /// participants présents, archivés exclus, triée par statut. `nil` hors
    /// `.work` ou si aucun projet — la dédup se fait sur `persistentModelID`.
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
