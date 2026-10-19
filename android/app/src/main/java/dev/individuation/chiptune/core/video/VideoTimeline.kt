package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Song

/**
 * Which step of the song each frame of an exported video shows. Port of
 * `Sources/Video/VideoTimeline.swift`.
 *
 * Built from exactly what the WAV renderer plays from: the normalized song,
 * [Chip.samplesPerStep], `song.chain` and the patterns' lengths. Frame `f`
 * shows the audio at sample `f x SAMPLES_PER_FRAME`, so a note's cell reaches
 * the playing row on the frame its sound starts, and the picture can't drift
 * from the soundtrack over a long song the way a seconds-based clock would.
 *
 * Both platforms are held to `Tests/Fixtures/video-timeline.json`.
 */
class VideoTimeline(song: Song, options: ExportOptions) {

    /** Where in the arrangement a frame is. */
    data class Position(
        /** Index into [chain]: the arrangement with its repeats expanded, so
         * the second play of a section is a slot of its own. */
        val chainSlot: Int,
        /** Index into `song.patterns`. */
        val pattern: Int,
        /** Step inside that pattern. */
        val step: Int,
    )

    val samplesPerStep: Int
    /** Pattern index per chain slot, as [Song.chain] gives it. */
    val chain: List<Int>
    /** Step count of each chain slot's pattern. */
    val slotLengths: List<Int>
    val loopCount: Int
    /** The arrangement's passes. Nothing new is triggered after this. */
    val bodySamples: Int
    /** The ring-out after the body, or 0 when the export folds it into the
     * start. Truncated the way the WAV renderer does. */
    val tailSamples: Int

    init {
        val normalized = song.normalized()
        val clamped = options.clamped
        samplesPerStep = Chip.samplesPerStep(normalized.tempo, WavExport.SAMPLE_RATE)
        chain = normalized.chain
        slotLengths = chain.map { normalized.patterns.getOrNull(it)?.length ?: 0 }
        loopCount = clamped.loopCount
        bodySamples = samplesPerStep * maxOf(normalized.arrangementSteps, 1) * clamped.loopCount
        tailSamples = if (clamped.effectiveTailMode == ExportOptions.TailMode.RING_OUT) {
            (WavExport.SAMPLE_RATE * WavExport.tailSeconds(normalized)).toInt()
        } else {
            0
        }
    }

    val totalSamples: Int get() = bodySamples + tailSamples
    /** Enough frames to cover every sample: the last one may run up to a
     * frame past the audio, never short of it. */
    val totalFrames: Int get() = (totalSamples + SAMPLES_PER_FRAME - 1) / SAMPLES_PER_FRAME
    val stepsPerPass: Int get() = slotLengths.sum()
    val seconds: Double get() = totalSamples.toDouble() / WavExport.SAMPLE_RATE

    /** The first sample [frame] shows. */
    fun sample(frame: Int): Int = frame * SAMPLES_PER_FRAME

    /** Steps since the start of the body at [frame], with the fraction of the
     * current step. Keeps counting through the tail, so a scroll or a decay
     * driven by it carries on smoothly past the last step. */
    fun elapsedSteps(frame: Int): Double = sample(frame).toDouble() / maxOf(samplesPerStep, 1).toDouble()

    /** The step [frame] shows, or null once the body is over and only the
     * tail is ringing. */
    fun position(frame: Int): Position? {
        val s = sample(frame)
        if (s < 0 || s >= bodySamples || samplesPerStep <= 0) return null
        return positionOfStep(s / samplesPerStep)
    }

    /** The step [globalStep] steps into the body, across passes; null outside
     * the body. Swift's `position(globalStep:)`. */
    fun positionOfStep(globalStep: Int): Position? {
        val perPass = stepsPerPass
        if (globalStep < 0 || perPass <= 0 || globalStep >= perPass * loopCount) return null
        var step = globalStep % perPass
        for ((slot, length) in slotLengths.withIndex()) {
            if (step < length) return Position(slot, chain[slot], step)
            step -= length
        }
        return null
    }

    companion object {
        const val FPS = 30
        /** 1470 at 44.1kHz: a whole number, so frames never accumulate rounding. */
        val SAMPLES_PER_FRAME: Int = WavExport.SAMPLE_RATE.toInt() / FPS
    }
}
