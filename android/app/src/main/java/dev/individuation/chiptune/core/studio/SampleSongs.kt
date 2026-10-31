package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import dev.individuation.chiptune.core.store.KeyValueStore
import dev.individuation.chiptune.core.store.SongLibrary
import dev.individuation.chiptune.core.store.SongStore

/**
 * The example songs shipped with the app (the `.chipsong` files iOS bundles
 * from `Sources/Resources/Samples`). Each goes into the library once: on a
 * first launch beside First Loop, and on an existing install the first time
 * a version that ships it runs. [prefs] remembers which ids have been seeded,
 * so a sample the user deletes stays deleted and a sample added later still
 * arrives once.
 *
 * [source] hands over the raw files; the app reads them from its assets. A
 * file that won't decode is skipped quietly, as is a [source] that throws.
 */
class SampleSongs(
    private val prefs: KeyValueStore,
    private val source: () -> List<ByteArray>,
) {
    /**
     * Saves every sample not seeded before, without making any current.
     * Never writes over a file that already holds a sample's id. [open] is
     * the song the launch reopens: unless the key already names it (it may
     * be unset, or name a song that's gone), it is marked now, or the newer samples would take over the next launch.
     */
    internal fun seed(store: SongStore, library: SongLibrary, open: Song?) {
        val files = try {
            source()
        } catch (_: Exception) {
            return
        }
        val seeded = (prefs.getStringList(SEEDED_KEY) ?: emptyList()).toMutableList()
        val existing = library.songs.map { it.id }.toSet()
        val unreadable = library.unreadable.toSet()
        var added = false
        for (bytes in files) {
            val sample = try {
                SongDocument.decode(bytes).normalized()
            } catch (_: Exception) {
                continue
            }
            val key = sample.id.toString().uppercase()
            if (seeded.any { it.equals(key, ignoreCase = true) }) continue
            // Already there (or there but unreadable): count it as seeded and
            // leave the file alone.
            val present = sample.id in existing || "$key.json" in unreadable
            if (!present) {
                try {
                    store.save(sample, makeCurrent = false)
                    added = true
                } catch (_: Exception) {
                    // Try again next launch.
                    continue
                }
            }
            seeded.add(key)
        }
        prefs.putStringList(SEEDED_KEY, seeded)
        if (added && open != null &&
            !open.id.toString().equals(prefs.getString(SongStore.CURRENT_KEY), ignoreCase = true)
        ) {
            prefs.putString(SongStore.CURRENT_KEY, open.id.toString().uppercase())
        }
    }

    companion object {
        /** The uppercase ids of every sample already put in the library. */
        const val SEEDED_KEY = "seededSampleSongIDs"
    }
}
