package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of `MidiExportNoteTests.swift`: where notes start and stop. One step
 * is 24 ticks (96 per quarter, four steps to the beat), so step `s` of the
 * arrangement is tick `24 × s`. */
class MidiExportNoteTest {

    /** One pulse track playing [cells] from step 0. Sustain by default, so a
     * note lasts until something on the track ends it. */
    private fun song(
        cells: List<Int>,
        length: Int = 16,
        tempo: Double = 120.0,
        sustain: Boolean = true,
        decay: Double = 0.35,
    ): Song {
        val base = TestSongs.empty(tempo = tempo, length = length)
        val track = Track(kind = ChannelKind.PULSE1).let {
            it.copy(instrument = it.instrument.copy(sustain = sustain, decay = decay))
        }
        val row = Pattern.EMPTY_ROW.toMutableList()
        for ((step, n) in cells.withIndex()) row[step] = n
        return base.copy(tracks = listOf(track), patterns = listOf(base.patterns[0].copy(rows = listOf(row))))
    }

    /** Each note as [note, on, off]. */
    private fun notes(song: Song, track: Int = 0): List<List<Int>> {
        val midi = MidiBytes(MidiExport.data(song))
        return MidiBytes.notes(midi.tracks[track + 1]).map { listOf(it.note, it.on, it.off) }
    }

    private fun assertNotes(actual: List<List<Int>>, vararg expected: List<Int>) =
        assertEquals("as [note, on, off]", expected.toList(), actual)

    /** A second pattern on the one-track song, appended to the arrangement unless [arranged] is false. */
    private fun Song.appending(pattern: Pattern, arranged: Boolean = true): Song = copy(
        patterns = patterns + pattern,
        arrangement = if (arranged) arrangement + SongSection(patternID = pattern.id) else arrangement,
    )

    // MARK: What ends a note

    @Test fun aNoteEndsWhereTheNextOneStarts() {
        // Steps 0 and 4: the first note's off lands on the second's on, at 96.
        // The second holds to the end of the 16 steps, 384.
        assertNotes(notes(song(listOf(60, -1, -1, -1, 64))), listOf(60, 0, 96), listOf(64, 96, 384))
    }

    @Test fun anOffCellEndsTheNote() {
        assertNotes(notes(song(listOf(60, -1, Chip.NOTE_OFF))), listOf(60, 0, 48))
    }

    @Test fun restsCarryTheNoteOn() {
        // Nothing but rests after step 1, so the note holds to the very end.
        assertNotes(notes(song(listOf(-1, 62, -1, -1, -1, -1))), listOf(62, 24, 384))
    }

    @Test fun anOffWithNothingSoundingWritesNothing() {
        assertNotes(notes(song(listOf(Chip.NOTE_OFF, 60, Chip.NOTE_OFF, Chip.NOTE_OFF))), listOf(60, 24, 48))
    }

    @Test fun aDecayingNoteEndsAfterItsDecay() {
        // round(0.35 s × 120/60 beats/s × 96) = round(67.2) = 67.
        assertNotes(notes(song(listOf(60, -1, -1, -1, -1, -1, -1, -1, 64), sustain = false)),
            listOf(60, 0, 67), listOf(64, 192, 192 + 67))
        // round(0.35 × 132/60 × 96) = round(73.92) = 74 — rounds up.
        assertNotes(notes(song(listOf(60), tempo = 132.0, sustain = false)), listOf(60, 0, 74))
    }

    @Test fun aShortDecayStillLastsATick() {
        // round(0.01 × 40/60 × 96) = round(0.64) = 1, not 0. A note-on and its
        // own off at one tick would leave a DAW nothing to draw.
        assertNotes(notes(song(listOf(60), tempo = 40.0, sustain = false, decay = 0.01)), listOf(60, 0, 1))
    }

