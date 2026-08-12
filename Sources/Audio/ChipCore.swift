import Foundation

/// A chiptune synthesiser and pattern sequencer.
///
/// Everything the render callback touches lives in manually allocated memory so
/// the audio thread never allocates, locks, or triggers copy-on-write. The main
/// thread writes parameters field-by-field; each field is word-sized and
/// independently meaningful, so a torn read is impossible and a stale read is
/// harmless (it lasts one buffer at most).
///
/// The core holds every pattern in the song plus the flattened chain, so
/// following an arrangement costs the audio thread one extra index lookup at
/// each pattern boundary and never a trip back to the main thread.
final class ChipCore {

    // MARK: Shared parameter blocks

    struct VoiceParams {
        /// `ChannelKind.rawValue`. A voice's waveform travels with its params
        /// because several voices can share one kind.
        var kind: Int32 = 0
        var duty: Double = 0.5
        var volume: Double = 0.8
        /// Per-sample multiplier for the amplitude envelope.
        var decayCoeff: Double = 0.9999
        /// 1 when the note should hold instead of decaying.
        var sustain: Int32 = 0
        /// Bumped when the main thread wants this voice cut. The audio thread
        /// compares it against its own ack rather than reading a flag, because
        /// `voiceSample` rewrites the whole voice struct every sample and would
        /// silently overwrite anything set into `voices` from outside.
        var releaseToken: Int32 = 0
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
        /// Samples left before a keyboard preview releases. 0 means "not a
        /// bounded preview" — sequencer notes are cut by the pattern instead.
        var previewSamples: Int32 = 0
        /// Set when a preview's time is up, or when a note-off cuts a note;
        /// overrides the sustain flag.
        var releasing: Bool = false
        /// Samples of ramp left before the envelope reaches full level. Every
        /// note starts with one so the waveform is never switched on mid-swing.
        var attack: Int32 = 0
        var attackInc: Double = 0
        /// Samples of fade-out left before `pendingNote` is triggered. Retriggering
        /// a voice that is still ringing goes through this, otherwise the jump in
        /// both amplitude and phase is a click — very audible on a run of the
        /// same note, where the level is still near 1.0 when the next one lands.
        var declick: Int32 = 0
        /// Per-sample amount to subtract during the fade. Linear rather than
        /// exponential: an exponential short enough to finish in a couple of
        /// milliseconds sheds >10% of the level per sample at the top, which is
        /// its own audible step.
        var declickDec: Double = 0
        var pendingNote: Int8 = -1
        /// Preview lifetime to apply once `pendingNote` starts.
        var pendingPreview: Int32 = 0
        /// Last `releaseToken` this voice has acted on.
        var releaseAck: Int32 = 0
        /// The pattern cell that started the note now sounding, or -1 when it
        /// came from the keyboard rather than from the sequencer. Lets the main
        /// thread ask "is the note I just erased the one I can hear?".
        var sourcePattern: Int32 = -1
        var sourceStep: Int32 = -1
    }

    /// Special pattern value meaning "cut the sustaining note".
    static let noteOff: Int8 = -2

    // MARK: Storage

    /// `maxPatterns * maxTracks * maxSteps` note bytes, pattern-major then track-major.
    private let pattern: UnsafeMutablePointer<Int8>
    private let patternLengths: UnsafeMutablePointer<Int32>
    /// Pattern slots to play in order, already expanded by section repeats.
    private let chain: UnsafeMutablePointer<Int32>
    private let params: UnsafeMutablePointer<VoiceParams>
    private let voices: UnsafeMutablePointer<VoiceState>
    /// Two slots: `[0]` is bumped by `start()` to ask the audio thread to
    /// rewind, `[1]` is the last value the audio thread acted on. Same shape as
    /// `VoiceParams.releaseToken`, and here for the same reason it lives in
    /// allocated memory rather than in a stored property — see `start()`.
    private let transport: UnsafeMutablePointer<Int32>

