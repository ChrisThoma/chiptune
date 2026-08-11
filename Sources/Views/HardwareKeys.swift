import SwiftUI
import UIKit

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
    case clear
    case octave(Int)

    /// `nil` for anything the editor doesn't claim, which the responder chain
    /// then carries on past.
    static func forKey(usage: UIKeyboardHIDUsage,
                       characters: String,
                       modifiers: UIKeyModifierFlags,
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
        default: break
        }

        guard let character = characters.first else { return nil }
        switch Character(character.lowercased()) {
        case NoteKeys.octaveDown: return .octave(-1)
        case NoteKeys.octaveUp: return .octave(1)
        default:
            guard let note = NoteKeys.note(for: character, octave: octave) else { return nil }
            return .type(note)
        }
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
        case .clear: clearAtCursor()
        case let .octave(delta):
            hardwareKeyboardInUse = true
            shiftOctave(delta)
        }
    }
}

extension View {
    /// Space, arrows and the note row, for the iPads that arrive attached to a
    /// keyboard.
    func hardwareKeys(studio: Studio) -> some View {
        background(KeyCatcher(studio: studio).frame(width: 0, height: 0))
    }
}

/// Keys arrive through the responder chain rather than SwiftUI's focus system.
/// `focusable()` and `onKeyPress` need the view to hold SwiftUI focus, and on
/// iOS the editor never takes it: nothing here is a focusable control, so
/// there's nothing for focus to land on and the presses go nowhere. A first
/// responder gets them whatever the focus system thinks.
private struct KeyCatcher: UIViewRepresentable {
    @Bindable var studio: Studio

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handle = { [weak studio] key in
            guard let studio,
                  let action = KeyAction.forKey(usage: key.keyCode,
                                                characters: key.charactersIgnoringModifiers,
                                                modifiers: key.modifierFlags,
                                                octave: studio.octave)
            else { return false }
            studio.apply(action)
            return true
        }
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        // Reclaims the keyboard once whatever borrowed it — the song name
        // field, a rename alert — has given it back. Every edit in the app
        // runs this, so there's no polling and no window where typing is dead.
        // Guarded on nothing else holding it, or a redraw mid-rename would
        // take the keyboard out from under the field being typed into.
        if view.window != nil, !view.isFirstResponder, UIResponder.currentFirstResponder == nil {
            view.becomeFirstResponder()
        }
    }

    final class CatcherView: UIView {
        var handle: ((UIKey) -> Bool)?

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let unhandled = presses.filter { press in
                guard let key = press.key else { return true }
                return handle?(key) != true
            }
            // Anything not claimed carries on up the chain, so the shortcuts
            // the system owns still work.
            if !unhandled.isEmpty {
                super.pressesBegan(unhandled, with: event)
            }
        }
    }
}

private extension UIResponder {
    @MainActor private static weak var found: UIResponder?

    /// Who holds the keyboard right now, or nil if nobody does. There's no API
    /// that answers this; an action sent to a nil target goes to the first
    /// responder, whoever that is, which is the same question asked sideways.
    @MainActor
    static var currentFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(reportAsFirstResponder),
                                        to: nil, from: nil, for: nil)
        return found
    }

    @MainActor
    @objc func reportAsFirstResponder() {
        UIResponder.found = self
    }
}
