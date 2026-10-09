package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The tokenizer under the codec. It accepts what Swift's `JSONDecoder`
 * accepts — RFC 8259 plus a trailing comma, a UTF-8 BOM, and the first of a
 * repeated key — and nothing else. The shared fixtures pin the same choices
 * against iOS. */
class StrictJsonTest {

    private fun rejects(text: String) {
        try {
            StrictJson.parse(text)
            fail("parsed: $text")
        } catch (e: SongDecodeException) {
            // expected
        }
    }

    @Test fun parsesEveryKindOfValue() {
        val v = StrictJson.parse("""{"a": [1, -2.5e3, "x\n\u00e9\ud83c\udfb5", true, false, null], "b": {}}""")
        val obj = v as JsonValue.Obj
        val arr = obj["a"] as JsonValue.Arr
        assertEquals(JsonValue.Num("1"), arr.items[0])
        assertEquals(JsonValue.Num("-2.5e3"), arr.items[1])
        assertEquals(JsonValue.Str("x\né\uD83C\uDFB5"), arr.items[2])
        assertEquals(JsonValue.Bool(true), arr.items[3])
        assertEquals(JsonValue.Bool(false), arr.items[4])
        assertEquals(JsonValue.Null, arr.items[5])
        assertEquals(JsonValue.Obj(linkedMapOf()), obj["b"])
    }

    @Test fun keepsKeyOrderAndTheFirstOfARepeatedKey() {
        val obj = StrictJson.parse("""{"z": 1, "a": 2, "z": 3}""") as JsonValue.Obj
        assertEquals(listOf("z", "a"), obj.entries.keys.toList())
        assertEquals(JsonValue.Num("1"), obj["z"])
    }

    @Test fun acceptsWhatSwiftAccepts() {
        StrictJson.parse("\uFEFF{}")
        StrictJson.parse("[1, 2,]")
        StrictJson.parse("""{"a": 1,}""")
        StrictJson.parse(" \n\t{} \r\n")
        StrictJson.parse("0")
        StrictJson.parse("-0.0e-0")
    }

    @Test fun rejectsWhatSwiftRejects() {
        for (bad in listOf(
            "", " ", "{", "}", "[1,,2]", "[,]", "{,}", "{\"a\" 1}", "{a: 1}", "{'a': 1}",
            "016", "+1", ".5", "1.", "1e", "-", "NaN", "Infinity", "tru", "nul",
            "\"a\tb\"", "\"\\x\"", "\"\\u12\"", "\"\\ud800\"", "\"\\udc00x\"", "\"abc",
            "{} x", "[1] [2]", "// c\n{}", "/* c */{}",
        )) rejects(bad)
    }

    /** Range is checked when a value is read as a number, not while
     * tokenizing, so an out-of-range number under an ignored key is harmless. */
    @Test fun outOfRangeNumbersTokenize() {
        StrictJson.parse("[1e400, -1e400, 99999999999999999999]")
    }

    @Test fun decodesUtf8StrictlyFromBytes() {
        assertEquals(JsonValue.Str("歌"), StrictJson.parse("\"歌\"".toByteArray()))
        try {
            StrictJson.parse(byteArrayOf('"'.code.toByte(), 0xC3.toByte(), '"'.code.toByte()))
            fail("malformed UTF-8 accepted")
        } catch (e: SongDecodeException) {
            // expected
        }
    }

    @Test fun deepNestingIsRejectedNotAStackOverflow() {
        rejects("[".repeat(100_000) + "]".repeat(100_000))
    }

    @Test fun integerReadingFollowsSwift() {
        assertEquals(16L, JsonValue.Num("16").asLongOrNull())
        assertEquals(16L, JsonValue.Num("16.0").asLongOrNull())
        assertEquals(32L, JsonValue.Num("3.2e1").asLongOrNull())
        assertEquals(null, JsonValue.Num("16.5").asLongOrNull())
        assertEquals(null, JsonValue.Num("99999999999999999999").asLongOrNull())
        assertEquals(Long.MIN_VALUE, JsonValue.Num("-9223372036854775808").asLongOrNull())
        assertTrue(JsonValue.Num("1e300").asDoubleOrNull()!!.isFinite())
        assertEquals(null, JsonValue.Num("1e400").asDoubleOrNull())
    }
}
