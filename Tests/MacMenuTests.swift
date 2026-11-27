import SwiftUI
import XCTest
@testable import Chiptune

/// The Mac menu bar's commands: their chords, and when each is enabled. The
/// menus themselves are SwiftUI `Commands` and can't be opened from a unit
/// test; these are the decisions they are built from.
final class MacMenuTests: XCTestCase {

    private func chord(_ command: MacMenuCommand) -> String {
        "\(command.modifiers.rawValue)-\(command.key.character)"
    }

    func testEveryChordIsUsedOnce() {
        var seen: [String: MacMenuCommand] = [:]
        for command in MacMenuCommand.allCases {
            XCTAssertNil(seen[chord(command)], "\(command) and \(seen[chord(command)].map { "\($0)" } ?? "") share a chord")
            seen[chord(command)] = command
        }
    }

    /// The note row owns the letters unmodified, so every letter chord has
    /// Command, and the editor's key catcher hands every Command press on to
    /// the menus.
    func testEveryLetterChordCarriesCommandAndIsLeftForTheMenus() {
        for command in MacMenuCommand.allCases where command.key.character.isLetter {
            XCTAssertTrue(command.modifiers.contains(.command), "\(command)")
            XCTAssertNil(KeyAction.forKey(usage: .keyboardErrorUndefined,
                                          characters: String(command.key.character),
                                          modifiers: [.command], octave: 5),
                         "The editor would swallow \(command)")
        }
    }

    /// The chords the Mac's own menus keep: Close, Quit, Hide, Minimize,
    /// Settings and Select All.
    func testNoChordTakesOneTheSystemMenusKeep() {
        let system: Set<String> = ["w", "q", "h", "m", ",", "a", "c", "v", "x"]
        for command in MacMenuCommand.allCases where command.modifiers == .command {
            XCTAssertFalse(system.contains(String(command.key.character)), "\(command)")
        }
    }

    /// Play/Stop shows Space, which is the key the editor already reads for
    /// it, unmodified.
    func testPlayStopIsTheBareSpaceTheEditorAlreadyReads() {
        XCTAssertEqual(MacMenuCommand.playStop.key, .space)
        XCTAssertEqual(MacMenuCommand.playStop.modifiers, [])
        XCTAssertEqual(KeyAction.forKey(usage: .keyboardSpacebar, characters: " ",
                                        modifiers: [], octave: 5), .togglePlay)
    }

    func testTheFileChordsAreTheMacOnes() {
        XCTAssertEqual(chord(.open), chord(of: "o", .command))
        XCTAssertEqual(chord(.newSong), chord(of: "n", .command))
        XCTAssertEqual(chord(.exportSong), chord(of: "s", [.command, .shift]))
        XCTAssertEqual(chord(.undo), chord(of: "z", .command))
        XCTAssertEqual(chord(.redo), chord(of: "z", [.command, .shift]))
    }

    private func chord(of key: Character, _ modifiers: EventModifiers) -> String {
        "\(modifiers.rawValue)-\(key)"
    }

    // MARK: Enabled

    private var idle: MacMenuState {
        MacMenuState(hasEditor: true, canChangeSong: true, anyPresented: false,
                     canUndo: true, canRedo: true, textEditing: false)
    }

    func testEverythingIsEnabledInAnIdleEditor() {
        for command in MacMenuCommand.allCases {
            XCTAssertTrue(idle.isEnabled(command), "\(command)")
        }
    }

    func testNothingIsEnabledWithNoEditor() {
        var state = idle
        state.hasEditor = false
        for command in MacMenuCommand.allCases {
            XCTAssertFalse(state.isEnabled(command), "\(command)")
        }
    }

    /// Undo and Redo follow the song's history.
    func testUndoAndRedoFollowTheHistory() {
        var state = idle
        state.canUndo = false
        XCTAssertFalse(state.isEnabled(.undo))
        XCTAssertTrue(state.isEnabled(.redo))
        state.canRedo = false
        XCTAssertFalse(state.isEnabled(.redo))
    }

    /// While a text field is being typed into, Undo is the field's own,
    /// whatever the song's history says, and it goes to the field.
    func testWhileTypingUndoBelongsToTheTextField() {
        var state = idle
        state.canUndo = false
        state.canRedo = false
        state.textEditing = true
        XCTAssertTrue(state.isEnabled(.undo))
        XCTAssertTrue(state.isEnabled(.redo))
        XCTAssertEqual(state.undoTarget, .textField)
        XCTAssertEqual(idle.undoTarget, .song)
    }

    /// A dialog holding state about the song dims every command that would
    /// change the song, as on iOS.
    func testADialogAboutTheSongDimsTheSongChangingCommands() {
        var state = idle
        state.canChangeSong = false
        for command in [MacMenuCommand.newSong, .open, .duplicateSong, .exportSong,
                        .newPattern, .clearPattern, .undo, .redo] {
            XCTAssertFalse(state.isEnabled(command), "\(command)")
        }
    }

    /// Anything up over the editor dims the commands that open a screen or
    /// drive playback: iOS ignores a second presentation, and Space behind a
    /// sheet does nothing there either.
    func testAnythingPresentedDimsTheScreensAndPlayback() {
        var state = idle
        state.anyPresented = true
        for command in [MacMenuCommand.songs, .exportMedia, .arrangement, .help,
                        .playStop, .patternMode, .songMode] {
            XCTAssertFalse(state.isEnabled(command), "\(command)")
        }
        XCTAssertTrue(state.isEnabled(.newSong), "The library and export survive a song change")
    }
}
