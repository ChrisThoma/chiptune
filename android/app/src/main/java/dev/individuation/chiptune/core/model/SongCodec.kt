package dev.individuation.chiptune.core.model

import java.math.BigDecimal
import java.util.UUID

/**
 * The `.chipsong` format, byte-compatible with the iOS app's `Codable`
 * conformances in `Song.swift`.
 *
 * Decoding mirrors each hand-written Swift `init(from:)`: a key that is
 * absent or `null` takes the decoder's fallback; a key that is present with
 * the wrong type rejects the whole song, as Swift's `decodeIfPresent` throws.
 * `SongSection` uses Swift's synthesized decoder, so all three of its keys
 * are required, and `Song.tracks` is required too. The result is always
 * normalized.
 *
 * Encoding writes Swift's keys in Swift's order, UUIDs uppercase, and
 * `modified` as seconds since 2001-01-01, so a file written here reads the
 * same on iOS.
 */
object SongCodec {

    private val UUID_PATTERN = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

    // MARK: Decoding

    fun decode(bytes: ByteArray): Song = decodeRoot(StrictJson.parse(bytes))

    fun decode(text: String): Song = decodeRoot(StrictJson.parse(text))

    private fun mismatch(key: String, expected: String): Nothing =
        throw SongDecodeException("\"$key\" is not $expected")

    /** Typed reads over one JSON object, each mirroring a Swift `decodeIfPresent`. */
    private class Reader(private val obj: JsonValue.Obj) {
        /** Absent and `null` are the same thing to `decodeIfPresent`. */
        fun present(key: String): JsonValue? = obj[key]?.takeUnless { it == JsonValue.Null }

        fun required(key: String): JsonValue = present(key) ?: throw SongDecodeException("missing \"$key\"")

        fun int(key: String): Int? = present(key)?.let { asInt(it, key) }

        fun long(key: String): Long? = present(key)?.let { asLong(it, key) }

        fun double(key: String): Double? = present(key)?.let {
            ((it as? JsonValue.Num) ?: mismatch(key, "a number")).asDoubleOrNull() ?: mismatch(key, "a finite Double")
        }

        fun bool(key: String): Boolean? = present(key)?.let { ((it as? JsonValue.Bool) ?: mismatch(key, "a Bool")).value }

        fun string(key: String): String? = present(key)?.let { ((it as? JsonValue.Str) ?: mismatch(key, "a String")).value }

        fun uuid(key: String): UUID? = present(key)?.let { asUuid(it, key) }

        fun array(key: String): List<JsonValue>? = present(key)?.let { asArray(it, key) }

        fun obj(key: String): JsonValue.Obj? = present(key)?.let { asObject(it, key) }
    }

    private fun asLong(v: JsonValue, key: String): Long =
        ((v as? JsonValue.Num) ?: mismatch(key, "an Int")).asLongOrNull() ?: mismatch(key, "an Int")

    /** Swift's `Int` is 64-bit; every Int the model keeps is clamped into a
     * small range by `normalized()`, so saturating here changes nothing a
     * normalized song can hold. */
    private fun asInt(v: JsonValue, key: String): Int =
        asLong(v, key).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

    private fun asUuid(v: JsonValue, key: String): UUID {
        val text = ((v as? JsonValue.Str) ?: mismatch(key, "a UUID")).value
        if (!UUID_PATTERN.matches(text)) mismatch(key, "a UUID")
        return UUID.fromString(text)
    }

    private fun asArray(v: JsonValue, key: String): List<JsonValue> = ((v as? JsonValue.Arr) ?: mismatch(key, "an array")).items

    private fun asObject(v: JsonValue, key: String): JsonValue.Obj = (v as? JsonValue.Obj) ?: mismatch(key, "an object")

    /** `[Int]` — a `null` element is a type error, as in Swift. */
    private fun longs(items: List<JsonValue>, key: String): List<Long> = items.map { asLong(it, key) }

