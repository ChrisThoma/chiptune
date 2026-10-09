package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.model.swiftRounded
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ChipCoreVoiceTests.swift`: what each voice is supposed to sound
 * like, measured off the rendered audio. Levels are asserted as ratios. */
class ChipCoreVoiceTest {

    private val sampleRate = RenderHarness.SAMPLE_RATE
    /** Skip the attack ramp and let the filters settle before measuring. */
    private val settled = 4410

    private fun render(song: dev.individuation.chiptune.core.model.Song, seconds: Double) =
        RenderHarness.render(song, seconds)

    // MARK: Pitch

    @Test fun pulseAndTriangleTrackTheWrittenNote() {
        for (kind in listOf(ChannelKind.PULSE1, ChannelKind.PULSE2, ChannelKind.TRIANGLE)) {
            for (note in listOf(48, 60, 69, 79)) {
                val samples = render(TestSongs.singleNote(kind, note), 0.5)
                val dominant = RenderHarness.dominantFrequency(samples, settled, samples.size,
                    RenderHarness.semitoneLadder(note))
                assertEquals("${kind.fullName} playing MIDI $note is not the loudest at its own pitch",
                    NoteName.frequency(note), dominant ?: 0.0, 0.001)
            }
        }
    }

    @Test fun noiseIsBroadbandRatherThanPitched() {
        for (note in listOf(48, 60, 72)) {
            val ladder = RenderHarness.semitoneLadder(note)
            val noise = render(TestSongs.singleNote(ChannelKind.NOISE, note), 0.5)
            val pulse = render(TestSongs.singleNote(ChannelKind.PULSE1, note), 0.5)
            val noisePeak = RenderHarness.spectralPeakiness(noise, settled, noise.size, ladder)
            val pulsePeak = RenderHarness.spectralPeakiness(pulse, settled, pulse.size, ladder)
            assertTrue("the noise channel has a dominant pitch it shouldn't ($noisePeak)", noisePeak < 6)
            assertTrue("a pulse must be far more sharply pitched than noise ($pulsePeak vs $noisePeak)",
                pulsePeak > noisePeak * 3)
        }
    }

    @Test fun noiseIsDeterministic() {
        val song = TestSongs.singleNote(ChannelKind.NOISE, 60)
        val a = render(song, 0.25)
        assertTrue("the noise render is silent, so determinism means nothing", RenderHarness.rms(a) > 0.01)
        assertTrue("two renders of the same noise song differ", sameBits(a, render(song, 0.25)))
    }

    // MARK: Waveform shape

    @Test fun aWildDutyIndexRendersAsTheLastDuty() {
        fun rendered(duty: Int): FloatArray {
            val song = TestSongs.singleNote(ChannelKind.PULSE1, 60).normalized()
            val core = ChipCore(RenderHarness.SAMPLE_RATE)
            core.load(song)
            core.setInstrument(Instrument(duty = duty), ChannelKind.PULSE1, 0, false)
            core.start()
            return RenderHarness.renderMono(core, (RenderHarness.SAMPLE_RATE * 0.25).toInt())
        }
        val last = rendered(Instrument.DUTY_CYCLES.size - 1)
        assertTrue(RenderHarness.rms(last) > 0.01)
        assertTrue("an out-of-range duty index must clamp to the last real duty", sameBits(rendered(999), last))
        assertTrue("a negative duty index must clamp to the first", sameBits(rendered(-5), rendered(0)))
    }

    @Test fun pulseDutyCyclesMatchTheirSettings() {
        for (duty in Instrument.DUTY_CYCLES.indices) {
            val samples = render(TestSongs.singleNote(ChannelKind.PULSE1, 60, duty = duty), 0.5)
            val ratio = RenderHarness.dutyRatio(samples, settled, samples.size)
            assertEquals("duty index $duty rendered $ratio", Instrument.DUTY_CYCLES[duty], ratio, 0.02)
        }
    }

    @Test fun triangleIsQuantizedIntoSixteenLevels() {
        val note = 36
        val period = sampleRate / NoteName.frequency(note)
        val cycles = 4
        val from = 10_000
        val until = 10_000 + (period * cycles).toInt()

        val triangle = render(TestSongs.singleNote(ChannelKind.TRIANGLE, note), 0.5)
        val steps = RenderHarness.levelSteps(triangle, from, until).toDouble() / cycles
        assertEquals("triangle staircase measured $steps steps per cycle", 30.0, steps, 3.0)

        val pulse = render(TestSongs.singleNote(ChannelKind.PULSE1, note), 0.5)
        val pulseSteps = RenderHarness.levelSteps(pulse, from, until).toDouble() / cycles
        assertEquals(2.0, pulseSteps, 1.0)
    }

    // MARK: Envelope

    @Test fun decayFallsToSilenceOverTheSetTime() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 60, sustain = false)
            .withInstrument(0) { it.copy(decay = 0.35) }
        val samples = render(song, 1.0)
        val early = RenderHarness.rms(samples, 2205, 4410)
        val late = RenderHarness.rms(samples, 13230, 15435)
        assertTrue("the note should be sounding at 0.05 s", early > 0.01)
        assertTrue("decay didn't reach roughly -60 dB by 0.3 s (${late / early})", late / early < 0.02)
    }

    @Test fun aNewTrackOfAnyKindDoesNotSustainByDefault() {
        for (kind in ChannelKind.entries) {
            assertFalse("${kind.fullName} ships holding", Instrument.defaultFor(kind).sustain)
            val song = TestSongs.empty(tempo = 40.0).copy(tracks = listOf(Track(kind = kind)))
                .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW)) }
                .setNote(0, 0, 48)
            val samples = render(song, 3.0)
            val early = RenderHarness.rms(samples, 2205, 4410)
            assertTrue("a default ${kind.fullName} never sounded", early > 0.005)
            val tail = RenderHarness.rms(samples, samples.size - 4410, samples.size)
            assertTrue("a default ${kind.fullName} was still sounding 3 s after one note", tail < 0.005)
        }
    }

    @Test fun sustainHoldsLevelForTheWholeNote() {
        val samples = render(TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = true), 1.5)
        val early = RenderHarness.rms(samples, settled, settled + 4410)
        val late = RenderHarness.rms(samples, samples.size - 4410, samples.size)
        assertTrue(early > 0.01)
        assertEquals("a sustaining voice drifted in level", 1.0, late / early, 0.05)
    }

    @Test fun noteOffCutsASustainingVoice() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 60, tempo = 120.0).setNote(0, 8, Chip.NOTE_OFF)
        val samples = render(song, 1.5)
        val sps = swiftRounded(sampleRate * 60.0 / (120 * 4)).toInt()
        val before = RenderHarness.rms(samples, sps * 7, sps * 8)
        val after = RenderHarness.rms(samples, sps * 8 + 2205, sps * 8 + 4410)
        assertTrue("the note should be sounding before the note-off", before > 0.01)
        assertTrue("note-off didn't release the voice", after / before < 0.01)
    }

    @Test fun mutedTrackIsSilent() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 60).withTrack(0) { it.copy(muted = true) }
        assertEquals(0.0, RenderHarness.peak(render(song, 0.5)), 1e-9)
    }

    @Test fun volumeScalesTheOutputProportionally() {
        val full = render(TestSongs.singleNote(ChannelKind.PULSE1, 60), 0.5)
        val half = render(TestSongs.singleNote(ChannelKind.PULSE1, 60).withInstrument(0) { it.copy(volume = 0.5) }, 0.5)
        val ratio = RenderHarness.rms(full, settled, settled + 4410) / RenderHarness.rms(half, settled, settled + 4410)
        assertEquals("halving the volume didn't halve the level", 2.0, ratio, 0.15)
    }

    // MARK: De-click

    @Test fun retriggeringTheSameNoteDoesNotStepTheWaveform() {
        var retriggering = TestSongs.singleNote(ChannelKind.TRIANGLE, 60, tempo = 240.0)
        for (step in 0 until 16) retriggering = retriggering.setNote(0, step, 60)
        val held = render(TestSongs.singleNote(ChannelKind.TRIANGLE, 60, tempo = 240.0), 1.0)
        val retriggered = render(retriggering, 1.0)
        val baseline = RenderHarness.maxDelta(held, 1000)
        val worst = RenderHarness.maxDelta(retriggered, 1000)
        assertTrue("retriggers step the waveform by $worst against a $baseline baseline", worst < baseline * 1.5)
    }

    // MARK: Arpeggio

    @Test fun arpeggioAlternatesPitchAtAboutFiftyHertz() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 69, arpeggio = listOf(0, 12))
        val samples = render(song, 0.5)
        val segments = listOf(
            Triple(100 until 800, 440.0, 880.0),
            Triple(950 until 1700, 880.0, 440.0),
            Triple(1850 until 2600, 440.0, 880.0),
        )
        for ((window, expected, other) in segments) {
            val strong = RenderHarness.goertzel(samples, window.first, window.last + 1, expected)
            val weak = RenderHarness.goertzel(samples, window.first, window.last + 1, other)
            assertTrue("window $window should be sitting at $expected Hz", strong > weak * 3)
        }
    }

    /** Beyond Swift's suite: the first offset is not applied until the first
     * wrap, so an arpeggio whose first entry is non-zero still opens on the
     * written note for one ~20 ms segment. */
    @Test fun theFirstArpeggioOffsetWaitsForTheFirstWrap() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 69, arpeggio = listOf(12, 0))
        val samples = render(song, 0.5)
        // Segment 0: base note (offset not applied yet). Segment 1: arp[1] = 0.
        // Segment 2: arp[0] = +12.
        val seg0 = RenderHarness.goertzel(samples, 100, 800, 440.0) / RenderHarness.goertzel(samples, 100, 800, 880.0)
        val seg2 = RenderHarness.goertzel(samples, 1850, 2600, 880.0) / RenderHarness.goertzel(samples, 1850, 2600, 440.0)
        assertTrue("the opening segment should be the written note, not the first offset", seg0 > 3)
        assertTrue("the third segment should be the first offset", seg2 > 3)
    }

    @Test fun noArpeggioMeansTheNoteHoldsItsPitch() {
        val samples = render(TestSongs.singleNote(ChannelKind.PULSE1, 69), 0.5)
        for (window in listOf(100 until 800, 950 until 1700, 1850 until 2600)) {
            val base = RenderHarness.goertzel(samples, window.first, window.last + 1, 440.0)
            val up = RenderHarness.goertzel(samples, window.first, window.last + 1, 880.0)
            assertTrue("pitch moved in window $window with no arpeggio set", base > up * 3)
        }
    }

    // MARK: Master level (port-specific pins)

    /** The core's own default is what export depends on; nothing sets it. */
    @Test fun masterVolumeDefaultsToNinetyPercent() {
        assertEquals(0.9, ChipCore(44100.0).masterVolume, 0.0)
    }

    /** `0.32 * sqrt(4 / max(n, 4))`: up to four tracks keep full gain; eight
     * tracks pull one voice down by sqrt(1/2), not by 1/2. The golden song
     * has four tracks, so it can't see this. */
    @Test fun eightTracksPullTheMixDownBySquareRootOfTwo() {
        fun withTracks(n: Int): FloatArray {
            val base = TestSongs.singleNote(ChannelKind.PULSE1, 60).withInstrument(0) { it.copy(volume = 0.3) }
            val extra = List(n - 1) { Track(kind = ChannelKind.PULSE1) }
            return render(base.copy(tracks = base.tracks + extra), 0.5)
        }
        val four = withTracks(4)
        val eight = withTracks(8)
        assertEquals("one track and four tracks share a gain", 1.0,
            RenderHarness.rms(withTracks(1), settled, four.size) / RenderHarness.rms(four, settled, four.size), 1e-9)
        val ratio = RenderHarness.rms(eight, settled, eight.size) / RenderHarness.rms(four, settled, four.size)
        assertEquals("eight tracks should be sqrt(1/2) of four", StrictMath.sqrt(0.5), ratio, 0.01)
    }

    /** The release is ~15 ms to -60 dB: well inside that window it is already
     * deep, which a slower release would not be. */
    @Test fun releaseReachesSixtyDecibelsDownInFifteenMilliseconds() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 60, tempo = 120.0).setNote(0, 8, Chip.NOTE_OFF)
        val samples = render(song, 1.5)
        val sps = swiftRounded(sampleRate * 60.0 / (120 * 4)).toInt()
        val before = RenderHarness.rms(samples, sps * 7, sps * 8)
        // 10-15 ms after the note-off: about -40 to -60 dB on a 15 ms release.
        val late = RenderHarness.rms(samples, sps * 8 + 441, sps * 8 + 662)
        println("release ratio ${late / before}")
        assertTrue("the release is slower than 15 ms (${late / before})", late / before < 0.008)
    }

    /** Swift's `max(Int32(sr * 0.0025), 8)` and `max(Int32(sr * 0.0012), 8)`:
     * truncated, and floored at 8 at low rates. */
    @Test fun declickAndAttackLengthsTruncateAndFloorAtEight() {
        val cd = ChipCore(44100.0)
        assertEquals(110, cd.declickSamples) // 110.25
        assertEquals(52, cd.attackSamples) // 52.92
        val native = ChipCore(48000.0)
        assertEquals(120, native.declickSamples)
        assertEquals(57, native.attackSamples) // 57.6
        val low = ChipCore(2000.0)
        assertEquals(8, low.declickSamples) // 5
        assertEquals(8, low.attackSamples) // 2.4
    }
}
