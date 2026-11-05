package dev.individuation.chiptune.ui.editor

import dev.individuation.chiptune.core.studio.HelpGuide
import org.junit.Assert.assertEquals
import org.junit.Test

/** Only one surface is up at a time here, so the (?) on a sheet swaps the sheet
 * for the guide, and Done has to bring the sheet back. */
class PresentedGuideTest {
    @Test fun theGuideOverASheetReturnsToThatSheet() {
        val guide = Presented.Arrangement.openingGuide(HelpGuide.SectionId.ARRANGEMENT)
        assertEquals(Presented.Guide(HelpGuide.SectionId.ARRANGEMENT, Presented.Arrangement), guide)
        assertEquals(Presented.Arrangement, guide.afterClosing)
    }

    @Test fun theGuideOverTheSoundSheetReturnsToTheSameTrack() {
        val sound = Presented.InstrumentEditor(track = 2)
        assertEquals(sound, sound.openingGuide(HelpGuide.SectionId.SOUND).afterClosing)
    }

    @Test fun theGuideOverTheEditorReturnsToNothing() {
        assertEquals(Presented.None, Presented.None.openingGuide(null).afterClosing)
    }

    @Test fun theGuideKeepsTheSoundSheetSongBound() {
        val guide = Presented.InstrumentEditor(track = 0).openingGuide(HelpGuide.SectionId.SOUND)
        assertEquals(Presented.InstrumentEditor(track = 0).songBoundSurface, guide.songBoundSurface)
    }
}
