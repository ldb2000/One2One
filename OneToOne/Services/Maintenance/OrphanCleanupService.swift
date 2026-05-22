import Foundation
import SwiftData

@MainActor
enum OrphanCleanupService {

    static func orphanAttachments(in context: ModelContext) -> [MeetingAttachment] {
        let descriptor = FetchDescriptor<MeetingAttachment>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !FileManager.default.fileExists(atPath: $0.filePath) }
    }

    static func staleTmpWavs(in directory: URL, olderThan minutes: Int = 5) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        return entries.filter {
            guard $0.lastPathComponent.hasSuffix(".tmp.wav") else { return false }
            let attrs = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
            guard let mtime = attrs?.contentModificationDate else { return false }
            return mtime < cutoff
        }
    }

    static func deleteAttachments(_ rows: [MeetingAttachment], in context: ModelContext) {
        for r in rows { context.delete(r) }
        try? context.save()
    }

    static func deleteFiles(_ urls: [URL]) {
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }
}
