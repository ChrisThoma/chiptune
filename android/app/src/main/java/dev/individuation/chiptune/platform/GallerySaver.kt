package dev.individuation.chiptune.platform

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.File
import java.io.IOException

/**
 * Adds a finished video to the Gallery under [ExportSaveRoute.GALLERY_FOLDER].
 * Android 10 and later let an app add its own media to the shared folders
 * without a storage permission. The entry is pending while it is written, so
 * the Gallery never shows half a video, and removed again if the copy fails.
 * Call off the main thread. Throws what the write threw.
 */
object GallerySaver {
    @RequiresApi(Build.VERSION_CODES.Q)
    fun saveVideo(context: Context, file: File, mimeType: String) {
        val resolver = context.contentResolver
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Video.Media.MIME_TYPE, mimeType)
            put(MediaStore.Video.Media.RELATIVE_PATH, ExportSaveRoute.GALLERY_FOLDER)
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("The Gallery refused the video")
        try {
            val out = resolver.openOutputStream(uri, "w") ?: throw IOException("no stream")
            out.use { o -> file.inputStream().use { it.copyTo(o) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
    }
}
