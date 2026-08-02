import XCTest
@testable import Chiptune

/// Every editing operation, checked on two fronts: the model ends up in the
/// state it should, and the DSP core ends up agreeing with it.
///
/// That second half is the point. A `Studio` method that updates `song` but
/// forgets to `pushAll()` looks completely correct from the UI — the grid
/// redraws, the chip labels change — and is silently inaudible. So after each
/// operation the core's own counts are compared against the model's.
@MainActor
final class StudioEditingTests: XCTestCase {

    private var temp: TempStore!
    private var studio: Studio!

    override func setUp() {
        super.setUp()
        temp = makeTempStore()
        // Autosave off: a live 1.5 s timer would fire into whichever test
        // happens to be running when it comes due.
        studio = Studio(store: temp.store, autosaveEnabled: false)
        // A Studio built on an empty store seeds the demo riff, so "is this
        // cell empty?" would be a question about the demo rather than about the
        // edit under test. Every test starts from a blank song instead.
        studio.open(Song(name: "Blank"))
    }

    override func tearDown() {
        studio.invalidateTimers()
        studio = nil
        temp = nil
        super.tearDown()
    }

    /// The core mirrors the model. Called after every mutation below.
    private func assertCoreMatchesModel(_ message: String = "", file: StaticString = #filePath,
                                        line: UInt = #line) {
        let core = studio.engine.core
        XCTAssertEqual(Int(core.trackCount), studio.song.tracks.count,
                       "core track count \(message)", file: file, line: line)
        XCTAssertEqual(Int(core.patternCount), studio.song.patterns.count,
                       "core pattern count \(message)", file: file, line: line)
        XCTAssertEqual(Int(core.chainCount), studio.song.chain.count,
                       "core chain length \(message)", file: file, line: line)
        XCTAssertTrue(studio.song.patterns.indices.contains(studio.selectedPattern),
                      "selected pattern out of range \(message)", file: file, line: line)
        XCTAssertTrue(studio.song.tracks.indices.contains(studio.selectedTrack),
                      "selected track out of range \(message)", file: file, line: line)
    }

    // MARK: Patterns

    func testAddPatternAppendsToTheArrangementAndSelectsIt() {
        let before = studio.song.patterns.count
        let index = studio.addPattern()

        XCTAssertEqual(index, before)
        XCTAssertEqual(studio.song.patterns.count, before + 1)
        XCTAssertEqual(studio.selectedPattern, before, "a new pattern should be the one you're editing")
        XCTAssertEqual(studio.song.arrangement.last?.patternID, studio.song.patterns.last?.id)
        assertCoreMatchesModel("after addPattern")
    }

    func testAddPatternStopsAtTheLimit() {
        while studio.song.canAddPattern { studio.addPattern() }
        XCTAssertEqual(studio.song.patterns.count, Chip.maxPatterns)

        XCTAssertNil(studio.addPattern(), "adding past the limit must report failure, not wrap")
        XCTAssertEqual(studio.song.patterns.count, Chip.maxPatterns)
        assertCoreMatchesModel("at the pattern limit")
    }

    func testDuplicatePatternCopiesNotesUnderAFreshIdentity() {
        studio.setNote(track: 0, step: 3, note: 64)
        studio.duplicatePattern(at: 0)

        XCTAssertEqual(studio.song.patterns.count, 2)
        XCTAssertEqual(studio.selectedPattern, 1)
        XCTAssertEqual(studio.song.patterns[1].rows[0][3], 64, "the copy should carry the notes")
        XCTAssertNotEqual(studio.song.patterns[0].id, studio.song.patterns[1].id,
                          "a duplicate sharing an id would make the arrangement ambiguous")

        // Editing the copy must not write through to the original.
        studio.setNote(track: 0, step: 3, note: 70)
        XCTAssertEqual(studio.song.patterns[0].rows[0][3], 64)
        assertCoreMatchesModel("after duplicatePattern")
    }

    func testRemovePatternDropsItsArrangementSectionsAndClampsSelection() {
        studio.addPattern()
        studio.addPattern()
        let doomed = studio.song.patterns[2].id
        studio.selectPattern(2)

        studio.removePattern(at: 2)

        XCTAssertEqual(studio.song.patterns.count, 2)
        XCTAssertFalse(studio.song.arrangement.contains { $0.patternID == doomed },
                       "a deleted pattern must not be left in the arrangement")
        XCTAssertEqual(studio.selectedPattern, 1, "selection should fall back, not dangle")
        assertCoreMatchesModel("after removePattern")
    }

    func testTheLastPatternCannotBeRemoved() {
        XCTAssertEqual(studio.song.patterns.count, 1)
        studio.removePattern(at: 0)
        XCTAssertEqual(studio.song.patterns.count, 1, "a song with no patterns isn't representable")
        assertCoreMatchesModel("after removing the only pattern")
    }

