package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.swiftClamp

/**
 * A chiptune synthesizer and pattern sequencer. Port of
 * `Sources/Audio/ChipCore.swift`; the constants and the order of operations
 * in [voiceSample] and [render] are the Swift ones, line for line, because the
 * shared golden WAV (`Tests/Fixtures/golden-demo.wav`) pins this output to the
 * iOS synth sample for sample.
 *
 * ## Threading contract
 *
 * Two threads touch a core: the main thread writes parameters, and one render
 * thread (Phase 4's AudioTrack write loop, or the WAV exporter's thread) calls
 * [render]. There are no locks, and [render] allocates nothing, so a GC pause
 * or a priority inversion can never reach the audio thread. The same argument
 * as the Swift file applies:
 *
 * - Every shared value is word-sized and independently meaningful. Transport
 *   scalars ([tempo], [trackCount], [songMode], the playhead...) are
 *   `@Volatile`, so each read sees some complete value a writer stored.
 * - Per-voice parameters, the pattern grid, pattern lengths and the chain live
 *   in primitive arrays preallocated at their maximum sizes (8 tracks x 16
 *   patterns x 64 steps) and are written element by element. A render that
 *   reads a mix of old and new elements is at worst stale for one buffer,
 *   which is inaudible. Every value the audio thread uses as an index is
 *   clamped by its writer and re-clamped by the reader, so a stale or racing
 *   value can sound wrong for a buffer but never index out of bounds.
 * - Voice state ([VoiceState]) belongs to the render thread. The main thread
 *   writes into it only where Swift does (`start`, `stop`, `finish`, `load`,
 *   `audition`, `setInstrument`'s preview hand-off), with the same "stale for
 *   a buffer" outcome. Requests that must not be lost (a release, a rewind)
 *   go through counter tokens instead: the main thread bumps a counter and the
 *   render thread acts when it differs from the last value it acked.
 * - 64-bit elements (the `DoubleArray`s and `Double` voice fields) are
 *   single-copy atomic on every 64-bit ABI. A 32-bit ABI may in principle
 *   tear a racing `Double`; the worst a torn value can do is produce a
 *   non-finite sample, and the master stage zeroes those and resets its
 *   filters (the same backstop Swift has), so the damage is one sample.
 *
 * Float32 from the master stage on, as in iOS: the mix and filters run in
 * Double, and each output sample is `tanh(...).toFloat()`.
 */
class ChipCore(val sampleRate: Double = 44100.0) {

    /** Which pattern cell started the note sounding on a track. */
    data class RingingSource(val pattern: Int, val step: Int)

    /** Render-thread-owned voice state; see the threading contract above.
     * Plain fields, preallocated once per track. */
    private class VoiceState {
        @JvmField var phase = 0.0
        @JvmField var inc = 0.0
        @JvmField var env = 0.0
        @JvmField var baseFreq = 0.0
        /** 15-bit LFSR, held unsigned in an Int (never a signed Short). */
        @JvmField var lfsr = 1
        @JvmField var noisePhase = 0.0
        @JvmField var noiseLevel = 0.0
        @JvmField var arpIndex = 0
        @JvmField var arpCounter = 0
        @JvmField var active = false
        /** Samples left before a keyboard preview releases; 0 = not a bounded preview. */
        @JvmField var previewSamples = 0
        /** A preview's time is up, or a note-off cut the note; overrides sustain. */
        @JvmField var releasing = false
        /** Samples of ramp left before the envelope reaches full level. */
        @JvmField var attack = 0
        @JvmField var attackInc = 0.0
        /** Samples of fade-out left before [pendingNote] is triggered. */
        @JvmField var declick = 0
        /** Per-sample amount to subtract during the fade (linear). */
        @JvmField var declickDec = 0.0
        @JvmField var pendingNote = Chip.EMPTY_NOTE
        /** Preview lifetime to apply once [pendingNote] starts. */
        @JvmField var pendingPreview = 0
        /** Last release token this voice has acted on. */
        @JvmField var releaseAck = 0
        /** The cell that started the sounding note, or -1 for a keyboard preview. */
        @JvmField var sourcePattern = -1
        @JvmField var sourceStep = -1
    }

