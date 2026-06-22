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
    /// Transcrit un clip 16 kHz mono déjà découpé et renvoie le texte trimmé
    /// (chaîne vide si le modèle n'est pas chargé).
    func transcribe(clip: MLXArray, language: String, maxTokens: Int) async -> String
    #endif
}

/// Résolution commune du dossier modèle : cache HuggingFace partagé, puis
/// dossier managé par OneToOne, puis chemin manuel (UserDefaults). `contains`
/// valide la présence des fichiers requis. Plusieurs `repoIds` peuvent être
/// fournis (variantes du même modèle, ex. 8bit puis fp16) : ils sont essayés
/// dans l'ordre, ce qui permet de retomber sur la variante réellement en cache.
enum STTModelResolver {
    /// Racine du cache HuggingFace partagé (`~/.cache/huggingface/hub`).
    static var huggingFaceHubRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    /// Racine des modèles managés par OneToOne sous Application Support.
    static var managedModelsRoot: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    /// `repoId` ex. "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit".
    /// `manualKey` : clé UserDefaults d'un chemin choisi à la main (peut être nil).
    static func resolveExistingDirectory(repoId: String,
                                         manualKey: String?,
                                         contains: (URL) -> Bool) -> URL? {
        resolveExistingDirectory(repoIds: [repoId], manualKey: manualKey, contains: contains)
    }

    /// Variante multi-repo : essaie les variantes dans l'ordre fourni.
    static func resolveExistingDirectory(repoIds: [String],
                                         manualKey: String?,
                                         contains: (URL) -> Bool) -> URL? {
        for url in candidateDirectories(repoIds: repoIds, manualKey: manualKey)
        where contains(url) { return url }
        return nil
    }

    static func candidateDirectories(repoId: String, manualKey: String?) -> [URL] {
        candidateDirectories(repoIds: [repoId], manualKey: manualKey)
    }

    /// Dossiers candidats dans l'ordre de priorité, pour chaque variante : snapshot
    /// HF le plus récent puis dossier managé OneToOne ; enfin un éventuel chemin
    /// manuel (clé UserDefaults). Sert aussi au message d'erreur `modelMissing`.
    static func candidateDirectories(repoIds: [String], manualKey: String?) -> [URL] {
        let manual = manualKey
            .flatMap { UserDefaults.standard.string(forKey: $0) }
            .map { URL(fileURLWithPath: $0) }
        return candidateDirectories(repoIds: repoIds, hubRoot: huggingFaceHubRoot,
                                    managedRoot: managedModelsRoot, manualPath: manual,
                                    ensureManaged: true)
    }

    /// Cœur pur (racines injectables, sans état global) — utilisé par les
    /// surcouches de production et directement par les tests.
    /// `ensureManaged` crée les dossiers managés au passage (utile en prod pour
    /// y déposer un modèle à la main ; à laisser `false` en test).
    static func candidateDirectories(repoIds: [String], hubRoot: URL, managedRoot: URL,
                                     manualPath: URL?, ensureManaged: Bool) -> [URL] {
        var out: [URL] = []
        for repoId in repoIds {
            if let snap = firstSnapshot(repoId: repoId, hubRoot: hubRoot) { out.append(snap) }
            let managed = managedDirectory(repoId: repoId, root: managedRoot)
            if ensureManaged { ensureDirectoryExists(managed) }
            out.append(managed)
        }
        if let manualPath { out.append(manualPath) }
        return out
    }

    /// Dossier modèle géré par OneToOne sous Application Support (créé au besoin),
    /// dérivé de `repoId` avec les `/` remplacés par `_`.
    static func managedDirectory(repoId: String) -> URL {
        let dir = managedDirectory(repoId: repoId, root: managedModelsRoot)
        ensureDirectoryExists(dir)
        return dir
    }

    /// URL du dossier managé (calcul pur, sans effet de bord).
    static func managedDirectory(repoId: String, root: URL) -> URL {
        root.appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    private static func ensureDirectoryExists(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Snapshot HF le plus récent (par tri lexicographique du commit) pour `repoId`
    /// sous `hubRoot`, ou nil si le dépôt n'est pas en cache.
    static func firstSnapshot(repoId: String, hubRoot: URL) -> URL? {
        let safeRepo = "models--" + repoId.replacingOccurrences(of: "/", with: "--")
        let snapshotsRoot = hubRoot
            .appendingPathComponent(safeRepo, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: nil) else { return nil }
        return entries.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    /// Vrai s'il existe config.json + au moins un .safetensors dans le dossier.
    static func containsSafetensors(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return false }
        return files.contains { $0.pathExtension == "safetensors" }
    }
}
