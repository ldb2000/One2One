import Foundation
import SwiftData

/// Résout un nom de collaborateur retourné par un LLM en `Collaborator`
/// concret, ou nil si aucun match raisonnable n'existe.
///
/// Ordre :
/// 1. Match exact (case + accent-insensible) parmi `meeting.participants`
/// 2. Match exact parmi collabs avec `pinLevel >= 1`
/// 3. Match exact parmi tous les collabs non-archivés
///
/// Tous les comparatifs normalisent via `lowercased() + folding(diacriticInsensitive)`.
/// Pas de matching fuzzy "contains" en V1 — trop ambigu, on préfère nil →
/// affichage chip "💡 Auto : <nom>" pour confirmation utilisateur.
@MainActor
enum CollaboratorMatcher {

    /// Résout `name` (issu du LLM) en `Collaborator` par priorité décroissante :
    /// participants de la réunion, puis favoris (`pinLevel >= 1`), puis tous les
    /// collabs non-archivés. Match exact normalisé uniquement ; `nil` si aucun.
    static func match(name: String,
                      in meeting: Meeting,
                      all: [Collaborator]) -> Collaborator? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }

        // 1. Participants
        if let hit = meeting.participants.first(where: { normalize($0.name) == target }) {
            return hit
        }
        // 2. Favoris (pinLevel >= 1)
        let favorites = all.filter { $0.pinLevel >= 1 && !$0.isArchived }
        if let hit = favorites.first(where: { normalize($0.name) == target }) {
            return hit
        }
        // 3. Tous non-archivés
        let actives = all.filter { !$0.isArchived }
        if let hit = actives.first(where: { normalize($0.name) == target }) {
            return hit
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
