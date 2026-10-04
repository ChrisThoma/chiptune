import XCTest
@testable import Chiptune

/// The sound sheet's Volume readout, shown as text and spoken as the slider's
/// value. `Int(0.57 * 100)` is 56 — the product lands a hair under 57 — so a
/// level the user set to 57 read back as 56.
final class FormatPercentTests: XCTestCase {
    func testRoundsRatherThanTruncates() {
        XCTAssertEqual(Format.percent(0.57), "57%")
        XCTAssertEqual(Format.percent(0.29), "29%")
        XCTAssertEqual(Format.percent(0.567), "57%")
        XCTAssertEqual(Format.percent(0.564), "56%")
    }

    func testEndsAreExact() {
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(1), "100%")
        XCTAssertEqual(Format.percent(0.5), "50%")
    }
}
