import XCTest
import SwiftUI
@testable import Chiptune

/// The ARR popover used to be declared on the ARR button inside every
/// `ViewThatFits` alternative, so crossing a form boundary with it open
/// swapped its anchor out from under it. It is now declared once, on the
/// transport as a whole, and pointed at wherever ARR was last laid out.
final class ArrangementPopoverAnchorTests: XCTestCase {

    func testPointsAtTheARRButtonOnceItHasBeenLaidOut() {
        let arr = CGRect(x: 180, y: 0, width: 56, height: 44)
        XCTAssertEqual(ArrangementPopoverAnchor.rect(arrFrame: arr), arr)
    }

    /// Before the first layout pass there is no frame yet; anchoring to an
    /// empty rect at the origin would put the arrow in the corner, so it
    /// says "none" and the transport anchors to its own bounds instead.
    func testFallsBackToTheWholeBarBeforeARRHasAFrame() {
        XCTAssertNil(ArrangementPopoverAnchor.rect(arrFrame: nil))
        XCTAssertNil(ArrangementPopoverAnchor.rect(arrFrame: .zero))
    }
}
