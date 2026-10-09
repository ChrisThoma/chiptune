package dev.individuation.chiptune.ui.arrangement

import android.view.View
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.core.model.ArrangementReorder
import dev.individuation.chiptune.core.model.ArrangementRowLeading
import dev.individuation.chiptune.core.model.RepeatsAccessibility
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.ui.editor.BarIconPill
import dev.individuation.chiptune.ui.editor.BarPill
import dev.individuation.chiptune.ui.editor.ChipSheet
import dev.individuation.chiptune.ui.editor.Editor
import dev.individuation.chiptune.ui.editor.FormColors
import dev.individuation.chiptune.ui.editor.FormFooter
import dev.individuation.chiptune.ui.editor.FormHeader
import dev.individuation.chiptune.ui.editor.FormSeparator
import dev.individuation.chiptune.ui.editor.PlainStepper
import dev.individuation.chiptune.ui.editor.SheetBar
import dev.individuation.chiptune.ui.editor.SwipeAction
import dev.individuation.chiptune.ui.editor.SwipeActionsRow
import dev.individuation.chiptune.ui.editor.SwipeRevealGroup
import dev.individuation.chiptune.ui.editor.plainClickable
import dev.individuation.chiptune.ui.layout.ArrangementCapacityAnnouncement
import dev.individuation.chiptune.ui.layout.ArrangementCopy
import dev.individuation.chiptune.ui.layout.ArrangementEditToggle
import dev.individuation.chiptune.ui.layout.PatternChipAccessibility
import dev.individuation.chiptune.ui.theme.ChipColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.isActive

/**
 * The play order (iOS `ArrangementView`), opened by ARR in the transport.
 * [regularWidth] is `LocalChipLayout.current.isRegularWidth` at the call
 * site; Phase 6 hosts [ArrangementPanel] in a popover there.
 */
@Composable
fun ArrangementSheet(editor: Editor, regularWidth: Boolean, onDismiss: () -> Unit) {
    ChipSheet(onDismiss = onDismiss, containerColor = FormColors.sheet) {
        ArrangementPanel(editor, onDismiss)
    }
}

/** The play order with its bar: Edit pill, title, Done. */
@Composable
fun ArrangementPanel(editor: Editor, onDismiss: () -> Unit) {
    var editing by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        SheetBar(
            title = "Arrangement",
            leading = {
                if (ArrangementEditToggle.title(editing) == "Edit") {
                    BarPill("Edit", { editing = ArrangementEditToggle.toggled(editing) })
                } else {
                    BarIconPill(Icons.Filled.Check, ArrangementEditToggle.title(editing), { editing = ArrangementEditToggle.toggled(editing) })
                }
            },
            trailing = { BarPill("Done", onDismiss) },
        )
        ArrangementList(editor, editing)
    }
}

/** The row being dragged, and how far. Visual only until the drop, which
 * is one `moveSection` (one undo step). */
@Stable
private class SectionDrag {
    var key by mutableStateOf<String?>(null)
    var from by mutableStateOf(-1)
    var over by mutableStateOf(-1)
    var offset by mutableFloatStateOf(0f)
    var rowHeight by mutableFloatStateOf(0f)

    val active: Boolean get() = key != null

    fun reset() {
        key = null
        from = -1
        over = -1
        offset = 0f
    }

    /** How far row [index] slides aside while the dragged row hovers. */
    fun shift(index: Int): Float = when {
        !active || index == from -> 0f
        from < over && index in (from + 1)..over -> -rowHeight
        from > over && index in over until from -> rowHeight
        else -> 0f
    }
}

private const val SECTION_KEY = "section-"

