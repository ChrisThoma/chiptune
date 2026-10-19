package dev.individuation.chiptune.platform.video

import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
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
import dev.individuation.chiptune.core.audio.MidiExport
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.video.ChannelPulse
import dev.individuation.chiptune.core.video.FrameRect
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
 * Grid: the current pattern scrolls up past a fixed playing row. The row that
 * is sounding is at full colour; rows away from it dim into the background,
 * so the eye stays on the beat. Cover: a card with the title, tempo and
 * length, a bar per track that flashes on each note ([ChannelPulse]), and a
 * progress bar. Both carry the "Made with Chiptune" tag.
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
    private val silent = this.song.tracks.map(MidiExport::isSilent)

    val bitmap: Bitmap = createBitmap(VideoLayout.WIDTH, VideoLayout.HEIGHT)
    private val canvas = Canvas(bitmap)

    private val medium: Typeface = resources.getFont(R.font.jetbrains_mono_medium)
    private val semibold: Typeface = resources.getFont(R.font.jetbrains_mono_semibold)
    private val bold: Typeface = resources.getFont(R.font.jetbrains_mono_bold)

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    /** Draws [frame] into [bitmap] and returns it. */
    fun draw(frame: Int): Bitmap {
        canvas.drawColor(BACKGROUND.argb)
        when (style) {
            ExportOptions.VideoStyle.GRID -> drawGrid(frame)
            ExportOptions.VideoStyle.COVER -> drawCover(frame)
        }
        drawTag()
        return bitmap
    }

    // MARK: Grid

    private fun drawGrid(frame: Int) {
        // In the ring-out nothing new plays, so the grid rests on the last
        // step and the playing row's highlight fades with the sound.
        val lastStep = timeline.stepsPerPass * timeline.loopCount - 1
        val elapsed = timeline.elapsedSteps(frame)
        val inTail = timeline.position(frame) == null
        val globalStep = minOf(elapsed.toInt(), lastStep)
        val at = timeline.positionOfStep(globalStep) ?: return
        val pattern = song.patterns.getOrNull(at.pattern) ?: return
        val fraction = if (inTail) 0.0 else elapsed - globalStep
        val position = at.step + fraction
        val tailFade = if (inTail) {
            maxOf(0.0, 1 - (timeline.sample(frame) - timeline.bodySamples).toDouble() / maxOf(timeline.tailSamples, 1))
        } else {
            1.0
        }

        drawGridHeader(pattern, at.step)
        drawColumnHeaders()

        canvas.withClip(layout.gridRect.toRectF()) {
            fill.color = TEXT.withAlpha(0.10 * tailFade).flattened(BACKGROUND).argb
            val radius = (layout.cellRadius + 4).toFloat()
            drawRoundRect(layout.playheadRowRect.toRectF(), radius, radius, fill)

            for (step in layout.visibleSteps(position, pattern.length)) {
                val y = layout.rowCenterY(step, position)
                drawRow(pattern, step, y, rowLight(y))
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
        text(song.name, layout.titleFontSize, bold, TEXT, FrameRect(header.x, header.y, header.width, 72.0))
        val readout = "${pattern.name}  ·  STEP ${twoDigits(step)}  ·  ${song.tempo.toInt()} BPM"
        text(readout, layout.subtitleFontSize, semibold, DIM, FrameRect(header.x, header.y + 86, header.width, 44.0))
    }

    private fun drawColumnHeaders() {
        for (index in song.tracks.indices) {
            val track = song.tracks[index]
            val cell = layout.cellRect(index, layout.columnHeaderY)
            val color = if (track.muted) DIM else channel(index)
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

    // MARK: Cover

    private fun drawCover(frame: Int) {
        val card = layout.coverCardRect.toRectF()
        val cardRadius = (VideoLayout.PANEL_RADIUS * 3).toFloat()
        fill.color = PANEL.argb
        canvas.drawRoundRect(card, cardRadius, cardRadius, fill)
        stroke.color = GRID.argb
        stroke.strokeWidth = 2f
        canvas.drawRoundRect(card, cardRadius, cardRadius, stroke)

        multilineText(song.name, layout.coverTitleFontSize, bold, TEXT, layout.coverTitleRect, maxLines = 2)
        val length = clock(timeline.seconds)
        text("${song.tempo.toInt()} BPM  ·  $length", layout.coverMetaFontSize, semibold, DIM, layout.coverMetaRect)

        val levels = pulse.levels(frame)
        for (index in song.tracks.indices) {
            val bar = layout.coverBarRect(index)
            val radius = minOf(bar.width / 2, 18.0).toFloat()
            fill.color = PANEL_HIGH.argb
            canvas.drawRoundRect(bar.toRectF(), radius, radius, fill)
            val level = levels.getOrNull(index) ?: 0.0
            if (level > 0) {
                val height = maxOf(bar.height * level, radius * 2.0)
                fill.color = channel(index).argb
                rect.set(bar.minX.toFloat(), (bar.maxY - height).toFloat(), bar.maxX.toFloat(), bar.maxY.toFloat())
                canvas.drawRoundRect(rect, radius, radius, fill)
            }
            val label = FrameRect(bar.midX - 90, layout.coverBarLabelY - 20, 180.0, 40.0)
            text(song.label(index), layout.coverLabelFontSize, bold,
                if (silent[index]) DIM else channel(index), label, Paint.Align.CENTER)
        }

        val track = layout.coverProgressRect
        val trackRadius = (track.height / 2).toFloat()
        fill.color = PANEL_HIGH.argb
        canvas.drawRoundRect(track.toRectF(), trackRadius, trackRadius, fill)
        val done = minOf(1.0, timeline.sample(frame).toDouble() / maxOf(timeline.totalSamples, 1))
        if (done > 0) {
            fill.color = TEXT.argb
            rect.set(track.minX.toFloat(), track.minY.toFloat(),
                (track.minX + maxOf(track.width * done, track.height)).toFloat(), track.maxY.toFloat())
            canvas.drawRoundRect(rect, trackRadius, trackRadius, fill)
        }
        val times = layout.coverTimeRect
        val elapsed = minOf(timeline.sample(frame) / WavExport.SAMPLE_RATE, timeline.seconds)
        text(clock(elapsed), 28.0, semibold, DIM, times)
        text(length, 28.0, semibold, DIM, times, Paint.Align.RIGHT)
    }

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
     * truncated. */
    private fun multilineText(string: String, size: Double, face: Typeface, color: Rgba, r: FrameRect, maxLines: Int) {
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

        /** Whole seconds, "m:ss", so a running clock keeps its shape. */
        fun clock(seconds: Double): String {
            val whole = maxOf(seconds, 0.0).toInt()
            return "${whole / 60}:${twoDigits(whole % 60)}"
        }

        /** "07", in ASCII digits whatever the locale, as the iOS frame shows. */
        fun twoDigits(n: Int): String = n.toString().padStart(2, '0')
    }
}
