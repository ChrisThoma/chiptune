package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of `MidiExportHeaderTests.swift`: the file's frame, the MThd chunk and
 * the conductor track. Expected bytes are written out from the SMF spec, not
 * read back from the writer. */
class MidiExportHeaderTest {

    private fun parse(song: Song) = MidiBytes(MidiExport.data(song))

    // MARK: MThd

    @Test fun headerIsFormatOneAtNinetySixTicksPerQuarter() {
        // Four tracks by default, so five chunks with the conductor.
        val data = MidiExport.data(TestSongs.empty())
        val expected = MidiBytes.bytes(
            0x4D, 0x54, 0x68, 0x64, // "MThd"
            0x00, 0x00, 0x00, 0x06, // header length
            0x00, 0x01, // format 1
            0x00, 0x05, // tracks
            0x00, 0x60, // 96 ticks per quarter
        )
        assertArrayEquals(expected, data.copyOfRange(0, 14))
    }

    @Test fun trackCountIsOnePerChipTrackPlusTheConductor() {
        for (count in listOf(1, 3, Chip.MAX_TRACKS)) {
            val base = TestSongs.empty()
            val song = base.copy(
                tracks = List(count) { Track(kind = ChannelKind.entries[it % 4]) },
                patterns = listOf(base.patterns[0].copy(rows = List(count) { Pattern.EMPTY_ROW })),
            )
            val midi = parse(song)
            assertEquals("$count tracks", count + 1, midi.declaredTrackCount)
            assertEquals("$count tracks: MTrk chunks in the file", count + 1, midi.tracks.size)
            assertEquals(1, midi.format)
            assertEquals(96, midi.division)
        }
    }

    // MARK: Conductor

    /** The whole conductor chunk, byte for byte, for a 16-step song at 120:
     * 500,000 µs per quarter is 07 A1 20, and the song ends at 16 × 24 = 384
     * ticks, which is 83 00 as a VLQ. */
    @Test fun conductorChunkIsExactlyNameTempoMeterAndEnd() {
        val data = MidiExport.data(TestSongs.empty(name = "Test", tempo = 120.0))
        val conductor = MidiBytes.bytes(
            0x4D, 0x54, 0x72, 0x6B, // "MTrk"
            0x00, 0x00, 0x00, 0x1C, // 28 bytes follow
            0x00, 0xFF, 0x03, 0x04, 0x54, 0x65, 0x73, 0x74, // name "Test"
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // tempo
            0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08, // 4/4, 24 clocks, 8 32nds
            0x83, 0x00, 0xFF, 0x2F, 0x00, // end of track at 384
        )
        assertArrayEquals(conductor, data.copyOfRange(14, 14 + conductor.size))
    }

    @Test fun tempoIsRoundedMicrosecondsPerQuarter() {
        // 60,000,000 / 132 = 454,545.45… → 454,545 = 0x06EF91.
        // 60,000,000 / 70 = 857,142.86… → 857,143 = 0x0D1437: rounds up, so a
        // truncating writer would be off by one here.
        // 60,000,000 / 40 = 1,500,000 = 0x16E360, the slowest tempo there is.
        val cases = listOf(
            132.0 to listOf(0x06, 0xEF, 0x91),
            70.0 to listOf(0x0D, 0x14, 0x37),
            40.0 to listOf(0x16, 0xE3, 0x60),
        )
        for ((tempo, expected) in cases) {
            val midi = parse(TestSongs.empty(tempo = tempo))
            assertEquals("$tempo BPM", listOf(expected), MidiBytes.metas(0x51, midi.tracks[0]))
        }
    }

    @Test fun outOfRangeTempoIsClampedFirst() {
        // Normalized like the WAV export: 1000 BPM plays as 300, which is
        // 200,000 µs = 0x030D40.
        val midi = parse(TestSongs.empty().copy(tempo = 1000.0))
        assertEquals(listOf(listOf(0x03, 0x0D, 0x40)), MidiBytes.metas(0x51, midi.tracks[0]))
    }

    // MARK: Text

    @Test fun songNameIsUtf8WithItsByteLength() {
        // "Café 歌": é is two bytes and 歌 three, so nine bytes for six
        // characters. A character count would cut the name short.
        val midi = parse(TestSongs.empty(name = "Café 歌"))
        val expected = listOf(0x43, 0x61, 0x66, 0xC3, 0xA9, 0x20, 0xE6, 0xAD, 0x8C)
        assertEquals(listOf(expected), MidiBytes.metas(0x03, midi.tracks[0]))
    }

    @Test fun longNameGetsAMultiByteLength() {
        // 200 bytes needs two VLQ bytes: 200 = 1×128 + 72 → 81 48.
        val data = MidiExport.data(TestSongs.empty(name = "L".repeat(200)))
        // MThd (14) + "MTrk" and its length (8) + delta 0, FF 03.
        assertArrayEquals(MidiBytes.bytes(0x00, 0xFF, 0x03, 0x81, 0x48), data.copyOfRange(22, 27))
        assertArrayEquals(ByteArray(200) { 0x4C }, data.copyOfRange(27, 227))
    }

    @Test fun blankNameIsNormalizedFirst() {
        val midi = parse(TestSongs.empty(name = "  "))
        assertEquals(Song.DEFAULT_NAME, MidiBytes.name(midi.tracks[0]))
    }
}
