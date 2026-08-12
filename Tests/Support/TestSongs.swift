import Foundation
@testable import Chiptune

/// Songs the suites build on, plus a seeded RNG for the property tests.
enum TestSongs {

    /// A song with no notes at all — the base every builder starts from.
    static func empty(name: String = "Test", tempo: Double = 120, length: Int = 16) -> Song {
        var song = Song(name: name)
        song.tempo = tempo
        song.patterns[0].length = length
        return song
    }

    /// One note on one track, everything else silent. The workhorse for voice
    /// tests: a single sounding voice means the analysis sees exactly one thing.
    ///
    /// `sustain` holds the note at full level for the whole render, which is
    /// what pitch and duty measurements need — a decaying note's amplitude is
    /// falling out from under the analysis window.
    static func singleNote(kind: ChannelKind,
                           note: Int8 = 69,
                           tempo: Double = 120,
                           sustain: Bool = true,
                           duty: Int = 2,
                           arpeggio: [Int] = []) -> Song {
        var song = empty(tempo: tempo)
        song.tracks = [Track(kind: kind)]
        song.tracks[0].instrument.sustain = sustain
        song.tracks[0].instrument.decay = 0.35
        song.tracks[0].instrument.volume = 1.0
        song.tracks[0].instrument.duty = duty
        song.tracks[0].instrument.arpeggio = arpeggio
        song.patterns[0].rows = [Pattern.emptyRow]
        song.patterns[0].rows[0][0] = note
        return song
    }

    /// Two patterns chained in a stated order, for the sequencer tests. Each
    /// pattern puts a note on step 0 so pattern changes are visible as onsets.
    static func twoPatterns(lengths: (Int, Int) = (16, 8),
                            repeats: (Int, Int) = (1, 1),
                            tempo: Double = 120) -> Song {
        var song = empty(tempo: tempo, length: lengths.0)
        song.tracks = [Track(kind: .pulse1)]
        song.patterns[0].rows = [Pattern.emptyRow]
        song.patterns[0].rows[0][0] = 60

        var second = Pattern(name: "B", length: lengths.1, trackCount: 1)
        second.rows[0][0] = 72
        song.patterns.append(second)

        song.arrangement = [
            SongSection(patternID: song.patterns[0].id, repeats: repeats.0),
            SongSection(patternID: second.id, repeats: repeats.1),
        ]
        return song
    }

    /// The song behind `Tests/Fixtures/golden-demo.wav`.
    ///
    /// Written out as a literal on purpose. The obvious alternative — reusing
    /// the app's `seedDemo()` — would make the golden track whatever the demo
    /// riff happens to be, so a deliberate change to the demo would look like a
    /// DSP regression. It is also `private`, and `Studio.init` reads the store.
    static func golden() -> Song {
        var song = Song(name: "Golden")
        song.tempo = 132
        let lead: [Int8] = [72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1]
        let harmony: [Int8] = [-1, 64, -1, 67, -1, 64, -1, 67, -1, 65, -1, 69, -1, 65, -1, 62]
        let bass: [Int8] = [48, -1, -1, -1, 48, -1, -1, -1, 53, -1, -1, -1, 43, -1, -1, -1]
        let drums: [Int8] = [60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1]
        for (i, notes) in [lead, harmony, bass, drums].enumerated() {
            for (step, n) in notes.enumerated() { song.patterns[0].rows[i][step] = n }
        }
        return song
    }
}

/// Deterministic RNG for the property tests. `SystemRandomNumberGenerator`
/// would make a failure unreproducible; this one is seeded, and the suites
/// print the seed so a failing run can be replayed exactly.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// SplitMix64 — small, and good enough for choosing test values.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
