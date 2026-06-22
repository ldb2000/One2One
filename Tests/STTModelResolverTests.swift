import XCTest
@testable import OneToOne

/// Résolution du dossier modèle STT : priorité aux variantes, repli sur ce qui
/// est réellement en cache. Régression du bug « Modèle STT introuvable » quand
/// la variante préférée (8bit) n'est pas téléchargée mais qu'une autre (fp16)
/// l'est.
final class STTModelResolverTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("STTResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Crée un snapshot HF complet (config.json + model.safetensors) pour `repoId`
    /// sous `hubRoot`, et renvoie l'URL du dossier snapshot.
    @discardableResult
    private func makeSnapshot(repoId: String, commit: String, in hubRoot: URL) throws -> URL {
        let safe = "models--" + repoId.replacingOccurrences(of: "/", with: "--")
        let snap = hubRoot.appendingPathComponent(safe, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(commit, isDirectory: true)
        try FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snap.appendingPathComponent("config.json"))
        try Data().write(to: snap.appendingPathComponent("model.safetensors"))
        return snap
    }

    private func resolve(_ repoIds: [String], hubRoot: URL, managedRoot: URL) -> URL? {
        STTModelResolver.candidateDirectories(
            repoIds: repoIds, hubRoot: hubRoot, managedRoot: managedRoot,
            manualPath: nil, ensureManaged: false
        ).first { STTModelResolver.containsSafetensors($0) }
    }

    /// Régression : repo « 8bit » préféré absent, variante « fp16 » présente en
    /// cache HF. La résolution doit retomber sur la fp16 plutôt que d'échouer.
    func testFallsBackToCachedVariantWhenPreferredMissing() throws {
        let hub = tmp.appendingPathComponent("hub", isDirectory: true)
        let managed = tmp.appendingPathComponent("managed", isDirectory: true)
        let eightBit = "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"
        let fp16 = "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"
        let fp16Snap = try makeSnapshot(repoId: fp16, commit: "abc123", in: hub)

        let resolved = resolve([eightBit, fp16], hubRoot: hub, managedRoot: managed)
        // `contentsOfDirectory` renvoie des chemins résolus (/var → /private/var) :
        // on compare donc après résolution des liens symboliques.
        XCTAssertEqual(resolved?.resolvingSymlinksInPath(), fp16Snap.resolvingSymlinksInPath())
    }

    /// Le repo préféré, s'il est présent, l'emporte sur la variante de repli.
    func testPrefersFirstRepoWhenBothCached() throws {
        let hub = tmp.appendingPathComponent("hub", isDirectory: true)
        let managed = tmp.appendingPathComponent("managed", isDirectory: true)
        let eightBit = "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"
        let fp16 = "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"
        let eightSnap = try makeSnapshot(repoId: eightBit, commit: "111", in: hub)
        try makeSnapshot(repoId: fp16, commit: "222", in: hub)

        let resolved = resolve([eightBit, fp16], hubRoot: hub, managedRoot: managed)
        XCTAssertEqual(resolved?.resolvingSymlinksInPath(), eightSnap.resolvingSymlinksInPath())
    }

    /// Sans variante en cache, aucune résolution ; les dossiers managés des deux
    /// variantes figurent dans les candidats (servant au message d'erreur).
    func testNoCandidateResolvesWhenNothingCached() throws {
        let hub = tmp.appendingPathComponent("hub", isDirectory: true)
        let managed = tmp.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        let repos = ["a/b-8bit", "a/b-fp16"]

        XCTAssertNil(resolve(repos, hubRoot: hub, managedRoot: managed))
        let cands = STTModelResolver.candidateDirectories(
            repoIds: repos, hubRoot: hub, managedRoot: managed,
            manualPath: nil, ensureManaged: false)
        XCTAssertEqual(cands.count, 2)
        XCTAssertTrue(cands[0].path.hasSuffix("a_b-8bit"))
        XCTAssertTrue(cands[1].path.hasSuffix("a_b-fp16"))
    }
}
