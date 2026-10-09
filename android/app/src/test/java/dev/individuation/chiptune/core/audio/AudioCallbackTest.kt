package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.Song
import java.lang.management.ManagementFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Port of `AudioCallbackTests.swift`: however many frames the output asks
 * for, every one is real rendered audio, bit-identical to what the synth
 * produces rendering the same stretch in one call. Phase 4's AudioTrack write
 * loop drives [RenderSlicer] exactly this way. */
class AudioCallbackTest {

    /** Notes on every channel, held, so the render is nonzero well past any
     * internal buffer size. */
    private fun makeSong(): Song {
        var song = TestSongs.empty(name = "CallbackTest", tempo = 240.0)
        for (i in song.tracks.indices) song = song.withInstrument(i) { it.copy(sustain = true) }
        return song.setNote(0, 0, 60).setNote(1, 4, 64).setNote(2, 8, 48).setNote(3, 12, 60).normalized()
    }

    private fun makeStartedCore(song: Song): ChipCore {
        val core = ChipCore(44100.0)
        core.load(song)
        core.start()
        return core
    }

    private fun reference(song: Song, frames: Int): FloatArray {
        val out = FloatArray(frames)
        makeStartedCore(song).render(frames, out)
        return out
    }

    private fun assertMatches(reference: FloatArray, filled: FloatArray, frames: Int) {
        for (i in 0 until frames) {
            assertFalse("frame $i was never written", filled[i].isNaN())
            assertEquals("frame $i differs from a straight render",
                reference[i].toRawBits(), filled[i].toRawBits())
        }
    }

    @Test fun fillMatchesStraightRenderBeyondScratchSize() {
        val song = makeSong()
        val scratchLen = RenderSlicer.SCRATCH_LENGTH
        assertEquals(4096, scratchLen)
        // Deliberately larger than the scratch, and not a multiple of it.
        val frames = 10_000
        val reference = reference(song, frames)
        assertTrue("test song must produce audio beyond $scratchLen frames",
            (scratchLen until frames).any { kotlin.math.abs(reference[it]) > 0.001f })

        val out = FloatArray(frames) { Float.NaN }
        RenderSlicer(makeStartedCore(song)).fill(out, frames)
        assertMatches(reference, out, frames)
    }

    @Test fun fillHandlesRequestSmallerThanScratch() {
        val song = makeSong()
        val frames = 512
        val reference = reference(song, frames)
        val out = FloatArray(frames) { Float.NaN }
        RenderSlicer(makeStartedCore(song)).fill(out, frames)
        assertMatches(reference, out, frames)
    }

    /** A run of uneven requests, like an AudioTrack whose buffer size moves,
     * must still add up to one straight render. */
    @Test fun repeatedUnevenFillsAddUpToOneStraightRender() {
        val song = makeSong()
        val sizes = listOf(1, 4095, 4096, 4097, 9000, 37, 12_288)
        val total = sizes.sum()
        val reference = reference(song, total)
        val slicer = RenderSlicer(makeStartedCore(song))
        val stitched = FloatArray(total)
        var at = 0
        for (n in sizes) {
            val out = FloatArray(n) { Float.NaN }
            slicer.fill(out, n)
            System.arraycopy(out, 0, stitched, at, n)
            at += n
        }
        assertMatches(reference, stitched, total)
    }

    /** `render` writing at an offset is what `fill` and `renderMono` lean on. */
    @Test fun renderAtAnOffsetLeavesTheRestOfTheBufferAlone() {
        val core = makeStartedCore(makeSong())
        val out = FloatArray(300) { Float.NaN }
        core.render(100, out, 100)
        assertTrue((0 until 100).all { out[it].isNaN() })
        assertTrue((100 until 200).none { out[it].isNaN() })
        assertTrue((200 until 300).all { out[it].isNaN() })
    }

    /** The render thread must not allocate: a GC pause on the audio thread is
     * a dropout. Measured with HotSpot's per-thread allocation counter. Before
     * C2 has compiled the loop, HotSpot's lower tiers report ~100 bytes per
     * call that are not the core's (the render path's bytecode contains no
     * `new`), and how long that lasts depends on the JIT. (This test is how
     * `StrictMath.pow` was caught allocating on the render thread: JDK 17's
     * Java FdLibm port allocates per call, and C2 doesn't always remove it.) So the claim is that
     * once compiled, a long stretch of rendering allocates exactly nothing:
     * keep rendering in rounds until one round is clean, and fail only if none
     * ever is. A real allocation in the loop would never produce a clean round. */
    @Test fun renderAndFillDoNotAllocate() {
        val bean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        if (!bean.isThreadAllocatedMemorySupported) return
        bean.isThreadAllocatedMemoryEnabled = true
        // The golden riff with an arpeggio on the lead, so note starts and
        // arpeggio steps (the two places that need pow) are both exercised.
        val song = TestSongs.golden().withInstrument(0) { it.copy(arpeggio = listOf(0, 4, 7, -12)) }.normalized()
        val core = makeStartedCore(song)
        val slicer = RenderSlicer(core)
        val out = FloatArray(10_000)
        val rounds = ArrayList<Long>()
        repeat(40) {
            val before = bean.currentThreadAllocatedBytes
            repeat(200) { slicer.fill(out, out.size) } // 2M frames, ~45 s of audio
            val allocated = bean.currentThreadAllocatedBytes - before
            rounds.add(allocated)
            if (allocated == 0L) return
        }
        fail("no round of 2M frames rendered without allocating: $rounds")
    }
}
