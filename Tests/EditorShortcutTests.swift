import XCTest
import SwiftUI
import UIKit
@testable import Chiptune

/// The Command-key chords, checked against the two things that can silently
/// break them.
///
/// The first is collision: a chord registered twice fires whichever command
/// SwiftUI happens to reach first, and the Cmd-hold overlay lists it twice.
/// The second is the letter row — `KeyAction` claims A through K as notes, so
/// a shortcut that arrived without a modifier would be typing a C sharp into
/// the pattern instead of duplicating the song. Both are invisible on the
/// device you tried and wrong everywhere else, so they're pinned here rather
/// than left to a keyboard being plugged in.
final class EditorShortcutTests: XCTestCase {

    /// How the same press looks to the responder chain, which is where the
    /// letter row reads it.
    private func uiModifiers(_ modifiers: EventModifiers) -> UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    func testEveryChordIsUsedOnce() {
        var seen: [String: String] = [:]
        for shortcut in EditorShortcut.allCases {
            let chord = "\(shortcut.modifiers.rawValue)-\(shortcut.key.character)"
            XCTAssertNil(seen[chord],
                         "\(shortcut.title) uses the same chord as \(seen[chord] ?? "")")
            seen[chord] = shortcut.title
        }
        XCTAssertEqual(seen.count, EditorShortcut.allCases.count)
    }

    /// The commands and the note row share a keyboard: the grid's catcher sees
    /// every press first and has to hand the modified ones back up the chain.
    func testNoCommandChordIsClaimedByTheNoteRow() {
        for shortcut in EditorShortcut.allCases {
            let characters = String(shortcut.key.character)
            // Command is always part of the press being asked about, whether
            // or not the shortcut itself carries it: Escape's partner chord is
            // Cmd+., so it reaches the editor modified too.
            var modifiers = uiModifiers(shortcut.modifiers)
            modifiers.insert(.command)
            XCTAssertNil(KeyAction.forKey(usage: .keyboardErrorUndefined,
                                          characters: characters,
                                          modifiers: modifiers,
                                          octave: 5),
                         "\(shortcut.title) would be swallowed by the editor")
            // Cmd+Backspace's usage is the one the editor otherwise claims for
            // clearing a cell, so it's worth asking in those terms too.
            XCTAssertNil(KeyAction.forKey(usage: .keyboardDeleteOrBackspace,
                                          characters: characters,
                                          modifiers: modifiers,
                                          octave: 5),
                         "\(shortcut.title) would clear the cell under the cursor")
        }
    }

    /// Every shortcut on a letter carries Command. Without it a chord on a
    /// letter the note row owns would be unreachable as a shortcut and
    /// destructive as a note. Escape is the one bare key, and the editor has
    /// never claimed it.
    func testNoShortcutIsABareNoteRowLetter() {
        for shortcut in EditorShortcut.allCases {
            let character = Character(String(shortcut.key.character).lowercased())
            guard character.isLetter else {
                XCTAssertNil(NoteKeys.semitones[character],
                             "\(shortcut.title) sits on the note key \(character)")
                continue
            }
            XCTAssertTrue(shortcut.modifiers.contains(.command),
                          "\(shortcut.title) is the bare note key \(character)")
        }
    }

    /// Commands keep firing while a sheet is up, unlike the key catcher. iOS
    /// answers a second presentation request with nothing at all, so Cmd+E
    /// behind the Arrangement sheet has to be dropped rather than queued.
    func testPresentationCommandsAreRefusedWhileSomethingIsPresented() {
        XCTAssertTrue(EditorPresentation.canOpen(anyPresented: false))
        XCTAssertFalse(EditorPresentation.canOpen(anyPresented: true))
    }
}
