package dev.individuation.chiptune.ui.editor

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberTransition
import androidx.compose.animation.core.spring
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.em
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import dev.individuation.chiptune.core.model.EffectMark
import dev.individuation.chiptune.ui.layout.CellMenuPlacement
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import dev.individuation.chiptune.core.studio.ControlLabel
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.GridCellText
import dev.individuation.chiptune.core.model.NoteEffect
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Track
import dev.individuation.chiptune.core.model.TrackReorder
import dev.individuation.chiptune.ui.layout.CellAccessibility
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.GridFollow
import dev.individuation.chiptune.ui.layout.GridPinning
import dev.individuation.chiptune.ui.layout.GridReveal
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.ChipRadii
import dev.individuation.chiptune.ui.theme.chipFont
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/** iOS's `onLongPressGesture` default: half a second. */
private const val CELL_LONG_PRESS_MS = 500L

/** A long press on a track header this long starts reorder mode. */
private const val REORDER_LONG_PRESS_MS = 450L

/** The header under the finger while a reorder drag is live. */
private data class HeaderDrag(val id: UUID, val source: Int, val translation: Float, val destination: Int)

/** Reorder mode: entered by a long press on a header, local to the grid. */
@Stable
private class ReorderState {
    var reordering by mutableStateOf(false)
    var drag by mutableStateOf<HeaderDrag?>(null)

    /** The other columns' slide while a drag hovers, by track id. */
    var slides by mutableStateOf<Map<UUID, Animatable<Float, AnimationVector1D>>>(emptyMap())

    /** The dropped column settling from under the finger into its slot. */
    var settle by mutableStateOf<Pair<UUID, Animatable<Float, AnimationVector1D>>?>(null)

    /** Where column [id] draws, in px. Read inside `graphicsLayer`, so a
     * drag moves layers rather than recomposing the grid. */
    fun offsetPx(id: UUID): Float {
        val d = drag
        if (d == null) {
            val s = settle
            return if (s != null && s.first == id) s.second.value else 0f
        }
        if (d.id == id) return d.translation
        return slides[id]?.value ?: 0f
    }
}

/** A `ViewConfiguration` with a different long-press timeout. */
private class LongPressConfiguration(base: ViewConfiguration, override val longPressTimeoutMillis: Long) : ViewConfiguration by base

/**
 * The step grid: one column per track, one row per step (port of
 * `GridView.swift`). Scrolls sideways once the columns stop fitting, with the
 * step numbers pinned at the leading edge.
 */
