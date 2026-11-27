import AppKit
import SwiftUI

/// The Mac app's entry point. The same root view as the iPhone and iPad
/// (`AppRoot`) in a single window: one studio is one song being edited, so a
/// second window would only be a second view of the same document.
@main
struct ChiptuneMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var studio: Studio?
    @State private var pendingImport: URL?

    init() {
        // One window, so no tabs and no Show Tab Bar in the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        guard !AppRoot.isTestHost else { return }
        DispatchQueue.global(qos: .utility).async { ExportFiles.sweep() }
    }

    var body: some Scene {
        Window("Chiptune", id: "editor") {
            AppRoot(studio: $studio, pendingImport: $pendingImport, scenePhase: scenePhase)
                .frame(minWidth: MacWindow.minimumSize.width,
                       minHeight: MacWindow.minimumSize.height)
                .background(WindowFrameKeeper())
                .onChange(of: studio != nil) { _, _ in appDelegate.studio = studio }
        }
        .defaultSize(MacWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .commands { MacCommands() }
    }
}

/// Quitting when the window closes, and saving on the way out.
///
/// Quit on close rather than staying open with no window: this is a
/// single-window app whose window *is* the song being played, like
/// Calculator or Photo Booth. Left running windowless, a playing song would
/// keep sounding with nothing on screen to stop it from, and the only way
/// back would be the Dock.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var studio: Studio?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A quit doesn't reliably pass through a scene phase the editor saves
    /// on, and autosave is debounced, so the last edit is written here.
    func applicationWillTerminate(_ notification: Notification) {
        _ = studio?.saveNow()
    }
}
