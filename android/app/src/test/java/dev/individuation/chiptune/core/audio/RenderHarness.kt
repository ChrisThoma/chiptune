package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.Track
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sqrt

/** Renders [ChipCore] offline and measures the result. Port of
 * `Tests/Support/RenderHarness.swift`: load a song, render a window, measure
 * it. No audio device, no timing, no flake.
 *
 * Swift's array slices become `(samples, from, until)` triples here, or a
 * [window] copy where a test reads better with one. */
object RenderHarness {

    const val SAMPLE_RATE = 44100.0

    // MARK: Rendering

    /** Renders [frames] samples in [chunk]-sized slices, the way both the live
     * callback and the WAV exporter do. A bug that only shows up across a slice
     * boundary is invisible to a single big render. */
    fun renderMono(core: ChipCore, frames: Int, chunk: Int = 1024): FloatArray {
        val out = FloatArray(frames)
        var done = 0
        while (done < frames) {
            val n = minOf(chunk, frames - done)
            core.render(n, out, done)
            done += n
        }
        return out
    }

    /** Loads a song into a fresh core and renders [seconds] of it playing.
     * `songMode` false loops the focused pattern, matching PATT in the app. */
    fun render(song: Song, seconds: Double, songMode: Boolean = false): FloatArray {
        val core = ChipCore(SAMPLE_RATE)
        core.load(song.normalized())
        core.setSongMode(songMode)
        core.start()
        return renderMono(core, (SAMPLE_RATE * seconds).toInt())
    }

    // MARK: Level

    fun rms(samples: FloatArray, from: Int = 0, until: Int = samples.size): Double {
        if (until <= from) return 0.0
        var sum = 0.0
        for (i in from until until) sum += samples[i].toDouble() * samples[i].toDouble()
        return sqrt(sum / (until - from).toDouble())
    }

    fun peak(samples: FloatArray, from: Int = 0, until: Int = samples.size): Double {
        var p = 0.0
        for (i in from until until) p = max(p, abs(samples[i].toDouble()))
        return p
    }

    /** Fraction of the window spent above zero - a duty cycle read off the output. */
    fun dutyRatio(samples: FloatArray, from: Int = 0, until: Int = samples.size): Double {
        if (until <= from) return 0.0
        var high = 0
        for (i in from until until) if (samples[i] > 0f) high += 1
        return high.toDouble() / (until - from).toDouble()
    }

    // MARK: Pitch

    /** Goertzel magnitude at [frequency], normalized by window length. */
    fun goertzel(samples: FloatArray, from: Int, until: Int, frequency: Double,
                 sampleRate: Double = SAMPLE_RATE): Double {
        if (until - from <= 1) return 0.0
        val k = 2.0 * cos(2.0 * PI * frequency / sampleRate)
        var s1 = 0.0
        var s2 = 0.0
        for (i in from until until) {
            val s0 = samples[i].toDouble() + k * s1 - s2
            s2 = s1
            s1 = s0
        }
        val power = s1 * s1 + s2 * s2 - k * s1 * s2
        return sqrt(max(power, 0.0)) / (until - from).toDouble()
    }

    /** The candidate frequency carrying the most energy; the first of equal
     * maxima, as Swift's `max(by:)` keeps. */
    fun dominantFrequency(samples: FloatArray, from: Int, until: Int, candidates: List<Double>): Double? {
        var best: Double? = null
        var bestMag = 0.0
        for (f in candidates) {
            val m = goertzel(samples, from, until, f)
            if (best == null || m > bestMag) {
                best = f
                bestMag = m
            }
        }
        return best
    }

    /** Semitone ladder around a MIDI note, for [dominantFrequency] candidates. */
    fun semitoneLadder(around: Int, spread: Int = 12): List<Double> =
        (-spread..spread).map { NoteName.frequency((around + it).coerceIn(-128, 127)) }

    /** Strongest bin over the average bin: ~20 for a pitched voice, ~3 for noise. */
    fun spectralPeakiness(samples: FloatArray, from: Int, until: Int, frequencies: List<Double>): Double {
        val mags = frequencies.map { goertzel(samples, from, until, it) }
        val mean = mags.sum() / mags.size.toDouble()
        if (mean <= 0) return 0.0
        return (mags.maxOrNull() ?: 0.0) / mean
    }

    /** Number of level changes in the window - runs of moving samples. */
    fun levelSteps(samples: FloatArray, from: Int, until: Int, threshold: Double = 0.008): Int {
        if (until - from <= 1) return 0
        var steps = 0
        var moving = false
        var previous = samples[from].toDouble()
        for (i in (from + 1) until until) {
            val value = samples[i].toDouble()
            val jumping = abs(value - previous) > threshold
            if (jumping && !moving) steps += 1
            moving = jumping
            previous = value
        }
        return steps
    }

    // MARK: Onsets

    /** Sample indices where the signal jumps from near-silence into audio. */
    fun onsets(samples: FloatArray, threshold: Double = 0.02, window: Int = 128, refractory: Int = 2048): List<Int> {
        val found = ArrayList<Int>()
        var wasQuiet = true
        var i = 0
        while (i + window <= samples.size) {
            val level = rms(samples, i, i + window)
            if (level > threshold) {
                val last = found.lastOrNull()
                if (wasQuiet && (last == null || i - last >= refractory)) found.add(i)
                wasQuiet = false
            } else if (level < threshold * 0.5) {
                wasQuiet = true
            }
            i += window
        }
        return found
    }

    /** Largest jump between neighboring samples. */
    fun maxDelta(samples: FloatArray, from: Int = 0, until: Int = samples.size): Double {
        if (until - from <= 1) return 0.0
        var worst = 0.0
        var previous = samples[from].toDouble()
        for (i in (from + 1) until until) {
            val value = samples[i].toDouble()
            worst = max(worst, abs(value - previous))
            previous = value
        }
        return worst
    }
}

// MARK: Song editing helpers for the immutable model

fun Song.withInstrument(track: Int, transform: (Instrument) -> Instrument): Song =
    copy(tracks = tracks.mapIndexed { i, t -> if (i == track) t.copy(instrument = transform(t.instrument)) else t })

fun Song.withTrack(track: Int, transform: (Track) -> Track): Song =
    copy(tracks = tracks.mapIndexed { i, t -> if (i == track) transform(t) else t })

fun Song.withPattern(index: Int, transform: (Pattern) -> Pattern): Song =
    copy(patterns = patterns.mapIndexed { i, p -> if (i == index) transform(p) else p })

/** `song.patterns[0].rows[row][step] = note`. */
fun Song.setNote(row: Int, step: Int, note: Int, pattern: Int = 0): Song =
    withPattern(pattern) { it.withNote(row, step, note) }

/** Bitwise float equality, so NaN == NaN and -0 != +0. */
fun sameBits(a: FloatArray, b: FloatArray): Boolean {
    if (a.size != b.size) return false
    for (i in a.indices) if (a[i].toRawBits() != b[i].toRawBits()) return false
    return true
}
