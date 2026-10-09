package dev.individuation.chiptune.core.model

/**
 * Fixed limits shared by the DSP core and the UI (port of `Chip` in
 * `Sources/Model/Song.swift`). The audio thread indexes into flat buffers
 * sized from these, so they must not change at runtime.
 *
 * Notes are stored as `Int` rather than Swift's `Int8`; every value a
 * normalized song holds is a rest (-1), a note-off (-2) or a MIDI note 0…127.
 */
object Chip {
    const val MAX_TRACKS = 8
    const val MAX_STEPS = 64
    const val MAX_PATTERNS = 16
    /** Caps the flat list sections expand into, not the sections the UI shows. */
    const val MAX_CHAIN = 128
    const val EMPTY_NOTE = -1
    /** Middle C — what a preview plays when nothing better is selected. */
    const val DEFAULT_PREVIEW_NOTE = 60
    /** "Cut the sustaining note". */
    const val NOTE_OFF = -2

    const val TEMPO_MIN = 40.0
    const val TEMPO_MAX = 300.0
    val tempoRange: ClosedFloatingPointRange<Double> = TEMPO_MIN..TEMPO_MAX
    /** Sequencer resolution — a step is a sixteenth. */
    const val STEPS_PER_BEAT = 4
    val patternLengthRange: IntRange = 4..MAX_STEPS

    /** Folds any raw JSON integer outside `NOTE_OFF..127` into a rest, rather
     * than failing the whole song's decode. */
    fun clampNote(raw: Long): Int = if (raw < NOTE_OFF || raw > 127) EMPTY_NOTE else raw.toInt()

    fun clampNote(raw: Int): Int = clampNote(raw.toLong())

    /** Samples in one sequencer step — the one formula the live core and the
     * offline exporter share. Rounds half away from zero like Swift. */
    fun samplesPerStep(tempo: Double, sampleRate: Double): Int {
        val bpm = swiftClamp(tempo, TEMPO_MIN, TEMPO_MAX)
        return swiftRounded(sampleRate * 60.0 / (bpm * STEPS_PER_BEAT.toDouble())).toInt()
    }
}

/** Swift's `.rounded()` (`.toNearestOrAwayFromZero`). `Math.round` rounds
 * -0.5 up to 0, and `rint` rounds half to even; neither matches. */
fun swiftRounded(x: Double): Double {
    if (!x.isFinite()) return x
    val a = Math.abs(x)
    val whole = Math.floor(a)
    // a - floor(a) is exact, so the tie test is too; floor(a + 0.5) is not
    // (0.49999999999999994 + 0.5 rounds up to 1.0).
    val r = if (a - whole >= 0.5) whole + 1.0 else whole
    return Math.copySign(r, x)
}

/** Swift's `min(max(x, lo), hi)`: NaN passes straight through, as it does
 * in the clamps this ports — callers that need a NaN default check first. */
fun swiftClamp(x: Double, lo: Double, hi: Double): Double {
    val atLeast = if (lo >= x) lo else x // Swift.max(x, lo) returns lo when lo >= x
    return if (hi < atLeast) hi else atLeast // Swift.min(atLeast, hi) returns hi when hi < atLeast
}

fun swiftClamp(x: Int, lo: Int, hi: Int): Int = minOf(maxOf(x, lo), hi)

/** Seconds since 2001-01-01T00:00:00Z — `Date`'s reference date, which is
 * what Swift's default `JSONEncoder` writes for `modified`. */
object SongClock {
    const val UNIX_SECONDS_AT_REFERENCE = 978_307_200L

    fun fromUnixMillis(millis: Long): Double = millis / 1000.0 - UNIX_SECONDS_AT_REFERENCE

    fun now(): Double = fromUnixMillis(System.currentTimeMillis())
}
