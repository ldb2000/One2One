import Foundation
import SwiftData

/// Calcule la répartition du stockage de l'app (WAV, pièces jointes, slides,
/// base SwiftData). Confiné au `@MainActor` ; le résultat est mémorisé avec un
/// TTL afin d'éviter de re-scanner le disque à chaque accès.
@MainActor
final class StorageStatsService {

    /// Tailles et compteurs par catégorie de fichiers ; `totalBytes` est dérivé.
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

    /// Retourne les stats, depuis le cache si celui-ci a moins de `ttl` secondes.
    /// `force == true` ignore le cache et force un recalcul immédiat.
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

    /// Vide le cache ; le prochain `snapshot` recalculera. À appeler après une
    /// suppression/compression de fichiers pour refléter le nouvel état.
    func invalidate() {
        cached = nil
        cachedAt = nil
    }

    /// Scanne le disque et la base pour produire un `Stats`.
    /// - WAV : découverts via `Meeting.wavFilePath`.
    /// - Pièces jointes : `MeetingAttachment`, en excluant le kind "slides"
    ///   (chemin virtuel, comptabilisé via le scan du dossier recordings).
    /// - Slides : fichiers sous `recordings/<meetingUUID>/slides/`.
    /// - Base : `OneToOne.store` + ses fichiers `-wal` / `-shm`.
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
        // Only count files within slides/ subdirs; recordings/ also contains wav files
        // which are already counted separately via Meeting.wavFilePath.
        let supportDir = applicationSupportDir()
        let recordingsDir = supportDir.appendingPathComponent("recordings")
        var slidesBytes: Int64 = 0
        var slidesCount = 0
        if let meetingDirs = try? FileManager.default.contentsOfDirectory(
            at: recordingsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for dir in meetingDirs {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let slidesSub = dir.appendingPathComponent("slides")
                let (b, c) = directorySize(at: slidesSub)
                slidesBytes += b
                slidesCount += c
            }
        }
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

    /// Dossier `Application Support/OneToOne`. Retombe sur
    /// `~/Library/Application Support` si l'URL système est indisponible.
    private func applicationSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OneToOne")
    }
}
