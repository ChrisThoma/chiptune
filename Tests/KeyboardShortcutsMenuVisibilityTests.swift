import XCTest
@testable import Chiptune

/// The song menu's "Keyboard shortcuts" row only means something once a
/// keyboard has actually said something to the app — a phone user tapping
/// through the menu has no use for a row that explains keys it doesn't have.
final class KeyboardShortcutsMenuVisibilityTests: XCTestCase {

    func testHiddenWithNoKeyboardEverSeen() {
        XCTAssertFalse(KeyboardShortcutsMenuVisibility.visible(keyboardConnected: false,
                                                                hardwareKeyboardInUse: false))
    }

    func testVisibleWhenAKeyboardIsCurrentlyConnected() {
        // Covers one plugged in but not yet pressed — GCKeyboard.coalesced
        // fires on connect, before any key press sets hardwareKeyboardInUse.
        XCTAssertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected: true,
                                                               hardwareKeyboardInUse: false))
    }

    func testVisibleWhenTheSessionAlreadyUsedOneEvenIfDisconnectedSince() {
        // studio.hardwareKeyboardInUse sticks once true, so a keyboard used
        // earlier and then unplugged keeps the row around for that session.
        XCTAssertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected: false,
                                                               hardwareKeyboardInUse: true))
    }

    func testVisibleWhenBothAreTrue() {
        XCTAssertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected: true,
                                                               hardwareKeyboardInUse: true))
    }
}