@Composable
fun GridView(editor: Editor, modifier: Modifier = Modifier) {
    val layout = LocalChipLayout.current
    val ui = editor.ui
    val studio = editor.studio
    val song by remember { derivedStateOf { ui.value.song } }
    val selectedPattern by remember { derivedStateOf { ui.value.selectedPattern } }
    val selectedTrack by remember { derivedStateOf { ui.value.selectedTrack } }
    val cursor by remember { derivedStateOf { if (ui.value.hardwareKeyboardInUse) ui.value.selectedTrack to ui.value.selectedStep else null } }
    // In SONG mode the sequencer can be elsewhere, so the highlight only runs
    // when the pattern on screen is the one sounding. -1 when nothing plays.
    val playheadRow = remember { derivedStateOf { val s = ui.value; if (s.isPlaying && s.playingPattern == s.selectedPattern) s.playhead else -1 } }
    val reorder = remember { ReorderState() }
    val liftedId by remember { derivedStateOf { reorder.drag?.id } }
    val hScroll = rememberScrollState()
    val listState = rememberLazyListState()
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    val pattern = song.patterns.getOrNull(selectedPattern) ?: song.patterns[0]
    val tracks = song.tracks
    val canAddTrack = song.canAddTrack
    val gutter = layout.gridGutterWidth
    val rowHeight = layout.gridRowHeight

    fun endReordering() {
        if (!reorder.reordering) return
        reorder.reordering = false
        reorder.drag = null
    }

    fun beginReordering() {
        if (!studio.song.canReorderTracks || reorder.reordering) return
        editor.haptics.reorderBegan()
        reorder.reordering = true
    }

    // A different song has different tracks; one track has nowhere to go.
    LaunchedEffect(song.id) { endReordering() }
    LaunchedEffect(tracks.size) { if (!song.canReorderTracks) endReordering() }

    BoxWithConstraints(modifier.background(ChipColors.background)) {
        val columnWidth = layout.gridColumnWidth(maxWidth.value.toDouble(), tracks.size, canAddTrack)
        val rowWidth = layout.gridRowWidth(columnWidth, tracks.size, canAddTrack)
        val columnStepPx = with(density) { (columnWidth + GridPinning.COLUMN_GAP).toFloat().dp.toPx() }

        fun dragTo(index: Int, id: UUID, translation: Float) {
            val current = reorder.drag
            if (current == null) {
                // Fresh slides at zero, made now so the first frame reads them.
                reorder.slides = studio.song.tracks.associate { it.id to Animatable(0f) }
                reorder.settle = null
            }
            val destination = TrackReorder.destination(index, translation.toDouble(), columnStepPx.toDouble(), studio.song.tracks.size)
            if (current != null && current.destination != destination) editor.haptics.reorderStep()
            reorder.drag = HeaderDrag(id, index, translation, destination)
        }

        fun drop() {
            val d = reorder.drag ?: return
            val remaining = d.translation - (d.destination - d.source) * columnStepPx
            val settle = Animatable(remaining)
            reorder.settle = d.id to settle
            studio.moveTrack(d.source, d.destination)
            reorder.drag = null
            scope.launch { settle.animateTo(0f, tween(250, easing = FastOutSlowInEasing)) }
        }

        fun move(index: Int, destination: Int) {
            studio.moveTrack(index, destination)
        }

        // Neighbours slide aside whenever the destination changes.
        val stepPx by rememberUpdatedState(columnStepPx)
        LaunchedEffect(Unit) {
            snapshotFlow { reorder.drag?.let { it.source to it.destination } }.distinctUntilChanged().collect { pair ->
                val (source, destination) = pair ?: return@collect
                studio.song.tracks.forEachIndexed { i, track ->
                    val target = TrackReorder.offset(i, source, destination, stepPx.toDouble()).toFloat()
                    reorder.slides[track.id]?.let { anim -> launch { anim.animateTo(target, tween(200, easing = FastOutSlowInEasing)) } }
                }
            }
        }

        CappedTextScale {
            Box(Modifier.fillMaxSize().horizontalScroll(hScroll, enabled = reorder.drag == null)) {
                Column(Modifier.width(rowWidth.dpValue()).fillMaxHeight()) {
                    HeaderRow(
                        editor = editor,
                        tracks = tracks,
                        song = song,
                        selectedTrack = selectedTrack,
                        reorder = reorder,
                        liftedId = liftedId,
                        columnWidth = columnWidth.dpValue(),
                        onBeginReorder = ::beginReordering,
                        onDragTo = ::dragTo,
                        onDrop = ::drop,
                        onMove = ::move,
                    )
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        StepRows(
                            editor = editor,
                            listState = listState,
                            hScroll = hScroll,
                            pattern = pattern,
                            tracks = tracks,
                            labels = tracks.indices.map { song.fullLabel(it) },
                            canAddTrack = canAddTrack,
                            columnWidth = columnWidth.dpValue(),
                            cursor = cursor,
                            playheadRow = playheadRow,
                            reorder = reorder,
                            liftedId = liftedId,
                            modifier = Modifier.fillMaxSize().graphicsLayer { alpha = if (reorder.reordering) 0.4f else 1f },
                        )
                        // In the mode the notes are along for the ride: a tap on
                        // them means "done", not a note you can't see you wrote.
                        if (reorder.reordering) {
                            Box(
                                Modifier.matchParentSize()
                                    .pointerInput(Unit) { detectTapGestures { endReordering() } }
                                    .semantics { hideFromAccessibility() },
                            )
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = reorder.reordering,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            ReorderBar { endReordering() }
        }

        // MARK: Scrolling

        // Sideways: a new song, an added track or an undo that moves the
        // selection brings the selected column on screen.
        val revealTrigger = remember {
            derivedStateOf {
                val s = ui.value
                GridReveal.Trigger(s.song.id, s.song.tracks.size, s.selectedTrack, s.revealRequest)
            }
        }
        val currentColumnWidth by rememberUpdatedState(columnWidth)
        LaunchedEffect(Unit) {
            var old = revealTrigger.value
            snapshotFlow { revealTrigger.value }.collect { new ->
                val target = GridReveal.target(old, new)
                old = new
                if (target != null) {
                    // Let the new column lay out before measuring the scroll range.
                    awaitFrame()
                    awaitFrame()
                    val px = { dp: Double -> with(density) { dp.toFloat().dp.toPx().toDouble() } }
                    val viewport = hScroll.viewportSize.toDouble()
                    val max = hScroll.maxValue.toDouble()
                    val colW = px(currentColumnWidth)
                    val to = when (target) {
                        GridReveal.Target.TrailingEdge -> max
                        is GridReveal.Target.Track ->
                            GridReveal.centredScroll(px(GridPinning.columnStart(target.index, gutter, currentColumnWidth)), colW, viewport, max)
                        is GridReveal.Target.Nearest -> {
                            val start = px(GridPinning.columnStart(target.index, gutter, currentColumnWidth))
                            GridReveal.nearestScroll(hScroll.value.toDouble(), start - px(GridPinning.revealClearance(gutter)), start + colW, viewport, max)
                        }
                    }
                    hScroll.animateScrollTo(to.toInt(), tween(200, easing = LinearOutSlowInEasing))
                }
            }
        }
    }

    // Down: playback drags the rows along only when the playing row is
    // clipped or off screen, to the top, in at most half a step.
    LaunchedEffect(listState) {
        snapshotFlow { playheadRow.value }.collect { step ->
            if (step < 0) return@collect
            val info = listState.layoutInfo
            val rowPx = with(density) { rowHeight.toFloat().dp.toPx() }
            val gapPx = with(density) { GridFollow.ROW_SPACING.toFloat().dp.toPx() }
            val viewportDp = info.viewportSize.height / density.density
            val steps = editor.studio.patternLength
            if (!GridFollow.follows(steps, rowHeight, viewportDp.toDouble())) return@collect
            val item = info.visibleItemsInfo.firstOrNull { it.index == step }
            val inView = item != null && item.offset >= info.viewportStartOffset - 1 &&
                item.offset + item.size <= info.viewportEndOffset + 1
            if (inView) return@collect
            val first = info.visibleItemsInfo.firstOrNull() ?: return@collect
            val offset = item?.offset ?: (first.offset + (step - first.index) * (rowPx + gapPx)).toInt()
            val delta = (offset - info.viewportStartOffset).toFloat()
            val ms = (GridFollow.scrollDuration(editor.studio.song.tempo) * 1000).toInt()
            listState.animateScrollBy(delta, tween(ms, easing = LinearOutSlowInEasing))
        }
    }
    // A pattern switch starts at the top of the new block.
    LaunchedEffect(selectedPattern) { listState.scrollToItem(0) }
    // An arrow key walking the cursor off the visible rows brings the grid,
    // unless the playhead is driving.
    val selectedStep by remember { derivedStateOf { if (ui.value.hardwareKeyboardInUse) ui.value.selectedStep else -1 } }
    LaunchedEffect(selectedStep) {
        if (selectedStep < 0 || playheadRow.value >= 0) return@LaunchedEffect
        val info = listState.layoutInfo
        val item = info.visibleItemsInfo.firstOrNull { it.index == selectedStep }
        if (item != null && item.offset >= info.viewportStartOffset && item.offset + item.size <= info.viewportEndOffset) return@LaunchedEffect
        val rowPx = with(density) { rowHeight.toFloat().dp.toPx() }
        listState.animateScrollToItem(selectedStep, -((info.viewportSize.height - rowPx) / 2).toInt())
    }
}

/** Track headers and the "+" column. */
@Composable
private fun HeaderRow(
    editor: Editor,
    tracks: List<Track>,
    song: dev.individuation.chiptune.core.model.Song,
    selectedTrack: Int,
    reorder: ReorderState,
    liftedId: UUID?,
    columnWidth: Dp,
    onBeginReorder: () -> Unit,
    onDragTo: (Int, UUID, Float) -> Unit,
    onDrop: () -> Unit,
    onMove: (Int, Int) -> Unit,
) {
    val layout = LocalChipLayout.current
    Row(
        Modifier.padding(horizontal = GridPinning.ROW_INSET.dpValue()).padding(bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(GridPinning.COLUMN_GAP.dpValue()),
    ) {
        Spacer(Modifier.width(layout.gridGutterWidth.dpValue()))
        tracks.forEachIndexed { index, track ->
            key(track.id) {
                val lifted = liftedId == track.id
                TrackHeader(
                    editor = editor,
                    index = index,
                    track = track,
                    label = song.label(index),
                    fullLabel = song.fullLabel(index),
                    selected = selectedTrack == index,
                    reordering = reorder.reordering,
                    count = tracks.size,
                    width = columnWidth,
                    onMove = { destination -> onMove(index, destination) },
                    modifier = Modifier
                        .zIndex(if (lifted) 1f else 0f)
                        .headerGestures(index, track.id, reorder, onBeginReorder, onDragTo, onDrop)
                        .graphicsLayer {
                            translationX = reorder.offsetPx(track.id)
                            val up = reorder.drag?.id == track.id
                            scaleX = if (up) 1.06f else 1f
                            scaleY = if (up) 1.06f else 1f
                            shadowElevation = if (up) 10.dp.toPx() else 0f
                            shape = RoundedCornerShape(ChipRadii.panel)
                        },
                )
            }
        }
        if (song.canAddTrack) AddTrackButton(editor, enabled = !reorder.reordering)
    }
}

/**
 * The header's long press and drag. Read at the Initial pass, so the name and
 * mute buttons inside keep their taps; nothing is consumed until the press
 * has become a reorder.
 *
 * Out of the mode: held still for 0.45 s, the header picks the tracks up and
 * the same finger can carry on dragging. In the mode: a drag past touch slop
 * moves the column, and a tap still reaches the arrows.
 */
@Composable
private fun Modifier.headerGestures(
    index: Int,
    id: UUID,
    reorder: ReorderState,
    onBeginReorder: () -> Unit,
    onDragTo: (Int, UUID, Float) -> Unit,
    onDrop: () -> Unit,
): Modifier {
    val currentIndex by rememberUpdatedState(index)
    val begin by rememberUpdatedState(onBeginReorder)
    val dragTo by rememberUpdatedState(onDragTo)
    val drop by rememberUpdatedState(onDrop)
    return pointerInput(id) {
        val slop = viewConfiguration.touchSlop
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            var started: Boolean
            if (!reorder.reordering) {
                // Wait out the long press; a lift or a move before it is a tap
                // or a scroll, and belongs to someone else.
                val ended = withTimeoutOrNull(REORDER_LONG_PRESS_MS) {
                    var result = false
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id }
                        if (change == null || !change.pressed || (change.position - down.position).getDistance() > slop) {
                            result = true
                            break
                        }
                    }
                    result
                }
                if (ended != null) return@awaitEachGesture
                begin()
                if (!reorder.reordering) return@awaitEachGesture
                started = true
            } else {
                started = false
            }
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                if (!change.pressed) {
                    if (started) {
                        change.consume()
                        if (reorder.drag != null) drop()
                    }
                    break
                }
                val dx = change.position.x - down.position.x
                if (!started) {
                    if ((change.position - down.position).getDistance() <= slop) continue
                    started = true
                }
                change.consume()
                if (abs(dx) > 0f || reorder.drag != null) dragTo(currentIndex, id, dx)
            }
        }
    }
}

