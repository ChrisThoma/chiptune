import XCTest
@testable import Chiptune

/// The clear-pattern and clear-track alerts both `checkpoint()` before they
/// erase notes, so both are undoable — but neither's copy said so. This pins
/// the copy to promise it, the way the delete-pattern alert already does.
@MainActor
final class ConfirmationCopyTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Confirm"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testClearPatternCopyPromisesUndoBecauseClearingCheckpoints() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.clearPattern()
        XCTAssertTrue(studio.canUndo)
        XCTAssertTrue(ConfirmationCopy.clearPattern.hasSuffix("Undo brings them back."))
    }

    func testClearTrackCopyPromisesUndoBecauseClearingCheckpoints() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.clearTrack(0)
        XCTAssertTrue(studio.canUndo)
        XCTAssertTrue(ConfirmationCopy.clearTrack.hasSuffix("Undo brings them back."))
    }
}
