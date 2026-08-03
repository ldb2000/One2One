import XCTest
import AppKit
@testable import OneToOne

final class ImageAttachmentFactoryTests: XCTestCase {

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
}
