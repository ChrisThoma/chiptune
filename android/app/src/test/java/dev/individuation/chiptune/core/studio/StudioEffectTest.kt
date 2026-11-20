package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.assertSameSong
import dev.individuation.chiptune.core.audio.PitchMeter
import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.NoteEffect
import dev.individuation.chiptune.core.model.Song
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Twin of the Swift Studio effect tests: setting an effect is one undo step,
 * cell edits keep or clear it as the plan says, every row operation keeps
 * effects aligned with notes, and the core always holds what the model does. */
class StudioEffectTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
        studio.undoCoalescingWindow = 0.0
    }

    @After
    fun tearDown() = h.close()

    /** Every cell of every pattern: the core's effect is the model's. */
    private fun assertCoreEffectsMatchModel(message: String = "") {
        for ((p, pattern) in studio.song.patterns.withIndex()) {
            for (track in studio.song.tracks.indices) {
                for (step in 0 until Chip.MAX_STEPS) {
                    assertEquals("pattern $p track $track step $step $message",
                        pattern.effect(track, step), studio.core.effect(p, track, step))
                }
            }
        }
    }

    private fun noteWithEffect(track: Int, step: Int, note: Int, effect: NoteEffect) {
        studio.setNote(track, step, note)
        studio.setEffect(track, step, effect)
    }

    // MARK: Setting

    @Test fun setEffectIsOneUndoStep() {
        studio.setNote(0, 2, 64)
        val before = studio.song
        studio.setEffect(0, 2, NoteEffect.VIBRATO)
        assertEquals(NoteEffect.VIBRATO, studio.effect(0, 2))
        assertEquals(NoteEffect.VIBRATO, studio.core.effect(0, 0, 2))
        assertTrue(studio.canUndo)
        studio.undo()
        assertSameSong(studio.song, before)
        assertEquals(NoteEffect.NONE, studio.effect(0, 2))
        assertCoreEffectsMatchModel("after undo")
        studio.redo()
        assertEquals(NoteEffect.VIBRATO, studio.effect(0, 2))
        assertCoreEffectsMatchModel("after redo")
    }

    @Test fun twoEffectsAreTwoUndoSteps() {
        studio.setNote(0, 2, 64)
        studio.setEffect(0, 2, NoteEffect.VIBRATO)
        studio.setEffect(0, 2, NoteEffect.GLIDE)
        studio.undo()
        assertEquals(NoteEffect.VIBRATO, studio.effect(0, 2))
    }

    @Test fun settingTheSameEffectIsNotAnEdit() {
        studio.setNote(0, 2, 64)
        studio.setEffect(0, 2, NoteEffect.VIBRATO)
        studio.undo()
        studio.setEffect(0, 2, NoteEffect.NONE)
        assertTrue("a no-op effect write wiped Redo", studio.canRedo)
    }

    @Test fun anEmptyOrOffCellTakesNoEffect() {
        studio.setEffect(0, 1, NoteEffect.SLIDE_UP)
        assertEquals(NoteEffect.NONE, studio.effect(0, 1))
        studio.setNote(0, 3, Chip.NOTE_OFF)
        studio.setEffect(0, 3, NoteEffect.SLIDE_UP)
        assertEquals(NoteEffect.NONE, studio.effect(0, 3))
        assertFalse(studio.song.patterns[0].hasEffects)
    }

    // MARK: Cell edits

    @Test fun clearingTheNoteClearsItsEffect() {
        studio.selectedNote = 64
        studio.toggleCell(0, 0)
        studio.setEffect(0, 0, NoteEffect.SLIDE_UP)
        studio.toggleCell(0, 0) // same note: clears
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
        assertEquals(NoteEffect.NONE, studio.effect(0, 0))
        assertCoreEffectsMatchModel()
    }

    @Test fun offOverANoteClearsItsEffect() {
        noteWithEffect(0, 0, 64, NoteEffect.SLIDE_DOWN)
        studio.selectedNote = Chip.NOTE_OFF
        studio.toggleCell(0, 0)
        assertEquals(Chip.NOTE_OFF, studio.note(0, 0))
        assertEquals(NoteEffect.NONE, studio.effect(0, 0))
        assertCoreEffectsMatchModel()
    }

    @Test fun clearAtCursorClearsTheEffect() {
        noteWithEffect(0, 0, 64, NoteEffect.SLIDE_DOWN)
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.clearAtCursor()
        assertEquals(NoteEffect.NONE, studio.effect(0, 0))
        assertCoreEffectsMatchModel()
    }

    @Test fun typingANewPitchOverANoteKeepsItsEffect() {
        noteWithEffect(0, 0, 64, NoteEffect.BEND_IN)
        studio.selectedNote = 67
        studio.toggleCell(0, 0)
        assertEquals(67, studio.note(0, 0))
        assertEquals(NoteEffect.BEND_IN, studio.effect(0, 0))

        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.typeNote(69)
        assertEquals(69, studio.note(0, 0))
        assertEquals(NoteEffect.BEND_IN, studio.effect(0, 0))
        assertCoreEffectsMatchModel()
    }

    @Test fun clearTrackAndClearPatternClearEffects() {
        noteWithEffect(0, 0, 64, NoteEffect.VIBRATO)
        noteWithEffect(1, 4, 60, NoteEffect.GLIDE)
        studio.clearTrack(0)
        assertEquals(NoteEffect.NONE, studio.effect(0, 0))
        assertEquals(NoteEffect.GLIDE, studio.effect(1, 4))
        assertCoreEffectsMatchModel("after clear track")
        studio.clearPattern()
        assertFalse(studio.song.patterns[0].hasEffects)
        assertCoreEffectsMatchModel("after clear pattern")
        studio.undo()
        assertEquals(NoteEffect.GLIDE, studio.effect(1, 4))
        assertCoreEffectsMatchModel("after undoing the clear")
    }

    // MARK: Row operations

    /** Each track's notes and effects, as one list per track, for alignment checks. */
    private fun cells(): List<List<Pair<Int, NoteEffect>>> =
        studio.song.tracks.indices.map { t ->
            (0 until Chip.MAX_STEPS).map { s -> studio.note(t, s) to studio.effect(t, s) }
        }

    private fun seedEffects() {
        noteWithEffect(0, 0, 72, NoteEffect.SLIDE_UP)
        noteWithEffect(1, 1, 64, NoteEffect.VIBRATO)
        noteWithEffect(2, 2, 48, NoteEffect.GLIDE)
        noteWithEffect(3, 3, 60, NoteEffect.SLIDE_DOWN)
    }

    @Test fun moveTrackCarriesItsEffects() {
        seedEffects()
        val before = cells()
        studio.moveTrack(0, 2)
        val after = cells()
        assertEquals(before[0], after[2])
        assertEquals(before[1], after[0])
        assertEquals(before[2], after[1])
        assertEquals(before[3], after[3])
        assertCoreEffectsMatchModel()
    }

    @Test fun removeTrackKeepsTheOthersAligned() {
        seedEffects()
        val before = cells()
        studio.removeTrack(1)
        assertEquals(listOf(before[0], before[2], before[3]), cells())
        assertCoreEffectsMatchModel()
        studio.undo()
        assertEquals(before, cells())
        assertCoreEffectsMatchModel("after undo")
    }

    @Test fun duplicateTrackCopiesEffects() {
        seedEffects()
        val before = cells()
        studio.duplicateTrack(1)
        assertEquals(listOf(before[0], before[1], before[1], before[2], before[3]), cells())
        assertCoreEffectsMatchModel()
    }

    @Test fun addTrackAddsARowWithoutEffects() {
        seedEffects()
        val before = cells()
        studio.addTrack(ChannelKind.PULSE1)
        val after = cells()
        assertEquals(before, after.take(4))
        assertTrue(after[4].all { it.second == NoteEffect.NONE })
        assertCoreEffectsMatchModel()
    }

    @Test fun duplicatePatternCopiesEffects() {
        seedEffects()
        val before = cells()
        studio.duplicatePattern(0)
        assertEquals(1, studio.selectedPattern)
        assertEquals(before, cells())
        assertCoreEffectsMatchModel()
    }

    @Test fun changingKindKeepsEffects() {
        seedEffects()
        val before = cells()
        studio.setKind(ChannelKind.TRIANGLE, 0)
        assertEquals(before, cells())
        assertCoreEffectsMatchModel()
    }

    @Test fun openingASongWithEffectsLoadsThemIntoTheCore() {
        val song = Song.create("Fx").let {
            it.copy(patterns = it.patterns.map { p -> p.withNote(0, 0, 60).withEffect(0, 0, NoteEffect.VIBRATO) })
        }
        studio.open(song)
        assertEquals(NoteEffect.VIBRATO, studio.effect(0, 0))
        assertCoreEffectsMatchModel()
    }

    // MARK: Preview

    @Test fun previewingACellAuditionsItsEffect() {
        studio.edit { it.withInstrument(0) { i -> i.copy(sustain = true, volume = 1.0, duty = 2, arpeggio = emptyList()) } }
        studio.pushInstrument(0)
        noteWithEffect(0, 0, 60, NoteEffect.SLIDE_UP)
        assertTrue(studio.previewCell(0, 0))
        val step = samplesPerStep(studio.song.tempo)
        val samples = RenderHarness.renderMono(studio.core, step * 2)
        val start = PitchMeter.frequency(samples, 200, 1400)
        val later = PitchMeter.frequency(samples, step + 200, step + 1400)
        assertTrue("a slide-up preview did not rise ($start -> $later)", later / start > 1.6)
    }
}