    // MARK: Storage

    /** `MAX_PATTERNS * MAX_TRACKS * MAX_STEPS` note bytes, pattern-major then track-major. */
    private val pattern = ByteArray(Chip.MAX_PATTERNS * Chip.MAX_TRACKS * Chip.MAX_STEPS) { Chip.EMPTY_NOTE.toByte() }
    private val patternLengths = IntArray(Chip.MAX_PATTERNS) { 16 }
    /** Pattern slots to play in order, already expanded by section repeats. */
    private val chain = IntArray(Chip.MAX_CHAIN)

    // Per-voice parameters (Swift's `VoiceParams`), one element per track.
    /** `ChannelKind.rawValue`. */
    private val paramKind = IntArray(Chip.MAX_TRACKS)
    private val paramDuty = DoubleArray(Chip.MAX_TRACKS) { 0.5 }
    private val paramVolume = DoubleArray(Chip.MAX_TRACKS) { 0.8 }
    /** Per-sample multiplier for the amplitude envelope. */
    private val paramDecayCoeff = DoubleArray(Chip.MAX_TRACKS) { 0.9999 }
    /** 1 when the note should hold instead of decaying. */
    private val paramSustain = IntArray(Chip.MAX_TRACKS)
    /** Bumped when the main thread wants this voice cut; the render thread
     * compares it against [VoiceState.releaseAck]. */
    private val paramReleaseToken = IntArray(Chip.MAX_TRACKS)
    private val paramMuted = IntArray(Chip.MAX_TRACKS)
    private val paramArpCount = IntArray(Chip.MAX_TRACKS)
    /** Four offsets per track. */
    private val paramArp = IntArray(Chip.MAX_TRACKS * 4)

    private val voices = Array(Chip.MAX_TRACKS) { VoiceState() }

    /** Bumped by [start] to ask the render thread to rewind; [transportAck]
     * is the last value the render thread acted on. */
    @Volatile private var transportRequest = 0
    private var transportAck = 0

    // Transport - written by the main thread, read by the render thread.
    @Volatile var tempo: Double = 120.0
    /** How many of the `MAX_TRACKS` voices the song actually uses. */
    @Volatile var trackCount: Int = 4
        private set
    @Volatile var patternCount: Int = 1
        private set
    @Volatile var chainCount: Int = 1
        private set
    /** When false the sequencer loops [focusPattern]; when true it walks the chain. */
    @Volatile var songMode: Boolean = false
        private set
    @Volatile var focusPattern: Int = 0
        private set
    @Volatile var playing: Boolean = false
        private set
    /** The export depends on this default; nothing in the app sets it. */
    @Volatile var masterVolume: Double = 0.9

    /** Advanced on the render thread; the UI polls them to draw the playhead. */
    @Volatile var currentStep: Int = 0
        private set
    @Volatile var currentPattern: Int = 0
        private set

    /** How far through the chain playback has got: advanced by the render
     * thread at each pattern boundary, reset by the main thread from
     * [setChain], [setSongMode] and [retarget]. */
    @Volatile private var chainPos: Int = 0

    /** The chain slot SONG playback is on, for the UI. A racy read like the
     * rest of the playhead - worst case one buffer stale. */
    val currentChainSlot: Int get() = chainPos

    // Render-thread-only state.
    private var sampleCounter = 0
    /** One-pole lowpass state, just enough to take the fizz off the aliasing. */
    private var lpState = 0.0
    /** DC blocker state (about 10 Hz high-pass on the master). */
    private var dcX = 0.0
    private var dcY = 0.0

    /** Per-sample multiplier that takes a released voice to silence in ~15 ms. */
    private val releaseCoeff: Double = StrictMath.pow(0.001, 1.0 / (0.015 * sampleRate))
    /** ~2.5 ms of fade before a retrigger, then ~1.2 ms ramping the new note
     * up. Truncated like Swift's `Int32(_:)`, floored at 8. Internal only so
     * tests can pin the rounding; nothing outside the core should read them. */
    internal val declickSamples: Int = maxOf((sampleRate * 0.0025).toInt(), 8)
    internal val attackSamples: Int = maxOf((sampleRate * 0.0012).toInt(), 8)

