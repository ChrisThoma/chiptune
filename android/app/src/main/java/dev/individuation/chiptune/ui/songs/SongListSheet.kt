package dev.individuation.chiptune.ui.songs

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.store.UnreadableSongs
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.editor.BarIconPill
import dev.individuation.chiptune.ui.editor.BarPill
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.ConfirmDialog
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.ErrorDialog
import dev.individuation.chiptune.ui.editor.FormColors
import dev.individuation.chiptune.ui.editor.SheetBar
import dev.individuation.chiptune.ui.editor.SwipeAction
import dev.individuation.chiptune.ui.editor.SwipeActionsRow
import dev.individuation.chiptune.ui.editor.SwipeRevealGroup
import dev.individuation.chiptune.ui.editor.reportsTextEntryFocus
import dev.individuation.chiptune.ui.editor.songDropTarget
import dev.individuation.chiptune.ui.layout.SongListCopy
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.chipFont

/**
 * The song library (iOS `SongListView`), opened by the Songs button. Opening
 * a different song closes it on its own (the presentation holder watches the
 * song id); the editor saved the song before this opened.
 */
@Composable
fun SongListSheet(editor: Editor, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss, skipPartiallyExpanded = true, containerColor = FormColors.sheet) {
        SongListPanel(editor, onDismiss)
    }
}

/** Failures raised from in here, claimed off the Studio so this sheet's own
 * dialogs show them (the editor's are underneath it). */
private class Claimed {
    var save by mutableStateOf<String?>(null)
    var delete by mutableStateOf<String?>(null)
    var import by mutableStateOf<String?>(null)
    var share by mutableStateOf<String?>(null)
    var unreadable by mutableStateOf<String?>(null)

    fun claimSave(studio: Studio) {
        studio.storageError?.let { save = it; studio.storageError = null }
    }

    fun claimDelete(studio: Studio) {
        studio.deleteError?.let { delete = it; studio.deleteError = null }
    }

    fun claimImport(studio: Studio) {
        studio.importError?.let { import = it; studio.importError = null }
    }

    fun claimShare(studio: Studio) {
        studio.shareError?.let { share = it; studio.shareError = null }
    }
}

/** The library with its bar; a regular-width popover can host this as is. */
@Composable
fun SongListPanel(editor: Editor, onDismiss: () -> Unit) {
    val studio = editor.studio
    val ui = editor.ui
    var songs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var pendingDelete by remember { mutableStateOf<Song?>(null) }
    var renaming by remember { mutableStateOf<Song?>(null) }
    val claimed = remember { Claimed() }
    val swipe = remember { SwipeRevealGroup() }
    val currentID by remember { derivedStateOf { ui.value.song.id } }
    // An import started here reports back through the Studio: the song
    // changes (the holder closes this sheet) or importError is set.
    val importError by remember { derivedStateOf { ui.value.importError } }

    fun reload() {
        songs = studio.loadLibrary()
        // A notice still waiting for the editor moves onto this sheet.
        studio.unreadableSongsNotice?.let {
            studio.unreadableSongsNotice = null
            claimed.unreadable = it
        }
    }
    LaunchedEffect(Unit) { reload() }
    LaunchedEffect(importError) { if (importError != null) claimed.claimImport(studio) }

    fun rename(song: Song) {
        renaming = song
    }
    fun duplicate(song: Song) {
        studio.duplicate(song)
        claimed.claimSave(studio)
        reload()
    }
    fun share(song: Song) {
        // The editor hands studio.shareFile to the share effect.
        studio.share(song)
        claimed.claimShare(studio)
    }

    Column(Modifier.fillMaxSize().songDropTarget(studio)) {
        SheetBar(
            title = SongListCopy.TITLE,
            leading = { BarPill("Close", onDismiss) },
            trailing = { AddMenu(onNew = { studio.newSong(); onDismiss() }, onImport = { editor.effects.importSong() }) },
        )
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            if (songs.isEmpty()) {
                EmptyLibrary()
            } else {
                // A song row is a name and a date; on a wide sheet it's capped and centred.
                LazyColumn(Modifier.widthIn(max = 640.dp).fillMaxWidth()) {
                    items(songs, key = { it.id.toString() }) { song ->
                        val isOpen = song.id == currentID
                        SongRow(
                            song = song,
                            isOpen = isOpen,
                            group = swipe,
                            onOpen = {
                                if (!isOpen) studio.open(song)
                                onDismiss()
                            },
                            onRename = { rename(song) },
                            onDuplicate = { duplicate(song) },
                            onShare = { share(song) },
                            onDelete = { pendingDelete = song },
                        )
                    }
                }
            }
        }
    }

    pendingDelete?.let { song ->
        ConfirmDialog(
            title = SongListCopy.deleteTitle(song.name),
            message = SongListCopy.DELETE_MESSAGE,
            confirmLabel = "Delete song",
            destructive = true,
            onConfirm = {
                studio.delete(song)
                claimed.claimDelete(studio)
                claimed.claimSave(studio)
                reload()
            },
            onDismiss = { pendingDelete = null },
        )
    }
    renaming?.let { song ->
        RenameSongDialog(
            song = song,
            canRename = { SongListCopy.canRename(it, songs, song.id) },
            onRename = { name ->
                studio.rename(song, name)
                claimed.claimSave(studio)
                renaming = null
                reload()
            },
            onDismiss = { renaming = null },
        )
    }
    claimed.save?.let { ErrorDialog("Save failed", it) { claimed.save = null } }
    claimed.delete?.let { ErrorDialog("Delete failed", it) { claimed.delete = null } }
    claimed.import?.let { ErrorDialog("Import failed", it) { claimed.import = null } }
    claimed.share?.let { ErrorDialog("Share failed", it) { claimed.share = null } }
    claimed.unreadable?.let { ErrorDialog(UnreadableSongs.TITLE, it) { claimed.unreadable = null } }
}

