package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.text.Graphemes
import dev.individuation.chiptune.core.text.SwiftText

/** The one rule for how much of a typed name a capped field may show
 * (port of `NameCap.swift`). Characters are grapheme clusters. */
object NameCap {
    fun clip(text: String, limit: Int): String = Graphemes.prefix(text, limit)

    /** What a field's draft should become when the stored name changes under
     * it, or null to leave the draft alone. */
    fun draftUpdate(draft: String, stored: String?): String? {
        val target = stored ?: ""
        if (target == draft) return null
        if (stored == null && SwiftText.trimWhitespaceAndNewlines(draft).isEmpty()) return null
        return target
    }
}

/** Renaming a pattern (port of `PatternNameCheck` in `PatternBar.swift`). */
sealed class PatternNameCheck {
    data class Accepted(val name: String) : PatternNameCheck()
    data object Blank : PatternNameCheck()
    data object Duplicate : PatternNameCheck()

    val acceptedName: String? get() = (this as? Accepted)?.name

    companion object {
        const val MAX_LENGTH = 6

        /** Trimmed, truncated, case-sensitive; another pattern's name is a duplicate. */
        fun evaluate(name: String, among: List<String>, renaming: Int): PatternNameCheck {
            val trimmed = Graphemes.prefix(SwiftText.trimWhitespaces(name), MAX_LENGTH)
            if (trimmed.isEmpty()) return Blank
            val taken = among.withIndex().any { (i, n) -> i != renaming && n == trimmed }
            return if (taken) Duplicate else Accepted(trimmed)
        }

        fun footer(text: String, among: List<String>, renaming: Int): String {
            if (evaluate(text, among, renaming) == Duplicate) return "Another pattern already uses this name."
            return "Up to $MAX_LENGTH characters — ${Graphemes.count(text)} of $MAX_LENGTH used."
        }
    }
}

/** Geometry for dragging a track header sideways (port of `TrackReorder.swift`). */
object TrackReorder {
    /** The column a header dragged [translation] from [source] has reached.
     * Rounds half away from zero, and clamps. */
    fun destination(source: Int, translation: Double, columnStep: Double, count: Int): Int {
        if (!(columnStep > 0) || count <= 0) return source
        val columns = swiftRounded(translation / columnStep).toInt()
        return minOf(maxOf(source + columns, 0), count - 1)
    }

    /** How far column [index] slides while [dragging] hovers over [to]. */
    fun offset(index: Int, dragging: Int, to: Int, columnStep: Double): Double {
        if (dragging < to && index > dragging && index <= to) return -columnStep
        if (dragging > to && index >= to && index < dragging) return columnStep
        return 0.0
    }
}

/** Index math for an arrangement drag-to-reorder drop (port of `ArrangementReorder.swift`):
 * the destination is in terms of the list before the dragged row is removed. */
object ArrangementReorder {
    fun destination(draggedIndex: Int, overIndex: Int): Int {
        if (draggedIndex == overIndex) return draggedIndex
        return if (draggedIndex < overIndex) overIndex + 1 else overIndex
    }
}

/** What an arrangement row shows in its leading slot. */
sealed class ArrangementRowLeading {
    data class Number(val text: String) : ArrangementRowLeading()
    data object PlayingMarker : ArrangementRowLeading()

    companion object {
        fun content(position: Int, playing: Boolean): ArrangementRowLeading =
            if (playing) PlayingMarker else Number("${position + 1}")
    }
}

/** Screen-reader words for an arrangement row's repeats stepper. */
object RepeatsAccessibility {
    fun label(position: Int): String = "Section ${position + 1} repeats"

    fun value(repeats: Int): String = if (repeats == 1) "1 time" else "$repeats times"
}
