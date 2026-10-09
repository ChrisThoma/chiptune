package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import java.io.File
import java.nio.file.Files
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `StudioImportTests.swift`: read the file, resolve collisions,
 * save, open -- plus sharing and drops. */
class StudioImportTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val temp get() = h.temp
    private lateinit var scratch: File

    @Before
    fun setUp() {
        h = StudioHarness()
        scratch = Files.createTempDirectory("chiptune-import-").toFile()
    }

    @After
    fun tearDown() {
        h.close()
        scratch.deleteRecursively()
    }

    /** What a friend's phone would hand over: the bytes of a shared file. */
    private fun shared(song: Song): File = SongShareWriter(scratch).write(song)

    private fun importFile(file: File): Boolean = studio.importSong { file.readBytes() }

    @Test fun importingASongAddsItToTheLibraryAndOpensIt() {
        val incoming = Song.create("From a friend").copy(tempo = 96.0).withPattern(0) { it.withNote(0, 3, 65) }
        assertTrue(importFile(shared(incoming)))
        assertEquals("From a friend", studio.song.name)
        assertEquals(96.0, studio.song.tempo, 0.0)
        assertEquals(65, studio.song.patterns[0].rows[0][3])
        assertNotNull(temp.store.load(studio.song.id))
        assertNull(studio.importError)
        assertEquals(studio.song.tracks.size, studio.core.trackCount)
    }

    @Test fun importingASongAlreadyInTheLibraryDoesNotOverwriteIt() {
        val original = Song.create("Mine").copy(tempo = 120.0).withPattern(0) { it.withNote(0, 0, 60) }
        temp.save(original)
        val incoming = original.copy(tempo = 200.0).withPattern(0) { it.withNote(0, 0, 72) }

        assertTrue(importFile(shared(incoming)))

        val mine = temp.store.load(original.id)!!
        assertEquals(120.0, mine.tempo, 0.0)
        assertEquals(60, mine.patterns[0].rows[0][0])
        assertNotEquals(original.id, studio.song.id)
        assertEquals("Mine (imported)", studio.song.name)
        assertEquals(200.0, studio.song.tempo, 0.0)
    }

    @Test fun warmImportDismissesAPresentedSongLibrary() {
        val previous = studio.song.id
        assertTrue(importFile(shared(studio.song)))
        assertFalse(SongLibraryPresentation.afterOpeningSong(true, previous, studio.song.id))
    }

    @Test fun warmImportClosesEveryPresentedSurface() {
        val previous = studio.song.id
        assertTrue(importFile(shared(studio.song)))
        val all = PresentedSurfaces(songs = true, arrangement = true, export = true, instrumentEditor = true)
        assertEquals(PresentedSurfaces(), all.afterOpeningSong(previous, studio.song.id))
    }

    @Test fun malformedImportLeavesPresentedSurfacesAlone() {
        val before = studio.song.id
        assertFalse(studio.importSong { "nope".toByteArray() })
        assertNotNull(studio.importError)
        assertEquals(before, studio.song.id)
        val all = PresentedSurfaces(songs = true, arrangement = true, export = true, instrumentEditor = true)
        assertEquals(all, all.afterOpeningSong(before, studio.song.id))
    }

    @Test fun importingRubbishReportsAnErrorAndLeavesTheOpenSongAlone() {
        studio.open(Song.create("Working on this"))
        assertFalse(studio.importSong { "absolutely not a song".toByteArray() })
        assertEquals("Couldn't import the file. It isn't a Chiptune song, or it's damaged.", studio.importError)
        assertEquals("Working on this", studio.song.name)
    }

    @Test fun importingRawBytesGoesThroughTheSameDecode() {
        assertFalse(studio.importSong("absolutely not a song".toByteArray()))
        assertEquals("Couldn't import the file. It isn't a Chiptune song, or it's damaged.", studio.importError)
        assertTrue(studio.importSong(SongDocument.encodeToBytes(Song.create("Bytes"))))
        assertEquals("Bytes", studio.song.name)
        assertNull(studio.importError)
    }

    @Test fun importingAMissingFileReportsAnError() {
        val missing = File(scratch, "gone-${UUID.randomUUID()}.chipsong")
        assertFalse(importFile(missing))
        assertEquals("Couldn't import the file. It couldn't be read. Try again.", studio.importError)
    }

    @Test fun importingAFileTheAppMayNotReadSaysSo() {
        assertFalse(studio.importSong { throw SecurityException("Permission Denial: opening provider") })
        assertEquals("Couldn't import the file. The app doesn't have permission to read it.", studio.importError)
    }

    @Test fun aSuccessfulImportClearsAPreviousError() {
        studio.importError = "an earlier failure"
        assertTrue(importFile(shared(Song.create("Fine"))))
        assertNull(studio.importError)
    }

    // MARK: Sharing

    @Test fun sharingPublishesAReadableFile() {
        studio.open(Song.create("To share").copy(tempo = 150.0))
        studio.share(studio.song)
        val file = studio.shareFile!!
        assertEquals("chipsong", file.extension)
        assertEquals("To share.chipsong", file.name)
        assertEquals(150.0, SongDocument.decode(file.readBytes()).tempo, 0.0)
        assertEquals("share-${studio.song.id.toString().uppercase()}", file.parentFile.name)
    }

    @Test fun aSharedSongCanBeImportedBack() {
        studio.open(Song.create("Round trip").copy(tempo = 108.0).withPattern(0) { it.withNote(1, 7, 71) })
        studio.share(studio.song)
        val file = studio.shareFile!!

        val other = StudioHarness()
        try {
            assertTrue(other.studio.importSong { file.readBytes() })
            assertEquals("Round trip", other.studio.song.name)
            assertEquals(108.0, other.studio.song.tempo, 0.0)
            assertEquals(71, other.studio.song.patterns[0].rows[1][7])
        } finally {
            other.close()
        }
    }

    @Test fun shareFailuresDoNotSurfaceAsImportFailures() {
        val blocked = File(h.shareDir, "share-${studio.song.id.toString().uppercase()}")
        blocked.writeText("not a directory")

        studio.share(studio.song)

        assertNull(studio.shareFile)
        assertNotNull(studio.shareError)
        assertTrue(studio.shareError!!.contains(studio.song.name))
        assertNull(studio.importError)
    }

    @Test fun aSuccessfulShareClearsAPreviousError() {
        studio.shareError = "an earlier failure"
        studio.share(studio.song)
        assertNotNull(studio.shareFile)
        assertNull(studio.shareError)
    }

    @Test fun aLongSongNameStillSharesUnderAFileNameThatFits() {
        studio.share(Song.create("L".repeat(300)))
        val name = studio.shareFile!!.name
        assertTrue(name.toByteArray().size <= 255)
        assertTrue(name.endsWith(".chipsong"))
    }

    // MARK: Decoded and dropped songs

    @Test fun importingADecodedSongSavesItAndOpensIt() {
        val incoming = Song.create("Dropped in").copy(tempo = 96.0).withPattern(0) { it.withNote(0, 3, 65) }
        assertTrue(studio.importDecoded(incoming))
        assertEquals(incoming.id, studio.song.id)
        assertEquals("Dropped in", studio.song.name)
        assertEquals(96.0, studio.song.tempo, 0.0)
        assertEquals(65, studio.song.patterns[0].rows[0][3])
        assertNotNull(temp.store.load(studio.song.id))
        assertNull(studio.importError)
        assertEquals(studio.song.tracks.size, studio.core.trackCount)
    }

    @Test fun importingADecodedSongAlreadyInTheLibraryDoesNotOverwriteIt() {
        val original = Song.create("Mine").copy(tempo = 120.0).withPattern(0) { it.withNote(0, 0, 60) }
        temp.save(original)
        val incoming = original.copy(tempo = 200.0).withPattern(0) { it.withNote(0, 0, 72) }
        assertTrue(studio.importDecoded(incoming))
        val mine = temp.store.load(original.id)!!
        assertEquals(120.0, mine.tempo, 0.0)
        assertEquals(60, mine.patterns[0].rows[0][0])
        assertNotEquals(original.id, studio.song.id)
        assertEquals("Mine (imported)", studio.song.name)
        assertEquals(200.0, studio.song.tempo, 0.0)
    }

    @Test fun aSuccessfulDecodedImportClearsAPreviousError() {
        studio.importError = "an earlier failure"
        assertTrue(studio.importDecoded(Song.create("Fine")))
        assertNull(studio.importError)
    }

    @Test fun anImportThatCannotBeSavedIsReportedAgainstTheImportedSong() {
        studio.open(Song.create("On screen"))
        val onScreen = studio.song.id
        temp.directory.setWritable(false)
        try {
            assertFalse(studio.importDecoded(Song.create("Imported Test")))
            assertEquals(
                "Couldn't import \u201CImported Test\u201D. The app doesn't have permission to write the song file.",
                studio.importError,
            )
            assertNull(studio.storageError)
            assertEquals(onScreen, studio.song.id)
        } finally {
            temp.directory.setWritable(true)
        }
        assertFalse(temp.store.loadAll().any { it.name == "Imported Test" })
    }

    @Test fun aDecodedImportIsNormalizedBeforeItIsSaved() {
        assertTrue(studio.importDecoded(Song.create("Hostile").copy(tempo = Double.NaN)))
        assertFalse(studio.song.tempo.isNaN())
        assertNotNull(temp.store.load(studio.song.id))
    }

    @Test fun aDroppedSongIsImportedAndOpened() {
        val incoming = Song.create("Dropped in").copy(tempo = 101.0)
        assertTrue(studio.importDropped(SongDrop(SongDocument.encodeToBytes(incoming))))
        assertEquals("Dropped in", studio.song.name)
        assertNotNull(temp.store.load(studio.song.id))
        assertNull(studio.importError)
    }

    @Test fun aDroppedFileThatIsNotASongIsReported() {
        val before = studio.song.id
        val count = temp.store.loadAll().size
        assertFalse(studio.importDropped(SongDrop("not a song".toByteArray())))
        assertEquals("Couldn't import the file. It isn't a Chiptune song, or it's damaged.", studio.importError)
        assertEquals(before, studio.song.id)
        assertEquals(count, temp.store.loadAll().size)
    }
}
