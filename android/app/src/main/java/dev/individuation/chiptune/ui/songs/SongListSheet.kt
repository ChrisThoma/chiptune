package dev.individuation.chiptune.ui.songs

import androidx.compose.runtime.Composable
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.PlaceholderSheetBody

/**
 * The song library (iOS `SongListView`), opened by the Songs button.
 *
 * PHASE 5B: replace the body; keep the signature. Call [onDismiss] to close
 * (it is `editor.presentation.close()`). Opening a different song closes this
 * sheet on its own (the presentation holder watches the song id), and the
 * editor saved the song before opening it.
 */
@Composable
fun SongListSheet(editor: Editor, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss) {
        PlaceholderSheetBody("Songs", onDismiss)
    }
}
