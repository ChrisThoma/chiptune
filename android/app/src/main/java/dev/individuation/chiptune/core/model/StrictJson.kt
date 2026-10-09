package dev.individuation.chiptune.core.model

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Anything that keeps bytes from being read as a song: malformed JSON, a
 * value of the wrong type, a missing required key. iOS reports all of them
 * as "That doesn't look like a Chiptune song." */
class SongDecodeException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** A parsed JSON value. Objects keep their keys in document order. Numbers
 * keep their source text, so each reader decides how to interpret it the
 * way Swift's `JSONDecoder` would for the type it asked for. */
sealed class JsonValue {
    data class Obj(val entries: LinkedHashMap<String, JsonValue>) : JsonValue() {
        operator fun get(key: String): JsonValue? = entries[key]
    }

    data class Arr(val items: List<JsonValue>) : JsonValue()

    data class Str(val value: String) : JsonValue()

    data class Num(val text: String) : JsonValue() {
        /** What Swift's decoder gives for an `Int`: the integer itself, or a
         * number that converts to a `Double` holding an exact Int64 (so `16.0`
         * and `3.2e1` are accepted and `16.5` is not). Null means "throw". */
        fun asLongOrNull(): Long? {
            if (text.none { it == '.' || it == 'e' || it == 'E' }) {
                text.toLongOrNull()?.let { return it }
            }
            val d = text.toDouble()
            if (!d.isFinite() || d != Math.floor(d)) return null
            if (d < -9.223372036854775808E18 || d >= 9.223372036854775808E18) return null
            return d.toLong()
        }

        /** What Swift's decoder gives for a `Double`; null (throw) when the
         * value overflows to infinity, as `1e400` does. */
        fun asDoubleOrNull(): Double? = text.toDouble().takeIf { it.isFinite() }
    }

    data class Bool(val value: Boolean) : JsonValue()

    data object Null : JsonValue()
}

/**
 * The JSON grammar Swift's `JSONDecoder` accepts, checked against iOS by the
 * shared fixtures: RFC 8259, plus a trailing comma before `]` or `}`, plus a
 * leading UTF-8 BOM. A repeated key keeps its first value. Everything else —
 * comments, single quotes, `NaN`, leading zeros, a bare `.5`, raw control
 * characters in strings, unpaired surrogate escapes, trailing garbage — is
 * rejected.
 *
 * Written by hand rather than on `org.json` because the platform `org.json`
 * on a device and the Maven one in JVM tests differ (and both are lenient:
 * unquoted strings, comments, `NaN`), so tests on one would prove nothing
 * about the other.
 */
object StrictJson {
    /** Swift's scanner gives up past this depth; a deep file is not a song. */
    private const val MAX_DEPTH = 512

    fun parse(bytes: ByteArray): JsonValue {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val text = try {
            decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: CharacterCodingException) {
            throw SongDecodeException("not UTF-8", e)
        }
        return parse(text)
    }

    fun parse(text: String): JsonValue = Parser(text.removePrefix("\uFEFF")).parseDocument()

    private class Parser(private val s: String) {
        private var i = 0

        private fun fail(what: String): Nothing = throw SongDecodeException("$what at offset $i")

        fun parseDocument(): JsonValue {
            skipWhitespace()
            val value = parseValue(0)
            skipWhitespace()
            if (i != s.length) fail("unexpected trailing content")
            return value
        }

        private fun skipWhitespace() {
            while (i < s.length) {
                when (s[i]) {
                    ' ', '\t', '\n', '\r' -> i++
                    else -> return
                }
            }
        }

        private fun parseValue(depth: Int): JsonValue {
            if (i >= s.length) fail("unexpected end")
            return when (val c = s[i]) {
                '{' -> parseObject(depth + 1)
                '[' -> parseArray(depth + 1)
                '"' -> JsonValue.Str(parseString())
                't' -> literal("true", JsonValue.Bool(true))
                'f' -> literal("false", JsonValue.Bool(false))
                'n' -> literal("null", JsonValue.Null)
                else -> if (c == '-' || c in '0'..'9') parseNumber() else fail("unexpected '$c'")
            }
        }

        private fun literal(word: String, value: JsonValue): JsonValue {
            if (!s.startsWith(word, i)) fail("bad literal")
            i += word.length
            return value
        }

