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
                       accuracy: 0.0001)
    }

    func testASeamlessWavHasNoTail() {
        let song = TestSongs.empty()
        var options = ExportOptions()
        options.tailMode = .seamlessLoop
        XCTAssertEqual(ExportLength.seconds(song: song, options: options),
                       song.arrangementDuration, accuracy: 0.0001)
    }

    func testAVideoOverThreeMinutesWarnsAboutReelsAndShorts() {
        XCTAssertEqual(ExportLength.warning(format: .video, seconds: 181), "Reels and Shorts cut off at 3:00.")
        XCTAssertNil(ExportLength.warning(format: .video, seconds: 180))
    }

    func testAWavOverThreeMinutesHasNoWarning() {
        XCTAssertNil(ExportLength.warning(format: .wav, seconds: 400))
    }

    func testAVideoOverTheCapSaysItIsTooLong() {
        XCTAssertEqual(ExportLength.warning(format: .video, seconds: 601), "Too long for a video — 10:00 max.")
    }
}
