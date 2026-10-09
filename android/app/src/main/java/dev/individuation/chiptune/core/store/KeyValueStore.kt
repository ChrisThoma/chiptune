package dev.individuation.chiptune.core.store

/**
 * The handful of small values the app remembers between launches: which song
 * was open, which unreadable files the user has been told about, and the
 * review prompt's export counts. iOS keeps these in `UserDefaults`; the app
 * backs this with SharedPreferences (Phase 4), the tests with
 * [InMemoryKeyValueStore].
 */
interface KeyValueStore {
    fun getString(key: String): String?

    /** null removes the key. */
    fun putString(key: String, value: String?)

    fun getStringList(key: String): List<String>?

    fun putStringList(key: String, value: List<String>)

    fun getInt(key: String, default: Int = 0): Int

    fun putInt(key: String, value: Int)
}

/** A [KeyValueStore] that lives as long as the object does. */
class InMemoryKeyValueStore : KeyValueStore {
    private val values = HashMap<String, Any>()

    @Synchronized
    override fun getString(key: String): String? = values[key] as? String

    @Synchronized
    override fun putString(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }

    @Synchronized
    @Suppress("UNCHECKED_CAST")
    override fun getStringList(key: String): List<String>? = (values[key] as? List<String>)?.toList()

    @Synchronized
    override fun putStringList(key: String, value: List<String>) {
        values[key] = value.toList()
    }

    @Synchronized
    override fun getInt(key: String, default: Int): Int = values[key] as? Int ?: default

    @Synchronized
    override fun putInt(key: String, value: Int) {
        values[key] = value
    }
}
