package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.studio.RevealRequest
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `GridFollowTests.swift`: playback scrolls the step rows only when
 * they don't all fit, and then only when the playing row leaves the view. */
class GridFollowTest {
    @Test fun sixteenStepsOnAPhoneFollow() {
        assertTrue(GridFollow.follows(16, 40.0, 340.0))
    }

    @Test fun sixteenStepsThatFitStayPut() {
        assertFalse(GridFollow.follows(16, 52.0, 900.0))
    }

    @Test fun contentExactlyFillingTheViewportStaysPut() {
        val height = GridFollow.contentHeight(16, 52.0)
        assertEquals(870.0, height, 0.0)
        assertFalse(GridFollow.follows(16, 52.0, height))
    }

    @Test fun oneRowTooManyFollows() {
        assertTrue(GridFollow.follows(17, 52.0, 870.0))
    }

    @Test fun shortPatternOnAPhoneStaysPut() {
        assertFalse(GridFollow.follows(4, 40.0, 340.0))
    }

    @Test fun longPatternOnAnIPadFollows() {
        assertTrue(GridFollow.follows(64, 52.0, 900.0))
    }

    private fun anchor(step: Int, steps: Int = 16, rowHeight: Double = 52.0, viewport: Double = 850.0, scrollY: Double?) =
        GridFollow.anchor(step, steps, rowHeight, viewport, scrollY)

    @Test fun aRowAlreadyInFullViewLeavesTheGridAlone() {
        for (step in 0..14) assertNull("row $step is on screen", anchor(step, scrollY = 0.0))
    }

    @Test fun aClippedRowScrollsToTheTopSoTheRowsAfterItShow() {
        assertEquals(GridFollow.Anchor.TOP, anchor(15, scrollY = 0.0))
    }

    @Test fun theWrapToTheTopIsTheOtherMove() {
        val scrolled = GridFollow.contentHeight(16, 52.0) - 850
        for (step in 1..15) assertNull("row $step is on screen", anchor(step, scrollY = scrolled))
        assertEquals(GridFollow.Anchor.TOP, anchor(0, scrollY = scrolled))
    }

    @Test fun aPhoneFollowsAPageAtATime() {
        for (step in 0..7) assertNull(anchor(step, rowHeight = 40.0, viewport = 340.0, scrollY = 0.0))
        assertEquals(GridFollow.Anchor.TOP, anchor(8, rowHeight = 40.0, viewport = 340.0, scrollY = 0.0))
    }

    @Test fun aGridScrolledAwayFromThePlayheadIsBroughtBack() {
        assertEquals(GridFollow.Anchor.TOP, anchor(2, steps = 64, scrollY = 1500.0))
    }

    @Test fun aGridThatFitsNeverScrolls() {
        assertNull(anchor(15, viewport = 900.0, scrollY = 0.0))
        assertNull(anchor(15, viewport = 900.0, scrollY = null))
    }

    @Test fun withoutAnOffsetItCentresAsBefore() {
        assertEquals(GridFollow.Anchor.CENTER, anchor(3, scrollY = null))
    }

    @Test fun theScrollFinishesWithinHalfAStep() {
        assertEquals(0.0625, GridFollow.scrollDuration(120.0), 0.0001)
        assertEquals(0.025, GridFollow.scrollDuration(300.0), 0.0001)
        assertEquals(0.15, GridFollow.scrollDuration(40.0), 0.0001)
    }
}

/** Port of `GridPinningTests.swift`: the step numbers stay at the leading
 * edge while the grid scrolls sideways. */
class GridPinningTest {
    @Test fun labelFollowsHorizontalScroll() = assertEquals(120.0, GridPinning.labelOffset(120.0), 0.0)

    @Test fun labelStaysPutAtRest() = assertEquals(0.0, GridPinning.labelOffset(0.0), 0.0)

    @Test fun labelIgnoresLeadingRubberBand() = assertEquals(0.0, GridPinning.labelOffset(-30.0), 0.0)

