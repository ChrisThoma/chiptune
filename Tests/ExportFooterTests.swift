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

    func testMidiFooterSaysAMutedTrackIsInTheFileAtVolumeZero() {
        var song = TestSongs.golden()
        song.tracks[0].muted = true
        XCTAssertEqual(midiFooter(song),
                       "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote. A muted or silent track keeps its notes in the file, turned all the way down.")
    }

    func testMidiFooterSaysMutedTracksAreInTheFileAtVolumeZero() {
        var song = TestSongs.golden()
        song.tracks[0].muted = true
        song.tracks[2].muted = true
        XCTAssertEqual(midiFooter(song),
                       "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote. Muted or silent tracks keep their notes in the file, turned all the way down.")
    }

    /// The MIDI file still has the notes, so the WAV's "would be silent"
    /// warning would be wrong for it.
    func testMidiFooterDoesNotWarnAboutSilenceWhenEverythingIsMuted() throws {
        var song = TestSongs.golden()
        for i in song.tracks.indices { song.tracks[i].muted = true }
        let text = try XCTUnwrap(midiFooter(song))
        XCTAssertFalse(text.contains("would be silent"))
        XCTAssertTrue(text.hasSuffix("Muted or silent tracks keep their notes in the file, turned all the way down."))
    }

    /// Every track plays a note at step 0.
    private func song(_ kinds: [ChannelKind], muted: Set<Int>) -> Song {
        var song = TestSongs.empty()
        song.tracks = kinds.map { Track(kind: $0) }
        for i in muted { song.tracks[i].muted = true }
        song.patterns[0].rows = kinds.map { _ in
            var row = Pattern.emptyRow
            row[0] = 60
            return row
        }
        return song
    }

    private func lead(_ song: Song) -> String {
        "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote."
    }

    /// Every noise track muted: none plays on the drum channel, so each is
    /// silenced with the channel's volume like any other muted track.
    func testMidiFooterCountsMutedDrumsAtVolumeZeroWhenNoDrumPlays() {
        let song = song([.pulse1, .noise, .noise], muted: [1, 2])
        XCTAssertEqual(midiFooter(song), lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.")
    }

    func testMidiFooterSaysAMutedDrumBesideAPlayingOneIsLeftEmpty() {
        let song = song([.pulse1, .noise, .noise], muted: [2])
        XCTAssertEqual(midiFooter(song),
                       lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.")
    }

    func testMidiFooterSaysSoOfEveryEmptiedDrumTrack() {
        let song = song([.noise, .noise, .noise], muted: [0, 2])
        XCTAssertEqual(midiFooter(song),
                       lead(song) + " Muted or silent drum tracks are left empty, because all drum tracks share one part in the file.")
    }

    func testMidiFooterGivesBothWhenBothHappen() {
        let song = song([.pulse1, .triangle, .noise, .noise], muted: [1, 3])
        XCTAssertEqual(midiFooter(song),
                       lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down."
                           + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.")
    }

    /// The unmuted drum track plays nothing, so the muted one is silenced
    /// with the channel's volume rather than left empty.
    func testMidiFooterLeavesNoDrumEmptyBesideADrumTrackWithNoNotes() {
        var song = song([.pulse1, .noise, .noise], muted: [2])
        song.patterns[0].rows[1] = Pattern.emptyRow
        XCTAssertEqual(midiFooter(song), lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down.")
    }

    /// A muted track with nothing the arrangement plays has no notes in the
    /// file to be at volume 0.
    func testMidiFooterSkipsAMutedTrackWithNoNotesInTheArrangement() {
        var song = song([.pulse1, .triangle, .pulse2], muted: [1, 2])
        song.patterns[0].rows[1] = Pattern.emptyRow
        song.patterns[0].rows[2] = Pattern.emptyRow
        // Past the pattern's end, and in a pattern the arrangement skips.
        song.patterns[0].rows[1][song.patterns[0].length] = 60
        var unplayed = Pattern(name: "B", trackCount: 3)
        unplayed.rows[2][0] = 60
        song.patterns.append(unplayed)
        XCTAssertEqual(midiFooter(song), lead(song))
    }

    /// Emptying a drum track that had no notes loses nothing worth a line.
    func testMidiFooterSkipsAnEmptiedDrumTrackWithNoNotes() {
        var song = song([.noise, .noise, .noise], muted: [1, 2])
        song.patterns[0].rows[2] = Pattern.emptyRow
        XCTAssertEqual(midiFooter(song),
                       lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.")
    }

    // MARK: 0% volume

    /// A track at 0% is written like a muted one, so it is counted with them.
    func testMidiFooterCountsATrackAtZeroVolumeAsInTheFileAtVolumeZero() {
        var song = song([.pulse1, .triangle], muted: [])
        song.tracks[1].instrument.volume = 0
        XCTAssertEqual(midiFooter(song), lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down.")
    }

    func testMidiFooterCountsMutedAndZeroVolumeTracksTogether() {
        var song = song([.pulse1, .triangle, .pulse2], muted: [2])
        song.tracks[1].instrument.volume = 0
        XCTAssertEqual(midiFooter(song), lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.")
    }

    func testMidiFooterSaysAZeroVolumeDrumBesideAPlayingOneIsLeftEmpty() {
        var song = song([.pulse1, .noise, .noise], muted: [])
        song.tracks[2].instrument.volume = 0
        XCTAssertEqual(midiFooter(song),
                       lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.")
    }

    /// A drum track at 0% doesn't play, so the muted one beside it is at
    /// volume 0 rather than left empty, and so is the 0% one.
    func testMidiFooterLeavesNoDrumEmptyBesideAZeroVolumeDrum() {
        var song = song([.noise, .noise], muted: [1])
        song.tracks[0].instrument.volume = 0
        XCTAssertEqual(midiFooter(song), lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.")
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

    // MARK: The Export button after a render

    /// A failed or canceled render gives the button back for another try.
    func testTheButtonComesBackWhenItsRenderLeftNoFile() {
        XCTAssertTrue(ExportControls.freesExportButton(startedAttempt: 1, completedAttempt: 1, producedFile: false))
    }

    /// A render that left a file is taking the panel down for the share
    /// sheet, which reads that file when it comes up: a second render
    /// started meanwhile would clear it first.
    func testTheButtonStaysLockedWhileASuccessTakesThePanelDown() {
        XCTAssertFalse(ExportControls.freesExportButton(startedAttempt: 1, completedAttempt: 1, producedFile: true))
    }

    func testTheButtonStaysLockedWhileItsRenderRuns() {
        XCTAssertFalse(ExportControls.freesExportButton(startedAttempt: 2, completedAttempt: 1, producedFile: false))
    }

    /// Two completions SwiftUI folded into one change still finish the
    /// attempt this panel started.
    func testALaterCompletionAlsoFinishesTheStartedAttempt() {
        XCTAssertTrue(ExportControls.freesExportButton(startedAttempt: 1, completedAttempt: 2, producedFile: false))
    }

    func testNothingStartedHasNothingToFree() {
        XCTAssertFalse(ExportControls.freesExportButton(startedAttempt: nil, completedAttempt: 1, producedFile: false))
    }
}

/// What sits under the WAV/MIDI picker.
final class ExportFormatFooterTests: XCTestCase {

    /// A beginner doesn't know a MIDI file has no sounds in it.
    func testMidiSaysTheFileHoldsNotesNotSounds() {
        XCTAssertEqual(ExportFormatFooter.text(for: .midi),
                       "A MIDI file holds your notes, not the chip sounds. The app you open it in plays them with its own instruments.")
    }

    /// A WAV is the sound itself; its repeats and ending say the rest.
    func testWavHasNoFormatFooter() {
        XCTAssertNil(ExportFormatFooter.text(for: .wav))
    }
}

/// The line under the progress bar while an export runs.
final class ExportProgressTextTests: XCTestCase {

    func testAWavExportSaysHowFarAlongItIs() {
        XCTAssertEqual(ExportProgressText.text(format: .wav, progress: 0.42), "Exporting… 42%")
    }

    /// A MIDI export never reports progress, so a percentage would sit at 0%.
    func testAMidiExportGivesNoPercentage() {
        XCTAssertEqual(ExportProgressText.text(format: .midi, progress: 0), "Exporting…")
    }
}
