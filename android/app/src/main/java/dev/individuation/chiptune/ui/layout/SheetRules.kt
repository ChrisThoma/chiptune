package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongClock
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.text.Graphemes
import dev.individuation.chiptune.core.text.SwiftText
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID

/*
 * The four sheets' pure rules and copy, ported from `ExportSheet.swift`,
 * `ArrangementView.swift`, `SongListView.swift` and `InstrumentEditor.swift`
 * so they are tested without a window. Copy is word for word.
 */

/** What the export section says under its button when the render wouldn't be
 * worth keeping; null when there is nothing to warn about. */
object ExportNotesFooter {
    fun text(song: Song): String? {
        if (song.hasNotes) {
            // Muting everything is a legitimate mix, so the export still runs.
            return if (song.hasAudibleNotes) null else "Every track with notes is muted, so the export would be silent."
        }
        if (!song.hasNotesAnywhere) return "This song has no notes yet."
        return "Its notes are in a pattern the arrangement doesn't play. Add that pattern to the arrangement to export it."
    }
}

/** The repeats and ending controls freeze for the length of a render: it
 * keeps the settings it started with. */
object ExportControls {
    fun settingsLocked(isExporting: Boolean): Boolean = isExporting
}

object ExportCopy {
    fun loopCount(n: Int): String = "$n\u00d7"

    /** Rough length of the file, so the repeat count means something. */
    fun duration(song: Song, options: ExportOptions): String {
        var seconds = song.arrangementDuration * options.loopCount
        if (options.tailMode == ExportOptions.TailMode.RING_OUT) seconds += WavExport.tailSeconds(song)
        return Format.clock(seconds)
    }

    fun repeatsFooter(song: Song, options: ExportOptions): String =
        "The whole arrangement, ${Format.count(options.loopCount, "time")} \u2014 ${duration(song, options)}."

    fun endingLabel(mode: ExportOptions.TailMode): String = when (mode) {
        ExportOptions.TailMode.SEAMLESS_LOOP -> "Seamless loop"
        ExportOptions.TailMode.RING_OUT -> "Ring out"
    }

    fun endingFooter(mode: ExportOptions.TailMode): String = when (mode) {
        ExportOptions.TailMode.SEAMLESS_LOOP ->
            "The last notes ring on into the start, so the file loops with no gap. Best for dropping into something else."
        ExportOptions.TailMode.RING_OUT ->
            "The last notes fade out past the end and the file finishes in silence. Best when the file is the finished thing."
    }

    /** Swift's `Int(progress * 100)` truncates. */
    fun rendering(progress: Double): String = "Rendering\u2026 ${(progress * 100).toInt()}%"

    fun canExport(hasNotes: Boolean, attemptInFlight: Boolean): Boolean = hasNotes && !attemptInFlight

    /** The Android share step's title (iOS goes straight to the share sheet). */
    fun resultTitle(fileName: String): String = "Exported $fileName"
}

/** The Edit pill: its label comes from the same flag that drives the rows. */
object ArrangementEditToggle {
    fun toggled(editing: Boolean): Boolean = !editing

    fun title(editing: Boolean): String = if (editing) "Done editing" else "Edit"
}

object ArrangementCopy {
    val CAPACITY_WARNING = "More than ${Chip.MAX_CHAIN} plays \u2014 sections past that won't sound."

    const val HELP = "Each section plays one pattern. Repeat it to hold a section for longer, and drag to reorder. " +
        "Switch the transport to SONG to hear the whole thing; PATT keeps looping just the pattern you're editing."

    fun summary(song: Song): String =
        "${Format.count(song.chain.toSet().size, "pattern")} \u00b7 ${song.arrangementSteps} steps \u00b7 " +
            "${Format.clock(song.arrangementDuration)} at ${Format.bpm(song.tempo)}"

    fun sectionLabel(position: Int, patternName: String?): String = "Section ${position + 1}, pattern ${patternName ?: "none"}"

    /** A song needs a section; the model puts a fresh one back rather than
     * remove the last, so the sheet doesn't offer a delete that does nothing. */
    fun canDelete(sectionCount: Int): Boolean = sectionCount > 1
}

object SongListCopy {
    const val TITLE = "Songs"
    const val EMPTY_TITLE = "No songs yet"
    const val EMPTY_MESSAGE = "Start writing and this one shows up here \u2014 songs save themselves as you go."
    const val DELETE_MESSAGE = "This can't be undone."

    fun deleteTitle(name: String): String = "Delete \u201c$name\u201d?"

