import XCTest
@testable import OneToOne

final class PanelLayoutEntryTests: XCTestCase {

    func test_defaultLayoutContainsAllCasesVisible() {
        let layout = PanelLayoutEntry.defaultLayout
        XCTAssertEqual(layout.count, RightSidebarPanelID.allCases.count)
        XCTAssertTrue(layout.allSatisfy { $0.visible })
        XCTAssertEqual(layout.map(\.id), RightSidebarPanelID.allCases)
    }

    func test_decodeFromJSON_roundTrip() throws {
        let original: [PanelLayoutEntry] = [
            PanelLayoutEntry(id: .projects, visible: true),
            PanelLayoutEntry(id: .actions, visible: false),
            PanelLayoutEntry(id: .capture, visible: true)
        ]
        let json = PanelLayoutEntry.encode(original)
        let decoded = PanelLayoutEntry.decode(json)
        XCTAssertEqual(decoded, original)
    }

    func test_decodeEmpty_returnsDefault() {
        let decoded = PanelLayoutEntry.decode("")
        XCTAssertEqual(decoded, PanelLayoutEntry.defaultLayout)
    }

    func test_decodeCorrupted_returnsDefault() {
        let decoded = PanelLayoutEntry.decode("not json at all")
        XCTAssertEqual(decoded, PanelLayoutEntry.defaultLayout)
    }

    func test_decodeMissingPanel_appendedAsVisible() {
        // Cas où l'utilisateur a un layout sauvegardé qui ne contient pas
        // `.capture` (ex: nouveau case enum ajouté après update).
        // Le décodeur doit l'ajouter en queue avec visible:true.
        let partial: [PanelLayoutEntry] = [
            PanelLayoutEntry(id: .actions, visible: true),
            PanelLayoutEntry(id: .projects, visible: false)
        ]
        let json = PanelLayoutEntry.encode(partial)
        let decoded = PanelLayoutEntry.decode(json)
        XCTAssertEqual(decoded.count, RightSidebarPanelID.allCases.count)
        XCTAssertTrue(decoded.contains { $0.id == .capture && $0.visible })
        XCTAssertEqual(decoded.first?.id, .actions)
        XCTAssertEqual(decoded[1].id, .projects)
        XCTAssertEqual(decoded.last?.id, .capture)
    }
}
