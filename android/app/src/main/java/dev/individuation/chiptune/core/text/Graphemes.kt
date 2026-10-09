package dev.individuation.chiptune.core.text

/**
 * Swift's `Character`: an extended grapheme cluster (UAX #29).
 *
 * Name caps count characters the way Swift's `String.count` and `prefix` do,
 * so a name clipped on Android is the name iOS would have stored. Neither
 * `java.text.BreakIterator` (JDK 17 predates its grapheme fixes) nor
 * `android.icu` (not available in plain JVM tests, and off-limits in `core`)
 * gives the same answer on both, so the rules are written out here. They
 * cover what a typed name meets — combining marks, emoji modifiers and ZWJ
 * sequences, flags, Hangul, CRLF — using `Character.getType` for the
 * property tables, with emoji ranges approximated by block.
 */
object Graphemes {

    private enum class Kind { CR, LF, CONTROL, EXTEND, ZWJ, RI, PREPEND, SPACING_MARK, L, V, T, LV, LVT, PICTO, OTHER }

    private fun kind(cp: Int): Kind {
        when (cp) {
            0x0D -> return Kind.CR
            0x0A -> return Kind.LF
            0x200D -> return Kind.ZWJ
            0x200C -> return Kind.EXTEND
        }
        if (cp in 0x1F1E6..0x1F1FF) return Kind.RI
        if (cp in 0x1F3FB..0x1F3FF) return Kind.EXTEND // emoji skin-tone modifiers
        if (cp in 0xE0020..0xE007F) return Kind.EXTEND // emoji tag sequences
        if (cp in 0xFE00..0xFE0F || cp in 0xE0100..0xE01EF) return Kind.EXTEND // variation selectors
        if (cp == 0xFF9E || cp == 0xFF9F) return Kind.EXTEND
        if (cp in 0x1100..0x115F || cp in 0xA960..0xA97C) return Kind.L
        if (cp in 0x1160..0x11A7 || cp in 0xD7B0..0xD7C6) return Kind.V
        if (cp in 0x11A8..0x11FF || cp in 0xD7CB..0xD7FB) return Kind.T
        if (cp in 0xAC00..0xD7A3) return if ((cp - 0xAC00) % 28 == 0) Kind.LV else Kind.LVT
        if (cp in 0x0600..0x0605 || cp == 0x06DD || cp == 0x070F || cp == 0x08E2 || cp == 0x110BD) return Kind.PREPEND
        if (isPictographic(cp)) return Kind.PICTO
        return when (Character.getType(cp)) {
            Character.NON_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt() -> Kind.EXTEND
            Character.COMBINING_SPACING_MARK.toInt() -> Kind.SPACING_MARK
            Character.CONTROL.toInt(), Character.LINE_SEPARATOR.toInt(),
            Character.PARAGRAPH_SEPARATOR.toInt(), Character.FORMAT.toInt(),
            Character.SURROGATE.toInt(),
            -> Kind.CONTROL
            else -> Kind.OTHER
        }
    }

    /** Extended_Pictographic, approximated by the blocks emoji live in. */
    private fun isPictographic(cp: Int): Boolean =
        cp == 0x00A9 || cp == 0x00AE || cp == 0x203C || cp == 0x2049 || cp == 0x2122 || cp == 0x2139 ||
            cp in 0x2194..0x2199 || cp in 0x21A9..0x21AA || cp in 0x231A..0x231B || cp == 0x2328 ||
            cp == 0x23CF || cp in 0x23E9..0x23F3 || cp in 0x23F8..0x23FA || cp == 0x24C2 ||
            cp in 0x25AA..0x25AB || cp == 0x25B6 || cp == 0x25C0 || cp in 0x25FB..0x25FE ||
            cp in 0x2600..0x27BF || cp in 0x2934..0x2935 || cp in 0x2B05..0x2B07 ||
            cp in 0x2B1B..0x2B1C || cp == 0x2B50 || cp == 0x2B55 || cp == 0x3030 || cp == 0x303D ||
            cp == 0x3297 || cp == 0x3299 || cp in 0x1F000..0x1FAFF || cp in 0x1FC00..0x1FFFD

