package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.audio.withTrack
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private const val SR = 44100.0

private fun Studio.render(seconds: Double): FloatArray =
    RenderHarness.renderMono(core, (SR * seconds).toInt())

private fun FloatArray.tailRms(): Double = RenderHarness.rms(this, size - 4410, size)

private fun FloatArray.afterFirstTenth(): Double = RenderHarness.rms(this, 4410, size)

/** A sustaining instrument at full level. */
private fun Track.held(): Track = copy(instrument = instrument.copy(sustain = true, volume = 1.0))

/** Port of `StudioSustainTests.swift`: erasing the note that started a held
 * voice must cut it, and nothing else may. */
class StudioSustainTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
    }

    @After
    fun tearDown() = h.close()

    private fun openHeldNote(extraNoteAt: Int? = null) {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW)).withNote(0, 0, 48) }
        if (extraNoteAt != null) song = song.withPattern(0) { it.withNote(0, extraNoteAt, 60) }
        studio.open(song)
        studio.core.start()
    }

    @Test fun clearingTheNoteThatStartedARingingVoiceCutsIt() {
        openHeldNote()
        assertTrue(studio.render(0.5).tailRms() > 0.01)
        studio.setNote(0, 0, Chip.EMPTY_NOTE)
        assertTrue("erasing the note that started it left the voice ringing", studio.render(0.2).tailRms() < 0.01)
    }

    @Test fun clearingAnUnrelatedStepLeavesTheRingingVoiceAlone() {
        openHeldNote(extraNoteAt = 8)
        assertTrue(studio.render(0.5).tailRms() > 0.01)
        studio.setNote(0, 8, Chip.EMPTY_NOTE)
        assertTrue("clearing an unrelated step cut a voice", studio.render(0.2).tailRms() > 0.01)
    }

    @Test fun clearingTheWholeTrackCutsIt() {
        openHeldNote()
        studio.render(0.5)
        studio.clearTrack(0)
        assertTrue(studio.render(0.2).afterFirstTenth() < 0.01)
    }

    @Test fun clearPatternOnlyCutsVoicesFromThatPattern() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW)).withNote(0, 0, 48) }
        song = song.copy(patterns = song.patterns + Pattern(name = "B", length = 16, trackCount = 1))
        song = song.copy(arrangement = song.patterns.map { SongSection(patternID = it.id) })
        studio.open(song)
        studio.core.start()
        studio.render(0.5)

        studio.clearPattern(1)
        assertTrue("clearing another pattern cut a note", studio.render(0.2).afterFirstTenth() > 0.01)

        studio.clearPattern(0)
        assertTrue("clearing the source pattern left it ringing", studio.render(0.2).afterFirstTenth() < 0.01)
    }

    @Test fun undoDoesNotLeaveAClearedNoteRinging() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW)) }
        studio.open(song)
        studio.core.start()

        studio.checkpoint()
        studio.setNote(0, 0, 48)
        assertTrue(studio.render(0.5).afterFirstTenth() > 0.01)

        studio.undo()

        assertTrue("undoing the note left the voice ringing", studio.render(0.2).afterFirstTenth() < 0.01)
    }

    @Test fun removingATrackCutsItsHeldNote() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.PULSE1), Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW)).withNote(1, 0, 48) }
        studio.open(song)
        studio.core.start()
        studio.render(0.5)

        studio.removeTrack(1)

        assertTrue(studio.render(0.2).afterFirstTenth() < 0.01)
    }

    @Test fun previewingAMutedTrackDoesNotStealItsRingingVoice() {
        openHeldNote()
        studio.render(0.3)
        val source = studio.core.ringingSource(0)
        assertNotNull("precondition", source)

        studio.edit { it.withTrack(0) { t -> t.copy(muted = true) } }
        studio.pushInstrument(0)
        studio.previewTrack(0)

        assertEquals(source?.step, studio.core.ringingSource(0)?.step)

        studio.edit { it.withTrack(0) { t -> t.copy(muted = false) } }
        studio.pushInstrument(0)
        studio.setNote(0, 0, Chip.EMPTY_NOTE)
        assertTrue(studio.render(0.2).afterFirstTenth() < 0.01)
    }

    @Test fun previewingACellPlaysThatCellsNoteOnThatCellsTrack() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held().copy(muted = true),
            Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW)).withNote(1, 4, 69) }
        studio.open(song)
        studio.selectedTrack = 0
        studio.selectedNote = 48

        studio.previewCell(1, 4)
        val rendered = studio.render(0.4)

        assertTrue(RenderHarness.rms(rendered, 4410, 4410 + 8820) > 0.01)
        val dominant = RenderHarness.dominantFrequency(rendered, 4410, 4410 + 8820, RenderHarness.semitoneLadder(69))
        assertEquals(NoteName.frequency(69), dominant ?: 0.0, 0.001)
    }
}