/**
 * Track name and mute: two stacked full-width targets. The name selects the
 * track (and opens its sound settings once selected); the speaker mutes. In
 * reorder mode the mute row becomes a grip between two arrows.
 */
@Composable
private fun TrackHeader(
    editor: Editor,
    index: Int,
    track: Track,
    label: String,
    fullLabel: String,
    selected: Boolean,
    reordering: Boolean,
    count: Int,
    width: Dp,
    onMove: (Int) -> Unit,
    modifier: Modifier,
) {
    val layout = LocalChipLayout.current
    val studio = editor.studio
    val accent = ChipColors.channel(track.kind)
    val muted = track.muted
    val inner = layout.trackHeaderHeight - 14
    val nameHeight = (inner * 0.53).dpValue()
    val muteHeight = (inner * 0.47).dpValue()
    val docked = layout.docksInstrumentEditor
    val shape = RoundedCornerShape(ChipRadii.panel)

    Column(
        modifier
            // The sound settings' popover hangs from here at regular width.
            .popoverAnchor(editor.presentation.anchors, PopoverAnchor.Track(index))
            .width(width)
            .height(layout.trackHeaderHeight.dpValue())
            .clip(shape)
            .background(if (selected) accent.copy(alpha = 0.18f) else ChipColors.panel)
            .then(if (selected) Modifier.border(1.5.dp, accent, shape) else Modifier)
            .drawBehind {
                // The mode's outline: every header in its own colour, dashed.
                if (reordering && !selected) {
                    val stroke = 1.5.dp.toPx()
                    drawRoundRect(
                        color = accent.copy(alpha = 0.7f),
                        topLeft = Offset(stroke / 2, stroke / 2),
                        size = Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(ChipRadii.panel.toPx()),
                        style = Stroke(stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                    )
                }
            }
            .padding(5.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(nameHeight)
                .plainClickable(enabled = !reordering) {
                    // The long press that starts reorder mode lets go here.
                    if (reordering) return@plainClickable
                    // Every tap demos the sound.
                    studio.previewTrack(index)
                    if (selected && !docked) {
                        editor.presentation.open(Presented.InstrumentEditor(index))
                    } else {
                        studio.selectedTrack = index
                    }
                }
                .clearAndSetSemantics {
                    contentDescription = fullLabel
                    this.selected = selected
                    role = Role.Button
                    onClick(if (selected && !docked) "Opens sound settings" else "Selects this track") {
                        studio.previewTrack(index)
                        if (selected && !docked) editor.presentation.open(Presented.InstrumentEditor(index)) else studio.selectedTrack = index
                        true
                    }
                    // The drag isn't reachable with TalkBack; the moves are.
                    customActions = buildList {
                        if (index > 0) add(CustomAccessibilityAction("Move left") { onMove(index - 1); true })
                        if (index < count - 1) add(CustomAccessibilityAction("Move right") { onMove(index + 1); true })
                    }
                },
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val color = if (muted) ChipColors.dim else accent
            Text(label, style = chipFont(13f), color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (selected && !reordering) SymbolIcon(Icons.Filled.Tune, 9f, color)
        }
        if (reordering) {
            ReorderRow(index, count, muteHeight, onMove)
        } else {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(muteHeight)
                    .clip(RoundedCornerShape(ChipRadii.cell))
                    .background(if (muted) Color.Black.copy(alpha = 0.35f) else ChipColors.panelHigh)
                    .toggleable(value = muted, role = Role.Switch, onValueChange = { studio.toggleMute(index) })
                    .semantics { contentDescription = "Mute $fullLabel" },
                contentAlignment = Alignment.Center,
            ) {
                SymbolIcon(
                    if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                    13f,
                    if (muted) ChipColors.dim else ChipColors.text,
                )
            }
        }
    }
}

/** The grip between two one-column nudges. */
@Composable
private fun ReorderRow(index: Int, count: Int, height: Dp, onMove: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(ChipRadii.cell)).background(ChipColors.panelHigh),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Nudge(Icons.Filled.ChevronLeft, enabled = index > 0) { onMove(index - 1) }
        Box(Modifier.weight(1f).semantics { hideFromAccessibility() }, contentAlignment = Alignment.Center) {
            // line.3.horizontal: three bars, so Menu rather than the two-bar DragHandle.
            SymbolIcon(Icons.Filled.Menu, 14f, ChipColors.text)
        }
        Nudge(Icons.Filled.ChevronRight, enabled = index < count - 1) { onMove(index + 1) }
    }
}

