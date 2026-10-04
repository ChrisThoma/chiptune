import UIKit
import XCTest
@testable import Chiptune

final class TempoFieldAccessibilityTests: XCTestCase {
    /// The alert prefills the current tempo, so the placeholder that would
    /// otherwise stand in for a label is never on screen.
    func testTempoAlertFieldReceivesItsSpokenPurpose() {
        let field = UITextField()
        field.text = "120"

        TempoFieldAccessibility.apply(to: field)

        XCTAssertEqual(field.accessibilityLabel, "BPM")
    }
}
