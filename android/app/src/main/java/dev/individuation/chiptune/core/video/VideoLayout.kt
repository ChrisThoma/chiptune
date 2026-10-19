package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.model.Chip
import kotlin.math.ceil
import kotlin.math.floor

/** A rectangle in video pixels, origin top left, y running down. CGRect's
 * shape, kept pure so the layout can be tested off-device. */
data class FrameRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val minY: Double get() = y
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2

    fun contains(other: FrameRect): Boolean =
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY

    /** CGRect's `intersects`: a shared edge alone doesn't count. */
    fun intersects(other: FrameRect): Boolean =
        other.minX < maxX && other.maxX > minX && other.minY < maxY && other.maxY > minY
}

/**
 * Where everything goes in a 1080x1920 video frame, for both styles. Port of
 * `Sources/Video/VideoLayout.swift`: pure geometry, in pixels with the
 * origin at the top left, the same numbers the iOS renderer draws with.
 *
 * Reels, TikTok and Shorts all lay their own chrome over a 9:16 video: a
 * title or tabs along the top, and the caption, account name and buttons
 * across the bottom fifth, with a column of buttons up the right edge.
 * Anything that carries meaning stays inside [safeRect]; only the background
 * runs to the edges.
 */
class VideoLayout(trackCount: Int) {
    val trackCount: Int = minOf(maxOf(trackCount, 1), Chip.MAX_TRACKS)

    // MARK: Grid

    /** Song title and the pattern/step readout. */
    val headerRect: FrameRect get() = FrameRect(safeRect.minX, safeRect.minY, safeRect.width, 150.0)
    val titleFontSize = 56.0
    val subtitleFontSize = 34.0

    val columnHeaderHeight = 52.0
    /** Centre line of the track names above the columns. */
    val columnHeaderY: Double get() = headerRect.maxY + 16 + columnHeaderHeight / 2
    val columnHeaderFontSize = 26.0

    /** Where rows are drawn; they are clipped to it as they scroll. */
    val gridRect: FrameRect
        get() {
            val top = columnHeaderY + columnHeaderHeight / 2 + 12
            return FrameRect(safeRect.minX, top, safeRect.width, contentBottom - top)
        }

    /** The fixed playing row's centre. The grid scrolls under it. */
    val playheadY: Double get() = gridRect.midY

    val rowPitch = 66.0
    val cellHeight = 58.0
    val gutterWidth = 76.0
    val gap = 10.0
    /** The app's 5pt cell radius on a cell of about 24pt, kept in proportion
     * at video size. */
    val cellRadius: Double get() = CELL_RADIUS * cellHeight / 24
    /** A single column wider than this reads as a bar, not a grid. */
    val maxColumnWidth = 180.0

    /** Every column is the same width, sized so eight fit the safe area with
     * the step-number gutter. */
    val columnWidth: Double
        get() {
            val available = safeRect.width - gutterWidth - gap - gap * (this.trackCount - 1)
            return minOf(maxColumnWidth, floor(available / this.trackCount))
        }

    /** Note names shrink with the columns so "C#4" still fits eight across. */
    val cellFontSize: Double get() = minOf(30.0, floor(columnWidth * 0.3))
    val gutterFontSize = 26.0

    /** Gutter plus columns, centred in the safe area. */
    private val gridContentWidth: Double
        get() = gutterWidth + gap + this.trackCount * columnWidth + (this.trackCount - 1) * gap
    private val gridOriginX: Double get() = safeRect.midX - gridContentWidth / 2

    fun gutterRect(centerY: Double): FrameRect =
        FrameRect(gridOriginX, centerY - cellHeight / 2, gutterWidth, cellHeight)

    fun cellRect(track: Int, centerY: Double): FrameRect {
        val x = gridOriginX + gutterWidth + gap + track * (columnWidth + gap)
        return FrameRect(x, centerY - cellHeight / 2, columnWidth, cellHeight)
    }

    /** The highlight behind the playing row, spanning gutter and columns. */
    val playheadRowRect: FrameRect
        get() = FrameRect(gridOriginX - 12, playheadY - rowPitch / 2, gridContentWidth + 24, rowPitch)

    /** Where [step]'s row is centred when the song is [position] steps into
     * the pattern (fraction included). At `position == step` that is the
     * playhead row, so a note reaches it on the frame its sound starts. */
    fun rowCenterY(step: Int, position: Double): Double = playheadY + (step - position) * rowPitch

