import SwiftUI

/// The app's Command-key chords, in one list.
///
/// Each chord has exactly one home. A `.keyboardShortcut` on a `Menu` row
/// doesn't fire app-wide on iOS, and a chord registered both here and on a
/// visible button appears twice in the Cmd-hold overlay — so the `…` menu rows
/// and the title-bar buttons deliberately carry no modifiers, and this enum is
/// the only place a chord is written down. The tests read it to check that no
/// two actions collide and that nothing lands on a bare note-row letter.
enum EditorShortcut: CaseIterable {
    case undo
    case redo
    case newSong
    case songs
    case duplicateSong
    case exportWAV
    case shareSong
    case newPattern
    case arrangement
    case clearPattern

    var key: KeyEquivalent {
        switch self {
        case .undo, .redo: return "z"
        case .newSong, .newPattern: return "n"
        case .songs: return "o"
        case .duplicateSong: return "d"
        case .exportWAV: return "e"
        case .shareSong: return "s"
        case .arrangement: return "a"
        case .clearPattern: return .delete
        }
    }

    /// Command on every one of them: the note row owns A through K
    /// unmodified, and Command is also what tells `KeyAction.forKey` to pass
    /// the press on up the responder chain instead of typing it into the
    /// pattern.
    var modifiers: EventModifiers {
        switch self {
        case .undo, .newSong, .songs, .duplicateSong, .exportWAV, .clearPattern:
            return .command
        // Cmd+Shift+A can't be exercised in the Simulator: the Simulator app
        // itself owns it (Features > Toggle Appearance) and swallows it before
        // iPadOS sees it, as it does Cmd+R, Cmd+S, Cmd+W, Cmd+L, Cmd+K and
        // Cmd+1–4. It isn't a system chord on iPadOS, so it's the right one on
        // a device; Cmd+Shift+N, registered identically here, is the proof the
        // path works.
        case .redo, .shareSong, .newPattern, .arrangement:
            return [.command, .shift]
        }
    }

    /// What the Cmd-hold overlay shows. Named after the action rather than the
    /// screen it opens, so the overlay reads as a list of things you can do.
    var title: String {
        switch self {
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .newSong: return "New Song"
        case .songs: return "Songs"
        case .duplicateSong: return "Duplicate Song"
        case .exportWAV: return "Export WAV"
        case .shareSong: return "Share Song File"
        case .newPattern: return "New Pattern"
        case .arrangement: return "Arrangement"
        case .clearPattern: return "Clear Pattern"
        }
    }
}

/// Whether a command may open a screen right now.
///
/// Commands keep firing while a sheet is up — unlike the grid's key catcher,
/// which resigns first responder for the duration. iOS answers a request to
/// present a second thing with silence, so Cmd+E behind the Arrangement sheet
/// would set `showingExport` and leave it set, and the export sheet would then
/// appear unbidden the next time something else dismissed. Pure so the rule is
/// testable without a window.
enum EditorPresentation {
    static func canOpen(anyPresented: Bool) -> Bool { !anyPresented }
}

/// What the commands act on: the studio plus the bits of editor state that
/// only `ContentView` holds.
///
/// Published as a *scene* value rather than a focused one because this editor
/// never gives SwiftUI focus to anything — nothing in the grid or the chrome
/// is a focusable control — and a plain focused value would be nil forever.
/// Equatable on the studio's identity alone: the closures can't be compared,
/// and a rebuilt set of closures over the same studio is the same editor.
struct EditorActions: Equatable {
    let studio: Studio
    let endRenaming: () -> Void
    let openSongs: () -> Void
    let openArrangement: () -> Void
    let openExport: () -> Void
    let confirmClearPattern: () -> Void

    static func == (lhs: EditorActions, rhs: EditorActions) -> Bool {
        lhs.studio === rhs.studio
    }
}

private struct EditorActionsKey: FocusedValueKey {
    typealias Value = EditorActions
}

extension FocusedValues {
    var editor: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

/// The app-wide chords. Attached to the `WindowGroup`, so they work with no
/// view focused and show up in the Cmd-hold overlay.
struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        // The app has its own `UndoHistory`, not an `UndoManager`, so the
        // system's undo group has nothing to drive and has to be replaced.
        // Accepted side effect: Cmd+Z inside the song-name field runs the
        // app's undo, which is what the title bar's undo button does too.
        CommandGroup(replacing: .undoRedo) {
            button(.undo) { $0.studio.undo() }
            button(.redo) { $0.studio.redo() }
        }
        CommandGroup(replacing: .newItem) {
            button(.newSong) { $0.studio.newSong() }
            button(.songs) { $0.openSongs() }
            button(.duplicateSong) { $0.studio.duplicateSong() }
        }
        CommandGroup(after: .importExport) {
            button(.exportWAV) { $0.openExport() }
            button(.shareSong) { $0.studio.share($0.studio.song) }
        }
        CommandMenu("Pattern") {
            button(.newPattern) { $0.studio.addPattern() }
            button(.arrangement) { $0.openArrangement() }
            button(.clearPattern) { $0.confirmClearPattern() }
        }
    }

    /// One command row. The optional is unwrapped inside the action rather
    /// than around the row: a `CommandsBuilder` has no `if let`, and
    /// `Commands.body` isn't guaranteed to re-evaluate when an `@Observable`
    /// changes, so `.disabled` here is a hint to the overlay and never the
    /// thing that keeps an action safe. Every action below no-ops or guards on
    /// its own.
    private func button(_ shortcut: EditorShortcut,
                        action: @escaping (EditorActions) -> Void) -> some View {
        Button(shortcut.title) {
            guard let editor else { return }
            // Same as every button in the chrome: commit whatever is in the
            // song-name field first, so the action lands on the state the user
            // can see rather than on one still being typed.
            editor.endRenaming()
            action(editor)
        }
        .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        .disabled(editor == nil)
    }
}

/// The keys that work without a modifier, listed for the `…` menu.
///
/// The Cmd-hold overlay can only show chords, so the half of the keyboard that
/// matters most while writing a part — space, the arrows, the note row — is
/// invisible there. This is that half, written out.
enum UnmodifiedKeyHelp {
    struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    static let rows: [Row] = [
        Row(keys: "Space", action: "Play or stop"),
        Row(keys: "← → ↑ ↓", action: "Move the cursor"),
        Row(keys: "A W S E D F T G Y H U J K", action: "Type a note, C upwards"),
        Row(keys: "Z / X", action: "Octave down or up"),
        Row(keys: "Return", action: "Type the selected note"),
        Row(keys: "\\", action: "Arm or disarm a note off"),
        Row(keys: "Delete", action: "Clear the step"),
    ]
}

/// The list above, as a popover on iPad and a sheet on a phone.
struct KeyboardHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KEYBOARD")
                .chipFont(11, weight: .bold)
                .foregroundStyle(Theme.dim)
                .tracking(2)

            ForEach(UnmodifiedKeyHelp.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.keys)
                        .chipFont(13, weight: .bold)
                        .foregroundStyle(Theme.text)
                    Text(row.action)
                        .chipFont(12)
                        .foregroundStyle(Theme.dim)
                }
                .accessibilityElement(children: .combine)
            }

            Text("Hold Command for the rest.")
                .chipFont(12)
                .foregroundStyle(Theme.dim)
        }
        .padding(20)
        // The ideal width is what the popover sizes itself from; the maximum
        // is what lets the phone's sheet fill the screen instead.
        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationCompactAdaptation(.sheet)
        .preferredColorScheme(.dark)
    }
}
