package dev.individuation.chiptune.ui.editor

import androidx.compose.runtime.Composable

/** The hardware-key list (iOS `KeyboardHelpView`). PHASE 6 fills it in. */
@Composable
fun KeyboardHelpSheet(onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss) {
        PlaceholderSheetBody("Keyboard shortcuts", onDismiss)
    }
}
