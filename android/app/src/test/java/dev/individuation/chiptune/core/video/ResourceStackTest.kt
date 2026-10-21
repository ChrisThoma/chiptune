package dev.individuation.chiptune.core.video

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** What `platform/video/Mp4Writer` leans on so a failed start doesn't leak
 * a hardware codec: everything opened before a throw is released, once, in
 * reverse order, however far the start got. The writer opens its frame
 * drawer, the YUV threads, the video encoder, the audio encoder, the muxer
 * and the soundtrack's stream through one of these, then configures and
 * starts them; any of those steps can throw. */
class ResourceStackTest {

    private val stages = listOf("drawer", "converters", "video", "audio", "muxer", "pcm")

    /** Opens [stages] in order on [stack], throwing at [failAt] (an index
     * into [stages], or [stages].size for a throw after everything opened,
     * as a refused configure or a short soundtrack does). */
    private fun start(stack: ResourceStack, failAt: Int, released: MutableList<String>) {
        for ((index, name) in stages.withIndex()) {
            if (index == failAt) throw IOException("$name refused")
            stack.open({ name }) { released.add(it) }
        }
        if (failAt == stages.size) throw IllegalStateException("configure refused")
    }

    @Test fun aFailureAtAnyStageReleasesEverythingOpenedSoFarOnceInReverse() {
        for (failAt in 0..stages.size) {
            val released = ArrayList<String>()
            val stack = ResourceStack()
            try {
                stack.use { start(it, failAt, released) }
                fail("stage $failAt should have thrown")
            } catch (e: Exception) {
                assertTrue("stage $failAt: ${e.message}", e is IOException || e is IllegalStateException)
            }
            assertEquals("failing at $failAt", stages.take(failAt).reversed(), released)
            stack.close()
            assertEquals("closing again releases nothing more", stages.take(failAt).reversed(), released)
        }
    }

    @Test fun theHappyPathReleasesEverythingOnceAfterTheWork() {
        val released = ArrayList<String>()
        val result = ResourceStack().use { stack ->
            for (name in stages) stack.open({ name }) { released.add(it) }
            assertTrue("nothing released while in use", released.isEmpty())
            "done"
        }
        assertEquals("done", result)
        assertEquals(stages.reversed(), released)
    }

    /** A codec that throws from stop or release must not keep the muxer or
     * the drawer behind it from being released. */
    @Test fun aReleaseThatThrowsDoesNotStopTheOthers() {
        val released = ArrayList<String>()
        val stack = ResourceStack()
        stack.open({ "drawer" }) { released.add(it) }
        stack.open({ "video" }) { throw IllegalStateException("stop on an unstarted codec") }
        stack.open({ "muxer" }) { released.add(it) }
        stack.close()
        assertEquals(listOf("muxer", "drawer"), released)
    }

    /** A create that throws opened nothing, so nothing of its is released. */
    @Test fun aCreateThatThrowsIsNotReleased() {
        val released = ArrayList<String>()
        val stack = ResourceStack()
        stack.open({ "video" }) { released.add(it) }
        val refused = IOException("no codec instances left")
        try {
            stack.open<String>({ throw refused }) { released.add("audio") }
            fail()
        } catch (e: IOException) {
            assertSame(refused, e)
        }
        stack.close()
        assertEquals(listOf("video"), released)
    }

    @Test fun openReturnsWhatWasCreated() {
        val stack = ResourceStack()
        val thing = Any()
        assertSame(thing, stack.open({ thing }) {})
        stack.close()
    }
}
