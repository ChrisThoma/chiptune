package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.TestSongs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Twin of the Swift `NoteEffect` model tests: per-note pitch effects live in
 * `Pattern.effects`, parallel to `rows`, and are written to the file only
 * when a cell has one, so songs without effects save exactly as before. */
class NoteEffectTest {

    private fun songWithNote(note: Int = 64): Song = TestSongs.singleNote(ChannelKind.PULSE1, note).normalized()

    private fun roundTrip(song: Song): Song = SongCodec.decode(SongCodec.encode(song))

    // MARK: The enum

    @Test fun codesSymbolsAndNamesAreTheSpecifiedOnes() {
        assertEquals(listOf(0, 1, 2, 3, 4, 5), NoteEffect.entries.map { it.code })
        assertEquals(listOf("", "↗", "↘", "~", "⌒", "⤴"), NoteEffect.entries.map { it.symbol })
        assertEquals(listOf("No effect", "Slide up", "Slide down", "Vibrato", "Glide", "Bend in"),
            NoteEffect.entries.map { it.displayName })
    }

    @Test fun unknownCodesAreNone() {
        assertEquals(NoteEffect.VIBRATO, NoteEffect.fromCode(3))
        for (raw in listOf(-1L, 6L, 9L, 127L, 300L, Long.MAX_VALUE)) {
            assertEquals("code $raw", NoteEffect.NONE, NoteEffect.fromCode(raw))
        }
    }

    // MARK: Labels

    @Test fun aLabelCarriesTheEffectSymbolAfterTheNote() {
        assertEquals("E5↗", NoteName.label(76, NoteEffect.SLIDE_UP))
        assertEquals("G5~", NoteName.label(79, NoteEffect.VIBRATO))
        assertEquals("A4⌒", NoteName.label(69, NoteEffect.GLIDE))
        assertEquals("C#4⤴", NoteName.label(61, NoteEffect.BEND_IN))
        assertEquals("C3↘", NoteName.label(48, NoteEffect.SLIDE_DOWN))
    }

    @Test fun noEffectOrNoNoteKeepsThePlainLabel() {
        assertEquals("E5", NoteName.label(76, NoteEffect.NONE))
        assertEquals("REST", NoteName.label(Chip.NOTE_OFF, NoteEffect.VIBRATO))
        assertEquals("", NoteName.label(Chip.EMPTY_NOTE, NoteEffect.SLIDE_UP))
    }

    // MARK: Pattern edits

    @Test fun aNewPatternHasNoEffects() {
        val p = Pattern(name = "A", trackCount = 4)
        assertFalse(p.hasEffects)
        for (row in 0 until 4) for (step in 0 until Chip.MAX_STEPS) assertEquals(NoteEffect.NONE, p.effect(row, step))
        assertEquals(NoteEffect.NONE, p.effect(9, 99))
    }

    @Test fun setAnEffectOnACell() {
        val p = Pattern(name = "A", trackCount = 2).withNote(1, 3, 60).withEffect(1, 3, NoteEffect.VIBRATO)
        assertEquals(NoteEffect.VIBRATO, p.effect(1, 3))
        assertEquals(NoteEffect.NONE, p.effect(0, 3))
        assertEquals(NoteEffect.NONE, p.effect(1, 2))
        assertTrue(p.hasEffects)
    }

    @Test fun clearingTheLastEffectLeavesAPatternEqualToOneThatNeverHadAny() {
        val plain = Pattern(name = "A", trackCount = 2).withNote(1, 3, 60)
        val back = plain.withEffect(1, 3, NoteEffect.GLIDE).withEffect(1, 3, NoteEffect.NONE)
        assertEquals(plain, back)
    }

    @Test fun clearingANoteOrPuttingOffOverItClearsItsEffect() {
        val p = Pattern(name = "A", trackCount = 1).withNote(0, 0, 60).withEffect(0, 0, NoteEffect.SLIDE_UP)
        assertEquals(NoteEffect.NONE, p.withNote(0, 0, Chip.EMPTY_NOTE).effect(0, 0))
        assertEquals(NoteEffect.NONE, p.withNote(0, 0, Chip.NOTE_OFF).effect(0, 0))
    }

    @Test fun aNewPitchOverANoteKeepsItsEffect() {
        val p = Pattern(name = "A", trackCount = 1).withNote(0, 0, 60).withEffect(0, 0, NoteEffect.SLIDE_UP)
        assertEquals(NoteEffect.SLIDE_UP, p.withNote(0, 0, 67).effect(0, 0))
    }

    @Test fun normalizePadsAndTrimsEffectsWithRows() {
        val short = Pattern(name = "A", rows = listOf(List(8) { 60 }), effects = listOf(listOf(NoteEffect.NONE, NoteEffect.VIBRATO)))
            .normalized(3)
        assertEquals(3, short.effects.size)
        assertTrue(short.effects.all { it.size == Chip.MAX_STEPS })
        assertEquals(NoteEffect.VIBRATO, short.effect(0, 1))

        val long = Pattern(name = "A", rows = List(5) { Pattern.EMPTY_ROW },
            effects = List(6) { List(Chip.MAX_STEPS + 10) { NoteEffect.GLIDE } }).normalized(2)
        assertEquals(2, long.effects.size)
        assertTrue(long.effects.all { it.size == Chip.MAX_STEPS })
    }

    @Test fun normalizeLeavesAPatternWithoutEffectsWithoutEffects() {
        val p = Pattern(name = "A", rows = listOf(Pattern.EMPTY_ROW),
            effects = listOf(List(Chip.MAX_STEPS) { NoteEffect.NONE })).normalized(1)
        assertTrue(p.effects.isEmpty())
        assertFalse(p.hasEffects)
    }

