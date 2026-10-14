import XCTest
@testable import Chiptune

/// A muted track is still in the file, silenced by a CC7 of 0 at its start
/// that a DAW user can remove or raise to get the part back. A muted noise
/// track beside an audible one is the exception: it is left empty.
final class MidiExportMuteTests: XCTestCase {

    private func song(_ kinds: [ChannelKind], muted: Set<Int>) -> Song {
        var song = TestSongs.empty()
        song.tracks = kinds.map { Track(kind: $0) }
        for i in muted { song.tracks[i].muted = true }
        song.patterns[0].rows = kinds.map { _ in
            var row = Pattern.emptyRow
            row[0] = 60
            row[8] = 62
            return row
        }
        return song
    }

    private func controls(_ track: [MidiBytes.Timed]) -> [MidiBytes.Timed] {
        track.filter {
            if case .control = $0.event { return true }
            return false
        }
    }

    func testAMutedTrackKeepsItsNotesAndSetsItsChannelVolumeToZero() throws {
        let midi = try MidiBytes(MidiExport.data(for: song([.pulse1, .triangle], muted: [1])))
        let triangle = midi.tracks[2]
        XCTAssertEqual(controls(triangle), [MidiBytes.Timed(tick: 0, event: .control(channel: 1, controller: 7, value: 0))])
        XCTAssertEqual(MidiBytes.name(of: triangle), "Triangle (muted)")
        // Notes as they'd be unmuted: the triangle's 0.9 volume is velocity
        // round(114.3) = 114.
        XCTAssertEqual(MidiBytes.notes(in: triangle).map { [$0.note, $0.velocity] }, [[60, 114], [62, 114]])
        // The volume is set before the first note can sound.
        let firstNote = triangle.firstIndex {
            if case .noteOn = $0.event { return true }
            return false
        }
        let volume = triangle.firstIndex { if case .control = $0.event { return true }; return false }
        XCTAssertLessThan(try XCTUnwrap(volume), try XCTUnwrap(firstNote))

        // The unmuted pulse beside it is left alone.
        XCTAssertEqual(controls(midi.tracks[1]), [])
        XCTAssertEqual(MidiBytes.name(of: midi.tracks[1]), "Pulse 1")
    }

    func testANamedMutedTrackKeepsItsName() throws {
        var song = song([.pulse2], muted: [0])
        song.tracks[0].name = "Echo"
        let midi = try MidiBytes(MidiExport.data(for: song))
        XCTAssertEqual(MidiBytes.name(of: midi.tracks[1]), "Echo (muted)")
    }

    func testAMutedNoiseTrackOnItsOwnSilencesTheDrumChannel() throws {
        let midi = try MidiBytes(MidiExport.data(for: song([.pulse1, .noise], muted: [1])))
        XCTAssertEqual(controls(midi.tracks[2]),
                       [MidiBytes.Timed(tick: 0, event: .control(channel: 9, controller: 7, value: 0))])
        XCTAssertEqual(MidiBytes.name(of: midi.tracks[2]), "Noise (muted)")
    }

    func testAMutedNoiseTrackBesideAnAudibleOneIsLeftEmpty() throws {
        // A CC7 of 0 on channel 10 would silence the unmuted noise track too,
        // and quiet notes would land on the audible track's keys and ticks.
        // So the muted one keeps its MIDI track and its name, and nothing else.
        let midi = try MidiBytes(MidiExport.data(for: song([.noise, .noise], muted: [1])))
        XCTAssertEqual(midi.tracks.count, 3)
        let audible = midi.tracks[1], muted = midi.tracks[2]
        XCTAssertEqual(controls(audible), [])
        // Hat at volume 0.5 is round(63.5) = 64.
        XCTAssertEqual(MidiBytes.notes(in: audible).map(\.velocity), [64, 64])
        XCTAssertEqual(MidiBytes.name(of: audible), "Noise A")
        // One sixteen-step pattern: 16 × 24 ticks.
        XCTAssertEqual(muted, [
            MidiBytes.Timed(tick: 0, event: .meta(type: 0x03, bytes: Array("Noise B (muted)".utf8))),
            MidiBytes.Timed(tick: 16 * 24, event: .meta(type: 0x2F, bytes: [])),
        ])
    }

    func testEveryMutedNoiseTrackBesideAnAudibleOneIsLeftEmpty() throws {
        let midi = try MidiBytes(MidiExport.data(for: song([.noise, .pulse1, .noise, .noise], muted: [0, 1, 3])))
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[1]), [])
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[4]), [])
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[3]).map(\.velocity), [64, 64])
        // The muted pulse has a channel of its own, so it is silenced as usual.
        XCTAssertEqual(controls(midi.tracks[2]),
                       [MidiBytes.Timed(tick: 0, event: .control(channel: 0, controller: 7, value: 0))])
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[2]).count, 2)
    }

    func testEveryNoiseTrackMutedSilencesTheDrumChannelFromEach() throws {
        let midi = try MidiBytes(MidiExport.data(for: song([.noise, .pulse1, .noise], muted: [0, 2])))
        for i in [1, 3] {
            XCTAssertEqual(controls(midi.tracks[i]),
                           [MidiBytes.Timed(tick: 0, event: .control(channel: 9, controller: 7, value: 0))],
                           "track \(i - 1)")
            XCTAssertEqual(MidiBytes.notes(in: midi.tracks[i]).map(\.velocity), [64, 64], "track \(i - 1)")
        }
    }
}
