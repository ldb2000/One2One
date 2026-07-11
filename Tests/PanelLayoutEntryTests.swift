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
        // Since the new cases (presence, transcription, managerAgenda) are migrated
        // by PanelLayoutEntry.decode and appended as visible, the roundtrip
        // now includes them. Check that the original 3 are preserved and the
        // new 3 are appended.
        XCTAssertEqual(Array(decoded.prefix(3)), original)
        XCTAssertTrue(decoded.contains { $0.id == .presence && $0.visible })
        XCTAssertTrue(decoded.contains { $0.id == .transcription && $0.visible })
        XCTAssertTrue(decoded.contains { $0.id == .managerAgenda && $0.visible })
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
        // The last appended card is now .managerAgenda (the last case enum)
        XCTAssertEqual(decoded.last?.id, .managerAgenda)
    }

    func test_defaultLayoutContainsNewCards() {
        let ids = PanelLayoutEntry.defaultLayout.map(\.id)
        XCTAssertTrue(ids.contains(.presence))
        XCTAssertTrue(ids.contains(.transcription))
        XCTAssertTrue(ids.contains(.managerAgenda))
        XCTAssertEqual(ids.first, .presence)   // Présence en tête
    }

    func test_decodeMigratesNewCardsAtEnd() {
        // JSON ancien (avant l'ajout des cartes) : seulement actions/projects/capture.
        let old = #"[{"id":"actions","visible":true},{"id":"projects","visible":false},{"id":"capture","visible":true}]"#
        let entries = PanelLayoutEntry.decode(old)
        let ids = entries.map(\.id)
        // Les 3 anciens préservés dans l'ordre + les nouveaux ajoutés en queue, visibles.
        XCTAssertEqual(Array(ids.prefix(3)), [.actions, .projects, .capture])
        XCTAssertTrue(ids.contains(.presence))
        XCTAssertTrue(ids.contains(.transcription))
        XCTAssertTrue(ids.contains(.managerAgenda))
        XCTAssertEqual(entries.first(where: { $0.id == .projects })?.visible, false) // visibilité préservée
        XCTAssertEqual(entries.first(where: { $0.id == .presence })?.visible, true)  // nouveau → visible
    }
}
