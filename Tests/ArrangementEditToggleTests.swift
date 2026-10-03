import SwiftUI
import XCTest
@testable import Chiptune

final class ArrangementEditToggleTests: XCTestCase {
    func testToggleFlipsBetweenInactiveAndActive() {
        XCTAssertEqual(ArrangementEditToggle.toggled(.inactive), .active)
        XCTAssertEqual(ArrangementEditToggle.toggled(.active), .inactive)
        XCTAssertEqual(ArrangementEditToggle.toggled(.transient), .inactive)
    }

    func testLabelAndIconFollowTheModeThatDrivesTheRows() {
        XCTAssertEqual(ArrangementEditToggle.title(.inactive), "Edit")
        XCTAssertEqual(ArrangementEditToggle.title(.active), "Done editing")
        XCTAssertTrue(ArrangementEditToggle.isEditing(.active))
        XCTAssertFalse(ArrangementEditToggle.isEditing(.inactive))
    }
}
