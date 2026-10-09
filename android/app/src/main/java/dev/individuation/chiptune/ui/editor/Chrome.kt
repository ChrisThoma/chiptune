package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.individuation.chiptune.core.studio.Studio
import dev.individuation.chiptune.core.studio.StudioState
import dev.individuation.chiptune.ui.layout.ChipLayout
import dev.individuation.chiptune.ui.layout.PlainStepperRules
import dev.individuation.chiptune.ui.layout.TextScale
import dev.individuation.chiptune.ui.theme.ChipColors
import dev.individuation.chiptune.ui.theme.ChipRadii
import dev.individuation.chiptune.ui.theme.chipFont

/** The window's metrics, as iOS's `\.chipLayout` environment value. */
val LocalChipLayout = compositionLocalOf { ChipLayout.PHONE }

/**
 * What every editor view reads: the [Studio] it acts on, its state as one
 * Compose [State] (read slices of it through `derivedStateOf`, so a playhead
 * tick doesn't recompose a view that doesn't show the playhead), and the
 * editor's seams.
 */
@Stable
class Editor(
    val studio: Studio,
    val ui: State<StudioState>,
    val presentation: EditorPresentationState,
    val effects: EditorEffects,
    val haptics: Haptics,
    val rename: TitleRename,
)

/** The song-title field's focus, so the grid, keys and chrome can close a
 * rename the way iOS's `endRenaming()` does. */
@Stable
class TitleRename {
    var focused by mutableStateOf(false)
        internal set

    /** Set by the title field: clears its focus (which normalises the name). */
    internal var clearFocus: () -> Unit = {}

    fun end() {
        if (focused) clearFocus()
    }
}

/** Any touch on this view closes the title rename first, without taking the
 * touch: grid cells and keys aren't focusable, so nothing else would. */
fun Modifier.endsRenameOnTouch(rename: TitleRename): Modifier = pointerInput(rename) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        rename.end()
    }
}

/** iOS's `@ScaledMetric(relativeTo: .body)` ratio: how much the system font
 * size grows fixed chrome metrics (tray heights, stepper ends). */
@Composable
fun metricScale(): Float = LocalDensity.current.fontScale

/** Caps text growth inside fixed-width chrome (grid, keys) at 1.5x, as iOS
 * caps it at `accessibility1`. */
@Composable
fun CappedTextScale(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val capped = TextScale.capped(density.fontScale)
    if (capped == density.fontScale) {
        content()
    } else {
        CompositionLocalProvider(LocalDensity provides Density(density.density, capped), content = content)
    }
}

fun Double.dpValue(): Dp = this.toFloat().dp

/** Groups controls onto one panel (iOS `chipTray()`). */
fun Modifier.chipTray(height: Dp): Modifier =
    this.height(height).clip(RoundedCornerShape(ChipRadii.tray)).background(ChipColors.panel)

/** Hairline between segments inside a tray. */
@Composable
fun TrayDivider() {
    Box(
        Modifier.width(ChipLayout.TRAY_DIVIDER_WIDTH.dpValue()).fillMaxHeight().padding(vertical = 8.dp)
            .background(ChipColors.divider),
    )
}

/** A plain button: no ripple, the content dims while pressed (SwiftUI's
 * `.plain` style). */
@Composable
fun Modifier.plainClickable(
    enabled: Boolean = true,
    role: Role = Role.Button,
    onClickLabel: String? = null,
    pressedAlpha: Float = 0.6f,
    onClick: () -> Unit,
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    return this
        .graphicsLayer { alpha = if (pressed) pressedAlpha else 1f }
        .clickable(interaction, indication = null, enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = onClick)
}

/** Small dark control button of the keyboard row (iOS `PadStyle`): at least
 * 44x44, filled `text` when [active]. */
@Composable
fun PadButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    active: Boolean = false,
    enabled: Boolean = true,
    content: @Composable (Color) -> Unit,
) {
    val fg = when {
        active -> ChipColors.onLight
        enabled -> ChipColors.text
        else -> ChipColors.dim.copy(alpha = 0.4f)
    }
    Box(
        modifier
            .widthIn(min = 44.dp)
            .height(44.dp)
            .clip(RoundedCornerShape(ChipRadii.inner))
            .background(if (active) ChipColors.text else ChipColors.panelHigh)
            .plainClickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) { content(fg) }
}

