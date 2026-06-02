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
                            .help("Glisser dans l'éditeur pour ajouter")
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

    /// Conteneur visuel d'une section du panneau : titre + icône SF Symbol en
    /// en-tête, suivi du contenu fourni.
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

    /// Charge le contexte du panneau scoped à la meeting : actions ouvertes,
    /// 3 derniers points et alertes élevées/critiques. La portée dépend du
    /// `kind` (collaborateur pour 1:1/manager, projet pour project).
    @MainActor
    private func loadContext() async {
        // --- Actions ouvertes ---
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

        // --- Past meetings (excluding self) ---
        let selfID = meeting.persistentModelID
        if let c = meeting.participants.first, meeting.kind == .oneToOne || meeting.kind == .manager {
            let cid = c.persistentModelID
            // SwiftData #Predicate doesn't support `.contains(where:)` on
            // relationship arrays — fetch all and filter in Swift.
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let all = (try? context.fetch(descriptor)) ?? []
            pastMeetings = Array(all
                .filter { $0.persistentModelID != selfID }
                .filter { $0.participants.contains(where: { $0.persistentModelID == cid }) }
                .prefix(3))
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

        // --- Alertes ---
        if let p = meeting.project {
            let pid = p.persistentModelID
            let d = FetchDescriptor<ProjectAlert>(
                predicate: #Predicate { $0.project?.persistentModelID == pid }
            )
            alerts = Array(((try? context.fetch(d)) ?? [])
                .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
                .prefix(5))
        }
    }

    /// Formate une date en français court (ex. "5 juin") pour l'affichage des
    /// derniers points.
    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}
