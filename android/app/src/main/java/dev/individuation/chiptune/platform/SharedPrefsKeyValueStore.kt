package dev.individuation.chiptune.platform

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import dev.individuation.chiptune.core.store.KeyValueStore

/**
 * [KeyValueStore] over one SharedPreferences file, "chiptune" (iOS's
 * `UserDefaults`). String lists are stored as a JSON array string
 * ([StringListEncoding]) so order and duplicates survive; a value that
 * doesn't decode reads as absent. Writes use `apply()`: the system flushes
 * pending applies when the activity stops, before the process can be killed.
 */
class SharedPrefsKeyValueStore(context: Context) : KeyValueStore {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = try {
        prefs.getString(key, null)
    } catch (e: ClassCastException) {
        null
    }

    override fun putString(key: String, value: String?) {
        prefs.edit { if (value == null) remove(key) else putString(key, value) }
    }

    override fun getStringList(key: String): List<String>? = getString(key)?.let(StringListEncoding::decode)

    override fun putStringList(key: String, value: List<String>) {
        prefs.edit { putString(key, StringListEncoding.encode(value)) }
    }

    override fun getInt(key: String, default: Int): Int = try {
        prefs.getInt(key, default)
    } catch (e: ClassCastException) {
        default
    }

    override fun putInt(key: String, value: Int) {
        prefs.edit { putInt(key, value) }
    }

    companion object {
        const val FILE_NAME = "chiptune"
    }
}
