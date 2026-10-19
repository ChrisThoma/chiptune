package dev.individuation.chiptune.core.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `VideoLayoutTests.swift`: frame geometry for both video styles.
 * Reels, TikTok and Shorts lay their own buttons and captions over the top
 * and bottom of a 9:16 video, so everything that carries meaning has to sit
 * between those bands. */
class VideoLayoutTest {

    private val frame = FrameRect(0.0, 0.0, 1080.0, 1920.0)

    @Test fun theFrameIsPortrait1080By1920() {
        assertEquals(1080, VideoLayout.WIDTH)
        assertEquals(1920, VideoLayout.HEIGHT)
    }

    @Test fun theSafeAreaClearsTheOverlayBands() {
        val safe = VideoLayout.safeRect
        assertTrue(frame.contains(safe))
        assertTrue(safe.minY >= 1920 * 0.12)
        assertTrue(safe.maxY <= 1920 * 0.80)
    }

    // MARK: Grid

    @Test fun columnsFitTheSafeWidthForOneFourAndEightTracks() {
        val safe = VideoLayout.safeRect
        for (count in listOf(1, 4, 8)) {
            val layout = VideoLayout(count)
            assertTrue("$count", layout.columnWidth > 0)
            assertTrue("$count", layout.gutterRect(900.0).minX >= safe.minX)
            var previous: FrameRect? = null
            for (track in 0 until count) {
                val cell = layout.cellRect(track, 900.0)
                assertTrue("$count / $track", cell.minX >= safe.minX)
                assertTrue("$count / $track", cell.maxX <= safe.maxX)
                previous?.let { assertTrue("$count / $track overlaps", it.maxX < cell.minX) }
                previous = cell
            }
        }
    }

    /** A lone track shouldn't stretch into one huge bar. */
    @Test fun aSingleColumnIsCapped() {
        assertTrue(VideoLayout(1).columnWidth < VideoLayout.safeRect.width / 2)
    }

    @Test fun eightColumnsLeaveRoomForANoteName() {
        assertTrue(VideoLayout(8).columnWidth >= 70)
    }

    /** The track count is clamped like the app's, 1 to 8. */
    @Test fun theTrackCountIsClamped() {
        assertEquals(1, VideoLayout(0).trackCount)
        assertEquals(8, VideoLayout(12).trackCount)
    }

    /** The step that is playing always sits on the same row; the grid moves
     * under it. */
    @Test fun thePlayingStepIsAlwaysOnThePlayheadRow() {
        for (count in listOf(1, 4, 8)) {
            val layout = VideoLayout(count)
            for (step in listOf(0, 7, 63)) {
                assertEquals(layout.playheadY, layout.rowCenterY(step, step.toDouble()), 0.0)
            }
            assertEquals(layout.playheadY + layout.rowPitch / 2, layout.rowCenterY(4, 3.5), 1e-9)
        }
        val layout = VideoLayout(4)
        assertEquals(layout.gridRect.midY, layout.playheadY, 0.5)
    }

    @Test fun theVisibleWindowClampsAtThePatternsEnds() {
        val layout = VideoLayout(4)
        assertEquals(0, layout.visibleSteps(0.0, 16).first)
        assertEquals(15, layout.visibleSteps(15.0, 16).last)
        val middle = layout.visibleSteps(32.0, 64)
        assertTrue(middle.first > 0)
        assertTrue(middle.last < 63)
        assertTrue(32 in middle)
    }

    /** Every row in the window at least touches the grid area, and the rows
     * just outside it don't, so nothing visible is skipped. */
    @Test fun theWindowCoversTheGridAreaAndNoMore() {
        val layout = VideoLayout(4)
        val window = layout.visibleSteps(32.0, 64)
        val grid = layout.gridRect
        for (step in listOf(window.first, window.last)) {
            val y = layout.rowCenterY(step, 32.0)
            assertTrue("$step", y - layout.cellHeight / 2 < grid.maxY)
            assertTrue("$step", y + layout.cellHeight / 2 > grid.minY)
        }
        for (step in listOf(window.first - 2, window.last + 2)) {
            val y = layout.rowCenterY(step, 32.0)
            assertTrue("$step", y + layout.cellHeight / 2 <= grid.minY || y - layout.cellHeight / 2 >= grid.maxY)
        }
    }

