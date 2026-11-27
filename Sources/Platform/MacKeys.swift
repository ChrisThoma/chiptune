#if os(macOS)
import AppKit

/// The Mac's stand-in for `UIKeyboardHIDUsage`: the same USB HID usage
/// numbers under the same names, so `KeyAction`'s mapping and its tests read
/// identically on both platforms. Only the keys something here asks about are
/// named; `MacKeys.usage(forKeyCode:)` fills them in from an `NSEvent`.
struct KeyUsage: RawRepresentable, Hashable {
    let rawValue: Int

    static let keyboardErrorUndefined = KeyUsage(rawValue: 0x03)
    static let keyboardA = KeyUsage(rawValue: 0x04)
    static let keyboardE = KeyUsage(rawValue: 0x08)
    static let keyboardU = KeyUsage(rawValue: 0x18)
    static let keyboardReturnOrEnter = KeyUsage(rawValue: 0x28)
    static let keyboardEscape = KeyUsage(rawValue: 0x29)
    static let keyboardDeleteOrBackspace = KeyUsage(rawValue: 0x2A)
    static let keyboardTab = KeyUsage(rawValue: 0x2B)
    static let keyboardSpacebar = KeyUsage(rawValue: 0x2C)
    static let keyboardBackslash = KeyUsage(rawValue: 0x31)
    static let keyboardPeriod = KeyUsage(rawValue: 0x37)
    static let keyboardF1 = KeyUsage(rawValue: 0x3A)
    static let keyboardHome = KeyUsage(rawValue: 0x4A)
    static let keyboardPageUp = KeyUsage(rawValue: 0x4B)
    static let keyboardDeleteForward = KeyUsage(rawValue: 0x4C)
    static let keyboardRightArrow = KeyUsage(rawValue: 0x4F)
    static let keyboardLeftArrow = KeyUsage(rawValue: 0x50)
    static let keyboardDownArrow = KeyUsage(rawValue: 0x51)
    static let keyboardUpArrow = KeyUsage(rawValue: 0x52)
    static let keypadEnter = KeyUsage(rawValue: 0x58)
}

/// The Mac's stand-in for `UIKeyModifierFlags`, with UIKit's names (Option
/// is `.alternate`) for the same reason as `KeyUsage`.
struct KeyModifiers: OptionSet, Hashable {
    let rawValue: Int

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let alternate = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// `NSEvent` to the key model above.
enum MacKeys {
    /// Carbon virtual key codes (`kVK_*`, which name positions on an ANSI
    /// keyboard) to HID usages. Letters are by position, as HID's are; the
    /// note row reads the typed character anyway, so a non-QWERTY layout
    /// still plays by letter.
    private static let usages: [UInt16: KeyUsage] = {
        var table: [UInt16: KeyUsage] = [
            49: .keyboardSpacebar,
            126: .keyboardUpArrow, 125: .keyboardDownArrow,
            123: .keyboardLeftArrow, 124: .keyboardRightArrow,
            51: .keyboardDeleteOrBackspace, 117: .keyboardDeleteForward,
            36: .keyboardReturnOrEnter, 76: .keypadEnter,
            53: .keyboardEscape, 48: .keyboardTab,
            42: .keyboardBackslash, 47: .keyboardPeriod,
            122: .keyboardF1, 115: .keyboardHome, 116: .keyboardPageUp,
        ]
        // kVK_ANSI_A ... kVK_ANSI_Z, in alphabet order. HID numbers the
        // letters 0x04 (A) through 0x1D (Z).
        let letterCodes: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
                                     45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
        for (offset, code) in letterCodes.enumerated() {
            table[code] = KeyUsage(rawValue: KeyUsage.keyboardA.rawValue + offset)
        }
        return table
    }()

    static func usage(forKeyCode keyCode: UInt16) -> KeyUsage {
        usages[keyCode] ?? .keyboardErrorUndefined
    }

    /// Only the four chord keys. Caps Lock, Fn and `.numericPad` ride along
    /// on ordinary presses (every arrow carries `.function` and
    /// `.numericPad`), and read as chords they would make the editor claim
    /// nothing.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.alternate) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
#endif
