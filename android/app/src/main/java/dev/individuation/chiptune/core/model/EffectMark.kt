package dev.individuation.chiptune.core.model

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * The marks a note's pitch effect draws after its name: ↗ ↘ ~ ⌒ ⤴ as pen
 * strokes in a unit box (y grows downward), so the grid, its menu and the
 * Grid video draw the same shape and no font has to carry the glyph.
 *
 * Sized to the text: the box is the font's cap height on a side, its bottom
 * on the baseline, [GAP_EM] of the font size after the note name. The
 * paths are iOS `EffectMark.swift`'s; keep the two in step.
 */
object EffectMark {
    data class Point(val x: Double, val y: Double)

    /** Pen width, as a fraction of the box. Round caps and joins. */
    const val STROKE_WIDTH = 0.14

    /** The box's side, as a fraction of the font size: the cap height of
     * JetBrains Mono, the grid's font (730 of 1000 units). */
    const val SIZE_EM = 0.73

    /** Space between the note name and the mark, as a fraction of the font size. */
    const val GAP_EM = 0.1

    // iOS `EffectMark.swift`'s paths, curves sampled into short lines.
    private val shapes: Map<NoteEffect, List<List<Point>>> = mapOf(
        NoteEffect.SLIDE_UP to listOf(
            listOf(Point(0.15, 0.85), Point(0.85, 0.15)),
            listOf(Point(0.4, 0.15), Point(0.85, 0.15), Point(0.85, 0.6)),
        ),
        NoteEffect.SLIDE_DOWN to listOf(
            listOf(Point(0.15, 0.15), Point(0.85, 0.85)),
            listOf(Point(0.4, 0.85), Point(0.85, 0.85), Point(0.85, 0.4)),
        ),
        // One wobble: up and back to the middle, then down and up.
        NoteEffect.VIBRATO to listOf(
            listOf(Point(0.08, 0.55)) +
                cubic(Point(0.08, 0.55), Point(0.18, 0.2), Point(0.38, 0.2), Point(0.5, 0.5)) +
                cubic(Point(0.5, 0.5), Point(0.62, 0.8), Point(0.82, 0.8), Point(0.92, 0.45)),
        ),
        NoteEffect.GLIDE to listOf(
            listOf(Point(0.1, 0.7)) + quad(Point(0.1, 0.7), Point(0.5, 0.1), Point(0.9, 0.7)),
        ),
        // Flat along the bottom, a turn, then up to an arrowhead.
        NoteEffect.BEND_IN to listOf(
            listOf(Point(0.1, 0.85), Point(0.45, 0.85)) +
                quad(Point(0.45, 0.85), Point(0.72, 0.85), Point(0.72, 0.55)) +
                listOf(Point(0.72, 0.12)),
            listOf(Point(0.47, 0.37), Point(0.72, 0.12), Point(0.97, 0.37)),
        ),
    )

    private const val SEGMENTS = 16

    /** A cubic Bézier's points after [p0], up to and including [p3]. */
    private fun cubic(p0: Point, p1: Point, p2: Point, p3: Point): List<Point> = (1..SEGMENTS).map { i ->
        val t = i.toDouble() / SEGMENTS
        val u = 1 - t
        fun at(a: Double, b: Double, c: Double, d: Double) = u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
        Point(at(p0.x, p1.x, p2.x, p3.x), at(p0.y, p1.y, p2.y, p3.y))
    }

    /** A quadratic Bézier's points after [p0], up to and including [p2]. */
    private fun quad(p0: Point, p1: Point, p2: Point): List<Point> = (1..SEGMENTS).map { i ->
        val t = i.toDouble() / SEGMENTS
        val u = 1 - t
        Point(u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x, u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y)
    }

    /** The pen strokes for [effect]; none for [NoteEffect.NONE]. */
    fun strokes(effect: NoteEffect): List<List<Point>> = shapes[effect].orEmpty()

    /** How much wider a label grows with [effect]'s mark at [fontSize]. */
    fun advance(fontSize: Double, effect: NoteEffect): Double =
        if (effect == NoteEffect.NONE) 0.0 else (GAP_EM + SIZE_EM) * fontSize

    /** [size], shrunk so text [textWidth] wide at [size] plus its mark fits
     * [available]: a long label scales down rather than losing its mark. */
    fun fittedSize(size: Double, textWidth: Double, effect: NoteEffect, available: Double): Double {
        val total = textWidth + advance(size, effect)
        return if (total <= available || total <= 0.0) size else size * available / total
    }
}