        private fun parseObject(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("too deep")
            i++ // {
            val entries = LinkedHashMap<String, JsonValue>()
            skipWhitespace()
            if (i < s.length && s[i] == '}') {
                i++
                return JsonValue.Obj(entries)
            }
            while (true) {
                skipWhitespace()
                if (i >= s.length || s[i] != '"') fail("expected a key")
                val key = parseString()
                skipWhitespace()
                if (i >= s.length || s[i] != ':') fail("expected ':'")
                i++
                skipWhitespace()
                val value = parseValue(depth)
                if (!entries.containsKey(key)) entries[key] = value
                skipWhitespace()
                if (i >= s.length) fail("unterminated object")
                when (s[i]) {
                    ',' -> {
                        i++
                        skipWhitespace()
                        if (i < s.length && s[i] == '}') {
                            i++
                            return JsonValue.Obj(entries)
                        }
                    }
                    '}' -> {
                        i++
                        return JsonValue.Obj(entries)
                    }
                    else -> fail("expected ',' or '}'")
                }
            }
        }

        private fun parseArray(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("too deep")
            i++ // [
            val items = ArrayList<JsonValue>()
            skipWhitespace()
            if (i < s.length && s[i] == ']') {
                i++
                return JsonValue.Arr(items)
            }
            while (true) {
                skipWhitespace()
                items.add(parseValue(depth))
                skipWhitespace()
                if (i >= s.length) fail("unterminated array")
                when (s[i]) {
                    ',' -> {
                        i++
                        skipWhitespace()
                        if (i < s.length && s[i] == ']') {
                            i++
                            return JsonValue.Arr(items)
                        }
                    }
                    ']' -> {
                        i++
                        return JsonValue.Arr(items)
                    }
                    else -> fail("expected ',' or ']'")
                }
            }
        }

        private fun parseNumber(): JsonValue {
            val start = i
            if (s[i] == '-') i++
            if (i >= s.length) fail("bad number")
            if (s[i] == '0') {
                i++
            } else if (s[i] in '1'..'9') {
                while (i < s.length && s[i] in '0'..'9') i++
            } else {
                fail("bad number")
            }
            if (i < s.length && s[i] == '.') {
                i++
                if (i >= s.length || s[i] !in '0'..'9') fail("bad fraction")
                while (i < s.length && s[i] in '0'..'9') i++
            }
            if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
                i++
                if (i < s.length && (s[i] == '+' || s[i] == '-')) i++
                if (i >= s.length || s[i] !in '0'..'9') fail("bad exponent")
                while (i < s.length && s[i] in '0'..'9') i++
            }
            // A digit straight after "0" ("016") is not a number continuing.
            if (i < s.length && s[i] in '0'..'9') fail("leading zero")
            return JsonValue.Num(s.substring(start, i))
        }

        private fun parseString(): String {
            i++ // opening quote
            val out = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i]
                when {
                    c == '"' -> {
                        i++
                        return out.toString()
                    }
                    c == '\\' -> {
                        i++
                        if (i >= s.length) fail("bad escape")
                        when (s[i]) {
                            '"' -> out.append('"')
                            '\\' -> out.append('\\')
                            '/' -> out.append('/')
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000C')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> {
                                i++
                                val unit = hex4()
                                if (Character.isHighSurrogate(unit)) {
                                    if (!s.startsWith("\\u", i)) fail("unpaired surrogate")
                                    i += 2
                                    val low = hex4()
                                    if (!Character.isLowSurrogate(low)) fail("unpaired surrogate")
                                    out.append(unit).append(low)
                                } else if (Character.isLowSurrogate(unit)) {
                                    fail("unpaired surrogate")
                                } else {
                                    out.append(unit)
                                }
                                continue
                            }
                            else -> fail("bad escape")
                        }
                        i++
                    }
                    c < ' ' -> fail("control character in string")
                    Character.isHighSurrogate(c) -> {
                        if (i + 1 >= s.length || !Character.isLowSurrogate(s[i + 1])) fail("unpaired surrogate")
                        out.append(c).append(s[i + 1])
                        i += 2
                    }
                    Character.isLowSurrogate(c) -> fail("unpaired surrogate")
                    else -> {
                        out.append(c)
                        i++
                    }
                }
            }
        }

        /** Four hex digits at [i], advancing past them. */
        private fun hex4(): Char {
            if (i + 4 > s.length) fail("bad \\u escape")
            var v = 0
            for (k in 0 until 4) {
                val d = Character.digit(s[i + k], 16)
                if (d < 0 || s[i + k].code > 0x7F) fail("bad \\u escape")
                v = v * 16 + d
            }
            i += 4
            return v.toChar()
        }
    }
}
