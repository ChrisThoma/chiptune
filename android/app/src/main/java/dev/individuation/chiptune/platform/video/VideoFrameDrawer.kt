package dev.individuation.chiptune.platform.video

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip
import dev.individuation.chiptune.R
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.video.ChannelPulse
import dev.individuation.chiptune.core.video.FrameRect
import dev.individuation.chiptune.core.video.GridFrame
import dev.individuation.chiptune.core.video.VideoLayout
import dev.individuation.chiptune.core.video.VideoTimeline
import dev.individuation.chiptune.ui.theme.ChipColors
import kotlin.math.abs

/**
 * Draws one frame of an exported video onto a reused [Bitmap], in the app's
 * own colours and JetBrains Mono. Port of `Sources/Video/VideoFrameRenderer.swift`:
 * sizes are fixed pixels from [VideoLayout], so the frame is a picture of the
 * song, the same on every phone, and lines up with the iOS one.
 *
 * Grid: the song's steps, across patterns and passes, scroll up past a fixed
 * playing row ([GridFrame]). The row that
 * is sounding is at full colour; rows away from it dim into the background,
 * so the eye stays on the beat. Cover (shown as "Cartridge"): a grey game
 * cartridge whose label carries the title, tempo and length, a bar per track
 * that flashes on each note ([ChannelPulse]), and a progress bar. Both carry the "Made with Chiptune" tag.
 *
 * Not unit-tested: it needs android.graphics, which the JVM suite stubs out.
 * Its geometry and timing come from the tested core types.
 */
