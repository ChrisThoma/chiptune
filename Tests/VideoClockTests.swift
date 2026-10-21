import XCTest
@testable import Chiptune

/// The length a video draws must be the length the Export sheet promised.
final class VideoClockTests: XCTestCase {
    func testTotalMatchesTheSheetForAnAlmostWholeLength() {
        // 7x First Loop: the sheet says 0:15 and the file is 14.977 s.
        XCTAssertEqual(VideoClock.total(14.977), Format.clock(14.977))
        XCTAssertEqual(VideoClock.total(14.977), "0:15")
    }

    func testTotalMatchesTheSheetUnderTenSeconds() {
        XCTAssertEqual(VideoClock.total(1.8), Format.clock(1.8))
        XCTAssertEqual(VideoClock.total(9.94), "0:09.9")
    }

    func testElapsedStaysInWholeSecondsWithoutRunningAhead() {
        XCTAssertEqual(VideoClock.elapsed(14.6, total: 14.977, isFinalFrame: false), "0:14")
        XCTAssertEqual(VideoClock.elapsed(0.9, total: 14.977, isFinalFrame: false), "0:00")
    }

    func testFinalFrameReadsTheTotal() {
        XCTAssertEqual(VideoClock.elapsed(14.96, total: 14.977, isFinalFrame: true), "0:15")
        XCTAssertEqual(VideoClock.elapsed(24.05, total: 24.07, isFinalFrame: true), "0:24")
    }

    /// Under ten seconds the total keeps a tenth, so the running clock does
    /// too: "0:00" against "0:04.1" read as two different clocks.
    func testElapsedKeepsATenthWhenTheTotalDoes() {
        XCTAssertEqual(VideoClock.total(4.1), "0:04.1")
        XCTAssertEqual(VideoClock.elapsed(0, total: 4.1, isFinalFrame: false), "0:00.0")
        XCTAssertEqual(VideoClock.elapsed(2.37, total: 4.1, isFinalFrame: false), "0:02.3")
        XCTAssertEqual(VideoClock.elapsed(4.09, total: 4.1, isFinalFrame: false), "0:04.0")
        XCTAssertEqual(VideoClock.elapsed(0.3, total: 4.1, isFinalFrame: false), "0:00.3")
        XCTAssertEqual(VideoClock.elapsed(4.1, total: 4.1, isFinalFrame: true), "0:04.1")
    }

    /// 9.96 s rounds to "0:10" on the sheet, a whole-second total, so the
    /// running clock stays in whole seconds.
    func testElapsedFollowsATotalThatRoundsUpToTenSeconds() {
        XCTAssertEqual(VideoClock.total(9.96), "0:10")
        XCTAssertEqual(VideoClock.elapsed(9.5, total: 9.96, isFinalFrame: false), "0:09")
    }
}
