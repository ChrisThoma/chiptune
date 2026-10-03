import XCTest
@testable import Chiptune

/// A track rename is one undo step, and a name write that changes nothing is
/// no step at all (issue #13: phantom no-op Undo presses).
@MainActor
final class TrackNameUndoTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(Song(name: "Names"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    func testRenamingATrackOnceIsOneUndoStep() {
        let original = studio.song.tracks[0].name
        studio.undoCoalescingWindow = 0
        studio.setTrackName("Lead", at: 0)
        XCTAssertEqual(studio.song.tracks[0].name, "Lead")

        studio.undo()
        XCTAssertEqual(studio.song.tracks[0].name, original)
        XCTAssertFalse(studio.canUndo, "one rename must be one undo step")
        XCTAssertTrue(studio.canRedo)
    }

    func testWritingTheSameNameCreatesNoUndoStep() {
        studio.undoCoalescingWindow = 0
        studio.setTrackName("Lead", at: 0)
        studio.undo()
        studio.redo()
        studio.setTrackName("Lead", at: 0)
        studio.setTrackName("Lead", at: 0)
        studio.undo()
        XCTAssertNil(studio.song.tracks[0].name)
        XCTAssertFalse(studio.canUndo)
    }

    func testWritingAnEmptyNameToAnUnnamedTrackCreatesNoUndoStep() {
        XCTAssertNil(studio.song.tracks[0].name)
        studio.setTrackName("", at: 0)
        studio.setTrackName("   ", at: 0)
        XCTAssertFalse(studio.canUndo)
    }

    func testTypingRunInsideTheWindowIsOneStep() {
        studio.undoCoalescingWindow = 60
        for text in ["A", "Al", "Alp", "Alph", "Alpha"] {
            studio.setTrackName(text, at: 0)
        }
        studio.undo()
        XCTAssertNil(studio.song.tracks[0].name)
        XCTAssertFalse(studio.canUndo)
    }

    /// The reported sequence: type, pause, type more, pause, clear. Every
    /// Undo must change the name until nothing is left.
    func testSeparateRunsUndoOneAtATimeWithNoNoOps() {
        studio.undoCoalescingWindow = 0
        studio.setTrackName("Alpha", at: 0)
        studio.setTrackName("Alphabet", at: 0)
        studio.setTrackName("Alphabet", at: 0)
        studio.setTrackName("", at: 0)
        studio.setTrackName("", at: 0)

        var seen: [String?] = []
        while studio.canUndo {
            studio.undo()
            seen.append(studio.song.tracks[0].name)
            XCTAssertLessThan(seen.count, 10)
        }
        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen[0], "Alphabet")
        XCTAssertEqual(seen[1], "Alpha")
        XCTAssertNil(seen[2])
    }

    func testRenamingAPatternToItsCurrentNameCreatesNoUndoStep() {
        let name = studio.song.patterns[0].name
        studio.renamePattern(at: 0, to: name)
        XCTAssertFalse(studio.canUndo)
    }

    func testSongTitleWriteOfTheSameNameCreatesNoUndoStep() {
        studio.setSongName(studio.song.name)
        XCTAssertFalse(studio.canUndo)
    }
}
