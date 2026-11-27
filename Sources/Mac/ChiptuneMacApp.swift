import SwiftUI

/// The Mac app's entry point. The same root view as the iPhone and iPad
/// (`AppRoot`) in a single window: one studio is one song being edited, so a
/// second window would only be a second view of the same document.
@main
struct ChiptuneMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var studio: Studio?
    @State private var pendingImport: URL?

    init() {
        guard !AppRoot.isTestHost else { return }
        DispatchQueue.global(qos: .utility).async { ExportFiles.sweep() }
    }

    var body: some Scene {
        Window("Chiptune", id: "editor") {
            AppRoot(studio: $studio, pendingImport: $pendingImport, scenePhase: scenePhase)
                .frame(minWidth: MacWindow.minimumSize.width,
                       minHeight: MacWindow.minimumSize.height)
        }
        .defaultSize(MacWindow.defaultSize)
        .windowResizability(.contentMinSize)
        .commands { EditorCommands() }
    }
}
