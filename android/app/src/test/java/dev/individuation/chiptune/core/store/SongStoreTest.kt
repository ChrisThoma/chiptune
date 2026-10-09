package dev.individuation.chiptune.core.store

import dev.individuation.chiptune.core.assertSameSong
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.audio.withTrack
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongClock
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.studio.TempStore
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `SongStoreTests.swift` and the store half of `UnreadableSongTests`. */
class SongStoreTest {

    private lateinit var temp: TempStore
    private val store get() = temp.store

    @Before
    fun setUp() {
        temp = TempStore()
    }

    @After
    fun tearDown() = temp.clean()

    private fun plant(text: String, name: String = "${UUID.randomUUID().toString().uppercase()}.json"): File =
        File(temp.directory, name).apply { writeText(text) }

    @Test fun saveAndLoadRoundTripsTheWholeSong() {
        var song = Song.create("Round trip").copy(tempo = 174.0)
            .withInstrument(1) { it.copy(volume = 0.42) }
            .withTrack(2) { it.copy(muted = true) }
            .withPattern(0) { it.withNote(0, 5, 64).copy(length = 32) }
        song = song.copy(patterns = song.patterns + Pattern(name = "B", length = 8, trackCount = song.tracks.size))
        song = song.copy(arrangement = song.arrangement + SongSection(patternID = song.patterns[1].id, repeats = 3))
            .normalized()
        temp.save(song)
        assertSameSong(store.load(song.id)!!, song)
    }

    @Test fun filesAreNamedByTheUppercaseIdAndWrittenWhole() {
        val song = Song.create("Named")
        temp.save(song)
        val names = temp.directory.list()!!.toList()
        assertEquals(listOf("${song.id.toString().uppercase()}.json"), names)
    }

    @Test fun saveStampsTheModifiedDate() {
        val song = Song.create("Stamped").copy(modified = -SongClock.UNIX_SECONDS_AT_REFERENCE.toDouble())
        val before = SongClock.now()
        temp.save(song)
        assertTrue(store.load(song.id)!!.modified >= before - 1)
    }

    @Test fun loadingAnUnknownIdReturnsNull() {
        assertNull(store.load(UUID.randomUUID()))
    }

    @Test fun loadLastReturnsTheSongMarkedCurrent() {
        val first = Song.create("First")
        temp.save(first, makeCurrent = true)
        temp.save(Song.create("Second"))
        assertEquals(first.id, store.loadLast()!!.id)
    }

    @Test fun loadLastFallsBackToTheNewestSongWhenTheCurrentOneIsMissing() {
        val missing = Song.create("Missing")
        temp.save(missing, makeCurrent = true)
        store.delete(missing)
        val older = Song.create("Older").copy(modified = 1000.0)
        val newer = Song.create("Newer").copy(modified = 2000.0)
        temp.save(older)
        temp.save(newer)
        assertEquals(newer.id, store.loadLast()!!.id)
    }

    @Test fun loadLastReturnsNullOnAnEmptyLibrary() {
        assertNull(store.loadLast())
    }

    @Test fun deletingTheCurrentSongClearsTheCurrentKey() {
        val song = Song.create("Doomed")
        temp.save(song, makeCurrent = true)
        store.delete(song)
        assertNull(store.load(song.id))
        assertNull(temp.prefs.getString(FileSongStore.CURRENT_KEY))
    }

    @Test fun deletingAnotherSongLeavesTheCurrentKeyAlone() {
        val current = Song.create("Current")
        val other = Song.create("Other")
        temp.save(current, makeCurrent = true)
        temp.save(other)
        store.delete(other)
        assertEquals(current.id.toString().uppercase(), temp.prefs.getString("currentSongID"))
    }

    @Test fun deletingAMissingFileIsNotAnError() {
        val song = Song.create("Ghost")
        temp.save(song)
        store.delete(song)
        store.delete(song)
    }

    @Test fun loadAllReturnsNewestFirst() {
        val names = listOf("One", "Two", "Three")
        for (name in names) temp.save(Song.create(name))
        assertEquals(names.reversed(), store.loadAll().map { it.name })
    }

    @Test fun corruptFilesAreSkippedRatherThanFailingTheWholeLoad() {
        temp.save(Song.create("Readable"))
        plant("{ not json at all")
        plant("{}")
        val loaded = store.loadAll()
        assertEquals(1, loaded.size)
        assertEquals("Readable", loaded.first().name)
    }

    @Test fun aFileWithAnUnknownTrackKindIsStillListed() {
        plant("""
        { "id": "${UUID.randomUUID()}", "name": "From the future", "tempo": 120,
          "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35 } },
            { "kind": 9, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35 } } ],
          "patterns": [ { "id": "${UUID.randomUUID()}", "name": "A", "length": 16,
                          "rows": [[60], [67]] } ],
          "arrangement": [] }
        """)
        plant("{}")
        assertEquals(listOf("From the future"), store.loadAll().map { it.name })
    }

    @Test fun nonJsonFilesAreIgnored() {
        temp.save(Song.create("Readable"))
        plant("nope", "stray.wav")
        assertEquals(1, store.loadAll().size)
        assertEquals("a stray file isn't an unreadable song", 0, store.loadLibrary().unreadable.size)
    }

    @Test fun loadAllOnAnEmptyDirectoryIsEmptyRatherThanAFailure() {
        assertEquals(0, store.loadAll().size)
        val never = FileSongStore(File(temp.directory, "not-yet"), InMemoryKeyValueStore())
        assertEquals(0, never.loadAll().size)
    }

