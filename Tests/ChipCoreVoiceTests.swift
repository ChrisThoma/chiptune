import XCTest
@testable import Chiptune

/// What each voice is supposed to sound like, measured off the rendered
/// audio rather than off the synth's internal state.
///
/// Levels are asserted as *ratios*, never as absolute RMS: the mix gain scales
/// with how many tracks a song has, so an absolute figure would be a fact about
/// the test song rather than about the voice.
final class ChipCoreVoiceTests: XCTestCase {

    private let sampleRate = RenderHarness.sampleRate
    /// Skip the attack ramp and let the filters settle before measuring.
    private let settled = 4410

    private func render(_ song: Song, seconds: Double) -> [Float] {
        RenderHarness.render(song: song, seconds: seconds)
    }

    // MARK: Pitch

    /// The note you write is the note you hear. Asserted as "this candidate
    /// beats every other semitone within an octave either way", which a mere
    /// "there is energy at 440 Hz" would not — broadband noise passes that.
    func testPulseAndTriangleTrackTheWrittenNote() {
        for kind in [ChannelKind.pulse1, .pulse2, .triangle] {
            for note: Int8 in [48, 60, 69, 79] {
                let samples = render(TestSongs.singleNote(kind: kind, note: note), seconds: 0.5)
                let dominant = RenderHarness.dominantFrequency(
                    samples[settled...],
                    candidates: RenderHarness.semitoneLadder(around: note))

                XCTAssertEqual(dominant ?? 0, NoteName.frequency(note), accuracy: 0.001,
                               "\(kind.fullName) playing MIDI \(note) is not the loudest at its own pitch")
            }
        }
    }

    /// Noise has no pitch to assert, so the claim is the opposite one: no
    /// single frequency dominates the way a pulse's fundamental does.
    func testNoiseIsBroadbandRatherThanPitched() {
        for note: Int8 in [48, 60, 72] {
            let ladder = RenderHarness.semitoneLadder(around: note)
            let noise = render(TestSongs.singleNote(kind: .noise, note: note), seconds: 0.5)
            let pulse = render(TestSongs.singleNote(kind: .pulse1, note: note), seconds: 0.5)

            let noisePeak = RenderHarness.spectralPeakiness(noise[settled...], frequencies: ladder)
            let pulsePeak = RenderHarness.spectralPeakiness(pulse[settled...], frequencies: ladder)

            XCTAssertLessThan(noisePeak, 6, "the noise channel has a dominant pitch it shouldn't")
            XCTAssertGreaterThan(pulsePeak, noisePeak * 3,
                                 "a pulse must be far more sharply pitched than noise")
        }
    }

    /// The noise channel is a seeded LFSR, not a random generator: the same
    /// song must render to the same bytes every time. Export, the golden
    /// fixture and every level assertion here depend on it.
    func testNoiseIsDeterministic() {
        let song = TestSongs.singleNote(kind: .noise, note: 60)
        XCTAssertEqual(render(song, seconds: 0.25), render(song, seconds: 0.25),
                       "two renders of the same noise song differ")
    }

    // MARK: Waveform shape

    func testPulseDutyCyclesMatchTheirSettings() {
        for duty in Instrument.dutyCycles.indices {
            let song = TestSongs.singleNote(kind: .pulse1, note: 60, duty: duty)
            let ratio = RenderHarness.dutyRatio(render(song, seconds: 0.5)[settled...])

            // The master chain removes the waveform's DC offset, which moves
            // where it sits but not the fraction of each cycle it spends high.
            XCTAssertEqual(ratio, Instrument.dutyCycles[duty], accuracy: 0.02,
                           "duty index \(duty) rendered \(ratio)")
        }
    }

    /// The NES triangle is a staircase, not a ramp — 16 levels per half cycle,
    /// which is most of why it sounds like a chip and not like a synth.
    func testTriangleIsQuantisedIntoSixteenLevels() {
        let note: Int8 = 36
        let period = sampleRate / NoteName.frequency(note)
        let cycles = 4
        let window = 10_000..<(10_000 + Int(period * Double(cycles)))

        let triangle = render(TestSongs.singleNote(kind: .triangle, note: note), seconds: 0.5)
        let steps = Double(RenderHarness.levelSteps(triangle[window])) / Double(cycles)

        // 32 levels are traversed per cycle (16 up, 16 down); the two at the
        // turning points merge, so 30 changes are visible.
        XCTAssertEqual(steps, 30, accuracy: 3, "triangle staircase measured \(steps) steps per cycle")

        // Contrast, so the number above is known to be measuring quantisation
        // and not just "the waveform moves": a pulse has two edges a cycle.
        let pulse = render(TestSongs.singleNote(kind: .pulse1, note: note), seconds: 0.5)
        let pulseSteps = Double(RenderHarness.levelSteps(pulse[window])) / Double(cycles)
        XCTAssertEqual(pulseSteps, 2, accuracy: 1)
    }

    // MARK: Envelope

