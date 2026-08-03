import XCTest
@testable import OneToOne

/// Couvre directement le point de construction partagé par `MarkdownParser`,
/// `EditorTextView.paste(_:)` et `MarkdownToolbar` — voir doc-comment
/// d'`ImagePlaceholder`.
final class ImagePlaceholderTests: XCTestCase {
    func test_attributedString_isSingleFFFCCharacterCarryingURLAndAlt() {
        let url = URL(string: "file:///tmp/x.png")!
        let result = ImagePlaceholder.attributedString(for: url, alt: "légende")

        XCTAssertEqual(result.string, "\u{FFFC}")
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(attrs[.mdImageURL] as? URL, url)
        XCTAssertEqual(attrs[.mdImageAlt] as? String, "légende")
    }
}
