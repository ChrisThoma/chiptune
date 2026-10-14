package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongDocument
import dev.individuation.chiptune.core.model.swiftClamp
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.UUID

/** How the exported file should be shaped. Port of Swift's `ExportOptions`. */
data class ExportOptions(
    /** Passes of the whole arrangement. */
    val loopCount: Int = 1,
    val tailMode: TailMode = TailMode.SEAMLESS_LOOP,
    /** Which file the export writes. MIDI is the arrangement once, so
     * [loopCount] and [tailMode] only shape a WAV. Last, because tests build
     * options positionally. */
    val format: Format = Format.WAV,
) {
    enum class Format { WAV, MIDI }

    enum class TailMode {
        /** Exactly `loopCount` passes long, with the final notes' ring-out
         * folded over the file's own start so it loops seamlessly. */
        SEAMLESS_LOOP,
        /** `loopCount` passes, then silence while the last notes decay. */
        RING_OUT,
    }

    val clamped: ExportOptions get() = copy(loopCount = minOf(maxOf(loopCount, 1), MAX_LOOP_COUNT))

    companion object {
        const val MAX_LOOP_COUNT = 16
    }
}

/** The outcome of an export. Canceling is not failing: the UI must not show an
 * error for a file the user decided they didn't want. */
sealed interface ExportResult {
    data class Success(val file: File) : ExportResult
    data object Canceled : ExportResult
    data object TooLong : ExportResult
    /** Carries the write error so the alert can name the cause. */
    data class Failed(val error: Throwable) : ExportResult
}

/** Everything one export needs. */
class ExportRequest(
    val song: Song,
    val options: ExportOptions = ExportOptions(),
    /** Called with 0..1 as the render proceeds, on the rendering thread. */
    val progress: (Double) -> Unit = {},
    /** Polled at chunk boundaries. Returning true abandons the render. */
    val isCanceled: () -> Boolean = { false },
)

/** Picks the writer for the format the export sheet chose. Studio's default
 * renderer, so the sheet's WAV / MIDI choice reaches the file without Studio
 * knowing either format. Clears the song's stale exports once the new file is
 * written, so neither writer has to. */
object ExportRenderer {
    fun render(request: ExportRequest, directory: File): ExportResult {
        val result = when (request.options.format) {
            ExportOptions.Format.WAV -> WavExport.render(request, directory)
            ExportOptions.Format.MIDI -> MidiExport.render(request, directory)
        }
        if (result is ExportResult.Success) ExportFiles.pruneStale(result.file)
        return result
    }
}

/** Where the exporters put their files, and how old ones are cleared away.
 * Port of `ExportFiles` in `Sources/Audio/WavExport.swift`. */
object ExportFiles {

    /** `<directory>/<SONG-UUID>/<safeName>.<ext>`; the per-song folder keeps
     * the shared file's display name clean while stopping two same-named
     * songs from overwriting each other's export. Creates the folder. */
    fun file(song: Song, directory: File, ext: String): File {
        val base = SongDocument.safeName(song)
        val dir = File(directory, song.id.toString().uppercase())
        dir.mkdirs()
        return File(dir, "$base.$ext")
    }

    /** Renaming a song leaves its old export sitting in the same per-song
     * folder as the new one. Only files of [keeping]'s own type go: the song's
     * WAV and its MIDI file are each worth keeping while the other is
     * exported. Only run once the new file is safely written, so a later
     * failure never costs the previous export. Best-effort: a cleanup failure
     * doesn't fail the export that just succeeded. */
    fun pruneStale(keeping: File) {
        val ext = keeping.extension.lowercase()
        val entries = keeping.parentFile?.listFiles() ?: return
        for (entry in entries) {
            if (entry.extension.lowercase() == ext && entry.name != keeping.name) entry.delete()
        }
    }
}

/**
 * Renders a song offline and writes it out as a 16-bit mono 44.1 kHz WAV.
 * Port of `Sources/Audio/WavExport.swift`.
 *
 * Every output file lands at `<directory>/<SONG-UUID>/<safeName>.wav`, and the
 * raw float scratch stream at `<directory>/<UUID>.raw`. The directory is
 * injected (tests pass a temp folder; the app passes `cacheDir`) where Swift
 * uses `FileManager.temporaryDirectory`.
 *
 * The render is memory-bounded: everything past the folded head streams
 * through the raw file, so a maximum-length arrangement never holds hundreds
 * of MB of floats. Arithmetic matches Swift's: the fold is a Float sum, the
 * peak and scale are Float, and the PCM conversion truncates toward zero like
 * `Int16(Float)`.
 */
object WavExport {
    const val SAMPLE_RATE = 44100.0
    private const val CHUNK = 4096
    /** Floats per read when streaming the raw file into the WAV (Swift's `1 << 16`). */
    private const val READ_CHUNK = 1 shl 16

