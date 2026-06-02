import Foundation
import SwiftData
import os

private let retLog = Logger(subsystem: "com.onetoone.app", category: "wav-retention")

/// Planifie et exécute le cleanup audio (compression + suppression).
@MainActor
enum WavRetentionService {

    /// Répartition des meetings éligibles au cleanup audio :
    /// `toCompress` pour la compression, `toDelete` pour la suppression du WAV.
    struct CleanupPlan {
        var toCompress: [Meeting]
        var toDelete: [Meeting]
    }

    /// Classe les meetings selon leur ancienneté et les seuils de rétention :
    /// suppression au-delà de `wavDeletionDays`, sinon compression au-delà de
    /// `wavCompressionDays`. Ignore les meetings sans résumé, marqués
    /// « conserver toujours », sans audio jouable, ou déjà compressés.
    static func plan(in context: ModelContext,
                     settings: AppSettings,
                     now: Date = Date()) -> CleanupPlan {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        func cutoff(daysAgo days: Int) -> Date {
            cal.date(byAdding: .day, value: -days, to: now) ?? now
        }
        let compressCutoff = cutoff(daysAgo: settings.wavCompressionDays)
        let deleteCutoff = cutoff(daysAgo: settings.wavDeletionDays)

        var toCompress: [Meeting] = []
        var toDelete: [Meeting] = []
        for m in all {
            guard !m.summary.isEmpty else { continue }
            guard !m.keepWavForever else { continue }
            guard m.hasPlayableAudio else { continue }
            if m.date < deleteCutoff {
                toDelete.append(m)
            } else if m.date < compressCutoff && !m.wavIsCompressed {
                toCompress.append(m)
            }
        }
        return CleanupPlan(toCompress: toCompress, toDelete: toDelete)
    }

    static func compress(_ meeting: Meeting, in context: ModelContext) async throws {
        guard let path = meeting.wavFilePath else { return }
        let newURL = try await AudioCompressionService.compress(url: URL(fileURLWithPath: path))
        meeting.wavFilePath = newURL.path
        meeting.wavIsCompressed = true
        try? context.save()
        retLog.info("compressed meeting=\(meeting.title, privacy: .public) → \(newURL.lastPathComponent, privacy: .public)")
    }

    static func delete(_ meeting: Meeting, in context: ModelContext) {
        guard let path = meeting.wavFilePath else { return }
        try? FileManager.default.removeItem(atPath: path)
        meeting.wavFilePath = nil
        meeting.wavIsCompressed = false
        try? context.save()
        retLog.info("deleted audio meeting=\(meeting.title, privacy: .public)")
    }
}
