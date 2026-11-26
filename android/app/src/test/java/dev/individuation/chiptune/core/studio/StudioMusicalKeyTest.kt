package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.MusicalKey
import dev.individuation.chiptune.core.model.Song
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Setting the song's key is an edit like any other: one undo step, saved. */
class StudioMusicalKeyTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Key"))
        studio.undoCoalescingWindow = 0.0
    }

    @After
    fun tearDown() = h.close()

    @Test fun settingAKeyIsOneUndoStep() {
        val g = MusicalKey(7, MusicalKey.Scale.MAJOR)
        studio.setKey(g)
        assertEquals(g, studio.song.key)
        assertTrue(studio.canUndo)
        studio.undo()
        assertNull(studio.song.key)
        studio.redo()
        assertEquals(g, studio.song.key)
    }

    @Test fun changingAndClearingTheKeyUndoBackThroughEach() {
        val a = MusicalKey(9, MusicalKey.Scale.MINOR)
        val d = MusicalKey(2, MusicalKey.Scale.MAJOR)
        studio.setKey(a)
        studio.setKey(d)
        studio.setKey(null)
        assertNull(studio.song.key)
        studio.undo()
        assertEquals(d, studio.song.key)
        studio.undo()
        assertEquals(a, studio.song.key)
        studio.undo()
        assertNull(studio.song.key)
    }

    @Test fun theSameKeyIsNotAnEdit() {
        val c = MusicalKey(0, MusicalKey.Scale.MAJOR)
        studio.setKey(c)
        studio.undo()
        assertTrue(studio.canRedo)
        studio.setKey(null)
        assertTrue("re-setting no key wiped Redo", studio.canRedo)
        assertFalse(studio.canUndo)
    }

    @Test fun anOutOfRangeRootIsIgnored() {
        studio.setKey(MusicalKey(12, MusicalKey.Scale.MAJOR))
        assertNull(studio.song.key)
        assertFalse(studio.canUndo)
    }

    @Test fun theKeyIsAutosaved() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            auto.studio.open(Song.create("Saved"))
            val key = MusicalKey(4, MusicalKey.Scale.MINOR)
            auto.studio.setKey(key)
            auto.scheduler.advance(10.0)
            assertEquals(key, auto.temp.store.load(auto.studio.song.id)?.key)
        } finally {
            auto.close()
        }
    }
}
