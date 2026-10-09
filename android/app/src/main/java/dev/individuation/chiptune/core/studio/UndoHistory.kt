package dev.individuation.chiptune.core.studio

/**
 * The undo/redo stacks and their folding rules (port of `UndoHistory.swift`).
 * Knows nothing about songs: [S] is whatever the owner restores, [R] names a
 * batch of edits that collapses to one step however long it takes, and [K]
 * tags an operation so time-coalescing only folds edits of the same kind.
 *
 * [clock] reads seconds; the Studio passes its scheduler's clock, so tests
 * drive the coalescing window by hand.
 */
class UndoHistory<S, R, K>(private val clock: () -> Double) {
    private val undoStack = ArrayList<S>()
    private val redoStack = ArrayList<S>()
    private var lastCheckpoint: Double? = null
    private var lastRun: R? = null
    private var lastKind: K? = null

    /** Edits closer together than this fold into one step. */
    var coalescingWindow: Double = 1.0

    /** Deep enough for a working session, shallow enough to stay bounded. */
    var limit: Int = 50

    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    /**
     * Records [state] unless it folds into the previous checkpoint.
     *
     * [coalescing] folds when the previous checkpoint was inside the window
     * and had the same [kind]; folding rolls the window forward, so a
     * continuous stroke stays one step. [run] folds into the same named run
     * however long ago it began; any record without a run ends the run.
     */
    fun record(state: S, coalescing: Boolean = false, kind: K? = null, run: R? = null) {
        val now = clock()
        if (run != null && run == lastRun && undoStack.isNotEmpty()) {
            lastCheckpoint = now
            return
        }
        val last = lastCheckpoint
        if (coalescing && run == null && undoStack.isNotEmpty() && last != null &&
            kind == lastKind && now - last < coalescingWindow
        ) {
            lastCheckpoint = now
            return
        }
        undoStack.add(state)
        if (undoStack.size > limit) undoStack.removeAt(0)
        // A new edit is a new branch; whatever was undone past is gone.
        redoStack.clear()
        lastCheckpoint = now
        lastRun = run
        lastKind = kind
    }

    /** Steps back, keeping [current] for redo. Null when there is nothing to undo. */
    fun undo(current: S): S? {
        if (undoStack.isEmpty()) return null
        val previous = undoStack.removeAt(undoStack.size - 1)
        redoStack.add(current)
        return previous
    }

    fun redo(current: S): S? {
        if (redoStack.isEmpty()) return null
        val next = redoStack.removeAt(redoStack.size - 1)
        undoStack.add(current)
        return next
    }

    /** The next edit starts a fresh step rather than folding into whatever
     * was just restored. */
    fun closeFolding() {
        lastCheckpoint = null
        lastRun = null
        lastKind = null
    }

    /** Ends the current named run. */
    fun endRun() {
        lastRun = null
    }

    /** Drops the redo branch, for a state that was rejected rather than undone. */
    fun dropRedo() {
        redoStack.clear()
    }

    fun reset() {
        undoStack.clear()
        redoStack.clear()
        closeFolding()
    }

    /** Whether the last checkpoint opened [run] and is still on the stack. */
    fun lastRunIs(run: R): Boolean = lastRun == run && undoStack.isNotEmpty()
}
