import AppKit
import XCTest
@testable import OneToOne

final class StyleRendererTests: XCTestCase {
    func test_boldAttributeRendersBoldWithoutMarkdownMarkers() {
        let storage = NSMutableAttributedString(string: "hello bold")
        storage.addAttribute(.mdBold, value: true, range: NSRange(location: 6, length: 4))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(textStorage.string, "hello bold")
        XCTAssertTrue(isBold(textStorage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont))
        XCTAssertFalse(isBold(textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
    }

    func test_partialStyleRefreshOnlyRecomputesAffectedLine() {
        let storage = NSMutableAttributedString(string: "Title\nplain")
        storage.addAttribute(.mdBlockType, value: BlockType.h2, range: NSRange(location: 0, length: 5))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)

        let plainRange = (textStorage.string as NSString).range(of: "plain")
        textStorage.addAttribute(.mdBold, value: true, range: plainRange)
        StyleRenderer.applyVisualStyle(to: textStorage, affectedRange: plainRange)

        XCTAssertTrue(isBold(textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
        XCTAssertTrue(isBold(textStorage.attribute(.font, at: plainRange.location, effectiveRange: nil) as? NSFont))
    }

    private func isBold(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }
}
