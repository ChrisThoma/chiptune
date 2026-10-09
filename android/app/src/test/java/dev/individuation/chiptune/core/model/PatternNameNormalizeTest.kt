package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.text.Graphemes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `PatternNameNormalizeTests.swift`. */
class PatternNameNormalizeTest {

    private fun song(names: List<String>): Song {
        val s = TestSongs.empty()
        val patterns = names.map { Pattern(name = it, length = 16, trackCount = s.tracks.size) }
        return s.copy(patterns = patterns, arrangement = patterns.map { SongSection(patternID = it.id) })
    }

    private fun names(s: Song) = s.patterns.map { it.name }

    @Test fun longNameIsClippedToSix() {
        assertEquals("ABCDEF", song(listOf("ABCDEFGHIJKLMNOPQRSTUVWXYZ")).normalized().patterns[0].name)
    }

    @Test fun blankNameGetsUniqueDefault() {
        assertEquals(listOf("A", "B", "C"), names(song(listOf("A", "   ", "")).normalized()))
    }

    @Test fun duplicateKeepsFirstAndRenamesLater() {
        assertEquals(listOf("A", "C", "B", "D"), names(song(listOf("A", "A", "B", "B")).normalized()))
    }

    @Test fun reportedFixtureShape() {
        val n = names(song(listOf("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "   ", "A", "A")).normalized())
        assertEquals(4, n.toSet().size)
        assertTrue(n.all { it.isNotEmpty() && Graphemes.count(it) <= 6 })
        assertEquals("ABCDEF", n[0])
        assertEquals("A", n[2])
    }

    @Test fun clippedCollisionIsMadeUnique() {
        val s = song(listOf("ABCDEFG", "ABCDEFH")).normalized()
        assertEquals("ABCDEF", s.patterns[0].name)
        assertNotEquals("ABCDEF", s.patterns[1].name)
    }

    @Test fun validUniqueNamesUnchangedAndIdempotent() {
        val s = song(listOf("Intro", "Verse", "x y")).normalized()
        assertEquals(listOf("Intro", "Verse", "x y"), names(s))
        assertEquals(s, s.normalized())
    }

    @Test fun surroundingWhitespaceTrimmed() {
        assertEquals("Hi", song(listOf("  Hi  ")).normalized().patterns[0].name)
    }

    /** Swift trims `.whitespacesAndNewlines`, which includes a no-break space
     * (Kotlin's `trim()` does not) and excludes U+001C (Kotlin's does). */
    @Test fun trimmingMatchesSwiftsWhitespaceSet() {
        assertEquals("Hi", song(listOf("\u00A0Hi\u2028")).normalized().patterns[0].name)
        assertEquals("\u001CHi", song(listOf("\u001CHi")).normalized().patterns[0].name)
    }
}
