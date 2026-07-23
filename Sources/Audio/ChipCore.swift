import Foundation

/// A 4-channel chiptune synthesiser and step sequencer.
///
/// Everything the render callback touches lives in manually allocated memory so
/// the audio thread never allocates, locks, or triggers copy-on-write. The main
/// thread writes parameters field-by-field; each field is word-sized and
/// independently meaningful, so a torn read is impossible and a stale read is
/// harmless (it lasts one buffer at most).
final class ChipCore {

    // MARK: Shared parameter blocks

    struct VoiceParams {
        var duty: Double = 0.5
        var volume: Double = 0.8
        /// Per-sample multiplier for the amplitude envelope.
        var decayCoeff: Double = 0.9999
        /// 1 when the note should hold instead of decaying.
        var sustain: Int32 = 0
        var muted: Int32 = 0
        var arpCount: Int32 = 0
        var arp0: Int32 = 0
        var arp1: Int32 = 0
        var arp2: Int32 = 0
        var arp3: Int32 = 0

        func arp(_ i: Int) -> Int32 {
            switch i {
            case 0: return arp0
            case 1: return arp1
            case 2: return arp2
            default: return arp3
            }
        }
    }

    private struct VoiceState {
        var phase: Double = 0
        var inc: Double = 0
        var env: Double = 0
        var baseFreq: Double = 0
        var lfsr: UInt16 = 1
        var noisePhase: Double = 0
        var noiseLevel: Double = 0
        var arpIndex: Int32 = 0
        var arpCounter: Int32 = 0
        var active: Bool = false
    }

    /// Special pattern value meaning "cut the sustaining note".
    static let noteOff: Int8 = -2

    // MARK: Storage

    /// `channelCount * maxSteps` note bytes, laid out channel-major.
    private let pattern: UnsafeMutablePointer<Int8>
    private let params: UnsafeMutablePointer<VoiceParams>
    private let voices: UnsafeMutablePointer<VoiceState>

    private let sampleRate: Double

    // Transport — written by the main thread, read by the audio thread.
    var tempo: Double = 120
    var length: Int32 = 16
    var playing: Bool = false
    var masterVolume: Double = 0.9

    /// Advances on the audio thread; the UI polls it to draw the playhead.
    private(set) var currentStep: Int32 = 0

