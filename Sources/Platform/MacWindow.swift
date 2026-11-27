#if os(macOS)
import SwiftUI

/// The Mac window's sizes, and the layout a size gets.
///
/// The iPad's metrics, arranged for a desk rather than a lap: the grid top
/// left, the selected track's sound controls in a column to its right, and a
/// piano across the whole bottom of the window with its octave, KEY, note
/// and REST row directly above the keys. A Mac window is wide and its keys
/// are clicked, not thumbed, so the keyboard can be the instrument-sized
/// strip a desktop music app has rather than a column's worth of keys.
enum MacWindow {
    /// The environment's size class is meaningless on a Mac window, so it
    /// isn't read; every Mac window is regular.
    static let sizeClass: UserInterfaceSizeClass = .regular

    /// White key height. 170pt reads as a keyboard (at the narrowest
    /// two-octave key it is 2.7 times as tall as it is wide, a desktop MIDI
    /// controller's proportion) and is the most the minimum window can spend
    /// on keys while keeping six grid rows within a 13-inch MacBook Air's
    /// usable height at its default resolution, about 900pt.
    static let keyHeight: CGFloat = 170

    /// The narrowest a white key gets in the two-octave keyboard. At 64pt the
    /// root key's double-size label ("C4") still fits with room either side,
    /// and a black key (0.58 of a white) is 37pt, a comfortable click. It is
    /// also what leaves a one-octave band at all: at 56 the threshold falls
    /// under the minimum window width, so every window would show two
    /// octaves of narrower keys.
    static let minimumWhiteKeyWidth: CGFloat = 64

    /// Fifteen white keys (C to C) at the minimum width, the fourteen gaps
    /// between them and the keyboard's inset: 1008pt.
    static var twoOctaveMinimumWidth: CGFloat {
        15 * minimumWhiteKeyWidth + 14 * ChipLayout.whiteKeySpacing
            + 2 * ChipLayout.keyboardHorizontalPadding
    }

    /// The sound controls' column beside the grid; the iPad's keyboard
    /// column width, which the controls were laid out for.
    static let soundColumnWidth: CGFloat = ChipLayout.sideKeyboardWidth

    /// Every track column's width, at any window size. The iPad's column
    /// floor (`ChipLayout.pad.gridMinColumnWidth`): the width an iPad grid
    /// already draws at once its tracks overflow, and half again the
    /// phone's 70, so the widest label (a sharp with an effect mark) fits at
    /// full size with room to spare. A wider window leaves background after
    /// the + column rather than stretching a part across it.
    static let trackColumnWidth: CGFloat = ChipLayout.pad.gridMinColumnWidth

    /// Everything the bottom keyboard takes: the rule above it (1), the gap
    /// (10), the control row (44), the gap to the keys (8), the keys, and
    /// the space under them (6 inside KeyboardView, 4 outside). Measured
    /// against the running app, like `ChipLayout.chromeHeight`.
    static var bottomKeysHeight: CGFloat { 1 + 10 + 44 + 8 + keyHeight + 6 + 4 }

    /// Wide enough for the grid beside the sound column
    /// (`ChipLayout.minimumSideBySideWidth` is 910), tall enough for six
    /// grid rows above the keyboard.
    static let minimumSize = CGSize(width: 960, height: 860)

    /// Opens with two octaves, five tracks at the iPad's column width, and
    /// a row or so more than the minimum.
    static let defaultSize = CGSize(width: 1280, height: 900)

    static func layout(for size: CGSize) -> ChipLayout {
        var layout = ChipLayout.pad
        layout.usesSideKeyboard = true
        layout.keysAlongBottom = true
        layout.sideColumnWidth = soundColumnWidth
        layout.keyboardMaxWidth = .infinity
        layout.keyboardHeight = keyHeight
        layout.keyboardOctaves = size.width >= twoOctaveMinimumWidth ? 2 : 1
        layout.keysMaxWidth = layout.keyboardOctaves >= 2 ? .infinity : oneOctaveKeysWidth
        layout.gridMinColumnWidth = trackColumnWidth
        layout.fixedColumnWidth = trackColumnWidth
        return layout
    }

    /// Where the keyboard sits in a window of this size: the full width,
    /// flush with the bottom.
    static func keyboardFrame(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: size.height - bottomKeysHeight, width: size.width, height: bottomKeysHeight)
    }

    /// One octave's keys (eight white) at `minimumWhiteKeyWidth`: 526pt.
    /// Below the two-octave threshold the keys stop here and centre, rather
    /// than stretching eight white keys to nearly twice the width they had
    /// a few points wider, where the second octave appears.
    static var oneOctaveKeysWidth: CGFloat {
        8 * minimumWhiteKeyWidth + 7 * ChipLayout.whiteKeySpacing
    }

    /// The keys themselves within the window: the keyboard's inset width
    /// with two octaves, `oneOctaveKeysWidth` centred with one, and 10pt
    /// above the window's bottom edge (6 inside KeyboardView, 4 outside).
    static func keysFrame(in size: CGSize) -> CGRect {
        let inset = size.width - 2 * ChipLayout.keyboardHorizontalPadding
        let width = layout(for: size).keyboardOctaves >= 2 ? inset : min(inset, oneOctaveKeysWidth)
        return CGRect(x: (size.width - width) / 2, y: size.height - 10 - keyHeight,
                      width: width, height: keyHeight)
    }

    /// Grid rows that fit above the keyboard: what's left after the chrome,
    /// the track headers (and the gap under them) and the keyboard, in rows
    /// with their 2pt gap.
    static func gridRows(in size: CGSize) -> CGFloat {
        let layout = layout(for: size)
        let fixed = layout.chromeHeight + layout.trackHeaderHeight + 7 + bottomKeysHeight
        return (size.height - fixed) / (layout.gridRowHeight + 2)
    }
}

/// Puts the window back where it was and at the size it was. SwiftUI's own
/// window restoration is part of macOS state restoration, which the default
/// "Close windows when quitting an application" setting turns off, so the
/// window opened at `defaultSize` in the corner after every quit. An AppKit
/// frame autosave doesn't depend on that setting.
struct WindowFrameKeeper: NSViewRepresentable {
    static let autosaveName = "ChiptuneEditorWindow"

    func makeNSView(context: Context) -> NSView { KeeperView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class KeeperView: NSView {
        private var attached = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !attached else { return }
            attached = true
            // After SwiftUI has applied its default size, or it would win.
            DispatchQueue.main.async {
                window.setFrameUsingName(WindowFrameKeeper.autosaveName)
                window.setFrameAutosaveName(WindowFrameKeeper.autosaveName)
            }
        }
    }
}
#endif
