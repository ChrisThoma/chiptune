import XCTest
@testable import Chiptune

final class ExportFooterTests: XCTestCase {

    func testASongWithNoNotesAtAllSaysSo() {
        XCTAssertEqual(ExportNotesFooter.text(for: TestSongs.empty()),
                       "This song has no notes yet.")
    }

    func testNotesOutsideTheArrangementPointAtTheArrangement() {
        var song = TestSongs.empty()
        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[0][0] = 60
        song.patterns.append(second)

        XCTAssertEqual(ExportNotesFooter.text(for: song),
                       "Its notes are in a pattern the arrangement doesn't play. Add that pattern to the arrangement to export it.")
    }

    func testASongWithNotesHasNoFooter() {
        XCTAssertNil(ExportNotesFooter.text(for: TestSongs.golden()))
    }

    func testEveryTrackWithNotesMutedWarnsAboutSilence() {
        var song = TestSongs.golden()
        for i in song.tracks.indices { song.tracks[i].muted = true }

        XCTAssertEqual(ExportNotesFooter.text(for: song),
                       "Every track with notes is muted, so the export would be silent.")
    }

    func testAMutedSongWithNoNotesStillSaysItHasNoNotes() {
        var song = TestSongs.empty()
        for i in song.tracks.indices { song.tracks[i].muted = true }

        XCTAssertEqual(ExportNotesFooter.text(for: song),
                       "This song has no notes yet.")
    }

    func testAMutedSongWhoseNotesAreUnarrangedStillPointsAtTheArrangement() {
        var song = TestSongs.empty()
        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[0][0] = 60
        song.patterns.append(second)
        for i in song.tracks.indices { song.tracks[i].muted = true }

        XCTAssertEqual(ExportNotesFooter.text(for: song),
                       "Its notes are in a pattern the arrangement doesn't play. Add that pattern to the arrangement to export it.")
    }
}
