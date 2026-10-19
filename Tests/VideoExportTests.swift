import XCTest
import AVFoundation
@testable import Chiptune

/// The video export end to end: a scratch soundtrack, frames drawn for it,
/// and an mp4 that social apps take.
final class VideoExportTests: XCTestCase {

    private func videoOptions(loops: Int = 1, style: ExportOptions.VideoStyle = .grid) -> ExportOptions {
        var options = ExportOptions()
        options.format = .video
        options.loopCount = loops
        options.videoStyle = style
        return options
    }

    // MARK: Too long

    /// Longer than TikTok takes. Found from the timeline before anything is
    /// rendered, rather than after minutes of drawing frames.
    func testAVideoOverTenMinutesIsRejectedBeforeRendering() {
        // 40 BPM, 64 steps twice: 48 s a pass, 16 passes: 12:48.
        var song = TestSongs.empty(name: "Long", tempo: 40, length: 64)
        song.patterns[0].rows[0][0] = 60
        song.arrangement[0].repeats = 2
        let polled = CallCounter()
        let progressed = CallCounter()
        let result = VideoExport.render(ExportRequest(
            song: song,
            options: videoOptions(loops: 16),
            progress: { _ in progressed.bump() },
            isCanceled: { polled.bump(); return false }))
        guard case .tooLong = result else { return XCTFail("expected tooLong, got \(result)") }
        XCTAssertEqual(polled.value, 0, "nothing should have been rendered")
        XCTAssertEqual(progressed.value, 0, "nothing should have been rendered")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ExportFiles.url(for: song, format: .video).path))
    }

    func testTheCapIsTenMinutes() {
        XCTAssertEqual(VideoExport.maxSeconds, 600)
    }
}

/// A thread-safe tally for closures the renderer calls off the main thread.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
