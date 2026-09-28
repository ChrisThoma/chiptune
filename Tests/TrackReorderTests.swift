import XCTest
@testable import Chiptune

/// The geometry behind dragging a track header sideways in reorder mode: which
/// column a drag has reached, and where every other column has to slide to
/// make room for it while the finger is still down.
final class TrackReorderTests: XCTestCase {

    /// 80 pt columns with the grid's 2 pt spacing between them.
    private let step: CGFloat = 82

    // MARK: Destination

    func testAShortDragStaysPut() {
        XCTAssertEqual(TrackReorder.destination(from: 1, translation: 30, columnStep: step, count: 4), 1)
        XCTAssertEqual(TrackReorder.destination(from: 1, translation: -30, columnStep: step, count: 4), 1)
    }

    /// Past halfway into the neighbor is where it swaps, the same point at
    /// which the neighbor's slide would otherwise have it overlapping.
    func testCrossingHalfAColumnReachesTheNeighbor() {
        XCTAssertEqual(TrackReorder.destination(from: 1, translation: 42, columnStep: step, count: 4), 2)
        XCTAssertEqual(TrackReorder.destination(from: 1, translation: -42, columnStep: step, count: 4), 0)
    }

    func testALongDragCrossesSeveralColumns() {
        XCTAssertEqual(TrackReorder.destination(from: 0, translation: 250, columnStep: step, count: 4), 3)
    }

    func testDraggingPastEitherEndStopsAtTheEnd() {
        XCTAssertEqual(TrackReorder.destination(from: 2, translation: 2000, columnStep: step, count: 4), 3)
        XCTAssertEqual(TrackReorder.destination(from: 2, translation: -2000, columnStep: step, count: 4), 0)
    }

    /// A zero-width layout pass must not divide into a NaN column.
    func testADegenerateColumnWidthStaysPut() {
        XCTAssertEqual(TrackReorder.destination(from: 2, translation: 50, columnStep: 0, count: 4), 2)
    }

    // MARK: Making room

    func testTheColumnsBetweenSlideTowardTheGap() {
        // Dragging track 0 onto column 2: 1 and 2 each shift one column left.
        XCTAssertEqual(TrackReorder.offset(for: 1, dragging: 0, to: 2, columnStep: step), -step)
        XCTAssertEqual(TrackReorder.offset(for: 2, dragging: 0, to: 2, columnStep: step), -step)
        XCTAssertEqual(TrackReorder.offset(for: 3, dragging: 0, to: 2, columnStep: step), 0)
    }

    func testDraggingLeftPushesTheColumnsBetweenRight() {
        XCTAssertEqual(TrackReorder.offset(for: 0, dragging: 3, to: 1, columnStep: step), 0)
        XCTAssertEqual(TrackReorder.offset(for: 1, dragging: 3, to: 1, columnStep: step), step)
        XCTAssertEqual(TrackReorder.offset(for: 2, dragging: 3, to: 1, columnStep: step), step)
    }

    /// The dragged column follows the finger itself; this only moves the rest.
    func testTheDraggedColumnGetsNoSlide() {
        XCTAssertEqual(TrackReorder.offset(for: 0, dragging: 0, to: 2, columnStep: step), 0)
    }

    // MARK: Who can enter

    /// One track has nowhere to go, so a long press on it shouldn't open a
    /// mode that can't do anything.
    func testASingleTrackCannotBeReordered() {
        var song = Song(name: "Solo")
        song.tracks = [Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow]
        XCTAssertFalse(song.canReorderTracks)

        song.tracks.append(Track(kind: .noise))
        XCTAssertTrue(song.canReorderTracks)
    }
}
