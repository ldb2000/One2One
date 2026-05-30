import XCTest
import AppKit
@testable import OneToOne

final class MarkdownParserTests: XCTestCase {

    func test_paragraphPlain() throws {
        let attr = MarkdownParser.parse("Hello world")
        XCTAssertEqual(attr.string, "Hello world")
        let firstRange = NSRange(location: 0, length: 1)
        XCTAssertNil(attr.attribute(.mdBold, at: 0, effectiveRange: nil))
        let block = attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType
        XCTAssertEqual(block, .paragraph)
        _ = firstRange
    }

    func test_boldRunHasBoldAttribute() throws {
        let attr = MarkdownParser.parse("hello **bold** world")
        let str = attr.string as NSString
        let boldRange = str.range(of: "bold")
        XCTAssertNotEqual(boldRange.location, NSNotFound)
        let hasBold = attr.attribute(.mdBold, at: boldRange.location, effectiveRange: nil) as? Bool
        XCTAssertEqual(hasBold, true)
        let hasBoldOnPrefix = attr.attribute(.mdBold, at: 0, effectiveRange: nil) as? Bool
        XCTAssertNil(hasBoldOnPrefix)
    }

    func test_h2BlockTypeApplied() throws {
        let attr = MarkdownParser.parse("## Title")
        XCTAssertEqual(attr.string, "Title")
        let block = attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType
        XCTAssertEqual(block, .h2)
    }

    func test_taskListUncheckedAndChecked() throws {
        let md = """
        - [ ] todo
        - [x] done
        """
        let attr = MarkdownParser.parse(md)
        let first = attr.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(first?.kind, .task)
        XCTAssertEqual(first?.checked, false)
        let str = attr.string as NSString
        let doneRange = str.range(of: "done")
        XCTAssertNotEqual(doneRange.location, NSNotFound)
        let second = attr.attribute(.mdListInfo, at: doneRange.location, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(second?.kind, .task)
        XCTAssertEqual(second?.checked, true)
    }
}
