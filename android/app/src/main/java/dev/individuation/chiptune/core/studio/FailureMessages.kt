package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.model.NameCap
import dev.individuation.chiptune.core.model.SongDecodeException
import dev.individuation.chiptune.core.text.SwiftText
import java.nio.file.AccessDeniedException

/*
 * Alert wording, ported word for word from `ShareFailureMessage.swift` and
 * `AudioFailureMessage.swift`. The system's own text names internal files (a
 * UUID) and folders, so it is never pasted; only a permission or disk-space
 * cause is kept, as one short sentence.
 */

/** Save failed, Export failed, and the reason shared by every write alert.
 * "Try again." follows every cause but permission, which retrying can't fix. */
object WriteFailureMessage {
    const val NAME_LIMIT = 30

    enum class Cause { PERMISSION, SPACE, OTHER }

    /** "Couldn't save \u201CName\u201D. <reason>[ Try again.]" */
    fun save(name: String, error: Throwable): String =
        "Couldn't save ${shown(name)}. ${reasonAndAdvice(error, "song file")}"

    /** "Couldn't export \u201CName\u201D. <reason>[ Try again.]" */
    fun export(name: String, error: Throwable): String = export(name, error, ExportOptions.Format.WAV.fileNoun)

    /** The three-argument form names the file; the two-argument one is the WAV
     * wrapper that keeps the shape the three alert builders share. */
    fun export(name: String, error: Throwable, file: String): String =
        "Couldn't export ${shown(name)}. ${reasonAndAdvice(error, file)}"

    /** "Couldn't save \u201CName\u201D. <reason>[ Try again.]" for a finished
     * export that "Save to device" couldn't copy out: the export itself
     * worked, so the alert says save. */
    fun saveExport(name: String, error: Throwable, file: String): String =
        "Couldn't save ${shown(name)}. ${reasonAndAdvice(error, file)}"

    /** "Couldn't export \u201CName\u201D. <reason>", knowing whether the app
     * left the screen while it rendered. Port of iOS's
     * `export(name:error:format:leftForeground:)`. A video's encoder and
     * muxer belong to a process Android may freeze, reclaim the codec from
     * or kill once nothing of it is on screen, so a video that failed for no
     * named reason after the app left the screen says to stay in the app:
     * trying again the same way would fail the same way. A named cause
     * (permission, space) is still named. A WAV renders on the CPU alone and
     * isn't affected. */
    fun export(name: String, error: Throwable, format: ExportOptions.Format, leftForeground: Boolean): String {
        if (format == ExportOptions.Format.VIDEO && leftForeground && cause(error) == Cause.OTHER) {
            return "Couldn't export ${shown(name)}. Keep Chiptune open while the video renders."
        }
        return export(name, error, format.fileNoun)
    }

    /** What a file of this extension is called in an alert: an export is its
     * format's file, and anything else is a song file, the one other kind of
     * file the app hands over. Named from the file that was offered rather
     * than the sheet's current format, which may have been switched since the
     * export finished. Swift's `fileNoun(forExtension:)` is the same rule. */
    fun fileNoun(extension: String): String = ExportOptions.Format.fromExtension(extension)?.fileNoun ?: "song file"

    /** The song's name in curly quotes, clipped with an ellipsis past
     * [NAME_LIMIT] characters, or "this song" when it's blank. */
    fun shown(name: String): String {
        val trimmed = SwiftText.trimWhitespaceAndNewlines(name)
        return when {
            trimmed.isEmpty() -> "this song"
            dev.individuation.chiptune.core.text.Graphemes.count(trimmed) > NAME_LIMIT ->
                LEFT_QUOTE + SwiftText.trimWhitespaces(NameCap.clip(trimmed, NAME_LIMIT)) + ELLIPSIS + RIGHT_QUOTE
            else -> LEFT_QUOTE + trimmed + RIGHT_QUOTE
        }
    }