    /** `NoteName.frequency` for every MIDI note, and `pow(2, semis / 12)` for
     * every offset `Instrument.normalized` allows, computed once here with the
     * very same calls so the values are bit-identical. The render thread must
     * not call `StrictMath.pow` itself: on the JVM it is Java code
     * (`FdLibm.Pow`) that allocates scratch arrays per call, which only C2's
     * escape analysis removes. */
    private val noteFrequency = DoubleArray(128) { NoteName.frequency(it) }
    private val arpRatio = DoubleArray(2 * Instrument.MAX_ARPEGGIO_SEMITONES + 1) {
        StrictMath.pow(2.0, (it - Instrument.MAX_ARPEGGIO_SEMITONES).toDouble() / 12.0)
    }

    private fun cell(pat: Int, track: Int, step: Int): Int = ((pat * Chip.MAX_TRACKS) + track) * Chip.MAX_STEPS + step

    // MARK: Main-thread writes

    fun setNote(pattern: Int, track: Int, step: Int, note: Int) {
        if (pattern < 0 || pattern >= Chip.MAX_PATTERNS || track < 0 || track >= Chip.MAX_TRACKS ||
            step < 0 || step >= Chip.MAX_STEPS) return
        this.pattern[cell(pattern, track, step)] = toCell(note)
    }

    /** Cuts a voice the sequencer has no way to stop (an erased sustaining note). */
    fun release(track: Int) {
        if (track < 0 || track >= Chip.MAX_TRACKS) return
        paramReleaseToken[track] = paramReleaseToken[track] + 1
    }

    fun releaseAll() {
        for (track in 0 until Chip.MAX_TRACKS) paramReleaseToken[track] = paramReleaseToken[track] + 1
    }

    /** Which pattern cell started the note sounding on [track], or null when it
     * is silent or came from a keyboard preview. Racy by construction: a stale
     * answer costs one missed or one extra release, never a wrong note. */
    fun ringingSource(track: Int): RingingSource? {
        if (track < 0 || track >= Chip.MAX_TRACKS) return null
        val v = voices[track]
        val pat = v.sourcePattern
        val step = v.sourceStep
        if (!v.active || pat < 0 || step < 0) return null
        return RingingSource(pat, step)
    }

    fun setLength(pattern: Int, length: Int) {
        if (pattern < 0 || pattern >= Chip.MAX_PATTERNS) return
        patternLengths[pattern] = minOf(maxOf(length, 1), Chip.MAX_STEPS)
    }

    fun load(song: Song) {
        tempo = song.tempo
        val count = minOf(song.tracks.size, Chip.MAX_TRACKS)

        for ((p, pat) in song.patterns.withIndex()) {
            if (p >= Chip.MAX_PATTERNS) break
            patternLengths[p] = minOf(maxOf(pat.length, 1), Chip.MAX_STEPS)
            for (track in 0 until Chip.MAX_TRACKS) {
                val row = if (track < count) pat.rows.getOrNull(track) else null
                for (step in 0 until Chip.MAX_STEPS) {
                    pattern[cell(p, track, step)] = toCell(row?.getOrNull(step) ?: Chip.EMPTY_NOTE)
                }
            }
        }
        patternCount = maxOf(minOf(song.patterns.size, Chip.MAX_PATTERNS), 1)

        for ((i, track) in song.tracks.withIndex()) {
            if (i >= Chip.MAX_TRACKS) break
            setInstrument(track.instrument, track.kind, i, track.muted)
        }
        // Silence anything the song no longer uses before the render loop can
        // stop looking at it, so a deleted track can't be left ringing.
        for (c in count until Chip.MAX_TRACKS) {
            voices[c].active = false
            voices[c].env = 0.0
            voices[c].declick = 0
        }
        trackCount = maxOf(count, 1)

        setChain(song.chain)
        if (focusPattern >= patternCount) focusPattern = 0
        if (currentPattern >= patternCount) currentPattern = 0
    }

    /** Replaces the play order. Writes the count last so the render thread
     * never walks entries that haven't been written yet. */
    fun setChain(slots: List<Int>) {
        val n = minOf(slots.size, Chip.MAX_CHAIN)
        for (i in 0 until n) chain[i] = minOf(maxOf(slots[i], 0), Chip.MAX_PATTERNS - 1)
        val count = maxOf(n, 1)
        if (chainPos >= count) chainPos = 0
        chainCount = count
    }

