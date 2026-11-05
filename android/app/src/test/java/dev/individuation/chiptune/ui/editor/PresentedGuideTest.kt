package dev.individuation.chiptune.ui.editor

import dev.individuation.chiptune.core.studio.HelpGuide
import org.junit.Assert.assertEquals
import org.junit.Test

/** The guide opens over the sheet its (?) sits on. That sheet stays up beneath it,
 * so it comes back as it was left, and Done lands on it. */
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

    @Test fun theSheetStaysUpBeneathTheGuide() {
        val guide = Presented.Arrangement.openingGuide(HelpGuide.SectionId.ARRANGEMENT)
        assertEquals(Presented.Arrangement, guide.base)
    }

    @Test fun theSoundSheetStaysUpBeneathTheGuide() {
        val sound = Presented.InstrumentEditor(track = 2)
        assertEquals(sound, sound.openingGuide(HelpGuide.SectionId.SOUND).base)
    }

    @Test fun theGuideOverTheEditorHasNothingBeneathIt() {
        assertEquals(Presented.None, Presented.None.openingGuide(null).base)
    }

    @Test fun anythingElseIsItsOwnBase() {
        assertEquals(Presented.Songs, Presented.Songs.base)
        assertEquals(Presented.None, Presented.None.base)
    }
}
