import Foundation
import os
import AppKit

private let attachmentLog = Logger(subsystem: "com.onetoone.app", category: "attachment")

/// Copies user-picked or dropped files into the app's Application Support
/// directory so they survive moves of the original file. Returns the destination
/// URL (file is fully copied, no bookmark dependency).
///
/// Layout :
///   ~/Library/Application Support/OneToOne/projects/<code>/<timestamp>_<filename>
///   ~/Library/Application Support/OneToOne/notes/<noteStableID>/<timestamp>_<filename>
enum AttachmentImporter {

    enum Bucket {
        case project(code: String)
        case note(stableID: UUID)

        var subpath: String {
            switch self {
            case .project(let code):
                return "projects/\(sanitize(code))"
            case .note(let id):
                return "notes/\(id.uuidString)"
            }
        }
    }

    enum ImporterError: Error, CustomStringConvertible {
        case sourceUnreadable(String)
        case createDirFailed(String)
        case copyFailed(String)

        var description: String {
            switch self {
            case .sourceUnreadable(let m): return "Fichier source illisible: \(m)"
            case .createDirFailed(let m):  return "Impossible de créer le dossier : \(m)"
            case .copyFailed(let m):       return "Copie impossible : \(m)"
            }
        }
    }

    /// Resolves the destination URL inside Application Support and copies the
    /// source file there. Filename is prefixed with a yyyyMMdd-HHmmss timestamp
    /// to avoid collisions when the same file is imported twice.
    @discardableResult
    static func copyIntoAppSupport(source: URL, bucket: Bucket) throws -> URL {
        let fm = FileManager.default

        // Security-scoped resource access if the source comes from a fileImporter.
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        guard fm.fileExists(atPath: source.path) else {
            throw ImporterError.sourceUnreadable(source.path)
        }

        let destDir = baseDirectory().appending(path: bucket.subpath, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            throw ImporterError.createDirFailed(error.localizedDescription)
        }

        let stamp = Self.timestamp()
        let safeName = sanitize(source.lastPathComponent)
        let destURL = destDir.appending(path: "\(stamp)_\(safeName)")

        // If a previous import created the same name in the same second, append
        // a counter rather than overwriting silently.
        let finalURL = uniqueURL(in: destDir, base: destURL)

        do {
            try fm.copyItem(at: source, to: finalURL)
        } catch {
            throw ImporterError.copyFailed(error.localizedDescription)
        }

        attachmentLog.info("copyIntoAppSupport: \(source.lastPathComponent, privacy: .public) -> \(finalURL.path, privacy: .public)")
        return finalURL
    }

    /// Open the file with the system's default application.
    /// For PDF and PPTX this typically resolves to Preview / Keynote.
    @discardableResult
    static func openWithDefaultApp(_ url: URL) -> Bool {
        attachmentLog.info("open: \(url.lastPathComponent, privacy: .public)")
        return NSWorkspace.shared.open(url)
    }

    /// Removes the file from disk. The SwiftData record deletion is the caller's
    /// responsibility (we don't want this service to know about model contexts).
    static func deleteFromDisk(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
            attachmentLog.info("delete: \(url.lastPathComponent, privacy: .public)")
        } catch {
            attachmentLog.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    static func baseDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "OneToOne", directoryHint: .isDirectory)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: illegal).joined(separator: "_")
    }

    private static func uniqueURL(in dir: URL, base: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base.path) { return base }
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        for i in 1...999 {
            let candidate = dir.appending(path: ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return base // give up — overwrite (extremely unlikely)
    }
}
