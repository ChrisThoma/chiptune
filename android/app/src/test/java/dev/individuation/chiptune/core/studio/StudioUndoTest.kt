package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.assertSameSong
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Song
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `StudioUndoTests.swift`. */
class StudioUndoTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Undo"))
        studio.undoCoalescingWindow = 0.0
    }

    @After
    fun tearDown() = h.close()

    @Test fun nothingToUndoOnAFreshSong() {
        assertFalse(studio.canUndo)
        assertFalse(studio.canRedo)
        studio.undo()
        studio.redo()
        assertEquals("Undo", studio.song.name)
    }

    @Test fun undoRestoresTheSongExactly() {
        val before = studio.song
        studio.toggleCell(0, 4)
        assertTrue(studio.canUndo)
        assertNotEquals(Chip.EMPTY_NOTE, studio.song.patterns[0].rows[0][4])
        studio.undo()
        assertSameSong(studio.song, before, "undo did not restore the song")
        assertFalse(studio.canUndo)
        assertTrue(studio.canRedo)
        assertTrue("the state flow mirrors it", studio.state.value.canRedo)
    }

    @Test fun redoReappliesTheEdit() {
        studio.selectedNote = 67
        studio.toggleCell(0, 4)
        val after = studio.song
        studio.undo()
        studio.redo()
        assertSameSong(studio.song, after)
        assertTrue(studio.canUndo)
        assertFalse(studio.canRedo)
    }

    @Test fun aNewEditClearsTheRedoStack() {
        studio.toggleCell(0, 0)
        studio.undo()
        assertTrue(studio.canRedo)
        studio.toggleCell(1, 1)
        assertFalse(studio.canRedo)
    }

    @Test fun undoWalksBackThroughSeveralEdits() {
        val expected = ArrayList<Song>()
        for (step in 0 until 5) {
            expected.add(studio.song)
            studio.toggleCell(0, step)
        }
        for (step in 4 downTo 0) {
            studio.undo()
            assertSameSong(studio.song, expected[step], "undo step $step")
        }
        assertFalse(studio.canUndo)
    }

    @Test fun undoPushesTheRestoredSongIntoTheCore() {
        studio.addPattern()
        studio.addTrack(ChannelKind.NOISE)
        studio.setTempo(200.0)
        repeat(3) { studio.undo() }
        val core = studio.core
        assertEquals(studio.song.tracks.size, core.trackCount)
        assertEquals(studio.song.patterns.size, core.patternCount)
        assertEquals(studio.song.chain.size, core.chainCount)
        assertEquals(studio.song.tempo, core.tempo, 0.0)
    }

    @Test fun undoingAPatternDeleteRestoresTheSelection() {
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(2)
        studio.removePattern(2)
        assertEquals(1, studio.selectedPattern)
        studio.undo()
        assertEquals(3, studio.song.patterns.size)
        assertEquals("undo must put the cursor back too", 2, studio.selectedPattern)
    }

    @Test fun undoingWhilePlayingPinsTheGrid() {
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(0)
        studio.toggleCell(0, 3)
        studio.songMode = true
        studio.isPlaying = true
        studio.applyPlayhead(0, 1)
        assertTrue("precondition: still following", studio.followsArrangement)

        studio.undo()

        assertFalse(studio.followsArrangement)
        assertEquals(0, studio.selectedPattern)
        studio.applyPlayhead(0, 2)
        assertEquals("and the arrangement must not take it away", 0, studio.selectedPattern)
    }

    @Test fun undoingATrackDeleteRestoresTheSelection() {
        studio.selectedTrack = 3
        studio.removeTrack(3)
        assertEquals(2, studio.selectedTrack)
        studio.undo()
        assertEquals(4, studio.song.tracks.size)
        assertEquals(3, studio.selectedTrack)
    }

    @Test fun undoingATrackDeleteRestoresItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(1, 2, 60)
        studio.selectPattern(1)
        studio.setNote(1, 6, 72)
        val before = studio.song
        studio.removeTrack(1)
        assertEquals(3, studio.song.tracks.size)
        studio.undo()
        assertSameSong(studio.song, before)
        assertEquals(60, studio.song.patterns[0].rows[1][2])
        assertEquals(72, studio.song.patterns[1].rows[1][6])
    }

    @Test fun undoingAClearedPatternIsASingleStep() {
        for (t in 0 until 4) studio.setNote(t, t, 60)
        val before = studio.song
        studio.clearPattern()
        assertTrue(studio.song.patterns[0].isEmpty)
        studio.undo()
        assertSameSong(studio.song, before)
    }

    @Test fun undoingAClearedTrackIsASingleStep() {
        for (step in 0 until 8) studio.setNote(0, step, 60)
        val before = studio.song
        studio.clearTrack(0)
        studio.undo()
        assertSameSong(studio.song, before)
    }

    // MARK: Coalescing

    @Test fun editsInsideTheWindowCoalesceIntoOneStep() {
        studio.undoCoalescingWindow = 60.0
        val before = studio.song
        studio.selectedNote = 60
        for (step in 0 until 8) studio.toggleCell(0, step)
        studio.undo()
        assertSameSong(studio.song, before)
        assertFalse(studio.canUndo)
    }

    /** The window is measured on the injected clock, and is strict: an edit a
     * whole window later starts a new step, one just inside it does not. */
    @Test fun theWindowIsMeasuredOnTheInjectedClock() {
        studio.undoCoalescingWindow = 1.0
        studio.toggleCell(0, 0)
        h.scheduler.advance(0.75)
        studio.toggleCell(0, 1)
        h.scheduler.advance(0.75)
        studio.toggleCell(0, 2)
        h.scheduler.advance(1.0)
        studio.toggleCell(0, 3)
        studio.undo()
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 3))
        assertEquals("the folded stroke rolls its window forward", 60, studio.note(0, 2))
        studio.undo()
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
        assertFalse(studio.canUndo)
    }

    @Test fun theDefaultWindowIsOneSecondAndTheLimitFifty() {
        val fresh = StudioHarness()
        try {
            assertEquals(1.0, fresh.studio.undoCoalescingWindow, 0.0)
            assertEquals(50, fresh.studio.undoLimit)
        } finally {
            fresh.close()
        }
    }

    @Test fun differentInstrumentControlsDoNotCoalesce() {
        studio.undoCoalescingWindow = 60.0
        val original = studio.song.tracks[0].instrument
        studio.checkpoint(coalescing = true, kind = CheckpointKind.Volume(0))
        studio.edit { it.withInstrument(0) { i -> i.copy(volume = 0.2) } }
        studio.checkpoint(coalescing = true, kind = CheckpointKind.Decay(0))
        studio.edit { it.withInstrument(0) { i -> i.copy(decay = 1.2) } }
        studio.undo()
        assertEquals(0.2, studio.song.tracks[0].instrument.volume, 0.0)
        assertEquals(original.decay, studio.song.tracks[0].instrument.decay, 0.0)
    }

    @Test fun sameInstrumentControlOnDifferentTracksDoesNotCoalesce() {
        studio.undoCoalescingWindow = 60.0
        val originalSecond = studio.song.tracks[1].instrument.volume
        studio.checkpoint(coalescing = true, kind = CheckpointKind.Volume(0))
        studio.edit { it.withInstrument(0) { i -> i.copy(volume = 0.2) } }
        studio.checkpoint(coalescing = true, kind = CheckpointKind.Volume(1))
        studio.edit { it.withInstrument(1) { i -> i.copy(volume = 0.3) } }
        studio.undo()
        assertEquals(0.2, studio.song.tracks[0].instrument.volume, 0.0)
        assertEquals(originalSecond, studio.song.tracks[1].instrument.volume, 0.0)
    }

    @Test fun aSliderDragIsOneUndoStep() {
        studio.undoCoalescingWindow = 60.0
        val original = studio.song.tracks[0].instrument.volume
        for (v in listOf(0.1, 0.2, 0.3, 0.4)) studio.setVolume(0, v)
        studio.undo()
        assertEquals(original, studio.song.tracks[0].instrument.volume, 0.0)
        assertFalse(studio.canUndo)
    }

    @Test fun discreteEditsDoNotCoalesce() {
        studio.undoCoalescingWindow = 60.0
        studio.toggleCell(0, 0)
        studio.addPattern()
        studio.addTrack(ChannelKind.NOISE)
        studio.undo()
        assertEquals(4, studio.song.tracks.size)
        studio.undo()
        assertEquals(1, studio.song.patterns.size)
        studio.undo()
        assertEquals(Chip.EMPTY_NOTE, studio.song.patterns[0].rows[0][0])
    }

    @Test fun anEditAfterUndoDoesNotCoalesceWithTheUndoneStroke() {
        studio.undoCoalescingWindow = 60.0
        studio.toggleCell(0, 0)
        studio.undo()
        studio.toggleCell(1, 1)
        assertTrue(studio.canUndo)
        studio.undo()
        assertEquals(Chip.EMPTY_NOTE, studio.song.patterns[0].rows[1][1])
    }

    // MARK: Grid reveal

    @Test fun undoAndRedoEachRequestAReveal() {
        studio.toggleCell(0, 0)
        val start = studio.revealRequest.generation
        studio.undo()
        assertEquals(RevealRequest(start + 1, RevealRequest.Reason.UNDO_REDO), studio.revealRequest)
        studio.redo()
        assertEquals(RevealRequest(start + 2, RevealRequest.Reason.UNDO_REDO), studio.revealRequest)
    }

    @Test fun editsSelectionAndAnEmptyUndoRequestNoReveal() {
        val start = studio.revealRequest
        studio.undo()
        studio.redo()
        studio.toggleCell(0, 0)
        studio.selectedTrack = 2
        assertEquals(start, studio.revealRequest)
    }

    // MARK: Bounds and lifecycle

    @Test fun theStackIsCapped() {
        studio.undoLimit = 5
        studio.selectedNote = 60
        for (step in 0 until 20) studio.toggleCell(0, step)
        var undos = 0
        while (studio.canUndo) {
            studio.undo()
            undos += 1
            assertTrue(undos <= 5)
        }
        assertEquals(5, undos)
    }

    @Test fun openingASongClearsTheHistory() {
        studio.toggleCell(0, 0)
        assertTrue(studio.canUndo)
        studio.open(Song.create("Different"))
        assertFalse(studio.canUndo)
        assertFalse(studio.canRedo)
    }

    @Test fun newSongClearsTheHistory() {
        studio.toggleCell(0, 0)
        studio.undo()
        assertTrue(studio.canRedo)
        studio.newSong()
        assertFalse(studio.canUndo)
        assertFalse(studio.canRedo)
    }

    @Test fun pushingDoesNotRecordUndoSteps() {
        studio.toggleCell(0, 0)
        assertEquals(1, countUndoSteps())
        studio.pushAll()
        studio.pushArrangement()
        studio.pushTransport()
        assertEquals(1, countUndoSteps())
    }

    private fun countUndoSteps(): Int {
        var depth = 0
        while (studio.canUndo) {
            studio.undo()
            depth += 1
        }
        repeat(depth) { studio.redo() }
        return depth
    }
}

