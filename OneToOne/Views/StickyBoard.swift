import SwiftUI

/// Vue « Sticky Note » : les actions ouvertes en post-it dans une grille
/// adaptative, colorés par destinataire. Clic sur la coche = terminer.
/// (Positionnement libre à la souris = plus tard ; ici grille propre.)
struct StickyBoard: View {
    let tasks: [ActionTask]
    var onToggle: (ActionTask) -> Void
    var fillsAvailableSpace: Bool = false

    /// Couleur pastel du post-it selon le destinataire.
    static func noteColor(_ audience: ActionAudience) -> Color {
        switch audience {
        case .moi:           return Color.yellow.opacity(0.22)
        case .collaborateur: return Color.green.opacity(0.18)
        case .chef:          return Color.orange.opacity(0.20)
        }
    }

    private var notes: [ActionTask] {
        tasks
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: fillsAvailableSpace ? 200 : 150), spacing: 10)],
            alignment: .leading, spacing: 10
        ) {
            ForEach(notes) { note($0) }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
            }
            Text(task.title).font(.callout).lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let name = task.collaborator?.name {
                    Label(name, systemImage: "person.fill")
                        .labelStyle(.titleAndIcon).lineLimit(1)
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
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "dd/MM"; return f
    }()
    private static func shortDate(_ d: Date) -> String { df.string(from: d) }
}
