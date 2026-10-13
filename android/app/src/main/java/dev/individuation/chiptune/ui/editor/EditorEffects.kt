package dev.individuation.chiptune.ui.editor

import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.android.play.core.review.ReviewManagerFactory
import dev.individuation.chiptune.ChiptuneApp
import dev.individuation.chiptune.core.studio.ShareFailureMessage
import dev.individuation.chiptune.core.studio.ShareOutcome
import dev.individuation.chiptune.core.studio.WriteFailureMessage
import dev.individuation.chiptune.platform.ShareChosenReceiver
import dev.individuation.chiptune.platform.ShareResult
import dev.individuation.chiptune.platform.SongImporter
import java.io.File
import java.util.concurrent.Executors

/**
 * What the editor asks the platform to do: the file pickers, share sheets
 * and links the iOS views get from SwiftUI. An interface so tests and
 * previews can stand in for [AndroidEditorEffects].
 */
interface EditorEffects {
    /** "Import song..." in the menu and the library's Add: `OpenDocument`,
     * then `studio.importSong`. */
    fun importSong()

    /** A `.chipsong` (`application/json`), a WAV (`audio/wav`) or a MIDI file (`audio/midi`) to share,
     * through a FileProvider with the MIME type set explicitly. [onFinished]
     * runs once with true when a share target was picked, false when the
     * chooser was backed out of or couldn't open; the review prompt reads it. */
    fun shareFile(file: File, mimeType: String, onFinished: (Boolean) -> Unit = {})

    /** Opens a web link in the browser. */
    fun openUrl(url: String)

    /** "Save to device" on a finished export: `CreateDocument` of [mimeType]
     * named [suggestedName], then [file] is copied into it. */
    fun saveToDevice(file: File, suggestedName: String, mimeType: String)

    /** The review prompt, once a share after a milestone export went through
     * (`ReviewPromptTracker.shareDismissed` said so): Play's in-app review
     * flow, which decides itself whether anything shows. */
    fun requestReview()

    /** Puts [text] on the clipboard (the build stamp row). */
    fun copyToClipboard(label: String, text: String)

    companion object {
        const val SONG_MIME = "application/json"
        const val WAV_MIME = "audio/wav"
        const val MIDI_MIME = "audio/midi"
        const val SUPPORT_URL = "https://individuation.dev/contact/"

        /** What to offer a file as, by its extension: an export is its format's
         * type, anything else a song file. Read off the file rather than the
         * sheet's format, which may have been switched since it was written. */
        fun mimeTypeFor(file: File): String = when (file.extension.lowercase()) {
            "wav" -> WAV_MIME
            "mid" -> MIDI_MIME
            else -> SONG_MIME
        }
    }
}

/** The app's [EditorEffects]. */
class AndroidEditorEffects(private val context: Context) : EditorEffects {
    private val activity: ComponentActivity? =
        generateSequence(context) { (it as? ContextWrapper)?.baseContext }.filterIsInstance<ComponentActivity>().firstOrNull()
    private val app: ChiptuneApp? = context.applicationContext as? ChiptuneApp
    private val main = Handler(Looper.getMainLooper())

    override fun importSong() {
        launch(ActivityResultContracts.OpenDocument(), arrayOf("application/json", "application/octet-stream")) { uri ->
            val studio = app?.studio
            if (uri != null && studio != null) SongImporter.import(context, studio, uri)
        }
    }

    override fun shareFile(file: File, mimeType: String, onFinished: (Boolean) -> Unit) {
        val host = activity
        if (host == null) {
            onFinished(false)
            return
        }
        val uri = try {
            FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        } catch (e: IllegalArgumentException) {
            failShare(file, onFinished)
            return
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val callback = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ShareChosenReceiver::class.java).setPackage(context.packageName),
            // Mutable: the system adds EXTRA_CHOSEN_COMPONENT to it.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        var finished = false
        fun finish(handedOff: Boolean) {
            if (finished) return
            finished = true
            ShareChosenReceiver.listener = null
            onFinished(handedOff)
        }
        ShareChosenReceiver.listener = { chosen -> finish(ShareResult.outcome(chosen) == ShareOutcome.COMPLETED) }
        try {
            host.startActivity(Intent.createChooser(send, null, callback.intentSender))
        } catch (e: ActivityNotFoundException) {
            ShareChosenReceiver.listener = null
            failShare(file, onFinished)
            return
        }
        // Backing out of the chooser sends nothing, so when the app is
        // foregrounded again with no pick reported, that was a cancel.
        host.lifecycle.addObserver(object : DefaultLifecycleObserver {
            private var left = false
            override fun onPause(owner: LifecycleOwner) {
                left = true
            }

            override fun onResume(owner: LifecycleOwner) {
                if (!left) return
                owner.lifecycle.removeObserver(this)
                main.postDelayed({ finish(false) }, CHOOSER_RESULT_GRACE_MS)
            }
        })
    }

    private fun failShare(file: File, onFinished: (Boolean) -> Unit) {
        app?.studio?.shareError = ShareFailureMessage.sheet(WriteFailureMessage.fileNoun(file.extension))
        onFinished(false)
    }

    override fun saveToDevice(file: File, suggestedName: String, mimeType: String) {
        launch(ActivityResultContracts.CreateDocument(mimeType), suggestedName) { uri ->
            if (uri != null) copyInto(file, uri)
        }
    }

    private fun copyInto(file: File, uri: Uri) {
        val resolver = context.contentResolver
        saver.execute {
            val failure = try {
                val out = resolver.openOutputStream(uri, "wt") ?: throw java.io.IOException("no stream")
                out.use { o -> file.inputStream().use { it.copyTo(o) } }
                null
            } catch (e: Exception) {
                e
            }
            main.post {
                val text = if (failure == null) "Saved" else WriteFailureMessage.export(file.nameWithoutExtension, failure, WriteFailureMessage.fileNoun(file.extension))
                Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun requestReview() {
        val host: Activity = activity ?: return
        val manager = ReviewManagerFactory.create(context)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            // Play decides whether anything shows; with no Play it never completes.
            if (request.isSuccessful) manager.launchReviewFlow(host, request.result)
        }
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

    /** One-shot launch through the activity's registry, which outlives the
     * composition that asked (the picker can take as long as it likes). */
    private fun <I, O> launch(contract: ActivityResultContract<I, O>, input: I, onResult: (O) -> Unit) {
        val host = activity ?: return
        var launcher: ActivityResultLauncher<I>? = null
        launcher = host.activityResultRegistry.register("chiptune-effect-${nextKey++}", contract) { result ->
            launcher?.unregister()
            onResult(result)
        }
        launcher.launch(input)
    }

    private companion object {
        const val CHOOSER_RESULT_GRACE_MS = 700L
        var nextKey = 0
        val saver = Executors.newSingleThreadExecutor { r -> Thread(r, "chiptune-save") }
    }
}
