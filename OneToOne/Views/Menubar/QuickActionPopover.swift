import SwiftUI
import SwiftData

/// Compact popover anchored on the menubar icon — creates an ActionTask.
struct QuickActionPopover: View {
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]

    @State private var title: String = ""
    @State private var project: Project?
    @State private var collaborator: Collaborator?
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nouvelle action").font(.headline)
            TextField("Titre de l'action…", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Picker("", selection: $project) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in
                        Text(p.name).tag(p as Project?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                Picker("", selection: $collaborator) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            HStack {
                Toggle("Échéance", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Annuler") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = ActionTask(title: trimmed, dueDate: hasDueDate ? dueDate : nil)
        task.project = project
        task.collaborator = collaborator
        context.insert(task)
        try? context.save()
        onDismiss()
    }
}
