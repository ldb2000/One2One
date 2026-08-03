import XCTest
import AppKit
@testable import OneToOne

final class MarkdownSerializerTests: XCTestCase {

    func test_plainParagraph() {
        let s = NSAttributedString(string: "Hello", attributes: [.mdBlockType: BlockType.paragraph])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "Hello")
    }

    func test_heading2() {
        let s = NSAttributedString(string: "Title", attributes: [.mdBlockType: BlockType.h2])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "## Title")
    }

    func test_boldInline() {
        let m = NSMutableAttributedString(string: "hello bold word",
                                          attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdBold, value: true, range: NSRange(location: 6, length: 4))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "hello **bold** word")
    }

    func test_taskListUnchecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: false)
        let s = NSAttributedString(string: "todo",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [ ] todo")
    }

    func test_taskListChecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: true)
        let s = NSAttributedString(string: "done",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [x] done")
    }

    /// Dans un `NSTextView`, du texte tapé juste après une image hérite des
    /// `typingAttributes` du caractère précédent — donc de `mdImageURL` et
    /// `mdImageAlt` — sans être lui-même une image. Ce layout ne peut pas être
    /// produit par le parser (qui n'attache ces attributs qu'au seul
    /// caractère `U+FFFC`) ; on le construit ici à la main pour vérifier que
    /// le texte qui suit n'est pas avalé par le markup de l'image.
    func test_imageAttributeOnRunDoesNotSwallowTrailingText() {
        let m = NSMutableAttributedString(string: "\u{FFFC}X",
                                           attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdImageURL, value: URL(string: "file:///x.png")!,
                       range: NSRange(location: 0, length: 2))
        m.addAttribute(.mdImageAlt, value: "a",
                       range: NSRange(location: 0, length: 2))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "![a](file:///x.png)X")
    }
}
