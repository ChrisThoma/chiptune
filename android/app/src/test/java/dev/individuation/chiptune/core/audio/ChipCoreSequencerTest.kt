package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.model.swiftRounded
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ChipCoreSequencerTests.swift`: steps land on the sample the tempo
 * says, PATT loops one pattern, SONG walks the chain with repeats and wraps,
 * and no mid-playback edit sends the playhead somewhere that doesn't exist. */
class ChipCoreSequencerTest {

    private val sampleRate = RenderHarness.SAMPLE_RATE

    private fun samplesPerStep(tempo: Double): Int = swiftRounded(sampleRate * 60.0 / (tempo * 4.0)).toInt()

    private fun makeCore(song: Song, songMode: Boolean = false): ChipCore {
        val core = ChipCore(sampleRate)
        core.load(song.normalized())
        core.setSongMode(songMode)
        core.start()
        return core
    }

    private fun oneTrack(tempo: Double, length: Int = 16): Song =
        TestSongs.empty(tempo = tempo, length = length).copy(tracks = listOf(Track(kind = ChannelKind.PULSE1)))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW)) }

    // MARK: Step timing

    @Test fun stepsTriggerOnTheSamplesPerStepBoundary() {
        val tempo = 120.0
        var song = oneTrack(tempo).withInstrument(0) { it.copy(decay = 0.05, volume = 1.0) }
        for (step in 0 until 8) song = song.setNote(0, step, 60)

        val sps = samplesPerStep(tempo)
        val samples = RenderHarness.renderMono(makeCore(song), sps * 6)
        val onsets = RenderHarness.onsets(samples, refractory = sps / 2)
        assertEquals("one onset per step: $onsets", 6, onsets.size)
        for ((index, onset) in onsets.withIndex()) {
            assertEquals("step $index fired at $onset, expected ${index * sps}",
                (index * sps).toDouble(), onset.toDouble(), 256.0)
        }
    }

    @Test fun stepLengthTracksTempoIncludingRounding() {
        for (tempo in listOf(120.0, 132.0, 175.0, 300.0)) {
            val sps = samplesPerStep(tempo)
            val core = makeCore(oneTrack(tempo))
            RenderHarness.renderMono(core, sps - 1)
            assertEquals("at $tempo BPM the step advanced early", 0, core.currentStep)
            RenderHarness.renderMono(core, 2)
            assertEquals("at $tempo BPM the step didn't advance on time", 1, core.currentStep)
        }
    }

    // MARK: PATT mode

    @Test fun patternModeLoopsTheFocusedPatternForever() {
        val core = makeCore(TestSongs.twoPatterns(lengths = 4 to 16), songMode = false)
        core.focus(1)
        val sps = samplesPerStep(120.0)
        repeat(40) {
            RenderHarness.renderMono(core, sps)
            assertEquals("PATT mode must not leave the focused pattern", 1, core.currentPattern)
        }
    }

    @Test fun patternLoopsBackToStepZeroAtItsOwnLength() {
        val core = makeCore(oneTrack(120.0, length = 4))
        val sps = samplesPerStep(120.0)
        val seen = ArrayList<Int>()
        repeat(9) {
            seen.add(core.currentStep)
            RenderHarness.renderMono(core, sps)
        }
        assertEquals(listOf(0, 1, 2, 3, 0, 1, 2, 3, 0), seen)
    }

    @Test fun focusChangeSwitchesPatternInPattMode() {
        val sps = samplesPerStep(120.0)
        val core = makeCore(TestSongs.twoPatterns(lengths = 16 to 16), songMode = false)
        RenderHarness.renderMono(core, sps * 3)
        assertEquals(0, core.currentPattern)
        core.focus(1)
        assertEquals(1, core.currentPattern)
        RenderHarness.renderMono(core, sps * 20)
        assertEquals(1, core.currentPattern)
    }

    // MARK: SONG mode

    @Test fun songModeWalksTheChainWithRepeatsAndWraps() {
        val song = TestSongs.twoPatterns(lengths = 16 to 8, repeats = 2 to 1)
        assertEquals("the test's premise: the flattened chain", listOf(0, 0, 1), song.chain)
        val sps = samplesPerStep(120.0)
        val core = makeCore(song, songMode = true)
        val seen = ArrayList<Int>()
        repeat(60) {
            seen.add(core.currentPattern)
            RenderHarness.renderMono(core, sps)
        }
        val expected = List(32) { 0 } + List(8) { 1 } + List(20) { 0 }
        assertEquals(expected, seen)
    }

    @Test fun songModeStartsAtTheTopOfTheChain() {
        val core = makeCore(TestSongs.twoPatterns(lengths = 16 to 16), songMode = false)
        core.focus(1)
        assertEquals(1, core.currentPattern)
        core.setSongMode(true)
        assertEquals("SONG must begin at the start of the arrangement", 0, core.currentPattern)
    }

    @Test fun startRewindsThePlayheadOnTheNextBuffer() {
        val sps = samplesPerStep(120.0)
        val core = makeCore(TestSongs.twoPatterns(lengths = 16 to 16), songMode = false)
        RenderHarness.renderMono(core, sps * 5)
        assertEquals("precondition: the playhead moved", 5, core.currentStep)
        core.start()
        RenderHarness.renderMono(core, 1)
        assertEquals("start() must rewind to the top", 0, core.currentStep)
        assertEquals(0, core.currentPattern)
    }

    // MARK: Retargeting

    @Test fun retargetMovesThePlaybackPositionWithoutRestartingIt() {
        val song = TestSongs.twoPatterns(lengths = 16 to 8, repeats = 2 to 1)
        val sps = samplesPerStep(120.0)
        val core = makeCore(song, songMode = true)
        RenderHarness.renderMono(core, sps * 4)
        assertEquals("precondition: still in the first play of A", 0, core.currentChainSlot)

        core.retarget(2, 1)
        assertEquals(2, core.currentChainSlot)
        assertEquals(1, core.currentPattern)

        RenderHarness.renderMono(core, sps * 3)
        assertEquals("still inside B", 1, core.currentPattern)
        assertEquals(2, core.currentChainSlot)
        RenderHarness.renderMono(core, sps * 2)
        assertEquals("the chain wrapped from the slot it was given", 0, core.currentChainSlot)
        assertEquals(0, core.currentPattern)
    }

    @Test fun retargetClampsOutOfRangeInputs() {
        val core = makeCore(TestSongs.twoPatterns(lengths = 16 to 8), songMode = true)
        core.retarget(99, 99)
        assertTrue(core.currentChainSlot < core.chainCount)
        assertTrue(core.currentPattern < core.patternCount)
        core.retarget(-3, -3)
        assertEquals(0, core.currentChainSlot)
        assertEquals(0, core.currentPattern)
    }

    // MARK: Hostile edits mid-playback

    @Test fun patternShrinkingUnderThePlayheadResetsTheStep() {
        val sps = samplesPerStep(120.0)
        val core = makeCore(oneTrack(120.0, length = 16))
        RenderHarness.renderMono(core, sps * 10)
        assertEquals(10, core.currentStep)
        core.setLength(0, 4)
        RenderHarness.renderMono(core, 64)
        assertTrue("the playhead must fold back inside the shorter pattern", core.currentStep < 4)
    }

    @Test fun setChainClampsSlotsAndCount() {
        val core = ChipCore(sampleRate)
        core.load(TestSongs.empty().normalized())

        core.setChain(emptyList())
        assertEquals("an empty chain still has to play something", 1, core.chainCount)

        core.setChain(List(Chip.MAX_CHAIN * 4) { 0 })
        assertEquals(Chip.MAX_CHAIN, core.chainCount)

        core.setChain(listOf(-5, 999, 1))
        assertEquals(3, core.chainCount)
        core.setSongMode(true)
        core.start()
        val samples = RenderHarness.renderMono(core, sampleRate.toInt())
        assertFalse(samples.any { !it.isFinite() })
        assertTrue(core.currentPattern < core.patternCount)
    }

    @Test fun loadPullsFocusInsideTheNewPatternCount() {
        var song = TestSongs.twoPatterns()
        val core = makeCore(song, songMode = false)
        core.focus(1)
        assertEquals(1, core.focusPattern)

        song = song.copy(patterns = song.patterns.dropLast(1)).normalized()
        core.load(song)
        assertTrue(core.focusPattern < core.patternCount)
        assertTrue(core.currentPattern < core.patternCount)
    }
}
