import XCTest
@testable import Chiptune

/// The starter song is 1.8 s, so its first video at 1x ran 4.1 s, more than
/// half of it ring-out. Switching to Video with Repeats untouched now picks
/// enough repeats for at least ten seconds of song before the tail.
final class ExportVideoRepeatsTests: XCTestCase {

    func testTheStarterSongGetsSixRepeats() {
        // The starter song's shape: 16 steps at 132 BPM, about 1.8 s.
        let song = TestSongs.empty(tempo: 132, length: 16)
        XCTAssertEqual(ExportRepeats.forVideo(song: song), 6)
    }

    func testTheSmallestCountReachingTenSeconds() {
        // 16 steps at 96 BPM is 2.5 s, so four passes is exactly ten.
        XCTAssertEqual(ExportRepeats.forVideo(song: TestSongs.empty(tempo: 96, length: 16)), 4)
        // 64 steps at 60 BPM is 16 s: once is plenty.
        XCTAssertEqual(ExportRepeats.forVideo(song: TestSongs.empty(tempo: 60, length: 64)), 1)
    }

    func testNeverPastTheMaximum() {
        let fast = TestSongs.empty(tempo: 300, length: 4)
        XCTAssertEqual(ExportRepeats.forVideo(song: fast), ExportOptions.maxLoopCount)
    }

    func testSwitchingToVideoAtOneRepeatPicksTheCount() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.video, for: song)
        XCTAssertEqual(options.format, .video)
        XCTAssertEqual(options.loopCount, 6)
    }

    func testACountTheUserChoseIsKept() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.setLoopCount(3)
        options.selectFormat(.video, for: song)
        XCTAssertEqual(options.loopCount, 3)
    }

    /// Stepped up and back down to 1 is still the user's choice.
    func testOneChosenOnPurposeIsKept() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.setLoopCount(2)
        options.setLoopCount(1)
        options.selectFormat(.video, for: song)
        XCTAssertEqual(options.loopCount, 1)
    }

    func testOtherFormatsLeaveTheCountAlone() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.midi, for: song)
        XCTAssertEqual(options.loopCount, 1)
        options.selectFormat(.wav, for: song)
        XCTAssertEqual(options.loopCount, 1)
    }

    /// Leaving Video puts the picked count back to 1, and coming back picks
    /// it again.
    func testComingBackToVideoKeepsThePickedCount() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.video, for: song)
        options.selectFormat(.wav, for: song)
        options.selectFormat(.video, for: song)
        XCTAssertEqual(options.loopCount, 6)
    }

    /// Looking at Video picked six repeats, but only for the video: going
    /// back to WAV without touching Repeats exported six passes of a song
    /// the user had asked for once.
    func testLeavingVideoPutsAPickedCountBack() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.video, for: song)
        options.selectFormat(.wav, for: song)
        XCTAssertEqual(options.format, .wav)
        XCTAssertEqual(options.loopCount, 1)
    }

    func testVideoThenMidiThenVideoPicksTheCountAgain() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.video, for: song)
        options.selectFormat(.midi, for: song)
        XCTAssertEqual(options.loopCount, 1)
        options.selectFormat(.video, for: song)
        XCTAssertEqual(options.loopCount, 6)
    }

    /// Stepped to on Video, the count is the user's, and leaving Video
    /// keeps it.
    func testACountSteppedToOnVideoSurvivesLeavingIt() {
        let song = TestSongs.empty(tempo: 132, length: 16)
        var options = ExportOptions()
        options.selectFormat(.video, for: song)
        options.setLoopCount(3)
        options.selectFormat(.wav, for: song)
        XCTAssertEqual(options.loopCount, 3)
    }
}

/// The readout under Repeats.
final class ExportLengthFooterTests: XCTestCase {

    func testAWavSaysTheCountAndLength() {
        XCTAssertEqual(ExportLengthFooter.text(format: .wav, loopCount: 1, seconds: 4.1),
                       "The whole arrangement, 1 time: 0:04.1.")
    }

    func testAVideoSaysItRingsOut() {
        XCTAssertEqual(ExportLengthFooter.text(format: .video, loopCount: 6, seconds: 13.1),
                       "The whole arrangement, 6 times: 0:13. Then it rings out.")
    }

    func testALongVideoAddsItsWarning() {
        XCTAssertEqual(ExportLengthFooter.text(format: .video, loopCount: 16, seconds: 200),
                       "The whole arrangement, 16 times: 3:20. Then it rings out. Over 3:00, YouTube posts it as a regular video, not a Short.")
    }
}
