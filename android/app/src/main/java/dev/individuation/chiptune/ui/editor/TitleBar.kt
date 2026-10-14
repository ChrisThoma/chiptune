package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.BuildConfig
import dev.individuation.chiptune.core.studio.KeyboardShortcutsMenuVisibility
import dev.individuation.chiptune.platform.KeyboardConnection
import dev.individuation.chiptune.ui.layout.BuildStamp
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont

/** Fixed for the life of the process. */
private val buildStamp = BuildStamp(
    commit = BuildConfig.GIT_COMMIT_HASH,
    builtAt = BuildStamp.parseBuildDate(BuildConfig.BUILD_DATE),
    version = BuildConfig.VERSION_NAME,
)

/** Songs, the song title, undo/redo and the song menu (ContentView.titleBar). */
@Composable
fun TitleBar(editor: Editor) {
    val layout = LocalChipLayout.current
    val studio = editor.studio
    val ui = editor.ui
    val name by remember { derivedStateOf { ui.value.song.name } }
    val canUndo by remember { derivedStateOf { ui.value.canUndo } }
    val canRedo by remember { derivedStateOf { ui.value.canRedo } }
    val focusManager = LocalFocusManager.current
    SideEffect { editor.rename.clearFocus = { focusManager.clearFocus() } }

    Row(
        Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TitleIconButton(Icons.AutoMirrored.Filled.QueueMusic, "Songs") {
            editor.presentation.openSongs { editor.rename.end() }
        }

        // Through setSongName, so a rename is one undo step; an undo of it
        // shows up in the field at once.
        BasicTextField(
            value = name,
            onValueChange = { studio.setSongName(it) },
            singleLine = true,
            textStyle = chipFont(16f, FontWeight.Bold).copy(color = ChipColors.text),
            cursorBrush = SolidColor(ChipColors.text),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = {
                studio.normalizeSongName()
                focusManager.clearFocus()
            }),
            modifier = Modifier
                .weight(1f)
                .reportsTextEntryFocus()
                .onFocusChanged { focus ->
                    val was = editor.rename.focused
                    editor.rename.focused = focus.isFocused
                    if (was && !focus.isFocused) studio.normalizeSongName()
                }
                .semantics { contentDescription = "Song title" },
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (name.isEmpty()) {
                        Text("Song name", style = chipFont(16f, FontWeight.Bold), color = ChipColors.dim, maxLines = 1)
                    }
                    field()
                }
            },
        )

        // Both close an open rename first, so undo lands on a step you can see.
        HistoryButton(Icons.AutoMirrored.Filled.Undo, "Undo", canUndo, layout.historyButtonWidth) {
            editor.rename.end()
            studio.undo()
        }
        HistoryButton(Icons.AutoMirrored.Filled.Redo, "Redo", canRedo, layout.historyButtonWidth) {
            editor.rename.end()
            studio.redo()
        }

        SongMenu(editor)
    }
}

@Composable
private fun TitleIconButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    val layout = LocalChipLayout.current
    Box(
        Modifier
            .size(layout.titleIconTargetSize.dpValue())
            .plainClickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(icon, layout.titleIconGlyphSize.toFloat(), ChipColors.text)
    }
}

/** Dimmed rather than hidden when there's nothing to undo, so the row
 * doesn't reflow as you edit. */
@Composable
private fun HistoryButton(icon: ImageVector, label: String, enabled: Boolean, width: Double, onClick: () -> Unit) {
    Box(
        Modifier
            .size(width.dpValue(), 44.dp)
            .plainClickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(icon, 15f, if (enabled) ChipColors.text else ChipColors.dim.copy(alpha = 0.4f))
    }
}

/** The ellipsis.circle.fill glyph: a filled disc with three dots knocked out. */
@Composable
private fun EllipsisCircle(size: Float) {
    Box(
        Modifier.size((size * 1.1f).dp).background(ChipColors.text, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.MoreHoriz, contentDescription = null, tint = ChipColors.background, modifier = Modifier.size((size * 0.85f).dp))
    }
}

