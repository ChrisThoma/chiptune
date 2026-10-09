package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.NameCap
import dev.individuation.chiptune.core.model.NoteName
import dev.individuation.chiptune.core.model.PatternNameCheck
import dev.individuation.chiptune.core.text.Graphemes
import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/*
 * Small pure rules the views read, ported from the SwiftUI files that hold
 * them: `Formatting.swift`, `ScreenshotMode` (ContentView.swift),
 * `PlainStepper`, `BuildStamp.swift`, `PatternChipAccessibility`,
 * `TransportPlayShape` and the accessibility adjustables.
 */

/** Display formatters shared by the export sheet, the library rows and the
 * arrangement summary (port of `Format`). */
object Format {
    /** `1:07`; under ten seconds it keeps a tenth, `0:01.8`. */
    fun clock(seconds: Double): String {
        val s = maxOf(seconds, 0.0)
        val tenths = swiftRound(s * 10)
        if (tenths in 1..99) return String.format(Locale.ROOT, "0:%02d.%d", tenths / 10, tenths % 10)
        val whole = swiftRound(s)
        return String.format(Locale.ROOT, "%d:%02d", whole / 60, whole % 60)
    }

    /** `3 patterns`, `1 pattern`. */
    fun count(n: Int, noun: String): String = "$n $noun${if (n == 1) "" else "s"}"

    /** `57%` for a 0...1 level, rounded rather than truncated. */
    fun percent(fraction: Double): String = "${swiftRound(fraction * 100)}%"

    /** `120 BPM`. */
    fun bpm(tempo: Double): String = "${tempo.toInt()} BPM"

    /** Swift's `.rounded()`: half away from zero (these are never negative). */
    private fun swiftRound(x: Double): Long = if (x >= 0) Math.floor(x + 0.5).toLong() else -Math.floor(-x + 0.5).toLong()
}

/**
 * Which screen a debug launch asked to open, for screenshots. The keys are
 * the shoot's command line (`adb shell am start ... --ez shotPlaying true`, or
 * `--es shotPlaying YES`). Declaration order is precedence, as iOS takes the
 * first case set.
 */
enum class ScreenshotMode(val key: String) {
    ARRANGEMENT("shotArrangement"),
    INSTRUMENT("shotEditor"),
    LIBRARY("shotLibrary"),
    EXPORT("shotExport"),
    PLAYING("shotPlaying"),
    PATTERN("shotPatternB"),
    ;

    companion object {
        /** [extras] holds each present key's raw value (Boolean or String). */
        fun requested(extras: Map<String, Any?>): ScreenshotMode? =
            entries.firstOrNull { truthy(extras[it.key]) }

        /** `NSString.boolValue`, near enough: YES, true or a non-zero number. */
        private fun truthy(value: Any?): Boolean = when (value) {
            is Boolean -> value
            is Number -> value.toLong() != 0L
            is String -> value.trim().lowercase().let { it == "yes" || it == "true" || it == "y" || it == "t" || (it.toLongOrNull() ?: 0L) != 0L }
            else -> false
        }
    }
}

/** The minus/plus pair standing in for a system stepper in sheets. */
object PlainStepperRules {
    const val INCREMENT_ACTION_NAME = Adjustable.INCREMENT_ACTION_NAME
    const val DECREMENT_ACTION_NAME = Adjustable.DECREMENT_ACTION_NAME

    fun delta(forIncrement: Boolean): Int = if (forIncrement) 1 else -1

    /** One step from [value], held at the ends of [range]; a locked stepper stays put. */
    fun stepped(value: Int, delta: Int, range: IntRange, isEnabled: Boolean): Int {
        if (!isEnabled) return value
        return minOf(maxOf(value + delta, range.first), range.last)
    }

    fun canDecrease(value: Int, range: IntRange, isEnabled: Boolean): Boolean = isEnabled && value > range.first

    fun canIncrease(value: Int, range: IntRange, isEnabled: Boolean): Boolean = isEnabled && value < range.last
}

/** TalkBack's increment/decrement, as iOS's `AccessibilityAdjustmentDirection`. */
enum class AdjustmentDirection { INCREMENT, DECREMENT }

/** An adjustable control's two custom actions, forwarded to one closure.
 * The Compose side exposes these as semantics custom actions. */
class Adjustable(private val adjust: (AdjustmentDirection) -> Unit) {
    fun increment() = adjust(AdjustmentDirection.INCREMENT)

    fun decrement() = adjust(AdjustmentDirection.DECREMENT)

    companion object {
        /** Worded as the system stepper words its actions. */
        const val INCREMENT_ACTION_NAME = "Increment"
        const val DECREMENT_ACTION_NAME = "Decrement"
    }
}

/** Increment moves toward "Ring out", decrement toward "Seamless loop";
 * neither wraps. */
fun ExportOptions.TailMode.adjusted(direction: AdjustmentDirection): ExportOptions.TailMode = when {
    this == ExportOptions.TailMode.SEAMLESS_LOOP && direction == AdjustmentDirection.INCREMENT -> ExportOptions.TailMode.RING_OUT
    this == ExportOptions.TailMode.RING_OUT && direction == AdjustmentDirection.DECREMENT -> ExportOptions.TailMode.SEAMLESS_LOOP
    else -> this
}

