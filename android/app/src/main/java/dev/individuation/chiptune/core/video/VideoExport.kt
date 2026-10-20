package dev.individuation.chiptune.core.video

import dev.individuation.chiptune.core.audio.ExportFiles
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.ExportRequest
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.model.Song
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/** Everything the platform encoder needs for one video. */
class VideoJob(
    /** Normalized. */
    val song: Song,
    /** Clamped, with [ExportOptions.format] set to video. */
    val options: ExportOptions,
    val timeline: VideoTimeline,
    /** The rendered 16-bit mono 44.1 kHz WAV, exactly
     * [VideoTimeline.totalSamples] long. */
    val soundtrack: File,
    /** Where the mp4 goes. A scratch file: the caller moves it into place. */
    val output: File,
    /** 0..1 over the frames; the caller maps it onto the export's bar. */
    val progress: (Double) -> Unit,
    /** Polled once per frame. */
    val isCanceled: () -> Boolean,
)

/** Draws and encodes a [VideoJob]'s frames with its soundtrack into its
 * output. The app passes the MediaCodec one (`platform/video/Mp4Writer`);
 * core only knows this interface, so it stays free of android imports. */
fun interface VideoWriter {
    fun write(job: VideoJob): ExportResult
}

/**
 * Renders a song as a 1080x1920, 30 fps H.264/AAC mp4 for Reels, TikTok and
 * Shorts. Port of `Sources/Video/VideoExport.swift`, minus the encoder.
 *
 * Audio first, then pictures: the soundtrack is rendered by [WavExport] to a
 * scratch WAV (the first 30% of the progress bar), then the [VideoWriter]
 * draws every frame and writes it alongside that audio (the rest). Frame `f`
 * shows sample `f x 1470` of the same render, through [VideoTimeline], so
 * the picture cannot drift from the sound.
 *
 * Nothing half-made is left behind. The WAV and the mp4 being written both
 * live in [SCRATCH_DIRECTORY], beside the per-song export folders rather
 * than in one, so neither clobbers the user's last WAV nor gets swept by
 * [ExportFiles.pruneStale], and both are deleted however the export ends.
 * The finished mp4 is moved over the song's previous video only once it is
 * complete, so a failure or a cancel keeps the old one.
 */
object VideoExport {
    /** TikTok's upload limit, the longest of the three. WAV's own limit is
     * about 13 hours, which says nothing useful about a video. */
    const val MAX_SECONDS = 600.0

    const val SCRATCH_DIRECTORY = "video-scratch"

    /** The share of the progress bar the soundtrack takes. Drawing and
     * encoding the frames is most of the work. */
    private const val AUDIO_SHARE = 0.3

    fun render(request: ExportRequest, directory: File, writer: VideoWriter?): ExportResult {
        val song = request.song.normalized()
        val options = request.options.clamped.copy(format = ExportOptions.Format.VIDEO)
        val timeline = VideoTimeline(song, options)
        // Checked from the timeline before anything is rendered: finding out
        // after minutes of drawing frames would waste them on a predictable
        // refusal.
        if (timeline.seconds > MAX_SECONDS) return ExportResult.TooLong
        if (writer == null) return ExportResult.Failed(UnsupportedOperationException("This build can't write videos."))

        val scratch = File(directory, SCRATCH_DIRECTORY)
        // A render killed mid-way (a crash, the process killed in the
        // background) never reached its cleanup. Only one export runs at a
        // time (Studio refuses a second while one is running), so whatever
        // is in here belongs to a dead one.
        scratch.deleteRecursively()
        if (!scratch.isDirectory && !scratch.mkdirs()) {
            return ExportResult.Failed(IOException("Couldn't create $scratch"))
        }
        val stem = UUID.randomUUID().toString().uppercase()
        val soundtrack = File(scratch, "$stem.wav")
        val partial = File(scratch, "$stem.mp4")
        try {
            val audio = WavExport.render(
                ExportRequest(song, options, { request.progress(it * AUDIO_SHARE) }, request.isCanceled),
                directory,
                soundtrack,
            )
            if (audio !is ExportResult.Success) return audio

            var reported = AUDIO_SHARE
            val job = VideoJob(
                song = song,
                options = options,
                timeline = timeline,
                soundtrack = soundtrack,
                output = partial,
                progress = { fraction ->
                    val overall = AUDIO_SHARE + (1 - AUDIO_SHARE) * fraction.coerceIn(0.0, 1.0)
                    // Never backwards, and the final 1 is reported once the
                    // file is in place.
                    if (overall > reported && overall < 1.0) {
                        reported = overall
                        request.progress(overall)
                    }
                },
                isCanceled = request.isCanceled,
            )
            val encoded = try {
                writer.write(job)
            } catch (e: Exception) {
                ExportResult.Failed(e)
            }
            if (encoded !is ExportResult.Success) return encoded
            // Stopping the muxer takes a moment, and a cancel tapped during
            // it is still a cancel: the previous video stays and nothing is
            // shared.
            if (request.isCanceled()) return ExportResult.Canceled

            val destination = ExportFiles.file(song, directory, ExportOptions.Format.VIDEO)
            try {
                Files.move(partial.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
            } catch (e: IOException) {
                return ExportResult.Failed(e)
            } catch (e: SecurityException) {
                return ExportResult.Failed(e)
            }
            request.progress(1.0)
            return ExportResult.Success(destination)
        } finally {
            soundtrack.delete()
            partial.delete()
        }
    }
}
