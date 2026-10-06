import XCTest
import SwiftUI
@testable import Chiptune

/// Playback scrolls the grid to the playhead only when the pattern's rows
/// don't all fit. The old rule was "longer than 16 steps", which left the
/// default 16-step pattern playing off screen on an iPhone that shows about
/// eight rows, while a pattern that fits (iPad) should stay put.
final class GridFollowTests: XCTestCase {
    func testSixteenStepsOnAPhoneFollow() {
        // About eight 40-pt rows of grid on an iPhone 17.
        XCTAssertTrue(GridFollow.follows(steps: 16, rowHeight: 40, viewportHeight: 340))
    }

    func testSixteenStepsThatFitStayPut() {
        // 16 × 52 + 15 × 2 + 8 = 870 pt of rows in a 900-pt iPad grid.
        XCTAssertFalse(GridFollow.follows(steps: 16, rowHeight: 52, viewportHeight: 900))
    }

    func testContentExactlyFillingTheViewportStaysPut() {
        let height = GridFollow.contentHeight(steps: 16, rowHeight: 52)
        XCTAssertEqual(height, 870)
        XCTAssertFalse(GridFollow.follows(steps: 16, rowHeight: 52, viewportHeight: height))
    }

    func testOneRowTooManyFollows() {
        XCTAssertTrue(GridFollow.follows(steps: 17, rowHeight: 52, viewportHeight: 870))
    }

    func testShortPatternOnAPhoneStaysPut() {
        XCTAssertFalse(GridFollow.follows(steps: 4, rowHeight: 40, viewportHeight: 340))
    }

    func testLongPatternOnAnIPadFollows() {
        XCTAssertTrue(GridFollow.follows(steps: 64, rowHeight: 52, viewportHeight: 900))
    }

    // MARK: Where it scrolls to

    /// Anchors the playing row, or leaves the grid alone, for a grid scrolled
    /// to `scrollY`. A 16-step pattern in a viewport one row short of it.
    private func anchor(_ step: Int, steps: Int = 16, rowHeight: CGFloat = 52,
                        viewport: CGFloat = 850, scrollY: CGFloat?) -> UnitPoint? {
        GridFollow.anchor(playhead: step, steps: steps, rowHeight: rowHeight,
                          viewportHeight: viewport, scrollY: scrollY)
    }

    /// The 13-inch iPad in portrait shows rows 00–14 with 15 cut off. Re-centring
    /// on every step nudged the grid up and down all bar long; it should hold
    /// still while the playing row is in full view.
    func testARowAlreadyInFullViewLeavesTheGridAlone() {
        for step in 0...14 {
            XCTAssertNil(anchor(step, scrollY: 0), "row \(step) is on screen")
        }
    }

    func testAClippedRowScrollsToTheTopSoTheRowsAfterItShow() {
        XCTAssertEqual(anchor(15, scrollY: 0), .top)
    }

    /// Once scrolled to show row 15, the bar plays through without moving,
    /// and the wrap back to 00 is the second and last move of the bar.
    func testTheWrapToTheTopIsTheOtherMove() {
        let scrolled = GridFollow.contentHeight(steps: 16, rowHeight: 52) - 850
        for step in 1...15 {
            XCTAssertNil(anchor(step, scrollY: scrolled), "row \(step) is on screen")
        }
        XCTAssertEqual(anchor(0, scrollY: scrolled), .top)
    }

    /// The phone shows about eight rows, so the default pattern flips a
    /// page at a time: still followed, just not on every step.
    func testAPhoneFollowsAPageAtATime() {
        for step in 0...7 {
            XCTAssertNil(anchor(step, rowHeight: 40, viewport: 340, scrollY: 0))
        }
        XCTAssertEqual(anchor(8, rowHeight: 40, viewport: 340, scrollY: 0), .top)
    }

    /// Scrolled away by hand, the playhead is brought back on its next step.
    func testAGridScrolledAwayFromThePlayheadIsBroughtBack() {
        XCTAssertEqual(anchor(2, steps: 64, scrollY: 1500), .top)
    }

    func testAGridThatFitsNeverScrolls() {
        XCTAssertNil(anchor(15, viewport: 900, scrollY: 0))
        XCTAssertNil(anchor(15, viewport: 900, scrollY: nil))
    }

    /// iOS 17 can't read the scroll offset, so it keeps the old behaviour of
    /// centring on every step.
    func testWithoutAnOffsetItCentresAsBefore() {
        XCTAssertEqual(anchor(3, scrollY: nil), .center)
    }

    /// A follow scroll that outlasts its step is still moving when the next
    /// step asks for one, and that second scroll is dropped: at 132 BPM the
    /// wrap back to 00 was lost every other bar. So it takes half a step,
    /// up to the 0.15 s it always had at slow tempos.
    func testTheScrollFinishesWithinHalfAStep() {
        XCTAssertEqual(GridFollow.scrollDuration(tempo: 120), 0.0625, accuracy: 0.0001)
        XCTAssertEqual(GridFollow.scrollDuration(tempo: 300), 0.025, accuracy: 0.0001)
        XCTAssertEqual(GridFollow.scrollDuration(tempo: 40), 0.15, accuracy: 0.0001)
    }
}
