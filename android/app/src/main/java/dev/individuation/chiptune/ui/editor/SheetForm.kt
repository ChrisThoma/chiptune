package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.individuation.chiptune.ui.layout.Adjustable
import dev.individuation.chiptune.ui.layout.AdjustmentDirection
import dev.individuation.chiptune.ui.layout.InstrumentEditorCopy
import dev.individuation.chiptune.ui.theme.ChipColors

/*
 * The look the four form sheets share: iOS's inset-grouped Form, on the app's
 * palette. The sheet is `panel`, each section a rounded `panelHigh` group with
 * a dim header above and a dim footer below; the bar's buttons are capsules,
 * as iOS 26 draws them.
 */

object FormColors {
    val sheet = ChipColors.panel
    val group = ChipColors.panelHigh
    val separator = ChipColors.grid

    /** iOS's default tint in dark mode, which the arrangement and sound
     * sheets keep (they set no `.tint` of their own). */
    val tint = Color(0xFF0A84FF)
    val destructive = ChipColors.accentRed
}

/** The sheet's navigation bar: [leading] and [trailing] slots around a
 * centred [title]. */
@Composable
fun SheetBar(
    title: String,
    leading: (@Composable RowScope.() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 2.dp, bottom = 8.dp).heightIn(min = 44.dp)) {
        Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) { leading?.invoke(this) }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
            color = ChipColors.text,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 96.dp).semantics { heading() },
        )
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically) { trailing?.invoke(this) }
    }
}

/** A capsule bar button with a word in it (Close, Done, Edit). */
@Composable
fun BarPill(
    label: String,
    onClick: () -> Unit,
    color: Color = ChipColors.text,
    bold: Boolean = false,
    enabled: Boolean = true,
    contentDescription: String? = null,
) {
    Box(
        Modifier
            .heightIn(min = 44.dp)
            .widthIn(min = 44.dp)
            .clip(CircleShape)
            .background(ChipColors.grid.copy(alpha = 0.55f))
            .plainClickable(enabled = enabled, onClick = onClick)
            .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = if (enabled) color else ChipColors.dim,
            fontSize = 17.sp,
            fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal,
            maxLines = 1,
        )
    }
}

/** A round bar button with a glyph in it (the library's +, the pill's check). */
@Composable
fun BarIconPill(icon: ImageVector, contentDescription: String, onClick: () -> Unit, tint: Color = ChipColors.text) {
    Box(
        Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(ChipColors.grid.copy(alpha = 0.55f))
            .plainClickable(onClick = onClick)
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
    }
}

/** One inset-grouped section: header, a rounded group, footer. */
@Composable
fun FormSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: String? = null,
    footerColor: Color = ChipColors.dim,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(bottom = 18.dp)) {
        if (header != null) FormHeader(header)
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(FormColors.group),
            content = content,
        )
        if (footer != null) FormFooter(footer, footerColor)
    }
}

@Composable
fun FormHeader(text: String) {
    Text(
        text,
        fontSize = 15.sp,
        fontWeight = FontWeight.Medium,
        color = ChipColors.dim,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp).semantics { heading() },
    )
}

@Composable
fun FormFooter(text: String, color: Color = ChipColors.dim) {
    Text(
        text,
        fontSize = 13.sp,
        lineHeight = 17.sp,
        color = color,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 7.dp),
    )
}

/** A row's standard frame inside a group. */
@Composable
fun FormRow(
    modifier: Modifier = Modifier,
    verticalPadding: Int = 10,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 20.dp, vertical = verticalPadding.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** A caption line inside a group (iOS's `.caption`, `.secondary`). */
@Composable
fun FormCaption(text: String, color: Color = ChipColors.dim) {
    Text(
        text,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        color = color,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
    )
}

/** The hairline between rows of a group, inset like iOS's. */
@Composable
fun FormSeparator() {
    Box(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp).height(0.5.dp).background(FormColors.separator))
}

/** A tappable text row (an action in a group). */
@Composable
fun FormButtonRow(
    label: String,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    color: Color = FormColors.tint,
    enabled: Boolean = true,
) {
    FormRow(Modifier.plainClickable(enabled = enabled, onClick = onClick).alpha(if (enabled) 1f else 0.4f)) {
        if (icon != null) Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(22.dp))
        Text(label, color = color, fontSize = 17.sp, modifier = Modifier.weight(1f))
    }
}

/**
 * TalkBack's adjustable element (iOS's `accessibilityAdjustableAction`):
 * one node with a label and a spoken value, a range so TalkBack's adjust
 * gestures and volume keys step it, and Increment/Decrement actions for
 * Switch Access and Voice Access. [steps] intermediate stops between the
 * ends set how far one adjust moves. A null [set] makes it a choice list:
 * any request to move goes one choice that way through [adjust].
 */
