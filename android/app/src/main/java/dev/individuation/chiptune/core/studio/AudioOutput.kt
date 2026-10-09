package dev.individuation.chiptune.core.studio

/**
 * The live audio output a [Studio] drives (iOS's `AudioEngine`, minus the
 * DSP). The platform implementation pulls samples from `Studio.core` through
 * a `RenderSlicer` on its own thread; the Studio only starts and stops it.
 *
 * The platform layer reports system events by calling the Studio's hooks:
 * audio-focus loss -> `onAudioFocusLost`, focus regained ->
 * `onAudioFocusGained`, `ACTION_AUDIO_BECOMING_NOISY` -> `onBecomingNoisy`,
 * a write that returns `ERROR_DEAD_OBJECT` -> `onAudioOutputDead` (posted to
 * the main thread).
 */
interface AudioOutput {
    val isRunning: Boolean

    /** Why the last [startIfNeeded] failed, for the "Audio unavailable" alert.
     * [AudioFocusDeniedException] when another app or a call holds audio. */
    val lastError: Throwable?

    /** Starts the output; safe to call repeatedly. Returns whether audio is
     * running -- a PLAY button that lights up over silence is worse than an error. */
    fun startIfNeeded(): Boolean

    fun stopEngine()

    /** Throws away the dead output and builds a fresh one around the same
     * core, stopped. The Studio pushes the whole song again afterwards. */
    fun rebuild()
}

/** Audio focus was refused -- the Android form of iOS's busy audio session. */
class AudioFocusDeniedException : Exception("Audio focus was not granted")
