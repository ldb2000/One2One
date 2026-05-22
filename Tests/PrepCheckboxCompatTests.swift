import XCTest
@testable import OneToOne

/// Garantit que les checkboxes générées par le serializer matchent le regex
/// de `PrepCarryoverService.extractUncheckedItems` — c'est la condition pour
/// que le carryover fonctionne après migration des champs prep.
final class PrepCheckboxCompatTests: XCTestCase {

    func test_uncheckedItemDetected() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: false)
        let s = NSAttributedString(string: "demander statut DAT",
                                   attributes: [.mdListInfo: info])
        let md = MarkdownSerializer.serialize(s)
        XCTAssertEqual(md, "- [ ] demander statut DAT")
        let extracted = PrepCarryoverService.extractUncheckedItems(from: md)
        XCTAssertEqual(extracted, ["- [ ] demander statut DAT"])
    }

    func test_checkedItemIgnored() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: true)
        let s = NSAttributedString(string: "fait",
                                   attributes: [.mdListInfo: info])
        let md = MarkdownSerializer.serialize(s)
        XCTAssertEqual(md, "- [x] fait")
        XCTAssertTrue(PrepCarryoverService.extractUncheckedItems(from: md).isEmpty)
    }

    func test_multipleItemsMixedStates() {
        let unchecked = NSMutableAttributedString(string: "a")
        unchecked.addAttribute(.mdListInfo,
                               value: ListInfo(kind: .task, level: 0, checked: false),
                               range: NSRange(location: 0, length: 1))
        let checked = NSMutableAttributedString(string: "b")
        checked.addAttribute(.mdListInfo,
                             value: ListInfo(kind: .task, level: 0, checked: true),
                             range: NSRange(location: 0, length: 1))
        let combined = NSMutableAttributedString()
        combined.append(unchecked)
        combined.append(NSAttributedString(string: "\n"))
        combined.append(checked)
        let md = MarkdownSerializer.serialize(combined)
        XCTAssertEqual(md, "- [ ] a\n- [x] b")
        XCTAssertEqual(PrepCarryoverService.extractUncheckedItems(from: md), ["- [ ] a"])
    }
}