/** Port of `NoOpEditUndoTests.swift`: a write that changes nothing is not an edit. */
class NoOpEditUndoTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("NoOps"))
        studio.undoCoalescingWindow = 0.0
        studio.checkpoint()
        studio.edit { it.copy(tempo = 100.0) }
        studio.undo()
        assertTrue(studio.canRedo)
    }

    @After
    fun tearDown() = h.close()

    @Test fun sameTempoKeepsRedo() {
        studio.setTempo(studio.song.tempo)
        assertTrue(studio.canRedo)
    }

    @Test fun tempoThatClampsToCurrentKeepsRedo() {
        studio.edit { it.copy(tempo = 300.0) }
        studio.setTempo(999.0)
        assertTrue(studio.canRedo)
    }

    @Test fun realTempoChangeStillCheckpoints() {
        studio.setTempo(150.0)
        assertFalse(studio.canRedo)
        assertTrue(studio.canUndo)
    }

    @Test fun setSectionSamePatternKeepsRedo() {
        val section = studio.song.arrangement[0]
        studio.setSection(section.id, patternID = section.patternID)
        assertTrue(studio.canRedo)
    }

    @Test fun sectionRepeatsAtBoundKeepsRedo() {
        studio.setSection(studio.song.arrangement[0].id, repeats = 0)
        assertTrue(studio.canRedo)
    }

    @Test fun clearEmptyPatternKeepsRedo() {
        studio.clearPattern(0)
        assertTrue(studio.canRedo)
    }

    @Test fun clearEmptyTrackKeepsRedo() {
        studio.clearTrack(0, 0)
        assertTrue(studio.canRedo)
    }

    @Test fun clearFilledPatternStillCheckpoints() {
        studio.setNote(0, 0, 60)
        studio.clearPattern(0)
        assertFalse(studio.canRedo)
        assertEquals(Chip.EMPTY_NOTE, studio.pattern.rows[0][0])
    }

    @Test fun samePresetKeepsRedo() {
        val preset = InstrumentPreset.presetsFor(studio.song.tracks[0].kind)[0]
        studio.edit { it.withInstrument(0) { preset.instrument } }
        studio.applyPreset(preset, 0)
        assertTrue(studio.canRedo)
    }

    @Test fun aDifferentPresetCheckpointsAndReachesTheCore() {
        val preset = InstrumentPreset.presetsFor(studio.song.tracks[0].kind)[1]
        studio.applyPreset(preset, 0)
        assertFalse(studio.canRedo)
        assertEquals(preset.instrument, studio.song.tracks[0].instrument)
    }
}

