package dev.individuation.chiptune.platform

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import dev.individuation.chiptune.core.studio.Cancellable
import dev.individuation.chiptune.core.studio.Scheduler

/**
 * The Studio's [Scheduler] on the main looper. [now] is monotonic seconds
 * from `SystemClock.uptimeMillis`, the same clock `Handler` schedules on, so
 * a delay measured with [now] agrees with when the action fires.
 *
 * Not JVM-testable (it needs a Looper); the Studio's timer logic is covered
 * by the core tests' manual scheduler, and this is checked on the device.
 */
class AndroidScheduler(private val handler: Handler = Handler(Looper.getMainLooper())) : Scheduler {

    override fun now(): Double = SystemClock.uptimeMillis() / 1000.0

    override fun schedule(delaySeconds: Double, action: () -> Unit): Cancellable {
        val runnable = Runnable { action() }
        handler.postDelayed(runnable, toMillis(delaySeconds))
        return Cancellable { handler.removeCallbacks(runnable) }
    }

    override fun scheduleRepeating(intervalSeconds: Double, action: () -> Unit): Cancellable {
        val interval = maxOf(toMillis(intervalSeconds), 1L)
        val repeating = object : Runnable {
            private var next = SystemClock.uptimeMillis() + interval
            var canceled = false

            override fun run() {
                if (canceled) return
                // Aim each tick at a fixed grid so the poll doesn't drift,
                // but skip missed ticks rather than firing a burst.
                val now = SystemClock.uptimeMillis()
                next += interval
                if (next <= now) next = now + interval
                handler.postAtTime(this, next)
                action()
            }

            fun start() {
                handler.postAtTime(this, next)
            }
        }
        repeating.start()
        return Cancellable {
            repeating.canceled = true
            handler.removeCallbacks(repeating)
        }
    }

    /** Handler.post is thread-safe. */
    override fun post(action: () -> Unit) {
        handler.post { action() }
    }

    private fun toMillis(seconds: Double): Long = maxOf(0L, Math.round(seconds * 1000.0))
}