    /** Points pattern-mode playback at the pattern being edited. */
    fun focus(pattern: Int) {
        val slot = minOf(maxOf(pattern, 0), Chip.MAX_PATTERNS - 1)
        focusPattern = slot
        if (!songMode) currentPattern = slot
    }

    /** Moves SONG playback to a different chain slot and pattern without
     * restarting anything, after the main thread renumbers patterns. */
    fun retarget(chainSlot: Int, pattern: Int) {
        chainPos = minOf(maxOf(chainSlot, 0), maxOf(chainCount, 1) - 1)
        currentPattern = minOf(maxOf(pattern, 0), maxOf(patternCount, 1) - 1)
    }

    /** Switches between looping one pattern and following the arrangement,
     * restarting the chain so SONG always begins at the top. */
    fun setSongMode(on: Boolean) {
        songMode = on
        if (on) {
            chainPos = 0
            currentPattern = chain[0]
        } else {
            currentPattern = focusPattern
        }
    }

    fun setInstrument(inst: Instrument, kind: ChannelKind, track: Int, muted: Boolean) {
        if (track < 0 || track >= Chip.MAX_TRACKS) return
        val wasSustaining = paramSustain[track] == 1
        paramKind[track] = kind.rawValue
        paramDuty[track] = if (kind.hasDuty) {
            Instrument.DUTY_CYCLES[minOf(maxOf(inst.duty, 0), Instrument.DUTY_CYCLES.size - 1)]
        } else {
            0.5
        }
        paramVolume[track] = swiftClamp(inst.volume, 0.0, 1.0)
        paramMuted[track] = if (muted) 1 else 0
        if (inst.sustain) {
            paramSustain[track] = 1
            paramDecayCoeff[track] = 1.0
        } else {
            paramSustain[track] = 0
            val seconds = swiftMax(inst.decay, 0.01)
            // Reach -60 dB after `seconds`.
            paramDecayCoeff[track] = StrictMath.pow(0.001, 1.0 / (seconds * sampleRate))
        }
        // Offsets before the count, so the render thread never pairs a new
        // count with offsets that haven't landed. Ints already: Swift's
        // `Int32(clamping:)` is the identity here.
        val arpCount = minOf(inst.arpeggio.size, 4)
        for (i in 0 until arpCount) paramArp[track * 4 + i] = inst.arpeggio[i]
        paramArpCount[track] = arpCount

        // A preview started under a decaying instrument has no lifetime of its
        // own. Turning hold on while it rings would remove the only thing that
        // ever ends it, so it inherits the lifetime `audition` would have given
        // it. The source guard keeps this away from sequencer notes.
        val v = voices[track]
        if (paramSustain[track] == 1 && !wasSustaining &&
            v.active && !v.releasing && v.previewSamples == 0 && v.sourceStep < 0) {
            v.previewSamples = (sampleRate * PREVIEW_SECONDS).toInt()
        }
    }

    fun start() {
        for (c in 0 until Chip.MAX_TRACKS) {
            voices[c].env = 0.0
            voices[c].active = false
            voices[c].declick = 0
            voices[c].pendingNote = Chip.EMPTY_NOTE
        }
        // The playhead and filter state are rewound on the render thread that
        // owns them, as Swift does: bump the token before `playing`, so a
        // buffer that sees playback start has already rewound.
        transportRequest = transportRequest + 1
        playing = true
    }

    fun stop() {
        playing = false
        // Release rather than cut: a hard stop mid-waveform is a click.
        for (c in 0 until Chip.MAX_TRACKS) {
            val v = voices[c]
            v.previewSamples = 0
            v.declick = 0
            v.pendingNote = Chip.EMPTY_NOTE
            v.attack = 0
            if (v.active) v.releasing = true
        }
    }

