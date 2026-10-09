package dev.individuation.chiptune.platform

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import dev.individuation.chiptune.core.model.SongDecodeException
import dev.individuation.chiptune.core.studio.Studio
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Reads a picked, opened or shared song file, applying the name rule and the size cap. */
object SongImporter {
    /** Imports [uri] into [studio]; every failure lands in `studio.importError`. */
    fun import(context: Context, studio: Studio, uri: Uri) {
        studio.importSong { readSong(context.contentResolver, uri, checkName = true) }
    }

    /** The bytes of [uri]. Songs are a few kilobytes, so this reads on the
     * caller's thread, but never more than [SongFileAcceptance.MAX_BYTES]. */
    fun readSong(resolver: ContentResolver, uri: Uri, checkName: Boolean): ByteArray {
        var name: String? = null
        var size = -1L
        try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val s = c.getColumnIndex(OpenableColumns.SIZE)
                    if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                    if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                }
            }
        } catch (e: SecurityException) {
            throw e
        } catch (e: RuntimeException) {
            // Providers without OpenableColumns: fall back to the type and a bounded read.
        }
        if (name == null && uri.scheme == "file") name = uri.lastPathSegment
        if (checkName && !SongFileAcceptance.accepts(name, resolver.getType(uri))) {
            throw SongDecodeException("not a song file")
        }
        if (size >= 0 && !SongFileAcceptance.fitsSizeCap(size)) throw SongDecodeException("file too large")
        val stream = resolver.openInputStream(uri) ?: throw IOException("no stream")
        stream.use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                if (!SongFileAcceptance.fitsSizeCap(out.size().toLong())) throw SongDecodeException("file too large")
            }
            return out.toByteArray()
        }
    }
}

/** A song URI that arrived (VIEW/SEND) and waits for the Studio, as iOS's `pendingImport`. */
class IncomingImports {
    private val mutablePending = MutableStateFlow<Uri?>(null)
    val pending: StateFlow<Uri?> = mutablePending.asStateFlow()

    fun offer(uri: Uri) {
        mutablePending.value = uri
    }

    fun consume(uri: Uri) {
        mutablePending.compareAndSet(uri, null)
    }
}
