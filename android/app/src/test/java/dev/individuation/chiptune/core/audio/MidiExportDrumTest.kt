package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `MidiExportDrumTests.swift`: noise tracks come out as General MIDI
 * drums on channel 10, because a pitch played on the drum channel picks a
 * drum, not a note. */
class MidiExportDrumTest {

    /** GM percussion keys, from the GM 1 drum map. */
    private val kick = 36
    private val snare = 38
    private val closedHat = 42
    private val openHat = 46
    private val crash = 49

    /** One noise track playing [cells] from step 0 with [instrument]. */
    private fun song(cells: List<Int>, instrument: Instrument): Song {
        val base = TestSongs.empty()
        val row = Pattern.EMPTY_ROW.toMutableList()
        for ((step, n) in cells.withIndex()) row[step] = n
        return base.copy(
            tracks = listOf(Track(kind = ChannelKind.NOISE, instrument = instrument)),
            patterns = listOf(base.patterns[0].copy(rows = listOf(row))),
        )
    }

    /** Edited away from every preset, which the instrument menu shows as "Custom". */
    private val custom = Instrument(duty = 2, volume = 0.55, decay = 0.2)

    private fun drumNotes(song: Song): List<MidiBytes.Note> =
        MidiBytes(MidiExport.data(song)).chipTracks.flatMap { MidiBytes.notes(it) }

    private fun preset(name: String): InstrumentPreset =
        InstrumentPreset.presetsFor(ChannelKind.NOISE).first { it.name == name }

    // MARK: Presets

    @Test fun eachNoisePresetPlaysItsOwnDrumWhateverThePitch() {
        val expected = mapOf("Kick" to kick, "Snare" to snare, "Hat" to openHat, "Closed hat" to closedHat, "Crash" to crash)
        val presets = InstrumentPreset.presetsFor(ChannelKind.NOISE)
        assertEquals("a new noise preset needs a drum of its own", expected.keys, presets.map { it.name }.toSet())
        for (preset in presets) {
            val notes = drumNotes(song(listOf(60, -1, 40, -1, 71), preset.instrument))
            assertEquals(preset.name, List(3) { expected.getValue(preset.name) }, notes.map { it.note })
            assertEquals(preset.name, setOf(9), notes.map { it.channel }.toSet())
        }
    }

    /** Volume is how loud the drum is, not which drum it is, and duty means
     * nothing to the noise channel. A preset nudged in either is still that
     * preset's drum. */
    @Test fun aPresetWithItsVolumeOrDutyChangedStillPlaysItsDrum() {
        val louder = preset("Kick").instrument.copy(volume = 0.5)
        assertEquals(listOf(kick, kick, kick), drumNotes(song(listOf(60, -1, 40, -1, 71), louder)).map { it.note })

        val otherDuty = preset("Crash").instrument.copy(duty = 0, volume = 0.3)
        assertEquals(listOf(crash, crash), drumNotes(song(listOf(60, -1, 40), otherDuty)).map { it.note })
    }

    /** Decay, hold and arpeggio change the sound itself, so a preset edited
     * in any of them is custom and is banded by pitch. */
    @Test fun aPresetWithItsSoundChangedIsBandedByPitch() {
        val kickSound = preset("Kick").instrument
        for (instrument in listOf(kickSound.copy(decay = 0.2), kickSound.copy(sustain = true), kickSound.copy(arpeggio = listOf(0, 12)))) {
            assertEquals("$instrument", listOf(snare, kick, closedHat), drumNotes(song(listOf(60, 50, 70), instrument)).map { it.note })
        }
    }

    // MARK: Custom

    @Test fun customNoiseSpreadsItsDistinctNotesOverKickSnareAndHat() {
        // Sorted distinct notes, note i of n in band i × 3 / n (whole-number
        // division): 0 kick, 1 snare, 2 closed hat.
        val cases = listOf(
            // n = 1 is the one exception: a lone note is a snare, not a kick.
            listOf(65, -1, 65) to listOf(snare, snare),
            // n = 2: bands 0 and 3/2 = 1.
            listOf(70, 50) to listOf(snare, kick),
            // n = 3: bands 0, 1, 2.
            listOf(60, 50, 70) to listOf(snare, kick, closedHat),
            // n = 4, sorted 50 55 60 65: bands 0, 3/4 = 0, 6/4 = 1, 9/4 = 2.
            listOf(65, 50, 60, 55) to listOf(closedHat, kick, snare, kick),
        )
        for ((cells, drums) in cases) {
            assertEquals("cells $cells", drums, drumNotes(song(cells, custom)).map { it.note })
        }
    }

