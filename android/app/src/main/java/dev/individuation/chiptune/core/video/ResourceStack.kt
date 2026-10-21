package dev.individuation.chiptune.core.video

/**
 * Releases what a video writer opened, in reverse order, exactly once,
 * however far it got. `platform/video/Mp4Writer` opens its frame drawer,
 * conversion threads, two MediaCodec encoders, the muxer and the
 * soundtrack's stream through one, so a start that fails part-way (every
 * configure refused, the muxer unable to open the file, a short soundtrack)
 * still hands back every encoder it took. A phone has only a few hardware
 * codec instances, and leaked ones stay taken until the process dies.
 *
 * A release that throws is ignored, so one codec refusing to stop never
 * keeps the rest from being released. Not thread-safe: one writer's thread
 * opens and closes it.
 */
class ResourceStack : AutoCloseable {
    private val releases = ArrayList<() -> Unit>()

    /** Creates a resource and remembers how to release it. If [create]
     * throws, nothing was opened and nothing is remembered. */
    fun <T> open(create: () -> T, release: (T) -> Unit): T {
        val resource = create()
        releases.add { release(resource) }
        return resource
    }

    /** Releases everything opened, newest first. Closing again does nothing. */
    override fun close() {
        while (releases.isNotEmpty()) {
            val release = releases.removeAt(releases.lastIndex)
            try {
                release()
            } catch (_: Exception) {
                // Best effort: the next one still gets its turn.
            }
        }
    }
}
