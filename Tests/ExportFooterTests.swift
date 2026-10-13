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

    // MARK: MIDI

    private func midiFooter(_ song: Song) -> String? {
        ExportNotesFooter.text(for: song, format: .midi)
    }

    func testWavFormatFooterIsTheExistingOne() {
        var song = TestSongs.golden()
        for i in song.tracks.indices { song.tracks[i].muted = true }
        XCTAssertEqual(ExportNotesFooter.text(for: song, format: .wav), ExportNotesFooter.text(for: song))
    }

    func testMidiFooterGivesTheLengthAndTheArpeggioNote() {
        let song = TestSongs.golden()
        XCTAssertEqual(midiFooter(song),
                       "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote.")
    }

    func testMidiFooterSaysMutedTracksAreInTheFileAtVolumeZero() {
        var song = TestSongs.golden()
        song.tracks[0].muted = true
        XCTAssertEqual(midiFooter(song),
                       "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote. Muted tracks are in the file at volume 0.")
    }

    /// The MIDI file still has the notes, so the WAV's "would be silent"
    /// warning would be wrong for it.
    func testMidiFooterDoesNotWarnAboutSilenceWhenEverythingIsMuted() throws {
        var song = TestSongs.golden()
        for i in song.tracks.indices { song.tracks[i].muted = true }
        let text = try XCTUnwrap(midiFooter(song))
        XCTAssertFalse(text.contains("silent"))
        XCTAssertTrue(text.hasSuffix("Muted tracks are in the file at volume 0."))
    }

    func testMidiFooterKeepsTheNoNotesMessages() {
        XCTAssertEqual(midiFooter(TestSongs.empty()), "This song has no notes yet.")
        var song = TestSongs.empty()
        var second = Pattern(name: "B", trackCount: song.tracks.count)
        second.rows[0][0] = 60
        song.patterns.append(second)
        XCTAssertEqual(midiFooter(song), ExportNotesFooter.text(for: song))
    }
}

final class ExportControlsLockTests: XCTestCase {

    func testSettingsAreLockedWhileARenderIsRunning() {
        XCTAssertTrue(ExportControls.settingsLocked(isExporting: true))
    }

    func testSettingsAreEditableWhenNoRenderIsRunning() {
        XCTAssertFalse(ExportControls.settingsLocked(isExporting: false))
    }
}