@Composable
private fun Nudge(icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.width(26.dp).fillMaxHeight().plainClickable(enabled = enabled, onClick = onClick)
            // The header already offers these as actions.
            .semantics { hideFromAccessibility() },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(icon, 17f, if (enabled) ChipColors.text else ChipColors.dim.copy(alpha = 0.4f))
    }
}

/** "+" with a menu of the four channel kinds. Kept in place in the mode, so
 * the columns don't resize under a drag, but out of play. */
@Composable
private fun AddTrackButton(editor: Editor, enabled: Boolean) {
    val layout = LocalChipLayout.current
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier
                .width(ChipLayout.ADD_COLUMN_WIDTH.dpValue())
                .height(layout.trackHeaderHeight.dpValue())
                .graphicsLayer { alpha = if (enabled) 1f else 0.3f }
                .clip(RoundedCornerShape(ChipRadii.panel))
                .background(ChipColors.panel)
                .plainClickable(enabled = enabled) { open = true }
                .semantics { contentDescription = "Add track" },
            contentAlignment = Alignment.Center,
        ) {
            SymbolIcon(Icons.Filled.Add, 15f, ChipColors.text)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = ChipColors.panelHigh, shape = RoundedCornerShape(ChipRadii.panel)) {
            for (kind in ChannelKind.entries) {
                DropdownMenuItem(
                    text = { Text(kind.fullName, style = MaterialTheme.typography.bodyLarge, color = ChipColors.text) },
                    onClick = {
                        open = false
                        editor.studio.addTrack(kind)
                    },
                )
            }
        }
    }
}

