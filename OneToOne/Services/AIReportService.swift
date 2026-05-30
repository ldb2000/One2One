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
    /// - Parameter additionalContext: bloc texte additionnel (ex. RAG sémantique
    ///   issu de `MeetingView.fetchHistoricalContext()`) injecté avant
    ///   l'historique structuré. Vide = pas d'injection.
    @MainActor
    static func generate(
        meeting: Meeting,
        in context: ModelContext,
        settings: AppSettings,
        additionalContext: String = "",
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> MeetingReportData {
        let template = meeting.reportTemplate ?? defaultTemplate(for: meeting.kind, in: context)
        let history = template.map { HistoryContextBuilder.build(for: meeting, template: $0, in: context) } ?? ""
        let preamble = template?.preamble ?? "Tu es l'assistant de synthèse de OneToOne."
        let body = template?.promptBody ?? ""
        let sections = template?.sections ?? []

        // 1. Resolve {{vars}} in the body.
        var resolved = TemplateVariableResolver.resolve(prompt: body, for: meeting, in: context)

        // 2. Historique inline ou append.
        let hasHistoryPlaceholder = resolved.contains("{{historique_n}}")
            || resolved.contains("{{project.historique_n}}")
        resolved = resolved.replacingOccurrences(of: "{{historique_n}}", with: history)
        resolved = resolved.replacingOccurrences(of: "{{project.historique_n}}", with: history)
        var historyAppendix = ""
        if !history.isEmpty, !hasHistoryPlaceholder {
            historyAppendix = "\n\nContexte historique (extraits de réunions précédentes) :\n\(history)\n"
        }
        if !additionalContext.isEmpty {
            historyAppendix += "\n\nContexte sémantique (RAG, extraits pertinents) :\n\(additionalContext)\n"
        }

        // Fallback append du contexte projets si le template ne contient pas
        // `{{collab.projects_context}}`. Si présent, TemplateVariableResolver
        // a déjà fait la substitution dans `resolved`.
        let hasProjectsPlaceholder = body.contains("{{collab.projects_context}}")
        if !hasProjectsPlaceholder {
            let projectsBlock = ProjectsContextBuilder.build(for: meeting, in: context)
            if !projectsBlock.isEmpty {
                historyAppendix += "\n\nContexte projets affectés au collaborateur :\n\(projectsBlock)\n"
            }
        }

        // Fallback append du contexte projets de l'équipe pour les réunions
        // de travail (.work). Si le template ne contient pas
        // `{{team.projects_context}}` mais que la réunion .work a des
        // participants avec projets affectés, append en queue.
        let hasTeamPlaceholder = body.contains("{{team.projects_context}}")
        if !hasTeamPlaceholder {
            let teamBlock = ProjectsContextBuilder.buildForTeam(meeting: meeting, in: context)
            if !teamBlock.isEmpty {
                historyAppendix += "\n\nContexte projets de l'équipe :\n\(teamBlock)\n"
            }
        }

        // Fallback append des passages marqués importants par l'utilisateur.
        // Si le template ne contient pas `{{transcript.highlights}}` mais que
        // la réunion a des segments highlighted, append en queue pour donner
        // au LLM le signal explicite.
        let hasHighlightsPlaceholder = body.contains("{{transcript.highlights}}")
        if !hasHighlightsPlaceholder {
            let highlights = TranscriptHighlightsBuilder.build(meeting: meeting)
            if !highlights.isEmpty {
                historyAppendix += "\n\nPassages marqués importants par l'utilisateur :\n\(highlights)\n"
            }
        }

        // 3. Documents joints (extraction script).
        let attachmentsBlock = buildAttachmentsBlock(
            for: meeting,
            promptLen: resolved.count + historyAppendix.count
        )

        // 4. Sections schema.
        var sectionsBlock = ""
        if !sections.isEmpty {
            sectionsBlock = "\n\n# Sections attendues (respecte cet ordre, un # par titre):\n"
            for (idx, s) in sections.enumerated() {
                sectionsBlock += "\(idx + 1). **\(s.title)** — \(s.hint)\n"
            }
        }

        // 5. Prompt final — markdown libre, plus de schéma JSON.
        let finalPrompt = """
        \(preamble)

        \(resolved)\(historyAppendix)\(attachmentsBlock)
        \(sectionsBlock)

        Produis un rapport en markdown français, structuré autour des sections
        demandées ci-dessus, concis et factuel. Pas de JSON, pas d'en-tête XML —
        uniquement le markdown du rapport.
        """

        reportLog.info("generate(meeting): template=\(template?.name ?? "default", privacy: .public) historyChars=\(history.count) attachmentsChars=\(attachmentsBlock.count)")
        let markdown = try await AIClient.send(prompt: finalPrompt, settings: settings, onProgress: onProgress)

        // 6. Extraction structurée 2e passe (Task 6 fournira la fonction).
        let extracted = await extractStructured(markdown: markdown, meeting: meeting, settings: settings)

        return MeetingReportData(
            summary: markdown,
            keyPoints: extracted.keyPoints,
            decisions: extracted.decisions,
            openQuestions: extracted.openQuestions,
            actions: extracted.actions,
            alerts: extracted.alerts
        )
    }

    /// Concatène les `extractedText` des attachments du meeting (pptx, pdf,
    /// docx…) en un bloc markdown injecté dans le prompt de génération.
    /// Plafonné par `promptLen` pour ne pas dépasser un budget total de
    /// ~30 000 caractères. Au-delà → on saute le bloc, le RAG (indexé
    /// séparément) prend le relais via `additionalContext`.
    private static func buildAttachmentsBlock(for meeting: Meeting, promptLen: Int) -> String {
        let docs = meeting.attachments.compactMap { att -> (String, String)? in
            let txt = att.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !txt.isEmpty else { return nil }
            return (att.fileName, txt)
        }
        guard !docs.isEmpty else { return "" }
        let totalBudget = 30_000 - promptLen
        guard totalBudget > 1000 else { return "" }
        let perDoc = max(500, totalBudget / docs.count)
        var block = "\n\n# Documents joints à cette réunion\n"
        for (name, txt) in docs {
            block += "## \(name)\n"
            if txt.count > perDoc {
                block += String(txt.prefix(perDoc))
                    + "\n\n[… document tronqué : \(txt.count - perDoc) caractères omis, voir le RAG …]\n\n"
                print("[AIReport] Document '\(name)' tronqué : \(txt.count - perDoc)/\(txt.count) caractères omis.")
            } else {
                block += txt + "\n\n"
            }
        }
        return block
    }

    // MARK: - Critique pass (inspiré tevslin/meeting-reporter)
    //
    // Une seconde passe LLM qui audite un draft de rapport contre des critères
    // stricts (porteurs nommés, pas d'invention, sections vides supprimées,
    // nuance préservée). Renvoie soit `nil` si le draft est jugé OK, soit un
    // bloc texte structuré listant les problèmes à corriger.

    /// Résultat du critique. `nil` = rapport accepté tel quel.
    static func critique(
        draft: String,
        mergedTranscript: String,
        participantsDescription: String,
        settings: AppSettings,
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> String? {
        let prompt = """
        Tu es un relecteur exigeant de comptes-rendus de réunion. Ton rôle
        est de pointer les défauts du brouillon, PAS de le réécrire.

        Critères stricts :
        1. Chaque action doit avoir un porteur NOMMÉMENT identifié parmi les
           participants réels ci-dessous. Aucune mention « Équipe de pilotage »,
           « À définir » est tolérée seulement si la transcription n'indique
           vraiment personne.
        2. Aucune information ne doit être inventée. Tout doit être traçable
           à la transcription. Si tu repères un chiffre, une date, un nom
           absent de la transcription → c'est une hallucination.
        3. Les nuances et désaccords doivent être préservés. Si deux
           participants ont nuancé un point, le rapport doit le restituer.
        4. Les sections vides ou inutiles (« (aucune) ») doivent être omises.
        5. Pour les votes ou décisions partagées, les noms doivent être cités.
        6. Pas d'éditorialisation : le ton doit rester factuel.

        Participants réels de la réunion :
        \(participantsDescription)

        Transcription source (référence pour vérifier l'absence d'invention) :
        ---
        \(mergedTranscript)
        ---

        Brouillon à critiquer :
        ---
        \(draft)
        ---

        Si le brouillon respecte TOUS les critères, réponds EXACTEMENT par le
        mot `OK` (sans guillemets, sans autre texte).

        Sinon, liste les défauts sous forme de puces courtes, regroupées par
        critère (ex. « Action 3 — porteur générique 'Équipe de pilotage' »).
        Reste concis : maximum 12 puces. N'écris pas de version corrigée.
        """

        reportLog.info("critique: draftChars=\(draft.count)")
        let raw = try await AIClient.send(prompt: prompt, settings: settings, onProgress: onProgress)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "OK" || trimmed.hasPrefix("OK\n") || trimmed.hasPrefix("OK ") {
            return nil
        }
        return trimmed
    }

    // MARK: - Revise pass
    //
    // Prend draft + critique → produit v2. Accepte un `previousMessage` du
    // writer (justifie ce qui n'a pas pu être corrigé lors d'une révision
    // antérieure — évite que le critique redemande la même chose).

    struct RevisionOutput {
        let body: String          // markdown révisé
        let writerMessage: String // explications du writer au critique
    }

    static func revise(
        draft: String,
        critique: String,
        mergedTranscript: String,
        participantsDescription: String,
        previousWriterMessage: String = "",
        settings: AppSettings,
        onProgress: AIClient.ProgressCallback? = nil
    ) async throws -> RevisionOutput {
        let prevBlock = previousWriterMessage.isEmpty ? "" : """

        Message précédent du rédacteur (raisons pour lesquelles certaines
        critiques n'ont pas pu être suivies — à conserver si toujours valides) :
        \(previousWriterMessage)

        """

        let prompt = """
        Tu es le rédacteur du compte-rendu. Tu dois réviser le brouillon ci-
        dessous en suivant les critiques du relecteur, SANS rien inventer.

        Participants réels :
        \(participantsDescription)

        Transcription source :
        ---
        \(mergedTranscript)
        ---

        Brouillon actuel :
        ---
        \(draft)
        ---

        Critiques du relecteur (à corriger) :
        ---
        \(critique)
        ---
        \(prevBlock)
        Règles :
        - Réécris le rapport en markdown, en conservant la structure de sections
          du brouillon. Corrige UNIQUEMENT ce que le relecteur a pointé.
        - Si une critique ne peut pas être satisfaite (info absente de la
          transcription), garde la formulation prudente et explique-le dans
          le `writer_message`.
        - Ne rajoute pas de sections que le brouillon n'avait pas.

        Réponds en JSON strict :
        {
          "body": "<markdown révisé complet>",
          "writer_message": "<court message au relecteur, max 200 mots, expliquant les changements ou justifiant l'absence de changement>"
        }
        """

        reportLog.info("revise: draftChars=\(draft.count) critiqueChars=\(critique.count)")
        let raw = try await AIClient.send(prompt: prompt, settings: settings, onProgress: onProgress)

        // Parse JSON. Si parsing échoue, on retourne le brut comme body et
        // un message vide — pas idéal mais préserve le travail du LLM.
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Tentative extraction d'un bloc ```json ... ``` éventuel.
            if let extracted = extractJSONBlock(from: raw),
               let data = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return RevisionOutput(
                    body: (json["body"] as? String) ?? raw,
                    writerMessage: (json["writer_message"] as? String) ?? ""
                )
            }
            return RevisionOutput(body: raw, writerMessage: "")
        }
        return RevisionOutput(
            body: (json["body"] as? String) ?? raw,
            writerMessage: (json["writer_message"] as? String) ?? ""
        )
    }

    private static func extractJSONBlock(from s: String) -> String? {
        // Extrait le premier bloc { ... } équilibré rencontré.
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = start
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" {
                depth -= 1
                if depth == 0 { return String(s[start...i]) }
            }
            i = s.index(after: i)
        }
        return nil
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

    // MARK: - ExtractedFacts

    /// Faits structurés extraits depuis le markdown du rapport par la 2e
    /// passe LLM. Permet d'alimenter actions / alerts SwiftData sans imposer
    /// un schéma JSON dans le prompt de génération principal.
    struct ExtractedFacts {
        var keyPoints: [String]
        var decisions: [String]
        var openQuestions: [String]
        var actions: [MeetingReportData.ActionProposal]
        var alerts: [MeetingReportData.AlertProposal]

        static let empty = ExtractedFacts(
            keyPoints: [], decisions: [], openQuestions: [], actions: [], alerts: []
        )
    }

    /// Passe 2 : extrait actions / alerts / décisions / questions / points clés
    /// depuis le markdown produit par `generate`. Le prompt ci-dessous est
    /// volontairement hardcoded (pas éditable côté template) car il garantit
    /// le contrat JSON attendu par le parser `parse(...)`. Si on rendait ce
    /// schéma éditable, le parser casserait silencieusement à la première
    /// dérive de format.
    @MainActor
    static func extractStructured(
        markdown: String,
        meeting: Meeting,
        settings: AppSettings
    ) async -> ExtractedFacts {
        let prompt = """
        Analyse ce compte-rendu de réunion et extrais les éléments structurés
        pour alimenter la base de données. Réponds EXCLUSIVEMENT en JSON strict
        avec ce schéma :
        {
          "summary": "",
          "keyPoints": ["..."],
          "decisions": ["..."],
          "openQuestions": ["..."],
          "actions": [
            { "title": "...", "assignee": "Nom complet ou null", "deadline": "YYYY-MM-DD ou null" }
          ],
          "alerts": [
            { "title": "...", "detail": "...", "severity": "Critique|Élevé|Modéré|Faible" }
          ]
        }

        Règles :
        - Tableaux vides `[]` si rien ne s'applique
        - `assignee` = nom complet exact si mentionné, sinon null
        - `deadline` = format ISO YYYY-MM-DD ou null
        - Pas d'invention — uniquement ce qui est explicitement dans le compte-rendu
        - Le champ `summary` doit rester vide ("") car on conserve le markdown original

        Compte-rendu à analyser :
        \(markdown)
        """

        do {
            let raw = try await AIClient.send(prompt: prompt, settings: settings)
            let parsed = parse(raw)
            return ExtractedFacts(
                keyPoints: parsed.keyPoints,
                decisions: parsed.decisions,
                openQuestions: parsed.openQuestions,
                actions: parsed.actions,
                alerts: parsed.alerts
            )
        } catch {
            reportLog.warning("extractStructured failed: \(error.localizedDescription, privacy: .public) — keeping markdown only")
            return .empty
        }
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

extension AIReportService {

    /// Génère un brouillon de préparation en markdown depuis l'historique des
    /// 3 dernières meetings, les actions ouvertes et alertes. Sortie = markdown
    /// avec sections `## Points à aborder` / `## Questions à poser` / etc., chaque
    /// item étant une checkbox `- [ ] ...`.
    @MainActor
    static func generatePrep(
        collab: Collaborator?,
        project: Project?,
        meeting: Meeting?,
        in context: ModelContext,
        settings: AppSettings
    ) async throws -> String {
        var ctxLines: [String] = []

        if let m = meeting {
            ctxLines.append("Réunion : \(m.title)")
            if let start = m.scheduledStart {
                let df = DateFormatter()
                df.locale = Locale(identifier: "fr_FR")
                df.dateFormat = "d MMM yyyy HH:mm"
                ctxLines.append("Date : \(df.string(from: start))")
            }
        }
        if let c = collab {
            ctxLines.append("Participant : \(c.name)\(c.role.isEmpty ? "" : " (\(c.role))")")
        }
        if let p = project {
            ctxLines.append("Projet : \(p.name) (\(p.code))")
        }

        // Historique : 3 dernières meetings du collab/projet, résumé court.
        // Note: #Predicate ne supporte pas .contains(where:) sur les relations
        // SwiftData — on fetch tout et on filtre en Swift.
        var historyBlock = ""
        if let c = collab {
            let collabID = c.persistentModelID
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let all = (try? context.fetch(descriptor)) ?? []
            let past = all
                .filter { $0.participants.contains(where: { $0.persistentModelID == collabID }) }
                .prefix(3)
            historyBlock = past.map { m -> String in
                let f = DateFormatter()
                f.locale = Locale(identifier: "fr_FR")
                f.dateFormat = "d MMM"
                let when = f.string(from: m.date)
                let snippet = String(m.summary.prefix(200))
                return "- \(when) — \(m.title) : \(snippet)"
            }.joined(separator: "\n")
        } else if let p = project {
            let projectID = p.persistentModelID
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { m in
                    m.project?.persistentModelID == projectID
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let past = ((try? context.fetch(descriptor)) ?? []).prefix(3)
            historyBlock = past.map { m -> String in
                let f = DateFormatter()
                f.locale = Locale(identifier: "fr_FR")
                f.dateFormat = "d MMM"
                let when = f.string(from: m.date)
                let snippet = String(m.summary.prefix(200))
                return "- \(when) — \(m.title) : \(snippet)"
            }.joined(separator: "\n")
        }

        // Actions ouvertes
        var actionsBlock = ""
        if let c = collab {
            let collabID = c.persistentModelID
            let desc = FetchDescriptor<ActionTask>(
                predicate: #Predicate { t in
                    !t.isCompleted && t.collaborator?.persistentModelID == collabID
                }
            )
            let open = ((try? context.fetch(desc)) ?? []).prefix(8)
            actionsBlock = open.map { "- \($0.title)" }.joined(separator: "\n")
        } else if let p = project {
            let projectID = p.persistentModelID
            let desc = FetchDescriptor<ActionTask>(
                predicate: #Predicate { t in
                    !t.isCompleted && t.project?.persistentModelID == projectID
                }
            )
            let open = ((try? context.fetch(desc)) ?? []).prefix(8)
            actionsBlock = open.map { "- \($0.title)" }.joined(separator: "\n")
        }

        // Alertes
        var alertsBlock = ""
        if let p = project {
            let projectID = p.persistentModelID
            let desc = FetchDescriptor<ProjectAlert>(
                predicate: #Predicate { $0.project?.persistentModelID == projectID }
            )
            let alerts = ((try? context.fetch(desc)) ?? [])
                .filter { $0.severity == "Élevé" || $0.severity == "Critique" }
                .prefix(5)
            alertsBlock = alerts.map { "- [\($0.severity)] \($0.title)" }.joined(separator: "\n")
        }

        let prompt = """
        Tu prépares la réunion ci-dessous. Produis une PRÉPARATION en markdown
        organisée en sections (omets celles vides) :
          ## Points à aborder
          ## Questions à poser
          ## Décisions à obtenir
          ## Infos à partager
        Chaque item = puce checkbox `- [ ] ...`. Reste concis, factuel.

        Contexte :
        \(ctxLines.joined(separator: "\n"))

        Historique récent :
        \(historyBlock.isEmpty ? "(aucun)" : historyBlock)

        Actions ouvertes :
        \(actionsBlock.isEmpty ? "(aucune)" : actionsBlock)

        Alertes en cours :
        \(alertsBlock.isEmpty ? "(aucune)" : alertsBlock)

        Ne réécris pas les actions ouvertes verbatim ; sélectionne celles qui
        méritent une discussion. N'invente rien.
        """

        let raw = try await AIClient.send(prompt: prompt, settings: settings)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
