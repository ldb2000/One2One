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
}
