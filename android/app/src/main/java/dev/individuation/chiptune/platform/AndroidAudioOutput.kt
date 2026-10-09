package dev.individuation.chiptune.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import androidx.core.content.ContextCompat
import dev.individuation.chiptune.core.audio.ChipCore
import dev.individuation.chiptune.core.audio.PcmSink
import dev.individuation.chiptune.core.audio.PcmWriteLoop
import dev.individuation.chiptune.core.studio.AudioFocusDeniedException
import dev.individuation.chiptune.core.studio.AudioOutput

/** The device's native output rate, which the [ChipCore] must be built at
 * so the mixer never resamples (and a fast track is possible). */
object AudioRate {
    const val FALLBACK = 48000.0

    fun native(context: Context): Double {
        val manager = context.getSystemService(AudioManager::class.java)
        val rate = manager?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
        return if (rate != null && rate > 0) rate.toDouble() else FALLBACK
    }
}

/** What the output reports to the app; the app graph points these at the
 * Studio's hooks. Always called on the main thread. */
interface AudioOutputEvents {
    fun onAudioFocusLost()
    fun onAudioFocusGained()
    fun onBecomingNoisy()
    fun onAudioOutputDead()
}

/**
 * Live playback through an [AudioTrack] (iOS's `AudioEngine`): float mono at
 * the core's rate, fed by a dedicated URGENT_AUDIO thread running a
 * [PcmWriteLoop]. The track, its thread, the focus request and the
 * becoming-noisy receiver all exist only while the engine runs.
 *
 * Buffering: the track's capacity is two of `getMinBufferSize`, but only
 * one minimum is used at first (`setBufferSizeInFrames`); the first underrun
 * grows it to the full capacity ([UnderrunAdaptingSink]). The loop writes
 * one HAL burst (`PROPERTY_OUTPUT_FRAMES_PER_BUFFER`) at a time, capped at
 * half the used buffer. With a blocking write the loop keeps the buffer
 * full, so output latency is about the used buffer plus the mixer and HAL
 * pipeline: a few ms on a device with a FastMixer, ~180 ms on the emulator,
 * whose mixer has no fast path and reports a large minimum. Latency only
 * delays keyboard previews and the drawn playhead; tempo is counted in
 * samples, so the song stays in time whatever it is.
 *
 * Audio focus (iOS's interruptions): a permanent or transient loss calls
 * `onAudioFocusLost`, regaining it calls `onAudioFocusGained`; ducking is
 * left to the system. A transient loss keeps the focus request alive so the
 * gain callback can still arrive; every other stop abandons focus.
 *
 * All methods but the render thread's are main-thread only.
 */
