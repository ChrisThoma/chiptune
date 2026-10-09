package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ChipCoreReleaseTests.swift`: the main thread's way of cutting a
 * voice it can't reach any other way, which must survive being issued while
 * the audio thread is mid-buffer. */
class ChipCoreReleaseTest {

    private val sampleRate = RenderHarness.SAMPLE_RATE

    /** A held triangle sounding on track 0, already past its attack. */
    private fun heldCore(): ChipCore {
        val core = ChipCore(sampleRate)
        core.load(TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = true).normalized())
        core.start()
        return core
    }

    private fun level(samples: FloatArray): Double = RenderHarness.rms(samples, samples.size - 4410, samples.size)

    @Test fun releaseCutsASustainingVoice() {
        val core = heldCore()
        assertTrue(level(RenderHarness.renderMono(core, 22050)) > 0.01)
        core.release(0)
        assertTrue("release left the voice sounding", level(RenderHarness.renderMono(core, 8820)) < 0.01)
    }

    @Test fun releaseAllCutsEverySoundingVoice() {
        var song = TestSongs.empty(tempo = 120.0)
            .copy(tracks = listOf(Track(kind = ChannelKind.TRIANGLE), Track(kind = ChannelKind.PULSE1)))
            .withPattern(0) { it.copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW)) }
        for (track in 0 until 2) {
            song = song.withInstrument(track) { it.copy(sustain = true, volume = 1.0) }.setNote(track, 0, 48 + track * 12)
        }
        val core = ChipCore(sampleRate)
        core.load(song.normalized())
        core.start()
        assertTrue(level(RenderHarness.renderMono(core, 22050)) > 0.01)
        core.releaseAll()
        assertTrue(level(RenderHarness.renderMono(core, 8820)) < 0.01)
    }

    @Test fun releaseOnAnIdleOrOutOfRangeTrackIsIgnored() {
        val core = heldCore()
        RenderHarness.renderMono(core, 22050)
        core.release(3)
        core.release(-1)
        core.release(Chip.MAX_TRACKS)
        core.release(999)
        assertTrue("releasing some other track cut the one that was sounding",
            level(RenderHarness.renderMono(core, 8820)) > 0.01)
    }

    @Test fun aReleaseIssuedMidBufferIsNotLost() {
        for (chunk in listOf(1, 7, 64, 1024)) {
            val core = heldCore()
            assertTrue("precondition: the held note is sounding",
                level(RenderHarness.renderMono(core, 22050, chunk)) > 0.01)
            core.release(0)
            val after = RenderHarness.renderMono(core, 8820, chunk)
            assertTrue("a release issued at a $chunk-frame chunk size was lost", level(after) < 0.01)
        }
    }

    @Test fun aReleaseIssuedWhileStoppedDoesNotCutTheNextNote() {
        val core = ChipCore(sampleRate)
        core.load(TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = true).normalized())
        core.release(0)
        core.start()
        assertTrue("a stale release cut the first note after START", level(RenderHarness.renderMono(core, 22050)) > 0.01)
    }

    // MARK: Attributing a ringing voice to the cell that started it

    @Test fun ringingSourceReportsTheTriggeringCell() {
        val core = heldCore()
        RenderHarness.renderMono(core, 22050)
        assertEquals(ChipCore.RingingSource(0, 0), core.ringingSource(0))
    }

    @Test fun ringingSourceIsNilForASilentTrack() {
        val core = heldCore()
        RenderHarness.renderMono(core, 22050)
        assertNull(core.ringingSource(1))
        assertNull(core.ringingSource(-1))
        assertNull(core.ringingSource(Chip.MAX_TRACKS))
    }

    @Test fun ringingSourceIsNilForAKeyboardPreview() {
        val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = true).setNote(0, 0, Chip.EMPTY_NOTE).normalized()
        val core = ChipCore(sampleRate)
        core.load(song)
        core.audition(0, 60)
        val samples = RenderHarness.renderMono(core, 4410)
        assertTrue("the preview never sounded", RenderHarness.rms(samples) > 0.01)
        assertNull("a preview was attributed to a pattern cell", core.ringingSource(0))
    }

    @Test fun turningHoldOnDuringAPreviewStillEndsTheNote() {
        val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = false).setNote(0, 0, Chip.EMPTY_NOTE).normalized()
        val core = ChipCore(sampleRate)
        core.load(song)
        core.audition(0, 60)
        RenderHarness.renderMono(core, 4410)

        core.setInstrument(song.tracks[0].instrument.copy(sustain = true), ChannelKind.TRIANGLE, 0, false)
        val after = RenderHarness.renderMono(core, (sampleRate * 1.5).toInt())
        assertTrue("turning Hold on mid-preview left the note ringing forever", level(after) < 0.01)
        assertTrue("the held preview should still sound right after Hold is turned on",
            RenderHarness.rms(after, 0, 4410) > 0.01)
    }

    /** A sustaining preview gets `previewSeconds` (0.9 s) of life, then releases. */
    @Test fun aSustainingPreviewEndsAfterItsLifetime() {
        val song = TestSongs.singleNote(ChannelKind.TRIANGLE, 48, sustain = true).setNote(0, 0, Chip.EMPTY_NOTE).normalized()
        val core = ChipCore(sampleRate)
        core.load(song)
        core.audition(0, 60)
        val samples = RenderHarness.renderMono(core, (sampleRate * 1.2).toInt())
        assertTrue("still sounding at 0.8 s", RenderHarness.rms(samples, 35000, 39000) > 0.01)
        assertTrue("silent by 1.1 s", RenderHarness.rms(samples, 48510, 52920) < 0.001)
    }
}
