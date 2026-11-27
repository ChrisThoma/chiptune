import SwiftUI

/// The Mac menu bar's commands, in one list: the chord, the title, and (in
/// `MacMenuState`) when each is enabled. iOS keeps `EditorShortcut`; the Mac
/// moves a few chords to where a Mac user looks for them (⌘O opens a file,
/// ⌘⇧S saves a copy), so it has a list of its own. Pure, so the chords and
/// the enabled rules are tested without a menu bar.
enum MacMenuCommand: CaseIterable {
    // File
    case newSong, open, songs, duplicateSong, exportSong, exportMedia
    // Edit
    case undo, redo
    // Pattern
    case newPattern, arrangement, clearPattern
    // Playback
    case playStop, patternMode, songMode
    // Help
    case help

    var key: KeyEquivalent {
        switch self {
        case .newSong, .newPattern: return "n"
        case .open, .songs: return "o"
        case .duplicateSong: return "d"
        case .exportSong: return "s"
        case .exportMedia: return "e"
        case .undo, .redo: return "z"
        case .arrangement: return "a"
        case .clearPattern: return .delete
        case .playStop: return .space
        case .patternMode: return "1"
        case .songMode: return "2"
        case .help: return "?"
        }
    }

    /// Command on every letter, for the same reason as `EditorShortcut`: the
    /// note row owns them unmodified. Play/Stop is the bare Space the editor
    /// already reads; the menu only shows it.
    var modifiers: EventModifiers {
        switch self {
        case .newSong, .open, .duplicateSong, .exportMedia, .undo, .clearPattern,
             .patternMode, .songMode, .help:
            return .command
        case .songs, .exportSong, .redo, .newPattern, .arrangement:
            return [.command, .shift]
        case .playStop:
            return []
        }
    }

    var title: String {
        switch self {
        case .newSong: return "New Song"
        case .open: return "Open…"
        case .songs: return "Songs…"
        case .duplicateSong: return "Duplicate Song"
        case .exportSong: return "Export Song…"
        case .exportMedia: return "Export Audio or Video…"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .newPattern: return "New Pattern"
        case .arrangement: return "Arrangement…"
        case .clearPattern: return "Clear Pattern…"
        case .playStop: return "Play/Stop"
        case .patternMode: return "Loop Pattern (PATT)"
        case .songMode: return "Play Song (SONG)"
        case .help: return "Chiptune Help"
        }
    }
}

/// What the menus are enabled from: a snapshot the editor publishes each
/// time any of it changes (see `MacEditorActions`).
struct MacMenuState: Equatable {
    var hasEditor: Bool
    /// False while a dialog, alert or sheet holds state about this song.
    var canChangeSong: Bool
    /// Anything is up over the editor: a sheet, popover or alert.
    var anyPresented: Bool
    var canUndo: Bool
    var canRedo: Bool
    /// A text field is being typed into.
    var textEditing: Bool

    /// Where ⌘Z goes. While a field is being typed into it is the field's
    /// undo, so a slip doesn't undo the last note behind the name being
    /// typed; otherwise the song's.
    enum UndoTarget: Equatable { case song, textField }
    var undoTarget: UndoTarget { textEditing ? .textField : .song }

    func isEnabled(_ command: MacMenuCommand) -> Bool {
        guard hasEditor else { return false }
        switch command {
        case .undo: return textEditing || (canChangeSong && canUndo)
        case .redo: return textEditing || (canChangeSong && canRedo)
        // The library and the export panel are built to survive the song
        // changing under them, as on iOS.
        case .newSong, .open, .duplicateSong, .exportSong, .newPattern, .clearPattern:
            return canChangeSong
        // A second presentation is ignored, and Space behind a sheet does
        // nothing on iOS.
        case .songs, .exportMedia, .arrangement, .help, .playStop, .patternMode, .songMode:
            return !anyPresented
        }
    }
}
