package dev.individuation.chiptune.core.studio

/**
 * Keeps a video render going while it runs: begun when the render starts,
 * ended once however it finishes. Both are called on the Studio's thread.
 * Port of iOS's `ExportKeepAlive`; the app's (`platform/ScreenOnExportKeepAlive`)
 * keeps the screen on and notes whether the app left the foreground.
 */
interface ExportKeepAlive {
    fun begin()

    /** Lets go, and says whether the app left the foreground in between:
     * what decides if a failed render is blamed on that. */
    fun end(): Boolean

    /** For tests and any caller with no screen to hold. */
    object None : ExportKeepAlive {
        override fun begin() = Unit
        override fun end(): Boolean = false
    }
}