    fun reason(error: Throwable, file: String): String = when (cause(error)) {
        Cause.PERMISSION -> "The app doesn't have permission to write the $file."
        Cause.SPACE -> "There isn't enough free space to write the $file."
        Cause.OTHER -> "The $file couldn't be written."
    }

    /** The reason, then "Try again." unless the cause is permission. */
    fun reasonAndAdvice(error: Throwable, file: String): String {
        val reason = reason(error, file)
        return if (cause(error) == Cause.PERMISSION) reason else "$reason Try again."
    }

    /**
     * Java and Android report a refused or full write in several shapes:
     * [AccessDeniedException] from java.nio, [SecurityException] from a
     * content provider, and an `IOException` or `android.system.ErrnoException`
     * (which core can't import) whose message carries the errno name. An
     * unrecognized error is looked under, the way Swift looks under a Cocoa
     * error for its POSIX cause.
     */
    fun cause(error: Throwable): Cause {
        var current: Throwable? = error
        val seen = HashSet<Throwable>()
        while (current != null && seen.add(current)) {
            classify(current)?.let { return it }
            current = current.cause
        }
        return Cause.OTHER
    }

    private fun classify(error: Throwable): Cause? {
        if (error is AccessDeniedException || error is SecurityException) return Cause.PERMISSION
        val message = error.message ?: return null
        if (PERMISSION_MARKERS.any { message.contains(it) }) return Cause.PERMISSION
        if (SPACE_MARKERS.any { message.contains(it) }) return Cause.SPACE
        return null
    }

    private val PERMISSION_MARKERS = listOf("EACCES", "EPERM", "Permission denied", "Operation not permitted")
    private val SPACE_MARKERS = listOf("ENOSPC", "No space left")


    internal const val LEFT_QUOTE = "\u201C"
    internal const val RIGHT_QUOTE = "\u201D"
    internal const val ELLIPSIS = "\u2026"
}

/** The "Share failed" alert's words. */
object ShareFailureMessage {
    fun songFile(name: String, error: Throwable): String =
        "Couldn't prepare ${WriteFailureMessage.shown(name)} to share. " +
            WriteFailureMessage.reasonAndAdvice(error, "song file")

    /** The share sheet itself failed; whichever app the user picked owns the
     * error, so no cause is named. */
    fun sheet(file: String): String = "Couldn't share the $file. Try again."
}

/** The "Delete failed" alert's words: only permission is worth naming,
 * since running out of space doesn't stop a delete. */
object DeleteFailureMessage {
    fun song(name: String, error: Throwable): String {
        val shown = WriteFailureMessage.shown(name)
        return when (WriteFailureMessage.cause(error)) {
            WriteFailureMessage.Cause.PERMISSION ->
                "Couldn't delete $shown. The app doesn't have permission to delete the song file."
            else -> "Couldn't delete $shown. Try again."
        }
    }
}

/** The "Import failed" alert's words. */
object ImportFailureMessage {
    /** The picked, opened or dropped file didn't become a song. */
    fun file(error: Throwable): String {
        val lead = "Couldn't import the file."
        if (error is SongDecodeException) return "$lead It isn't a Chiptune song, or it's damaged."
        if (WriteFailureMessage.cause(error) == WriteFailureMessage.Cause.PERMISSION) {
            return "$lead The app doesn't have permission to read it."
        }
        return "$lead It couldn't be read. Try again."
    }

    /** The song was read but couldn't be written into the library. */
    fun save(name: String, error: Throwable): String =
        "Couldn't import ${WriteFailureMessage.shown(name)}. ${WriteFailureMessage.reasonAndAdvice(error, "song file")}"
}

/** The "Audio unavailable" alert's words. Only a busy output is named --
 * audio focus refused, usually by a call -- because that's the one the user
 * can do something about. */
object AudioFailureMessage {
    fun start(error: Throwable?): String =
        if (error is AudioFocusDeniedException) {
            "Another app or a call is using audio. Try again when it's finished."
        } else {
            "Couldn't start audio. Try again."
        }
}