    // MARK: Codec

    @Test fun aSongWithoutEffectsDecodesWithNone() {
        val song = SongCodec.decode(SongCodec.encode(TestSongs.golden()))
        for (p in song.patterns) assertFalse(p.hasEffects)
    }

    @Test fun aSongWithoutEffectsEncodesWithoutTheKey() {
        for (song in listOf(TestSongs.golden(), TestSongs.twoPatterns(), Song.create())) {
            val text = SongCodec.encode(song)
            assertFalse("a song without effects wrote an effects key", text.contains("\"effects\""))
        }
    }

    @Test fun aCellsEffectRoundTrips() {
        for (effect in NoteEffect.entries) {
            val song = songWithNote().withEffect(0, 0, 0, effect)
            val back = roundTrip(song)
            assertEquals("$effect", effect, back.patterns[0].effect(0, 0))
            assertEquals(song.normalized(), back)
        }
    }

    @Test fun effectsAreWrittenAfterRowsInTheRowsShape() {
        val song = songWithNote().withEffect(0, 0, 0, NoteEffect.BEND_IN)
        val root = StrictJson.parse(SongCodec.encode(song)) as JsonValue.Obj
        val pattern = (root["patterns"] as JsonValue.Arr).items[0] as JsonValue.Obj
        assertEquals(listOf("id", "name", "length", "rows", "effects"), pattern.entries.keys.toList())
        val effects = (pattern["effects"] as JsonValue.Arr).items.map { (it as JsonValue.Arr).items }
        assertEquals(1, effects.size)
        assertEquals(Chip.MAX_STEPS, effects[0].size)
        assertEquals(5L, (effects[0][0] as JsonValue.Num).asLongOrNull())
        assertEquals(0L, (effects[0][1] as JsonValue.Num).asLongOrNull())
    }

    private fun swiftShapedSong(effects: String): String {
        val row = (0 until Chip.MAX_STEPS).joinToString(", ") { if (it == 0) "64" else if (it == 4) "67" else "-1" }
        return """
        {
          "id" : "5A1C8E0B-7F7E-4C35-9C1D-2C0E2E3F4A5B",
          "name" : "From iOS",
          "tempo" : 120,
          "tracks" : [
            {
              "id" : "0B8D3F55-1C4F-4E8A-9E8E-6B7C1D2E3F40",
              "kind" : 0,
              "instrument" : { "duty" : 2, "volume" : 0.8, "decay" : 0.35, "sustain" : false, "arpeggio" : [] },
              "muted" : false
            }
          ],
          "patterns" : [
            {
              "id" : "9F7E6D5C-4B3A-4291-8F7E-6D5C4B3A2910",
              "name" : "A",
              "length" : 16,
              "rows" : [
                [$row]
              ]$effects
            }
          ],
          "arrangement" : [
            { "id" : "1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D", "patternID" : "9F7E6D5C-4B3A-4291-8F7E-6D5C4B3A2910", "repeats" : 1 }
          ],
          "modified" : 785000000
        }
        """.trimIndent()
    }

    @Test fun aSwiftWrittenSongWithEffectsDecodes() {
        val cells = (0 until Chip.MAX_STEPS).joinToString(", ") { if (it == 0) "3" else if (it == 4) "4" else "0" }
        val song = SongCodec.decode(swiftShapedSong(",\n      \"effects\" : [\n        [$cells]\n      ]"))
        val p = song.patterns[0]
        assertEquals(NoteEffect.VIBRATO, p.effect(0, 0))
        assertEquals(NoteEffect.GLIDE, p.effect(0, 4))
        assertEquals(NoteEffect.NONE, p.effect(0, 1))
        // And back out in the same shape.
        assertEquals(song, roundTrip(song))
    }

    @Test fun aSwiftWrittenSongWithoutEffectsDecodes() {
        val p = SongCodec.decode(swiftShapedSong("")).patterns[0]
        assertFalse(p.hasEffects)
        assertEquals(64, p.rows[0][0])
    }

    @Test fun unknownEffectValuesDecodeAsNone() {
        val song = SongCodec.decode(swiftShapedSong(",\n \"effects\" : [[9, 1, -4, 300]]"))
        val p = song.patterns[0]
        assertEquals(NoteEffect.NONE, p.effect(0, 0))
        assertEquals(NoteEffect.SLIDE_UP, p.effect(0, 1))
        assertEquals(NoteEffect.NONE, p.effect(0, 2))
        assertEquals(NoteEffect.NONE, p.effect(0, 3))
    }

    @Test fun nullEffectsAreMissingEffects() {
        assertFalse(SongCodec.decode(swiftShapedSong(",\n \"effects\" : null")).patterns[0].hasEffects)
    }

    @Test fun effectsOfTheWrongTypeRejectTheSong() {
        for (bad in listOf("\"x\"", "[\"x\"]", "[[\"x\"]]", "[[1.5]]", "[[null]]", "{}")) {
            try {
                SongCodec.decode(swiftShapedSong(",\n \"effects\" : $bad"))
                fail("effects $bad decoded")
            } catch (_: SongDecodeException) {
            }
        }
    }

    @Test fun shortEffectRowsArePaddedOnDecode() {
        val p = SongCodec.decode(swiftShapedSong(",\n \"effects\" : [[0, 2]]")).patterns[0]
        assertEquals(1, p.effects.size)
        assertEquals(Chip.MAX_STEPS, p.effects[0].size)
        assertEquals(NoteEffect.SLIDE_DOWN, p.effect(0, 1))
    }
}
