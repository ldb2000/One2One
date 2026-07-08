import Foundation
import os

private let mailLLMLog = Logger(subsystem: "com.onetoone.app", category: "mail-llm")

/// Étage 2 du matching mail → projet : classification par le LLM local
/// (Gemma 4 via `DirectLLMClient`) des mails que les heuristiques n'ont pas
/// tranchés. Réponse attendue : JSON strict {"projectCode": ..., "confidence": ...}.
@MainActor
enum MailLLMClassifier {

    struct Candidate {
        let code: String
        let name: String
        /// Emails des collaborateurs du projet (signal expéditeur ↔ équipe).
        let collaborators: [String]
    }

    /// Résultat de classification (sémantique spec §4) :
    /// `.verdict` remplace le verdict heuristique ; `.unparseable` → le mail
    /// sera ignoré ; `.unavailable` (LLM en échec) → repli heuristique.
    enum ClassifyResult: Equatable {
        case verdict(MailProjectMatcher.Verdict)
        case unparseable
        case unavailable
    }

    /// Prompt de classification. Les candidats sont limités par l'appelant
    /// (tous les projets actifs — volume faible pour un portefeuille).
    static func buildPrompt(
        subject: String,
        sender: String,
        preview: String,
        candidates: [Candidate]
    ) -> String {
        let list = candidates
            .map { c in
                let team = c.collaborators.isEmpty ? "" : " (équipe : \(c.collaborators.joined(separator: ", ")))"
                return "- \(c.code) : \(c.name)\(team)"
            }
            .joined(separator: "\n")
        return """
        Tu classes un email professionnel vers un projet d'un portefeuille.

        Email :
        - Sujet : \(subject)
        - Expéditeur : \(sender)
        - Aperçu : \(preview)

        Projets candidats (code : nom, équipe) :
        \(list)

        Réponds UNIQUEMENT avec un objet JSON, sans autre texte :
        {"projectCode": "<code du projet>" ou null si aucun ne correspond, "confidence": <nombre entre 0 et 1>}
        """
    }

    /// Parse la réponse du LLM. Tolère les fences markdown et le texte autour
    /// (extraction du premier bloc {…} équilibré). Un code inconnu du
    /// portefeuille (hallucination) est traité comme « aucun projet ».
    /// Retourne nil si aucun JSON exploitable.
    static func parseVerdict(_ raw: String, knownCodes: Set<String>) -> MailProjectMatcher.Verdict? {
        struct Resp: Decodable {
            let projectCode: String?
            let confidence: Double?
        }
        let cleaned = stripCodeFence(raw)
        guard let block = extractJSONBlock(from: cleaned),
              let data = block.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            return nil
        }
        let confidence = min(1.0, max(0.0, resp.confidence ?? 0))
        guard let code = resp.projectCode, knownCodes.contains(code) else {
            return MailProjectMatcher.Verdict(projectCode: nil, confidence: confidence)
        }
        return MailProjectMatcher.Verdict(projectCode: code, confidence: confidence)
    }

    /// Classifie un mail ambigu. `generate` nil → Gemma 4 réel
    /// (`DirectLLMClient`, repo = `settings.directModelRepo`).
    /// Réponse illisible → `.unparseable` (spec : le mail sera ignoré) ;
    /// erreur LLM (chargement/génération) → `.unavailable` (repli heuristique,
    /// le scan continue). Tout est loggé.
    static func classify(
        subject: String,
        sender: String,
        preview: String,
        candidates: [Candidate],
        settings: AppSettings,
        generate: ((String) async throws -> String)? = nil
    ) async -> ClassifyResult {
        let prompt = buildPrompt(subject: subject, sender: sender,
                                 preview: preview, candidates: candidates)
        do {
            let raw: String
            if let generate {
                raw = try await generate(prompt)
            } else {
                raw = try await DirectLLMClient.send(
                    prompt: prompt,
                    modelRepo: settings.directModelRepo,
                    onProgress: nil
                )
            }
            guard let verdict = parseVerdict(raw, knownCodes: Set(candidates.map(\.code))) else {
                mailLLMLog.error("classify: réponse inexploitable — \(String(raw.prefix(200)), privacy: .public)")
                return .unparseable
            }
            return .verdict(verdict)
        } catch {
            mailLLMLog.error("classify: échec LLM — \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    // MARK: - Helpers JSON (pattern AIReportService, dupliqué faute de helper partagé)

    private static func stripCodeFence(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONBlock(from s: String) -> String? {
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
}
