import XCTest
import UIKit
@testable import Chiptune

/// The hardware-key catcher holds first responder for the whole session, so
/// whatever iOS decides to show for the first responder, it shows for the
/// catcher. On iOS 27.1 opening any menu (the song menu, a Sound preset)
/// brought up the full software keyboard over the app, with the catcher as
/// first responder and no text field focused (2026-10-24, iPhone Duo and
/// iPhone 18 Pro Max simulators, idb taps as well as accessibility presses).
/// An empty input view leaves the system nothing to show for it; hardware
/// presses still arrive through `pressesBegan`, which doesn't involve it.
@MainActor
final class KeyCatcherSoftwareKeyboardTests: XCTestCase {

    func testCatcherOffersAnEmptyInputViewSoNoSoftwareKeyboardShows() throws {
        let catcher = KeyCatcher.CatcherView()
        let input = try XCTUnwrap(catcher.inputView,
                                  "with no input view of its own, iOS falls back to the software keyboard")
        XCTAssertEqual(input.frame.height, 0)
        XCTAssertTrue(input.subviews.isEmpty)
    }

    func testCatcherIsNotATextInput() {
        // The reclaim logic treats a UITextInput first responder as someone
        // typing; the catcher must never look like one.
        XCTAssertFalse(KeyCatcher.CatcherView() is UITextInput)
    }
}
