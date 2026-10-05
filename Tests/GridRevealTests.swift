import XCTest
@testable import Chiptune

/// When the song or its track count changes under the grid, the selected
/// track's column has to end up on screen: an import, a song switch or an
/// undone delete used to leave the grid at its trailing edge with the
/// selected header scrolled out of sight on the left. The same goes for an
/// Undo, Redo or arrow key that hands the selection to another column.
final class GridRevealTests: XCTestCase {
    private let song = UUID()
    private let other = UUID()

    private func target(_ old: (UUID, Int), _ new: (UUID, Int), selected: Int) -> GridReveal.Target? {
        GridReveal.target(from: .init(songID: old.0, trackCount: old.1, selectedTrack: selected, reveal: .init()),
                          to: .init(songID: new.0, trackCount: new.1, selectedTrack: selected, reveal: .init()))
    }

    /// The same song before and after, `request` saying what asked for a
    /// reveal in between, if anything did.
    private func target(tracks old: Int, selected from: Int, to new: Int, selected to: Int,
                        request: Studio.RevealRequest.Reason?) -> GridReveal.Target? {
        let before = Studio.RevealRequest(generation: 3, reason: .undoRedo)
        let after = request.map { Studio.RevealRequest(generation: 4, reason: $0) } ?? before
        return GridReveal.target(from: .init(songID: song, trackCount: old, selectedTrack: from, reveal: before),
                                 to: .init(songID: song, trackCount: new, selectedTrack: to, reveal: after))
    }

    func testAddedTrackAtTheEndShowsTheTrailingEdge() {
        XCTAssertEqual(target((song, 4), (song, 5), selected: 4), .trailingEdge)
    }

    func testUndoneDeleteShowsTheRestoredSelectedTrack() {
        XCTAssertEqual(target((song, 7), (song, 8), selected: 0), .track(0))
    }

    func testDuplicateShowsTheCopyRatherThanTheEnd() {
        XCTAssertEqual(target((song, 6), (song, 7), selected: 1), .track(1))
    }

    func testImportedSongShowsItsSelectedTrack() {
        XCTAssertEqual(target((song, 4), (other, 8), selected: 0), .track(0))
    }

    func testSongSwitchWithTheSameTrackCountStillShowsTheSelectedTrack() {
        XCTAssertEqual(target((song, 8), (other, 8), selected: 2), .track(2))
    }

    func testSongSwitchOntoItsLastTrackShowsTheTrailingEdge() {
        XCTAssertEqual(target((song, 4), (other, 8), selected: 7), .trailingEdge)
    }

    func testDeleteLeavesTheScrollAlone() {
        XCTAssertNil(target((song, 8), (song, 7), selected: 2))
    }

    func testNothingChangedLeavesTheScrollAlone() {
        XCTAssertNil(target((song, 8), (song, 8), selected: 0))
    }

    // MARK: Undo and Redo

    /// The SE case: track 0 edited, the grid scrolled right, track 7 edited,
    /// then Undo. The selection goes back to track 0 with no change in count.
    func testUndoThatMovesTheSelectionShowsTheRestoredTrack() {
        XCTAssertEqual(target(tracks: 8, selected: 7, to: 8, selected: 0, request: .undoRedo), .track(0))
    }

    func testRedoThatMovesTheSelectionOntoTheLastTrackShowsTheTrailingEdge() {
        XCTAssertEqual(target(tracks: 8, selected: 0, to: 8, selected: 7, request: .undoRedo), .trailingEdge)
    }

    /// Undoing an Add track drops the column and hands the selection back to
    /// the track that had it, which may be far to the left by then.
    func testUndoneAddShowsTheTrackSelectedBeforeIt() {
        XCTAssertEqual(target(tracks: 8, selected: 7, to: 7, selected: 2, request: .undoRedo), .track(2))
    }

    /// Undoing an edit on the column already selected restores nothing new to
    /// look at; the user may have scrolled away on purpose.
    func testUndoThatKeepsTheSelectionLeavesTheScrollAlone() {
        XCTAssertNil(target(tracks: 8, selected: 3, to: 8, selected: 3, request: .undoRedo))
    }

    /// Taps, reorder mode and playback follow keep their own scrolling: a
    /// selection change with nothing asking for a reveal is theirs.
    func testSelectionChangeWithoutARequestLeavesTheScrollAlone() {
        XCTAssertNil(target(tracks: 8, selected: 7, to: 8, selected: 0, request: nil))
    }

    // MARK: Arrow keys

    /// Left and Right move the cursor one column; the grid follows it the way
    /// a text view follows its caret, only as far as it has to.
    func testArrowMoveShowsTheNewColumnJustFarEnough() {
        XCTAssertEqual(target(tracks: 8, selected: 2, to: 8, selected: 3, request: .cursor), .nearest(3))
        XCTAssertEqual(target(tracks: 8, selected: 3, to: 8, selected: 2, request: .cursor), .nearest(2))
    }

    /// Not the trailing edge: that would slide an already visible last column
    /// over by the width of the "+" beside it.
    func testArrowMoveOntoTheLastTrackStillScrollsJustFarEnough() {
        XCTAssertEqual(target(tracks: 8, selected: 6, to: 8, selected: 7, request: .cursor), .nearest(7))
    }

    /// An arrow held against the end of the row moves nothing, but a cursor
    /// the user had scrolled out of sight still comes back, the way a caret
    /// does. Already on screen, `.nearest` leaves the scroll where it is.
    func testArrowPressAtTheEndStillBringsTheCursorColumnBack() {
        XCTAssertEqual(target(tracks: 8, selected: 7, to: 8, selected: 7, request: .cursor), .nearest(7))
    }
}
