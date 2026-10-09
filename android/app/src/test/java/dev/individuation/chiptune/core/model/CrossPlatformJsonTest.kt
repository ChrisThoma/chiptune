package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.SeededRandom
import dev.individuation.chiptune.core.TestSongs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** What Android writes is what Swift's `JSONEncoder` writes, as far as a
 * Swift `JSONDecoder` can tell: Swift's keys in Swift's order, uppercase
 * UUIDs, `modified` as seconds since 2001-01-01, and Doubles that read back
 * to the same bits. */
class CrossPlatformJsonTest {

    private val uuidUpper = Regex("^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$")

    private val songKeys = listOf("id", "name", "tempo", "tracks", "patterns", "arrangement", "modified")
    private val trackKeys = listOf("id", "kind", "instrument", "muted", "name")
    private val instrumentKeys = listOf("duty", "volume", "decay", "sustain", "arpeggio")
    private val patternKeys = listOf("id", "name", "length", "rows")
    private val sectionKeys = listOf("id", "patternID", "repeats")

    private fun samples(): List<Song> {
        val named = TestSongs.twoPatterns().let { s ->
            s.copy(tracks = s.tracks.map { it.copy(name = "Lead \"1\" \\ 歌\n") })
        }
        val rng = SeededRandom(0xC4177175_7E000001uL)
        return listOf(TestSongs.empty(), TestSongs.singleNote(ChannelKind.TRIANGLE, arpeggio = listOf(0, 12)),
            TestSongs.twoPatterns(), TestSongs.golden(), named) +
            (0 until 20).map { SongPropertyTest.hostileSong(rng) }
    }

    private fun roundTrip(song: Song): Song = SongDocument.decode(SongDocument.encode(song).toByteArray())

    @Test fun anAndroidEncodedSongDecodesBackToAnEqualSong() {
        for (song in samples()) {
            val normalized = song.normalized()
            assertEquals(normalized, roundTrip(normalized))
        }
    }

    @Test fun keysAreSwiftsKeysInSwiftsOrder() {
        for (song in samples()) {
            val root = StrictJson.parse(SongDocument.encode(song)) as JsonValue.Obj
            assertEquals(songKeys, root.entries.keys.toList())
            val tracks = (root["tracks"] as JsonValue.Arr).items.map { it as JsonValue.Obj }
            for ((i, track) in tracks.withIndex()) {
                val expected = if (song.normalized().tracks[i].name == null) trackKeys.dropLast(1) else trackKeys
                assertEquals(expected, track.entries.keys.toList())
                assertEquals(instrumentKeys, (track["instrument"] as JsonValue.Obj).entries.keys.toList())
            }
            for (p in (root["patterns"] as JsonValue.Arr).items) {
                assertEquals(patternKeys, (p as JsonValue.Obj).entries.keys.toList())
            }
            for (s in (root["arrangement"] as JsonValue.Arr).items) {
                assertEquals(sectionKeys, (s as JsonValue.Obj).entries.keys.toList())
            }
        }
    }

    @Test fun uuidsAreWrittenUppercase() {
        for (song in samples()) {
            val root = StrictJson.parse(SongDocument.encode(song)) as JsonValue.Obj
            val ids = mutableListOf(root["id"])
            (root["tracks"] as JsonValue.Arr).items.forEach { ids += (it as JsonValue.Obj)["id"] }
            (root["patterns"] as JsonValue.Arr).items.forEach { ids += (it as JsonValue.Obj)["id"] }
            (root["arrangement"] as JsonValue.Arr).items.forEach {
                ids += (it as JsonValue.Obj)["id"]
                ids += it["patternID"]
            }
            for (id in ids) assertTrue("$id", uuidUpper.matches((id as JsonValue.Str).value))
        }
    }

    @Test fun lowercaseUuidsAreReadInAnyCase() {
        val song = TestSongs.twoPatterns().normalized()
        val lower = SongDocument.encode(song).replace(Regex("\"[0-9A-F-]{36}\"")) { it.value.lowercase() }
        assertEquals(song, SongDocument.decode(lower.toByteArray()))
    }