    /// Deleting B and adding again should give you B back, rather than
    /// marching the letters up forever.
    func testPatternLettersAreReused() {
        studio.addPattern()
        XCTAssertEqual(studio.song.patterns[1].name, "B")

        studio.removePattern(at: 1)
        studio.addPattern()
        XCTAssertEqual(studio.song.patterns[1].name, "B")
    }

    func testRenamePatternTrimsAndRejectsBlanks() {
        studio.renamePattern(at: 0, to: "  Intro  ")
        XCTAssertEqual(studio.song.patterns[0].name, "Intro")

        studio.renamePattern(at: 0, to: "   ")
        XCTAssertEqual(studio.song.patterns[0].name, "Intro", "a blank rename must be ignored")

        studio.renamePattern(at: 0, to: "abcdefghij")
        XCTAssertEqual(studio.song.patterns[0].name, "abcdef", "names are capped at six characters")
    }

    // MARK: Tracks

    /// A pattern holds one row per track, and the audio thread reads rows by
    /// track index. If any pattern's rows fall out of step with the track list,
    /// notes appear on the wrong voice.
    func testAddTrackGivesEveryPatternAMatchingRow() {
        studio.addPattern()
        studio.addPattern()
        let before = studio.song.tracks.count

        studio.addTrack(kind: .pulse2)

        XCTAssertEqual(studio.song.tracks.count, before + 1)
        XCTAssertEqual(studio.selectedTrack, before, "a new track should be the selected one")
        for (index, pattern) in studio.song.patterns.enumerated() {
            XCTAssertEqual(pattern.rows.count, before + 1, "pattern \(index) is out of step")
        }
        assertCoreMatchesModel("after addTrack")
    }

    func testDuplicateTrackCopiesItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 1, step: 2, note: 60)
        studio.selectPattern(1)
        studio.setNote(track: 1, step: 5, note: 67)

        studio.duplicateTrack(at: 1)

        XCTAssertEqual(studio.selectedTrack, 2)
        XCTAssertEqual(studio.song.patterns[0].rows[2][2], 60)
        XCTAssertEqual(studio.song.patterns[1].rows[2][5], 67)
        XCTAssertNotEqual(studio.song.tracks[1].id, studio.song.tracks[2].id)
        for pattern in studio.song.patterns {
            XCTAssertEqual(pattern.rows.count, studio.song.tracks.count)
        }
        assertCoreMatchesModel("after duplicateTrack")
    }

    func testRemoveTrackRemovesItsRowFromEveryPatternInLockstep() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 2, step: 1, note: 48)
        studio.selectPattern(1)
        studio.setNote(track: 2, step: 1, note: 50)

        studio.removeTrack(at: 1)

        XCTAssertEqual(studio.song.tracks.count, 3)
        for pattern in studio.song.patterns {
            XCTAssertEqual(pattern.rows.count, 3, "rows must track the deletion")
        }
        // What was track 2 is now track 1 — in every pattern, with its notes.
        XCTAssertEqual(studio.song.patterns[0].rows[1][1], 48)
        XCTAssertEqual(studio.song.patterns[1].rows[1][1], 50)
        assertCoreMatchesModel("after removeTrack")
    }

    func testRemovingTheLastTrackIsRefused() {
        while studio.song.tracks.count > 1 { studio.removeTrack(at: 0) }
        studio.removeTrack(at: 0)
        XCTAssertEqual(studio.song.tracks.count, 1)
        assertCoreMatchesModel("after removing the only track")
    }

    func testSelectionClampsWhenTheSelectedTrackIsDeleted() {
        studio.selectedTrack = 3
        studio.removeTrack(at: 3)
        XCTAssertEqual(studio.selectedTrack, 2)
        assertCoreMatchesModel("after deleting the selected track")
    }

    /// Switching waveform keeps the notes but takes the new kind's defaults —
    /// a bass triangle's envelope makes no sense on noise.
    func testSetKindResetsTheInstrumentButKeepsTheNotes() {
        studio.setNote(track: 0, step: 0, note: 60)
        studio.song.tracks[0].instrument.volume = 0.11

        studio.setKind(.noise, for: 0)

        XCTAssertEqual(studio.song.tracks[0].kind, .noise)
        XCTAssertEqual(studio.song.tracks[0].instrument, .default(for: .noise))
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], 60, "the notes should stay put")
    }

    func testSetKindToTheSameKindLeavesTheInstrumentAlone() {
        studio.song.tracks[0].instrument.volume = 0.11
        studio.setKind(studio.song.tracks[0].kind, for: 0)
        XCTAssertEqual(studio.song.tracks[0].instrument.volume, 0.11,
                       "a no-op kind change must not wipe a tweaked sound")
    }

    // MARK: Clearing

    /// Notes live in patterns, so clearing a track empties the pattern on
    /// screen and leaves that track's part in the others.
    func testClearTrackOnlyTouchesTheSelectedPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(track: 0, step: 0, note: 60)
        studio.selectPattern(1)
        studio.setNote(track: 0, step: 0, note: 72)

        studio.clearTrack(0)

        XCTAssertEqual(studio.song.patterns[1].rows[0][0], Chip.emptyNote)
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], 60, "the other pattern must be untouched")
    }

    func testClearPatternEmptiesEveryTrackInThatPatternOnly() {
        studio.addPattern()
        studio.selectPattern(0)
        for track in 0..<4 { studio.setNote(track: track, step: track, note: 60) }
        studio.selectPattern(1)
        for track in 0..<4 { studio.setNote(track: track, step: track, note: 64) }

        studio.clearPattern()

        XCTAssertTrue(studio.song.patterns[1].isEmpty)
        XCTAssertFalse(studio.song.patterns[0].isEmpty, "clear pattern is not clear everything")
    }

    // MARK: Bounds

    func testTempoIsClampedToTheSupportedRange() {
        studio.setTempo(1000)
        XCTAssertEqual(studio.song.tempo, 300)
        studio.setTempo(-5)
        XCTAssertEqual(studio.song.tempo, 40)
        studio.setTempo(174)
        XCTAssertEqual(studio.song.tempo, 174)
        XCTAssertEqual(studio.engine.core.tempo, 174, "the core must hear the new tempo")
    }

    func testPatternLengthIsClampedToTheSupportedRange() {
        studio.setPatternLength(1000)
        XCTAssertEqual(studio.patternLength, Chip.maxSteps)
        studio.setPatternLength(0)
        XCTAssertEqual(studio.patternLength, 4)
    }

    func testSetNoteIgnoresOutOfRangeCoordinates() {
        studio.setNote(track: 99, step: 0, note: 60)
        studio.setNote(track: 0, step: 9999, note: 60)
        XCTAssertTrue(studio.song.patterns[0].isEmpty, "an out-of-range write must be dropped")
    }

    func testToggleCellWritesThenClears() {
        XCTAssertEqual(studio.note(track: 0, step: 0), Chip.emptyNote)

        studio.selectedNote = 67
        studio.toggleCell(track: 0, step: 0)
        XCTAssertEqual(studio.note(track: 0, step: 0), 67)

        studio.toggleCell(track: 0, step: 0)
        XCTAssertEqual(studio.note(track: 0, step: 0), Chip.emptyNote)
    }

    // MARK: Arrangement

    func testRemovingEveryArrangementSectionFallsBackToTheFirstPattern() {
        studio.removeSection(at: IndexSet(studio.song.arrangement.indices))

        XCTAssertEqual(studio.song.arrangement.count, 1,
                       "an empty arrangement isn't representable")
        XCTAssertEqual(studio.song.arrangement[0].patternID, studio.song.patterns[0].id)
    }

    func testSectionRepeatsAreClamped() {
        let id = studio.song.arrangement[0].id
        studio.setSection(id, repeats: 9999)
        XCTAssertEqual(studio.song.arrangement[0].repeats, SongSection.maxRepeats)
        studio.setSection(id, repeats: -4)
        XCTAssertEqual(studio.song.arrangement[0].repeats, 1)
    }

    func testArrangementChangesReachTheCore() {
        studio.addPattern()
        let id = studio.song.arrangement[0].id
        studio.setSection(id, repeats: 4)

        XCTAssertEqual(Int(studio.engine.core.chainCount), studio.song.chain.count)
        assertCoreMatchesModel("after an arrangement edit")
    }

    // MARK: Song lifecycle

    func testOpeningASongResetsTheEditingCursor() {
        studio.addPattern()
        studio.selectPattern(1)
        studio.setSongMode(true)

        var other = Song(name: "Other")
        other.tempo = 90
        studio.open(other)

        XCTAssertEqual(studio.song.name, "Other")
        XCTAssertEqual(studio.selectedPattern, 0)
        XCTAssertFalse(studio.songMode, "opening a song should drop back to PATT")
        assertCoreMatchesModel("after open")
    }

    func testNewSongStartsEmptyAndIsPersisted() throws {
        studio.newSong()

        XCTAssertEqual(studio.song.name, "Untitled")
        XCTAssertEqual(studio.selectedPattern, 0)
        XCTAssertNotNil(temp.store.load(id: studio.song.id), "a new song should be on disk at once")
        assertCoreMatchesModel("after newSong")
    }

    func testDuplicateSongIsAnIndependentCopy() {
        studio.setNote(track: 0, step: 0, note: 60)
        let original = studio.song.id

        studio.duplicateSong()

        XCTAssertNotEqual(studio.song.id, original)
        XCTAssertEqual(studio.song.name, "Blank copy")
        XCTAssertEqual(studio.song.patterns[0].rows[0][0], 60)
        XCTAssertNotNil(temp.store.load(id: original), "the original must survive being duplicated")
    }
}
