package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.store.KeyValueStore
import java.io.File
import java.util.UUID

/*
 * Pure policies the views lean on, ported from the SwiftUI views so they stay
 * testable without a window: `ScenePhasePolicy` (ChiptuneApp.swift),
 * `ReviewPromptPolicy`, `SongLibraryPresentation`, `PresentedSurfaces`,
 * `ExportFlow`, `KeyboardShortcutsMenuVisibility` (ContentView.swift),
 * `EditorPresentation`, `SongBoundPresenters` (EditorCommands.swift) and
 * `ConfirmationCopy` (ViewModifiers.swift).
 */

/** iOS scene phases, as Android lifecycle events reach them: ACTIVE is
 * ON_RESUME, INACTIVE is ON_PAUSE (a dialog or the shade over the app),
 * BACKGROUND is ON_STOP. */
enum class AppPhase {
    ACTIVE, INACTIVE, BACKGROUND;

    companion object {
        /** From `Lifecycle.Event.name`; null for events that change nothing. */
        fun fromLifecycleEvent(name: String): AppPhase? = when (name) {
            "ON_RESUME" -> ACTIVE
            "ON_PAUSE" -> INACTIVE
            "ON_STOP" -> BACKGROUND
            else -> null
        }
    }
}

/** What leaving the foreground does. Any phase but ACTIVE saves -- the one
 * moment autosave's debounce might not have fired. Only BACKGROUND stops the
 * engine: the shade or a dialog over the app must not cut the song off. */
object ScenePhasePolicy {
    fun savesNow(entering: AppPhase): Boolean = entering != AppPhase.ACTIVE

    fun stopsEngine(entering: AppPhase): Boolean = entering == AppPhase.BACKGROUND
}

/** What became of the share sheet the review prompt is gated behind. */
enum class ShareOutcome { COMPLETED, CANCELED, FAILED }

/** When to ask for a review: at the third successful export, then every ten
 * after the last ask, and only once a share actually went somewhere. */
object ReviewPromptPolicy {
    const val FIRST_REQUEST_EXPORT_COUNT = 3
    const val RETRY_INTERVAL = 10

    data class AfterDismiss(val shouldRequestReview: Boolean, val lastRequestExportCount: Int)

    fun isDue(successfulExports: Int, lastRequestExportCount: Int): Boolean {
        if (successfulExports < FIRST_REQUEST_EXPORT_COUNT) return false
        if (lastRequestExportCount <= 0) return true
        if (successfulExports < lastRequestExportCount) return false
        return successfulExports - lastRequestExportCount >= RETRY_INTERVAL
    }

    fun shouldRequest(eligible: Boolean, outcome: ShareOutcome): Boolean =
        eligible && outcome == ShareOutcome.COMPLETED

    /** A skipped request leaves the count alone, so a canceled share doesn't
     * spend the milestone. */
    fun afterShareDismiss(
        eligible: Boolean,
        outcome: ShareOutcome,
        successfulExports: Int,
        lastRequestExportCount: Int,
    ): AfterDismiss {
        if (!shouldRequest(eligible, outcome)) return AfterDismiss(false, lastRequestExportCount)
        return AfterDismiss(true, successfulExports)
    }
}

/**
 * The review prompt's state, persisted the way iOS's `@AppStorage` keeps it.
 * Call [exportSucceeded] when a WAV export publishes its file and
 * [shareDismissed] when the share sheet that followed closes; ask the store
 * for a review when the latter returns true.
 */
class ReviewPromptTracker(private val prefs: KeyValueStore) {
    private var reviewAfterSharing = false

    /** Counts the export; returns whether the share that follows is eligible. */
    fun exportSucceeded(): Boolean {
        val count = prefs.getInt(SUCCESSFUL_EXPORTS_KEY) + 1
        prefs.putInt(SUCCESSFUL_EXPORTS_KEY, count)
        reviewAfterSharing = ReviewPromptPolicy.isDue(count, prefs.getInt(LAST_REQUEST_KEY))
        return reviewAfterSharing
    }

    /** Whether to request a review now. */
    fun shareDismissed(outcome: ShareOutcome): Boolean {
        val result = ReviewPromptPolicy.afterShareDismiss(
            reviewAfterSharing, outcome, prefs.getInt(SUCCESSFUL_EXPORTS_KEY), prefs.getInt(LAST_REQUEST_KEY),
        )
        reviewAfterSharing = false
        prefs.putInt(LAST_REQUEST_KEY, result.lastRequestExportCount)
        return result.shouldRequestReview
    }

    companion object {
        const val SUCCESSFUL_EXPORTS_KEY = "successfulExportCount"
        const val LAST_REQUEST_KEY = "lastReviewRequestExportCount"
    }
}

/** Presentation guards for shortcuts and menu entries. */
object EditorPresentation {
    /** A second presentation while one is up would be lost or appear later
     * on its own, so screens only open with nothing presented. */
    fun canOpen(anyPresented: Boolean): Boolean = !anyPresented

