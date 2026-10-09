package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.audio.withTrack
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `StudioEditingTests.swift`: every editing operation, checked on two
 * fronts -- the model ends up where it should, and the DSP core agrees. */
class StudioEditingTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val temp get() = h.temp

    @Before
    fun setUp() {
        h = StudioHarness()
        // A Studio on an empty store seeds the demo riff; every test starts blank.
        studio.open(Song.create("Blank"))
    }

    @After
    fun tearDown() = h.close()

    private fun assertCoreMatchesModel(message: String = "") {
        val core = studio.core
        assertEquals("core track count $message", studio.song.tracks.size, core.trackCount)
        assertEquals("core pattern count $message", studio.song.patterns.size, core.patternCount)
        assertEquals("core chain length $message", studio.song.chain.size, core.chainCount)
        assertTrue("selected pattern out of range $message", studio.selectedPattern in studio.song.patterns.indices)
        assertTrue("selected track out of range $message", studio.selectedTrack in studio.song.tracks.indices)
    }

    // MARK: The note-off arm

    @Test fun offTogglesBackToThePreviousPitch() {
        studio.selectedNote = 64
        studio.toggleNoteOff()
        assertEquals(Chip.NOTE_OFF, studio.selectedNote)
        studio.toggleNoteOff()
        assertEquals("a second tap should disarm back to the pitch", 64, studio.selectedNote)
    }

    @Test fun offReturnsToTheLastTypedNote() {
        studio.typeNote(55)
        studio.toggleNoteOff()
        studio.toggleNoteOff()
        assertEquals(55, studio.selectedNote)
    }

    @Test fun offFromAFreshStudioReturnsToMiddleC() {
        studio.toggleNoteOff()
        studio.toggleNoteOff()
        assertEquals(60, studio.selectedNote)
    }

    @Test fun selectingAPitchWhileOffIsArmedReplacesRatherThanRestores() {
        studio.selectedNote = 64
        studio.toggleNoteOff()
        studio.selectedNote = 72
        studio.toggleNoteOff()
        assertEquals(Chip.NOTE_OFF, studio.selectedNote)
        studio.toggleNoteOff()
        assertEquals(72, studio.selectedNote)
    }

    @Test fun armingOffTwiceStillDisarmsToAPitch() {
        studio.selectedNote = 67
        studio.selectedNote = Chip.NOTE_OFF
        studio.selectedNote = Chip.NOTE_OFF
        studio.toggleNoteOff()
        assertEquals(67, studio.selectedNote)
    }

    // MARK: Patterns

    @Test fun addPatternAppendsToTheArrangementAndSelectsIt() {
        val before = studio.song.patterns.size
        val index = studio.addPattern()
        assertEquals(before, index)
        assertEquals(before + 1, studio.song.patterns.size)
        assertEquals("a new pattern should be the one you're editing", before, studio.selectedPattern)
        assertEquals(studio.song.patterns.last().id, studio.song.arrangement.last().patternID)
        assertCoreMatchesModel("after addPattern")
    }

    @Test fun addPatternStopsAtTheLimit() {
        while (studio.song.canAddPattern) studio.addPattern()
        assertEquals(Chip.MAX_PATTERNS, studio.song.patterns.size)
        assertNull("adding past the limit must report failure, not wrap", studio.addPattern())
        assertEquals(Chip.MAX_PATTERNS, studio.song.patterns.size)
        assertCoreMatchesModel("at the pattern limit")
    }

    @Test fun duplicatePatternCopiesNotesUnderAFreshIdentity() {
        studio.setNote(0, 3, 64)
        studio.duplicatePattern(0)
        assertEquals(2, studio.song.patterns.size)
        assertEquals(1, studio.selectedPattern)
        assertEquals("the copy should carry the notes", 64, studio.song.patterns[1].rows[0][3])
        assertNotEquals(studio.song.patterns[0].id, studio.song.patterns[1].id)
        studio.setNote(0, 3, 70)
        assertEquals(64, studio.song.patterns[0].rows[0][3])
        assertCoreMatchesModel("after duplicatePattern")
    }

    @Test fun removePatternDropsItsArrangementSectionsAndClampsSelection() {
        studio.addPattern()
        studio.addPattern()
        val doomed = studio.song.patterns[2].id
        studio.selectPattern(2)
        studio.removePattern(2)
        assertEquals(2, studio.song.patterns.size)
        assertFalse(studio.song.arrangement.any { it.patternID == doomed })
        assertEquals("selection should fall back, not dangle", 1, studio.selectedPattern)
        assertCoreMatchesModel("after removePattern")
    }

    @Test fun removingAPatternBeforeTheSelectedOneKeepsEditingIt() {
        repeat(3) { studio.addPattern() }
        studio.selectPattern(2)
        val edited = studio.song.patterns[2].id
        studio.removePattern(0)
        assertEquals(1, studio.selectedPattern)
        assertEquals(edited, studio.song.patterns[studio.selectedPattern].id)
        assertEquals("the core should follow the selection", studio.selectedPattern, studio.core.focusPattern)
        assertCoreMatchesModel()
    }

    @Test fun removingAPatternAfterTheSelectedOneKeepsEditingIt() {
        repeat(3) { studio.addPattern() }
        studio.selectPattern(1)
        val edited = studio.song.patterns[1].id
        studio.removePattern(3)
        assertEquals(1, studio.selectedPattern)
        assertEquals(edited, studio.song.patterns[studio.selectedPattern].id)
        assertEquals(studio.selectedPattern, studio.core.focusPattern)
        assertCoreMatchesModel()
    }

    @Test fun selectingAShorterPatternPullsTheCursorInside() {
        studio.addPattern()
        studio.setPatternLength(4)
        studio.selectPattern(0)
        studio.selectedStep = studio.patternLength - 1
        assertTrue(studio.selectedStep > 3)
        studio.selectPattern(1)
        assertEquals("the cursor should clamp to the shorter pattern", 3, studio.selectedStep)
    }

    @Test fun theLastPatternCannotBeRemoved() {
        assertEquals(1, studio.song.patterns.size)
        studio.removePattern(0)
        assertEquals(1, studio.song.patterns.size)
        assertCoreMatchesModel()
    }

    @Test fun patternLettersAreReused() {
        studio.addPattern()
        assertEquals("B", studio.song.patterns[1].name)
        studio.removePattern(1)
        studio.addPattern()
        assertEquals("B", studio.song.patterns[1].name)
    }

    @Test fun renamePatternTrimsAndRejectsBlanks() {
        studio.renamePattern(0, "  Intro  ")
        assertEquals("Intro", studio.song.patterns[0].name)
        studio.renamePattern(0, "   ")
        assertEquals("a blank rename must be ignored", "Intro", studio.song.patterns[0].name)
        studio.renamePattern(0, "abcdefghij")
        assertEquals("names are capped at six characters", "abcdef", studio.song.patterns[0].name)
    }

    // MARK: Tracks

    @Test fun addTrackGivesEveryPatternAMatchingRow() {
        studio.addPattern()
        studio.addPattern()
        val before = studio.song.tracks.size
        studio.addTrack(ChannelKind.PULSE2)
        assertEquals(before + 1, studio.song.tracks.size)
        assertEquals(before, studio.selectedTrack)
        for ((i, p) in studio.song.patterns.withIndex()) assertEquals("pattern $i", before + 1, p.rows.size)
        assertCoreMatchesModel("after addTrack")
    }

    @Test fun duplicateTrackCopiesItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(1, 2, 60)
        studio.selectPattern(1)
        studio.setNote(1, 5, 67)
        studio.duplicateTrack(1)
        assertEquals(2, studio.selectedTrack)
        assertEquals(60, studio.song.patterns[0].rows[2][2])
        assertEquals(67, studio.song.patterns[1].rows[2][5])
        assertNotEquals(studio.song.tracks[1].id, studio.song.tracks[2].id)
        for (p in studio.song.patterns) assertEquals(studio.song.tracks.size, p.rows.size)
        assertCoreMatchesModel("after duplicateTrack")
    }

    @Test fun removeTrackRemovesItsRowFromEveryPatternInLockstep() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(2, 1, 48)
        studio.selectPattern(1)
        studio.setNote(2, 1, 50)
        studio.removeTrack(1)
        assertEquals(3, studio.song.tracks.size)
        for (p in studio.song.patterns) assertEquals(3, p.rows.size)
        assertEquals(48, studio.song.patterns[0].rows[1][1])
        assertEquals(50, studio.song.patterns[1].rows[1][1])
        assertCoreMatchesModel("after removeTrack")
    }

    @Test fun removingTheLastTrackIsRefused() {
        while (studio.song.tracks.size > 1) studio.removeTrack(0)
        studio.removeTrack(0)
        assertEquals(1, studio.song.tracks.size)
        assertCoreMatchesModel()
    }

    @Test fun selectionClampsWhenTheSelectedTrackIsDeleted() {
        studio.selectedTrack = 3
        studio.removeTrack(3)
        assertEquals(2, studio.selectedTrack)
        assertCoreMatchesModel()
    }

    @Test fun setKindResetsTheInstrumentButKeepsTheNotes() {
        studio.setNote(0, 0, 60)
        studio.edit { it.withInstrument(0) { i -> i.copy(volume = 0.11) } }
        studio.setKind(ChannelKind.NOISE, 0)
        assertEquals(ChannelKind.NOISE, studio.song.tracks[0].kind)
        assertEquals(Instrument.defaultFor(ChannelKind.NOISE), studio.song.tracks[0].instrument)
        assertEquals(60, studio.song.patterns[0].rows[0][0])
    }

    @Test fun setKindToTheSameKindLeavesTheInstrumentAlone() {
        studio.edit { it.withInstrument(0) { i -> i.copy(volume = 0.11) } }
        studio.setKind(studio.song.tracks[0].kind, 0)
        assertEquals(0.11, studio.song.tracks[0].instrument.volume, 0.0)
    }

    // MARK: Clearing

    @Test fun clearTrackOnlyTouchesTheSelectedPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(0, 0, 60)
        studio.selectPattern(1)
        studio.setNote(0, 0, 72)
        studio.clearTrack(0)
        assertEquals(Chip.EMPTY_NOTE, studio.song.patterns[1].rows[0][0])
        assertEquals(60, studio.song.patterns[0].rows[0][0])
    }

    @Test fun clearTrackInANamedPatternLeavesTheSelectedPatternAlone() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(0, 0, 60)
        studio.selectPattern(1)
        studio.setNote(0, 0, 72)
        studio.clearTrack(0, 0)
        assertEquals(Chip.EMPTY_NOTE, studio.song.patterns[0].rows[0][0])
        assertEquals(72, studio.song.patterns[1].rows[0][0])
        assertEquals(1, studio.selectedPattern)
        assertCoreMatchesModel()
    }

    @Test fun clearPatternAtIndexSurvivesThePlayheadMovingTheSelection() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(0, 0, 60)
        studio.selectPattern(1)
        studio.setNote(0, 0, 72)
        studio.selectPattern(0)
        studio.setSongMode(true)
        studio.isPlaying = true
        studio.applyPlayhead(0, 1)
        assertEquals("precondition", 1, studio.selectedPattern)

        studio.clearPattern(0)

        assertTrue(studio.song.patterns[0].isEmpty)
        assertEquals(72, studio.song.patterns[1].rows[0][0])
        assertCoreMatchesModel()
    }

    @Test fun clearPatternEmptiesEveryTrackInThatPatternOnly() {
        studio.addPattern()
        studio.selectPattern(0)
        for (t in 0 until 4) studio.setNote(t, t, 60)
        studio.selectPattern(1)
        for (t in 0 until 4) studio.setNote(t, t, 64)
        studio.clearPattern()
        assertTrue(studio.song.patterns[1].isEmpty)
        assertFalse(studio.song.patterns[0].isEmpty)
    }

    // MARK: Bounds

    @Test fun tempoIsClampedToTheSupportedRange() {
        studio.setTempo(1000.0)
        assertEquals(300.0, studio.song.tempo, 0.0)
        studio.setTempo(-5.0)
        assertEquals(40.0, studio.song.tempo, 0.0)
        studio.setTempo(174.0)
        assertEquals(174.0, studio.song.tempo, 0.0)
        assertEquals("the core must hear the new tempo", 174.0, studio.core.tempo, 0.0)
    }

    @Test fun patternLengthIsClampedToTheSupportedRange() {
        studio.setPatternLength(1000)
        assertEquals(Chip.MAX_STEPS, studio.patternLength)
        studio.setPatternLength(0)
        assertEquals(4, studio.patternLength)
    }

    @Test fun setNoteIgnoresOutOfRangeCoordinates() {
        studio.setNote(99, 0, 60)
        studio.setNote(0, 9999, 60)
        assertTrue(studio.song.patterns[0].isEmpty)
    }

    @Test fun toggleCellWritesThenClears() {
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
        studio.selectedNote = 67
        studio.toggleCell(0, 0)
        assertEquals(67, studio.note(0, 0))
        studio.toggleCell(0, 0)
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
    }

    @Test fun toggleCellOverwritesWithDifferentNote() {
        studio.selectedNote = 60
        studio.toggleCell(0, 0)
        assertEquals(60, studio.note(0, 0))
        studio.selectedNote = 67
        studio.toggleCell(0, 0)
        assertEquals(67, studio.note(0, 0))
        studio.toggleCell(0, 0)
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
    }

    @Test fun noteOffArmedFollowsTheSelectedNote() {
        assertFalse(studio.noteOffArmed)
        studio.toggleNoteOff()
        assertTrue(studio.noteOffArmed)
        assertTrue("the state flow carries it too", studio.state.value.noteOffArmed)
        studio.selectedNote = 64
        assertFalse(studio.noteOffArmed)
    }

    // MARK: Previewing a track

    @Test fun previewingATrackPlaysTheArmedPitch() {
        studio.selectedNote = 67
        assertEquals(67, studio.previewNote(0))
    }

    @Test fun previewingATrackFallsBackToMiddleCWhenOffIsArmed() {
        studio.toggleNoteOff()
        assertEquals(60, studio.previewNote(0))
    }

    @Test fun previewingANoiseTrackAlwaysUsesTheSameHit() {
        val index = studio.song.tracks.indexOfFirst { it.kind == ChannelKind.NOISE }
        studio.selectedNote = 36
        assertEquals(60, studio.previewNote(index))
    }

    @Test fun previewingAMutedTrackPlaysNothing() {
        studio.edit { it.withTrack(0) { t -> t.copy(muted = true) } }
        assertNull(studio.previewNote(0))
    }

    @Test fun previewingAMissingTrackPlaysNothing() {
        assertNull(studio.previewNote(99))
        assertNull(studio.previewNote(-1))
    }

    @Test fun previewingATrackDoesNotEditOrChangeTheSelection() {
        studio.selectedNote = 60
        studio.selectedTrack = 0
        val before = studio.song
        studio.previewTrack(1)
        assertEquals(before.patterns, studio.song.patterns)
        assertEquals(0, studio.selectedTrack)
        assertEquals(60, studio.selectedNote)
        assertFalse(studio.canUndo)
    }

    // MARK: Previewing a cell

    @Test fun previewingACellChangesNothing() {
        studio.selectedNote = 60
        studio.toggleCell(0, 3)
        studio.selectedNote = 72
        studio.selectedTrack = 1
        studio.selectedStep = 5
        studio.hardwareKeyboardInUse = true
        val before = studio.song
        val undoBefore = studio.canUndo

        assertTrue(studio.previewCell(0, 3))

        assertEquals(before.patterns, studio.song.patterns)
        assertEquals(72, studio.selectedNote)
        assertEquals(1, studio.selectedTrack)
        assertEquals(5, studio.selectedStep)
        assertEquals(undoBefore, studio.canUndo)
    }

    @Test fun previewingAnEmptyCellDoesNothingAtAll() {
        h.audio.startSucceeds = false
        assertFalse(studio.previewCell(0, 0))
        assertNull("an empty cell must not even reach the engine", studio.audioError)
        assertEquals(0, h.audio.starts)
    }

    @Test fun previewingANoteOffCellDoesNothingAtAll() {
        studio.toggleNoteOff()
        studio.toggleCell(0, 2)
        assertEquals(Chip.NOTE_OFF, studio.note(0, 2))
        h.audio.startSucceeds = false
        h.audio.stopEngine()
        assertFalse(studio.previewCell(0, 2))
        assertNull(studio.audioError)
    }

    @Test fun previewingAnOutOfRangeCellIsDropped() {
        assertFalse(studio.previewCell(99, 0))
        assertFalse(studio.previewCell(0, 9999))
        assertFalse(studio.previewCell(-1, -1))
    }

    @Test fun previewingACellDoesNotPinTheGrid() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.selectedNote = 60
        studio.toggleCell(0, 1)
        studio.songMode = true
        studio.isPlaying = true
        studio.selectPattern(studio.playingPattern)
        assertTrue("precondition", studio.followsArrangement)
        studio.previewCell(0, 1)
        assertTrue(studio.followsArrangement)
    }

    /** A preview that can't start audio says so, and one that can clears it. */
    @Test fun aPreviewThatCannotStartAudioReportsItAndARetryClearsIt() {
        studio.setNote(0, 0, 60)
        h.audio.startSucceeds = false
        h.audio.failure = AudioFocusDeniedException()
        assertTrue(studio.previewCell(0, 0))
        assertEquals("Another app or a call is using audio. Try again when it's finished.", studio.audioError)
        h.audio.startSucceeds = true
        studio.previewCell(0, 0)
        assertNull(studio.audioError)
    }

    // MARK: Arrangement

    @Test fun removingEveryArrangementSectionFallsBackToTheFirstPattern() {
        studio.removeSection(studio.song.arrangement.indices.toSet())
        assertEquals(1, studio.song.arrangement.size)
        assertEquals(studio.song.patterns[0].id, studio.song.arrangement[0].patternID)
    }

    @Test fun sectionRepeatsAreClamped() {
        val id = studio.song.arrangement[0].id
        studio.setSection(id, repeats = 9999)
        assertEquals(SongSection.MAX_REPEATS, studio.song.arrangement[0].repeats)
        studio.setSection(id, repeats = -4)
        assertEquals(1, studio.song.arrangement[0].repeats)
    }

    @Test fun repeatsEditsOnDifferentSectionsDoNotCoalesceIntoOneUndoStep() {
        studio.addSection(studio.song.patterns[0].id)
        val first = studio.song.arrangement[0].id
        val second = studio.song.arrangement[1].id
        studio.setSection(first, repeats = 3)
        studio.setSection(second, repeats = 5)
        studio.undo()
        assertEquals(1, studio.song.arrangement[1].repeats)
        assertEquals(3, studio.song.arrangement[0].repeats)
    }

    @Test fun arrangementChangesReachTheCore() {
        studio.addPattern()
        val id = studio.song.arrangement[0].id
        studio.setSection(id, repeats = 4)
        assertEquals(studio.song.chain.size, studio.core.chainCount)
        assertCoreMatchesModel()
    }

    @Test fun moveSectionFollowsArrayMoveSemantics() {
        studio.addPattern()
        studio.addPattern()
        val ids = studio.song.arrangement.map { it.id }
        studio.moveSection(setOf(0), 3)
        assertEquals(listOf(ids[1], ids[2], ids[0]), studio.song.arrangement.map { it.id })
        studio.moveSection(setOf(2), 0)
        assertEquals(ids, studio.song.arrangement.map { it.id })
        studio.moveSection(setOf(0, 2), 2)
        assertEquals(listOf(ids[1], ids[0], ids[2]), studio.song.arrangement.map { it.id })
    }

    // MARK: Instrument edits

    @Test fun instrumentEditsReachTheModelAndCheckpoint() {
        studio.setVolume(0, 0.3)
        studio.setDecay(0, 1.1)
        studio.setDuty(0, 1)
        studio.setSustain(0, true)
        studio.setArpeggio(0, listOf(0, 4, 7))
        studio.toggleMute(0)
        val inst = studio.song.tracks[0].instrument
        assertEquals(0.3, inst.volume, 0.0)
        assertEquals(1.1, inst.decay, 0.0)
        assertEquals(1, inst.duty)
        assertTrue(inst.sustain)
        assertEquals(listOf(0, 4, 7), inst.arpeggio)
        assertTrue(studio.song.tracks[0].muted)
        var undos = 0
        while (studio.canUndo) {
            studio.undo()
            undos += 1
        }
        assertEquals("six different controls are six steps", 6, undos)
        assertEquals(Song.create().tracks[0].instrument, studio.song.tracks[0].instrument)
    }

    @Test fun anInstrumentWriteThatChangesNothingIsNotAnEdit() {
        val volume = studio.song.tracks[0].instrument.volume
        studio.setVolume(0, volume)
        studio.setVolume(9, 0.5)
        assertFalse(studio.canUndo)
    }

    // MARK: Song lifecycle

    @Test fun openingASongResetsTheEditingCursor() {
        studio.addPattern()
        studio.selectPattern(1)
        studio.setSongMode(true)
        studio.open(Song.create("Other").copy(tempo = 90.0))
        assertEquals("Other", studio.song.name)
        assertEquals(0, studio.selectedPattern)
        assertFalse(studio.songMode)
        assertCoreMatchesModel("after open")
    }

    @Test fun newSongStartsEmptyAndIsPersisted() {
        studio.newSong()
        assertEquals("Untitled", studio.song.name)
        assertEquals(0, studio.selectedPattern)
        assertNotNull(temp.store.load(studio.song.id))
        assertCoreMatchesModel("after newSong")
    }

    @Test fun duplicateSongIsAnIndependentCopy() {
        studio.setNote(0, 0, 60)
        val original = studio.song.id
        studio.duplicateSong()
        assertNotEquals(original, studio.song.id)
        assertEquals("Blank copy", studio.song.name)
        assertEquals(60, studio.song.patterns[0].rows[0][0])
        assertNotNull(temp.store.load(original))
    }

    @Test fun duplicateCopiesALibrarySongWithoutOpeningIt() {
        val other = Song.create("Other")
        temp.save(other)
        val open = studio.song.id
        studio.duplicate(other)
        assertEquals(open, studio.song.id)
        assertTrue(temp.store.loadAll().any { it.name == "Other copy" && it.id != other.id })
    }
}
