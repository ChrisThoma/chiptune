package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import java.io.File
import java.nio.file.AccessDeniedException
import javax.sound.midi.MidiSystem
import javax.sound.midi.ShortMessage
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of `MidiExportFileTests.swift`: the exported file on disk, that
 * something other than this app's own reader can open it, where it lands,
 * and what it clears away. */
class MidiExportFileTest {

    @get:Rule val temp = TemporaryFolder()

    private fun render(song: Song): File {
        val result = MidiExport.render(ExportRequest(song), temp.root)
        assertTrue("expected a file, got $result", result is ExportResult.Success)
        return (result as ExportResult.Success).file
    }

    private fun fileNames(dir: File): Set<String> = dir.list()!!.toSet()

    // MARK: An independent reader

    /** The JDK's own SMF parser, `javax.sound.midi`, stands in for a DAW the
     * way AudioToolbox does on iOS. */
    @Test fun theJdkMidiReaderReadsTheExportAsTheSong() {
        val song = TestSongs.golden().withPattern(0) { p ->
            p.copy(rows = p.rows.mapIndexed { i, row -> if (i == 1) Pattern.EMPTY_ROW else row })
        }.setNote(1, 0, 64)
        val sequence = MidiSystem.getSequence(render(song))

        // The conductor, then four chip tracks.
        assertEquals(96, sequence.resolution)
        assertEquals(5, sequence.tracks.size)

        // 132 BPM is stored as 454,545 µs per quarter, a hair over 132.
        val conductor = sequence.tracks[0]
        val tempos = (0 until conductor.size()).map { conductor.get(it).message }
            .filterIsInstance<javax.sound.midi.MetaMessage>().filter { it.type == 0x51 }
            .map { m -> m.data.fold(0) { acc, b -> acc shl 8 or (b.toInt() and 0xFF) } }
        assertEquals(listOf(454_545), tempos)

        data class Loaded(val tick: Long, val note: Int, val channel: Int)
        fun notes(track: Int): List<Loaded> {
            val t = sequence.tracks[track]
            return (0 until t.size()).map { t.get(it) }.mapNotNull { e ->
                val m = e.message as? ShortMessage ?: return@mapNotNull null
                if (m.command == ShortMessage.NOTE_ON && m.data2 > 0) Loaded(e.tick, m.data1, m.channel) else null
            }
        }

        // The golden lead plays eight notes, one every half beat; the
        // harmony track now plays one, at the top.
        val lead = notes(1)
        assertEquals(listOf(72, 76, 79, 76, 74, 77, 81, 79), lead.map { it.note })
        assertEquals(List(8) { it * 48L }, lead.map { it.tick })
        val harmony = notes(2)
        assertEquals(listOf(64), harmony.map { it.note })
        assertEquals(listOf(1), harmony.map { it.channel })
        // The drums are on channel 10, every hit the Hat preset's open hat.
        val drums = notes(4)
        assertEquals(setOf(9), drums.map { it.channel }.toSet())
        assertEquals(setOf(46), drums.map { it.note }.toSet())
        assertEquals(6, drums.size)
    }

    // MARK: Where it goes

    @Test fun theFileIsTheSongsBytesUnderItsSafeName() {
        val song = TestSongs.empty(name = "My Song / v2").setNote(0, 0, 60)
        val file = render(song)
        assertEquals(MidiExport.filename(song, temp.root), file)
        assertEquals("My Song v2.mid", file.name)
        assertEquals(song.id.toString().uppercase(), file.parentFile.name)
        assertArrayEquals(MidiExport.data(song), file.readBytes())
    }

    @Test fun theFileSitsInTheSongsOwnExportFolder() {
        // Beside the WAV, so the two can't miss each other's stale files, and
        // apart from any other song's export of the same name.
        val song = Song.create("Twin")
        assertEquals(WavExport.filename(song, temp.root).parentFile, MidiExport.filename(song, temp.root).parentFile)
        assertNotEquals(MidiExport.filename(song, temp.root), MidiExport.filename(Song.create("Twin"), temp.root))
    }

    @Test fun aLongNameStillMakesAFileName() {
        for (name in listOf("L".repeat(300), "歌".repeat(90))) {
            val fileName = MidiExport.filename(Song.create(name), temp.root).name
            val bytes = fileName.toByteArray(Charsets.UTF_8).size
            assertTrue("$bytes bytes", bytes <= 255)
            assertTrue(fileName.endsWith(".mid"))
            assertTrue(bytes > ".mid".length)
        }
    }

    // MARK: Pruning

    @Test fun aMidiExportClearsTheSongsOlderExportsOfEitherKind() {
        var song = TestSongs.empty(name = "One", tempo = 240.0).setNote(0, 0, 60)
        val wav = WavExport.render(song, temp.root)!!
        val dir = wav.parentFile
        File(dir, "Old.mid").writeBytes(byteArrayOf(0))
        File(dir, "keep.txt").writeBytes(byteArrayOf(0))

        song = song.copy(name = "Two")
        render(song)
        assertEquals(setOf("Two.mid", "keep.txt"), fileNames(dir))
    }

    @Test fun aWavExportClearsAnOlderMidiExport() {
        var song = TestSongs.empty(name = "One", tempo = 240.0).setNote(0, 0, 60)
        val dir = render(song).parentFile

        song = song.copy(name = "Two")
        WavExport.render(song, temp.root)!!
        assertEquals(setOf("Two.wav"), fileNames(dir))
    }

    // MARK: Failure

    @Test fun aFailedWriteReportsItsErrorAndKeepsThePreviousExport() {
        var song = TestSongs.empty(name = "One").setNote(0, 0, 60)
        val first = render(song)
        val firstBytes = first.readBytes()
        val dir = first.parentFile

        assertTrue(dir.setWritable(false))
        try {
            song = song.copy(name = "Two")
            val result = MidiExport.render(ExportRequest(song), temp.root)
            assertTrue("expected the write to fail, got $result", result is ExportResult.Failed)
            val error = (result as ExportResult.Failed).error
            assertTrue("$error", error is AccessDeniedException)
            assertArrayEquals(firstBytes, first.readBytes())
            assertEquals(setOf("One.mid"), fileNames(dir))
        } finally {
            dir.setWritable(true)
        }
    }

    /** Port-specific, as in `WavExportTest`: the root is injectable, so it can
     * be made unusable. */
    @Test fun anUnwritableRootFailsRatherThanThrowing() {
        val notADirectory = temp.newFile("plain-file")
        val result = MidiExport.render(ExportRequest(TestSongs.empty().setNote(0, 0, 60)), notADirectory)
        assertTrue("expected Failed, got $result", result is ExportResult.Failed)
    }
}
