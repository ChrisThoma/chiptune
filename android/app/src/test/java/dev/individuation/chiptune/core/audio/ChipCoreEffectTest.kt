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

/** Twin of the Swift effect engine tests (`ChipCoreVoiceTests` style): each
 * pitch effect measured off the rendered audio by zero-crossing frequency. */
class ChipCoreEffectTest {

    private val sampleRate = RenderHarness.SAMPLE_RATE
    private val tempo = 120.0
    /** Samples in one step at [tempo]. */
    private val step = Chip.samplesPerStep(tempo, sampleRate)
    private val attack = maxOf((sampleRate * 0.0012).toInt(), 8)

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

    // MARK: Slides

    @Test fun slideUpDoublesThePitchOverOneStep() {
        val base = NoteName.frequency(60)
        val samples = render(fxSong(60, NoteEffect.SLIDE_UP), 2.0)
        assertRatio("at the step end", 2.0, f(samples, step - 300, step + 300) / base, 0.04)
        // Rising all the way: each later window is higher.
        val windows = (0 until 6).map { k -> f(samples, 200 + k * 800, 200 + k * 800 + 600) }
        for (k in 1 until windows.size) assertTrue("slide up fell at window $k: $windows", windows[k] > windows[k - 1])
    }

    @Test fun slideUpFollowsTwelveSemitonesPerStep() {
        val base = NoteName.frequency(60)
        val samples = render(fxSong(60, NoteEffect.SLIDE_UP), 1.5)
        for (center in listOf(1000, 2000, 3000, 4000, 5000, 7000)) {
            val semis = 12.0 * (center - attack).toDouble() / step.toDouble()
            val expected = Math.pow(2.0, semis / 12.0)
            assertRatio("at sample $center", expected, f(samples, center - 250, center + 250) / base, 0.02)
        }
    }

    @Test fun slideUpStopsAtTwentyFourSemitones() {
        val base = NoteName.frequency(48)
        val samples = render(fxSong(48, NoteEffect.SLIDE_UP), 4.0)
        assertRatio("after the cap", 4.0, f(samples, 3 * step, 4 * step) / base, 0.01)
    }

    @Test fun slideDownHalvesThePitchOverOneStepAndStopsAtTwentyFour() {
        val base = NoteName.frequency(72)
        val samples = render(fxSong(72, NoteEffect.SLIDE_DOWN), 4.0)
        assertRatio("at the step end", 0.5, f(samples, step - 400, step + 400) / base, 0.04)
        assertRatio("after the cap", 0.25, f(samples, 3 * step, 4 * step) / base, 0.01)
    }

    @Test fun aSlideIsClampedToTheNoteRange() {
        val samples = render(fxSong(127, NoteEffect.SLIDE_UP), 3.5)
        assertTrue(samples.all { it.isFinite() })
        assertRatio("clamped at MIDI 127", NoteName.frequency(127) / 1.0,
            f(samples, 2 * step, 2 * step + 4000), 0.02)
    }

    @Test fun slideDownOnNoiseStillSounds() {
        val samples = render(fxSong(60, NoteEffect.SLIDE_DOWN, kind = ChannelKind.NOISE), 3.0)
        assertTrue(samples.all { it.isFinite() })
        assertTrue(RenderHarness.rms(samples, 2 * step, 3 * step) > 0.01)
        // A falling noise clock changes the sound; it isn't the plain render.
        assertTrue(!sameBits(samples, render(fxSong(60, NoteEffect.NONE, kind = ChannelKind.NOISE), 3.0)))
    }

    // MARK: Vibrato

    @Test fun vibratoWobblesAroundThePitch() {
        val base = NoteName.frequency(69)
        val samples = render(fxSong(69, NoteEffect.VIBRATO), 8.0) // one second
        // Eight cycles (~18 ms) per reading: smooths the pulse's edge jitter,
        // and a tenth of a 6 Hz wobble barely dents its peaks.
        val cycles = PitchMeter.cycles(samples, 2000, samples.size, span = 8)
        val semis = cycles.map { PitchMeter.semitones(it.second / base) }
        val mean = cycles.sumOf { it.second } / cycles.size
        assertRatio("mean pitch", 1.0, mean / base, 0.01)
        assertEquals("highest", 0.4, semis.max(), 0.08)
        assertEquals("lowest", -0.4, semis.min(), 0.08)
        // About 6 Hz: some 5 wobbles in the ~0.95 s measured, two sign changes each.
        val signChanges = (1 until semis.size).count { (semis[it] >= 0) != (semis[it - 1] >= 0) }
        assertTrue("vibrato rate off: $signChanges sign changes", signChanges in 9..13)
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
        val cycles = PitchMeter.cycles(samples, at, at + step / 2).map { it.second }
        assertTrue("glide started away from the sounding pitch: ${cycles.first()}", abs(cycles.first() / from - 1) < 0.05)
        for (i in 1 until cycles.size) {
            assertTrue("glide went back down at cycle $i: $cycles", cycles[i] >= cycles[i - 1] * 0.997)
        }
        assertRatio("landed", 1.0, f(samples, at + step / 2 + 100, at + step) / to, 0.005)
    }

    @Test fun glideOnASilentVoiceIsAPlainNote() {
        val plain = render(fxSong(64, NoteEffect.NONE), 3.0)
        val glide = render(fxSong(64, NoteEffect.GLIDE), 3.0)
        assertTrue("a glide with nothing to glide from differs from a plain note", sameBits(plain, glide))
    }

    // MARK: Bend in

    @Test fun bendInStartsTwoSemitonesFlatAndReachesPitchInAQuarterStep() {
        val base = NoteName.frequency(69)
        val samples = render(fxSong(69, NoteEffect.BEND_IN), 2.0)
        val quarter = step / 4.0
        val early = PitchMeter.cycles(samples, 100, (quarter - 50).toInt())
        assertTrue(early.size > 5)
        for ((center, freq) in early) {
            val expected = -2.0 * (1.0 - center / quarter)
            assertEquals("at sample $center", expected, PitchMeter.semitones(freq / base), 0.15)
        }
        assertTrue("first cycle is not near 2 semitones flat",
            PitchMeter.semitones(early.first().second / base) < -1.7)
        assertRatio("on pitch after a quarter step", 1.0, f(samples, (quarter + 200).toInt(), step) / base, 0.003)
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
        val samples = render(fxSong(48, NoteEffect.SLIDE_UP, arpeggio = listOf(0, 12)), 4.0)
        val freqs = PitchMeter.cycles(samples, 3 * step, 4 * step).map { it.second / base }
        val low = freqs.count { abs(it / 4.0 - 1) < 0.03 }
        val high = freqs.count { abs(it / 8.0 - 1) < 0.03 }
        assertTrue("arp root not slid up two octaves ($low of ${freqs.size})", low > freqs.size / 5)
        assertTrue("arp +12 not slid up two octaves ($high of ${freqs.size})", high > freqs.size / 5)
        assertTrue("cycles off both arp notes", low + high > freqs.size * 0.8)
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
        val samples = RenderHarness.renderMono(core, 2 * step)
        assertRatio("audition slid", 2.0, f(samples, step - 300, step + 300) / NoteName.frequency(60), 0.04)
    }
}
