package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.store.FileSongStore
import dev.individuation.chiptune.core.store.InMemoryKeyValueStore
import dev.individuation.chiptune.core.store.UnreadableSongs
import java.io.File
import java.io.IOException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** Saving, deleting and renaming from the Studio: `ErrorSurfacingTests`
 * (save/delete half), `SongRenameTests` and `StudioAutosaveTests`. */
class StudioLibraryTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val temp get() = h.temp

    @Before
    fun setUp() {
        h = StudioHarness()
    }

    @After
    fun tearDown() = h.close()

    // MARK: Launch

    @Test fun anEmptyLibraryLaunchesOnTheDemoRiffAndSavesIt() {
        assertEquals("First Loop", studio.song.name)
        assertEquals(132.0, studio.song.tempo, 0.0)
        assertEquals(listOf(72, -1, 76, -1, 79, -1, 76, -1, 74, -1, 77, -1, 81, -1, 79, -1),
            studio.song.patterns[0].rows[0].take(16))
        assertEquals(listOf(60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, -1, 60, -1, 60, -1),
            studio.song.patterns[0].rows[3].take(16))
        val saved = temp.store.loadLast()!!
        assertEquals(studio.song.id, saved.id)
        assertEquals("the riff is the golden render's", TestSongs.golden().patterns[0].rows, saved.patterns[0].rows)
        assertEquals("the core holds it", studio.song.tracks.size, studio.core.trackCount)
    }

    @Test fun aRelaunchReopensTheLastSong() {
        studio.open(Song.create("Keep working"))
        assertEquals("Keep working", launch().song.name)
    }

    // MARK: Delete

    @Test fun aFailedDeleteIsReported() {
        val doomed = Song.create("Doomed")
        temp.save(doomed)
        temp.directory.setWritable(false)
        try {
            studio.delete(doomed)
        } finally {
            temp.directory.setWritable(true)
        }
        assertEquals(
            "Couldn't delete \u201CDoomed\u201D. The app doesn't have permission to delete the song file.",
            studio.deleteError,
        )
        assertNull(studio.storageError)
        assertNotNull("the file is still there", temp.store.load(doomed.id))
    }

    @Test fun deleteRemovesTheSongFromTheLibrary() {
        val song = Song.create("Doomed")
        temp.save(song)
        assertEquals(2, temp.store.loadAll().size)
        studio.delete(song)
        assertNull(temp.store.load(song.id))
        assertFalse(temp.store.loadAll().any { it.id == song.id })
    }

    /** Deleting the song on screen moves the editor to the next one, or a new
     * one, and the deleted song must not be written back. */
    @Test fun deletingTheOpenSongFallsBackToAnotherSong() {
        val other = Song.create("Survivor")
        temp.save(other)
        studio.toggleCell(0, 0)
        val doomed = studio.song
        studio.setSongMode(true)

        studio.delete(doomed)

        assertEquals("Survivor", studio.song.name)
        assertFalse(studio.songMode)
        assertEquals(0, studio.selectedPattern)
        assertFalse("undo does not reach across songs", studio.canUndo)
        assertNull(temp.store.load(doomed.id))
        studio.saveNow()
        assertNull("the deleted song must not come back", temp.store.load(doomed.id))
        assertEquals(other.id, temp.store.loadLast()!!.id)
    }

    @Test fun deletingTheOnlySongStartsANewOne() {
        val only = studio.song
        studio.delete(only)
        assertNotEquals(only.id, studio.song.id)
        assertEquals("Untitled", studio.song.name)
        assertEquals(listOf(studio.song.id), temp.store.loadAll().map { it.id })
    }

    @Test fun deletingTheOpenSongCancelsAPendingAutosave() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            auto.studio.edit { it.copy(name = "Pending") }
            val doomed = auto.studio.song
            auto.studio.delete(doomed)
            auto.scheduler.advance(10.0)
            assertNull(auto.temp.store.load(doomed.id))
        } finally {
            auto.close()
        }
    }

    // MARK: Save

    @Test fun aFailedSaveIsReported() {
        val blocked = File.createTempFile("blocked-", "")
        try {
            val harness = StudioHarness(temp = TempStore())
            try {
                val studio = Studio(FileSongStore(blocked, InMemoryKeyValueStore()), harness.audio, harness.scheduler,
                    autosaveEnabled = false, renderer = { throw AssertionError() },
                    exportExecutor = harness.executor, shareWriter = SongShareWriter(harness.shareDir))
                studio.edit { it.copy(name = "Unsaveable") }
                assertFalse(studio.saveNow())
                assertTrue(studio.storageError!!.contains("Unsaveable"))
            } finally {
                harness.close()
            }
        } finally {
            blocked.delete()
        }
    }

    @Test fun aReadOnlyStoreSaysWhyWithoutTheRawErrorOrFileName() {
        studio.edit { it.copy(name = "Locked In") }
        temp.directory.setWritable(false)
        try {
            assertFalse(studio.saveNow())
        } finally {
            temp.directory.setWritable(true)
        }
        val message = studio.storageError!!
        assertTrue(message, message.contains("\u201CLocked In\u201D"))
        assertFalse(message, message.contains(studio.song.id.toString().uppercase()))
        assertFalse(message, message.contains(".json"))
        assertFalse(message, message.contains("folder"))
        assertTrue(message, message.lowercase().contains("permission"))
        assertFalse(message, message.contains("Try again"))
    }

    @Test fun aSuccessfulSaveClearsAPreviousFailure() {
        studio.storageError = "something went wrong earlier"
        assertTrue(studio.saveNow())
        assertNull(studio.storageError)
    }

    @Test fun storeSaveThrowsRatherThanFailingSilently() {
        val blocked = File.createTempFile("blocked-", "")
        try {
            val store = FileSongStore(blocked, InMemoryKeyValueStore())
            try {
                store.save(Song.create("Nope"))
                fail("expected a throw")
            } catch (expected: IOException) {
            }
        } finally {
            blocked.delete()
        }
    }

    @Test fun openingAnotherSongBailsWhenTheOutgoingSaveFails() {
        studio.edit { it.copy(name = "Stuck") }
        temp.directory.setWritable(false)
        try {
            studio.open(Song.create("Elsewhere"))
            studio.newSong()
        } finally {
            temp.directory.setWritable(true)
        }
        assertEquals("the failed song stays on screen", "Stuck", studio.song.name)
        assertTrue(studio.storageError!!.contains("Stuck"))
    }

    // MARK: Autosave

    @Test fun editsAreWrittenAfterTheDebounceElapses() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            val id = auto.studio.song.id
            auto.studio.edit { it.copy(name = "Edited") }
            auto.scheduler.advance(1.49)
            assertNotEquals("not before the debounce", "Edited", auto.temp.store.load(id)!!.name)
            auto.scheduler.advance(0.02)
            assertEquals("Edited", auto.temp.store.load(id)!!.name)
        } finally {
            auto.close()
        }
    }

    @Test fun eachEditRestartsTheDebounce() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            val id = auto.studio.song.id
            auto.studio.edit { it.copy(name = "One") }
            auto.scheduler.advance(1.0)
            auto.studio.edit { it.copy(name = "Two") }
            auto.scheduler.advance(1.0)
            assertEquals("First Loop", auto.temp.store.load(id)!!.name)
            auto.scheduler.advance(0.6)
            assertEquals("Two", auto.temp.store.load(id)!!.name)
        } finally {
            auto.close()
        }
    }

    @Test fun saveNowWritesImmediatelyAndCancelsThePendingTimer() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            val s = auto.studio
            s.edit { it.copy(name = "First edit") }
            s.saveNow()
            assertEquals("First edit", auto.temp.store.load(s.song.id)!!.name)
            val behind = auto.temp.store.load(s.song.id)!!.copy(name = "Written elsewhere")
            auto.temp.save(behind)
            auto.scheduler.advance(5.0)
            assertEquals("Written elsewhere", auto.temp.store.load(s.song.id)!!.name)
        } finally {
            auto.close()
        }
    }

    @Test fun autosaveDisabledMeansNoTimerFires() {
        val id = studio.song.id
        studio.saveNow()
        studio.edit { it.copy(name = "Not saved") }
        h.scheduler.advance(5.0)
        assertNotEquals("Not saved", temp.store.load(id)!!.name)
    }

    @Test fun selectionAndPlaybackChangesAreNotEdits() {
        val auto = StudioHarness(autosaveEnabled = true)
        try {
            auto.studio.selectedTrack = 2
            auto.studio.selectPattern(0)
            auto.studio.applyPlayhead(3, 0)
            auto.studio.pushAll()
            assertEquals(0, auto.scheduler.pendingTimers)
        } finally {
            auto.close()
        }
    }

    // MARK: Rename from the library

    @Test fun renamingAnotherSongPersistsToTheStore() {
        val other = Song.create("Old name")
        temp.save(other)
        studio.rename(other, "New name")
        assertEquals("New name", temp.store.load(other.id)!!.name)
    }

    @Test fun renamingTheOpenSongSurvivesTheNextSave() {
        studio.edit { it.copy(name = "Working title") }
        studio.saveNow()
        val id = studio.song.id
        studio.rename(studio.song, "Final title")
        assertEquals("Final title", studio.song.name)
        studio.saveNow()
        assertEquals("Final title", temp.store.load(id)!!.name)
    }

    @Test fun emptyOrWhitespaceNameIsRejected() {
        val song = Song.create("Keep me")
        temp.save(song)
        studio.rename(song, "   ")
        assertEquals("Keep me", temp.store.load(song.id)!!.name)
    }

    @Test fun renamingToAnotherSongsNameIsRejected() {
        temp.save(Song.create("Taken"))
        val target = Song.create("Keep me")
        temp.save(target)
        studio.rename(target, "Taken")
        assertEquals("Keep me", temp.store.load(target.id)!!.name)
    }

    @Test fun renamingASongToItsOwnCurrentNameIsAllowed() {
        val song = Song.create("Mine")
        temp.save(song)
        studio.rename(song, "  Mine  ")
        assertEquals("Mine", temp.store.load(song.id)!!.name)
    }

    @Test fun renameTrimsSurroundingWhitespace() {
        val song = Song.create("Old")
        temp.save(song)
        studio.rename(song, "  Padded  ")
        assertEquals("Padded", temp.store.load(song.id)!!.name)
    }

    @Test fun libraryRenameOfTheOpenSongIsUndoable() {
        studio.edit { it.copy(name = "Old") }
        studio.rename(studio.song, "New")
        assertEquals("New", studio.song.name)
        studio.undo()
        assertEquals("Old", studio.song.name)
    }

    // MARK: Rename from the title bar

    private fun type(name: String) {
        for (end in 1..name.length) studio.setSongName(name.substring(0, end))
    }

    @Test fun typedRenameIsOneUndoStep() {
        studio.edit { it.copy(name = "Old") }
        studio.saveNow()
        type("New name")
        studio.normalizeSongName()
        assertEquals("New name", studio.song.name)
        studio.undo()
        assertEquals("Old", studio.song.name)
        assertFalse(studio.canUndo)
    }

    @Test fun aPauseWhileTypingDoesNotSplitTheRename() {
        studio.undoCoalescingWindow = 0.0
        studio.edit { it.copy(name = "Old") }
        type("New")
        h.scheduler.advance(30.0)
        studio.setSongName("New name")
        studio.normalizeSongName()
        studio.undo()
        assertEquals("Old", studio.song.name)
        assertFalse(studio.canUndo)
    }

    @Test fun undoingARenameCanBeRedone() {
        studio.edit { it.copy(name = "Old") }
        type("New")
        studio.normalizeSongName()
        studio.undo()
        assertEquals("Old", studio.song.name)
        studio.redo()
        assertEquals("New", studio.song.name)
    }

    @Test fun anInterveningEditClosesTheRenameRun() {
        studio.edit { it.copy(name = "First") }
        type("Second")
        studio.addPattern()
        type("Third")
        studio.undo()
        assertEquals("Second", studio.song.name)
    }

    @Test fun endingTheRunSeparatesConsecutiveRenames() {
        studio.edit { it.copy(name = "First") }
        type("Second")
        studio.normalizeSongName()
        type("Third")
        studio.normalizeSongName()
        studio.undo()
        assertEquals("Second", studio.song.name)
        studio.undo()
        assertEquals("First", studio.song.name)
    }

    @Test fun settingTheSameNameRecordsNothing() {
        studio.edit { it.copy(name = "Unchanged") }
        studio.setSongName("Unchanged")
        assertFalse(studio.canUndo)
    }

    @Test fun trailingSpaceSurvivesTypingAndIsTrimmedOnCommit() {
        studio.edit { it.copy(name = "Old") }
        studio.setSongName("Two ")
        assertEquals("Two ", studio.song.name)
        studio.setSongName("Two words ")
        studio.normalizeSongName()
        assertEquals("Two words", studio.song.name)
    }

    @Test fun clearingTheNameEntirelyRestoresThePreviousOne() {
        studio.edit { it.copy(name = "Keep me") }
        studio.saveNow()
        type("X")
        studio.setSongName("")
        studio.normalizeSongName()
        assertEquals("Keep me", studio.song.name)
        assertFalse(studio.canUndo)
        assertFalse("redo must not reinstate the rejected name", studio.canRedo)
    }

    @Test fun committedRenameRoundTripsThroughTheStore() {
        val id = studio.song.id
        type("Persisted")
        studio.normalizeSongName()
        assertEquals("Persisted", temp.store.load(id)!!.name)
    }

    // MARK: Unreadable files

    private fun plantCorrupt(): File =
        File(temp.directory, "${java.util.UUID.randomUUID().toString().uppercase()}.json").apply { writeText("{broken") }

    private fun launch(): Studio {
        val s = Studio(temp.store, h.audio, h.scheduler, autosaveEnabled = false, renderer = { throw AssertionError() },
            exportExecutor = h.executor, shareWriter = SongShareWriter(h.shareDir))
        launched.add(s)
        return s
    }

    private val launched = ArrayList<Studio>()

    @After
    fun closeLaunched() = launched.forEach { it.invalidateTimers() }

    @Test fun launchWithUnreadableFileTellsTheUserAndLeavesTheFileAlone() {
        temp.save(Song.create("Fine"), makeCurrent = true)
        val bad = plantCorrupt()
        val s = launch()
        assertEquals("Fine", s.song.name)
        assertEquals(UnreadableSongs.message(1), s.unreadableSongsNotice)
        assertEquals("{broken", bad.readText())
    }

    @Test fun noNoticeWhenEverythingIsReadable() {
        temp.save(Song.create("Fine"), makeCurrent = true)
        val s = launch()
        assertNull(s.unreadableSongsNotice)
        s.loadLibrary()
        assertNull(s.unreadableSongsNotice)
    }

    @Test fun libraryOpenDoesNotRepeatAnAlreadyReportedFile() {
        temp.save(Song.create("Fine"), makeCurrent = true)
        plantCorrupt()
        val s = launch()
        assertNotNull(s.unreadableSongsNotice)
        s.unreadableSongsNotice = null
        assertTrue(s.loadLibrary().map { it.name }.contains("Fine"))
        assertNull(s.unreadableSongsNotice)
        plantCorrupt()
        s.loadLibrary()
        assertEquals(UnreadableSongs.message(1), s.unreadableSongsNotice)
    }

    @Test fun aReportedFileIsNotReportedAgainOnTheNextLaunch() {
        temp.save(Song.create("Fine"), makeCurrent = true)
        plantCorrupt()
        assertNotNull(launch().unreadableSongsNotice)
        val second = launch()
        assertNull(second.unreadableSongsNotice)
        second.loadLibrary()
        assertNull(second.unreadableSongsNotice)
    }

    @Test fun aReplacedOrChangedFileIsReportedAgain() {
        temp.save(Song.create("Fine"), makeCurrent = true)
        val bad = plantCorrupt()
        assertNotNull(launch().unreadableSongsNotice)
        bad.setLastModified(bad.lastModified() + 60_000)
        assertEquals(UnreadableSongs.message(1), launch().unreadableSongsNotice)
    }

    // MARK: Audio events (AudioSessionTests, recast for Android)

    private fun pretendPlaying() {
        studio.isPlaying = true
        studio.playhead = 7
    }

    @Test fun focusLossStopsPlaybackAndTheEngine() {
        h.audio.startIfNeeded()
        pretendPlaying()
        studio.onAudioFocusLost()
        assertFalse(studio.isPlaying)
        assertEquals(0, studio.playhead)
        assertFalse(h.audio.isRunning)
    }

    @Test fun regainingFocusRestartsTheEngineButNotPlayback() {
        pretendPlaying()
        studio.onAudioFocusLost()
        studio.onAudioFocusGained()
        assertFalse("playback must not resume on its own", studio.isPlaying)
        assertTrue("the engine comes back", h.audio.isRunning)
    }

    @Test fun regainingFocusWhilePlayingLeavesPlaybackAlone() {
        pretendPlaying()
        studio.onAudioFocusGained()
        assertTrue(studio.isPlaying)
    }

    @Test fun becomingNoisyStopsPlayback() {
        pretendPlaying()
        studio.onBecomingNoisy()
        assertFalse(studio.isPlaying)
    }

    @Test fun aDeadOutputRebuildsAndRestoresTheSong() {
        var song = TestSongs.golden().copy(tempo = 174.0)
        song = song.copy(patterns = song.patterns + Pattern(name = "B", length = 8, trackCount = song.tracks.size))
        song = song.copy(arrangement = song.arrangement + SongSection(patternID = song.patterns[1].id, repeats = 2))
        studio.open(song)
        pretendPlaying()
        // Scramble the core the way a dead output's replacement would see it.
        studio.core.load(Song.create("Other"))
        studio.core.tempo = 60.0

        studio.onAudioOutputDead()

        assertFalse(studio.isPlaying)
        assertEquals(1, h.audio.rebuilds)
        val core = studio.core
        assertEquals(studio.song.tracks.size, core.trackCount)
        assertEquals(studio.song.patterns.size, core.patternCount)
        assertEquals(studio.song.chain.size, core.chainCount)
        assertEquals(174.0, core.tempo, 0.0)
        core.start()
        val samples = RenderHarness.renderMono(core, 4096)
        assertFalse(samples.any { !it.isFinite() })
    }

    @Test fun backgroundingWhilePlayingStopsPlaybackTruthfully() {
        h.audio.startIfNeeded()
        pretendPlaying()
        studio.stopEngineForBackground()
        assertFalse(studio.isPlaying)
        assertFalse(h.audio.isRunning)
    }

    @Test fun backgroundingWhileIdleStopsTheEngine() {
        h.audio.startIfNeeded()
        studio.isPlaying = false
        studio.stopEngineForBackground()
        assertFalse(h.audio.isRunning)
    }
}
