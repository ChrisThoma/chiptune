package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import dev.individuation.chiptune.core.store.FileSongStore
import java.io.File
import java.nio.file.Files

/**
 * Writes a song out as a `.chipsong` ready for a share sheet (the file half
 * of `SongDocument.write`): `<directory>/share-<UUID>/<safeName>.chipsong`.
 * The per-song folder keeps two same-named songs from overwriting each other
 * while the shared file keeps a readable name. The app passes its cache dir.
 */
class SongShareWriter(private val directory: File) {
    fun write(song: Song): File {
        val bytes = SongDocument.encodeToBytes(song)
        val folder = File(directory, "share-${song.id.toString().uppercase()}")
        Files.createDirectories(folder.toPath())
        val target = File(folder, SongDocument.fileName(song))
        FileSongStore.writeAtomically(target, bytes)
        return target
    }
}

/**
 * A file dropped into the app, decoded or not. Drops arrive as bytes, and
 * decoding never throws: the failure is carried so the drop can say what the
 * Import picker says about the same file.
 */
class SongDrop(bytes: ByteArray) {
    val result: Result<Song> = runCatching { SongDocument.decode(bytes) }
}
