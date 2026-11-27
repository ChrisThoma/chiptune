#if os(macOS)
import SwiftUI

/// The Mac window's sizes, and the layout a size gets.
///
/// A Mac window is laid out as a landscape iPad's: the iPad's metrics, the
/// grid on the left and the keys with the docked sound controls in a column
/// on the right. Pointer and keyboard make the iPad's touch-sized targets
/// roomy rather than wrong, and one set of metrics keeps the two platforms'
/// layout code the same code.
enum MacWindow {
    /// The environment's size class is meaningless on a Mac window, so it
    /// isn't read; every Mac window is regular.
    static let sizeClass: UserInterfaceSizeClass = .regular

    /// Wide enough for the side arrangement (`ChipLayout.minimumSideBySideWidth`
    /// is 910) with a little grid to spare, and tall enough for eight grid
    /// rows beside the keys and the docked sound controls.
    static let minimumSize = CGSize(width: 960, height: 720)

    /// Opens with room for five tracks at the iPad's column width. Under
    /// the two-octave threshold (1358), which is kept for a window someone
    /// made large on purpose.
    static let defaultSize = CGSize(width: 1240, height: 800)

    static func layout(for size: CGSize) -> ChipLayout {
        ChipLayout.resolve(size: size, horizontalSizeClass: sizeClass)
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