@Composable
private fun AddMenu(onNew: () -> Unit, onImport: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        BarIconPill(Icons.Filled.Add, "Add", onClick = { open = true })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = ChipColors.panelHigh) {
            MenuItem("New song", Icons.AutoMirrored.Filled.NoteAdd) { open = false; onNew() }
            MenuItem("Import song\u2026", Icons.Filled.FileDownload) { open = false; onImport() }
        }
    }
}

@Composable
private fun MenuItem(title: String, icon: ImageVector, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) ChipColors.accentRed else ChipColors.text
    DropdownMenuItem(
        text = { Text(title, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
        colors = MenuDefaults.itemColors(textColor = color, leadingIconColor = color),
    )
}

@Composable
private fun EmptyLibrary() {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp).padding(top = 120.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = ChipColors.text, modifier = Modifier.size(44.dp))
        Text(SongListCopy.EMPTY_TITLE, color = ChipColors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(SongListCopy.EMPTY_MESSAGE, color = ChipColors.dim, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SongRow(
    song: Song,
    isOpen: Boolean,
    group: SwipeRevealGroup,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onShare: () -> Unit,
    onDelete: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val gray = ChipColors.panelHigh
    Column {
        SwipeActionsRow(
            key = song.id,
            group = group,
            leading = listOf(
                SwipeAction("Duplicate", Icons.Filled.LibraryAdd, gray, ChipColors.text, onDuplicate),
                SwipeAction("Rename", Icons.Filled.Edit, gray, ChipColors.text, onRename),
            ),
            trailing = listOf(
                SwipeAction("Share", Icons.Filled.IosShare, gray, ChipColors.text, onShare),
                SwipeAction("Delete", Icons.Filled.Delete, Color(0xFFFF3B30), Color.White, onDelete),
            ),
        ) {
            Box {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(FormColors.sheet)
                        .combinedClickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onLongClickLabel = "More actions",
                            onLongClick = { menu = true },
                            onClick = onOpen,
                        )
                        .heightIn(min = 60.dp)
                        .padding(horizontal = 20.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            song.name,
                            color = ChipColors.text,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(SongListCopy.detail(song), style = chipFont(11f, FontWeight.Normal), color = ChipColors.dim, maxLines = 1)
                    }
                    if (isOpen) Text("OPEN", style = chipFont(11f, FontWeight.Bold), color = ChipColors.accentGreen)
                }
                // The same actions again for a long press, and so rename is
                // discoverable without swiping.
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = ChipColors.panelHigh) {
                    MenuItem("Rename", Icons.Filled.Edit) { menu = false; onRename() }
                    MenuItem("Duplicate", Icons.Filled.LibraryAdd) { menu = false; onDuplicate() }
                    MenuItem("Share song file", Icons.Filled.IosShare) { menu = false; onShare() }
                    MenuItem("Delete", Icons.Filled.Delete, destructive = true) { menu = false; onDelete() }
                }
            }
        }
        Box(Modifier.fillMaxWidth().padding(start = 20.dp).height(0.5.dp).background(ChipColors.grid))
    }
}

/** "Rename song": the field is "Song title" to TalkBack; Rename is greyed
 * for a blank name or one another song has. */
@Composable
private fun RenameSongDialog(
    song: Song,
    canRename: (String) -> Boolean,
    onRename: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember(song.id) { mutableStateOf(song.name) }
    val focus = remember { FocusRequester() }
    val enabled = canRename(text)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChipColors.panelHigh,
        title = { Text("Rename song") },
        text = {
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(ChipColors.panel).padding(horizontal = 14.dp, vertical = 12.dp)) {
                BasicTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = ChipColors.text),
                    cursorBrush = SolidColor(ChipColors.text),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (enabled) onRename(text) }),
                    modifier = Modifier.fillMaxWidth().reportsTextEntryFocus().focusRequester(focus).semantics { contentDescription = "Song title" },
                    decorationBox = { field ->
                        Box {
                            if (text.isEmpty()) Text("Name", color = ChipColors.dim, style = MaterialTheme.typography.bodyLarge)
                            field()
                        }
                    },
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onRename(text) }, enabled = enabled) {
                Text("Rename", color = if (enabled) ChipColors.accentGreen else ChipColors.dim)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
    LaunchedEffect(Unit) { focus.requestFocus() }
}