/** The step rows, lazily: only the rows on screen exist. */
@Composable
private fun StepRows(
    editor: Editor,
    listState: LazyListState,
    hScroll: ScrollState,
    pattern: Pattern,
    tracks: List<Track>,
    labels: List<String>,
    canAddTrack: Boolean,
    columnWidth: Dp,
    cursor: Pair<Int, Int>?,
    playheadRow: State<Int>,
    reorder: ReorderState,
    liftedId: UUID?,
    modifier: Modifier,
) {
    val studio = editor.studio
    val haptics = editor.haptics
    val onTap = remember(studio) {
        { track: Int, step: Int ->
            haptics.gridCell()
            studio.placeCursor(track, step)
            studio.toggleCell(track, step)
        }
    }
    val onPreview = remember(studio) { { track: Int, step: Int -> studio.previewCell(track, step); Unit } }
    val onMenu = remember(haptics) { { haptics.cellMenu() } }
    // The choice is heard: the note plays with its new effect.
    val onEffect = remember(studio) {
        { track: Int, step: Int, effect: NoteEffect ->
            studio.setEffect(track, step, effect)
            studio.previewCell(track, step)
            Unit
        }
    }
    val base = LocalViewConfiguration.current
    val cellConfiguration = remember(base) { LongPressConfiguration(base, CELL_LONG_PRESS_MS) }
    CompositionLocalProvider(LocalViewConfiguration provides cellConfiguration) {
        LazyColumn(
            modifier,
            state = listState,
            contentPadding = PaddingValues(vertical = GridFollow.VERTICAL_PADDING.dpValue()),
            verticalArrangement = Arrangement.spacedBy(GridFollow.ROW_SPACING.dpValue()),
        ) {
            items(pattern.length, key = { it }, contentType = { 0 }) { step ->
                StepRow(
                    step = step,
                    pattern = pattern,
                    tracks = tracks,
                    labels = labels,
                    canAddTrack = canAddTrack,
                    columnWidth = columnWidth,
                    cursorTrack = if (cursor != null && cursor.second == step) cursor.first else -1,
                    hScroll = hScroll,
                    playheadRow = playheadRow,
                    reorder = reorder,
                    liftedId = liftedId,
                    onTap = onTap,
                    onPreview = onPreview,
                    onMenu = onMenu,
                    onEffect = onEffect,
                )
            }
        }
    }
}

