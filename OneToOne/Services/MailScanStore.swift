import Foundation
import SwiftData

/// Accès aux traces du scan automatique de mails : dédup des messages déjà
/// évalués, purge des vieux records, nettoyage des suggestions orphelines.
@MainActor
enum MailScanStore {

    /// Tous les `messageId` déjà connus : mails rattachés, suggestions en
    /// attente, mails évalués (ignorés inclus). Un mail dans cet ensemble
    /// n'est jamais ré-évalué par le scan.
    static func knownMessageIds(in context: ModelContext) -> Set<String> {
        let mails = (try? context.fetch(FetchDescriptor<ProjectMail>())) ?? []
        let suggestions = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        return Set(mails.map(\.messageId))
            .union(suggestions.map(\.messageId))
            .union(records.map(\.messageId))
    }

    /// Insère la trace d'évaluation d'un mail (sans save : l'appelant groupe).
    static func record(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext) {
        context.insert(MailScanRecord(messageId: messageId, verdict: verdict))
    }

    /// Upsert du verdict d'un mail : mute le record existant, ou en crée un si
    /// absent (ex. purgé entre-temps). Utilisé à la validation / l'ignore d'une
    /// suggestion pour tracer le verdict final sans perdre la dédup.
    static func setVerdict(_ messageId: String, verdict: MailScanVerdict, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        if let existing = all.first(where: { $0.messageId == messageId }) {
            existing.verdict = verdict
            existing.evaluatedAt = Date()
        } else {
            context.insert(MailScanRecord(messageId: messageId, verdict: verdict))
        }
    }

    /// Purge les records plus vieux que `days` jours. Un mail hors fenêtre de
    /// scan ne peut plus réapparaître : sa trace est inutile.
    @discardableResult
    static func purgeRecords(olderThanDays days: Int, in context: ModelContext) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let all = (try? context.fetch(FetchDescriptor<MailScanRecord>())) ?? []
        let old = all.filter { $0.evaluatedAt < cutoff }
        old.forEach { context.delete($0) }
        return old.count
    }

    /// Supprime les suggestions dont le projet a disparu (relation nullifiée).
    @discardableResult
    static func deleteOrphanSuggestions(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<MailIndexSuggestion>())) ?? []
        let orphans = all.filter { $0.suggestedProject == nil }
        orphans.forEach { context.delete($0) }
        return orphans.count
    }
}
