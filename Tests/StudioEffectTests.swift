import XCTest
@testable import Chiptune

/// Editing per-note effects through `Studio`: one undo step each, cleared with
/// the note, carried with the track, and mirrored into the audio core the same
/// way notes are.
@MainActor
final class StudioEffectTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Blank"))
        studio.undoCoalescingWindow = 0
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    private func modelEffect(pattern: Int = 0, track: Int, step: Int) -> NoteEffect {
        studio.song.patterns[safe: pattern]?.effect(track: track, step: step) ?? .none
    }

    private func coreEffect(pattern: Int = 0, track: Int, step: Int) -> NoteEffect {
        studio.engine.core.effect(pattern: pattern, track: track, step: step)
    }

    /// Every pattern's effects have one row per track and one cell per step,
    /// and the core agrees with the model on every cell.
    private func assertEffectsAligned(_ message: String = "",
                                      file: StaticString = #filePath, line: UInt = #line) {
        for (p, pattern) in studio.song.patterns.enumerated() {
            XCTAssertEqual(pattern.effects.count, pattern.rows.count,
                           "pattern \(p) effects rows \(message)", file: file, line: line)
            for track in pattern.rows.indices {
                for step in 0..<Chip.maxSteps
                where pattern.effect(track: track, step: step) != coreEffect(pattern: p, track: track, step: step) {
                    XCTFail("core disagrees at \(p)/\(track)/\(step) \(message)", file: file, line: line)
                    return
                }
            }
        }
    }

    // MARK: Setting

    func testSettingAnEffectIsOneUndoStep() {
        studio.setNote(track: 0, step: 4, note: 60)
        let undoBefore = studio.canUndo

        studio.setEffect(track: 0, step: 4, effect: .vibrato)

        XCTAssertEqual(modelEffect(track: 0, step: 4), .vibrato)
        XCTAssertEqual(coreEffect(track: 0, step: 4), .vibrato, "the core must hear the edit")
        XCTAssertTrue(studio.canUndo)

        studio.undo()
        XCTAssertEqual(modelEffect(track: 0, step: 4), .none)
        XCTAssertEqual(coreEffect(track: 0, step: 4), .none)
        XCTAssertEqual(studio.song.patterns[0].rows[0][4], 60, "undo takes back the effect, not the note")
        XCTAssertEqual(studio.canUndo, undoBefore)

        studio.redo()
        XCTAssertEqual(modelEffect(track: 0, step: 4), .vibrato)
        XCTAssertEqual(coreEffect(track: 0, step: 4), .vibrato)
    }

    func testTwoEffectEditsAreTwoUndoSteps() {
        studio.setNote(track: 0, step: 4, note: 60)
        studio.undoCoalescingWindow = 10
        studio.setEffect(track: 0, step: 4, effect: .vibrato)
        studio.setEffect(track: 0, step: 4, effect: .slideUp)
        studio.undo()
        XCTAssertEqual(modelEffect(track: 0, step: 4), .vibrato,
                       "picking from the menu twice is two decisions")
    }

    func testSettingTheSameEffectAgainIsNotAnEdit() {
        studio.setNote(track: 0, step: 4, note: 60)
        studio.setEffect(track: 0, step: 4, effect: .glide)
        studio.undo()
        studio.redo()
        XCTAssertTrue(studio.canUndo)
        studio.setEffect(track: 0, step: 4, effect: .glide)
        studio.undo()
        XCTAssertEqual(modelEffect(track: 0, step: 4), .none,
                       "a no-op set must not have pushed its own undo step")
    }

    func testAnEffectOnARestOrAnOffIsRefused() {
        studio.setNote(track: 0, step: 2, note: Chip.noteOff)
        studio.setEffect(track: 0, step: 1, effect: .vibrato)
        studio.setEffect(track: 0, step: 2, effect: .vibrato)
        XCTAssertEqual(modelEffect(track: 0, step: 1), .none)
        XCTAssertEqual(modelEffect(track: 0, step: 2), .none)
        XCTAssertFalse(studio.canUndo, "a refused set is not an undo step")
    }

    func testOutOfRangeEffectEditsAreDropped() {
        studio.setEffect(track: 99, step: 0, effect: .vibrato)
        studio.setEffect(track: 0, step: 999, effect: .vibrato)
        studio.setEffect(track: -1, step: -1, effect: .vibrato)
        XCTAssertFalse(studio.canUndo)
    }

    // MARK: Cell edits

    func testClearingTheNoteClearsItsEffect() {
        studio.selectedNote = 60
        studio.toggleCell(track: 0, step: 3)
        studio.setEffect(track: 0, step: 3, effect: .slideDown)
        studio.toggleCell(track: 0, step: 3)
        XCTAssertEqual(studio.song.patterns[0].rows[0][3], Chip.emptyNote)
        XCTAssertEqual(modelEffect(track: 0, step: 3), .none)
        XCTAssertEqual(coreEffect(track: 0, step: 3), .none)
    }

    func testClearingAtTheCursorClearsTheEffect() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .bendIn)
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.clearAtCursor()
        XCTAssertEqual(modelEffect(track: 0, step: 0), .none)
        XCTAssertEqual(coreEffect(track: 0, step: 0), .none)
    }

    func testTypingANewPitchOverANoteKeepsItsEffect() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .vibrato)
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.typeNote(64)
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], 64)
        XCTAssertEqual(modelEffect(track: 0, step: 0), .vibrato)

        studio.selectedNote = 67
        studio.toggleCell(track: 0, step: 0)
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], 67)
        XCTAssertEqual(modelEffect(track: 0, step: 0), .vibrato, "a tap that overwrites keeps it too")
        XCTAssertEqual(coreEffect(track: 0, step: 0), .vibrato)
    }

    func testOffOverANoteClearsItsEffect() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .glide)
        studio.selectedNote = Chip.noteOff
        studio.toggleCell(track: 0, step: 0)
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], Chip.noteOff)
        XCTAssertEqual(modelEffect(track: 0, step: 0), .none)
        XCTAssertEqual(coreEffect(track: 0, step: 0), .none)
    }

    func testClearTrackClearsItsEffects() {
        studio.setNote(track: 1, step: 0, note: 60)
        studio.setEffect(track: 1, step: 0, effect: .vibrato)
        studio.setNote(track: 2, step: 0, note: 60)
        studio.setEffect(track: 2, step: 0, effect: .vibrato)
        studio.clearTrack(1)
        XCTAssertEqual(modelEffect(track: 1, step: 0), .none)
        XCTAssertEqual(coreEffect(track: 1, step: 0), .none)
        XCTAssertEqual(modelEffect(track: 2, step: 0), .vibrato, "only the cleared track")
        studio.undo()
        XCTAssertEqual(modelEffect(track: 1, step: 0), .vibrato)
        assertEffectsAligned("after undoing clearTrack")
    }

    func testClearPatternClearsItsEffects() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .slideUp)
        studio.setNote(track: 3, step: 5, note: 60)
        studio.setEffect(track: 3, step: 5, effect: .slideDown)
        studio.clearPattern()
        XCTAssertEqual(modelEffect(track: 0, step: 0), .none)
        XCTAssertEqual(modelEffect(track: 3, step: 5), .none)
        assertEffectsAligned("after clearPattern")
    }

    // MARK: Tracks and patterns

    func testAddTrackGivesEveryPatternAnEffectsRow() {
        studio.addPattern()
        studio.addTrack(kind: .pulse2)
        assertEffectsAligned("after addTrack")
    }

    func testDuplicateTrackCopiesItsEffects() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 1, step: 2, note: 60)
        studio.setEffect(track: 1, step: 2, effect: .vibrato)
        studio.setNote(track: 2, step: 2, note: 60)
        studio.setEffect(track: 2, step: 2, effect: .bendIn)
        studio.selectPattern(1)
        studio.setNote(track: 1, step: 5, note: 67)
        studio.setEffect(track: 1, step: 5, effect: .glide)

        studio.duplicateTrack(at: 1)

        XCTAssertEqual(modelEffect(pattern: 0, track: 2, step: 2), .vibrato)
        XCTAssertEqual(modelEffect(pattern: 1, track: 2, step: 5), .glide)
        XCTAssertEqual(modelEffect(pattern: 0, track: 3, step: 2), .bendIn,
                       "the track after the copy keeps its own effects")
        assertEffectsAligned("after duplicateTrack")
    }

    func testRemoveTrackKeepsEffectsWithTheirNotes() {
        studio.setNote(track: 2, step: 1, note: 48)
        studio.setEffect(track: 2, step: 1, effect: .slideDown)
        studio.setNote(track: 1, step: 1, note: 48)
        studio.setEffect(track: 1, step: 1, effect: .vibrato)

        studio.removeTrack(at: 1)

        XCTAssertEqual(studio.song.patterns[0].rows[1][1], 48)
        XCTAssertEqual(modelEffect(track: 1, step: 1), .slideDown,
                       "what was track 2 is now track 1, effect and all")
        assertEffectsAligned("after removeTrack")
    }

    func testMoveTrackKeepsEffectsWithTheirNotes() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 0, step: 3, note: 60)
        studio.setEffect(track: 0, step: 3, effect: .slideUp)
        studio.selectPattern(1)
        studio.setNote(track: 0, step: 7, note: 67)
        studio.setEffect(track: 0, step: 7, effect: .vibrato)

        studio.moveTrack(from: 0, to: 2)

        XCTAssertEqual(modelEffect(pattern: 0, track: 2, step: 3), .slideUp)
        XCTAssertEqual(modelEffect(pattern: 1, track: 2, step: 7), .vibrato)
        XCTAssertEqual(modelEffect(pattern: 0, track: 0, step: 3), .none)
        assertEffectsAligned("after moveTrack")

        studio.undo()
        XCTAssertEqual(modelEffect(pattern: 0, track: 0, step: 3), .slideUp)
        assertEffectsAligned("after undoing moveTrack")
    }

    func testDuplicatePatternCopiesEffects() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .bendIn)
        studio.duplicatePattern(at: 0)
        XCTAssertEqual(modelEffect(pattern: 1, track: 0, step: 0), .bendIn)
        assertEffectsAligned("after duplicatePattern")
    }

    func testSetKindKeepsEffects() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .slideDown)
        studio.setKind(.noise, for: 0)
        XCTAssertEqual(modelEffect(track: 0, step: 0), .slideDown)
        assertEffectsAligned("after setKind")
    }

    // MARK: Loading

    func testOpeningASongPushesItsEffectsToTheCore() {
        var song = Song(name: "Fx")
        song.patterns[0].rows[1][6] = 55
        song.patterns[0].setEffect(.vibrato, track: 1, step: 6)
        studio.open(song)
        XCTAssertEqual(coreEffect(track: 1, step: 6), .vibrato)
        assertEffectsAligned("after open")
    }

    func testOpeningAPlainSongClearsTheCoresEffects() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .vibrato)
        studio.open(Song(name: "Plain"))
        XCTAssertEqual(coreEffect(track: 0, step: 0), .none)
    }

    // MARK: Preview

    func testPreviewingACellPlaysItWithItsEffect() throws {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.setEffect(track: 0, step: 0, effect: .bendIn)
        XCTAssertTrue(studio.previewCell(track: 0, step: 0))
        try XCTSkipIf(studio.audioError != nil, "no audio engine on this machine")
        XCTAssertEqual(studio.engine.core.soundingEffect(track: 0), .bendIn)
    }
}