    @Test fun theNextNoteCutsALongDecay() {
        // 4 s at 120 BPM is 768 ticks, far past the next note at 48.
        assertNotes(notes(song(listOf(60, -1, 64), sustain = false, decay = 4.0)),
            listOf(60, 0, 48), listOf(64, 48, 384))
    }

    @Test fun theEndOfTheSongCutsALongDecay() {
        assertNotes(notes(song(List(14) { -1 } + 60, sustain = false, decay = 4.0)), listOf(60, 14 * 24, 384))
    }

    // MARK: Order at one tick

    @Test fun aRepeatedPitchIsOffThenOnAtTheSameTick() {
        // The other order would start the second note and then immediately
        // end it, which a DAW reads as one note running to step 1 and stopping.
        val midi = MidiBytes(MidiExport.data(song(listOf(60, 60))))
        val atStep1 = midi.tracks[1].filter { it.tick == 24 }.map { it.event }
        assertEquals(2, atStep1.size)
        val off = atStep1[0] as? MidiBytes.Event.NoteOff
        val on = atStep1[1] as? MidiBytes.Event.NoteOn
        assertEquals("first is ${atStep1[0]}", listOf(0, 60), off?.let { listOf(it.channel, it.note) })
        assertEquals("second is ${atStep1[1]}", listOf(0, 60), on?.let { listOf(it.channel, it.note) })
    }

    // MARK: Across the arrangement

    @Test fun aHeldNoteCarriesAcrossAPatternBoundary() {
        // A is 16 steps with a note at step 12; B is 8 steps with a note at
        // its step 4, which is step 20 of the song. Nothing in between.
        val b = Pattern(name = "B", length = 8, trackCount = 1).withNote(0, 4, 64)
        val song = song(List(12) { -1 } + 60).appending(b)
        assertNotes(notes(song), listOf(60, 12 * 24, 20 * 24), listOf(64, 20 * 24, 24 * 24))
    }

    @Test fun repeatsAndMixedLengthsJoinEndToEnd() {
        // A (16 steps) twice, then B (8 steps): starts at 0, 384 and 768, and
        // the song ends at (16 + 16 + 8) × 24 = 960.
        val b = Pattern(name = "B", length = 8, trackCount = 1).withNote(0, 0, 72)
        val base = song(listOf(60))
        val song = base.copy(
            patterns = base.patterns + b,
            arrangement = listOf(
                SongSection(patternID = base.patterns[0].id, repeats = 2),
                SongSection(patternID = b.id),
            ),
        )
        assertNotes(notes(song), listOf(60, 0, 384), listOf(60, 384, 768), listOf(72, 768, 960))
    }

    @Test fun cellsPastAPatternsLengthAreNotPlayed() {
        // Rows are always 64 long; a 4-step pattern only plays the first four.
        val song = song(listOf(60), length = 4).setNote(0, 8, 72)
        assertNotes(notes(song), listOf(60, 0, 96))
    }

    @Test fun onlyArrangedPatternsArePlayed() {
        val unused = Pattern(name = "B", length = 16, trackCount = 1).withNote(0, 0, 72)
        assertNotes(notes(song(listOf(60)).appending(unused, arranged = false)), listOf(60, 0, 384))
    }

    @Test fun everyTrackEndsAtTheLastTick() {
        // Four tracks whose last notes end in very different places. Every
        // track, conductor included, has to end on 24 × 24 = 576 so the file
        // loops cleanly in a DAW.
        val base = TestSongs.empty(length = 16).setNote(0, 0, 60).setNote(2, 15, 40)
        val b = Pattern(name = "B", length = 8, trackCount = 4).withNote(1, 3, 67)
        val song = base.appending(b)

        val midi = MidiBytes(MidiExport.data(song))
        assertEquals(5, midi.tracks.size)
        for ((i, track) in midi.tracks.withIndex()) {
            assertEquals("track $i", MidiBytes.Timed(576, MidiBytes.END_OF_TRACK), track.last())
            assertEquals("track $i", 1, track.count { it.event == MidiBytes.END_OF_TRACK })
        }
    }
}
