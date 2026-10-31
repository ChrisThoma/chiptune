package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The three bundled sample songs: seeded on a first launch beside First
 * Loop, and once into an existing library, never twice and never over a
 * song already there. */
class StudioSampleSongsTest {

    private val names = listOf("sample-sky-arcade.chipsong", "sample-rainy-waltz.chipsong", "sample-tower-climb.chipsong")

    private fun bytes(name: String): ByteArray =
        javaClass.classLoader!!.getResourceAsStream(name)!!.use { it.readBytes() }

    private val files: List<ByteArray> by lazy { names.map(::bytes) }
    private val sampleSongs: List<Song> by lazy { files.map(SongDocument::decode) }

    private val harnesses = ArrayList<StudioHarness>()

    /** A launch on [temp] (fresh if null) that sees [samples] bundled. */
    private fun launch(temp: TempStore? = null, samples: List<ByteArray>? = files): StudioHarness =
        StudioHarness(temp = temp ?: TempStore(), samples = samples).also { harnesses.add(it) }

    @After
    fun tearDown() {
        // Each relaunch shares its TempStore; close every Studio, then clean once.
        harnesses.forEach { it.studio.invalidateTimers(); it.executor.shutdownNow() }
        harnesses.map { it.temp }.distinct().forEach { it.clean() }
    }

    @Test fun theBundledSampleFilesDecodeThroughTheImportPath() {
        assertEquals(listOf("Sky Arcade", "Rainy Waltz", "Tower Climb"), sampleSongs.map { it.name })
        assertEquals("fixed ids, so a reseed can tell them apart", 3, sampleSongs.map { it.id }.toSet().size)
    }

    @Test fun aFirstLaunchSeedsFirstLoopAndTheSamplesWithFirstLoopOpenAndFirst() {
        val h = launch()
        assertEquals("First Loop", h.studio.song.name)
        val library = h.temp.store.loadAll()
        assertEquals(4, library.size)
        assertEquals("First Loop", library[0].name)
        assertEquals(sampleSongs.map { it.id }.toSet(), library.drop(1).map { it.id }.toSet())
        assertEquals(h.studio.song.id, h.temp.store.loadLast()!!.id)
        assertEquals("the samples are what the files hold",
            sampleSongs.first { it.name == "Sky Arcade" }.patterns,
            h.temp.store.load(sampleSongs[0].id)!!.patterns)
    }

    @Test fun anExistingLibraryGetsTheSamplesOnceAndKeepsItsOpenSong() {
        val temp = TempStore()
        val mine = Song.create("Mine")
        temp.save(mine, makeCurrent = true)

        val first = launch(temp)
        assertEquals("Mine", first.studio.song.name)
        assertEquals(4, temp.store.loadAll().size)
        assertTrue(temp.store.loadAll().none { it.name == "First Loop" })

        val second = launch(temp)
        assertEquals("Mine", second.studio.song.name)
        assertEquals(4, temp.store.loadAll().size)
    }

    @Test fun anExistingLibraryWithNoCurrentSongStillReopensTheSameSong() {
        val temp = TempStore()
        temp.save(Song.create("Older"))
        temp.save(Song.create("Newest"))

        assertEquals("Newest", launch(temp).studio.song.name)
        assertEquals("the samples don't take over the launch", "Newest", launch(temp).studio.song.name)
    }

    @Test fun aDeletedSampleIsNotSeededAgain() {
        val temp = TempStore()
        val h = launch(temp)
        val doomed = temp.store.load(sampleSongs[1].id)!!
        h.studio.delete(doomed)

        launch(temp)
        assertNull(temp.store.load(doomed.id))
        assertEquals(3, temp.store.loadAll().size)
    }

    @Test fun aNewSampleInALaterVersionIsSeededOnceIntoAnOldLibrary() {
        val temp = TempStore()
        launch(temp, samples = files.take(2))
        assertEquals(3, temp.store.loadAll().size)
        temp.store.delete(temp.store.load(sampleSongs[0].id)!!)

        launch(temp, samples = files)
        assertNull("the deleted one stays gone", temp.store.load(sampleSongs[0].id))
        assertEquals("Tower Climb", temp.store.load(sampleSongs[2].id)!!.name)
    }

    @Test fun aSongAlreadyHoldingASampleIdIsNotOverwritten() {
        val temp = TempStore()
        val edited = sampleSongs[0].copy(name = "My Arcade", tempo = 90.0)
        temp.save(edited, makeCurrent = true)

        launch(temp)
        val kept = temp.store.load(edited.id)!!
        assertEquals("My Arcade", kept.name)
        assertEquals(90.0, kept.tempo, 0.0)
        assertEquals(3, temp.store.loadAll().size)
    }

    @Test fun aBrokenSampleIsSkippedAndTheOthersStillSeed() {
        val broken = "{\"id\": \"not a song".toByteArray()
        val h = launch(samples = listOf(broken) + files.drop(1))
        assertEquals("First Loop", h.studio.song.name)
        assertEquals(listOf("First Loop", "Rainy Waltz", "Tower Climb").sorted(),
            h.temp.store.loadAll().map { it.name }.sorted())
        assertNull(h.studio.storageError)
        assertNull(h.studio.unreadableSongsNotice)
    }

    @Test fun aSourceThatThrowsSeedsNothingAndStillLaunches() {
        val temp = TempStore()
        val h = StudioHarness(temp = temp, samples = null).also { harnesses.add(it) }
        assertEquals(1, temp.store.loadAll().size)
        val failing = SampleSongs(temp.prefs) { throw java.io.IOException("no assets") }
        val s = Studio(temp.store, h.audio, h.scheduler, autosaveEnabled = false, renderer = { throw AssertionError() },
            exportExecutor = h.executor, shareWriter = SongShareWriter(h.shareDir), samples = failing)
        s.invalidateTimers()
        assertEquals("First Loop", s.song.name)
        assertEquals(1, temp.store.loadAll().size)
        assertFalse(temp.prefs.getStringList(SampleSongs.SEEDED_KEY).orEmpty().isNotEmpty())
    }

    @Test fun theSeededRecordHoldsTheSampleIds() {
        val h = launch()
        assertEquals(sampleSongs.map { it.id.toString().uppercase() }.toSet(),
            h.temp.prefs.getStringList(SampleSongs.SEEDED_KEY)!!.toSet())
        assertTrue(sampleSongs.none { it.id == UUID(0, 0) })
    }
}
