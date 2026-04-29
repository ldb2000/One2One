import Foundation
import SwiftData
import os

private let importLog = Logger(subsystem: "com.onetoone.app", category: "backlog-import")

/// Service d'import du backlog projets depuis un fichier xlsx
/// (typiquement `STTi_BACKLOG_PROJET_2026.xlsx`, feuille `Backlog_2025`).
///
/// Le parsing xlsx est délégué à un script Python (openpyxl) qui émet du JSON
/// sur stdout — l'app n'écrit donc jamais en SQLite hors ModelContext, et le
/// script peut être ré-exécuté à chaque mise à jour du fichier source.
@MainActor
struct ProjectBacklogImportService {

    /// Une ligne projet telle que retournée par le script Python.
    struct Row: Decodable {
        let code: String
        let name: String
        let domain: String
        let phase: String
        let cp: String
        let at: String
    }

    /// Synthèse d'un import (pour l'UI).
    struct Summary {
        var inserted: Int = 0
        var updated: Int = 0
        var unchanged: Int = 0
        var entitiesCreated: Int = 0
        var rowsParsed: Int = 0
        var errors: [String] = []
    }

    enum ImportError: LocalizedError {
        case scriptNotFound(URL)
        case pythonNotFound
        case scriptFailed(code: Int32, stderr: String)
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptNotFound(let url):
                return "Script d'import introuvable : \(url.path). Vérifie que le repo est cloné en entier (Scripts/import_projects_xlsx.py)."
            case .pythonNotFound:
                return "python3 introuvable dans le PATH."
            case .scriptFailed(let code, let stderr):
                return "Le script Python a échoué (code \(code)) : \(stderr.prefix(400))"
            case .decodeFailed(let msg):
                return "JSON invalide en sortie du script : \(msg)"
            }
        }
    }

    /// Exécute le script Python sur `xlsxURL`, parse le JSON et upsert les
    /// projets + entités correspondantes dans `context`. Idempotent : un
    /// second appel après mise à jour du fichier rafraîchit les champs CP /
    /// AT / phase / domaine / nom des projets existants.
    static func importBacklog(
        xlsxURL: URL,
        scriptURL: URL,
        context: ModelContext
    ) async throws -> Summary {
        importLog.info("import: xlsx=\(xlsxURL.path, privacy: .public) script=\(scriptURL.path, privacy: .public)")

        let rows = try await runParser(xlsxURL: xlsxURL, scriptURL: scriptURL)
        importLog.info("import: \(rows.count) lignes parsées")

        return try upsert(rows: rows, context: context)
    }

    // MARK: - Python runner

    private static func runParser(xlsxURL: URL, scriptURL: URL) async throws -> [Row] {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw ImportError.scriptNotFound(scriptURL)
        }
        let pythonPath = resolvePython3() ?? "/usr/bin/python3"
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw ImportError.pythonNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path, xlsxURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: ImportError.scriptFailed(
                        code: process.terminationStatus,
                        stderr: errString
                    ))
                    return
                }

                do {
                    let rows = try JSONDecoder().decode([Row].self, from: outData)
                    continuation.resume(returning: rows)
                } catch {
                    let preview = String(data: outData, encoding: .utf8)?.prefix(200) ?? ""
                    continuation.resume(throwing: ImportError.decodeFailed(
                        "\(error.localizedDescription) — préview : \(preview)"
                    ))
                }
            }
        }
    }

    /// Cherche un `python3` capable d'importer openpyxl. On teste les
    /// candidats dans l'ordre et on garde le premier qui répond `OK`.
    /// Cela évite de prendre un Brew Python (3.14) sans openpyxl alors que
    /// `/usr/bin/python3` (3.9) a le module installé via `pip --user`.
    private static func resolvePython3() -> String? {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if probeOpenpyxl(at: path) { return path }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func probeOpenpyxl(at python: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", "import openpyxl"]
        let null = Pipe()
        process.standardOutput = null
        process.standardError = null
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Upsert

    private static func upsert(rows: [Row], context: ModelContext) throws -> Summary {
        var summary = Summary()
        summary.rowsParsed = rows.count

        // Index des entités existantes par nom.
        let existingEntities = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        var entityByName: [String: Entity] = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.name, $0) })

        // Index des projets existants par code.
        let existingProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projectByCode: [String: Project] = Dictionary(
            existingProjects.map { ($0.code, $0) },
            uniquingKeysWith: { lhs, _ in lhs }
        )

        for row in rows {
            // Crée l'entité si nécessaire.
            let entity: Entity
            if let existing = entityByName[row.domain] {
                entity = existing
            } else {
                let new = Entity(name: row.domain)
                context.insert(new)
                entityByName[row.domain] = new
                entity = new
                summary.entitiesCreated += 1
            }

            if let existing = projectByCode[row.code] {
                var changed = false
                if existing.name != row.name { existing.name = row.name; changed = true }
                if existing.domain != row.domain { existing.domain = row.domain; changed = true }
                if existing.phase != row.phase { existing.phase = row.phase; changed = true }
                if existing.chefDeProjet != row.cp { existing.chefDeProjet = row.cp; changed = true }
                if existing.architecte != row.at { existing.architecte = row.at; changed = true }
                if existing.entity?.name != entity.name { existing.entity = entity; changed = true }
                if changed {
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
            } else {
                let project = Project(
                    code: row.code,
                    name: row.name,
                    domain: row.domain,
                    phase: row.phase
                )
                project.chefDeProjet = row.cp
                project.architecte = row.at
                project.entity = entity
                context.insert(project)
                summary.inserted += 1
            }
        }

        try context.save()
        importLog.info("import: \(summary.inserted) créés, \(summary.updated) màj, \(summary.unchanged) inchangés, \(summary.entitiesCreated) entités créées")
        return summary
    }
}
