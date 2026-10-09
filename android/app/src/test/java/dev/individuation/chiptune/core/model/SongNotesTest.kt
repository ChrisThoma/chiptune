package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.TestSongs
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `SongNotesTests.swift`. */
class SongNotesTest {

    private fun Song.withTrack(index: Int, f: (Track) -> Track): Song =
        copy(tracks = tracks.mapIndexed { i, t -> if (i == index) f(t) else t })

    @Test fun anEmptySongHasNoNotes() = assertFalse(TestSongs.empty().hasNotes)

    @Test fun aSingleNoteCounts() = assertTrue(TestSongs.singleNote(ChannelKind.PULSE1).hasNotes)

    @Test fun aNoteOffAloneIsNotANote() {
        assertFalse(TestSongs.empty().withNote(0, 0, 0, Chip.NOTE_OFF).hasNotes)
    }

    @Test fun aNoteBeyondThePatternLengthDoesNotCount() {
        val song = TestSongs.empty(length = 16).withNote(0, 0, 20, 60)
        assertFalse(song.hasNotes)
        assertTrue(song.copy(patterns = listOf(song.patterns[0].copy(length = 32))).hasNotes)
    }

    @Test fun aNoteInAPatternOutsideTheArrangementDoesNotCount() {
        val song = TestSongs.empty()
        val second = Pattern(name = "B", trackCount = song.tracks.size).withNote(0, 0, 60)
        val withSecond = song.copy(patterns = song.patterns + second)
        assertFalse(withSecond.hasNotes)
        assertTrue(withSecond.copy(arrangement = withSecond.arrangement + SongSection(patternID = second.id)).hasNotes)
    }

    @Test fun aMutedTrackStillCounts() {
        assertTrue(TestSongs.singleNote(ChannelKind.PULSE1).withTrack(0) { it.copy(muted = true) }.hasNotes)
    }

    @Test fun aChainedSecondPatternCounts() {
        val song = TestSongs.twoPatterns()
        val cleared = song.patterns[0].copy(rows = song.patterns[0].rows.map { Pattern.EMPTY_ROW })
        assertTrue(song.copy(patterns = listOf(cleared, song.patterns[1])).hasNotes)
    }

    @Test fun notesInAnUnarrangedPatternAreStillNotesSomewhere() {
        val song = TestSongs.empty()
        val second = Pattern(name = "B", trackCount = song.tracks.size).withNote(0, 0, 60)
        val withSecond = song.copy(patterns = song.patterns + second)
        assertFalse(withSecond.hasNotes)
        assertTrue(withSecond.hasNotesAnywhere)
    }

    @Test fun anAllMutedSongHasNoAudibleNotes() {
        val song = TestSongs.empty().withNote(0, 0, 0, 60).withTrack(0) { it.copy(muted = true) }
        assertTrue(song.hasNotes)
        assertFalse(song.hasAudibleNotes)
        assertTrue(song.withTrack(0) { it.copy(muted = false) }.hasAudibleNotes)
    }

    @Test fun oneUnmutedTrackWithNotesIsAudible() {
        val song = TestSongs.empty().withNote(0, 0, 0, 60).withNote(0, 1, 0, 64)
            .withTrack(0) { it.copy(muted = true) }
        assertTrue(song.hasAudibleNotes)
    }

    @Test fun anUnmutedTrackWhoseOnlyNotesAreUnarrangedIsNotAudible() {
        val song = TestSongs.empty().withNote(0, 0, 0, 60).withTrack(0) { it.copy(muted = true) }
        val second = Pattern(name = "B", trackCount = song.tracks.size).withNote(1, 0, 64)
        val withSecond = song.copy(patterns = song.patterns + second)
        assertFalse(withSecond.hasAudibleNotes)
        assertTrue(withSecond.copy(arrangement = withSecond.arrangement + SongSection(patternID = second.id)).hasAudibleNotes)
    }
}
