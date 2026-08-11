import Foundation
import SwiftData

/// Service de reformulation IA des notes d'entretien et de génération
/// d'exports hebdomadaires, basé sur les prompts configurables d'`AppSettings`.
class AIReformulationService {

    /// Reformule des notes brutes via l'IA et en extrait les actions taguées
    /// `[ACTION]` dans la réponse.
    func reformulate(notes: String, settings: AppSettings) async throws -> ReformulationResult {
        let prompt = settings.reformulatePrompt
            .replacingOccurrences(of: "{{notes}}", with: notes)

        let response = try await AIClient.send(prompt: prompt, settings: settings)
        return parseReformulation(response)
    }

    /// Construit un export hebdomadaire markdown à partir des réunions tenues
    /// (triées par date, actions incluses) puis le fait synthétiser par l'IA.
    ///
    /// Bâti autrefois sur `Interview`, supprimé le 2026-08-11 : ses lignes
    /// étaient vides, l'export produisait donc des en-têtes sans corps. La
    /// matière vit dans les réunions ; le montage du texte est vérifiable à
    /// part, dans `WeeklyExportText`.
    ///
    /// Le jeton du prompt reste `{{interviews}}` : il est écrit dans le
    /// `weeklyExportPrompt` que l'utilisateur a enregistré, et le renommer
    /// couperait silencieusement l'interpolation de son prompt.
    func generateWeeklyExport(meetings: [Meeting], settings: AppSettings) async throws -> String {
        let prompt = settings.weeklyExportPrompt
            .replacingOccurrences(of: "{{interviews}}", with: WeeklyExportText.build(meetings: meetings))

        return try await AIClient.send(prompt: prompt, settings: settings)
    }

    private func parseReformulation(_ text: String) -> ReformulationResult {
        var actions: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[ACTION]") {
                let action = trimmed.replacingOccurrences(of: "[ACTION]", with: "").trimmingCharacters(in: .whitespaces)
                if !action.isEmpty { actions.append(action) }
            }
        }
        return ReformulationResult(reformulatedNotes: text, extractedActions: actions)
    }
}

/// Résultat d'une reformulation : notes reformulées + actions extraites des
/// lignes taguées `[ACTION]`.
struct ReformulationResult {
    let reformulatedNotes: String
    let extractedActions: [String]
}
