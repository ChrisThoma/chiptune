package dev.individuation.chiptune.platform

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import dev.individuation.chiptune.core.studio.ExportKeepAlive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The app's [ExportKeepAlive], Android's counterpart of iOS's
 * `SystemExportKeepAlive`. While a video renders, [active] is true and the
 * root view keeps the screen on (`View.keepScreenOn`, which sets
 * FLAG_KEEP_SCREEN_ON on the activity's window), so the phone doesn't lock
 * and stop the activity halfway through a long render.
 *
 * It also notes whether the whole app left the foreground in between, from
 * [ProcessLifecycleOwner], which reports ON_STOP about 700 ms after the last
 * activity stops, so a rotation doesn't count. Once nothing of the app is on
 * screen the system may freeze the process, reclaim its codec or kill it, so
 * a video that fails after that says to keep Chiptune open.
 *
 * No foreground service: a render takes seconds on a phone, and one would
 * need a notification, the notification permission and a service type for
 * what keeping the screen on already covers.
 *
 * Main thread only, like the Studio that drives it.
 */
class ScreenOnExportKeepAlive : ExportKeepAlive, DefaultLifecycleObserver {
    private val mutableActive = MutableStateFlow(false)
    /** True while a video renders; the root view holds the screen on. */
    val active: StateFlow<Boolean> = mutableActive.asStateFlow()
    private var leftForeground = false

    init {
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStop(owner: LifecycleOwner) {
        if (mutableActive.value) leftForeground = true
    }

    override fun begin() {
        leftForeground = false
        mutableActive.value = true
    }

    override fun end(): Boolean {
        mutableActive.value = false
        return leftForeground
    }
}
