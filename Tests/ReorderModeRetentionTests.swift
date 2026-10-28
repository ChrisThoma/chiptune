import XCTest
@testable import Chiptune

/// Reorder mode lives on the Studio, not in the grid view's own state, so a
/// pose change on the iPhone Duo (which can rebuild the grid) keeps it.
@MainActor
final class ReorderModeRetentionTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Reorder"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testBeginningReorderModeIsKeptByTheStudio() {
        XCTAssertGreaterThan(studio.song.tracks.count, 1)
        XCTAssertFalse(studio.reorderingTracks)
        studio.beginReorderingTracks()
        XCTAssertTrue(studio.reorderingTracks)
    }

    func testMovingATrackKeepsReorderMode() {
        studio.beginReorderingTracks()
        studio.moveTrack(from: 0, to: 1)
        XCTAssertTrue(studio.reorderingTracks)
    }

    func testDoneEndsReorderMode() {
        studio.beginReorderingTracks()
        studio.endReorderingTracks()
        XCTAssertFalse(studio.reorderingTracks)
    }

    func testOneTrackCannotEnterReorderMode() {
        var song = Song(name: "One")
        song.tracks = Array(song.tracks.prefix(1))
        studio.open(song)
        studio.beginReorderingTracks()
        XCTAssertFalse(studio.reorderingTracks)
    }

    func testOpeningAnotherSongEndsReorderMode() {
        studio.beginReorderingTracks()
        studio.open(Song(name: "Other"))
        XCTAssertFalse(studio.reorderingTracks)
    }
}
