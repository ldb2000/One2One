import SwiftUI
import SwiftData

/// Sheet listant les réunions futures (kind .global/.work surtout) pour
/// ouvrir leur tab Préparation directement.
struct CalendarMeetingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.date, order: .forward) private var allMeetings: [Meeting]
    let onPick: (Meeting) -> Void

    /// Réunions dont l'heure de début planifiée (ou la date) est encore à venir.
    private var futureMeetings: [Meeting] {
        let now = Date()
        return allMeetings.filter { ($0.scheduledStart ?? $0.date) >= now }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choisir une réunion à préparer").font(.headline)
                Spacer()
                Button("Annuler") { dismiss() }
            }
            if futureMeetings.isEmpty {
                Text("Aucune réunion future planifiée.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(futureMeetings, id: \.persistentModelID) { m in
                    Button {
                        onPick(m)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(m.title).font(.body.bold())
                            Text("\(formatDate(m.scheduledStart ?? m.date)) — \(m.kind.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 240)
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 320)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f
    }()

    private func formatDate(_ d: Date) -> String {
        Self.dateFormatter.string(from: d)
    }
}
