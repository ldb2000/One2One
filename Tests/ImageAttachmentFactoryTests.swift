import XCTest
import AppKit
@testable import OneToOne

final class ImageAttachmentFactoryTests: XCTestCase {

    /// Le cache de `ImageAttachmentFactory` est un état statique partagé entre
    /// tous les tests de cette classe : sans ce reset, un test qui peuple le
    /// cache influence les suivants selon l'ordre d'exécution.
    override func setUp() {
        super.setUp()
        ImageAttachmentFactory.invalidate()
    }

    func test_imageNarrowerThanMaxWidth_isNotScaled() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 200, height: 100))
        XCTAssertEqual(bounds.width, 200)
        XCTAssertEqual(bounds.height, 100)
    }

    func test_imageWiderThanMaxWidth_isScaledKeepingAspectRatio() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 960, height: 480))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertEqual(bounds.height, ImageAttachmentFactory.maxWidth / 2)
    }

    func test_degenerateSize_fallsBackToPlaceholderBounds() {
        let bounds = ImageAttachmentFactory.displayBounds(for: NSSize(width: 0, height: 0))
        XCTAssertEqual(bounds.width, ImageAttachmentFactory.maxWidth)
        XCTAssertGreaterThan(bounds.height, 0)
    }

    func test_missingFile_returnsNil() {
        let url = URL(fileURLWithPath: "/tmp/onetoone-inexistant-\(UUID().uuidString).png")
        XCTAssertNil(ImageAttachmentFactory.attachment(for: url))
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
        ImageAttachmentFactory.invalidate()
        let second = try XCTUnwrap(ImageAttachmentFactory.attachment(for: url))

        XCTAssertFalse(first === second)
    }

    /// Écrit un petit PNG dans le répertoire temporaire, sur le même principe
    /// (TIFF → `NSBitmapImageRep` → PNG) que `ImagePasteService.saveClipboardImage()`
    /// dans `OneToOne/Views/EditableTextField.swift`. Le fichier n'est pas
    /// supprimé par cette fonction — l'appelant en a la responsabilité.
    private func makeTemporaryPNGFile() throws -> URL {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmapRep = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmapRep.representation(using: .png, properties: [:]))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-cache-test-\(UUID().uuidString).png")
        try pngData.write(to: url)
        return url
    }
}