fun SemanticsPropertyReceiver.adjustable(
    label: String,
    value: String,
    current: Float,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    enabled: Boolean,
    set: ((Float) -> Unit)?,
    adjust: (AdjustmentDirection) -> Unit,
) {
    contentDescription = label
    stateDescription = value
    progressBarRangeInfo = ProgressBarRangeInfo(current.coerceIn(range), range, steps)
    if (!enabled) {
        disabled()
        return
    }
    setProgress { target ->
        if (set != null) {
            set(target.coerceIn(range))
        } else if (target > current) {
            // A choice list: TalkBack's nudge (a fraction of the range when
            // there are no stops) means one choice along.
            adjust(AdjustmentDirection.INCREMENT)
        } else if (target < current) {
            adjust(AdjustmentDirection.DECREMENT)
        }
        true
    }
    customActions = listOf(
        CustomAccessibilityAction(Adjustable.INCREMENT_ACTION_NAME) { adjust(AdjustmentDirection.INCREMENT); true },
        CustomAccessibilityAction(Adjustable.DECREMENT_ACTION_NAME) { adjust(AdjustmentDirection.DECREMENT); true },
    )
}

/**
 * iOS's segmented `Picker`. For TalkBack the segments are one adjustable
 * element named [label], as iOS hides the picker behind an
 * `accessibilitySelector`.
 */
@Composable
fun SegmentedPicker(
    labels: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val last = (labels.size - 1).coerceAtLeast(0)
    Row(
        modifier
            .fillMaxWidth()
            .height(36.dp)
            .clip(CircleShape)
            .background(ChipColors.panel)
            .padding(2.dp)
            .clearAndSetSemantics {
                adjustable(
                    label, value, selected.toFloat(), 0f..last.toFloat(), (last - 1).coerceAtLeast(0), enabled,
                    set = null,
                    adjust = { direction ->
                        val next = InstrumentEditorCopy.adjustedIndex(selected, labels.size, direction)
                        if (next != selected) onSelect(next)
                    },
                )
            },
    ) {
        labels.forEachIndexed { index, text ->
            val on = index == selected
            Box(
                Modifier
                    .weight(1f)
                    .height(32.dp)
                    .clip(CircleShape)
                    .background(if (on) ChipColors.dim.copy(alpha = 0.55f) else Color.Transparent)
                    .plainClickable(enabled = enabled, role = Role.Tab) { if (!on) onSelect(index) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text,
                    color = ChipColors.text,
                    fontSize = 13.sp,
                    fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** A titled slider row (the sound sheet's Volume and Decay). TalkBack moves
 * it a tenth of its range at a time and reads [display]'s value. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FormSlider(
    title: String,
    value: Double,
    range: ClosedFloatingPointRange<Double>,
    display: (Double) -> String,
    accent: Color,
    onChange: (Double) -> Unit,
    enabled: Boolean = true,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.4f)
            .padding(horizontal = 20.dp)
            .padding(top = 10.dp, bottom = 2.dp),
    ) {
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = ChipColors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
            Text(display(value), color = ChipColors.dim, fontSize = 17.sp)
        }
        val colors = SliderDefaults.colors(
            thumbColor = Color.White,
            activeTrackColor = accent,
            inactiveTrackColor = ChipColors.grid,
            disabledThumbColor = Color.White,
            disabledActiveTrackColor = accent,
            disabledInactiveTrackColor = ChipColors.grid,
        )
        Box(
            Modifier.fillMaxWidth().clearAndSetSemantics {
                adjustable(
                    title, display(value), value.toFloat(),
                    range.start.toFloat()..range.endInclusive.toFloat(), 9, enabled,
                    set = { onChange(it.toDouble().coerceIn(range)) },
                    adjust = { onChange(InstrumentEditorCopy.sliderStep(value, range, it)) },
                )
            },
        ) {
            Slider(
                value = value.toFloat(),
                onValueChange = { onChange(it.toDouble().coerceIn(range)) },
                valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
                enabled = enabled,
                colors = colors,
                // iOS's slider: a thin track and a round white knob.
                thumb = {
                    Box(Modifier.size(26.dp).shadow(2.dp, CircleShape).clip(CircleShape).background(Color.White))
                },
                track = { state ->
                    SliderDefaults.Track(
                        sliderState = state,
                        modifier = Modifier.height(4.dp),
                        enabled = enabled,
                        colors = colors,
                        drawStopIndicator = null,
                        thumbTrackGapSize = 0.dp,
                        trackInsideCornerSize = 2.dp,
                    )
                },
            )
        }
    }
}

/** A labelled switch row; the whole row toggles (iOS's Hold needed the same). */
@Composable
fun FormSwitch(title: String, checked: Boolean, accent: Color, onChange: (Boolean) -> Unit) {
    FormRow(
        Modifier
            .plainClickable(role = Role.Switch, pressedAlpha = 1f) { onChange(!checked) }
            .clearAndSetSemantics {
                contentDescription = title
                stateDescription = if (checked) "On" else "Off"
                role = Role.Switch
                toggleableState = ToggleableState(checked)
                onClick { onChange(!checked); true }
            },
        verticalPadding = 4,
    ) {
        Text(title, color = ChipColors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = accent,
                checkedBorderColor = accent,
                uncheckedThumbColor = ChipColors.text,
                uncheckedTrackColor = ChipColors.grid,
                uncheckedBorderColor = ChipColors.grid,
            ),
        )
    }
}