    /** Between steps the grid has scrolled part of a row, so the window
     * follows the fraction: the row coming up from below appears before its
     * step starts. */
    @Test fun theWindowFollowsAScrollBetweenSteps() {
        val layout = VideoLayout(4)
        val grid = layout.gridRect
        for (position in listOf(32.25, 32.5, 32.95)) {
            val window = layout.visibleSteps(position, 64)
            for (step in listOf(window.first, window.last)) {
                val y = layout.rowCenterY(step, position)
                assertTrue("$position / $step", y - layout.cellHeight / 2 < grid.maxY)
                assertTrue("$position / $step", y + layout.cellHeight / 2 > grid.minY)
            }
            val below = layout.rowCenterY(window.last + 1, position)
            assertTrue("$position", below - layout.cellHeight / 2 >= grid.maxY)
        }
    }

    @Test fun theGridSitsInsideTheSafeArea() {
        val safe = VideoLayout.safeRect
        val layout = VideoLayout(8)
        assertTrue(safe.contains(layout.gridRect))
        assertTrue(safe.contains(layout.headerRect))
        assertTrue(layout.headerRect.maxY <= layout.columnHeaderY - layout.columnHeaderHeight / 2)
        assertTrue(layout.columnHeaderY + layout.columnHeaderHeight / 2 <= layout.gridRect.minY)
    }

    /** The same numbers as iOS, so the two platforms' frames line up. */
    @Test fun theGeometryMatchesIos() {
        assertEquals(FrameRect(120.0, 240.0, 840.0, 1280.0), VideoLayout.safeRect)
        assertEquals(FrameRect(120.0, 1480.0, 420.0, 40.0), VideoLayout.tagRect)
        val layout = VideoLayout(4)
        assertEquals(FrameRect(120.0, 470.0, 840.0, 986.0), layout.gridRect)
        assertEquals(963.0, layout.playheadY, 0.0)
        assertEquals(180.0, layout.columnWidth, 0.0)
        assertEquals(85.0, VideoLayout(8).columnWidth, 0.0)
        assertEquals(25.0, VideoLayout(8).cellFontSize, 0.0)
        assertEquals(5.0 * 58 / 24, layout.cellRadius, 1e-9)
    }

    // MARK: Cover

    @Test fun coverBarsSitSideBySideInsideTheCard() {
        for (count in listOf(1, 4, 8)) {
            val layout = VideoLayout(count)
            assertTrue(VideoLayout.safeRect.contains(layout.coverCardRect))
            var previous: FrameRect? = null
            for (track in 0 until count) {
                val bar = layout.coverBarRect(track)
                assertTrue("$count / $track", layout.coverCardRect.contains(bar))
                assertTrue(bar.height > 200)
                previous?.let { assertTrue(it.maxX < bar.minX) }
                previous = bar
            }
            assertTrue(layout.coverCardRect.contains(layout.coverProgressRect))
            assertTrue(layout.coverTitleRect.maxY < layout.coverBarRect(0).minY)
            assertTrue(layout.coverBarRect(0).maxY < layout.coverProgressRect.minY)
        }
    }

    // MARK: Tag

    @Test fun theTagIsInsideTheFrameAndClearOfTheBottomOverlays() {
        val tag = VideoLayout.tagRect
        assertTrue(frame.contains(tag))
        assertTrue(tag.maxY <= 1920 * 0.80)
        assertTrue(tag.minY >= 1920 * 0.12)
        assertTrue(tag.minX >= VideoLayout.safeRect.minX)
    }

    @Test fun theTagOverlapsNeitherStylesContent() {
        val layout = VideoLayout(8)
        assertFalse(VideoLayout.tagRect.intersects(layout.gridRect))
        assertFalse(VideoLayout.tagRect.intersects(layout.coverCardRect))
    }
}