/** Port of `NoOpHardwareWriteTests.swift`. */
class NoOpHardwareWriteTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("HW"))
        studio.undoCoalescingWindow = 0.0
        studio.setNote(0, 0, Chip.EMPTY_NOTE)
        studio.setNote(0, 1, Chip.EMPTY_NOTE)
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.checkpoint()
        studio.edit { it.copy(tempo = 100.0) }
        studio.undo()
        assertTrue(studio.canRedo)
    }

    @After
    fun tearDown() = h.close()

    @Test fun sameNoteKeepsRedoAndAdvances() {
        studio.setNote(0, 0, 60)
        studio.selectedStep = 0
        studio.typeNote(60)
        assertTrue(studio.canRedo)
        assertEquals(1, studio.selectedStep)
        assertEquals(60, studio.selectedNote)
    }

    @Test fun restOnRestKeepsRedo() {
        studio.setNote(0, 0, Chip.NOTE_OFF)
        studio.typeNote(Chip.NOTE_OFF)
        assertTrue(studio.canRedo)
        assertEquals(1, studio.selectedStep)
    }

    @Test fun deleteOnEmptyKeepsRedoAndAdvances() {
        studio.clearAtCursor()
        assertTrue(studio.canRedo)
        assertEquals(1, studio.selectedStep)
    }

    @Test fun differentNoteStillCheckpoints() {
        studio.setNote(0, 0, 60)
        studio.typeNote(62)
        assertFalse(studio.canRedo)
        assertEquals(62, studio.pattern.rows[0][0])
    }

    @Test fun deleteOnFilledStillCheckpoints() {
        studio.setNote(0, 0, 60)
        studio.clearAtCursor()
        assertFalse(studio.canRedo)
        assertEquals(Chip.EMPTY_NOTE, studio.pattern.rows[0][0])
    }
}