    /** Ends offline playback at the tail: stops the sequencer and releases any
     * voice that would otherwise sustain forever, leaving decaying voices to
     * ring out naturally. */
    fun finish() {
        playing = false
        for (c in 0 until Chip.MAX_TRACKS) {
            val v = voices[c]
            v.previewSamples = 0
            if (paramSustain[c] != 1) continue
            v.declick = 0
            v.pendingNote = Chip.EMPTY_NOTE
            if (v.active) v.releasing = true
        }
    }

    /** Plays a single note immediately, for keyboard previews. A sustaining
     * instrument gets its own fixed lifetime; decaying ones preview as they'll sound. */
    fun audition(track: Int, note: Int) {
        if (track < 0 || track >= Chip.MAX_TRACKS || note < 0 || note > 127) return
        trigger(track, note)
        val v = voices[track]
        v.sourcePattern = -1
        v.sourceStep = -1
        val preview = if (paramSustain[track] == 1) (sampleRate * PREVIEW_SECONDS).toInt() else 0
        // A retrigger defers the note past its de-click fade, so the preview
        // lifetime has to wait with it.
        if (v.declick > 0) v.pendingPreview = preview else v.previewSamples = preview
    }

    // MARK: Render thread

    /** Starts a note on a voice that is already at silence. */
    private fun begin(v: VoiceState, kind: Int, note: Int) {
        v.baseFreq = noteFrequency[note] // NoteName.frequency(note); note is 0..127
        v.inc = v.baseFreq / sampleRate
        v.env = 0.0
        v.attack = attackSamples
        v.attackInc = 1.0 / attackSamples.toDouble()
        v.active = true
        v.arpIndex = 0
        v.arpCounter = 0
        v.releasing = false
        v.declick = 0
        v.pendingNote = Chip.EMPTY_NOTE
        v.previewSamples = v.pendingPreview
        v.pendingPreview = 0
        // Noise keeps its shift register running; retriggering it sounds worse.
        if (kind != NOISE) v.phase = 0.0
        if (v.lfsr == 0) v.lfsr = 1
    }

    private fun trigger(track: Int, note: Int) {
        val v = voices[track]
        if (v.active && v.env > 0.002) {
            // Still ringing: fade it out first and start the new note from the
            // far side of the fade.
            v.pendingNote = note
            v.pendingPreview = 0
            v.declick = declickSamples
            v.declickDec = v.env / declickSamples.toDouble()
            v.attack = 0
            v.releasing = false
        } else {
            v.pendingPreview = 0
            begin(v, paramKind[track], note)
        }
    }

    private fun triggerStep(pat: Int, step: Int, tracks: Int) {
        for (c in 0 until tracks) {
            val note = pattern[cell(pat, c, step)].toInt()
            if (note == Chip.NOTE_OFF) {
                val v = voices[c]
                if (v.active) v.releasing = true
                v.declick = 0
                v.pendingNote = Chip.EMPTY_NOTE
            } else if (note >= 0) {
                trigger(c, note)
                // Recorded here rather than in `begin`: a retrigger defers the
                // note past its fade, and the cell is known now.
                voices[c].sourcePattern = pat
                voices[c].sourceStep = step
            }
        }
    }