    /** The steps of a [patternLength]-step pattern with any part of their row
     * inside [gridRect] at [position]. Only the current pattern is drawn, so
     * the window stops at its first and last steps rather than showing the
     * neighbours. */
    fun visibleSteps(position: Double, patternLength: Int): IntRange {
        val reach = (gridRect.height / 2 + cellHeight / 2) / rowPitch
        // Strictly inside: a row whose edge only meets the grid's edge shows nothing.
        val lower = floor(position - reach).toInt() + 1
        val upper = ceil(position + reach).toInt() - 1
        val last = maxOf(patternLength - 1, 0)
        val lo = minOf(maxOf(lower, 0), last)
        return lo..maxOf(minOf(upper, last), lo)
    }

    // MARK: Cover

    /** The cartridge-style card everything in the Cover style sits on. */
    val coverCardRect: FrameRect
        get() = FrameRect(safeRect.minX, safeRect.minY, safeRect.width, contentBottom - safeRect.minY)
    val coverPadding = 48.0
    val coverTitleFontSize = 76.0
    val coverMetaFontSize = 36.0
    val coverLabelFontSize = 26.0

    /** Up to two lines of title. */
    val coverTitleRect: FrameRect
        get() {
            val card = coverCardRect
            return FrameRect(card.minX + coverPadding, card.minY + 56, card.width - 2 * coverPadding, 190.0)
        }

    /** Tempo and length. */
    val coverMetaRect: FrameRect
        get() = FrameRect(coverTitleRect.minX, coverTitleRect.maxY + 8, coverTitleRect.width, 48.0)

    val coverProgressRect: FrameRect
        get() {
            val card = coverCardRect
            return FrameRect(card.minX + coverPadding, card.maxY - 110, card.width - 2 * coverPadding, 14.0)
        }

    /** Elapsed and total time, under the progress bar. */
    val coverTimeRect: FrameRect
        get() = FrameRect(coverProgressRect.minX, coverProgressRect.maxY + 14, coverProgressRect.width, 40.0)

    private val coverBarGap = 24.0
    private val coverBarsTop: Double get() = coverMetaRect.maxY + 60
    /** Room under the bars for each track's name. */
    private val coverBarsBottom: Double get() = coverProgressRect.minY - 100
    private val coverBarWidth: Double
        get() {
            val available = coverCardRect.width - 2 * coverPadding - coverBarGap * (this.trackCount - 1)
            return minOf(140.0, floor(available / this.trackCount))
        }

    /** The full extent of a track's bar. The drawer fills it from the bottom
     * by the track's pulse. */
    fun coverBarRect(track: Int): FrameRect {
        val total = this.trackCount * coverBarWidth + (this.trackCount - 1) * coverBarGap
        val x = coverCardRect.midX - total / 2 + track * (coverBarWidth + coverBarGap)
        return FrameRect(x, coverBarsTop, coverBarWidth, coverBarsBottom - coverBarsTop)
    }

    /** Track names sit centred under their bars. */
    val coverBarLabelY: Double get() = coverBarsBottom + 40

    companion object {
        const val WIDTH = 1080
        const val HEIGHT = 1920
        /** Kept clear at the top: 12.5% of the height. */
        const val TOP_BAND = 240.0
        /** Kept clear at the bottom: about 21%, where the caption sits. */
        const val BOTTOM_BAND = 400.0
        /** Wide enough on the right to clear TikTok's button column; the same
         * on the left so the content stays centred. */
        const val SIDE_MARGIN = 120.0
        /** iOS `Theme.cellRadius` and Android `ChipRadii.cell`. */
        const val CELL_RADIUS = 5.0
        /** iOS `Theme.panelRadius` and Android `ChipRadii.panel`. */
        const val PANEL_RADIUS = 8.0

        val safeRect: FrameRect =
            FrameRect(SIDE_MARGIN, TOP_BAND, WIDTH - 2 * SIDE_MARGIN, HEIGHT - TOP_BAND - BOTTOM_BAND)

        const val TAG_HEIGHT = 40.0
        const val TAG_FONT_SIZE = 28.0

        /** "Made with Chiptune", in the bottom-left corner of the safe area:
         * low enough to stay out of the way, high enough to stay above the
         * caption. */
        val tagRect: FrameRect = FrameRect(safeRect.minX, safeRect.maxY - TAG_HEIGHT, 420.0, TAG_HEIGHT)

        /** The bottom of everything but the tag. */
        val contentBottom: Double = tagRect.minY - 24
    }
}
