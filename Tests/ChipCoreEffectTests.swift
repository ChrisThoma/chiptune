import XCTest
@testable import Chiptune

/// Per-note pitch effects as heard: slides, vibrato, glide and bend in,
/// measured off the rendered audio by timing zero crossings over short windows.
final class ChipCoreEffectTests: XCTestCase {

    private let sampleRate = RenderHarness.sampleRate
    /// Samples in one step at the test songs' 120 BPM.
    private var step: Int { Chip.samplesPerStep(tempo: 120, sampleRate: sampleRate) }

    // MARK: Helpers

    /// A held pulse note at step 0 carrying `effect`.
    private func song(note: Int8 = 69, effect: NoteEffect, arpeggio: [Int] = []) -> Song {
        var song = TestSongs.singleNote(kind: .pulse1, note: note, sustain: true, arpeggio: arpeggio)
        song.normalize()
        song.patterns[0].setEffect(effect, track: 0, step: 0)
        return song
    }

    /// Frequency from the upward zero crossings in `samples`, interpolated
    /// between samples. Nil when the window holds fewer than two crossings.
    private func frequency(_ samples: ArraySlice<Float>) -> Double? {
        var crossings: [Double] = []
        var i = samples.startIndex + 1
        while i < samples.endIndex {
            let a = Double(samples[i - 1]), b = Double(samples[i])
            if a < 0, b >= 0 {
                crossings.append(Double(i - 1) + (-a) / (b - a))
            }
            i += 1
        }
        guard crossings.count >= 2, let first = crossings.first, let last = crossings.last,
              last > first else { return nil }
        return Double(crossings.count - 1) * sampleRate / (last - first)
    }

    /// Frequency in a window of `width` samples centered on `center`.
    private func frequency(_ samples: [Float], at center: Int, width: Int = 400,
                           file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let lo = max(center - width / 2, 0)
        let hi = min(center + width / 2, samples.count)
        guard lo < hi else {
            XCTFail("window \(lo)..<\(hi) is outside the render", file: file, line: line)
            return 0
        }
        return try XCTUnwrap(frequency(samples[lo..<hi]), "no pitch at \(center)",
                             file: file, line: line)
    }

    private func semitones(_ f: Double, from base: Double) -> Double {
        12 * log2(f / base)
    }

    private func assertRatio(_ measured: Double, _ expected: Double, within tolerance: Double,
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(measured / expected, 1, accuracy: tolerance,
                       "\(message): measured \(measured) Hz, expected \(expected) Hz",
                       file: file, line: line)
    }

    // MARK: Pitch trace (spec v2)
    //
    // The numbers below are written out from the spec rather than read from
    // ChipCore, so these tests check the engine against the spec.

