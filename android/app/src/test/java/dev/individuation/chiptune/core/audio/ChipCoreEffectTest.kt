package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.NoteEffect
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.log2

/** Twin of the Swift effect engine tests (`ChipCoreVoiceTests` style): each
 * pitch effect measured off the rendered audio by zero-crossing frequency. */
class ChipCoreEffectTest {

    private val sampleRate = RenderHarness.SAMPLE_RATE
    private val tempo = 120.0
    /** Samples in one step at [tempo]. */
    private val step = Chip.samplesPerStep(tempo, sampleRate)

    /** A held 50% pulse with [note] on step 0 carrying [effect]. */
    private fun fxSong(
        note: Int,
        effect: NoteEffect,
        kind: ChannelKind = ChannelKind.PULSE1,
        arpeggio: List<Int> = emptyList(),
    ): Song = TestSongs.singleNote(kind, note, tempo = tempo, sustain = true, duty = 2, arpeggio = arpeggio)
        .withPattern(0) { it.withEffect(0, 0, effect) }

    private fun render(song: Song, steps: Double): FloatArray = RenderHarness.render(song, steps * step / sampleRate)

    private fun f(samples: FloatArray, from: Int, until: Int) = PitchMeter.frequency(samples, from, until)

    private fun assertRatio(message: String, expected: Double, actual: Double, tolerance: Double) {
        assertTrue("$message: expected ratio $expected, got $actual", abs(actual / expected - 1.0) < tolerance)
    }

    // MARK: Probes

    /** A fresh core playing [song] from the top. */
    private fun started(song: Song): ChipCore {
        val core = ChipCore(sampleRate)
        core.load(song.normalized())
        core.setSongMode(false)
        core.start()
        return core
    }

    /** The oscillator frequency of track 0 for each of the next [frames]
     * samples, rendered one at a time: `trace[i]` is what sample i used. */
    private fun trace(core: ChipCore, frames: Int): DoubleArray {
        val buf = FloatArray(1)
        return DoubleArray(frames) {
            core.render(1, buf)
            core.voiceFrequency(0)
        }
    }

    private fun trace(song: Song, frames: Int): DoubleArray = trace(started(song), frames)

    /** The first sample of 60 Hz frame [frame]. */
    private fun tick(frame: Int): Int = frame * TICK

    /** The spec's slide, in semitones from the written note, at [frame]: the
     * NES period moves 16 units a frame up or 64 down and holds at 8 / 2047. */
    private fun slideSemis(note: Int, kind: ChannelKind, up: Boolean, frame: Int): Double {
        val k = if (kind == ChannelKind.TRIANGLE) 32.0 else 16.0
        val p0 = CPU / (k * NoteName.frequency(note))
        val p = if (up) maxOf(p0 - 16.0 * frame, minOf(p0, 8.0)) else minOf(p0 + 64.0 * frame, maxOf(p0, 2047.0))
        return 12.0 * log2(p0 / p)
    }

    // MARK: Slides

