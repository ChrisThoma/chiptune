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
import org.junit.Assert.assertFalse
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
        // Beside the song's WAV, and apart from any other song's export of
        // the same name.
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

    /** Through the dispatcher, which is where the app's exports prune. */
    private fun export(song: Song, format: ExportOptions.Format): File {
        val result = ExportRenderer.render(ExportRequest(song, ExportOptions(format = format)), temp.root)
        assertTrue("the $format export failed: $result", result is ExportResult.Success)
        return (result as ExportResult.Success).file
    }

    @Test fun aMidiExportClearsARenamedSongsOldExportsAndNothingElse() {
        var song = TestSongs.empty(name = "One", tempo = 240.0).setNote(0, 0, 60)
        val dir = export(song, ExportOptions.Format.MIDI).parentFile!!
        export(song, ExportOptions.Format.WAV)
        File(dir, "keep.txt").writeBytes(byteArrayOf(0))

        song = song.copy(name = "Two")
        export(song, ExportOptions.Format.MIDI)
        assertEquals(setOf("Two.mid", "keep.txt"), fileNames(dir))
    }

    @Test fun aWavExportClearsARenamedSongsOldExports() {
        var song = TestSongs.empty(name = "One", tempo = 240.0).setNote(0, 0, 60)
        val dir = export(song, ExportOptions.Format.WAV).parentFile!!
        export(song, ExportOptions.Format.MIDI)

        song = song.copy(name = "Two")
        export(song, ExportOptions.Format.WAV)
        assertEquals(setOf("Two.wav"), fileNames(dir))
    }

    /** The old name's file of the other format is as stale as its own: a
     * rename leaves nothing under the old name. */
    @Test fun aRenameClearsTheOldNamesFileOfTheOtherFormat() {
        var song = TestSongs.empty(name = "Old", tempo = 240.0).setNote(0, 0, 60)
        val dir = export(song, ExportOptions.Format.MIDI).parentFile!!
        File(dir, "keep.txt").writeBytes(byteArrayOf(0))

        song = song.copy(name = "New")
        export(song, ExportOptions.Format.WAV)
        assertEquals(setOf("New.wav", "keep.txt"), fileNames(dir))
    }

    /** The current name's file of the other format is the song's, not stale. */
    @Test fun aRenameKeepsTheNewNamesFileOfTheOtherFormat() {
        var song = TestSongs.empty(name = "Old", tempo = 240.0).setNote(0, 0, 60)
        val dir = export(song, ExportOptions.Format.MIDI).parentFile!!
        File(dir, "keep.txt").writeBytes(byteArrayOf(0))

        song = song.copy(name = "New")
        // Straight through the writer, which prunes nothing, so Old.mid is
        // still there beside it.
        render(song)
        assertEquals(setOf("Old.mid", "New.mid", "keep.txt"), fileNames(dir))
        export(song, ExportOptions.Format.WAV)
        assertEquals(setOf("New.wav", "New.mid", "keep.txt"), fileNames(dir))
    }

    /** Switching formats is not a stale export: the song's WAV and its MIDI
     * file are both wanted. */
    @Test fun eachFormatLeavesTheOthersFileAlone() {
        val song = TestSongs.empty(name = "Both", tempo = 240.0).setNote(0, 0, 60)
        val wav = export(song, ExportOptions.Format.WAV)
        val mid = export(song, ExportOptions.Format.MIDI)
        assertEquals(setOf("Both.wav", "Both.mid"), fileNames(wav.parentFile!!))
        export(song, ExportOptions.Format.WAV)
        assertTrue(mid.exists())
    }

    // MARK: Canceling

    /** Closing the sheet or switching songs cancels: no file is shared. */
    @Test fun aCancelBeforeTheWriteWritesNothingAndKeepsThePreviousExport() {
        val song = TestSongs.empty(name = "Kept").setNote(0, 0, 60)
        val first = render(song)
        val firstBytes = first.readBytes()

        val result = MidiExport.render(ExportRequest(song.setNote(0, 4, 64), isCanceled = { true }), temp.root)
        assertEquals(ExportResult.Canceled, result)
        assertArrayEquals(firstBytes, first.readBytes())

        val other = TestSongs.empty(name = "Never").setNote(0, 0, 60)
        assertEquals(ExportResult.Canceled, MidiExport.render(ExportRequest(other, isCanceled = { true }), temp.root))
        assertFalse(MidiExport.filename(other, temp.root).exists())
    }

    /** A cancel that lands while the file is written still cancels, and the
     * new file goes: nothing was there before it. */
    @Test fun aCancelDuringTheWriteRemovesTheNewFile() {
        val song = TestSongs.empty(name = "Late").setNote(0, 0, 60)
        val target = MidiExport.filename(song, temp.root)
        // True once the file is on disk, which is to say after the write.
        val result = MidiExport.render(ExportRequest(song, isCanceled = { target.exists() }), temp.root)
        assertEquals(ExportResult.Canceled, result)
        assertFalse(target.exists())
    }

    /** The write already replaced the previous export of that name, so the
     * new, whole file is kept rather than leaving the song with none. */
    @Test fun aLateCancelKeepsAFileThatReplacedThePreviousExport() {
        var song = TestSongs.empty(name = "Again").setNote(0, 0, 60)
        val file = render(song)

        song = song.setNote(0, 4, 64)
        val newBytes = MidiExport.data(song)
        val result = MidiExport.render(ExportRequest(song, isCanceled = { file.readBytes().contentEquals(newBytes) }), temp.root)
        assertEquals(ExportResult.Canceled, result)
        assertArrayEquals(newBytes, file.readBytes())
    }

    /** The dispatcher prunes only after a success, so a canceled export
     * costs no older file. */
    @Test fun aCanceledExportPrunesNothing() {
        val song = TestSongs.empty(name = "Old", tempo = 240.0).setNote(0, 0, 60)
        val old = export(song, ExportOptions.Format.MIDI)
        val result = ExportRenderer.render(
            ExportRequest(song.copy(name = "New"), ExportOptions(format = ExportOptions.Format.MIDI), isCanceled = { true }),
            temp.root,
        )
        assertEquals(ExportResult.Canceled, result)
        assertEquals(setOf("Old.mid"), fileNames(old.parentFile!!))
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
