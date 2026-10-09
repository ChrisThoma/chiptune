package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.studio.RevealRequest
import java.util.UUID

/*
 * The grid's pure geometry, ported from `GridView.swift`: the pinned step
 * column (`GridPinning`), where a song or track change scrolls sideways
 * (`GridReveal`) and when playback drags the rows along (`GridFollow`).
 */

/** Keeps the step-number column at the leading edge of a grid that scrolls
 * sideways: each label is shifted by how far the grid has scrolled. */
object GridPinning {
    /** The rows' leading inset, before the step number. */
    const val ROW_INSET = 6.0
    /** The gap between the step number and the first column, and between columns. */
    const val COLUMN_GAP = 2.0
    /** The cursor ring's stroke, centred on the cell's edge. */
    const val CURSOR_RING_WIDTH = 2.0

    fun labelOffset(scrollX: Double): Double = maxOf(0.0, scrollX)

    /** What the pinned step numbers hide once the grid scrolls. */
    fun stripWidth(gutterWidth: Double): Double = ROW_INSET + gutterWidth + COLUMN_GAP

    /** How far left of a column an arrow-key reveal keeps clear. */
    fun revealClearance(gutterWidth: Double): Double = stripWidth(gutterWidth) + CURSOR_RING_WIDTH / 2

    data class Backing(val leading: Double, val width: Double)

    /** The label's opaque backing, in the label's own coordinates. */
    fun backing(gutterWidth: Double, scrollX: Double): Backing =
        if (scrollX > 0) Backing(-ROW_INSET, stripWidth(gutterWidth)) else Backing(0.0, gutterWidth)

    /** Where track column [index] starts inside the scrolling row. */
    fun columnStart(index: Int, gutterWidth: Double, columnWidth: Double): Double =
        stripWidth(gutterWidth) + index * (columnWidth + COLUMN_GAP)
}

/** Where the grid scrolls sideways when the song or its track count changes
 * under it, or an undo/redo or arrow key moves the selection. */
object GridReveal {
    data class Trigger(
        val songID: UUID,
        val trackCount: Int,
        val selectedTrack: Int,
        val reveal: RevealRequest,
    )

    sealed class Target {
        /** The last track and the "+" beside it. */
        data object TrailingEdge : Target()

        /** Centred in the row. */
        data class Track(val index: Int) : Target()

        /** Only as far as it takes to show the whole column. */
        data class Nearest(val index: Int) : Target()
    }

    /** Null leaves the scroll where the user put it. */
    fun target(old: Trigger, new: Trigger): Target? {
        val last = maxOf(new.trackCount - 1, 0)
        val selected = minOf(maxOf(new.selectedTrack, 0), last)
        val songOrCountChanged = new.songID != old.songID || new.trackCount > old.trackCount
        val requested = new.reveal != old.reveal
        if (requested && new.reveal.reason == RevealRequest.Reason.CURSOR && !songOrCountChanged) {
            return Target.Nearest(selected)
        }
        val undoMovedSelection = requested && new.reveal.reason == RevealRequest.Reason.UNDO_REDO &&
            new.selectedTrack != old.selectedTrack
        if (!(songOrCountChanged || undoMovedSelection)) return null
        return if (selected == last) Target.TrailingEdge else Target.Track(selected)
    }

    /** `scrollTo(id, anchor: .center)`: the column's centre at the
     * viewport's, clamped to what the row can scroll. */
    fun centredScroll(columnStart: Double, columnWidth: Double, viewport: Double, maxScroll: Double): Double =
        (columnStart + columnWidth / 2 - viewport / 2).coerceIn(0.0, maxOf(maxScroll, 0.0))

    /** `scrollTo(id, anchor: nil)`: the least scroll that shows
     * [frameStart]..[frameEnd], and none if it already shows. */
    fun nearestScroll(current: Double, frameStart: Double, frameEnd: Double, viewport: Double, maxScroll: Double): Double {
        val target = when {
            frameStart < current -> frameStart
            frameEnd > current + viewport -> frameEnd - viewport
            else -> current
        }
        return target.coerceIn(0.0, maxOf(maxScroll, 0.0))
    }
}

/** Whether playback drags the step rows along with the playhead, and where. */
object GridFollow {
    /** The rows' gap and the list's padding above and below. */
    const val ROW_SPACING = 2.0
    const val VERTICAL_PADDING = 4.0

    enum class Anchor { TOP, CENTER }

    fun contentHeight(steps: Int, rowHeight: Double): Double {
        if (steps <= 0) return VERTICAL_PADDING * 2
        return steps * rowHeight + (steps - 1) * ROW_SPACING + VERTICAL_PADDING * 2
    }

    fun follows(steps: Int, rowHeight: Double, viewportHeight: Double): Boolean =
        contentHeight(steps, rowHeight) > viewportHeight

    /** Where a step's scroll lands, or null to leave the grid alone. Only a
     * playing row that is clipped or off screen moves the grid, to the top.
     * A null [scrollY] (offset unknown) centres on every step. */
    fun anchor(playhead: Int, steps: Int, rowHeight: Double, viewportHeight: Double, scrollY: Double?): Anchor? {
        if (!follows(steps, rowHeight, viewportHeight)) return null
        if (scrollY == null) return Anchor.CENTER
        val top = VERTICAL_PADDING + playhead * (rowHeight + ROW_SPACING)
        val inView = top >= scrollY - 0.5 && top + rowHeight <= scrollY + viewportHeight + 0.5
        return if (inView) null else Anchor.TOP
    }

    /** Half a step, up to 0.15 s: a scroll that outlasts its step loses the next. */
    fun scrollDuration(tempo: Double): Double {
        val step = 60 / (maxOf(tempo, 1.0) * Chip.STEPS_PER_BEAT)
        return minOf(0.15, step / 2)
    }
}
