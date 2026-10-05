import XCTest
@testable import Chiptune

/// When the song or its track count changes under the grid, the selected
/// track's column has to end up on screen: an import, a song switch or an
/// undone delete used to leave the grid at its trailing edge with the
/// selected header scrolled out of sight on the left.
final class GridRevealTests: XCTestCase {
    private let song = UUID()
    private let other = UUID()

    private func target(_ old: (UUID, Int), _ new: (UUID, Int), selected: Int) -> GridReveal.Target? {
        GridReveal.target(from: .init(songID: old.0, trackCount: old.1, selectedTrack: selected, undoRedoGeneration: 0),
                          to: .init(songID: new.0, trackCount: new.1, selectedTrack: selected, undoRedoGeneration: 0))
    }

    /// The same song before and after, `undone` saying whether an Undo or
    /// Redo ran in between.
    private func target(tracks old: Int, selected from: Int,
                        to new: Int, selected to: Int, undone: Bool) -> GridReveal.Target? {
        GridReveal.target(from: .init(songID: song, trackCount: old, selectedTrack: from, undoRedoGeneration: 3),
                          to: .init(songID: song, trackCount: new, selectedTrack: to,
                                    undoRedoGeneration: undone ? 4 : 3))
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
        XCTAssertEqual(target(tracks: 8, selected: 7, to: 8, selected: 0, undone: true), .track(0))
    }

    func testRedoThatMovesTheSelectionOntoTheLastTrackShowsTheTrailingEdge() {
        XCTAssertEqual(target(tracks: 8, selected: 0, to: 8, selected: 7, undone: true), .trailingEdge)
    }

    /// Undoing an Add track drops the column and hands the selection back to
    /// the track that had it, which may be far to the left by then.
    func testUndoneAddShowsTheTrackSelectedBeforeIt() {
        XCTAssertEqual(target(tracks: 8, selected: 7, to: 7, selected: 2, undone: true), .track(2))
    }

    /// Undoing an edit on the column already selected restores nothing new to
    /// look at; the user may have scrolled away on purpose.
    func testUndoThatKeepsTheSelectionLeavesTheScrollAlone() {
        XCTAssertNil(target(tracks: 8, selected: 3, to: 8, selected: 3, undone: true))
    }

    /// Arrow keys, taps, reorder mode and playback follow keep their own
    /// scrolling: a selection change with no Undo or Redo behind it is theirs.
    func testSelectionChangeWithoutUndoLeavesTheScrollAlone() {
        XCTAssertNil(target(tracks: 8, selected: 7, to: 8, selected: 0, undone: false))
    }
}
