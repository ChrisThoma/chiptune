package dev.individuation.chiptune.ui.editor

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * Small tactile cues for the primary actions (port of `Haptics.swift`).
 * `View.performHapticFeedback` honours the system's touch-feedback setting.
 */
@Stable
class Haptics(private val view: View) {
    /** A grid cell tap; iOS's light impact. */
    fun gridCell() = perform(HapticFeedbackConstants.CLOCK_TICK)

    /** Play/Stop; iOS's medium impact. */
    fun transport() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)

    /** A long press picked the tracks up for reordering. */
    fun reorderBegan() = perform(HapticFeedbackConstants.LONG_PRESS)

    /** A dragged track crossed into another column; iOS's selection tick. */
    fun reorderStep() = perform(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK)

    /** An export finished; iOS's success notification. */
    fun exportSucceeded() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)

    private fun perform(constant: Int) {
        view.performHapticFeedback(constant)
    }
}

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}
