package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.SeededRandom
import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.SongPropertyTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The render half of `SongPropertyTests.swift`, which Phase 1 left for the
 * synth: a hostile song, normalized, actually rendered. */
class SongRenderPropertyTest {

    private val seed: ULong = 0xC4177175_7E000001uL

    @Test fun anyNormalizedSongRendersFiniteAudio() {
        val rng = SeededRandom(seed)
        for (i in 0 until 50) {
            val tag = "seed ${seed.toString(16)}, iteration $i"
            val song = SongPropertyTest.hostileSong(rng).normalized()
            val core = ChipCore(RenderHarness.SAMPLE_RATE)
            core.load(song)
            core.setSongMode(true)
            core.start()
            val samples = RenderHarness.renderMono(core, 4096)
            assertFalse("render produced NaN or infinity ($tag)", samples.any { !it.isFinite() })
            assertTrue("render exceeded full scale ($tag)", RenderHarness.peak(samples) <= 1.0)
        }
    }

    @Test fun extremeArpeggioOffsetsCannotWedgeTheMasterChain() {
        val song = TestSongs.singleNote(ChannelKind.PULSE1, 69, arpeggio = listOf(0, Int.MAX_VALUE / 2))
        val samples = RenderHarness.render(song, 0.5)
        assertFalse("an extreme arpeggio offset put NaN into the output", samples.any { !it.isFinite() })
        assertTrue("the voice went silent instead of playing a clamped pitch",
            RenderHarness.rms(samples, 4410, samples.size) > 0.01)
    }

    /** The backstop itself: an instrument the core is handed directly, never
     * normalized, with an offset whose pitch overflows to infinity. The bad
     * samples are zeroed; the DC blocker never latches a NaN. */
    @Test fun aNonFiniteVoiceIsContainedByTheMasterBackstop() {
        val core = ChipCore(RenderHarness.SAMPLE_RATE)
        val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 69).normalized()
        core.load(song)
        core.setInstrument(song.tracks[0].instrument.copy(arpeggio = listOf(0, 1_000_000)), ChannelKind.TRIANGLE, 0, false)
        core.start()
        val samples = RenderHarness.renderMono(core, 22050)
        assertFalse("a non-finite voice reached the output", samples.any { !it.isFinite() })
        // Back to a sane instrument: the master chain must not be wedged.
        core.setInstrument(song.tracks[0].instrument, ChannelKind.TRIANGLE, 0, false)
        core.start()
        val after = RenderHarness.renderMono(core, 22050)
        assertTrue("the master chain stayed wedged after a non-finite sample", RenderHarness.rms(after, 4410, after.size) > 0.01)
    }
}
