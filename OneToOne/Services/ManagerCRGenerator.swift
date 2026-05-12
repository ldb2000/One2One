import Foundation
import SwiftData
import os

private let crLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// Generates the dedicated manager 1:1 CR. Builds a prompt from the checked
/// items + their notes + the meeting transcript, calls the AI, parses the
/// markdown/JSON-actions response, archives the items, and persists a
/// `ManagerMeetingReport`.
@MainActor
enum ManagerCRGenerator {

    enum GenerationError: Error, CustomStringConvertible {
        case noItems
        case missingManagerName
        case wrongMeetingKind

        var description: String {
            switch self {
            case .noItems: return "Cochez au moins un point avant de générer le CR."
            case .missingManagerName: return "Configurez le nom de votre manager dans Paramètres."
            case .wrongMeetingKind: return "Le meeting cible doit être de type 1:1 Manager."
            }
        }
    }

    struct ExtractedAction: Codable {
        let title: String
        let deadlineISO: String?

        enum CodingKeys: String, CodingKey {
            case title
            case deadlineISO = "deadline"
        }
    }

    struct Parsed {
        let markdown: String
        let actions: [ExtractedAction]
    }

    // MARK: - Generate

    @discardableResult
    static func generate(
        meeting: Meeting,
        items: [ManagerReportItem],
        settings: AppSettings,
        context: ModelContext,
        client: AIClientProtocol = AIClient.live
    ) async throws -> ManagerMeetingReport {
        guard meeting.kind == .manager else { throw GenerationError.wrongMeetingKind }
        guard !items.isEmpty else { throw GenerationError.noItems }
        guard !settings.managerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.missingManagerName
        }

        let prompt = buildPrompt(meeting: meeting, items: items, settings: settings)
        let started = Date()
        let raw = try await client.send(prompt: prompt, settings: settings)
        let elapsed = Date().timeIntervalSince(started)
        let parsed = parseResponse(raw)

        let report = ManagerMeetingReport(meeting: meeting)
        report.generatedSummary = parsed.markdown
        report.durationSeconds = elapsed
        report.modelUsed = settings.modelName
        report.extractedActionsJSON = encodeActions(parsed.actions)
        report.itemsSnapshotJSON = encodeItemsSnapshot(items)
        context.insert(report)

        // Archive items now (first save in step 6 of spec section 6.3).
        for item in items {
            item.archivedAt = Date()
            item.archivedInMeeting = meeting
        }