@Composable
private fun StepRow(
    step: Int,
    pattern: Pattern,
    tracks: List<Track>,
    labels: List<String>,
    canAddTrack: Boolean,
    columnWidth: Dp,
    cursorTrack: Int,
    hScroll: ScrollState,
    playheadRow: State<Int>,
    reorder: ReorderState,
    liftedId: UUID?,
    onTap: (Int, Int) -> Unit,
    onPreview: (Int, Int) -> Unit,
    onMenu: () -> Unit,
    onEffect: (Int, Int, NoteEffect) -> Unit,
) {
    val layout = LocalChipLayout.current
    val gutter = layout.gridGutterWidth
    val highlight = Color.White.copy(alpha = 0.14f)
    Row(
        Modifier
            .height(layout.gridRowHeight.dpValue())
            // Its own layer, so a playhead tick re-records this row alone
            // rather than the whole list's display list.
            .graphicsLayer()
            // The playhead, read in the draw phase: a tick repaints the rows on
            // screen instead of recomposing them.
            .drawBehind { if (playheadRow.value == step) drawRect(highlight) }
            .padding(horizontal = GridPinning.ROW_INSET.dpValue()),
        horizontalArrangement = Arrangement.spacedBy(GridPinning.COLUMN_GAP.dpValue()),
    ) {
        // Pinned: counters the horizontal scroll, over an opaque backing so
        // cells slide underneath. It carries the playhead too.
        Box(
            Modifier
                .zIndex(2f)
                .width(gutter.dpValue())
                .fillMaxHeight()
                .offset { IntOffset(GridPinning.labelOffset(hScroll.value.toDouble()).toInt(), 0) }
                .drawBehind {
                    val backing = GridPinning.backing(gutter, hScroll.value.toDouble())
                    val left = backing.leading.toFloat().dp.toPx()
                    val w = backing.width.toFloat().dp.toPx()
                    drawRect(ChipColors.background, topLeft = Offset(left, 0f), size = Size(w, size.height))
                    if (playheadRow.value == step) drawRect(highlight, topLeft = Offset(left, 0f), size = Size(w, size.height))
                }
                .semantics { hideFromAccessibility() },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                String.format(Locale.ROOT, "%02d", step),
                style = chipFont(11f),
                color = if (step % 4 == 0) ChipColors.text else ChipColors.dim,
                maxLines = 1,
                softWrap = false,
            )
        }
        tracks.forEachIndexed { index, track ->
            key(track.id) {
                GridCell(
                    note = pattern.rows.getOrNull(index)?.getOrNull(step) ?: Chip.EMPTY_NOTE,
                    effect = pattern.effect(index, step),
                    kind = track.kind,
                    muted = track.muted,
                    step = step,
                    track = index,
                    atCursor = cursorTrack == index,
                    label = labels.getOrElse(index) { "" },
                    onTap = onTap,
                    onPreview = onPreview,
                    onMenu = onMenu,
                    onEffect = onEffect,
                    modifier = Modifier
                        .zIndex(if (liftedId == track.id) 1f else 0f)
                        .width(columnWidth)
                        .fillMaxHeight()
                        // The notes travel with their header.
                        .graphicsLayer { translationX = reorder.offsetPx(track.id) },
                )
            }
        }
        if (canAddTrack) Spacer(Modifier.width(ChipLayout.ADD_COLUMN_WIDTH.dpValue()))
    }
}

/**
 * One step on one track. A tap writes (or clears, or replaces). A long press
 * on a note opens its effect menu; on a REST or an empty step it previews
 * what's there. Either way the tap is cancelled.
 */
