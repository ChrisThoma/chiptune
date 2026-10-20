import XCTest
@testable import Chiptune

/// The Cover style's bars: each track flashes on a note and fades. A bar that
/// moves for a note nobody hears would be lying about the music, so silent
/// tracks and non-notes stay dark.
final class ChannelPulseTests: XCTestCase {

    /// 150 BPM: a step is exactly three frames. Two tracks, all rests.
    private func song() -> Song {
        var song = TestSongs.empty(name: "Pulse", tempo: 150, length: 16)
        song.tracks = [Track(kind: .pulse1), Track(kind: .triangle)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        return song
    }

    private func pulse(_ song: Song, loops: Int = 1) -> ChannelPulse {
        var options = ExportOptions()
        options.format = .video
        options.loopCount = loops
        return ChannelPulse(song: song, timeline: VideoTimeline(song: song, options: options))
    }

    func testThereIsOneLevelPerTrack() {
        XCTAssertEqual(pulse(song()).levels(frame: 0).count, 2)
    }

    func testANoteFlashesFullAndFadesSteadilyToNothing() {
        var song = song()
        song.patterns[0].rows[0][0] = 60
        let pulse = pulse(song)
        XCTAssertEqual(pulse.levels(frame: 0)[0], 1.0)
        var last = 1.0
        for frame in 1..<ChannelPulse.decayFrames {
            let level = pulse.levels(frame: frame)[0]
            XCTAssertLessThan(level, last, "frame \(frame)")
            XCTAssertGreaterThan(level, 0, "frame \(frame)")
            last = level
        }
        XCTAssertEqual(pulse.levels(frame: ChannelPulse.decayFrames)[0], 0)
        XCTAssertEqual(pulse.levels(frame: ChannelPulse.decayFrames + 5)[0], 0)
    }

    func testTheNextNoteFlashesAgain() {
        var song = song()
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[0][2] = 64
        let pulse = pulse(song)
        XCTAssertLessThan(pulse.levels(frame: 5)[0], 1)
        XCTAssertEqual(pulse.levels(frame: 6)[0], 1)
    }

    func testARestGivesNoPulse() {
        var song = song()
        song.patterns[0].rows[0][0] = 60
        let pulse = pulse(song)
        for frame in 0..<48 { XCTAssertEqual(pulse.levels(frame: frame)[1], 0, "frame \(frame)") }
    }

    func testANoteOffGivesNoPulseAndCutsTheOneBefore() {
        var song = song()
        song.patterns[0].rows[1][0] = Chip.noteOff
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[0][1] = Chip.noteOff
        let pulse = pulse(song)
        XCTAssertEqual(pulse.levels(frame: 0)[1], 0)
        XCTAssertGreaterThan(pulse.levels(frame: 2)[0], 0)
        XCTAssertEqual(pulse.levels(frame: 3)[0], 0)
    }

    func testAMutedTrackGivesNoPulse() {
        var song = song()
        song.patterns[0].rows[0][0] = 60
        song.tracks[0].muted = true
        XCTAssertEqual(pulse(song).levels(frame: 0)[0], 0)
    }

    /// The same rule as the MIDI export's: a volume that rounds to velocity 0
    /// is silent, not just one at exactly 0.
    func testASilentVolumeGivesNoPulse() {
        for volume in [0.0, 0.003] {
            var song = song()
            song.patterns[0].rows[0][0] = 60
            song.tracks[0].instrument.volume = volume
            XCTAssertEqual(pulse(song).levels(frame: 0)[0], 0, "\(volume)")
        }
        var quiet = song()
        quiet.patterns[0].rows[0][0] = 60
        quiet.tracks[0].instrument.volume = 0.01
        XCTAssertEqual(pulse(quiet).levels(frame: 0)[0], 1)
    }

    /// Both styles dim a track's name by the same rule the bars go dark by:
    /// muted, or a volume the MIDI export would call silent.
    func testBothStylesDimTheNamesOfTheSameSilentTracks() {
        var muted = Track(kind: .pulse1)
        muted.muted = true
        var zero = Track(kind: .pulse2)
        zero.instrument.volume = 0
        var roundsToZero = Track(kind: .triangle)
        roundsToZero.instrument.volume = 0.003
        var quiet = Track(kind: .noise)
        quiet.instrument.volume = 0.01
        let cases: [(String, Track, Bool)] = [
            ("muted", muted, true), ("volume 0", zero, true),
            ("volume 0.003", roundsToZero, true), ("volume 0.01", quiet, false),
            ("plain", Track(kind: .pulse1), false),
        ]
        for style in ExportOptions.VideoStyle.allCases {
            for (name, track, dim) in cases {
                XCTAssertEqual(VideoFrameRenderer.dimsName(of: track, in: style), dim, "\(style) / \(name)")
            }
        }
    }

    /// The last note of the song keeps fading into the ring-out rather than
    /// switching off where the body ends.
    func testTheLastNoteFadesIntoTheTail() {
        var song = song()
        song.patterns[0].length = 4
        song.patterns[0].rows[0][3] = 60
        let pulse = pulse(song)
        // Step 3 starts at frame 9; the body ends at frame 12.
        XCTAssertEqual(pulse.levels(frame: 9)[0], 1)
        XCTAssertGreaterThan(pulse.levels(frame: 13)[0], 0)
        XCTAssertLessThan(pulse.levels(frame: 13)[0], pulse.levels(frame: 12)[0])
    }

    // MARK: Shared fixture

    private struct Fixture: Decodable {
        struct Row: Decodable {
            let frame: Int
            let levels: [Double]?
        }
        let loopCount: Int
        let song: Song
        let frames: [Row]
    }

    /// `video-timeline.json` carries every frame's bar levels, worked out by
    /// the reference script: a muted track that stays dark, a sustaining one
    /// that still flashes, note-offs, and the fade on into the tail.
    func testTheSharedFixtureLevelsMatch() throws {
        let data = try Data(contentsOf: try FixtureFiles.url("video-timeline.json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let pulse = pulse(fixture.song, loops: fixture.loopCount)
        let rows = fixture.frames.filter { $0.levels != nil }
        XCTAssertEqual(rows.count, fixture.frames.count, "every frame has its levels")
        XCTAssertTrue(rows.contains { $0.levels?.contains(where: { $0 > 0 && $0 < 1 }) == true }, "some bar is mid-fade")
        for row in rows {
            let want = row.levels ?? []
            let got = pulse.levels(frame: row.frame)
            XCTAssertEqual(got.count, want.count, "frame \(row.frame)")
            for (index, level) in zip(got, want).enumerated() {
                XCTAssertEqual(level.0, level.1, accuracy: 1e-9, "frame \(row.frame) / track \(index)")
            }
        }
    }

    /// The first step of the second pass is the first step again.
    func testTheSecondPassFlashesAgain() {
        var song = song()
        song.patterns[0].length = 4
        song.patterns[0].rows[0][0] = 60
        XCTAssertEqual(pulse(song, loops: 2).levels(frame: 12)[0], 1)
    }
}
