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
        GridReveal.target(from: .init(songID: old.0, trackCount: old.1),
                          to: .init(songID: new.0, trackCount: new.1),
                          selectedTrack: selected)
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
}
