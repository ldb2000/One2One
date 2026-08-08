import XCTest
@testable import ProbeCore

/// Undo unifié : l'historique vit au-dessus des vues et ignore complètement
/// les `UndoManager` des `NSTextView`, qui sont désactivés.
final class ProbeHistoryTests: XCTestCase {

    private func snapshot(_ texts: [String], caret: ProbePosition) -> ProbeSnapshot {
        ProbeSnapshot(document: ProbeDocument(texts: texts),
                      selection: ProbeSelection(caret: caret))
    }

    func test_undo_restoresTheDocumentAndTheSelection() {
        let history = ProbeHistory()
        let before = snapshot(["Un", "Deux"], caret: ProbePosition(blockIndex: 1, offset: 0))
        let after = snapshot(["UnDeux"], caret: ProbePosition(blockIndex: 0, offset: 2))

        history.record(before)
        let restored = history.undo(current: after)

        XCTAssertEqual(restored, before)
    }

    /// Le point du prototype : deux mutations qui ont touché **des blocs
    /// différents** s'annulent dans l'ordre inverse, globalement.
    func test_undo_walksBackAcrossBlocksInReverseOrder() {
        let history = ProbeHistory()
        let first = snapshot(["a", "b"], caret: ProbePosition(blockIndex: 0, offset: 1))
        let second = snapshot(["aX", "b"], caret: ProbePosition(blockIndex: 1, offset: 1))
        let third = snapshot(["aX", "bY"], caret: ProbePosition(blockIndex: 1, offset: 2))

        history.record(first)
        history.record(second)

        XCTAssertEqual(history.undo(current: third), second)
        XCTAssertEqual(history.undo(current: second), first)
        XCTAssertNil(history.undo(current: first), "pile épuisée")
    }

    func test_redo_replaysWhatUndoTookBack() {
        let history = ProbeHistory()
        let before = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))
        let after = snapshot(["UnX"], caret: ProbePosition(blockIndex: 0, offset: 3))

        history.record(before)
        _ = history.undo(current: after)

        XCTAssertEqual(history.redo(current: before), after)
    }

    /// Une nouvelle mutation après un undo jette la pile de rétablissement —
    /// comportement attendu de tout éditeur.
    func test_record_afterAnUndo_dropsTheRedoStack() {
        let history = ProbeHistory()
        let before = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))
        let after = snapshot(["UnX"], caret: ProbePosition(blockIndex: 0, offset: 3))

        history.record(before)
        _ = history.undo(current: after)
        XCTAssertTrue(history.canRedo)

        history.record(before)

        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.redo(current: before))
    }

    func test_anEmptyHistory_canNeitherUndoNorRedo() {
        let history = ProbeHistory()
        let now = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))

        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.undo(current: now))
        XCTAssertNil(history.redo(current: now))
    }
}
