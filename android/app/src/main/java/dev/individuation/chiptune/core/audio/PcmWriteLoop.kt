package dev.individuation.chiptune.core.audio

/**
 * Where the write loop sends PCM: an `AudioTrack` in the app, a recording
 * fake in tests. Mirrors `AudioTrack.write(float[], int, int, WRITE_BLOCKING)`:
 * returns how many frames were taken (possibly fewer than offered, or 0 when
 * the track has been paused or stopped), or a negative error code.
 */
fun interface PcmSink {
    fun write(buffer: FloatArray, offset: Int, frames: Int): Int

    companion object {
        /** The `AudioTrack` constants, copied so core stays platform-free. */
        const val ERROR = -1
        const val ERROR_BAD_VALUE = -2
        const val ERROR_INVALID_OPERATION = -3
        const val ERROR_DEAD_OBJECT = -6
    }
}

/**
 * The body of the AudioTrack write thread, platform-free so it is tested on
 * the JVM. Each [step] renders one chunk of [chunkFrames] through a
 * [RenderSlicer] into a preallocated buffer and hands it to the sink until
 * all of it is taken. Nothing is allocated per step.
 *
 * Any negative write result means the track is unusable: `ERROR_DEAD_OBJECT`
 * is the media server dying (iOS's media-services reset), and `ERROR` /
 * `ERROR_INVALID_OPERATION` leave a track that will never play again either.
 * The loop then stops for good and calls [onDead] exactly once; the owner
 * builds a new track and a new loop.
 *
 * Threading: [run] and [step] belong to the render thread. [requestStop] may
 * be called from any thread; a blocked write returns once the owner pauses
 * the track, and the loop then sees the flag.
 */
class PcmWriteLoop(
    core: ChipCore,
    private val sink: PcmSink,
    chunkFrames: Int,
    private val onDead: () -> Unit,
) {
    private val slicer = RenderSlicer(core, scratchLength = chunkFrames)
    private val buffer = FloatArray(chunkFrames)

    @Volatile private var stopRequested = false
    @Volatile var isDead = false
        private set

    fun requestStop() {
        stopRequested = true
    }

    /** Loops [step] until a stop is requested or the sink dies. */
    fun run() {
        while (!stopRequested && step()) {
            // step() did the work.
        }
    }

    /** Renders and writes one chunk. Returns false once the sink is dead
     * (and from then on), true otherwise -- including when a stop request
     * cut the chunk short. */
    fun step(): Boolean {
        if (isDead) return false
        val frames = buffer.size
        slicer.fill(buffer, frames)
        var written = 0
        while (written < frames) {
            val result = sink.write(buffer, written, frames - written)
            if (result < 0) {
                isDead = true
                onDead()
                return false
            }
            if (result == 0) {
                // A paused or stopped track takes nothing; if we asked for
                // that, drop the rest of the chunk. Otherwise retry.
                if (stopRequested) return true
                Thread.yield()
                continue
            }
            written += result
        }
        return true
    }
}