    /** How long the last notes are given to decay past the end: 1.5 x the
     * longest audible decay, floored at 1 s and capped at 6 s. */
    fun tailSeconds(song: Song): Double = swiftClamp(1.5 * (song.maxAudibleDecay ?: 0.0), 1.0, 6.0)

    /** Thrown out of the render loops so a cancel unwinds in one hop. */
    private class CanceledSignal : Exception() {
        override fun fillInStackTrace(): Throwable = this
    }

    /** One pass, seamless loop, no progress, no cancel: the tests' one-line render. */
    fun render(song: Song, directory: File): File? =
        (render(ExportRequest(song), directory) as? ExportResult.Success)?.file

    /** Renders [request] and writes the WAV under [directory]. */
    fun render(request: ExportRequest, directory: File): ExportResult {
        val song = request.song.normalized()
        val options = request.options.clamped
        val folding = options.tailMode == ExportOptions.TailMode.SEAMLESS_LOOP

        val samplesPerStep = Chip.samplesPerStep(song.tempo, SAMPLE_RATE).toLong()
        val onePass = samplesPerStep * maxOf(song.arrangementSteps, 1)
        // The chain wraps on its own, so N passes are just a longer render.
        val bodySamples = onePass * options.loopCount
        val tail = (SAMPLE_RATE * tailSeconds(song)).toInt()

        // Reject an invalid RIFF size before rendering anything.
        val outputSamples = bodySamples + (if (folding) 0 else tail)
        if (!fitsInWav(outputSamples)) return ExportResult.TooLong

        val core = ChipCore(SAMPLE_RATE)
        core.load(song)
        core.setSongMode(true)
        core.start()

        val totalFrames = bodySamples + tail
        var reported = -1.0
        fun report(done: Long) {
            val fraction = minOf(done.toDouble() / maxOf(totalFrames, 1L).toDouble(), 1.0)
            // At most about a hundred calls, rather than one per chunk.
            if (!(fraction - reported >= 0.01 || fraction >= 1.0)) return
            reported = fraction
            request.progress(fraction)
        }

        val rawFile = File(directory, UUID.randomUUID().toString().uppercase() + ".raw")
        val raw: FileChannel
        try {
            directory.mkdirs()
            raw = FileOutputStream(rawFile).channel
        } catch (e: IOException) {
            return ExportResult.Failed(e)
        } catch (e: SecurityException) {
            return ExportResult.Failed(e)
        }

        try {
            // The stretch the tail folds over, kept in memory; ring-out keeps nothing.
            val headLen = if (folding) minOf(tail.toLong(), bodySamples).toInt() else 0
            val head = FloatArray(headLen)
            var bodyPeak = 0f
            val scratch = FloatArray(CHUNK)
            val bytes = ByteBuffer.allocate(CHUNK * 4).order(ByteOrder.LITTLE_ENDIAN)

            fun writeRaw(from: Int, until: Int) {
                bytes.clear()
                for (i in from until until) bytes.putFloat(scratch[i])
                bytes.flip()
                while (bytes.hasRemaining()) raw.write(bytes)
            }

            try {
                // Body.
                var written = 0L
                while (written < bodySamples) {
                    if (request.isCanceled()) throw CanceledSignal()
                    val n = minOf(CHUNK.toLong(), bodySamples - written).toInt()
                    core.render(n, scratch, 0)
                    val inHead = maxOf(0L, minOf(n.toLong(), headLen - written)).toInt()
                    for (i in 0 until inHead) head[(written + i).toInt()] = scratch[i]
                    if (n > inHead) {
                        for (i in inHead until n) {
                            val a = Math.abs(scratch[i])
                            if (a >= bodyPeak) bodyPeak = a // Swift's max(peak, a)
                        }
                        writeRaw(inHead, n)
                    }
                    written += n
                    report(written)
                }

                core.finish()

                // Tail: the sequencer is stopped, so nothing new is triggered
                // while the envelopes ring out.
                var done = 0
                while (done < tail) {
                    if (request.isCanceled()) throw CanceledSignal()
                    val n = minOf(CHUNK, tail - done)
                    core.render(n, scratch, 0)
                    if (folding) {
                        // Fold over the start, in Float: played on repeat, the
                        // last notes ring on into the beginning exactly as they
                        // would have if the sequencer had kept running.
                        if (headLen > 0) {
                            for (i in 0 until n) {
                                val at = (done + i) % headLen
                                head[at] = head[at] + scratch[i]
                            }
                        }
                    } else {
                        for (i in 0 until n) {
                            val a = Math.abs(scratch[i])
                            if (a >= bodyPeak) bodyPeak = a
                        }
                        writeRaw(0, n)
                    }
                    done += n
                    report(bodySamples + done)
                }
                raw.close()
            } catch (e: CanceledSignal) {
                return ExportResult.Canceled
            } catch (e: IOException) {
                return ExportResult.Failed(e)
            }

            // Summing the overlap can push it past full scale. Scale the whole
            // file rather than letting the write clamp only the seam.
            var peak = bodyPeak
            for (s in head) {
                val a = Math.abs(s)
                if (a >= peak) peak = a
            }
            val scale: Float = if (peak > 1f) 1f / peak else 1f

            val streamed = (bodySamples - headLen) + (if (folding) 0 else tail)
            val target = filename(song, directory)
            val result = writeWav(head, rawFile, streamed, scale, request.isCanceled, target)
            if (result is ExportResult.Success) report(totalFrames)
            return result
        } finally {
            try {
                raw.close()
            } catch (_: IOException) {
            }
            rawFile.delete()
        }
    }