/** An icon sized like an SF Symbol of point size [size]. */
@Composable
fun SymbolIcon(image: ImageVector, size: Float, tint: Color, modifier: Modifier = Modifier) {
    // Material glyphs fill about 20/24 of their box; SF Symbols' cap height is
    // close to their point size. 1.2x brings the two to the same ink.
    Icon(image, contentDescription = null, tint = tint, modifier = modifier.size((size * 1.2f).dp))
}

/**
 * The -/value/+ control (port of `ChipStepper`). Draws no tray of its own.
 * The readout is a button when [onTapValue] is given.
 */
@Composable
fun ChipStepper(
    label: String,
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onTapValue: (() -> Unit)? = null,
) {
    val layout = LocalChipLayout.current
    val scale = metricScale()
    val trayHeight = (layout.trayHeight * scale).dpValue()
    val endWidth = (layout.stepperEndWidth * scale).dpValue()
    val canDecrease = value > range.first
    val canIncrease = value < range.last
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        StepperEnd(Icons.Filled.Remove, canDecrease, endWidth, trayHeight, "Decrease $label", "Current value $value") { onChange(-1) }
        val readout = Modifier
            .widthIn(min = ChipLayout.STEPPER_READOUT_MIN_WIDTH.dpValue())
            .height(trayHeight)
        Column(
            if (onTapValue != null) {
                readout.plainClickable(onClickLabel = "edit", onClick = onTapValue)
                    .clearAndSetSemantics {
                        contentDescription = label
                        stateDescription = "$value"
                        role = Role.Button
                        onClick("edit") { onTapValue(); true }
                    }
            } else {
                readout.clearAndSetSemantics {
                    contentDescription = label
                    stateDescription = "$value"
                }
            },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // The number must never be the part that truncates; the label gives way.
            Text("$value", style = chipFont(15f, FontWeight.Bold), color = ChipColors.text, maxLines = 1, softWrap = false)
            Text(label, style = chipFont(8f), color = ChipColors.dim, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        StepperEnd(Icons.Filled.Add, canIncrease, endWidth, trayHeight, "Increase $label", "Current value $value") { onChange(1) }
    }
}

@Composable
private fun StepperEnd(
    icon: ImageVector,
    enabled: Boolean,
    width: Dp,
    height: Dp,
    label: String,
    value: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(width, height)
            .plainClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = label
                stateDescription = value
            },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(icon, 13f, if (enabled) ChipColors.text else ChipColors.dim.copy(alpha = 0.4f))
    }
}

/**
 * A minus/plus pair in a capsule (port of `PlainStepper`), for the sheets'
 * repeat counts (Arrangement, Export). One element for TalkBack, with
 * Increment/Decrement actions.
 */
@Composable
fun PlainStepper(
    value: Int,
    onValueChange: (Int) -> Unit,
    range: IntRange,
    accessibilityLabel: String,
    accessibilityValue: String,
    modifier: Modifier = Modifier,
    isEnabled: Boolean = true,
) {
    fun step(delta: Int) {
        val next = PlainStepperRules.stepped(value, delta, range, isEnabled)
        if (next != value) onValueChange(next)
    }
    val canDecrease = PlainStepperRules.canDecrease(value, range, isEnabled)
    val canIncrease = PlainStepperRules.canIncrease(value, range, isEnabled)
    Row(
        modifier
            .clip(CircleShape)
            .background(ChipColors.dim.copy(alpha = 0.18f))
            .clearAndSetSemantics {
                contentDescription = accessibilityLabel
                stateDescription = accessibilityValue
                if (!isEnabled) disabled()
                customActions = listOf(
                    CustomAccessibilityAction(PlainStepperRules.INCREMENT_ACTION_NAME) { step(PlainStepperRules.delta(true)); true },
                    CustomAccessibilityAction(PlainStepperRules.DECREMENT_ACTION_NAME) { step(PlainStepperRules.delta(false)); true },
                )
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PlainStepperEnd(Icons.Filled.Remove, canDecrease) { step(-1) }
        Box(Modifier.width(1.dp).height(18.dp).background(ChipColors.divider))
        PlainStepperEnd(Icons.Filled.Add, canIncrease) { step(1) }
    }
}

@Composable
private fun PlainStepperEnd(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(46.dp, 32.dp).plainClickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(icon, 15f, if (enabled) ChipColors.text else ChipColors.dim.copy(alpha = 0.4f))
    }
}

/** Fallback for a composable that needs the [Editor] but sits outside one. */
val LocalEditor = staticCompositionLocalOf<Editor> { error("No Editor provided") }
