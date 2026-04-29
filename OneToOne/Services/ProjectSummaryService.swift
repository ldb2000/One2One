import Foundation

struct ProjectSummaryResult {
    var detailedSummary: String
    var keySignals: [String]
    var risks: [String]
    var recommendedActions: [String]
}

enum ProjectSummaryService {
    static func generate(
        project: Project,
        meetings: [Meeting],
        mails: [ProjectMail],
        settings: AppSettings
    ) async throws -> ProjectSummaryResult {
        let prompt = buildPrompt(project: project, meetings: meetings, mails: mails)
        let raw = try await AIClient.send(prompt: prompt, settings: settings)
        return parse(raw)
    }

    private static func buildPrompt(project: Project, meetings: [Meeting], mails: [ProjectMail]) -> String {
        let meetingBlocks = meetings
            .sorted(by: { $0.date > $1.date })
            .prefix(12)
            .map { meeting in
                let title = meeting.title.isEmpty ? "Réunion sans titre" : meeting.title
                let summary = String(meeting.summary.prefix(1200))
                let decisions = meeting.decisions.prefix(8).joined(separator: " | ")
                let tasks = meeting.tasks.filter { !$0.isCompleted }.map(\.title).prefix(8).joined(separator: " | ")
                return """
                - Date: \(meeting.date.formatted(date: .abbreviated, time: .shortened))
                  Titre: \(title)
                  Résumé: \(summary)
                  Décisions: \(decisions)
                  Actions ouvertes: \(tasks)
                """
            }
            .joined(separator: "\n")

        let mailBlocks = mails
            .sorted(by: { $0.dateReceived > $1.dateReceived })
            .prefix(20)
            .map { mail in
                let subject = mail.subject.isEmpty ? "(sans sujet)" : mail.subject
                let body = String(mail.body.prefix(1200))
                return """
                - Date: \(mail.dateReceived.formatted(date: .abbreviated, time: .shortened))
                  Sujet: \(subject)
                  Expéditeur: \(mail.sender)
                  Extrait: \(body)
                """
            }
            .joined(separator: "\n")

        let projectContext = """
        Code: \(project.code)
        Nom: \(project.name)
        Domaine: \(project.domain)
        Sponsor: \(project.sponsor)
        Type: \(project.projectType)
        Phase: \(project.phase)
        Statut: \(project.status)
        Risque déclaré: \(project.riskLevel ?? "non renseigné")
        Description risque: \(project.riskDescription ?? "")
        Commentaire libre: \(project.comment ?? "")
        Informations complémentaires: \(project.additionalInfo ?? "")
        """

        return """
        Tu es assistant PMO. Génère une fiche projet détaillée et actionnable en français.

        Contexte projet:
        \(projectContext)

        Synthèses de réunions liées au projet:
        \(meetingBlocks.isEmpty ? "Aucune réunion disponible" : meetingBlocks)

        Mails liés au projet:
        \(mailBlocks.isEmpty ? "Aucun mail disponible" : mailBlocks)

        Réponds UNIQUEMENT en JSON valide:
        {
          "detailedSummary": "texte structuré en 3 à 6 paragraphes, factuel, détaillé",
          "keySignals": ["signal 1", "signal 2"],
          "risks": ["risque 1", "risque 2"],
          "recommendedActions": ["action 1", "action 2"]
        }

        Contraintes:
        - Pas d'invention: si info absente, indique l'incertitude.
        - Priorise les éléments récents.
        - Les actions doivent être concrètes et pilotables.
        - Ne renvoie aucun texte hors JSON.
        """
    }

    private static func parse(_ raw: String) -> ProjectSummaryResult {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            return ProjectSummaryResult(detailedSummary: cleaned, keySignals: [], risks: [], recommendedActions: [])
        }

        struct Payload: Decodable {
            var detailedSummary: String?
            var keySignals: [String]?
            var risks: [String]?
            var recommendedActions: [String]?
        }

        if let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            return ProjectSummaryResult(
                detailedSummary: decoded.detailedSummary ?? "",
                keySignals: decoded.keySignals ?? [],
                risks: decoded.risks ?? [],
                recommendedActions: decoded.recommendedActions ?? []
            )
        }

        return ProjectSummaryResult(detailedSummary: cleaned, keySignals: [], risks: [], recommendedActions: [])
    }

    private static func stripCodeFence(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        if !lines.isEmpty { lines.removeFirst() }
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
