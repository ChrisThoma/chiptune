package dev.individuation.chiptune.ui.export

import androidx.compose.runtime.Composable
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.PlaceholderSheetBody

/**
 * WAV export (iOS `ExportSheet`), opened by "Export WAV" in the song menu.
 *
 * PHASE 5B: replace the body; keep the signature. Closing through
 * `editor.presentation.closeAll()` (Escape, a song change) already cancels a
 * running render; a swipe-down or Close while rendering must cancel it too
 * (`ExportFlow.afterPanelDisappeared`). The finished file goes out through
 * `editor.effects.shareFile(file, EditorEffects.WAV_MIME)` once this sheet has
 * closed (`ExportFlow.afterRender` / `afterExportClosed`), and the review
 * prompt hangs off that share (`ReviewPromptTracker`, Phase 7).
 */
@Composable
fun ExportSheet(editor: Editor, regularWidth: Boolean, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss) {
        PlaceholderSheetBody("Export", onDismiss)
    }
}
