package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of `SongSanitizeTests.swift`. */
class SongSanitizeTest {

    @Test fun normalizeScrubsInvalidCellsAndKeepsValidOnes() {
        var song = Song.create("Sanitize")
        val input = listOf(-128, -100, -3, -2, -1, 0, 60, 127)
        for ((step, value) in input.withIndex()) song = song.withNote(0, 0, step, value)

        val row = song.normalized().patterns[0].rows[0]
        assertEquals("note-off must survive normalize", -2, row[3])
        assertEquals("rest must survive normalize", -1, row[4])
        assertEquals("lowest MIDI note must survive normalize", 0, row[5])
        assertEquals("ordinary note must survive normalize", 60, row[6])
        assertEquals("highest MIDI note must survive normalize", 127, row[7])
        assertEquals(-1, row[0])
        assertEquals(-1, row[1])
        assertEquals(-1, row[2])
    }

    @Test fun invalidCellsSurviveEncodeButNotDecode() {
        val song = Song.create("Decode").withNote(0, 0, 0, -100).withNote(0, 0, 1, 64)
        val decoded = SongDocument.decode(SongDocument.encode(song).toByteArray())
        assertEquals(-1, decoded.patterns[0].rows[0][0])
        assertEquals(64, decoded.patterns[0].rows[0][1])
    }
}
