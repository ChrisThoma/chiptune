package dev.individuation.chiptune.platform.video

import android.content.res.Resources
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import dev.individuation.chiptune.core.audio.ExportResult
import dev.individuation.chiptune.core.video.VideoJob
import dev.individuation.chiptune.core.video.VideoLayout
import dev.individuation.chiptune.core.video.VideoTimeline
import dev.individuation.chiptune.core.video.VideoWriter
import dev.individuation.chiptune.core.video.Yuv
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.IntBuffer
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Encodes a [VideoJob] as an H.264/AAC mp4 with MediaCodec and MediaMuxer:
 * 1080x1920 at 30 fps and about 8 Mbps, mono AAC at 128 kbps and 44.1 kHz.
 * The Android counterpart of the encoding half of `Sources/Video/VideoExport.swift`.
 *
 * Every frame is drawn by [VideoFrameDrawer], converted to YUV 4:2:0 with
 * [Yuv] straight into the encoder's input image (whatever plane layout the
 * device uses), and stamped with an explicit presentation time from the
 * frame number, so the picture runs at exactly 30 fps against the audio.
 * For speed, the conversion is split into bands on a few threads, and the
 * next frame is drawn while the current one converts; the bitmap's memory is
 * copied out as it is rather than unpacked pixel by pixel. The
 * soundtrack's PCM is fed to the AAC encoder from the scratch WAV, timed by
 * sample count, and kept no more than a second ahead of the pictures so
 * neither stream waits long on the other.
 *
 * Not unit-tested: MediaCodec only exists on a device, and the app has no
 * instrumented suite. Everything it is driven by (the timeline, the layout,
 * the pulse, the YUV conversion, the scratch-and-move around it) is tested
 * in core; this file is checked by exporting on a phone and probing the file.
 */
class Mp4Writer(private val resources: Resources) : VideoWriter {

    override fun write(job: VideoJob): ExportResult {
        val drawer = VideoFrameDrawer(resources, job.song, job.options, job.timeline)
        val session = try {
            Session(job, drawer)
        } catch (e: Exception) {
            return ExportResult.Failed(e)
        }
        return try {
            session.run()
        } catch (e: Exception) {
            ExportResult.Failed(e)
        } finally {
            session.release()
            drawer.recycle()
        }
    }

    private class Pending(val track: Int, val data: ByteArray, val info: MediaCodec.BufferInfo)

    private class Session(private val job: VideoJob, private val drawer: VideoFrameDrawer) {
        private val width = VideoLayout.WIDTH
        private val height = VideoLayout.HEIGHT
        private val totalFrames = job.timeline.totalFrames

        /** Two frames' pixels: [ready] holds frame [readyFrame], converting,
         * while the next is drawn into [spare]. In the bitmap's own memory
         * order (see [Yuv.Order.ABGR]). */
        private var ready = IntArray(width * height)
        private var spare = IntArray(width * height)
        private var readyFrame = -1

        /** Converts each frame in [BANDS] horizontal bands at once. */
        private val converters: ExecutorService = Executors.newFixedThreadPool(BANDS) { task ->
            Thread(task, "VideoYuv").apply { isDaemon = true }
        }

        private fun render(frame: Int, into: IntArray) {
            drawer.draw(frame).copyPixelsToBuffer(IntBuffer.wrap(into))
        }

