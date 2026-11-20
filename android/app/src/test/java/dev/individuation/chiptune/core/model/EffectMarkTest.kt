package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The effect marks are drawn from these strokes in the grid, the menu and
 * the video, so the three can't disagree and no font has to carry ⤴. */
class EffectMarkTest {
    private val marked = NoteEffect.entries.filter { it != NoteEffect.NONE }
    private fun points(effect: NoteEffect) = EffectMark.strokes(effect).flatten()

    @Test fun noEffectHasNoMark() = assertTrue(EffectMark.strokes(NoteEffect.NONE).isEmpty())

    @Test fun everyEffectHasStrokesInsideTheUnitBox() {
        for (effect in marked) {
            val strokes = EffectMark.strokes(effect)
            assertTrue(effect.name, strokes.isNotEmpty() && strokes.all { it.size >= 2 })
            for (p in points(effect)) assertTrue("$effect $p", p.x in 0.0..1.0 && p.y in 0.0..1.0)
        }
    }

    @Test fun everyMarkIsDifferent() {
        assertEquals(marked.size, marked.map { EffectMark.strokes(it) }.toSet().size)
    }

    /** y grows downward, as on a canvas. */
    @Test fun slidesPointTheWayThePitchMoves() {
        val up = EffectMark.strokes(NoteEffect.SLIDE_UP).first()
        assertTrue(up.last().x > up.first().x && up.last().y < up.first().y)
        val down = EffectMark.strokes(NoteEffect.SLIDE_DOWN).first()
        assertTrue(down.last().x > down.first().x && down.last().y > down.first().y)
    }

    @Test fun vibratoWobblesAcrossTheMiddle() {
        val ys = points(NoteEffect.VIBRATO).map { it.y }
        assertTrue(ys.any { it < 0.4 } && ys.any { it > 0.6 })
    }

    @Test fun glideArchesUp() {
        val arc = EffectMark.strokes(NoteEffect.GLIDE).first()
        val top = arc.minBy { it.y }
        assertTrue(top.x in 0.4..0.6 && arc.first().y > top.y + 0.2 && arc.last().y > top.y + 0.2)
    }

    @Test fun bendInRunsFlatThenRisesToAnArrowhead() {
        val line = EffectMark.strokes(NoteEffect.BEND_IN).first()
        assertEquals(line[0].y, line[1].y, 1e-9)
        assertTrue(line.last().y < line.first().y - 0.4)
        assertNotEquals(1, EffectMark.strokes(NoteEffect.BEND_IN).size)
    }

    /** Sized to the text: a box as tall as the capitals, sat on the baseline,
     * with a small gap after the note name. */
    @Test fun markWidthFollowsTheFontSize() {
        assertEquals(0.0, EffectMark.advance(12.0, NoteEffect.NONE), 1e-9)
        assertEquals((EffectMark.GAP_EM + EffectMark.SIZE_EM) * 12, EffectMark.advance(12.0, NoteEffect.VIBRATO), 1e-9)
        assertTrue(EffectMark.SIZE_EM in 0.6..0.8)
        assertEquals(0.1, EffectMark.GAP_EM, 1e-9)
    }

    /** A label too wide for its cell shrinks, mark included, rather than
     * being cut off; one that fits keeps its size. */
    @Test fun fittedSizeShrinksTextAndMarkTogether() {
        // 20 px of text at size 10, a mark adds 10 * (gap + size) more.
        val markPx = EffectMark.advance(10.0, NoteEffect.GLIDE)
        assertEquals(10.0, EffectMark.fittedSize(10.0, 20.0, NoteEffect.GLIDE, 100.0), 1e-9)
        val fitted = EffectMark.fittedSize(10.0, 20.0, NoteEffect.GLIDE, (20.0 + markPx) / 2)
        assertEquals(5.0, fitted, 1e-9)
        assertEquals(5.0, EffectMark.fittedSize(10.0, 20.0, NoteEffect.NONE, 10.0), 1e-9)
    }
}

/** The same paths as iOS `EffectMark.swift`, curves sampled into lines. */
class EffectMarkIosGeometryTest {
    private fun ends(effect: NoteEffect) = EffectMark.strokes(effect).map { it.first() to it.last() }
    private fun p(x: Double, y: Double) = EffectMark.Point(x, y)

    @Test fun endpointsMatchIos() {
        assertEquals(listOf(p(0.15, 0.85) to p(0.85, 0.15), p(0.4, 0.15) to p(0.85, 0.6)), ends(NoteEffect.SLIDE_UP))
        assertEquals(listOf(p(0.15, 0.15) to p(0.85, 0.85), p(0.4, 0.85) to p(0.85, 0.4)), ends(NoteEffect.SLIDE_DOWN))
        assertEquals(listOf(p(0.08, 0.55) to p(0.92, 0.45)), ends(NoteEffect.VIBRATO))
        assertEquals(listOf(p(0.1, 0.7) to p(0.9, 0.7)), ends(NoteEffect.GLIDE))
        assertEquals(listOf(p(0.1, 0.85) to p(0.72, 0.12), p(0.47, 0.37) to p(0.97, 0.37)), ends(NoteEffect.BEND_IN))
    }

    @Test fun curvesPassThroughTheirIosMidpoints() {
        // Vibrato's two cubics meet at (0.5, 0.5); glide's quad peaks at (0.5, 0.4).
        assertTrue(EffectMark.Point(0.5, 0.5) in EffectMark.strokes(NoteEffect.VIBRATO).first())
        val glide = EffectMark.strokes(NoteEffect.GLIDE).first()
        val top = glide.minBy { it.y }
        assertEquals(0.5, top.x, 1e-9)
        assertEquals(0.4, top.y, 1e-9)
        // Bend in's quad ends where the riser starts.
        assertTrue(EffectMark.Point(0.72, 0.55) in EffectMark.strokes(NoteEffect.BEND_IN).first())
    }
}