    @Test fun scrolledBackingReachesBackOverTheRowInset() {
        assertEquals(-GridPinning.ROW_INSET, GridPinning.backing(28.0, 40.0).leading, 0.0)
    }

    @Test fun scrolledBackingSpansTheWholePinnedStrip() {
        for (gutter in listOf(28.0, 38.0)) {
            val backing = GridPinning.backing(gutter, 1.0)
            assertEquals(GridPinning.stripWidth(gutter), backing.width, 0.0)
            assertEquals(gutter + GridPinning.COLUMN_GAP, backing.leading + backing.width, 0.0)
        }
    }

    @Test fun backingAtRestIsJustTheGutter() {
        for (scrollX in listOf(0.0, -30.0)) {
            val backing = GridPinning.backing(28.0, scrollX)
            assertEquals(0.0, backing.leading, 0.0)
            assertEquals(28.0, backing.width, 0.0)
        }
    }

    @Test fun stripIsInsetGutterAndGap() = assertEquals(6.0 + 28 + 2, GridPinning.stripWidth(28.0), 0.0)

    @Test fun revealClearsTheBackingByTheRingsOuterHalf() {
        for (gutter in listOf(28.0, 38.0)) {
            val backing = GridPinning.backing(gutter, 1.0)
            val backingEnd = GridPinning.ROW_INSET + backing.leading + backing.width
            assertEquals(GridPinning.CURSOR_RING_WIDTH / 2, GridPinning.revealClearance(gutter) - backingEnd, 0.0)
        }
    }

    /** Where column [index] starts inside the scrolling row: what a reveal
     * scrolls to. The inset, the gutter, the gap after it, then whole columns. */
    @Test fun columnStartIsInsetGutterGapAndTheColumnsBefore() {
        assertEquals(6.0 + 28 + 2, GridPinning.columnStart(0, 28.0, 80.0), 0.0)
        assertEquals(6.0 + 28 + 2 + 2 * 82, GridPinning.columnStart(2, 28.0, 80.0), 0.0)
    }
}

/** Port of `GridRevealTests.swift`. */
class GridRevealTest {
    private val song = UUID.randomUUID()
    private val other = UUID.randomUUID()

    private fun target(old: Pair<UUID, Int>, new: Pair<UUID, Int>, selected: Int): GridReveal.Target? =
        GridReveal.target(
            GridReveal.Trigger(old.first, old.second, selected, RevealRequest()),
            GridReveal.Trigger(new.first, new.second, selected, RevealRequest()),
        )

    private fun target(tracks: Int, selected: Int, to: Int, selectedTo: Int, request: RevealRequest.Reason?): GridReveal.Target? {
        val before = RevealRequest(3, RevealRequest.Reason.UNDO_REDO)
        val after = request?.let { RevealRequest(4, it) } ?: before
        return GridReveal.target(
            GridReveal.Trigger(song, tracks, selected, before),
            GridReveal.Trigger(song, to, selectedTo, after),
        )
    }

    @Test fun addedTrackAtTheEndShowsTheTrailingEdge() =
        assertEquals(GridReveal.Target.TrailingEdge, target(song to 4, song to 5, 4))

    @Test fun undoneDeleteShowsTheRestoredSelectedTrack() =
        assertEquals(GridReveal.Target.Track(0), target(song to 7, song to 8, 0))

    @Test fun duplicateShowsTheCopyRatherThanTheEnd() =
        assertEquals(GridReveal.Target.Track(1), target(song to 6, song to 7, 1))

    @Test fun importedSongShowsItsSelectedTrack() =
        assertEquals(GridReveal.Target.Track(0), target(song to 4, other to 8, 0))

    @Test fun songSwitchWithTheSameTrackCountStillShowsTheSelectedTrack() =
        assertEquals(GridReveal.Target.Track(2), target(song to 8, other to 8, 2))

