import XCTest
@testable import Chiptune

/// Properties that must hold for *any* song, checked against randomly built
/// hostile ones rather than against hand-picked examples.
///
/// This is the suite that covers `.chipsong` import before import exists: a
/// song arriving from a file is arbitrary JSON, and `normalize()` is the only
/// thing standing between it and the audio thread's fixed-size buffers.
///
/// The generator is seeded, so a failure here reproduces exactly — the seed is
/// printed with every failure.
final class SongPropertyTests: XCTestCase {

    private let seed: UInt64 = 0xC417_7175_7E00_0001
    private let iterations = 50

    /// Runs `body` over generated songs, tagging any failure with the seed and
    /// iteration needed to replay it.
    private func forEachSong(_ body: (Song, String) throws -> Void) rethrows {
        var rng = SeededRandom(seed: seed)
        for i in 0..<iterations {
            let song = Self.hostileSong(using: &rng)
            try body(song, "seed \(String(seed, radix: 16)), iteration \(i)")
        }
    }

    // MARK: Generation

    /// Builds a song out of values the UI could never produce: NaN and infinite
    /// tempos and volumes, arpeggio offsets that overflow the pitch maths, more
    /// tracks and patterns than the buffers hold, notes outside MIDI range, and
    /// arrangements pointing at patterns that don't exist.
    private static func hostileSong(using rng: inout SeededRandom) -> Song {
        func pick<T>(_ options: [T]) -> T { options[Int(rng.next() % UInt64(options.count))] }
        func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(rng.next() % UInt64(range.count))
        }

        var song = Song(name: pick(["", "Hostile", String(repeating: "x", count: 300)]))
        song.tempo = pick([.nan, .infinity, -.infinity, -1000, 0, 1e18, 120, 40, 300, 137.5])

        let trackCount = int(0...(Chip.maxTracks + 4))
        song.tracks = (0..<trackCount).map { _ in
            var track = Track(kind: pick(ChannelKind.allCases))
            track.instrument.volume = pick([.nan, .infinity, -.infinity, -5, 0, 0.5, 1, 99])
            track.instrument.decay = pick([.nan, .infinity, -.infinity, -1, 0, 0.35, 4, 1e9])
            track.instrument.duty = pick([-100, -1, 0, 2, 3, 4, 9999])
            track.instrument.arpeggio = (0..<int(0...9)).map { _ in
                pick([0, 3, 7, 12, -12, 5000, -5000, Int.max / 2, Int.min / 2])
            }
            track.instrument.sustain = rng.next() % 2 == 0
            track.muted = rng.next() % 2 == 0
            return track
        }

        let patternCount = int(0...(Chip.maxPatterns + 4))
        song.patterns = (0..<patternCount).map { index in
            var pattern = Pattern(name: "P\(index)",
                                  length: pick([-50, 0, 1, 4, 16, 64, 500]),
                                  trackCount: max(trackCount, 1))
            for row in pattern.rows.indices {
                for step in pattern.rows[row].indices where rng.next() % 3 == 0 {
                    pattern.rows[row][step] = Int8(truncatingIfNeeded: Int(rng.next() % 256))
                }
            }
            // Rows that don't match the track count at all.
            if rng.next() % 3 == 0 { pattern.rows = Array(pattern.rows.prefix(int(0...2))) }
            return pattern
        }