    @Test fun slideDownOnTriangleFollowsThePeriodAndIgnoresTempo() {
        val p0 = CPU / (32.0 * NoteName.frequency(48))
        val expected = 12.0 * log2(p0 / (p0 + 384.0))
        val at = tick(6) + 300
        val readings = listOf(80.0, 180.0).map { bpm ->
            val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 48, tempo = bpm, sustain = true)
                .withPattern(0) { it.withEffect(0, 0, NoteEffect.SLIDE_DOWN) }
            trace(song, at + 1)[at]
        }
        for (f in readings) {
            assertEquals("six frames in", expected, PitchMeter.semitones(f / NoteName.frequency(48)), 0.1)
        }
        assertEquals("80 and 180 BPM slide alike", readings[0], readings[1], 0.0)
    }

    @Test fun slidePitchHoldsWithinATickAndMovesAtTheBoundary() {
        val freqs = trace(fxSong(60, NoteEffect.SLIDE_UP), tick(21))
        for (frame in 0 until 20) {
            val held = freqs[tick(frame)]
            for (i in tick(frame) until tick(frame + 1)) {
                assertEquals("frame $frame moved at sample $i", held, freqs[i], 0.0)
            }
            assertTrue("no step at frame ${frame + 1}", freqs[tick(frame + 1)] > held)
            assertEquals("frame $frame off the period model", slideSemis(60, ChannelKind.PULSE1, true, frame),
                PitchMeter.semitones(held / NoteName.frequency(60)), 1e-9)
        }
    }

    /** The probe is what sounds: a held frame measured off the audio. */
    @Test fun slideUpSoundsAtThePeriodPitch() {
        val samples = render(fxSong(60, NoteEffect.SLIDE_UP), 2.0)
        for (frame in listOf(2, 6, 10)) {
            val expected = Math.pow(2.0, slideSemis(60, ChannelKind.PULSE1, true, frame) / 12.0)
            assertRatio("frame $frame", expected,
                f(samples, tick(frame) + 40, tick(frame + 1) - 40) / NoteName.frequency(60), 0.01)
        }
    }

    @Test fun slidesHoldAtThePeriodLimits() {
        // Triangle 48 (P0 ~428) reaches 2047 after ~26 frames of +64.
        val tri = { note: Int, fx: NoteEffect ->
            TestSongs.singleNote(ChannelKind.TRIANGLE, note, tempo = tempo, sustain = true)
                .withPattern(0) { it.withEffect(0, 0, fx) }
        }
        val down = trace(tri(48, NoteEffect.SLIDE_DOWN), tick(80) + 1)
        for (frame in listOf(30, 50, 80)) {
            assertEquals("held at period 2047, frame $frame", CPU / (32.0 * 2047.0), down[tick(frame)], 1e-6)
        }
        // Triangle 60 (P0 ~214) reaches 8 on frame 14 (214 - 16*14 <= 8),
        // where it sits while the voice releases.
        val up = trace(tri(60, NoteEffect.SLIDE_UP), tick(15) + 1)
        assertEquals("at period 8, frame 14", CPU / (32.0 * 8.0), up[tick(14)], 1e-6)
    }

    /** Envelope of track 0 after each of the next [frames] samples. */
    private fun envelopes(core: ChipCore, frames: Int): DoubleArray {
        val buf = FloatArray(1)
        return DoubleArray(frames) {
            core.render(1, buf)
            core.voiceEnvelope(0)
        }
    }

    @Test fun slideUpReachingPeriodEightReleasesTheVoice() {
        // Pulse 60: P0 ~427.6, so 427.6 - 16n <= 8 first at n = 27.
        val p0 = CPU / (16.0 * NoteName.frequency(60))
        val muteFrame = ceil((p0 - 8.0) / 16.0).toInt()
        assertEquals(27, muteFrame)
        val core = started(fxSong(60, NoteEffect.SLIDE_UP))
        val env = envelopes(core, tick(muteFrame) + 1323 + 1)
        assertEquals("sustained up to the tick", 1.0, env[tick(muteFrame) - 1], 1e-9)
        assertTrue("released at the tick", env[tick(muteFrame)] < 1.0)
        assertTrue("not silent 30 ms later: ${env.last()}", env.last() < 0.001)
        val after = RenderHarness.renderMono(core, 2000)
        assertTrue("still sounding after the mute", RenderHarness.peak(after) < 0.01)
    }

    @Test fun slideUpOnANoteAlreadyBelowPeriodEightDoesNotMute() {
        // Triangle 120: P0 ~4.3, already under 8.
        val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 120, tempo = tempo, sustain = true)
            .withPattern(0) { it.withEffect(0, 0, NoteEffect.SLIDE_UP) }
        val core = started(song)
        val env = envelopes(core, 2 * step)
        assertEquals("muted a note that started under period 8", 1.0, env.last(), 1e-9)
        assertEquals("moved", NoteName.frequency(120), core.voiceFrequency(0), 1e-9)
    }

    @Test fun slideDownNeverMutes() {
        val core = started(fxSong(72, NoteEffect.SLIDE_DOWN))
        assertEquals(1.0, envelopes(core, tick(80)).last(), 1e-9)
    }

    /** No 24-semitone cap any more: a long slide down keeps going to 2047. */
    @Test fun slideDownPassesTheOldTwoOctaveCap() {
        val freqs = trace(fxSong(72, NoteEffect.SLIDE_DOWN), tick(40) + 1)
        val semis = PitchMeter.semitones(freqs[tick(40)] / NoteName.frequency(72))
        assertEquals(slideSemis(72, ChannelKind.PULSE1, false, 40), semis, 1e-9)
        assertTrue("slide stopped at $semis", semis < -24.0)
    }

    /** A note whose period is already past the limit in the slide's
     * direction holds where it is instead of jumping to the limit. */
    @Test fun aNoteAlreadyPastThePeriodLimitDoesNotJump() {
        // Pulse MIDI 20: P0 ~4310, past 2047.
        val freqs = trace(fxSong(20, NoteEffect.SLIDE_DOWN), tick(10))
        for (i in freqs.indices) assertEquals("moved at $i", NoteName.frequency(20), freqs[i], 1e-9)
    }

    /** Pulse 127 (P0 ~8.9) slides past period 8 on its first tick and
     * releases; nothing goes non-finite on the way. */
    @Test fun aSlideUpOffTheTopIsFiniteAndReleases() {
        val samples = render(fxSong(127, NoteEffect.SLIDE_UP), 3.5)
        assertTrue(samples.all { it.isFinite() })
        assertTrue(RenderHarness.peak(samples, 2 * step, 3 * step) < 0.01)
    }

    @Test fun slideDownOnNoiseStillSounds() {
        val samples = render(fxSong(60, NoteEffect.SLIDE_DOWN, kind = ChannelKind.NOISE), 3.0)
        assertTrue(samples.all { it.isFinite() })
        assertTrue(RenderHarness.rms(samples, 2 * step, 3 * step) > 0.01)
        // A falling noise clock changes the sound; it isn't the plain render.
        assertTrue(!sameBits(samples, render(fxSong(60, NoteEffect.NONE, kind = ChannelKind.NOISE), 3.0)))
    }

    // MARK: Noise

    /** Every ratio q(c)/q(c0) two table rates can make. */
    private val rateRatios: List<Double> = NOISE_PERIODS.flatMap { a -> NOISE_PERIODS.map { b -> b / a } }

    private fun isRateRatio(r: Double) = rateRatios.any { abs(r / it - 1.0) < 1e-9 }

    @Test fun noiseEffectsStartOnThePlainPitchAndMoveInRateRatios() {
        val base = NoteName.frequency(60)
        for (fx in listOf(NoteEffect.SLIDE_DOWN, NoteEffect.SLIDE_UP, NoteEffect.VIBRATO, NoteEffect.BEND_IN)) {
            val freqs = trace(fxSong(60, fx, kind = ChannelKind.NOISE), 3 * step)
            // Offset 0 sounds exactly as the plain note: frame 0 of a slide or
            // vibrato, and a bend in once it lands on frame 3.
            val plainFrom = if (fx == NoteEffect.BEND_IN) tick(3) else 0
            for (i in plainFrom until plainFrom + TICK) assertEquals("$fx plain at sample $i", base, freqs[i], 0.0)
            val seen = HashSet<Double>()
            for ((i, f) in freqs.withIndex()) {
                assertTrue("$fx sample $i: ratio ${f / base} is not q(c)/q(c0)", isRateRatio(f / base))
                seen.add(f)
            }
            if (fx == NoteEffect.SLIDE_DOWN) assertTrue("slide down never moved: $seen", seen.size >= 3)
        }
    }

    @Test fun noiseEffectOnAnArpeggioIsRelativeToTheSoundingArpTone() {
        val base = NoteName.frequency(60)
        val freqs = trace(fxSong(60, NoteEffect.SLIDE_DOWN, kind = ChannelKind.NOISE, arpeggio = listOf(0, 12)), 3 * step)
        for ((i, f) in freqs.withIndex()) {
            assertTrue("sample $i: $f is no rate ratio off either arp tone",
                isRateRatio(f / base) || isRateRatio(f / (base * 2.0)))
        }
        // The +12 tone shows up, so the arp still moves the noise.
        assertTrue(freqs.any { it > base * 1.2 })
    }

    @Test fun plainNoiseKeepsItsUnquantizedClock() {
        val freqs = trace(fxSong(60, NoteEffect.NONE, kind = ChannelKind.NOISE), 2 * step)
        for (i in freqs.indices) assertEquals("sample $i", NoteName.frequency(60), freqs[i], 0.0)
    }

    // MARK: Vibrato

    @Test fun vibratoWaitsOneStepThenWobbles() {
        val base = NoteName.frequency(69)
        val freqs = trace(fxSong(69, NoteEffect.VIBRATO), sampleRate.toInt())
        for (i in 0 until step) assertEquals("wobbled during the first step at $i", base, freqs[i], 0.0)
        val semis = (step until freqs.size).map { PitchMeter.semitones(freqs[it] / base) }
        assertEquals("highest", 0.4, semis.max(), 0.03)
        assertEquals("lowest", -0.4, semis.min(), 0.03)
        // Ramps in: the first post-delay frames stay under full depth.
        val firstWobble = (step until step + 3 * TICK).maxOf { abs(PitchMeter.semitones(freqs[it] / base)) }
        assertTrue("no ramp: $firstWobble", firstWobble < 0.4)
        val signChanges = (1 until semis.size).count { (semis[it] > 0) != (semis[it - 1] > 0) && semis[it] != 0.0 }
        assertTrue("vibrato rate off: $signChanges sign changes", signChanges in 8..12)
    }

    @Test fun vibratoWobblesAroundThePitchAfterItsDelay() {
        val base = NoteName.frequency(69)
        val samples = render(fxSong(69, NoteEffect.VIBRATO), 8.0) // one second
        assertRatio("on pitch during the delay", 1.0, f(samples, 1500, step - 100) / base, 0.003)
        val cycles = PitchMeter.cycles(samples, step + 3 * TICK, samples.size, span = 8)
        val semis = cycles.map { PitchMeter.semitones(it.second / base) }
        val mean = cycles.sumOf { it.second } / cycles.size
        assertRatio("mean pitch", 1.0, mean / base, 0.01)
        assertEquals("highest", 0.4, semis.max(), 0.1)
        assertEquals("lowest", -0.4, semis.min(), 0.1)
    }

    // MARK: Glide

    /** 60 on step 0 then 67 on step 2, the second carrying [effect]. */
    private fun twoNotes(effect: NoteEffect): Song = TestSongs.singleNote(ChannelKind.PULSE1, 60, tempo = tempo, sustain = true)
        .withPattern(0) { it.withNote(0, 2, 67).withEffect(0, 2, effect) }

    private fun minWindowLevel(samples: FloatArray, from: Int, until: Int): Double =
        (from until until step 64).minOf { RenderHarness.rms(samples, it, it + 128) }

    @Test fun glideHasNoDeclickDip() {
        val at = 2 * step
        val plain = render(twoNotes(NoteEffect.NONE), 4.0)
        val glide = render(twoNotes(NoteEffect.GLIDE), 4.0)
        val held = RenderHarness.rms(plain, at - 2048, at - 1024)
        assertTrue("precondition: a plain retrigger dips", minWindowLevel(plain, at - 256, at + 512) < held * 0.6)
        assertTrue("glide dipped between the notes", minWindowLevel(glide, at - 256, at + 512) > held * 0.8)
    }

    @Test fun glideSlidesMonotonicallyAndLandsByHalfAStep() {
        val at = 2 * step
        val samples = render(twoNotes(NoteEffect.GLIDE), 4.0)
        val from = NoteName.frequency(60)
        val to = NoteName.frequency(67)
        // Four-cycle spans: the pitch now holds still within each 60 Hz frame,
        // where a single pulse cycle's whole-sample edges jitter by ~0.5%.
        val cycles = PitchMeter.cycles(samples, at, at + step / 2, span = 4).map { it.second }
        assertTrue("glide started away from the sounding pitch: ${cycles.first()}", abs(cycles.first() / from - 1) < 0.05)
        for (i in 1 until cycles.size) {
            assertTrue("glide went back down at cycle $i: $cycles", cycles[i] >= cycles[i - 1] * 0.997)
        }
        // Stepped on 60 Hz ticks: it lands on the first tick at or past half a step.
        val landed = at + ceil(step / 2.0 / TICK).toInt() * TICK
        assertRatio("landed", 1.0, f(samples, landed + 50, at + step) / to, 0.005)
    }

    @Test fun glideFollowsTheSpecFormulaOnTicks() {
        val at = 2 * step
        val freqs = trace(twoNotes(NoteEffect.GLIDE), at + step)
        val from = 12.0 * log2(NoteName.frequency(60) / NoteName.frequency(67))
        for (frame in 0 until 6) {
            val expected = from * maxOf(0.0, 1.0 - frame * TICK.toDouble() / (step * 0.5))
            for (i in at + tick(frame) until at + tick(frame + 1)) {
                assertEquals("frame $frame sample $i", expected,
                    PitchMeter.semitones(freqs[i] / NoteName.frequency(67)), 1e-9)
            }
        }
    }

    /** A held core voice playing [note] from an audition, rendered [frames] in. */
    private fun auditioned(note: Int, frames: Int, arpeggio: List<Int> = emptyList()): ChipCore {
        val core = ChipCore(sampleRate)
        core.load(fxSong(note, NoteEffect.NONE, arpeggio = arpeggio).normalized())
        core.tempo = tempo
        core.audition(0, note)
        RenderHarness.renderMono(core, frames)
        return core
    }

    @Test fun glideOntoAReleasingVoicePlaysPlain() {
        val core = auditioned(60, 4000)
        core.release(0)
        RenderHarness.renderMono(core, 32) // the release lands; the voice still rings
        core.audition(0, 67, NoteEffect.GLIDE)
        val samples = RenderHarness.renderMono(core, step)
        // Swift: no glide out of a release; the plain declick and attack, then 67.
        assertTrue("a glide out of a release kept the voice level (no declick)",
            minWindowLevel(samples, 0, 256) < RenderHarness.rms(samples, 1000, 2000) * 0.6)
        assertRatio("on 67 at once", 1.0, f(samples, 300, 1300) / NoteName.frequency(67), 0.01)
    }

    @Test fun aGlideStartsNoMoreThanTwoOctavesAway() {
        for ((from, expected) in listOf(20 to -24.0, 100 to 24.0)) {
            val song = TestSongs.singleNote(ChannelKind.PULSE1, from, tempo = tempo, sustain = true)
                .withPattern(0) { it.withNote(0, 1, 60).withEffect(0, 1, NoteEffect.GLIDE) }
            val freqs = trace(song, step + 1)
            assertEquals("glide from $from", expected, PitchMeter.semitones(freqs[step] / NoteName.frequency(60)), 1e-9)
        }
    }

    @Test fun glideOnAnArpeggioStartsFromTheOldBasePitchNotTheChordTone() {
        // 48 with an octave arpeggio, past its first wrap: 60's pitch is sounding.
        val core = auditioned(48, 882 + 200, arpeggio = listOf(0, 12))
        assertEquals("precondition: the +12 tone sounds", NoteName.frequency(60), core.voiceFrequency(0), 1e-9)
        core.audition(0, 60, NoteEffect.GLIDE)
        val buf = FloatArray(1)
        core.render(1, buf)
        assertEquals("glide started from 48", NoteName.frequency(48), core.voiceFrequency(0), 1e-9)
        val samples = RenderHarness.renderMono(core, 700)
        assertRatio("sounding 48 in the first frame", 1.0,
            f(samples, 20, 700) / NoteName.frequency(48), 0.01)
    }

    @Test fun glideStartsFromTheOldNotesEffectPitch() {
        // 60 sliding up, then a glide to 67: it starts where the slide had got to.
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 60, tempo = tempo, sustain = true)
            .withPattern(0) { it.withEffect(0, 0, NoteEffect.SLIDE_UP).withNote(0, 1, 67).withEffect(0, 1, NoteEffect.GLIDE) }
        val freqs = trace(song, step + 1)
        assertEquals("glide began at the slid pitch", freqs[step - 1], freqs[step], 1e-6)
    }

    /** Vibrato's one-step delay is measured in the step length its note
     * started with, even if the tempo changes under it. */
    @Test fun anEffectsStepLengthIsTakenWhenItsNoteStarts() {
        val core = started(fxSong(69, NoteEffect.VIBRATO))
        val head = trace(core, 100)
        core.tempo = tempo / 2 // longer steps from here on; the note keeps its own
        val freqs = head + trace(core, 2 * step)
        val firstMove = freqs.indexOfFirst { it != NoteName.frequency(69) }
        // The first tick at or past one 120 BPM step, not two.
        assertEquals(ceil(step.toDouble() / TICK).toInt() * TICK, firstMove)
    }

    @Test fun glideOnASilentVoiceIsAPlainNote() {
        val plain = render(fxSong(64, NoteEffect.NONE), 3.0)
        val glide = render(fxSong(64, NoteEffect.GLIDE), 3.0)
        assertTrue("a glide with nothing to glide from differs from a plain note", sameBits(plain, glide))
    }

    // MARK: Bend in

    @Test fun bendInReachesPitchAfterThreeFramesAtAnyTempo() {
        val base = NoteName.frequency(69)
        for (bpm in listOf(80.0, 180.0)) {
            val song = TestSongs.singleNote(ChannelKind.PULSE1, 69, tempo = bpm, sustain = true, duty = 2)
                .withPattern(0) { it.withEffect(0, 0, NoteEffect.BEND_IN) }
            val freqs = trace(song, tick(6))
            val expected = listOf(-2.0, -4.0 / 3.0, -2.0 / 3.0, 0.0, 0.0, 0.0)
            for (frame in 0 until 6) {
                for (i in tick(frame) until tick(frame + 1)) {
                    assertEquals("$bpm BPM frame $frame", expected[frame],
                        PitchMeter.semitones(freqs[i] / base), 1e-9)
                }
            }
            assertEquals("$bpm BPM on pitch exactly", base, freqs[tick(3)], 0.0)
        }
        val samples = render(fxSong(69, NoteEffect.BEND_IN), 2.0)
        assertRatio("sounds two semitones flat first", Math.pow(2.0, -2.0 / 12.0),
            f(samples, 30, TICK - 30) / base, 0.01)
        assertRatio("on pitch after three frames", 1.0, f(samples, tick(3) + 50, step) / base, 0.003)
    }

    // MARK: Plain notes and arpeggios

    @Test fun anExplicitlyEmptyEffectGridRendersBitIdentically() {
        val song = TestSongs.golden()
        val padded = song.copy(patterns = song.patterns.map { p ->
            Pattern(p.id, p.name, p.length, p.rows, effects = p.rows.map { List(Chip.MAX_STEPS) { NoteEffect.NONE } })
        })
        assertTrue(sameBits(RenderHarness.render(song, 2.0), RenderHarness.render(padded, 2.0)))
    }

    @Test fun anEffectSetAndClearedLeavesTheRenderUnchanged() {
        val song = TestSongs.golden().normalized()
        val core = ChipCore(sampleRate)
        core.load(song)
        core.setEffect(0, 0, 0, NoteEffect.VIBRATO)
        core.setEffect(0, 0, 0, NoteEffect.NONE)
        core.start()
        val touched = RenderHarness.renderMono(core, 88200)
        assertTrue(sameBits(RenderHarness.render(song, 2.0), touched))
    }

    @Test fun theEffectStacksOnEveryArpeggioNote() {
        val base = NoteName.frequency(48)
        val freqs = trace(fxSong(48, NoteEffect.SLIDE_DOWN, arpeggio = listOf(0, 12)), 4 * step)
        var low = 0
        var high = 0
        for ((i, f) in freqs.withIndex()) {
            val slide = slideSemis(48, ChannelKind.PULSE1, false, i / TICK)
            val semis = PitchMeter.semitones(f / base)
            when {
                abs(semis - slide) < 1e-9 -> low += 1
                abs(semis - (slide + 12.0)) < 1e-9 -> high += 1
                else -> throw AssertionError("sample $i: $semis is neither $slide nor ${slide + 12}")
            }
        }
        assertTrue("arp root never sounded slid ($low)", low > freqs.size / 5)
        assertTrue("arp +12 never sounded slid ($high)", high > freqs.size / 5)
    }

    // MARK: Main-thread API

    @Test fun loadFillsTheEffectBufferAndSetEffectWritesIt() {
        val core = ChipCore(sampleRate)
        core.load(fxSong(60, NoteEffect.GLIDE).normalized())
        assertEquals(NoteEffect.GLIDE, core.effect(0, 0, 0))
        assertEquals(NoteEffect.NONE, core.effect(0, 0, 1))
        core.setEffect(0, 0, 5, NoteEffect.BEND_IN)
        assertEquals(NoteEffect.BEND_IN, core.effect(0, 0, 5))
        // Out of range: ignored, no throw.
        core.setEffect(-1, 0, 0, NoteEffect.VIBRATO)
        core.setEffect(0, Chip.MAX_TRACKS, 0, NoteEffect.VIBRATO)
        core.setEffect(0, 0, Chip.MAX_STEPS, NoteEffect.VIBRATO)
        assertEquals(NoteEffect.NONE, core.effect(-1, 0, 0))
        // Reloading a song without effects clears them.
        core.load(fxSong(60, NoteEffect.NONE).normalized())
        assertEquals(NoteEffect.NONE, core.effect(0, 0, 0))
        assertEquals(NoteEffect.NONE, core.effect(0, 0, 5))
    }

    @Test fun anAuditionPlaysItsEffect() {
        val core = ChipCore(sampleRate)
        core.load(fxSong(60, NoteEffect.NONE).normalized())
        core.tempo = tempo
        core.audition(0, 60, NoteEffect.SLIDE_UP)
        val freqs = trace(core, tick(10) + 1)
        assertEquals("audition slid", slideSemis(60, ChannelKind.PULSE1, true, 10),
            PitchMeter.semitones(freqs[tick(10)] / NoteName.frequency(60)), 1e-9)
    }

    private companion object {
        const val CPU = 1789773.0
        /** Samples in one 60 Hz frame at 44.1 kHz. */
        const val TICK = 735
        val NOISE_PERIODS = listOf(4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068)
            .map { it.toDouble() }
    }
}