    @Test fun songSwitchOntoItsLastTrackShowsTheTrailingEdge() =
        assertEquals(GridReveal.Target.TrailingEdge, target(song to 4, other to 8, 7))

    @Test fun deleteLeavesTheScrollAlone() = assertNull(target(song to 8, song to 7, 2))

    @Test fun nothingChangedLeavesTheScrollAlone() = assertNull(target(song to 8, song to 8, 0))

    @Test fun undoThatMovesTheSelectionShowsTheRestoredTrack() =
        assertEquals(GridReveal.Target.Track(0), target(8, 7, 8, 0, RevealRequest.Reason.UNDO_REDO))

    @Test fun redoThatMovesTheSelectionOntoTheLastTrackShowsTheTrailingEdge() =
        assertEquals(GridReveal.Target.TrailingEdge, target(8, 0, 8, 7, RevealRequest.Reason.UNDO_REDO))

    @Test fun undoneAddShowsTheTrackSelectedBeforeIt() =
        assertEquals(GridReveal.Target.Track(2), target(8, 7, 7, 2, RevealRequest.Reason.UNDO_REDO))

    @Test fun undoThatKeepsTheSelectionLeavesTheScrollAlone() =
        assertNull(target(8, 3, 8, 3, RevealRequest.Reason.UNDO_REDO))

    @Test fun selectionChangeWithoutARequestLeavesTheScrollAlone() = assertNull(target(8, 7, 8, 0, null))

    @Test fun arrowMoveShowsTheNewColumnJustFarEnough() {
        assertEquals(GridReveal.Target.Nearest(3), target(8, 2, 8, 3, RevealRequest.Reason.CURSOR))
        assertEquals(GridReveal.Target.Nearest(2), target(8, 3, 8, 2, RevealRequest.Reason.CURSOR))
    }

    @Test fun arrowMoveOntoTheLastTrackStillScrollsJustFarEnough() =
        assertEquals(GridReveal.Target.Nearest(7), target(8, 6, 8, 7, RevealRequest.Reason.CURSOR))

    @Test fun arrowPressAtTheEndStillBringsTheCursorColumnBack() =
        assertEquals(GridReveal.Target.Nearest(7), target(8, 7, 8, 7, RevealRequest.Reason.CURSOR))

    // MARK: Where the scroll lands (ScrollViewReader's anchors, done by hand)

    /** Centred, then clamped to the scroll range. */
    @Test fun centredScrollClampsToTheRange() {
        assertEquals(0.0, GridReveal.centredScroll(columnStart = 36.0, columnWidth = 70.0, viewport = 400.0, maxScroll = 300.0), 0.0)
        assertEquals(300.0, GridReveal.centredScroll(columnStart = 600.0, columnWidth = 70.0, viewport = 400.0, maxScroll = 300.0), 0.0)
        assertEquals(135.0, GridReveal.centredScroll(columnStart = 300.0, columnWidth = 70.0, viewport = 400.0, maxScroll = 300.0), 0.0)
    }

    /** The least scroll that shows [columnStart - clearance, columnEnd]; none
     * when it already shows. */
    @Test fun nearestScrollMovesOnlyAsFarAsItMust() {
        // Already in view.
        assertEquals(50.0, GridReveal.nearestScroll(current = 50.0, frameStart = 100.0, frameEnd = 200.0, viewport = 400.0, maxScroll = 500.0), 0.0)
        // Off the trailing edge: scroll until its end meets the viewport's end.
        assertEquals(300.0, GridReveal.nearestScroll(current = 0.0, frameStart = 600.0, frameEnd = 700.0, viewport = 400.0, maxScroll = 500.0), 0.0)
        // Off the leading edge: scroll until its start meets the viewport's start.
        assertEquals(20.0, GridReveal.nearestScroll(current = 200.0, frameStart = 20.0, frameEnd = 120.0, viewport = 400.0, maxScroll = 500.0), 0.0)
    }
}