    @Test fun legacyFormatMigratesItsNotesIntoPatternA() {
        val id = UUID.randomUUID()
        plant("""
        {
          "id": "$id",
          "name": "Legacy",
          "tempo": 128,
          "length": 8,
          "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
              "notes": [60, -1, 64, -1, 67, -1, -1, -1] },
            { "kind": 2, "instrument": { "duty": 2, "volume": 0.9, "decay": 4.0, "arpeggio": [] },
              "notes": [48, -1, -1, -1, 48, -1, -1, -1] }
          ]
        }
        """, "${id.toString().uppercase()}.json")
        val song = store.load(id)!!
        assertEquals("Legacy", song.name)
        assertEquals(128.0, song.tempo, 0.0)
        assertEquals(2, song.tracks.size)
        assertEquals(1, song.patterns.size)
        assertEquals(8, song.patterns[0].length)
        assertEquals(listOf(60, -1, 64, -1, 67, -1, -1, -1), song.patterns[0].rows[0].take(8))
        assertEquals(listOf(48, -1, -1, -1, 48, -1, -1, -1), song.patterns[0].rows[1].take(8))
        assertEquals(1, song.arrangement.size)
        assertEquals(song.patterns[0].id, song.arrangement[0].patternID)
        temp.save(song)
        assertSameSong(store.load(id)!!, song)
    }

    @Test fun legacyFileWithoutAnIdStillLoads() {
        plant("""
        { "name": "No id", "tracks": [
            { "kind": 0, "instrument": { "duty": 2, "volume": 0.8, "decay": 0.35, "arpeggio": [] },
              "notes": [60] } ] }
        """)
        val songs = store.loadAll()
        assertEquals(1, songs.size)
        assertEquals("No id", songs[0].name)
        assertEquals(60, songs[0].patterns[0].rows[0][0])
    }

    @Test fun storesOnDifferentDirectoriesAreIndependent() {
        val other = TempStore()
        try {
            temp.save(Song.create("Mine"))
            assertEquals(1, store.loadAll().size)
            assertEquals(0, other.store.loadAll().size)
        } finally {
            other.clean()
        }
    }

    @Test fun anInterruptedWriteLeavesTheOldFileWhole() {
        val song = Song.create("Whole")
        temp.save(song)
        // A temp file a crash left behind is not a song and not unreadable.
        File(temp.directory, ".write-123.tmp").writeText("{half")
        assertEquals(listOf("Whole"), store.loadAll().map { it.name })
        assertEquals(0, store.loadLibrary().unreadable.size)
    }

    // MARK: Unreadable files

    @Test fun storeReportsUnreadableFilesAlongsideSongs() {
        temp.save(Song.create("Fine"))
        val bad = plant("{broken")
        val library = store.loadLibrary()
        assertEquals(listOf("Fine"), library.songs.map { it.name })
        assertEquals(listOf(bad.name), library.unreadable)
        assertEquals(listOf("Fine"), store.loadAll().map { it.name })
    }

    @Test fun claimUnreportedCountsEachFileVersionOnce() {
        plant("{broken")
        assertEquals(1, store.claimUnreported(store.loadLibrary()))
        assertEquals(0, store.claimUnreported(store.loadLibrary()))
        val second = plant("{also broken")
        assertEquals(1, store.claimUnreported(store.loadLibrary()))
        second.setLastModified(second.lastModified() + 120_000)
        assertEquals(1, store.claimUnreported(store.loadLibrary()))
        assertEquals(0, store.claimUnreported(store.loadLibrary()))
    }

    @Test fun onlyFilesStillUnreadableAreRemembered() {
        val bad = plant("{broken")
        store.claimUnreported(store.loadLibrary())
        bad.delete()
        store.claimUnreported(store.loadLibrary())
        assertEquals(emptyList<String>(), temp.prefs.getStringList(FileSongStore.REPORTED_UNREADABLE_KEY) ?: emptyList<String>())
    }

    @Test fun noticeWording() {
        assertEquals("Load failed", UnreadableSongs.TITLE)
        assertEquals("1 saved song couldn't be read, so it's left out of your library. It may be damaged.",
            UnreadableSongs.message(1))
        assertEquals("3 saved songs couldn't be read, so they're left out of your library. They may be damaged.",
            UnreadableSongs.message(3))
    }

    // MARK: The in-memory double

    @Test fun theInMemoryStoreBehavesLikeTheFileStore() {
        val prefs = InMemoryKeyValueStore()
        var t = 0.0
        val mem = InMemorySongStore(prefs) { t += 1.0; t }
        val a = Song.create("A")
        val b = Song.create("B")
        mem.save(a, makeCurrent = true)
        mem.save(b)
        assertEquals(listOf("B", "A"), mem.loadAll().map { it.name })
        assertEquals(a.id, mem.loadLast()!!.id)
        mem.delete(a)
        mem.delete(a)
        assertNull(prefs.getString(FileSongStore.CURRENT_KEY))
        assertEquals(b.id, mem.loadLast()!!.id)
        mem.saveError = java.io.IOException("full")
        try {
            mem.save(a)
            org.junit.Assert.fail("expected a throw")
        } catch (expected: java.io.IOException) {
        }
        assertNotNull(mem.load(b.id))
    }
}
