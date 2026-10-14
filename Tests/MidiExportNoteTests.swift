import XCTest
@testable import Chiptune

/// Where notes start and stop. One step is 24 ticks (96 per quarter, four
/// steps to the beat), so step `s` of the arrangement is tick `24 × s`.
final class MidiExportNoteTests: XCTestCase {

    /// One pulse track playing `cells` from step 0. Sustain by default, so a
    /// note lasts until something on the track ends it.
    private func song(_ cells: [Int8], length: Int = 16, tempo: Double = 120,
                      sustain: Bool = true, decay: Double = 0.35) -> Song {
        var song = TestSongs.empty(tempo: tempo, length: length)
        song.tracks = [Track(kind: .pulse1)]
        song.tracks[0].instrument.sustain = sustain
        song.tracks[0].instrument.decay = decay
        song.patterns[0].rows = [Pattern.emptyRow]
        for (step, n) in cells.enumerated() { song.patterns[0].rows[0][step] = n }
        return song
    }

    private func notes(_ song: Song, track: Int = 0) throws -> [(note: Int, on: Int, off: Int)] {
        let midi = try MidiBytes(MidiExport.data(for: song))
        return MidiBytes.notes(in: midi.tracks[track + 1]).map { ($0.note, $0.on, $0.off) }
    }

    private func assertNotes(_ actual: [(note: Int, on: Int, off: Int)],
                             _ expected: [(Int, Int, Int)],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.map { [$0.note, $0.on, $0.off] }, expected.map { [$0.0, $0.1, $0.2] },
                       "as [note, on, off]", file: file, line: line)
    }

    // MARK: What ends a note

    func testANoteEndsWhereTheNextOneStarts() throws {
        // Steps 0 and 4: the first note's off lands on the second's on, at 96.
        // The second holds to the end of the 16 steps, 384.
        assertNotes(try notes(song([60, -1, -1, -1, 64])), [(60, 0, 96), (64, 96, 384)])
    }

    func testAnOffCellEndsTheNote() throws {
        assertNotes(try notes(song([60, -1, Chip.noteOff])), [(60, 0, 48)])
    }

    func testRestsCarryTheNoteOn() throws {
        // Nothing but rests after step 1, so the note holds to the very end.
        assertNotes(try notes(song([-1, 62, -1, -1, -1, -1])), [(62, 24, 384)])
    }

    func testAnOffWithNothingSoundingWritesNothing() throws {
        assertNotes(try notes(song([Chip.noteOff, 60, Chip.noteOff, Chip.noteOff])), [(60, 24, 48)])
    }

    func testADecayingNoteEndsAfterItsDecay() throws {
        // round(0.35 s × 120/60 beats/s × 96) = round(67.2) = 67.
        assertNotes(try notes(song([60, -1, -1, -1, -1, -1, -1, -1, 64], sustain: false)),
                    [(60, 0, 67), (64, 192, 192 + 67)])
        // round(0.35 × 132/60 × 96) = round(73.92) = 74 — rounds up.
        assertNotes(try notes(song([60], tempo: 132, sustain: false)), [(60, 0, 74)])
    }

    func testAShortDecayStillLastsATick() throws {
        // round(0.01 × 40/60 × 96) = round(0.64) = 1, not 0. A note-on and its
        // own off at one tick would leave a DAW nothing to draw.
        assertNotes(try notes(song([60], tempo: 40, sustain: false, decay: 0.01)), [(60, 0, 1)])
    }

    func testTheNextNoteCutsALongDecay() throws {
        // 4 s at 120 BPM is 768 ticks, far past the next note at 48.
        assertNotes(try notes(song([60, -1, 64], sustain: false, decay: 4.0)),
                    [(60, 0, 48), (64, 48, 384)])
    }

    func testTheEndOfTheSongCutsALongDecay() throws {
        assertNotes(try notes(song([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 60],
                                   sustain: false, decay: 4.0)),
                    [(60, 14 * 24, 384)])
    }

    // MARK: Order at one tick

    func testARepeatedPitchIsOffThenOnAtTheSameTick() throws {
        // The other order would start the second note and then immediately
        // end it, which a DAW reads as one note running to step 1 and stopping.
        let midi = try MidiBytes(MidiExport.data(for: song([60, 60])))
        let atStep1 = midi.tracks[1].filter { $0.tick == 24 }.map(\.event)
        XCTAssertEqual(atStep1.count, 2)
        guard atStep1.count == 2 else { return }
        guard case .noteOff(0, 60, _) = atStep1[0] else { return XCTFail("first is \(atStep1[0])") }
        guard case .noteOn(0, 60, _) = atStep1[1] else { return XCTFail("second is \(atStep1[1])") }
    }

    // MARK: Across the arrangement

    func testAHeldNoteCarriesAcrossAPatternBoundary() throws {
        // A is 16 steps with a note at step 12; B is 8 steps with a note at
        // its step 4, which is step 20 of the song. Nothing in between.
        var song = song([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 60])
        var b = Pattern(name: "B", length: 8, trackCount: 1)
        b.rows[0][4] = 64
        song.patterns.append(b)
        song.arrangement.append(SongSection(patternID: b.id))
        assertNotes(try notes(song), [(60, 12 * 24, 20 * 24), (64, 20 * 24, 24 * 24)])
    }

    func testRepeatsAndMixedLengthsJoinEndToEnd() throws {
        // A (16 steps) twice, then B (8 steps): starts at 0, 384 and 768, and
        // the song ends at (16 + 16 + 8) × 24 = 960.
        var song = song([60])
        var b = Pattern(name: "B", length: 8, trackCount: 1)
        b.rows[0][0] = 72
        song.patterns.append(b)
        song.arrangement = [SongSection(patternID: song.patterns[0].id, repeats: 2),
                            SongSection(patternID: b.id)]
        assertNotes(try notes(song), [(60, 0, 384), (60, 384, 768), (72, 768, 960)])
    }

    func testCellsPastAPatternsLengthAreNotPlayed() throws {
        // Rows are always 64 long; a 4-step pattern only plays the first four.
        var song = song([60], length: 4)
        song.patterns[0].rows[0][8] = 72
        assertNotes(try notes(song), [(60, 0, 96)])
    }

    func testOnlyArrangedPatternsArePlayed() throws {
        var song = song([60])
        var unused = Pattern(name: "B", length: 16, trackCount: 1)
        unused.rows[0][0] = 72
        song.patterns.append(unused)
        assertNotes(try notes(song), [(60, 0, 384)])
    }

    func testEveryTrackEndsAtTheLastTick() throws {
        // Four tracks whose last notes end in very different places. Every
        // track, conductor included, has to end on 24 × 24 = 576 so the file
        // loops cleanly in a DAW.
        var song = TestSongs.empty(length: 16)
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[2][15] = 40
        var b = Pattern(name: "B", length: 8, trackCount: 4)
        b.rows[1][3] = 67
        song.patterns.append(b)
        song.arrangement.append(SongSection(patternID: b.id))

        let midi = try MidiBytes(MidiExport.data(for: song))
        XCTAssertEqual(midi.tracks.count, 5)
        for (i, track) in midi.tracks.enumerated() {
            XCTAssertEqual(track.last, MidiBytes.Timed(tick: 576, event: .meta(type: 0x2F, bytes: [])),
                           "track \(i)")
            XCTAssertEqual(track.filter { $0.event == .meta(type: 0x2F, bytes: []) }.count, 1, "track \(i)")
        }
    }
}
