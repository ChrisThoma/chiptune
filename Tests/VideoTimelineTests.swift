import XCTest
@testable import Chiptune

/// Which step each video frame shows. The picture is only worth anything if
/// it agrees with the audio sample for sample, so these pin the mapping to
/// the same step length and chain the WAV renderer plays.
final class VideoTimelineTests: XCTestCase {

    private func videoOptions(loops: Int = 1) -> ExportOptions {
        var options = ExportOptions()
        options.format = .video
        options.loopCount = loops
        return options
    }

    /// 150 BPM is 4410 samples a step: exactly three frames.
    private func evenSong() -> Song {
        var song = TestSongs.empty(name: "Even", tempo: 150, length: 4)
        song.patterns[0].rows[0][0] = 60
        return song
    }

    func testFrameZeroIsTheFirstStep() {
        let timeline = VideoTimeline(song: evenSong(), options: videoOptions())
        XCTAssertEqual(timeline.position(frame: 0),
                       VideoTimeline.Position(chainSlot: 0, pattern: 0, step: 0))
    }

    func testAFrameOnAStepBoundaryShowsTheNewStep() {
        let timeline = VideoTimeline(song: evenSong(), options: videoOptions())
        XCTAssertEqual(timeline.samplesPerStep, 3 * VideoTimeline.samplesPerFrame)
        XCTAssertEqual(timeline.position(frame: 2)?.step, 0)
        XCTAssertEqual(timeline.position(frame: 3)?.step, 1)
        XCTAssertEqual(timeline.position(frame: 11)?.step, 3)
    }

    /// Repeats expand into chain slots, so the second play of a section is
    /// its own slot even though it shows the same pattern.
    func testSectionRepeatsWalkTheChain() {
        let song = TestSongs.twoPatterns(lengths: (4, 4), repeats: (2, 1), tempo: 150)
        let timeline = VideoTimeline(song: song, options: videoOptions())
        let perPattern = 4 * 3
        XCTAssertEqual(timeline.position(frame: 0), .init(chainSlot: 0, pattern: 0, step: 0))
        XCTAssertEqual(timeline.position(frame: perPattern), .init(chainSlot: 1, pattern: 0, step: 0))
        XCTAssertEqual(timeline.position(frame: 2 * perPattern + 3), .init(chainSlot: 2, pattern: 1, step: 1))
    }

    func testTheSecondPassStartsAgainAtSlotZero() {
        let song = TestSongs.twoPatterns(lengths: (4, 4), repeats: (1, 1), tempo: 150)
        let timeline = VideoTimeline(song: song, options: videoOptions(loops: 2))
        let onePass = 8 * 3
        XCTAssertEqual(timeline.position(frame: onePass - 1), .init(chainSlot: 1, pattern: 1, step: 3))
        XCTAssertEqual(timeline.position(frame: onePass), .init(chainSlot: 0, pattern: 0, step: 0))
    }

    func testTailFramesShowNoStepAndTheFrameCountCoversTheAudio() {
        let song = evenSong()
        let timeline = VideoTimeline(song: song, options: videoOptions())
        let body = 4 * 4410
        let tail = Int(44100 * WavExport.tailSeconds(for: song))
        XCTAssertEqual(timeline.bodySamples, body)
        XCTAssertEqual(timeline.tailSamples, tail)
        XCTAssertEqual(timeline.totalSamples, body + tail)
        XCTAssertEqual(timeline.totalFrames,
                       Int((Double(body + tail) / 44100 * 30).rounded(.up)))
        XCTAssertNotNil(timeline.position(frame: body / 1470 - 1))
        XCTAssertNil(timeline.position(frame: body / 1470))
        XCTAssertNil(timeline.position(frame: timeline.totalFrames - 1))
    }

    /// The timeline's length is the soundtrack's length, so the video ends
    /// with its audio rather than cutting it or running on in silence.
    func testTheTotalIsTheLengthOfTheRenderedSoundtrack() throws {
        let song = TestSongs.twoPatterns(lengths: (16, 8), repeats: (2, 1), tempo: 133)
        let options = videoOptions(loops: 2)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard case .success = WavExport.render(ExportRequest(song: song, options: options), to: scratch) else {
            return XCTFail("render failed")
        }
        let samples = (try Data(contentsOf: scratch).count - 44) / 2
        XCTAssertEqual(VideoTimeline(song: song, options: options).totalSamples, samples)
    }

    /// The renderer normalizes first, and so does the timeline: an imported
    /// tempo past the range plays at 300 BPM, so it must draw at 300 too.
    func testTheSongIsNormalizedFirst() {
        var song = evenSong()
        song.tempo = 1000
        let timeline = VideoTimeline(song: song, options: videoOptions())
        XCTAssertEqual(timeline.samplesPerStep, Chip.samplesPerStep(tempo: 300, sampleRate: 44100))
    }

    // MARK: Shared fixture

    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let samplesPerStep: Int
            let chain: [Int]
            let arrangementSteps: Int
            let bodySamples: Int
            let tailSamples: Int
            let totalSamples: Int
            let totalFrames: Int
        }
        struct Row: Decodable {
            let frame: Int
            let chainSlot: Int?
            let pattern: Int?
            let step: Int?
        }
        let sampleRate: Int
        let fps: Int
        let samplesPerFrame: Int
        let loopCount: Int
        let song: Song
        let expected: Expected
        let frames: [Row]
    }

    /// The Android suite reads the same file, so both platforms draw the
    /// same step on the same frame.
    func testTheSharedFixtureMatches() throws {
        let data = try Data(contentsOf: try FixtureFiles.url("video-timeline.json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        XCTAssertEqual(fixture.sampleRate, Int(WavExport.sampleRate))
        XCTAssertEqual(fixture.fps, VideoTimeline.fps)
        XCTAssertEqual(fixture.samplesPerFrame, VideoTimeline.samplesPerFrame)

        let timeline = VideoTimeline(song: fixture.song, options: videoOptions(loops: fixture.loopCount))
        XCTAssertEqual(timeline.samplesPerStep, fixture.expected.samplesPerStep)
        XCTAssertEqual(timeline.chain, fixture.expected.chain)
        XCTAssertEqual(fixture.song.arrangementSteps, fixture.expected.arrangementSteps)
        XCTAssertEqual(timeline.bodySamples, fixture.expected.bodySamples)
        XCTAssertEqual(timeline.tailSamples, fixture.expected.tailSamples)
        XCTAssertEqual(timeline.totalSamples, fixture.expected.totalSamples)
        XCTAssertEqual(timeline.totalFrames, fixture.expected.totalFrames)
        XCTAssertEqual(fixture.frames.count, fixture.expected.totalFrames)

        for row in fixture.frames {
            let expected = row.chainSlot.map {
                VideoTimeline.Position(chainSlot: $0, pattern: row.pattern ?? -1, step: row.step ?? -1)
            }
            XCTAssertEqual(timeline.position(frame: row.frame), expected, "frame \(row.frame)")
        }
    }
}
