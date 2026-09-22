import XCTest
@testable import Chiptune

final class SongNotesTests: XCTestCase {

    func testAnEmptySongHasNoNotes() {
        XCTAssertFalse(TestSongs.empty().hasNotes)
    }

    func testASingleNoteCounts() {
        XCTAssertTrue(TestSongs.singleNote(kind: .pulse1).hasNotes)
    }

    func testANoteOffAloneIsNotANote() {
        var song = TestSongs.empty()
        song.patterns[0].rows[0][0] = Chip.noteOff
        XCTAssertFalse(song.hasNotes)
    }

    func testANoteBeyondThePatternLengthDoesNotCount() {
        var song = TestSongs.empty(length: 16)
        song.patterns[0].rows[0][20] = 60
        XCTAssertFalse(song.hasNotes)

        song.patterns[0].length = 32
        XCTAssertTrue(song.hasNotes)
    }

    func testANoteInAPatternOutsideTheArrangementDoesNotCount() {
        var song = TestSongs.empty()
        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[0][0] = 60
        song.patterns.append(second)

        XCTAssertFalse(song.hasNotes)

        song.arrangement.append(SongSection(patternID: song.patterns[1].id))
        XCTAssertTrue(song.hasNotes)
    }

    func testAMutedTrackStillCounts() {
        var song = TestSongs.singleNote(kind: .pulse1)
        song.tracks[0].muted = true
        XCTAssertTrue(song.hasNotes)
    }

    func testAChainedSecondPatternCounts() {
        var song = TestSongs.twoPatterns()
        for i in song.patterns[0].rows.indices {
            song.patterns[0].rows[i] = Pattern.emptyRow
        }
        XCTAssertTrue(song.hasNotes)
    }

    func testNotesInAnUnarrangedPatternAreStillNotesSomewhere() {
        var song = TestSongs.empty()
        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[0][0] = 60
        song.patterns.append(second)

        XCTAssertFalse(song.hasNotes)
        XCTAssertTrue(song.hasNotesAnywhere)
    }

    func testAnAllMutedSongHasNoAudibleNotes() {
        var song = TestSongs.empty()
        song.patterns[0].rows[0][0] = 60
        song.tracks[0].muted = true

        XCTAssertTrue(song.hasNotes)
        XCTAssertFalse(song.hasAudibleNotes)

        song.tracks[0].muted = false
        XCTAssertTrue(song.hasAudibleNotes)
    }

    func testOneUnmutedTrackWithNotesIsAudible() {
        var song = TestSongs.empty()
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[1][0] = 64
        song.tracks[0].muted = true

        XCTAssertTrue(song.hasAudibleNotes)
    }

    func testAnUnmutedTrackWhoseOnlyNotesAreUnarrangedIsNotAudible() {
        var song = TestSongs.empty()
        song.patterns[0].rows[0][0] = 60
        song.tracks[0].muted = true

        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[1][0] = 64
        song.patterns.append(second)

        XCTAssertFalse(song.hasAudibleNotes)

        song.arrangement.append(SongSection(patternID: second.id))
        XCTAssertTrue(song.hasAudibleNotes)
    }
}
