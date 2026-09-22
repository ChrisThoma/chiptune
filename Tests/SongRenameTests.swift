import XCTest
import SwiftUI
import UIKit
@testable import Chiptune

/// Renaming from the library. The App Store copy promises it, so it has to
/// actually stick — including the case the naive implementation gets wrong,
/// where the renamed song is the one currently open and the next save writes
/// the old name straight back over it.
@MainActor
final class SongRenameTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testRenamingAnotherSongPersistsToTheStore() throws {
        var other = Song(name: "Old name")
        temp.save(other)

        studio.rename(other, to: "New name")

        other = try XCTUnwrap(temp.store.load(id: other.id))
        XCTAssertEqual(other.name, "New name")
    }

    /// The failure mode worth having a test for: renaming the open song via the
    /// store alone leaves `studio.song` holding the old name, and the next
    /// autosave undoes the rename.
    func testRenamingTheOpenSongSurvivesTheNextSave() throws {
        studio.song.name = "Working title"
        studio.saveNow()
        let id = studio.song.id

        studio.rename(studio.song, to: "Final title")
        XCTAssertEqual(studio.song.name, "Final title", "the open song must be renamed in place")

        // Whatever the app does next that writes the song must not resurrect
        // the old name.
        studio.saveNow()
        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: id)).name, "Final title")
    }

    func testEmptyOrWhitespaceNameIsRejected() throws {
        var song = Song(name: "Keep me")
        temp.save(song)

        studio.rename(song, to: "   ")

        song = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(song.name, "Keep me", "a blank rename must leave the name alone")
    }

    /// Two songs sharing a name are indistinguishable in the library list and
    /// in the "OPEN" indicator, so renaming into a collision with a
    /// *different* song's name must no-op rather than silently duplicate it.
    func testRenamingToAnotherSongsNameIsRejected() throws {
        let other = Song(name: "Taken")
        temp.save(other)
        var target = Song(name: "Keep me")
        temp.save(target)

        studio.rename(target, to: "Taken")

        target = try XCTUnwrap(temp.store.load(id: target.id))
        XCTAssertEqual(target.name, "Keep me", "a colliding rename must leave the name alone")
    }

    /// Re-confirming a song's own current name (including different
    /// whitespace/casing-preserving trim) must not be blocked as a "duplicate"
    /// of itself.
    func testRenamingASongToItsOwnCurrentNameIsAllowed() throws {
        var song = Song(name: "Mine")
        temp.save(song)

        studio.rename(song, to: "  Mine  ")

        song = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(song.name, "Mine")
    }

    func testRenameTrimsSurroundingWhitespace() throws {
        var song = Song(name: "Old")
        temp.save(song)

        studio.rename(song, to: "  Padded  ")

        song = try XCTUnwrap(temp.store.load(id: song.id))
        XCTAssertEqual(song.name, "Padded")
    }

    func testRenameFieldInkIsDarkOverAWhiteField() {
        let foreground = SongRenameAlertStyle.textColor(over: .white)
        XCTAssertGreaterThan(SongRenameAlertStyle.contrastRatio(foreground, .white), 4.5)
    }

    func testRenameFieldInkIsLightOverADarkField() {
        let dark = UIColor(white: 0.11, alpha: 1)
        let foreground = SongRenameAlertStyle.textColor(over: dark)
        XCTAssertGreaterThan(SongRenameAlertStyle.contrastRatio(foreground, dark), 4.5)
    }

    /// The old rule picked ink by a 0.5 luminance cut, not by which candidate
    /// actually contrasts more with the background -- so a mid-grey field
    /// (0.45-0.74 luminance) got the lower-contrast ink. Every grey must get
    /// whichever of the two inks wins the contrast ratio outright.
    func testRenameFieldInkIsTheHigherContrastChoiceOnEveryGrey() {
        for white in stride(from: 0.0, through: 1.0, by: 0.05) {
            let background = UIColor(white: white, alpha: 1)
            let chosen = SongRenameAlertStyle.textColor(over: background)
            let onLight = UIColor(Theme.onLight)
            let text = UIColor(Theme.text)
            let other = chosen == onLight ? text : onLight

            let chosenRatio = SongRenameAlertStyle.contrastRatio(chosen, background)
            let otherRatio = SongRenameAlertStyle.contrastRatio(other, background)

            XCTAssertGreaterThanOrEqual(
                chosenRatio, otherRatio,
                "grey \(white): chosen ink's contrast ratio \(chosenRatio) should be >= the other candidate's \(otherRatio)"
            )
        }
    }

    func testRenameFieldTakesItsInkFromItsContainer() {
        let whiteContainer = UIView()
        whiteContainer.backgroundColor = .white
        let whiteField = UITextField()
        whiteContainer.addSubview(whiteField)
        SongRenameAlertStyle.apply(to: whiteField)
        XCTAssertEqual(whiteField.textColor, SongRenameAlertStyle.textColor(over: .white))

        let darkContainer = UIView()
        darkContainer.backgroundColor = UIColor(white: 0.11, alpha: 1)
        let darkField = UITextField()
        darkContainer.addSubview(darkField)
        SongRenameAlertStyle.apply(to: darkField)
        XCTAssertEqual(darkField.textColor, SongRenameAlertStyle.textColor(over: darkContainer.backgroundColor!))

        let bareContainer = UIView()
        let bareField = UITextField()
        bareContainer.addSubview(bareField)
        SongRenameAlertStyle.apply(to: bareField)
        XCTAssertEqual(bareField.textColor, .label)
    }

    func testNativeRenameAlertFieldReceivesItsSpokenPurpose() {
        let field = UITextField()

        SongNameFieldAccessibility.apply(to: field)

        XCTAssertEqual(field.accessibilityLabel, "Song title")
    }

    // MARK: Renaming from the title bar
    //
    // The field writes through `setSongName` on every keystroke, so these
    // spell keystrokes out rather than assigning the finished string — the
    // thing under test is what the undo stack looks like afterwards.

    private func type(_ name: String) {
        for end in 1...name.count {
            studio.setSongName(String(name.prefix(end)))
        }
    }

    func testTypedRenameIsOneUndoStep() {
        studio.song.name = "Old"
        studio.saveNow()

        type("New name")
        studio.normalizeSongName()
        XCTAssertEqual(studio.song.name, "New name")

        studio.undo()
        XCTAssertEqual(studio.song.name, "Old", "the whole rename undoes at once")
        XCTAssertFalse(studio.canUndo, "eight keystrokes must not leave eight steps")
    }

    /// The bug the wall-clock coalescing window would have: a pause mid-word
    /// splitting one rename into two undo steps. The run is keyed, not timed,
    /// so shrinking the window to nothing must change nothing.
    func testAPauseWhileTypingDoesNotSplitTheRename() {
        studio.undoCoalescingWindow = 0
        studio.song.name = "Old"

        type("New")
        studio.setSongName("New name")
        studio.normalizeSongName()

        studio.undo()
        XCTAssertEqual(studio.song.name, "Old")
        XCTAssertFalse(studio.canUndo)
    }

    func testUndoingARenameCanBeRedone() {
        studio.song.name = "Old"
        type("New")
        studio.normalizeSongName()

        studio.undo()
        XCTAssertEqual(studio.song.name, "Old")
        studio.redo()
        XCTAssertEqual(studio.song.name, "New")
    }

    /// Two renames with an unrelated edit between them are two steps: the
    /// intervening checkpoint carries no run, which ends the first one.
    func testAnInterveningEditClosesTheRenameRun() {
        studio.song.name = "First"
        type("Second")
        studio.addPattern()
        type("Third")

        studio.undo()
        XCTAssertEqual(studio.song.name, "Second", "only the second rename undoes")
    }

    /// Focus loss ends the run too, so renaming twice without touching
    /// anything else is still two steps.
    func testEndingTheRunSeparatesConsecutiveRenames() {
        studio.song.name = "First"
        type("Second")
        studio.normalizeSongName()
        type("Third")
        studio.normalizeSongName()

        studio.undo()
        XCTAssertEqual(studio.song.name, "Second")
        studio.undo()
        XCTAssertEqual(studio.song.name, "First")
    }

    func testSettingTheSameNameRecordsNothing() {
        studio.song.name = "Unchanged"
        studio.setSongName("Unchanged")
        XCTAssertFalse(studio.canUndo, "a no-op edit must not push an undo step")
    }

    /// Trimming happens when editing ends, not per keystroke — trimming as you
    /// type makes a space untypeable.
    func testTrailingSpaceSurvivesTypingAndIsTrimmedOnCommit() {
        studio.song.name = "Old"

        studio.setSongName("Two ")
        XCTAssertEqual(studio.song.name, "Two ", "mid-word space must survive")
        studio.setSongName("Two words")
        studio.normalizeSongName()

        XCTAssertEqual(studio.song.name, "Two words")
    }

    func testClearingTheNameEntirelyRestoresThePreviousOne() {
        studio.song.name = "Keep me"
        studio.saveNow()

        type("X")
        studio.setSongName("")
        studio.normalizeSongName()

        XCTAssertEqual(studio.song.name, "Keep me", "a blank name falls back rather than sticking")
        XCTAssertFalse(studio.canUndo, "and the abandoned rename leaves no step behind")
    }

    func testCommittedRenameRoundTripsThroughTheStore() throws {
        let id = studio.song.id
        type("Persisted")
        studio.normalizeSongName()

        XCTAssertEqual(try XCTUnwrap(temp.store.load(id: id)).name, "Persisted",
                       "committing the field saves, under the same id")
    }

    /// The library's rename dialog goes through `rename(_:to:)`, which is a
    /// single deliberate act rather than a run — but it must still be undoable.
    func testLibraryRenameOfTheOpenSongIsUndoable() {
        studio.song.name = "Old"
        studio.rename(studio.song, to: "New")
        XCTAssertEqual(studio.song.name, "New")

        studio.undo()
        XCTAssertEqual(studio.song.name, "Old")
    }

    func testDeleteRemovesTheSongFromTheLibrary() {
        let song = Song(name: "Doomed")
        temp.save(song)
        XCTAssertEqual(temp.store.loadAll().count, 2, "the studio's own song plus this one")

        studio.delete(song)

        XCTAssertNil(temp.store.load(id: song.id))
        XCTAssertFalse(temp.store.loadAll().contains { $0.id == song.id })
    }
}
