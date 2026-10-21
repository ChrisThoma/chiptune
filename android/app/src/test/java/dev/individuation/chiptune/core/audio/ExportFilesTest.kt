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

    /** A day and a minute after the files above were written: old enough to sweep. */
    private val later = System.currentTimeMillis() + ExportFiles.SWEEP_MIN_AGE_MILLIS + 60_000

    /** A file another app may still be reading through a share's URI stays
     * through a relaunch; one over a day old goes. */
    @Test fun theSweepKeepsExportsUnderADayOld() {
        val root = temp.newFolder("export")
        val now = 1_000_000_000_000L
        val day = 24 * 60 * 60 * 1000L
        val fresh = songFolder(root)
        val shared = fresh.touch("Shared.wav")
        shared.setLastModified(now - day + 60_000)
        val mixed = songFolder(root)
        val recent = mixed.touch("Recent.mp4")
        recent.setLastModified(now - 60_000)
        val old = mixed.touch("Old.wav")
        old.setLastModified(now - day - 60_000)
        val stale = songFolder(root)
        stale.touch("Stale.mid").setLastModified(now - 2 * day)

        ExportFiles.sweep(root, now, day)

        assertTrue("a file under a day old may still be open in another app", shared.exists())
        assertTrue(recent.exists())
        assertFalse("over a day old goes", old.exists())
        assertFalse("an emptied folder goes", stale.exists())
        assertTrue("a folder still holding a recent export stays", mixed.isDirectory)
    }

    /** Scratch is never shared, so it goes whatever its age. */
    @Test fun theSweepClearsFreshScratch() {
        val root = temp.newFolder("export")
        val wav = File(root, WavExport.SCRATCH_DIRECTORY).also { it.mkdirs() }
        val now = 1_000_000_000_000L
        wav.touch("ABC.raw").setLastModified(now)
        wav.setLastModified(now)

        ExportFiles.sweep(root, now, ExportFiles.SWEEP_MIN_AGE_MILLIS)

        assertFalse(wav.exists())
    }

    @Test fun theSweepClearsEverySongsExportsAndTheirEmptyFolders() {
        val root = temp.newFolder("export")
        val a = songFolder(root)
        a.touch("Song.wav")
        a.touch("Song.mid")
        val b = songFolder(root)
        b.touch("Other.mp4")

        ExportFiles.sweep(root, later)

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

        ExportFiles.sweep(root, later)

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

        ExportFiles.sweep(root, later)

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

        ExportFiles.sweep(root, later)

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
