package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.text.Graphemes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `TrackNameTests.swift`. */
class TrackNameTest {

    private fun song(kinds: List<ChannelKind>): Song {
        val song = Song.create("Named")
        return song.copy(
            tracks = kinds.map { Track(kind = it) },
            patterns = listOf(song.patterns[0].copy(rows = kinds.map { Pattern.EMPTY_ROW })),
        )
    }

    private fun Song.named(index: Int, name: String?): Song =
        copy(tracks = tracks.mapIndexed { i, t -> if (i == index) t.copy(name = name) else t })

    // MARK: Labels

    @Test fun labelPrefersTheCustomName() {
        val s = song(listOf(ChannelKind.TRIANGLE)).named(0, "Bass")
        assertEquals("Bass", s.label(0))
        assertEquals("Bass", s.fullLabel(0))
    }

    @Test fun anUnnamedTrackStillReadsAsItsChannel() {
        val s = song(listOf(ChannelKind.TRIANGLE))
        assertEquals("TRI", s.label(0))
        assertEquals("Triangle", s.fullLabel(0))
    }

    @Test fun aBlankNameFallsBackToTheChannel() {
        for (blank in listOf("", "   ", "\t\n")) {
            assertEquals("NOI", song(listOf(ChannelKind.NOISE)).named(0, blank).label(0))
        }
    }

    @Test fun duplicateSuffixesStillApplyToUnnamedTracks() {
        val s = song(listOf(ChannelKind.TRIANGLE, ChannelKind.TRIANGLE))
        assertEquals("TRI A", s.label(0))
        assertEquals("TRI B", s.label(1))
        assertEquals("Triangle B", s.fullLabel(1))
        val renamed = s.named(0, "Bass")
        assertEquals("Bass", renamed.label(0))
        assertEquals("renaming a sibling moved this track's letter", "TRI B", renamed.label(1))
    }

    @Test fun namingBothTracksDropsTheSuffixEntirely() {
        val s = song(listOf(ChannelKind.PULSE1, ChannelKind.PULSE1)).named(0, "Lead").named(1, "Harmony")
        assertEquals("Lead", s.label(0))
        assertEquals("Harmony", s.label(1))
    }

    @Test fun anOutOfRangeTrackHasNoLabel() {
        val s = song(listOf(ChannelKind.PULSE1))
        assertEquals("", s.label(4))
        assertEquals("", s.fullLabel(-1))
    }

    // MARK: Sanitizing

    @Test fun normalizeTrimsAndCapsAName() {
        val s = song(listOf(ChannelKind.PULSE1, ChannelKind.PULSE2))
            .named(0, "  Lead  ").named(1, "x".repeat(500)).normalized()
        assertEquals("Lead", s.tracks[0].name)
        assertEquals(Track.MAX_NAME_LENGTH, Graphemes.count(s.tracks[1].name!!))
    }

    @Test fun normalizeDropsABlankName() {
        assertNull(song(listOf(ChannelKind.PULSE1)).named(0, "   ").normalized().tracks[0].name)
    }

    @Test fun capCountsGraphemesNotUtf16Units() {
        val flags = "\uD83C\uDDEF\uD83C\uDDF5".repeat(20)
        val s = song(listOf(ChannelKind.PULSE1)).named(0, flags).normalized()
        assertEquals("\uD83C\uDDEF\uD83C\uDDF5".repeat(16), s.tracks[0].name)
    }

    // MARK: Files

    @Test fun aNameSurvivesARoundTrip() {
        val s = song(listOf(ChannelKind.TRIANGLE, ChannelKind.NOISE)).named(0, "Bass").normalized()
        val restored = SongDocument.decode(SongDocument.encode(s).toByteArray())
        assertEquals("Bass", restored.tracks[0].name)
        assertNull("an unnamed track should stay unnamed", restored.tracks[1].name)
    }

    @Test fun aFileWithNoTrackNameStillLoads() {
        val old = """
            { "name": "Unnamed tracks", "tempo": 120, "tracks": [
                { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 0.35,
                                             "sustain": false, "arpeggio": [] } } ],
              "patterns": [ { "id": "${java.util.UUID.randomUUID()}", "name": "A", "length": 16,
                              "rows": [[60]] } ],
              "arrangement": [] }
        """
        val song = SongDocument.decode(old.toByteArray())
        assertNull(song.tracks[0].name)
        assertEquals("TRI", song.label(0))
    }

    @Test fun anUnnamedTrackIsNotWrittenIntoTheFile() {
        val s = song(listOf(ChannelKind.PULSE1)).normalized()
        val json = SongDocument.encode(s)
        assertFalse(json.contains("\"name\" : \"\"") || json.contains("\"name\":\"\""))
        // Exactly two names: the song's and the pattern's.
        assertEquals(2, Regex("\"name\"").findAll(json).count())
        assertTrue(json.contains("\"muted\""))
    }
}
