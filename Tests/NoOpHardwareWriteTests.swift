import XCTest
@testable import Chiptune

/// A hardware key that writes what the cell already holds changes nothing, so
/// it must not add an Undo step or wipe Redo (issue #11). The cursor still moves.
@MainActor
final class NoOpHardwareWriteTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "HW"))
        studio.undoCoalescingWindow = 0
        studio.setNote(track: 0, step: 0, note: Chip.emptyNote)
        studio.setNote(track: 0, step: 1, note: Chip.emptyNote)
        studio.selectedTrack = 0
        studio.selectedStep = 0
        // One real edit, undone, so Redo is armed.
        studio.checkpoint()
        studio.song.tempo = 100
        studio.undo()
        XCTAssertTrue(studio.canRedo)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testSameNoteKeepsRedoAndAdvances() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.selectedStep = 0
        studio.typeNote(60)
        XCTAssertTrue(studio.canRedo)
        XCTAssertEqual(studio.selectedStep, 1)
        XCTAssertEqual(studio.selectedNote, 60)
    }

    func testRestOnRestKeepsRedo() {
        studio.setNote(track: 0, step: 0, note: Chip.noteOff)
        studio.typeNote(Chip.noteOff)
        XCTAssertTrue(studio.canRedo)
        XCTAssertEqual(studio.selectedStep, 1)
    }

    func testDeleteOnEmptyKeepsRedoAndAdvances() {
        studio.clearAtCursor()
        XCTAssertTrue(studio.canRedo)
        XCTAssertEqual(studio.selectedStep, 1)
    }

    func testDifferentNoteStillCheckpoints() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.typeNote(62)
        XCTAssertFalse(studio.canRedo)
        XCTAssertEqual(studio.pattern.rows[0][0], 62)
    }

    func testDeleteOnFilledStillCheckpoints() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.clearAtCursor()
        XCTAssertFalse(studio.canRedo)
        XCTAssertEqual(studio.pattern.rows[0][0], Chip.emptyNote)
    }
}
