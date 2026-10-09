package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import java.lang.management.ManagementFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The AudioTrack write loop, driven against a fake sink: what reaches the
 * track must be the synth's output sample for sample, a dead track must be
 * reported once, and the loop must not allocate. */
class PcmWriteLoopTest {

    private fun startedCore(): ChipCore {
        val song = TestSongs.golden().withInstrument(0) { it.copy(arpeggio = listOf(0, 4, 7, -12)) }.normalized()
        val core = ChipCore(48000.0)
        core.load(song)
        core.start()
        return core
    }

    private fun straightRender(frames: Int): FloatArray {
        val out = FloatArray(frames)
        startedCore().render(frames, out)
        return out
    }

    /** Copies everything it is given into one preallocated array, accepting
     * at most [maxPerWrite] frames per call like a nearly full track does. */
    private class RecordingSink(capacity: Int, private val maxPerWrite: Int = Int.MAX_VALUE) : PcmSink {
        val recorded = FloatArray(capacity)
        var size = 0
        var writes = 0
        override fun write(buffer: FloatArray, offset: Int, frames: Int): Int {
            writes++
            val n = minOf(frames, maxPerWrite, recorded.size - size)
            System.arraycopy(buffer, offset, recorded, size, n)
            size += n
            return n
        }
    }

    @Test fun manyChunksAddUpToOneStraightRender() {
        val chunk = 480
        val iterations = 300 // 144,000 frames, three seconds at 48 kHz
        val sink = RecordingSink(chunk * iterations)
        val loop = PcmWriteLoop(startedCore(), sink, chunk) { fail("no death expected") }
        repeat(iterations) { assertTrue(loop.step()) }
        val reference = straightRender(chunk * iterations)
        assertEquals(reference.size, sink.size)
        assertTrue("the song must make sound", reference.any { kotlin.math.abs(it) > 0.001f })
        for (i in reference.indices) {
            assertEquals("frame $i", reference[i].toRawBits(), sink.recorded[i].toRawBits())
        }
    }

    /** A track that takes a chunk in pieces still gets every frame once, in order. */
    @Test fun partialWritesLoseAndRepeatNothing() {
        val chunk = 1000
        val iterations = 50
        val sink = RecordingSink(chunk * iterations, maxPerWrite = 333)
        val loop = PcmWriteLoop(startedCore(), sink, chunk) { fail("no death expected") }
        repeat(iterations) { assertTrue(loop.step()) }
        val reference = straightRender(chunk * iterations)
        assertEquals(reference.size, sink.size)
        assertTrue(sink.writes > iterations)
        for (i in reference.indices) {
            assertEquals("frame $i", reference[i].toRawBits(), sink.recorded[i].toRawBits())
        }
    }

    private fun assertDeathReportedOnce(code: Int) {
        var calls = 0
        val sink = PcmSink { _, _, frames -> if (++calls == 3) code else frames }
        var deaths = 0
        val loop = PcmWriteLoop(startedCore(), sink, 256) { deaths++ }
        loop.run() // returns on its own once the sink dies
        assertEquals("death for code $code", 1, deaths)
        assertEquals(3, calls)
        assertFalse(loop.step())
        loop.run()
        assertEquals("a dead loop reports once", 1, deaths)
        assertEquals("a dead loop writes nothing more", 3, calls)
    }

    @Test fun deadObjectStopsTheLoopAndReportsOnce() = assertDeathReportedOnce(PcmSink.ERROR_DEAD_OBJECT)

    @Test fun genericErrorCountsAsDeath() = assertDeathReportedOnce(PcmSink.ERROR)

    @Test fun invalidOperationCountsAsDeath() = assertDeathReportedOnce(PcmSink.ERROR_INVALID_OPERATION)

    @Test fun requestStopEndsRunWithoutADeath() {
        var deaths = 0
        lateinit var loop: PcmWriteLoop
        var calls = 0
        val sink = PcmSink { _, _, frames -> if (++calls == 5) loop.requestStop(); frames }
        loop = PcmWriteLoop(startedCore(), sink, 256) { deaths++ }
        loop.run()
        assertEquals(5, calls)
        assertEquals(0, deaths)
    }

    /** A stopped track returns 0 from a blocking write; the loop must notice
     * the stop request instead of spinning on the same chunk. */
    @Test fun zeroWriteAfterStopRequestEndsRun() {
        lateinit var loop: PcmWriteLoop
        var calls = 0
        val sink = PcmSink { _, _, _ -> calls++; loop.requestStop(); 0 }
        loop = PcmWriteLoop(startedCore(), sink, 256) { fail("no death expected") }
        loop.run()
        assertEquals(1, calls)
    }

    /** Same technique as `AudioCallbackTest.renderAndFillDoNotAllocate`:
     * keep going in rounds until one allocates nothing once compiled. */
    @Test fun stepDoesNotAllocate() {
        val bean = ManagementFactory.getThreadMXBean() as com.sun.management.ThreadMXBean
        if (!bean.isThreadAllocatedMemorySupported) return
        bean.isThreadAllocatedMemoryEnabled = true
        val sink = PcmSink { _, _, frames -> frames }
        val loop = PcmWriteLoop(startedCore(), sink, 960) { fail("no death expected") }
        val rounds = ArrayList<Long>()
        repeat(40) {
            val before = bean.currentThreadAllocatedBytes
            repeat(2000) { loop.step() } // ~1.9M frames
            val allocated = bean.currentThreadAllocatedBytes - before
            rounds.add(allocated)
            if (allocated == 0L) return
        }
        fail("no round of steps ran without allocating: $rounds")
    }
}
