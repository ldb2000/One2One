import SwiftUI

/// Sheet shown after `ManagerCRGenerator.generate` returns. Lists the actions
/// extracted by the AI; user can edit titles, set/clear due dates, untick to
/// skip. On confirm, the kept actions are materialized into ActionTask via
/// `ManagerCRGenerator.materializeActions`.
struct ManagerActionReviewSheet: View {
    struct DraftAction: Identifiable {
        let id = UUID()
        var title: String
        var dueDate: Date?
        var keep: Bool
    }

    @State var drafts: [DraftAction]
    let onCancel: () -> Void
    let onConfirm: ([ManagerCRGenerator.ExtractedAction]) -> Void

    init(
        actions: [ManagerCRGenerator.ExtractedAction],
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([ManagerCRGenerator.ExtractedAction]) -> Void
    ) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let initial = actions.map {
            DraftAction(
                title: $0.title,
                dueDate: $0.deadlineISO.flatMap(isoFormatter.date(from:)),
                keep: true
            )
        }
        self._drafts = State(initialValue: initial)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Actions demandées par le manager")
                .font(.headline)
            Text("L'IA a proposé les actions ci-dessous. Décoche celles à ignorer, modifie titre / échéance, puis valide.")
                .font(.caption)
                .foregroundColor(.secondary)

            if drafts.isEmpty {
                Text("Aucune action extraite par l'IA.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($drafts) { $draft in
                            HStack(spacing: 8) {
                                Toggle("", isOn: $draft.keep).labelsHidden()
                                TextField("Titre", text: $draft.title).textFieldStyle(.roundedBorder)
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { draft.dueDate ?? Date() },
                                        set: { draft.dueDate = $0 }
                                    ),
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .disabled(!draft.keep)
                                Button {
                                    draft.dueDate = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Retirer la date d'échéance")
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack {
                Spacer()
                Button("Ignorer toutes", action: onCancel)
                Button("Créer les actions") {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withFullDate]
                    let kept: [ManagerCRGenerator.ExtractedAction] = drafts
                        .filter { $0.keep && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { d in
                            ManagerCRGenerator.ExtractedAction(
                                title: d.title,
                                deadlineISO: d.dueDate.map { isoFormatter.string(from: $0) }
                            )
                        }
                    onConfirm(kept)
                }
                .buttonStyle(.borderedProminent)
                .disabled(drafts.allSatisfy { !$0.keep })
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }
}
