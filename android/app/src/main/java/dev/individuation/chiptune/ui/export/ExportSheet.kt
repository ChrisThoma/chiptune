package dev.individuation.chiptune.ui.export

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.studio.ExportFlow
import dev.individuation.chiptune.ui.editor.BarPill
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.ErrorDialog
import dev.individuation.chiptune.ui.editor.FormButtonRow
import dev.individuation.chiptune.ui.editor.FormColors
import dev.individuation.chiptune.ui.editor.FormRow
import dev.individuation.chiptune.ui.editor.FormSection
import dev.individuation.chiptune.ui.editor.FormSeparator
import dev.individuation.chiptune.ui.editor.PlainStepper
import dev.individuation.chiptune.ui.editor.SheetBar
import dev.individuation.chiptune.ui.editor.adjustable
import dev.individuation.chiptune.ui.editor.plainClickable
import dev.individuation.chiptune.ui.layout.ExportAnnouncement
import dev.individuation.chiptune.ui.layout.ExportControls
import dev.individuation.chiptune.ui.layout.ExportCopy
import dev.individuation.chiptune.ui.layout.ExportFormatFooter
import dev.individuation.chiptune.ui.layout.ExportLength
import dev.individuation.chiptune.ui.layout.ExportNotesFooter
import dev.individuation.chiptune.ui.layout.Format
import dev.individuation.chiptune.ui.layout.adjusted
import dev.individuation.chiptune.ui.layout.text
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont
import androidx.compose.ui.text.font.FontWeight

/**
 * WAV, MIDI or video export (iOS `ExportSheet`), opened by "Export\u2026" in the song menu.
 *
 * Closing it while a render runs cancels the render, however it closes:
 * Close, a swipe down, or `closeAll()` (`ExportFlow.afterPanelDisappeared`).
 * A finished file is picked up by [ExportResultHost], which takes this sheet
 * down and offers Share / Save to device once it has gone.
 */
@Composable
fun ExportSheet(editor: Editor, regularWidth: Boolean, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss, skipPartiallyExpanded = true, containerColor = FormColors.sheet) {
        ExportPanel(editor, onDismiss)
    }
}