    /** `120 BPM \u00b7 3 patterns \u00b7 Oct 9, 2026`: no clock, so a long
     * song doesn't wrap on a narrow phone. */
    fun detail(song: Song, locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault()): String =
        "${Format.bpm(song.tempo)} \u00b7 ${Format.count(song.patterns.size, "pattern")} \u00b7 ${date(song.modified, locale, zone)}"

    /** `Date.formatted(date: .abbreviated, time: .omitted)`; [modified] is
     * seconds since 2001-01-01. */
    fun date(modified: Double, locale: Locale, zone: ZoneId): String {
        val millis = ((modified + SongClock.UNIX_SECONDS_AT_REFERENCE) * 1000).toLong()
        return Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
            .format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale))
    }

    /** Blank, or another song's name, is refused by the model: grey Rename out. */
    fun canRename(text: String, songs: List<Song>, renaming: UUID?): Boolean {
        val trimmed = SwiftText.trimWhitespaces(text)
        if (trimmed.isEmpty()) return false
        return songs.none { it.id != renaming && it.name == trimmed }
    }
}

object InstrumentEditorCopy {
    /** A preset arpeggio; [spoken] is what TalkBack says ("Major", not "Maj"). */
    data class ArpShape(val label: String, val spoken: String, val offsets: List<Int>)

    val ARPS: List<ArpShape> = listOf(
        ArpShape("Off", "Off", emptyList()),
        ArpShape("Maj", "Major", listOf(0, 4, 7)),
        ArpShape("Min", "Minor", listOf(0, 3, 7)),
        ArpShape("Oct", "Octave", listOf(0, 12)),
        ArpShape("5th", "Fifth", listOf(0, 7)),
    )

    const val PRESET_CAPTION = "A starting point. Every control below stays yours to move."
    const val CHANNEL_CAPTION = "Switching waveform keeps this track's notes and loads the new channel's default sound."
    const val ARPEGGIO_CAPTION = "Cycles through the chord tones fast enough to sound like one voice \u2014 " +
        "the classic way to fake a chord on a single channel."
    val TRACK_LIMIT_FOOTER = "A song can hold up to ${Chip.MAX_TRACKS} tracks."

    val VOLUME_RANGE = 0.0..1.0
    val DECAY_RANGE = 0.03..4.0

    /** "Custom" once the sound has been edited away from every preset. */
    fun presetName(instrument: Instrument?, kind: ChannelKind): String =
        instrument?.let { InstrumentPreset.matching(it, kind)?.name } ?: "Custom"

    fun nameFooter(draft: String): String {
        val max = Track.MAX_NAME_LENGTH
        return "Up to $max characters \u2014 ${Graphemes.count(draft)} of $max used."
    }

    /** `String(format: "%.2fs")`, which ignores the locale. */
    fun decay(seconds: Double): String = String.format(Locale.ROOT, "%.2fs", seconds)

    fun levelFooter(held: Boolean): String =
        if (held) "The note sounds until the next one on this track, or a rest." else "The note fades out over the decay time."

    fun pulseWidthValue(duty: Int): String = Instrument.DUTY_LABELS.getOrNull(duty) ?: "Unknown"

    fun arpeggioValue(offsets: List<Int>): String = ARPS.firstOrNull { it.offsets == offsets }?.spoken ?: "Custom"

    /** The segment a shape selects; an off-menu shape adjusts from Off. */
    fun arpeggioIndex(offsets: List<Int>): Int = ARPS.indexOfFirst { it.offsets == offsets }.coerceAtLeast(0)

    fun adjustedIndex(current: Int, count: Int, direction: AdjustmentDirection): Int = when (direction) {
        AdjustmentDirection.INCREMENT -> minOf(current + 1, count - 1)
        AdjustmentDirection.DECREMENT -> maxOf(current - 1, 0)
    }

    /** A slider's TalkBack step: a tenth of its range, held at the ends. */
    fun sliderStep(value: Double, range: ClosedFloatingPointRange<Double>, direction: AdjustmentDirection): Double {
        val step = (range.endInclusive - range.start) / 10
        return when (direction) {
            AdjustmentDirection.INCREMENT -> minOf(value + step, range.endInclusive)
            AdjustmentDirection.DECREMENT -> maxOf(value - step, range.start)
        }
    }

    fun clearTrackButton(patternName: String): String = "Clear this track in pattern $patternName"

    fun clearTrackTitle(patternName: String): String = "Clear this track in pattern $patternName?"

    fun dockedHeading(label: String): String = "Sound settings for $label"
}
