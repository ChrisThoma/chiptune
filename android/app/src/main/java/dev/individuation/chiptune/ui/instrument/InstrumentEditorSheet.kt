package dev.individuation.chiptune.ui.instrument

import androidx.compose.runtime.Composable
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.PlaceholderSheetBody

/**
 * One track's sound settings (iOS `InstrumentEditor`), opened by tapping an
 * already-selected track header. [track] is the track index snapshotted when
 * it opened (iOS's rule: confirm-time reads of the selection act on the
 * wrong track).
 *
 * PHASE 5B: replace the body; keep the signature. The holder reports this as
 * the song-bound TRACK_SOUND presenter while it's up. Phase 6 adds the docked
 * (side column) and popover forms.
 */
@Composable
fun InstrumentEditorSheet(editor: Editor, track: Int, onDismiss: () -> Unit) {
    val title = "Sound \u2014 " + editor.studio.song.fullLabel(track)
    ChipSheet(onDismiss = onDismiss) {
        PlaceholderSheetBody(title, onDismiss)
    }
}
