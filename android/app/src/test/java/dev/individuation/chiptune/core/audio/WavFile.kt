package dev.individuation.chiptune.core.audio

import java.io.File
import java.io.IOException

/** Reads WAVs back from the outside, never through the writer's own code.
 * Port of `Tests/Support/WavBytes.swift` plus the readers the Swift suites
 * built on `AVAudioFile`. */
object WavFile {

    /** Little-endian 32-bit read, for walking chunk headers by hand. */
    fun le32(data: ByteArray, offset: Int): Int =
        (data[offset].toInt() and 0xFF) or
            ((data[offset + 1].toInt() and 0xFF) shl 8) or
            ((data[offset + 2].toInt() and 0xFF) shl 16) or
            ((data[offset + 3].toInt() and 0xFF) shl 24)

    fun le16(data: ByteArray, offset: Int): Int =
        (data[offset].toInt() and 0xFF) or ((data[offset + 1].toInt() and 0xFF) shl 8)

    data class Format(val channels: Int, val sampleRate: Int, val bitsPerSample: Int, val formatTag: Int)

    /** Walks the RIFF chunks and returns the body of chunk [id], or null. */
    fun chunk(data: ByteArray, id: String): ByteArray? {
        var offset = 12
        while (offset + 8 <= data.size) {
            val name = String(data, offset, 4, Charsets.US_ASCII)
            val size = le32(data, offset + 4)
            if (name == id) {
                val end = minOf(offset + 8 + size, data.size)
                return data.copyOfRange(offset + 8, end)
            }
            offset += 8 + size + (size % 2)
        }
        return null
    }

    fun format(file: File): Format {
        val fmt = chunk(file.readBytes(), "fmt ") ?: throw IOException("no fmt chunk")
        return Format(channels = le16(fmt, 2), sampleRate = le32(fmt, 4),
            bitsPerSample = le16(fmt, 14), formatTag = le16(fmt, 0))
    }

    /** The stored 16-bit integers, so "within 2 LSB" is a statement about the
     * file rather than about a float conversion applied to both sides. */
    fun pcm16(bytes: ByteArray): ShortArray {
        val payload = chunk(bytes, "data") ?: throw IOException("no data chunk")
        val out = ShortArray(payload.size / 2)
        for (i in out.indices) out[i] = le16(payload, i * 2).toShort()
        return out
    }

    fun pcm16(file: File): ShortArray = pcm16(file.readBytes())

    /** Samples as floats the way `AVAudioFile` reads 16-bit PCM: x / 32768. */
    fun samples(file: File): FloatArray {
        val ints = pcm16(file)
        return FloatArray(ints.size) { ints[it] / 32768f }
    }
}
