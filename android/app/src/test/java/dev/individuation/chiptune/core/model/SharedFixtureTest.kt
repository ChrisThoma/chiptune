package dev.individuation.chiptune.core.model

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The `.chipsong` contract shared with iOS. `Tests/Fixtures/song-fixtures.json`
 * says, for every `song-*.chipsong`, whether it decodes and what the
 * normalized song looks like; `Tests/SharedFixtureTests.swift` asserts the
 * same manifest against the Swift decoder, which is the source of truth. */
class SharedFixtureTest {

    private fun resource(name: String): ByteArray {
        val stream = javaClass.classLoader!!.getResourceAsStream(name)
            ?: error("$name is not on the test classpath (sourceSets test resources → ../../Tests/Fixtures)")
        return stream.use { it.readBytes() }
    }

    private fun manifest(): JSONObject = JSONObject(String(resource("song-fixtures.json"), Charsets.UTF_8))

    @Test fun theManifestCoversEveryFixtureInTheCheckout() {
        val dir = File("../../Tests/Fixtures")
        assertTrue("run from android/app", dir.isDirectory)
        val files = dir.list()!!.filter { it.startsWith("song-") && it.endsWith(".chipsong") }.toSet()
        assertEquals(files, manifest().keys().asSequence().toSet())
        assertTrue(files.size > 20)
    }

    @Test fun everyFixtureDecodesOrIsRejectedAsTheManifestSays() {
        val m = manifest()
        for (fileName in m.keys().asSequence().sorted().toList()) {
            val facts = m.getJSONObject(fileName)
            val bytes = resource(fileName)
            if (!facts.getBoolean("decodes")) {
                try {
                    SongDocument.decode(bytes)
                    fail("$fileName should be rejected")
                } catch (e: SongDecodeException) {
                    // expected
                }
                continue
            }
            val song = try {
                SongDocument.decode(bytes)
            } catch (e: SongDecodeException) {
                throw AssertionError("$fileName should decode: ${e.message}", e)
            }
            check(song, facts, fileName)
        }
    }

    /** Re-encoding a fixture and decoding it again changes nothing. */
    @Test fun everyDecodableFixtureSurvivesAnAndroidRoundTrip() {
        val m = manifest()
        for (fileName in m.keys().asSequence().sorted().toList()) {
            if (!m.getJSONObject(fileName).getBoolean("decodes")) continue
            val song = SongDocument.decode(resource(fileName))
            assertEquals(fileName, song, SongDocument.decode(SongDocument.encode(song).toByteArray()))
        }
    }

    private fun check(song: Song, facts: JSONObject, file: String) {
        fun ints(key: String) = facts.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getInt(it) } }
        fun doubles(key: String) = facts.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getDouble(it) } }
        fun bools(key: String) = facts.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getBoolean(it) } }
        fun near(key: String, actual: List<Double>) {
            val expected = doubles(key) ?: return
            assertEquals("$file: $key count", expected.size, actual.size)
            for ((a, e) in actual.zip(expected)) assertEquals("$file: $key", e, a, 1e-9)
        }

        if (facts.has("id")) assertEquals("$file: id", facts.getString("id"), song.id.toString().uppercase())
        if (facts.has("name")) assertEquals("$file: name", facts.getString("name"), song.name)
        if (facts.has("tempo")) assertEquals("$file: tempo", facts.getDouble("tempo"), song.tempo, 1e-9)
        if (facts.has("modified")) assertEquals("$file: modified", facts.getDouble("modified"), song.modified, 1e-6)
        if (facts.has("trackCount")) assertEquals("$file: trackCount", facts.getInt("trackCount"), song.tracks.size)
        if (facts.has("patternCount")) assertEquals("$file: patternCount", facts.getInt("patternCount"), song.patterns.size)
        if (facts.has("sectionCount")) assertEquals("$file: sectionCount", facts.getInt("sectionCount"), song.arrangement.size)
        ints("trackKinds")?.let { assertEquals("$file: trackKinds", it, song.tracks.map { t -> t.kind.rawValue }) }
        bools("trackSustain")?.let { assertEquals("$file: trackSustain", it, song.tracks.map { t -> t.instrument.sustain }) }
        near("trackDecays", song.tracks.map { it.instrument.decay })
        ints("trackDuties")?.let { assertEquals("$file: trackDuties", it, song.tracks.map { t -> t.instrument.duty }) }
        near("trackVolumes", song.tracks.map { it.instrument.volume })
        bools("trackMuted")?.let { assertEquals("$file: trackMuted", it, song.tracks.map { t -> t.muted }) }
        facts.optJSONArray("trackNames")?.let { a ->
            val expected = (0 until a.length()).map { if (a.isNull(it)) null else a.getString(it) }
            assertEquals("$file: trackNames", expected, song.tracks.map { it.name })
        }
        facts.optJSONArray("trackArpeggios")?.let { a ->
            val expected = (0 until a.length()).map { i -> a.getJSONArray(i).let { r -> (0 until r.length()).map { r.getInt(it) } } }
            assertEquals("$file: trackArpeggios", expected, song.tracks.map { it.instrument.arpeggio })
        }
        facts.optJSONArray("patternNames")?.let { a ->
            assertEquals("$file: patternNames", (0 until a.length()).map { a.getString(it) }, song.patterns.map { it.name })
        }
        ints("patternLengths")?.let { assertEquals("$file: patternLengths", it, song.patterns.map { p -> p.length }) }
        ints("sectionRepeats")?.let { assertEquals("$file: sectionRepeats", it, song.arrangement.map { s -> s.repeats }) }
        ints("sectionPatternIndices")?.let {
            assertEquals("$file: sectionPatternIndices", it, song.arrangement.map { s -> song.patternIndex(s.patternID) ?: -1 })
        }
        val cells: JSONArray = facts.optJSONArray("cells") ?: JSONArray()
        for (i in 0 until cells.length()) {
            val c = cells.getJSONArray(i)
            assertEquals("$file: pattern ${c.getInt(0)} row ${c.getInt(1)} step ${c.getInt(2)}",
                c.getInt(3), song.patterns[c.getInt(0)].rows[c.getInt(1)][c.getInt(2)])
        }
    }
}
