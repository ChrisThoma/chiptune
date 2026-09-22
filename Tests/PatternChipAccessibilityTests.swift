import XCTest
@testable import Chiptune

final class PatternChipAccessibilityTests: XCTestCase {
    func testChipValueNamesPlayingAndEmpty() {
        XCTAssertNil(PatternChipAccessibility.value(playing: false, isEmpty: false))
        XCTAssertEqual(PatternChipAccessibility.value(playing: true, isEmpty: false), "Playing")
        XCTAssertEqual(PatternChipAccessibility.value(playing: false, isEmpty: true), "Empty")
        XCTAssertEqual(PatternChipAccessibility.value(playing: true, isEmpty: true), "Playing, Empty")
    }
}
