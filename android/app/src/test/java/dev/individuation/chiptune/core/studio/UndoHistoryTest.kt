package dev.individuation.chiptune.core.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The folding rules on their own, with a hand-driven clock. */
class UndoHistoryTest {

    private var now = 0.0
    private val history = UndoHistory<Int, String, String> { now }

    @Test fun recordsUndoesAndRedoes() {
        history.record(1)
        history.record(2)
        assertEquals(2, history.undo(3))
        assertEquals(1, history.undo(2))
        assertNull(history.undo(1))
        assertEquals(2, history.redo(1))
        assertTrue(history.canUndo)
        assertTrue(history.canRedo)
    }

    @Test fun coalescesOnlyTheSameKindInsideTheWindow() {
        history.record(1, coalescing = true, kind = "cell")
        now = 0.5
        history.record(2, coalescing = true, kind = "cell")
        now = 0.9
        history.record(3, coalescing = true, kind = "tempo")
        assertEquals(3, history.undo(4))
        assertEquals(1, history.undo(3))
        assertFalse(history.canUndo)
    }

    @Test fun theWindowIsStrictAndRollsForward() {
        history.record(1, coalescing = true, kind = "cell")
        now = 0.75
        history.record(2, coalescing = true, kind = "cell")
        now = 1.5
        history.record(3, coalescing = true, kind = "cell")
        now = 2.5
        history.record(4, coalescing = true, kind = "cell")
        assertEquals(4, history.undo(5))
        assertEquals(1, history.undo(4))
    }

    @Test fun aNonCoalescingRecordNeverFolds() {
        history.record(1, coalescing = true, kind = "cell")
        history.record(2, kind = "cell")
        assertEquals(2, history.undo(3))
        assertEquals(1, history.undo(2))
    }

    @Test fun namedRunsFoldHoweverLongTheyTake() {
        history.record(1, run = "rename")
        now = 1000.0
        history.record(2, run = "rename")
        assertTrue(history.lastRunIs("rename"))
        assertEquals(1, history.undo(3))
        assertFalse(history.canUndo)
    }

    @Test fun anyRecordWithoutARunEndsTheRun() {
        history.record(1, run = "rename")
        history.record(2)
        history.record(3, run = "rename")
        assertEquals(3, history.undo(4))
        assertEquals(2, history.undo(3))
    }

    @Test fun endRunAndCloseFoldingStartFreshSteps() {
        history.record(1, run = "rename")
        history.endRun()
        assertFalse(history.lastRunIs("rename"))
        history.record(2, run = "rename")
        history.record(3, coalescing = true, kind = "cell")
        history.closeFolding()
        history.record(4, coalescing = true, kind = "cell")
        assertEquals(4, history.undo(5))
        assertEquals(3, history.undo(4))
        assertEquals(2, history.undo(3))
        assertEquals(1, history.undo(2))
    }

    @Test fun aNewRecordDropsRedoAndDropRedoDoesToo() {
        history.record(1)
        history.undo(2)
        assertTrue(history.canRedo)
        history.record(2)
        assertFalse(history.canRedo)
        history.undo(3)
        history.dropRedo()
        assertFalse(history.canRedo)
    }

    @Test fun theLimitDropsTheOldest() {
        history.limit = 3
        for (i in 1..5) history.record(i)
        assertEquals(5, history.undo(6))
        assertEquals(4, history.undo(5))
        assertEquals(3, history.undo(4))
        assertNull(history.undo(3))
    }

    @Test fun resetClearsEverything() {
        history.record(1, run = "rename")
        history.undo(2)
        history.record(3, run = "rename")
        history.reset()
        assertFalse(history.canUndo)
        assertFalse(history.canRedo)
        assertFalse(history.lastRunIs("rename"))
    }

    @Test fun lastRunIsNeedsAStepOnTheStack() {
        history.record(1, run = "rename")
        history.undo(2)
        assertFalse(history.lastRunIs("rename"))
    }
}
