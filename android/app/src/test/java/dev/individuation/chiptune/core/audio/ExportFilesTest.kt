package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.video.VideoExport
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The launch sweep and the song-delete cleanup of `cache/export/`. */
class ExportFilesTest {

    @get:Rule val temp = TemporaryFolder()

    private fun songFolder(root: File, id: UUID = UUID.randomUUID()): File =
        File(root, id.toString().uppercase()).also { it.mkdirs() }

    private fun File.touch(name: String): File = File(this, name).also { it.writeText("x") }

    @Test fun theSweepClearsEverySongsExportsAndTheirEmptyFolders() {
        val root = temp.newFolder("export")
        val a = songFolder(root)
        a.touch("Song.wav")
        a.touch("Song.mid")
        val b = songFolder(root)
        b.touch("Other.mp4")

        ExportFiles.sweep(root)

        assertFalse("a's exports and folder are gone", a.exists())
        assertFalse(b.exists())
        assertTrue("the export root itself stays", root.isDirectory)
    }

    @Test fun theSweepClearsBothScratchFolders() {
        val root = temp.newFolder("export")
        val wav = File(root, WavExport.SCRATCH_DIRECTORY).also { it.mkdirs() }
        wav.touch("ABC.raw")
        val video = File(root, VideoExport.SCRATCH_DIRECTORY).also { it.mkdirs() }
        video.touch("ABC.mp4")

        ExportFiles.sweep(root)

        assertFalse(wav.exists())
        assertFalse(video.exists())
    }

    @Test fun theSweepLeavesFilesAndFoldersTheExportersDoNotWrite() {
        val root = temp.newFolder("export")
        val song = songFolder(root)
        song.touch("Song.wav")
        val note = song.touch("notes.txt")
        val stranger = File(root, "something-else").also { it.mkdirs() }
        val strangerWav = stranger.touch("keep.wav")
        val loose = root.touch("loose.wav")

        ExportFiles.sweep(root)

        assertFalse(File(song, "Song.wav").exists())
        assertTrue("a folder still holding something stays", note.exists())
        assertTrue("a folder not named for a song is not ours", strangerWav.exists())
        assertTrue("only per-song folders are swept", loose.exists())
    }

    @Test fun theSweepNeverReachesTheShareFolder() {
        val cache = temp.newFolder("cache")
        val root = File(cache, "export").also { it.mkdirs() }
        songFolder(root).touch("Song.wav")
        val share = File(cache, "share").also { it.mkdirs() }
        val shared = share.touch("Song.chipsong")

        ExportFiles.sweep(root)

        assertTrue(shared.exists())
    }

    @Test fun theSweepOfAMissingFolderDoesNothing() {
        ExportFiles.sweep(File(temp.root, "never-made"))
        assertFalse(File(temp.root, "never-made").exists())
    }

    @Test fun deletingASongRemovesOnlyItsFolder() {
        val root = temp.newFolder("export")
        val gone = UUID.randomUUID()
        songFolder(root, gone).touch("Song.mp4")
        val kept = songFolder(root)
        kept.touch("Kept.wav")

        ExportFiles.removeSong(root, gone)

        assertFalse(File(root, gone.toString().uppercase()).exists())
        assertEquals(listOf("Kept.wav"), kept.list()!!.toList())
    }
}
