package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.TestSongs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** Port of `DuplicateIDTests.swift` (the store-load case waits for SongStore in Phase 3). */
class DuplicateIDTest {

    private fun roundTrip(song: Song): Song = SongDocument.decode(SongDocument.encode(song).toByteArray())

    private fun twoPatternSong(): Song {
        val song = TestSongs.twoPatterns().withNote(0, 0, 0, 60).withNote(1, 0, 0, 72)
        val first = song.patterns[0]
        return song.copy(
            patterns = listOf(first, song.patterns[1].copy(id = first.id)),
            arrangement = listOf(song.arrangement[0], song.arrangement[1].copy(patternID = first.id)),
        )
    }

    @Test fun decodeGivesDuplicatePatternsUniqueIdsAndKeepsTheirNotes() {
        val original = twoPatternSong()
        val loaded = roundTrip(original)
        assertEquals(2, loaded.patterns.map { it.id }.toSet().size)
        assertEquals("first occurrence keeps its id", original.patterns[0].id, loaded.patterns[0].id)
        assertEquals(60, loaded.patterns[0].rows[0][0])
        assertEquals(72, loaded.patterns[1].rows[0][0])
        assertEquals("B", loaded.patterns[1].name)
    }

    @Test fun sectionsThatSharedTheIdStillPointAtTheFirstPattern() {
        val loaded = roundTrip(twoPatternSong())
        assertEquals(2, loaded.arrangement.size)
        for (section in loaded.arrangement) {
            assertNotNull(loaded.patternIndex(section.patternID))
            assertEquals(loaded.patterns[0].id, section.patternID)
        }
    }

    @Test fun decodeGivesDuplicateTrackIdsUniqueIds() {
        val song = Song.create("Tracks").let {
            it.copy(tracks = it.tracks.mapIndexed { i, t -> if (i == 1) t.copy(id = it.tracks[0].id) else t })
        }
        val loaded = roundTrip(song)
        assertEquals(loaded.tracks.size, loaded.tracks.map { it.id }.toSet().size)
        assertEquals(song.tracks[0].id, loaded.tracks[0].id)
    }

    @Test fun decodeGivesDuplicateSectionIdsUniqueIds() {
        val song = Song.create("Sections").let { it.copy(arrangement = it.arrangement + it.arrangement[0]) }
        val loaded = roundTrip(song)
        assertEquals(2, loaded.arrangement.size)
        assertEquals(2, loaded.arrangement.map { it.id }.toSet().size)
    }

    @Test fun songWithUniqueIdsIsLeftAlone() {
        val song = TestSongs.twoPatterns()
        val loaded = roundTrip(song)
        assertEquals(song.patterns.map { it.id }, loaded.patterns.map { it.id })
        assertEquals(song.tracks.map { it.id }, loaded.tracks.map { it.id })
        assertEquals(song.arrangement.map { it.id }, loaded.arrangement.map { it.id })
    }

    @Test fun normalizeInPlaceRepairsDuplicates() {
        assertEquals(2, twoPatternSong().normalized().patterns.map { it.id }.toSet().size)
    }
}
