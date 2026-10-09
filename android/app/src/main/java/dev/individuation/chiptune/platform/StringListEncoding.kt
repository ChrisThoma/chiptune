package dev.individuation.chiptune.platform

import org.json.JSONArray
import org.json.JSONException

/**
 * Ordered string lists as one SharedPreferences string. `putStringSet`
 * would lose order and duplicates; a JSON array keeps both. No android.*
 * imports, so the JVM tests cover it (org.json is on both classpaths).
 */
object StringListEncoding {
    fun encode(list: List<String>): String {
        val array = JSONArray()
        for (s in list) array.put(s)
        return array.toString()
    }

    /** null for anything that isn't a JSON array of strings. */
    fun decode(encoded: String): List<String>? = try {
        val array = JSONArray(encoded)
        val out = ArrayList<String>(array.length())
        for (i in 0 until array.length()) {
            val value = array.get(i) as? String ?: return null
            out.add(value)
        }
        out
    } catch (e: JSONException) {
        null
    }
}
