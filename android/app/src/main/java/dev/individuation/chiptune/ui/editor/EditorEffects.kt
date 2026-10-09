package dev.individuation.chiptune.ui.editor

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.core.net.toUri
import java.io.File

/**
 * What the editor asks the platform to do: the file pickers, share sheets
 * and links the iOS views get from SwiftUI. An interface so Phase 7 can
 * replace [AndroidEditorEffects]'s placeholders (the SAF importer, the
 * FileProvider share) without touching the editor.
 */
interface EditorEffects {
    /** "Import song..." in the menu (and the library's Add, in 5B). Phase 7:
     * `OpenDocument`, then `studio.importSong { bytes }`. */
    fun importSong()

    /** A `.chipsong` (`application/json`) or a WAV (`audio/wav`) to share. Phase
     * 7: `ACTION_SEND` through a FileProvider with the MIME type set
     * explicitly. [onFinished] runs when the share is handed off (true) or
     * fails (false); the review prompt reads it. */
    fun shareFile(file: File, mimeType: String, onFinished: (Boolean) -> Unit = {})

    /** Opens a web link in the browser. */
    fun openUrl(url: String)

    /** Puts [text] on the clipboard (the build stamp row). */
    fun copyToClipboard(label: String, text: String)

    companion object {
        const val SONG_MIME = "application/json"
        const val WAV_MIME = "audio/wav"
        const val SUPPORT_URL = "https://individuation.dev/contact/"
    }
}

/** The app's [EditorEffects]. Links and the clipboard are real; import and
 * share are placeholders until Phase 7 wires the SAF and the FileProvider. */
class AndroidEditorEffects(private val context: Context) : EditorEffects {
    override fun importSong() {
        // TODO(Phase 7): launch OpenDocument(application/json, application/octet-stream).
        Toast.makeText(context, "Importing songs arrives in a later build.", Toast.LENGTH_SHORT).show()
    }

    override fun shareFile(file: File, mimeType: String, onFinished: (Boolean) -> Unit) {
        // TODO(Phase 7): ACTION_SEND through a FileProvider, MIME set explicitly.
        Toast.makeText(context, "Sharing arrives in a later build.", Toast.LENGTH_SHORT).show()
        onFinished(false)
    }

    override fun openUrl(url: String) {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(context, url, Toast.LENGTH_LONG).show()
        }
    }

    override fun copyToClipboard(label: String, text: String) {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }
}
