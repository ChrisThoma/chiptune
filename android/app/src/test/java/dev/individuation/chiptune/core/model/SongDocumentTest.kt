package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.assertSameSong
import java.util.UUID
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Port of `SongDocumentTests.swift` (model-only parts; the render assertion
 * in the hostile test arrives with the synth in Phase 2, and file I/O with
 * the platform layer). */
class SongDocumentTest {

    private fun makeSong(): Song {
        val base = Song.create("Shared")
        val tracks = base.tracks.toMutableList()
        tracks[0] = tracks[0].copy(instrument = tracks[0].instrument.copy(volume = 0.42))
        tracks[2] = tracks[2].copy(muted = true)
        val a = base.patterns[0].withNote(0, 5, 64)
        val b = Pattern(name = "B", length = 8, trackCount = tracks.size)
        return base.copy(
            tempo = 174.0,
            tracks = tracks,
            patterns = listOf(a, b),
            arrangement = base.arrangement + SongSection(patternID = b.id, repeats = 3),
        ).normalized()
    }

    private fun roundTrip(song: Song): Song = SongDocument.decode(SongDocument.encode(song).toByteArray())

    private fun decode(json: String): Song = SongDocument.decode(json.toByteArray())

    private fun assertRejected(json: String) {
        try {
            decode(json)
            fail("decoded $json as a song")
        } catch (e: SongDecodeException) {
            // expected
        }
    }

    // MARK: Round trip

    @Test fun writingThenReadingGivesTheSameSong() {
        val song = makeSong()
        assertSameSong(roundTrip(song), song)
    }

    @Test fun theFileIsNamedAfterTheSong() {
        val song = makeSong().copy(name = "My Song / v2")
        assertEquals("My Song v2", SongDocument.safeName(song))
        assertEquals("My Song v2.chipsong", SongDocument.fileName(song))
    }

    @Test fun aSongWithNoUsableNameStillGetsAFilename() {
        assertEquals("chiptune", SongDocument.safeName(makeSong().copy(name = "///")))
    }

    @Test fun twoSongsWithTheSameNameRoundTripIndependently() {
        val first = makeSong().copy(name = "Twin")
        val second = makeSong().copy(id = UUID.randomUUID(), name = "Twin", tempo = 90.0)
        assertEquals(174.0, roundTrip(first).tempo, 0.0)
        assertEquals(90.0, roundTrip(second).tempo, 0.0)
    }

    // MARK: Rejecting rubbish

    @Test fun garbageIsRejected() {
        for (bytes in listOf("", "{", "not json", "[1,2,3]", "{\"unrelated\": true}")) {
            assertRejected(bytes)
        }
    }

    @Test fun aNumberTooLargeForADoubleIsRejected() {
        assertRejected(
            """
            { "name": "Overflow", "tempo": 1e400, "tracks": [
                { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] } } ] }
            """,
        )
    }

    @Test fun randomBinaryIsRejectedRatherThanCrashing() {
        val rng = Random(7)
        repeat(20) {
            val bytes = ByteArray(512) { rng.nextInt(256).toByte() }
            try {
                SongDocument.decode(bytes)
                fail("binary decoded as a song")
            } catch (e: SongDecodeException) {
                // expected
            }
        }
    }

    // MARK: Hostile values

    @Test fun hostileValuesAreSanitizedOnImport() {
        val song = decode(
            """
            {
              "id": "${UUID.randomUUID()}",
              "name": "Hostile",
              "tempo": 1e300,
              "tracks": [
                { "kind": 0,
                  "instrument": { "duty": 9999, "volume": 500, "decay": -3,
                                  "arpeggio": [1000000, -1000000, 7, 12, 5, 9] } },
                { "kind": 2,
                  "instrument": { "duty": -5, "volume": -2, "decay": 1e12, "arpeggio": [] } }
              ],
              "patterns": [
                { "id": "${UUID.randomUUID()}", "name": "A", "length": 99999,
                  "rows": [[60, -100, 127, -3], [48]] }
              ],
              "arrangement": []
            }
            """,
        )
        assertTrue(song.tempo.isFinite())
        assertTrue(song.tempo in 40.0..300.0)
        for (track in song.tracks) {
            assertTrue(track.instrument.volume in 0.0..1.0)
            assertTrue(track.instrument.decay in 0.01..4.0)
            assertTrue(track.instrument.duty in Instrument.DUTY_CYCLES.indices)
            assertTrue(track.instrument.arpeggio.size <= Instrument.MAX_ARPEGGIO_STEPS)
            for (semitones in track.instrument.arpeggio) {
                assertTrue(kotlin.math.abs(semitones) <= Instrument.MAX_ARPEGGIO_SEMITONES)
            }
        }
        assertTrue(song.patterns[0].length in 4..Chip.MAX_STEPS)
        assertFalse("an empty arrangement isn't representable", song.arrangement.isEmpty())
    }

    // MARK: Hold