    private let sampleRate: Double

    // Transport — written by the main thread, read by the audio thread.
    var tempo: Double = 120
    /// How many of the `maxTracks` voices the song actually uses.
    var trackCount: Int32 = 4
    var patternCount: Int32 = 1
    var chainCount: Int32 = 1
    /// When false the sequencer loops `focusPattern` — the pattern being edited.
    /// When true it walks the chain.
    var songMode: Bool = false
    var focusPattern: Int32 = 0
    var playing: Bool = false
    var masterVolume: Double = 0.9

    /// Advance on the audio thread; the UI polls them to draw the playhead.
    private(set) var currentStep: Int32 = 0
    private(set) var currentPattern: Int32 = 0

    private var chainPos: Int32 = 0
    private var sampleCounter: Int32 = 0
    /// One-pole lowpass state, just enough to take the fizz off the aliasing.
    private var lpState: Double = 0
    /// DC blocker state. Narrow pulse duties are strongly asymmetric (a 12%
    /// pulse sits at -0.75 on average), which eats headroom and clicks on note
    /// changes, so the master output is high-passed at about 10 Hz.
    private var dcX: Double = 0
    private var dcY: Double = 0

    /// How long a sustaining instrument rings when auditioned from the keyboard.
    private static let previewSeconds = 0.9
    /// Per-sample multiplier that takes a released preview to silence in ~15 ms.
    private let releaseCoeff: Double
    /// ~2.5 ms of fade before a retrigger, then ~1.2 ms ramping the new note up.
    /// Short enough that the attack still reads as instant, long enough that
    /// neither edge is a step.
    private let declickSamples: Int32
    private let attackSamples: Int32

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        releaseCoeff = pow(0.001, 1.0 / (0.015 * sampleRate))
        declickSamples = max(Int32(sampleRate * 0.0025), 8)
        attackSamples = max(Int32(sampleRate * 0.0012), 8)

