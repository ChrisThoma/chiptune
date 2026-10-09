package dev.individuation.chiptune.core.text

import org.junit.Assert.assertEquals
import org.junit.Test

/** Swift counts `Character`s — extended grapheme clusters. These are the
 * cases a name field actually meets: flags, skin tones, ZWJ families,
 * combining accents, Hangul jamo, CRLF. */
class GraphemesTest {
    private fun clusters(s: String) = Graphemes.split(s)

    @Test fun asciiIsOneClusterPerChar() = assertEquals(listOf("a", "b", "c"), clusters("abc"))

    @Test fun surrogatePairsAreOneCluster() = assertEquals(1, Graphemes.count("🎵"))

    @Test fun regionalIndicatorsPairUp() {
        val jp = "\uD83C\uDDEF\uD83C\uDDF5"
        assertEquals(listOf(jp, jp, jp), clusters(jp.repeat(3)))
        // An odd one out stands alone.
        assertEquals(2, Graphemes.count(jp + "\uD83C\uDDEF"))
    }

    @Test fun combiningMarksAttach() = assertEquals(listOf("e\u0301", "x"), clusters("e\u0301x"))

    @Test fun skinToneModifiersAttach() = assertEquals(1, Graphemes.count("\uD83D\uDC4D\uD83C\uDFFD"))

    @Test fun zwjSequencesAreOneCluster() {
        val family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67"
        assertEquals(1, Graphemes.count(family))
        assertEquals(2, Graphemes.count(family + "a"))
    }

    @Test fun variationSelectorsAttach() = assertEquals(1, Graphemes.count("\u2764\uFE0F"))

    @Test fun crlfIsOneCluster() = assertEquals(listOf("a", "\r\n", "b"), clusters("a\r\nb"))

    @Test fun hangulJamoCompose() = assertEquals(1, Graphemes.count("\u1100\u1161\u11A8"))

    @Test fun prefixTakesWholeClusters() {
        assertEquals("e\u0301", Graphemes.prefix("e\u0301e\u0301", 1))
        assertEquals("", Graphemes.prefix("abc", 0))
        assertEquals("abc", Graphemes.prefix("abc", 10))
    }

    @Test fun swiftWhitespaceSets() {
        assertEquals("x", SwiftText.trimWhitespaceAndNewlines("\u00A0\t\n x \u2029\u0085\u3000"))
        assertEquals("\u001Cx", SwiftText.trimWhitespaceAndNewlines("\u001Cx"))
        // `.whitespaces` alone keeps newlines.
        assertEquals("\nx", SwiftText.trimWhitespaces(" \nx\t"))
    }
}
