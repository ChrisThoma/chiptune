import XCTest
@testable import Chiptune

final class TempoEntryTests: XCTestCase {
    func testWholeNumbersInRangeAreAccepted() {
        XCTAssertEqual(TempoEntry.bpm(from: "120"), 120)
        XCTAssertEqual(TempoEntry.bpm(from: " 40 "), 40)
        XCTAssertEqual(TempoEntry.bpm(from: "300"), 300)
    }

    /// 1280 used to be quietly turned into 300 by Set.
    func testOutOfRangeEntryIsRejectedRatherThanClamped() {
        XCTAssertNil(TempoEntry.bpm(from: "1280"))
        XCTAssertNil(TempoEntry.bpm(from: "39"))
        XCTAssertNil(TempoEntry.bpm(from: "301"))
        XCTAssertNil(TempoEntry.bpm(from: "0"))
    }

    func testBlankOrNonNumericEntryIsRejected() {
        XCTAssertNil(TempoEntry.bpm(from: ""))
        XCTAssertNil(TempoEntry.bpm(from: "  "))
        XCTAssertNil(TempoEntry.bpm(from: "abc"))
    }
}
