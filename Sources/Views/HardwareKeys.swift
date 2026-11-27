import SwiftUI
#if os(iOS)
import UIKit

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
struct KeyCatcher: UIViewRepresentable {
    @Bindable var studio: Studio

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handle = { [weak studio] key, modalPresented in
            guard let studio else { return nil }
            // Two mappings, one keyboard. With a sheet up the editor is not
            // what's being typed at, so only the cancel gesture is claimed.
            let action: KeyAction?
            if modalPresented {
                action = KeyAction.forPresentedKey(usage: key.keyCode,
                                                   modifiers: key.modifierFlags)
            } else {
                action = KeyAction.forKey(usage: key.keyCode,
                                          characters: key.charactersIgnoringModifiers,
                                          modifiers: key.modifierFlags,
                                          octave: studio.octave)
            }
            guard let action else { return nil }
            studio.apply(action)
            return action
        }
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        // Deliberately holds first responder even while a sheet is up. It used
        // to resign, to stop grid keys reaching the pattern underneath — but
        // `pressesBegan` already does that job properly, by asking a different
        // mapping which keys count while something is presented, and resigning
        // took the catcher off the responder chain. That chain is the only way
        // Escape and Cmd+. arrive: UIKit sends its cancel gesture down it from
        // the first responder, never through the command system, so with
        // nobody on it the chain ran window → application and no sheet could
        // be closed from the keyboard at all.
        //
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
        /// Takes whether a sheet or popover is up, because that decides which
        /// of the two mappings the press is read with. Returns what the press
        /// did, or nil if it wasn't claimed.
        var handle: ((UIKey, Bool) -> KeyAction?)?

        /// Walks a held arrow; see `KeyRepeat`.
        private let repeater = KeyRepeater()

        /// The one instance actually installed in the view hierarchy (the
        /// editor has exactly one). Lets a deliberate focus handoff elsewhere
        /// in the app — ending a song rename — reclaim first responder
        /// directly, rather than only through `updateUIView` incidentally
        /// running again. See `HardwareKeyCapture.reclaim()`.
        static weak var current: CatcherView?

        override var canBecomeFirstResponder: Bool { true }

        // This view holds first responder all session, so whatever iOS shows
        // for the first responder it shows for this view. On iOS 27.1 opening
        // any menu (the song menu, the old Sound preset menu) raised the full software
        // keyboard over the app with this view as first responder and no
        // text field focused. An empty input view gives the system nothing
        // to show. Hardware presses come through `pressesBegan` and don't
        // involve it; a text field brings its own keyboard when focused.
        private let noKeyboard = UIView(frame: .zero)
        override var inputView: UIView? { noKeyboard }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                CatcherView.current = self
                becomeFirstResponder()
            } else {
                repeater.stop()
                if CatcherView.current === self { CatcherView.current = nil }
            }
        }

        // A text field taking the keyboard mid-hold never sends this view the
        // release, so the repeat would walk on under it.
        override func resignFirstResponder() -> Bool {
            repeater.stop()
            return super.resignFirstResponder()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            // Checked synchronously here rather than relying solely on
            // updateUIView: a sheet like InstrumentEditor can be presented by
            // state this view never observes, so updateUIView may not re-run
            // until after the very key press that would otherwise leak
            // through and mutate the grid underneath. Asked of the UIKit
            // hierarchy rather than a per-screen @State flag, since some
            // sheets (InstrumentEditor's) are toggled by state that isn't
            // owned by this view's ancestor at all.
            let unhandled = presses.filter { press in
                guard let key = press.key,
                      let action = handle?(key, modalPresented) else { return true }
                if KeyRepeat.repeats(action) {
                    repeater.start(usage: key.keyCode) { [weak self] in
                        // Asked again on every repeat: a sheet that opens
                        // mid-hold reads the arrow with its own mapping, which
                        // doesn't claim it, and that ends the walk.
                        guard let self else { return }
                        if self.handle?(key, self.modalPresented) == nil {
                            self.repeater.stop()
                        }
                    }
                }
                return false
            }
            // Anything not claimed carries on up the chain, so the shortcuts
            // the system owns still work.
            if !unhandled.isEmpty {
                super.pressesBegan(unhandled, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stopRepeating(presses)
            super.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stopRepeating(presses)
            super.pressesCancelled(presses, with: event)
        }

        private func stopRepeating(_ presses: Set<UIPress>) {
            for press in presses {
                if let key = press.key { repeater.stop(usage: key.keyCode) }
            }
        }

        private var modalPresented: Bool {
            window?.rootViewController?.presentedViewController != nil
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
                  !view.isFirstResponder
            else { return }
            // Deliberately *not* guarded on `!textIsFirstResponder` the way
            // `updateUIView` is. That guard is right for a redraw, which can
            // land mid-rename and must not pull the keyboard out from under
            // a field being typed into. It is wrong here: this is only
            // called once the app has decided the rename is over, and the
            // case that has to be fixed is precisely a name field that is
            // still holding the keyboard — a `@FocusState` flipping to false
            // is not a promise that SwiftUI has resigned the underlying text
            // field yet, or ever. Backing off then leaves the field first
            // responder with nothing scheduled to try again, so every
            // subsequent hardware key is typed into the song title.
            //
            // So take it rather than ask for it. `becomeFirstResponder()`
            // does route through the current holder's `resignFirstResponder`,
            // but a text field is entitled to refuse mid-edit; resigning it
            // first, as its own decision, is the part that actually lands.
            if let holder = UIResponder.currentFirstResponder, holder !== view {
                holder.resignFirstResponder()
            }
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
#endif
