import Foundation
import os
import SwiftData

private let reportLog = Logger(subsystem: "com.onetoone.app", category: "report")

// MARK: - MeetingReportData

/// Résultat structuré du pipeline de post-processing IA d'une réunion.
/// Non persisté en l'état : les champs sont routés vers `Meeting.summary`,
/// `keyPoints`, `decisions`, etc., et vers la création d'`ActionTask`/`ProjectAlert`.
struct MeetingReportData {
    var summary: String
    var keyPoints: [String]
    var decisions: [String]
    var openQuestions: [String]
    var actions: [ActionProposal]
    var alerts: [AlertProposal]

    struct ActionProposal {
        var title: String
        var assignee: String?
        var deadlineISO: String?
    }

    struct AlertProposal {
        var title: String
        var detail: String
        var severity: String    // Critique | Élevé | Modéré | Faible
    }
}

// MARK: - AIReportService

/// Pipeline de post-processing d'une réunion : transcription mergée + contexte
/// → résumé ≥150 mots / points clés / décisions / questions ouvertes /
/// actions / alertes. Sortie JSON stricte parsée ensuite.
struct AIReportService {

    /// Longueur cible du résumé : au moins 150 mots, et ~20 mots par minute.
    /// Cap raisonnable à 800 mots pour éviter les longueurs absurdes.
    static func targetSummaryWords(durationSeconds: Int) -> Int {
        let minutes = max(1, durationSeconds / 60)
        return min(800, max(150, minutes * 20))
    }

