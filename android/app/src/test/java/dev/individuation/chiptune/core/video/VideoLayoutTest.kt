package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.awt.Font
import java.awt.font.FontRenderContext
import java.io.File

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
        assertTrue(safe.maxY <= 1920 - CAPTION_REACH)
    }

    @Test fun theBottomBandClearsALongTikTokCaption() {
        assertTrue(VideoLayout.BOTTOM_BAND >= CAPTION_REACH)
        for (count in listOf(1, 4, 8)) {
            val layout = VideoLayout(count)
            listOf("tag" to VideoLayout.tagRect, "grid" to layout.gridRect, "cartridge" to layout.cartridgeRect)
                .forEach { (name, rect) -> assertTrue("$count / $name", rect.maxY <= 1920 - CAPTION_REACH) }
        }
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

    @Test fun theVisibleWindowClampsAtTheSongsEnds() {
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
        assertEquals(FrameRect(120.0, 240.0, 840.0, 1200.0), VideoLayout.safeRect)
        assertEquals(FrameRect(120.0, 1400.0, 420.0, 40.0), VideoLayout.tagRect)
        val layout = VideoLayout(4)
        assertEquals(FrameRect(120.0, 470.0, 840.0, 906.0), layout.gridRect)
        assertEquals(923.0, layout.playheadY, 0.0)
        assertEquals(180.0, layout.columnWidth, 0.0)
        assertEquals(85.0, VideoLayout(8).columnWidth, 0.0)
        assertEquals(25.0, VideoLayout(8).cellFontSize, 0.0)
        assertEquals(5.0 * 58 / 24, layout.cellRadius, 1e-9)
    }

    // MARK: Grid scroll

    private fun timeline(song: Song, loops: Int = 1): VideoTimeline =
        VideoTimeline(song, ExportOptions(loops, format = ExportOptions.Format.VIDEO))

    private fun bodyFrames(timeline: VideoTimeline): IntRange =
        0 until (timeline.bodySamples + VideoTimeline.SAMPLES_PER_FRAME - 1) / VideoTimeline.SAMPLES_PER_FRAME

    /** A 4-step pattern into a 16-step one, played twice: two pattern
     * changes and a loop wrap per pass. */
    private fun shortThenLong(tempo: Double = 150.0): VideoTimeline =
        timeline(TestSongs.twoPatterns(lengths = 4 to 16, repeats = 1 to 1, tempo = tempo), loops = 2)

    /** The grid scrolls as one piece across pattern changes and the loop
     * wrap: between two frames every row that is in both moves by the same
     * amount, up and never by more than a row, and the rows coming up next
     * are already there, from whichever pattern they belong to. */
    @Test fun rowsScrollContinuouslyAcrossPatternChangesAndTheLoopWrap() {
        val layout = VideoLayout(1)
        val timeline = shortThenLong()
        val total = timeline.stepsPerPass * timeline.loopCount
        var previous: GridFrame? = null
        for (frame in bodyFrames(timeline)) {
            val grid = GridFrame.of(layout, timeline, frame) ?: return fail("frame $frame has no grid")
            val steps = grid.rows.map { it.globalStep }
            assertEquals("frame $frame skips a row", (steps.first()..steps.last()).toList(), steps)
            for (ahead in 1..3) {
                if (grid.soundingStep + ahead < total) {
                    assertTrue("frame $frame is missing the row $ahead ahead", grid.soundingStep + ahead in steps)
                }
            }
            if (grid.soundingStep > 0) assertTrue("frame $frame is missing the row behind", grid.soundingStep - 1 in steps)
            for (row in grid.rows) {
                val at = timeline.positionOfStep(row.globalStep)
                assertEquals("frame $frame / ${row.globalStep}", at?.pattern, row.pattern)
                assertEquals("frame $frame / ${row.globalStep} is numbered by its own pattern", at?.step, row.step)
            }
            assertEquals("frame $frame header", timeline.position(frame), grid.playing)
            previous?.let { before ->
                val was = before.rows.associate { it.globalStep to it.centerY }
                val moves = grid.rows.mapNotNull { row -> was[row.globalStep]?.let { row.centerY - it } }
                assertTrue("frame $frame shares no row with the frame before", moves.isNotEmpty())
                val first = moves.first()
                for (move in moves) assertEquals("frame $frame tears", first, move, 0.001)
                assertTrue("frame $frame scrolls back down", first <= 0.001)
                assertTrue("frame $frame jumps more than a row", first >= -layout.rowPitch - 0.001)
            }
            previous = grid
        }
    }

    /** Nothing is drawn before the song's first step or past its last. */
    @Test fun rowsStopAtTheSongsEnds() {
        val layout = VideoLayout(1)
        val timeline = shortThenLong()
        val total = timeline.stepsPerPass * timeline.loopCount
        for (frame in 0 until timeline.totalFrames) {
            for (row in GridFrame.of(layout, timeline, frame)?.rows.orEmpty()) {
                assertTrue("frame $frame / ${row.globalStep}", row.globalStep in 0 until total)
            }
        }
    }

    /** The row whose sound is playing stays inside the highlighted band on
     * every frame of its step, at slow, middling, fast and uneven tempos. */
    @Test fun theSoundingRowStaysInsideTheBandForItsWholeStep() {
        for (count in listOf(1, 8)) {
            val layout = VideoLayout(count)
            for (tempo in listOf(40.0, 60.0, 97.0, 137.0, 150.0, 300.0)) {
                val timeline = shortThenLong(tempo)
                for (frame in bodyFrames(timeline)) {
                    val grid = GridFrame.of(layout, timeline, frame)
                    val row = grid?.rows?.firstOrNull { it.globalStep == grid.soundingStep }
                    if (grid == null || row == null) {
                        fail("$tempo BPM frame $frame doesn't draw its sounding row"); return
                    }
                    assertEquals(timeline.sample(frame) / timeline.samplesPerStep, grid.soundingStep)
                    val rect = layout.rowRect(row.centerY)
                    assertTrue("$count tracks, $tempo BPM frame $frame: $rect outside ${grid.band}", grid.band.contains(rect))
                    assertTrue("$tempo BPM frame $frame", grid.band.height <= 2 * layout.rowPitch + 0.001)
                }
            }
        }
    }

    /** For most of its step the sounding row sits still on the playhead,
     * with the band its own size; the grid only moves on in the step's last
     * part. */
    @Test fun theSoundingRowHoldsOnThePlayheadForMostOfItsStep() {
        val layout = VideoLayout(4)
        val timeline = shortThenLong(tempo = 60.0)
        for (frame in bodyFrames(timeline)) {
            val into = (timeline.sample(frame) % timeline.samplesPerStep).toDouble() / timeline.samplesPerStep
            if (into >= 0.65) continue
            val grid = GridFrame.of(layout, timeline, frame) ?: continue
            val row = grid.rows.firstOrNull { it.globalStep == grid.soundingStep } ?: continue
            assertEquals("frame $frame", layout.playheadY, row.centerY, 0.001)
            assertEquals("frame $frame", layout.playheadRowRect, grid.band)
        }
    }

    /** In the ring-out the grid rests on the last step and the band fades. */
    @Test fun theGridRestsOnTheLastStepInTheTail() {
        val layout = VideoLayout(4)
        val timeline = shortThenLong()
        val last = timeline.stepsPerPass * timeline.loopCount - 1
        var light = 1.0
        for (frame in bodyFrames(timeline).last + 1 until timeline.totalFrames) {
            val grid = GridFrame.of(layout, timeline, frame) ?: return fail("frame $frame")
            assertEquals(last, grid.soundingStep)
            assertEquals(layout.playheadY, grid.rows.first { it.globalStep == last }.centerY, 0.0)
            assertEquals(layout.playheadRowRect, grid.band)
            assertTrue(grid.bandLight <= light)
            light = grid.bandLight
        }
        assertTrue(light < 0.1)
    }

    // MARK: Cartridge

    /** A tall cartridge, centred, with room left round it for its shadow. */
    @Test fun theCartridgeSitsInsideTheSafeArea() {
        for (count in listOf(1, 4, 8)) {
            val cart = VideoLayout(count).cartridgeRect
            assertTrue("$count", VideoLayout.safeRect.contains(cart))
            assertTrue("$count", cart.height > cart.width)
            assertEquals(VideoLayout.safeRect.midX, cart.midX, 0.5)
        }
    }

    /** The outline runs clockwise from the top-left corner; its second and
     * third points are the ends of the diagonal cut off the top-right
     * corner, which stays above the label. */
    @Test fun theNotchIsCutFromTheTopRightCorner() {
        val layout = VideoLayout(4)
        val cart = layout.cartridgeRect
        val outline = layout.cartridgeOutline
        assertEquals(5, outline.size)
        assertEquals(FramePoint(cart.minX, cart.minY), outline[0])
        assertEquals(FramePoint(cart.maxX - layout.cartridgeNotch, cart.minY), outline[1])
        assertEquals(FramePoint(cart.maxX, cart.minY + layout.cartridgeNotch), outline[2])
        assertEquals(FramePoint(cart.maxX, cart.maxY), outline[3])
        assertEquals(FramePoint(cart.minX, cart.maxY), outline[4])
        assertTrue(layout.cartridgeNotch > layout.cartridgeCornerRadius)
        assertTrue(outline[1].x > cart.midX)
        assertTrue(outline[2].y < layout.labelRecessRect.minY)
    }

    /** Grip ridges stack across the band above the label, inside the body
     * and clear of the notch's diagonal. */
    @Test fun gripRidgesRunAcrossTheTopBand() {
        val layout = VideoLayout(4)
        val cart = layout.cartridgeRect
        val ridges = layout.gripRidgeRects
        assertTrue(ridges.size >= 4)
        var previous: FrameRect? = null
        ridges.forEachIndexed { index, ridge ->
            assertTrue("$index", cart.contains(ridge))
            assertTrue("$index", ridge.minY > cart.minY)
            assertTrue("$index", ridge.maxY < layout.labelRecessRect.minY)
            assertTrue("$index", ridge.width > cart.width / 2)
            // The top-right corner is inside the body, not in the cut.
            assertTrue("$index", ridge.maxX - (cart.maxX - layout.cartridgeNotch) <= ridge.minY - cart.minY)
            previous?.let { assertTrue("$index", it.maxY < ridge.minY) }
            previous = ridge
        }
    }

    /** The label sits in a recess that takes most of the body, with a bevel
     * of plastic all round it. */
    @Test fun theLabelIsInsetInsideTheBody() {
        val layout = VideoLayout(4)
        val cart = layout.cartridgeRect
        val recess = layout.labelRecessRect
        val label = layout.labelRect
        assertTrue(cart.insetBy(24.0, 24.0).contains(recess))
        assertTrue(recess.insetBy(8.0, 8.0).contains(label))
        assertTrue(label.width * label.height > cart.width * cart.height / 2)
    }

    @Test fun theTitleBarsAndProgressSitInsideTheLabel() {
        for (count in listOf(1, 4, 8)) {
            val layout = VideoLayout(count)
            val label = layout.labelRect
            listOf(
                "title" to layout.coverTitleRect, "meta" to layout.coverMetaRect,
                "progress" to layout.coverProgressRect, "times" to layout.coverTimeRect,
            ).forEach { (name, rect) -> assertTrue("$count / $name", label.contains(rect)) }
            var previous: FrameRect? = null
            for (track in 0 until count) {
                val bar = layout.coverBarRect(track)
                assertTrue("$count / $track", label.contains(bar))
                assertTrue(bar.height > 200)
                assertTrue(bar.width >= 40)
                previous?.let { assertTrue(it.maxX < bar.minX) }
                previous = bar
            }
            assertTrue(layout.coverMetaRect.maxY < layout.coverBarRect(0).minY)
            assertTrue(layout.coverBarRect(0).maxY < layout.coverBarLabelY - 20)
            assertTrue(layout.coverBarLabelY + 20 < layout.coverProgressRect.minY)
        }
    }

    /** An imported name keeps any line breaks it was saved with. Drawn as
     * they are, the Grid header's one line would run "A" and "B" together,
     * and the Cartridge's two lines would go to the breaks rather than to the
     * width the tempo line is placed for. Both frames wrap the title by width
     * alone. */
    @Test fun aTitlesLineBreaksAreDrawnAsSpaces() {
        assertEquals("A B", VideoLayout.displayTitle("A\nB"))
        assertEquals("A B", VideoLayout.displayTitle("A\r\n\nB"))
        assertEquals("A B C", VideoLayout.displayTitle("A   B\u0085C"))
        assertEquals("Song", VideoLayout.displayTitle("Song\n"))
        assertEquals("Two  spaces", VideoLayout.displayTitle("Two  spaces"))
    }

    /** The moulded arrow sits in the plastic under the label. */
    @Test fun theTriangleSitsBetweenTheLabelAndTheBodysBottom() {
        val layout = VideoLayout(4)
        val triangle = layout.triangleRect
        assertTrue(triangle.minY > layout.labelRecessRect.maxY)
        assertTrue(triangle.maxY < layout.cartridgeRect.maxY)
        assertEquals(layout.cartridgeRect.midX, triangle.midX, 0.5)
        assertTrue(triangle.width > 0)
        assertTrue(triangle.height > 0)
    }

    /** The numbers iOS's VideoLayoutTests pins too, so both platforms draw
     * the same cartridge. */
    @Test fun theCartridgeGeometryMatchesIos() {
        val layout = VideoLayout(4)
        assertEquals(FrameRect(150.0, 252.0, 780.0, 1100.0), layout.cartridgeRect)
        assertEquals(96.0, layout.cartridgeNotch, 0.0)
        assertEquals(28.0, layout.cartridgeCornerRadius, 0.0)
        assertEquals(5, layout.gripRidgeRects.size)
        assertEquals(FrameRect(214.0, 286.0, 580.0, 8.0), layout.gripRidgeRects.firstOrNull())
        assertEquals(FrameRect(202.0, 402.0, 676.0, 774.0), layout.labelRecessRect)
        assertEquals(FrameRect(216.0, 416.0, 648.0, 746.0), layout.labelRect)
        assertEquals(FrameRect(508.0, 1236.0, 64.0, 56.0), layout.triangleRect)
        assertEquals(FrameRect(256.0, 456.0, 568.0, 190.0), layout.coverTitleRect)
        assertEquals(FrameRect(256.0, 1062.0, 568.0, 14.0), layout.coverProgressRect)
        assertEquals(FrameRect(256.0, 752.0, 124.0, 220.0), layout.coverBarRect(0))
        assertEquals(FrameRect(774.0, 752.0, 50.0, 220.0), VideoLayout(8).coverBarRect(7))
    }

    // MARK: Track names

    /** Width of [text] as the drawer draws it: JetBrains Mono Bold, measured
     * with the JVM's own font engine from the app's font file. */
    private fun width(text: String, size: Double): Double {
        val font = BOLD.deriveFont(size.toFloat())
        return font.getStringBounds(text, FontRenderContext(null, true, true)).width
    }

    /** Track names side by side: each within its own slot, none touching the
     * next, a default name ("PU1 A") whole at the size drawn, and more space
     * between two names than the space inside one, so "PU1 A PU2 A" reads as
     * two names rather than one run. */
    private fun assertNamesStaySeparate(rects: List<FrameRect>, centres: List<Double>, size: Double, what: String) {
        val name = width("PU1 A", size)
        val space = width(" ", size)
        rects.forEachIndexed { index, rect ->
            assertEquals("$what / $index centred", centres[index], rect.midX, 0.5)
            assertTrue("$what / $index truncates a default name", name <= rect.width)
            if (index > 0) {
                assertTrue("$what / $index overlaps", rects[index - 1].maxX <= rect.minX)
                val textGap = (centres[index] - name / 2) - (centres[index - 1] + name / 2)
                assertTrue("$what / $index runs into the one before", textGap > 1.5 * space)
            }
        }
    }

    @Test fun cartridgeTrackNamesStaySeparateForOneToEightTracks() {
        for (count in 1..8) {
            val layout = VideoLayout(count)
            val rects = (0 until count).map { layout.coverBarLabelRect(it) }
            val centres = (0 until count).map { layout.coverBarRect(it).midX }
            assertNamesStaySeparate(rects, centres, layout.coverLabelFontSize, "cartridge $count")
            for (rect in rects) assertTrue("$count", layout.labelRect.contains(rect))
        }
    }

    @Test fun gridColumnNamesStaySeparateForOneToEightTracks() {
        for (count in 1..8) {
            val layout = VideoLayout(count)
            val rects = (0 until count).map { layout.columnHeaderRect(it) }
            val centres = (0 until count).map { layout.cellRect(it, 900.0).midX }
            assertNamesStaySeparate(rects, centres, layout.columnHeaderFontSize, "grid $count")
            for (rect in rects) assertTrue("$count", VideoLayout.safeRect.contains(rect))
        }
    }

    /** Few tracks keep the full-size names; only crowded rows shrink them. */
    @Test fun namesOnlyShrinkWhenCrowded() {
        assertEquals(26.0, VideoLayout(4).coverLabelFontSize, 0.0)
        assertEquals(26.0, VideoLayout(4).columnHeaderFontSize, 0.0)
        assertTrue(VideoLayout(8).coverLabelFontSize < 26)
        assertTrue(VideoLayout(8).columnHeaderFontSize < 26)
    }

    /** iOS's sizes: 18px on an eight-track cartridge, 23px over eight columns. */
    @Test fun crowdedNameSizesMatchIos() {
        assertEquals(18.0, VideoLayout(8).coverLabelFontSize, 0.0)
        assertEquals(23.0, VideoLayout(8).columnHeaderFontSize, 0.0)
    }

    // MARK: Tag

    @Test fun theTagIsInsideTheFrameAndClearOfTheBottomOverlays() {
        val tag = VideoLayout.tagRect
        assertTrue(frame.contains(tag))
        assertTrue(tag.maxY <= 1920 - CAPTION_REACH)
        assertTrue(tag.minY >= 1920 * 0.12)
        assertTrue(tag.minX >= VideoLayout.safeRect.minX)
        assertTrue(tag.maxY <= VideoLayout.HEIGHT - VideoLayout.BOTTOM_BAND)
    }

    /** "Made with Chiptune" sits under the cartridge, not on it. */
    @Test fun theTagSitsBelowTheCartridge() {
        for (count in listOf(1, 4, 8)) {
            assertTrue(VideoLayout.tagRect.minY > VideoLayout(count).cartridgeRect.maxY)
        }
    }

    @Test fun theTagOverlapsNeitherStylesContent() {
        val layout = VideoLayout(8)
        assertFalse(VideoLayout.tagRect.intersects(layout.gridRect))
        assertFalse(VideoLayout.tagRect.intersects(layout.cartridgeRect))
    }

    private companion object {
        /** TikTok's caption, account name and sound line can stack up to
         * about 480px from the bottom of a 1920px frame on a long caption. */
        const val CAPTION_REACH = 480.0

        /** The drawer's bold face; unit tests run from the module directory. */
        val BOLD: Font = Font.createFont(Font.TRUETYPE_FONT, File("src/main/res/font/jetbrains_mono_bold.ttf"))
    }
}
