import XCTest
import AppKit
@testable import OneToOne

final class ImageAttachmentFactoryTests: XCTestCase {

    /// Le cache et l'historique des échecs de `ImageAttachmentFactory` sont un
    /// état statique partagé entre tous les tests de cette classe (et entre
    /// classes, dans le même process) : sans reset avant/après chaque test, un
    /// test qui peuple ces états en influence d'autres selon l'ordre
    /// d'exécution.
    override func setUp() {
        super.setUp()
        ImageAttachmentFactory.invalidate()
    }

    override func tearDown() {
        ImageAttachmentFactory.invalidate()
        super.tearDown()
    }

    // MARK: - displayBounds

    func test_imageNarrowerThanMaxWidth_isNotScaled() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 200, height: 100))
        XCTAssertEqual(bounds.width, 200)
        XCTAssertEqual(bounds.height, 100)
    }

    func test_imageExactlyAtMaxWidth_isNotScaled() {
        let bounds = ImageAttachmentFactory.displayBounds(
            for: NSSize(width: ImageAttachmentFactory.maxWidth, height: 200)
        )
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertEqual(bounds.height, 200)
    }

    func test_imageWiderThanMaxWidth_isScaledKeepingAspectRatio() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 960, height: 480))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertEqual(bounds.height, ImageAttachmentFactory.maxWidth / 2)
    }

    func test_scaledHeight_isRoundedToWholeNumber() {
        // 480/500 * 333 = 319.68 → doit être arrondi à 320, pas tronqué.
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 500, height: 333))
        XCTAssertEqual(bounds.height, 320)
    }

    func test_veryWideImage_scaledHeightHasFloorOfOne() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 2000, height: 1))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertEqual(bounds.height, 1)
    }

    func test_degenerateSize_fallsBackToPlaceholderBounds() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 0, height: 0))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertGreaterThan(bounds.height, 0)
    }

    // MARK: - attachment(for:)

    func test_missingFile_returnsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-inexistant-\(UUID().uuidString).png")
        XCTAssertNil(ImageAttachmentFactory.attachment(for: url))
    }

    func test_nonFileURL_returnsNilWithoutNetworkAccess() {
        // 192.0.2.1 (TEST-NET-1, RFC 5737) est réservée à la documentation et
        // non routable : si un accès réseau était tenté malgré la garde,
        // l'appel resterait bloqué plusieurs secondes en attendant un
        // timeout de connexion — ce que l'assertion de délai détecterait.
        let url = URL(string: "http://192.0.2.1/onetoone-test.png")!

        let start = Date()
        let result = ImageAttachmentFactory.attachment(for: url)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 1, "une URL non-fichier ne doit déclencher aucun accès réseau")
    }

    func test_sameURL_returnsSameCachedAttachmentInstance() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))
        let second = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))

        XCTAssertTrue(first === second)
    }

    func test_invalidate_forcesNewInstanceOnNextCall() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))
        let second = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))
        XCTAssertTrue(first === second, "sans invalidate(), deux appels doivent partager la même instance")

        ImageAttachmentFactory.invalidate()
        let third = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))
        XCTAssertFalse(second === third, "après invalidate(), une nouvelle instance doit être créée")
    }

    func test_missingFileFailure_isCached_andNotRetried() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-cache-failure-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        // Premier appel : le fichier n'existe pas encore → échec mémorisé.
        XCTAssertNil(ImageAttachmentFactory.attachment(for: url))

        // On crée ensuite un vrai PNG au même chemin. Si l'échec précédent
        // n'était pas mis en cache, cet appel relirait le disque et
        // réussirait — ce que l'assertion suivante détecterait.
        try makeTemporaryPNGData().write(to: url)

        XCTAssertNil(
            ImageAttachmentFactory.attachment(for: url),
            "l'échec précédent doit être court-circuité, pas retenté"
        )
    }

    // MARK: - Fixtures

    /// Construit les octets d'un petit PNG valide directement via
    /// `NSBitmapImageRep`, sans passer par `NSImage.lockFocus()` — qui
    /// dépend du window server et peut échouer en environnement headless.
    private func makeTemporaryPNGData() throws -> Data {
        let bitmapRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 10,
            pixelsHigh: 10,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmapRep.representation(using: .png, properties: [:]))
    }

    /// Écrit un petit PNG dans le répertoire temporaire. Le fichier n'est pas
    /// supprimé par cette fonction — l'appelant en a la responsabilité.
    private func makeTemporaryPNGFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-cache-test-\(UUID().uuidString).png")
        try makeTemporaryPNGData().write(to: url)
        return url
    }
}