    private var sampleCounter: Int32 = 0
    /// One-pole lowpass state, just enough to take the fizz off the aliasing.
    private var lpState: Double = 0
    /// DC blocker state. Narrow pulse duties are strongly asymmetric (a 12%
    /// pulse sits at -0.75 on average), which eats headroom and clicks on note
    /// changes, so the master output is high-passed at about 10 Hz.
    private var dcX: Double = 0
    private var dcY: Double = 0

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        let cells = Chip.channelCount * Chip.maxSteps
        pattern = .allocate(capacity: cells)
        pattern.initialize(repeating: Chip.emptyNote, count: cells)
        params = .allocate(capacity: Chip.channelCount)
        params.initialize(repeating: VoiceParams(), count: Chip.channelCount)
        voices = .allocate(capacity: Chip.channelCount)
        voices.initialize(repeating: VoiceState(), count: Chip.channelCount)
    }

    deinit {
        pattern.deallocate()
        params.deallocate()
        voices.deallocate()
    }

    // MARK: Main-thread writes

    func setNote(channel: Int, step: Int, note: Int8) {
        guard channel >= 0, channel < Chip.channelCount, step >= 0, step < Chip.maxSteps else { return }
        pattern[channel * Chip.maxSteps + step] = note
    }

    func load(song: Song) {
        tempo = song.tempo
        length = Int32(min(max(song.length, 4), Chip.maxSteps))
        for (i, track) in song.tracks.enumerated() where i < Chip.channelCount {
            for step in 0..<Chip.maxSteps {
                pattern[i * Chip.maxSteps + step] = step < track.notes.count ? track.notes[step] : Chip.emptyNote
            }
            setInstrument(track.instrument, kind: track.kind, channel: i, muted: track.muted)
        }
    }

    func setInstrument(_ inst: Instrument, kind: ChannelKind, channel: Int, muted: Bool) {
        guard channel >= 0, channel < Chip.channelCount else { return }
        var p = params[channel]
        p.duty = kind.hasDuty ? Instrument.dutyCycles[min(max(inst.duty, 0), 3)] : 0.5
        p.volume = min(max(inst.volume, 0), 1)
        p.muted = muted ? 1 : 0
        // 4 s of decay is the UI's maximum and means "hold until the next note".
        if inst.decay >= 3.99 {
            p.sustain = 1
            p.decayCoeff = 1.0
        } else {
            p.sustain = 0
            let seconds = max(inst.decay, 0.01)
            // Reach -60 dB after `seconds`.
            p.decayCoeff = pow(0.001, 1.0 / (seconds * sampleRate))
        }
        let arp = inst.arpeggio.prefix(4)
        p.arpCount = Int32(arp.count)
        for (i, semi) in arp.enumerated() {
            switch i {
            case 0: p.arp0 = Int32(semi)
            case 1: p.arp1 = Int32(semi)
            case 2: p.arp2 = Int32(semi)
            default: p.arp3 = Int32(semi)
            }
        }
        params[channel] = p
    }

    func start() {
        for c in 0..<Chip.channelCount { voices[c].env = 0; voices[c].active = false }
        currentStep = 0
        sampleCounter = 0
        lpState = 0
        dcX = 0
        dcY = 0
        playing = true
    }

    func stop() {
        playing = false
        for c in 0..<Chip.channelCount { voices[c].active = false; voices[c].env = 0 }
    }

    /// Plays a single note immediately, for keyboard previews.
    func audition(channel: Int, note: Int8) {
        guard channel >= 0, channel < Chip.channelCount, note >= 0 else { return }
        trigger(channel: channel, note: note)
    }

    // MARK: Audio thread

    private func samplesPerStep() -> Int32 {
        let bpm = min(max(tempo, 40), 300)
        return Int32((sampleRate * 60.0 / (bpm * 4.0)).rounded())
    }

    private func trigger(channel: Int, note: Int8) {
        var v = voices[channel]
        v.baseFreq = NoteName.frequency(note)
        v.inc = v.baseFreq / sampleRate
        v.env = 1.0
        v.active = true
        v.arpIndex = 0
        v.arpCounter = 0
        // Noise keeps its shift register running; retriggering it sounds worse.
        if channel != ChannelKind.noise.rawValue { v.phase = 0 }
        if v.lfsr == 0 { v.lfsr = 1 }
        voices[channel] = v
    }

    private func triggerStep(_ step: Int32) {
        let s = Int(step)
        for c in 0..<Chip.channelCount {
            let note = pattern[c * Chip.maxSteps + s]
            if note == ChipCore.noteOff {
                voices[c].active = false
                voices[c].env = 0
            } else if note >= 0 {
                trigger(channel: c, note: note)
            }
        }
    }

    /// Produces one sample for a voice, advancing its oscillator state.
    private func voiceSample(_ c: Int) -> Double {
        var v = voices[c]
        guard v.active, v.env > 0.0001 else {
            if v.active && v.env <= 0.0001 { v.active = false; voices[c] = v }
            return 0
        }
        let p = params[c]

        // Arpeggio: step through the offsets at ~50 Hz for that "fake chord" trill.
        if p.arpCount > 1 {
            v.arpCounter += 1
            if Double(v.arpCounter) >= sampleRate / 50.0 {
                v.arpCounter = 0
                v.arpIndex = (v.arpIndex + 1) % p.arpCount
                let semis = Double(p.arp(Int(v.arpIndex)))
                v.inc = (v.baseFreq * pow(2.0, semis / 12.0)) / sampleRate
            }
        }

        var out: Double
        switch ChannelKind(rawValue: c) ?? .pulse1 {
        case .pulse1, .pulse2:
            v.phase += v.inc
            if v.phase >= 1 { v.phase -= 1 }
            out = v.phase < p.duty ? 1.0 : -1.0

        case .triangle:
            v.phase += v.inc
            if v.phase >= 1 { v.phase -= 1 }
            // 16 quantisation steps per half cycle, like the NES triangle channel.
            let tri = v.phase < 0.5 ? v.phase * 4.0 - 1.0 : 3.0 - v.phase * 4.0
            out = (tri * 8.0).rounded(.down) / 8.0

        case .noise:
            // Clock a 15-bit LFSR at a multiple of the note frequency so the
            // noise is pitched rather than a flat hiss.
            v.noisePhase += v.inc * 8.0
            while v.noisePhase >= 1 {
                v.noisePhase -= 1
                let bit = (v.lfsr ^ (v.lfsr >> 1)) & 1
                v.lfsr = (v.lfsr >> 1) | (bit << 14)
                v.noiseLevel = (v.lfsr & 1) == 1 ? 1.0 : -1.0
            }
            out = v.noiseLevel
        }

        if p.sustain == 0 {
            v.env *= p.decayCoeff
        }
        out *= v.env * p.volume
        if p.muted == 1 { out = 0 }
        voices[c] = v
        return out
    }

    /// Renders `frames` mono samples. Used by both the live render callback and
    /// the offline WAV exporter.
    func render(frames: Int, into out: UnsafeMutablePointer<Float>) {
        let sps = samplesPerStep()
        let len = min(max(length, 1), Int32(Chip.maxSteps))

        for i in 0..<frames {
            if playing {
                if sampleCounter <= 0 {
                    triggerStep(currentStep)
                    sampleCounter = sps
                }
                sampleCounter -= 1
                if sampleCounter <= 0 {
                    currentStep = (currentStep + 1) % len
                }
            }

            var mix = 0.0
            for c in 0..<Chip.channelCount { mix += voiceSample(c) }
            mix *= 0.32 * masterVolume

            // Gentle lowpass, DC blocker, then a soft clip so stacked channels
            // never crack.
            lpState += (mix - lpState) * 0.55
            dcY = lpState - dcX + 0.9985 * dcY
            dcX = lpState
            out[i] = Float(tanh(dcY * 1.2))
        }
    }
}
