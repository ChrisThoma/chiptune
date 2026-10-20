package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.MidiExport
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track

/**
 * How bright each track's bar is on a frame of the Cover style. Port of
 * `Sources/Video/ChannelPulse.swift`.
 *
 * A note-on lights the bar fully on the frame its sound starts, and it fades
 * in a straight line to dark over [DECAY_FRAMES]. A note-off cuts it, as it
 * cuts the sound. A track that is heard as nothing (muted, or at a volume the
 * MIDI export would also call silent, [MidiExport.isSilent]) never lights, so
 * the bars only move for music the soundtrack actually plays.
 *
 * The fade is fixed rather than following each instrument's decay: a
 * triangle held for four seconds would otherwise sit at full brightness and
 * stop reading as a beat.
 */
class ChannelPulse(song: Song, private val timeline: VideoTimeline) {
    private val patterns: List<Pattern>
    private val silent: List<Boolean>

    init {
        val normalized = song.normalized()
        patterns = normalized.patterns
        silent = normalized.tracks.map(MidiExport::isSilent)
    }

    /** One level per track, 0..1. */
    fun levels(frame: Int): List<Double> = silent.indices.map { level(it, frame) }

    private fun level(track: Int, frame: Int): Double {
        if (silent[track] || timeline.samplesPerStep <= 0) return 0.0
        val now = timeline.sample(frame)
        val lastStep = timeline.stepsPerPass * timeline.loopCount - 1
        // Past the body the last step is still the latest thing played, so a
        // note on it carries on fading through the tail.
        var step = minOf(now / timeline.samplesPerStep, lastStep)
        while (step >= 0) {
            val since = (now - step * timeline.samplesPerStep).toDouble() / VideoTimeline.SAMPLES_PER_FRAME
            if (since >= DECAY_FRAMES) return 0.0
            val at = timeline.positionOfStep(step)
            val note = at?.let { patterns.getOrNull(it.pattern)?.rows?.getOrNull(track)?.getOrNull(it.step) }
            if (note != null) {
                if (note >= 0) return 1 - since / DECAY_FRAMES
                if (note == Chip.NOTE_OFF) return 0.0
            }
            step -= 1
        }
        return 0.0
    }

    companion object {
        /** A third of a second at 30 fps. */
        const val DECAY_FRAMES = 10

        /** Whether a track's name is drawn dim, as one the soundtrack doesn't
         * play: muted, or at a volume the MIDI export calls silent. The same
         * rule in both styles, and the one that keeps a Cartridge bar dark.
         * iOS's `VideoFrameRenderer.dimsName(of:in:)`. */
        @Suppress("UNUSED_PARAMETER")
        fun dimsName(track: Track, style: ExportOptions.VideoStyle): Boolean = MidiExport.isSilent(track)
    }
}
