import Foundation
import SwiftData

@MainActor
final class StorageStatsService {

    struct Stats: Equatable {
        var wavBytes: Int64 = 0
        var wavCount: Int = 0
        var attachmentBytes: Int64 = 0
        var attachmentCount: Int = 0
        var slidesBytes: Int64 = 0
        var slidesCount: Int = 0
        var databaseBytes: Int64 = 0
        var totalBytes: Int64 {
            wavBytes + attachmentBytes + slidesBytes + databaseBytes
        }
    }

    static let shared = StorageStatsService()

    private var cached: Stats?
    private var cachedAt: Date?
    private let ttl: TimeInterval = 60

    func snapshot(in context: ModelContext, force: Bool = false) -> Stats {
        if !force, let s = cached, let at = cachedAt,
           Date().timeIntervalSince(at) < ttl {
            return s
        }
        let s = compute(in: context)
        cached = s
        cachedAt = Date()
        return s
    }

    func invalidate() {
        cached = nil
        cachedAt = nil
    }

    private func compute(in context: ModelContext) -> Stats {
        var stats = Stats()

        // WAV files via Meeting.wavFilePath
        let meetingDescriptor = FetchDescriptor<Meeting>()
        let meetings = (try? context.fetch(meetingDescriptor)) ?? []
        for m in meetings {
            guard let path = m.wavFilePath else { continue }
            if let size = fileSize(atPath: path) {
                stats.wavBytes += size
                stats.wavCount += 1
            }
        }

        // Attached documents (pdf, pptx, etc.) — excludes slides kind
        let attDescriptor = FetchDescriptor<MeetingAttachment>()
        let attachments = (try? context.fetch(attDescriptor)) ?? []
        for a in attachments {
            // "slides" kind entries use a virtual path, their actual disk usage
            // is captured below via the recordings directory scan.
            guard a.kind != "slides" else { continue }
            if let size = fileSize(atPath: a.filePath) {
                stats.attachmentBytes += size
                stats.attachmentCount += 1
            }
        }

        // Slide captures live under Application Support/OneToOne/recordings/
        // organised as <meetingUUID>/slides/<file>.png
        let supportDir = applicationSupportDir()
        let recordingsDir = supportDir.appendingPathComponent("recordings")
        let (slidesBytes, slidesCount) = directorySize(at: recordingsDir)
        stats.slidesBytes = slidesBytes
        stats.slidesCount = slidesCount

        // SwiftData store: OneToOne.store (+ WAL and SHM)
        let storeFile = supportDir.appendingPathComponent("OneToOne.store")
        var dbBytes: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeFile.path + suffix)
            if let size = fileSize(atPath: url.path) { dbBytes += size }
        }
        stats.databaseBytes = dbBytes

        return stats
    }

    private func fileSize(atPath path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private func directorySize(at url: URL) -> (Int64, Int) {
        var total: Int64 = 0
        var count = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return (0, 0) }
        for case let path as URL in enumerator {
            if let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
                count += 1
            }
        }
        return (total, count)
    }

    private func applicationSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OneToOne")
    }
}
