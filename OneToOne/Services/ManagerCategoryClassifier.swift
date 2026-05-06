import Foundation
import os

private let classifierLog = Logger(subsystem: "com.onetoone.app", category: "manager")

/// Suggests a category for a manager-report item by asking the configured AI
/// provider to pick from `AppSettings.managerCategories`. Always non-throwing:
/// errors / timeouts / out-of-list responses return `nil` so the UI can fall
/// back to the default "Information" category.
enum ManagerCategoryClassifier {

    /// Maximum time allowed for the AI call; UI should also treat the call as
    /// non-blocking (sheet opens immediately with placeholder).
    static let timeout: TimeInterval = 3

    static func classify(
        snippet: String,
        projectName: String?,
        settings: AppSettings,
        client: AIClientProtocol = AIClient.live
    ) async -> String? {
        let categories = settings.managerCategories
        guard !categories.isEmpty else {
            classifierLog.info("classify: empty categories, skip")
            return nil
        }

        let prompt = buildPrompt(snippet: snippet, projectName: projectName, categories: categories)

        do {
            let raw = try await withTimeout(seconds: timeout) {
                try await client.send(prompt: prompt, settings: settings)
            }
            return match(response: raw, categories: categories)
        } catch {
            classifierLog.error("classify: failed \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func buildPrompt(snippet: String, projectName: String?, categories: [String]) -> String {
        let projectLine = projectName.map { "Contexte projet : \($0)" } ?? "Contexte projet : n/a"
        return """
        Classe ce passage parmi les catégories suivantes :
        \(categories.joined(separator: ", "))

        Passage : "\(snippet)"
        \(projectLine)

        Réponds UNIQUEMENT par le nom exact d'une catégorie de la liste.
        """
    }

    /// Matches the AI response against the category list (case- + diacritic-insensitive,
    /// stripping surrounding punctuation/quotes). Returns the canonical
    /// category string from the list, or nil if no match.
    static func match(response: String, categories: [String]) -> String? {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,!?:;«»"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        for category in categories {
            if category.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return category
            }
        }
        return nil
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
