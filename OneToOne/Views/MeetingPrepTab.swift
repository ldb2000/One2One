import SwiftUI
import SwiftData

/// Tab "Préparation" d'une réunion. Split 60/40 entre l'éditeur markdown et
/// le panneau contexte. Bouton "Générer brouillon" en bas.
struct MeetingPrepTab: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @State private var showOverwriteConfirm = false
    @State private var isGenerating = false
    @State private var generationError: String?

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        HStack(spacing: 0) {
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            MeetingPrepContextPanel(meeting: meeting)
                .frame(width: 320)
        }
        .alert("Remplacer la préparation actuelle ?", isPresented: $showOverwriteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Remplacer", role: .destructive) { Task { await runGenerate(force: true) } }
        } message: {
            Text("Le brouillon IA va écraser le contenu actuel.")
        }
    }

    /// Volet gauche : éditeur markdown des notes de préparation (sauvegarde à
    /// chaque frappe), message d'erreur éventuel et bouton de génération IA
    /// (demande confirmation si des notes existent déjà).
    @ViewBuilder
    private var editorPane: some View {
        let prepID = "meetingPrep.\(meeting.persistentModelID.hashValue)"
        VStack(spacing: 0) {
            MarkdownToolbar(textViewID: prepID)
                .padding(.horizontal, 8).padding(.top, 6)
            MarkdownEditorView(
                text: Binding(
                    get: { meeting.prepNotes },
                    set: { meeting.prepNotes = $0; saveCtx() }
                ),
                textViewID: prepID
            )
            if let err = generationError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            HStack {
                Spacer()
                Button {
                    if meeting.prepNotes.isEmpty {
                        Task { await runGenerate(force: false) }
                    } else {
                        showOverwriteConfirm = true
                    }
                } label: {
                    Label(isGenerating ? "Génère…" : "Générer brouillon IA",
                          systemImage: "wand.and.stars")
                }
                .disabled(isGenerating)
            }
            .padding(8)
        }
    }

    /// Génère le brouillon de préparation via l'IA et l'écrit dans
    /// `meeting.prepNotes` (+ `prepGeneratedAt`). Gère l'indicateur de
    /// progression et expose toute erreur via `generationError`.
    @MainActor
    private func runGenerate(force: Bool) async {
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }
        do {
            let md = try await AIReportService.generatePrep(
                collab: (meeting.kind == .oneToOne || meeting.kind == .manager)
                    ? meeting.participants.first : nil,
                project: meeting.kind == .project ? meeting.project : nil,
                meeting: meeting,
                in: context,
                settings: settings
            )
            meeting.prepNotes = md
            meeting.prepGeneratedAt = Date()
            saveCtx()
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func saveCtx() {
        try? context.save()
    }
}