/** The arrangement's 128-play warning is announced on crossing, not on every change. */
object ArrangementCapacityAnnouncement {
    fun shouldAnnounce(previouslyExceeded: Boolean, nowExceeds: Boolean): Boolean = !previouslyExceeded && nowExceeds
}

/** What a pattern chip tells TalkBack beyond its name. */
object PatternChipAccessibility {
    fun value(playing: Boolean, isEmpty: Boolean): String? = when {
        playing && isEmpty -> "Playing, Empty"
        playing -> "Playing"
        isEmpty -> "Empty"
        else -> null
    }
}

/** The chip's long-press menu and its TalkBack actions share these rules:
 * Duplicate needs room for another pattern, Delete needs a pattern left over. */
object PatternChipActions {
    const val RENAME = "Rename"
    const val DUPLICATE = "Duplicate"
    const val CLEAR = "Clear"
    const val DELETE = "Delete"

    fun canDuplicate(canAddPattern: Boolean): Boolean = canAddPattern

    fun canDelete(patternCount: Int): Boolean = patternCount > 1

    /** The TalkBack actions, in menu order; the menu shows all four and dims these. */
    fun available(canAddPattern: Boolean, patternCount: Int): List<String> = buildList {
        add(RENAME)
        if (canDuplicate(canAddPattern)) add(DUPLICATE)
        add(CLEAR)
        if (canDelete(patternCount)) add(DELETE)
    }
}

/** Play's shape: the fixed width in a row, the whole row when stacked. */
object TransportPlayShape {
    fun width(fillsRow: Boolean): Double? = if (fillsRow) null else ChipLayout.PLAY_BUTTON_WIDTH

    fun glyphSize(scale: Double): Double = 18 * scale
}

/** A grid cell's spoken label and value. */
object CellAccessibility {
    fun label(fullTrackLabel: String, step: Int): String = "$fullTrackLabel step ${step + 1}"

    fun value(note: Int): String = if (note == -1) "Empty" else NoteName.label(note)

    const val PREVIEW_ACTION = "Preview"
}

/** The rename sheet's live state: the cap as you type, the footer, and
 * whether Rename is offered. */
object PatternRenameForm {
    fun capped(text: String): String = NameCap.clip(text, PatternNameCheck.MAX_LENGTH)

    fun footer(text: String, names: List<String>, index: Int?): String {
        if (index == null) {
            val max = PatternNameCheck.MAX_LENGTH
            return "Up to $max characters \u2014 ${Graphemes.count(text)} of $max used."
        }
        return PatternNameCheck.footer(text, names, index)
    }

    fun canRename(text: String, names: List<String>, index: Int?): Boolean =
        index != null && PatternNameCheck.evaluate(text, names, index).acceptedName != null
}

/** The tempo dialog's field, read as Swift's `Double(String)` reads it:
 * plain decimal digits, an optional sign, point and exponent, nothing else. */
object TempoInput {
    private val NUMBER = Regex("[+-]?(\\d+(\\.\\d*)?|\\.\\d+)([eE][+-]?\\d+)?")

    fun parse(text: String): Double? {
        val trimmed = text.trim(' ', '\t')
        if (!NUMBER.matches(trimmed)) return null
        return trimmed.toDoubleOrNull()
    }
}

/**
 * Which build this is (port of `BuildStamp.swift`): the date legible at a
 * glance, the commit that names the code, and the release on its own line.
 */
class BuildStamp(commit: String?, val builtAt: Instant?, version: String?) {
    val commit: String? = present(commit)
    val version: String? = present(version)

    /** `Built 11 Aug 2026`, in the reader's own date format. */
    val builtLine: String?
        get() = builtAt?.let {
            val date = it.atZone(ZoneOffset.UTC).toLocalDate()
            "Built ${date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))}"
        }

    val versionLine: String? get() = version?.let { "Version $it" }

    /** Top to bottom, with anything unavailable left out. */
    val lines: List<String> get() = listOfNotNull(builtLine, commit, versionLine)

    /** What the menu row copies: the release and the commit. */
    val copyText: String get() = listOfNotNull(version, commit).joinToString(" \u00b7 ")

    companion object {
        /** Blank, an unexpanded `$(...)`, or the Gradle stamp's "nogit" is not data. */
        private fun present(value: String?): String? {
            val trimmed = value?.trim() ?: return null
            if (trimmed.isEmpty() || trimmed.contains("\$(") || trimmed == "nogit") return null
            return trimmed
        }

        /** `BuildConfig.BUILD_DATE` is an ISO day (`2026-10-09`), stamped in UTC. */
        fun parseBuildDate(value: String?): Instant? = try {
            value?.trim()?.takeIf { it.isNotEmpty() }?.let { LocalDate.parse(it).atStartOfDay().toInstant(ZoneOffset.UTC) }
        } catch (e: Exception) {
            null
        }
    }
}