        let cells = Chip.maxPatterns * Chip.maxTracks * Chip.maxSteps
        pattern = .allocate(capacity: cells)
        pattern.initialize(repeating: Chip.emptyNote, count: cells)
        patternLengths = .allocate(capacity: Chip.maxPatterns)
        patternLengths.initialize(repeating: 16, count: Chip.maxPatterns)
        chain = .allocate(capacity: Chip.maxChain)
        chain.initialize(repeating: 0, count: Chip.maxChain)
        params = .allocate(capacity: Chip.maxTracks)
        params.initialize(repeating: VoiceParams(), count: Chip.maxTracks)
        voices = .allocate(capacity: Chip.maxTracks)
        voices.initialize(repeating: VoiceState(), count: Chip.maxTracks)
        transport = .allocate(capacity: 2)
        transport.initialize(repeating: 0, count: 2)
    }

    deinit {
        pattern.deallocate()
        patternLengths.deallocate()
        chain.deallocate()
        params.deallocate()
        voices.deallocate()
        transport.deallocate()
    }

    private func cell(_ pat: Int, _ track: Int, _ step: Int) -> Int {
        ((pat * Chip.maxTracks) + track) * Chip.maxSteps + step
    }

    // MARK: Main-thread writes

    func setNote(pattern pat: Int, track: Int, step: Int, note: Int8) {
        guard pat >= 0, pat < Chip.maxPatterns,
              track >= 0, track < Chip.maxTracks,
              step >= 0, step < Chip.maxSteps else { return }
        pattern[cell(pat, track, step)] = note
    }

    /// Cuts a voice the sequencer has no way to stop. A sustaining note is
    /// otherwise ended only by a note-off cell, a new note, or `stop()` — erase
    /// the note that started it and nothing is left to release it.
    func release(track: Int) {
        guard track >= 0, track < Chip.maxTracks else { return }
        params[track].releaseToken &+= 1
    }

    func releaseAll() {
        for track in 0..<Chip.maxTracks { params[track].releaseToken &+= 1 }
    }

    /// Which pattern cell started the note currently sounding on `track`, or
    /// nil when it is silent or came from a keyboard preview.
    ///
    /// Racy by construction: the audio thread can retrigger the voice while the
    /// answer is in flight. A stale answer costs one missed or one extra
    /// release, never a wrong note, which is why this needs no synchronisation.
    func ringingSource(track: Int) -> (pattern: Int, step: Int)? {
        guard track >= 0, track < Chip.maxTracks else { return nil }
        let voice = voices[track]
        guard voice.active, voice.sourcePattern >= 0, voice.sourceStep >= 0 else { return nil }
        return (Int(voice.sourcePattern), Int(voice.sourceStep))
    }

    func setLength(pattern pat: Int, length: Int) {
        guard pat >= 0, pat < Chip.maxPatterns else { return }
        patternLengths[pat] = Int32(min(max(length, 1), Chip.maxSteps))
    }

    func load(song: Song) {
        tempo = song.tempo
        let count = min(song.tracks.count, Chip.maxTracks)

        for (p, pat) in song.patterns.enumerated() where p < Chip.maxPatterns {
            patternLengths[p] = Int32(min(max(pat.length, 1), Chip.maxSteps))
            for track in 0..<Chip.maxTracks {
                let row = track < count ? pat.rows[safe: track] : nil
                for step in 0..<Chip.maxSteps {
                    pattern[cell(p, track, step)] = row?[safe: step] ?? Chip.emptyNote
                }
            }
        }
        patternCount = Int32(max(min(song.patterns.count, Chip.maxPatterns), 1))

        for (i, track) in song.tracks.enumerated() where i < Chip.maxTracks {
            setInstrument(track.instrument, kind: track.kind, track: i, muted: track.muted)
        }
        // Silence anything the song no longer uses before the render loop can
        // stop looking at it, so a deleted track can't be left ringing.
        for c in count..<Chip.maxTracks {
            voices[c].active = false
            voices[c].env = 0
            voices[c].declick = 0
        }
        trackCount = Int32(max(count, 1))

        setChain(song.chain)
        if focusPattern >= patternCount { focusPattern = 0 }
        if currentPattern >= patternCount { currentPattern = 0 }
    }

    /// Replaces the play order. Writes the count last so the audio thread never
    /// walks entries that haven't been written yet.
    func setChain(_ slots: [Int]) {
        let clamped = slots.prefix(Chip.maxChain)
        for (i, slot) in clamped.enumerated() {
            chain[i] = Int32(min(max(slot, 0), Chip.maxPatterns - 1))
        }
        let count = Int32(max(clamped.count, 1))
        if chainPos >= count { chainPos = 0 }
        chainCount = count
    }

    /// Points pattern-mode playback at the pattern being edited.
    func focus(pattern index: Int) {
        let slot = Int32(min(max(index, 0), Chip.maxPatterns - 1))
        focusPattern = slot
        if !songMode { currentPattern = slot }
    }

    /// Switches between looping one pattern and following the arrangement,
    /// restarting the chain so SONG always begins at the top.
    func setSongMode(_ on: Bool) {
        songMode = on
        if on {
            chainPos = 0
            currentPattern = chain[0]
        } else {
            currentPattern = focusPattern
        }
    }

    func setInstrument(_ inst: Instrument, kind: ChannelKind, track: Int, muted: Bool) {
        guard track >= 0, track < Chip.maxTracks else { return }
        let wasSustaining = params[track].sustain == 1
        var p = params[track]
        p.kind = Int32(kind.rawValue)
        p.duty = kind.hasDuty ? Instrument.dutyCycles[min(max(inst.duty, 0), 3)] : 0.5
        p.volume = min(max(inst.volume, 0), 1)
        p.muted = muted ? 1 : 0
        if inst.sustain {
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
            // `Int32(_:)` traps on anything that doesn't fit, so a file with a
            // wild offset would crash here rather than merely sound wrong.
            // `Instrument.normalize` clamps these to ±48 long before they
            // arrive; the saturating conversion is the belt to that's braces.
            let value = Int32(clamping: semi)
            switch i {
            case 0: p.arp0 = value
            case 1: p.arp1 = value
            case 2: p.arp2 = value
            default: p.arp3 = value
            }
        }
        params[track] = p

        // A preview started under a decaying instrument has no lifetime of its
        // own — the decay was going to end it. Turning hold on while it rings
        // removes the only thing that ever would, so it inherits the lifetime
        // `audition` would have given it. The source guard keeps this away from
        // sequencer notes, which the pattern is still responsible for cutting.
        if p.sustain == 1, !wasSustaining,
           voices[track].active, !voices[track].releasing,
           voices[track].previewSamples == 0, voices[track].sourceStep < 0 {
            voices[track].previewSamples = Int32(sampleRate * ChipCore.previewSeconds)
        }
    }

    func start() {
        for c in 0..<Chip.maxTracks {
            voices[c].env = 0
            voices[c].active = false
            voices[c].declick = 0
            voices[c].pendingNote = Chip.emptyNote
        }
        // The playhead and the filter state are deliberately not written here.
        // `render` mutates both in place — `currentStep += 1`, `lpState += …` —
        // and Swift treats a read-modify-write of a stored property as an
        // exclusive access. A main-thread write landing inside one is an
        // exclusivity violation, which is undefined behaviour, not the harmless
        // stale read the rest of this contract trades on: the compiler is
        // entitled to assume nothing else writes for the duration. Thread
        // Sanitizer names it a "Swift access race" rather than a data race, and
        // that is the distinction — the benign reports here are the latter.
        //
        // Note this applies to the stored properties only. `voices`, `params`
        // and `pattern` are reached through `UnsafeMutablePointer`, which
        // exclusivity enforcement does not cover, so the writes above stay.
        //
        // So the rewind is requested and performed on the audio thread that
        // owns those fields, exactly as `releaseToken` does for voices. The
        // token is bumped before `playing`, so a buffer that sees playback
        // start has already rewound; a buffer that sees only the token rewinds
        // and stays silent one more buffer, which is inaudible.
        //
        // It lives in `transport` rather than in a stored property for the very
        // reason described above: `token &+= 1` on a property is itself a
        // read-modify-write, so a token kept there would only move the
        // exclusivity violation from `lpState` into the mechanism meant to
        // avoid it. Through a pointer it is an ordinary word-sized write.
        transport[0] = transport[0] &+ 1
        playing = true
    }

    func stop() {
        playing = false
        // Release rather than cut: a hard stop mid-waveform is a click.
        for c in 0..<Chip.maxTracks {
            voices[c].previewSamples = 0
            voices[c].declick = 0
            voices[c].pendingNote = Chip.emptyNote
            voices[c].attack = 0
            if voices[c].active { voices[c].releasing = true }
        }
    }

    /// Ends offline playback at the tail. Stops the sequencer and releases any
    /// voice that would otherwise sustain forever — a sustaining instrument has
    /// no next note to cut it once the song runs out — while leaving decaying
    /// voices alone so they ring out naturally through the tail rather than
    /// holding at full level and then hard-cutting at the end of the file.
    func finish() {
        playing = false
        for c in 0..<Chip.maxTracks {
            voices[c].previewSamples = 0
            guard params[c].sustain == 1 else { continue }
            voices[c].declick = 0
            voices[c].pendingNote = Chip.emptyNote
            if voices[c].active { voices[c].releasing = true }
        }
    }

    /// Plays a single note immediately, for keyboard previews.
    ///
    /// A sustaining instrument (the triangle ships that way) has no pattern step
    /// to cut it here, so the preview gets its own fixed lifetime. Decaying
    /// instruments are left alone and preview exactly as they'll sound.
    func audition(track: Int, note: Int8) {
        guard track >= 0, track < Chip.maxTracks, note >= 0 else { return }
        trigger(track: track, note: note)
        voices[track].sourcePattern = -1
        voices[track].sourceStep = -1
        let preview = params[track].sustain == 1 ? Int32(sampleRate * ChipCore.previewSeconds) : 0
        // A retrigger defers the note past its de-click fade, so the preview
        // lifetime has to wait with it.
        if voices[track].declick > 0 {
            voices[track].pendingPreview = preview
        } else {
            voices[track].previewSamples = preview
        }
    }

    // MARK: Audio thread

    private func samplesPerStep() -> Int32 {
        let bpm = min(max(tempo, 40), 300)
        return Int32((sampleRate * 60.0 / (bpm * 4.0)).rounded())
    }

    /// Starts a note on a voice that is already at silence.
    private func begin(_ v: inout VoiceState, kind: Int32, note: Int8) {
        v.baseFreq = NoteName.frequency(note)
        v.inc = v.baseFreq / sampleRate
        v.env = 0
        v.attack = attackSamples
        v.attackInc = 1.0 / Double(attackSamples)
        v.active = true
        v.arpIndex = 0
        v.arpCounter = 0
        v.releasing = false
        v.declick = 0
        v.pendingNote = Chip.emptyNote
        v.previewSamples = v.pendingPreview
        v.pendingPreview = 0
        // Noise keeps its shift register running; retriggering it sounds worse.
        if kind != Int32(ChannelKind.noise.rawValue) { v.phase = 0 }
        if v.lfsr == 0 { v.lfsr = 1 }
    }

    private func trigger(track: Int, note: Int8) {
        var v = voices[track]
        if v.active && v.env > 0.002 {
            // Still ringing — fade it out first and start the new note from the
            // far side of the fade.
            v.pendingNote = note
            v.pendingPreview = 0
            v.declick = declickSamples
            v.declickDec = v.env / Double(declickSamples)
            v.attack = 0
            v.releasing = false
        } else {
            v.pendingPreview = 0
            begin(&v, kind: params[track].kind, note: note)
        }
        voices[track] = v
    }

    private func triggerStep(_ pat: Int32, _ step: Int32, tracks: Int) {
        let s = Int(step)
        let p = Int(pat)
        for c in 0..<tracks {
            let note = pattern[cell(p, c, s)]
            if note == ChipCore.noteOff {
                if voices[c].active { voices[c].releasing = true }
                voices[c].declick = 0
                voices[c].pendingNote = Chip.emptyNote
            } else if note >= 0 {
                trigger(track: c, note: note)
                // Recorded here rather than in `begin`, because a retrigger
                // defers the note past its de-click fade — the cell it came
                // from is known now, not when it eventually starts.
                voices[c].sourcePattern = pat
                voices[c].sourceStep = step
            }
        }
    }

    /// Produces one sample for a voice, advancing its oscillator state.
    private func voiceSample(_ c: Int) -> Double {
        var v = voices[c]
        // A voice mid-attack sits at env 0 and must not be culled here.
        guard v.active, v.env > 0.0001 || v.attack > 0 || v.declick > 0 else {
            if v.active { v.active = false; v.env = 0; voices[c] = v }
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
        switch ChannelKind(rawValue: Int(p.kind)) ?? .pulse1 {
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

        if v.previewSamples > 0 {
            v.previewSamples -= 1
            if v.previewSamples == 0 { v.releasing = true }
        }

        // Envelope. The order matters: a pending retrigger owns the voice until
        // its fade completes, and the note that follows starts in attack.
        if v.declick > 0 {
            v.declick -= 1
            v.env = max(0, v.env - v.declickDec)
            if v.declick == 0 {
                let note = v.pendingNote
                if note >= 0 {
                    begin(&v, kind: p.kind, note: note)
                } else {
                    v.env = 0
                    v.active = false
                }
            }
        } else if v.attack > 0 {
            v.attack -= 1
            v.env = min(1.0, v.env + v.attackInc)
        } else if v.releasing {
            v.env *= releaseCoeff
        } else if p.sustain == 0 {
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
        let patterns = Int32(min(max(patternCount, 1), Int32(Chip.maxPatterns)))
        let links = Int32(min(max(chainCount, 1), Int32(Chip.maxChain)))
        let tracks = Int(min(max(trackCount, 1), Int32(Chip.maxTracks)))
        // Four tracks keep the level they always had; beyond that the mix is
        // pulled down so eight voices at once don't ride the soft clipper.
        let gain = 0.32 * (4.0 / Double(max(tracks, 4))).squareRoot()

        // Pick up anything the main thread asked to cut since the last buffer.
        // Once per buffer rather than per sample, and via the token rather than
        // a flag written straight into `voices`, which the per-sample
        // read-modify-write below would clobber.
        // `releaseAck` is written only here, on the audio thread. A token
        // bumped while the transport was stopped is acked against a voice
        // `start`/`load` has already silenced, so the `active` guard drops it —
        // no main-thread sync needed, and none wanted: writing into `voices`
        // from outside is the hazard this whole mechanism exists to avoid.
        for c in 0..<tracks where params[c].releaseToken != voices[c].releaseAck {
            voices[c].releaseAck = params[c].releaseToken
            guard voices[c].active else { continue }
            voices[c].releasing = true
            voices[c].previewSamples = 0
            voices[c].declick = 0
            voices[c].pendingNote = Chip.emptyNote
        }

        // A `start()` since the last buffer rewinds the transport here rather
        // than on the main thread — see `start()` for why it cannot do it
        // itself. Before the sample loop, so the first step lands on frame 0.
        if transport[0] != transport[1] {
            transport[1] = transport[0]
            chainPos = 0
            currentPattern = songMode ? chain[0] : focusPattern
            currentStep = 0
            sampleCounter = 0
            lpState = 0
            dcX = 0
            dcY = 0
        }

        for i in 0..<frames {
            if playing {
                if currentPattern >= patterns { currentPattern = 0 }
                let len = min(max(patternLengths[Int(currentPattern)], 1), Int32(Chip.maxSteps))
                // The edited pattern can shrink under the playhead, and a mode
                // switch can move it to a shorter pattern mid-bar.
                if currentStep >= len { currentStep = 0 }

                if sampleCounter <= 0 {
                    triggerStep(currentPattern, currentStep, tracks: tracks)
                    sampleCounter = sps
                }
                sampleCounter -= 1
                if sampleCounter <= 0 {
                    currentStep += 1
                    if currentStep >= len {
                        currentStep = 0
                        if songMode {
                            chainPos = (chainPos + 1) % links
                            currentPattern = min(chain[Int(chainPos)], patterns - 1)
                        } else {
                            currentPattern = min(focusPattern, patterns - 1)
                        }
                    }
                }
            }

            var mix = 0.0
            for c in 0..<tracks { mix += voiceSample(c) }
            mix *= gain * masterVolume

            // The DC blocker below feeds `dcY` back into itself, so a single
            // non-finite sample reaching it doesn't glitch — it latches, and
            // the app outputs NaN until it's relaunched. `Instrument.normalize`
            // is what stops such a sample existing; this is the backstop that
            // keeps a miss to one bad buffer instead of a dead audio engine.
            if !mix.isFinite {
                mix = 0
                lpState = 0
                dcX = 0
                dcY = 0
            }

            // Gentle lowpass, DC blocker, then a soft clip so stacked channels
            // never crack.
            lpState += (mix - lpState) * 0.55
            dcY = lpState - dcX + 0.9985 * dcY
            dcX = lpState
            out[i] = Float(tanh(dcY * 1.2))
        }
    }
}
