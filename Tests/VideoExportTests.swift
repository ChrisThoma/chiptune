import XCTest
import AVFoundation
import SwiftUI
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

    /// Four tracks, 8 steps at 240 BPM: half a second a pass, so a render
    /// with its one-second tail is about 45 frames. Pulse 1 plays on step 0;
    /// pulse 2 stays empty so a probe can tell a lit cell from an unlit one.
    private func song(_ name: String = "Clip \(UUID().uuidString.prefix(6))") -> Song {
        var song = TestSongs.empty(name: name, tempo: 240, length: 8)
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[0][4] = 67
        song.patterns[0].rows[2][0] = 36
        song.patterns[0].rows[3][2] = 62
        return song
    }

    private func export(_ song: Song, _ options: ExportOptions,
                        progress: @escaping @Sendable (Double) -> Void = { _ in },
                        isCanceled: @escaping @Sendable () -> Bool = { false }) -> ExportResult {
        VideoExport.render(ExportRequest(song: song, options: options,
                                         progress: progress, isCanceled: isCanceled))
    }

    private func exported(_ song: Song, _ options: ExportOptions) throws -> URL {
        let result = export(song, options)
        guard case .success(let url) = result else {
            XCTFail("video export did not succeed: \(result)")
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func scratchFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: VideoExport.scratchDirectory.path)) ?? []
    }

    // MARK: The file

    func testAVideoIsWrittenWhereTheSongsExportsGo() throws {
        let song = song()
        let url = try exported(song, videoOptions())
        XCTAssertEqual(url, ExportFiles.url(for: song, format: .video))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTheExportSheetsRendererRoutesVideoHere() throws {
        let song = song()
        guard case .success(let url) = Export.render(ExportRequest(song: song, options: videoOptions())) else {
            return XCTFail("a video export through Export should succeed")
        }
        XCTAssertEqual(url.pathExtension, "mp4")
    }

    func testTheFileHasOnePortraitH264TrackAndOneAacTrack() async throws {
        for style in ExportOptions.VideoStyle.allCases {
            let url = try exported(song(), videoOptions(style: style))
            let asset = AVURLAsset(url: url)
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(video.count, 1, "\(style)")
            XCTAssertEqual(audio.count, 1, "\(style)")
            let size = try await video[0].load(.naturalSize)
            XCTAssertEqual(size, CGSize(width: 1080, height: 1920), "\(style)")
            let videoFormat = try await video[0].load(.formatDescriptions)
            XCTAssertEqual(videoFormat.first.map(CMFormatDescriptionGetMediaSubType), kCMVideoCodecType_H264)
            let audioFormat = try await audio[0].load(.formatDescriptions)
            XCTAssertEqual(audioFormat.first.map(CMFormatDescriptionGetMediaSubType), kAudioFormatMPEG4AAC)
            let rate = try await video[0].load(.nominalFrameRate)
            XCTAssertEqual(rate, 30, accuracy: 0.5, "\(style)")
        }
    }

    /// The video runs as long as its soundtrack, and the soundtrack starts
    /// at zero: AAC's priming samples are trimmed rather than pushing the
    /// audio about 50ms behind the picture.
    func testTheVideoIsAsLongAsItsSoundtrack() async throws {
        let song = song()
        let options = videoOptions(loops: 2)
        let url = try exported(song, options)
        let expected = Double(VideoTimeline(song: song, options: options).totalSamples) / 44100
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, expected, accuracy: 1.0 / 30)
        let audio = try await asset.loadTracks(withMediaType: .audio)[0]
        let range = try await audio.load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(range.duration.seconds, expected, accuracy: 1.0 / 30)
    }

    func testProgressRisesToOne() throws {
        let seen = Recorder()
        guard case .success = export(song(), videoOptions(), progress: { seen.append($0) }) else {
            return XCTFail("export failed")
        }
        let values = seen.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values, values.sorted(), "progress went backwards")
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(values.allSatisfy { (0...1).contains($0) })
        // The frames are most of the work, so the bar spends most of its
        // length on them rather than jumping there after the audio.
        XCTAssertTrue(values.contains { $0 > 0.3 && $0 < 1 })
    }

    // MARK: Cleaning up

    func testCancelingMidRenderLeavesNoVideoAndNoScratch() {
        let song = song()
        let seen = Recorder()
        let result = export(song, videoOptions(loops: 4),
                            progress: { seen.append($0) },
                            isCanceled: { (seen.values.last ?? 0) > 0.5 })
        guard case .canceled = result else { return XCTFail("expected a cancel, got \(result)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExportFiles.url(for: song, format: .video).path))
        XCTAssertEqual(scratchFiles(), [])
    }

    /// Cancel tapped while the writer is finishing the file — after the last
    /// frame, before the move — is still a cancel: the old video stays and
    /// nothing is handed to the share sheet.
    func testACancelDuringFinishWritingKeepsThePreviousVideo() throws {
        let song = song()
        let first = try exported(song, videoOptions())
        let before = try Data(contentsOf: first)
        let finished = Flag()
        let result = VideoExport.render(
            ExportRequest(song: song, options: videoOptions(loops: 2),
                          isCanceled: { finished.isSet }),
            hooks: VideoExport.Hooks(finishedWriting: { finished.set() }))
        XCTAssertTrue(finished.isSet, "the render should have reached the end of writing")
        guard case .canceled = result else { return XCTFail("expected a cancel, got \(result)") }
        XCTAssertEqual(try Data(contentsOf: first), before, "the previous video was replaced")
        XCTAssertEqual(scratchFiles(), [])
    }

    /// A crash or a kill mid-render skips the cleanup, so the next export
    /// clears whatever the last one left. Only one export runs at a time
    /// (`Studio.export` refuses a second), so nothing in there is live.
    func testAnExportSweepsScratchLeftByAKilledOne() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: VideoExport.scratchDirectory, withIntermediateDirectories: true)
        let stale = VideoExport.scratchDirectory.appendingPathComponent("killed.mp4")
        try Data(repeating: 1, count: 1024).write(to: stale)
        _ = try exported(song(), videoOptions())
        XCTAssertFalse(fm.fileExists(atPath: stale.path), "the killed export's partial file is still there")
        XCTAssertEqual(scratchFiles(), [])
    }

    func testASuccessLeavesNoScratch() throws {
        _ = try exported(song(), videoOptions())
        XCTAssertEqual(scratchFiles(), [])
    }

    func testAFailedWriteLeavesNoScratchAndReportsTheError() throws {
        let song = song()
        let dir = ExportFiles.url(for: song, format: .video).deletingLastPathComponent()
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let result = export(song, videoOptions())
        guard case .failed = result else { return XCTFail("expected a failure, got \(result)") }
        XCTAssertEqual(scratchFiles(), [])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [])
    }

    /// The soundtrack goes to a scratch file, never to the song's WAV export.
    func testTheUsersWavOfTheSameSongIsUntouched() throws {
        let song = song()
        guard case .success(let wav) = WavExport.render(ExportRequest(song: song)) else {
            return XCTFail("WAV export failed")
        }
        let before = try Data(contentsOf: wav)
        _ = try exported(song, videoOptions(loops: 3))
        XCTAssertEqual(try Data(contentsOf: wav), before)
    }

    // MARK: The picture

    private func firstFrame(_ url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: .zero).image
    }

    /// RGB at a point in top-left pixel coordinates.
    private func pixel(_ image: CGImage, _ point: CGPoint) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Draw the image shifted so the wanted pixel lands on the 1×1 context.
        // Core Graphics counts y from the bottom.
        context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func assertColor(_ got: (r: Int, g: Int, b: Int), _ want: UIColor,
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        want.getRed(&r, green: &g, blue: &b, alpha: &a)
        let expected = (Int(r * 255), Int(g * 255), Int(b * 255))
        let close = abs(got.r - expected.0) <= 24 && abs(got.g - expected.1) <= 24 && abs(got.b - expected.2) <= 24
        XCTAssertTrue(close, "\(message): got \(got), want \(expected)", file: file, line: line)
    }

    private func isFar(_ got: (r: Int, g: Int, b: Int), _ from: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        from.getRed(&r, green: &g, blue: &b, alpha: &a)
        return abs(got.r - Int(r * 255)) + abs(got.g - Int(g * 255)) + abs(got.b - Int(b * 255)) > 120
    }

    /// On the first frame the playing row is step 0, where pulse 1 has a
    /// note: its cell is filled with the pulse 1 colour, and pulse 2's empty
    /// cell beside it is not.
    func testTheGridsFirstFrameLightsTheFirstStepInItsChannelColour() async throws {
        let song = song()
        let image = try await firstFrame(try exported(song, videoOptions(style: .grid)))
        XCTAssertEqual(image.width, 1080)
        let layout = VideoLayout(trackCount: song.tracks.count)
        let red = UIColor(Theme.color(for: .pulse1))
        let lit = layout.cellRect(track: 0, centerY: layout.playheadY)
        assertColor(pixel(image, CGPoint(x: lit.minX + 16, y: lit.midY)), red, "pulse 1 at step 0")
        let empty = layout.cellRect(track: 1, centerY: layout.playheadY)
        XCTAssertTrue(isFar(pixel(image, CGPoint(x: empty.minX + 16, y: empty.midY)),
                            UIColor(Theme.color(for: .pulse2))), "pulse 2 has no note at step 0")
    }

    /// The Cover style's bar for a track with a note on step 0 is lit in its
    /// colour on the first frame; one with nothing to play is not.
    func testTheCoversFirstFrameLightsTheBarOfATrackThatPlays() async throws {
        let song = song()
        let image = try await firstFrame(try exported(song, videoOptions(style: .cover)))
        let layout = VideoLayout(trackCount: song.tracks.count)
        let bar = layout.coverBarRect(track: 0)
        assertColor(pixel(image, CGPoint(x: bar.midX, y: bar.maxY - 20)),
                    UIColor(Theme.color(for: .pulse1)), "pulse 1's bar")
        let quiet = layout.coverBarRect(track: 1)
        XCTAssertTrue(isFar(pixel(image, CGPoint(x: quiet.midX, y: quiet.maxY - 20)),
                            UIColor(Theme.color(for: .pulse2))), "pulse 2 never plays")
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

/// A thread-safe list of progress values.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Double] = []
    var values: [Double] { lock.withLock { list } }
    func append(_ value: Double) { lock.withLock { list.append(value) } }
}

/// A thread-safe switch that only turns on.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var isSet: Bool { lock.withLock { on } }
    func set() { lock.withLock { on = true } }
}

/// A thread-safe tally for closures the renderer calls off the main thread.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}
