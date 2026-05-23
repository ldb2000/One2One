import SwiftUI
import SwiftData

/// Panneau "Projets affectés" de la sidebar configurable.
/// Visible pour `Meeting.kind == .oneToOne` ; liste les projets où le partenaire
/// est archi technique ou chef de projet, triés Red → Yellow → Green → Unknown.
/// Pour chaque row : code · nom · chip statut · count actions ouvertes.
struct ProjectsPanel: View {

    let meeting: Meeting

    private var partner: Collaborator? {
        meeting.kind == .oneToOne ? meeting.participants.first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = partner {
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
            } else {
                emptyState("Visible uniquement pour les 1:1.")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
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
                } label: {
                    projectRow(p)
                }
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
