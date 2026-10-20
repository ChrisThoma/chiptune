import XCTest
import CoreGraphics
@testable import Chiptune

/// The docked instrument editor sits under the piano in the landscape side
/// column, where the software keyboard covers all of it. While its Name field
/// is being typed into, the column has to keep the field above the keyboard.
final class DockedKeyboardAvoidanceTests: XCTestCase {
    // iPad mini landscape: the column runs the full window height, the piano
    // takes about 300 pt at its top, and the software keyboard's top edge is
    // at y 311.
    private let column = CGRect(x: 780, y: 24, width: 353, height: 700)

    func testSoftwareKeyboardOverTheEditorHidesTheKeysAndInsetsTheForm() {
        let avoidance = DockedKeyboardAvoidance.resolve(
            nameEditing: true, column: column, keyboardTop: 311, keysHeight: 300)
        XCTAssertEqual(avoidance.bottomInset, 724 - 311)
        XCTAssertTrue(avoidance.hidesKeys)
    }

    func testHardwareKeyboardShortcutBarKeepsTheKeys() {
        // A hardware keyboard leaves only the shortcut bar on screen.
        let avoidance = DockedKeyboardAvoidance.resolve(
            nameEditing: true, column: column, keyboardTop: 724 - 55, keysHeight: 300)
        XCTAssertEqual(avoidance.bottomInset, 55)
        XCTAssertFalse(avoidance.hidesKeys)
    }

    func testNoKeyboardChangesNothing() {
        // With no keyboard the safe-area bottom is the column's own bottom.
        let avoidance = DockedKeyboardAvoidance.resolve(
            nameEditing: true, column: column, keyboardTop: 724, keysHeight: 300)
        XCTAssertEqual(avoidance, .none)
    }

    func testAKeyboardRaisedForAnotherFieldLeavesTheColumnAlone() {
        // The song title in the title bar also brings the keyboard up; the
        // piano must not vanish for that.
        let avoidance = DockedKeyboardAvoidance.resolve(
            nameEditing: false, column: column, keyboardTop: 311, keysHeight: 300)
        XCTAssertEqual(avoidance, .none)
    }

    func testInsetAlwaysLeavesTheEditorItsMinimum() {
        // Padding the column past its own height made it grow, which moved
        // its bottom further under the keyboard: a layout loop on device.
        let avoidance = DockedKeyboardAvoidance.resolve(
            nameEditing: true, column: column, keyboardTop: 0, keysHeight: 300)
        XCTAssertEqual(avoidance.bottomInset,
                       column.height - DockedKeyboardAvoidance.minimumEditorHeight)
        XCTAssertTrue(avoidance.hidesKeys)
    }
}