@Composable
private fun ArrangementList(editor: Editor, editing: Boolean) {
    val studio = editor.studio
    val ui = editor.ui
    val view = LocalView.current
    val song by remember { derivedStateOf { ui.value.song } }
    val playingSection by remember {
        derivedStateOf { ui.value.let { if (it.isPlaying && it.songMode) it.playingSection else -1 } }
    }
    val listState = rememberLazyListState()
    val drag = remember { SectionDrag() }
    val swipe = remember { SwipeRevealGroup() }
    val scope = rememberCoroutineScope()
    val canDelete = ArrangementCopy.canDelete(song.arrangement.size)

    AnnounceCapacity(view, ui = { ui.value.song.exceedsChainCapacity })

    // Scrolls while a dragged row is held near an edge; the row stays under
    // the finger by taking up the scrolled distance.
    LaunchedEffect(drag.active) {
        if (!drag.active) return@LaunchedEffect
        while (isActive && drag.active) {
            val info = listState.layoutInfo
            val item = info.visibleItemsInfo.firstOrNull { it.key == drag.key }
            if (item != null) {
                val top = item.offset + drag.offset
                val bottom = top + item.size
                val edge = 48f
                val speed = when {
                    top < info.viewportStartOffset + edge -> -12f
                    bottom > info.viewportEndOffset - edge -> 12f
                    else -> 0f
                }
                if (speed != 0f) {
                    val used = listState.scrollBy(speed)
                    drag.offset += used
                    updateOver(drag, listState)
                }
            }
            delay(16)
        }
    }

    fun beginDrag(section: SongSection, position: Int) {
        val item = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == SECTION_KEY + section.id } ?: return
        swipe.open = null
        drag.key = SECTION_KEY + section.id
        drag.from = position
        drag.over = position
        drag.offset = 0f
        drag.rowHeight = item.size.toFloat()
        editor.haptics.reorderBegan()
    }
    fun moveDrag(dy: Float) {
        if (!drag.active) return
        val before = drag.over
        drag.offset += dy
        updateOver(drag, listState)
        if (drag.over != before) editor.haptics.reorderStep()
    }
    fun endDrag() {
        if (!drag.active) return
        val from = drag.from
        val over = drag.over
        drag.reset()
        if (from >= 0 && over >= 0 && from != over) {
            studio.moveSection(setOf(from), ArrangementReorder.destination(from, over))
        }
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 24.dp),
    ) {
        item(key = "header") { FormHeader("Play order") }
        itemsIndexed(song.arrangement, key = { _, section -> SECTION_KEY + section.id }) { position, section ->
            val isDragged = drag.key == SECTION_KEY + section.id
            val shift by animateFloatAsState(if (isDragged) 0f else drag.shift(position), label = "sectionShift")
            val first = position == 0
            Box(
                Modifier
                    .graphicsLayer {
                        translationY = if (isDragged) drag.offset else shift
                        if (isDragged) {
                            scaleX = 1.02f
                            scaleY = 1.02f
                        }
                    }
                    .then(if (isDragged) Modifier.shadow(8.dp, RoundedCornerShape(12.dp)) else Modifier)
                    .clip(RoundedCornerShape(topStart = if (first) 20.dp else 0.dp, topEnd = if (first) 20.dp else 0.dp))
                    .background(FormColors.group),
            ) {
              Column {
                SwipeActionsRow(
                    key = section.id,
                    group = swipe,
                    leading = emptyList(),
                    trailing = if (canDelete && !editing) {
                        listOf(SwipeAction("Delete", null, Color(0xFFFF3B30), Color.White) { studio.removeSection(setOf(position)) })
                    } else {
                        emptyList()
                    },
                    enabled = !editing && canDelete && !drag.active,
                ) {
                    SectionRow(
                        editor = editor,
                        song = song,
                        position = position,
                        section = section,
                        playing = playingSection == position,
                        editing = editing,
                        canDelete = canDelete,
                        handleModifier = Modifier.pointerInput(section.id, position) {
                            detectDragGestures(
                                onDragStart = { beginDrag(section, position) },
                                onDragEnd = ::endDrag,
                                onDragCancel = ::endDrag,
                            ) { change, amount ->
                                change.consume()
                                moveDrag(amount.y)
                            }
                        },
                        modifier = Modifier.pointerInput(section.id, position, editing) {
                            if (editing) return@pointerInput
                            detectDragGesturesAfterLongPress(
                                onDragStart = { beginDrag(section, position) },
                                onDragEnd = ::endDrag,
                                onDragCancel = ::endDrag,
                            ) { change, amount ->
                                change.consume()
                                moveDrag(amount.y)
                            }
                        },
                        onMove = { delta ->
                            val dest = position + delta
                            if (dest in song.arrangement.indices) {
                                studio.moveSection(setOf(position), ArrangementReorder.destination(position, dest))
                            }
                        },
                    )
                }
                FormSeparator()
              }
            }
        }
        item(key = "add") { AddSectionRow(studio, song) }
        item(key = "summary") {
            FormFooter(ArrangementCopy.summary(song))
            Spacer(Modifier.height(18.dp))
        }
        if (song.exceedsChainCapacity) {
            item(key = "capacity") {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(FormColors.group)
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = ORANGE, modifier = Modifier.size(16.dp))
                    Text(ArrangementCopy.CAPACITY_WARNING, color = ORANGE, fontSize = 12.sp, lineHeight = 16.sp)
                }
                Spacer(Modifier.height(18.dp))
            }
        }
        item(key = "help") {
            Text(
                ArrangementCopy.HELP,
                color = ChipColors.dim,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(FormColors.group)
                    .padding(horizontal = 20.dp, vertical = 12.dp),
            )
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

/** iOS's `.orange` in dark mode. */
private val ORANGE = Color(0xFFFF9F0A)

/** Which section the dragged row's centre is over. */
private fun updateOver(drag: SectionDrag, listState: LazyListState) {
    val items = listState.layoutInfo.visibleItemsInfo
    val dragged = items.firstOrNull { it.key == drag.key } ?: return
    val centre = dragged.offset + drag.offset + dragged.size / 2f
    val sections = items.filter { (it.key as? String)?.startsWith(SECTION_KEY) == true }
    if (sections.isEmpty()) return
    // Positions are the lazy indices less the header item.
    val hit = sections.firstOrNull { centre >= it.offset && centre < it.offset + it.size }
    drag.over = when {
        hit != null -> hit.index - 1
        centre < sections.first().offset -> sections.first().index - 1
        else -> sections.last().index - 1
    }
}

/** Says the 128-play warning once, when the arrangement crosses it. */
@Composable
private fun AnnounceCapacity(view: View, ui: () -> Boolean) {
    LaunchedEffect(view) {
        var previous = ui()
        snapshotFlow(ui).distinctUntilChanged().collect { now ->
            if (ArrangementCapacityAnnouncement.shouldAnnounce(previous, now)) {
                @Suppress("DEPRECATION")
                view.announceForAccessibility(ArrangementCopy.CAPACITY_WARNING)
            }
            previous = now
        }
    }
}

@Composable
private fun SectionRow(
    editor: Editor,
    song: Song,
    position: Int,
    section: SongSection,
    playing: Boolean,
    editing: Boolean,
    canDelete: Boolean,
    onMove: (Int) -> Unit,
    modifier: Modifier = Modifier,
    handleModifier: Modifier = Modifier,
) {
    val studio = editor.studio
    val index = song.patternIndex(section.patternID)
    val pattern = index?.let { song.patterns.getOrNull(it) }
    Row(
        Modifier
            .fillMaxWidth()
            .background(FormColors.group)
            .then(modifier)
            .heightIn(min = 52.dp)
            .padding(start = if (editing) 12.dp else 16.dp, end = if (editing) 8.dp else 16.dp, top = 6.dp, bottom = 6.dp)
            .semantics {
                // Reordering without a drag, for TalkBack and switch users.
                customActions = buildList {
                    if (position > 0) add(CustomAccessibilityAction("Move up") { onMove(-1); true })
                    if (position < song.arrangement.size - 1) add(CustomAccessibilityAction("Move down") { onMove(1); true })
                    if (canDelete) add(CustomAccessibilityAction("Delete") { studio.removeSection(setOf(position)); true })
                }
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (editing) {
            Box(
                Modifier.size(32.dp).plainClickable(enabled = canDelete) { studio.removeSection(setOf(position)) }
                    .semantics { contentDescription = "Delete section ${position + 1}" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.RemoveCircle,
                    contentDescription = null,
                    tint = if (canDelete) Color(0xFFFF3B30) else ChipColors.dim.copy(alpha = 0.4f),
                    modifier = Modifier.size(22.dp),
                )
            }
        }
        Leading(ArrangementRowLeading.content(position, playing))
        Row(Modifier.weight(1f)) {
            PatternMenu(studio, song, position, section, pattern?.name, playing, pattern?.isEmpty ?: true)
        }
        Text(
            "\u00d7${section.repeats}",
            color = ChipColors.dim,
            fontSize = 15.sp,
            modifier = Modifier.clearAndSetSemantics { },
        )
        PlainStepper(
            value = section.repeats,
            onValueChange = { studio.setSection(section.id, repeats = it) },
            range = 1..SongSection.MAX_REPEATS,
            accessibilityLabel = RepeatsAccessibility.label(position),
            accessibilityValue = RepeatsAccessibility.value(section.repeats),
        )
        if (editing) {
            Box(
                Modifier.size(36.dp, 44.dp).then(handleModifier).clearAndSetSemantics { },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.DragHandle, contentDescription = null, tint = ChipColors.dim, modifier = Modifier.size(22.dp))
            }
        }
    }
}

/** The section number, or the green playing marker in its place. */
@Composable
private fun Leading(content: ArrangementRowLeading) {
    Box(Modifier.width(18.dp), contentAlignment = Alignment.CenterEnd) {
        when (content) {
            is ArrangementRowLeading.Number -> Text(content.text, color = ChipColors.dim, fontSize = 12.sp, modifier = Modifier.clearAndSetSemantics { })
            ArrangementRowLeading.PlayingMarker ->
                Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = null, tint = Color(0xFF30D158), modifier = Modifier.size(15.dp))
        }
    }
}

