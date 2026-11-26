package dev.individuation.chiptune.core.model

/** The key a song is written in. It only marks the in-key notes on the
 * piano; nothing stops a note outside it, and playback ignores it. */
data class MusicalKey(
    /** Pitch class of the tonic, 0 (C) through 11 (B). */
    val root: Int,
    val scale: Scale,
) {
    /** The raw value is what the file holds, so it matches iOS. */
    enum class Scale(val rawValue: String, val shortName: String, val fullName: String, val steps: List<Int>) {
        MAJOR("major", "maj", "major", listOf(0, 2, 4, 5, 7, 9, 11)),
        /** Natural minor only; harmonic and melodic would need a third choice. */
        MINOR("minor", "min", "minor", listOf(0, 2, 3, 5, 7, 8, 10)),
        ;

        companion object {
            fun fromRaw(raw: String): Scale? = entries.firstOrNull { it.rawValue == raw }
        }
    }

    /** floorMod, not %, so a pitch below C-1 still lands on its letter. */
    private fun interval(midi: Int): Int = Math.floorMod(midi - root, 12)

    fun contains(midi: Int): Boolean = interval(midi) in scale.steps

    fun isRoot(midi: Int): Boolean = interval(midi) == 0

    /** 1…7 counted from the root, or null for a note outside the scale. */
    fun degree(midi: Int): Int? = scale.steps.indexOf(interval(midi)).takeIf { it >= 0 }?.plus(1)

    private val rootName: String get() = NoteName.NAMES[Math.floorMod(root, 12)]

    /** The KEY button's label: "C maj", "F# min". */
    val shortLabel: String get() = "$rootName ${scale.shortName}"

    /** What TalkBack reads: "C major". */
    val spokenLabel: String get() = "$rootName ${scale.fullName}"

    val isValid: Boolean get() = root in ROOTS

    companion object {
        val ROOTS: IntRange = 0..11
    }
}
