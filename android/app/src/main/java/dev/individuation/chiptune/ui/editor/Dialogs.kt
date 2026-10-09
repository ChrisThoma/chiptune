package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.core.store.UnreadableSongs
import dev.individuation.chiptune.core.studio.StudioState
import dev.individuation.chiptune.ui.layout.TextScale
import dev.individuation.chiptune.ui.theme.ChipColors

/**
 * The app's bottom sheet: dark, and opened fully expanded at accessibility
 * text sizes (iOS's `compactSheetDetents`) or whenever [skipPartiallyExpanded].
 * The four form sheets (songs, arrangement, export, sound) pass
 * [FormColors.sheet] as [containerColor].
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ChipSheet(
    onDismiss: () -> Unit,
    skipPartiallyExpanded: Boolean = false,
    containerColor: androidx.compose.ui.graphics.Color = ChipColors.background,
    content: @Composable ColumnScope.() -> Unit,
) {
    val large = TextScale.isAccessibilitySize(LocalDensity.current.fontScale)
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded || large)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = containerColor,
        contentColor = ChipColors.text,
    ) {
        // A half-open sheet would leave a focused field under the keyboard:
        // its content is laid out full height and only slid partly on
        // screen, so nothing scrolls the field into view. Typing opens it.
        PresentedWindowKeys(onDismiss)
        val imeVisible = WindowInsets.isImeVisible
        LaunchedEffect(imeVisible) {
            if (imeVisible && state.currentValue == SheetValue.PartiallyExpanded) state.expand()
        }
        content()
    }
}

/** A sheet's top row: Cancel/Close on the left, a title, a confirm on the
 * right (iOS's inline navigation bar). */
@Composable
fun SheetHeader(
    title: String,
    leading: Pair<String, () -> Unit>?,
    trailing: Triple<String, Boolean, () -> Unit>? = null,
) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
        leading?.let { (label, action) ->
            TextButton(onClick = action, modifier = Modifier.align(Alignment.CenterStart)) { Text(label) }
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.Center).semantics { heading() },
        )
        trailing?.let { (label, enabled, action) ->
            TextButton(onClick = action, enabled = enabled, modifier = Modifier.align(Alignment.CenterEnd)) {
                Text(label, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** A two-button confirmation; [destructive] colours the confirm red. */
@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    destructive: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChipColors.panelHigh,
        title = {
            PresentedWindowKeys(onDismiss)
            Text(title)
        },
        text = { Text(message, color = ChipColors.text) },
        confirmButton = {
            TextButton(onClick = { onConfirm(); onDismiss() }) {
                Text(confirmLabel, color = if (destructive) ChipColors.accentRed else ChipColors.accentGreen)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** One OK button that clears the message, so the same failure twice shows twice. */
@Composable
fun ErrorDialog(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChipColors.panelHigh,
        title = { Text(title) },
        text = { Text(message, color = ChipColors.text) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
    )
}

/** The failures that used to pass silently: one at a time, in iOS's order. */
@Composable
fun EditorErrorDialogs(editor: Editor) {
    val ui = editor.ui
    val studio = editor.studio
    val pending by remember {
        derivedStateOf { firstError(ui.value) }
    }
    pending?.let { (title, message, clear) ->
        ErrorDialog(title, message) { clear(studio) }
    }
}

private fun firstError(s: StudioState): Triple<String, String, (dev.individuation.chiptune.core.studio.Studio) -> Unit>? {
    s.storageError?.let { return Triple("Save failed", it) { st -> st.storageError = null } }
    s.audioError?.let { return Triple("Audio unavailable", it) { st -> st.audioError = null } }
    s.importError?.let { return Triple("Import failed", it) { st -> st.importError = null } }
    s.shareError?.let { return Triple("Share failed", it) { st -> st.shareError = null } }
    s.unreadableSongsNotice?.let { return Triple(UnreadableSongs.TITLE, it) { st -> st.unreadableSongsNotice = null } }
    return null
}

/** Placeholder body for a sheet Phase 5B fills: its title and a Close. */
@Composable
fun PlaceholderSheetBody(title: String, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SheetHeader(title, leading = null, trailing = Triple("Close", true, onClose))
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
            Text("Coming in the next build.", color = ChipColors.dim)
        }
    }
}
