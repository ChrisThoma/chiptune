package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Track
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `StudioPresetPickTests.swift`: tapping a preset chip in the sound
 * panel applies the sound and plays a note of it. The audio half is measured
 * by rendering the studio's own core offline after the pick; the harness's
 * fake output means no render thread competes for it. */
class StudioPresetPickTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.undoCoalescingWindow = 0.0
    }

    @After
    fun tearDown() = h.close()

    /** Tracks with no notes, so anything the render hears came from the pick. */
    private fun openSilentSong(kinds: List<ChannelKind> = listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE)) {
        val base = TestSongs.empty(tempo = 120.0, length = 16)
        val song = base.copy(
            tracks = kinds.map { Track(kind = it) },
            patterns = base.patterns.mapIndexed { i, p ->
                if (i == 0) p.copy(rows = kinds.map { Pattern.EMPTY_ROW }) else p
            },
        )
        studio.open(song)
    }

    private fun preset(name: String, kind: ChannelKind): InstrumentPreset {
        val found = InstrumentPreset.presetsFor(kind).firstOrNull { it.name == name }
        assertNotNull("no $kind preset named $name", found)
        return found!!
    }

    private fun renderAfterPreview(seconds: Double): FloatArray =
        RenderHarness.renderMono(studio.core, (RenderHarness.SAMPLE_RATE * seconds).toInt())

    // The song

    @Test fun pickingAPresetAppliesItsSound() {
        openSilentSong()
        val blip = preset("Blip", ChannelKind.PULSE1)

        studio.pickPreset(blip, 0)

        assertEquals(blip.instrument, studio.song.tracks[0].instrument)
        assertEquals("Blip", InstrumentPreset.matching(studio.song.tracks[0].instrument, ChannelKind.PULSE1)?.name)
    }

    @Test fun pickingAPresetIsOneUndoStep() {
        openSilentSong()
        val before = studio.song.tracks[0].instrument
        assertFalse("precondition: a freshly opened song has no history", studio.canUndo)

        studio.pickPreset(preset("Chord", ChannelKind.PULSE1), 0)
        assertTrue(studio.canUndo)

        studio.undo()
        assertEquals(before, studio.song.tracks[0].instrument)
        assertFalse("the pick took more than one undo step", studio.canUndo)
    }

    /** Re-tapping the selected chip is how you hear it again. That is not an
     * edit: no Undo step, and Redo survives. */
    @Test fun rePickingTheCurrentPresetChangesNothingInTheSong() {
        openSilentSong()
        val lead = preset("Lead", ChannelKind.PULSE1)
        assertEquals("precondition: a new pulse 1 track starts on Lead", lead.instrument, studio.song.tracks[0].instrument)
        // Arm Redo with one real edit, undone.
        studio.pickPreset(preset("Blip", ChannelKind.PULSE1), 0)
        studio.undo()
        assertTrue(studio.canRedo)
        val song = studio.song

        studio.pickPreset(lead, 0)

        assertEquals(song, studio.song)
        assertFalse("re-picking the current preset added an undo step", studio.canUndo)
        assertTrue("re-picking the current preset wiped Redo", studio.canRedo)
    }

    @Test fun pickingOnAMissingTrackDoesNothing() {
        openSilentSong()
        val song = studio.song

        val played = studio.pickPreset(preset("Blip", ChannelKind.PULSE1), 7)

        assertFalse(played)
        assertEquals(song, studio.song)
        assertFalse(studio.canUndo)
    }

    // The preview

    @Test fun pickingAPresetPlaysIt() {
        openSilentSong()

        val played = studio.pickPreset(preset("Pluck", ChannelKind.PULSE1), 0)

        assertTrue(played)
        assertTrue("picking a preset made no sound", RenderHarness.rms(renderAfterPreview(0.1)) > 0.01)
    }

    /** The tap on the chip that's already lit is the "play it again" gesture,
     * so the no-op on the song must not swallow the preview. */
    @Test fun rePickingTheCurrentPresetStillPlaysIt() {
        openSilentSong()

        val played = studio.pickPreset(preset("Lead", ChannelKind.PULSE1), 0)

        assertTrue(played)
        assertTrue("re-tapping the selected preset was silent", RenderHarness.rms(renderAfterPreview(0.1)) > 0.01)
    }

    /** The preview is on the track that was picked for, not the selected one. */
    @Test fun thePreviewPlaysOnThePickedTrack() {
        openSilentSong()
        studio.selectedTrack = 0
        studio.edit { s -> s.copy(tracks = s.tracks.mapIndexed { i, t -> if (i == 0) t.copy(muted = true) else t }) }
        studio.pushInstrument(0)

        val played = studio.pickPreset(preset("Sub", ChannelKind.TRIANGLE), 1)

        assertTrue(played)
        assertTrue(
            "the preview went to the selected (muted) track instead",
            RenderHarness.rms(renderAfterPreview(0.1)) > 0.01,
        )
    }

    /** A muted track still takes the sound but plays nothing, and like a
     * header tap doesn't take over the voice (see `previewNote`). */
    @Test fun pickingOnAMutedTrackAppliesTheSoundWithoutPlayingIt() {
        openSilentSong()
        studio.toggleMute(0)
        val blip = preset("Blip", ChannelKind.PULSE1)

        val played = studio.pickPreset(blip, 0)

        assertFalse(played)
        assertEquals(blip.instrument, studio.song.tracks[0].instrument)
        assertTrue(RenderHarness.rms(renderAfterPreview(0.1)) < 0.001)
    }

    /** "Pad (holds)" and "Drone (holds)" have no decay to end them and no
     * pattern step comes along to cut a preview, so it has to stop by itself. */
    @Test fun previewingAHeldPresetStopsByItself() {
        for ((name, kind) in listOf("Pad (holds)" to ChannelKind.PULSE1, "Drone (holds)" to ChannelKind.TRIANGLE)) {
            openSilentSong(listOf(kind))
            val held = preset(name, kind)
            assertTrue("precondition: $name holds", held.instrument.sustain)

            assertTrue(studio.pickPreset(held, 0))
            val samples = renderAfterPreview(2.0)

            assertTrue("$name preview was silent", RenderHarness.rms(samples, 0, 4410) > 0.01)
            assertTrue("$name preview was still ringing 2 s later", RenderHarness.rms(samples, samples.size - 4410, samples.size) < 0.001)
        }
    }
}