class VideoFrameDrawer(
    resources: Resources,
    song: Song,
    options: ExportOptions,
    private val timeline: VideoTimeline,
) {
    private val song: Song = song.normalized()
    private val style = options.videoStyle
    private val layout = VideoLayout(this.song.tracks.size)
    private val pulse = ChannelPulse(this.song, timeline)
    private val dimmed = this.song.tracks.map { ChannelPulse.dimsName(it, style) }

    val bitmap: Bitmap = createBitmap(VideoLayout.WIDTH, VideoLayout.HEIGHT)
    private val canvas = Canvas(bitmap)

    private val medium: Typeface = resources.getFont(R.font.jetbrains_mono_medium)
    private val semibold: Typeface = resources.getFont(R.font.jetbrains_mono_semibold)
    private val bold: Typeface = resources.getFont(R.font.jetbrains_mono_bold)

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    /** Everything in a Cartridge frame that never changes (the background,
     * the cartridge, the label's text, the bars' wells, the progress track,
     * the total time and the tag), drawn once and kept here. Each frame
     * copies it back and draws only what moves on top, so the blurred shadow
     * and the paths aren't redrawn 30 times a second. Nothing that moves
     * overlaps anything the original order drew after it, so the frame comes
     * out pixel for pixel the same. */
    private val coverBackdrop: Bitmap? = if (style == ExportOptions.VideoStyle.COVER) {
        canvas.drawColor(BACKGROUND.argb)
        drawCoverStatic()
        drawTag()
        bitmap.copy(Bitmap.Config.ARGB_8888, false)
    } else {
        null
    }

    /** Draws [frame] into [bitmap] and returns it. */
    fun draw(frame: Int): Bitmap {
        when (style) {
            ExportOptions.VideoStyle.GRID -> {
                canvas.drawColor(BACKGROUND.argb)
                drawGrid(frame)
                drawTag()
            }
            ExportOptions.VideoStyle.COVER -> {
                canvas.drawBitmap(checkNotNull(coverBackdrop), 0f, 0f, null)
                drawCoverMoving(frame)
            }
        }
        return bitmap
    }

    /** Frees the frame and the backdrop. */
    fun recycle() {
        coverBackdrop?.recycle()
        bitmap.recycle()
    }

    // MARK: Grid

    private fun drawGrid(frame: Int) {
        val grid = GridFrame.of(layout, timeline, frame) ?: return
        val playing = song.patterns.getOrNull(grid.playing.pattern) ?: return

        drawGridHeader(playing, grid.playing.step)
        drawColumnHeaders()

        canvas.withClip(layout.gridRect.toRectF()) {
            fill.color = TEXT.withAlpha(0.10 * grid.bandLight).flattened(BACKGROUND).argb
            val radius = (layout.cellRadius + 4).toFloat()
            drawRoundRect(grid.band.toRectF(), radius, radius, fill)

            for (row in grid.rows) {
                val pattern = song.patterns.getOrNull(row.pattern) ?: continue
                drawRow(pattern, row.step, row.centerY, rowLight(row.centerY))
            }
        }
    }

    /** Full on the playing row, easing to about 40% a row away, then fading
     * out toward the grid's top and bottom edges. */
    private fun rowLight(y: Double): Double {
        val distance = abs(y - layout.playheadY)
        var near = maxOf(0.0, 1 - distance / (layout.rowPitch * 1.1))
        near = near * near * (3 - 2 * near)
        val base = 0.42 + 0.58 * near
        val half = layout.gridRect.height / 2
        var edge = minOf(1.0, maxOf(0.0, (half - distance) / (half * 0.55)))
        edge = edge * edge * (3 - 2 * edge)
        return base * edge
    }

    private fun drawGridHeader(pattern: Pattern, step: Int) {
        val header = layout.headerRect
        text(VideoLayout.displayTitle(song.name), layout.titleFontSize, bold, TEXT, FrameRect(header.x, header.y, header.width, 72.0))
        val readout = "${pattern.name}  ·  STEP ${twoDigits(step)}  ·  ${song.tempo.toInt()} BPM"
        text(readout, layout.subtitleFontSize, semibold, DIM, FrameRect(header.x, header.y + 86, header.width, 44.0))
    }

    private fun drawColumnHeaders() {
        for (index in song.tracks.indices) {
            val cell = layout.columnHeaderRect(index)
            val color = if (dimmed[index]) DIM else channel(index)
            text(song.label(index), layout.columnHeaderFontSize, bold, color, cell, Paint.Align.CENTER)
        }
    }

    /** One step's gutter number and cells, after the app's grid cell: a note
     * fills with its channel colour and is named in dark text; a note-off is
     * a dim REST; an empty step is the row tint with a hairline and a dot.
     * Muted tracks fade their notes to 35% as the app does. [light] blends
     * the whole row toward the background. */
    private fun drawRow(pattern: Pattern, step: Int, centerY: Double, light: Double) {
        if (light <= 0.004) return
        val bg = BACKGROUND
        val gutter = layout.gutterRect(centerY)
        text(twoDigits(step), layout.gutterFontSize, medium,
            (if (step % 4 == 0) TEXT else DIM).blended(bg, light), gutter, Paint.Align.CENTER)

        val radius = layout.cellRadius.toFloat()
        for (index in song.tracks.indices) {
            val track = song.tracks[index]
            val note = pattern.rows.getOrNull(index)?.getOrNull(step) ?: Chip.EMPTY_NOTE
            val cell = layout.cellRect(index, centerY)
            val filled = note != Chip.EMPTY_NOTE
            val cellFill: Rgba
            val label: String
            val labelColor: Rgba
            if (filled) {
                val base = if (note == Chip.NOTE_OFF) DIM else channel(index)
                cellFill = if (track.muted) base.withAlpha(0.35).flattened(bg) else base
                label = NoteName.label(note)
                labelColor = (if (track.muted) TEXT else ON_LIGHT).withAlpha(0.85).flattened(cellFill)
            } else {
                cellFill = if (step % 4 == 0) PANEL_HIGH else PANEL
                label = "·"
                labelColor = DIM.withAlpha(0.6).flattened(cellFill)
            }
            fill.color = cellFill.blended(bg, light).argb
            val r = cell.toRectF()
            canvas.drawRoundRect(r, radius, radius, fill)
            if (!filled) {
                stroke.color = GRID.withAlpha(0.6).flattened(cellFill).blended(bg, light).argb
                stroke.strokeWidth = 2f
                // Core Graphics strokes centred on the path, as here.
                canvas.drawRoundRect(r, radius, radius, stroke)
            }
            val size = when {
                note == Chip.NOTE_OFF -> layout.cellFontSize * 0.8
                filled -> layout.cellFontSize
                else -> layout.cellFontSize * 1.3
            }
            text(label, size, semibold, labelColor.blended(bg, light), cell, Paint.Align.CENTER)
        }
    }

    // MARK: Cartridge (the Cover style)

    /** The body with its notch, the grip ridges, the sunken label and the
     * moulded arrow, in grey plastic lit from the top left. Flat fills only,
     * since H.264 bands gradients. The song is drawn on the label after. */
    private fun drawCartridge() {
        val cart = layout.cartridgeRect
        val notch = layout.cartridgeNotch
        val radius = layout.cartridgeCornerRadius
        val body = cartridgePath(cart, notch, radius)

        // A soft shadow under the whole body.
        fill.color = PLASTIC_SHADE.argb
        fill.setShadowLayer(30f, 0f, 26f, android.graphics.Color.argb(178, 0, 0, 0))
        canvas.drawPath(body, fill)
        fill.clearShadowLayer()

        // Edges: lit top and left, shaded bottom and right, then the face.
        canvas.withClip(body) {
            fill.color = PLASTIC_HIGHLIGHT.argb
            drawPath(body, fill)
            fill.color = PLASTIC_SHADE.argb
            drawPath(cartridgePath(cart.offsetBy(EDGE, EDGE), notch, radius), fill)
            fill.color = PLASTIC_BODY.argb
            drawPath(cartridgePath(cart.insetBy(EDGE, EDGE), notch - 3, radius - EDGE), fill)
        }

        // Grip ridges: a groove with a lit lip under it.
        for (ridge in layout.gripRidgeRects) {
            val r = (ridge.height / 2).toFloat()
            fill.color = PLASTIC_GROOVE.argb
            canvas.drawRoundRect(ridge.toRectF(), r, r, fill)
            fill.color = PLASTIC_HIGHLIGHT.argb
            canvas.drawRoundRect(FrameRect(ridge.minX, ridge.maxY, ridge.width, 3.0).toRectF(), 1.5f, 1.5f, fill)
        }

        // The recess: shaded on its top and left, where the rim overhangs,
        // lit on its bottom and right.
        val recess = layout.labelRecessRect
        val recessRadius = 22f
        val recessPath = Path().apply { addRoundRect(recess.toRectF(), recessRadius, recessRadius, Path.Direction.CW) }
        canvas.withClip(recessPath) {
            fill.color = PLASTIC_HIGHLIGHT.argb
            drawRoundRect(recess.toRectF(), recessRadius, recessRadius, fill)
            fill.color = PLASTIC_RECESS_DARK.argb
            drawRoundRect(recess.offsetBy(-5.0, -5.0).toRectF(), recessRadius, recessRadius, fill)
            fill.color = PLASTIC_BEVEL.argb
            drawRoundRect(recess.insetBy(5.0, 5.0).toRectF(), recessRadius - 5, recessRadius - 5, fill)
        }

        // The label itself, on the app's own background.
        fill.color = BACKGROUND.argb
        canvas.drawRoundRect(layout.labelRect.toRectF(), 12f, 12f, fill)

        // The arrow moulded under the label: a slightly sunken triangle with
        // a lit lower edge.
        val tri = layout.triangleRect
        fill.color = PLASTIC_HIGHLIGHT.argb
        canvas.drawPath(triangle(tri.offsetBy(0.0, 3.0)), fill)
        fill.color = PLASTIC_GROOVE.argb
        canvas.drawPath(triangle(tri), fill)
    }

    /** A cartridge outline in [r]: the top-right corner cut by a diagonal
     * [notch] long on each leg, the other three rounded by [radius]. */
    private fun cartridgePath(r: FrameRect, notch: Double, radius: Double): Path {
        val d = (radius * 2).toFloat()
        return Path().apply {
            moveTo(r.minX.toFloat(), (r.minY + radius).toFloat())
            arcTo(RectF(r.minX.toFloat(), r.minY.toFloat(), r.minX.toFloat() + d, r.minY.toFloat() + d), 180f, 90f)
            lineTo((r.maxX - notch).toFloat(), r.minY.toFloat())
            lineTo(r.maxX.toFloat(), (r.minY + notch).toFloat())
            lineTo(r.maxX.toFloat(), (r.maxY - radius).toFloat())
            arcTo(RectF(r.maxX.toFloat() - d, r.maxY.toFloat() - d, r.maxX.toFloat(), r.maxY.toFloat()), 0f, 90f)
            lineTo((r.minX + radius).toFloat(), r.maxY.toFloat())
            arcTo(RectF(r.minX.toFloat(), r.maxY.toFloat() - d, r.minX.toFloat() + d, r.maxY.toFloat()), 90f, 90f)
            close()
        }
    }

    /** An upward-pointing triangle filling [r]. */
    private fun triangle(r: FrameRect): Path = Path().apply {
        moveTo(r.midX.toFloat(), r.minY.toFloat())
        lineTo(r.maxX.toFloat(), r.maxY.toFloat())
        lineTo(r.minX.toFloat(), r.maxY.toFloat())
        close()
    }

    /** The Cartridge frame's parts that stay put, for [coverBackdrop]. */
    private fun drawCoverStatic() {
        drawCartridge()

        val titleRect = layout.coverTitleRect
        val titleHeight = multilineText(VideoLayout.displayTitle(song.name), layout.coverTitleFontSize, bold, TEXT, titleRect, maxLines = 2)
        // The tempo line sits under the title as drawn, so a one-line title
        // doesn't leave a gap where a second line would go.
        val meta = layout.coverMetaRect.let {
            it.copy(y = minOf(it.minY, titleRect.minY + titleHeight + 8))
        }
        val length = clock(timeline.seconds)
        text("${song.tempo.toInt()} BPM  ·  $length", layout.coverMetaFontSize, semibold, DIM, meta)

        for (index in song.tracks.indices) {
            val bar = layout.coverBarRect(index)
            val radius = coverBarRadius(bar)
            fill.color = PANEL_HIGH.argb
            canvas.drawRoundRect(bar.toRectF(), radius, radius, fill)
            // Below the bar, so no level ever reaches it.
            val label = layout.coverBarLabelRect(index)
            text(song.label(index), layout.coverLabelFontSize, bold,
                if (dimmed[index]) DIM else channel(index), label, Paint.Align.CENTER)
        }

        val track = layout.coverProgressRect
        val trackRadius = (track.height / 2).toFloat()
        fill.color = PANEL_HIGH.argb
        canvas.drawRoundRect(track.toRectF(), trackRadius, trackRadius, fill)
        text(length, 28.0, semibold, DIM, layout.coverTimeRect, Paint.Align.RIGHT)
    }

    /** The bars' levels, the progress and the running clock, over
     * [coverBackdrop]. */
    private fun drawCoverMoving(frame: Int) {
        val levels = pulse.levels(frame)
        for (index in song.tracks.indices) {
            val level = levels.getOrNull(index) ?: 0.0
            if (level > 0) {
                val bar = layout.coverBarRect(index)
                val radius = coverBarRadius(bar)
                val height = maxOf(bar.height * level, radius * 2.0)
                fill.color = channel(index).argb
                rect.set(bar.minX.toFloat(), (bar.maxY - height).toFloat(), bar.maxX.toFloat(), bar.maxY.toFloat())
                canvas.drawRoundRect(rect, radius, radius, fill)
            }
        }

        val track = layout.coverProgressRect
        val trackRadius = (track.height / 2).toFloat()
        val done = minOf(1.0, timeline.sample(frame).toDouble() / maxOf(timeline.totalSamples, 1))
        if (done > 0) {
            fill.color = TEXT.argb
            rect.set(track.minX.toFloat(), track.minY.toFloat(),
                (track.minX + maxOf(track.width * done, track.height)).toFloat(), track.maxY.toFloat())
            canvas.drawRoundRect(rect, trackRadius, trackRadius, fill)
        }
        val elapsed = minOf(timeline.sample(frame) / WavExport.SAMPLE_RATE, timeline.seconds)
        text(clock(elapsed), 28.0, semibold, DIM, layout.coverTimeRect)
    }

    private fun coverBarRadius(bar: FrameRect): Float = minOf(bar.width / 2, 18.0).toFloat()

    // MARK: Tag

    private fun drawTag() {
        text("Made with Chiptune", VideoLayout.TAG_FONT_SIZE, semibold,
            DIM.withAlpha(0.8).flattened(BACKGROUND), VideoLayout.tagRect)
    }

    // MARK: Text

    /** One line, vertically centred in [r], truncated with an ellipsis
     * rather than spilling out of it. */
    private fun text(string: String, size: Double, face: Typeface, color: Rgba, r: FrameRect, align: Paint.Align = Paint.Align.LEFT) {
        textPaint.typeface = face
        textPaint.textSize = size.toFloat()
        textPaint.color = color.argb
        textPaint.textAlign = align
        val fitted = TextUtils.ellipsize(string, textPaint, r.width.toFloat(), TextUtils.TruncateAt.END).toString()
        val metrics = textPaint.fontMetrics
        val baseline = (r.midY - (metrics.ascent + metrics.descent) / 2).toFloat()
        val x = when (align) {
            Paint.Align.LEFT -> r.minX
            Paint.Align.CENTER -> r.midX
            Paint.Align.RIGHT -> r.maxX
        }.toFloat()
        canvas.drawText(fitted, x, baseline, textPaint)
    }

    /** Word-wrapped from the top of [r], up to [maxLines], the last one
     * truncated. Returns the height the lines took. */
    private fun multilineText(string: String, size: Double, face: Typeface, color: Rgba, r: FrameRect, maxLines: Int): Double {
        textPaint.typeface = face
        textPaint.textSize = size.toFloat()
        textPaint.color = color.argb
        textPaint.textAlign = Paint.Align.LEFT
        val width = r.width.toInt()
        val text = StaticLayout.Builder.obtain(string, 0, string.length, textPaint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setIncludePad(false)
            .build()
        canvas.withClip(r.toRectF()) {
            translate(r.minX.toFloat(), r.minY.toFloat())
            text.draw(this)
        }
        return text.height.toDouble()
    }

    private fun channel(index: Int): Rgba = Rgba(ChipColors.channel(song.tracks[index].kind))

    private fun FrameRect.toRectF(): RectF = RectF(minX.toFloat(), minY.toFloat(), maxX.toFloat(), maxY.toFloat())

    /** ChipColors as plain components, so the drawer can blend them toward
     * the background itself instead of drawing every cell through a layer. */
    private class Rgba(val r: Double, val g: Double, val b: Double, val a: Double = 1.0) {
        constructor(color: Color) : this(color.red.toDouble(), color.green.toDouble(), color.blue.toDouble(), color.alpha.toDouble())

        fun withAlpha(alpha: Double) = Rgba(r, g, b, alpha)

        /** This colour, at its alpha, composited onto an opaque [base]. */
        fun flattened(base: Rgba) = Rgba(base.r + (r - base.r) * a, base.g + (g - base.g) * a, base.b + (b - base.b) * a)

        /** Shown at [light] (0..1) over [base]: 1 is this colour, 0 is [base]. */
        fun blended(base: Rgba, light: Double) =
            Rgba(base.r + (r - base.r) * light, base.g + (g - base.g) * light, base.b + (b - base.b) * light)

        val argb: Int get() = Color(r.toFloat().coerceIn(0f, 1f), g.toFloat().coerceIn(0f, 1f),
            b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f)).toArgb()
    }

    private companion object {
        val BACKGROUND = Rgba(ChipColors.background)
        val PANEL = Rgba(ChipColors.panel)
        val PANEL_HIGH = Rgba(ChipColors.panelHigh)
        val GRID = Rgba(ChipColors.grid)
        val TEXT = Rgba(ChipColors.text)
        val DIM = Rgba(ChipColors.dim)
        val ON_LIGHT = Rgba(ChipColors.onLight)

        /** The cartridge's grey plastic, the same values as iOS. */
        val PLASTIC_BODY = rgb(0xBD, 0xBA, 0xB3)
        val PLASTIC_HIGHLIGHT = rgb(0xDA, 0xD7, 0xD0)
        val PLASTIC_SHADE = rgb(0x8E, 0x8B, 0x84)
        val PLASTIC_GROOVE = rgb(0x9E, 0x9B, 0x94)
        val PLASTIC_BEVEL = rgb(0xA8, 0xA5, 0x9E)
        val PLASTIC_RECESS_DARK = rgb(0x7C, 0x79, 0x73)
        /** How far the lit and shaded edges reach in from the outline. */
        const val EDGE = 7.0

        fun rgb(r: Int, g: Int, b: Int) = Rgba(r / 255.0, g / 255.0, b / 255.0)

        /** Whole seconds, "m:ss", so a running clock keeps its shape. */
        fun clock(seconds: Double): String {
            val whole = maxOf(seconds, 0.0).toInt()
            return "${whole / 60}:${twoDigits(whole % 60)}"
        }

        /** "07", in ASCII digits whatever the locale, as the iOS frame shows. */
        fun twoDigits(n: Int): String = n.toString().padStart(2, '0')
    }
}
