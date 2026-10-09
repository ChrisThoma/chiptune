package dev.individuation.chiptune.core

import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals

/** Songs the suites build on, plus a seeded RNG for the property tests.
 * Port of `Tests/Support/TestSongs.swift`. */
object TestSongs {

    /** A song with no notes at all — the base every builder starts from. */
    fun empty(name: String = "Test", tempo: Double = 120.0, length: Int = 16): Song {
        val song = Song.create(name)
        return song.copy(
            tempo = tempo,
            patterns = song.patterns.mapIndexed { i, p -> if (i == 0) p.copy(length = length) else p },
        )
    }

    /** One note on one track, everything else silent. */
    fun singleNote(
        kind: ChannelKind,
        note: Int = 69,
        tempo: Double = 120.0,
        sustain: Boolean = true,
        duty: Int = 2,
        arpeggio: List<Int> = emptyList(),
    ): Song {
        val song = empty(tempo = tempo)
        val track = Track(kind = kind).let {
            it.copy(
                instrument = it.instrument.copy(
                    sustain = sustain, decay = 0.35, volume = 1.0, duty = duty, arpeggio = arpeggio,
                ),
            )
        }
        val pattern = song.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW)).withNote(0, 0, note)
        return song.copy(tracks = listOf(track), patterns = listOf(pattern))
    }

    /** Two patterns chained in a stated order, each with a note on step 0. */
    fun twoPatterns(
        lengths: Pair<Int, Int> = 16 to 8,
        repeats: Pair<Int, Int> = 1 to 1,
        tempo: Double = 120.0,
    ): Song {
        val song = empty(tempo = tempo, length = lengths.first)
        val first = song.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW)).withNote(0, 0, 60)
        val second = Pattern(name = "B", length = lengths.second, trackCount = 1).withNote(0, 0, 72)
        return song.copy(
            tracks = listOf(Track(kind = ChannelKind.PULSE1)),
            patterns = listOf(first, second),
            arrangement = listOf(
                SongSection(patternID = first.id, repeats = repeats.first),
                SongSection(patternID = second.id, repeats = repeats.second),
            ),
        )
    }

    /** The song behind `Tests/Fixtures/golden-demo.wav`, written out as a literal. */
    fun golden(): Song {
        val song = Song.create("Golden").copy(tempo = 132.0)
        val lead = listOf(72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1)
        val harmony = listOf(-1, 64, -1, 67, -1, 64, -1, 67, -1, 65, -1, 69, -1, 65, -1, 62)
        val bass = listOf(48, -1, -1, -1, 48, -1, -1, -1, 53, -1, -1, -1, 43, -1, -1, -1)
        val drums = listOf(60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1)
        var pattern = song.patterns[0]
        for ((i, notes) in listOf(lead, harmony, bass, drums).withIndex()) {
            for ((step, n) in notes.withIndex()) pattern = pattern.withNote(i, step, n)
        }
        return song.copy(patterns = listOf(pattern))
    }
}

/** SplitMix64, bit for bit the Swift `SeededRandom`. */
class SeededRandom(seed: ULong) {
    private var state: ULong = seed

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
}

/** Asserts two songs are the same edit, ignoring `modified`. */
fun assertSameSong(a: Song, b: Song, message: String = "") {
    assertEquals(message, a.copy(modified = 0.0), b.copy(modified = 0.0))
}

fun equalIgnoringModified(a: Song, b: Song): Boolean = a.copy(modified = 0.0) == b.copy(modified = 0.0)
