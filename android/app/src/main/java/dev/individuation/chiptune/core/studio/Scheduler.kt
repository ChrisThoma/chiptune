package dev.individuation.chiptune.core.studio

/** A scheduled action that can be called off. */
fun interface Cancellable {
    fun cancel()
}

/**
 * Time and the main thread, injected so the Studio stays pure JVM: the 1.5 s
 * autosave debounce, the 1.0 s undo coalescing window and the ~60 Hz playhead
 * poll all run on it, and tests drive it by hand instead of sleeping.
 *
 * Every Studio call is made on one thread (the main thread in the app); the
 * scheduler runs its actions there too. [post] is the one method that may be
 * called from any thread -- the export renderer uses it to hand results back.
 */
interface Scheduler {
    /** Monotonic seconds. */
    fun now(): Double

    fun schedule(delaySeconds: Double, action: () -> Unit): Cancellable

    /** First fires after one interval, then every interval until canceled. */
    fun scheduleRepeating(intervalSeconds: Double, action: () -> Unit): Cancellable

    /** Runs [action] on the Studio's thread. Callable from any thread. */
    fun post(action: () -> Unit)
}
