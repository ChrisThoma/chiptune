import XCTest
import UIKit
@testable import Chiptune

/// Typing notes instead of tapping them out, and the cursor that says where
/// they land.
///
/// The cursor is the part with logic in it. It indexes into two collections
/// that move underneath it — a pattern can be shortened, a track deleted —
/// and every way of writing at it has to survive both, because "wrote a note
/// into a track that no longer exists" is a crash rather than a wrong note.
@MainActor
final class HardwareKeyTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Blank"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    // MARK: The note row

    /// The layout is the one every DAW uses, so the test states it in the same
    /// terms a person would: A is C, and the row climbs a full octave to K.
    func testTheNoteRowIsAPianoStartingAtC() {
        XCTAssertEqual(NoteKeys.note(for: "a", octave: 5), 60, "C4 is MIDI 60")
        XCTAssertEqual(NoteKeys.note(for: "w", octave: 5), 61)
        XCTAssertEqual(NoteKeys.note(for: "s", octave: 5), 62)
        XCTAssertEqual(NoteKeys.note(for: "k", octave: 5), 72, "K is the octave above A")
    }

    func testTheNoteRowIsCaseInsensitive() {
        XCTAssertEqual(NoteKeys.note(for: "A", octave: 5), NoteKeys.note(for: "a", octave: 5))
    }

    func testKeysOutsideTheRowWriteNothing() {
        for character in ["q", "r", "i", "o", "p", "l", "1", " ", "ñ"] {
            XCTAssertNil(NoteKeys.note(for: Character(character), octave: 5),
                         "\(character) is not part of the layout")
        }
    }

    /// The top of the row runs past MIDI 127 in the highest octave. Dropping
    /// the key is right; clamping would write a note the layout didn't mean.
    func testKeysPastTheTopOfMIDIAreDroppedRatherThanClamped() {
        XCTAssertEqual(NoteKeys.note(for: "a", octave: 10), 120)
        XCTAssertNil(NoteKeys.note(for: "k", octave: 10), "120 + 12 is past 127")
    }

    // MARK: What a press means

    private func action(_ usage: UIKeyboardHIDUsage = .keyboardErrorUndefined,
                        characters: String = "",
                        modifiers: UIKeyModifierFlags = [],
                        octave: Int = 5) -> KeyAction? {
        KeyAction.forKey(usage: usage, characters: characters,
                         modifiers: modifiers, octave: octave)
    }

    func testTheTransportAndCursorKeys() {
        XCTAssertEqual(action(.keyboardSpacebar), .togglePlay)
        XCTAssertEqual(action(.keyboardUpArrow), .move(track: 0, step: -1))
        XCTAssertEqual(action(.keyboardDownArrow), .move(track: 0, step: 1))
        XCTAssertEqual(action(.keyboardLeftArrow), .move(track: -1, step: 0))
        XCTAssertEqual(action(.keyboardRightArrow), .move(track: 1, step: 0))
    }

    /// A keyboard with a full-size delete key sends the forward one, and
    /// nobody pressing it expects to have to know that.
    func testBothDeleteKeysClear() {
        XCTAssertEqual(action(.keyboardDeleteOrBackspace), .clear)
        XCTAssertEqual(action(.keyboardDeleteForward), .clear)
    }

    /// The letter row has no key for a note off, so return writes whatever the
    /// on-screen keyboard is holding — which is where a note off is selected.
    func testReturnWritesTheSelectedNote() {
        XCTAssertEqual(action(.keyboardReturnOrEnter), .typeSelected)
        XCTAssertEqual(action(.keypadEnter), .typeSelected)
    }

    func testLettersWriteNotesAtTheCurrentOctave() {
        XCTAssertEqual(action(characters: "a", octave: 5), .type(60))
        XCTAssertEqual(action(characters: "a", octave: 6), .type(72))
        XCTAssertEqual(action(characters: "z"), .octave(-1))
        XCTAssertEqual(action(characters: "x"), .octave(1))
    }

    /// Command and control belong to the system and to menu shortcuts. A
    /// letter row that swallowed Cmd-A would break every one of them.
    func testModifiedPressesAreLeftToTheSystem() {
        XCTAssertNil(action(characters: "a", modifiers: .command))
        XCTAssertNil(action(.keyboardSpacebar, modifiers: .control))
        XCTAssertNil(action(characters: "a", modifiers: .alternate))
        // Shift is how a capital arrives, and the row doesn't care about case.
        XCTAssertEqual(action(characters: "A", modifiers: .shift), .type(60))
    }

    func testKeysTheEditorDoesntClaimArePassedOn() {
        XCTAssertNil(action(characters: "q"))
        XCTAssertNil(action(.keyboardTab))
        XCTAssertNil(action(.keyboardEscape))
    }

    // MARK: The cursor

    func testArrowsStopAtTheEdgesRatherThanWrapping() {
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.moveCursor(track: -1, step: -1)
        XCTAssertEqual(studio.selectedTrack, 0)
        XCTAssertEqual(studio.selectedStep, 0)

        studio.selectedTrack = studio.song.tracks.count - 1
        studio.selectedStep = studio.patternLength - 1
        studio.moveCursor(track: 1, step: 1)
        XCTAssertEqual(studio.selectedTrack, studio.song.tracks.count - 1)
        XCTAssertEqual(studio.selectedStep, studio.patternLength - 1)
    }

    /// Typing wraps where the arrows don't: filling a pattern in runs off the
    /// end of it, and stopping dead on the last step means reaching for the
    /// mouse to carry on.
    func testTypingAdvancesTheCursorAndWrapsAtTheEndOfThePattern() {
        studio.selectedStep = 0
        studio.typeNote(60)
        XCTAssertEqual(studio.selectedStep, 1)

        studio.selectedStep = studio.patternLength - 1
        studio.typeNote(62)
        XCTAssertEqual(studio.selectedStep, 0, "The next note goes at the top again")
    }

    func testTypingWritesTheNoteAndPointsTheOnScreenKeyboardAtIt() {
        studio.selectedTrack = 1
        studio.selectedStep = 4
        studio.typeNote(67)
        XCTAssertEqual(studio.note(track: 1, step: 4), 67)
        XCTAssertEqual(studio.selectedNote, 67,
                       "The note row and the on-screen keys are one selection")
    }

    func testDeleteEmptiesTheCellAndCarriesOnDownTheTrack() {
        studio.selectedStep = 2
        studio.typeNote(60)
        studio.selectedStep = 2
        studio.clearAtCursor()
        XCTAssertEqual(studio.note(track: 0, step: 2), Chip.emptyNote)
        XCTAssertEqual(studio.selectedStep, 3)
    }

    func testTypingIsUndoable() {
        studio.selectedStep = 0
        studio.typeNote(60)
        XCTAssertTrue(studio.canUndo)
        studio.undo()
        XCTAssertEqual(studio.note(track: 0, step: 0), Chip.emptyNote)
    }

    /// The pattern the cursor is in can be shortened out from under it, from
    /// the STEPS stepper or by opening another song. Writing at a cursor past
    /// the end would be a note nobody can see, or an index nobody can hold.
    func testAShortenedPatternPullsTheCursorBackInside() {
        studio.setPatternLength(64)
        studio.selectedStep = 60
        studio.setPatternLength(16)
        studio.typeNote(60)
        XCTAssertLessThan(studio.selectedStep, studio.patternLength)
        XCTAssertEqual(studio.note(track: 0, step: 15), 60,
                       "The note lands on the last step that still exists")
    }

    func testADeletedTrackPullsTheCursorBackInside() {
        studio.selectedTrack = studio.song.tracks.count - 1
        studio.removeTrack(at: studio.song.tracks.count - 1)
        studio.typeNote(60)
        XCTAssertLessThan(studio.selectedTrack, studio.song.tracks.count)
    }

    // MARK: The cursor's visibility

    /// The grid draws no cursor until a key has moved it: on a touch-only iPad
    /// nothing does, and a ringed cell would read as a selection nobody made.
    func testTheCursorStaysHiddenUntilAKeyIsPressed() {
        XCTAssertFalse(studio.hardwareKeyboardInUse)
        studio.placeCursor(track: 2, step: 5)
        XCTAssertEqual(studio.selectedStep, 0, "A tap alone doesn't move a hidden cursor")

        studio.moveCursor(step: 1)
        XCTAssertTrue(studio.hardwareKeyboardInUse)
        studio.placeCursor(track: 2, step: 5)
        XCTAssertEqual(studio.selectedTrack, 2)
        XCTAssertEqual(studio.selectedStep, 5,
                       "Once it's visible, taps and arrows agree on where it is")
    }

    // MARK: Octave

    func testTheOctaveIsSharedAndStaysInTheKeyboardsRange() {
        studio.octave = 5
        studio.shiftOctave(1)
        XCTAssertEqual(studio.octave, 6)

        studio.octave = 8
        studio.shiftOctave(1)
        XCTAssertEqual(studio.octave, 8, "Same ceiling the on-screen buttons have")

        studio.octave = 0
        studio.shiftOctave(-1)
        XCTAssertEqual(studio.octave, 0)
    }

    // MARK: Note off

    /// Return types whatever the on-screen keyboard holds, so it can only
    /// enter a note off once one is already armed. Backslash arms it — the key
    /// trackers have used for a cut for as long as there have been trackers.
    func testBackslashArmsAndDisarmsNoteOff() {
        let action = KeyAction.forKey(usage: .keyboardBackslash,
                                      characters: "\\",
                                      modifiers: [],
                                      octave: 5)
        XCTAssertEqual(action, .toggleNoteOff)

        studio.selectedNote = 62
        studio.apply(.toggleNoteOff)
        XCTAssertEqual(studio.selectedNote, ChipCore.noteOff)
        studio.apply(.toggleNoteOff)
        XCTAssertEqual(studio.selectedNote, 62)
    }

    /// Backslash is a printing character, so the letter-row lookup must not
    /// get a chance to claim it first.
    func testBackslashIsNotReadAsANote() {
        XCTAssertNil(NoteKeys.note(for: "\\", octave: 5))
    }
}
