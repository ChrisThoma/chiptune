package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The words on and behind one grid cell, shared by the grid and the Grid
 * video (twin of iOS `GridCellText`). The effect's mark is drawn beside the
 * text from [EffectMark], not typed into it. */
class GridCellTextTest {
    private val e5 = 76

    @Test fun titleIsThePlainNoteWhateverTheEffect() {
        assertEquals("E5", GridCellText.title(e5, NoteEffect.SLIDE_UP))
        assertEquals("E5", GridCellText.title(e5, NoteEffect.VIBRATO))
        assertEquals("E5", GridCellText.title(e5, NoteEffect.NONE))
    }

    @Test fun restsAndEmptyStepsKeepTheirPlainTitles() {
        assertEquals("REST", GridCellText.title(Chip.NOTE_OFF, NoteEffect.VIBRATO))
        assertEquals("·", GridCellText.title(Chip.EMPTY_NOTE, NoteEffect.NONE))
    }

    @Test fun onlyANoteWithAnEffectCarriesAMark() {
        assertEquals(NoteEffect.SLIDE_UP, GridCellText.mark(e5, NoteEffect.SLIDE_UP))
        assertEquals(null, GridCellText.mark(e5, NoteEffect.NONE))
        assertEquals(null, GridCellText.mark(Chip.NOTE_OFF, NoteEffect.VIBRATO))
        assertEquals(null, GridCellText.mark(Chip.EMPTY_NOTE, NoteEffect.VIBRATO))
    }

    /** What the Grid video draws for a cell. */
    @Test fun titleAndMarkReadTheCellFromAPattern() {
        val pattern = Pattern(name = "A", length = 16, trackCount = 2)
            .withNote(1, 3, e5)
            .withEffect(1, 3, NoteEffect.GLIDE)
        assertEquals("E5", GridCellText.title(pattern, 1, 3))
        assertEquals(NoteEffect.GLIDE, GridCellText.mark(pattern, 1, 3))
        assertEquals("·", GridCellText.title(pattern, 0, 3))
        assertEquals(null, GridCellText.mark(pattern, 0, 3))
        // A track past the pattern's rows reads as empty.
        assertEquals("·", GridCellText.title(pattern, 5, 3))
        assertEquals(null, GridCellText.mark(pattern, 5, 3))
    }

    @Test fun spokenValueNamesTheEffect() {
        assertEquals("E5, Vibrato", GridCellText.accessibilityValue(e5, NoteEffect.VIBRATO))
        assertEquals("E5", GridCellText.accessibilityValue(e5, NoteEffect.NONE))
        assertEquals("REST", GridCellText.accessibilityValue(Chip.NOTE_OFF, NoteEffect.NONE))
        assertEquals("Empty", GridCellText.accessibilityValue(Chip.EMPTY_NOTE, NoteEffect.NONE))
    }

    @Test fun actionNamesSayEffect() {
        assertEquals("No effect", GridCellText.actionName(NoteEffect.NONE))
        assertEquals("Effect: Bend in", GridCellText.actionName(NoteEffect.BEND_IN))
    }

    @Test fun onlyPitchesOfferEffects() {
        assertTrue(GridCellText.offersEffects(0))
        assertTrue(GridCellText.offersEffects(127))
        assertFalse(GridCellText.offersEffects(Chip.NOTE_OFF))
        assertFalse(GridCellText.offersEffects(Chip.EMPTY_NOTE))
    }

    @Test fun menuListsNoEffectThenEachEffectInOrder() {
        assertEquals(
            listOf(NoteEffect.NONE, NoteEffect.SLIDE_UP, NoteEffect.SLIDE_DOWN, NoteEffect.VIBRATO, NoteEffect.GLIDE, NoteEffect.BEND_IN),
            GridCellText.menuEffects,
        )
    }
}
