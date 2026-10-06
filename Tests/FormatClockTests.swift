import XCTest
@testable import Chiptune

/// The export sheet's length and the arrangement summary. `Int(seconds)`
/// truncated, so the 1.8 s starter song read "0:01" and a 59.9 s song "0:59".
final class FormatClockTests: XCTestCase {
    func testShortDurationsShowTenths() {
        XCTAssertEqual(Format.clock(1.8), "0:01.8")
        XCTAssertEqual(Format.clock(0.5), "0:00.5")
        XCTAssertEqual(Format.clock(9.94), "0:09.9")
    }

    func testTenthsRoundRatherThanTruncate() {
        XCTAssertEqual(Format.clock(1.86), "0:01.9")
        XCTAssertEqual(Format.clock(3.6), "0:03.6")
    }

    func testTenSecondsAndUpRoundToWholeSeconds() {
        XCTAssertEqual(Format.clock(10), "0:10")
        XCTAssertEqual(Format.clock(12.6), "0:13")
        XCTAssertEqual(Format.clock(67.2), "1:07")
    }

    /// Just under ten seconds rounds up to ten, which is shown whole rather
    /// than as "0:10.0".
    func testRoundingUpToTenDropsTheTenths() {
        XCTAssertEqual(Format.clock(9.96), "0:10")
    }

    func testRoundingCarriesIntoTheMinute() {
        XCTAssertEqual(Format.clock(59.6), "1:00")
    }

    func testZeroIsWhole() {
        XCTAssertEqual(Format.clock(0), "0:00")
    }
}
