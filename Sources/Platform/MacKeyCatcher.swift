#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Space, arrows and the note row from the Mac's keyboard. The mapping is
    /// the iPad's (`KeyAction`); only the way presses arrive differs.
    func hardwareKeys(studio: Studio) -> some View {
        background(KeyCatcher(studio: studio).frame(width: 0, height: 0))
    }
}

/// Reads key presses for the editor's window through a local event monitor
/// rather than by holding first responder, which is how the iOS catcher does
/// it. On the Mac a click on the grid can make SwiftUI's hosting view first
/// responder, and the keys would then walk up a chain this view isn't on.
/// A monitor sees every key down in the app before it is dispatched, so the
/// editor gets its keys whatever was clicked last, and only gives way to a
/// text field being typed into, a sheet, or another window (a popover).
struct KeyCatcher: NSViewRepresentable {
    @Bindable var studio: Studio

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.studio = studio
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.studio = studio
    }

    final class CatcherView: NSView {
        weak var studio: Studio?
        private var monitor: Any?

        /// Takes first responder only so that nothing else gets it by
        /// default: a window becoming key with no first responder hands it
        /// to its first key view, which here is the song name field, and the
        /// next note typed renamed the song. It reads no keys itself.
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard let window else { return }
            window.initialFirstResponder = self
            MacTextEditing.shared.watch(window)
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window,
                      !(window.firstResponder is NSText) else { return }
                window.makeFirstResponder(self)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                switch event.type {
                case .keyDown:
                    if Self.typeSpaceIntoField(event) { return nil }
                    return self.handleKey(event) ? nil : event
                case .leftMouseDown:
                    self.endTextEditingIfClickedAway(event)
                    return event
                default: return event
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// Playback > Play/Stop shows Space as its key, and a menu's key
        /// equivalent is matched before the key reaches the field being
        /// typed into, so a space in a song name would start playback
        /// instead. Handing the press to the field directly keeps it typing.
        private static func typeSpaceIntoField(_ event: NSEvent) -> Bool {
            guard event.keyCode == 49,
                  MacKeys.modifiers(from: event.modifierFlags).isDisjoint(with: [.command, .control, .alternate]),
                  let field = event.window?.firstResponder as? NSText else { return false }
            field.keyDown(with: event)
            return true
        }

        /// True when the press was the editor's.
        private func handleKey(_ event: NSEvent) -> Bool {
            guard let studio, let window, event.window === window else { return false }
            // Typing into the song name, a track name, or a sheet's field.
            if window.firstResponder is NSText { return false }

            let usage = MacKeys.usage(forKeyCode: event.keyCode)
            let modifiers = MacKeys.modifiers(from: event.modifierFlags)
            let action: KeyAction?
            if window.attachedSheet != nil {
                action = KeyAction.forPresentedKey(usage: usage, modifiers: modifiers)
            } else {
                action = KeyAction.forKey(usage: usage,
                                          characters: event.charactersIgnoringModifiers ?? "",
                                          modifiers: modifiers,
                                          octave: studio.octave)
            }
            guard let action else { return false }
            // The Mac repeats a held key itself, at the rate set in System
            // Settings, so there is no `KeyRepeater` here; only the keys that
            // repeat on the iPad (the arrows) act on a repeat. A held letter
            // or Space is still claimed, so it doesn't beep.
            if !event.isARepeat || KeyRepeat.repeats(action) {
                studio.apply(action)
            }
            return true
        }

        /// A click anywhere but a text field ends typing into one, as it does
        /// in any Mac app, and gives first responder back to this view.
        /// SwiftUI's fields otherwise keep the keyboard after a click on the
        /// grid, and the next note typed lands in the name.
        private func endTextEditingIfClickedAway(_ event: NSEvent) {
            guard let window, event.window === window,
                  window.firstResponder is NSText,
                  let content = window.contentView else { return }
            let point = content.convert(event.locationInWindow, from: nil)
            var hit = content.hitTest(point)
            while let view = hit {
                if view is NSTextField || view is NSText { return }
                hit = view.superview
            }
            // After the click is delivered, so a control under it still sees
            // the field's last edit committed rather than mid-flight.
            DispatchQueue.main.async { [weak self] in window.makeFirstResponder(self) }
        }
    }
}

/// The iOS catcher has to take first responder back from a song name field
/// that SwiftUI let go of but never resigned. The Mac's catcher doesn't hold
/// first responder at all, and AppKit does resign a field when its
/// `@FocusState` goes false, so there is nothing to reclaim.
enum HardwareKeyCapture {
    @MainActor
    static func reclaim() {}
}
#endif