    private fun decodeRoot(root: JsonValue): Song {
        val c = Reader((root as? JsonValue.Obj) ?: throw SongDecodeException("not a JSON object"))
        val id = c.uuid("id") ?: UUID.randomUUID()
        val name = c.string("name") ?: Song.DEFAULT_NAME
        val tempo = c.double("tempo") ?: 120.0
        val modified = c.double("modified") ?: SongClock.now()
        val decodedTracks = asArray(c.required("tracks"), "tracks").map { decodeTrack(asObject(it, "tracks")) }
        val tracks = decodedTracks.map { it.first }

        val saved = c.array("patterns")?.map { decodePattern(asObject(it, "patterns")) }
        val patterns: List<Pattern>
        val arrangement: List<SongSection>
        if (saved != null && saved.isNotEmpty()) {
            patterns = saved
            arrangement = c.array("arrangement")?.map { decodeSection(asObject(it, "arrangement")) } ?: emptyList()
        } else {
            // Written before patterns existed: the tracks' own notes become pattern A.
            // The arrangement key is not read at all on this path, as in Swift.
            var first = Pattern(name = "A", length = c.int("length") ?: 16, trackCount = tracks.size)
            for ((i, pair) in decodedTracks.withIndex()) {
                val notes = pair.second ?: continue
                if (i < first.rows.size) first = first.copy(rows = first.rows.mapIndexed { r, row -> if (r == i) notes else row })
            }
            patterns = listOf(first)
            arrangement = listOf(SongSection(patternID = first.id))
        }
        return Song(id = id, name = name, tempo = tempo, tracks = tracks, patterns = patterns,
            arrangement = arrangement, modified = modified).normalized()
    }

    /** A track and the legacy `notes` it carried, if any. */
    private fun decodeTrack(obj: JsonValue.Obj): Pair<Track, List<Int>?> {
        val c = Reader(obj)
        val id = c.uuid("id") ?: UUID.randomUUID()
        // Read as a raw Int: an unknown kind lands on pulse1 and the song still opens.
        val kind = c.int("kind")?.let { ChannelKind.fromRaw(it) } ?: ChannelKind.PULSE1
        val instrument = c.obj("instrument")?.let { decodeInstrument(it) } ?: Instrument.defaultFor(kind)
        val muted = c.bool("muted") ?: false
        val name = c.string("name")
        val notes = c.array("notes")?.let { longs(it, "notes").map(Chip::clampNote) }
        return Track(id = id, kind = kind, instrument = instrument, muted = muted, name = name) to notes
    }

    private fun decodeInstrument(obj: JsonValue.Obj): Instrument {
        val c = Reader(obj)
        val duty = c.int("duty") ?: 2
        val volume = c.double("volume") ?: 0.8
        var decay = c.double("decay") ?: 0.35
        val arpeggio = c.array("arpeggio")?.map { asInt(it, "arpeggio") } ?: emptyList()
        val sustain: Boolean
        val saved = c.bool("sustain")
        if (saved != null) {
            sustain = saved
        } else if (decay >= Instrument.LEGACY_HOLD_DECAY) {
            // An older file saying hold the only way it could; leave a real decay behind.
            sustain = true
            decay = 0.35
        } else {
            sustain = false
        }
        return Instrument(duty = duty, volume = volume, decay = decay, sustain = sustain, arpeggio = arpeggio)
    }

    private fun decodePattern(obj: JsonValue.Obj): Pattern {
        val c = Reader(obj)
        val id = c.uuid("id") ?: UUID.randomUUID()
        val name = c.string("name") ?: "A"
        val length = c.int("length") ?: 16
        val rows = c.array("rows")?.map { row -> longs(asArray(row, "rows"), "rows").map(Chip::clampNote) } ?: emptyList()
        return Pattern(id = id, name = name, length = length, rows = rows)
    }

    /** Synthesized `Codable` in Swift: every key is required. */
    private fun decodeSection(obj: JsonValue.Obj): SongSection {
        val c = Reader(obj)
        return SongSection(
            id = asUuid(c.required("id"), "id"),
            patternID = asUuid(c.required("patternID"), "patternID"),
            repeats = asInt(c.required("repeats"), "repeats"),
        )
    }

    // MARK: Encoding

