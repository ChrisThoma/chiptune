import XCTest
@testable import Chiptune

/// Which channel and sound each track gets, what it's called, and how loud
/// its notes are.
final class MidiExportChannelTests: XCTestCase {

    /// One track per kind given, each with a note on step 0.
    private func song(_ kinds: [ChannelKind]) -> Song {
        var song = TestSongs.empty()
        song.tracks = kinds.map { Track(kind: $0) }
        song.patterns[0].rows = kinds.map { _ in
            var row = Pattern.emptyRow
            row[0] = 60
            return row
        }
        return song
    }

    private func parse(_ song: Song) throws -> MidiBytes {
        try MidiBytes(MidiExport.data(for: song))
    }

    // MARK: Channels and programs

    func testMelodicTracksCountUpFromZeroAndNoiseSharesTheDrumChannel() throws {
        let kinds: [ChannelKind] = [.pulse1, .noise, .pulse2, .triangle, .noise, .pulse1, .triangle, .pulse2]
        let midi = try parse(song(kinds))
        // Noise is channel 10 to a person, 9 on the wire.
        let expected = [0, 9, 1, 2, 9, 3, 4, 5]
        for (i, channel) in expected.enumerated() {
            XCTAssertEqual(MidiBytes.notes(in: midi.tracks[i + 1]).map(\.channel), [channel], "track \(i)")
        }
    }

    func testPulseGetsSquareLeadTriangleGetsSynthBassAndNoiseGetsNoProgram() throws {
        let kinds: [ChannelKind] = [.pulse1, .noise, .pulse2, .triangle, .noise, .pulse1, .triangle, .pulse2]
        let midi = try parse(song(kinds))
        // GM program 81 "Lead 1 (square)" and 39 "Synth Bass 1", counted from
        // zero on the wire: 80 and 38.
        let expected: [[MidiBytes.Event]] = [
            [.program(channel: 0, program: 80)],
            [],
            [.program(channel: 1, program: 80)],
            [.program(channel: 2, program: 38)],
            [],
            [.program(channel: 3, program: 80)],
            [.program(channel: 4, program: 38)],
            [.program(channel: 5, program: 80)],
        ]
        for (i, programs) in expected.enumerated() {
            let actual = midi.tracks[i + 1].filter {
                if case .program = $0.event { return true }
                return false
            }
            XCTAssertEqual(actual.map(\.event), programs, "track \(i)")
            XCTAssertTrue(actual.allSatisfy { $0.tick == 0 }, "track \(i)")
        }
    }

    func testATrackOpensWithItsNameThenItsProgramThenItsNotes() throws {
        let midi = try parse(song([.triangle]))
        let opening = midi.tracks[1].prefix(3).map(\.event)
        XCTAssertEqual(opening.count, 3)
        guard opening.count == 3 else { return }
        XCTAssertEqual(opening[0], .meta(type: 0x03, bytes: Array("Triangle".utf8)))
        XCTAssertEqual(opening[1], .program(channel: 0, program: 38))
        guard case .noteOn(0, 60, _) = opening[2] else { return XCTFail("third is \(opening[2])") }
    }

    // MARK: Names

    func testTracksAreNamedAsTheEditorNamesThem() throws {
        var song = song([.triangle, .triangle, .pulse1, .noise])
        song.tracks[2].name = "Bässe"
        let midi = try parse(song)
        XCTAssertEqual(midi.chipTracks.map { MidiBytes.name(of: $0) },
                       ["Triangle A", "Triangle B", "Bässe", "Noise"])
        // "ä" is two bytes, so six bytes for five letters.
        XCTAssertEqual(MidiBytes.metas(0x03, in: midi.tracks[3]),
                       [[0x42, 0xC3, 0xA4, 0x73, 0x73, 0x65]])
    }

    // MARK: Velocity

    func testVelocityFollowsTheTracksVolume() throws {
        // round(volume × 127). One that rounds to 0 is a silent track: a
        // note-on at velocity 0 is a note-off, so its notes go in at 1 and
        // its channel's volume is set to 0, as a muted track's is.
        let cases: [(volume: Double, velocity: Int, silent: Bool)] = [
            (1.0, 127, false),
            (0.8, 102, false),   // 101.6
            (0.6, 76, false),    // 76.2
            (0.5, 64, false),    // 63.5, half rounds up
            (0.45, 57, false),   // 57.15
            (0.01, 1, false),    // 1.27
            (0.0, 1, true),
        ]
        var song = song(Array(repeating: .pulse1, count: cases.count))
        for (i, c) in cases.enumerated() { song.tracks[i].instrument.volume = c.volume }
        let midi = try parse(song)
        for (i, c) in cases.enumerated() {
            let track = midi.tracks[i + 1]
            XCTAssertEqual(MidiBytes.notes(in: track).map(\.velocity), [c.velocity], "volume \(c.volume)")
            let volumes = track.filter {
                if case .control(_, 7, 0) = $0.event { return true }
                return false
            }
            XCTAssertEqual(volumes.count, c.silent ? 1 : 0, "volume \(c.volume)")
        }
    }

    func testNoiseTracksKeepTheirOwnVelocityOnTheSharedChannel() throws {
        var song = song([.noise, .noise])
        song.tracks[0].instrument.volume = 0.9
        song.tracks[1].instrument.volume = 0.3
        let midi = try parse(song)
        // 114.3 and 38.1.
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[1]).map(\.velocity), [114])
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[2]).map(\.velocity), [38])
    }
}
