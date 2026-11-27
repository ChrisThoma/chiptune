#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What only the Mac's menus need from the editor, beside `EditorActions`:
/// the state the menu rows are enabled and checked from, and the screens
/// `EditorActions` has no way to open. Equatable on the snapshot, for the
/// reason `EditorActions` is: the commands re-read a scene value only when it
/// compares unequal.
struct MacEditorActions: Equatable {
    var state: MacMenuState
    var isPlaying: Bool
    var songMode: Bool
    let openGuide: () -> Void

    static func == (lhs: MacEditorActions, rhs: MacEditorActions) -> Bool {
        lhs.state == rhs.state && lhs.isPlaying == rhs.isPlaying && lhs.songMode == rhs.songMode
    }
}

private struct MacEditorActionsKey: FocusedValueKey {
    typealias Value = MacEditorActions
}

extension FocusedValues {
    var macEditor: MacEditorActions? {
        get { self[MacEditorActionsKey.self] }
        set { self[MacEditorActionsKey.self] = newValue }
    }
}

/// Whether a text field anywhere in the app is being typed into, kept live
/// for the menus (`MacMenuState.textEditing`). AppKit says so by making a
/// field editor (an `NSText`) the key window's first responder; it's
/// re-read whenever that could have changed.
@Observable
final class MacTextEditing {
    static let shared = MacTextEditing()

    private(set) var isEditing = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var responderObservation: NSKeyValueObservation?

    private init() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    /// Watches the editor's window, where focus moves between the song name,
    /// a track's name and the grid without any window changing key.
    func watch(_ window: NSWindow) {
        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    static var isEditingNow: Bool { NSApp.keyWindow?.firstResponder is NSText }

    private func refresh() {
        let now = Self.isEditingNow
        if now != isEditing { isEditing = now }
    }
}

/// The Mac menu bar. Replaces `EditorCommands` there: the same actions on
/// `EditorActions`, laid out in the menus a Mac app has, with the Mac's
/// chords (`MacMenuCommand`).
struct MacCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.macEditor) private var mac

    private var state: MacMenuState {
        mac?.state ?? MacMenuState(hasEditor: false, canChangeSong: false, anyPresented: false,
                                   canUndo: false, canRedo: false, textEditing: false)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Chiptune") { AboutPanel.show() }
        }
        CommandGroup(replacing: .newItem) {
            item(.newSong) { $0.studio.newSong() }
            item(.open) { MacFilePanels.open(into: $0.studio) }
            item(.songs) { $0.openSongs() }
            Divider()
            item(.duplicateSong) { $0.studio.duplicateSong() }
        }
        // Replacing the save group takes the system's Close with it, so it's
        // put back first.
        CommandGroup(replacing: .saveItem) {
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            item(.exportSong) { MacFilePanels.saveCopy(of: $0.studio) }
            item(.exportMedia) { $0.openExport() }
        }
        // Print has nothing to print.
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .undoRedo) {
            undoItem(.undo)
            undoItem(.redo)
        }
        CommandMenu("Pattern") {
            item(.newPattern) { _ = $0.studio.addPattern() }
            item(.arrangement) { $0.openArrangement() }
            Divider()
            item(.clearPattern) { $0.confirmClearPattern() }
        }
        CommandMenu("Playback") {
            item(.playStop, title: mac?.isPlaying == true ? "Stop" : "Play") { $0.studio.togglePlay() }
            Divider()
            modeItem(.patternMode, song: false)
            modeItem(.songMode, song: true)
        }
        CommandGroup(replacing: .help) {
            item(.help) { _ in mac?.openGuide() }
        }
    }

    private func item(_ command: MacMenuCommand, title: String? = nil,
                      action: @escaping (EditorActions) -> Void) -> some View {
        Button(title ?? command.title) {
            guard let editor else { return }
            // Song-changing commands check the live state as iOS's do; the
            // dimming reads a snapshot that can lag by a frame.
            if [.newSong, .open, .duplicateSong, .exportSong, .newPattern, .clearPattern].contains(command),
               !editor.canChangeSongNow() { return }
            editor.endRenaming()
            action(editor)
        }
        .keyboardShortcut(command.key, modifiers: command.modifiers)
        .disabled(!state.isEnabled(command))
    }

    /// ⌘Z goes to the field being typed into, if any, and to the song's
    /// history otherwise. Asked again at the moment it's chosen, since the
    /// snapshot the row was enabled from may predate a click into a field.
    private func undoItem(_ command: MacMenuCommand) -> some View {
        Button(command.title) {
            if MacTextEditing.isEditingNow {
                let selector = command == .undo ? Selector(("undo:")) : Selector(("redo:"))
                NSApp.sendAction(selector, to: nil, from: nil)
                return
            }
            guard let editor, editor.canChangeSongNow() else { return }
            editor.endRenaming()
            if command == .undo { editor.studio.undo() } else { editor.studio.redo() }
        }
        .keyboardShortcut(command.key, modifiers: command.modifiers)
        .disabled(!state.isEnabled(command))
    }

    /// PATT and SONG, the transport's two modes, with a check on the current
    /// one.
    private func modeItem(_ command: MacMenuCommand, song: Bool) -> some View {
        Toggle(command.title, isOn: Binding(
            get: { mac?.songMode == song },
            set: { _ in editor?.studio.setSongMode(song) }))
            .keyboardShortcut(command.key, modifiers: command.modifiers)
            .disabled(!state.isEnabled(command))
    }
}

/// File > Open… and File > Export Song…, the Mac's file panels for a
/// `.chipsong`. Both go through the paths iOS uses: `importSong(from:)`, and
/// the same document `share` writes.
enum MacFilePanels {
    @MainActor
    static func open(into studio: Studio) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SongDocument.contentType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            studio.importSong(from: url)
        }
    }

    @MainActor
    static func saveCopy(of studio: Studio) {
        let file: URL
        do {
            file = try SongDocument.write(studio.song)
        } catch {
            studio.shareError = ShareFailureMessage.songFile(name: studio.song.name, error: error)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SongDocument.contentType]
        panel.nameFieldStringValue = ExportDestination.suggestedName(for: file)
        panel.directoryURL = ExportDestination.directory(for: file)
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try ExportDestination.copy(file, to: destination)
            } catch {
                studio.shareError = ShareFailureMessage.songFile(name: studio.song.name, error: error)
            }
        }
    }
}
#endif
