import XCTest
@testable import Chiptune

/// Noise tracks come out as General MIDI drums on channel 10, because a pitch
/// played on the drum channel picks a drum, not a note.
final class MidiExportDrumTests: XCTestCase {

    /// GM percussion keys, from the GM 1 drum map.
    private let kick = 36, snare = 38, closedHat = 42, openHat = 46, crash = 49

    /// One noise track playing `cells` from step 0 with `instrument`.
    private func song(_ cells: [Int8], instrument: Instrument) -> Song {
        var song = TestSongs.empty()
        song.tracks = [Track(kind: .noise)]
        song.tracks[0].instrument = instrument
        song.patterns[0].rows = [Pattern.emptyRow]
        for (step, n) in cells.enumerated() { song.patterns[0].rows[0][step] = n }
        return song
    }

    /// Edited away from every preset, which the instrument menu shows as
    /// "Custom".
    private var custom: Instrument {
        Instrument(duty: 2, volume: 0.55, decay: 0.2)
    }

    private func drumNotes(_ song: Song) throws -> [MidiBytes.Note] {
        let midi = try MidiBytes(MidiExport.data(for: song))
        return midi.chipTracks.flatMap { MidiBytes.notes(in: $0) }
    }

    // MARK: Presets

    func testEachNoisePresetPlaysItsOwnDrumWhenTheTrackPlaysOnePitch() throws {
        let expected = ["Kick": kick, "Snare": snare, "Hat": openHat, "Closed hat": closedHat, "Crash": crash]
        let presets = InstrumentPreset.presets(for: .noise)
        XCTAssertEqual(Set(presets.map(\.name)), Set(expected.keys),
                       "a new noise preset needs a drum of its own")
        for preset in presets {
            let notes = try drumNotes(song([40, -1, 40, -1, 40], instrument: preset.instrument))
            XCTAssertEqual(notes.map(\.note), Array(repeating: expected[preset.name]!, count: 3), preset.name)
            XCTAssertEqual(Set(notes.map(\.channel)), [9], preset.name)
        }
    }

    /// A preset track written at several pitches is someone writing a kit by
    /// pitch, so it is banded like a custom one, whichever preset it is.
    func testAPresetTrackPlayingSeveralPitchesIsBandedByPitch() throws {
        for preset in InstrumentPreset.presets(for: .noise) {
            XCTAssertEqual(try drumNotes(song([60, 50, 70], instrument: preset.instrument)).map(\.note),
                           [snare, kick, closedHat], preset.name)
        }
    }

    /// The default track every new song starts with is the Hat preset. A
    /// beginner who writes kick, snare and hat on it by pitch gets them, not
    /// a bar of open hats.
    func testTheDefaultHatTrackWrittenAtThreePitchesPlaysKickSnareAndHat() throws {
        let track = Track(kind: .noise)
        XCTAssertEqual(InstrumentPreset.matching(track.instrument, kind: .noise)?.name, "Hat",
                       "the premise: a new noise track is the Hat preset")
        let notes = try drumNotes(song([36, -1, 48, -1, 60, -1, 48], instrument: track.instrument))
        XCTAssertEqual(notes.map(\.note), [kick, snare, closedHat, snare])
    }

    /// Volume is how loud the drum is, not which drum it is, and duty means
    /// nothing to the noise channel. A preset nudged in either is still that
    /// preset's drum.
    func testAPresetWithItsVolumeOrDutyChangedStillPlaysItsDrum() throws {
        let presets = InstrumentPreset.presets(for: .noise)
        let kickPreset = try XCTUnwrap(presets.first { $0.name == "Kick" })
        var louder = kickPreset.instrument
        louder.volume = 0.5
        XCTAssertEqual(try drumNotes(song([60, -1, 60, -1, 60], instrument: louder)).map(\.note),
                       [kick, kick, kick])

        let crashPreset = try XCTUnwrap(presets.first { $0.name == "Crash" })
        var otherDuty = crashPreset.instrument
        otherDuty.duty = 0
        otherDuty.volume = 0.3
        XCTAssertEqual(try drumNotes(song([60, -1, 60], instrument: otherDuty)).map(\.note),
                       [crash, crash])
    }

    /// Decay, hold and arpeggio change the sound itself, so a preset edited
    /// in any of them is custom and is banded by pitch.
    func testAPresetWithItsSoundChangedIsBandedByPitch() throws {
        let kickPreset = try XCTUnwrap(InstrumentPreset.presets(for: .noise).first { $0.name == "Kick" })
        var longer = kickPreset.instrument
        longer.decay = 0.2
        var held = kickPreset.instrument
        held.sustain = true
        var arp = kickPreset.instrument
        arp.arpeggio = [0, 12]
        for instrument in [longer, held, arp] {
            XCTAssertEqual(try drumNotes(song([60, 50, 70], instrument: instrument)).map(\.note),
                           [snare, kick, closedHat], "\(instrument)")
        }
    }

    // MARK: Custom

