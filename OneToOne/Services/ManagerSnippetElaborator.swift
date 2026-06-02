import Foundation
import os

private let elaboratorLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// Rédige un texte autonome (1-3 phrases) à partir du snippet sélectionné +
/// contexte + projet/réunion source, pour qu'il soit lisible hors contexte
/// dans le rapport manager. Always non-throwing: errors / timeouts return
/// a deterministic fallback ("contextBefore + snippet + contextAfter") so the
/// UI always has something to show.
enum ManagerSnippetElaborator {

    /// Plus généreux que le classifier (texte rédigé > nom de catégorie).
    static let timeout: TimeInterval = 8

    /// Résultat d'une tentative d'élaboration — distingue le succès IA du repli
    /// (fallback) afin que l'appelant puisse refléter cette distinction dans l'UI.
    enum Outcome {
        case ai(text: String)
        case fallback(text: String, reason: String)
    }

    /// Rédige le texte autonome à partir du snippet et de son contexte.
    /// Ne lance jamais d'erreur : un timeout, une erreur IA ou une réponse vide
    /// renvoie un `Outcome.fallback` déterministe au lieu de propager l'échec.
    static func elaborate(
        snippet: String,
        contextBefore: String,
        contextAfter: String,
        projectName: String?,
        sourceMeetingTitle: String?,
        sourceMeetingDate: Date?,
        settings: AppSettings,
        client: AIClientProtocol = AIClient.live
    ) async -> Outcome {
        let prompt = buildPrompt(
            snippet: snippet,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            projectName: projectName,
            sourceMeetingTitle: sourceMeetingTitle,
            sourceMeetingDate: sourceMeetingDate
        )
        elaboratorLog.info("elaborate: prompt sent, len=\(prompt.count, privacy: .public)")

        do {
            let raw = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                elaboratorLog.info("elaborate: AI returned empty, using fallback")
                return .fallback(text: fallback(contextBefore: contextBefore, snippet: snippet, contextAfter: contextAfter),
                                 reason: "Réponse IA vide")
            }
            elaboratorLog.info("elaborate: AI success, response len=\(cleaned.count, privacy: .public)")
            return .ai(text: cleaned)
        } catch {
            elaboratorLog.error("elaborate: failed \(error.localizedDescription, privacy: .public)")
            return .fallback(text: fallback(contextBefore: contextBefore, snippet: snippet, contextAfter: contextAfter),
                             reason: error.localizedDescription)
        }
    }

    /// Texte de repli déterministe : concatène contexte avant + snippet +
    /// contexte après (parties vides ignorées), séparés par une espace.
    static func fallback(contextBefore: String, snippet: String, contextAfter: String) -> String {
        let before = contextBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = contextAfter.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !before.isEmpty { parts.append(before) }
        parts.append(snippet)
        if !after.isEmpty { parts.append(after) }
        return parts.joined(separator: " ")
    }

    /// Construit le prompt IA : consignes de rédaction + lignes projet/source +
    /// les trois blocs de contexte (avant, extrait, après).
    static func buildPrompt(
        snippet: String,
        contextBefore: String,
        contextAfter: String,
        projectName: String?,
        sourceMeetingTitle: String?,
        sourceMeetingDate: Date?
    ) -> String {
        let projectLine = projectName.map { "Projet : \($0)" } ?? "Projet : non précisé"
        let meetingLine: String = {
            switch (sourceMeetingTitle, sourceMeetingDate) {
            case (let t?, let d?):
                let date = d.formatted(date: .abbreviated, time: .omitted)
                return "Source : « \(t.isEmpty ? "Réunion" : t) » du \(date)"
            case (let t?, nil):
                return "Source : « \(t.isEmpty ? "Réunion" : t) »"
            default:
                return "Source : ajout manuel"
            }
        }()

        return """
        Tu prépares un point à aborder avec mon manager. À partir de l'extrait
        sélectionné et de son contexte, rédige UN paragraphe court (2-3 phrases,
        ~80 mots max) qui restitue l'information de façon claire, autonome et
        actionnable — il doit être compréhensible sans avoir lu la transcription
        d'origine.

        Règles :
        - Pas de paraphrase littérale : reformule pour lisibilité.
        - Inclus le contexte projet si pertinent.
        - Reste factuel, n'invente rien. Si une info manque, omets-la.
        - Réponds UNIQUEMENT par le texte rédigé, sans préambule, sans guillemets,
          sans bullet points.

        \(projectLine)
        \(meetingLine)

        Contexte avant (jusqu'à ~2 phrases) :
        \(contextBefore.isEmpty ? "(vide)" : contextBefore)

        EXTRAIT SÉLECTIONNÉ (au cœur du point) :
        \(snippet)

        Contexte après (jusqu'à ~2 phrases) :
        \(contextAfter.isEmpty ? "(vide)" : contextAfter)
        """
    }

    // MARK: - Timeout helper (same pattern as ManagerCategoryClassifier)

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