/** Port of `TrackNameUndoTests.swift`. */
class TrackNameUndoTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Names"))
    }

    @After
    fun tearDown() = h.close()

    @Test fun renamingATrackOnceIsOneUndoStep() {
        val original = studio.song.tracks[0].name
        studio.undoCoalescingWindow = 0.0
        studio.setTrackName("Lead", 0)
        assertEquals("Lead", studio.song.tracks[0].name)
        studio.undo()
        assertEquals(original, studio.song.tracks[0].name)
        assertFalse(studio.canUndo)
        assertTrue(studio.canRedo)
    }

    @Test fun writingTheSameNameCreatesNoUndoStep() {
        studio.undoCoalescingWindow = 0.0
        studio.setTrackName("Lead", 0)
        studio.undo()
        studio.redo()
        studio.setTrackName("Lead", 0)
        studio.setTrackName("Lead", 0)
        studio.undo()
        assertNull(studio.song.tracks[0].name)
        assertFalse(studio.canUndo)
    }

    @Test fun writingAnEmptyNameToAnUnnamedTrackCreatesNoUndoStep() {
        assertNull(studio.song.tracks[0].name)
        studio.setTrackName("", 0)
        studio.setTrackName("   ", 0)
        assertFalse(studio.canUndo)
    }

    @Test fun typingRunInsideTheWindowIsOneStep() {
        studio.undoCoalescingWindow = 60.0
        for (text in listOf("A", "Al", "Alp", "Alph", "Alpha")) studio.setTrackName(text, 0)
        studio.undo()
        assertNull(studio.song.tracks[0].name)
        assertFalse(studio.canUndo)
    }

    @Test fun separateRunsUndoOneAtATimeWithNoNoOps() {
        studio.undoCoalescingWindow = 0.0
        studio.setTrackName("Alpha", 0)
        studio.setTrackName("Alphabet", 0)
        studio.setTrackName("Alphabet", 0)
        studio.setTrackName("", 0)
        studio.setTrackName("", 0)
        val seen = ArrayList<String?>()
        while (studio.canUndo) {
            studio.undo()
            seen.add(studio.song.tracks[0].name)
            assertTrue(seen.size < 10)
        }
        assertEquals(3, seen.size)
        assertEquals("Alphabet", seen[0])
        assertEquals("Alpha", seen[1])
        assertNull(seen[2])
    }

    @Test fun aLongNameIsCappedAtSixteenCharacters() {
        studio.setTrackName("A very long track name", 0)
        assertEquals("A very long trac", studio.song.tracks[0].name)
    }

    @Test fun renamingAPatternToItsCurrentNameCreatesNoUndoStep() {
        studio.renamePattern(0, studio.song.patterns[0].name)
        assertFalse(studio.canUndo)
    }

    @Test fun songTitleWriteOfTheSameNameCreatesNoUndoStep() {
        studio.setSongName(studio.song.name)
        assertFalse(studio.canUndo)
    }
}
