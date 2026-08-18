import XCTest
@testable import Chiptune

/// What the grid does while the sequencer runs underneath it.
///
/// The behaviour under test used to live inside a 60 Hz `Timer` closure, which
/// made it unreachable: the timer needs a spinning run loop, and arming it
/// needs `play()`, which needs a real `AVAudioEngine` that may or may not start
/// on the machine running the suite. `applyPlayhead(step:pattern:)` is that
/// closure's body lifted out so it can be called directly, one tick at a time.
@MainActor
final class StudioPlayheadTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Blank"))
        studio.addPattern()          // three patterns, so there's somewhere to
        studio.addPattern()          // advance to and somewhere else after that
        studio.selectPattern(0)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    /// Playing is set by hand rather than through `play()`, which would need an
    /// audio engine to start. `followsArrangement` is true from init, so
    /// nothing here needs `play()` to arm it either.
    private func pretendPlayingSong() {
        studio.songMode = true
        studio.isPlaying = true
    }

    // MARK: Following

    func testSongModePlaybackDragsTheGridToTheSoundingPattern() {
        pretendPlayingSong()

        studio.applyPlayhead(step: 3, pattern: 1)

        XCTAssertEqual(studio.playhead, 3)
        XCTAssertEqual(studio.playingPattern, 1)
        XCTAssertEqual(studio.selectedPattern, 1, "the grid should follow the arrangement")
        XCTAssertTrue(studio.followsArrangement)
    }

    /// In PATT mode the sequencer loops one pattern, so there is no arrangement
    /// to follow and the selection must never move on its own.
    func testPatternModeNeverMovesTheSelection() {
        studio.songMode = false
        studio.isPlaying = true

        studio.applyPlayhead(step: 5, pattern: 1)

        XCTAssertEqual(studio.playingPattern, 1)
        XCTAssertEqual(studio.selectedPattern, 0)
    }

    /// The core's pattern index and the model's pattern list can disagree for a
    /// tick after a delete — the audio thread has its own copy. Following a
    /// stale index would index out of bounds.
    func testAPatternIndexPastTheEndOfTheSongIsIgnored() {
        pretendPlayingSong()

        studio.applyPlayhead(step: 0, pattern: 9)

        XCTAssertEqual(studio.playingPattern, 9, "the readout still reports what the core said")
        XCTAssertEqual(studio.selectedPattern, 0, "but the grid must not follow it")
    }

    /// Repeated ticks within one pattern are the common case — 63 of every 64.
    func testStayingOnThePatternOnlyMovesThePlayhead() {
        pretendPlayingSong()
        studio.applyPlayhead(step: 0, pattern: 1)
        studio.selectPattern(0)          // pin, so a second follow would be visible

        studio.applyPlayhead(step: 7, pattern: 1)

        XCTAssertEqual(studio.playhead, 7)
        XCTAssertEqual(studio.selectedPattern, 0)
    }

    // MARK: Pinning

    /// Choosing some pattern other than the sounding one mid-playback keeps
    /// the grid there for the rest of the play-through.
    func testSelectingAPatternWhilePlayingStopsTheFollow() {
        pretendPlayingSong()
        studio.applyPlayhead(step: 0, pattern: 1)

        studio.selectPattern(0)
        studio.applyPlayhead(step: 0, pattern: 2)

        XCTAssertFalse(studio.followsArrangement)
        XCTAssertEqual(studio.playingPattern, 2, "the sequencer carries on")
        XCTAssertEqual(studio.selectedPattern, 0, "the pattern being edited must stay put")
    }

    func testSelectingAPatternWhileStoppedLeavesTheFollowArmed() {
        studio.songMode = true

        studio.selectPattern(1)

        XCTAssertTrue(studio.followsArrangement, "nothing is playing to be dragged away from")
    }

    /// The reported bug. Writing notes into a pattern while the song plays used
    /// to leave the follow armed, so the next arrangement boundary took the
    /// grid away mid-edit and there was no way to keep working over playback.
    func testEditingTheSoundingPatternPinsTheGrid() {
        pretendPlayingSong()

        studio.toggleCell(track: 0, step: 4)
        studio.applyPlayhead(step: 0, pattern: 1)

        XCTAssertFalse(studio.followsArrangement)
        XCTAssertEqual(studio.playingPattern, 1, "the sequencer carries on")
        XCTAssertEqual(studio.selectedPattern, 0, "but the pattern being edited stays on screen")
    }

    /// Every way to change what's in the pattern, not just the one the bug was
    /// reported against. `setNote` funnels most of them; the last two write
    /// around it and need their own pin.
    func testEveryPatternEditPinsTheGrid() {
        let edits: [(String, () -> Void)] = [
            ("toggleCell", { self.studio.toggleCell(track: 0, step: 2) }),
            ("typeNote", { self.studio.typeNote(64) }),
            ("clearAtCursor", { self.studio.clearAtCursor() }),
            ("clearTrack", { self.studio.clearTrack(0) }),
            ("setPatternLength", { self.studio.setPatternLength(32) }),
            ("clearPattern", { self.studio.clearPattern() }),
        ]

        for (name, edit) in edits {
            setUp()
            pretendPlayingSong()

            edit()
            studio.applyPlayhead(step: 0, pattern: 1)

            XCTAssertFalse(studio.followsArrangement, "\(name) should pin the grid")
            XCTAssertEqual(studio.selectedPattern, 0, "\(name) let the arrangement take the grid")
        }
    }

    /// Clearing B from its chip menu deliberately doesn't move the editor off
    /// A, so it has no business pinning A either.
    func testClearingSomeOtherPatternDoesNotPin() {
        pretendPlayingSong()

        studio.clearPattern(at: 1)
        studio.applyPlayhead(step: 0, pattern: 1)

        XCTAssertTrue(studio.followsArrangement)
        XCTAssertEqual(studio.selectedPattern, 1, "the grid should still be following")
    }

    /// The scope boundary, asserted on purpose. An instrument belongs to the
    /// track and sounds in every pattern, so being carried to the next one
    /// doesn't interrupt tweaking a decay — and neither does the tempo or the
    /// arrangement, where refusing to follow is the opposite of what you want.
    func testEditsOutsideThePatternDoNotPin() {
        pretendPlayingSong()

        studio.setTempo(140)
        studio.song.tracks[0].instrument.decay = 0.5
        studio.pushInstrument(0)
        studio.addSection(patternID: studio.song.patterns[1].id)
        studio.applyPlayhead(step: 0, pattern: 1)

        XCTAssertTrue(studio.followsArrangement)
        XCTAssertEqual(studio.selectedPattern, 1, "the grid should still be following")
    }

    // MARK: Re-arming

    /// Getting the follow back without stopping. Jumping to the pattern that's
    /// currently sounding is the gesture for "I'm back with the song", so it
    /// re-arms rather than pinning the way any other pattern does.
    func testReselectingTheSoundingPatternReArmsTheFollow() {
        pretendPlayingSong()
        studio.toggleCell(track: 0, step: 4)
        studio.applyPlayhead(step: 0, pattern: 1)
        XCTAssertFalse(studio.followsArrangement, "precondition: pinned by the edit")

        studio.selectPattern(1)          // the one that's playing

        XCTAssertTrue(studio.followsArrangement)
        XCTAssertEqual(studio.selectedPattern, 1)

        studio.applyPlayhead(step: 0, pattern: 0)
        XCTAssertEqual(studio.selectedPattern, 0, "and the grid follows again")
    }

    /// A brand-new pattern is never the one already sounding, so adding one
    /// mid-playback pins the grid to it rather than bouncing straight off.
    func testAddingAPatternWhilePlayingPinsTheGridToIt() {
        pretendPlayingSong()

        let added = studio.addPattern()

        XCTAssertEqual(studio.selectedPattern, added)
        XCTAssertFalse(studio.followsArrangement)
    }
}
