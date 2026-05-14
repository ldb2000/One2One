import SwiftUI
import SwiftData

/// Read-only popover with two write actions: complete the task or open the
/// source Meeting (if any). Edits remain in ActionsListView.
struct UrgentActionPopover: View {
    @Bindable var task: ActionTask
    let onComplete: () -> Void
    let onOpenMeeting: (Meeting) -> Void
    let onDismiss: () -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(.headline)

            HStack(spacing: 12) {
                if let project = task.project { Label(project.name, systemImage: "folder").font(.caption) }
                if let collab = task.collaborator { Label(collab.name, systemImage: "person.fill").font(.caption) }
                if let due = task.dueDate {
                    Label(Self.dateFmt.string(from: due), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(due < Date() ? .red : .secondary)
                }
            }
            .foregroundColor(.secondary)

            if !task.comments.isEmpty {
                Divider()
                Text("Commentaires").font(.caption.bold()).foregroundColor(.secondary)
                let recent = task.comments.sorted { $0.date > $1.date }.prefix(3)
                ForEach(Array(recent), id: \.persistentModelID) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Text(Self.dateFmt.string(from: c.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 84, alignment: .leading)
                        Text(c.text).font(.caption)
                    }
                }
            }

            Divider()
            HStack {
                Button("Terminer ✓") {
                    onComplete()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                Button("Ouvrir Meeting ↗") {
                    if let m = task.meeting { onOpenMeeting(m) }
                    onDismiss()
                }
                .disabled(task.meeting == nil)
                Spacer()
                Button("Fermer") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}