    /** Whether a chord may change the song (undo, redo, new, duplicate, add
     * pattern, share): not while a dialog holds state read from it. */
    fun canChangeSong(songBoundPresented: Boolean): Boolean = !songBoundPresented

    /** Whether a shortcut's row shows as enabled. */
    fun commandEnabled(hasEditor: Boolean, canChangeSong: Boolean): Boolean = hasEditor && canChangeSong
}

/** The presenters that capture state from the current song. Immutable, so it
 * can live in [StudioState]; [set] returns the updated set. */
data class SongBoundPresenters(private val active: Set<Surface> = emptySet()) {
    enum class Surface { PATTERN_RENAME, PATTERN_CLEAR, PATTERN_DELETE, TEMPO_ALERT, TRACK_SOUND }

    val isPresented: Boolean get() = active.isNotEmpty()

    fun set(surface: Surface, presented: Boolean): SongBoundPresenters =
        SongBoundPresenters(if (presented) active + surface else active - surface)
}

object SongLibraryPresentation {
    /** Opening a different song routes back to the editor. */
    fun afterOpeningSong(isPresented: Boolean, previousSongID: UUID, currentSongID: UUID): Boolean =
        isPresented && previousSongID == currentSongID
}

/** Every surface that edits or exports the open song; a different song
 * opening (an import, say) closes all of them. */
data class PresentedSurfaces(
    val songs: Boolean = false,
    val arrangement: Boolean = false,
    val export: Boolean = false,
    val instrumentEditor: Boolean = false,
) {
    fun afterOpeningSong(previousSongID: UUID, currentSongID: UUID): PresentedSurfaces =
        if (previousSongID == currentSongID) this else PresentedSurfaces()
}

/** Confirmation copy shown at more than one entrance, kept in one place. */
object ConfirmationCopy {
    const val CLEAR_PATTERN = "Every track's notes in this pattern are erased. Undo brings them back."
    const val CLEAR_TRACK = "Its notes in the other patterns are left alone. Undo brings them back."
    const val DELETE_TRACK = "Its notes in every pattern go with it. Undo brings it back."
    const val DELETE_PATTERN = "It's removed from the arrangement too. Undo brings it back."

    fun deleteTrackTitle(label: String): String = "Delete track $label?"

    fun deletePatternTitle(name: String): String = "Delete pattern $name?"
}

/** Getting from a finished render to the share sheet: the export panel goes
 * first, and the share waits for it to be gone. */
object ExportFlow {
    data class Step(
        val closeExport: Boolean = false,
        val shareWhenExportCloses: Boolean = false,
        val shareNow: Boolean = false,
        /** The export is over, so its options go back to the defaults and
         * the next opening starts at WAV, 1x, Seamless loop. */
        val endsFlow: Boolean = false,
    )

    fun afterRender(file: File?, exportPresented: Boolean): Step {
        if (file == null) return Step()
        if (!exportPresented) return Step(shareNow = true)
        return Step(closeExport = true, shareWhenExportCloses = true)
    }

    /** The file a just-finished render left to share, read off the attempt
     * counter rather than the file. Exporting the same song in the same
     * format again writes the same path, and a MIDI file can land before the
     * next frame, so the file's clear-then-set can fold into no change at all
     * and the second export would end with nothing on screen. The counter
     * moves for every finished render; one that left no file (canceled,
     * failed) and a counter that hasn't moved forward ask for nothing. */
    fun finishedExport(previousAttempt: Int, completedAttempt: Int, file: File?): File? =
        if (completedAttempt > previousAttempt) file else null

    /** The panel closing with no share owed was closed by hand (Close, a
     * swipe, Escape, another song opening), which ends the export. Closing
     * for the result dialog doesn't: the file still has to be offered. */
    fun afterExportClosed(pendingShare: Boolean): Step =
        Step(shareNow = pendingShare, endsFlow = !pendingShare)

    /** The result dialog going away ends the export, whichever button closed
     * it. iOS brings the panel back after a canceled share; nothing does
     * here, so there is no later step to keep the options for. */
    fun afterResultClosed(): Step = Step(endsFlow = true)

    /** A panel dismissed mid-render cancels the render. */
    fun afterPanelDisappeared(isExporting: Boolean): Boolean = isExporting
}

/** Which render progress reports are worth a new [StudioState]. A video
 * reports once a frame, up to 18,000 for a ten minute export, and each post
 * copies the whole state. Only a move of a whole percent, or reaching the
 * end, gets through, as iOS's exporters report. One per render: it is read
 * on the rendering thread only. */
class ExportProgressThrottle(private val step: Double = 0.01) {
    private var reported = 0.0

    fun admits(fraction: Double): Boolean {
        val completes = fraction >= 1.0 && reported < 1.0
        if (fraction - reported < step && !completes) return false
        reported = fraction
        return true
    }
}

object KeyboardShortcutsMenuVisibility {
    fun visible(keyboardConnected: Boolean, hardwareKeyboardInUse: Boolean): Boolean =
        keyboardConnected || hardwareKeyboardInUse
}
