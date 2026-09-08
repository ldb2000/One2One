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
        /// Récaps 1:1 versés dans `recordings/annual/<année>/<personne>/`
        /// (lot 10). Une ligne de plus, pour qu'un dossier qui grossit seul
        /// reste visible dans les réglages de stockage.
        var annualBytes: Int64 = 0
        var annualCount: Int = 0
        /// Planches d'atelier : `recordings/<uuid>/boards/` (scène + vignette).
        var boardsBytes: Int64 = 0
        var boardsCount: Int = 0
        var databaseBytes: Int64 = 0
        var totalBytes: Int64 {
            wavBytes + attachmentBytes + slidesBytes + annualBytes + boardsBytes + databaseBytes
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
    /// - Pièces jointes : le scan de `recordings/<meetingUUID>/documents/`
    ///   (pièces copiées, politique D5) **plus** les lignes
    ///   `MeetingAttachment` encore référencées hors de l'application. Le kind
    ///   "slides" est exclu (chemin virtuel) et les lignes déjà couvertes par
    ///   le scan ne sont pas recomptées.
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

        let supportDir = applicationSupportDir()
        let recordingsDir = supportDir.appendingPathComponent("recordings")

        // Pièces copiées (D5) : le scan du dossier fait foi, y compris pour un
        // fichier qu'aucune ligne ne réclame plus — c'est justement celui-là
        // qu'on veut voir dans la répartition du disque.
        let (documentsBytes, documentsCount) = Self.documentsUsage(inRecordings: recordingsDir)
        stats.attachmentBytes += documentsBytes
        stats.attachmentCount += documentsCount

        // Pièces encore **référencées** hors de l'application : les lignes
        // antérieures à D5 que la migration paresseuse n'a pas encore vues.
        // Une ligne déjà couverte par le scan ci-dessus n'est pas recomptée.
        let attDescriptor = FetchDescriptor<MeetingAttachment>()
        let attachments = (try? context.fetch(attDescriptor)) ?? []
        for a in attachments {
            // "slides" kind entries use a virtual path, their actual disk usage
            // is captured below via the recordings directory scan.
            guard a.kind != "slides", a.kind != AttachmentCopyPolicy.linkKind else { continue }
            guard !AttachmentCopyPolicy.isCopied(path: a.filePath, base: supportDir) else { continue }
            if let size = fileSize(atPath: a.filePath) {
                stats.attachmentBytes += size
                stats.attachmentCount += 1
            }
        }

        // Slide captures live under Application Support/OneToOne/recordings/
        // organised as <meetingUUID>/slides/<file>.png
        // Only count files within slides/ subdirs; recordings/ also contains wav files
        // which are already counted separately via Meeting.wavFilePath.
        var slidesBytes: Int64 = 0
        var slidesCount = 0
        var boardsBytes: Int64 = 0
        var boardsCount = 0
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
                // Planches d'atelier : le même patron, un dossier de plus.
                // Chaque nouveau dossier de fichiers s'enregistre ici (plan
                // §2.4 point 6), sinon il grossit sans jamais être compté.
                let boardsSub = dir.appendingPathComponent(BoardStore.folderName)
                let (bb, bc) = directorySize(at: boardsSub)
                boardsBytes += bb
                boardsCount += bc
            }
        }
        stats.slidesBytes = slidesBytes
        stats.slidesCount = slidesCount
        stats.boardsBytes = boardsBytes
        stats.boardsCount = boardsCount

        // Récaps 1:1 du dossier annuel (lot 10) : `recordings/annual/` n'est
        // pas un dossier de réunion, il n'a donc pas de sous-dossier `slides`
        // et le scan ci-dessus l'a compté pour zéro.
        let (annualBytes, annualCount) = directorySize(
            at: recordingsDir.appendingPathComponent("annual")
        )
        stats.annualBytes = annualBytes
        stats.annualCount = annualCount

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

    /// Octets et nombre de fichiers sous `recordings/*/documents/` — le dossier
    /// des pièces copiées (D5). `nonisolated static` : c'est une lecture de
    /// dossier, elle se teste sans base, sans acteur principal et sans
    /// `Application Support` réel.
    nonisolated static func documentsUsage(inRecordings recordings: URL) -> (Int64, Int) {
        var total: Int64 = 0
        var count = 0
        guard let meetingDirs = try? FileManager.default.contentsOfDirectory(
            at: recordings, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return (0, 0) }
        for dir in meetingDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let documents = dir.appendingPathComponent("documents")
            guard let enumerator = FileManager.default.enumerator(
                at: documents, includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for case let fichier as URL in enumerator {
                if let taille = try? fichier.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(taille)
                    count += 1
                }
            }
        }
        return (total, count)
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
