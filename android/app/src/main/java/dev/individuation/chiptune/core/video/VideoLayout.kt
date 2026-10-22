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

    /** CGRect's `insetBy`: shrunk by [dx] on each side and [dy] top and bottom. */
    fun insetBy(dx: Double, dy: Double): FrameRect = FrameRect(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

    fun offsetBy(dx: Double, dy: Double): FrameRect = FrameRect(x + dx, y + dy, width, height)

    /** CGRect's `union`: the smallest rectangle holding both. */
    fun union(other: FrameRect): FrameRect {
        val left = minOf(minX, other.minX)
        val top = minOf(minY, other.minY)
        return FrameRect(left, top, maxOf(maxX, other.maxX) - left, maxOf(maxY, other.maxY) - top)
    }
}

/** A point in video pixels, origin top left. CGPoint's shape. */
data class FramePoint(val x: Double, val y: Double)

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
    /** Full size, or smaller when eight columns crowd the names together. */
    val columnHeaderFontSize: Double get() = nameFontSize(columnWidth + gap)

    /** Where a track's name is drawn above its column: no wider than the
     * column, so the drawer truncates a long name rather than letting it run
     * into the next. */
    fun columnHeaderRect(track: Int): FrameRect {
        val cell = cellRect(track, columnHeaderY)
        return FrameRect(cell.minX, columnHeaderY - columnHeaderHeight / 2, cell.width, columnHeaderHeight)
    }

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

    /** A whole row's cells, gutter to last column. */
    fun rowRect(centerY: Double): FrameRect = FrameRect(gridOriginX, centerY - cellHeight / 2, gridContentWidth, cellHeight)

    /** The highlight behind the playing row, spanning gutter and columns. */
    val playheadRowRect: FrameRect
        get() = FrameRect(gridOriginX - 12, playheadY - rowPitch / 2, gridContentWidth + 24, rowPitch)

    /** Where [step]'s row is centred when the grid shows [position] (steps
     * since the start of the body, fraction included) on the playhead row. */
    fun rowCenterY(step: Int, position: Double): Double = playheadY + (step - position) * rowPitch

    /** The steps, counted across the whole body, with any part of their row
     * inside [gridRect] at [position]. The window stops at the song's first
     * and last steps: nothing is drawn before the start or past the end. */
    fun visibleSteps(position: Double, stepCount: Int): IntRange {
        val reach = (gridRect.height / 2 + cellHeight / 2) / rowPitch
        // Strictly inside: a row whose edge only meets the grid's edge shows nothing.
        val lower = floor(position - reach).toInt() + 1
        val upper = ceil(position + reach).toInt() - 1
        val last = maxOf(stepCount - 1, 0)
        val lo = minOf(maxOf(lower, 0), last)
        return lo..maxOf(minOf(upper, last), lo)
    }

    // MARK: Cartridge (the Cover style)

    /** The cartridge's body: a tall slab of grey plastic, centred, a little
     * inside the safe area so its shadow has room. */
    val cartridgeRect: FrameRect
        get() {
            val width = 780.0
            val top = safeRect.minY + 12
            return FrameRect(safeRect.midX - width / 2, top, width, contentBottom - 24 - top)
        }
    /** The legs of the diagonal cut off the top-right corner. */
    val cartridgeNotch = 96.0
    /** The other three corners are rounded this much. */
    val cartridgeCornerRadius = 28.0

    /** The body's corners, clockwise from the top left, with the notch's two
     * ends in place of the top-right corner. The drawer rounds the three
     * square corners by [cartridgeCornerRadius]. */
    val cartridgeOutline: List<FramePoint>
        get() {
            val cart = cartridgeRect
            return listOf(
                FramePoint(cart.minX, cart.minY),
                FramePoint(cart.maxX - cartridgeNotch, cart.minY),
                FramePoint(cart.maxX, cart.minY + cartridgeNotch),
                FramePoint(cart.maxX, cart.maxY),
                FramePoint(cart.minX, cart.maxY),
            )
        }

    /** Grip ridges moulded across the top band, stopping short of the notch. */
    val gripRidgeRects: List<FrameRect>
        get() {
            val cart = cartridgeRect
            val left = cart.minX + 64
            val right = cart.maxX - cartridgeNotch - 40
            return (0 until 5).map { index -> FrameRect(left, cart.minY + 34 + index * 22, right - left, 8.0) }
        }

    /** The sunken area the label is stuck into. Its rim is the bevel. */
    val labelRecessRect: FrameRect
        get() {
            val cart = cartridgeRect
            return FrameRect(cart.minX + 52, cart.minY + 150, cart.width - 104, cart.height - 150 - 176)
        }

    /** The label: the app's dark background, carrying the song. */
    val labelRect: FrameRect get() = labelRecessRect.insetBy(14.0, 14.0)

    /** The bounding box of the arrow moulded under the label, pointing up. */
    val triangleRect: FrameRect
        get() {
            val cart = cartridgeRect
            val width = 64.0
            val height = 56.0
            val centerY = (labelRecessRect.maxY + cart.maxY) / 2
            return FrameRect(cart.midX - width / 2, centerY - height / 2, width, height)
        }

    val coverPadding = 40.0
    val coverTitleFontSize = 72.0
    val coverMetaFontSize = 34.0
    val coverLabelFontSize: Double get() = nameFontSize(coverBarWidth + coverBarGap)

    /** Up to two lines of title. */
    val coverTitleRect: FrameRect
        get() = FrameRect(labelRect.minX + coverPadding, labelRect.minY + coverPadding,
            labelRect.width - 2 * coverPadding, 190.0)

    /** Tempo and length. */
    val coverMetaRect: FrameRect
        get() = FrameRect(coverTitleRect.minX, coverTitleRect.maxY + 8, coverTitleRect.width, 48.0)

    val coverProgressRect: FrameRect
        get() = FrameRect(labelRect.minX + coverPadding, labelRect.maxY - 100,
            labelRect.width - 2 * coverPadding, 14.0)

    /** Elapsed and total time, under the progress bar. */
    val coverTimeRect: FrameRect
        get() = FrameRect(coverProgressRect.minX, coverProgressRect.maxY + 14, coverProgressRect.width, 40.0)

    private val coverBarGap = 24.0
    private val coverBarsTop: Double get() = coverMetaRect.maxY + 50
    /** Room under the bars for each track's name. */
    private val coverBarsBottom: Double get() = coverProgressRect.minY - 90
    private val coverBarWidth: Double
        get() {
            val available = labelRect.width - 2 * coverPadding - coverBarGap * (this.trackCount - 1)
            return minOf(140.0, floor(available / this.trackCount))
        }

    /** The full extent of a track's bar. The drawer fills it from the bottom
     * by the track's pulse. */
    fun coverBarRect(track: Int): FrameRect {
        val total = this.trackCount * coverBarWidth + (this.trackCount - 1) * coverBarGap
        val x = labelRect.midX - total / 2 + track * (coverBarWidth + coverBarGap)
        return FrameRect(x, coverBarsTop, coverBarWidth, coverBarsBottom - coverBarsTop)
    }

    /** Track names sit centred under their bars. */
    /** [coverBarRect] cut into [COVER_SEGMENT_COUNT] equal segments, bottom
     * first, with [COVER_SEGMENT_GAP] between each, like the app icon's
     * meter. iOS's `coverBarSegments(track:)`. */
    fun coverBarSegments(track: Int): List<FrameRect> {
        val bar = coverBarRect(track)
        val height = (bar.height - COVER_SEGMENT_GAP * (COVER_SEGMENT_COUNT - 1)) / COVER_SEGMENT_COUNT
        return (0 until COVER_SEGMENT_COUNT).map { index ->
            FrameRect(bar.minX, bar.maxY - height - index * (height + COVER_SEGMENT_GAP), bar.width, height)
        }
    }

    val coverBarLabelY: Double get() = coverBarsBottom + 40

    /** Where a track's name is drawn under its bar: no wider than the bar's
     * share of the row, less a gap, so names never run into each other; the
     * drawer truncates a longer one. A lone track has the row to itself. */
    fun coverBarLabelRect(track: Int): FrameRect {
        val bar = coverBarRect(track)
        val width = if (this.trackCount == 1) labelRect.width - 2 * coverPadding else coverBarWidth + coverBarGap - 8
        return FrameRect(bar.midX - width / 2, coverBarLabelY - 20, width, 40.0)
    }

    companion object {
        const val COVER_SEGMENT_COUNT = 6
        const val COVER_SEGMENT_GAP = 8.0
        const val WIDTH = 1080
        const val HEIGHT = 1920
        /** Kept clear at the top: 12.5% of the height. */
        const val TOP_BAND = 240.0
        /** Kept clear at the bottom: a quarter of the height. TikTok's
         * caption, account name and sound line reach about 480px up on a
         * long caption. */
        const val BOTTOM_BAND = 480.0
        /** Wide enough on the right to clear TikTok's button column; the same
         * on the left so the content stays centred. */
        const val SIDE_MARGIN = 120.0
        /** iOS `Theme.cellRadius` and Android `ChipRadii.cell`. */
        const val CELL_RADIUS = 5.0

        /** How much of a step the sounding row holds still on the playhead
         * before the grid starts moving on to the next. */
        const val SCROLL_HOLD = 0.7

        /** Where the grid is, in steps, [elapsed] steps into the body: held on
         * the sounding step for most of it, then eased to the next over the
         * step's last 30%, so the scroll is continuous at slow tempos but the
         * sounding row is never half a row off the playhead mid-step. The
         * last step holds, since nothing follows it. */
        fun scrollPosition(elapsed: Double, lastStep: Int): Double {
            val step = minOf(maxOf(elapsed, 0.0).toInt(), lastStep)
            if (step >= lastStep) return step.toDouble()
            val into = ((elapsed - step - SCROLL_HOLD) / (1 - SCROLL_HOLD)).coerceIn(0.0, 1.0)
            return step + into * into * (3 - 2 * into)
        }

        /** The song's name as both frames draw it: each line break, with the
         * spaces around it, becomes one space. A name typed in the app has
         * none, but an imported one keeps any it was saved with, and the
         * frames wrap the title by width alone: the Grid header has one line,
         * and the Cartridge places its tempo line under the lines the title
         * wrapped to. */
        fun displayTitle(name: String): String = name.replace(LINE_BREAKS, " ").trim()

        private val LINE_BREAKS = Regex("[ \\t]*[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]+[ \\t]*")

        /** Track names are drawn this large unless their slots are narrow. */
        const val FULL_NAME_FONT_SIZE = 26.0

        /** The largest size, up to full, at which a default name like "PU1 A"
         * leaves more room before the next name than the space inside it, so
         * a row of names doesn't read as one run. iOS's rule, sized for SF
         * Mono's advance of about 0.62 of its size: five characters plus one
         * and a half spaces' gap. JetBrains Mono's 0.6 fits it too. */
        fun nameFontSize(pitch: Double): Double = minOf(FULL_NAME_FONT_SIZE, floor(pitch / 4.1))
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

/**
 * What the Grid style draws on one frame: which rows, where, and where the
 * playing band is. Pure geometry from the timeline, so the scroll can be
 * tested frame by frame without drawing. Port of iOS's `GridFrame`.
 */
data class GridFrame(
    /** The step that is sounding: the header names its pattern and step. */
    val playing: VideoTimeline.Position,
    val soundingStep: Int,
    val rows: List<Row>,
    /** The highlight behind the sounding row. */
    val band: FrameRect,
    /** 1 through the body, falling to 0 over the ring-out. */
    val bandLight: Double,
) {
    data class Row(
        /** Steps since the start of the body, across chain slots and passes. */
        val globalStep: Int,
        /** Index into `song.patterns`. */
        val pattern: Int,
        /** Step inside that pattern: the row's own number. */
        val step: Int,
        val centerY: Double,
    )

    companion object {
        /** Swift's failable `init(layout:timeline:frame:)`: null when the
         * song has no steps. */
        fun of(layout: VideoLayout, timeline: VideoTimeline, frame: Int): GridFrame? {
            // Rows are laid out by step across the whole body, so the steps of
            // the next chain slot, or of the next pass after the loop wrap,
            // come up under the current ones and the scroll never jumps back.
            // In the ring-out nothing new plays, so the grid rests on the last
            // step and the band fades with the sound.
            val total = timeline.stepsPerPass * timeline.loopCount
            val elapsed = timeline.elapsedSteps(frame)
            val sounding = minOf(maxOf(elapsed, 0.0).toInt(), total - 1)
            val at = timeline.positionOfStep(sounding) ?: return null
            val position = VideoLayout.scrollPosition(elapsed, total - 1)

            val rows = layout.visibleSteps(position, total).mapNotNull { step ->
                timeline.positionOfStep(step)?.let {
                    Row(step, it.pattern, it.step, layout.rowCenterY(step, position))
                }
            }
            // While the grid moves on, the band stretches up to keep the
            // sounding row inside it until its step ends.
            val lift = layout.rowCenterY(sounding, position) - layout.playheadY
            val band = layout.playheadRowRect.union(layout.playheadRowRect.offsetBy(0.0, lift))
            val light = if (timeline.position(frame) == null) {
                maxOf(0.0, 1 - (timeline.sample(frame) - timeline.bodySamples).toDouble() / maxOf(timeline.tailSamples, 1))
            } else {
                1.0
            }
            return GridFrame(at, sounding, rows, band, light)
        }
    }
}
