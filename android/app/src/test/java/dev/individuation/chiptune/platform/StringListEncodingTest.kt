package dev.individuation.chiptune.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** SharedPreferences has no ordered list type, so string lists are stored
 * as one encoded string. Order, duplicates and awkward characters survive. */
class StringListEncodingTest {

    @Test fun roundTripsInOrder() {
        val list = listOf("b.json", "a.json", "c.json", "a.json")
        assertEquals(list, StringListEncoding.decode(StringListEncoding.encode(list)))
    }

    @Test fun roundTripsEmpty() {
        assertEquals(emptyList<String>(), StringListEncoding.decode(StringListEncoding.encode(emptyList())))
    }

    @Test fun roundTripsAwkwardCharacters() {
        val list = listOf("", "comma,here", "quote\"here", "back\\slash", "new\nline", "[\"x\"]", "caf\u00e9 \ud83c\udfb5")
        assertEquals(list, StringListEncoding.decode(StringListEncoding.encode(list)))
    }

    @Test fun garbageDecodesToNull() {
        assertNull(StringListEncoding.decode("not json"))
        assertNull(StringListEncoding.decode("{\"a\":1}"))
        assertNull(StringListEncoding.decode("[1, 2]"))
    }
}
