#if os(macOS)
import AppKit
import XCTest
@testable import Chiptune

/// The Mac's half of the hardware keys: turning an `NSEvent`'s key code and
/// modifier flags into the same `KeyUsage`/`KeyModifiers` the iPad reads, so
/// `KeyAction`'s one mapping (and `HardwareKeyTests`) covers both.
///
/// Key codes are the Carbon virtual key codes (`kVK_*`), which name physical
/// key positions on an ANSI keyboard.
final class MacKeyMappingTests: XCTestCase {

    func testTheTransportAndCursorKeys() {
        XCTAssertEqual(MacKeys.usage(forKeyCode: 49), .keyboardSpacebar)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 126), .keyboardUpArrow)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 125), .keyboardDownArrow)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 123), .keyboardLeftArrow)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 124), .keyboardRightArrow)
    }

    /// The Mac's Delete key is backspace; the full-size keyboard's ⌦ is
    /// forward delete. Both clear, as on the iPad.
    func testBothDeleteKeys() {
        XCTAssertEqual(MacKeys.usage(forKeyCode: 51), .keyboardDeleteOrBackspace)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 117), .keyboardDeleteForward)
    }

    func testReturnEnterEscapeAndTheCutKey() {
        XCTAssertEqual(MacKeys.usage(forKeyCode: 36), .keyboardReturnOrEnter)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 76), .keypadEnter)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 53), .keyboardEscape)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 42), .keyboardBackslash)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 47), .keyboardPeriod)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 48), .keyboardTab)
    }

    /// Letters map by position. The note row itself is read from the typed
    /// character, not the code, but the cancel mapping and the repeater key
    /// on the usage, so a letter must never come out as one of the claimed
    /// keys.
    func testLettersMapToTheirOwnUsage() {
        XCTAssertEqual(MacKeys.usage(forKeyCode: 0), .keyboardA)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 14), .keyboardE)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 32), .keyboardU)
    }

    /// A key nothing asks about still maps to something, so a press is
    /// never dropped before `KeyAction` has looked at its character.
    func testAnUnnamedKeyIsUndefinedRatherThanAClaimedOne() {
        XCTAssertEqual(MacKeys.usage(forKeyCode: 122), .keyboardF1)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 115), .keyboardHome)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 116), .keyboardPageUp)
        XCTAssertEqual(MacKeys.usage(forKeyCode: 0x7F), .keyboardErrorUndefined)
    }

    func testModifierFlags() {
        XCTAssertEqual(MacKeys.modifiers(from: []), [])
        XCTAssertEqual(MacKeys.modifiers(from: .command), .command)
        XCTAssertEqual(MacKeys.modifiers(from: .option), .alternate)
        XCTAssertEqual(MacKeys.modifiers(from: .control), .control)
        XCTAssertEqual(MacKeys.modifiers(from: .shift), .shift)
        XCTAssertEqual(MacKeys.modifiers(from: [.command, .shift]), [.command, .shift])
    }

    /// Caps Lock, Fn and the arrows' own `.numericPad`/`.function` flags are
    /// set on ordinary presses. Read as modifiers, they would make every arrow
    /// and every note look like a chord, and the editor would claim nothing.
    func testFlagsThatAreNotChordsAreIgnored() {
        XCTAssertEqual(MacKeys.modifiers(from: [.capsLock, .function, .numericPad]), [])
    }

    // MARK: Through KeyAction, end to end

    private func action(keyCode: UInt16, characters: String,
                        flags: NSEvent.ModifierFlags = [], octave: Int = 5) -> KeyAction? {
        KeyAction.forKey(usage: MacKeys.usage(forKeyCode: keyCode),
                         characters: characters,
                         modifiers: MacKeys.modifiers(from: flags),
                         octave: octave)
    }

    func testAnArrowPressAsTheMacSendsItMovesTheCursor() {
        // AppKit sends an arrow as a private-use character with .function
        // and .numericPad set.
        XCTAssertEqual(action(keyCode: 125, characters: "\u{F701}", flags: [.function, .numericPad]),
                       .move(track: 0, step: 1))
    }

    func testTheNoteRowTypesNotes() {
        XCTAssertEqual(action(keyCode: 0, characters: "a"), .type(60))
        XCTAssertEqual(action(keyCode: 0, characters: "A", flags: .shift), .type(60))
        XCTAssertEqual(action(keyCode: 32, characters: "u", flags: .capsLock), .type(70))
    }

    /// AppKit names its function keys with single private-use characters
    /// (F1 is U+F704) rather than UIKit's "UIKeyInputF1" strings. They are
    /// one character long, so they have to fall through as nothing rather
    /// than as a note.
    func testFunctionKeysTypeNothing() {
        XCTAssertNil(action(keyCode: 122, characters: "\u{F704}", flags: .function))
        XCTAssertNil(action(keyCode: 115, characters: "\u{F729}", flags: .function))
        XCTAssertNil(action(keyCode: 53, characters: "\u{1B}"))
    }

    func testCommandChordsAreLeftForTheMenus() {
        XCTAssertNil(action(keyCode: 0, characters: "a", flags: .command))
    }

    func testEscapeAndCommandPeriodDismissWhilePresented() {
        XCTAssertEqual(KeyAction.forPresentedKey(usage: MacKeys.usage(forKeyCode: 53),
                                                 modifiers: MacKeys.modifiers(from: [])),
                       .dismiss)
        XCTAssertEqual(KeyAction.forPresentedKey(usage: MacKeys.usage(forKeyCode: 47),
                                                 modifiers: MacKeys.modifiers(from: .command)),
                       .dismiss)
    }
}
#endif
