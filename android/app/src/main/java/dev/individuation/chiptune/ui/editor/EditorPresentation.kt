package dev.individuation.chiptune.ui.editor

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import dev.individuation.chiptune.core.studio.EditorPresentation
import dev.individuation.chiptune.core.studio.SongBoundPresenters
import dev.individuation.chiptune.core.studio.SongLibraryPresentation
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.core.studio.StudioState
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop

/**
 * Everything the editor can put over itself. At most one at a time:
 * [EditorPresentation.canOpen] refuses a second while one is up, as iOS does
 * (a second presentation request there is lost or appears later on its own).
 *
 * The four Phase 5B surfaces ([Songs], [Arrangement], [Export],
 * [InstrumentEditor]) and [KeyboardHelp] are bottom sheets on a phone; at
 * regular width they're popovers (Songs a centred dialog), and the
 * instrument editor docks in the side layout (`SurfaceContainers`). The rest
 * are the editor's own dialogs and sheets.
 */
sealed interface Presented {
    data object None : Presented

    /** SongListView. */
    data object Songs : Presented

    /** ArrangementView. */
    data object Arrangement : Presented

    /** ExportSheet. Closing it while a render runs cancels the render. */
    data object Export : Presented

    /** The sound settings of one track (iOS `TrackHeader.showingEditor`).
     * [showSound] lands on the sound controls rather than the top (the
     * screenshot shoot's frame, as iOS's `ScreenshotMode.instrument`). */
    data class InstrumentEditor(val track: Int, val showSound: Boolean = false) : Presented

    /** A finished export's next step (Share or Save to device); opens once
     * the export panel has gone, as iOS's share sheet waits for it. */
    data class ExportResult(val file: java.io.File) : Presented

    /** The hardware-key list (Phase 6). */
    data object KeyboardHelp : Presented

    /** The pattern rename sheet, for the pattern at [pattern] when it opened. */
    data class PatternRename(val pattern: Int) : Presented

    /** "Clear pattern X?", from the menu or a chip. The index is snapshotted
     * when raised: in SONG mode the selection moves under the dialog. */
    data class ClearPattern(val pattern: Int) : Presented

    /** "Delete pattern X?". */
    data class DeletePattern(val pattern: Int) : Presented

    /** The tap-to-type tempo dialog. */
    data object Tempo : Presented

    /** The song-bound presenter this reports into `Studio`, if any: these hold
     * an index or a value read from the song, so song-changing chords wait. */
    val songBoundSurface: SongBoundPresenters.Surface?
        get() = when (this) {
            is PatternRename -> SongBoundPresenters.Surface.PATTERN_RENAME
            is ClearPattern -> SongBoundPresenters.Surface.PATTERN_CLEAR
            is DeletePattern -> SongBoundPresenters.Surface.PATTERN_DELETE
            Tempo -> SongBoundPresenters.Surface.TEMPO_ALERT
            is InstrumentEditor -> SongBoundPresenters.Surface.TRACK_SOUND
            else -> null
        }
}

/**
 * The editor's presentation seam. One instance per editor, made by
 * [rememberEditorPresentation].
 *
 * For Phase 5B: a surface opens with [open] (which returns false and does
 * nothing while anything is up) and closes with [close]. The editor draws
 * the current one through `PresentedSurfaceHost`, which calls the four sheet
 * composables in `ui/songs`, `ui/arrangement`, `ui/export` and
 * `ui/instrument`; replace those bodies, keep their signatures. Each gets an
 * `onDismiss` that is [close]. Surfaces never need to report themselves to
 * `Studio.setPresented`: this holder does it from [current].
 *
 * Rules carried over from ContentView.swift:
 * - [closeAll] runs on every `studio.dismissRequests` bump (Escape, Ctrl+.)
 *   and when a different song opens (an import, a library pick). Closing
 *   [Presented.Export] that way cancels a running export, as iOS does.
 * - Opening Songs saves first (and stays shut if the save fails), after
 *   ending any title rename -- [openSongs] does both.
 */
@Stable
class EditorPresentationState internal constructor(
    private val studio: Studio,
    private val ui: State<StudioState>,
) {
    var current: Presented by mutableStateOf(Presented.None)
        private set

    /** Where the regular-width popovers hang from (Phase 6). */
    val anchors = PopoverAnchors()

    /** Phase 7's share sheet counts as presented while a song file waits. */
    val anyPresented: Boolean by derivedStateOf { current != Presented.None || ui.value.shareFile != null }

    /** Song-bound presenters, here or reported by others into the Studio. */
    val songBoundPresented: Boolean by derivedStateOf {
        current.songBoundSurface != null || ui.value.songBoundPresenters.isPresented
    }

    val canChangeSong: Boolean get() = EditorPresentation.canChangeSong(songBoundPresented)

    /** Opens [surface] if nothing is up; returns whether it opened. */
    fun open(surface: Presented): Boolean {
        if (surface == Presented.None) return false
        if (!EditorPresentation.canOpen(anyPresented)) return false
        current = surface
        return true
    }

    /** The Songs entrance: saves before it opens, so the list shows the name
     * as typed, and stays shut when the save fails (storageError says why). */
    fun openSongs(endRenaming: () -> Unit): Boolean {
        if (!EditorPresentation.canOpen(anyPresented)) return false
        endRenaming()
        if (!studio.saveNow()) return false
        current = Presented.Songs
        return true
    }

    /** Closes whatever is up; a surface's Close button or swipe-down. */
    fun close() {
        current = Presented.None
    }

    /** Closes [surface] only if it is still the one up (a late callback from
     * a sheet that has already been replaced must not close its successor). */
    fun close(surface: Presented) {
        if (current == surface) current = Presented.None
    }

    /** Escape / Ctrl+. and a song change: everything closes, and an export
     * that was rendering behind its panel is called off. */
    fun closeAll() {
        if (current == Presented.Export && studio.isExporting) studio.cancelExport()
        current = Presented.None
    }

    internal fun afterSongChanged(previous: java.util.UUID, now: java.util.UUID) {
        val songsStays = SongLibraryPresentation.afterOpeningSong(current == Presented.Songs, previous, now)
        if (previous != now && !songsStays) closeAll()
    }
}

/** Makes the editor's [EditorPresentationState] and wires its rules: song
 * change and dismiss requests close everything, and the current surface is
 * mirrored into `Studio.setPresented` for the song-bound ones. */
@Composable
fun rememberEditorPresentation(studio: Studio, ui: State<StudioState>): EditorPresentationState {
    val state = remember(studio) { EditorPresentationState(studio, ui) }
    LaunchedEffect(state) {
        var previous = ui.value.song.id
        snapshotFlow { ui.value.song.id }.distinctUntilChanged().drop(1).collect { id ->
            state.afterSongChanged(previous, id)
            previous = id
        }
    }
    LaunchedEffect(state) {
        snapshotFlow { ui.value.dismissRequests }.distinctUntilChanged().drop(1).collect { state.closeAll() }
    }
    LaunchedEffect(state) {
        var reported: SongBoundPresenters.Surface? = null
        try {
            snapshotFlow { state.current.songBoundSurface }.collect { surface ->
                if (reported != surface) {
                    reported?.let { studio.setPresented(it, false) }
                    surface?.let { studio.setPresented(it, true) }
                    reported = surface
                }
            }
        } finally {
            // Leaving the screen withdraws the report, as iOS's onDisappear does.
            reported?.let { studio.setPresented(it, false) }
        }
    }
    return state
}
