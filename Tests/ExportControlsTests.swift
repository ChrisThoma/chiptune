import XCTest
@testable import Chiptune

/// Which sections of the export form each format shows.
final class ExportControlsVisibilityTests: XCTestCase {

    /// A WAV and a video both play the arrangement more than once; a MIDI
    /// file is the arrangement once.
    func testRepeatsShowForWavAndVideoOnly() {
        XCTAssertTrue(ExportControls.showsRepeats(.wav))
        XCTAssertTrue(ExportControls.showsRepeats(.video))
        XCTAssertFalse(ExportControls.showsRepeats(.midi))
    }

    /// A video always rings out, so only a WAV has an ending to choose.
    func testEndingShowsForWavOnly() {
        XCTAssertTrue(ExportControls.showsEnding(.wav))
        XCTAssertFalse(ExportControls.showsEnding(.video))
        XCTAssertFalse(ExportControls.showsEnding(.midi))
    }

    func testStyleShowsForVideoOnly() {
        XCTAssertTrue(ExportControls.showsStyle(.video))
        XCTAssertFalse(ExportControls.showsStyle(.wav))
        XCTAssertFalse(ExportControls.showsStyle(.midi))
    }

    func testAnOverlongVideoBlocksTheExportButton() {
        XCTAssertTrue(ExportControls.blocksExport(format: .video, seconds: VideoExport.maxSeconds + 1))
        XCTAssertFalse(ExportControls.blocksExport(format: .video, seconds: VideoExport.maxSeconds))
        XCTAssertFalse(ExportControls.blocksExport(format: .wav, seconds: VideoExport.maxSeconds + 1))
    }
}

/// The length readout under Repeats.
final class ExportLengthTests: XCTestCase {

    /// A video rings out whatever the stored ending says, so its length
    /// includes the tail.
    func testAVideosLengthIncludesTheTail() {
        let song = TestSongs.empty()
        var options = ExportOptions()
        options.format = .video
        options.tailMode = .seamlessLoop
        options.loopCount = 2
        XCTAssertEqual(ExportLength.seconds(song: song, options: options),
                       song.arrangementDuration * 2 + WavExport.tailSeconds(for: song),
                       accuracy: 0.01)
        // Exactly the renderer's length, which counts whole samples a step.
        XCTAssertEqual(ExportLength.seconds(song: song, options: options),
                       VideoTimeline(song: song, options: options).seconds)
    }

    func testASeamlessWavHasNoTail() {
        let song = TestSongs.empty()
        var options = ExportOptions()
        options.tailMode = .seamlessLoop
        XCTAssertEqual(ExportLength.seconds(song: song, options: options),
                       song.arrangementDuration, accuracy: 0.0001)
    }

    /// Nothing cuts a longer video off: YouTube posts it as a regular video
    /// rather than a Short, so that's what the warning says.
    func testAVideoOverThreeMinutesSaysItWontBeAShort() {
        XCTAssertEqual(ExportLength.warning(format: .video, seconds: 181),
                       "Over 3:00, YouTube posts it as a regular video, not a Short.")
        XCTAssertNil(ExportLength.warning(format: .video, seconds: 180))
    }

    func testAWavOverThreeMinutesHasNoWarning() {
        XCTAssertNil(ExportLength.warning(format: .wav, seconds: 400))
    }

    func testAVideoOverTheCapSaysItIsTooLong() {
        XCTAssertEqual(ExportLength.warning(format: .video, seconds: 601), "Too long for a video. The limit is 10:00.")
    }
}

/// The sheet's Export button and the renderer agree on which videos are over
/// the cap. The sheet once worked the length out from the exact step length
/// while the renderer counts whole samples per step, so a song a hair under
/// ten minutes on the sheet could be refused after the tap.
final class ExportCapAgreementTests: XCTestCase {

    /// `steps` steps in one pass at `tempo`: whole 64-step patterns, then one
    /// shorter pattern for the rest. One track, no notes, so the tail is 1 s.
    private func song(tempo: Double, steps: Int) -> Song {
        var song = TestSongs.empty(name: "Cap", tempo: tempo, length: 64)
        let whole = steps / 64
        let rest = steps % 64
        song.arrangement = []
        var left = whole
        while left > 0 {
            let repeats = min(left, SongSection.maxRepeats)
            song.arrangement.append(SongSection(patternID: song.patterns[0].id, repeats: repeats))
            left -= repeats
        }
        if rest > 0 {
            let tail = Pattern(name: "B", length: rest, trackCount: song.tracks.count)
            song.patterns.append(tail)
            song.arrangement.append(SongSection(patternID: tail.id))
        }
        return song
    }

    private func videoOptions() -> ExportOptions {
        var options = ExportOptions()
        options.format = .video
        return options
    }

    private func sheetBlocks(_ song: Song) -> Bool {
        ExportControls.blocksExport(format: .video,
                                    seconds: ExportLength.seconds(song: song, options: videoOptions()))
    }

    private func rendererRefuses(_ song: Song) -> Bool {
        VideoTimeline(song: song, options: videoOptions()).seconds > VideoExport.maxSeconds
    }

    /// The case the review found: 599.985 s by the exact step length, 600.023 s
    /// by whole samples.
    func testA133BpmSongJustOverTheCapIsBlockedOnTheSheet() {
        let song = song(tempo: 133, steps: 5311)
        XCTAssertEqual(song.arrangementSteps, 5311)
        XCTAssertTrue(rendererRefuses(song), "the renderer refuses this one")
        XCTAssertTrue(sheetBlocks(song), "so the sheet must not offer Export")
    }

    func testTheSheetAndTheRendererAgreeNearTheCap() {
        var disagreements: [String] = []
        for tempo in stride(from: 60.0, through: 200.0, by: 1.0) {
            // Steps that put one pass plus the 1 s tail near 600 s.
            let center = Int((599 * tempo * Double(Chip.stepsPerBeat) / 60).rounded())
            for steps in (center - 3)...(center + 3) {
                let song = song(tempo: tempo, steps: steps)
                if sheetBlocks(song) != rendererRefuses(song) {
                    disagreements.append("\(tempo) BPM, \(steps) steps")
                }
            }
        }
        XCTAssertEqual(disagreements, [])
    }
}