    /// Génère le rapport structuré.
    /// - Parameters:
    ///   - mergedTranscript: sortie `NoteMergeService.merge(...)`.
    ///   - meetingKind: contexte (project / oneToOne / work / global).
    ///   - durationSeconds: pour dimensionner la longueur du résumé.
    ///   - projectName: si `.project`.
    ///   - participantsDescription: liste texte des participants.
    ///   - customPrompt: prompt additionnel fourni par l'utilisateur pour cette réunion.
    ///   - historicalContext: extraits de réunions précédentes (RAG, Phase 8).
    static func generate(
        mergedTranscript: String,
        meetingKind: MeetingKind,
        durationSeconds: Int,
        projectName: String? = nil,
        participantsDescription: String = "",
        customPrompt: String = "",
        historicalContext: String = "",
        attachmentsContext: String = "",
        settings: AppSettings,
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> MeetingReportData {
        let words = targetSummaryWords(durationSeconds: durationSeconds)
        let prompt = buildPrompt(
            mergedTranscript: mergedTranscript,
            meetingKind: meetingKind,
            targetWords: words,
            projectName: projectName,
            participantsDescription: participantsDescription,
            customPrompt: customPrompt,
            historicalContext: historicalContext,
            attachmentsContext: attachmentsContext
        )

        reportLog.info("generate: kind=\(meetingKind.rawValue, privacy: .public) duration=\(durationSeconds)s targetWords=\(words)")

        let raw = try await AIClient.send(prompt: prompt, settings: settings, onProgress: onProgress)
        return parse(raw)
    }

    /// Template-driven report generation. Resolves `meeting.reportTemplate`
    /// (or default by kind), injects history + variables, then calls
    /// `AIClient`. Returns parsed `MeetingReportData`.
    @MainActor
    static func generate(
        meeting: Meeting,
        in context: ModelContext,
        settings: AppSettings,
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> MeetingReportData {
        let template = meeting.reportTemplate ?? defaultTemplate(for: meeting.kind, in: context)
        let history = template.map { HistoryContextBuilder.build(for: meeting, template: $0, in: context) } ?? ""
        let body = template?.promptBody ?? ""
        let sections = template?.sections ?? []

        // 1. Resolve {{vars}} in the body
        var resolved = TemplateVariableResolver.resolve(prompt: body, for: meeting, in: context)

        // 2. Substitute {{historique_n}} with the history bloc
        resolved = resolved.replacingOccurrences(of: "{{historique_n}}", with: history)
        resolved = resolved.replacingOccurrences(of: "{{project.historique_n}}", with: history)

        // 3. Append the sections schema so the LLM structures its output
        var sectionsBlock = ""
        if !sections.isEmpty {
            sectionsBlock = "\n\n# Sections attendues (respecte cet ordre, un # par titre):\n"
            for (idx, s) in sections.enumerated() {
                sectionsBlock += "\(idx + 1). **\(s.title)** — \(s.hint)\n"
            }
        }

        let finalPrompt = """
        Tu es l'assistant de synthèse de OneToOne.

        \(resolved)
        \(sectionsBlock)

        Produis un compte-rendu en markdown structuré autour des sections demandées,
        en français, concis et factuel.
        """

        reportLog.info("generate(meeting): template=\(template?.name ?? "default", privacy: .public) historyChars=\(history.count)")
        let raw = try await AIClient.send(prompt: finalPrompt, settings: settings, onProgress: onProgress)
        return parse(raw)
    }

    @MainActor
    private static func defaultTemplate(for kind: MeetingKind, in context: ModelContext) -> ReportTemplate? {
        let templateKind: ReportTemplateKind
        switch kind {
        case .global:    templateKind = .general
        case .oneToOne:  templateKind = .oneToOne
        case .manager:   templateKind = .manager
        case .project:   templateKind = .copil
        case .work:      templateKind = .general
        }
        let raw = templateKind.rawValue
        let descriptor = FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true && $0.kindRaw == raw && !$0.isArchived }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Prompt

    private static func buildPrompt(
        mergedTranscript: String,
        meetingKind: MeetingKind,
        targetWords: Int,
        projectName: String?,
        participantsDescription: String,
        customPrompt: String,
        historicalContext: String,
        attachmentsContext: String
    ) -> String {
        var ctx = ""
        if let p = projectName, !p.isEmpty {
            ctx += "Projet associé : \(p)\n"
        }
        if !participantsDescription.isEmpty {
            ctx += "Participants : \(participantsDescription)\n"
        }
        if !historicalContext.isEmpty {
            ctx += "\nContexte historique (extraits de réunions précédentes) :\n\(historicalContext)\n"
        }
        if !attachmentsContext.isEmpty {
            ctx += "\nDocuments joints à cette réunion (prime sur la transcription pour les chiffres, dates, noms propres) :\n\(attachmentsContext)\n"
        }

        let customBlock = customPrompt.isEmpty ? "" : """

        Instructions spécifiques à cette réunion :
        \(customPrompt)

        """

        return """
        Tu es l'assistant de synthèse de OneToOne (gestion de projets + suivi collaborateurs).

        Type de réunion : \(meetingKind.label)
        \(ctx)
        \(customBlock)
        Analyse la transcription ci-dessous (qui contient la sortie STT + les
        notes prises en live par l'utilisateur). Les notes utilisateur priment
        sur la transcription en cas d'ambiguïté.

        ---
        \(mergedTranscript)
        ---

        Réponds exclusivement en JSON strict, conforme au schéma suivant :

        {
          "summary": "résumé dense de la réunion, français, environ \(targetWords) mots",
          "keyPoints": ["point clé 1", "point clé 2", ...],
          "decisions": ["décision 1", ...],
          "openQuestions": ["question 1", ...],
          "actions": [
            {"title": "action à mener", "assignee": "nom du responsable ou null", "deadline": "YYYY-MM-DD ou null"}
          ],
          "alerts": [
            {"title": "titre de l'alerte", "detail": "description", "severity": "Critique|Élevé|Modéré|Faible"}
          ]
        }

        Contraintes :
        - Le résumé doit faire au minimum \(targetWords) mots, structuré en 2-4 paragraphes.
        - N'invente rien : si une info manque, omets-la. Les listes peuvent être vides.
        - Toutes les chaînes en français.
        - Pas de texte avant ou après le JSON. Pas de bloc markdown ``` ```.
        """
    }

    // MARK: - Parsing

    static func parse(_ raw: String) -> MeetingReportData {
        let cleaned = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            reportLog.error("parse: encoding UTF-8 impossible")
            return MeetingReportData(summary: cleaned, keyPoints: [], decisions: [], openQuestions: [], actions: [], alerts: [])
        }

        struct Raw: Decodable {
            var summary: String?
            var keyPoints: [String]?
            var decisions: [String]?
            var openQuestions: [String]?
            var actions: [RawAction]?
            var alerts: [RawAlert]?
        }
        struct RawAction: Decodable {
            var title: String
            var assignee: String?
            var deadline: String?
        }
        struct RawAlert: Decodable {
            var title: String
            var detail: String
            var severity: String?
        }

        do {
            let decoded = try JSONDecoder().decode(Raw.self, from: data)
            return MeetingReportData(
                summary: decoded.summary ?? "",
                keyPoints: decoded.keyPoints ?? [],
                decisions: decoded.decisions ?? [],
                openQuestions: decoded.openQuestions ?? [],
                actions: (decoded.actions ?? []).map {
                    MeetingReportData.ActionProposal(title: $0.title, assignee: $0.assignee, deadlineISO: $0.deadline)
                },
                alerts: (decoded.alerts ?? []).map {
                    MeetingReportData.AlertProposal(title: $0.title, detail: $0.detail, severity: $0.severity ?? "Modéré")
                }
            )
        } catch {
            reportLog.error("parse: JSON invalide \(error.localizedDescription, privacy: .public). Fallback : tout le texte dans summary.")
            return MeetingReportData(summary: cleaned, keyPoints: [], decisions: [], openQuestions: [], actions: [], alerts: [])
        }
    }

    /// Enlève un éventuel bloc de code markdown `\`\`\`json … \`\`\`` autour du JSON.
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
