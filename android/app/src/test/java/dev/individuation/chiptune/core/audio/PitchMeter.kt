package dev.individuation.chiptune.core.audio

import kotlin.math.ln

/** Zero-crossing pitch measurement for the effect tests: where a pitch moves
 * within a note, Goertzel's fixed bins can't follow it, but the spacing of
 * rising zero crossings can. */
object PitchMeter {

    /** Fractional sample positions where the signal rises through zero. */
    fun risingCrossings(samples: FloatArray, from: Int = 0, until: Int = samples.size): List<Double> {
        val out = ArrayList<Double>()
        for (i in maxOf(from, 1) until until) {
            val a = samples[i - 1].toDouble()
            val b = samples[i].toDouble()
            if (a < 0.0 && b >= 0.0) out.add((i - 1) + (-a) / (b - a))
        }
        return out
    }

    /** Mean frequency over the window, from the first to the last rising crossing. */
    fun frequency(samples: FloatArray, from: Int, until: Int, sampleRate: Double = RenderHarness.SAMPLE_RATE): Double {
        val c = risingCrossings(samples, from, until)
        if (c.size < 2) return 0.0
        return (c.size - 1).toDouble() * sampleRate / (c.last() - c.first())
    }

    /** One frequency per cycle: (position of the span's middle, frequency),
     * each measured over [span] cycles. A naive pulse's edges land on whole
     * samples, so a single cycle jitters by up to a sample; a few cycles
     * average that out. */
    fun cycles(samples: FloatArray, from: Int, until: Int, sampleRate: Double = RenderHarness.SAMPLE_RATE,
               span: Int = 1): List<Pair<Double, Double>> {
        val c = risingCrossings(samples, from, until)
        return (span until c.size).map { i -> (c[i] + c[i - span]) / 2.0 to span * sampleRate / (c[i] - c[i - span]) }
    }

    fun semitones(ratio: Double): Double = 12.0 * ln(ratio) / ln(2.0)
}
