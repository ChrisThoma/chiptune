import SwiftUI
import XCTest
@testable import Chiptune

final class SelectionAccessibilityTests: XCTestCase {
    func testSelectedReadsAsSelectedButton() {
        let traits = SelectionAccessibility.traits(selected: true)
        XCTAssertTrue(traits.contains(.isSelected))
        XCTAssertTrue(traits.contains(.isButton))
    }

    func testUnselectedIsAPlainButton() {
        let traits = SelectionAccessibility.traits(selected: false)
        XCTAssertFalse(traits.contains(.isSelected))
        XCTAssertTrue(traits.contains(.isButton))
    }
}