    @Test fun onlyNotesTheArrangementPlaysCountTowardTheBands() {
        // 50 60 70 alone are bands 0 1 2. Counting the 80 past the pattern's
        // end, or the 90 in a pattern nothing plays, would shift them down.
        val base = song(listOf(50, -1, 60, -1, 70), custom).setNote(0, 20, 80)
        val unused = Pattern(name = "B", length = 16, trackCount = 1).withNote(0, 0, 90)
        val song = base.copy(patterns = base.patterns + unused)
        assertEquals(listOf(kick, snare, closedHat), drumNotes(song).map { it.note })
    }

    @Test fun eachCustomTrackIsBandedOnItsOwnNotes() {
        val base = TestSongs.empty()
        val song = base.copy(
            tracks = listOf(Track(kind = ChannelKind.NOISE, instrument = custom), Track(kind = ChannelKind.NOISE, instrument = custom)),
            patterns = listOf(base.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW))),
        ).setNote(0, 0, 40).setNote(0, 4, 80).setNote(1, 2, 60)
        val midi = MidiBytes(MidiExport.data(song))
        assertEquals(listOf(kick, snare), MidiBytes.notes(midi.tracks[1]).map { it.note })
        assertEquals(listOf(snare), MidiBytes.notes(midi.tracks[2]).map { it.note })
    }

    /** Why the bands are relative. The library songs keep their noise notes
     * between 52 and 71, so fixed pitch ranges would make nearly every hit
     * a snare. Boss Door's noise track is a custom instrument. */
    @Test fun aLibrarySongsDrumsUseAllThreeBands() {
        val bytes = javaClass.classLoader!!.getResourceAsStream("song-library-boss-door.chipsong")!!.use { it.readBytes() }
        val song = SongDocument.decode(bytes)
        val noise = song.tracks.indexOfFirst { it.kind == ChannelKind.NOISE }
        assertTrue(noise >= 0)
        assertNull(InstrumentPreset.matching(song.tracks[noise].instrument, ChannelKind.NOISE))
        val written = song.chain.flatMap { song.patterns[it].rows[noise].take(song.patterns[it].length) }
            .filter { it >= 0 }.toSet()
        assertTrue("the premise: ${written.sorted()}", written.all { it in 52..71 })

        val midi = MidiBytes(MidiExport.data(song))
        val drums = MidiBytes.notes(midi.tracks[noise + 1]).map { it.note }.toSet()
        assertEquals(setOf(kick, snare, closedHat), drums)
    }

    // MARK: Length

    @Test fun aNoiseNoteLastsAtMostOneTickShortOfAStep() {
        // Every noise track shares channel 10, so one track's off must never
        // land on the tick where another starts the same drum: a DAW merging
        // the tracks could put the off second and swallow the hit. 23 ticks
        // is the longest that guarantees it.
        // Crash decays for 1.4 s, which would be round(1.4 × 2 × 96) = 269 ticks.
        assertEquals(listOf(listOf(0, 23)),
            drumNotes(song(listOf(60), preset("Crash").instrument)).map { listOf(it.on, it.off) })

        val held = custom.copy(sustain = true)
        assertEquals(listOf(listOf(24, 47)), drumNotes(song(listOf(-1, 60), held)).map { listOf(it.on, it.off) })

        // The cap only ever shortens. Closed hat decays in
        // round(0.04 × 2 × 96) = round(7.68) = 8 ticks, inside it.
        assertEquals(listOf(listOf(0, 8), listOf(24, 32)),
            drumNotes(song(listOf(60, 60), preset("Closed hat").instrument)).map { listOf(it.on, it.off) })
    }

    @Test fun twoNoiseTracksOnOneDrumNeverMeetAtATick() {
        // Both hats, alternating steps: each off falls a tick before the other
        // track's next on.
        val base = TestSongs.empty()
        var song = base.copy(
            tracks = listOf(Track(kind = ChannelKind.NOISE), Track(kind = ChannelKind.NOISE)),
            patterns = listOf(base.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW))),
        ).withInstrument(0) { it.copy(sustain = true) }.withInstrument(1) { it.copy(sustain = true) }
        for (step in 0 until 16 step 2) song = song.setNote(0, step, 60).setNote(1, step + 1, 60)
        val midi = MidiBytes(MidiExport.data(song))
        val ons = HashSet<Int>()
        val offs = HashSet<Int>()
        for (track in midi.chipTracks) {
            for (timed in track) {
                if (timed.event is MidiBytes.Event.NoteOn) ons.add(timed.tick)
                if (timed.event is MidiBytes.Event.NoteOff) offs.add(timed.tick)
            }
        }
        assertEquals(16, ons.size)
        assertTrue("offs ${offs.sorted()} meet ons ${ons.sorted()}", offs.intersect(ons).isEmpty())
    }
}
