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
}