        song.arrangement = (0..<int(0...(Chip.maxChain + 8))).map { _ in
            // Half the sections point at a pattern that exists; the rest are
            // dangling references of the kind a hand-edited file would have.
            let id = song.patterns.isEmpty || rng.next() % 2 == 0
                ? UUID()
                : song.patterns[int(0...(song.patterns.count - 1))].id
            return SongSection(patternID: id, repeats: pick([-10, 0, 1, 4, 16, 999]))
        }
        return song
    }

    // MARK: Properties

    /// `normalize` is the only sanitiser, so running it twice has to be the
    /// same as running it once — otherwise "normalised" isn't a stable state
    /// and every caller has to guess how many times to call it.
    func testNormalizeIsIdempotent() {
        forEachSong { song, tag in
            var once = song
            once.normalize()
            var twice = once
            twice.normalize()
            XCTAssertTrue(Self.equalIgnoringModified(once, twice),
                          "normalize is not idempotent (\(tag))")
        }
    }

    func testNormalizeProducesValuesTheEngineCanPlay() {
        forEachSong { song, tag in
            // Hold is a switch rather than a value with a range, so the only
            // thing normalising can do wrong is change it. Captured before,
            // because normalize clamps the track count.
            let heldBefore = song.tracks.map(\.instrument.sustain)
            var song = song
            song.normalize()

            for (index, held) in zip(song.tracks.indices, heldBefore) {
                XCTAssertEqual(song.tracks[index].instrument.sustain, held,
                               "normalize changed hold on track \(index) (\(tag))")
            }

            XCTAssertTrue(song.tempo.isFinite, "non-finite tempo survived (\(tag))")
            XCTAssertTrue((40...300).contains(song.tempo), "tempo \(song.tempo) out of range (\(tag))")

            XCTAssertTrue((1...Chip.maxTracks).contains(song.tracks.count), tag)
            XCTAssertTrue((1...Chip.maxPatterns).contains(song.patterns.count), tag)

            for track in song.tracks {
                let inst = track.instrument
                XCTAssertTrue((0...1).contains(inst.volume), "volume \(inst.volume) (\(tag))")
                XCTAssertTrue((0.01...4.0).contains(inst.decay), "decay \(inst.decay) (\(tag))")
                XCTAssertTrue(Instrument.dutyCycles.indices.contains(inst.duty),
                              "duty \(inst.duty) (\(tag))")
                XCTAssertLessThanOrEqual(inst.arpeggio.count, Instrument.maxArpeggioSteps, tag)
                for semitones in inst.arpeggio {
                    XCTAssertLessThanOrEqual(abs(semitones), Instrument.maxArpeggioSemitones,
                                             "arpeggio offset \(semitones) (\(tag))")
                }
            }

            for pattern in song.patterns {
                XCTAssertTrue((4...Chip.maxSteps).contains(pattern.length), tag)
                XCTAssertEqual(pattern.rows.count, song.tracks.count, tag)
                for row in pattern.rows {
                    XCTAssertEqual(row.count, Chip.maxSteps, tag)
                    for note in row {
                        XCTAssertTrue(note == Chip.emptyNote || note == ChipCore.noteOff
                                        || (0...127).contains(note),
                                      "note \(note) (\(tag))")
                    }
                }
            }
        }
    }

    /// The chain is what the audio thread walks, indexing straight into the
    /// pattern table with it.
    func testChainStaysInsideTheSongsPatterns() {
        forEachSong { song, tag in
            var song = song
            song.normalize()
            let chain = song.chain

            XCTAssertFalse(chain.isEmpty, tag)
            XCTAssertLessThanOrEqual(chain.count, Chip.maxChain, tag)
            for slot in chain {
                XCTAssertTrue(song.patterns.indices.contains(slot),
                              "chain slot \(slot) with \(song.patterns.count) patterns (\(tag))")
            }
        }
    }

    /// Saving and reopening must give back the same song. `modified` is
    /// excluded deliberately: `SongStore.save` stamps it on the way out, and a
    /// `Date` doesn't survive a JSON round trip to the last bit anyway.
    func testEncodeDecodeRoundTripsExceptForTheModifiedStamp() throws {
        try forEachSong { song, tag in
            var song = song
            song.normalize()

            let data = try JSONEncoder().encode(song)
            var decoded = try JSONDecoder().decode(Song.self, from: data)
            decoded.normalize()

            XCTAssertTrue(Self.equalIgnoringModified(song, decoded),
                          "song did not survive a JSON round trip (\(tag))")
        }
    }

    /// The end of the line: a hostile song, normalised, actually rendered. This
    /// is the assertion the unclamped-arpeggio bug fails — an infinite phase
    /// increment turns the voice's output into NaN, which then latches in the
    /// master DC blocker and silences the app until it is relaunched.
    func testAnyNormalisedSongRendersFiniteAudio() {
        forEachSong { song, tag in
            var song = song
            song.normalize()

            let core = ChipCore(sampleRate: RenderHarness.sampleRate)
            core.load(song: song)
            core.setSongMode(true)
            core.start()

            let samples = RenderHarness.renderMono(core, frames: 4096)
            XCTAssertFalse(samples.contains { !$0.isFinite },
                           "render produced NaN or infinity (\(tag))")
            XCTAssertLessThanOrEqual(RenderHarness.peak(samples), 1.0,
                                     "render exceeded full scale (\(tag))")
        }
    }

    /// The specific value that reaches `pow(2, semitones / 12)` in the voice's
    /// arpeggio step. Kept as its own named test because the property suite
    /// above would only ever report it as "some random song broke".
    func testExtremeArpeggioOffsetsCannotWedgeTheMasterChain() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 69, arpeggio: [0, Int.max / 2])
        song.normalize()

        let samples = RenderHarness.render(song: song, seconds: 0.5)
        XCTAssertFalse(samples.contains { !$0.isFinite },
                       "an extreme arpeggio offset put NaN into the output")

        // And the damage must not be permanent: the DC blocker feeds back into
        // itself, so one NaN reaching it would otherwise silence every song
        // rendered afterwards on the same core.
        XCTAssertGreaterThan(RenderHarness.rms(samples[4410...]), 0.01,
                             "the voice went silent instead of playing a clamped pitch")
    }

    // MARK: Comparison

    /// `Song`'s own `==` includes `modified`, which is a wall clock and not
    /// part of the song's content.
    private static func equalIgnoringModified(_ a: Song, _ b: Song) -> Bool {
        var a = a, b = b
        let epoch = Date(timeIntervalSince1970: 0)
        a.modified = epoch
        b.modified = epoch
        return a == b
    }
}
