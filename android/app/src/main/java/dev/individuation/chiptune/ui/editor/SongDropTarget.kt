package dev.individuation.chiptune.ui.editor

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.ui.draganddrop.mimeTypes
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.core.studio.SongDrop
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.platform.SongFileAcceptance
import dev.individuation.chiptune.platform.SongImporter
import dev.individuation.chiptune.ui.theme.ChipColors

/**
 * Accepts a song file dropped from another window (tablets, ChromeOS,
 * desktop windowing): `Studio.importDropped`, with iOS's green border while
 * a song hovers (ContentView's `isDropTargeted`).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun Modifier.songDropTarget(studio: Studio): Modifier {
    val context = LocalContext.current
    var hovering by remember { mutableStateOf(false) }
    val border by animateColorAsState(
        if (hovering) ChipColors.accentGreen else Color.Transparent,
        tween(120),
        label = "drop border",
    )
    val target = remember(studio, context) {
        object : DragAndDropTarget {
            override fun onEntered(event: DragAndDropEvent) {
                hovering = true
            }

            override fun onExited(event: DragAndDropEvent) {
                hovering = false
            }

            override fun onEnded(event: DragAndDropEvent) {
                hovering = false
            }

            override fun onDrop(event: DragAndDropEvent): Boolean {
                hovering = false
                return dropSongs(context, studio, event)
            }
        }
    }
    return this
        .dragAndDropTarget(
            shouldStartDragAndDrop = { event -> event.mimeTypes().any(SongFileAcceptance::acceptsDropMime) },
            target = target,
        )
        .border(2.dp, border, RoundedCornerShape(12.dp))
}

private fun dropSongs(context: Context, studio: Studio, event: DragAndDropEvent): Boolean {
    val android = event.toAndroidDragEvent()
    val clip = android.clipData ?: return false
    val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    if (uris.isEmpty()) return false
    val activity = generateSequence(context) { (it as? ContextWrapper)?.baseContext }.filterIsInstance<Activity>().firstOrNull()
    // Without this the drop's content URI can't be read once onDrop returns.
    activity?.requestDragAndDropPermissions(android)
    uris.forEach { importDropped(context, studio, it) }
    return true
}

private fun importDropped(context: Context, studio: Studio, uri: Uri) {
    val bytes = try {
        SongImporter.readSong(context.contentResolver, uri, checkName = false)
    } catch (e: Exception) {
        studio.importSong { throw e }
        return
    }
    studio.importDropped(SongDrop(bytes))
}
