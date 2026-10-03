import XCTest
@testable import Chiptune

/// The step-number column stays at the leading edge while the grid scrolls
/// sideways, by shifting each label by how far the grid has scrolled.
final class GridPinningTests: XCTestCase {
    func testLabelFollowsHorizontalScroll() {
        XCTAssertEqual(GridPinning.labelOffset(scrollX: 120), 120)
    }

    func testLabelStaysPutAtRest() {
        XCTAssertEqual(GridPinning.labelOffset(scrollX: 0), 0)
    }

    func testLabelIgnoresLeadingRubberBand() {
        XCTAssertEqual(GridPinning.labelOffset(scrollX: -30), 0)
    }
}
