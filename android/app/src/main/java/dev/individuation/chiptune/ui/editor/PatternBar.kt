package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FormatClear
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.ui.platform.LocalDensity
import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.studio.ConfirmationCopy
import dev.individuation.chiptune.ui.layout.EditorChrome
import dev.individuation.chiptune.ui.layout.PatternChipAccessibility
import dev.individuation.chiptune.ui.layout.PatternChipActions
import dev.individuation.chiptune.ui.layout.PatternRenameForm
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.ChipRadii
import dev.individuation.chiptune.ui.theme.chipFont
import java.util.UUID

/** The patterns strip and STEPS (port of `PatternBar`). */
@Composable
fun PatternBar(editor: Editor) {
    val layout = LocalChipLayout.current
    val scale = metricScale()
    val trayHeight = (layout.trayHeight * scale).dpValue()
    val stacks = EditorChrome.patternBarStacks(scale)
    val modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 6.dp)
    if (stacks) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PatternTray(editor, trayHeight, Modifier)
            StepsStepper(editor, trayHeight, Modifier.fillMaxWidth())
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            // The tray hugs its chips and grows with them; the 12 dp keeps it
            // off STEPS, which belongs to the pattern rather than the strip.
            PatternTray(editor, trayHeight, Modifier.weight(1f, fill = false).padding(end = 12.dp))
            StepsStepper(editor, trayHeight, Modifier)
        }
    }
}

@Composable
private fun StepsStepper(editor: Editor, trayHeight: Dp, modifier: Modifier) {
    val ui = editor.ui
    val length by remember { derivedStateOf { ui.value.patternLength } }
    ChipStepper(
        label = "STEPS",
        value = length,
        range = Chip.patternLengthRange,
        onChange = { editor.studio.setPatternLength(editor.studio.patternLength + it * 4) },
        modifier = modifier.chipTray(trayHeight),
    )
}

/** How wide each edge fade is. */
private val FadeWidth = 20.dp

@Composable
private fun PatternTray(editor: Editor, trayHeight: Dp, modifier: Modifier) {
    val ui = editor.ui
    val patterns by remember { derivedStateOf { ui.value.song.patterns } }
    val selected by remember { derivedStateOf { ui.value.selectedPattern } }
    val playingPattern by remember { derivedStateOf { if (ui.value.isPlaying) ui.value.playingPattern else -1 } }
    val canAdd = patterns.size < Chip.MAX_PATTERNS
    val scroll = rememberScrollState()
    // Chip frames inside the strip, keyed by pattern id, for "show the selected chip".
    val frames = remember { mutableStateMapOf<UUID, Pair<Int, Int>>() }
    val selectedId = patterns.getOrNull(selected)?.id
    // Derived, so scrolling only recomposes when a fade appears or goes.
    val moreBefore by remember { derivedStateOf { scroll.value > 0 } }
    val moreAfter by remember { derivedStateOf { scroll.value < scroll.maxValue } }

    Row(modifier.chipTray(trayHeight), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f, fill = false).fillMaxHeight()) {
            Row(
                Modifier.fillMaxHeight().horizontalScroll(scroll).padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                patterns.forEachIndexed { index, pattern ->
                    androidx.compose.runtime.key(pattern.id) {
                        PatternChip(
                            editor = editor,
                            index = index,
                            pattern = pattern,
                            selected = index == selected,
                            playing = index == playingPattern,
                            canAddPattern = canAdd,
                            patternCount = patterns.size,
                            height = trayHeight,
                            modifier = Modifier.onGloballyPositioned { frames[pattern.id] = it.parentLayoutCoordinatesX() to it.size.width },
                        )
                    }
                }
            }
            // Painted over the strip in the tray's own colour, only at an edge
            // with more chips behind it.
            if (moreBefore) {
                Box(
                    Modifier.align(Alignment.CenterStart).width(FadeWidth).fillMaxHeight()
                        .background(Brush.horizontalGradient(listOf(ChipColors.panel, ChipColors.panel.copy(alpha = 0f)))),
                )
            }
            if (moreAfter) {
                Box(
                    Modifier.align(Alignment.CenterEnd).width(FadeWidth).fillMaxHeight()
                        .background(Brush.horizontalGradient(listOf(ChipColors.panel.copy(alpha = 0f), ChipColors.panel))),
                )
            }
        }
        if (canAdd) {
            TrayDivider()
            val layout = LocalChipLayout.current
            Box(
                Modifier.width(layout.patternAddWidth.dpValue()).height(trayHeight)
                    .plainClickable { editor.studio.addPattern() }
                    .semantics { contentDescription = "Add pattern" },
                contentAlignment = Alignment.Center,
            ) {
                SymbolIcon(Icons.Filled.Add, 13f, ChipColors.text)
            }
        }
    }

    // Every selection change brings its chip to the middle of the strip: a new
    // pattern lands past the trailing edge, behind the pinned "+".
    val density = LocalDensity.current
    LaunchedEffect(selectedId, scroll.maxValue) {
        val frame = selectedId?.let { frames[it] } ?: return@LaunchedEffect
        if (scroll.maxValue <= 0) return@LaunchedEffect
        val viewport = scroll.viewportSize
        val padding = with(density) { 4.dp.roundToPx() }
        val target = (frame.first + padding + frame.second / 2 - viewport / 2).coerceIn(0, scroll.maxValue)
        scroll.animateScrollTo(target, tween(200, easing = FastOutSlowInEasing))
    }
}

