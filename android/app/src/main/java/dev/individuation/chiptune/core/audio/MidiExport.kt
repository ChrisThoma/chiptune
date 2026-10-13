package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.swiftRounded
import java.io.ByteArrayOutputStream

/**
 * Writes a song out as a Standard MIDI File, for taking the notes into a DAW.
 * Port of `Sources/Audio/MidiExport.swift`.
 *
 * Format 1 at 96 ticks per quarter: track 0 is the conductor (name, tempo,
 * meter), then one MIDI track per chip track in song order. The bytes are the
 * iOS writer's for the same song, and the golden files in
 * `Tests/Fixtures/midi-*.mid` hold both to that.
 */
object MidiExport {
    /** 96 divides into a sixteenth evenly, which is all the sequencer can
     * place a note on. */
    const val TICKS_PER_QUARTER = 96
    const val TICKS_PER_STEP = TICKS_PER_QUARTER / Chip.STEPS_PER_BEAT

    /** The file's bytes. Normalizes first, as the WAV export does, so a song
     * straight from a file can't put an out-of-range tempo into the header. */
    fun data(song: Song): ByteArray {
        val normalized = song.normalized()
        val endTick = normalized.arrangementSteps * TICKS_PER_STEP

        val file = ByteArrayOutputStream()
        file.write("MThd".toByteArray(Charsets.US_ASCII))
        file.write(be32(6))
        file.write(be16(1))
        file.write(be16(normalized.tracks.size + 1))
        file.write(be16(TICKS_PER_QUARTER))

        file.write(chunk(conductor(normalized, endTick)))
        for (index in normalized.tracks.indices) {
            file.write(chunk(track(index, normalized, endTick)))
        }
        return file.toByteArray()
    }

    /** One chip track's MIDI track. */
    private fun track(index: Int, song: Song, endTick: Int): TrackEvents {
        val events = TrackEvents()
        // Every track ends on the last tick, sounding or not, so the file
        // loops at the arrangement's length in a DAW.
        events.append(endTick, 0xFF, 0x2F, 0x00)
        return events
    }

    private fun conductor(song: Song, endTick: Int): TrackEvents {
        val events = TrackEvents()
        events.append(0, text(0x03, song.name))
        val micros = swiftRounded(60_000_000.0 / song.tempo).toInt()
        events.append(0, 0xFF, 0x51, 0x03, micros shr 16 and 0xFF, micros shr 8 and 0xFF, micros and 0xFF)
        // 4/4; a click every 24 MIDI clocks (one quarter); eight 32nds to the
        // quarter. The app has no meter of its own, and four sixteenths to the
        // beat reads naturally as 4/4.
        events.append(0, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08)
        events.append(endTick, 0xFF, 0x2F, 0x00)
        return events
    }

    // MARK: Bytes

    /** A track's events at absolute ticks, appended in the order they are to
     * be written. Deltas are worked out on the way to bytes, so a caller
     * never has to. */
    private class TrackEvents {
        val items = ArrayList<Pair<Int, ByteArray>>()

        fun append(tick: Int, bytes: ByteArray) {
            items.add(tick to bytes)
        }

        fun append(tick: Int, vararg bytes: Int) = append(tick, ByteArray(bytes.size) { bytes[it].toByte() })
    }

    private fun chunk(events: TrackEvents): ByteArray {
        val body = ByteArrayOutputStream()
        var last = 0
        for ((tick, bytes) in events.items) {
            body.write(vlq(tick - last))
            body.write(bytes)
            last = tick
        }
        val out = ByteArrayOutputStream()
        out.write("MTrk".toByteArray(Charsets.US_ASCII))
        out.write(be32(body.size()))
        body.writeTo(out)
        return out.toByteArray()
    }

    /** A text meta event. The length is the UTF-8 byte count, not the
     * character count: one non-ASCII letter in a name would otherwise cut
     * the end off it, or swallow the next event's first byte. */
    private fun text(type: Int, string: String): ByteArray {
        val bytes = string.toByteArray(Charsets.UTF_8)
        return byteArrayOf(0xFF.toByte(), type.toByte()) + vlq(bytes.size) + bytes
    }

    private fun vlq(value: Int): ByteArray {
        val out = ArrayDeque<Byte>()
        out.addFirst((value and 0x7F).toByte())
        var rest = value shr 7
        while (rest > 0) {
            out.addFirst((rest and 0x7F or 0x80).toByte())
            rest = rest shr 7
        }
        return out.toByteArray()
    }

    private fun be16(value: Int): ByteArray =
        byteArrayOf((value shr 8 and 0xFF).toByte(), (value and 0xFF).toByte())

    private fun be32(value: Int): ByteArray = byteArrayOf(
        (value shr 24 and 0xFF).toByte(), (value shr 16 and 0xFF).toByte(),
        (value shr 8 and 0xFF).toByte(), (value and 0xFF).toByte(),
    )
}