        private val video: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        private val audio: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        private val muxer = MediaMuxer(job.output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        private val pcm = FileInputStream(job.soundtrack)

        private var videoTrack = -1
        private var audioTrack = -1
        private var muxing = false
        private val pending = ArrayList<Pending>()

        private var frame = 0
        private var videoInputDone = false
        private var videoOutputDone = false
        private var samplesFed = 0L
        private val totalSamples = job.timeline.totalSamples.toLong()
        private var audioInputDone = false
        private var audioOutputDone = false
        private val info = MediaCodec.BufferInfo()

        /** The encoder's settings. [unthrottled] asks it to run flat out:
         * left to [MediaFormat.KEY_FRAME_RATE] alone, an encoder may clock
         * itself for 30 fps live capture (the Pixel 3 XL's managed about 46
         * fps, slower than the frames could be drawn). The rate and the
         * non-realtime priority are what Android's own transcoder asks for
         * at 1080p. */
        private fun videoFormat(unthrottled: Boolean, srgb: Boolean): MediaFormat =
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, VIDEO_BIT_RATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, VideoTimeline.FPS)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
                if (unthrottled) {
                    setInteger(MediaFormat.KEY_OPERATING_RATE, OPERATING_RATE)
                    setInteger(MediaFormat.KEY_PRIORITY, 1)
                }
                // Tagged explicitly, as iOS does, so players don't guess at
                // the theme colours. Yuv converts with BT.709's matrix into
                // limited range, and 709's primaries are sRGB's. The frames
                // are drawn in sRGB, so the transfer is sRGB's: tagged 709's
                // curve, a player that honours it shows every mid-grey
                // lighter than drawn (iOS 7f82f90). An encoder that refuses
                // the sRGB tag gets 709's rather than no video.
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, if (srgb) COLOR_TRANSFER_SRGB else MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                // High profile, as iOS writes, where the encoder offers it:
                // Baseline blocks up the near-black background on the
                // opening keyframe.
                val profiles = video.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).profileLevels
                profiles.filter { it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh }
                    .maxByOrNull { it.level }?.let {
                        setInteger(MediaFormat.KEY_PROFILE, it.profile)
                        setInteger(MediaFormat.KEY_LEVEL, minOf(it.level, MediaCodecInfo.CodecProfileLevel.AVCLevel42))
                    }
            }

        init {
            // An encoder that refuses the operating rate still encodes at its
            // own pace; one that refuses the sRGB tag gets 709's.
            val attempts = listOf(true to true, false to true, true to false, false to false)
            for ((index, attempt) in attempts.withIndex()) {
                try {
                    video.configure(videoFormat(attempt.first, attempt.second), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    break
                } catch (e: Exception) {
                    if (index == attempts.lastIndex) throw e
                    video.reset()
                }
            }
            val audioFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, AUDIO_CHUNK_SAMPLES * 2)
            }
            audio.configure(audioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            video.start()
            audio.start()
            // The canonical 44-byte header VideoExport's WavExport writes.
            if (pcm.skip(WAV_HEADER.toLong()) != WAV_HEADER.toLong()) throw IOException("The soundtrack is cut short.")
        }

        fun run(): ExportResult {
            while (!videoOutputDone || !audioOutputDone) {
                if (job.isCanceled()) return ExportResult.Canceled
                var moved = feedVideo()
                moved = feedAudio() or moved
                moved = drain(video, isVideo = true) or moved
                moved = drain(audio, isVideo = false) or moved
                if (!moved) Thread.sleep(1)
            }
            muxer.stop()
            muxing = false
            return ExportResult.Success(job.output)
        }

        private fun presentationUs(frame: Int): Long = frame.toLong() * 1_000_000L / VideoTimeline.FPS

        private fun feedVideo(): Boolean {
            if (videoInputDone) return false
            val index = video.dequeueInputBuffer(0)
            if (index < 0) return false
            if (frame >= totalFrames) {
                video.queueInputBuffer(index, 0, 0, presentationUs(frame), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                videoInputDone = true
                return true
            }
            val image = video.getInputImage(index) ?: throw IOException("The video encoder gave no input image.")
            if (readyFrame != frame) {
                render(frame, ready)
                readyFrame = frame
            }
            val planes = image.planes
            val y = Yuv.Plane(planes[0].buffer, 0, planes[0].rowStride, planes[0].pixelStride)
            val u = Yuv.Plane(planes[1].buffer, 0, planes[1].rowStride, planes[1].pixelStride)
            val v = Yuv.Plane(planes[2].buffer, 0, planes[2].rowStride, planes[2].pixelStride)
            val pixels = ready
            val chromaHeight = (height + 1) / 2
            val bands = (0 until BANDS).map { band ->
                converters.submit {
                    Yuv.fromArgb(pixels, width, height, y, u, v, Yuv.Order.ABGR,
                        chromaRows = band * chromaHeight / BANDS until (band + 1) * chromaHeight / BANDS)
                }
            }
            // The next frame is drawn while this one converts. However the
            // drawing ends, every band is waited for before going on, so none
            // is still writing into the image when the encoder takes it back.
            var failure: Throwable? = null
            try {
                if (frame + 1 < totalFrames) {
                    render(frame + 1, spare)
                    spare = ready.also { ready = spare }
                    readyFrame = frame + 1
                }
            } catch (e: Throwable) {
                failure = e
            }
            for (band in bands) {
                try {
                    band.get()
                } catch (e: ExecutionException) {
                    if (failure == null) failure = e.cause ?: e
                }
            }
            failure?.let { throw it }
            val size = video.getInputBuffer(index)?.capacity() ?: (width * height * 3 / 2)
            video.queueInputBuffer(index, 0, size, presentationUs(frame), 0)
            frame += 1
            job.progress(frame.toDouble() / totalFrames)
            return true
        }

        private fun feedAudio(): Boolean {
            if (audioInputDone) return false
            // Stay within a second of the pictures, unless they're all in.
            val audioUs = samplesFed * 1_000_000L / SAMPLE_RATE
            if (!videoInputDone && audioUs > presentationUs(frame) + 1_000_000L) return false
            val index = audio.dequeueInputBuffer(0)
            if (index < 0) return false
            val remaining = totalSamples - samplesFed
            if (remaining <= 0) {
                audio.queueInputBuffer(index, 0, 0, audioUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                audioInputDone = true
                return true
            }
            val buffer: ByteBuffer = audio.getInputBuffer(index) ?: throw IOException("The audio encoder gave no input buffer.")
            buffer.clear()
            val samples = minOf(remaining, minOf(AUDIO_CHUNK_SAMPLES, buffer.capacity() / 2).toLong()).toInt()
            val bytes = ByteArray(samples * 2)
            var read = 0
            while (read < bytes.size) {
                val n = pcm.read(bytes, read, bytes.size - read)
                if (n < 0) throw IOException("The soundtrack is cut short.")
                read += n
            }
            buffer.put(bytes)
            audio.queueInputBuffer(index, 0, bytes.size, audioUs, 0)
            samplesFed += samples
            return true
        }

        private fun drain(codec: MediaCodec, isVideo: Boolean): Boolean {
            if (if (isVideo) videoOutputDone else audioOutputDone) return false
            var moved = false
            while (true) {
                val index = codec.dequeueOutputBuffer(info, 0)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> return moved
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val track = muxer.addTrack(codec.outputFormat)
                        if (isVideo) videoTrack = track else audioTrack = track
                        startMuxerWhenReady()
                        moved = true
                    }
                    index >= 0 -> {
                        val output = codec.getOutputBuffer(index) ?: throw IOException("An encoder gave no output buffer.")
                        val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        if (!config && info.size > 0) write(if (isVideo) videoTrack else audioTrack, output, info)
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            if (isVideo) videoOutputDone = true else audioOutputDone = true
                            return true
                        }
                        moved = true
                    }
                    else -> return moved
                }
            }
        }

        /** The muxer can't start until both tracks are known; anything
         * encoded before then waits. */
        private fun write(track: Int, output: ByteBuffer, info: MediaCodec.BufferInfo) {
            output.position(info.offset)
            output.limit(info.offset + info.size)
            if (muxing) {
                muxer.writeSampleData(track, output, info)
                return
            }
            val data = ByteArray(info.size)
            output.get(data)
            val copy = MediaCodec.BufferInfo().apply { set(0, info.size, info.presentationTimeUs, info.flags) }
            pending.add(Pending(track, data, copy))
        }

        private fun startMuxerWhenReady() {
            if (muxing || videoTrack < 0 || audioTrack < 0) return
            muxer.start()
            muxing = true
            for (p in pending) muxer.writeSampleData(p.track, ByteBuffer.wrap(p.data), p.info)
            pending.clear()
        }

        fun release() {
            converters.shutdownNow()
            runCatching { pcm.close() }
            runCatching { video.stop() }
            runCatching { video.release() }
            runCatching { audio.stop() }
            runCatching { audio.release() }
            if (muxing) runCatching { muxer.stop() }
            runCatching { muxer.release() }
        }
    }

    private companion object {
        const val SAMPLE_RATE = 44100
        const val VIDEO_BIT_RATE = 8_000_000
        const val AUDIO_BIT_RATE = 128_000
        const val AUDIO_CHUNK_SAMPLES = 4096
        const val WAV_HEADER = 44
        /** Threads converting each frame to YUV: the Pixel 3 XL's four big
         * cores, while the encoder thread draws the next frame. */
        const val BANDS = 4
        /** Frames a second the encoder is asked to be able to take. */
        const val OPERATING_RATE = 240
        /** sRGB's transfer function (H.264 transfer_characteristics 13).
         * MediaFormat names only LINEAR (1), SDR_VIDEO (3), ST2084 (6) and
         * HLG (7), but KEY_COLOR_TRANSFER takes the platform's ColorAspects
         * numbering, in which 2 is kColorTransferSRGB. */
        const val COLOR_TRANSFER_SRGB = 2
    }
}