    func testCustomNoiseSpreadsItsDistinctNotesOverKickSnareAndHat() throws {
        // Sorted distinct notes, note i of n in band i × 3 / n (whole-number
        // division): 0 kick, 1 snare, 2 closed hat.
        let cases: [(cells: [Int8], drums: [Int])] = [
            // n = 1 is the one exception: a lone note is a snare, not a kick.
            ([65, -1, 65], [snare, snare]),
            // n = 2: bands 0 and 3/2 = 1.
            ([70, 50], [snare, kick]),
            // n = 3: bands 0, 1, 2.
            ([60, 50, 70], [snare, kick, closedHat]),
            // n = 4, sorted 50 55 60 65: bands 0, 3/4 = 0, 6/4 = 1, 9/4 = 2.
            ([65, 50, 60, 55], [closedHat, kick, snare, kick]),
        ]
        for c in cases {
            XCTAssertEqual(try drumNotes(song(c.cells, instrument: custom)).map(\.note), c.drums,
                           "cells \(c.cells)")
        }
    }

    func testOnlyNotesTheArrangementPlaysCountTowardTheBands() throws {
        // 50 60 70 alone are bands 0 1 2. Counting the 80 past the pattern's
        // end, or the 90 in a pattern nothing plays, would shift them down.
        var song = song([50, -1, 60, -1, 70], instrument: custom)
        song.patterns[0].rows[0][20] = 80
        var unused = Pattern(name: "B", length: 16, trackCount: 1)
        unused.rows[0][0] = 90
        song.patterns.append(unused)
        XCTAssertEqual(try drumNotes(song).map(\.note), [kick, snare, closedHat])
    }

    func testEachCustomTrackIsBandedOnItsOwnNotes() throws {
        var song = TestSongs.empty()
        song.tracks = [Track(kind: .noise), Track(kind: .noise)]
        song.tracks[0].instrument = custom
        song.tracks[1].instrument = custom
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        song.patterns[0].rows[0][0] = 40
        song.patterns[0].rows[0][4] = 80
        song.patterns[0].rows[1][2] = 60
        let midi = try MidiBytes(MidiExport.data(for: song))
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[1]).map(\.note), [kick, snare])
        XCTAssertEqual(MidiBytes.notes(in: midi.tracks[2]).map(\.note), [snare])
    }

    /// Why the bands are relative. The library songs keep their noise notes
    /// between 52 and 71, so fixed pitch ranges would make nearly every hit
    /// a snare. Boss Door's noise track is a custom instrument.
    func testALibrarySongsDrumsUseAllThreeBands() throws {
        let song = try SongDocument.decode(Data(contentsOf: FixtureFiles.url("song-library-boss-door.chipsong")))
        let noise = try XCTUnwrap(song.tracks.firstIndex { $0.kind == .noise })
        XCTAssertNil(InstrumentPreset.matching(song.tracks[noise].instrument, kind: .noise))
        let written = Set(song.chain.flatMap { song.patterns[$0].rows[noise].prefix(song.patterns[$0].length) }
            .filter { $0 >= 0 })
        XCTAssertTrue(written.allSatisfy { (52...71).contains($0) }, "the premise: \(written.sorted())")

        let midi = try MidiBytes(MidiExport.data(for: song))
        let drums = Set(MidiBytes.notes(in: midi.tracks[noise + 1]).map(\.note))
        XCTAssertEqual(drums, [kick, snare, closedHat])
    }

    // MARK: Length

    func testANoiseNoteLastsAtMostOneTickShortOfAStep() throws {
        // Every noise track shares channel 10, so one track's off must never
        // land on the tick where another starts the same drum: a DAW merging
        // the tracks could put the off second and swallow the hit. 23 ticks
        // is the longest that guarantees it.
        let crash = try XCTUnwrap(InstrumentPreset.presets(for: .noise).first { $0.name == "Crash" })
        // Crash decays for 1.4 s, which would be round(1.4 × 2 × 96) = 269 ticks.
        XCTAssertEqual(try drumNotes(song([60], instrument: crash.instrument)).map { [$0.on, $0.off] },
                       [[0, 23]])

        var held = custom
        held.sustain = true
        XCTAssertEqual(try drumNotes(song([-1, 60], instrument: held)).map { [$0.on, $0.off] },
                       [[24, 47]])

        // The cap only ever shortens. Closed hat decays in
        // round(0.04 × 2 × 96) = round(7.68) = 8 ticks, inside it.
        let closed = try XCTUnwrap(InstrumentPreset.presets(for: .noise).first { $0.name == "Closed hat" })
        XCTAssertEqual(try drumNotes(song([60, 60], instrument: closed.instrument)).map { [$0.on, $0.off] },
                       [[0, 8], [24, 32]])
    }

    func testTwoNoiseTracksOnOneDrumNeverMeetAtATick() throws {
        // Both hats, alternating steps: each off falls a tick before the other
        // track's next on.
        var song = TestSongs.empty()
        song.tracks = [Track(kind: .noise), Track(kind: .noise)]
        song.patterns[0].rows = [Pattern.emptyRow, Pattern.emptyRow]
        song.tracks[0].instrument.sustain = true
        song.tracks[1].instrument.sustain = true
        for step in stride(from: 0, to: 16, by: 2) {
            song.patterns[0].rows[0][step] = 60
            song.patterns[0].rows[1][step + 1] = 60
        }
        let midi = try MidiBytes(MidiExport.data(for: song))
        var offs = Set<Int>(), ons = Set<Int>()
        for track in midi.chipTracks {
            for timed in track {
                if case .noteOn = timed.event { ons.insert(timed.tick) }
                if case .noteOff = timed.event { offs.insert(timed.tick) }
            }
        }
        XCTAssertEqual(ons.count, 16)
        XCTAssertTrue(offs.isDisjoint(with: ons), "offs \(offs.sorted()) meet ons \(ons.sorted())")
    }
}
