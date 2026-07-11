import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Dimension de regroupement des colonnes Kanban.
enum ActionGrouping: String, CaseIterable {
    case destinataire, projet, collaborateur
    var label: String {
        switch self {
        case .destinataire: return "Destinataire"
        case .projet: return "Projet"
        case .collaborateur: return "Collaborateur"
        }
    }
}

/// Une colonne Kanban : appartenance + réassignation au drop.
struct KanbanColumn: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let contains: (ActionTask) -> Bool
    /// Appliqué quand une carte est déposée dans cette colonne.
    let assign: (ActionTask) -> Void
}

/// Tableau Kanban générique : colonnes fournies par l'appelant (selon la
/// dimension de regroupement). Glisser une carte vers une colonne appelle son
/// `assign` puis `onChanged`. `fillsAvailableSpace` = colonnes plein écran avec
/// ascenseur.
struct KanbanBoard: View {
    let columns: [KanbanColumn]
    let tasks: [ActionTask]
    var onToggle: (ActionTask) -> Void
    var onChanged: () -> Void
    var fillsAvailableSpace: Bool = false

    @State private var dragged: ActionTask?

    /// Construit les colonnes selon la dimension choisie (valeurs présentes dans
    /// les tâches + une colonne « aucun »).
    static func columns(for grouping: ActionGrouping, tasks: [ActionTask]) -> [KanbanColumn] {
        switch grouping {
        case .destinataire:
            return ActionAudience.allCases.map { a in
                KanbanColumn(id: "aud-\(a.rawValue)", title: a.sectionTitle, systemImage: a.systemImage,
                             contains: { $0.destinataire == a },
                             assign: { t in
                                 t.destinataire = a
                                 if a != .collaborateur { t.collaborator = nil }
                             })
            }
        case .projet:
            var seen = Set<PersistentIdentifier>()
            let projects = tasks.compactMap(\.project)
                .filter { seen.insert($0.persistentModelID).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var cols = projects.map { p in
                KanbanColumn(id: "proj-\(p.persistentModelID.hashValue)", title: p.name, systemImage: "folder.fill",
                             contains: { $0.project?.persistentModelID == p.persistentModelID },
                             assign: { $0.project = p })
            }
            cols.append(KanbanColumn(id: "proj-none", title: "Sans projet", systemImage: "folder",
                                     contains: { $0.project == nil }, assign: { $0.project = nil }))
            return cols
        case .collaborateur:
            var seen = Set<PersistentIdentifier>()
            let collabs = tasks.compactMap(\.collaborator)
                .filter { seen.insert($0.persistentModelID).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var cols = collabs.map { c in
                KanbanColumn(id: "col-\(c.persistentModelID.hashValue)", title: c.name, systemImage: "person.fill",
                             contains: { $0.collaborator?.persistentModelID == c.persistentModelID },
                             assign: { $0.collaborator = c })
            }
            cols.append(KanbanColumn(id: "col-none", title: "Non assigné", systemImage: "person",
                                     contains: { $0.collaborator == nil }, assign: { $0.collaborator = nil }))
            return cols
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(columns) { col in column(col) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
    }

    private func column(_ col: KanbanColumn) -> some View {
        let items = tasks
            .filter { !$0.isCompleted && col.contains($0) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let charge = items.reduce(0) { $0 + $1.pomodoros }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: col.systemImage).font(.caption2)
                Text(col.title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(items.count)").font(.caption2).foregroundColor(.secondary)
                if charge > 0 { Text("· \(charge)🍅").font(.caption2).foregroundColor(.secondary) }
            }
            if fillsAvailableSpace {
                ScrollView { cards(items).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                cards(items)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let t = dragged else { return false }
            col.assign(t)
            onChanged()
            dragged = nil
            return true
        }
    }

    @ViewBuilder
    private func cards(_ items: [ActionTask]) -> some View {
        if items.isEmpty {
            Text("—").font(.caption2).foregroundColor(.secondary)
        } else {
            VStack(spacing: 6) { ForEach(items) { task in card(task) } }
        }
    }

    private func card(_ task: ActionTask) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { onToggle(task) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.caption).lineLimit(3)
                HStack(spacing: 6) {
                    if task.isUrgent || task.isImportant {
                        Circle()
                            .fill(EisenhowerBoard.quadrantColor(urgent: task.isUrgent, important: task.isImportant))
                            .frame(width: 7, height: 7)
                    }
                    if let name = task.collaborator?.name {
                        Label(name, systemImage: "person.fill")
                            .font(.caption2).foregroundColor(.secondary).labelStyle(.titleAndIcon)
                    }
                    if task.pomodoros > 0 {
                        Text("\(task.pomodoros)🍅").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
        .onDrag {
            dragged = task
            return NSItemProvider(object: NSString(string: "task"))
        }
    }
}
