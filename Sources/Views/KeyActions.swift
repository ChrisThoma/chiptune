import SwiftUI
#if os(iOS)
import UIKit

/// The key model the mapping below reads. On iOS it is UIKit's own, so a
/// press goes from `UIKey` to `KeyAction` untouched; the Mac fills the same
/// names in from `NSEvent` (see `MacKeys`).
typealias KeyUsage = UIKeyboardHIDUsage
typealias KeyModifiers = UIKeyModifierFlags
#endif

/// Which note a letter key writes.
///
/// The home row plus the row above it, laid out as a piano: `A` is C, `W` is
/// C sharp, `S` is D, and so on up to `K`, the octave above. Every DAW with a
/// typing-keyboard mode uses this arrangement, so it's the one a person
/// arriving with a hardware keyboard already knows — and its shape is visible
/// in the keys themselves, the black notes sitting above the gaps.
enum NoteKeys {
    /// Semitones above the octave's C.
    static let semitones: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6,
        "g": 7, "y": 8, "h": 9, "u": 10, "j": 11, "k": 12,
    ]

    /// Octave down and up, on the keys under the note row that the same DAWs
    /// put them on.
    static let octaveDown: Character = "z"
    static let octaveUp: Character = "x"

    /// The MIDI note a key writes, or nil if that key isn't part of the
    /// layout. `octave` matches the on-screen keyboard's, where C4 is 60.
    ///
    /// Out-of-range results are dropped rather than clamped: at the top octave
    /// the end of the row runs past MIDI 127, and a key that quietly writes
    /// the wrong note is worse than one that does nothing.
    static func note(for character: Character, octave: Int) -> Int8? {
        guard let semitone = semitones[Character(character.lowercased())] else { return nil }
        let midi = octave * 12 + semitone
        guard (0...127).contains(midi) else { return nil }
        return Int8(midi)
    }
}

/// What a key press means. Worked out from the press alone, so the whole
/// mapping is testable without a keyboard attached.
enum KeyAction: Equatable {
    case togglePlay
    /// Arrow keys, in tracks and steps.
    case move(track: Int, step: Int)
    case type(Int8)
    /// Return: writes whatever the on-screen keyboard is holding, which is the
    /// only way to enter a note off — the letter row has no key for one.
    case typeSelected
    /// Arms or disarms a note off (rest), mirroring the REST button.
    case toggleNoteOff
    case clear
    case octave(Int)
    /// Escape, or Cmd+., while a sheet or popover is up. Says only that the
    /// user asked to close something — which screen that is, is `ContentView`'s
    /// to know.
    case dismiss

    /// `nil` for anything the editor doesn't claim, which the responder chain
    /// then carries on past.
    static func forKey(usage: KeyUsage,
                       characters: String,
                       modifiers: KeyModifiers,
                       octave: Int) -> KeyAction? {
        // Command and control belong to the system and to menu shortcuts. Shift
        // is let through: it's how a capital arrives, and the note row doesn't
        // care which case it's in.
        guard !modifiers.contains(.command), !modifiers.contains(.control),
              !modifiers.contains(.alternate) else { return nil }

        switch usage {
        case .keyboardSpacebar: return .togglePlay
        case .keyboardUpArrow: return .move(track: 0, step: -1)
        case .keyboardDownArrow: return .move(track: 0, step: 1)
        case .keyboardLeftArrow: return .move(track: -1, step: 0)
        case .keyboardRightArrow: return .move(track: 1, step: 0)
        // Both, because a full-size keyboard's forward-delete is the same
        // gesture to the person pressing it.
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: return .clear
        case .keyboardReturnOrEnter, .keypadEnter: return .typeSelected
        // Backslash is the tracker convention for a cut. Matched on usage
        // rather than character so a layout that puts it elsewhere still works.
        case .keyboardBackslash: return .toggleNoteOff
        default: break
        }

        // One character only. UIKit names the non-printing keys with constant
        // strings ("UIKeyInputEscape", "UIKeyInputF1", "UIKeyInputHome"), whose
        // first letter is not what was typed: the "U" of those names is the
        // note row's U, so Escape used to write A sharp and advance the cursor.
        guard characters.count == 1, let character = characters.first else { return nil }
        switch Character(character.lowercased()) {
        case NoteKeys.octaveDown: return .octave(-1)
        case NoteKeys.octaveUp: return .octave(1)
        default:
            guard let note = NoteKeys.note(for: character, octave: octave) else { return nil }
            return .type(note)
        }
    }

    /// What a press means while a sheet or popover is up — which is a much
    /// shorter list: close it, or nothing.
    ///
    /// Escape and Cmd+. are UIKit's cancel gesture, and UIKit delivers them
    /// down the responder chain from the first responder rather than through
    /// the menu and command system. So neither a `.keyboardShortcut(
    /// .cancelAction)` on a sheet's own Close button nor one on an app-level
    /// command is ever consulted: a presented sheet's hosting controller isn't
    /// on the chain, and commands aren't asked. The catcher is the one thing
    /// that is on it, so answering here is what makes Escape work at all.
    ///
    /// Everything else returns nil and is forwarded on, which is how the
    /// Command chords keep firing while a sheet is open.
    static func forPresentedKey(usage: KeyUsage,
                                modifiers: KeyModifiers) -> KeyAction? {
        switch usage {
        case .keyboardEscape: return .dismiss
        // The period alone is a period; only the Command form is the cancel.
        case .keyboardPeriod where modifiers.contains(.command): return .dismiss
        default: return nil
        }
    }
}

/// Which held keys repeat, and how fast. UIKit sends a hardware press once
/// however long it's held, so without this holding Down moved one step.
enum KeyRepeat {
    /// Long enough that an ordinary tap never repeats; about the system's own.
    static let initialDelay: TimeInterval = 0.4
    static let interval: TimeInterval = 0.08

    /// Only the arrows. A held letter filling a track with one note, or a held
    /// Space starting and stopping playback, is never what was meant.
    static func repeats(_ action: KeyAction) -> Bool {
        if case .move = action { return true }
        return false
    }
}

/// Fires a held key again, first after `KeyRepeat.initialDelay` and then every
/// `interval`, until that key is let go. One key at a time: pressing another
/// arrow takes over, the way a text field's repeat does.
final class KeyRepeater {
    private var timer: Timer?
    private var usage: KeyUsage?

    var isRepeating: Bool { timer != nil }

    func start(usage: KeyUsage, fire: @escaping () -> Void) {
        stop()
        self.usage = usage
        timer = Timer.scheduledTimer(withTimeInterval: KeyRepeat.initialDelay,
                                     repeats: false) { [weak self] _ in
            fire()
            self?.timer = Timer.scheduledTimer(withTimeInterval: KeyRepeat.interval,
                                               repeats: true) { _ in fire() }
        }
    }

    /// Letting go of some other key leaves this one repeating.
    func stop(usage: KeyUsage) {
        guard usage == self.usage else { return }
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        usage = nil
    }
}

extension Studio {
    /// Runs a decoded key press. Split from the decoding so the mapping stays
    /// a pure function and this stays the only place a press changes anything.
    func apply(_ action: KeyAction) {
        switch action {
        case .togglePlay: togglePlay()
        case let .move(track, step): moveCursor(track: track, step: step)
        case let .type(note): typeNote(note)
        case .typeSelected: typeNote(selectedNote)
        case .toggleNoteOff:
            hardwareKeyboardInUse = true
            toggleNoteOff()
        case .clear: clearAtCursor()
        case let .octave(delta):
            hardwareKeyboardInUse = true
            shiftOctave(delta)
        case .dismiss: requestDismiss()
        }
    }
}