/** Port of `StudioTrackMoveTests.swift`. */
class StudioTrackMoveTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val trackIDs: List<UUID> get() = studio.song.tracks.map { it.id }

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
    }

    @After
    fun tearDown() = h.close()

    @Test fun movingATrackCarriesItsNotesInEveryPattern() {
        studio.addPattern()
        studio.selectPattern(0)
        studio.setNote(0, 3, 60)
        studio.selectPattern(1)
        studio.setNote(0, 7, 67)
        val moved = studio.song.tracks[0].id

        studio.moveTrack(0, 2)

        assertEquals(moved, studio.song.tracks[2].id)
        assertEquals(60, studio.song.patterns[0].rows[2][3])
        assertEquals(67, studio.song.patterns[1].rows[2][7])
        assertEquals(Chip.EMPTY_NOTE, studio.song.patterns[0].rows[0][3])
        for (p in studio.song.patterns) assertEquals(studio.song.tracks.size, p.rows.size)
    }

    @Test fun movingATrackKeepsItsSoundMuteAndName() {
        studio.edit {
            it.withTrack(3) { t -> t.copy(muted = true, name = "Hats") }.withInstrument(3) { i -> i.copy(volume = 0.3) }
        }
        val before = studio.song.tracks[3]
        studio.moveTrack(3, 0)
        assertEquals(before, studio.song.tracks[0])
    }

    @Test fun theOtherTracksCloseUpInOrder() {
        val ids = trackIDs
        studio.moveTrack(1, 3)
        assertEquals(listOf(ids[0], ids[2], ids[3], ids[1]), trackIDs)
    }

    @Test fun aMoveIsOneUndoStepAndRedoes() {
        studio.setNote(1, 0, 72)
        val before = studio.song
        val ids = trackIDs
        studio.moveTrack(1, 3)
        val after = studio.song
        studio.undo()
        assertEquals(ids, trackIDs)
        assertEquals(before.patterns, studio.song.patterns)
        studio.redo()
        assertEquals(after.tracks, studio.song.tracks)
        assertEquals(after.patterns, studio.song.patterns)
    }

    @Test fun theSelectionFollowsTheMovedTrack() {
        studio.selectedTrack = 1
        val selected = studio.song.tracks[1].id
        studio.moveTrack(1, 3)
        assertEquals(selected, studio.song.tracks[studio.selectedTrack].id)
    }

    @Test fun theSelectionStaysOnItsTrackWhenAnotherMovesPastIt() {
        studio.selectedTrack = 2
        val selected = studio.song.tracks[2].id
        studio.moveTrack(0, 3)
        assertEquals(1, studio.selectedTrack)
        assertEquals(selected, studio.song.tracks[studio.selectedTrack].id)
    }

    @Test fun undoingAMovePutsTheSelectionBack() {
        studio.selectedTrack = 0
        studio.moveTrack(0, 3)
        assertEquals(3, studio.selectedTrack)
        studio.undo()
        assertEquals(0, studio.selectedTrack)
    }

    @Test fun movingATrackOntoItselfIsNotAnEdit() {
        val ids = trackIDs
        studio.moveTrack(2, 2)
        assertEquals(ids, trackIDs)
        assertFalse(studio.canUndo)
    }

    @Test fun outOfRangeMovesAreIgnored() {
        val ids = trackIDs
        studio.moveTrack(0, 4)
        studio.moveTrack(0, -1)
        studio.moveTrack(9, 0)
        studio.moveTrack(-1, 0)
        assertEquals(ids, trackIDs)
        assertFalse(studio.canUndo)
    }

    @Test fun duplicateLettersFollowTheNewColumnOrder() {
        var song = Song.create("Letters")
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE), Track(kind = ChannelKind.PULSE1, name = "Lead"),
            Track(kind = ChannelKind.TRIANGLE)))
            .withPattern(0) { it.copy(rows = List(3) { Pattern.EMPTY_ROW }) }
        studio.open(song)
        val wasB = studio.song.tracks[2].id
        assertEquals("TRI B", studio.song.label(2))

        studio.moveTrack(2, 0)
        studio.moveTrack(2, 1)

        assertEquals(wasB, studio.song.tracks[0].id)
        assertEquals("TRI A", studio.song.label(0))
        assertEquals("Lead", studio.song.label(1))
        assertEquals("Lead", studio.song.fullLabel(1))
        assertEquals("TRI B", studio.song.label(2))
        assertEquals("Triangle B", studio.song.fullLabel(2))
    }

    @Test fun theCorePlaysEachTrackWithItsOwnSoundAfterAMove() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held().copy(muted = true),
            Track(kind = ChannelKind.TRIANGLE).held()))
            .withPattern(0) {
                it.copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW)).withNote(0, 0, 69).withNote(1, 0, 60)
            }
        studio.open(song)

        studio.moveTrack(0, 1)
        studio.core.start()
        val rendered = studio.render(0.4)

        assertTrue(RenderHarness.rms(rendered, 4410, 4410 + 8820) > 0.01)
        val dominant = RenderHarness.dominantFrequency(rendered, 4410, 4410 + 8820, RenderHarness.semitoneLadder(64))
        assertEquals(NoteName.frequency(60), dominant ?: 0.0, 0.001)
    }

    @Test fun movingDuringPlaybackCutsAHeldNote() {
        var song = TestSongs.empty(tempo = 120.0, length = 16)
        song = song.copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE).held(), Track(kind = ChannelKind.PULSE1)))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW)).withNote(0, 0, 48) }
        studio.open(song)
        studio.core.start()
        assertTrue(studio.render(0.5).tailRms() > 0.01)

        studio.moveTrack(0, 1)

        assertTrue(studio.render(0.2).afterFirstTenth() < 0.01)
    }
}
