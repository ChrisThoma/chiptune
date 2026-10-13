package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `MidiExportMuteTests.swift`: a muted track is still in the file, so
 * unmuting it in a DAW gets the part back, but it plays silent until someone
 * does. */
class MidiExportMuteTest {

    private fun song(kinds: List<ChannelKind>, muted: Set<Int>): Song {
        val base = TestSongs.empty()
        val rows = kinds.map { Pattern.EMPTY_ROW.toMutableList().also { row -> row[0] = 60; row[8] = 62 } }
        return base.copy(
            tracks = kinds.mapIndexed { i, kind -> Track(kind = kind, muted = i in muted) },
            patterns = listOf(base.patterns[0].copy(rows = rows)),
        )
    }

    private fun controls(track: List<MidiBytes.Timed>) = track.filter { it.event is MidiBytes.Event.Control }

    private fun volumeZero(channel: Int) = listOf(MidiBytes.Timed(0, MidiBytes.Event.Control(channel, 7, 0)))

    @Test fun aMutedTrackKeepsItsNotesAndSetsItsChannelVolumeToZero() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE), muted = setOf(1))))
        val triangle = midi.tracks[2]
        assertEquals(volumeZero(1), controls(triangle))
        assertEquals("Triangle (muted)", MidiBytes.name(triangle))
        // Notes as they'd be unmuted: the triangle's 0.9 volume is velocity
        // round(114.3) = 114.
        assertEquals(listOf(listOf(60, 114), listOf(62, 114)), MidiBytes.notes(triangle).map { listOf(it.note, it.velocity) })
        // The volume is set before the first note can sound.
        val firstNote = triangle.indexOfFirst { it.event is MidiBytes.Event.NoteOn }
        val volume = triangle.indexOfFirst { it.event is MidiBytes.Event.Control }
        assertTrue("volume at $volume, first note at $firstNote", volume >= 0 && firstNote >= 0 && volume < firstNote)

        // The unmuted pulse beside it is left alone.
        assertEquals(emptyList<MidiBytes.Timed>(), controls(midi.tracks[1]))
        assertEquals("Pulse 1", MidiBytes.name(midi.tracks[1]))
    }

    @Test fun aNamedMutedTrackKeepsItsName() {
        val song = song(listOf(ChannelKind.PULSE2), muted = setOf(0)).withTrack(0) { it.copy(name = "Echo") }
        val midi = MidiBytes(MidiExport.data(song))
        assertEquals("Echo (muted)", MidiBytes.name(midi.tracks[1]))
    }

    @Test fun aMutedNoiseTrackOnItsOwnSilencesTheDrumChannel() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE), muted = setOf(1))))
        assertEquals(volumeZero(9), controls(midi.tracks[2]))
        assertEquals("Noise (muted)", MidiBytes.name(midi.tracks[2]))
    }

    @Test fun aMutedNoiseTrackBesideAnAudibleOnePlaysAtVelocityOneInstead() {
        // A CC7 of 0 on channel 10 would silence the unmuted noise track too,
        // so the muted one goes as quiet as a note can go instead.
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1))))
        val audible = midi.tracks[1]
        val muted = midi.tracks[2]
        assertEquals(emptyList<MidiBytes.Timed>(), controls(audible))
        assertEquals(emptyList<MidiBytes.Timed>(), controls(muted))
        // Hat at volume 0.5 is round(63.5) = 64.
        assertEquals(listOf(64, 64), MidiBytes.notes(audible).map { it.velocity })
        assertEquals(listOf(1, 1), MidiBytes.notes(muted).map { it.velocity })
        assertEquals("Noise A", MidiBytes.name(audible))
        assertEquals("Noise B (muted)", MidiBytes.name(muted))
    }

    @Test fun everyNoiseTrackMutedSilencesTheDrumChannelFromEach() {
        val midi = MidiBytes(MidiExport.data(
            song(listOf(ChannelKind.NOISE, ChannelKind.PULSE1, ChannelKind.NOISE), muted = setOf(0, 2)),
        ))
        for (i in listOf(1, 3)) {
            assertEquals("track ${i - 1}", volumeZero(9), controls(midi.tracks[i]))
            assertEquals("track ${i - 1}", listOf(64, 64), MidiBytes.notes(midi.tracks[i]).map { it.velocity })
        }
    }
}
