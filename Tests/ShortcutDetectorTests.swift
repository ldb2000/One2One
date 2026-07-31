import AppKit
import XCTest
@testable import OneToOne

final class ShortcutDetectorTests: XCTestCase {
    func test_typingClosingBoldMarkerConvertsMarkersToBoldAttribute() {
        let textView = NSTextView()
        textView.string = "**gras**"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        ShortcutDetector.apply(
            after: "*",
            in: textView,
            cursor: 8,
            features: .prep
        )

        XCTAssertEqual(textView.string, "gras")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.textStorage?.attribute(.mdBold, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(MarkdownSerializer.serialize(textView.textStorage ?? NSTextStorage()), "**gras**")
    }

    func test_typingClosingItalicMarkerConvertsMarkersToItalicAttribute() {
        let textView = NSTextView()
        textView.string = "_mot_"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        ShortcutDetector.apply(
            after: "_",
            in: textView,
            cursor: 5,
            features: .prep
        )

        XCTAssertEqual(textView.string, "mot")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(textView.textStorage?.attribute(.mdItalic, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(MarkdownSerializer.serialize(textView.textStorage ?? NSTextStorage()), "_mot_")
    }
}
