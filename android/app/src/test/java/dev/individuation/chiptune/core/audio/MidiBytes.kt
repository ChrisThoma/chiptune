package dev.individuation.chiptune.core.audio

/**
 * A small Standard MIDI File reader, written from the SMF 1.0 spec and
 * nothing else, so the MIDI tests check the stored bytes rather than the
 * writer's own idea of them. It turns a file into each track's events at
 * their absolute ticks. Port of `Tests/Support/MidiBytes.swift`.
 *
 * It is strict where the export promises to be: running status is a parse
 * error rather than something to tolerate, and every chunk has to end exactly
 * where its length says it does.
 */
class MidiBytes(data: ByteArray) {

    sealed interface Event {
        data class NoteOn(val channel: Int, val note: Int, val velocity: Int) : Event
        data class NoteOff(val channel: Int, val note: Int, val velocity: Int) : Event
        data class Program(val channel: Int, val program: Int) : Event
        data class Control(val channel: Int, val controller: Int, val value: Int) : Event
        /** `bytes` as a list so two metas compare by content. */
        data class Meta(val type: Int, val bytes: List<Int>) : Event
    }

    data class Timed(val tick: Int, val event: Event)

    /** One sounding note: the note-on paired with the first note-off of the
     * same pitch on the same channel after it. */
    data class Note(val channel: Int, val note: Int, val velocity: Int, val on: Int, var off: Int)

    class ParseError(message: String) : Exception(message)

    val format: Int
    val declaredTrackCount: Int
    val division: Int
    val tracks: List<List<Timed>>

    init {
        val bytes = data
        var pos = 0

        fun u(i: Int): Int = bytes[i].toInt() and 0xFF
        fun take(n: Int): IntRange {
            if (n < 0 || pos + n > bytes.size) throw ParseError("truncated")
            val range = pos until pos + n
            pos += n
            return range
        }
        fun be(range: IntRange): Int = range.fold(0) { acc, i -> acc shl 8 or u(i) }
        fun chunk(id: String): IntRange {
            val tagRange = take(4)
            val tag = String(bytes, tagRange.first, 4, Charsets.US_ASCII)
            if (tag != id) throw ParseError("bad chunk $tag")
            val length = be(take(4))
            if (pos + length > bytes.size) throw ParseError("chunk overrun")
            return pos until pos + length
        }

        val header = chunk("MThd")
        if (header.count() != 6) throw ParseError("MThd length ${header.count()}")
        format = be(take(2))
        declaredTrackCount = be(take(2))
        division = be(take(2))

        val out = ArrayList<List<Timed>>()
        while (pos < bytes.size) {
            val body = chunk("MTrk")
            val end = body.last + 1
            val events = ArrayList<Timed>()
            var tick = 0

            fun vlq(): Int {
                var value = 0
                repeat(4) {
                    if (pos >= end) throw ParseError("chunk overrun")
                    val b = u(pos)
                    pos += 1
                    value = value shl 7 or (b and 0x7F)
                    if (b and 0x80 == 0) return value
                }
                throw ParseError("VLQ longer than four bytes")
            }
            fun data(): Int {
                if (pos >= end) throw ParseError("chunk overrun")
                return u(pos).also { pos += 1 }
            }

            while (pos < end) {
                tick += vlq()
                if (pos >= end) throw ParseError("chunk overrun")
                val status = u(pos)
                if (status and 0x80 == 0) throw ParseError("running status at $pos")
                pos += 1
                val channel = status and 0x0F
                val event: Event = when {
                    status and 0xF0 == 0x80 -> Event.NoteOff(channel, data(), data())
                    status and 0xF0 == 0x90 -> Event.NoteOn(channel, data(), data())
                    status and 0xF0 == 0xB0 -> Event.Control(channel, data(), data())
                    status and 0xF0 == 0xC0 -> Event.Program(channel, data())
                    status == 0xFF -> {
                        val type = data()
                        val length = vlq()
                        if (pos + length > end) throw ParseError("chunk overrun")
                        Event.Meta(type, (pos until pos + length).map { u(it) }).also { pos += length }
                    }
                    // The export writes nothing else; anything here is a bug
                    // in it, not something for the reader to skip politely.
                    else -> throw ParseError("unsupported status 0x${status.toString(16)}")
                }
                events.add(Timed(tick, event))
            }
            if (pos != end) throw ParseError("chunk overrun")
            out.add(events)
        }
        tracks = out
    }

    /** The chip tracks, without the conductor. */
    val chipTracks: List<List<Timed>> get() = tracks.drop(1)

    companion object {
        val END_OF_TRACK: Event = Event.Meta(0x2F, emptyList())

        fun metas(type: Int, track: List<Timed>): List<List<Int>> =
            track.mapNotNull { (it.event as? Event.Meta)?.takeIf { m -> m.type == type }?.bytes }

        /** The track's FF 03 name, decoded as UTF-8. */
        fun name(track: List<Timed>): String? =
            metas(0x03, track).firstOrNull()?.let { b -> String(ByteArray(b.size) { b[it].toByte() }, Charsets.UTF_8) }

        /** Notes in the order they start. A note-on with no matching note-off is
         * returned with `off` of -1, which no assertion will mistake for a tick. */
        fun notes(track: List<Timed>): List<Note> {
            val open = HashMap<Int, Int>() // channel shl 8 or note -> index into out
            val out = ArrayList<Note>()
            for (timed in track) {
                when (val e = timed.event) {
                    is Event.NoteOn -> {
                        open[e.channel shl 8 or e.note] = out.size
                        out.add(Note(e.channel, e.note, e.velocity, timed.tick, -1))
                    }
                    is Event.NoteOff -> open.remove(e.channel shl 8 or e.note)?.let { out[it].off = timed.tick }
                    else -> {}
                }
            }
            return out
        }

        /** UTF-8 bytes as the unsigned ints a [Event.Meta] holds. */
        fun utf8(text: String): List<Int> = text.toByteArray(Charsets.UTF_8).map { it.toInt() and 0xFF }

        /** Unsigned bytes, for building expected file bytes by hand. */
        fun bytes(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }
    }
}
