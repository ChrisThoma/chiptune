import XCTest
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
}
