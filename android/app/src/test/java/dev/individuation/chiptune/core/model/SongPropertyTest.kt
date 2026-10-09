package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.SeededRandom
import dev.individuation.chiptune.core.equalIgnoringModified
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `SongPropertyTests.swift`, model-only properties. The render
 * properties arrive with the synth in Phase 2. */
class SongPropertyTest {

    private val seed: ULong = 0xC4177175_7E000001uL
    private val iterations = 50

    private fun forEachSong(body: (Song, String) -> Unit) {
        val rng = SeededRandom(seed)
        for (i in 0 until iterations) {
            body(hostileSong(rng), "seed ${seed.toString(16)}, iteration $i")
        }
    }

    @Test fun splitMix64MatchesTheSwiftSequence() {
        // Reference values for SplitMix64 seeded with 0 (Vigna's reference implementation).
        val rng = SeededRandom(0uL)
        assertEquals(0xE220A8397B1DCDAFuL, rng.next())
        assertEquals(0x6E789E6AA1B965F4uL, rng.next())
        assertEquals(0x06C45D188009454FuL, rng.next())
    }

    companion object {
        /** Values the UI could never produce, as in the Swift generator. */
        fun hostileSong(rng: SeededRandom): Song {
            fun <T> pick(options: List<T>): T = options[(rng.next() % options.size.toULong()).toInt()]
            fun int(range: IntRange): Int =
                range.first + (rng.next() % (range.last - range.first + 1).toULong()).toInt()

            val name = pick(listOf("", "Hostile", "x".repeat(300)))
            val tempo = pick(listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY,
                -1000.0, 0.0, 1e18, 120.0, 40.0, 300.0, 137.5))

            val trackCount = int(0..(Chip.MAX_TRACKS + 4))
            val tracks = (0 until trackCount).map {
                val track = Track(kind = pick(ChannelKind.entries))
                val volume = pick(listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY,
                    -5.0, 0.0, 0.5, 1.0, 99.0))
                val decay = pick(listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY,
                    -1.0, 0.0, 0.35, 4.0, 1e9))
                val duty = pick(listOf(-100, -1, 0, 2, 3, 4, 9999))
                val arpeggio = (0 until int(0..9)).map {
                    pick(listOf(0, 3, 7, 12, -12, 5000, -5000, Int.MAX_VALUE / 2, Int.MIN_VALUE / 2))
                }
                val sustain = rng.next() % 2uL == 0uL
                val muted = rng.next() % 2uL == 0uL
                track.copy(
                    instrument = track.instrument.copy(volume = volume, decay = decay, duty = duty,
                        arpeggio = arpeggio, sustain = sustain),
                    muted = muted,
                )
            }

            val patternCount = int(0..(Chip.MAX_PATTERNS + 4))
            val patterns = (0 until patternCount).map { index ->
                var pattern = Pattern(name = "P$index", length = pick(listOf(-50, 0, 1, 4, 16, 64, 500)),
                    trackCount = maxOf(trackCount, 1))
                val rows = pattern.rows.map { row ->
                    row.map { cell ->
                        if (rng.next() % 3uL == 0uL) (rng.next() % 256uL).toInt().toByte().toInt() else cell
                    }
                }
                pattern = pattern.copy(rows = rows)
                if (rng.next() % 3uL == 0uL) pattern = pattern.copy(rows = pattern.rows.take(int(0..2)))
                pattern
            }

            val arrangement = (0 until int(0..(Chip.MAX_CHAIN + 8))).map {
                val id = if (patterns.isEmpty() || rng.next() % 2uL == 0uL) UUID.randomUUID()
                else patterns[int(0..(patterns.size - 1))].id
                SongSection(patternID = id, repeats = pick(listOf(-10, 0, 1, 4, 16, 999)))
            }
            return Song.create(name).copy(tempo = tempo, tracks = tracks, patterns = patterns, arrangement = arrangement)
        }
    }

    @Test fun normalizeIsIdempotent() = forEachSong { song, tag ->
        val once = song.normalized()
        assertTrue("normalize is not idempotent ($tag)", equalIgnoringModified(once, once.normalized()))
    }

    @Test fun normalizeProducesValuesTheEngineCanPlay() = forEachSong { original, tag ->
        val heldBefore = original.tracks.map { it.instrument.sustain }
        val song = original.normalized()
        for ((index, held) in heldBefore.withIndex()) {
            if (index >= song.tracks.size) break
            assertEquals("normalize changed hold on track $index ($tag)", held, song.tracks[index].instrument.sustain)
        }
        assertTrue(tag, song.tempo.isFinite() && song.tempo in 40.0..300.0)
        assertTrue(tag, song.tracks.size in 1..Chip.MAX_TRACKS)
        assertTrue(tag, song.patterns.size in 1..Chip.MAX_PATTERNS)
        for (track in song.tracks) {
            val inst = track.instrument
            assertTrue("volume ${inst.volume} ($tag)", inst.volume in 0.0..1.0)
            assertTrue("decay ${inst.decay} ($tag)", inst.decay in 0.01..4.0)
            assertTrue("duty ${inst.duty} ($tag)", inst.duty in Instrument.DUTY_CYCLES.indices)
            assertTrue(tag, inst.arpeggio.size <= Instrument.MAX_ARPEGGIO_STEPS)
            for (s in inst.arpeggio) assertTrue("arpeggio $s ($tag)", kotlin.math.abs(s) <= Instrument.MAX_ARPEGGIO_SEMITONES)
        }
        for (pattern in song.patterns) {
            assertTrue(tag, pattern.length in 4..Chip.MAX_STEPS)
            assertEquals(tag, song.tracks.size, pattern.rows.size)
            for (row in pattern.rows) {
                assertEquals(tag, Chip.MAX_STEPS, row.size)
                for (note in row) {
                    assertTrue("note $note ($tag)", note == Chip.EMPTY_NOTE || note == Chip.NOTE_OFF || note in 0..127)
                }
            }
        }
        assertEquals(tag, song.patterns.size, song.patterns.map { it.id }.toSet().size)
        assertEquals(tag, song.patterns.size, song.patterns.map { it.name }.toSet().size)
        assertFalse(tag, song.arrangement.isEmpty())
        assertTrue(tag, song.arrangement.all { it.repeats in 1..SongSection.MAX_REPEATS })
    }

    @Test fun chainStaysInsideTheSongsPatterns() = forEachSong { original, tag ->
        val song = original.normalized()
        val chain = song.chain
        assertFalse(tag, chain.isEmpty())
        assertTrue(tag, chain.size <= Chip.MAX_CHAIN)
        for (slot in chain) assertTrue("chain slot $slot ($tag)", slot in song.patterns.indices)
    }

    @Test fun encodeDecodeRoundTripsExceptForTheModifiedStamp() = forEachSong { original, tag ->
        val song = original.normalized()
        val decoded = SongDocument.decode(SongDocument.encode(song).toByteArray())
        assertTrue("song did not survive a JSON round trip ($tag)", equalIgnoringModified(song, decoded))
    }

    /** Swift excludes `modified` because a `Date` can lose its last bit; the
     * port stores the Double itself, so it survives exactly. */
    @Test fun theModifiedStampSurvivesExactlyToo() = forEachSong { original, tag ->
        val song = original.normalized().copy(modified = 781234567.123456789)
        assertEquals(tag, song, SongDocument.decode(SongDocument.encode(song).toByteArray()))
    }
}