    /** Pretty-printed JSON in the shape Swift's `JSONEncoder` writes. The song
     * is normalized first, so a NaN or infinity can never reach the file
     * (Swift's encoder would refuse to write one). */
    fun encode(song: Song): String {
        val s = song.normalized()
        val w = Writer()
        w.obj {
            field("id") { uuid(s.id) }
            field("name") { string(s.name) }
            field("tempo") { number(s.tempo) }
            field("tracks") {
                array(s.tracks) { t ->
                    obj {
                        field("id") { uuid(t.id) }
                        field("kind") { raw(t.kind.rawValue.toString()) }
                        field("instrument") {
                            obj {
                                field("duty") { raw(t.instrument.duty.toString()) }
                                field("volume") { number(t.instrument.volume) }
                                field("decay") { number(t.instrument.decay) }
                                field("sustain") { raw(t.instrument.sustain.toString()) }
                                field("arpeggio") { inlineInts(t.instrument.arpeggio) }
                            }
                        }
                        field("muted") { raw(t.muted.toString()) }
                        t.name?.let { name -> field("name") { string(name) } }
                    }
                }
            }
            field("patterns") {
                array(s.patterns) { p ->
                    obj {
                        field("id") { uuid(p.id) }
                        field("name") { string(p.name) }
                        field("length") { raw(p.length.toString()) }
                        field("rows") { array(p.rows) { row -> inlineInts(row) } }
                    }
                }
            }
            field("arrangement") {
                array(s.arrangement) { section ->
                    obj {
                        field("id") { uuid(section.id) }
                        field("patternID") { uuid(section.patternID) }
                        field("repeats") { raw(section.repeats.toString()) }
                    }
                }
            }
            field("modified") { number(s.modified) }
        }
        return w.toString()
    }

    /** A Double as the shortest JSON number that reads back to the same bits. */
    internal fun formatDouble(d: Double): String {
        require(d.isFinite()) { "non-finite value in a song" }
        if (d == 0.0) return if (1.0 / d < 0) "-0" else "0"
        val java = d.toString() // shortest-round-trip digits, as "123.4" or "1.234E-5"
        val e = java.indexOf('E')
        if (e < 0) return java.removeSuffix(".0")
        val exponent = java.substring(e + 1).toInt()
        if (exponent in -7..20) return BigDecimal(java).toPlainString().let { plain ->
            if (plain.contains('.')) plain.trimEnd('0').removeSuffix(".") else plain
        }
        val mantissa = java.substring(0, e).removeSuffix(".0")
        return "${mantissa}e$exponent"
    }

    private class Writer {
        private val sb = StringBuilder()
        private var indent = 0
        private var first = true

        private fun newline() {
            sb.append('\n')
            repeat(indent) { sb.append("  ") }
        }

        fun obj(body: Writer.() -> Unit) {
            sb.append('{')
            indent++
            val saved = first
            first = true
            body()
            indent--
            if (!first) newline()
            first = saved
            sb.append('}')
        }

        fun field(key: String, value: Writer.() -> Unit) {
            if (!first) sb.append(',')
            first = false
            newline()
            string(key)
            sb.append(" : ")
            value()
        }

        fun <T> array(items: List<T>, element: Writer.(T) -> Unit) {
            if (items.isEmpty()) {
                sb.append("[]")
                return
            }
            sb.append('[')
            indent++
            for ((i, item) in items.withIndex()) {
                if (i > 0) sb.append(',')
                newline()
                val saved = first
                element(item)
                first = saved
            }
            indent--
            newline()
            sb.append(']')
        }

        fun inlineInts(values: List<Int>) {
            sb.append('[')
            values.joinTo(sb, ", ")
            sb.append(']')
        }

        fun raw(text: String) {
            sb.append(text)
        }

        fun number(d: Double) {
            sb.append(formatDouble(d))
        }

        fun uuid(id: UUID) = string(id.toString().uppercase())

        fun string(text: String) {
            sb.append('"')
            var i = 0
            while (i < text.length) {
                val c = text[i]
                when {
                    c == '"' -> sb.append("\\\"")
                    c == '\\' -> sb.append("\\\\")
                    c == '\n' -> sb.append("\\n")
                    c == '\r' -> sb.append("\\r")
                    c == '\t' -> sb.append("\\t")
                    c == '\b' -> sb.append("\\b")
                    c == '\u000C' -> sb.append("\\f")
                    c < ' ' -> sb.append("\\u").append(String.format("%04x", c.code))
                    Character.isHighSurrogate(c) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1]) -> {
                        sb.append(c).append(text[i + 1])
                        i++
                    }
                    // An unpaired surrogate can't be written as UTF-8, and
                    // Swift rejects its escape; write the replacement character.
                    Character.isSurrogate(c) -> sb.append('�')
                    else -> sb.append(c)
                }
                i++
            }
            sb.append('"')
        }

        override fun toString(): String = sb.toString()
    }
}
