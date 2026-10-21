package dev.individuation.chiptune.core.video

import kotlin.math.floor

/**
 * The times a Cartridge video draws (port of `Sources/Video/VideoClock.swift`).
 * The total is the Export sheet's own text (`ui/layout/Format.clock`, the
 * same rule kept here so core needn't reach into the UI), so the file says
 * what the sheet promised: `1:07`, or `0:04.1` under ten seconds.
 *
 * The running clock takes the total's shape, so the two read alike side by
 * side: a tenth when the total has one, whole seconds otherwise. It is
 * truncated, so it never runs ahead of the audio, never passes the total,
 * and the last frame shows the total so the bar ends on it.
 */
object VideoClock {
    fun total(seconds: Double): String {
        val s = maxOf(seconds, 0.0)
        val tenths = rounded(s * 10)
        if (hasTenths(tenths)) return tenthsText(tenths)
        val whole = rounded(s)
        return "${whole / 60}:${twoDigits(whole % 60)}"
    }

    fun elapsed(seconds: Double, total: Double, isFinalFrame: Boolean): String {
        if (isFinalFrame) return total(total)
        val s = seconds.coerceIn(0.0, maxOf(total, 0.0))
        if (hasTenths(rounded(maxOf(total, 0.0) * 10))) {
            // A hair of slack, so a frame landing on a tenth in samples
            // (13230 / 44100) isn't shown a tenth early in binary.
            return tenthsText(floor(s * 10 + 1e-9).toLong())
        }
        val whole = floor(s + 1e-9).toLong()
        return "${whole / 60}:${twoDigits(whole % 60)}"
    }

    private fun hasTenths(tenths: Long): Boolean = tenths in 1..99

    private fun tenthsText(tenths: Long): String = "0:${twoDigits(tenths / 10)}.${tenths % 10}"

    /** Swift's `.rounded()` for the non-negative values here: half up. */
    private fun rounded(x: Double): Long = floor(x + 0.5).toLong()

    /** ASCII digits whatever the locale, as the iOS frame shows. */
    private fun twoDigits(n: Long): String = n.toString().padStart(2, '0')
}
