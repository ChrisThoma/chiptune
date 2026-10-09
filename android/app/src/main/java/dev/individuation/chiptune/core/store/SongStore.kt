package dev.individuation.chiptune.core.store

import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongClock
import dev.individuation.chiptune.core.model.SongDocument
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/** What a library load found: the songs, newest first, and the file names
 * that could not be read. */
data class SongLibrary(
    val songs: List<Song>,
    val unreadable: List<String>,
    /** Each unreadable file's name and modification time, for remembering
     * which ones the user has already been told about. */
    val unreadableVersions: Set<String> = emptySet(),
)

/** Wording for the "some song files could not be read" alert. */
object UnreadableSongs {
    const val TITLE = "Load failed"

    fun message(count: Int): String =
        if (count == 1) {
            "1 saved song couldn't be read, so it's left out of your library. It may be damaged."
        } else {
            "$count saved songs couldn't be read, so they're left out of your library. They may be damaged."
        }
}

/**
 * Where songs are read and written (port of `SongStore.swift`). Autosave is
 * the app's whole persistence story -- there is no Save button -- so [save]
 * and [delete] throw rather than failing quietly.
 */
interface SongStore {
    /** Stamps `modified`, writes the song, and with [makeCurrent] records it
     * as the one to reopen on launch. */
    fun save(song: Song, makeCurrent: Boolean = false)

    /** A file that is already gone is the outcome delete wanted: no throw. */
    fun delete(song: Song)

    fun load(id: UUID): Song?

    /** The song open when the app last ran, else the most recently modified. */
    fun loadLast(): Song?

    /** Every readable song, newest first. */
    fun loadAll(): List<Song> = loadLibrary().songs

    fun loadLibrary(): SongLibrary

    /** How many of [library]'s unreadable files haven't been reported on this
     * launch or an earlier one; records them all as reported. */
    fun claimUnreported(library: SongLibrary): Int

    companion object {
        const val CURRENT_KEY = "currentSongID"
        const val REPORTED_UNREADABLE_KEY = "reportedUnreadableSongFiles"
    }
}

/** Shared by both stores: remembers only files still unreadable, so the
 * record can't grow without end. */
private fun claim(prefs: KeyValueStore, library: SongLibrary): Int {
    val reported = (prefs.getStringList(SongStore.REPORTED_UNREADABLE_KEY) ?: emptyList()).toSet()
    val current = library.unreadableVersions
    if (current != reported) prefs.putStringList(SongStore.REPORTED_UNREADABLE_KEY, current.sorted())
    return (current - reported).size
}

/** A clock that never repeats or goes backwards, so two saves in the same
 * millisecond still sort newest-first. */
private class MonotonicStamp(private val clock: () -> Double) {
    private var last = Double.NEGATIVE_INFINITY

    @Synchronized
    fun next(): Double {
        val now = clock()
        last = if (now > last) now else last + 0.001
        return last
    }
}

/**
 * Songs as `<directory>/<UPPERCASE-UUID>.json`, the same name iOS gives them.
 * Writes are atomic (a temp file in the same folder, then a rename), so a
 * crash mid-save leaves the previous version whole. The directory is created
 * lazily, so constructing a store never touches disk.
 */
