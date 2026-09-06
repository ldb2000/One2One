import Foundation
import SwiftData

/// Règles de rétention des `ChatSession` (historique persisté du chatbot,
/// `ChatbotView`). Isolé de la vue pour rester testable sans SwiftUI.
@MainActor
enum ChatSessionStore {
    nonisolated static let maxSessions = 100

    /// Sessions à supprimer pour respecter `limit` : les plus anciennes par
    /// `updatedAt`, au-delà de la limite. Fonction pure, ne touche pas au contexte.
    static func sessionsToPrune(from sessions: [ChatSession], limit: Int = maxSessions) -> [ChatSession] {
        guard sessions.count > limit else { return [] }
        let sorted = sessions.sorted { $0.updatedAt < $1.updatedAt }
        return Array(sorted.prefix(sessions.count - limit))
    }

    /// Applique la limite : supprime les sessions les plus anciennes au-delà de
    /// `limit` (cascade sur leurs messages), sauvegarde une fois, logge l'action.
    static func enforceLimit(sessions: [ChatSession], in context: ModelContext, limit: Int = maxSessions) {
        let toPrune = sessionsToPrune(from: sessions, limit: limit)
        guard !toPrune.isEmpty else { return }
        for session in toPrune {
            context.delete(session)
        }
        try? context.save()
        print("[ChatSessionStore] \(toPrune.count) session(s) la plus ancienne(s) supprimée(s) (limite \(limit)).")
    }
}
