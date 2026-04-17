import Foundation
import SwiftData

class AIReformulationService {

    func reformulate(notes: String, settings: AppSettings) async throws -> ReformulationResult {
        let prompt = settings.reformulatePrompt
            .replacingOccurrences(of: "{{notes}}", with: notes)

        let response = try await AIClient.send(prompt: prompt, settings: settings)
        return parseReformulation(response)
    }

    func generateWeeklyExport(interviews: [Interview], settings: AppSettings) async throws -> String {
        var interviewsText = ""
        for interview in interviews.sorted(by: { $0.date < $1.date }) {
            let dateStr = interview.date.formatted(date: .long, time: .omitted)
            let collabName = interview.collaborator?.name ?? "Inconnu"
            let typeStr = interview.type.label
            interviewsText += "### \(dateStr) — \(collabName) (\(typeStr))\n"
            interviewsText += interview.notes + "\n\n"

            if !interview.tasks.isEmpty {
                interviewsText += "Actions:\n"
                for task in interview.tasks {
                    let check = task.isCompleted ? "[x]" : "[ ]"
                    interviewsText += "- \(check) \(task.title)"
                    if let project = task.project {
                        interviewsText += " (Projet: \(project.name))"
                    }
                    interviewsText += "\n"
                }
                interviewsText += "\n"
            }
        }

        let prompt = settings.weeklyExportPrompt
            .replacingOccurrences(of: "{{interviews}}", with: interviewsText)

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

struct ReformulationResult {
    let reformulatedNotes: String
    let extractedActions: [String]
}
