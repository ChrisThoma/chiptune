import XCTest
@testable import Chiptune

/// Undo and redo. The snapshot stack is the whole implementation, so these
/// tests are mostly about the two things a snapshot stack gets wrong: what
/// counts as one step, and whether the editing cursor comes back with the song.
@MainActor
final class StudioUndoTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Undo"))
        // Coalescing off by default: almost every test here wants each edit to
        // be its own step, and a wall-clock window would otherwise decide.
        studio.undoCoalescingWindow = 0
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    /// `Song`'s own `==` includes `modified`, which moves on every save.
    // MARK: Basics

    func testNothingToUndoOnAFreshSong() {
        XCTAssertFalse(studio.canUndo)
        XCTAssertFalse(studio.canRedo)
        studio.undo()
        studio.redo()
        XCTAssertEqual(studio.song.name, "Undo", "undoing nothing must do nothing")
    }

    func testUndoRestoresTheSongExactly() {
        let before = studio.song
        studio.toggleCell(track: 0, step: 4)
        XCTAssertTrue(studio.canUndo)
        XCTAssertNotEqual(studio.song.patterns[0].rows[0][4], Chip.emptyNote)

        studio.undo()

        assertSameSong(studio.song, before, "undo did not restore the song")
        XCTAssertFalse(studio.canUndo)
        XCTAssertTrue(studio.canRedo)
    }

    func testRedoReappliesTheEdit() {
        studio.selectedNote = 67
        studio.toggleCell(track: 0, step: 4)
        let after = studio.song

        studio.undo()
        studio.redo()

        assertSameSong(studio.song, after, "redo did not reapply the edit")
        XCTAssertTrue(studio.canUndo)
        XCTAssertFalse(studio.canRedo)
    }

    /// Undoing then editing forks the history — the redo branch is gone.
    func testANewEditClearsTheRedoStack() {
        studio.toggleCell(track: 0, step: 0)
        studio.undo()
        XCTAssertTrue(studio.canRedo)

        studio.toggleCell(track: 1, step: 1)

        XCTAssertFalse(studio.canRedo, "a new edit must not leave a stale redo branch")
    }

    func testUndoWalksBackThroughSeveralEdits() {
        var expected: [Song] = []
        for step in 0..<5 {
            expected.append(studio.song)
            studio.toggleCell(track: 0, step: step)
        }

        for step in (0..<5).reversed() {
            studio.undo()
            assertSameSong(studio.song, expected[step], "undo step \(step)")
        }
        XCTAssertFalse(studio.canUndo)
    }

    // MARK: The core follows

    /// Undo puts the song back; the DSP core has to be put back with it, or
    /// you see the old notes and hear the new ones.
    func testUndoPushesTheRestoredSongIntoTheCore() {
        studio.addPattern()
        studio.addTrack(kind: .noise)
        studio.setTempo(200)

        studio.undo()
        studio.undo()
        studio.undo()

        let core = studio.engine.core
        XCTAssertEqual(Int(core.trackCount), studio.song.tracks.count)
        XCTAssertEqual(Int(core.patternCount), studio.song.patterns.count)
        XCTAssertEqual(Int(core.chainCount), studio.song.chain.count)
        XCTAssertEqual(core.tempo, studio.song.tempo)
    }

    // MARK: Selection

    /// The case the song alone can't recover: `pushAll` clamps the selection
    /// against the *current* song, so restoring a deleted pattern without its
    /// selection leaves you editing the wrong one.
    func testUndoingAPatternDeleteRestoresTheSelection() {
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(2)
        XCTAssertEqual(studio.selectedPattern, 2)

        studio.removePattern(at: 2)
        XCTAssertEqual(studio.selectedPattern, 1, "the selection should have fallen back")

        studio.undo()

        XCTAssertEqual(studio.song.patterns.count, 3)
        XCTAssertEqual(studio.selectedPattern, 2, "undo must put the cursor back too")
    }

    /// Undo assigns `selectedPattern` directly rather than going through
    /// `selectPattern`, so without a pin of its own the next arrangement
    /// boundary takes the grid straight back off the pattern the undo just
    /// restored — which reads as the undo having failed.
    func testUndoingWhilePlayingPinsTheGrid() {
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(0)
        studio.toggleCell(track: 0, step: 3)
        studio.songMode = true
        studio.isPlaying = true
        // Left following on purpose, so the pin under test is undo's own and
        // not one inherited from a manual pattern selection.
        studio.applyPlayhead(step: 0, pattern: 1)
        XCTAssertTrue(studio.followsArrangement, "precondition: still following")

        studio.undo()

        XCTAssertFalse(studio.followsArrangement)
        XCTAssertEqual(studio.selectedPattern, 0, "undo put the cursor here")
        studio.applyPlayhead(step: 0, pattern: 2)
        XCTAssertEqual(studio.selectedPattern, 0, "and the arrangement must not take it away")
    }

    func testUndoingATrackDeleteRestoresTheSelection() {
        studio.selectedTrack = 3
        studio.removeTrack(at: 3)
        XCTAssertEqual(studio.selectedTrack, 2)

        studio.undo()

        XCTAssertEqual(studio.song.tracks.count, 4)
        XCTAssertEqual(studio.selectedTrack, 3)
    }

    /// A track carries its notes in every pattern, so this is the most
    /// destructive single action in the app.
    func testUndoingATrackDeleteRestoresItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 1, step: 2, note: 60)
        studio.selectPattern(1)
        studio.setNote(track: 1, step: 6, note: 72)
        let before = studio.song

        studio.removeTrack(at: 1)
        XCTAssertEqual(studio.song.tracks.count, 3)

        studio.undo()

        assertSameSong(studio.song, before, "a deleted track's notes did not come back")
        XCTAssertEqual(studio.song.patterns[0].rows[1][2], 60)
        XCTAssertEqual(studio.song.patterns[1].rows[1][6], 72)
    }

    func testUndoingAClearedPatternIsASingleStep() {
        for track in 0..<4 { studio.setNote(track: track, step: track, note: 60) }
        let before = studio.song

        studio.clearPattern()
        XCTAssertTrue(studio.song.patterns[0].isEmpty)

        studio.undo()

        assertSameSong(studio.song, before,
                       "clearing a pattern should take one undo, not one per track")
    }

    func testUndoingAClearedTrackIsASingleStep() {
        for step in 0..<8 { studio.setNote(track: 0, step: step, note: 60) }
        let before = studio.song

        studio.clearTrack(0)

        studio.undo()
        assertSameSong(studio.song, before)
    }

    // MARK: Coalescing

    /// Painting a run of cells is one gesture and should be one undo.
    func testEditsInsideTheWindowCoalesceIntoOneStep() {
        studio.undoCoalescingWindow = 60
        let before = studio.song

        studio.selectedNote = 60
        for step in 0..<8 { studio.toggleCell(track: 0, step: step) }

        studio.undo()

        assertSameSong(studio.song, before, "a single paint stroke should be a single undo")
        XCTAssertFalse(studio.canUndo)
    }

    /// A discrete edit is never folded into the stroke before it, however fast
    /// it follows — deleting a pattern must not be undone by accident.
    func testDiscreteEditsDoNotCoalesce() {
        studio.undoCoalescingWindow = 60

        studio.toggleCell(track: 0, step: 0)
        studio.addPattern()
        studio.addTrack(kind: .noise)

        studio.undo()
        XCTAssertEqual(studio.song.tracks.count, 4, "the track add should undo on its own")
        studio.undo()
        XCTAssertEqual(studio.song.patterns.count, 1, "the pattern add should undo on its own")
        studio.undo()
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], Chip.emptyNote)
    }

    /// After an undo, the next edit starts a fresh gesture rather than folding
    /// itself into the one that was just undone.
    func testAnEditAfterUndoDoesNotCoalesceWithTheUndoneStroke() {
        studio.undoCoalescingWindow = 60

        studio.toggleCell(track: 0, step: 0)
        studio.undo()
        studio.toggleCell(track: 1, step: 1)

        XCTAssertTrue(studio.canUndo)
        studio.undo()
        XCTAssertEqual(studio.song.patterns[0].rows[1][1], Chip.emptyNote)
    }

    // MARK: Bounds and lifecycle

    func testTheStackIsCapped() {
        studio.undoLimit = 5

        studio.selectedNote = 60
        for step in 0..<20 { studio.toggleCell(track: 0, step: step) }

        var undos = 0
        while studio.canUndo {
            studio.undo()
            undos += 1
            XCTAssertLessThanOrEqual(undos, 5, "the stack grew past its limit")
        }
        XCTAssertEqual(undos, 5)
    }

    /// Undo must not reach across songs — restoring a snapshot of a song you're
    /// no longer editing would silently replace the one you are.
    func testOpeningASongClearsTheHistory() {
        studio.toggleCell(track: 0, step: 0)
        XCTAssertTrue(studio.canUndo)

        studio.open(Song(name: "Different"))

        XCTAssertFalse(studio.canUndo)
        XCTAssertFalse(studio.canRedo)
    }

    func testNewSongClearsTheHistory() {
        studio.toggleCell(track: 0, step: 0)
        studio.undo()
        XCTAssertTrue(studio.canRedo)

        studio.newSong()

        XCTAssertFalse(studio.canUndo)
        XCTAssertFalse(studio.canRedo)
    }

    /// `pushAll()` reassigns `song`, which is exactly why checkpoints are taken
    /// at the call sites rather than from a `didSet` hook. If they weren't,
    /// pushes would land on the stack as no-op steps and undoing twice would
    /// appear to do nothing.
    func testPushingDoesNotRecordUndoSteps() {
        studio.toggleCell(track: 0, step: 0)
        let depthAfterOneEdit = countUndoSteps()
        XCTAssertEqual(depthAfterOneEdit, 1)

        studio.pushAll()
        studio.pushArrangement()
        studio.pushTransport()

        XCTAssertEqual(countUndoSteps(), 1, "pushing state to the core is not an edit")
    }

    private func countUndoSteps() -> Int {
        // Non-destructive: walk back, then walk forward again.
        var depth = 0
        while studio.canUndo {
            studio.undo()
            depth += 1
        }
        for _ in 0..<depth { studio.redo() }
        return depth
    }
}