    private let cpu = 1789773.0
    /// Samples in one 60 Hz tick.
    private var tick: Double { sampleRate / 60 }
    private let noisePeriods: [Double] = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254,
                                          380, 508, 762, 1016, 2034, 4068]

    /// A held note at step 0 on any channel, at any tempo.
    private func song(note: Int8, effect: NoteEffect, kind: ChannelKind, tempo: Double = 120,
                      arpeggio: [Int] = []) -> Song {
        var song = TestSongs.singleNote(kind: kind, note: note, tempo: tempo, sustain: true,
                                        arpeggio: arpeggio)
        song.normalize()
        song.patterns[0].setEffect(effect, track: 0, step: 0)
        return song
    }

    /// The frequency the voice used for each rendered sample, one sample per
    /// render call. Index n is the note's n-th sample when it starts at 0.
    private func pitchTrace(_ song: Song, frames: Int) -> [Double] {
        var song = song
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(false)
        core.start()
        var trace = [Double](repeating: 0, count: frames)
        var sample: Float = 0
        for i in 0..<frames {
            withUnsafeMutablePointer(to: &sample) { core.render(frames: 1, into: $0) }
            trace[i] = core.soundingFrequency(track: 0)
        }
        return trace
    }

    /// A sample in the middle of tick `frame`.
    private func mid(_ frame: Int) -> Int { Int(Double(frame) * tick + tick / 2) }

    private func period(_ freq: Double, k: Double) -> Double { cpu / (k * freq) }

    // MARK: Slides

    func testSlideDownOnTriangleFollowsThePeriodAtAnyTempo() throws {
        let base = NoteName.frequency(48)
        let p0 = period(base, k: 32)
        let expected = 12 * log2(p0 / (p0 + 384))
        var traces: [[Double]] = []
        for bpm in [80.0, 180.0] {
            let trace = pitchTrace(song(note: 48, effect: .slideDown, kind: .triangle, tempo: bpm),
                                   frames: Int(tick * 20))
            XCTAssertEqual(semitones(trace[mid(6)], from: base), expected, accuracy: 0.1,
                           "after 6 frames at \(bpm) BPM")
            traces.append(trace)
        }
        XCTAssertEqual(traces[0], traces[1], "a slide doesn't depend on the tempo")
    }

    func testSlideUpOnPulseFollowsThePeriod() throws {
        let base = NoteName.frequency(69)
        let p0 = period(base, k: 16)
        let trace = pitchTrace(song(note: 69, effect: .slideUp, kind: .pulse1), frames: Int(tick * 8))
        for frame in 0..<6 {
            assertRatio(trace[mid(frame)], cpu / (16 * (p0 - 16 * Double(frame))), within: 1e-9,
                        "slide up at frame \(frame)")
        }
    }

    func testSlidePitchHoldsWithinATickAndMovesAtTheBoundary() {
        let trace = pitchTrace(song(note: 69, effect: .slideUp, kind: .pulse1), frames: Int(tick * 10))
        for frame in 0..<9 {
            let lo = Int((Double(frame) * tick).rounded(.up))
            let hi = Int((Double(frame + 1) * tick).rounded(.up))
            let held = trace[lo]
            XCTAssertTrue(trace[lo..<hi].allSatisfy { $0 == held },
                          "pitch moved inside tick \(frame)")
            XCTAssertGreaterThan(trace[hi], held, "pitch should step up at tick \(frame + 1)")
        }
    }

    func testSlideHoldsAtThePeriodLimits() {
        // Triangle C3 down: P0 ≈ 428 reaches 2047 by frame 26.
        let down = pitchTrace(song(note: 48, effect: .slideDown, kind: .triangle), frames: Int(tick * 61))
        let floor = cpu / (32 * 2047)
        assertRatio(down[mid(30)], floor, within: 1e-9, "slide down holds at period 2047")
        assertRatio(down[mid(60)], floor, within: 1e-9, "and stays there")

        // Triangle A4 up: P0 ≈ 127 reaches 8 by frame 8.
        let up = pitchTrace(song(note: 69, effect: .slideUp, kind: .triangle), frames: Int(tick * 41))
        let ceiling = cpu / (32 * 8)
        assertRatio(up[mid(10)], ceiling, within: 1e-9, "slide up holds at period 8")
        assertRatio(up[mid(40)], ceiling, within: 1e-9, "and stays there")
    }

    /// The trace is the pitch the speaker actually hears.
    func testSlideTraceMatchesTheAudio() throws {
        let base = NoteName.frequency(69)
        let p0 = period(base, k: 16)
        let out = RenderHarness.render(song: song(effect: .slideUp), seconds: 0.2)
        assertRatio(try frequency(out, at: mid(3), width: 600), cpu / (16 * (p0 - 48)), within: 0.01,
                    "three frames into a slide up")
    }

    // MARK: Noise

    func testNoiseWithAnEffectClocksAtTheNESNoiseRates() {
        let rates = noisePeriods.map { cpu / $0 }
        for effect: NoteEffect in [.slideDown, .slideUp, .vibrato, .bendIn] {
            let trace = pitchTrace(song(note: 60, effect: effect, kind: .noise), frames: Int(tick * 40))
            for (i, f) in trace.enumerated() {
                let clock = 8 * f
                guard rates.contains(where: { abs($0 / clock - 1) < 1e-9 }) else {
                    XCTFail("\(effect): LFSR clock \(clock) Hz at sample \(i) is not an NES noise rate")
                    break
                }
            }
        }
    }

    func testNoiseQuantizesToTheNearestRateInLogDistance() {
        // C4 noise clocks at 8 × 261.6 = 2093 Hz: nearest is CPU/1016 (1762)
        // or CPU/762 (2349) — 2093/1762 = 1.188, 2349/2093 = 1.122.
        let trace = pitchTrace(song(note: 60, effect: .bendIn, kind: .noise), frames: Int(tick * 5))
        assertRatio(8 * trace[mid(4)], cpu / 762, within: 1e-9, "landed bend in on C4 noise")
    }

    func testPlainNoiseIsUnquantized() {
        let trace = pitchTrace(song(note: 60, effect: .none, kind: .noise), frames: Int(tick * 5))
        XCTAssertEqual(trace[mid(4)], NoteName.frequency(60), accuracy: 1e-9,
                       "a plain noise note keeps its pitch")
    }

    // MARK: Vibrato

    func testVibratoWobblesAroundThePitch() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .vibrato), seconds: 1)

        var readings: [Double] = []
        let settled = step + 4 * Int(tick)
        var center = settled
        while center < settled + 22050 {
            readings.append(try frequency(out, at: center, width: 441))
            center += 147
        }
        let mean = readings.reduce(0, +) / Double(readings.count)
        assertRatio(mean, base, within: 0.01, "vibrato must center on the written note")

        let swing = readings.map { semitones($0, from: base) }
        let high = try XCTUnwrap(swing.max()), low = try XCTUnwrap(swing.min())
        XCTAssertEqual(high, 0.4, accuracy: 0.1, "upper swing")
        XCTAssertEqual(low, -0.4, accuracy: 0.1, "lower swing")
    }

    func testVibratoRateIsAboutSixHertz() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .vibrato), seconds: 1.4)
        // Count upward passes through the base pitch over one second.
        var passes = 0
        var previous: Double?
        let settled = step + 4 * Int(tick)
        var center = settled
        while center < settled + 44100 {
            let semis = semitones(try frequency(out, at: center, width: 441), from: base)
            if let previous, previous < 0, semis >= 0 { passes += 1 }
            previous = semis
            center += 147
        }
        XCTAssertEqual(Double(passes), 6, accuracy: 1)
    }

    func testVibratoWaitsAStepThenRampsIn() throws {
        let base = NoteName.frequency(69)
        let trace = pitchTrace(song(effect: .vibrato), frames: step + Int(tick * 40))
        XCTAssertTrue(trace[0..<step].allSatisfy { abs($0 / base - 1) < 1e-12 },
                      "no wobble during the first step")

        let wobble = trace[step...].map { semitones($0, from: base) }
        let high = try XCTUnwrap(wobble.max()), low = try XCTUnwrap(wobble.min())
        XCTAssertEqual(high, 0.4, accuracy: 0.05, "upper swing after the delay")
        XCTAssertEqual(low, -0.4, accuracy: 0.05, "lower swing after the delay")

        // The ramp: the first tick after the delay ends is at partial depth.
        let firstTick = Int((Double(step) / tick).rounded(.up))
        let tAfter = Double(firstTick) * tick - Double(step)
        let ramp = min(1, tAfter / (3 * tick))
        let expected = 0.4 * ramp * sin(2 * .pi * 6 * tAfter / sampleRate)
        XCTAssertEqual(semitones(trace[mid(firstTick)], from: base), expected, accuracy: 1e-9,
                       "first tick after the delay")
    }

    // MARK: Bend in

    func testBendInLandsAfterThreeFramesAtAnyTempo() {
        let base = NoteName.frequency(69)
        var traces: [[Double]] = []
        for bpm in [80.0, 180.0] {
            let trace = pitchTrace(song(note: 69, effect: .bendIn, kind: .pulse1, tempo: bpm),
                                   frames: Int(tick * 6))
            for (frame, semis) in [(0, -2.0), (1, -4.0 / 3), (2, -2.0 / 3), (3, 0.0), (5, 0.0)] {
                XCTAssertEqual(semitones(trace[mid(frame)], from: base), semis, accuracy: 1e-9,
                               "frame \(frame) at \(bpm) BPM")
            }
            traces.append(trace)
        }
        XCTAssertEqual(traces[0], traces[1], "bend in doesn't depend on the tempo")
    }

    func testBendInStartsTwoSemitonesFlatAndLandsAfterThreeFrames() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .bendIn), seconds: 0.5)

        let opening = semitones(try frequency(out[60..<360]), from: base)
        XCTAssertLessThan(opening, -1.4, "bend in should start well flat")
        XCTAssertGreaterThan(opening, -2.1, "but no more than two semitones")

        let landed = try frequency(out, at: 3 * Int(tick) + 900, width: 1200)
        assertRatio(landed, base, within: 0.005, "on pitch after three frames")
    }

    private func frequency(_ samples: ArraySlice<Float>, file: StaticString = #filePath,
                           line: UInt = #line) throws -> Double {
        try XCTUnwrap(frequency(samples), "no pitch in window", file: file, line: line)
    }

    // MARK: Glide

    /// A4 then a gliding A5 on the next step.
    private func glideSong(first: Int8 = 69, second: Int8 = 81) -> Song {
        var song = TestSongs.singleNote(kind: .pulse1, note: first, sustain: true)
        song.normalize()
        song.patterns[0].rows[0][1] = second
        song.patterns[0].setEffect(.glide, track: 0, step: 1)
        return song
    }

    func testGlideHasNoEnvelopeDipBetweenTheNotes() {
        var plain = glideSong()
        plain.patterns[0].setEffect(.none, track: 0, step: 1)
        let glided = RenderHarness.render(song: glideSong(), seconds: 0.5)
        let retriggered = RenderHarness.render(song: plain, seconds: 0.5)

        func lowestLevel(_ out: [Float]) -> Double {
            var lowest = Double.infinity
            var at = step - 512
            while at < step + 512 {
                lowest = min(lowest, RenderHarness.rms(out[at..<(at + 64)]))
                at += 16
            }
            return lowest
        }
        let before = RenderHarness.rms(glided[(step - 2048)..<(step - 512)])
        XCTAssertGreaterThan(lowestLevel(glided), before * 0.6,
                             "a glide must not fade the voice out between the notes")
        XCTAssertLessThan(lowestLevel(retriggered), before * 0.4,
                          "precondition: a plain retrigger does dip (de-click)")
    }

    func testGlideSlidesFromTheOldPitchToTheNewOneByHalfAStep() throws {
        let from = NoteName.frequency(69), to = NoteName.frequency(81)
        let out = RenderHarness.render(song: glideSong(), seconds: 0.5)

        var readings: [Double] = []
        var center = step + 150
        while center < step + step / 2 - 150 {
            readings.append(try frequency(out, at: center, width: 300))
            center += 150
        }
        let first = try XCTUnwrap(readings.first)
        XCTAssertLessThan(first, from * pow(2, 3.0 / 12), "the glide starts near the old pitch")
        for (a, b) in zip(readings, readings.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a * 0.98, "the glide must rise steadily: \(readings)")
        }
        assertRatio(try frequency(out, at: step + step / 2 + 1000, width: 1500), to, within: 0.005,
                    "on the new pitch after half a step")
    }

    func testGlideDownwardFallsSteadily() throws {
        let to = NoteName.frequency(69)
        let out = RenderHarness.render(song: glideSong(first: 81, second: 69), seconds: 0.5)
        var readings: [Double] = []
        var center = step + 150
        while center < step + step / 2 - 150 {
            readings.append(try frequency(out, at: center, width: 300))
            center += 150
        }
        for (a, b) in zip(readings, readings.dropFirst()) {
            XCTAssertLessThanOrEqual(b, a * 1.02, "the glide must fall steadily: \(readings)")
        }
        assertRatio(try frequency(out, at: step + step / 2 + 1000, width: 1500), to, within: 0.005,
                    "on the new pitch after half a step")
    }

    /// The glide starts from the old note's own pitch, not the chord tone
    /// its arpeggio happened to be on.
    func testGlideOnAnArpeggioStartsFromTheOldBasePitch() {
        var song = TestSongs.singleNote(kind: .pulse1, note: 69, sustain: true, arpeggio: [7, 7])
        song.normalize()
        song.patterns[0].rows[0][1] = 81
        song.patterns[0].setEffect(.glide, track: 0, step: 1)
        let trace = pitchTrace(song, frames: step + 10)
        XCTAssertEqual(trace[step - 1], NoteName.frequency(76), accuracy: 0.01,
                       "precondition: the old note sounds its +7 chord tone")
        XCTAssertEqual(trace[step], NoteName.frequency(69), accuracy: 0.01,
                       "the glide starts on the old base pitch")
    }

    /// Glides move on the 60 Hz ticks and finish half a step in.
    func testGlideIsSteppedOnTicks() {
        let to = NoteName.frequency(81)
        let trace = pitchTrace(glideSong(), frames: step + step / 2 + Int(tick * 2))
        let glide = Array(trace[step...])
        let ticks = Double(step) * 0.5 / tick
        for frame in 0..<Int(ticks) {
            let expected = -12 * max(0, 1 - Double(frame) * tick / (Double(step) * 0.5))
            XCTAssertEqual(semitones(glide[mid(frame)], from: to), expected, accuracy: 1e-9,
                           "glide at frame \(frame)")
        }
        XCTAssertEqual(glide[glide.count - 1], to, accuracy: 1e-9, "on the new pitch")
    }

    func testGlideOnASilentVoiceIsAPlainNote() {
        let glide = RenderHarness.render(song: song(effect: .glide), seconds: 0.3)
        let plain = RenderHarness.render(song: song(effect: .none), seconds: 0.3)
        XCTAssertEqual(glide, plain, "with nothing ringing, a glide is just a note")
    }

    // MARK: Arpeggio

    /// The effect's offset rides on top of the arpeggio's, so a slide on an
    /// arpeggiated note slides every arp note.
    func testEffectStacksOnTheArpeggio() throws {
        let base = NoteName.frequency(69)
        // Both offsets +12: after the first switch every arp note is an
        // octave up, which keeps the window measurement simple.
        let arp = RenderHarness.render(song: song(effect: .slideDown, arpeggio: [12, 12]), seconds: 0.5)
        let flat = RenderHarness.render(song: song(effect: .slideDown), seconds: 0.5)

        let p0 = period(base, k: 16)
        func slid(_ frame: Int) -> Double { p0 / (p0 + 64 * Double(frame)) }
        assertRatio(try frequency(arp, at: mid(3), width: 600), base * 2 * slid(3), within: 0.01,
                    "arp octave plus the slide")
        assertRatio(try frequency(flat, at: mid(3), width: 600), base * slid(3), within: 0.01,
                    "the same slide without the arp")

        // The arp switches 882 samples in, inside tick 1: the new arp note
        // takes the slide offset that tick holds.
        let trace = pitchTrace(song(effect: .slideDown, arpeggio: [12, 12]), frames: 1400)
        XCTAssertEqual(trace[800], base * slid(1), accuracy: 1e-9, "before the arp switch")
        XCTAssertEqual(trace[1000], base * 2 * slid(1), accuracy: 1e-9, "after it, same held slide")
    }

    // MARK: Range and safety

    func testExtremeSlidesStayFiniteAndInRange() throws {
        for (note, effect): (Int8, NoteEffect) in [(127, .slideUp), (0, .slideDown), (127, .vibrato),
                                                   (0, .bendIn), (120, .slideUp)] {
            let out = RenderHarness.render(song: song(note: note, effect: effect), seconds: 1)
            XCTAssertTrue(out.allSatisfy(\.isFinite), "MIDI \(note) with \(effect) went non-finite")
        }
        // Clamped to MIDI 127: a slide from 120 can't go past ~12.5 kHz.
        let out = RenderHarness.render(song: song(note: 115, effect: .slideUp), seconds: 1)
        let top = NoteName.frequency(127)
        let measured = try frequency(out, at: 4 * step, width: 4000)
        XCTAssertLessThan(measured, top * 1.05, "pitch must be clamped to the note range")
        XCTAssertGreaterThan(measured, top * 0.9, "and sit at the top of it")
    }

    // MARK: Storage

    func testSetEffectAndLoadReachTheCoresBuffer() {
        let core = ChipCore(sampleRate: sampleRate)
        core.setEffect(pattern: 2, track: 3, step: 4, effect: .vibrato)
        XCTAssertEqual(core.effect(pattern: 2, track: 3, step: 4), .vibrato)
        core.setEffect(pattern: 99, track: 0, step: 0, effect: .vibrato)
        XCTAssertEqual(core.effect(pattern: 99, track: 0, step: 0), .none, "out of range is dropped")

        var withFx = song(effect: .slideUp)
        withFx.patterns[0].rows[0][5] = 60
        withFx.patterns[0].setEffect(.glide, track: 0, step: 5)
        core.load(song: withFx)
        XCTAssertEqual(core.effect(pattern: 0, track: 0, step: 0), .slideUp)
        XCTAssertEqual(core.effect(pattern: 0, track: 0, step: 5), .glide)

        core.load(song: song(effect: .none))
        XCTAssertEqual(core.effect(pattern: 0, track: 0, step: 0), .none, "load replaces old effects")
        XCTAssertEqual(core.effect(pattern: 0, track: 0, step: 5), .none)
    }

    func testAuditionCarriesTheEffect() {
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song(effect: .none))
        core.audition(track: 0, note: 69, effect: .bendIn)
        XCTAssertEqual(core.soundingEffect(track: 0), .bendIn)

        let out = RenderHarness.renderMono(core, frames: 4000)
        let opening = semitones((frequency(out[60..<360]) ?? 0), from: NoteName.frequency(69))
        XCTAssertLessThan(opening, -1.4, "an auditioned bend in starts flat")
    }

    func testAuditionWithoutAnEffectIsPlain() {
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song(effect: .none))
        core.audition(track: 0, note: 69)
        XCTAssertEqual(core.soundingEffect(track: 0), NoteEffect.none)
    }
}
