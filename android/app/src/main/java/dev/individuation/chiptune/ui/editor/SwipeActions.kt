package dev.individuation.chiptune.ui.editor

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** One button a swipe uncovers (iOS's `swipeActions` button). */
data class SwipeAction(
    val label: String,
    val icon: ImageVector?,
    val background: Color,
    val foreground: Color = Color.White,
    val onClick: () -> Unit,
)

/** Which row of a list has its actions out: opening one closes the rest,
 * as a List does on iOS. */
@Stable
class SwipeRevealGroup {
    var open: Any? by mutableStateOf(null)
}

/**
 * A row that slides aside to show [leading] (swipe right) or [trailing]
 * (swipe left) buttons, each 76 dp wide. No full-swipe action: the buttons
 * have to be tapped. TalkBack gets every action as a custom action on the
 * row, since it can't swipe.
 */
@Composable
fun SwipeActionsRow(
    key: Any,
    group: SwipeRevealGroup,
    leading: List<SwipeAction>,
    trailing: List<SwipeAction>,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val actionWidth = with(density) { ACTION_WIDTH.dp.toPx() }
    val leadingWidth = actionWidth * leading.size
    val trailingWidth = actionWidth * trailing.size
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    fun settle(target: Float) {
        scope.launch { offset.animateTo(target, spring(stiffness = 600f)) }
        group.open = if (target == 0f) (if (group.open == key) null else group.open) else key
    }

    LaunchedEffect(group.open) {
        if (group.open != key && offset.value != 0f) offset.animateTo(0f, spring(stiffness = 600f))
    }
    LaunchedEffect(enabled) {
        if (!enabled && offset.value != 0f) settle(0f)
    }

    fun run(action: SwipeAction) {
        settle(0f)
        action.onClick()
    }

    Box(
        modifier
            .clipToBounds()
            .semantics {
                customActions = (leading + trailing).map { action ->
                    CustomAccessibilityAction(action.label) { action.onClick(); true }
                }
            },
    ) {
        // The buttons sit under the row and are uncovered as it slides.
        if (offset.value > 0f) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.Start) {
                leading.forEach { ActionButton(it) { run(it) } }
            }
        } else if (offset.value < 0f) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.End) {
                trailing.forEach { ActionButton(it) { run(it) } }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(offset.value.roundToInt(), 0) }
                .pointerInput(enabled, leadingWidth, trailingWidth) {
                    if (!enabled) return@pointerInput
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val v = offset.value
                            settle(
                                when {
                                    v > leadingWidth / 2 -> leadingWidth
                                    v < -trailingWidth / 2 -> -trailingWidth
                                    else -> 0f
                                },
                            )
                        },
                        onDragCancel = { settle(0f) },
                    ) { change, dx ->
                        change.consume()
                        val next = (offset.value + dx).coerceIn(-trailingWidth, leadingWidth)
                        scope.launch { offset.snapTo(next) }
                    }
                },
        ) { content() }
    }
}

@Composable
private fun ActionButton(action: SwipeAction, onClick: () -> Unit) {
    Column(
        Modifier
            .width(ACTION_WIDTH.dp)
            .fillMaxHeight()
            .background(action.background)
            .plainClickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        action.icon?.let { Icon(it, contentDescription = null, tint = action.foreground, modifier = Modifier.size(20.dp)) }
        Text(action.label, color = action.foreground, fontSize = 12.sp, maxLines = 1)
    }
}

private const val ACTION_WIDTH = 76