    @Test fun modifiedIsSecondsSince2001() {
        assertEquals(0.0, SongClock.fromUnixMillis(978_307_200_000L), 0.0)
        assertEquals(-978_307_200.0, SongClock.fromUnixMillis(0L), 0.0)
        val now = SongClock.now()
        assertTrue("now is after 2026 in the 2001 epoch", now > 780_000_000.0)
        val song = TestSongs.empty().copy(modified = 781_234_567.5)
        val root = StrictJson.parse(SongDocument.encode(song)) as JsonValue.Obj
        assertEquals(781_234_567.5, (root["modified"] as JsonValue.Num).asDoubleOrNull()!!, 0.0)
    }

    @Test fun awkwardDoublesSurviveBitForBit() {
        for (v in listOf(0.1, 1.0 / 3.0, 1e-300, Double.MIN_VALUE, 0.7000000000000001, 1.0, 0.0, 0.5)) {
            val song = TestSongs.empty().let { s ->
                s.copy(tracks = s.tracks.map { it.copy(instrument = it.instrument.copy(volume = v)) })
            }
            assertEquals(v, roundTrip(song).tracks[0].instrument.volume, 0.0)
        }
        for (m in listOf(781_234_567.123456789, 1e21, -3.0e-7, 0.0, 123456789012345.67)) {
            assertEquals(m, roundTrip(TestSongs.empty().copy(modified = m)).modified, 0.0)
        }
    }

    @Test fun numbersAreWrittenAsJsonNumbersSwiftReads() {
        val json = SongDocument.encode(TestSongs.empty().copy(tempo = 120.0, modified = 1e22))
        assertTrue(json, json.contains("\"tempo\" : 120,"))
        // Every number token is RFC 8259 syntax (no NaN, no Infinity, no bare ".5").
        val numbers = Regex("(?<=[\\[ ,:])-?[0-9][0-9eE.+-]*").findAll(json).map { it.value }.toList()
        for (n in numbers) assertTrue(n, Regex("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$").matches(n))
        assertFalse(json.contains("NaN") || json.contains("Infinity"))
    }

    @Test fun aNonFiniteValueIsNeverWritten() {
        val song = TestSongs.empty().copy(tempo = Double.NaN, modified = 0.0).let { s ->
            s.copy(tracks = s.tracks.map { it.copy(instrument = it.instrument.copy(volume = Double.POSITIVE_INFINITY)) })
        }
        val json = SongDocument.encode(song)
        assertFalse(json.contains("NaN") || json.contains("Infinity"))
        assertEquals(120.0, SongDocument.decode(json.toByteArray()).tempo, 0.0)
    }

    @Test fun stringsAreEscapedPerJson() {
        val name = "q\"b\\s/\u0000\u001F\n\t\u2028 歌 🎵"
        val song = TestSongs.empty().copy(name = "x$name")
        val json = SongDocument.encode(song)
        assertFalse(json.contains('\u0000'))
        assertFalse(json.contains('\u001F'))
        assertEquals("x$name", roundTrip(song).name)
    }

    @Test fun wrongTypesThrow() {
        val good = SongDocument.encode(TestSongs.twoPatterns())
        fun mutate(from: String, to: String) {
            val bad = good.replaceFirst(from, to)
            assertTrue("fixture text $from missing", bad != good)
            try {
                SongDocument.decode(bad.toByteArray())
                fail("accepted $to")
            } catch (e: SongDecodeException) {
                // expected
            }
        }
        mutate("\"tempo\" : 120", "\"tempo\" : \"120\"")
        mutate("\"muted\" : false", "\"muted\" : 0")
        mutate("\"length\" : 16", "\"length\" : 16.5")
        mutate("\"length\" : 16", "\"length\" : true")
        mutate("\"kind\" : 0", "\"kind\" : \"0\"")
        mutate("\"repeats\" : 1", "\"repeats\" : null")
        mutate("\"sustain\" : false", "\"sustain\" : \"no\"")
        mutate("\"arpeggio\" : [", "\"arpeggio\" : [\"x\", ")
        mutate("\"rows\" : [", "\"rows\" : [7, ")
        mutate("\"tracks\" : [", "\"tracks\" : {}, \"x\" : [")
        mutate("\"instrument\" : {", "\"instrument\" : [], \"x\" : {")
    }
}
