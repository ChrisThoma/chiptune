package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * Port of `MidiGoldenTests.swift`: the iOS writer's `Tests/Fixtures/midi-*.mid`,
 * compared byte for byte with what this port writes from the same `.chipsong`
 * inputs. Each `song-X.chipsong` goes to `midi-X.mid`. This is the
 * cross-platform pin, and like [GoldenRenderTest] there is no regeneration
 * path here: iOS owns the fixtures.
 *
 * `song-export-edge.chipsong` exists for this: a sustained track carried over
 * a pattern boundary and cut by OFF cells, a muted melodic track, a muted
 * noise track beside audible ones, a custom noise track, patterns of three
 * lengths, repeated sections, an unarranged pattern, and non-ASCII names.
 */
class MidiGoldenTest {

    private val inputs = listOf(
        "song-library-neon-ascent.chipsong",
        "song-library-boss-door.chipsong",
        "song-export-edge.chipsong",
    )

    private fun goldenName(input: String) = "midi-" + input.removePrefix("song-").removeSuffix(".chipsong") + ".mid"

    private fun resource(name: String): ByteArray {
        val stream = javaClass.classLoader!!.getResourceAsStream(name)
        assertNotNull("$name is missing from the test resources (../../Tests/Fixtures)", stream)
        return stream!!.use { it.readBytes() }
    }

    /** Through the app's own decoder, so the golden starts from what the app
     * would make of the file, normalization included. */
    private fun song(input: String): Song = SongDocument.decode(resource(input))

    @Test fun eachGoldenMatchesTheIosWriter() {
        for (input in inputs) {
            val golden = goldenName(input)
            val expected = resource(golden)
            val fresh = MidiExport.data(song(input))
            val at = (0 until minOf(fresh.size, expected.size)).firstOrNull { fresh[it] != expected[it] }
            assertEquals("$golden: first difference at byte $at", null, at)
            assertEquals("$golden: length", expected.size, fresh.size)
        }
    }

    /** What can be said of the edge golden without the writer: its shape
     * follows from the input file alone. */
    @Test fun theEdgeGoldenHasTheShapeItsSongImplies() {
        val midi = MidiBytes(resource("midi-export-edge.mid"))
        assertEquals(1, midi.format)
        assertEquals(96, midi.division)
        assertEquals(7, midi.tracks.size)
        assertEquals("Fête Nocturne 夜", MidiBytes.name(midi.tracks[0]))
        // 60,000,000 / 150 = 400,000 = 0x061A80.
        assertEquals(listOf(listOf(0x06, 0x1A, 0x80)), MidiBytes.metas(0x51, midi.tracks[0]))
        // A twice, B once, C three times: (2 × 16 + 8 + 3 × 12) × 24.
        val end = (2 * 16 + 8 + 3 * 12) * 24
        for ((i, track) in midi.tracks.withIndex()) {
            assertEquals("track $i", MidiBytes.Timed(end, MidiBytes.END_OF_TRACK), track.last())
        }
        assertEquals(
            listOf("Mélodie", "Pulse 2 (muted)", "Triangle", "Noise A", "Noise B (muted)", "Noise C"),
            midi.chipTracks.map { MidiBytes.name(it) },
        )
        val muted = MidiBytes.notes(midi.tracks[5])
        assertFalse(muted.isEmpty())
        assertEquals(setOf(1), muted.map { it.velocity }.toSet())
    }
}