class FileSongStore(
    private val directory: File,
    private val prefs: KeyValueStore,
    clock: () -> Double = SongClock::now,
) : SongStore {

    private val stamp = MonotonicStamp(clock)

    private fun file(id: UUID): File = File(directory, "${id.toString().uppercase()}.json")

    private fun ensureDirectory() {
        // Best effort, like Swift's `try? createDirectory`: if it fails, the
        // write below fails with the reason the user needs to hear.
        if (!directory.isDirectory) runCatching { Files.createDirectories(directory.toPath()) }
    }

    override fun save(song: Song, makeCurrent: Boolean) {
        val stamped = song.copy(modified = stamp.next())
        val bytes = SongDocument.encodeToBytes(stamped)
        ensureDirectory()
        writeAtomically(file(song.id), bytes)
        if (makeCurrent) prefs.putString(SongStore.CURRENT_KEY, song.id.toString().uppercase())
    }

    override fun delete(song: Song) {
        Files.deleteIfExists(file(song.id).toPath())
        val current = prefs.getString(SongStore.CURRENT_KEY)
        if (current != null && current.equals(song.id.toString(), ignoreCase = true)) {
            prefs.putString(SongStore.CURRENT_KEY, null)
        }
    }

    override fun load(id: UUID): Song? = read(file(id))

    private fun read(file: File): Song? = try {
        SongDocument.decode(file.readBytes())
    } catch (e: Exception) {
        null
    }

    override fun loadLast(): Song? {
        val raw = prefs.getString(SongStore.CURRENT_KEY)
        val id = raw?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        if (id != null) load(id)?.let { return it }
        return loadAll().firstOrNull()
    }

    override fun loadLibrary(): SongLibrary {
        val files = directory.listFiles()?.filter { it.isFile && it.extension == "json" }?.sortedBy { it.name }
            ?: emptyList()
        val songs = ArrayList<Song>()
        val unreadable = ArrayList<String>()
        val versions = HashSet<String>()
        for (file in files) {
            val song = read(file)
            if (song == null) {
                unreadable.add(file.name)
                versions.add("${file.name}@${file.lastModified()}")
            } else {
                songs.add(song)
            }
        }
        return SongLibrary(songs.sortedByDescending { it.modified }, unreadable.sorted(), versions)
    }

    override fun claimUnreported(library: SongLibrary): Int = claim(prefs, library)

    companion object {
        const val CURRENT_KEY = SongStore.CURRENT_KEY
        const val REPORTED_UNREADABLE_KEY = SongStore.REPORTED_UNREADABLE_KEY

        /** Writes [bytes] beside [target] and renames it into place. */
        internal fun writeAtomically(target: File, bytes: ByteArray) {
            val dir = target.absoluteFile.parentFile ?: throw IOException("no folder for ${target.name}")
            val temp = Files.createTempFile(dir.toPath(), ".write-", ".tmp")
            try {
                Files.write(temp, bytes)
                try {
                    Files.move(temp, target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                } catch (e: java.nio.file.AtomicMoveNotSupportedException) {
                    Files.move(temp, target.toPath(), StandardCopyOption.REPLACE_EXISTING)
                }
            } finally {
                Files.deleteIfExists(temp)
            }
        }
    }
}

/**
 * The same contract in memory, for tests and previews. [saveError] and
 * [deleteError] make the next writes fail the way a full or locked disk would;
 * [unreadable] stands in for files that would not decode.
 */
class InMemorySongStore(
    private val prefs: KeyValueStore = InMemoryKeyValueStore(),
    clock: () -> Double = SongClock::now,
) : SongStore {
    var saveError: Throwable? = null
    var deleteError: Throwable? = null
    val unreadable: MutableList<String> = ArrayList()

    private val stamp = MonotonicStamp(clock)
    private val songs = LinkedHashMap<UUID, Song>()

    @Synchronized
    override fun save(song: Song, makeCurrent: Boolean) {
        saveError?.let { throw it }
        songs[song.id] = song.normalized().copy(modified = stamp.next())
        if (makeCurrent) prefs.putString(SongStore.CURRENT_KEY, song.id.toString().uppercase())
    }

    @Synchronized
    override fun delete(song: Song) {
        deleteError?.let { throw it }
        songs.remove(song.id)
        val current = prefs.getString(SongStore.CURRENT_KEY)
        if (current != null && current.equals(song.id.toString(), ignoreCase = true)) {
            prefs.putString(SongStore.CURRENT_KEY, null)
        }
    }

    @Synchronized
    override fun load(id: UUID): Song? = songs[id]

    override fun loadLast(): Song? {
        val id = prefs.getString(SongStore.CURRENT_KEY)?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        if (id != null) load(id)?.let { return it }
        return loadAll().firstOrNull()
    }

    @Synchronized
    override fun loadLibrary(): SongLibrary =
        SongLibrary(songs.values.sortedByDescending { it.modified }, unreadable.sorted(), unreadable.map { "$it@0" }.toSet())

    override fun claimUnreported(library: SongLibrary): Int = claim(prefs, library)
}
