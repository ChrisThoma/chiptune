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

    // MARK: Slides

    func testSlideUpReachesAnOctaveByTheEndOfTheStepAndStopsAtTwo() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .slideUp), seconds: 1)

        assertRatio(try frequency(out, at: step / 2), base * pow(2, 0.5), within: 0.03, "half a step in")
        assertRatio(try frequency(out, at: step), base * 2, within: 0.03, "one step in")
        assertRatio(try frequency(out, at: 3 * step, width: 1500), base * 4, within: 0.02,
                    "past two steps the slide holds at two octaves")
        assertRatio(try frequency(out, at: 5 * step, width: 1500), base * 4, within: 0.02,
                    "and stays there")
    }

    func testSlideDownFallsAnOctaveByTheEndOfTheStepAndStopsAtTwo() throws {
        let base = NoteName.frequency(81)
        let out = RenderHarness.render(song: song(note: 81, effect: .slideDown), seconds: 1)

        assertRatio(try frequency(out, at: step / 2), base * pow(2, -0.5), within: 0.03, "half a step in")
        assertRatio(try frequency(out, at: step), base / 2, within: 0.03, "one step in")
        assertRatio(try frequency(out, at: 4 * step, width: 3000), base / 4, within: 0.02,
                    "past two steps the slide holds at two octaves down")
    }

    // MARK: Vibrato

    func testVibratoWobblesAroundThePitch() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .vibrato), seconds: 1)

        var readings: [Double] = []
        var center = 4410
        while center < 4410 + 22050 {
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
        let out = RenderHarness.render(song: song(effect: .vibrato), seconds: 1.2)
        // Count upward passes through the base pitch over one second.
        var passes = 0
        var previous: Double?
        var center = 4410
        while center < 4410 + 44100 {
            let semis = semitones(try frequency(out, at: center, width: 441), from: base)
            if let previous, previous < 0, semis >= 0 { passes += 1 }
            previous = semis
            center += 147
        }
        XCTAssertEqual(Double(passes), 6, accuracy: 1)
    }

    // MARK: Bend in

    func testBendInStartsTwoSemitonesFlatAndLandsByAQuarterStep() throws {
        let base = NoteName.frequency(69)
        let out = RenderHarness.render(song: song(effect: .bendIn), seconds: 0.5)

        let opening = semitones(try frequency(out[60..<360]), from: base)
        XCTAssertLessThan(opening, -1.4, "bend in should start well flat")
        XCTAssertGreaterThan(opening, -2.1, "but no more than two semitones")

        let quarter = step / 4
        let landed = try frequency(out, at: quarter + 900, width: 1200)
        assertRatio(landed, base, within: 0.005, "on pitch after a quarter step")
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

        assertRatio(try frequency(arp, at: step / 2), base * 2 * pow(2, -0.5), within: 0.03,
                    "arp octave plus half an octave of slide")
        assertRatio(try frequency(flat, at: step / 2), base * pow(2, -0.5), within: 0.03,
                    "the same slide without the arp")
        assertRatio(try frequency(arp, at: step), base, within: 0.03,
                    "a full octave down from the arp octave")
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
