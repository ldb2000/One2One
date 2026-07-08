import SwiftUI
import SwiftData

/// File de validation des mails suggérés par le scan automatique.
/// Chaque ligne : sujet/expéditeur/date + projet (modifiable) + Valider/Ignorer.
/// « Valider » récupère le corps + PJ puis matérialise un `ProjectMail`
/// (pipeline `ProjectMailStore.save`, chunking + embedding inclus).
struct MailSuggestionReviewSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MailIndexSuggestion.dateReceived, order: .reverse)
    private var suggestions: [MailIndexSuggestion]
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var busyIDs: Set<PersistentIdentifier> = []
    @State private var errorMessage: String?

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mails à valider").font(.headline)
            Text("Le scan automatique a trouvé des mails probablement liés à un projet. Valider indexe le mail (RAG) ; Ignorer l'écarte définitivement.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            if suggestions.isEmpty {
                Text("Aucune suggestion en attente.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Groupées par projet suggéré (spec §6), tri par date dans
                // chaque groupe (le @Query trie déjà par date desc).
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedSuggestions, id: \.0) { projectName, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(projectName)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(items) { suggestion in
                                    row(suggestion)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }

            HStack {
                Spacer()
                Button("Fermer", action: onClose)
            }
        }
        .padding(20)
        .frame(minWidth: 680)
    }

    /// Groupes (nom de projet, suggestions) triés par nom ; l'ordre par date
    /// est préservé à l'intérieur de chaque groupe.
    private var groupedSuggestions: [(String, [MailIndexSuggestion])] {
        Dictionary(grouping: suggestions) { $0.suggestedProject?.name ?? "Sans projet" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    @ViewBuilder
    private func row(_ suggestion: MailIndexSuggestion) -> some View {
        let isBusy = busyIDs.contains(suggestion.persistentModelID)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.subject).font(.callout.bold()).lineLimit(1)
                Text("\(suggestion.sender) · \(suggestion.dateReceived.formatted(date: .abbreviated, time: .shortened)) · conf. \(suggestion.confidence, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !suggestion.preview.isEmpty {
                    Text(suggestion.preview).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { suggestion.suggestedProject },
                set: { suggestion.suggestedProject = $0; try? context.save() }
            )) {
                ForEach(projects) { project in
                    Text(project.name).tag(project as Project?)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Button("Valider") {
                Task { await validate(suggestion) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || suggestion.suggestedProject == nil)

            Button("Ignorer") {
                ignore(suggestion)
            }
            .disabled(isBusy)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
        .overlay(alignment: .trailing) {
            if isBusy { ProgressView().controlSize(.small).padding(.trailing, 6) }
        }
    }

    private func validate(_ suggestion: MailIndexSuggestion) async {
        busyIDs.insert(suggestion.persistentModelID)
        defer { busyIDs.remove(suggestion.persistentModelID) }
        do {
            try await MailSuggestionService.validate(suggestion, in: context)
            errorMessage = nil
        } catch {
            errorMessage = "Validation échouée : \(error.localizedDescription)"
        }
    }

    private func ignore(_ suggestion: MailIndexSuggestion) {
        MailSuggestionService.ignore(suggestion, in: context)
    }
}
