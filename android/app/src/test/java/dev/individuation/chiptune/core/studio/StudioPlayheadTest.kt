package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.model.Song
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Drives the real core the way the 60 Hz poll does, for the playback suites. */
internal class SongPlayback(private val studio: Studio) {
    /** `play()` minus the audio output: the part the sequencer cares about. */
    fun start(armFollow: Boolean = false) {
        studio.songMode = true
        studio.isPlaying = true
        studio.pushAll()
        studio.core.setSongMode(true)
        if (armFollow) studio.armSongFollow()
        studio.core.start()
        RenderHarness.renderMono(studio.core, 1)
    }

    fun advance(steps: Int) {
        RenderHarness.renderMono(studio.core, samplesPerStep(studio.song.tempo) * steps)
        tick()
    }

    fun tick() {
        val core = studio.core
        studio.applyPlayhead(core.currentStep, core.currentPattern, core.currentChainSlot)
    }
}

/** Port of `StudioPlayheadTests.swift`: what the grid does while the
 * sequencer runs underneath it. */
class StudioPlayheadTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val playback get() = SongPlayback(studio)

    private fun fresh() {
        if (::h.isInitialized) h.close()
        h = StudioHarness()
        studio.open(Song.create("Blank"))
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(0)
    }

    @Before
    fun setUp() = fresh()

    @After
    fun tearDown() = h.close()

    private fun pretendPlayingSong() {
        studio.songMode = true
        studio.isPlaying = true
    }

    @Test fun songModePlaybackDragsTheGridToTheSoundingPattern() {
        pretendPlayingSong()
        studio.applyPlayhead(3, 1)
        assertEquals(3, studio.playhead)
        assertEquals(1, studio.playingPattern)
        assertEquals(1, studio.selectedPattern)
        assertTrue(studio.followsArrangement)
    }

    @Test fun patternModeNeverMovesTheSelection() {
        studio.songMode = false
        studio.isPlaying = true
        studio.applyPlayhead(5, 1)
        assertEquals(1, studio.playingPattern)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun aPatternIndexPastTheEndOfTheSongIsIgnored() {
        pretendPlayingSong()
        studio.applyPlayhead(0, 9)
        assertEquals(9, studio.playingPattern)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun stayingOnThePatternOnlyMovesThePlayhead() {
        pretendPlayingSong()
        studio.applyPlayhead(0, 1)
        studio.selectPattern(0)
        studio.applyPlayhead(7, 1)
        assertEquals(7, studio.playhead)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun selectingAPatternWhilePlayingStopsTheFollow() {
        pretendPlayingSong()
        studio.applyPlayhead(0, 1)
        studio.selectPattern(0)
        studio.applyPlayhead(0, 2)
        assertFalse(studio.followsArrangement)
        assertEquals(2, studio.playingPattern)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun selectingAPatternWhileStoppedLeavesTheFollowArmed() {
        studio.songMode = true
        studio.selectPattern(1)
        assertTrue(studio.followsArrangement)
    }

    @Test fun editingTheSoundingPatternPinsTheGrid() {
        pretendPlayingSong()
        studio.toggleCell(0, 4)
        studio.applyPlayhead(0, 1)
        assertFalse(studio.followsArrangement)
        assertEquals(1, studio.playingPattern)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun everyPatternEditPinsTheGrid() {
        val edits: List<Pair<String, () -> Unit>> = listOf(
            "toggleCell" to { studio.toggleCell(0, 2) },
            "typeNote" to { studio.typeNote(64) },
            "clearAtCursor" to { studio.clearAtCursor() },
            "clearTrack" to { studio.clearTrack(0) },
            "setPatternLength" to { studio.setPatternLength(32) },
            "clearPattern" to { studio.clearPattern() },
        )
        for ((name, edit) in edits) {
            fresh()
            pretendPlayingSong()
            edit()
            studio.applyPlayhead(0, 1)
            assertFalse("$name should pin the grid", studio.followsArrangement)
            assertEquals("$name let the arrangement take the grid", 0, studio.selectedPattern)
        }
    }

    @Test fun clearingSomeOtherPatternDoesNotPin() {
        pretendPlayingSong()
        studio.clearPattern(1)
        studio.applyPlayhead(0, 1)
        assertTrue(studio.followsArrangement)
        assertEquals(1, studio.selectedPattern)
    }

    @Test fun editsOutsideThePatternDoNotPin() {
        pretendPlayingSong()
        studio.setTempo(140.0)
        studio.edit { it.withInstrument(0) { i -> i.copy(decay = 0.5) } }
        studio.pushInstrument(0)
        studio.setVolume(1, 0.2)
        studio.addSection(studio.song.patterns[1].id)
        studio.applyPlayhead(0, 1)
        assertTrue(studio.followsArrangement)
        assertEquals(1, studio.selectedPattern)
    }

    @Test fun reselectingTheSoundingPatternReArmsTheFollow() {
        pretendPlayingSong()
        studio.toggleCell(0, 4)
        studio.applyPlayhead(0, 1)
        assertFalse(studio.followsArrangement)
        studio.selectPattern(1)
        assertTrue(studio.followsArrangement)
        assertEquals(1, studio.selectedPattern)
        studio.applyPlayhead(0, 0)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun addingAPatternWhilePlayingPinsTheGridToIt() {
        pretendPlayingSong()
        val added = studio.addPattern()
        assertEquals(added, studio.selectedPattern)
        assertFalse(studio.followsArrangement)
    }

    // MARK: Re-indexing the patterns under the sequencer

    @Test fun deletingAnEarlierPatternKeepsTheSoundingPatternPlaying() {
        playback.start()
        val soundingID = studio.song.patterns[1].id
        playback.advance(16)
        assertEquals(1, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.selectedPattern)

        studio.removePattern(0)

        assertEquals(soundingID, studio.song.patterns[0].id)
        assertEquals(0, studio.core.currentPattern)
        assertEquals(0, studio.core.currentChainSlot)
        assertEquals(0, studio.playingPattern)
        assertTrue(studio.followsArrangement)
        assertEquals(0, studio.selectedPattern)
    }

    @Test fun duplicatingAnEarlierPatternKeepsTheSoundingPatternPlaying() {
        playback.start()
        val soundingID = studio.song.patterns[1].id
        playback.advance(16)
        assertEquals(1, studio.core.currentChainSlot)

        studio.duplicatePattern(0)

        assertEquals(soundingID, studio.song.patterns[2].id)
        assertEquals(2, studio.core.currentPattern)
        assertEquals(1, studio.core.currentChainSlot)
        assertEquals(2, studio.playingPattern)
    }

    @Test fun deletingAnEarlierPatternKeepsTheOffsetWithinTheRepeats() {
        studio.edit { it.withSection(1) { s -> s.copy(repeats = 3) } }
        studio.pushArrangement()
        playback.start()
        assertEquals(listOf(0, 1, 1, 1, 2), studio.song.chain)

        playback.advance(32)
        assertEquals(2, studio.core.currentChainSlot)

        studio.removePattern(0)

        assertEquals(listOf(0, 0, 0, 1), studio.song.chain)
        assertEquals(0, studio.core.currentPattern)
        assertEquals("still the section's second play", 1, studio.core.currentChainSlot)
        assertEquals(0, studio.playingPattern)
    }

    @Test fun deletingTheSoundingPatternLetsTheNextSlotTakeOver() {
        playback.start()
        playback.advance(16)
        assertEquals(1, studio.core.currentPattern)

        studio.removePattern(1)

        assertEquals(2, studio.song.patterns.size)
        assertEquals(1, studio.core.currentPattern)
        assertTrue(studio.core.currentPattern < studio.song.patterns.size)
        assertEquals(studio.song.chain[studio.core.currentChainSlot], studio.core.currentPattern)
    }

    // MARK: The 60 Hz poll itself

    /** Play arms the poll on the injected scheduler; each tick mirrors the core. */
    @Test fun playPollsTheCoreAtSixtyHertzUntilStop() {
        studio.setSongMode(true)
        studio.play()
        assertTrue(studio.isPlaying)
        RenderHarness.renderMono(studio.core, samplesPerStep(studio.song.tempo) * 16 + 10)
        h.scheduler.advance(1.0 / 60.0)
        assertEquals(1, studio.playingPattern)
        assertEquals(1, studio.selectedPattern)
        studio.stop()
        assertFalse(studio.isPlaying)
        assertEquals(0, studio.playhead)
        assertEquals("stop cancels the poll", 0, h.scheduler.pendingTimers)
    }

    @Test fun playThatCannotStartAudioLeavesPlayOff() {
        h.audio.startSucceeds = false
        studio.play()
        assertFalse(studio.isPlaying)
        assertEquals("Couldn't start audio. Try again.", studio.audioError)
        assertEquals(0, h.scheduler.pendingTimers)
        h.audio.startSucceeds = true
        studio.togglePlay()
        assertTrue(studio.isPlaying)
        assertEquals(null, studio.audioError)
        studio.togglePlay()
        assertFalse(studio.isPlaying)
    }
}

/** Port of `StudioSongPlayStartTests`. */
class StudioSongPlayStartTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
        studio.addPattern()
        studio.addPattern()
        studio.songMode = true
    }

    @After
    fun tearDown() = h.close()

    @Test fun playFromAStaleHeadPatternStillMovesTheGridToTheArrangementHead() {
        studio.playingPattern = 0
        studio.selectPattern(1)
        studio.armSongFollow()
        studio.isPlaying = true
        studio.applyPlayhead(0, 0)
        assertEquals(0, studio.selectedPattern)
        assertEquals(0, studio.playingPattern)
        assertTrue(studio.followsArrangement)
    }

    @Test fun playGivesTheSameResultAfterEarlierPlaybackMovedOn() {
        studio.playingPattern = 2
        studio.selectPattern(1)
        studio.armSongFollow()
        studio.isPlaying = true
        studio.applyPlayhead(0, 0)
        assertEquals(0, studio.selectedPattern)
        assertEquals(0, studio.playingPattern)
    }

    @Test fun playRearmsAPinnedFollow() {
        studio.isPlaying = true
        studio.applyPlayhead(0, 1)
        studio.selectPattern(2)
        assertFalse(studio.followsArrangement)
        studio.isPlaying = false
        studio.armSongFollow()
        assertTrue(studio.followsArrangement)
    }

    @Test fun chipTapWhilePlayingStillPins() {
        studio.armSongFollow()
        studio.isPlaying = true
        studio.applyPlayhead(0, 0)
        studio.selectPattern(2)
        studio.applyPlayhead(0, 1)
        assertFalse(studio.followsArrangement)
        assertEquals(2, studio.selectedPattern)
    }

    @Test fun patternModeIsUntouched() {
        studio.songMode = false
        studio.selectPattern(2)
        studio.armSongFollow()
        assertEquals(2, studio.selectedPattern)
        assertEquals(2, studio.playingPattern)
    }
}