        try context.save()
        crLog.info("generate: report saved, items=\(items.count, privacy: .public) actions=\(parsed.actions.count, privacy: .public) elapsed=\(elapsed, privacy: .public)")
        return report
    }

    // MARK: - Materialize actions (called from sheet of review)

    /// Materialize the actions selected by the user into ActionTask rows.
    /// Called after `generate` once the user has confirmed the action review sheet.
    @discardableResult
    static func materializeActions(
        _ actions: [ExtractedAction],
        in meeting: Meeting,
        context: ModelContext
    ) throws -> [ActionTask] {
        var created: [ActionTask] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        for action in actions {
            let task = ActionTask(title: action.title)
            task.fromManager = true
            task.managerMeeting = meeting
            if let iso = action.deadlineISO,
               let d = isoFormatter.date(from: iso) {
                task.dueDate = d
            }
            context.insert(task)
            created.append(task)
        }
        try context.save()
        return created
    }

    // MARK: - Prompt build

    static func buildPrompt(
        meeting: Meeting,
        items: [ManagerReportItem],
        settings: AppSettings
    ) -> String {
        let transcript: String = {
            let merged = meeting.mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty { return merged }
            return meeting.rawTranscript
        }()

        var itemsBlock = ""
        for (idx, item) in items.enumerated() {
            let tag = item.tag.isEmpty ? "" : " · tag: \(item.tag)"
            let projectLine: String = {
                if let name = item.sourceMeeting?.project?.name { return "Projet: \(name)" }
                return "Projet: n/a"
            }()
            let sourceLine = item.sourceMeeting.map {
                "Source: « \($0.title.isEmpty ? "Réunion sans titre" : $0.title) » du \($0.date.formatted(date: .abbreviated, time: .omitted))"
            } ?? "Source: ajout manuel"
            let notesLine = item.userNotes.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Notes prises pendant le 1:1 : (aucune)"
                : "Notes prises pendant le 1:1 : \(item.userNotes)"
            // Prefer the elaborated/edited text (rédigé à l'ajout) when present;
            // fallback to rawSnippet + contextes for items créés avant l'élaboration.
            let elaborated = item.elaboratedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let coreBlock: String
            if !elaborated.isEmpty {
                coreBlock = """
                \(idx + 1). [\(item.category)\(tag)] \(elaborated)
                   Extrait original: \(item.rawSnippet)
                   \(sourceLine) · \(projectLine)
                   \(notesLine)
                """
            } else {
                coreBlock = """
                \(idx + 1). [\(item.category)\(tag)] \(item.rawSnippet)
                   \(sourceLine) · \(projectLine)
                   Contexte avant: \(item.contextBefore.isEmpty ? "(vide)" : item.contextBefore)
                   Contexte après: \(item.contextAfter.isEmpty ? "(vide)" : item.contextAfter)
                   \(notesLine)
                """
            }
            itemsBlock += coreBlock + "\n\n\n"
        }

        return """
        Tu es l'assistant de OneToOne. Tu produis le compte-rendu d'un 1:1
        avec le manager direct de l'utilisateur. Le compte-rendu doit
        distinguer:
        - les points abordés (avec ce qui a été dit / décidé pour chacun)
        - les actions demandées par le manager (à matérialiser ensuite)
        - les décisions prises
        - les sujets à reporter à la prochaine session

        Réponds UNIQUEMENT en markdown structuré, sections H2.
        À la fin, inclus un bloc JSON ```json { "actions": [...] } ```
        listant les actions demandées par le manager (titre court, due date
        ISO YYYY-MM-DD si mentionnée, sinon null).

        [CONTEXTE GLOBAL]
        Manager : \(settings.managerName)
        Date du 1:1 : \(meeting.date.formatted(date: .complete, time: .shortened))
        Durée : \(meeting.durationSeconds)s

        [POINTS PRÉPARÉS — uniquement les COCHÉS]
        \(itemsBlock.isEmpty ? "(aucun)" : itemsBlock)

        [TRANSCRIPTION DU 1:1 MANAGER]
        \(transcript.isEmpty ? "(transcription absente)" : transcript)

        [INSTRUCTIONS]
        - Pour chaque item, restitue ce qui a été dit en t'appuyant en
          priorité sur les notes prises pendant le 1:1, puis en complétant
          avec la transcription.
        - Si un point coché n'a pas de notes ET aucune trace dans la
          transcription, signale-le explicitement ("non couvert dans la
          transcription").
        - N'invente rien. Si l'info manque, dis-le.

        [PROMPT UTILISATEUR ÉDITABLE]
        \(settings.managerReportPrompt)
        """
    }

    // MARK: - Parse response

    static func parseResponse(_ raw: String) -> Parsed {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fenceRange = trimmed.range(of: "```json", options: .caseInsensitive) else {
            return Parsed(markdown: trimmed, actions: [])
        }
        let beforeFence = String(trimmed[..<fenceRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterFenceStart = trimmed.index(fenceRange.upperBound, offsetBy: 0)
        let after = String(trimmed[afterFenceStart...])
        guard let closingRange = after.range(of: "```") else {
            return Parsed(markdown: beforeFence, actions: [])
        }
        let jsonBody = String(after[..<closingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct Wrapper: Codable { let actions: [ExtractedAction]? }
        guard let data = jsonBody.data(using: .utf8) else {
            return Parsed(markdown: beforeFence, actions: [])
        }
        let actions = (try? JSONDecoder().decode(Wrapper.self, from: data))?.actions ?? []
        return Parsed(markdown: beforeFence, actions: actions)
    }

    // MARK: - Encoding helpers

    private static func encodeActions(_ actions: [ExtractedAction]) -> String {
        guard let data = try? JSONEncoder().encode(actions),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func encodeItemsSnapshot(_ items: [ManagerReportItem]) -> String {
        struct Snap: Codable {
            let stableID: String
            let category: String
            let tag: String
            let rawSnippet: String
            let elaboratedText: String
            let userNotes: String
            let sourceMeetingTitle: String?
        }
        let snaps = items.map {
            Snap(stableID: $0.stableID.uuidString,
                 category: $0.category,
                 tag: $0.tag,
                 rawSnippet: $0.rawSnippet,
                 elaboratedText: $0.elaboratedText,
                 userNotes: $0.userNotes,
                 sourceMeetingTitle: $0.sourceMeeting?.title)
        }
        guard let data = try? JSONEncoder().encode(snaps),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
