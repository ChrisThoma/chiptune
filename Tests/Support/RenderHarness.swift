import Foundation
@testable import Chiptune

/// Renders `ChipCore` offline and measures the result.
///
/// The core is deterministic and hardware-free, so every DSP assertion in the
/// suite runs here rather than through an audio device: load a song, render a
/// window, measure it. No `AVAudioEngine`, no timing, no flake.
enum RenderHarness {

    static let sampleRate = 44100.0

    // MARK: Rendering

    /// Renders `frames` samples in `chunk`-sized slices, the way both the live
    /// callback and the WAV exporter do. Chunking matters: a bug that only
    /// shows up across a slice boundary is invisible to a single big render.
    static func renderMono(_ core: ChipCore, frames: Int, chunk: Int = 1024) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        out.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var done = 0
            while done < frames {
                let n = min(chunk, frames - done)
                core.render(frames: n, into: base + done)
                done += n
            }
        }
        return out
    }

    /// Loads a song into a fresh core and renders `seconds` of it playing.
    /// `songMode` false loops the focused pattern, matching PATT in the app.
    static func render(song: Song, seconds: Double, songMode: Bool = false) -> [Float] {
        var song = song
        song.normalize()
        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(songMode)
        core.start()
        return renderMono(core, frames: Int(sampleRate * seconds))
    }

    // MARK: Level

    static func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    static func rms(_ samples: [Float]) -> Double { rms(samples[...]) }

    static func peak(_ samples: ArraySlice<Float>) -> Double {
        samples.reduce(0.0) { max($0, abs(Double($1))) }
    }

    static func peak(_ samples: [Float]) -> Double { peak(samples[...]) }

    /// Fraction of the window spent above zero. A 25% pulse sits high a quarter
    /// of the time, so this reads a duty cycle straight off the output.
    ///
    /// Measured after the master chain's DC blocker, which shifts the waveform
    /// so its average is zero — that moves the crossing point but not the ratio
    /// of time spent on each side, because the blocker is far below the note.
    static func dutyRatio(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let high = samples.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
        return Double(high) / Double(samples.count)
    }

    // MARK: Pitch

    /// Goertzel magnitude at `frequency` — the energy the signal carries at one
    /// specific frequency, without paying for a whole FFT.
    ///
    /// Normalised by window length so magnitudes from different-sized windows
    /// are comparable.
    static func goertzel(_ samples: ArraySlice<Float>, frequency: Double,
                         sampleRate: Double = RenderHarness.sampleRate) -> Double {
        guard samples.count > 1 else { return 0 }
        let k = 2.0 * cos(2.0 * .pi * frequency / sampleRate)
        var s1 = 0.0, s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + k * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - k * s1 * s2
        return max(power, 0).squareRoot() / Double(samples.count)
    }

    /// The candidate frequency carrying the most energy. Voice tests hand it a
    /// semitone ladder and assert the expected note wins — a stronger claim
    /// than "there is energy at the right frequency", which a broadband noise
    /// burst would also satisfy.
    static func dominantFrequency(_ samples: ArraySlice<Float>,
                                  candidates: [Double]) -> Double? {
        candidates.max { goertzel(samples, frequency: $0) < goertzel(samples, frequency: $1) }
    }

    /// Semitone ladder around a MIDI note, for `dominantFrequency` candidates.
    static func semitoneLadder(around midi: Int8, spread: Int = 12) -> [Double] {
        ((-spread)...spread).map { NoteName.frequency(Int8(clamping: Int(midi) + $0)) }
    }

    /// How sharply the spectrum peaks across `frequencies`: strongest bin over
    /// the average bin. A pitched voice scores ~20 because one bin holds nearly
    /// all the energy; broadband noise scores ~3 because none does.
    ///
    /// This is what stands in for a pitch assertion on the noise channel, which
    /// has no pitch to assert. (A min/max "flatness" ratio does not work here:
    /// a pitched tone measured on a ladder that misses its fundamental scores
    /// as flat, so flatness fails to tell the two apart at all.)
    static func spectralPeakiness(_ samples: ArraySlice<Float>,
                                  frequencies: [Double]) -> Double {
        let mags = frequencies.map { goertzel(samples, frequency: $0) }
        let mean = mags.reduce(0, +) / Double(mags.count)
        guard mean > 0 else { return 0 }
        return (mags.max() ?? 0) / mean
    }

    /// Number of level changes in the window — runs of samples that are moving,
    /// separated by samples that aren't.
    ///
    /// Counts *runs* rather than samples over the threshold: the master
    /// lowpass smears every edge across two or three samples, so a per-sample
    /// count would depend on the threshold rather than on the waveform. This
    /// reads the NES triangle's staircase directly: 30 changes per cycle for a
    /// 16-level triangle, 2 for a pulse, 0 for anything smooth.
    static func levelSteps(_ samples: ArraySlice<Float>, threshold: Double = 0.008) -> Int {
        guard samples.count > 1 else { return 0 }
        var steps = 0
        var moving = false
        var previous = Double(samples[samples.startIndex])
        for i in (samples.startIndex + 1)..<samples.endIndex {
            let value = Double(samples[i])
            let jumping = abs(value - previous) > threshold
            if jumping && !moving { steps += 1 }
            moving = jumping
            previous = value
        }
        return steps
    }

    // MARK: Onsets

    /// Sample indices where the signal jumps from near-silence into audio —
    /// i.e. where a note started.
    ///
    /// Works on a short-window RMS envelope rather than raw samples, because a
    /// raw waveform crosses any fixed threshold twice per cycle. `refractory`
    /// stops one attack being counted as several.
    static func onsets(_ samples: [Float],
                       threshold: Double = 0.02,
                       window: Int = 128,
                       refractory: Int = 2048) -> [Int] {
        var found: [Int] = []
        var wasQuiet = true
        var i = 0
        while i + window <= samples.count {
            let level = rms(samples[i..<(i + window)])
            if level > threshold {
                if wasQuiet, found.last.map({ i - $0 >= refractory }) ?? true {
                    found.append(i)
                }
                wasQuiet = false
            } else if level < threshold * 0.5 {
                // Hysteresis: a signal hovering at the threshold must not
                // register as a run of onsets.
                wasQuiet = true
            }
            i += window
        }
        return found
    }

    /// Largest jump between neighbouring samples. A retrigger that skips the
    /// de-click fade shows up here as a step the rest of the waveform never
    /// takes.
    static func maxDelta(_ samples: ArraySlice<Float>) -> Double {
        guard samples.count > 1 else { return 0 }
        var worst = 0.0
        var previous = Double(samples[samples.startIndex])
        for i in (samples.startIndex + 1)..<samples.endIndex {
            let value = Double(samples[i])
            worst = max(worst, abs(value - previous))
            previous = value
        }
        return worst
    }
}
