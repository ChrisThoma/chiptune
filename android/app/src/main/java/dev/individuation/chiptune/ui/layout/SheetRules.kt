package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.MidiExport
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
import dev.individuation.chiptune.core.video.VideoExport
import dev.individuation.chiptune.core.video.VideoTimeline
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

/** What sits under the Export button for [format]. A WAV keeps the notes above.
 * A MIDI file still carries a muted or 0% track's notes (at volume 0;
 * "silent" to the user, who sets it as 0%), or, for such a drum track beside
 * one that plays, an empty track (see
 * [MidiExport.emptiedTracks]), so the "would be silent" warning is replaced by a
 * line saying where those tracks went; the no-notes messages stay, since there
 * is nothing to export either way. */
fun ExportNotesFooter.text(song: Song, format: ExportOptions.Format): String? = when (format) {
    ExportOptions.Format.WAV, ExportOptions.Format.VIDEO -> text(song)
    ExportOptions.Format.MIDI -> if (!song.hasNotes) {
        text(song)
    } else {
        val line = StringBuilder("The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. ")
            .append("Arpeggios come out as the note you wrote.")
        // Worked out once: only a silent track with notes the arrangement
        // plays has anything in the file to speak of.
        val chain = song.chain
        val emptied = MidiExport.emptiedTracks(song, chain)
        val silentWithNotes = song.tracks.indices.filter {
            MidiExport.isSilent(song.tracks[it]) && MidiExport.reaches(it, song, chain)
        }
        val emptiedCount = silentWithNotes.count { it in emptied }
        val silencedCount = silentWithNotes.size - emptiedCount
        when {
            silencedCount == 1 -> line.append(" A muted or silent track keeps its notes in the file, turned all the way down.")
            silencedCount > 1 -> line.append(" Muted or silent tracks keep their notes in the file, turned all the way down.")
        }
        when {
            emptiedCount == 1 -> line.append(" A muted or silent drum track is left empty, because all drum tracks share one part in the file.")
            emptiedCount > 1 -> line.append(" Muted or silent drum tracks are left empty, because all drum tracks share one part in the file.")
        }
        line.toString()
    }
}

/** What sits under the WAV/MIDI picker. A MIDI file is the one a beginner
 * can be surprised by: it opens in another app with that app's sounds, not
 * the chip's. Null for a WAV, which is the sound itself. */
object ExportFormatFooter {
    fun text(format: ExportOptions.Format): String? = when (format) {
        ExportOptions.Format.WAV -> null
        ExportOptions.Format.VIDEO -> "A 9:16 video for Reels, TikTok and Shorts."
        ExportOptions.Format.MIDI ->
            "A MIDI file holds your notes, not the chip sounds. The app you open it in plays them with its own instruments."
    }
}

/** The format, repeats and ending controls freeze for the length of a render:
 * it keeps the settings it started with. */
object ExportControls {
    fun settingsLocked(isExporting: Boolean): Boolean = isExporting

    /** Whether the Export button comes back once the render it started has
     * finished. A failed or canceled one frees it for another try. One that
     * left a file keeps it: the panel is coming down for the result dialog,
     * which offers that file, and a second render started in the meantime
     * would clear it first. The panel comes back fresh. */
    fun freesExportButton(startedAttempt: Int?, completedAttempt: Int, producedFile: Boolean): Boolean =
        startedAttempt != null && completedAttempt >= startedAttempt && !producedFile
}

/** The length readout under Repeats, and what to say when the file will run
 * long. Port of `ExportLength`. */
object ExportLength {
    /** Reels and Shorts cut a video off here. */
    const val SHORTS_LIMIT_SECONDS = 180.0

    /** Rough length of the file, so the repeat count means something. Reads
     * the effective ending, so a video's length includes its tail.
     *
     * A video's is exact: it comes from the same [VideoTimeline] (normalized
     * song, whole samples per step, truncated tail) that [VideoExport]
     * checks against the cap, so the Export button is never offered for a
     * video the renderer would then refuse as too long. */
    fun seconds(song: Song, options: ExportOptions): Double {
        if (options.format == ExportOptions.Format.VIDEO) return VideoTimeline(song, options).seconds
        var seconds = song.arrangementDuration * options.loopCount
        if (options.effectiveTailMode == ExportOptions.TailMode.RING_OUT) seconds += WavExport.tailSeconds(song)
        return seconds
    }

    /** Null for anything but a video that runs long. */
    fun warning(format: ExportOptions.Format, seconds: Double): String? {
        if (format != ExportOptions.Format.VIDEO) return null
        if (seconds > VideoExport.MAX_SECONDS) return "Too long for a video — ${Format.clock(VideoExport.MAX_SECONDS)} max."
        if (seconds > SHORTS_LIMIT_SECONDS) return "Reels and Shorts cut off at ${Format.clock(SHORTS_LIMIT_SECONDS)}."
        return null
    }
}

object ExportCopy {
    fun exportButton(format: ExportOptions.Format): String = "Export ${format.label}"

    /** What TalkBack reads for one segment of the format picker. The picker's
     * name rides on each segment rather than on the row around them, which
     * TalkBack would stop on by itself: iOS's segments sit in a tab group
     * labelled "Format" that VoiceOver names on the way in. */
    fun formatSegment(format: ExportOptions.Format): String = "Format, ${format.label}"

    /** A MIDI file is the arrangement once, so Repeats and Ending only shape a WAV. */
    fun hasRepeats(format: ExportOptions.Format): Boolean = when (format) {
        ExportOptions.Format.WAV, ExportOptions.Format.VIDEO -> true
        ExportOptions.Format.MIDI -> false
    }

    /** Only a WAV has an ending to choose: a video always rings out. */
    fun hasEnding(format: ExportOptions.Format): Boolean = format == ExportOptions.Format.WAV

    /** Only a video has a picture to style. */
    fun hasStyle(format: ExportOptions.Format): Boolean = format == ExportOptions.Format.VIDEO

    /** Whether the Export button is off because the file couldn't be made: a
     * video past [VideoExport.MAX_SECONDS] is refused before it renders. */
    fun blocksExport(format: ExportOptions.Format, seconds: Double): Boolean =
        format == ExportOptions.Format.VIDEO && seconds > VideoExport.MAX_SECONDS

    /** What TalkBack reads for one segment of the style picker; the picker's
     * name rides on each segment, as the format picker's does. */
    fun styleSegment(style: ExportOptions.VideoStyle): String = "Style, ${style.label}"

    fun loopCount(n: Int): String = "$n\u00d7"

    /** Rough length of the file, so the repeat count means something. */
    fun duration(song: Song, options: ExportOptions): String = Format.clock(ExportLength.seconds(song, options))

    /** The repeats readout, with a video's length warning after it. */
    fun repeatsFooter(song: Song, options: ExportOptions): String {
        val line = "The whole arrangement, ${Format.count(options.loopCount, "time")} \u2014 ${duration(song, options)}."
        val warning = ExportLength.warning(options.format, ExportLength.seconds(song, options)) ?: return line
        return "$line $warning"
    }

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

    /** The line under the progress bar. "Exporting", not "Rendering", since
     * it covers both formats; only a WAV reports progress, so only a WAV
     * gives a percentage, where a MIDI one would sit at 0%. Swift's
     * `Int(progress * 100)` truncates. Swift's `ExportProgressText`. */
    fun exporting(format: ExportOptions.Format, progress: Double): String = when (format) {
        ExportOptions.Format.WAV, ExportOptions.Format.VIDEO -> "Exporting\u2026 ${(progress * 100).toInt()}%"
        ExportOptions.Format.MIDI -> "Exporting\u2026"
    }

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
