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
    /// Arms or disarms a note off, mirroring the OFF button.
    case toggleNoteOff
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
        // Backslash is the tracker convention for a cut. Matched on usage
        // rather than character so a layout that puts it elsewhere still works.
        case .keyboardBackslash: return .toggleNoteOff
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
        case .toggleNoteOff:
            hardwareKeyboardInUse = true
            toggleNoteOff()
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
        // A presented sheet (InstrumentEditor, ArrangementView, ExportSheet,
        // SongListView, ...) can put non-text-field controls on screen that
        // never take first responder away from us, so hardware keys would
        // otherwise keep reaching the grid underneath. Check the UIKit
        // hierarchy directly rather than a per-screen @State flag, since some
        // sheets (InstrumentEditor's) are toggled by state that isn't owned
        // by this view's ancestor at all.
        guard view.window?.rootViewController?.presentedViewController == nil else {
            if view.isFirstResponder { view.resignFirstResponder() }
            return
        }
        // Reclaims the keyboard once whatever borrowed it — the song name
        // field, a rename alert — has given it back. Every edit in the app
        // runs this, so there's no polling and no window where typing is dead.
        // Guarded on no *text* still holding it, or a redraw mid-rename would
        // take the keyboard out from under the field being typed into.
        //
        // Deliberately not `currentFirstResponder == nil`: once a text field
        // has been focused and let go, first responder doesn't come back to
        // nobody — it settles on a responder that isn't ours and isn't typing
        // either (the window, SwiftUI's hosting view). That responder is above
        // this view rather than below it, so presses walk up past the grid and
        // vanish, and a nil-only guard would never reclaim them again for the
        // rest of the session.
        if view.window != nil, !view.isFirstResponder, !UIResponder.textIsFirstResponder {
            view.becomeFirstResponder()
        }
    }

    final class CatcherView: UIView {
        var handle: ((UIKey) -> Bool)?

        /// The one instance actually installed in the view hierarchy (the
        /// editor has exactly one). Lets a deliberate focus handoff elsewhere
        /// in the app — ending a song rename — reclaim first responder
        /// directly, rather than only through `updateUIView` incidentally
        /// running again. See `HardwareKeyCapture.reclaim()`.
        static weak var current: CatcherView?

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                CatcherView.current = self
                becomeFirstResponder()
            } else if CatcherView.current === self {
                CatcherView.current = nil
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            // Checked synchronously here rather than relying solely on
            // updateUIView: a sheet like InstrumentEditor can be presented by
            // state this view never observes, so updateUIView may not re-run
            // until after the very key press that would otherwise leak
            // through and mutate the grid underneath.
            let modalPresented = window?.rootViewController?.presentedViewController != nil
            let unhandled = presses.filter { press in
                guard !modalPresented, let key = press.key else { return true }
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

/// Reclaims the hardware-key catcher's first-responder status on demand.
/// Called directly from wherever the app deliberately hands focus to a text
/// field and then takes it back — e.g. ending a song rename — instead of
/// relying solely on `KeyCatcher.updateUIView` happening to run again for
/// that.
///
/// It has to be a separate, explicit call: `nameFocused` going false is a
/// `@FocusState` owned by `ContentView`, so it invalidates only
/// `ContentView`'s body, and `updateUIView` runs as part of that same
/// render pass — before SwiftUI has actually told UIKit to resign the text
/// field's first-responder status, which happens slightly later. At that
/// moment `UIResponder.textIsFirstResponder` is still true, so the reclaim
/// attempt in `updateUIView` no-ops, and nothing else in the app is
/// guaranteed to force `updateUIView` to run again afterward — leaving
/// hardware keys dead until relaunch. Deferring to the next run loop turn
/// gives the resign time to actually land first.
enum HardwareKeyCapture {
    @MainActor
    static func reclaim() {
        DispatchQueue.main.async {
            guard let view = KeyCatcher.CatcherView.current,
                  view.window != nil,
                  !view.isFirstResponder,
                  !UIResponder.textIsFirstResponder
            else { return }
            view.becomeFirstResponder()
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

    /// Whether something that takes typing — a text field, a text view, an
    /// alert's field — currently holds the keyboard. `UITextInput` is what
    /// every one of those conforms to and nothing else does, which is exactly
    /// the line that matters here: a responder that isn't typing has no claim
    /// on the note row.
    @MainActor
    static var textIsFirstResponder: Bool {
        guard let responder = currentFirstResponder else { return false }
        return responder is UITextInput
    }

    @MainActor
    @objc func reportAsFirstResponder() {
        UIResponder.found = self
    }
}