    /** `<directory>/<SONG-UUID>/<safeName>.wav`. Creates the folder. */
    fun filename(song: Song, directory: File): File = ExportFiles.file(song, directory, "wav")

    /** Streams the folded head plus the raw body file out as a WAV, converting
     * to 16-bit in chunks so the whole song is never in memory twice. */
    private fun writeWav(
        head: FloatArray,
        body: File,
        bodySamples: Long,
        scale: Float,
        isCanceled: () -> Boolean,
        to: File,
    ): ExportResult {
        val totalSamples = head.size + bodySamples
        if (!fitsInWav(totalSamples)) return ExportResult.TooLong
        val channels = 1
        val bitsPerSample = 16
        val byteRate = SAMPLE_RATE.toInt() * channels * (bitsPerSample / 8)
        val blockAlign = channels * (bitsPerSample / 8)
        val dataSize = totalSamples * 2

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt((36 + dataSize).toInt()) // UInt32 bit pattern
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16) // PCM chunk size
        header.putShort(1) // PCM format
        header.putShort(channels.toShort())
        header.putInt(SAMPLE_RATE.toInt())
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataSize.toInt())
        header.flip()

        to.delete()
        val out: FileChannel
        try {
            out = FileOutputStream(to).channel
        } catch (e: IOException) {
            return ExportResult.Failed(e)
        } catch (e: SecurityException) {
            return ExportResult.Failed(e)
        }

        /** A half-written WAV is worse than no file: it would show up in the
         * share sheet and play as noise. */
        fun discard() {
            try {
                out.close()
            } catch (_: IOException) {
            }
            to.delete()
        }

        try {
            while (header.hasRemaining()) out.write(header)

            val pcm = ByteBuffer.allocate(READ_CHUNK * 2).order(ByteOrder.LITTLE_ENDIAN)
            fun writePcm(samples: FloatArray, from: Int, until: Int) {
                pcm.clear()
                for (i in from until until) pcm.putShort(pcm16(samples[i], scale))
                pcm.flip()
                while (pcm.hasRemaining()) out.write(pcm)
            }

            var at = 0
            while (at < head.size) {
                val n = minOf(READ_CHUNK, head.size - at)
                writePcm(head, at, at + n)
                at += n
            }

            if (bodySamples > 0) {
                FileInputStream(body).channel.use { input ->
                    val rawBytes = ByteBuffer.allocate(READ_CHUNK * 4).order(ByteOrder.LITTLE_ENDIAN)
                    val floats = FloatArray(READ_CHUNK)
                    var remaining = bodySamples
                    while (remaining > 0) {
                        if (isCanceled()) {
                            discard()
                            return ExportResult.Canceled
                        }
                        val n = minOf(READ_CHUNK.toLong(), remaining).toInt()
                        rawBytes.clear()
                        rawBytes.limit(n * 4)
                        while (rawBytes.hasRemaining()) {
                            if (input.read(rawBytes) < 0) break
                        }
                        rawBytes.flip()
                        val got = rawBytes.remaining()
                        // A short raw file means the render was cut off; a
                        // truncated WAV with a full-length header is worse than none.
                        if (got == 0 || got % 4 != 0) throw IOException("the rendered audio was cut short")
                        val count = got / 4
                        for (i in 0 until count) floats[i] = rawBytes.getFloat()
                        writePcm(floats, 0, count)
                        remaining -= count
                    }
                }
            }
            out.close()
            return ExportResult.Success(to)
        } catch (e: IOException) {
            discard()
            return ExportResult.Failed(e)
        }
    }

    /** RIFF stores its whole chunk size, including the 36 bytes around the
     * sample data, in one UInt32. */
    private fun fitsInWav(sampleCount: Long): Boolean =
        sampleCount >= 0 && sampleCount <= (0xFFFFFFFFL - 36) / 2

    /** One sample as 16-bit PCM: Swift's `Int16(max(-1, min(1, x * scale)) * 32767)`,
     * all in Float, truncating toward zero. */
    internal fun pcm16(sample: Float, scale: Float): Short {
        val scaled = sample * scale
        val upper = if (scaled < 1f) scaled else 1f // Swift min(1.0, x): x < 1 ? x : 1
        val clamped = if (upper >= -1f) upper else -1f // Swift max(-1.0, m): m >= -1 ? m : -1
        return (clamped * 32767f).toInt().toShort()
    }
}