@Composable
private fun PatternMenu(
    studio: Studio,
    song: Song,
    position: Int,
    section: SongSection,
    name: String?,
    playing: Boolean,
    isEmpty: Boolean,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .clip(RoundedCornerShape(7.dp))
                .background(ChipColors.dim.copy(alpha = 0.18f))
                .plainClickable { open = true }
                .clearAndSetSemantics {
                    contentDescription = ArrangementCopy.sectionLabel(position, name)
                    PatternChipAccessibility.value(playing, isEmpty)?.let { stateDescription = it }
                    role = Role.DropdownList
                    onClick { open = true; true }
                }
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                name ?: "?",
                color = FormColors.tint,
                fontSize = 17.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                softWrap = false,
            )
            Icon(Icons.Filled.UnfoldMore, contentDescription = null, tint = FormColors.tint, modifier = Modifier.size(13.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = ChipColors.panelHigh) {
            song.patterns.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(candidate.name, color = ChipColors.text, style = MaterialTheme.typography.bodyLarge) },
                    trailingIcon = if (candidate.id == section.patternID) {
                        { Icon(Icons.Filled.Check, contentDescription = null, tint = ChipColors.text) }
                    } else {
                        null
                    },
                    onClick = {
                        open = false
                        studio.setSection(section.id, patternID = candidate.id)
                    },
                )
            }
        }
    }
}

@Composable
private fun AddSectionRow(studio: Studio, song: Song) {
    var open by remember { mutableStateOf(false) }
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(bottomStart = 20.dp, bottomEnd = 20.dp)).background(FormColors.group),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .plainClickable { open = true }
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = FormColors.tint, modifier = Modifier.size(22.dp))
            Text("Add section", color = FormColors.tint, fontSize = 17.sp)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = ChipColors.panelHigh) {
            song.patterns.forEach { pattern ->
                DropdownMenuItem(
                    text = { Text("Pattern ${pattern.name}", color = ChipColors.text, style = MaterialTheme.typography.bodyLarge) },
                    onClick = {
                        open = false
                        studio.addSection(pattern.id)
                    },
                )
            }
        }
    }
}