@Composable
private fun GridCell(
    note: Int,
    effect: NoteEffect,
    kind: ChannelKind,
    muted: Boolean,
    step: Int,
    track: Int,
    atCursor: Boolean,
    label: String,
    onTap: (Int, Int) -> Unit,
    onPreview: (Int, Int) -> Unit,
    onMenu: () -> Unit,
    onEffect: (Int, Int, NoteEffect) -> Unit,
    modifier: Modifier,
) {
    val filled = note != Chip.EMPTY_NOTE
    val isOff = note == Chip.NOTE_OFF
    val title = GridCellText.title(note, effect)
    val mark = GridCellText.mark(note, effect)
    val hasMenu = GridCellText.offersEffects(note)
    // Muting fades the fill to 35% over near-black, so dark note text flips light.
    val titleColor = when {
        !filled -> ChipColors.dim.copy(alpha = 0.6f)
        muted -> ChipColors.text.copy(alpha = 0.85f)
        else -> ChipColors.onLight.copy(alpha = 0.85f)
    }
    val fill = when {
        !filled -> ChipColors.rowTint(step)
        else -> (if (isOff) ChipColors.dim else ChipColors.channel(kind)).copy(alpha = if (muted) 0.35f else 1f)
    }
    val shape = RoundedCornerShape(ChipRadii.cell)
    var pressed by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val tap by rememberUpdatedState(onTap)
    val preview by rememberUpdatedState(onPreview)
    val openMenu by rememberUpdatedState(onMenu)
    val setEffect by rememberUpdatedState(onEffect)
    val offersMenu by rememberUpdatedState(hasMenu)
    // The cell's layout, for sizing its menu. Not state, and the window bounds
    // are only worked out when the menu opens, not on every scroll frame.
    val placed = remember { arrayOfNulls<LayoutCoordinates>(1) }
    Box(
        modifier
            .onGloballyPositioned { placed[0] = it }
            .drawWithContent {
                drawContent()
                // White, not the accent: the ring must show on a filled cell.
                // It also marks the note whose effect menu is open.
                if (atCursor || menu) {
                    drawRoundRect(
                        ChipColors.text,
                        cornerRadius = CornerRadius(ChipRadii.cell.toPx()),
                        style = Stroke(GridPinning.CURSOR_RING_WIDTH.toFloat().dp.toPx()),
                    )
                }
            }
            .graphicsLayer { alpha = if (pressed) 0.6f else 1f }
            .clip(shape)
            .background(fill)
            .then(if (!filled) Modifier.border(1.dp, ChipColors.grid.copy(alpha = 0.6f), shape) else Modifier)
            .pointerInput(track, step) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        tryAwaitRelease()
                        pressed = false
                    },
                    onLongPress = {
                        if (offersMenu) {
                            openMenu()
                            menu = true
                        } else {
                            preview(track, step)
                        }
                    },
                    onTap = { tap(track, step) },
                )
            }
            .clearAndSetSemantics {
                contentDescription = CellAccessibility.label(label, step)
                stateDescription = CellAccessibility.value(note, effect)
                role = Role.Button
                onClick { tap(track, step); true }
                customActions = buildList {
                    add(CustomAccessibilityAction(CellAccessibility.PREVIEW_ACTION) { preview(track, step); true })
                    if (hasMenu) {
                        for (choice in GridCellText.menuEffects) {
                            add(CustomAccessibilityAction(GridCellText.actionName(choice)) { setEffect(track, step, choice); true })
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        // A marked note shrinks to fit the narrowest column rather than
        // losing its mark to an ellipsis.
        val size = if (filled) 12f else 14f
        val text = remember(title, mark) {
            buildAnnotatedString {
                append(title)
                if (mark != null) appendInlineContent(MARK_ID, mark.displayName)
            }
        }
        BasicText(
            text,
            style = chipFont(size).copy(color = titleColor),
            maxLines = 1,
            softWrap = false,
            // In em, so the mark scales with the text when it shrinks.
            inlineContent = if (mark == null) emptyMap() else mapOf(MARK_ID to markContent(mark, titleColor)),
            autoSize = TextAutoSize.StepBased(minFontSize = (size * 0.6f).sp, maxFontSize = size.sp, stepSize = 0.5.sp),
            modifier = Modifier.padding(horizontal = 3.dp),
        )
        if (hasMenu) {
            EffectMenu(
                expanded = menu,
                current = effect,
                anchor = { placed[0]?.takeIf { it.isAttached }?.boundsInWindow() },
                onDismiss = { menu = false },
                onPick = { choice -> menu = false; setEffect(track, step, choice) },
                onPlay = { menu = false; preview(track, step) },
            )
        }
    }
}

private const val MARK_ID = "effectMark"

/** The effect's mark as a slot in the cell's text: a box [EffectMark.SIZE_EM]
 * tall sat on the baseline, after a small gap. */
private fun markContent(effect: NoteEffect, color: Color) = InlineTextContent(
    Placeholder(
        width = (EffectMark.GAP_EM + EffectMark.SIZE_EM).em,
        height = EffectMark.SIZE_EM.em,
        placeholderVerticalAlign = PlaceholderVerticalAlign.AboveBaseline,
    ),
) {
    Canvas(Modifier.fillMaxSize()) {
        val side = size.height
        drawEffectMark(effect, Offset(size.width - side, 0f), side, color)
    }
}

/** Draws [effect]'s [EffectMark] strokes in a [side]-square box at [topLeft]. */
private fun DrawScope.drawEffectMark(effect: NoteEffect, topLeft: Offset, side: Float, color: Color) {
    val stroke = Stroke(width = (EffectMark.STROKE_WIDTH * side).toFloat(), cap = StrokeCap.Round, join = StrokeJoin.Round)
    for (line in EffectMark.strokes(effect)) {
        val path = Path()
        line.forEachIndexed { i, p ->
            val x = topLeft.x + (p.x * side).toFloat()
            val y = topLeft.y + (p.y * side).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color, style = stroke)
    }
}

/** The mark on its own, as a menu icon in the current content colour. */
@Composable
private fun EffectMarkIcon(effect: NoteEffect, size: Dp) {
    val color = LocalContentColor.current
    Canvas(Modifier.size(size).semantics { hideFromAccessibility() }) {
        drawEffectMark(effect, Offset.Zero, this.size.minDimension, color)
    }
}

/** Material3's `MotionScheme.standard()` fast spatial and fast effects
 * springs, which DropdownMenu animates with. */
private val MENU_SCALE_SPEC = spring<Float>(dampingRatio = 0.9f, stiffness = 1400f)
private val MENU_ALPHA_SPEC = spring<Float>(dampingRatio = 1f, stiffness = 3800f)

/** Space between a cell and its menu. */
private val MENU_GAP = 4.dp

/** Kept clear between the menu and the screen's edges. */
private val MENU_MARGIN = 8.dp

/**
 * A note's long-press menu: no effect, each effect with its mark (the
 * current one ticked), then Play. Hangs below the cell, or above it when only
 * that fits, and never over it (see [CellMenuPlacement]); a popup of its own
 * because `DropdownMenu` covers its anchor when neither side holds it.
 */
@Composable
private fun EffectMenu(
    expanded: Boolean,
    current: NoteEffect,
    anchor: () -> Rect?,
    onDismiss: () -> Unit,
    onPick: (NoteEffect) -> Unit,
    onPlay: () -> Unit,
) {
    // Stays composed until the closing animation has run, as DropdownMenu does.
    val expandedState = remember { MutableTransitionState(false) }
    expandedState.targetState = expanded
    if (!expandedState.currentState && !expandedState.targetState) return
    val transformOrigin = remember { mutableStateOf(TransformOrigin.Center) }
    val density = LocalDensity.current
    val view = LocalView.current
    val visible = remember(expanded) { android.graphics.Rect().also { view.getWindowVisibleDisplayFrame(it) } }
    val gap = with(density) { MENU_GAP.toPx().toDouble() }
    val margin = with(density) { MENU_MARGIN.toPx().toDouble() }
    val top = visible.top + margin
    // The popup measures against the visible frame's height; its y runs from
    // the window's top.
    val bottom = visible.height() - margin
    // Rows are 48 dp; the height only decides the side and the cap, and the
    // popup places itself with its real height below.
    val estimate = with(density) { ((GridCellText.menuEffects.size + 1) * 48 + 17).dp.toPx().toDouble() }
    val cell = anchor()
    val maxHeight = if (cell == null) bottom - top else
        CellMenuPlacement.place(cell.top.toDouble(), cell.bottom.toDouble(), top, bottom, estimate, gap).maxHeight
    val position = remember(top, bottom, gap, margin) {
        object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                val place = CellMenuPlacement.place(
                    anchorBounds.top.toDouble(), anchorBounds.bottom.toDouble(),
                    top, windowSize.height - margin, popupContentSize.height.toDouble(), gap,
                )
                val x = CellMenuPlacement.x(anchorBounds.left.toDouble(), popupContentSize.width.toDouble(), windowSize.width.toDouble(), margin)
                val origin = CellMenuPlacement.transformOrigin(
                    anchorBounds.left.toDouble(), anchorBounds.top.toDouble(), anchorBounds.right.toDouble(), anchorBounds.bottom.toDouble(),
                    x, place.y, x + popupContentSize.width, place.y + popupContentSize.height,
                )
                transformOrigin.value = TransformOrigin(origin.first.toFloat(), origin.second.toFloat())
                return IntOffset(x.toInt(), place.y.toInt())
            }
        }
    }
    Popup(popupPositionProvider = position, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        // DropdownMenuContent (Material3 1.4.0): scale from 0.8 and fade, on
        // the standard motion scheme's fast springs.
        val transition = rememberTransition(expandedState, "EffectMenu")
        val scale by transition.animateFloat(transitionSpec = { MENU_SCALE_SPEC }) { if (it) 1f else 0.8f }
        val alpha by transition.animateFloat(transitionSpec = { MENU_ALPHA_SPEC }) { if (it) 1f else 0f }
        Surface(
            modifier = Modifier.graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
                this.transformOrigin = transformOrigin.value
            },
            shape = RoundedCornerShape(ChipRadii.panel),
            color = ChipColors.panelHigh,
            tonalElevation = MenuDefaults.TonalElevation,
            shadowElevation = MenuDefaults.ShadowElevation,
        ) {
            Column(
                Modifier
                    .heightIn(max = with(density) { maxHeight.toFloat().toDp() })
                    // DropdownMenuVerticalPadding, outside the scroll as there.
                    .padding(vertical = 8.dp)
                    .width(IntrinsicSize.Max)
                    .verticalScroll(rememberScrollState()),
            ) {
                val colors = MenuDefaults.itemColors(textColor = ChipColors.text, leadingIconColor = ChipColors.text, trailingIconColor = ChipColors.text)
                for (choice in GridCellText.menuEffects) {
                    val chosen = choice == current
                    DropdownMenuItem(
                        text = { Text(choice.displayName, style = MaterialTheme.typography.bodyLarge) },
                        leadingIcon = {
                            // Space held for the tick so the names line up.
                            Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
                                if (chosen) Icon(Icons.Filled.Check, contentDescription = null)
                            }
                        },
                        trailingIcon = if (choice == NoteEffect.NONE) null else {
                            { EffectMarkIcon(choice, 15.dp) }
                        },
                        onClick = { onPick(choice) },
                        colors = colors,
                        modifier = Modifier.semantics { selected = chosen },
                    )
                }
                HorizontalDivider(color = ChipColors.grid)
                DropdownMenuItem(
                    text = { Text("Play", style = MaterialTheme.typography.bodyLarge) },
                    leadingIcon = { Box(Modifier.size(20.dp)) },
                    trailingIcon = { Icon(Icons.Filled.PlayArrow, contentDescription = null) },
                    onClick = onPlay,
                    colors = colors,
                )
            }
        }
    }
}

/** Says what the mode is for and how to leave it; pinned to the grid's
 * bottom so Done stays on screen with eight tracks scrolled sideways. */
@Composable
private fun ReorderBar(onDone: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = 12.dp)
            .padding(bottom = 12.dp)
            .fillMaxWidth()
            .graphicsLayer {
                shadowElevation = 12.dp.toPx()
                shape = RoundedCornerShape(ChipRadii.tray)
                clip = false
            }
            .background(ChipColors.panelHigh, RoundedCornerShape(ChipRadii.tray))
            .padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.semantics { hideFromAccessibility() }) { SymbolIcon(Icons.Filled.SwapHoriz, 14f, ChipColors.dim) }
        Text("Drag a track's name to move it", style = MaterialTheme.typography.bodyMedium, color = ChipColors.text, modifier = Modifier.weight(1f))
        Box(
            Modifier
                .heightIn(min = 36.dp)
                .clip(CircleShape)
                .background(ChipColors.text)
                .plainClickable(onClick = onDone)
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(ControlLabel.REORDER_DONE, style = chipFont(14f), color = ChipColors.onLight)
        }
    }
}
