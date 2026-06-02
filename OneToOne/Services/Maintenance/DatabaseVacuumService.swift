import Foundation
import SQLite3
import os

private let vacLog = Logger(subsystem: "com.onetoone.app", category: "db-vacuum")

/// Compacte le fichier SQLite sous-jacent à SwiftData via SQLite3 (`VACUUM`) pour
/// récupérer l'espace disque libéré par les suppressions.
@MainActor
enum DatabaseVacuumService {

    /// Taille du store (en octets) avant et après le `VACUUM`.
    struct Result { let bytesBefore: Int64; let bytesAfter: Int64 }

    /// Ouvre directement le store SQLite et exécute `PRAGMA optimize; VACUUM;` :
    /// `optimize` met à jour les statistiques d'index, `VACUUM` réécrit la base pour la
    /// défragmenter. À n'appeler qu'app au repos (aucune écriture concurrente) ; renvoie
    /// les tailles avant/après ou lève une erreur si l'ouverture ou l'exécution échoue.
    static func vacuum() throws -> Result {
        let storeURL = storePath()
        let before = sizeOf(storeURL)

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "DatabaseVacuumService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Impossible d'ouvrir la DB"])
        }
        defer { sqlite3_close(db) }

        let sql = "PRAGMA optimize; VACUUM;"
        let status = sqlite3_exec(db, sql, nil, nil, nil)
        guard status == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "DatabaseVacuumService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let after = sizeOf(storeURL)
        vacLog.info("vacuum before=\(before)B after=\(after)B")
        return Result(bytesBefore: before, bytesAfter: after)
    }

    /// Chemin du store SQLite (`OneToOne/OneToOne.store` sous Application Support),
    /// nom fixé par la configuration SwiftData. Retombe sur `~/Library/Application Support`
    /// si le répertoire système n'est pas résolu.
    private static func storePath() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OneToOne/OneToOne.store")
    }

    private static func sizeOf(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }
}