    /** Produces one sample for a voice, advancing its oscillator state. */
    private fun voiceSample(c: Int): Double {
        val v = voices[c]
        // A voice mid-attack sits at env 0 and must not be culled here.
        if (!(v.active && (v.env > 0.0001 || v.attack > 0 || v.declick > 0))) {
            if (v.active) {
                v.active = false
                v.env = 0.0
            }
            return 0.0
        }
        // One snapshot of the params per sample, as Swift's `let p = params[c]`:
        // the count must not change between the `> 1` test and the modulo.
        val kind = paramKind[c]
        val duty = paramDuty[c]
        val volume = paramVolume[c]
        val decayCoeff = paramDecayCoeff[c]
        val sustain = paramSustain[c]
        val muted = paramMuted[c]
        val arpCount = paramArpCount[c]

        // Arpeggio: step through the offsets at ~50 Hz for the "fake chord" trill.
        // The first offset is not applied until the first wrap.
        if (arpCount > 1) {
            v.arpCounter += 1
            if (v.arpCounter.toDouble() >= sampleRate / 50.0) {
                v.arpCounter = 0
                v.arpIndex = (v.arpIndex + 1) % arpCount
                val semis = paramArp[c * 4 + v.arpIndex]
                // pow(2, semis / 12), from the table when normalized (always,
                // in the app); a raw out-of-range offset still gets the formula.
                val ratio = if (semis >= -Instrument.MAX_ARPEGGIO_SEMITONES && semis <= Instrument.MAX_ARPEGGIO_SEMITONES) {
                    arpRatio[semis + Instrument.MAX_ARPEGGIO_SEMITONES]
                } else {
                    StrictMath.pow(2.0, semis.toDouble() / 12.0)
                }
                v.inc = (v.baseFreq * ratio) / sampleRate
            }
        }

        var out: Double
        when (kind) {
            TRIANGLE -> {
                v.phase += v.inc
                if (v.phase >= 1) v.phase -= 1
                // 16 quantization steps per half cycle, like the NES triangle channel.
                val tri = if (v.phase < 0.5) v.phase * 4.0 - 1.0 else 3.0 - v.phase * 4.0
                out = StrictMath.floor(tri * 8.0) / 8.0
            }
            NOISE -> {
                // Clock a 15-bit LFSR at a multiple of the note frequency so the
                // noise is pitched rather than a flat hiss. Taps at bits 0 and 1,
                // feedback into bit 14; unsigned in an Int, so no sign extension.
                v.noisePhase += v.inc * 8.0
                while (v.noisePhase >= 1) {
                    v.noisePhase -= 1
                    val lfsr = v.lfsr
                    val bit = (lfsr xor (lfsr ushr 1)) and 1
                    v.lfsr = ((lfsr ushr 1) or (bit shl 14)) and 0xFFFF
                    v.noiseLevel = if ((v.lfsr and 1) == 1) 1.0 else -1.0
                }
                out = v.noiseLevel
            }
            else -> { // PULSE1, PULSE2, and anything unknown (Swift's `?? .pulse1`)
                v.phase += v.inc
                if (v.phase >= 1) v.phase -= 1
                out = if (v.phase < duty) 1.0 else -1.0
            }
        }

        if (v.previewSamples > 0) {
            v.previewSamples -= 1
            if (v.previewSamples == 0) v.releasing = true
        }

        // Envelope. The order matters: a pending retrigger owns the voice until
        // its fade completes, and the note that follows starts in attack.
        if (v.declick > 0) {
            v.declick -= 1
            v.env = swiftMax(0.0, v.env - v.declickDec)
            if (v.declick == 0) {
                val note = v.pendingNote
                if (note >= 0) {
                    begin(v, kind, note)
                } else {
                    v.env = 0.0
                    v.active = false
                }
            }
        } else if (v.attack > 0) {
            v.attack -= 1
            v.env = swiftMin(1.0, v.env + v.attackInc)
        } else if (v.releasing) {
            v.env *= releaseCoeff
        } else if (sustain == 0) {
            v.env *= decayCoeff
        }

        out *= v.env * volume
        if (muted == 1) out = 0.0
        return out
    }