    @Test fun aFileWrittenBeforeHoldWasASwitchStillLoads() {
        val song = decode(
            """
            { "name": "Before hold", "tempo": 120, "tracks": [
                { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 0.35, "arpeggio": [] } } ],
              "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16, "rows": [[60]] } ],
              "arrangement": [] }
            """,
        )
        assertEquals(1, song.tracks.size)
        assertFalse(song.tracks[0].instrument.sustain)
        assertEquals(0.35, song.tracks[0].instrument.decay, 0.0001)
    }

    @Test fun fullDecayInAnOldFileBecomesHold() {
        val song = decode(
            """
            { "name": "Held", "tempo": 120, "tracks": [
                { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 4.0, "arpeggio": [] } } ],
              "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16, "rows": [[48]] } ],
              "arrangement": [] }
            """,
        )
        assertTrue("a 4 s decay was the old way of saying hold", song.tracks[0].instrument.sustain)
        assertTrue(song.tracks[0].instrument.decay < 3.99)
    }

    @Test fun anInstrumentMissingEveryOptionalKeyDecodes() {
        val song = decode(
            """
            { "name": "Sparse", "tempo": 120, "tracks": [ { "kind": 0, "instrument": {} } ],
              "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16, "rows": [[60]] } ],
              "arrangement": [] }
            """,
        )
        val instrument = song.tracks[0].instrument
        assertTrue(instrument.volume in 0.0..1.0)
        assertTrue(instrument.decay in 0.01..4.0)
        assertTrue(instrument.duty in Instrument.DUTY_CYCLES.indices)
        assertTrue(instrument.arpeggio.isEmpty())
        assertFalse(instrument.sustain)
    }

    @Test fun aTrackWithAnUnknownKindStillLoads() {
        val song = decode(
            """
            { "name": "From the future", "tempo": 120, "tracks": [
                { "kind": 0, "instrument": {} },
                { "kind": 9, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35 } } ],
              "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16,
                              "rows": [[60], [67]] } ],
              "arrangement": [] }
            """,
        )
        assertEquals(2, song.tracks.size)
        assertEquals(ChannelKind.PULSE1, song.tracks[1].kind)
        assertEquals(67, song.patterns[0].rows[1][0])
    }

    @Test fun aTrackMissingItsInstrumentStillLoads() {
        val song = decode(
            """
            { "name": "No instrument", "tempo": 120, "tracks": [
                { "kind": 0, "instrument": {} },
                { "kind": 2 } ],
              "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16,
                              "rows": [[60], [67]] } ],
              "arrangement": [] }
            """,
        )
        assertEquals(2, song.tracks.size)
        assertEquals(ChannelKind.TRIANGLE, song.tracks[1].kind)
        assertEquals(Instrument.defaultFor(ChannelKind.TRIANGLE).normalized(), song.tracks[1].instrument)
    }

    @Test fun holdSurvivesARoundTrip() {
        val base = makeSong()
        val tracks = base.tracks.toMutableList()
        tracks[0] = tracks[0].copy(instrument = tracks[0].instrument.copy(sustain = true))
        tracks[1] = tracks[1].copy(instrument = tracks[1].instrument.copy(sustain = false))
        val restored = roundTrip(base.copy(tracks = tracks))
        assertTrue(restored.tracks[0].instrument.sustain)
        assertFalse(restored.tracks[1].instrument.sustain)
    }

    @Test fun aLegacyFileImports() {
        val song = decode(
            """
            { "name": "Legacy share", "tempo": 128, "length": 8, "tracks": [
                { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
                  "notes": [60, -1, 64, -1, 67, -1, -1, -1] } ] }
            """,
        )
        assertEquals("Legacy share", song.name)
        assertEquals(1, song.patterns.size)
        assertEquals(8, song.patterns[0].length)
        assertEquals(listOf(60, -1, 64, -1, 67, -1, -1, -1), song.patterns[0].rows[0].take(8))
    }

    // MARK: Collisions

    @Test fun anIdCollisionGetsAFreshIdentity() {
        val existing = makeSong()
        val resolved = SongDocument.resolvingCollision(existing, listOf(existing.id))
        assertNotEquals(existing.id, resolved.id)
        assertEquals("Shared (imported)", resolved.name)
    }

    @Test fun noCollisionMeansTheSongIsUntouched() {
        val song = makeSong()
        val resolved = SongDocument.resolvingCollision(song, listOf(UUID.randomUUID(), UUID.randomUUID()))
        assertSameSong(resolved, song)
    }

    // MARK: Drops (SongDropTests): same decode, same normalization

    @Test fun jsonThatIsNotASongIsRejected() {
        assertRejected("""{"name": "shopping list", "items": [1, 2]}""")
    }

    @Test fun decodedBytesAreNormalized() {
        val song = makeSong().copy(tempo = 100_000.0)
        val imported = roundTrip(song)
        assertTrue("a dropped tempo must be clamped", imported.tempo < 100_000.0)
    }
}
