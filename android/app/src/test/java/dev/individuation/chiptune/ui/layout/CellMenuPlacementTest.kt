package dev.individuation.chiptune.ui.layout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The effect menu hangs below its cell, or above it, and never over it, so
 * you can see which note you're changing. */
class CellMenuPlacementTest {
    // A 846-tall window with 30 at the top and 20 at the bottom kept clear.
    private fun place(top: Double, bottom: Double, content: Double) =
        CellMenuPlacement.place(anchorTop = top, anchorBottom = bottom, windowTop = 30.0, windowBottom = 826.0, contentHeight = content, gap = 4.0)

    @Test fun belowWhenItFits() {
        val p = place(100.0, 140.0, 370.0)
        assertTrue(p.below)
        assertEquals(144.0, p.y, 1e-9)
        assertEquals(826.0 - 144.0, p.maxHeight, 1e-9)
    }

    @Test fun aboveWhenOnlyAboveFits() {
        val p = place(600.0, 640.0, 370.0)
        assertFalse(p.below)
        assertEquals(600.0 - 4.0 - 370.0, p.y, 1e-9)
    }

    /** The middle of the screen: neither side holds the whole menu, so it
     * takes the roomier side and scrolls, and the cell stays clear. */
    @Test fun roomierSideWhenNeitherFits() {
        val p = place(412.0, 450.0, 500.0)
        assertFalse(p.below)
        assertEquals(412.0 - 4.0 - 30.0, p.maxHeight, 1e-9)
        assertEquals(30.0, p.y, 1e-9)
        val q = place(380.0, 418.0, 500.0)
        assertTrue(q.below)
        assertEquals(826.0 - 422.0, q.maxHeight, 1e-9)
    }

    @Test fun menuNeverOverlapsTheCell() {
        for (top in listOf(40.0, 200.0, 412.0, 600.0, 780.0)) {
            for (content in listOf(100.0, 370.0, 900.0)) {
                val p = place(top, top + 40, content)
                val height = minOf(content, p.maxHeight)
                assertTrue("$top $content", p.y + height <= top || p.y >= top + 40)
            }
        }
    }

    @Test fun sidewaysItLinesUpWithTheCellAndStaysOnScreen() {
        assertEquals(50.0, CellMenuPlacement.x(anchorLeft = 50.0, contentWidth = 200.0, windowWidth = 400.0, margin = 8.0), 1e-9)
        assertEquals(192.0, CellMenuPlacement.x(anchorLeft = 300.0, contentWidth = 200.0, windowWidth = 400.0, margin = 8.0), 1e-9)
    }

    /** Material3's `calculateTransformOrigin`: the menu grows out of the edge
     * nearest the cell, centred on the part of the cell it lines up with. */
    @Test fun growsFromTheCellEdgeItOpensFrom() {
        // Cell x 50..130, y 400..440. Menu below, x 50..250.
        val below = CellMenuPlacement.transformOrigin(50.0, 400.0, 130.0, 440.0, 50.0, 444.0, 250.0, 744.0)
        assertEquals(0.2, below.first, 1e-9)
        assertEquals(0.0, below.second, 1e-9)
        // Menu above: grows up from its bottom edge.
        val above = CellMenuPlacement.transformOrigin(50.0, 400.0, 130.0, 440.0, 50.0, 96.0, 250.0, 396.0)
        assertEquals(1.0, above.second, 1e-9)
        // Entirely to the cell's right or left: the near side.
        assertEquals(0.0, CellMenuPlacement.transformOrigin(50.0, 400.0, 130.0, 440.0, 130.0, 444.0, 330.0, 744.0).first, 1e-9)
        assertEquals(1.0, CellMenuPlacement.transformOrigin(250.0, 400.0, 330.0, 440.0, 50.0, 444.0, 250.0, 744.0).first, 1e-9)
    }
}
