package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.TestSongs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Twin of the Swift `MusicalKey` tests: a song can name a key, which only
 * marks keys on the piano; the notes it allows are a pitch-class test. */
class MusicalKeyTest {

    private fun pitchClasses(key: MusicalKey): List<Int> = (0 until 12).filter { key.contains(it) }

    @Test fun cMajorHoldsTheWhiteKeys() {
        val key = MusicalKey(0, MusicalKey.Scale.MAJOR)
        assertEquals(listOf(0, 2, 4, 5, 7, 9, 11), pitchClasses(key))
        assertTrue(key.contains(60))
        assertFalse(key.contains(61))
        assertTrue(key.isRoot(60))
        assertTrue(key.isRoot(72))
        assertFalse(key.isRoot(62))
    }

    @Test fun aMinorHoldsTheSameNotesRootedOnA() {
        val key = MusicalKey(9, MusicalKey.Scale.MINOR)
        assertEquals(listOf(0, 2, 4, 5, 7, 9, 11), pitchClasses(key))
        assertTrue(key.isRoot(69))
        assertFalse(key.isRoot(60))
    }

    @Test fun fSharpMajorWrapsPastB() {
        val key = MusicalKey(6, MusicalKey.Scale.MAJOR)
        // F# G# A# B C# D# F
        assertEquals(listOf(1, 3, 5, 6, 8, 10, 11), pitchClasses(key))
        assertTrue(key.isRoot(66))
        assertFalse(key.contains(67))
    }

    @Test fun pitchClassHoldsBelowZeroAndAbove127() {
        val c = MusicalKey(0, MusicalKey.Scale.MAJOR)
        assertTrue(c.isRoot(-12))
        assertTrue(c.contains(-1)) // B
        assertFalse(c.contains(-2)) // A#
        assertTrue(c.isRoot(132))
        assertTrue(c.contains(127)) // G
        val fs = MusicalKey(6, MusicalKey.Scale.MAJOR)
        assertTrue(fs.isRoot(-6))
        assertFalse(fs.contains(-5)) // G
    }

    @Test fun labels() {
        assertEquals("C maj", MusicalKey(0, MusicalKey.Scale.MAJOR).shortLabel)
        assertEquals("F# min", MusicalKey(6, MusicalKey.Scale.MINOR).shortLabel)
        assertEquals("C major", MusicalKey(0, MusicalKey.Scale.MAJOR).spokenLabel)
        assertEquals("A# minor", MusicalKey(10, MusicalKey.Scale.MINOR).spokenLabel)
    }

    @Test fun cMajorDegreesRunOneToSevenOnTheWhiteKeys() {
        val key = MusicalKey(0, MusicalKey.Scale.MAJOR)
        assertEquals(listOf(1, null, 2, null, 3, 4, null, 5, null, 6, null, 7), (60 until 72).map { key.degree(it) })
    }

    @Test fun fSharpMinorDegrees() {
        val key = MusicalKey(6, MusicalKey.Scale.MINOR)
        // F# G# A B C# D E
        val expected = mapOf(66 to 1, 68 to 2, 69 to 3, 71 to 4, 73 to 5, 74 to 6, 76 to 7)
        for (midi in 66 until 78) assertEquals("$midi", expected[midi], key.degree(midi))
    }

    @Test fun degreeHoldsBelowZeroAndAbove127() {
        val key = MusicalKey(0, MusicalKey.Scale.MAJOR)
        assertEquals(1, key.degree(-12))
        assertEquals(7, key.degree(-1))
        assertNull(key.degree(-2))
        assertEquals(1, key.degree(132))
        assertEquals(5, key.degree(127))
    }

    @Test fun theRootIsDegreeOne() {
        for (scale in MusicalKey.Scale.entries) {
            for (root in 0 until 12) {
                val key = MusicalKey(root, scale)
                for (midi in 48 until 72) assertEquals(key.isRoot(midi), key.degree(midi) == 1)
                for (midi in 48 until 72) assertEquals(key.contains(midi), key.degree(midi) != null)
            }
        }
    }

