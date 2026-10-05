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

    // Once the grid scrolls, the label's opaque backing has to hide
    // everything the pinned strip covers: the row's leading inset before the
    // label and the gap after it, not just the label's own gutter. Otherwise
    // a sliver of the scrolled-under column shows at the screen's edge.
    func testScrolledBackingReachesBackOverTheRowInset() {
        let backing = GridPinning.backing(gutterWidth: 28, scrollX: 40)
        XCTAssertEqual(backing.leading, -GridPinning.rowInset)
    }

    func testScrolledBackingSpansTheWholePinnedStrip() {
        for gutter: CGFloat in [28, 38] {
            let backing = GridPinning.backing(gutterWidth: gutter, scrollX: 1)
            // The same width the arrow-key reveal keeps clear of the strip.
            XCTAssertEqual(backing.width, GridPinning.stripWidth(gutterWidth: gutter))
            // Ends where the first column starts, in the label's coordinates.
            XCTAssertEqual(backing.leading + backing.width, gutter + GridPinning.columnGap)
        }
    }

    // At rest nothing is underneath, and the first column's edge stroke and
    // cursor ring spill into the gap, so the backing stays the gutter alone.
    func testBackingAtRestIsJustTheGutter() {
        for scrollX: CGFloat in [0, -30] {
            let backing = GridPinning.backing(gutterWidth: 28, scrollX: scrollX)
            XCTAssertEqual(backing.leading, 0)
            XCTAssertEqual(backing.width, 28)
        }
    }

    func testStripIsInsetGutterAndGap() {
        XCTAssertEqual(GridPinning.stripWidth(gutterWidth: 28), 6 + 28 + 2)
    }

    // An arrow key that reveals a column from the left lands it beside the
    // strip. The cursor ring is centred on the cell's edge, so its outer half
    // lies outside the column; the reveal leaves room for it rather than
    // tucking it under the now-opaque backing.
    func testRevealClearsTheBackingByTheRingsOuterHalf() {
        for gutter: CGFloat in [28, 38] {
            let backing = GridPinning.backing(gutterWidth: gutter, scrollX: 1)
            let backingEnd = GridPinning.rowInset + backing.leading + backing.width
            XCTAssertEqual(GridPinning.revealClearance(gutterWidth: gutter) - backingEnd,
                           GridPinning.cursorRingWidth / 2)
        }
    }
}