    /** Whether a cluster boundary falls between [prev] and [next]. [riRun]
     * counts the regional indicators immediately before [next]; [pictoZwj]
     * says the cluster so far is pictographic, Extend*, ZWJ. */
    private fun breaks(prev: Kind, next: Kind, riRun: Int, pictoZwj: Boolean): Boolean {
        if (prev == Kind.CR && next == Kind.LF) return false // GB3
        if (prev == Kind.CR || prev == Kind.LF || prev == Kind.CONTROL) return true // GB4
        if (next == Kind.CR || next == Kind.LF || next == Kind.CONTROL) return true // GB5
        if (prev == Kind.L && (next == Kind.L || next == Kind.V || next == Kind.LV || next == Kind.LVT)) return false // GB6
        if ((prev == Kind.LV || prev == Kind.V) && (next == Kind.V || next == Kind.T)) return false // GB7
        if ((prev == Kind.LVT || prev == Kind.T) && next == Kind.T) return false // GB8
        if (next == Kind.EXTEND || next == Kind.ZWJ) return false // GB9
        if (next == Kind.SPACING_MARK) return false // GB9a
        if (prev == Kind.PREPEND) return false // GB9b
        if (prev == Kind.ZWJ && next == Kind.PICTO && pictoZwj) return false // GB11
        if (prev == Kind.RI && next == Kind.RI) return riRun % 2 == 0 // GB12/13
        return true // GB999
    }

    /** The string split into Swift `Character`s. */
    fun split(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val out = ArrayList<String>()
        var start = 0
        var i = 0
        var prev: Kind? = null
        var riRun = 0
        // GB11 state: inside "Pictographic Extend*", and whether a ZWJ followed it.
        var inPicto = false
        var pictoZwj = false
        while (i < text.length) {
            val cp = text.codePointAt(i)
            val k = kind(cp)
            if (prev != null && breaks(prev, k, riRun, pictoZwj)) {
                out.add(text.substring(start, i))
                start = i
            }
            // Advance GB11 state.
            pictoZwj = inPicto && k == Kind.ZWJ
            inPicto = when (k) {
                Kind.PICTO -> true
                Kind.EXTEND -> inPicto
                else -> false
            }
            riRun = if (k == Kind.RI) riRun + 1 else 0
            prev = k
            i += Character.charCount(cp)
        }
        out.add(text.substring(start))
        return out
    }

    fun count(text: String): Int = split(text).size

    /** Swift's `String(text.prefix(n))`. */
    fun prefix(text: String, n: Int): String {
        if (n <= 0) return ""
        val clusters = split(text)
        if (clusters.size <= n) return text
        return clusters.subList(0, n).joinToString("")
    }
}

/** Foundation's character sets, which are not Kotlin's `isWhitespace`. */
object SwiftText {
    /** `CharacterSet.whitespaces`: Unicode Zs plus tab. */
    fun isWhitespace(cp: Int): Boolean = cp == 0x09 || Character.getType(cp) == Character.SPACE_SEPARATOR.toInt()

    /** `CharacterSet.whitespacesAndNewlines`: the above plus U+000A–U+000D, U+0085, U+2028, U+2029. */
    fun isWhitespaceOrNewline(cp: Int): Boolean =
        isWhitespace(cp) || cp in 0x0A..0x0D || cp == 0x85 || cp == 0x2028 || cp == 0x2029

    private fun trim(text: String, drop: (Int) -> Boolean): String {
        var start = 0
        while (start < text.length) {
            val cp = text.codePointAt(start)
            if (!drop(cp)) break
            start += Character.charCount(cp)
        }
        var end = text.length
        while (end > start) {
            val cp = text.codePointBefore(end)
            if (!drop(cp)) break
            end -= Character.charCount(cp)
        }
        return text.substring(start, end)
    }

    /** `trimmingCharacters(in: .whitespaces)`. */
    fun trimWhitespaces(text: String): String = trim(text, ::isWhitespace)

    /** `trimmingCharacters(in: .whitespacesAndNewlines)`. */
    fun trimWhitespaceAndNewlines(text: String): String = trim(text, ::isWhitespaceOrNewline)
}
