package dev.individuation.chiptune.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import dev.individuation.chiptune.ChiptuneApp
import dev.individuation.chiptune.core.studio.Studio
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Hands the process-wide [Studio] to the UI; it owns nothing itself. Until
 * the Studio is ready [studio] is null and the splash shows.
 *
 * The launch sequence copies iOS's: let the splash paint (40 ms), build the
 * Studio on the main thread (it reads the library and last song from disk,
 * and is single-threaded), hold the splash a beat (250 ms) and let the UI
 * fade it out. A recreated activity finds the Studio already built and
 * skips the splash.
 */
class StudioViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as ChiptuneApp
    private val mutableStudio = MutableStateFlow(app.studio)
    val studio: StateFlow<Studio?> = mutableStudio.asStateFlow()

    init {
        if (mutableStudio.value == null) {
            viewModelScope.launch {
                delay(SPLASH_PAINT_MS)
                val built = app.buildStudio()
                delay(SPLASH_HOLD_MS)
                mutableStudio.value = built
            }
        }
    }

    companion object {
        const val SPLASH_PAINT_MS = 40L
        const val SPLASH_HOLD_MS = 250L
    }
}