/** The export form with its bar; a regular-width popover can host this as is. */
@Composable
fun ExportPanel(editor: Editor, onDismiss: () -> Unit) {
    val studio = editor.studio
    val ui = editor.ui
    // Held by the Studio, not the sheet, so the choice outlasts the sheet closing.
    val options by remember { derivedStateOf { ui.value.exportOptions } }
    // Separate from isExporting: a render that starts and finishes between
    // frames would be missed, and the attempt token can't be.
    var startedAttempt by remember { mutableStateOf<Int?>(null) }
    val isExporting by remember { derivedStateOf { ui.value.isExporting } }
    val progress by remember { derivedStateOf { ui.value.exportProgress } }
    val song by remember { derivedStateOf { ui.value.song } }
    val completed by remember { derivedStateOf { ui.value.completedExportAttempt } }
    val exportError by remember { derivedStateOf { ui.value.exportError } }
    val locked = ExportControls.settingsLocked(isExporting)

    // A failed or canceled attempt frees the button; a successful one
    // closes the sheet (ExportResultHost).
    LaunchedEffect(completed) {
        if (ExportControls.freesExportButton(startedAttempt, completed, producedFile = studio.exportFile != null)) {
            startedAttempt = null
        }
    }
    // TalkBack hears the render start and each quarter of it; otherwise it
    // only learns how far along it is by finding the bar.
    val view = LocalView.current
    LaunchedEffect(view) {
        var wasExporting = ui.value.isExporting
        var previous = ui.value.exportProgress
        snapshotFlow { ui.value.let { Triple(it.isExporting, it.exportProgress, it.exportOptions.format) } }
            .collect { (exporting, now, format) ->
                val text = when {
                    exporting && !wasExporting -> ExportAnnouncement.started(format)
                    exporting -> ExportAnnouncement.milestone(previous, now)
                    else -> null
                }
                @Suppress("DEPRECATION")
                text?.let { view.announceForAccessibility(it) }
                wasExporting = exporting
                previous = if (exporting) now else 0.0
            }
    }
    DisposableEffect(Unit) {
        onDispose {
            if (ExportFlow.afterPanelDisappeared(studio.isExporting)) studio.cancelExport()
        }
    }

    // Full height, as iOS's sheet opens at its large detent.
    Column(Modifier.fillMaxSize()) {
        SheetBar(
            title = "Export",
            leading = {
                BarPill("Close", {
                    studio.cancelExport()
                    onDismiss()
                })
            },
        )
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp)
                .navigationBarsPadding(),
        ) {
            FormSection(footer = ExportFormatFooter.text(options.format)) {
                SegmentedChoice(
                    ExportOptions.Format.entries, options.format, enabled = !locked,
                    label = { it.label }, description = ExportCopy::formatSegment,
                ) { studio.exportOptions = ExportCopy.withFormat(song, options, it) }
            }

            if (ExportCopy.hasRepeats(options.format)) {
                FormSection(footer = ExportCopy.repeatsFooter(song, options)) {
                    // The stepper speaks for the row, as one "Repeats" element.
                    FormRow(Modifier.alpha(if (locked) 0.4f else 1f)) {
                        Text("Repeats", color = ChipColors.text, fontSize = 17.sp, modifier = Modifier.weight(1f).clearAndSetSemantics { })
                        Text(
                            ExportCopy.loopCount(options.loopCount),
                            style = chipFont(15f, FontWeight.Bold),
                            color = ChipColors.dim,
                            modifier = Modifier.clearAndSetSemantics { },
                        )
                        PlainStepper(
                            value = options.loopCount,
                            onValueChange = { studio.exportOptions = options.copy(loopCount = it) },
                            range = 1..ExportOptions.MAX_LOOP_COUNT,
                            accessibilityLabel = "Repeats",
                            accessibilityValue = Format.count(options.loopCount, "time"),
                            isEnabled = !locked,
                        )
                    }
                }
            }

            if (ExportCopy.hasEnding(options.format)) {
                FormSection(header = "Ending", footer = ExportCopy.endingFooter(options.tailMode)) {
                    // One adjustable "Ending" element for TalkBack, as iOS has.
                    Column(
                        Modifier.clearAndSetSemantics {
                            val modes = ExportOptions.TailMode.entries
                            adjustable(
                                "Ending", ExportCopy.endingLabel(options.tailMode), options.tailMode.ordinal.toFloat(),
                                0f..(modes.size - 1).toFloat(), 0, !locked,
                                set = null,
                                adjust = { studio.exportOptions = options.copy(tailMode = options.tailMode.adjusted(it)) },
                            )
                        },
                    ) {
                        ExportOptions.TailMode.entries.forEachIndexed { i, mode ->
                            if (i > 0) FormSeparator()
                            EndingRow(ExportCopy.endingLabel(mode), options.tailMode == mode, enabled = !locked) {
                                studio.exportOptions = options.copy(tailMode = mode)
                            }
                        }
                    }
                }
            }

            if (ExportCopy.hasStyle(options.format)) {
                // Frozen and dimmed during a render, like Repeats.
                FormSection(header = "Style", footer = ExportCopy.styleFooter(options.videoStyle)) {
                    SegmentedChoice(
                        ExportOptions.VideoStyle.entries, options.videoStyle, enabled = !locked,
                        label = { it.label }, description = ExportCopy::styleSegment,
                    ) { studio.exportOptions = options.copy(videoStyle = it) }
                }
            }

            FormSection(footer = ExportNotesFooter.text(song, options.format)) {
                if (isExporting) {
                    // One TalkBack stop: the line and the bar's value together.
                    Column(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        LinearProgressIndicator(
                            progress = { progress.toFloat() },
                            color = ChipColors.accentGreen,
                            trackColor = ChipColors.grid,
                            drawStopIndicator = {},
                            modifier = Modifier.fillMaxWidth().height(4.dp),
                        )
                        Text(ExportCopy.exporting(options.format, progress), style = chipFont(11f), color = ChipColors.dim)
                    }
                    FormSeparator()
                    FormButtonRow("Cancel export", color = FormColors.destructive, onClick = {
                        studio.cancelExport()
                        @Suppress("DEPRECATION")
                        view.announceForAccessibility(ExportAnnouncement.CANCELED)
                    })
                } else {
                    FormButtonRow(
                        ExportCopy.exportButton(options.format),
                        icon = Icons.Filled.IosShare,
                        color = ChipColors.text,
                        enabled = ExportCopy.canExport(song.hasNotes, startedAttempt != null) &&
                            !ExportCopy.blocksExport(options.format, ExportLength.seconds(song, options)),
                        onClick = {
                            if (startedAttempt == null) startedAttempt = studio.export()
                        },
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }

    exportError?.let { message ->
        ErrorDialog("Export failed", message) { studio.exportError = null }
    }
}

@Composable
private fun EndingRow(label: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    FormRow(
        Modifier
            .plainClickable(enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f)
            .semantics {
                this.selected = selected
                if (!enabled) disabled()
            },
    ) {
        Text(label, color = ChipColors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = ChipColors.text, modifier = Modifier.size(22.dp))
    }
}

/** A segmented choice frozen like the other settings during a render, which
 * keeps what it started with. The label is on each segment, not on the row:
 * a described row with no action of its own is a TalkBack stop. */
@Composable
private fun <T> SegmentedChoice(
    options: List<T>,
    selected: T,
    enabled: Boolean,
    label: (T) -> String,
    description: (T) -> String,
    onSelect: (T) -> Unit,
) {
    FormRow(Modifier.alpha(if (enabled) 1f else 0.4f)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            options.forEachIndexed { i, option ->
                SegmentedButton(
                    selected = option == selected,
                    onClick = { onSelect(option) },
                    modifier = Modifier.semantics { contentDescription = description(option) },
                    shape = SegmentedButtonDefaults.itemShape(index = i, count = options.size),
                    enabled = enabled,
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = ChipColors.grid,
                        activeContentColor = ChipColors.text,
                        activeBorderColor = ChipColors.dim,
                        inactiveContainerColor = FormColors.group,
                        inactiveContentColor = ChipColors.dim,
                        inactiveBorderColor = ChipColors.grid,
                        disabledActiveContainerColor = ChipColors.grid,
                        disabledActiveContentColor = ChipColors.text,
                        disabledActiveBorderColor = ChipColors.dim,
                        disabledInactiveContainerColor = FormColors.group,
                        disabledInactiveContentColor = ChipColors.dim,
                        disabledInactiveBorderColor = ChipColors.grid,
                    ),
                    icon = {},
                ) {
                    Text(label(option), fontSize = 15.sp)
                }
            }
        }
    }
}