/** The chip's x inside the scrolling row's content. */
private fun androidx.compose.ui.layout.LayoutCoordinates.parentLayoutCoordinatesX(): Int =
    parentLayoutCoordinates?.let { parent -> parent.localPositionOf(this, androidx.compose.ui.geometry.Offset.Zero).x.toInt() } ?: 0

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PatternChip(
    editor: Editor,
    index: Int,
    pattern: Pattern,
    selected: Boolean,
    playing: Boolean,
    canAddPattern: Boolean,
    patternCount: Int,
    height: Dp,
    modifier: Modifier,
) {
    val layout = LocalChipLayout.current
    val studio = editor.studio
    val presentation = editor.presentation
    var menu by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val isEmpty = pattern.isEmpty
    val rename = { presentation.open(Presented.PatternRename(index)); Unit }
    val duplicate = { studio.duplicatePattern(index) }
    val clear = { presentation.open(Presented.ClearPattern(index)); Unit }
    val delete = { presentation.open(Presented.DeletePattern(index)); Unit }

    Box(modifier) {
        Box(
            Modifier
                .widthIn(min = layout.patternChipWidth.dpValue())
                .height(height)
                .graphicsLayer { alpha = if (pressed) 0.6f else 1f }
                .combinedClickable(
                    interactionSource = interaction,
                    indication = null,
                    onLongClick = {
                        editor.haptics.reorderBegan()
                        menu = true
                    },
                    onClick = { studio.selectPattern(index) },
                )
                .clearAndSetSemantics {
                    contentDescription = "Pattern ${pattern.name}"
                    PatternChipAccessibility.value(playing, isEmpty)?.let { stateDescription = it }
                    this.selected = selected
                    role = Role.Button
                    onClick { studio.selectPattern(index); true }
                    // The long-press menu, mirrored as actions.
                    customActions = PatternChipActions.available(canAddPattern, patternCount).map { name ->
                        CustomAccessibilityAction(name) {
                            when (name) {
                                PatternChipActions.RENAME -> rename()
                                PatternChipActions.DUPLICATE -> duplicate()
                                PatternChipActions.CLEAR -> clear()
                                else -> delete()
                            }
                            true
                        }
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.matchParentSize().padding(vertical = 4.dp).clip(RoundedCornerShape(ChipRadii.inner))
                    .background(if (selected) ChipColors.text else ChipColors.panelHigh),
            )
            Row(
                Modifier.padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (playing) {
                    // On a selected (near-white) chip the bright green vanishes.
                    Box(Modifier.size(5.dp).background(if (selected) ChipColors.onLightGreen else ChipColors.accentGreen, CircleShape))
                }
                Text(
                    pattern.name,
                    style = chipFont(13f, if (selected) FontWeight.Bold else FontWeight.SemiBold),
                    color = when {
                        selected -> ChipColors.onLight
                        isEmpty -> ChipColors.dim
                        else -> ChipColors.text
                    },
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = ChipColors.panelHigh) {
            ChipMenuRow("Rename", Icons.Filled.Edit) { menu = false; rename() }
            ChipMenuRow("Duplicate", Icons.Filled.LibraryAdd, enabled = PatternChipActions.canDuplicate(canAddPattern)) {
                menu = false
                duplicate()
            }
            ChipMenuRow("Clear", Icons.Filled.FormatClear, destructive = true) { menu = false; clear() }
            ChipMenuRow("Delete", Icons.Filled.Delete, destructive = true, enabled = PatternChipActions.canDelete(patternCount)) {
                menu = false
                delete()
            }
        }
    }
}

@Composable
private fun ChipMenuRow(title: String, icon: ImageVector, enabled: Boolean = true, destructive: Boolean = false, onClick: () -> Unit) {
    val color = if (destructive) ChipColors.accentRed else ChipColors.text
    DropdownMenuItem(
        text = { Text(title, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        enabled = enabled,
        onClick = onClick,
        colors = MenuDefaults.itemColors(
            textColor = color,
            leadingIconColor = color,
            disabledTextColor = ChipColors.dim.copy(alpha = 0.5f),
            disabledLeadingIconColor = ChipColors.dim.copy(alpha = 0.5f),
        ),
    )
}

/**
 * Renaming one pattern: a sheet rather than a dialog so the six-character
 * cap shows as you type. [index] is the pattern as it was when raised.
 */
@Composable
fun PatternRenameSheet(editor: Editor, index: Int, onDismiss: () -> Unit) {
    val studio = editor.studio
    val ui = editor.ui
    val names by remember { derivedStateOf { ui.value.song.patterns.map { it.name } } }
    var text by remember { mutableStateOf(PatternRenameForm.capped(names.getOrNull(index) ?: "")) }
    val focus = remember { FocusRequester() }
    val canRename = PatternRenameForm.canRename(text, names, index.takeIf { it in names.indices })
    fun commit() {
        if (!canRename) return
        studio.renamePattern(index, text)
        onDismiss()
    }
    ChipSheet(onDismiss = onDismiss, skipPartiallyExpanded = true) {
        SheetHeader(
            "Rename pattern",
            leading = "Cancel" to onDismiss,
            trailing = Triple("Rename", canRename) { commit() },
        )
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp)) {
            Text("NAME", style = MaterialTheme.typography.labelMedium, color = ChipColors.dim, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(ChipColors.panel).padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                BasicTextField(
                    value = text,
                    onValueChange = { text = PatternRenameForm.capped(it) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = ChipColors.text),
                    cursorBrush = SolidColor(ChipColors.text),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { commit() }),
                    modifier = Modifier.fillMaxWidth().reportsTextEntryFocus().focusRequester(focus).semantics { contentDescription = "Pattern name" },
                    decorationBox = { field ->
                        Box {
                            if (text.isEmpty()) Text("Name", color = ChipColors.dim, style = MaterialTheme.typography.bodyLarge)
                            field()
                        }
                    },
                )
            }
            Text(
                PatternRenameForm.footer(text, names, index.takeIf { it in names.indices }),
                style = MaterialTheme.typography.bodySmall,
                color = ChipColors.dim,
                modifier = Modifier.padding(start = 16.dp, top = 6.dp),
            )
        }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
}

/** "Clear pattern X?", shared by the menu and the chip. */
@Composable
fun ClearPatternDialog(editor: Editor, index: Int, onDismiss: () -> Unit) {
    val name = editor.studio.song.patterns.getOrNull(index)?.name ?: ""
    ConfirmDialog(
        title = "Clear pattern $name?",
        message = ConfirmationCopy.CLEAR_PATTERN,
        confirmLabel = "Clear pattern",
        destructive = true,
        // In place: jumping to the cleared pattern reads as lost work.
        onConfirm = { editor.studio.clearPattern(index) },
        onDismiss = onDismiss,
    )
}

@Composable
fun DeletePatternDialog(editor: Editor, index: Int, onDismiss: () -> Unit) {
    val name = editor.studio.song.patterns.getOrNull(index)?.name ?: ""
    ConfirmDialog(
        title = ConfirmationCopy.deletePatternTitle(name),
        message = ConfirmationCopy.DELETE_PATTERN,
        confirmLabel = "Delete pattern",
        destructive = true,
        onConfirm = { editor.studio.removePattern(index) },
        onDismiss = onDismiss,
    )
}
