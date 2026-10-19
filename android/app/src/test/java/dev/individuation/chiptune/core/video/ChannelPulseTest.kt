package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.setNote
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.audio.withTrack
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ChannelPulseTests.swift`: the Cover style's bars. Each track
 * flashes on a note and fades. A bar that moves for a note nobody hears would
 * be lying about the music, so silent tracks and non-notes stay dark. */
class ChannelPulseTest {

    /** 150 BPM: a step is exactly three frames. Two tracks, all rests. */
    private fun song(): Song {
        val base = TestSongs.empty(name = "Pulse", tempo = 150.0, length = 16)
        return base.copy(
            tracks = listOf(Track(kind = ChannelKind.PULSE1), Track(kind = ChannelKind.TRIANGLE)),
            patterns = listOf(base.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW, Pattern.EMPTY_ROW))),
        )
    }

    private fun pulse(song: Song, loops: Int = 1): ChannelPulse {
        val options = ExportOptions(loops, format = ExportOptions.Format.VIDEO)
        return ChannelPulse(song, VideoTimeline(song, options))
    }

    @Test fun thereIsOneLevelPerTrack() {
        assertEquals(2, pulse(song()).levels(0).size)
    }

    @Test fun aNoteFlashesFullAndFadesSteadilyToNothing() {
        val pulse = pulse(song().setNote(0, 0, 60))
        assertEquals(1.0, pulse.levels(0)[0], 0.0)
        var last = 1.0
        for (frame in 1 until ChannelPulse.DECAY_FRAMES) {
            val level = pulse.levels(frame)[0]
            assertTrue("frame $frame", level < last)
            assertTrue("frame $frame", level > 0)
            last = level
        }
        assertEquals(0.0, pulse.levels(ChannelPulse.DECAY_FRAMES)[0], 0.0)
        assertEquals(0.0, pulse.levels(ChannelPulse.DECAY_FRAMES + 5)[0], 0.0)
    }

    @Test fun theNextNoteFlashesAgain() {
        val pulse = pulse(song().setNote(0, 0, 60).setNote(0, 2, 64))
        assertTrue(pulse.levels(5)[0] < 1)
        assertEquals(1.0, pulse.levels(6)[0], 0.0)
    }

    @Test fun aRestGivesNoPulse() {
        val pulse = pulse(song().setNote(0, 0, 60))
        for (frame in 0 until 48) assertEquals("frame $frame", 0.0, pulse.levels(frame)[1], 0.0)
    }

    @Test fun aNoteOffGivesNoPulseAndCutsTheOneBefore() {
        val pulse = pulse(song().setNote(1, 0, Chip.NOTE_OFF).setNote(0, 0, 60).setNote(0, 1, Chip.NOTE_OFF))
        assertEquals(0.0, pulse.levels(0)[1], 0.0)
        assertTrue(pulse.levels(2)[0] > 0)
        assertEquals(0.0, pulse.levels(3)[0], 0.0)
    }

    @Test fun aMutedTrackGivesNoPulse() {
        val song = song().setNote(0, 0, 60).withTrack(0) { it.copy(muted = true) }
        assertEquals(0.0, pulse(song).levels(0)[0], 0.0)
    }

    /** The same rule as the MIDI export's: a volume that rounds to velocity 0
     * is silent, not just one at exactly 0. */
    @Test fun aSilentVolumeGivesNoPulse() {
        for (volume in listOf(0.0, 0.003)) {
            val song = song().setNote(0, 0, 60).withInstrument(0) { it.copy(volume = volume) }
            assertEquals("$volume", 0.0, pulse(song).levels(0)[0], 0.0)
        }
        val quiet = song().setNote(0, 0, 60).withInstrument(0) { it.copy(volume = 0.01) }
        assertEquals(1.0, pulse(quiet).levels(0)[0], 0.0)
    }

    /** The last note of the song keeps fading into the ring-out rather than
     * switching off where the body ends. */
    @Test fun theLastNoteFadesIntoTheTail() {
        val song = song().withPattern(0) { it.copy(length = 4) }.setNote(0, 3, 60)
        val pulse = pulse(song)
        // Step 3 starts at frame 9; the body ends at frame 12.
        assertEquals(1.0, pulse.levels(9)[0], 0.0)
        assertTrue(pulse.levels(13)[0] > 0)
        assertTrue(pulse.levels(13)[0] < pulse.levels(12)[0])
    }

    /** The first step of the second pass is the first step again. */
    @Test fun theSecondPassFlashesAgain() {
        val song = song().withPattern(0) { it.copy(length = 4) }.setNote(0, 0, 60)
        assertEquals(1.0, pulse(song, loops = 2).levels(12)[0], 0.0)
    }
}
