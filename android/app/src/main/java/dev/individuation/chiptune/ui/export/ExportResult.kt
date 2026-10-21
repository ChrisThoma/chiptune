package dev.individuation.chiptune.ui.export

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.ChiptuneApp
import dev.individuation.chiptune.core.store.InMemoryKeyValueStore
import dev.individuation.chiptune.core.studio.ExportFlow
import dev.individuation.chiptune.core.studio.ReviewPromptTracker
import dev.individuation.chiptune.core.studio.ShareOutcome
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.EditorEffects
import dev.individuation.chiptune.ui.editor.Presented
import dev.individuation.chiptune.ui.layout.ExportCopy
import dev.individuation.chiptune.ui.theme.ChipColors
import java.io.File

/**
 * From a finished render to the share step (iOS ContentView's
 * `onChange(of: completedExportAttempt)` and `shareAfterExport()`): a success haptic, the
 * export counted for the review prompt, the export panel taken down, and
 * once it has gone, [Presented.ExportResult]. Lives in the editor, not the
 * sheet, because the sheet is what goes away first.
 */
@Composable
fun ExportResultHost(editor: Editor) {
    val context = LocalContext.current
    val tracker = remember(context) {
        (context.applicationContext as? ChiptuneApp)?.reviewPrompt ?: ReviewPromptTracker(InMemoryKeyValueStore())
    }
    val flow = remember { PendingShare() }
    val presentation = editor.presentation

    LaunchedEffect(editor) {
        // Watched through the attempt counter, not the file: see
        // [ExportFlow.finishedExport]. Both read from one state, so the file
        // is the one that attempt left. The first value is whatever finished
        // before the editor was up, which is not this host's to present.
        var previous: Int? = null
        val finished = snapshotFlow { editor.ui.value.let { Triple(it.completedExportAttempt, it.exportFile, it.exportTitle) } }
        finished.collect { (completed, latest, title) ->
            val last = previous
            previous = completed
            if (last == null) return@collect
            val file = ExportFlow.finishedExport(last, completed, latest) ?: return@collect
            editor.haptics.exportSucceeded()
            tracker.exportSucceeded()
            val step = ExportFlow.afterRender(file, exportPresented = presentation.current == Presented.Export)
            flow.file = file
            flow.title = title.orEmpty()
            flow.waiting = step.shareWhenExportCloses
            if (step.closeExport) presentation.close(Presented.Export)
            if (step.shareNow) presentation.open(Presented.ExportResult(file, flow.title))
        }
    }
    LaunchedEffect(editor) {
        var previous = presentation.current
        snapshotFlow { presentation.current }.collect { now ->
            if (previous == Presented.Export && now != Presented.Export) {
                val step = ExportFlow.afterExportClosed(flow.waiting)
                flow.waiting = false
                if (step.endsFlow) editor.studio.endExportFlow()
                val file = flow.file
                if (step.shareNow && file != null) presentation.open(Presented.ExportResult(file, flow.title))
            }
            if (previous is Presented.ExportResult && now !is Presented.ExportResult) {
                if (ExportFlow.afterResultClosed().endsFlow) editor.studio.endExportFlow()
            }
            previous = now
        }
    }
}

/** What the render left owed: a file to offer once the panel has closed. */
private class PendingShare {
    var file: File? = null
    /** The exported song's own title ([dev.individuation.chiptune.core.studio.StudioState.exportTitle]). */
    var title = ""
    var waiting = false
}

/**
 * "Exported \u201CX\u201D": Share... or Save to device. Android's stand-in for the
 * iOS share sheet that follows an export; the review prompt hangs off the
 * share as it does there.
 */
@Composable
fun ExportResultDialog(editor: Editor, file: File, title: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val tracker = remember(context) {
        (context.applicationContext as? ChiptuneApp)?.reviewPrompt ?: ReviewPromptTracker(InMemoryKeyValueStore())
    }
    fun closeWithoutSharing() {
        // Like closing iOS's share sheet untouched: the milestone isn't spent.
        tracker.shareDismissed(ShareOutcome.CANCELED)
        onDismiss()
    }
    AlertDialog(
        onDismissRequest = ::closeWithoutSharing,
        containerColor = ChipColors.panelHigh,
        title = { Text(ExportCopy.resultTitle(title)) },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = {
                    // Phase 7's save reports nothing back; it doesn't spend the milestone.
                    tracker.shareDismissed(ShareOutcome.CANCELED)
                    onDismiss()
                    editor.effects.saveToDevice(file, file.name, EditorEffects.mimeTypeFor(file), title)
                }) { Text("Save to device", color = ChipColors.text) }
                TextButton(onClick = {
                    onDismiss()
                    editor.effects.shareFile(file, EditorEffects.mimeTypeFor(file)) { handedOff ->
                        val outcome = if (handedOff) ShareOutcome.COMPLETED else ShareOutcome.CANCELED
                        if (tracker.shareDismissed(outcome)) editor.effects.requestReview()
                    }
                }) { Text("Share\u2026", color = ChipColors.accentGreen) }
            }
        },
        dismissButton = { TextButton(onClick = ::closeWithoutSharing) { Text("Close", color = ChipColors.dim) } },
    )
}
