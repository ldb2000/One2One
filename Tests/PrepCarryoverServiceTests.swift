import XCTest
@testable import OneToOne

final class PrepCarryoverServiceTests: XCTestCase {

    func test_extractUncheckedItems_returnsOnlyUnchecked() {
        let md = """
        # Prep
        - [ ] First unchecked
        - [x] Already done
          - [ ] Indented unchecked
        Some other line
        - [ ] Last unchecked
        """
        let items = PrepCarryoverService.extractUncheckedItems(from: md)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], "- [ ] First unchecked")
        XCTAssertEqual(items[1], "  - [ ] Indented unchecked")
        XCTAssertEqual(items[2], "- [ ] Last unchecked")
    }

    func test_extractUncheckedItems_ignoresCheckedAndPlainText() {
        let md = """
        - [x] Done
        - Not a checkbox
        Some prose
        """
        XCTAssertTrue(PrepCarryoverService.extractUncheckedItems(from: md).isEmpty)
    }
}