    @Test fun aNewSongHasNoKey() = assertNull(Song.create().key)
}

/** The `key` field of a `.chipsong`: `{"root": 0-11, "scale": "major"|"minor"}`,
 * absent when there is none, and never a reason to reject a song. */
class MusicalKeyCodecTest {

    private fun withKey(json: String, key: String): String {
        // Splice a raw "key" value in after "tempo", as a hand-edited or
        // newer-version file might carry it.
        val marker = "\"tempo\" : 120,"
        assertTrue(json.contains(marker))
        return json.replace(marker, "$marker\n  \"key\" : $key,")
    }

    private fun base(): String = SongCodec.encode(TestSongs.empty())

    @Test fun aKeyRoundTrips() {
        for (scale in MusicalKey.Scale.entries) {
            for (root in 0 until 12) {
                val song = TestSongs.empty().copy(key = MusicalKey(root, scale)).normalized()
                val back = SongCodec.decode(SongCodec.encode(song))
                assertEquals(MusicalKey(root, scale), back.key)
                assertEquals(song, back)
            }
        }
    }

    @Test fun theKeyIsWrittenInTheSharedShape() {
        val song = TestSongs.empty().copy(key = MusicalKey(6, MusicalKey.Scale.MINOR))
        val root = StrictJson.parse(SongCodec.encode(song)) as JsonValue.Obj
        // Swift encodes it last, after "modified".
        assertEquals(listOf("id", "name", "tempo", "tracks", "patterns", "arrangement", "modified", "key"),
            root.entries.keys.toList())
        val key = root["key"] as JsonValue.Obj
        assertEquals(listOf("root", "scale"), key.entries.keys.toList())
        assertEquals(6L, (key["root"] as JsonValue.Num).asLongOrNull())
        assertEquals("minor", (key["scale"] as JsonValue.Str).value)
        assertEquals("major", ((StrictJson.parse(SongCodec.encode(song.copy(key = MusicalKey(0, MusicalKey.Scale.MAJOR))))
            as JsonValue.Obj)["key"] as JsonValue.Obj).let { (it["scale"] as JsonValue.Str).value })
    }

    @Test fun noKeyWritesNoKeyField() {
        for (song in listOf(TestSongs.empty(), TestSongs.golden(), Song.create())) {
            val root = StrictJson.parse(SongCodec.encode(song)) as JsonValue.Obj
            assertFalse("a song without a key wrote one", root.entries.containsKey("key"))
        }
    }

    @Test fun aFileWithoutAKeyDecodesWithNone() = assertNull(SongCodec.decode(base()).key)

    @Test fun aBadKeyDecodesAsNoneAndTheSongStillLoads() {
        val bad = listOf(
            """{"root": 12, "scale": "major"}""",
            """{"root": -1, "scale": "minor"}""",
            """{"root": 3, "scale": "dorian"}""",
            """{"root": 3}""",
            """{"scale": "major"}""",
            """{"root": "C", "scale": "major"}""",
            """{"root": 1.5, "scale": "major"}""",
            """{"root": 3, "scale": 1}""",
            """"C major"""",
            "null",
            "[]",
        )
        val file = base()
        val expected = SongCodec.decode(file)
        for (value in bad) {
            val song = SongCodec.decode(withKey(file, value))
            assertNull(value, song.key)
            assertEquals(value, expected.copy(modified = 0.0), song.copy(modified = 0.0))
        }
    }

    @Test fun normalizeDropsAKeyWhoseRootIsOutOfRange() {
        assertNull(TestSongs.empty().copy(key = MusicalKey(12, MusicalKey.Scale.MAJOR)).normalized().key)
        assertNull(TestSongs.empty().copy(key = MusicalKey(-1, MusicalKey.Scale.MAJOR)).normalized().key)
    }
}
