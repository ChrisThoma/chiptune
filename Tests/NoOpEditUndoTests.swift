import XCTest
@testable import Chiptune

/// A write that changes nothing is not an edit: it must not add an Undo step
/// or wipe Redo (issue #2).
@MainActor
final class NoOpEditUndoTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "NoOps"))
        studio.undoCoalescingWindow = 0
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

    private func assertRedoSurvives(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(studio.canRedo, message, file: file, line: line)
    }

    func testSameTempoKeepsRedo() {
        studio.setTempo(studio.song.tempo)
        assertRedoSurvives("same BPM")
    }

    func testTempoThatClampsToCurrentKeepsRedo() {
        studio.song.tempo = 300
        studio.setTempo(999)
        assertRedoSurvives("999 clamps to 300")
    }

    func testRealTempoChangeStillCheckpoints() {
        studio.setTempo(150)
        XCTAssertFalse(studio.canRedo)
        XCTAssertTrue(studio.canUndo)
    }

    func testSetSectionSamePatternKeepsRedo() {
        let section = studio.song.arrangement[0]
        studio.setSection(section.id, patternID: section.patternID)
        assertRedoSurvives("same pattern")
    }

    func testSectionRepeatsAtBoundKeepsRedo() {
        let id = studio.song.arrangement[0].id
        studio.setSection(id, repeats: 0)  // clamps to 1, unchanged
        assertRedoSurvives("repeats clamp to current")
    }

    func testClearEmptyPatternKeepsRedo() {
        studio.clearPattern(at: 0)
        assertRedoSurvives("pattern already empty")
    }

    func testClearEmptyTrackKeepsRedo() {
        studio.clearTrack(0, in: 0)
        assertRedoSurvives("track already empty")
    }

    func testClearFilledPatternStillCheckpoints() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.clearPattern(at: 0)
        XCTAssertFalse(studio.canRedo)
        XCTAssertEqual(studio.pattern.rows[0][0], Chip.emptyNote)
    }

    func testSamePresetKeepsRedo() {
        let preset = InstrumentPreset.presets(for: studio.song.tracks[0].kind)[0]
        studio.song.tracks[0].instrument = preset.instrument
        studio.applyPreset(preset, to: 0)
        assertRedoSurvives("preset already applied")
    }
}
