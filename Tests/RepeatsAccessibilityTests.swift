import XCTest
@testable import Chiptune

final class RepeatsAccessibilityTests: XCTestCase {
    func testLabelNamesTheOneBasedSection() {
        XCTAssertEqual(RepeatsAccessibility.label(position: 0), "Section 1 repeats")
        XCTAssertEqual(RepeatsAccessibility.label(position: 2), "Section 3 repeats")
    }

    func testLabelsDifferAcrossRows() {
        let labels = (0..<4).map { RepeatsAccessibility.label(position: $0) }
        XCTAssertEqual(Set(labels).count, 4)
    }

    func testValueIsGrammatical() {
        XCTAssertEqual(RepeatsAccessibility.value(1), "1 time")
        XCTAssertEqual(RepeatsAccessibility.value(2), "2 times")
        XCTAssertEqual(RepeatsAccessibility.value(16), "16 times")
    }
}
