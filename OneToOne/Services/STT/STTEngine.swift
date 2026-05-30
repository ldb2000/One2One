import Foundation

#if canImport(MLX)
import MLX
#endif

/// Moteur STT pluggable. Les deux impls (Cohere, Voxtral) wrappent un modèle
/// MLX conforme `STTGenerationModel`. `transcribe` prend un clip 16 kHz mono
/// déjà découpé et renvoie le texte trimmé.
@MainActor
protocol STTEngine: AnyObject {
    var isLoaded: Bool { get }
    func load() async throws
    #if canImport(MLX)
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) -> String
    #endif
}

/// Résolution commune du dossier modèle : cache HuggingFace partagé, puis
/// dossier managé par OneToOne, puis chemin manuel (UserDefaults). `contains`
/// valide la présence des fichiers requis.
enum STTModelResolver {
    /// `repoId` ex. "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit".
    /// `manualKey` : clé UserDefaults d'un chemin choisi à la main (peut être nil).
    static func resolveExistingDirectory(repoId: String,
                                         manualKey: String?,
                                         contains: (URL) -> Bool) -> URL? {
        for url in candidateDirectories(repoId: repoId, manualKey: manualKey)
        where contains(url) { return url }
        return nil
    }

    static func candidateDirectories(repoId: String, manualKey: String?) -> [URL] {
        var out: [URL] = []
        if let snap = firstSnapshot(repoId: repoId) { out.append(snap) }
        out.append(managedDirectory(repoId: repoId))
        if let manualKey, let manual = UserDefaults.standard.string(forKey: manualKey) {
            out.append(URL(fileURLWithPath: manual))
        }
        return out
    }

    static func managedDirectory(repoId: String) -> URL {
        let base = URL.applicationSupportDirectory
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private static func firstSnapshot(repoId: String) -> URL? {
        let safeRepo = "models--" + repoId.replacingOccurrences(of: "/", with: "--")
        let snapshotsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            .appendingPathComponent(safeRepo, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: nil) else { return nil }
        return entries.first
    }

    /// Vrai s'il existe config.json + au moins un .safetensors dans le dossier.
    static func containsSafetensors(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return false }
        return files.contains { $0.pathExtension == "safetensors" }
    }
}