    /** Renders [frames] mono samples into [out] starting at [offset]. Used by
     * both the live write loop and the offline WAV exporter. Allocates nothing. */
    fun render(frames: Int, out: FloatArray, offset: Int = 0) {
        val sps = Chip.samplesPerStep(tempo, sampleRate)
        val patterns = minOf(maxOf(patternCount, 1), Chip.MAX_PATTERNS)
        val links = minOf(maxOf(chainCount, 1), Chip.MAX_CHAIN)
        val tracks = minOf(maxOf(trackCount, 1), Chip.MAX_TRACKS)
        // Four tracks keep the level they always had; beyond that the mix is
        // pulled down so eight voices at once don't ride the soft clipper.
        val gain = 0.32 * StrictMath.sqrt(4.0 / maxOf(tracks, 4).toDouble())

        // Pick up anything the main thread asked to cut since the last buffer.
        for (c in 0 until tracks) {
            val token = paramReleaseToken[c]
            val v = voices[c]
            if (token == v.releaseAck) continue
            v.releaseAck = token
            if (!v.active) continue
            v.releasing = true
            v.previewSamples = 0
            v.declick = 0
            v.pendingNote = Chip.EMPTY_NOTE
        }

        // A `start()` since the last buffer rewinds the transport here, before
        // the sample loop, so the first step lands on frame 0.
        val request = transportRequest
        if (request != transportAck) {
            transportAck = request
            chainPos = 0
            currentPattern = if (songMode) chain[0] else focusPattern
            currentStep = 0
            sampleCounter = 0
            lpState = 0.0
            dcX = 0.0
            dcY = 0.0
        }

        for (i in 0 until frames) {
            if (playing) {
                // Read once: the main thread may write these mid-sample, and a
                // value checked must be the value used as an index.
                var pat = currentPattern
                if (pat >= patterns || pat < 0) {
                    pat = 0
                    currentPattern = 0
                }
                val len = minOf(maxOf(patternLengths[pat], 1), Chip.MAX_STEPS)
                // The edited pattern can shrink under the playhead, and a mode
                // switch can move it to a shorter pattern mid-bar.
                var step = currentStep
                if (step >= len || step < 0) {
                    step = 0
                    currentStep = 0
                }

                if (sampleCounter <= 0) {
                    triggerStep(pat, step, tracks)
                    sampleCounter = sps
                }
                sampleCounter -= 1
                if (sampleCounter <= 0) {
                    step += 1
                    if (step >= len) {
                        step = 0
                        if (songMode) {
                            val pos = (chainPos + 1) % links
                            chainPos = pos
                            currentPattern = minOf(chain[if (pos < 0) 0 else pos], patterns - 1)
                        } else {
                            currentPattern = minOf(focusPattern, patterns - 1)
                        }
                    }
                    currentStep = step
                }
            }

            var mix = 0.0
            for (c in 0 until tracks) mix += voiceSample(c)
            mix *= gain * masterVolume

            // The DC blocker feeds back into itself, so a single non-finite
            // sample would latch and silence the app; this is the backstop.
            if (!mix.isFinite()) {
                mix = 0.0
                lpState = 0.0
                dcX = 0.0
                dcY = 0.0
            }

            // Gentle lowpass, DC blocker, then a soft clip so stacked channels
            // never crack.
            lpState += (mix - lpState) * 0.55
            dcY = lpState - dcX + 0.9985 * dcY
            dcX = lpState
            out[offset + i] = StrictMath.tanh(dcY * 1.2).toFloat()
        }
    }

    private companion object {
        /** How long a sustaining instrument rings when auditioned from the keyboard. */
        const val PREVIEW_SECONDS = 0.9
        val NOISE = ChannelKind.NOISE.rawValue
        val TRIANGLE = ChannelKind.TRIANGLE.rawValue

        /** A note value as a grid cell: rest, note-off or MIDI 0..127; anything
         * else is a rest (Swift's `Int8` storage can't hold it at all). */
        fun toCell(note: Int): Byte =
            if (note >= Chip.NOTE_OFF && note <= 127) note.toByte() else Chip.EMPTY_NOTE.toByte()

        /** Swift's `max(x, y)`: `y >= x ? y : x` (NaN and signed-zero behavior included). */
        fun swiftMax(x: Double, y: Double): Double = if (y >= x) y else x

        /** Swift's `min(x, y)`: `y < x ? y : x`. */
        fun swiftMin(x: Double, y: Double): Double = if (y < x) y else x
    }
}

/**
 * Renders an arbitrarily large request through one fixed scratch buffer, the
 * way `AudioEngine.fill` does on iOS: the output can ask for more frames than
 * the scratch holds, so this loops until the whole request is filled rather
 * than dropping the excess (which would lose audio and let the sequencer clock
 * drift). Allocates nothing after construction; Phase 4's AudioTrack write
 * loop drives it.
 */
class RenderSlicer(private val core: ChipCore, scratchLength: Int = SCRATCH_LENGTH) {
    private val scratch = FloatArray(scratchLength)

    fun fill(out: FloatArray, frames: Int, offset: Int = 0) {
        var done = 0
        while (done < frames) {
            val n = minOf(frames - done, scratch.size)
            core.render(n, scratch, 0)
            System.arraycopy(scratch, 0, out, offset + done, n)
            done += n
        }
    }

    companion object {
        const val SCRATCH_LENGTH = 4096
    }
}
