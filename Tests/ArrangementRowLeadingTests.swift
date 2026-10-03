import XCTest
@testable import Chiptune

/// The playing marker used to be an extra element in the arrangement row,
/// so in edit mode (delete circle + drag handle) the playing row ran out of
/// width and its pattern name truncated to "WW…". The marker now takes the
/// section number's slot, the way a music player swaps a track number for a
/// speaker, so the playing row has exactly the same width budget as the rest.
final class ArrangementRowLeadingTests: XCTestCase {

    func testIdleRowShowsItsOneBasedSectionNumber() {
        XCTAssertEqual(ArrangementRowLeading.content(position: 1, playing: false), .number("2"))
    }

    func testPlayingRowShowsTheMarkerInTheNumberSlot() {
        XCTAssertEqual(ArrangementRowLeading.content(position: 1, playing: true), .playingMarker)
    }
}
