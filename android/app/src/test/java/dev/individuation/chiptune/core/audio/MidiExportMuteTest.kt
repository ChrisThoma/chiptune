package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `MidiExportMuteTests.swift`: a muted track is still in the file,
 * silenced by a CC7 of 0 at its start that a DAW user can remove or raise to
 * get the part back. A muted noise track beside an audible one is the
 * exception: it is left empty. */
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

    @Test fun aMutedNoiseTrackBesideAnAudibleOneIsLeftEmpty() {
        // A CC7 of 0 on channel 10 would silence the unmuted noise track too,
        // and quiet notes would land on the audible track's keys and ticks.
        // So the muted one keeps its MIDI track and its name, and nothing else.
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1))))
        assertEquals(3, midi.tracks.size)
        val audible = midi.tracks[1]
        val muted = midi.tracks[2]
        assertEquals(emptyList<MidiBytes.Timed>(), controls(audible))
        // Hat at volume 0.5 is round(63.5) = 64.
        assertEquals(listOf(64, 64), MidiBytes.notes(audible).map { it.velocity })
        assertEquals("Noise A", MidiBytes.name(audible))
        // One sixteen-step pattern: 16 × 24 ticks.
        assertEquals(
            listOf(
                MidiBytes.Timed(0, MidiBytes.Event.Meta(0x03, MidiBytes.utf8("Noise B (muted)"))),
                MidiBytes.Timed(16 * 24, MidiBytes.END_OF_TRACK),
            ),
            muted,
        )
    }

    @Test fun everyMutedNoiseTrackBesideAnAudibleOneIsLeftEmpty() {
        val midi = MidiBytes(MidiExport.data(
            song(listOf(ChannelKind.NOISE, ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(0, 1, 3)),
        ))
        assertEquals(emptyList<MidiBytes.Note>(), MidiBytes.notes(midi.tracks[1]))
        assertEquals(emptyList<MidiBytes.Note>(), MidiBytes.notes(midi.tracks[4]))
        assertEquals(listOf(64, 64), MidiBytes.notes(midi.tracks[3]).map { it.velocity })
        // The muted pulse has a channel of its own, so it is silenced as usual.
        assertEquals(volumeZero(0), controls(midi.tracks[2]))
        assertEquals(2, MidiBytes.notes(midi.tracks[2]).size)
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

    // MARK: Only a drum track that plays empties the others

    /** The muted noise track keeps its notes and a CC7 of 0, as if it were
     * the only noise track: the unmuted one beside it plays nothing. */
    private fun assertSilencedNotEmptied(song: Song, index: Int) {
        val midi = MidiBytes(MidiExport.data(song))
        assertEquals(volumeZero(9), controls(midi.tracks[index + 1]))
        assertEquals(2, MidiBytes.notes(midi.tracks[index + 1]).size)
    }

    private fun mutedBesideSilentDrum() = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1))
        .withPattern(0) { p -> p.copy(rows = p.rows.mapIndexed { i, row -> if (i == 0) Pattern.EMPTY_ROW else row }) }

    @Test fun anUnmutedNoiseTrackWithNoNotesEmptiesNothing() =
        assertSilencedNotEmptied(mutedBesideSilentDrum(), 1)

    @Test fun notesPastThePatternsEndDoNotCountAsPlaying() {
        val song = mutedBesideSilentDrum()
        assertSilencedNotEmptied(song.setNote(0, song.patterns[0].length, 60), 1)
    }

    @Test fun notesInAPatternTheArrangementSkipsDoNotCountAsPlaying() {
        val song = mutedBesideSilentDrum()
        val unplayed = Pattern(name = "B", trackCount = 2).withNote(0, 0, 60)
        assertSilencedNotEmptied(song.copy(patterns = song.patterns + unplayed), 1)
    }

    // MARK: A track at 0% volume is silent, like a muted one

    /** A track whose volume rounds to velocity 0. */
    private fun song(kinds: List<ChannelKind>, muted: Set<Int> = emptySet(), silent: Set<Int>): Song =
        silent.fold(song(kinds, muted)) { song, i -> song.withInstrument(i) { it.copy(volume = 0.0) } }

    private val none = emptyList<MidiBytes.Timed>()

    @Test fun aTrackAtZeroVolumeIsSilencedWithItsChannelVolume() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE), silent = setOf(1))))
        val triangle = midi.tracks[2]
        assertEquals(volumeZero(1), controls(triangle))
        // A note-on needs a velocity of at least 1 to be a note at all.
        assertEquals(listOf(listOf(60, 1), listOf(62, 1)), MidiBytes.notes(triangle).map { listOf(it.note, it.velocity) })
        // It isn't muted, so it isn't called muted.
        assertEquals("Triangle", MidiBytes.name(triangle))
        assertEquals(none, controls(midi.tracks[1]))
    }

    /** round(0.003 × 127) = round(0.381) = 0: silent. round(0.004 × 127) =
     * round(0.508) = 1: the quietest audible track, left alone. */
    @Test fun onlyAVolumeThatRoundsToZeroIsSilent() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.PULSE2), muted = emptySet())
            .withInstrument(0) { it.copy(volume = 0.003) }
            .withInstrument(1) { it.copy(volume = 0.004) }
        val midi = MidiBytes(MidiExport.data(song))
        assertEquals(volumeZero(0), controls(midi.tracks[1]))
        assertEquals(none, controls(midi.tracks[2]))
        assertEquals(listOf(1, 1), MidiBytes.notes(midi.tracks[2]).map { it.velocity })
    }

    @Test fun aNoiseTrackAtZeroVolumeOnItsOwnSilencesTheDrumChannel() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE), silent = setOf(1))))
        assertEquals(volumeZero(9), controls(midi.tracks[2]))
        assertEquals(listOf(1, 1), MidiBytes.notes(midi.tracks[2]).map { it.velocity })
        assertEquals("Noise", MidiBytes.name(midi.tracks[2]))
    }

    /** The same reason as a muted one: a CC7 of 0 on the drum channel would
     * silence the audible noise track too. */
    @Test fun aNoiseTrackAtZeroVolumeBesideAnAudibleOneIsLeftEmpty() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), silent = setOf(1))))
        assertEquals(none, controls(midi.tracks[1]))
        assertEquals(listOf(64, 64), MidiBytes.notes(midi.tracks[1]).map { it.velocity })
        assertEquals(
            listOf(
                MidiBytes.Timed(0, MidiBytes.Event.Meta(0x03, MidiBytes.utf8("Noise B"))),
                MidiBytes.Timed(16 * 24, MidiBytes.Event.Meta(0x2F, emptyList())),
            ),
            midi.tracks[2],
        )
    }

    /** A noise track at 0% doesn't play, so it empties nothing: the muted
     * one beside it is silenced with the channel's volume, and so is it. */
    @Test fun aNoiseTrackAtZeroVolumeDoesNotEmptyAMutedOne() {
        val midi = MidiBytes(MidiExport.data(song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1), silent = setOf(0))))
        for (i in listOf(1, 2)) {
            assertEquals("track ${i - 1}", volumeZero(9), controls(midi.tracks[i]))
            assertEquals("track ${i - 1}", 2, MidiBytes.notes(midi.tracks[i]).size)
        }
        assertEquals("Noise A", MidiBytes.name(midi.tracks[1]))
        assertEquals("Noise B (muted)", MidiBytes.name(midi.tracks[2]))
    }

    @Test fun emptiedTracksCountsZeroVolumeNoiseBesideAnAudibleOne() {
        val song = song(
            listOf(ChannelKind.NOISE, ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE),
            muted = setOf(3),
            silent = setOf(1, 2),
        )
        assertEquals(setOf(2, 3), MidiExport.emptiedTracks(song, song.chain))
    }
}
