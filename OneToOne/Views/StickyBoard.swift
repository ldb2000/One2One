import SwiftUI
import UniformTypeIdentifiers

/// Vue « Post-it » groupable et éditable. Les actions ouvertes sont réparties en
/// sections selon `columns` (destinataire/projet/collaborateur). Chaque post-it
/// est éditable (titre inline + menu ⋯), et glissable vers une autre section pour
/// réassigner le champ de regroupement.
struct StickyBoard: View {
    let tasks: [ActionTask]
    let columns: [KanbanColumn]
    let allCollaborators: [Collaborator]
    var onToggle: (ActionTask) -> Void
    var onChanged: () -> Void
    var onDelete: (ActionTask) -> Void
    var fillsAvailableSpace: Bool = false

    @State private var dragged: ActionTask?

    /// Couleur pastel du post-it selon le destinataire.
    static func noteColor(_ audience: ActionAudience) -> Color {
        switch audience {
        case .moi:           return Color.yellow.opacity(0.22)
        case .collaborateur: return Color.green.opacity(0.18)
        case .chef:          return Color.orange.opacity(0.20)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(columns) { col in section(col) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func section(_ col: KanbanColumn) -> some View {
        let items = tasks
            .filter { !$0.isCompleted && col.contains($0) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let charge = items.reduce(0) { $0 + $1.pomodoros }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: col.systemImage).font(.caption2)
                Text(col.title).font(.caption.weight(.semibold)).tracking(0.5)
                Spacer()
                Text("\(items.count)").font(.caption2).foregroundColor(.secondary)
                if charge > 0 { Text("· \(charge)🍅").font(.caption2).foregroundColor(.secondary) }
            }
            .foregroundColor(.secondary)

            if items.isEmpty {
                Text("Déposer une action ici…")
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.04)))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: fillsAvailableSpace ? 200 : 150), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(items) { task in note(task) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let t = dragged else { return false }
            col.assign(t)
            onChanged()
            dragged = nil
            return true
        }
    }

    private func note(_ task: ActionTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { onToggle(task) } label: {
                    Image(systemName: "circle").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                if task.isUrgent || task.isImportant {
                    Circle()
                        .fill(EisenhowerBoard.quadrantColor(urgent: task.isUrgent, important: task.isImportant))
                        .frame(width: 7, height: 7)
                }
                Spacer(minLength: 0)
                if task.pomodoros > 0 {
                    Text("\(task.pomodoros)🍅").font(.caption2).foregroundColor(.secondary)
                }
                noteMenu(task)
            }
            EditableTextField(placeholder: "Action…", text: Bindable(task).title)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let name = task.collaborator?.name {
                    Label(name, systemImage: "person.fill").labelStyle(.titleAndIcon).lineLimit(1)
                }
                if let due = task.dueDate {
                    Label(Self.shortDate(due), systemImage: "calendar").labelStyle(.titleAndIcon)
                }
            }
            .font(.caption2).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Self.noteColor(task.destinataire)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .onDrag {
            dragged = task
            return NSItemProvider(object: NSString(string: "task"))
        }
    }

    private func noteMenu(_ task: ActionTask) -> some View {
        Menu {
            Section("Destinataire") {
                ForEach(ActionAudience.allCases, id: \.self) { a in
                    Button {
                        task.destinataire = a
                        if a != .collaborateur { task.collaborator = nil }
                        onChanged()
                    } label: {
                        if task.destinataire == a { Label(a.label, systemImage: "checkmark") }
                        else { Label(a.label, systemImage: a.systemImage) }
                    }
                }
            }
            if !allCollaborators.isEmpty {
                Menu("Assigner à") {
                    Button("Non assigné") { task.collaborator = nil; onChanged() }
                    ForEach(allCollaborators.filter { !$0.isArchived }) { c in
                        Button(c.name) {
                            task.collaborator = c
                            task.destinataire = .collaborateur
                            onChanged()
                        }
                    }
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { task.isUrgent }, set: { task.isUrgent = $0; onChanged() })) {
                Label("Urgent", systemImage: "exclamationmark")
            }
            Toggle(isOn: Binding(get: { task.isImportant }, set: { task.isImportant = $0; onChanged() })) {
                Label("Important", systemImage: "star")
            }
            Menu("Charge") {
                ForEach([0, 1, 2, 3, 4, 6, 8], id: \.self) { n in
                    Button(n == 0 ? "Aucune" : "\(n) 🍅") { task.pomodoros = n; onChanged() }
                }
            }
            Divider()
            Button(role: .destructive) { onDelete(task) } label: { Label("Supprimer", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "dd/MM"; return f
    }()
    private static func shortDate(_ d: Date) -> String { df.string(from: d) }
}
