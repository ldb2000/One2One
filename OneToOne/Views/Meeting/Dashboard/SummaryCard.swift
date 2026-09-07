import SwiftUI

/// Carte « Résumé » du dashboard : résumé court (≤10 lignes) de la réunion,
/// généré à la demande via l'LLM (`AIClient`, provider des Réglages). Persisté
/// dans `meeting.shortSummary` (indépendant du Rapport complet).
struct SummaryCard: View {
    let meeting: Meeting
    let settings: AppSettings
    var isEditing: Bool = false
    /// Persistance déléguée au parent (même contexte SwiftData).
    var saveContext: () -> Void = {}

    @ObservedObject private var live = LiveTranscriptionService.shared
    @State private var isGenerating = false
    @State private var errorMessage: String?

    /// Source du résumé : transcript fusionné, sinon brut.
    private var transcriptSource: String { Self.transcriptSource(for: meeting) }

    var body: some View {
        DashboardCard(title: "Résumé",
                      systemImage: "text.line.first.and.arrowtriangle.forward",
                      isEditing: isEditing) {
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Label(meeting.shortSummary.isEmpty ? "Générer" : "Régénérer",
                          systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(isGenerating || live.isLive || transcriptSource.isEmpty)
            .help(transcriptSource.isEmpty
                  ? "Transcris d'abord la réunion"
                  : "Résume la réunion en 10 lignes maximum")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
                if meeting.shortSummary.isEmpty {
                    Text(transcriptSource.isEmpty
                         ? "Transcris la réunion, puis génère un résumé court."
                         : "Aucun résumé. Clique sur « Générer ».")
                        .font(.body).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        // Rendu markdown (puces, gras, titres) plutôt que texte brut.
                        MarkdownText(markdown: meeting.shortSummary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: .infinity)
                }
            }
        }
    }

    @MainActor
    private func generate() async {
        isGenerating = true
        errorMessage = nil
        do {
            try await Self.generate(meeting: meeting, settings: settings)
            saveContext()
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    /// La source du résumé : transcript fusionné, sinon brut. Extraite de
    /// l'instance pour que le mode Relire de l'espace Réunion emploie **la
    /// même** — deux définitions du « texte de la réunion » finiraient par
    /// produire deux résumés différents. Comportement inchangé : pas de repli
    /// sur les notes live.
    static func transcriptSource(for meeting: Meeting) -> String {
        meeting.mergedTranscript.isEmpty ? meeting.rawTranscript : meeting.mergedTranscript
    }

    /// Écrit `meeting.shortSummary`. Ne sauvegarde pas : l'appelant décide
    /// quand persister (la carte le fait aussitôt, le mode Relire aussi).
    ///
    /// Sans texte à résumer, ne fait rien plutôt que d'appeler le modèle pour
    /// rien.
    @MainActor
    static func generate(meeting: Meeting, settings: AppSettings) async throws {
        let source = transcriptSource(for: meeting)
        guard !source.isEmpty else { return }
        let prompt = """
        Résume la réunion suivante en 10 lignes maximum, en français, sous forme de \
        puces concises. Va à l'essentiel : sujets abordés, décisions, actions à suivre. \
        Ne réponds qu'avec le résumé, sans préambule.

        \(source)
        """
        let result = try await AIClient.send(prompt: prompt, settings: settings)
        meeting.shortSummary = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
