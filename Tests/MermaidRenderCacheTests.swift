import XCTest
@testable import OneToOne

final class MermaidRenderCacheTests: XCTestCase {

    override func tearDown() {
        MermaidRenderCache.invalidateMemoryCache()
        super.tearDown()
    }

    // MARK: - key(source:isDark:)

    /// Le piège mesuré sur cette branche : les couleurs mermaid dépendent du
    /// thème (clair/sombre), qui bascule automatiquement avec l'heure — la
    /// clé doit donc changer avec `isDark` pour un même source, sinon un
    /// diagramme rendu de jour resservirait ses couleurs claires une fois la
    /// machine passée en sombre.
    func test_key_differsBetweenLightAndDarkForSameSource() {
        let light = MermaidRenderCache.key(source: "graph TD; A-->B", isDark: false)
        let dark = MermaidRenderCache.key(source: "graph TD; A-->B", isDark: true)
        XCTAssertNotEqual(light, dark)
    }

    func test_key_differsBetweenDifferentSourcesForSameAppearance() {
        let a = MermaidRenderCache.key(source: "graph TD; A-->B", isDark: false)
        let b = MermaidRenderCache.key(source: "graph TD; A-->C", isDark: false)
        XCTAssertNotEqual(a, b)
    }

    func test_key_isStableForSameInputs() {
        let first = MermaidRenderCache.key(source: "graph TD; A-->B", isDark: true)
        let second = MermaidRenderCache.key(source: "graph TD; A-->B", isDark: true)
        XCTAssertEqual(first, second)
    }

    // MARK: - store / cachedRenderData

    func test_store_thenCachedRenderData_roundTrips() {
        let key = "test-\(UUID().uuidString)"
        let svg = Data("<svg>test</svg>".utf8)
        defer { try? FileManager.default.removeItem(at: MermaidRenderCache.directory.appendingPathComponent("\(key).render")) }

        MermaidRenderCache.store(svg, forKey: key)
        XCTAssertEqual(MermaidRenderCache.cachedRenderData(forKey: key), svg)
    }

    func test_cachedRenderData_missingKey_returnsNil() {
        XCTAssertNil(MermaidRenderCache.cachedRenderData(forKey: "onetoone-does-not-exist-\(UUID().uuidString)"))
    }

    /// `invalidateMemoryCache()` ne doit vider que la mémoire — le fichier
    /// écrit sur disque doit rester lisible après (sinon `store`/
    /// `cachedRenderData` ne serait pas un vrai cache disque, juste un cache
    /// mémoire qui écrit en plus sur disque sans jamais relire).
    func test_invalidateMemoryCache_doesNotDeleteDiskFile() {
        let key = "test-\(UUID().uuidString)"
        let svg = Data("<svg>persisted</svg>".utf8)
        defer { try? FileManager.default.removeItem(at: MermaidRenderCache.directory.appendingPathComponent("\(key).render")) }

        MermaidRenderCache.store(svg, forKey: key)
        MermaidRenderCache.invalidateMemoryCache()

        XCTAssertEqual(MermaidRenderCache.cachedRenderData(forKey: key), svg)
    }

    /// Distingue le cache mémoire du simple cache disque : après `store`, un
    /// appel à `cachedRenderData` doit pouvoir servir depuis la mémoire même si
    /// le fichier disque a disparu entre-temps (sans quoi `memoryCache`
    /// serait un no-op mort — mutation qu'un test se contentant du seul
    /// round-trip disque ne détecterait pas).
    func test_cachedRenderData_servesFromMemory_evenIfDiskFileDeletedAfterStore() {
        let key = "test-\(UUID().uuidString)"
        let svg = Data("<svg>memory</svg>".utf8)
        let fileURL = MermaidRenderCache.directory.appendingPathComponent("\(key).render")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MermaidRenderCache.store(svg, forKey: key)
        try? FileManager.default.removeItem(at: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "précondition : le fichier disque a bien disparu")

        XCTAssertEqual(MermaidRenderCache.cachedRenderData(forKey: key), svg, "doit être servi depuis le cache mémoire")
    }

    func test_directory_pointsUnderApplicationSupportRenderCache() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let expected = appSupport.appendingPathComponent("OneToOne/render-cache", isDirectory: true)
        XCTAssertEqual(MermaidRenderCache.directory.standardizedFileURL, expected.standardizedFileURL)
    }
}
