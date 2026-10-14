package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `MidiExportChannelTests.swift`: which channel and sound each track
 * gets, what it's called, and how loud its notes are. */
class MidiExportChannelTest {

    /** One track per kind given, each with a note on step 0. */
    private fun song(kinds: List<ChannelKind>): Song {
        val base = TestSongs.empty()
        val rows = kinds.map { Pattern.EMPTY_ROW.toMutableList().also { row -> row[0] = 60 } }
        return base.copy(tracks = kinds.map { Track(kind = it) }, patterns = listOf(base.patterns[0].copy(rows = rows)))
    }

    private fun parse(song: Song) = MidiBytes(MidiExport.data(song))

    private val mixed = listOf(
        ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.PULSE2, ChannelKind.TRIANGLE,
        ChannelKind.NOISE, ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.PULSE2,
    )

    // MARK: Channels and programs

    @Test fun melodicTracksCountUpFromZeroAndNoiseSharesTheDrumChannel() {
        val midi = parse(song(mixed))
        // Noise is channel 10 to a person, 9 on the wire.
        val expected = listOf(0, 9, 1, 2, 9, 3, 4, 5)
        for ((i, channel) in expected.withIndex()) {
            assertEquals("track $i", listOf(channel), MidiBytes.notes(midi.tracks[i + 1]).map { it.channel })
        }
    }

    @Test fun pulseGetsSquareLeadTriangleGetsSynthBassAndNoiseGetsNoProgram() {
        val midi = parse(song(mixed))
        // GM program 81 "Lead 1 (square)" and 39 "Synth Bass 1", counted from
        // zero on the wire: 80 and 38.
        val expected = listOf(
            listOf(MidiBytes.Event.Program(0, 80)),
            emptyList(),
            listOf(MidiBytes.Event.Program(1, 80)),
            listOf(MidiBytes.Event.Program(2, 38)),
            emptyList(),
            listOf(MidiBytes.Event.Program(3, 80)),
            listOf(MidiBytes.Event.Program(4, 38)),
            listOf(MidiBytes.Event.Program(5, 80)),
        )
        for ((i, programs) in expected.withIndex()) {
            val actual = midi.tracks[i + 1].filter { it.event is MidiBytes.Event.Program }
            assertEquals("track $i", programs, actual.map { it.event })
            assertTrue("track $i", actual.all { it.tick == 0 })
        }
    }

    @Test fun aTrackOpensWithItsNameThenItsProgramThenItsNotes() {
        val midi = parse(song(listOf(ChannelKind.TRIANGLE)))
        val opening = midi.tracks[1].take(3).map { it.event }
        assertEquals(3, opening.size)
        assertEquals(MidiBytes.Event.Meta(0x03, MidiBytes.utf8("Triangle")), opening[0])
        assertEquals(MidiBytes.Event.Program(0, 38), opening[1])
        val on = opening[2] as? MidiBytes.Event.NoteOn
        assertEquals("third is ${opening[2]}", listOf(0, 60), on?.let { listOf(it.channel, it.note) })
    }

    // MARK: Names

    @Test fun tracksAreNamedAsTheEditorNamesThem() {
        val song = song(listOf(ChannelKind.TRIANGLE, ChannelKind.TRIANGLE, ChannelKind.PULSE1, ChannelKind.NOISE))
            .withTrack(2) { it.copy(name = "Bässe") }
        val midi = parse(song)
        assertEquals(listOf("Triangle A", "Triangle B", "Bässe", "Noise"), midi.chipTracks.map { MidiBytes.name(it) })
        // "ä" is two bytes, so six bytes for five letters.
        assertEquals(listOf(listOf(0x42, 0xC3, 0xA4, 0x73, 0x73, 0x65)), MidiBytes.metas(0x03, midi.tracks[3]))
    }

    // MARK: Velocity

    @Test fun velocityFollowsTheTracksVolume() {
        // round(volume × 127). One that rounds to 0 is a silent track: a
        // note-on at velocity 0 is a note-off, so its notes go in at 1 and
        // its channel's volume is set to 0, as a muted track's is.
        data class Case(val volume: Double, val velocity: Int, val silent: Boolean)
        val cases = listOf(
            Case(1.0, 127, false),
            Case(0.8, 102, false), // 101.6
            Case(0.6, 76, false), // 76.2
            Case(0.5, 64, false), // 63.5, half rounds up
            Case(0.45, 57, false), // 57.15
            Case(0.01, 1, false), // 1.27
            Case(0.0, 1, true),
        )
        var song = song(List(cases.size) { ChannelKind.PULSE1 })
        for ((i, c) in cases.withIndex()) song = song.withInstrument(i) { it.copy(volume = c.volume) }
        val midi = parse(song)
        for ((i, c) in cases.withIndex()) {
            val track = midi.tracks[i + 1]
            assertEquals("volume ${c.volume}", listOf(c.velocity), MidiBytes.notes(track).map { it.velocity })
            val volumes = track.count { (it.event as? MidiBytes.Event.Control)?.let { e -> e.controller == 7 && e.value == 0 } == true }
            assertEquals("volume ${c.volume}", if (c.silent) 1 else 0, volumes)
        }
    }

    @Test fun noiseTracksKeepTheirOwnVelocityOnTheSharedChannel() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE))
            .withInstrument(0) { it.copy(volume = 0.9) }
            .withInstrument(1) { it.copy(volume = 0.3) }
        val midi = parse(song)
        // 114.3 and 38.1.
        assertEquals(listOf(114), MidiBytes.notes(midi.tracks[1]).map { it.velocity })
        assertEquals(listOf(38), MidiBytes.notes(midi.tracks[2]).map { it.velocity })
    }
}
