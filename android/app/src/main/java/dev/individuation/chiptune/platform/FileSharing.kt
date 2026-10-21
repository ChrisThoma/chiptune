package dev.individuation.chiptune.platform

import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.studio.ShareOutcome
import java.io.File

/**
 * Pure rules for songs coming in and files going out. No android.* here, so
 * the JVM tests cover them; the Android glue only feeds in strings.
 */
object IncomingSongIntent {
    const val ACTION_VIEW = "android.intent.action.VIEW"
    const val ACTION_SEND = "android.intent.action.SEND"

    enum class Reason { WRONG_ACTION, NO_URI, WRONG_TYPE }

    sealed interface Result {
        data class Accepted(val uri: String) : Result
        data class Rejected(val reason: Reason) : Result
    }

    private val acceptedTypes = setOf("application/json", "application/octet-stream")

    /** VIEW carries the file in the data URI, SEND in EXTRA_STREAM. A null
     * [type] is fine (file links often have none); a known wrong one isn't. */
    fun parse(action: String?, dataUri: String?, streamUri: String?, type: String?): Result {
        val uri = when (action) {
            ACTION_VIEW -> dataUri
            ACTION_SEND -> streamUri
            else -> return Result.Rejected(Reason.WRONG_ACTION)
        }
        if (uri.isNullOrBlank()) return Result.Rejected(Reason.NO_URI)
        if (type != null && type.lowercase() !in acceptedTypes) return Result.Rejected(Reason.WRONG_TYPE)
        return Result.Accepted(uri)
    }
}

object SongFileAcceptance {
    /** The biggest song file read; a real song is a few kilobytes. */
    const val MAX_BYTES = 10L * 1024 * 1024

    fun fitsSizeCap(bytes: Long): Boolean = bytes <= MAX_BYTES

    /** `.chipsong` and `.json` by name; with no usable name, `application/json` by type. */
    fun accepts(displayName: String?, mimeType: String?): Boolean {
        val name = displayName?.trim().orEmpty()
        if (name.isEmpty()) return mimeType.equals("application/json", ignoreCase = true)
        val lower = name.lowercase()
        return lower.endsWith(".chipsong") || lower.endsWith(".json")
    }

    /** Drag-and-drop clip descriptions worth looking inside. */
    fun acceptsDropMime(mimeType: String): Boolean = mimeType.lowercase() in
        setOf("application/json", "application/octet-stream", "text/uri-list")
}

object ShareResult {
    /** The chooser reports the component the user picked; no pick is a back-out. */
    fun outcome(chosenComponent: String?): ShareOutcome =
        if (chosenComponent.isNullOrEmpty()) ShareOutcome.CANCELED else ShareOutcome.COMPLETED
}

/** Where "Save to device" puts a finished export. A video goes into the
 * Gallery's Movies/Chiptune, as iOS's Save Video goes to Photos; Android 10
 * and later let an app add its own media there with no permission. Before
 * that it would need storage permission, which the app doesn't ask for, so
 * those, and every WAV and MIDI file, go through the system file picker. */
object ExportSaveRoute {
    enum class Route { GALLERY, PICKER }

    /** `Build.VERSION_CODES.Q`, where scoped MediaStore writes begin. */
    const val GALLERY_MIN_SDK = 29

    const val GALLERY_FOLDER = "Movies/Chiptune"
    const val SAVED_TO_GALLERY = "Saved to $GALLERY_FOLDER."

    fun route(format: ExportOptions.Format?, sdk: Int): Route =
        if (format == ExportOptions.Format.VIDEO && sdk >= GALLERY_MIN_SDK) Route.GALLERY else Route.PICKER
}

/** The cache subfolders `res/xml/file_paths.xml` exposes; keep the two in step. */
object ShareRoots {
    const val SHARE = "share"
    const val EXPORT = "export"

    fun covers(cacheDir: File, file: File): Boolean {
        val cache = cacheDir.canonicalFile
        val target = file.canonicalFile
        return listOf(SHARE, EXPORT).any { root ->
            val rootDir = File(cache, root)
            target.path.startsWith(rootDir.path + File.separator)
        }
    }
}
