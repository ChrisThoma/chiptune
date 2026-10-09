package dev.individuation.chiptune.ui.arrangement

import androidx.compose.runtime.Composable
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.PlaceholderSheetBody

/**
 * The play order (iOS `ArrangementView`), opened by ARR in the transport.
 *
 * PHASE 5B: replace the body; keep the signature. [regularWidth] is
 * `LocalChipLayout.current.isRegularWidth` at the call site (iOS passes it
 * down because a popover's content can't ask for itself).
 */
@Composable
fun ArrangementSheet(editor: Editor, regularWidth: Boolean, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss) {
        PlaceholderSheetBody("Arrangement", onDismiss)
    }
}