class AndroidAudioOutput(
    context: Context,
    private val core: ChipCore,
) : AudioOutput {
    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(AudioManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Set by the app graph once the Studio exists. */
    var events: AudioOutputEvents? = null

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                transientLoss = false
                events?.onAudioFocusLost()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                transientLoss = true
                events?.onAudioFocusLost()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (transientLoss) {
                    transientLoss = false
                    events?.onAudioFocusGained()
                }
            }
            // LOSS_TRANSIENT_CAN_DUCK: the system lowers our volume itself.
        }
    }

    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(attributes)
        .setWillPauseWhenDucked(false)
        .setOnAudioFocusChangeListener(focusListener, mainHandler)
        .build()

    /** Focus was lost for a while; keep the request so its GAIN arrives. */
    private var transientLoss = false
    private var holdsFocus = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) events?.onBecomingNoisy()
        }
    }
    private var noisyRegistered = false

    private var track: AudioTrack? = null
    private var loop: PcmWriteLoop? = null
    private var thread: Thread? = null

    override var isRunning: Boolean = false
        private set

    override var lastError: Throwable? = null
        private set

    override fun startIfNeeded(): Boolean {
        if (isRunning) return true
        // During a transient loss the request is still held but focus isn't:
        // ask again, so Play during a call is refused rather than talking over it.
        if (!holdsFocus || transientLoss) {
            val result = audioManager.requestAudioFocus(focusRequest)
            if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                lastError = AudioFocusDeniedException()
                return false
            }
            holdsFocus = true
        }
        transientLoss = false
        val newTrack = try {
            buildTrack()
        } catch (e: Exception) {
            Log.w(TAG, "AudioTrack build failed", e)
            lastError = e
            abandonFocus()
            return false
        }
        try {
            newTrack.play()
        } catch (e: Exception) {
            Log.w(TAG, "AudioTrack play failed", e)
            newTrack.release()
            lastError = e
            abandonFocus()
            return false
        }
        val chunk = chunkFrames(newTrack)
        val sink = UnderrunAdaptingSink(newTrack)
        lateinit var newLoop: PcmWriteLoop
        newLoop = PcmWriteLoop(core, sink, chunk) {
            // Render thread; the loop guarantees one call per death. Ignore
            // a death report from a loop that has since been replaced.
            mainHandler.post { if (loop === newLoop) events?.onAudioOutputDead() }
        }
        val newThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            newLoop.run()
        }, "chiptune-audio")
        track = newTrack
        loop = newLoop
        thread = newThread
        newThread.start()
        registerNoisy()
        isRunning = true
        lastError = null
        Log.i(
            TAG,
            "started: rate=${newTrack.sampleRate} buffer=${newTrack.bufferSizeInFrames}/" +
                "${newTrack.bufferCapacityInFrames} frames " +
                "chunk=$chunk perfMode=${newTrack.performanceMode}",
        )
        return true
    }

    override fun stopEngine() {
        if (!transientLoss) abandonFocus()
        unregisterNoisy()
        val oldTrack = track
        val oldLoop = loop
        val oldThread = thread
        track = null
        loop = null
        thread = null
        isRunning = false
        if (oldTrack == null) return
        oldLoop?.requestStop()
        // pause() makes a blocking write return early, so the join is quick.
        runCatching { oldTrack.pause() }
        runCatching { oldTrack.flush() }
        oldThread?.join(JOIN_TIMEOUT_MS)
        if (oldThread?.isAlive == true) Log.w(TAG, "render thread did not stop within $JOIN_TIMEOUT_MS ms")
        Log.i(
            TAG,
            "stopped: underruns=${runCatching { oldTrack.underrunCount }.getOrDefault(-1)} " +
                "buffer=${runCatching { oldTrack.bufferSizeInFrames }.getOrDefault(-1)}",
        )
        runCatching { oldTrack.stop() }
        oldTrack.release()
    }

    /** The track is built on each start, so a rebuild is a clean stop that
     * also forgets a pending transient loss. */
    override fun rebuild() {
        transientLoss = false
        stopEngine()
    }

    private fun buildTrack(): AudioTrack {
        val rate = core.sampleRate.toInt()
        val minBytes = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        require(minBytes > 0) { "AudioTrack.getMinBufferSize failed ($minBytes) at $rate Hz" }
        val built = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(minBytes * BUFFER_MULTIPLE)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        // Capacity is two minimums, but only one is used: that's the latency
        // the device says it can sustain, and the spare capacity lets
        // [UnderrunAdaptingSink] back off without rebuilding the track.
        runCatching { built.setBufferSizeInFrames(minBytes / BYTES_PER_FRAME) }
        return built
    }

    private fun chunkFrames(track: AudioTrack): Int {
        val burst = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull()
            ?.takeIf { it > 0 } ?: FALLBACK_BURST
        return burst.coerceAtMost(maxOf(track.bufferSizeInFrames / 2, 1))
    }

    private fun abandonFocus() {
        if (holdsFocus) {
            audioManager.abandonAudioFocusRequest(focusRequest)
            holdsFocus = false
        }
        transientLoss = false
    }

    private fun registerNoisy() {
        if (noisyRegistered) return
        // A system broadcast; NOT_EXPORTED keeps other apps from faking it
        // and is still delivered system broadcasts.
        ContextCompat.registerReceiver(
            appContext,
            noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        noisyRegistered = true
    }

    private fun unregisterNoisy() {
        if (!noisyRegistered) return
        appContext.unregisterReceiver(noisyReceiver)
        noisyRegistered = false
    }

    companion object {
        private const val TAG = "ChiptuneAudio"
        private const val BUFFER_MULTIPLE = 2
        private const val BYTES_PER_FRAME = 4 // mono float
        private const val FALLBACK_BURST = 256
        private const val JOIN_TIMEOUT_MS = 1000L
    }
}

/**
 * Writes to the track on the render thread, and the first time the track
 * underruns grows its used buffer to the full capacity (one JNI call per
 * write to read the count; nothing allocated). Starting at the minimum keeps
 * latency low where the device keeps up; one glitch buys the margin back.
 */
private class UnderrunAdaptingSink(private val track: AudioTrack) : PcmSink {
    private var grown = false

    override fun write(buffer: FloatArray, offset: Int, frames: Int): Int {
        val result = track.write(buffer, offset, frames, AudioTrack.WRITE_BLOCKING)
        if (!grown && track.underrunCount > 0) {
            grown = true
            track.setBufferSizeInFrames(track.bufferCapacityInFrames)
        }
        return result
    }
}
