import SwiftUI

/// Matrice d'Eisenhower réutilisable : les 4 quadrants urgent×important.
/// - `fillsAvailableSpace == false` (défaut) : grille compacte qui grandit avec
///   le contenu (l'appelant l'enveloppe dans un ScrollView) — pour la carte réunion.
/// - `fillsAvailableSpace == true` : vrai 2×2 qui remplit la hauteur dispo, chaque
///   quadrant ayant son propre ascenseur — pour l'écran Actions plein.
struct EisenhowerBoard: View {
    let tasks: [ActionTask]
    var onToggle: (ActionTask) -> Void
    var fillsAvailableSpace: Bool = false

    private struct Quad { let urgent: Bool; let important: Bool; let title: String }
    private let quads: [Quad] = [
        Quad(urgent: true,  important: true,  title: "Urgent & important"),
        Quad(urgent: false, important: true,  title: "Important — à planifier"),
        Quad(urgent: true,  important: false, title: "Urgent — à déléguer"),
        Quad(urgent: false, important: false, title: "Ni urgent ni important"),
    ]

    /// Couleur d'accent d'un quadrant Eisenhower.
    static func quadrantColor(urgent: Bool, important: Bool) -> Color {
        switch (urgent, important) {
        case (true, true):   return .red
        case (false, true):  return .orange
        case (true, false):  return .blue
        default:             return .gray
        }
    }

    var body: some View {
        if fillsAvailableSpace {
            VStack(spacing: 10) {
                HStack(spacing: 10) { box(quads[0]); box(quads[1]) }
                HStack(spacing: 10) { box(quads[2]); box(quads[3]) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 10) {
                ForEach(quads.indices, id: \.self) { i in box(quads[i]) }
            }
        }
    }

    @ViewBuilder
    private func box(_ q: Quad) -> some View {
        let items = tasks
            .filter { !$0.isCompleted && $0.isUrgent == q.urgent && $0.isImportant == q.important }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let color = Self.quadrantColor(urgent: q.urgent, important: q.important)
        let charge = items.reduce(0) { $0 + $1.pomodoros }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(q.title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)").font(.caption2).foregroundColor(.secondary)
                }
                if charge > 0 { Text("· \(charge) 🍅").font(.caption2).foregroundColor(.secondary) }
            }
            if fillsAvailableSpace {
                ScrollView {
                    itemsList(items)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                itemsList(items)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: fillsAvailableSpace ? nil : 90)
        .frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func itemsList(_ items: [ActionTask]) -> some View {
        if items.isEmpty {
            Text("—").font(.caption2).foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { task in row(task) }
            }
        }
    }

    private func row(_ task: ActionTask) -> some View {
        HStack(spacing: 6) {
            Button { onToggle(task) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            Text(task.title).font(.caption).lineLimit(2)
            Spacer(minLength: 4)
            if task.pomodoros > 0 {
                Text("\(task.pomodoros)🍅").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
