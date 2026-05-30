import Foundation
import SwiftData
import os

private let retLog = Logger(subsystem: "com.onetoone.app", category: "wav-retention")

/// Planifie et exécute le cleanup audio (compression + suppression).
@MainActor
enum WavRetentionService {

    struct CleanupPlan {
        var toCompress: [Meeting]
        var toDelete: [Meeting]
    }

    static func plan(in context: ModelContext,
                     settings: AppSettings,
                     now: Date = Date()) -> CleanupPlan {
        let descriptor = FetchDescriptor<Meeting>()
        let all = (try? context.fetch(descriptor)) ?? []
        let cal = Calendar.current
        let compressCutoff = cal.date(
            byAdding: .day,
            value: -settings.wavCompressionDays,
            to: now
        ) ?? now
        let deleteCutoff = cal.date(
            byAdding: .day,
            value: -settings.wavDeletionDays,
            to: now
        ) ?? now

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