/** The \u2022\u2022\u2022 song menu, in iOS's order. */
@Composable
private fun SongMenu(editor: Editor) {
    val layout = LocalChipLayout.current
    val studio = editor.studio
    val ui = editor.ui
    var open by remember { mutableStateOf(false) }
    val isExporting by remember { derivedStateOf { ui.value.isExporting } }
    val patternName by remember { derivedStateOf { ui.value.pattern.name } }
    val hardwareKeyboardInUse by remember { derivedStateOf { ui.value.hardwareKeyboardInUse } }
    val configuration = LocalConfiguration.current
    val keyboardConnected = KeyboardConnection.isConnected(configuration.keyboard, configuration.hardKeyboardHidden)

    Box {
        Box(
            Modifier
                // Export and the key list hang from here at regular width.
                .popoverAnchor(editor.presentation.anchors, PopoverAnchor.Menu)
                .size(layout.titleIconTargetSize.dpValue())
                .plainClickable { open = true }
                .semantics { contentDescription = "Song menu" },
            contentAlignment = Alignment.Center,
        ) {
            EllipsisCircle(layout.titleIconGlyphSize.toFloat())
        }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            containerColor = ChipColors.panelHigh,
            modifier = Modifier.widthIn(min = 250.dp),
        ) {
            fun pick(action: () -> Unit) {
                open = false
                action()
            }
            MenuRow("New song", Icons.AutoMirrored.Filled.NoteAdd) {
                pick { if (editor.presentation.canChangeSong) studio.newSong() }
            }
            MenuRow("Import song\u2026", Icons.Filled.FileDownload) { pick { editor.effects.importSong() } }
            MenuRow("Duplicate song", Icons.Filled.LibraryAdd) {
                pick { if (editor.presentation.canChangeSong) studio.duplicateSong() }
            }
            MenuDivider()
            // Export first: it's what most people open the menu for. The sheet
            // it opens chooses WAV or MIDI.
            MenuRow(if (isExporting) "Exporting\u2026" else "Export\u2026", Icons.Filled.FileUpload, enabled = !isExporting) {
                pick { editor.presentation.open(Presented.Export) }
            }
            MenuRow("Share song file", Icons.Filled.IosShare) { pick { studio.share(studio.song) } }
            MenuDivider()
            MenuRow("Clear pattern $patternName", Icons.Filled.Delete, destructive = true) {
                pick { editor.presentation.open(Presented.ClearPattern(studio.selectedPattern)) }
            }
            MenuDivider()
            if (KeyboardShortcutsMenuVisibility.visible(keyboardConnected, hardwareKeyboardInUse)) {
                MenuRow("Keyboard shortcuts", Icons.Filled.Keyboard) { pick { editor.presentation.open(Presented.KeyboardHelp) } }
            }
            MenuRow("Contact support", Icons.Filled.Email) { pick { editor.effects.openUrl(EditorEffects.SUPPORT_URL) } }
            if (buildStamp.lines.isNotEmpty()) {
                // Last, because it's read rarely; tapping copies the release
                // and commit, since the reason to look is a bug report.
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(buildStamp.lines[0], style = MaterialTheme.typography.bodyLarge, color = ChipColors.text)
                            val rest = buildStamp.lines.drop(1)
                            if (rest.isNotEmpty()) {
                                Text(rest.joinToString("\n"), style = MaterialTheme.typography.bodySmall, color = ChipColors.dim)
                            }
                        }
                    },
                    leadingIcon = { Icon(Icons.Filled.Info, contentDescription = null, tint = ChipColors.text) },
                    onClick = { pick { editor.effects.copyToClipboard("Chiptune build", buildStamp.copyText) } },
                    modifier = Modifier.semantics {
                        onClick("Copies the version and commit to the clipboard") {
                            pick { editor.effects.copyToClipboard("Chiptune build", buildStamp.copyText) }
                            true
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun MenuRow(
    title: String,
    icon: ImageVector,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val color: Color = when {
        destructive -> ChipColors.accentRed
        else -> ChipColors.text
    }
    DropdownMenuItem(
        text = { Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
        enabled = enabled,
        colors = androidx.compose.material3.MenuDefaults.itemColors(
            textColor = color,
            leadingIconColor = color,
            disabledTextColor = ChipColors.dim,
            disabledLeadingIconColor = ChipColors.dim,
        ),
        modifier = Modifier.alpha(1f),
    )
}

@Composable
private fun MenuDivider() {
    HorizontalDivider(color = ChipColors.grid, thickness = 6.dp, modifier = Modifier.padding(vertical = 2.dp).alpha(0.5f))
}