    func testDecayFallsToSilenceOverTheSetTime() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 60, sustain: false)
        song.tracks[0].instrument.decay = 0.35
        let samples = render(song, seconds: 1.0)

        let early = RenderHarness.rms(samples[2205..<4410])       // ~0.05 s
        let late = RenderHarness.rms(samples[13230..<15435])      // ~0.30 s

        XCTAssertGreaterThan(early, 0.01, "the note should be sounding at 0.05 s")
        // The envelope is specified as -60 dB after `decay` seconds.
        XCTAssertLessThan(late / early, 0.02, "decay didn't reach roughly -60 dB by 0.3 s")
    }

    /// A track added from the UI must not drone. The triangle used to ship
    /// holding, which is what a playtester hit: one note, and the channel
    /// never went quiet again.
    func testANewTrackOfAnyKindDoesNotSustainByDefault() {
        for kind in ChannelKind.allCases {
            XCTAssertFalse(Instrument.default(for: kind).sustain,
                           "\(kind.fullName) ships holding")

            // Slow enough that 16 steps run past the window: at a normal tempo
            // the pattern would wrap and retrigger the note under measurement.
            var song = TestSongs.empty(tempo: 40)
            song.tracks = [Track(kind: kind)]
            song.patterns[0].rows = [Pattern.emptyRow]
            song.patterns[0].rows[0][0] = 48
            let samples = render(song, seconds: 3.0)

            let tail = RenderHarness.rms(samples[(samples.count - 4410)...])
            XCTAssertLessThan(tail, 0.005,
                              "a default \(kind.fullName) was still sounding 3 s after one note")
        }
    }

    func testSustainHoldsLevelForTheWholeNote() {
        let samples = render(TestSongs.singleNote(kind: .triangle, note: 48, sustain: true),
                             seconds: 1.5)

        let early = RenderHarness.rms(samples[settled..<(settled + 4410)])
        let late = RenderHarness.rms(samples[(samples.count - 4410)...])

        XCTAssertGreaterThan(early, 0.01)
        XCTAssertEqual(late / early, 1.0, accuracy: 0.05, "a sustaining voice drifted in level")
    }

    func testNoteOffCutsASustainingVoice() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 60, tempo: 120)
        song.patterns[0].rows[0][8] = ChipCore.noteOff
        let samples = render(song, seconds: 1.5)

        let sps = Int((sampleRate * 60.0 / (120 * 4)).rounded())
        let before = RenderHarness.rms(samples[(sps * 7)..<(sps * 8)])
        // The release is specified at ~15 ms; 50 ms later it must be gone.
        let after = RenderHarness.rms(samples[(sps * 8 + 2205)..<(sps * 8 + 4410)])

        XCTAssertGreaterThan(before, 0.01, "the note should be sounding before the note-off")
        XCTAssertLessThan(after / before, 0.01, "note-off didn't release the voice")
    }

    func testMutedTrackIsSilent() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 60)
        song.tracks[0].muted = true
        XCTAssertEqual(RenderHarness.peak(render(song, seconds: 0.5)), 0, accuracy: 1e-9)
    }

    func testVolumeScalesTheOutputProportionally() {
        let full = render(TestSongs.singleNote(kind: .pulse1, note: 60), seconds: 0.5)
        var quiet = TestSongs.singleNote(kind: .pulse1, note: 60)
        quiet.tracks[0].instrument.volume = 0.5
        let half = render(quiet, seconds: 0.5)

        let window = settled..<(settled + 4410)
        let ratio = RenderHarness.rms(full[window]) / RenderHarness.rms(half[window])
        XCTAssertEqual(ratio, 2.0, accuracy: 0.15, "halving the volume didn't halve the level")
    }

    // MARK: De-click

    /// Retriggering a voice that is still ringing fades it out first. Without
    /// that, a run of the same note steps the amplitude from near full scale to
    /// zero on one sample, which is an audible tick on every repeat.
    ///
    /// Measured on the triangle because it's the smooth waveform: a pulse's own
    /// square edges are bigger than any click, so they'd hide the defect.
    func testRetriggeringTheSameNoteDoesNotStepTheWaveform() {
        var retriggering = TestSongs.singleNote(kind: .triangle, note: 60, tempo: 240)
        for step in 0..<16 { retriggering.patterns[0].rows[0][step] = 60 }

        // Baseline: the same voice holding one note, so the comparison is
        // against the waveform's own largest jump (its quantisation step)
        // rather than against a number picked out of the air.
        let held = render(TestSongs.singleNote(kind: .triangle, note: 60, tempo: 240), seconds: 1.0)
        let retriggered = render(retriggering, seconds: 1.0)

        let baseline = RenderHarness.maxDelta(held[1000...])
        let worst = RenderHarness.maxDelta(retriggered[1000...])

        XCTAssertLessThan(worst, baseline * 1.5,
                          "retriggers step the waveform by \(worst) against a \(baseline) baseline")
    }

    // MARK: Arpeggio

    /// The arpeggio cycles its offsets at ~50 Hz — one offset every 882 samples
    /// at 44.1 kHz — which is what makes a single channel read as a chord.
    func testArpeggioAlternatesPitchAtAboutFiftyHertz() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 69, arpeggio: [0, 12])
        song.normalize()
        let samples = render(song, seconds: 0.5)

        let base = 440.0
        let octaveUp = 880.0
        // Windows sitting inside consecutive offset segments, clear of the
        // boundaries where the pitch is mid-change.
        let segments: [(Range<Int>, Double, Double)] = [
            (100..<800, base, octaveUp),
            (950..<1700, octaveUp, base),
            (1850..<2600, base, octaveUp),
        ]
        for (window, expected, other) in segments {
            let strong = RenderHarness.goertzel(samples[window], frequency: expected)
            let weak = RenderHarness.goertzel(samples[window], frequency: other)
            XCTAssertGreaterThan(strong, weak * 3,
                                 "window \(window) should be sitting at \(expected) Hz")
        }
    }

    func testNoArpeggioMeansTheNoteHoldsItsPitch() {
        let samples = render(TestSongs.singleNote(kind: .pulse1, note: 69), seconds: 0.5)
        for window in [100..<800, 950..<1700, 1850..<2600] {
            let base = RenderHarness.goertzel(samples[window], frequency: 440)
            let octaveUp = RenderHarness.goertzel(samples[window], frequency: 880)
            XCTAssertGreaterThan(base, octaveUp * 3,
                                 "pitch moved in window \(window) with no arpeggio set")
        }
    }
}
