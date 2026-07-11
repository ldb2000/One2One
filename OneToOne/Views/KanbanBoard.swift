import SwiftUI
import UniformTypeIdentifiers

/// Tableau Kanban réutilisable : une colonne par destinataire (Collaborateur /
/// Moi / Chef). Glisser une carte vers une autre colonne change son destinataire.
/// - `fillsAvailableSpace == true` : colonnes qui remplissent la hauteur, chacune
///   avec son ascenseur (écran Actions plein).
/// - `false` (défaut) : colonnes compactes (carte réunion, dans un ScrollView).
struct KanbanBoard: View {
    let tasks: [ActionTask]
    var onToggle: (ActionTask) -> Void
    var onMove: (ActionTask, ActionAudience) -> Void
    var fillsAvailableSpace: Bool = false

    @State private var dragged: ActionTask?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(ActionAudience.allCases, id: \.self) { audience in
                column(audience)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
    }

    private func column(_ audience: ActionAudience) -> some View {
        let items = tasks
            .filter { !$0.isCompleted && $0.destinataire == audience }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let charge = items.reduce(0) { $0 + $1.pomodoros }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: audience.systemImage).font(.caption2)
                Text(audience.sectionTitle).font(.caption.weight(.semibold)).lineLimit(1)
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
            if t.destinataire != audience { onMove(t, audience) }
            dragged = nil
            return true
        }
    }

    @ViewBuilder
    private func cards(_ items: [ActionTask]) -> some View {
        if items.isEmpty {
            Text("—").font(.caption2).foregroundColor(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(items) { task in card(task) }
            }
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
