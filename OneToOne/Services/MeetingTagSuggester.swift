import Foundation
import os

private let tagSuggesterLog = Logger(subsystem: "com.onetoone.app", category: "tags")

/// Suggère des thèmes (`MeetingTag`) pour une réunion à partir de son compte-rendu.
/// Toujours non-throwing : erreur / timeout / réponse inexploitable → `[]`, l'UI
/// n'affiche simplement aucune proposition.
///
/// Les propositions ne sont **jamais** appliquées automatiquement : elles sont
/// affichées en chips « fantômes » que l'utilisateur accepte ou ignore.
enum MeetingTagSuggester {

    /// Temps max accordé à l'appel IA. L'appelant doit de toute façon lancer la
    /// suggestion en tâche de fond, sans bloquer l'UI.
    static let timeout: TimeInterval = 5

    /// Longueur max du texte source envoyé au modèle — assez pour cerner les
    /// thèmes sans faire exploser le prompt.
    static let maxSourceCharacters = 4000

    /// Nombre max de thèmes retenus dans la réponse.
    static let maxSuggestions = 5

    /// Longueur max d'un libellé de thème : au-delà, c'est une phrase, pas un
    /// thème — on l'ignore (garde-fou contre les réponses bavardes).
    static let maxLabelLength = 40

    /// Réponses signifiant « rien à proposer ».
    private static let refusals: Set<String> = ["aucun", "aucune", "aucun theme", "n/a", "na", "none", "rien", "-"]

    /// Demande 3–5 thèmes courts pour `summary`, en réutilisant `existingTags`
    /// quand ils collent. Renvoie les libellés proposés : ceux qui matchent un
    /// thème existant sont renvoyés dans leur graphie canonique, les autres tels
    /// quels (= nouveaux thèmes à créer).
    static func suggest(
        summary: String,
        existingTags: [String],
        settings: AppSettings,
        client: AIClientProtocol = AIClient.live
    ) async -> [String] {
        let source = truncated(summary)
        guard !source.isEmpty else {
            tagSuggesterLog.info("suggest: source vide, skip")
            return []
        }

        let prompt = buildPrompt(source: source, existingTags: existingTags)

        do {
            let raw = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            return parse(response: raw, existingTags: existingTags)
        } catch {
            tagSuggesterLog.error("suggest: échec \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Texte source à envoyer : le résumé s'il est non vide, sinon la
    /// transcription fusionnée, dans les deux cas tronqué.
    static func sourceText(summary: String, transcript: String) -> String {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated(cleanSummary.isEmpty ? transcript : cleanSummary)
    }

    static func truncated(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxSourceCharacters else { return clean }
        return String(clean.prefix(maxSourceCharacters))
    }

    /// Prompt demandant une liste courte de thèmes, en réutilisant en priorité
    /// les thèmes déjà utilisés dans l'app.
    static func buildPrompt(source: String, existingTags: [String]) -> String {
        let existingBlock = existingTags.isEmpty
            ? "Aucun thème existant pour l'instant."
            : "Thèmes déjà utilisés (réutilise-les quand ils conviennent) :\n\(existingTags.joined(separator: ", "))"
        return """
        Voici le compte-rendu d'une réunion :
        \"\"\"
        \(source)
        \"\"\"

        \(existingBlock)

        Donne 3 à 5 thèmes courts (1 à 3 mots) qui résument les sujets abordés.
        Réponds UNIQUEMENT par la liste des thèmes séparés par des virgules,
        sans numérotation ni phrase d'introduction.
        """
    }

    /// Découpe la réponse (virgules, retours à la ligne, puces, numérotation),
    /// nettoie chaque libellé, écarte le bruit, dédoublonne (casse/accents
    /// ignorés) et remplace par la graphie canonique d'un thème existant quand
    /// il y a correspondance. Limité à `maxSuggestions`.
    static func parse(response: String, existingTags: [String]) -> [String] {
        var canonical: [String: String] = [:]
        for tag in existingTags {
            canonical[MeetingTag.normalizedKey(tag)] = tag
        }

        var seen = Set<String>()
        var result: [String] = []

        for rawLine in response.components(separatedBy: .newlines) {
            for rawItem in rawLine.components(separatedBy: ",") {
                guard let label = cleanLabel(rawItem) else { continue }
                let key = MeetingTag.normalizedKey(label)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(canonical[key] ?? label)
                if result.count == maxSuggestions { return result }
            }
        }
        return result
    }

    /// Nettoie un item : retire puce / numérotation / ponctuation de bord.
    /// Renvoie `nil` si l'item est vide, trop long ou signifie « aucun ».
    private static func cleanLabel(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Puces : «- », «• », «* », «– »
        while let first = text.first, "-•*–—".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // Numérotation : «1. », «2) »
        if let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }),
           text[text.startIndex..<dot].allSatisfy({ $0.isNumber }),
           dot > text.startIndex {
            text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        text = text
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,!?:;«»"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, text.count <= maxLabelLength else { return nil }
        guard !refusals.contains(MeetingTag.normalizedKey(text)) else { return nil }
        return text
    }

    // MARK: - Timeout helper

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
